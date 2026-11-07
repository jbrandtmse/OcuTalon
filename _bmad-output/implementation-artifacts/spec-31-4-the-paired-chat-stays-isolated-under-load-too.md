---
title: 'Story 31.4: the paired chat stays isolated under load too (Story 29.4''s three paired-chat cases turned on with the demo full, plus DW-237, DW-446, DW-450, DW-474 and DW-511)'
type: 'feature'
created: '2026-11-07'
status: 'done'
baseline_revision: '784f2ac173748232f8f03ea2e2eba25cadd14b88'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 29.4's online run proves that one visitor's incident stays out of another visitor's views, but its three paired-chat cases are still `notBuilt(..., '31.4')` (`web/e2e-online/demo-path/demo-path.spec.ts:408-410`). So nothing yet proves the following on the online demo with the demo full: a judge's paired Telegram chat gets only that judge's incident, notice and approval request; a press from another visitor's paired chat answers nothing; and no Telegram identity or IRIS user name reaches a production message. Until this is proved, the public demo keeps Telegram pairing off. Five ledger entries also wait on this story.

**Approach:** Replace the three placeholders with one serial `describe` in the same unit (`live:online-demo-path`). It uses the CI model mock and the mocked Telegram API only. Six proxied visitors fill the demo to its visitor cap, which is the load shape of Story 29.8's L1: A and B are paired to two mock chats, and A, C and D press Break the feed at the same time. The cases assert three things: the routing to the paired chats; the refusal of B's press, followed by A answering from its own chat; and a message search over every OCUTALON and OCUORDERS header and body of the run. The unit's report check is then made to require ten passed cases. The ledger entries are settled beside the cases: the probe's `error` fallback, the shared global walk, and one assertion line.

## Boundaries & Constraints

**Always:**
- **Mocks only.** Only the CI model mock and the mock Bot API of the throwaway (`ci/compose.ci.yml:21-22`). No real bot token, no real chat and no real model key, anywhere.
- **Telegram setup.** Telegram goes through `web/e2e-online/telegram.ts` (`startTelegram`, then `pairChat`, then `finishTelegram` and `unpairChat` in clean-up). Chats are paired by fixture rows with 11-digit `840177341xx` ids. Never use `populate(..., {pairing})`: its `zz<n>` chat id reaches the Bot API as `chat_id 0`, and the oldest-row rule would route to it.
- **The demo is full.** The describe saves `proxyAddress` and sets it to the host address that the unit passes in (`OCUTALON_ONLINE_HOST_ADDRESS`). It then signs in six visitors one after another, each with its own `X-Forwarded-For` (198.51.100.101 to .106). It puts the proxy address back, and removes those addresses' counter rows, in `afterAll`, whatever failed before.
- **Hermetic.** The describe creates and removes everything it asserts on. Its marks (message header ids per namespace, the mock's press-answer count) are taken by the describe itself. Every test added or changed passes on a fresh environment, in either order (alone with `-g`, or after the rest of the file).
- **The message search** runs before any clean-up removes the run's messages. It uses `OcuTalon.Test.Eval.KeyProof.TraceHits`, once per value and per namespace, from the describe's own header marks. It also has positive controls: A's SessionRef must be found in OCUTALON, and A's TraceRef in OCUORDERS.
- **Lanes.** Lane A classes (`OcuTalon.Test.Channel.TelegramPageFixture`, `LiveCase`, `OcuTalon.Test.Eval.KeyProof`, `OcuTalon.Channel.Telegram.*`) are called and never edited (AD-29, AD-33).
- **Source files.** Files under `docker/tests/` stay ASCII. No tracked file holds a local path, host, address of this machine, or key.

**Never:**
- Edit `release/*.sh`, `release/demo-host-check.sh`, `release/upgrade-harness.sh`, `eval/run.sh` or any release artifact or check script (the release-tool freeze).
- Edit a contended path: `docker/tests/lib-live.sh`, `ci/units.sh`, `docker/tests/test-ci-config.sh`, `.github/workflows/*.yml`, `README.md`, `web/e2e/support/floor.ts`, `web/playwright.config.ts`, `web/e2e/banners/banners.spec.ts`, or the files of Epics 7, 11 and 19 in the contended list.
- Edit an existing mock scenario.
- Connect to, configure or probe the demo host.
- Change product behaviour or any user-facing text. If a case finds a real leak (a value found in a message, or a press that is not refused), stop with a clarification that names it. Do not change the oracle.
- Change AD-13's busy rule, the visitor cap or the address limit.

## I/O & Edge-Case Matrix

All rows except 6 to 9 are in `web/e2e-online/demo-path/demo-path.spec.ts`, in the describe "the paired chat under load". A, B, C, D, E and F are proxied visitors; CHAT_A is `84017734151` and CHAT_B is `84017734153`.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|---|
| 1 | The demo is full (load) | Telegram started; A to F signed in one after another; B paired to CHAT_B first, then A to CHAT_A, each with a unique display name | The plain public status reads busy, with the marker header and 200, once F is in | A sign-in that is refused fails the case and names the visitor |
| 2 | Routing (AC: A's chat only) | A, B, C and D watch Orders through the guide's Send, all at once. Then a call mark is taken (`callMark()`), and A, C and D press Break the feed at the same moment | Within 90 s each of A, C and D shows its own approval card. `buttonsOf(CHAT_A)` equals `[approve:<A's key>, reject:<A's key>]`. Every sendMessage and editMessageText call after the mark goes to CHAT_A (at least one). After C's and D's phones show their notices plus a 5 s settle, no call after the mark goes to CHAT_B | none |
| 3 | B's press (AC: refused, changes nothing) | A new call mark; `pressFromChat(CHAT_B, 'approve:<A's key>', B's name)` | The newest press answer is `{text: "Only the paired chat can answer this request.", show_alert: 1}`. A's row stays `pending`. After a 5 s settle, no sendMessage or editMessageText call follows the mark (CHAT_B gets no message, and CHAT_A no edit). A's card still offers Approve and Reject. There is no `approval` event on A's or B's stream since the press | none |
| 4 | A answers from its own chat (AC: any of A's channels, first answer wins) | `pressFromChat(CHAT_A, 'approve:<A's key>', A's name)` | The press answer starts with "Approved." The row leaves `pending` with channel `telegram`. CHAT_A gets one edit that ends with `Approved from Telegram at H:MM` and an optional zone, then ".". A's card and A's phone show "Approved from Telegram at". A's phone copy offers no Approve any more. The case waits for the row to leave `approved` and `executing` | none |
| 5 | The message search (AC) | Before the presses, A's and B's chats each queued one contact update (chat.first_name = the display name, from `{first_name "Zqfrom", username "zqfromuser"}`, contact.phone_number a unique `+1555` number) | Since the describe's header marks, `TraceHits` gives exactly 0 in OCUTALON and in OCUORDERS for each of: A's and B's display names, `zqfromuser`, CHAT_A, CHAT_B, A's phone digits, and the demo account's IRIS user name. The controls give more than 0: A's SessionRef in OCUTALON and A's TraceRef in OCUORDERS | A result of -1 (unreadable) fails, with its places and stats printed |
| 6 | DW-446 | A probe run whose decision has fallback reason `error` | `degraded count=1 fallback=error`, exit 1, one alert, no reset, the count and the busy file untouched, as for no_key, timeout and rate_limited. A reason outside the five (`unusable`) stays healthy and alerts nothing | none |
| 7 | DW-474, DW-450 | `ReferenceHits(value, dbs)` with a value held only inside a 16-bit `$List` element of a global in OCUTALON_DATA | 1 or more hits. An empty value or a missing database gives -1. ReferenceHits has no walk of its own; it delegates to `KeyProof.GlobalHits` | none |
| 8 | DW-511 | `TestNextReset` | Its assertion reads `now ] ($Translate(...)_"Z")`. `ALLOW_CONCAT` no longer names it, and `test-class-rules.sh` passes | none |
| 9 | DW-237 | The current `Pairing.HashCode` | It keeps its guard and quits `Session.Hash(code)` (already so: `Data/Pairing.cls:69-73`). `TestHashCodeIsSessionHash` is green and pins it | none |

</intent-contract>

## Code Map

- `web/e2e-online/demo-path/demo-path.spec.ts`:
  - The 410-line online run. `notBuilt` placeholders are at :408-410, and their import is at :5 (remove it once unused). The header comment at :53-73 says these cases "wait for Story 31.4" (rewrite that bullet). `eventsSince` :94, `A_ONLY` :117, `askToWatch` :120.
  - The second visitor case (:240-406) is the model: approval card `data-key`, the phone notice via `/state` `phone[].approvalRef`, `readApproval`, the wait at :396-398 for the row to leave approved and executing, and the answered-line regex with its optional zone at :393.
- `web/e2e-online/telegram.ts` (Lane B, Story 31.3):
  - It exports `CHAT_A` :15, `MOCK_MS`, `startTelegram`, `finishTelegram`, `pairChat(sessionRef, chatId, name)` :77, `unpairChat`, `sendFromChat`, `pressFromChat(chatId, data)` :104 (it passes name `""`, so the update has no first_name and no from), `repliesOf`, `buttonsOf`, `pressAnswers`, `chatTurnsOf` and `sendApprovalNotice`.
  - Its `fixture()` wrapper is at :30. Extend this module; do not copy it.
- Lane A, read only:
  - `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: `Start` :76 (resets the mock and deletes `840177341xx` rows), `Finish` :162, `Press(chatId, name, data, .queuedAt)` :399 (newest keyboard's message id, else 1), `Replies` :385, `Buttons` :441, `Edits(chatId, .texts)` :464 and `PressAnswers` :482.
  - `Test/Channel/LiveCase.cls`: `PrivateMessage` :640 and `ButtonPress` :652 show the update shapes (from `{first_name "Zqfrom", username "zqfromuser"}`), and `CallsOf` :465.
  - `Test/Contract/Mock.cls`: `Control(route, body)` :417 (POST `/_mock/telegram/<route>`; `updates` takes a list) and `Calls()` :429 (`[{seq, ts, method, params}]`).
- How a press reaches an answer:
  - `Channel/Telegram/In.cls:18-46` (the contract): a paired chat's message with no text gets no turn and no reply, and the from object is never read.
  - `Core/AnswersIn.cls:55-81` `FromTelegram` (it builds a `Core.Msg.Answer` production message: Ref, Action, Channel, SessionRef). `TelegramCode` :120 turns `not_found` into `not_visible`, which `In.cls` renders as `press.notPairedChat` (`Msg/Catalog/Core.cls:65-69`).
  - The answered line is `answered.approved` (:80-87).
- `Data/Ownership.cls:396-401` `Pairing(sessionRef)` uses the query at :900-902 (`SELECT TOP 1 ... WHERE SessionRef = ? ORDER BY ID`). This is the routing lookup TelegramOut uses (the routing mutation's target).
- `web/e2e-online/support.ts`:
  - `openVisitor(browser, address?)` :246 and `leaveVisitor` :267.
  - `publicValue` :294 and `setPublic` :300.
  - `readStatus(api)` :319, `BUSY_HEADER` :289 and `removeCounterRows` :357.
  - The pattern for saving, setting and restoring the proxy is `web/e2e-online/visitors/visitors.spec.ts:111,160-167,269`; its `BUSY` reading is at :79.
- `web/e2e/support/iris.ts`: `irisScript(script, ms)` :105 (it retries up to 3 times), `chk`, `quoted` :201, `fixtureUser` and `readApproval` :803. `web/e2e/support/api.ts:37` `post`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls` (Lane A, call only):
  - `TraceHits(value, after, .places, .stats, namespace)` :268. It exports each header and body after the mark to XML and searches it in 32,000-character chunks. It gives -1 when anything is unreadable, and it needs no test classes in the namespace it visits.
  - `GlobalHits(value, databases, .places, .stats)` :261. It uses the walk of 30.8 with the `$List` decode (`Holds`, `HoldsSubscript`, `LISTDEPTH = 10`) and no stream decode, which is guarded by `TestNoMessageBodyHoldsAGlobalStream`.
  - Nothing in `release/` calls KeyProof. `eval/run.sh:506` calls only `Scan` and `Print`.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls:624-666` `ReferenceHits` is the Lane B copy of the walk: a plain `[` match over the namespace's globals located in the databases. It has no `%UnitTest` of its own. Its callers are only `docker/tests/test-online-demo.sh` :1776-1778 (row 6 controls), :1805 (row 6 resume reference, expects 0) and :1852-1853 (row 13: raw 1, base64url 0).
- `docker/tests/test-online-demo-path.sh`:
  - The header is at :1-35 (paired-chat wording at :16-19).
  - `run_e2e` is at :86-99; add the host address there.
  - `report_check` is at :104-149 (the wanted list :131, the `bystory` 31.4 counting :136-145, and the total of 10 :147). Its pass and fail lines are at :172 and :175.
  - The load phase computes `host_ip=$(host_address)` at :225. `host_address` and `set_proxy` are in `docker/tests/lib-online.sh:134-139` (not contended).
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls:105` holds the form `now ] $Translate(...)_"Z"`. `docker/tests/test-class-rules.sh:60` is `ALLOW_CONCAT="OcuTalon.Test.Data.PublicSettings:TestNextReset"`, with the stale-entry check at :36 and :225-228.
- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls:69-73` `HashCode` already holds the guard and `Quit ##class(OcuTalon.Data.Session).Hash(code)`, and `Session.cls:143-146` is `Hash`. `Test/Data/PairingRows.cls:72` `TestHashCodeIsSessionHash` reads the method's source.
- CI and time:
  - `live:online-demo-path` is in the group `image` (`ci/units.sh:88`), with storage-roundtrip, build-inputs and `shard:lane-b`.
  - Clean `image` jobs took 29.1 to 29.6 min (runs 42375447084, 42373379335, 42370390895 and 42368408573).
  - The unit took 367 to 396 s: browser step 77 to 79 s, load phase 44 to 45 s.
  - The CI deadline is `OCUTALON_LIVE_DEADLINE: "1200"` (`.github/workflows/ci.yml:115`); the local default is 540 s.

## Tasks & Acceptance

**Execution:**
- [x] Task 0, measure first (`web/e2e-online/demo-path/demo-path.spec.ts`, results into this spec's `## Verification`; fresh stack, lane D): `-g "the paired chat under load"` on a first draft of the describe, with `MEASURED Story 31.4` lines for:
  - the describe's seconds;
  - each `TraceHits` pass's seconds and the number of messages per namespace;
  - whether every sendMessage call went to CHAT_A, and how many went there.

  Record the figures under Verification. If the describe takes more than 240 s locally, cut the drivers to A and C, and record that under Decided in-stage.
- [x] `web/e2e-online/telegram.ts` -- extend, never copy (Rule 2):
  - Export `CHAT_B = '84017734153'`.
  - Give `pressFromChat` and `sendFromChat` an optional `name` (default `""`, so existing callers are unchanged) that goes to the fixture's name.
  - Add `editsOf(chatId)` (fixture `Edits`).
  - Add `callMark()` (the highest `seq` in `Test.Contract.Mock.Calls()`, 0 when there is none) and `sentChats(after)`: the chat_id of every sendMessage and editMessageText call with a `seq` above `after`, read in one IRIS script. A mark, not a reset, so the watches' own traffic before it never counts.
  - Add `shareContactFromChat(chatId, name, phone)`: one contact update, queued through `Test.Contract.Mock.Control("updates", [...])`, with the shape of LiveCase's private message plus `contact {phone_number, first_name, user_id}` and no text.
  - Update the module's header -- these are the shared Telegram helpers of the online units.
- [x] `web/e2e-online/demo-path/demo-path.spec.ts` -- replace :408-410 with `test.describe('the paired chat under load', ...)`, in serial mode with per-test timeouts:
  - `beforeAll`:
    - Require `OCUTALON_ONLINE_HOST_ADDRESS`.
    - Save the proxy and set it to the host address; `startTelegram`.
    - Open A to F one after another with .101 to .106, and assert the plain status is `BUSY`.
    - `pairChat(B, CHAT_B, nameB)` then `pairChat(A, CHAT_A, nameA)`. Names are `Zqpaired` plus 8 random lowercase letters.
    - Take the header marks of OCUTALON and OCUORDERS (`$Order(^|"<ns>"|Ens.MessageHeaderD(""),-1)`).
    - Queue a contact update from each chat.
  - Test titles keep the placeholders' three titles verbatim (rows 2 + 1, row 3 + 4, row 5).
  - The search test is the describe's last test, so it runs before `afterAll` removes the run's messages.
  - `afterAll`, in `finally` order, with each step not stopping the next:
    - reject C's and D's pending requests with their own web answer (`{action:'reject', channel:'web'}`) and wait for them to leave pending;
    - `finishTelegram`, then `unpairChat` for both;
    - `leaveVisitor` for each visitor, then `removeCounterRows` for each address;
    - restore the proxy and read it back.
  - Rewrite the header bullet at :71 to say what these cases do.
- [x] `docker/tests/test-online-demo-path.sh` -- pass the host address to the browser step, and make the report check want ten passed cases:
  - Compute `host_ip=$(host_address)` once before the browser step, and pass `OCUTALON_ONLINE_HOST_ADDRESS="$host_ip"` in `run_e2e`. The load phase keeps its own read.
  - `report_check` wants exactly one passed case for each of `/^step [1-6]:/`, `/^second visitor:/`, `/^the paired chat: A's paired chat/`, `/^the paired chat: a press from B's paired chat/` and `/^the message search:/`. That makes 10 passed cases, 10 in all and no skipped case: any skipped case is a problem.
  - Update the header (:13-19) and the comment, PASS and FAIL texts at :104-107, :172 and :175.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls` -- DW-474 and DW-450:
  - `ReferenceHits` keeps its signature and its -1 rules, and its body becomes `Quit ##class(OcuTalon.Test.Eval.KeyProof).GlobalHits(value, databases)`. Its doc comment says that it scans every global of the named databases with the key proof's walk (the `$List` decode) and that no stream decode is needed (`TestNoMessageBodyHoldsAGlobalStream`).
  - Add `TestReferenceHitsReadsLists`, using one fresh value:
    - a fixture node `^OcuTalonTest("ReferenceHits", <n>)` holds `$ListBuild("zz", $Char(8364)_value)`; `^OcuTalonTest` has no mapping in `docker/merge.cpf`, so it is in OCUTALON's default globals database, OCUTALON_DATA;
    - the node gives 1 or more hits; an empty value gives -1; a database named `ZZNONE` gives -1;
    - the test kills the node.
  - R2: add `MessageHits(value, after, namespace, .places, .stats)`, which calls `KeyProof.TraceHits` and reads the messages it names as unreadable with a second reader (`MessageHolds`: the header as XML, the body as the tree of `%ZEN.Auxiliary.altJSONProvider.%ObjectToAET`); what neither reader can read gives -1 and is named in `stats.unreadable`. The demo-path message search calls it.
  - R2: add the fixtures `Test/Web/NoXmlPart.cls` (a serial object that is not XML-enabled) and `Test/Web/NoXmlBody.cls` (an `Ens.Request` with a list of them), and the tests `TestMessageHitsReadsWhatXmlCannot` and `TestMessageHitsUnreadableByBoth`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls:105` -- DW-511: parenthesise the right side, `now ] ($Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z")`.
- [x] `docker/tests/test-class-rules.sh:60` -- same change: remove the entry (`ALLOW_CONCAT=""`). Check that the stale check and the sample self-test (:530-580) still pass with an empty list; if the empty list breaks them, fix the read so it does not.
- [x] DW-237, verify and pin, no code change: on the current tree, `Pairing.HashCode` is the guard plus `Session.Hash` (`Data/Pairing.cls:69-73`). Run `Test.Data.PairingRows`, and record its mutation.

**Acceptance Criteria:**
- Given the online-demo-path throwaway with the CI mock and the mock Bot API, when `ci/iris.sh live online-demo-path` runs with no arguments, then the report check passes with ten passed cases and none skipped, and the unit ends `all checks passed` (rows 1 to 5 inside).
- Given the describe ran, when the unit's load phase starts, then the status reads not busy, the units are at their start reading, and the proxy address is the start value (the load phase's own checks pass unchanged).
- Given `ReferenceHits` delegates to `KeyProof.GlobalHits`, when `live:online-demo` runs, then its row 6 scans (resume reference 0, controls found) and row 13 (raw 1, base64url 0) pass. If a count changes, or row 6 now finds the resume reference, stop with a clarification that names the node; it is a leak the old scan could not see.
- Given the whole change, when `bash ci/checks.sh` runs, then `boundaries` and `class-rules` pass with every other check, `online-load` included.

- [x] [Lead R1] Restore `docker/probe.sh` and `docker/tests/test-probe.sh` to HEAD exactly (`git diff --quiet HEAD -- docker/probe.sh docker/tests/test-probe.sh`); drop row 6's tasks, its mutation line and its `(loop)` probe command; `bash ci/checks.sh` must then pass with `online-load` green.
- [x] [Lead R2] Restore `src/ocutalon/cls/OcuTalon/Watch/Msg/Failure.cls` to HEAD exactly; add the Lane B no-XML fallback for unexportable bodies to the message search (row 5), with its own pinning (a body class without `%XML.Adaptor` that holds a searched value is found by the fallback; a body unreadable by both paths fails the case) and a mutation line; reload the changed Lane B classes into the slot or throwaway you test on.
- [x] [Lead R3] Measure the routing case's `/state` stalls (at least 5 more lone runs, with what else ran on the machine) and act per ruling R3; record the measurements under Verification.

## Spec Change Log

- 2026-11-07 (lead, after implement pass 1 halted `intent gap`): rulings R1 (DW-446 declined, release-tool freeze; probe files restored), R2 (AD-33 comply: Failure.cls restored, Lane B no-XML fallback in the message search) and R3 (measure the routing stalls) added under Design Notes and as `[Lead R1-R3]` tasks; status reset to `in-progress` for re-implement. The pass-1 diff stays in the tree as the starting point.

## Review Triage Log

### 2026-11-07 - Review pass
- verdicts: 34 findings - high 0, medium 4, low 15, false 15, maybe-false 0
- findings:
  - `[low]` `[patch]` blind: MessageHits undercounts above the places limit on the fallback path - doc comment now says exact as zero or not zero (also edge, verification-gap "other")
  - `[low]` `[reject]` blind: StreamHolds repeats KeyProof's chunk loop - KeyProof.Trace is Lane A (AD-33) and cannot be edited or extended; the copy is forced by R2
  - `[low]` `[reject]` blind: host_ip may be empty - the describe's beforeAll names OCUTALON_ONLINE_HOST_ADDRESS when it is empty; no new failure mode
  - `[false]` `[reject]` blind: no positive control for Telegram values - TestMessageHitsReadsWhatXmlCannot finds an arbitrary value in a header and a body, and the chat-id mutation turned the case red
  - `[low]` `[reject]` blind: contact update not confirmed consumed - updates are handled in order, and B's and A's presses (answered, asserted) came after both contacts
  - `[low]` `[reject]` blind: fixed 5 s settles - the settle is the spec's row 2 and 3 wording
  - `[low]` `[patch]` blind: leftover code - `state.answered` removed, the second readStatus merged into drive(), the `?? 'a'` fallback now throws; the hard-coded 10 stays (it equals the report's case count)
  - `[low]` `[patch]` blind: stale ALLOW_CONCAT comment in test-class-rules.sh - comment rewritten
  - `[low]` `[reject]` blind: six visitors hard-coded - the cap is an owner-fixed value (P12) and the busy assertion names the dependency
  - `[false]` `[reject]` blind: ReferenceHits behaviour change - the callers pass three mounted OCUTALON databases; the old scan also returned 0 for an unmounted one; rows 6 and 13 of live:online-demo passed
  - `[low]` `[reject]` blind: NoXml fixtures unasserted - the test asserts TraceHits gives -1 on the body, so the XML failure is pinned; a stream body is not reachable by a Lane B message
  - `[low]` `[patch]` edge: proxySet set after setPublic - set before it, so a throwing read-back still restores
  - `[medium]` `[patch]` edge: E and F could lapse before the presses - the busy status is read again just before the presses
  - `[false]` `[reject]` edge: Mock.Calls empty when the mock is down - the routing case requires calls to CHAT_A and the press answers before the empty-list assertions
  - `[false]` `[reject]` edge: second reader's tree misses private or stream properties - the only body that needs it (FailureBatch, Failure) holds scalar properties; a stream gives -1
  - `[false]` `[reject]` edge: count capped at 20 - same as the first row
  - `[false]` `[reject]` edge: 16 searches of 240 s in 900 s - measured 0.07 to 0.15 s each; the timeouts are ceilings
  - `[low]` `[patch]` edge: B's phone digits not searched - added to the values (Zqfrom stays out, Decided in-stage 4)
  - `[medium]` `[patch]` edge: marks taken after the pairing - taken before it, so the pairing's own messages are searched
  - `[false]` `[reject]` edge: default 540 s deadline too short - the describe takes about 45 s and the unit 196 s; Rule 21 passes 900 locally, CI uses 1200
  - `[false]` `[reject]` edge: empty databases scans all - no caller passes "" and the default is non-empty
  - `[false]` `[reject]` edge: skipped databases read as clean - the old scan also read an unmounted database as 0
  - `[false]` `[reject]` edge: empty host_ip - same as the blind row
  - `[medium]` `[patch]` verification-gap: cases 2 and 3 depend on case 1 and run order - one memoized drive() that every case awaits; the two cases passed alone (-g) on fresh throwaways
  - `[false]` `[reject]` verification-gap: nothing shows the Telegram values reach the system - see the blind row
  - `[low]` `[patch]` verification-gap: report check has no mutation line - mutation run and line written (AC 1)
  - `[false]` `[reject]` verification-gap: AC 2, 3 and 4 have no mutation line - they are regressions pinned by existing checks (the load phase, live:online-demo rows 6 and 13, ci/checks.sh), all green; the changed tests carry lines
  - `[low]` `[reject]` verification-gap: the phone-read throughStalls site is not injected - a flake guard around the same helper that was injected
  - `[false]` `[reject]` verification-gap other: no positive control for eventsSince - the same pattern as the second visitor case
  - `[false]` `[reject]` verification-gap other: ^OcuTalonTest assumed unmapped - the test passed on the slot, the warm and the lane-b stacks
  - `[false]` `[reject]` verification-gap other: exact hits=2 over a live production - hits count only messages holding the unique value
  - `[low]` `[patch]` intent: DW-446 absent from the diff - ruled R1 (declined); the contract text is stale by that ruling
  - `[low]` `[patch]` intent: routing checked by destination - A's newest keyboard is re-read after the settle, so a notice of C or D in A's chat fails the case
  - `[medium]` `[patch]` intent: cases are order-dependent - see the verification-gap row

## Design Notes

**Architecture decisions that govern this story (Rule 6):**
- AD-4: session ownership. "Production messages carry `SessionRef`, never a user name, Telegram chat id or display name" (row 5). One live pairing per chat, and the identity lives only in `Pairing`.
- AD-11: `AnswersIn` refuses a request that another session cannot see (`not_visible`), and the first answer wins (rows 3 and 4).
- AD-13: the visitor cap and busy rule, here only read as the load condition (row 1).
- AD-14: outbound routing through `Notify` (row 2).
- AD-22: throwaways, CI groups and mocks; no scenario is edited or added.
- AD-25: no host action.
- AD-29 and AD-33: the lanes. Lane B files are edited; Lane A test classes are only called.
- AD-32: the notice with Approve and Reject, and the answered line (row 4).

No AC contradicts an AD's Rule.

**Decided in-stage (plan):**
1. **"Under load" means the demo is full, with concurrent drivers, in L1's shape.** Story 29.4's isolation case runs with two visitors who both watch, and 29.8's L1 is this unit's load (6 visitors, 5 drive). The visitor count counts proxied sessions only (`SessionEvents.cls:95-121`), so the describe sets the proxy to the host address, as `visitors.spec.ts` does, and opens six proxied visitors; the busy status is the observable that the demo is full. A, C and D press at once (three concurrent incidents), B watches without pressing, and E and F only sign in. Five drivers would cost about twice the messages to search, and three keep the concurrency. The proxy is set by the spec and not by the shell, so the earlier cases keep their unproxied sign-ins. This follows `test-online-demo.sh`'s proxied phase, inside one Playwright run.
2. **One message is the incident, its notice and its approval request.** The first incident notice is kind `incident` with `ApprovalRef` and the buttons `approve:<Ref>` / `reject:<Ref>` (`Watch/IncidentManager.cls:1013-1035`, `Channel/Telegram/Out.cls:35-41`). Row 2 asserts the buttons and that no call goes to another chat; it does not pin the count of messages to CHAT_A. Task 0 records the count.
3. **"Any of A's channels"** is A's own paired chat here. Story 29.4 already answers on the phone. "First answer wins" is observed on A's card, A's phone and the Telegram edit.
4. **The identity values come in through the mock.** The display names come from the pairing rows and each update's `chat.first_name`. The user name is `zqfromuser`, from the `from` object of the fixture's own builders. The phone number comes from a contact update (a paired chat's message with no text gets no turn and no reply, `In.cls:36`). The chat ids come from every update. The search covers both chats, which keeps it to 7 values times 2 namespaces. `Zqfrom` (the from object's first name) is left out, as a short common token. The later presses of the same chat prove that each contact update was handled, because updates are handled in order.
5. **The search is `KeyProof.TraceHits`, with no new walk (Rule 2).** `LiveCase.Bodies` and `RowsText` cover OCUTALON only and are Lane A. A global scan would hit the `Session` and `Pairing` rows, which hold these values by design. ChatRef is not a control: in this run only a pairing-kind `Notification` carries it (`Msg/Notification.cls:9`, `Rule/Notify.cls:31`), and none is sent.
6. **CHAT_B is `84017734153`.** Story 31.3's `test-online-session.sh` uses 152 on its own stack. Every `840177341xx` row is cleaned by `Start` and `Finish`.
7. **DW-474's "Story 30.1's $List decode" is Story 30.8's.** 30.1 measured and 30.8 built (spec-30-8:268-273, :424). No stream decode is needed (branch N). The epics bullet is not amended: its intent is unchanged.
9. **The local deadline.** A full local run passes `OCUTALON_LIVE_DEADLINE=900`, as Rule 21 records for `live:sign-in`. The default stays 540 s (`lib-live.sh` is contended), and the script's header already says to raise it on a slow machine.

**Decided in-stage (implement):**
10. **The message search has a second reader (R2).** `KeyProof.TraceHits` exports each body as XML and gives -1 for a body it cannot export: the body of a `Watch.Msg.FailureBatch` that holds failures fails with `ERROR #6249` because `Watch.Msg.Failure` is not XML-enabled (three batches in a run). `SessionEvents.MessageHits` (Lane B) calls `TraceHits` and reads the messages it names as unreadable a second way: the header as XML and the body as the property tree of `%ZEN.Auxiliary.altJSONProvider.%ObjectToAET`. A message that neither reader can read, a body that is a stream, and a namespace that cannot be visited still give -1, so nothing is skipped silently. This is a second reader of bodies, forced by AD-33 (`KeyProof` and `Failure` are Lane A's, so neither is edited); the missing `%XML.Adaptor` on `Watch.Msg.Failure` is a request to Lane A. Its fixture is `Test.Web.NoXmlBody`, a message body with a serial property that is not XML-enabled (`Test.Web.NoXmlPart`), so the pin does not depend on Lane A's class. In the run it covers 3 of 166 OCUTALON messages and none of OCUORDERS' 250.
11. **E and F only fill the demo.** Their pages are closed after the sign-in (their sessions stay counted, which the busy status shows), so that only the four visitors that watch and press hold a live socket. Task 0 did not need the cut to A and C: the describe takes 37.7 s with its hooks, far under 240 s.
12. **`ReferenceHits` now scans every global of the named databases**, as `KeyProof.GlobalHits` does, and no longer only the globals that the OCUTALON namespace maps there. Rows 6 and 13 of `live:online-demo` are a (once) line left to the lead; a changed count there is the clarification of the third AC.

13. **The routing case reads through a stalled HTTP read (R3).** The watch step (`doneTurn`) and the phone reads of C and D run inside `throughStalls`: a read that ends in `apiRequestContext.<verb>: Timeout <n>ms exceeded` starts that wait again, for up to 90 s, and each stall is printed as a `MEASURED Story 31.4` line. A wait that ran out of its own budget, any other error and a stall past the budget fail the case. The stall was not isolated and no product mechanism was found (see the measurements), so this takes R3's machine branch without proof; if the printed lines show up on the CI runner, they are a product finding for the lead.
14. **The three cases share one drive.** The watch, the three presses, the cards and A's notice run in one memoized `drive()` of the describe; the first case that needs the incidents runs it and the others reuse it, so each case passes alone (`-g`) and after the rest. The header marks are taken before the pairing, and the routing case re-reads A's newest keyboard after its settle.

**Lead rulings on the implement stage's intent gaps (2026-11-07, runner D, unattended; `ruling ... category=decide`):**
- **R1 (gap 1, DW-446 vs the release-tool freeze):** the dispatch's freeze rule applies: a ledger entry that needs a frozen release tool is re-routed, and the file is not edited. `docker/tests/test-online-load.sh` S16 pins `docker/probe.sh`'s degraded reasons to `release/demo-load.sh`'s `DEGRADED_REASONS`, so the probe half of DW-446 cannot land without the frozen edit, and weakening S16 is not allowed. So: `docker/probe.sh` and `docker/tests/test-probe.sh` go back to HEAD exactly (no change in this story), and DW-446 is declined here.
  - Declined DW-446: release-tool freeze (its probe change must land together with `release/demo-load.sh`'s `DEGRADED_REASONS` and comments :50/:88, which `test-online-load.sh` S16 pins); re-routed by the lead to the burn-down until after the v1.0.4 merge-back.
- **R2 (gap 2, `Watch/Msg/Failure.cls`, AD-33 "only the owning lane edits a class"):** comply first (doctrine U7 step 1). `Watch/Msg/Failure.cls` is Lane A's and goes back to HEAD exactly; no Lane A file is edited. The message search keeps its full scope (every OCUTALON and OCUORDERS header and body since the describe's marks) with a Lane B fallback for the bodies `KeyProof.TraceHits` cannot export as XML: such a body is opened and read without XML (for example `##class(%ZEN.Auxiliary.altJSONProvider).%ObjectToAET(body)` then `%ToJSON()`, or the body's storage node decoded with KeyProof's own matcher), and searched for the same values. Build it as a small classmethod in a Lane B test class (for example `OcuTalon.Test.Web.SessionEvents`), calling Lane A classes only to read. The case must still fail when a body is unreadable by both paths (no silent skip). Rule 2: the fallback is a second reader of bodies, forced by AD-33 (KeyProof and Failure are Lane A's); record that reason here when built. The missing `%XML.Adaptor` on `Watch.Msg.Failure` is filed by the lead as a ledger request for Lane A (AD-33: "the other lane ... asks for any property it needs").
- **R3 (the routing case's 3-in-10 `/state` timeouts):** a test that is red 30 % of the time is not done. Measure before finalizing: run the routing case alone at least 5 more times and record each result and, for any stall, what else was running on this machine (other lanes' throwaway stacks, `docker stats`). If the stall is the machine's (other load), a test-side wait for C's and D's `/state` reads that stays inside the case's existing 90 s budget is acceptable (record it as Decided in-stage). If it is the product's (IRIS itself serializes or stalls with the demo full, with nothing else loading the machine), HALT `intent gap` with the measurement: that would be a real product finding under AD-13's full house, never something to wait out.

**Ledger inbox (Rule 17):**
- DW-237: addressed as "verify + pin" (row 9 and its task). It was already delegating on this tree (`Data/Pairing.cls:69-73`; the 11.0 fix).
- Declined DW-446: release-tool freeze (R1); the probe files are unchanged.
- DW-450: addressed (row 7). With `ReferenceHits` delegating, the key proof's walk is the only walk, so KeyProof's copy has no sibling left. Lane A's file is untouched.
- DW-474: addressed (row 7): the `$List` decode reaches the Lane B scan through `GlobalHits`.
- DW-511: addressed (row 8, two tasks).
- Declined DW-485: release-tool freeze (release/demo-host-check.sh); re-routed to the burn-down until after the v1.0.4 merge-back. Its secondary note is declined with it. The stand-in's guard is a deny-list that already admits `WARGC`, `WEVENT` and `WARG_<n>` (`docker/tests/test-online-host.sh:238-256`), and its fake IRIS answers 404 for the broker path (:296-297). A route there would only serve the frozen check that is not written yet. Recording the allowance beside AD-25 is a spine amendment, which is not this stage's to make.

**Integration ACs (Rule 1).** No service is introduced.
- The shared test helpers have consumers in this story:
  - `telegram.ts`'s new helpers are used by rows 2 to 5.
  - `ReferenceHits` is used by `live:online-demo` rows 6 and 13 (the third AC).
- **Consumes:**
  - Epic 12's Telegram channel and `TelegramPageFixture`.
  - Story 31.3's `telegram.ts`.
  - Stories 29.4 and 29.7's `openVisitor`, `readStatus`, `publicValue` and `setPublic`.
  - Story 9.10 and 30.8's `KeyProof.TraceHits` and `GlobalHits`.
  - The mock's `guide-watch` and `diagnosis` scenarios.
  - Story 31.5's tool-call notices (none is expected in this run).
- **Consumed-by:** no later story. The Contest Planner's host switch (setting the bot token, U-219) waits on this story landing.

**Extend, don't copy (Rule 2):**
- `telegram.ts` gains its helpers in place, as optional parameters and new exports.
- The contact-update builder is new: LiveCase builds no contact update, and LiveCase is Lane A's.
- The proxy save, set and restore is three inline calls of `support.ts`'s `publicValue` and `setPublic`, as in `visitors.spec.ts`.
- `ReferenceHits` stops being a copy (DW-450 and DW-474).

**ci/units.sh:** no change. The unit stays in `image`. Expected (inference until CI measures it): the describe adds 1.5 to 3 min to the unit on CI, so `image` goes from about 29.5 to about 31 to 32.5 min, under 35. The unit stays far under 1,000 s (about 500 to 580 s).

**footprint_extensions:** none. `web/e2e-online/**`, `docker/tests/test-online-demo-path.sh`, `docker/tests/test-class-rules.sh`, `Test/Web/SessionEvents.cls`, the fixture classes `Test/Web/NoXmlPart.cls` and `Test/Web/NoXmlBody.cls`, and `Test/Data/PublicSettings.cls` are this story's or its ledger entries' files. None is contended.

### Public text
none

## Verification

The lane values are `OCUTALON_LOCK_DIR=<lock-dir>/lane-d`, `OCUTALON_TEST_WEB_PORT=52804` and `OCUTALON_LOCK_OWNER='epic=31 stage=implement'`; written `<lane D>` below. Every call passes `timeout: 600000`. Warm tag `e31s4iw` (`<lane D> OCUTALON_RUN_TAG=e31s4iw ci/warm.sh up` once, `ci/warm.sh down` at the end, also after a failure). Fresh tag `e31s4i`, with `ci/iris.sh teardown` on it at the end. If the web bundle is older than a merge, run `<lane D> OCUTALON_RUN_TAG=e31s4i ci/iris.sh build` once first.

**Commands:**
- (loop) `<lane D> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s4iw ci/iris.sh class OcuTalon.Test.Web.SessionEvents` -- expected: `CLASS ... passed`, with `TestReferenceHitsReadsLists` green.
- (loop) `<lane D> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s4iw ci/iris.sh class OcuTalon.Test.Data.PublicSettings` -- expected: passed.
- (loop) `<lane D> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s4iw ci/iris.sh class OcuTalon.Test.Data.PairingRows` -- expected: passed (DW-237).
- (loop) `bash docker/tests/test-class-rules.sh` -- expected: every line PASS, exit 0.
- (loop) `npm --prefix web run lint` -- expected: exit 0 (the e2e typecheck included).
- (loop) `<lane D> OCUTALON_RUN_TAG=e31s4i OCUTALON_LIVE_DEADLINE=900 ci/iris.sh live online-demo-path -g "the paired chat under load"` -- expected: the three cases pass, the load phase passes, exit 0 (about 5 to 8 min).
- (once) `<lane D> OCUTALON_RUN_TAG=e31s4i OCUTALON_LIVE_DEADLINE=900 ci/iris.sh live online-demo-path` -- expected: the report check holds ten passed cases, `all checks passed`.
- (once) `<lane D> OCUTALON_RUN_TAG=e31s4i OCUTALON_LIVE_DEADLINE=900 ci/iris.sh live online-demo` -- expected: rows 6 and 13 pass with ReferenceHits delegating.
- (once) `<lane D> OCUTALON_RUN_TAG=e31s4i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2` -- expected: every class passed.
- (once) `bash ci/checks.sh` -- expected: every block passes.

**Mutations (Rule 19).** Each is applied, observed red, then reverted to a byte-identical tree. The implement stage records the red it observed:
- Row 2: in `Data/Ownership.cls:901`, `WHERE SessionRef = ?` becomes `WHERE SessionRef <> ?`. A's notice then goes to CHAT_B, and "the paired chat: A's paired chat..." goes red.
- Rows 3 and 4: in `Core/AnswersIn.cls` `FromTelegram`, the answer is made for the request's owner instead of `chat.SessionRef`. B's press then approves A's request, and "...a press from B's paired chat..." goes red.
- Row 5: `Core.Msg.Answer` gains a property `ChatId`, which `FromTelegram` sets from the chat row. The Answer message then holds the chat id, and "the message search: ..." goes red while the first two cases stay green.
- Row 5, the second reader: `MessageHolds` searches the body for another value (found = 1 becomes 0), and `TestMessageHitsReadsWhatXmlCannot` goes red. A failure of the second reader is dropped instead of named, and `TestMessageHitsUnreadableByBoth` goes red.
- Routing wait (R3): a read stall is injected into the watch step, once with `throughStalls` as written (the case stays green, the stall printed) and once with it rethrowing (the case goes red).
- Row 7: `ReferenceHits`'s old body is put back, and `TestReferenceHitsReadsLists` goes red.
- Row 8: the unparenthesised form is put back, and `test-class-rules.sh` goes red.
- Row 9: `HashCode` repeats the SHA-256 line, and `TestHashCodeIsSessionHash` goes red.

**Implement-stage results** (lane D, ARM developer machine, fresh throwaway `e31s4i`, warm `e31s4iw`):
- MEASURED Story 31.4: the describe (`-g "the paired chat under load"`, hooks included) took 42.8 s in Playwright; its three cases took 20.2 s, 6.7 s and 1.3 s; the unit took 197 s. Each `MessageHits` pass took 0.07 to 0.10 s over 166 messages in OCUTALON (3 read by the second reader) and 250 in OCUORDERS (none); 1 sendMessage or editMessageText call went out after the call mark of the routing case, to CHAT_A.
- The positive controls hold: A's SessionRef is found in OCUTALON and A's TraceRef in OCUORDERS.
- MEASURED Story 31.4 (R3): the routing case alone (`-g "A's paired chat gets the incident"`, a fresh throwaway each time), 13 runs: 12 green (19.5 to 20.6 s) and 1 red (run 1: a `/state` read of visitor D timed out at 30 s at the start of the watch step, 31.4 s). Pass 1 saw 3 reds in 10. Run 1 ran at a load average of 3.2 with three other stacks up, and a lane-a shard stack started 56 s after this one started; the stacks' CPU after it was under 7 %. The 12 green runs ran at load averages from 3.3 to 11.5 with 2 to 4 other stacks (shard, eval, class and warm stacks of other lanes, an IPM check and an upgrade-set stack in runs 7 and 8). Runs 7 to 13 polled the plain public status every second from outside: no read of it was slow while the case ran. The red run was not sampled and nothing in a green run reproduced the stall, so the cause is not isolated: no product mechanism was found, and it is not shown to be the host's either.
- (loop) `test-class-rules.sh`, `test-boundaries.sh`, `npm --prefix web run lint`: green. Warm classes `Test.Web.SessionEvents` (with `TestReferenceHitsReadsLists`, `TestMessageHitsReadsWhatXmlCannot` and `TestMessageHitsUnreadableByBoth`), `Test.Data.PublicSettings` and `Test.Data.PairingRows`: passed. `git diff --quiet HEAD` holds for `docker/probe.sh`, `docker/tests/test-probe.sh` and `Watch/Msg/Failure.cls`.

Mutations observed (Rule 19), each reverted to a byte-identical tree:
- mutation: Row 2: `Ownership.cls` `WHERE SessionRef = ?` -> `<>` in the pairing query -> "the paired chat: A's paired chat gets the incident..." red (`buttonsOf(CHAT_A)` never showed A's buttons), the other two cases did not run.
- mutation: Rows 3 and 4: `AnswersIn.FromTelegram` answers as the request's owner (`ApprovalRequest.OwnerRef`) instead of `chat.SessionRef` -> "...a press from B's paired chat..." red (no "Only the paired chat can answer this request." alert); the routing case stayed green.
- mutation: Row 5: `Core.Msg.Answer` gained `ChatId`, set in `FromTelegram` from the chat row -> "the message search: ..." red ("no value is found in any header or body"), the first two cases green (observed again with the search going through `MessageHits`).
- mutation: Row 5, the second reader: `MessageHolds` searches the body for `value_"x"` -> `TestMessageHitsReadsWhatXmlCannot` red ("the body that XML cannot export and the header that holds the value are both found").
- mutation: Row 5, no silent skip: the Catch of `MessageHits` pushes the message to `stats.fallback` instead of `stats.unreadable` -> `TestMessageHitsUnreadableByBoth` red (3 assertions: -1, the header named, the only one).
- mutation: R3 wait: a stall error (`apiRequestContext.get: Timeout 30000ms exceeded.`) thrown once for D inside the watch step's `throughStalls` -> the case green with the stall printed; the same injection with `throughStalls` rethrowing every error -> the case red (1.3 s).
- mutation: AC 1, the report check: the title of the search case retitled ("the message lookup: ...") and the full unit run with no arguments -> `test-online-demo-path.sh` red ("wanted exactly one passed case matching /^the message search:/, found 0" and "FAIL the report does not hold exactly the ten passed cases and no skipped one"); green again with the title back.
- mutation: Row 7: `ReferenceHits`'s old body put back -> `TestReferenceHitsReadsLists` red ("a value held only inside a 16-bit $List element is found"); green again on the same warm stack after the revert.
- mutation: Row 8: the unparenthesised `now ] $Translate(...)_"Z"` put back in `Test/Data/PublicSettings.cls` -> `test-class-rules.sh` red (assert-concat names line 105).
- mutation: Row 9: `HashCode` repeats the SHA-256 line -> `TestHashCodeIsSessionHash` red ("with no hashing of its own"); green again on the same warm stack after the revert.

**Shared surfaces:**
- The report check of `docker/tests/test-online-demo-path.sh` (lines ~17, 106-172): it changes from "seven passed cases and the three skipped ones of Story 31.4" to ten passed cases and none skipped.
- The headers of `demo-path.spec.ts` and the script.
- `telegram.ts`'s exports: additive; the optional name keeps the callers in `leave.spec.ts`, `messages.spec.ts` and `daily-cap.spec.ts` unchanged.
- `ReferenceHits`'s counts, which `test-online-demo.sh` rows 6 and 13 assert.
- `test-class-rules.sh` `ALLOW_CONCAT`, which becomes empty.
- The public `proxyAddress` and the AddressCounter rows of .101 to .106: restored and removed by the describe.
- The mock's call log, which `startTelegram` and `finishTelegram` reset.
- Every test added or changed passes on a fresh environment, in either order: the three cases of the describe each passed alone (`-g`) on a fresh throwaway.

## Auto Run Result

Status: done
Blocking condition: none

Summary: the paired-chat describe ("the paired chat under load": six proxied visitors fill the demo, A and B are paired to two mock chats, A, C and D press Break the feed together) replaces the three placeholders; the report check wants ten passed cases and none skipped. R1: the probe files are unchanged at HEAD and DW-446 is declined. R2: `Failure.cls` is unchanged at HEAD and the message search uses `SessionEvents.MessageHits` (the key proof's `TraceHits` plus a second reader for bodies it cannot export as XML). R3: the routing case reads through stalled HTTP reads (Decided in-stage 13), 1 red in 13 lone runs. `ReferenceHits` delegates to `KeyProof.GlobalHits` (DW-474, DW-450); DW-511 and DW-237 are settled.

Files changed:
- `web/e2e-online/demo-path/demo-path.spec.ts`: the describe, its helpers (`drive`, `throughStalls`, `traceHits`, `headerMark`).
- `web/e2e-online/telegram.ts`: `CHAT_B`, the optional name, `editsOf`, `callMark`, `sentChats`, `shareContactFromChat`.
- `docker/tests/test-online-demo-path.sh`: the host address for the browser step; the report check wants ten passed cases and none skipped.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls`: `ReferenceHits` delegates; `MessageHits`, `MessageHolds`, `StreamHolds`; three tests.
- `src/ocutalon/cls/OcuTalon/Test/Web/NoXmlBody.cls`, `NoXmlPart.cls`: fixtures of the second reader.
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls`, `docker/tests/test-class-rules.sh`: DW-511.

Review (first pass, four layers, 34 findings): patch rows 12 (4 medium, 8 low; 3 medium entries after grouping), deferred 0, rejected 22 (see the Review Triage Log for each reason). Follow-up review recommended: true, for the reshaped routing case (`drive()` and the re-read of A's newest keyboard), which ran green in the full unit, in the describe run and alone; the CI runner's stall rate is unmeasured.

Verification: `(once)` `live online-demo-path` (10 passed, report check passes, all checks passed), `live online-demo` (52 passed, rows 6 and 13 pass), `shard lane-b` parts 1/2 and 2/2 (54 classes each, passed), `bash ci/checks.sh` (all scripts passed, `online-load`, `boundaries`, `class-rules` and `probe` included), `-g "the paired chat under load"`, `-g "a press from B's paired chat"` and `-g "the message search"` each green on a fresh throwaway, `npm --prefix web run lint` green. No `e31s4` container is left.

Residual risks: the routing case's `/state` stall is not isolated (Decided in-stage 13; the printed MEASURED lines on the CI runner would be a product finding); the missing `%XML.Adaptor` on `Watch.Msg.Failure` is a request to Lane A (the lead files it); DW-446 and DW-485 are declined to the burn-down.
