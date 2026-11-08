---
title: 'Story 18.4: Read the digest on every channel and mark notices as handled'
type: 'feature'
created: '2026-11-08'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-18-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Stories 17.10, 17.11 and 12.12 delivered a plain-text web digest card, Telegram's digest and Got it, and the server half of Got it. The web card still has no teal bar and no "What I checked ({n})" disclosure, and its check rows reach neither the event nor a reload. The Simulated phone shows no digest. The web chat and the phone have no Got it control and no "Marked as handled at {time}" copy. The Digest chip still reads release 1's meaning, and `Data.Handled` has no purge (DW-695).

**Approach:** Extend what exists; do not rebuild it:
- the digest's `Slots.rows` are kept on the web `Delivery` row and carried in the `notification` payload, which the notice card draws with `app-check-rows`;
- `SimPhoneOut` renders a digest through `DigestText.Text(slots, "phone")`;
- a web route submits the existing `GotIt`;
- both `*Out`s update their copy on the existing `handled` Notification;
- the chip text changes;
- `Handled.Purge(daysToKeep)` is added. Registering it is Lane A's.

## Boundaries & Constraints

**Always:**
- Judge against delivered code; reuse `SessionOps.GotIt`, `Handled.Marked`, `Delivery.FindByRef` / `Ownership.DeliveryByRef`, `DigestText.Text`, `Catalog.Render`, `Part.CheckRow.ListFromJSON`, `Bridge.Time.DaysCutoff`, `ServerButton`, `app-check-rows` and the catalog keys `button.gotIt` and `handled.marked` as built.
- `WebChatOut` stays the only `notification` publisher and `SimPhoneOut` the only `phone` publisher (AD-33). Producers never render; the page formats times itself (AD-32).
- Got it: the route submits with origin `web_user`, and only through `Commands.Submit`. `SessionOps` alone decides (own tell-now Decision; first press wins). A decision the session can't see is 404 before anything is submitted.
- No all-clear comes from rows (AD-28). A result other than `passed` shows as Not checked and expands the disclosure.
- New user-facing strings ship only as ruled (PUBLIC TEXT). Each one is pinned by a fixed-string test.
- The demo path stays green (product default 1).

**Never:**
- Edit Lane A files (U-177): `Digest/**`, `Checks/**`, `Channel/Telegram/**`, `Channel/DigestText.cls`, `Msg/Catalog/Watch.cls`, `Install/**`, `src/bridge/**`, or the Lane A test areas.
- Edit `Core/SessionOps.cls`, `Core/CommandsIn.cls`, `Data/Ownership.cls` or `Production.cls`; none is needed.
- In `Web/Api.cls`, `Test/Web/Api.cls` and `Test/Web/BodyLimit.cls`, change anything beyond the named additions (Epic 41 contends them).
- Add a role, an origin or a grant. Add a column for the handled marker (AD-14: it is `Handled`).
- Edit `ARCHITECTURE-SPINE.md`, `EXPERIENCE.md`, `DESIGN.md`, `release/**` or `eval/run.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Digest with rows | kind `digest`, `Slots.rows` = [passed, failed] | web row keeps `CheckRows` (the rows JSON); event and snapshot payload carry `checks` (2). Card: teal 4px bar, text, "What I checked (2)" with `aria-expanded="true"`, two check rows | Slots unreadable: no row, no event (as built) |
| All passed | rows all `passed` | the disclosure is collapsed; pressing it opens the rows inline | -- |
| No rows | `rows: []` | the card is the text alone, with no disclosure | -- |
| Phone digest | demo on, `digest.channels` has phone | one SimMessage, text = `DigestText.Text(slots,"phone")`, one `phone` event. Greeting first, "Passed:"/"Failed:"/"Not checked:" lines, cost `$n.nn`, no Markdown | render error: no row, no event |
| Web Got it | `POST /v1/decisions/:ref/got-it` `{}` on the session's own tell-now | 200 `{"result":"done","handledAt"}`. One Handled row (channel web), then the web card is republished with `handledAt` and the phone message is edited | -- |
| Phone Got it | same, body `{"channel":"phone"}` | as above, with channel `phone` | -- |
| Second press | the notice is already marked | 200 with the first `handledAt`. No new event, no edit | -- |
| Not visible / not tell-now | another session's Ref, a digest Decision, a bad Ref | 404 `not_found`; nothing written | owner failed: 500 |
| Copies after a press | either channel pressed | web card: no Got it, the line "Marked as handled at {time}" (browser zone), also after a reload. Phone: its answer line is the server's "Marked as handled at {time}", with no Got it | no card row: bare Delivery row only (as today) |
| Purge | `Handled.Purge(90)` | deletes the rows whose `HandledAt` is before `DaysCutoff(90)`; rows at or after it stay | bad day count: error, nothing deleted |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`:
  - `OnNotification` :61. The digest branch is :68.
  - `Record` call :74 (append the rows).
  - Kind `handled` today falls to the record-only branch :65-66.
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls`:
  - `CARDKINDS` :31; `OnNotification` :53.
  - `EditAnswered` :70-90 is the sibling of the handled edit.
  - `Save` :94-106 (sets ApprovalRef for `REQUESTKINDS` only).
- `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls` (Lane A, read only): `Text(slots, channel, .sc)` :17.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` (Lane A, read only):
  - `EditHandled` :296-322 is the pattern for the handled copy: `DeliveryByRef`, skip a row of kind handled, `Handled.Marked`, `Render(handled.marked, {time})`.
  - `GotItKeyboard` :203.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls`:
  - properties :12-39; `Record` :48 (`Output row` is its last parameter today).
  - `FindByRef` :83.
- `src/ocutalon/cls/OcuTalon/Data/SimMessage.cls`: `ApprovalRef` :40 and `Answer` :43 are the siblings of the new `DecisionRef`.
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls`: `Marked` :30, `DropSession` :39.
- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls` `Purge` :218 is the sibling purge. Use `src/bridge/cls/OcuTalon/Bridge/Time.cls` `DaysCutoff` :203 (DW-371's shared helper), not a copy.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` (read only, contended):
  - `DeliveryByRef` :478 gives the newest row by DecisionRef.
  - The `recentNotices` SQL :909-911 already keeps `digest` rows with a ChannelMessageId.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Notification.cls` `FromRow` :44. Siblings:
  - `Live/Payload/ChatMessage.cls` :58 (`Checks As list Of Part.CheckRow`) and :87 (`ListFromJSON(row.CheckRows)`);
  - `Data/Turn.cls:71` `CheckRows`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Phone.cls` `FromRow`.
- The snapshot reads both payloads through `FromRow`: `Web/Api.cls` :1113-1118 (notices) and :1040-1043 (phone). No snapshot change is needed.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` (read only) `GotIt` :251-277: outcomes `handled`, `already_handled`, `not_found`, `failed`. The `handled` Notification has `DecisionRef`, CatalogKey "", Slots `{}`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (contended):
  - UrlMap :178 (`/v1/incidents/:ref/dismiss`);
  - `DismissIncident` :668 is the sibling handler (Ownership check, `Commands.Submit` `web_user`, outcome map).
  - Epic 41 adds `/v1/decisions/:ref/noise` after `/v1/heartbeat/run` and its handlers at the end of the class. Its channel rule is "exact `{"channel":"phone"}` is phone, else web".
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (Lane A, read only): `button.gotIt` :422, `handled.marked` :427 (slot `time`).
- Web:
  - `web/scripts/catalog.mjs` `LISTED_KEYS` :61-102; then `npm --prefix web run catalog` regenerates `web/src/app/msg/catalog.ts`.
  - `web/scripts/payloads.mjs`; then `npm --prefix web run payloads` regenerates `web/src/app/live/payloads.ts`.
  - `web/src/app/chat/chat-view.ts`: `CHAT_TEXTS.meaningDigest` :71, `NOTICE_TEXTS` :80, `NoticeView` :145, `noticeOf` :214.
  - `web/src/app/chat/notice-card.ts`: template :33-53, `.digest` style :82-85. The tokens are `--digest-card-*` in `web/src/styles/tokens.css` :537-540, :769-771, :992-994.
  - `web/src/app/chat/check-rows.ts`: the row component (inputs `checkKey`, `checks`). Pass no `checkKey`: the digest text already holds the sentence.
  - `web/src/app/incidents/incident-dismiss.ts` :100-120: the ServerButton press with the error notice (`messageOf(error) || BUSY_NOTICE`). The Got it control copies this pattern.
  - `web/src/app/api/api-client.ts` :133 `dismissIncident` is the sibling of `gotIt`.
  - `web/src/app/phone/simulated-phone.ts` :53 (the `approvalRef` branch).
  - `web/src/app/phone/phone-view.ts` :49-60, :144-160 (`answered`, `requestView`).
  - `web/src/app/phone/phone-request.ts`: the answer-line pattern.
- Tests that hold the old shapes or texts:
  - `Test/Core/GotItChannels.cls` (both tests assert record-only);
  - `Test/Demo/SimPhoneOut.cls:279` (`digest` among the record-only kinds);
  - `Test/Core/WebChatOut.cls` `TestDigestCard` :310 and :304;
  - `Test/Live/Payloads.cls` :1166 (Notification), :1189 (Phone), `TestNotificationFromRow` :835;
  - `Test/Data/Tables.cls` :412 (SimMessage), :433 (Delivery);
  - `Test/Web/Api.cls` `TestRoutes` :953; `Test/Web/BodyLimit.cls` `POSTROUTES` :14;
  - `web/e2e/chat/notice.spec.ts` N16 :469;
  - meaningDigest: `web/scripts/chat-view.test.mjs:493`, `web/scripts/ux-strings.test.mjs:228`, `web/e2e/chat/chat.spec.ts:152`, `web/e2e/chat/decision.spec.ts:250`, `web/e2e/demo-path/01-page.spec.ts:69`;
  - `README.md:74` with `docker/tests/test-readme.sh` `chk_outcomes` :644;
  - `web/e2e-online/demo-path/demo-path.spec.ts` step 7 :260-281 ("the simulated phone gets no digest note") and its comment in `docker/tests/test-online-demo-path.sh:13-14`.
- Test siblings to follow:
  - `Test/Web/DismissApi.cls` (route through the real production; throwaway and CI only);
  - `Test/Data/PairingRows.cls` (purge);
  - `web/e2e/support/iris.ts` `sendNotification`, `seedDecision`, `fixtureUser('NOTICE')`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls` -- add `Property CheckRows As %String(MAXLEN = "")` (the rows JSON of a web digest card; empty otherwise), with its storage value. Append `checkRows As %String = ""` as `Record`'s LAST parameter, after `Output row`, so every caller is unchanged. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Data/SimMessage.cls` -- add `Property DecisionRef As %String(MAXLEN = 22)`: set on a tell-now phone message only. A row written before it reads empty.
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls` -- `ClassMethod Purge(daysToKeep As %Integer) As %Status`:
  - `Bridge.Time.DaysCutoff(daysToKeep, "OcuTalon.Data.Handled.Purge", .cutoff)`; on an error or an empty cutoff, delete nothing;
  - delete the rows with `HandledAt < cutoff`, the way `DropSession` does;
  - update the class doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Notification.cls`:
  - `Checks As list Of OcuTalon.Live.Payload.Part.CheckRow(%JSONFIELDNAME = "checks")`, from `ListFromJSON(row.CheckRows)`;
  - `HandledAt` (`handledAt`, MAXLEN 20) = `Handled.Marked(row.DecisionRef)`, for kind `tellnow` only;
  - update `FromRow`'s doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Phone.cls` -- `DecisionRef` (`decisionRef`) from the row.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`:
  - the digest branch passes the `rows` member of the Slots (as JSON, `[]` when absent) to `Record`;
  - add kind `handled`: read `Ownership.DeliveryByRef(DecisionRef, "web", SessionRef)`. When the row is a `tellnow` card with a ChannelMessageId, `Announce` one `notification` event with `FromRow` of THAT row (same ref, now with `handledAt`). Then record the bare handled Delivery row as today. A row of kind `handled`, or no card, gives the row only and no event;
  - update the class doc.
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls`:
  - add `digest` to the message kinds, with the text of `DigestText.Text(Slots, "phone", .sc)` in place of `Render`;
  - `Save` sets `DecisionRef` for kind `tellnow`;
  - add `EditHandled`, the sibling of `EditAnswered`: `Delivery.FindByRef(DecisionRef, "phone", SessionRef)` gives the message. It must be this session's phone message with that `DecisionRef`. An empty `Answer` becomes `Render("handled.marked", {"time": Handled.Marked(ref)}, "phone")`, kept with a Delivery row of kind handled in one transaction, then one `phone` event. When an answer is already there, or there is no message, record the Delivery row only;
  - update the class doc.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (contended):
  - one UrlMap line, `<Route Url="/v1/decisions/:ref/got-it" Method="POST" Call="GotIt"/>`, right after the dismiss route;
  - the handler `GotIt(ref)`, right after `DismissIncident` (not at the end of the class): Ownership session and `Decision` check (404 first); channel `phone` only for the exact body `{"channel":"phone"}`, else `web`; `Commands.Submit` of `Msg.Command.GotIt` with origin `web_user`;
  - outcomes: `handled` / `already_handled` give 200 `{"result":"done","handledAt": Handled.Marked(ref)}`; `not_found` 404; `not_built` 501; anything else 500;
  - one class-doc clause.
- `web/scripts/catalog.mjs` -- list `button.gotIt` and `handled.marked` (slot type `time`) in `LISTED_KEYS` and its header comment. Run `npm --prefix web run catalog` and `npm --prefix web run payloads`.
- `web/src/app/chat/chat-view.ts`:
  - `meaningDigest` = "Saved for the daily digest";
  - `NOTICE_TEXTS.whatIChecked` = "What I checked ({n})";
  - `NoticeView` gains `checks`, `handledAt` and `decisionRef`;
  - add the pure `digestOpen(checks)`: true when any row's result is not `passed`.
- `web/src/app/chat/got-it.ts` (new) -- the Got it control, inputs `ref` and `channel`. It copies `incident-dismiss.ts`'s press: a ServerButton labelled from `PAGE_TEXTS['button.gotIt']`, calling `api.gotIt(ref, channel)`; an error reply sets and announces `messageOf(error) || BUSY_NOTICE`. Add `gotIt` to `api-client.ts` and `GotItBody` to `api-types.ts`.
- `web/src/app/chat/notice-card.ts`:
  - a digest takes the `--digest-card-*` background, border, accent bar and radius;
  - with one or more checks, it adds a button "What I checked ({n})" with `aria-expanded` (starting from `digestOpen`) and `aria-controls`, over `app-check-rows [checks]`, inline;
  - a tell-now with a `decisionRef` shows `app-got-it` (channel web) until `handledAt`, then the line `renderPageText('handled.marked', {time: pageTimeBeside(handledAt, zone)})`;
  - update the class doc.
- `web/src/app/phone/simulated-phone.ts`, `phone-view.ts` -- a message with `decisionRef` and no `approvalRef` shows its text, then `app-got-it` (channel phone) while `answer` is empty, else its `answer` line (muted, as `phone-request.ts` draws one). Add the pure `gotItShown(message)`.
- `README.md:74` -- "**Digest**: Saved for the daily digest." (`chk_outcomes` pins it to `meaningDigest`).
- IRIS tests (shadow instances unless noted):
  - `Test/Core/WebChatOut.cls`: `TestDigestCard` keeps the rows (`CheckRows`, payload `checks`) and an empty `rows`. Add `TestHandledRepublishesTheCard` (one event, the card's ref, `handledAt`; the bare row), `TestHandledWithNoCardRecordsOnly` and `TestReloadShowsHandled` (`FromRow` after a mark).
  - `Test/Core/GotItChannels.cls`: rewrite both tests to the new copies (web republish; phone edit), and `TestSecondHandledChangesNothing`.
  - `Test/Demo/SimPhoneOut.cls`:
    - `TestDigestMessage`: the text equals `DigestText.Text(slots,"phone")`; the first line is a greeting; the lines starting "Passed:", "Failed:", "Not checked:"; `$0.04`; no `*`, `_`, `` ` `` or `#`; one event;
    - `TestTellNowKeepsDecisionRef`, `TestHandledEditsInPlace`, `TestHandledFirstAnswerStays`, `TestHandledNoMessageRecordsOnly`, `TestHandledNeverEditsAnotherSession`;
    - `:279` drops `digest`.
  - `Test/Live/Payloads.cls`: the Notification and Phone shapes, and `FromRow` (`checks`, `handledAt` for tellnow only, `decisionRef`).
  - `Test/Data/Tables.cls`: the two new properties.
  - `Test/Data/HandledPurge.cls` (new): the cutoff edges, bad day counts, other rows untouched.
  - `Test/Web/GotItApi.cls` (new; extends `DismissApi`'s pattern; throwaway and CI only): AC 4. Also:
    - `TestOtherSessionIs404`: 404, and no GotIt reached SessionOps (the trace's CommandList, as in `DismissApi`);
    - `TestDigestDecisionIs404`, `TestSecondPressIs200`, `TestPhoneBody`.
  - `Test/Web/Api.cls` `TestRoutes` (+1 route); `Test/Web/BodyLimit.cls` `POSTROUTES` (append `/v1/decisions/zzRef/got-it`).
- Web unit tests:
  - `web/scripts/chat-view.test.mjs`: `noticeOf` checks/handledAt/decisionRef, `digestOpen`, meaningDigest;
  - `phone-view.test.mjs`: `gotItShown`;
  - `catalog.test.mjs`: the listed keys;
  - `api-client-sources.test.mjs`: the route;
  - `ux-strings.test.mjs`: sources for the new and changed strings;
  - `web/scripts/digest-card-sources.test.mjs` (new; the `approval-sources.test.mjs` pattern): `notice-card.ts` uses the `--digest-card-*` tokens and `app-check-rows`, and `got-it.ts` uses `ServerButton` and `messageOf`.
- `web/e2e/chat/notice.spec.ts` (NOTICE fixture user, the chromium project):
  - N16 becomes the full card: the `--digest-card-accent-bar` colour and 4px, the text, "What I checked (2)" expanded with a failed row, a passed-only digest collapsed and opened by a press, and the same after a reload;
  - N17: Got it on the web card, then "Marked as handled at" on the web card and on the phone message, with no Got it on either, also after a reload;
  - N18: Got it on the phone, and the web card updates;
  - N19: the phone digest is one message, starting with the greeting and ending with the cost.
  - Use `getByRole` with exact names, scoped to the card or phone message found by a unique marker.
- `web/scripts/chat-view.test.mjs:493`, `ux-strings.test.mjs:228`, `web/e2e/chat/chat.spec.ts:152`, `web/e2e/chat/decision.spec.ts:250`, `web/e2e/demo-path/01-page.spec.ts:69` -- the new meaning text.
- `web/e2e-online/demo-path/demo-path.spec.ts` step 7 (and the comment in `docker/tests/test-online-demo-path.sh:13-14`) -- the phone now gets exactly one digest note, its first line a greeting and its last the cost. The card assertions are unchanged.

- [ ] [Ruling U-313] Pin that an OLDER row renders without error: a `Data.Delivery` digest row with `CheckRows` empty and a `Data.SimMessage` row with `DecisionRef` empty (as rows written before this story are) -- the web chat's digest card (and `RecentNotices` after a reload) and the phone render them without error (a card without the disclosure; a phone message with no Got it edit). One IRIS test and, if the web side reads the payload, one web unit case.
- [ ] [U-177 grant (a)] Exactly ONE appended call registering `OcuTalon.Data.Handled.Purge(daysToKeep)` in `src/ocutalon/cls/OcuTalon/Install/Step/Core.cls`'s `Purge` method (append it after the existing purge calls; nothing else in that method or file, and nothing else in any Lane A file). Epic 41 also edits that method: keep the hunk to the one line so the second merge is a plain union.
- [ ] [Doc] `Channel/DigestText.cls`'s class comment names SimPhoneOut as a third caller (doc-only, allowed by the orchestrator).
- [ ] [Demo path, ruled] `web/e2e-online/demo-path/demo-path.spec.ts:279` and its comment in `docker/tests/test-online-demo-path.sh` change from "no digest note" to EXACTLY ONE digest note on the simulated phone. Nothing else in the demo path changes.

**Acceptance Criteria:**
- **AC 1.** Given a digest Notification with rows, when `WebChatOut` delivers it, then the web chat shows the digest card: a 4px brand-teal bar (`--digest-card-accent-bar`), the digest text, then "What I checked ({n})" over the check rows, expanded when any row failed or wasn't checked and collapsed otherwise. The card is the same after a reload. Pinned by `Test.Core.WebChatOut` `TestDigestCard`, `chat-view.test.mjs` `digestOpen`, and N16.
- **AC 2.** Given the same notification and demo mode on, when `SimPhoneOut` renders it, then the phone gets one plain-text message:
  - the parts in the PRD's order and a time-of-day greeting;
  - check lines starting "Passed:", "Failed:" or "Not checked:";
  - the previous day's cost with two decimals;
  - no Markdown, and the reserved sentences as their catalog keys give them.

  Pinned by `Test.Demo.SimPhoneOut` `TestDigestMessage` and N19. Telegram is already met (Design Notes).
- **AC 3.** Given a tell-now notice on the web chat and the phone, when the user presses **Got it** on either, then the handled marker is set once (the first press wins). Both copies show "Marked as handled at {time}" within one live update and lose Got it, and the item no longer counts as needing the user. Pinned by `GotItChannels`, `SimPhoneOut` `TestHandled*`, `WebChatOut` `TestHandled*`, N17 and N18.
- **AC 4 (Integration, Rule 1).** Given the real production, when `POST /v1/decisions/:ref/got-it` is called for the session's own tell-now notice, then the consumer chain (`CommandsIn`, then `SessionOps`, `Notify`, `WebChatOut` and `SimPhoneOut`) produces:
  - one Handled row, with the route's channel;
  - one `notification` event of the card's ref carrying `handledAt`;
  - one `phone` event whose `answer` is the rendered handled line;
  - `Digest.NeedsYou` no longer counting it;
  - and a second press is 200 with the same `handledAt` and no new event.

  Pinned by `Test.Web.GotItApi` `TestPressUpdatesEveryCopy`.
- **AC 5.** Given the Digest outcome chip, when its meaning shows (the strip description or the tooltip), then it reads "Saved for the daily digest". Pinned by `chat-view.test.mjs`, `decision.spec.ts:250` and `test-readme.sh`.
- **AC 6.** Given the demo-path tests and the web tests, when this story merges, then the demo path still passes (with the step 7 phone note). The Playwright tests cover the Settings page as the README account (already met: `settings.spec.ts` S1 to S14), a fixture digest card (N16, N19) and **Got it** (N17, N18).
- **AC 7 (DW-695).** Given Handled rows of different ages, when `Handled.Purge(daysToKeep)` runs, then exactly the rows handled before `DaysCutoff(daysToKeep)` are deleted, and a bad day count deletes nothing. Pinned by `Test.Data.HandledPurge`. The registration is a LANE A RESIDUAL (Design Notes).

## Spec Change Log
- 2026-11-08, rulings (Contest Planner under the owner's delegation, relayed by the orchestrator; key planner-2026-11-08-18.4): PUBLIC TEXT rows 1-6 APPROVED exactly as listed, all pinned with fixed strings; U-177 grant (a): one appended call registering `Data.Handled.Purge` in `Install/Step/Core.cls` `Purge`, nothing else in Lane A (whichever of Epics 18 and 41 merges second takes it as a plain union); the demo path's "no digest note" assertion becomes exactly one phone digest note, nothing else changes; the `DigestText` class-comment doc change is allowed; access unchanged.
- 2026-11-08, inbox answers applied (owner via the inbox, relayed): U-312 at=2026-11-08T20:03:06Z#950 KEEP -- `Data.Handled.Purge` uses AD-27's `DaysToKeep` (90 days), no new number; U-313 at=2026-11-08T20:03:06Z#951 KEEP -- two nullable columns (`Delivery.CheckRows`, `SimMessage.DecisionRef`), older rows read empty, no migration, and ADD a pin that an older row (both columns empty) renders without error (task added).
- 2026-11-08, spine (orchestrator ruling): at close the LEAD records AD-14's as-built Got it note, the Notice cards convention row and the REST row for `POST /api/v1/decisions/:ref/got-it`, with the orchestrator's marker; AD-27's Handled-purge bullet WAITS (in-flight 41.2, 30.7 and 32.7 cite AD-27). No stage edits the spine.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**
- AD-1: the route submits through `CommandsIn`.
- AD-4: session ownership; the 404 before the submit.
- AD-12: events and the snapshot through `FromRow`.
- AD-13: the web app.
- AD-14: Got it, `Handled`, `FindByRef`, and the `*Out` copies.
- AD-18: the digest sub-bullet: delivery is Digest's; channels are `digest.channels`.
- AD-27: retention and purge declarations.
- AD-28: no all-clear from rows.
- AD-29 and AD-33: lanes, one publisher, table owners.
- AD-32: the Notification and digest contract; only the `*Out`s render; the page formats times.
- AD-5: new properties are additive; old rows read empty.

**Already met (evidence, not rebuilt):**
- The web digest card path, its text and the reload:
  - `WebChatOut` (17.10), `Ownership` `recentNotices` (:909-911);
  - `Test.Core.WebChatOut` `TestDigestCard`, N16;
  - the online demo's digest facts: Lane A's `Test.Digest.OnlineDemoFacts` (17.11).
- Telegram's digest text and Got it (Lane A, delivered): `Test.Channel.TelegramDigest` `TestDigestMessage`, `TestGotItButton`, `TestHandledEdit` and `TestGotItEdits`.
- The Got it command, first press wins, refusals and the session-end delete: `Test.Core.GotIt`, `Test.Core.GotItProduction` (12.12).
- Handled items leave needs-you: `Test.Digest.NeedsYou` (Lane A).
- The Settings page as the README account: `web/e2e/settings/settings.spec.ts` S1-S14 (33.2, 18.2, 18.3).

**Decided in-stage:**
1. The rows persist on `Delivery.CheckRows`, the sibling of `Turn.CheckRows` and `ChatMessage.Checks`, so they survive a reload (VETO ITEM c).
2. With no rows there is no disclosure. A row whose result is not `passed` opens it, as `check-rows.ts` shows such a result as Not checked.
3. The route is `POST /v1/decisions/:ref/got-it`, since a notice's Ref is its Decision's Ref ("commands as POST on a resource"). Its body rule copies Epic 41's noise route, which is not on this branch, so it cannot be shared yet; unify at the merge (Rule 2, stated reason). `already_handled` is 200, because the notice IS handled.
4. The web line is page-rendered: `handled.marked` from `catalog.ts`, with `pageTimeBeside` in the browser's zone (AD-32: the page formats times). The phone line is `SimPhoneOut`'s render for `phone`, as `EditAnswered` does.
5. `WebChatOut` republishes the card's own payload, with the same ref, so the store replaces the entry in place (`live-store.ts:45` keys notifications by ref).
6. A failed press shows the route's message, else `BUSY_NOTICE` (`incident-dismiss.ts`). No new text.
7. `Record` gets `checkRows` after `Output row`, so existing callers, and `Test.Contract.Ac`'s four-argument prefix, are unchanged.
8. The route line and the handler sit away from Epic 41's hunks.
9. Size: this fits one story. Each part extends a named sibling, about the size of 18.3. If the lead prefers a split, the line is Got it (AC 3, AC 4, N17, N18) apart from the digest parts. That split would need the veto window (moving an AC).

**VETO ITEM (a), retention (DW-695):**
- `Handled.Purge(daysToKeep)` keeps rows for the purge task's `DaysToKeep`: AD-27's task property, 90 by default (the same count the bridge decisions and Epic 30's `Data.Purge` use). This story adds no number.
- A row can outlive its card for up to one run, since `Delivery.RecordedAt` is never after `HandledAt` (inference).

**VETO ITEM (b), who presses Got it:** none. The existing origins (`web_user`, `web_admin`, `telegram`) are unchanged. The route uses `web_user`, as `DismissIncident` does. `SessionOps` keeps the ownership check.

**VETO ITEM (c), stored data shape:**
- New columns:
  - `Data.Delivery.CheckRows` (`%String`, MAXLEN ""), JSON, web digest rows only;
  - `Data.SimMessage.DecisionRef` (`%String`, MAXLEN 22), tell-now phone messages only.
- Not stored: the payload fields `notification.checks`, `notification.handledAt` and `phone.decisionRef`.
- There is no migration; older rows read empty.

**LANE A RESIDUAL (for the lead):**
1. Register `OcuTalon.Data.Handled.Purge(daysToKeep)`: one call in `Install/Step/Core.cls` `Purge`. Epic 41's open branch rewrites that method now (adding `Data.Precedent.Purge`); Epic 30's `Install/Step/Retention.cls` / `Data.Purge` is the other candidate when it merges.
2. Doc only, low: `Channel/DigestText.cls`'s class doc names TelegramOut and WebChatOut as its only callers; SimPhoneOut becomes one.

**Integration ACs and consumers (Rules 1, 2):**
- Consumes:
  - `SessionOps.GotIt` (12.12), `Handled.Marked`, `Delivery.FindByRef` / `Ownership.DeliveryByRef`, `DigestText.Text` (17.10);
  - `Catalog.Render`, `Part.CheckRow.ListFromJSON`, `Bridge.Time.DaysCutoff`;
  - `ServerButton`, `check-rows.ts`, `button.gotIt`, `handled.marked`;
  - `Digest.NeedsYou` (asserted).
  
  AC 4 exercises them on the real production.
- Consumed-by: the route by this story's controls. For `Handled.Purge`: no consumers in this story; the first consumer will be the Lane A registration above, in the story the lead routes LANE A RESIDUAL 1 to.

**Extend, don't copy (Rule 2):**
- `EditHandled` (phone) extends `EditAnswered` and mirrors `TelegramOut.EditHandled`.
- `got-it.ts` copies `incident-dismiss.ts`'s press. This is a copy because Dismiss is incident-specific (Dismissals); the shared part is `ServerButton`.
- `Handled.Purge` calls `DaysCutoff` (DW-371), never `Pairing.Purge`'s copy.
- The card reuses `app-check-rows` and the `--digest-card-*` tokens.

**Ledger (Rule 17):** DW-695 is addressed by AC 7. The registration half is LANE A RESIDUAL 1, so the entry stays open on that residual.

**Footprint extensions (Rule 11 b):**
- `Data/SimMessage.cls`, `Live/Payload/{Notification,Phone}.cls`;
- `Test/{Demo/SimPhoneOut,Live/Payloads,Data/Tables,Data/HandledPurge}.cls`;
- `web/scripts/*.test.mjs` as listed, and `web/src/app/{msg/catalog,live/payloads}.ts` (generated);
- `web/e2e/{chat,demo-path}/**`, `web/e2e-online/demo-path/demo-path.spec.ts`, `docker/tests/test-online-demo-path.sh` (comment).

No open branch changes these (checked 2026-11-08).

**Contended files touched:**
- `Web/Api.cls`: one route line and one handler.
- `Test/Web/Api.cls` `TestRoutes`: the count. Epic 41 changes the count too, so it needs a plain-union merge.
- `Test/Web/BodyLimit.cls` `POSTROUTES`: an append.

**SPINE NOTE (lead, not this stage):**
- The Notice cards convention row (:1140) gains: a digest card's `CheckRows` on its `Delivery` row; the payload's `checks` and `handledAt`; and `SimMessage.DecisionRef`.
- Add a REST row for `POST /api/v1/decisions/:ref/got-it`.
- AD-14's Got it bullet: "Story 18.4 adds" is now as built.
- AD-27: the `Handled` purge, once it is registered.

**UX NOTE (lead):** the NOTE at EXPERIENCE.md :969 ("until Story 18.4 ... the simulated phone shows none") is stale after this story.

**PUBLIC TEXT (RULED 2026-11-08, key planner-2026-11-08-18.4, the Contest Planner under the owner's delegation, relayed by the orchestrator: all six rows APPROVED exactly as listed; pin every one with a fixed string):**

| # | String | Source | File |
|---|---|---|---|
| 1 | What I checked ({n}) | AC 1, verbatim (EXPERIENCE :347) | `chat-view.ts` |
| 2 | Passed / Failed / Not checked (row words) | existing, reused | `decision-view.ts` |
| 3 | Got it | AC 3; catalog `button.gotIt` (reused) | `catalog.ts` (generated) |
| 4 | Marked as handled at {time} | AC 3; catalog `handled.marked` (reused) | `catalog.ts`, `SimPhone/Out.cls` |
| 5 | Saved for the daily digest | AC 5, verbatim (EXPERIENCE :284) | `chat-view.ts` |
| 6 | **Digest**: Saved for the daily digest. | AC 5 (README mirrors the chip, `chk_outcomes`) | `README.md:74` |
| 7 | the phone digest's pieces | the 33.1 catalog keys through `DigestText` (reused) | -- |

No other string is new: failures reuse the route's messages and `BUSY_NOTICE`.

## Verification

Lane D variables (`$LANE_D` below):
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=18 stage=<stage>' OCUTALON_RUN_TAG=e18s4<stage letter>w`

Runtime:
- Compile on slot D (`ocutalon-slot-d`, `OCUTALON`) with `iris_doc_load`, passing an absolute `baseDir`.
- Run tests on one lane-D warm throwaway (CI mock; never a real key or bot).
- Make one `iris_execute_tests` call per message.

**Commands** (one per call, each about 150 s or less):
- `$LANE_D ci/warm.sh up` (once). Expected: the stack is ready.
- One `$LANE_D OCUTALON_WARM=1 ci/iris.sh class <C>` per call (loop), for `C` in:
  - `OcuTalon.Test.Core.WebChatOut`
  - `OcuTalon.Test.Core.GotItChannels`
  - `OcuTalon.Test.Demo.SimPhoneOut`
  - `OcuTalon.Test.Live.Payloads`
  - `OcuTalon.Test.Data.HandledPurge`
  - `OcuTalon.Test.Web.GotItApi`

  Expected: `CLASS ... passed`.
- The same command (once), for `OcuTalon.Test.Data.Tables`, `Test.Web.Api`, `Test.Web.BodyLimit`, `Test.Core.GotIt`, `Test.Core.GotItProduction`, `Test.Digest.NeedsYou`, `Test.Channel.TelegramDigest` and `Test.Contract.Ac`. Expected: passed.
- `node --test web/scripts/<x>.test.mjs`, one file per call: loop for `chat-view` and `phone-view`; once for `catalog`, `payloads`, `api-client-sources`, `ux-strings` and `digest-card-sources`. Expected: pass.
- `npm --prefix web run catalog` and `npm --prefix web run payloads` (once). Then `git diff --stat web/src/app/msg/catalog.ts web/src/app/live/payloads.ts`. Expected: only the new keys and fields.
- `npm --prefix web run lint`, then `npm --prefix web run build` (once each). Expected: exit 0.
- `bash docker/tests/test-readme.sh` and `bash docker/tests/test-boundaries.sh` (once). Expected: pass.
- `$LANE_D ci/warm.sh down` (once).

**Left to CI and the lead's smoke:**
- Playwright N16 to N19 and the changed `chat.spec.ts` and `decision.spec.ts` (chromium, the `live:sign-in` parts: `--part k/n`, `OCUTALON_LIVE_DEADLINE=1200`).
- `demo-path/01-page.spec.ts` (`live:demo-path`) and the online demo-path step 7 (`live:online-demo-path`).
- The full shards, and the fresh-environment check.

`Test.Data.HandledPurge` and `Test.Web.GotItApi` are in Lane B areas: no `ci/units.sh` change.

**Mutations (Rule 19; apply, observe red, revert byte-identical, record here):**
- AC 1: `WebChatOut` drops the rows from `Record`. Then `WebChatOut` `TestDigestCard` turns red. Also `digestOpen` returns false for a failed row: `chat-view.test.mjs` red.
- AC 2: `SimPhoneOut` keeps `digest` out of its message kinds. Then `SimPhoneOut` `TestDigestMessage` turns red.
- AC 3: `EditHandled` (phone) skips the first-answer check: `TestHandledFirstAnswerStays` red. `WebChatOut` stops republishing: `TestHandledRepublishesTheCard` red. `FromRow` drops `handledAt`: `TestReloadShowsHandled` red.
- AC 4: the route submits with channel `web` for a phone body: `GotItApi` `TestPhoneBody` red. The route skips the `Ownership.Decision` check: `TestOtherSessionIs404` red, because a GotIt now reaches SessionOps (the 404 itself still comes back).
- AC 5: `meaningDigest` put back. Then `chat-view.test.mjs` and `test-readme.sh` turn red.
- AC 7: `Purge` compares with `<=`. Then `HandledPurge` turns red at the cutoff edge.
- The Playwright pins are not observed locally (the 150 s rule; the DW-938 pattern).

**Shared surfaces:**
- the `notification` and `phone` payload shapes (`Test.Live.Payloads`, `payloads.ts`, `payloads.test.mjs`);
- the `Delivery` and `SimMessage` schemas (`Test.Data.Tables`);
- `SimPhoneOut`'s message kinds (`SimPhoneOut` :279);
- the record-only `handled` behaviour (`GotItChannels`);
- the URL map and POST list (`TestRoutes`, `POSTROUTES`);
- `LISTED_KEYS` / `catalog.ts`;
- `CHAT_TEXTS.meaningDigest` (the files in the Code Map, README and `chk_outcomes`);
- N16's card look;
- the online demo-path step 7 phone assertion;
- the tell-now cards of every spec, which now carry a Got it button (keep locators exact).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
