---
title: 'Story 4.3: Break the feed with a real batch of 50 orders'
type: 'feature'
created: '2026-10-25'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Break the feed does nothing yet. `POST /api/v1/demo/break-feed` answers 501, `BreakFeedIn` and `PartnerTrigger` are stubs, and nothing writes a `BreakFeedRun` row. So the demo's real failure never happens, and the guide's Break the feed stages (Story 4.2) never move.

**Approach:**
- `Web.Api` hands the press to `BreakFeedIn`, an adapterless service created in the request's own process. Under the session's lock, `BreakFeedIn`:
  1. checks `Guide.Compute`;
  2. closes the session's resolved Orders incident through `IncidentManager`;
  3. writes and publishes the run;
  4. asks `PartnerTrigger` synchronously.
- `PartnerTrigger` audits the `Action`. Then, in its one `New $NAMESPACE` method, it makes the Orders partner send the session's 50 orders. The orders use `MM/DD/YYYY` and are tagged with the session's `TraceRef`, and Epic 0's transform fails them for real.

## Boundaries & Constraints

**Always:**
- **The order inside `BreakFeedIn` (AD-12).**
  1. It takes `LOCK +^OcuTalon.Demo.BreakFeed(SessionRef)`, held until the end.
  2. It checks `Guide.Compute(SessionRef).BreakFeed` (`Active`, `Reason`).
  3. It sends `closeForReplay` (`SendRequestSync`) for each of the session's own noticed `resolved` Orders incidents, oldest first.
  4. It writes `BreakFeedRun` as `sending` and publishes `breakfeed.progress`.
  5. It sends `SendRequestSync` to `PartnerTrigger`.
  6. It marks the run `sent` and publishes `breakfeed.progress` again.
- **A refused press sends nothing and writes nothing.** That covers an inactive or refused press: no run, no audit entry, no message.
- **A press is never a turn.**
  - It creates no `Turn` and no `Decision`.
  - It never calls `Core.Allowance`, and never sends to `WebChatIn` or `Conversation`.
  - Its messages carry the `SessionRef` and `SuperSession` = the session's `TraceRef`.
  - It starts its own trace session and never calls `Trace.Join` (AD-26).
- **`PartnerTrigger`.**
  - It is the press's only namespace switch: exactly one method with `New $NAMESPACE`. Constants are read before the switch.
  - It calls `Partner.Send(COUNT 50, "MM/DD/YYYY", traceRef, "")`.
  - Orders bodies carry no `SessionRef` (AD-3, AD-4).
- **The audit (AD-17).**
  - Each run that reaches `PartnerTrigger` writes one `Action` entry through `Bridge.Audit.Write`, in `PartnerTrigger`'s job, before the send.
  - Its data is `{user, sessionRef, channel, action, orders, dateFormat}`, passed through `Bridge.Redact.Text`. `user` is the session row's `IrisUser`.
  - If the write fails, nothing is sent.
- **Writers (AD-33).**
  - Only `BreakFeedIn` writes `BreakFeedRun`. `StartedAt` comes from `Data.Time.NowUtc()`.
  - Only `BreakFeedIn` publishes `breakfeed.progress`, after its commit.
  - `IncidentManager` stays the only writer of incidents.
- **REST, in this order.**
  1. Demo mode off: 404 `not_found`, before anything else.
  2. A session that can't be read: 500.
  3. Inactive or refused: 409 `{"error":{"code":<reason>,"message":<hint>}}`.
  4. Sent: 200 `{"state":"sent","startedAt"}`.
  5. Any other failure: 500 `server_error`.

  The body is not read, and the session comes from the CSP session. The hints are EXPERIENCE.md L600-601, verbatim:
  - `not_watching`: "Ask OcuTalon to watch the Orders production first (step 1)."
  - `incident_in_progress`: "Finish the current Orders incident first: approve or reject its fix, or dismiss the incident."
- **Tests.**
  - Real batches, the real production and the item swap run only on lane-B fresh throwaways. They are guarded the way `Test.Demo.Production` is.
  - The `IncidentManager` double goes behind the item through `Test.Agent.RunnerFixture.UseItemClass`, and is restored on every path.
  - Rows come from `Test.Data.Fixture`. Messages are removed with `Fixture.RemoveMessages` in OCUTALON and OCUORDERS.

**Never:**
- **Contended paths.** Never edit `src/bridge/**`, `Install/**`, `Core/{Commands,Allowance,Trace}*`, `Data/Time.cls`, or existing `Test/{Agent,Bridge,Install}/**` files (calling them is fine). Of `docker/**`, edit only the lines the clarification below asks for, and only once ruled.
- **No new structure.** No new table, live-event type, route, role, grant or production item. No change to `Partner`, `Transform`, `Translator`, the Orders production, or `Guide.Compute`'s rules. No `failed` run state, and no retry of a failed press.
- **No product write to Lane A rows.**
- **Out of scope:**
  - the page's box (Story 4.4);
  - the incident card, which stays `notBuilt` for Story 11.1;
  - NFR-7's 60 s, which is measured in the rehearsal, not in CI.

## I/O & Edge-Case Matrix

Conventions for the rows:
- S is a fixture session with an Orders check (`OCUORDERS` / `OcuTalon.Demo.Orders.Production`), demo mode on.
- "Press" means `BreakFeedIn` through `CreateBusinessService` and `ProcessInput(Demo.Press)`, as `Web.Api` sends it.
- "Batch" is S's `TraceRef` in OCUORDERS.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1. Press | S has no incident and no run | The output is `sent`, with one run (`sent`, `StartedAt` = now, UTC). S's stream holds `breakfeed.progress` `sending`, then `sent`, with the same `startedAt`; a `guide.state` follows each change (stage `sending`, then `waiting`). OCUTALON holds one request `BreakFeedIn` → `PartnerTrigger` (`Demo.Msg.SendOrders`, `SessionRef` S, `SuperSession` = `TraceRef`) and none to `IncidentManager` | none |
| 2. Real failures | as row 1 | The batch is exactly 50 headers at `OrdersFromPartner` with `Status` 8 (Error), in 50 sessions, and none at `OrdersToWarehouse`. Each session's event-log error ends "Expected YYYY-MM-DD, got '<MM/DD/YYYY>'." | none |
| 3. Any other means | one order sent through `Partner.Send` directly, `MM/DD/YYYY`, same date | the same item, status and error text as row 2 | none |
| 4. Not watching | S has no Orders check | `inactive`, `not_watching`; no run, message, event or audit entry | REST 409 `not_watching`, hint 1 |
| 5. Busy | an Orders incident of S `open` (any variant), `awaiting_approval` or `fixing`, or a run under 180 s with no notice | `inactive`, `incident_in_progress`; nothing sent | REST 409, hint 2 |
| 6. Two quick presses | two presses for S at once | one `sent`, one `incident_in_progress`; one run; 50 headers, not 100 | if the lock isn't free within `LOCKWAIT`, `incident_in_progress` |
| 7. Replay | S has a noticed `resolved` Orders incident I; the double is `IncidentManager` | The double gets exactly one `IncidentCommand` (`closeForReplay`, I, `SessionRef` S, `Origin` `web_user`) while S has no run. I is then closed, and rows 1 and 2 hold. A resolved `instance` incident, or another session's resolved Orders incident, gets no command | none |
| 8. Close refused | the double answers `Ok` 0 | `inactive`, `incident_in_progress`; no run and no `PartnerTrigger` message | the double errors or times out: an error status (500), nothing sent |
| 9. Partner fails | `PartnerTrigger` errors or times out | An error status (500). The run stays `sending`, with one `sending` event, and the guide's 180 s rule frees the control | logged |
| 10. Audit | after row 1 | within 180 s, `%SYS.Audit` holds exactly one `OcuTalon/Action/Action` entry with `sessionRef` S, `user` = S's `IrisUser` and `channel` `web`. Row 4 adds none | the audit write fails: nothing is sent, an error status |
| 11. Not a turn | after row 1 | S has no `Turn` and no `Decision`. `BreakFeedIn`, `PartnerTrigger` and `Web.Api.BreakFeed` name no `Core.Allowance`, `WebChatIn` or `Conversation` | none |
| 12. Two sessions | A and B, each watching Orders, pressed at once | 50 failed orders per `TraceRef`, none crossing over. `PartnerOrdersIn`'s settings are unchanged, and a `YYYY-MM-DD` control batch afterwards completes at `OrdersToWarehouse` | none |
| 13. REST | `POST /v1/demo/break-feed` | 200 `{"state":"sent","startedAt"}`, or 409 `{"error":{"code","message"}}`. With demo mode off, 404 `not_found`, and `BreakFeedIn` is never asked. A `sessionRef` in the body is ignored | an error from `BreakFeedIn`: 500 `server_error` |
| 14. `ResolvedIncidents` | rows of every kind | S's own noticed `resolved` incidents of the production, oldest first. Never `instance` incidents, another session's, unnoticed ones, other states or other productions | an empty, `instance` or `eval` owner is refused |
| 15. REL-2 over real HTTP | the README session on a fresh demo-path stack | First press: 409 `not_watching`. After the fixture Orders watch: 200 `sent`, and `/events` holds `breakfeed.progress` `sending` and `sent`, then a `guide.state`. A second press: 409 `incident_in_progress`. OCUORDERS holds 50 failed orders for README's `TraceRef` | NFR-7 not asserted |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Demo/BreakFeedIn.cls`, `PartnerTrigger.cls` -- stubs (`STUB` 1, `NotImplemented`). Items `Production.cls:70-71`: `BreakFeedIn` pool 0, `PartnerTrigger` pool 1, no settings (unchanged).
- `src/ocutalon/cls/OcuTalon/Demo/Orders/Partner.cls:83` -- `Send(count, dateFormat, traceRef, orderDate)`, the cross-lane entry (call it in OCUORDERS). `:12` `FORMATS`. Not changed.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls:44` -- `Compute(sessionRef)`, which throws on a failed read; `.BreakFeed.Active` / `.Reason`. `:30` `REASONS`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls:39,42` (read-only) -- `NAMESPACE`, `PRODUCTION`.
- `src/ocutalon/cls/OcuTalon/Data/BreakFeedRun.cls` -- `SessionRef`, `State`, `StartedAt`; no writer yet. Add the writers only, no property.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `:46` `INCIDENTVISIBLE`;
  - `:429` `LatestBreakFeedRun` (the method pattern);
  - `:459` `Rows`;
  - `:507-618` `Statement`. Append the new kind before `:618` `Quit ""`.
- `src/ocutalon/cls/OcuTalon/Msg/IncidentCommand.cls` -- `Verb`, `IncidentRef`, and from `Msg.Command`: `Origin`, `IdempotencyKey`, `SessionRef`. The answer is `Msg.CommandResult` (`Ok`, `Outcome`, `Message`).
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` (Lane A, read-only) -- a stub in this tree (`Production.cls:37`, pool 1). Epic 5's Story 5.5 builds `closeForReplay`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/BreakFeedProgress.cls` -- `State`, `StartedAt`; no `Ref`. `live-store.ts` keeps the latest only.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls:62` -- `Publish(stream, type, payload, .seq, lockWait)`. `breakfeed.progress` is in `GUIDETRIGGERS` (`:21`), so the hook refreshes the guide.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls:12,15,18` -- `Ref`, `TraceRef`, `IrisUser`.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- the patterns for the audit:
  - `:80-86` `AuditData`: the data through `Bridge.Redact.Text`, with the key `user`, never `username`;
  - `:89` the `WriteAudit` seam.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:31` (contended, call only) -- `Write(type, data, description)`.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls` -- the adapterless-service pattern. It sets `..%SuperSession` inside `OnProcessInput`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `:1-24` the header;
  - `:42-56` the `MESSAGE*` parameters;
  - `:64` the route (`Call="NotBuilt"`);
  - `:209` `Post`, which `Test.Web.ApiProbe` overrides;
  - `:247` `GuideMarkers`, the demo-off and 500 pattern;
  - `:450` `CurrentSession`;
  - `:515` `Fail`, whose `$Case` has no 409. `%CSP.REST` has `HTTP409CONFLICT`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls:644,655` (Lane A, call only) -- `UseItemClass(item, class, .saved)` and `RestoreItemClass`. Both change the running production, so throwaways only.
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls`:
  - `:41` the guard;
  - `:321-424` the private helpers `WaitCount`, `Running`, `Send`, `Count`, `Sessions`, `Headers`, `ErrorTexts` (made public in this story);
  - `:426` `RemoveMessages`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - `:19` `Session(user)`, which sets `IrisUser`;
  - `:65` `Check(ref, ns, prod)`;
  - `:81` `Incident(owner, noticedAt, ns, prod, fields)`;
  - `:315` `Clean`, which drops `BreakFeedRun` and `GuideState` rows;
  - `:348` `RemoveMessages(refs, ns)`;
  - `:410` `Headers`;
  - `:433` `Between`.
- Test patterns to reuse:
  - `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls`: seams through `..`, answers from `^OcuTalonTest`, called on a shadow instance (`Ens.Host.GetShadowInstance`);
  - `Test/Web/GuideApi.cls:231-253`: the `Csp` and `Post` stand-in request helpers;
  - `Test/Live/Publish.cls:290`: `Holder`, a lock held by a JOBbed process;
  - `Test/Bridge/WebStatus.cls:504-520` (Lane A): `AuditMark` and `AuditRows` read `%SYS.Audit`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:733` -- `TestRoutes` pins `"POST /v1/demo/break-feed NotBuilt"`.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:36-37` -- Lane B's oracle rows, with `"stub": 1` for both items. `Test.Install.Production` (lane-a shard) checks `STUB` against them, and `test-production.sh` row 16 too.
- `web/e2e/demo-path/04-incident.spec.ts` -- two `notBuilt(..., '11.1')` parts, both kept.
- `web/e2e/support/iris.ts` -- `irisScript` and `chk`. They need `OCUTALON_E2E_IRIS_CONTAINER`.
- `web/e2e/support/api.ts:37,45` -- `post` (the full envelope) and `sessionEvents`.
- `web/e2e/sign-in/helpers.ts:6,94` -- `README_ACCOUNT` and `signInReadme`.
- `web/e2e/api/api.spec.ts`:
  - `:50` `BREAK_FEED`;
  - `:66-70` `UNBUILT`;
  - `:244-247` "the whole envelope is let through", which expects 501.
- **Contended:**
  - `docker/tests/test-demo-switch.sh:16,311-316`: step 5 expects break-feed 501 with demo mode off;
  - `docker/tests/test-demo-path.sh:12-13,44-48`: no container variable reaches the e2e run. `cid` comes from `lib-live.sh:403`.
- `ci/units.sh` -- the `lane-b` shard holds the areas Demo, Web and Data, so no entry is needed.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0 (implement):** the first press over real HTTP (rows 13 and 15) proves that the request's process may use `SendRequestSync` (inference: `WebChatIn` already sends async from it). If it is refused, stop with `## Clarification Needed`: a grant is a veto item.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- kind `resolvedIncidents`, binds `oaa`: `SELECT i.ID FROM OcuTalon_Data.Incident i WHERE i.OwnerRef = ? AND i.Namespace = ? AND i.Production = ? AND i.State = 'resolved' AND i.NoticedAt <> '' ORDER BY i.NoticedAt, i.ID`. Add `ClassMethod ResolvedIncidents(sessionRef, namespace, production, Output sc) As %ListOfObjects` beside `LatestBreakFeedRun` (row 14).
- [ ] `src/ocutalon/cls/OcuTalon/Data/BreakFeedRun.cls` -- `ClassMethod Start(sessionRef, Output sc) As BreakFeedRun` (`sending`, `StartedAt` `NowUtc()`, saved) and `Method MarkSent() As %Status`. The doc says that `BreakFeedIn` is the only caller.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/BreakFeedProgress.cls` -- `ClassMethod FromRow(run) As BreakFeedProgress`.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Press.cls` (new) -- a `%RegisteredObject` with `SessionRef`: the input `Web.Api` hands to `BreakFeedIn`.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Msg/SendOrders.cls` (new; V1) -- an `Ens.Request` with `SessionRef` (22) and `Channel` (32), and a `Storage Default` block. It sets no `DEFAULTGLOBAL`, because it is a message.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/BreakFeedIn.cls`:
  - drop `STUB` and implement the Boundaries' order;
  - parameters: `CHANNEL` "web", `ORIGIN` "web_user", `LOCKWAIT` 10, `CLOSETIMEOUT` 10, `SENDTIMEOUT` 30;
  - private seams `Close(command, .result)` and `Trigger(request)`, each one `..SendRequestSync`;
  - output: JSON text, `{"outcome":"sent","state","startedAt"}` or `{"outcome":"inactive","reason"}`;
  - errors: a bad input (not a `Press`, an empty ref, no session row) is an error status with nothing written;
  - a failed publish is a `$$$LOGWARNING`, and the run goes on (rows 1 and 4 to 9).
- [ ] `src/ocutalon/cls/OcuTalon/Demo/PartnerTrigger.cls`:
  - drop `STUB`; parameters `COUNT` 50 and `DATEFORMAT` "MM/DD/YYYY";
  - `OnMessage(SendOrders)`: refuse any other class and an unknown session; read the session row, then `WriteAudit`, then `Send(traceRef)`;
  - `Send` is the one `New $NAMESPACE` method;
  - private seams `WriteAudit(data, description)` and `Send(traceRef)`;
  - the description is "Break the feed: 50 orders" (rows 2 and 10).
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - the route gets `Call="BreakFeed"`;
  - add `MESSAGENOTWATCHING` and `MESSAGEINCIDENTINPROGRESS` (the hints);
  - `ClassMethod BreakFeed()` follows the REST order;
  - a private `Press(input, .output)` creates `BreakFeedIn` and calls `ProcessInput`;
  - `Fail` gets `409: ..#HTTP409CONFLICT`;
  - the header names the route (row 13).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/BreakFeedInProbe.cls` (new) and `Test/Demo/BreakFeedIn.cls` (new):
  - the probe overrides `Close` and `Trigger`, recording each call and S's run count and state at that moment, and answering from `^OcuTalonTest`. It also overrides `LOCKWAIT` to 1 (inference: an inherited method reads the subclass's parameter; if it does not, the held-lock test waits the real 10 s);
  - the tests run on a shadow instance, with no production: rows 4 to 9 and 11, the lock held by a JOBbed holder, and a bad input;
  - the exact order: the close comes before any run, the run is `sending` at `Trigger`, then `sent`; the events are `sending`, `sent`, with the guide events filtered out.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/PartnerTriggerProbe.cls` (new) and `Test/Demo/PartnerTrigger.cls` (new):
  - the audit comes before the send, with exact data and a redacted copy;
  - a failed audit sends nothing;
  - an unknown session or another class sends nothing and writes no audit;
  - `COUNT` 50, and `DATEFORMAT` is `Partner`'s second format.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/IncidentManagerDouble.cls` (new) -- an `Ens.BusinessProcess` with a `Storage Default` block:
  - for an `IncidentCommand`, it records verb, ref, session, origin and S's run count. Then, by `^OcuTalonTest("IncidentManagerDouble","answer")`: "" closes the fixture incident (`State` closed, `ClosedAt`) and answers `Ok` 1; `refuse` answers `Ok` 0; `error` answers an error status;
  - any other request is answered OK with no response.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/BreakFeedProduction.cls` (new; throwaways and CI only):
  - the guard is `Test.Demo.Production`'s, plus `OcuTalon.Production` running;
  - the double goes in with `UseItemClass` and comes out with `RestoreItemClass` in `OnAfterAllTests`;
  - it covers rows 1, 2, 3, 6, 7, 8 (refuse), 10 and 12;
  - concurrent presses are JOBbed processes released by one gate;
  - the audit poll copies `AuditMark` and `AuditRows` (Rule 2 note).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls` -- make `WaitCount`, `Send`, `Count`, `Sessions` and `ErrorTexts` public class methods, and correct the header's "private class methods" sentence.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/ApiProbe.cls` (override `Press`, answering from `^OcuTalonTest("ApiProbe","press")`) and `Test/Web/BreakFeedApi.cls` (new) -- row 13 with stand-in requests.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipGuide.cls` -- `TestResolvedIncidents` (row 14), and the kind added to `TestRefusedOwners`.
- [ ] Shared surfaces:
  - `Test/Web/Api.cls` `TestRoutes`: `POST /v1/demo/break-feed BreakFeed`;
  - `Test/Core/ProductionItems.cls:36-37`: `"stub": 0`;
  - `web/e2e/api/api.spec.ts`: drop break-feed from `UNBUILT`. "Let through" expects 409 `not_watching` with hint 1, because README watches nothing on the sign-in stack.
- [ ] `web/e2e/demo-path/04-incident.spec.ts` -- one new `@floor` test, "Break the feed sends the session's 50 orders, which fail for real in the Orders production" (row 15), with the README account:
  - it seeds the README session's Orders watch with `irisScript`: `Fixture.Check(ref, "OCUORDERS", "OcuTalon.Demo.Orders.Production")`, the fixture for Lane A's watch;
  - it counts the batch with the now-public `Test.Demo.Production.Count`, polling up to 60 s;
  - every assertion is relative to the cursor;
  - the two `11.1` parts stay as they are.
- [ ] `web/e2e/support/iris.ts` -- its header and `required()`'s message also name `docker/tests/test-demo-path.sh`.
- [ ] **Contended, only once ruled (see `## Clarification Needed` in the Auto Run Result):**
  - `docker/tests/test-demo-switch.sh:16,311-316`: step 5 expects 404 `not_found`;
  - `docker/tests/test-demo-path.sh`: add `OCUTALON_E2E_IRIS_CONTAINER="$cid" \` to the e2e call at `:44-48`, and change header lines 12-13 to say that a step spec may seed fixtures for Lane A paths that are not merged yet.

**Acceptance Criteria:**
- Given demo mode on and S signed in, when the page calls `POST /api/v1/demo/break-feed`, then:
  - `BreakFeedIn` locks and checks `Guide.Compute`;
  - an inactive press answers 409 with its plain-English hint and sends nothing;
  - two quick presses send one batch (rows 4 to 6 and 13; `Test.Demo.BreakFeedIn`, `Test.Demo.BreakFeedProduction`, `Test.Web.BreakFeedApi`).
- Given demo mode off, when the route is called, then it answers 404 (`Test.Web.BreakFeedApi`; `live:demo-switch` step 5 once ruled).
- Given an available press and S's resolved Orders incident, when `BreakFeedIn` runs, then it first gets the double's synchronous answer to `closeForReplay`, and only then writes the run (rows 7 and 8).
- Given a press that passed, when it triggers the partner, then the run goes `sending` → `sent` with both publishes, and `PartnerTrigger` sends 50 `MM/DD/YYYY` orders tagged with S's `TraceRef` (rows 1 and 9).
- Given the Orders production, when the batch arrives, then:
  - 50 orders fail as real errors in OCUORDERS;
  - orders sent by other means fail the same way;
  - two sessions at once get exactly 50 each, with no shared state changed (rows 2, 3 and 12).
- Given a press, when it is recorded, then it is production messages and no turn, and one `Action` audit entry names the user, the `SessionRef` and the channel (rows 1, 10 and 11).
- Given the fresh demo-path stack, when 04's new test runs over real HTTP, then row 15 holds. Integration: the consumers `/events` (`breakfeed.progress` and the hook's `guide.state`) and the Orders production (50 failed headers) observe the press. NFR-7 is not asserted.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- AD-1: the press enters through a business service (`CreateBusinessService` + `ProcessInput`); REST writes no state.
- AD-3: the one `New $NAMESPACE` method in `PartnerTrigger`; `Partner.Send` runs in OCUORDERS.
- AD-4: `SessionRef` travels on OCUTALON messages only; the `TraceRef` is the batch's `SuperSession`; no ref from the client.
- AD-12: `BreakFeedIn` alone checks, under the lock; the replay rule; `breakfeed.progress` triggers the guide refresh.
- AD-15: `IncidentManager` is the only incident writer; `closeForReplay` is answered synchronously.
- AD-17: the `Action` entry through `Bridge.Audit`, in a production job, naming the acting user.
- AD-22 and AD-29: the double in `OcuTalon.Test.Demo`; real batches on throwaways; REL-2 on fixtures until Epic 11.
- AD-26: its own trace session, with the `TraceRef` as `SuperSession`.
- AD-33: one writer and one publisher.

**Task 0, measured in this plan.** On the lane-B warm throwaway `e4s3pw`, now torn down, a probe class was loaded as `PartnerTrigger` and reached through `SendRequestSync` from an adapterless service.
- **The send.** A pool-1 job of `OcuTalon.Production` that does `New $NAMESPACE` to OCUORDERS and calls `Partner.Send(50, "MM/DD/YYYY", ref, "")` sends the batch:
  - 50 headers `PartnerOrdersIn` → `OrdersFromPartner`, `Status` 8, in 50 sessions, with `SuperSession` = ref;
  - the event-log error "...Expected YYYY-MM-DD, got '10/25/2026'.".
- **Timing.** The send took 0.023 to 0.052 s, and the whole `SendRequestSync` 0.026 to 0.056 s.
- **The job afterwards.** `%Ensemble("ConfigName")` stays `PartnerTrigger`, and later requests on the same job work. OCUTALON logged no warning or error. The job runs as `_Ensemble`.
- **Leftovers.** The job stays registered in OCUORDERS as a visiting temp job of `PartnerOrdersIn`, as any outside caller of an adapterless service does. Stopping and restarting the Orders production clears it, the `PartnerTrigger` job survives, and the next batch fails as expected.
- **Unmeasured (inference).** `SendRequestSync` from the REST process; implement's Task 0 settles it.

**Decided in-stage:**
1. **REST contract.** The codes are the reasons; the hints are the UX texts. 200 carries the run's `breakfeed.progress` view, and the body is not read.
2. **Lock and timeouts.**
   - The lock waits 10 s. On a timeout the answer is `incident_in_progress`, because a press is in flight.
   - The close waits 10 s and the send 30 s, so the worst case, 50 s, stays under the gateway's 60 s.
   - A refused close is a 409; an error or a timeout is a 500.
3. **Which incidents are closed:** only the session's own noticed `resolved` Orders incidents. An `instance` incident is shared with other watchers and can't absorb session-tagged failures (AD-4, AD-15). This needs a new `Ownership` kind.
4. **Origin and key.** `Origin` is `web_user`, because the press comes from the signed-in page. There is no `IdempotencyKey`: the press is not a tool call.
5. **The audit.** It is written in `PartnerTrigger` (a production job, AD-17) from `Session.IrisUser`, so no user name travels in a message (AD-4). It comes before the send, and a failed write sends nothing, as `SettingsOps` does. A refused press is no run and writes no entry.
6. **A failed partner leaves the run `sending`.** The guide's 180 s rule makes the control available again; no new run state is added.
7. **The batch.** 50 orders in `MM/DD/YYYY`, with no order date, so the partner uses its local date today.
8. **Doubles and seams.**
   - `Close` and `Trigger` are seams for the unit tests, which run on a slot with no production.
   - The real item swap is in `BreakFeedProduction`.
   - Once Epic 5 merges, the double ignores failure batches.
9. **"Never counts toward the allowance."** The allowance keeps no count until Story 16.9. So it is pinned structurally: the press's classes name no `Core.Allowance`, and no `Turn` row is made (labelled).
10. **`api.spec.ts` "let through".** It now expects 409 `not_watching`, which has no side effect. The README session watches nothing on the sign-in stack: no spec seeds an Orders check there.
11. **Demo-path fixture.** A fixture Orders check for README stands in for Lane A's watch (Epic 5's `WatchOps`), as the AC's "fixtures for Lane A's incident path" asks. Epic 11 replaces it with the real chat watch.

**Veto-window item (written with the recommendation):**
- **V1 (stored data: a new message class).**
  - `OcuTalon.Demo.Msg.SendOrders` (`SessionRef`, `Channel`) is the `BreakFeedIn` → `PartnerTrigger` request. Its readable class name shows in Visual Trace (AD-26).
  - It is additive, and no message of it exists yet.
  - Reversal: send an `Ens.StringRequest` that carries the `SessionRef`.

**Rule 2:**
- `Ownership` gains one kind of `Statement`; `BreakFeedProgress.FromRow` follows `Live.Payload.Decision.FromRow`.
- `Web.Api.Press` repeats `Post`'s three lines for `BreakFeedIn`. `Post` stays untouched because `ApiProbe` overrides its signature, and `Web.Api` is shared with Epic 8 by function, which prefers new methods.
- `Fail` gains one `$Case` branch for 409. That is an extension of the shared method; no caller changes.
- `Test.Demo.Production`'s helpers become public and are reused, not copied.
- `AuditMark` and `AuditRows` are copied from `Test.Bridge.WebStatus`, a contended Lane A test whose helpers are private.
- The probes follow `SettingsOpsProbe`.

**Integration ACs (Rule 1).** Each is checked on a real instance:
- `Web.Api` (HTTP) consumes `BreakFeedIn`;
- the `Live.Publish` hook, through `Guide.Compute` and `/events`, consumes the run rows and `breakfeed.progress`, with the stage `sending` and then `waiting`;
- the Orders production consumes `PartnerTrigger`'s batch;
- the `IncidentManager` item (the double) consumes `closeForReplay`.

**Consumed-by:**
- Story 4.4: the box renders from `guide.state`, and the press's 200 and 409 answers.
- Story 4.7: Run again and the finish.
- Epic 5: `FailurePoller` and `IncidentManager` turn the `TraceRef`-tagged failures into the session's incident. Story 5.5 answers `closeForReplay`.
- Epic 11: turns 04's `11.1` parts on.
- Story 16.9: its allowance count must not include presses.

**Consumes:**
- `Guide.Compute` and the `BreakFeedRun` reads (4.2);
- `Partner.Send` and the Orders production (0.10);
- `Bridge.Audit` (0.4);
- `RunnerFixture.UseItemClass` (Lane A, test);
- `Fixture` rows for Lane A's checks and incidents.

**Ledger.**
- **Declined DW-98:**
  - **The `decision.recorded` half is already met in this tree.** Story 2.17's `Test.Core.{Routing,Conversation,Thread}Production` drive the real `Decide`'s emission through the production's `BridgeSink` to the session stream. Its review demonstrated it: "`BridgeSink.OnEvent` drops `decision.recorded` → `RoutingProduction` red".
  - **This story's batch makes no decision.** `IncidentManager` is a stub until Epic 5.
  - **The `turn.step` half can't be met from Epic 4.** No bridge code in this tree emits `turn.step` (only `Decide.cls:765,837` fire, and they fire `decision.recorded`). AD-9 and Story 3.2 put that report in the governance gate, in contended `src/bridge/**`.
  - Recommended to the lead:
    - close the first half as `resolved-by` Story 2.17;
    - re-own the residual, "assert that the gate's `turn.step` reaches the session's stream through `BridgeSink`", to `3-2-one-gate-decides-every-tool-call` (another epic's story: the orchestrator's call).
  - The evidence step under Verification re-runs the mutation on this tree.

**For the lead:**
- **Footprint.** These Lane B paths are outside the listed footprint; none is contended:
  - `Data/{BreakFeedRun,Ownership}.cls` and `Live/Payload/BreakFeedProgress.cls`;
  - `Test/Web/{Api,ApiProbe,BreakFeedApi}.cls`, `Test/Data/OwnershipGuide.cls` and `Test/Core/ProductionItems.cls` (Lane B's rows);
  - `web/e2e/api/api.spec.ts` and `web/e2e/support/iris.ts`.

  The two contended scripts are in the clarification.
- **Spine (Rule 20, a dependency edge only).** `BreakFeedIn` and `PartnerTrigger` read `Install.Step.Demo`'s `NAMESPACE` and `PRODUCTION`, as `Guide` does. So the edge `Guide --> DemoKey` becomes `Demo --> DemoKey`. This is not an AD change.

## Verification

`<B>` means: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=implement'`.
- The fresh tag is `e4s3i`; tear it down with `ci/iris.sh teardown`.
- The warm tag is `e4s3iw`: `ci/warm.sh up` once, `down` at the end, also after a failure.
- One command per foreground call (`timeout: 600000`).
- Real batches, the item swap and `live` units run only on fresh throwaways. Slot B is for loading and compiling only.

**Commands:**

`(loop)`:
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s3iw ci/iris.sh class <C>`, one call each, for these classes. Expected: `CLASS ... passed`.
  - `OcuTalon.Test.Demo.BreakFeedIn`
  - `OcuTalon.Test.Demo.PartnerTrigger`
  - `OcuTalon.Test.Web.BreakFeedApi`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Data.OwnershipGuide`
  - `OcuTalon.Test.Demo.Guide`
  - `OcuTalon.Test.Live.GuideRefresh`
  - `OcuTalon.Test.Install.Production`
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh class OcuTalon.Test.Demo.BreakFeedProduction` (fresh) -- expected: passed.
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh class OcuTalon.Test.Demo.Production` (fresh) -- expected: passed.
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh live demo-path` (fresh) -- expected: PASS, with 04's new `@floor` test passed.
- `npm --prefix web run lint` -- expected: exit 0.

`(once)`:
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh shard lane-a` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh live demo-switch` (needs the ruling) -- expected: all PASS.
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh live sign-in` -- expected: PASS.
- `<B> OCUTALON_RUN_TAG=e4s3i ci/iris.sh live production` -- expected: PASS (row 16's stubs).
- `npm --prefix web test` and `bash ci/checks.sh` -- expected: exit 0.
- **DW-98 evidence (warm).** Apply the mutation "`BridgeSink.Recorded` publishes nothing" and run `class OcuTalon.Test.Core.RoutingProduction` and `ConversationProduction`. Expect red, then revert byte-identical. Record the line below.

**Planned mutations.** Apply each, observe red, revert, confirm `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | the availability check skipped | `BreakFeedIn` row 4 |
| 1 | the lock released before the run is written | `BreakFeedProduction` row 6 (two runs, 100 headers) |
| 2 | `BreakFeed` without its demo-off check | `BreakFeedApi`, and `live:demo-switch` once ruled |
| 3 | the run written before `Close` | `BreakFeedIn` order, and `BreakFeedProduction` row 7 (runs = 1) |
| 3 | a refusal ignored | row 8 |
| 4 | `MarkSent` dropped | row 1 |
| 4 | `PartnerTrigger` sends `traceRef` "" | rows 1 and 2 |
| 5 | `DATEFORMAT` "YYYY-MM-DD" | row 2 |
| 5 | the first session's `TraceRef` used for both | row 12 |
| 6 | `WriteAudit` skipped | row 10 and `PartnerTrigger` |
| 6 | `BreakFeedIn` also calls `Allowance.TryConsume` | row 11 |
| 7 | `COUNT` 49 | `live:demo-path` 04 |
| — | `resolvedIncidents` without the owner check | `OwnershipGuide` |

**Shared surfaces:**
- the route table (`TestRoutes`, `api.spec.ts` `UNBUILT`) and the envelope rows of `api.spec.ts`;
- `live:demo-switch` step 5;
- Lane B's production-item oracle rows (`Test.Install.Production`, `test-production.sh` row 16);
- the `IncidentManager` item's class, swapped and restored by `BreakFeedProduction`;
- the OCUORDERS and OCUTALON message stores, where each test removes its own `TraceRef`'s messages;
- session streams, which gain `breakfeed.progress` and `guide.state` after a press, so tests filter by type;
- the demo-path stack's README session, which gains a fixture Orders watch, a run and 50 failed orders (steps 5 and 6 are `notBuilt`);
- `Test.Demo.Production`'s helpers becoming public.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked
Blocking condition: Clarification Needed (contended paths, Rule 11 (c)). The spec is otherwise ready for development, but two existing `docker/tests/**` scripts must change beyond the one appended block that the standing ruling allows. (1) `docker/tests/test-demo-switch.sh` (Story 4.1's script), line 16 and lines 311-316: step 5 asserts that `POST /v1/demo/break-feed` answers 501 `not_built` with demo mode off. This story's AC makes that 404 `not_found`, so `live:demo-switch` turns red unless the check and its header line change to 404. (2) `docker/tests/test-demo-path.sh` (Story 0.8's script): lines 44-48 must pass `OCUTALON_E2E_IRIS_CONTAINER="$cid"` to the demo-path e2e run, and header lines 12-13 must say that a step spec may seed fixtures. Only then can the REL-2 spec `web/e2e/demo-path/04-incident.spec.ts` seed the README session's Orders watch (Lane A's watch is not merged) and count the batch in OCUORDERS, as the AC asks ("checks the press and the batch, using fixtures for Lane A's incident path"). Recommended ruling: a one-time footprint extension for exactly those lines, as in the Story 8.1 and 13.1 rulings. On that ruling, set the status to ready-for-dev; no re-plan is needed. If (2) is refused, the demo-path stack can check only the 409 press, and dropping the batch check from the AC is an owner-only scope call.

**For the spec gate.** Veto V1 is the new message class `OcuTalon.Demo.Msg.SendOrders`. DW-98 is declined, with a re-own to `3-2-one-gate-decides-every-tool-call` recommended (Design Notes, Ledger). The spine needs one edge relabel, `Guide --> DemoKey` to `Demo --> DemoKey` (Rule 20, an edge only). Task 0 was measured in this plan on the throwaway `e4s3pw`, now torn down.
