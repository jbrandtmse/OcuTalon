---
title: 'The mailbox address and user name stay out of the trace'
type: 'bugfix'
created: '2026-11-13'
status: 'done'
baseline_revision: 'b3fdf16c5c8d8352d496400b03c421d92d135fd6'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
warnings: ['oversized', 'retrofit_added_ruling_L']
deferred:
  - summary: >-
      Test.Watch.SettingSecret (Story 36.1) scans the trace by Ens.MessageHeader.Description only and has no TraceLeaks assertion.
    evidence: |-
      Ruling L lists the retrofit sites by story (21.2, 21.3, 21.8, 35.3, 22.3, 22.4); 36.1 is not listed, and a secret in a stored message body would pass that scan.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Watch/SettingSecret.cls:254
    severity: low
---

<intent-contract>

## Intent

**Problem:** Saving Settings > Channels > Email puts the mailbox `address` and `user` as plain text in `SaveSettings.Changes`, a traced production message (`^Ens.MessageBodyD`), so anyone with the trace role can read them (DW-1255).

**Approach:** Extend the password/clientSecret handoff swap of `Web/Api.cls` `SaveChannels` to `address` and `user`; `SettingsOps.SaveEmail` takes both from `SecretHandoff` before it validates them. Storage stays as it is. `docs/security-overview.md` gets one sentence on what the trace role sees.

## Boundaries & Constraints

**Always:**
- `SaveSettings.Changes` for slug `channels` holds `address` and `user` only as `secret://handoff/<32 hex>` references. `incoming`, `outgoing`, `signIn`, `clientId` and `origin` stay plain, and `password` and `clientSecret` stay as they are.
- The route checks `address` and `user` the way it checks the secrets: present but not a JSON string, or longer than `PASSWORDMAX` (256), gives 400 `bad_settings` naming the field, with nothing offered and nothing submitted. Any other non-empty string is offered. Every untaken reference is taken back after the submit, whatever the submit answered.
- `SettingsOps` takes the two values with the same `SecretHandoff.Take` call the password uses, before `EmailShape`, which then validates them unchanged. A string that is not a reference, or a reference that names nothing, is refused naming that field. The online demo still refuses first, taking nothing.
- The values are held in local variables only. Settings audit entries keep the `set`/`changed` form, with no value. Every existing answer, text and field name stays the same.
- Storage is unchanged: `email.address` stays a product key in `Data.Setting` (`^OcuTalonP.SettingD`, the private database, on which the trace role has nothing). The user name stays in the credential `OcuTalonMail`. GET `/v1/settings` and the page still show both to the admin.

**Never:** no change to storage, properties, classes, routes, catalog or UI text. Do not move `email.address` out of `Data.Setting`, and do not change readers of the stored key (`CommandsIn`, `Rule.Functions`, `EmailOut`, 21.7's digest). No new handoff class, and no handoff for an asynchronous command (ruling item 4). `Msg.Item.Sender` and `SendEmail.Recipients` are not changed (ruling items 4 and 5). No real mail, and no slot or other instance.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Route save | admin POST with unique address A and user U | the message's `address`/`user` are references; A and U are in no message body, header, log row or audit entry; the credential user is U and `email.address` is A | none |
| Odd value | `address` or `user` is a number, object or 257 characters | 400 naming it; nothing offered or submitted; no message holds it | as for `password` |
| Plain value at the owner | `SaveSettings` with a plain address or user | `refused` naming it; nothing written | none |
| Lost reference | a reference that names nothing | `refused` naming that field; nothing written | none |
| Refused after the take | a valid A/U with `incoming` `x@{y` | 400 naming `incoming`; references taken; the message holds neither value | none |
| Online demo | `onlineDemo` 1 | 409 `not_available` before the body is read; nothing offered | unchanged |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- `SaveChannels` (about l.951): the type/length loop `For name = "password", "clientSecret"` (l.954) and the offer loop (l.963) that puts the reference in the body; untaken references are taken back at l.985. `PASSWORDMAX` (l.199). Class doc l.45-52 and method doc l.940-947 describe the contract.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `SaveEmail` (l.1468): the online demo first, then `EmailShape`, then the password and clientSecret `Take` (l.1480, l.1491); the todo list writes `email.address` (l.1513) and the credential user name (l.1517, `WriteCredential` l.1559/1563). `EmailShape` (l.1775) validates `address` (`IsAddress`) and `user` (1 to 256 characters). `AddField` (l.1381) adds each name once. The class doc is at l.64-68.
- `src/ocutalon/cls/OcuTalon/Core/SecretHandoff.cls` -- `Put`/`Take`, the reference form `^secret://handoff/[0-9A-F]{32}$`; its class doc says "a secret".
- `src/ocutalon/cls/OcuTalon/Msg/Command/SaveSettings.cls` -- `Changes`, stored in the shared extent `^Ens.MessageBodyD` (not `^OcuTalon*`), so the existing `Leaks()` scan never covered the trace.
- `src/ocutalon/cls/OcuTalon/Test/Core/SecretHandoff.cls` -- `Leaks(text)` (l.177; `^OcuTalon*` minus `OcuTalonTest`) and `TableHolds` (l.203).
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsEmail.cls` -- every save goes through `Save(body)` -> `SaveText(text)` (l.1079/1085). `Offer` and `Uris` feed `Reset`'s discard. `ADDRESS` and `USER` are the same string. `TestNoSecretAnywhere` (l.468) and `TestHandOffLost` (l.310) are the siblings.
- `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` -- `TestChannelsRoute` (l.544), `Handoffs`, `SaveSettingsRows` and `SaveSettingsHold` (l.717-745). The saves go through the real production and `SettingsOps`; its `ok` body has fixed values.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailLive.cls` -- real saves through `Commands.Submit`: `Connect` (l.265), `Resave` (l.289), `ConnectOAuth` (l.1652), and inline submits at l.837 and l.1979. `TestPasswordOnlyInTheCredential` (l.853) is the sibling leak scan.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsStep4.cls` -- `SaveMailbox` (l.551) submits a plain channels body.
- `docs/security-overview.md` -- "Roles and accounts:" list, the `OcuTalonTraceViewer` bullet (l.162). It is hand-written; `test-security-overview.sh` checks only the generated regions.
- `web/e2e/settings/email.spec.ts` -- posts plain values to the route and counts SaveSettings messages. The route body is unchanged, so it is read-only here.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- add `"address", "user"` to both name lists of `SaveChannels`, and update the `PASSWORDMAX`, method and class docs (the reference now covers the mailbox address and user name too) -- the one swap that keeps the values out of the command.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- in `SaveEmail`, after the online-demo check and before `EmailShape`, add one private method that does this for `address` and `user`: a string reference is taken with `SecretHandoff.Take(ref, .value)` (as for the password) and set as a string on the parsed `changes`; a failed take, or a string that is not a reference, goes to `AddField(bad, name)`; any other type is left for `EmailShape`. Kill the values on every path. Update the docs of `SaveEmail`, `EmailShape` and the class -- the owner takes them like the secrets.
- `src/ocutalon/cls/OcuTalon/Core/SecretHandoff.cls` -- doc only: it also carries the mailbox address and user name of a synchronous save.
- `src/ocutalon/cls/OcuTalon/Test/Core/SecretHandoff.cls` -- move `Leaks`' per-global walk into one private `Holds(root, text)`. Add `TraceLeaks(text)`: the names, among `^Ens.MessageBodyD`, `^Ens.MessageBodyS`, `^Ens.MessageHeaderD` and `^Ens.Util.LogD`, whose data or subscripts hold the text. Add `Swap(body, ByRef uris)`: it offers each non-empty string `address`/`user`, puts the reference in its place and appends it to `uris`. Add `TestTraceLeaksFinds`. It writes one `Ens.Util.Log` row (`LogInfo`) and saves one `SaveSettings` whose `Changes` holds a unique text, then asserts that `TraceLeaks` names `Ens.Util.LogD` and `Ens.MessageBodyD`. It deletes both by ID and asserts `""` -- shared scan and builder, extended, not copied.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsEmail.cls` -- `Save(body)` swaps a copy through `Swap` (into `..Uris`); `SaveText` stays raw. Add `TestAddressAndUserByReference` (plain address, then plain user: refused naming it, `AssertUntouched`; a lost reference for each: refused naming it; after a valid save, a second `Take` of both references fails) and `TestAddressAndUserNowhereElse` (unique address and user that are not equal: neither in any audit entry, answer or `Ens.Util.Log` row; `Leaks(user)` is ""; `Leaks(address)` is exactly `OcuTalonP.SettingD`, and only the `email.address` row holds it). Update the header list.
- `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` -- in `TestChannelsRoute`, make the `ok` values unique per run (`..Number`, `$Random`). Add: address and user as a JSON number, an object and 257 characters, each 400 naming it, nothing offered or submitted, and `SaveSettingsHold` 0. Add a body refused after the take (`incoming` `x@{y`): the newest SaveSettings message's `Changes` has references for `address` and `user`, its `incoming` is plain, `TraceLeaks` of both values is "", and `Handoffs()` is back to before. Update the header.
- `src/ocutalon/cls/OcuTalon/Test/Channel/EmailLive.cls` -- route every channels submit (`Connect`, `Resave`, `ConnectOAuth`, l.837, l.1979) through one private submit that swaps with `Swap` and takes back the references after the submit. Add `TestAddressAndUserOutOfTheTrace`: a real `Connect` with a unique address and user; the save's message holds two references; `TraceLeaks` of both is ""; `AuditLog.Entries(since)` holds neither; `Leaks(user)` is ""; `Leaks(address)` is `OcuTalonP.SettingD` only; the credential's Username is the user and `email.address` is the address; `Values()` shows both; then `Disconnect`. Update the header.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsStep4.cls` -- `SaveMailbox` swaps with `Swap` and takes back what is left.
- `docs/security-overview.md` -- insert the Public text sentence as a bullet right after the `OcuTalonTraceViewer` bullet.
- **TraceLeaks retrofit (Planner ruling L, condition).** `TraceLeaks` is a public class method of `Test.Core.SecretHandoff`, so other classes can call it. Add one `TraceLeaks(<same value>) = ""` assertion, or one "the trace" place in the class's own place helper, beside every existing scan that says a secret is never in a trace. Change test code only. The sites are:
  - `Test/Channel/EmailLive.cls`: the password (l.870, l.1570) and the OAuth2 client secret and tokens (l.1846, l.2322, l.2377). Stories 21.2, 21.3 and 21.8.
  - `Test/Core/SettingsEmail.cls`: l.476 and l.933 (Story 21.2).
  - `Test/Web/SettingsApi.cls`: l.626-628, the client secret and the password (Stories 21.2 and 21.3).
  - `Test/Web/HookSettingsApi.cls`: the per-secret loop (about l.303-318), for both webhook secrets (Story 35.3).
  - `Test/Mcp/Attach.cls` `Leaks(adapter)`, `Test/Mcp/Proxy.cls` `Places` and `Test/Mcp/JobFixture.cls` `Places`: add "the trace" when `TraceLeaks(value)` is not "".
  - `Test/Mcp/Ops.cls` l.564: for the credential.
  - `Test/Mcp/Approval.cls` l.571 and `Test/Mcp/ProxyJob.cls` l.156: for `..Secret`.
  These are Stories 22.3 and 22.4 (MCP secrets). Story 36.4's on-call scan is not on the branch yet, so it is out of scope.
- **A red retrofit scan is a REAL LEAK (ruling L).** Run the retrofitted classes BEFORE the 21.14 product change, against the unchanged product code. If any of them is red: change no product code for it, do not weaken, skip or exempt the assertion, and halt `blocked`. Name the test, the value kind (for example password or MCP credential) and the global where `TraceLeaks` found it, never the value. The lead takes it to the Planner before anything is fixed. A red that the retrofit itself causes (a wrong argument or a scan error) is fixed in the test. Show that it is not a real leak by the global the scan named.

**Acceptance Criteria:**
- Given an admin, when they POST `/v1/settings/channels` with a valid address and user, then the stored `SaveSettings` message holds only handoff references for them, neither value is in any message body, message header or `Ens.Util.Log` row, and no handoff resource is left (DW-1255; pin `SettingsApi:TestChannelsRoute`).
- Given a real save through the running production, when it is done, then neither value is in any traced message, log row, Settings audit entry or `^OcuTalon*` global, except the address in its one `email.address` row in the private database. The credential holds the user name, and GET still shows both (pin `EmailLive:TestAddressAndUserOutOfTheTrace`).
- Given a `SaveSettings` with a plain address or user, or a lost reference, when `SettingsOps` handles it, then it is refused naming the field and nothing is written (pin `SettingsEmail:TestAddressAndUserByReference`).
- Given the other fields, when any save runs, then `incoming`, `outgoing`, `signIn`, `clientId` and `origin` are plain in `Changes`, and every existing test of `SettingsEmail`, `SettingsApi`, `EmailLive`, `EmailOAuth` and `CommandsStep4` passes with only the helper changes above.
- Given `docs/security-overview.md`, when a reader reads the roles list, then it holds the Public text sentence word for word, after the `OcuTalonTraceViewer` bullet (DW-1255, ruling item 5).
- Given every existing scan that says a mail password, OAuth2 client secret or token, webhook secret or MCP credential is never in a trace (21.2, 21.3, 21.8, 35.3, 22.3, 22.4), when it runs, then it also asserts that `TraceLeaks` of that value is "" over `^Ens.MessageBodyD`, `^Ens.MessageBodyS`, `^Ens.MessageHeaderD` and `^Ens.Util.LogD`, and it passes against the product code (ruling L). A red is reported as a leak, not fixed in this story (pin `SecretHandoff:TestTraceLeaksFinds` for the helper; the retrofitted classes listed in the tasks).

## Spec Change Log

- 2026-11-13 (lead, Planner ruling L): the gate is approved as planned, and so are the AD-1, AD-19 and route-row wording (the spine is amended in the bookkeeping commit). The Public text is approved verbatim. Added the condition: the TraceLeaks retrofit into the leak scans of 21.2, 21.3, 21.8, 35.3, 22.3 and 22.4, its AC and its runs. A red retrofit scan is a real leak, so implement halts `blocked` and the lead reports it before any fix.

## Review Triage Log

### 2026-11-13 - Review pass
- verdicts: 20 findings - high 0, medium 4, low 13, false 7, maybe-false 0 (rows that share a root cause are marked carried; 3 medium entries)
- findings:
  - `[low]` `[reject]` Blind: a stored SaveSettings replayed from the message viewer is refused (the references are one-shot) - the intent says a plain value or a lost reference is refused naming the field; a save with a password was never replayable; spec-bound, not worth a guard.
  - `[false]` `[reject]` Blind: the address can reach the trace by the digest mail's recipient - the spec leaves `Msg.Item.Sender` and `SendEmail.Recipients` out (ruling items 4 and 5); the tests claim only the save message.
  - `[false]` `[reject]` Blind: the Public text sentence is too broad - the sentence is approved verbatim by the Planner (ruling item 5).
  - `[false]` `[reject]` Blind: TraceLeaks scans are unbounded and may add run time - measured: Mcp.Attach 163 s before and 166 s after, other classes unchanged.
  - `[medium]` `[patch]` Blind: the positive control covers two of the four globals - TestTraceLeaksFinds now also writes a header and a stream node and asserts both names; mutation line added.
  - `[low]` `[patch]` Blind: NewestChanges is unfiltered - it now selects the newest message of slug channels.
  - `[false]` `[reject]` Blind: PASSWORDMAX is misnamed and may differ from EmailShape's limits - the spec bounds all four fields by PASSWORDMAX (256) and keeps SettingsOps' exact rules, so each refusal is still a 400 naming the field.
  - `[low]` `[patch]` Blind: helpers drop failures and the cleanup of TestTraceLeaksFinds is not in a Catch - the test now makes and deletes its rows around a Try/Catch.
  - `[medium]` `[patch]` Edge: TestRefusedBodies' unknown-field case sent a plain address, so the refusal was no longer about the unknown field - the case goes through Save with references and asserts the refusal names no field.
  - `[false]` `[reject]` Edge: the route's pre-check names only the pre-checked fields in a multi-fault body - decided in the spec (Design Notes), as for the password.
  - `[low]` `[reject]` Edge: TakeMailbox names address and user before the fields of EmailShape in the refused list - only a body with both a take failure and another fault; the spec orders the take first, and the list is a set the page shows.
  - `[false]` `[reject]` Edge: Places in Proxy and Attach pass constants to TraceLeaks and may meet leftovers - both classes ran green repeatedly on the shared warm stack; a hit would have been red.
  - `[false]` `[reject]` Edge: an empty value gives a "[empty text]" trace place - fail-closed by design, and the same as for Leaks.
  - `[low]` `[patch]` Edge: NewestChanges may read another save's message - carried with the Blind row above, fixed by the channels filter.
  - `[low]` `[reject]` Edge: replay after the references are taken - carried with the Blind row above.
  - `[medium]` `[patch]` Gap: TestOnlineDemo never shows the address and user references stay untaken - the test now takes both after the demo refusal; mutation line added.
  - `[medium]` `[patch]` Gap: TraceLeaks finds only two of its four globals in the one test that proves it - carried with the Blind row above, fixed.
  - `[low]` `[reject]` Gap: the TraceLeaks lines in SettingsEmail cannot see a persisted message - the spec requires them beside the 21.2 and 21.3 scans (ruling L), they do scan Ens.Util.LogD; the route and live tests carry the pin.
  - `[low]` `[patch]` Gap: AC 4 and the new tests have no mutation line - the AC 4 line is added (Rule 19 is one per AC); the retrofit sites need none beyond TestTraceLeaksFinds' lines.
  - `[low]` `[defer]` Gap: Test.Watch.SettingSecret (Story 36.1) is not retrofitted - out of the spec's listed sites; deferred.
  - `[low]` `[reject]` Gap: TestAddressAndUserOutOfTheTrace scans once after the first poll - the value is written at the save, and the sibling scans cover the polls for the password.
  - `[low]` `[reject]` Gap: TestTraceLeaksFinds deletes after its assertions with no Catch - carried with the Blind row above, fixed.
  - `[low]` `[reject]` Intent: the tests of EmailLive, SettingsEmail and CommandsStep4 use the test-side Swap rather than the route - the route is pinned by TestChannelsRoute and its mutation; a drift of Swap would show there.
  - `[low]` `[reject]` Intent: the SettingsEmail TraceLeaks lines are vacuous for the persisted message - carried with the Gap row above.

## Design Notes

**Governing ADs:** AD-1 (every change is a traced command; the REST handoff bullet), AD-19 (fixed homes; the "Handing a secret" and mail-credential bullets: storage unchanged), AD-24/AD-25 (the trace role and the online demo's shared Visual Trace). No contradiction: the ruling widens what the handoff carries, for a synchronous save only.

**Scope, stated plainly:** `email.address` as a stored product key is not in scope. The ruling moves the values out of the traced command only, not out of storage. The address stays in `Data.Setting` (`^OcuTalonP.SettingD`, mapped to `OCUTALON_PRIVATE`, where the trace role has nothing). The user name stays in `Ens.Config.Credentials`. Readers of the stored key (`CommandsIn` l.150, `Rule.Functions` l.79, `EmailOut`, 21.7's digest recipient) do not change. Neither do the GET answer and the page. The only reader of `address`/`user` from `Changes` is `SettingsOps.EmailShape`, through `SaveEmail`. "IRIS's own audit entry" in the AC: OcuTalon's Settings entries in the instance audit log keep `set`/`changed`, and IRIS's credential trigger writes `Modified: Username`. Neither holds a value.

**Rule 1/2:** no new service or class. The change extends the password/clientSecret swap in `Api.SaveChannels` and the password `Take` in `SaveEmail`. On the test side it extends `Test.Core.SecretHandoff`'s `Leaks` (shared walk) and the existing body helpers. Consumes: `OcuTalon.Core.SecretHandoff` (Stories 21.2, 35.3), against the real class.

**Ledger inbox:** DW-1255 is addressed by AC 1 to AC 5.

**Decided in-stage:**
- The owner refuses a plain address or user rather than accepting both forms, so the contract cannot drift back unseen. Today the route is the only producer, so nothing reaches this path.
- `PASSWORDMAX` (256) bounds all four fields at the route. `SettingsOps` keeps the exact rules (address 254, user 256), so every refusal is still a 400 naming the field.
- As for the password, the route's type/length pre-check names only the pre-checked fields. A body that is bad there and elsewhere names the pre-checked ones first.
- There is no browser part. `web/` and the route's input are unchanged, so a browser save adds no discriminating power. The route-level pin goes red when the swap is removed.
- The one exemption from the `^OcuTalon*` scan is the address's `email.address` row. If `Leaks` names any other global, that is a leak and is never a wider exemption. Implement fixes it when `SettingsOps` writes it, and otherwise halts `blocked`.
- The trace scan walks `^Ens.MessageBody*`, `^Ens.MessageHeaderD` and `^Ens.Util.LogD`, because every OcuTalon message shares the `Ens.MessageBody` extent. The scan of `^OcuTalon*` alone (21.2/21.3/21.8) never covered the trace.

**For the lead (Rule 20, veto window):** amend AD-1's REST handoff bullet ("may offer a secret it received") and AD-19's "Handing a secret" bullet to say the handoff also carries the mailbox address and user name of the synchronous channels save, and say so in the channels route row. This goes in the bookkeeping commit, with memlog and lint.

**Veto items** (the email settings are off on the online demo, so it behaves the same: 409 before the body is read, nothing offered):
- Amending an AD: the AD-1/AD-19 handoff wording above.
- Security posture: this narrows the trace only, within the ruling. The owner now refuses plain values, a stricter contract.
- Stored-data shape: none. A new route: none. A new dependency: none.
- Public text: the one sentence below. No other new text.

## Public text

Insert in `docs/security-overview.md`, "Roles and accounts:", as the bullet right after the `OcuTalonTraceViewer` bullet, exactly:

`- Anyone with the trace role can read the content of every item that reaches OcuTalon in Visual Trace and the message viewer, such as a chat message's text and an email's sender, subject and text.`

Nothing else new is public.

## Verification

Run every command from the worktree root, one per foreground call (`timeout: 600000`), each about 150 s at most. Never put two test runs in one message. Put one `iris_execute_tests` per message, with `server` and `namespace` on every MCP call (Rule 21). Use lane-C throwaways only.

`<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=implement'`. The warm tag is `e21s14iw` and the fresh tag `e21s14i`.

**Implement-stage notes (lead, pre-answered):**
- Order: build `TraceLeaks` and the retrofit first, then run the retrofitted classes against the UNCHANGED product code (`Api.cls`, `SettingsOps.cls` untouched) before any product change. A red scan caused by a secret really sitting in `^Ens.MessageBody*`, `^Ens.MessageHeaderD` or `^Ens.Util.LogD` is a REAL LEAK: change no product code, do not weaken, skip or exempt the assertion, and stop and report (test, value kind, global; never the value). A red caused by the retrofit itself (wrong argument, scan error) is fixed in the test.
- Public text: exactly the sentence above. No other new public text.
- Rule 19: every pin gets its `mutation:` line (applied, observed red, reverted byte-identical), written under Verification.
- Rule 14: the spec is `oversized`; add nothing beyond its tasks.
- Scan cost: `TraceLeaks` walks whole globals on a shared warm instance, and `Mcp.Attach` calls its `Leaks` about 25 times. If a class's run time grows by more than about 30 s, compute the scan once per test, not once per assertion, and record that here.
- Runtime (lane C only): `OCUTALON_LOCK_DIR=<worktree parent>/.coordination/locks/lane-c`, `OCUTALON_TEST_WEB_PORT=52803`, `OCUTALON_LOCK_OWNER='epic=21 stage=implement'`; warm tag `e21s14iw`, fresh tag `e21s14i`. Never read `.env`, never send real mail, never touch another lane's containers, `ocutalon-aihub-test`, `ocupilot*` or `iris-community-edition`. A mutation of production-run code needs `ci/warm.sh down` then `up`. Tear down everything you start. Scratch only under the scratchpad directory given in the spawn prompt. No absolute local path in a tracked file. Do not touch any Epic 22 product file; the Mcp test files get the retrofit lines only. Do not edit the architecture spine.

**Shared surfaces:** the shape of `SaveSettings.Changes` for slug `channels`. It is built or asserted by `Test.Core.SettingsEmail` (`Save`), `Test.Core.CommandsStep4` (`SaveMailbox`), `Test.Channel.EmailLive` (`Connect`, `Resave`, `ConnectOAuth`, l.837, l.1979), `Test.Web.SettingsApi` (`TestChannelsRoute`, `SaveSettingsHold`) and, read-only, `web/e2e/settings/email.spec.ts` (route input unchanged). Every test added or changed passes on a fresh environment, in either order, with unique values per run and every reference taken back.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s14iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s14iw ci/iris.sh class OcuTalon.Test.Web.SettingsApi:TestChannelsRoute` (loop) -- pass. Mutation: `"address", "user"` removed from the offer loop of `SaveChannels` -> red (the message holds the address; the save is refused).
- `... class OcuTalon.Test.Core.SettingsEmail` (loop) -- pass. Mutation: the new take step accepts a plain string -> `TestAddressAndUserByReference` red.
- `... class OcuTalon.Test.Core.SecretHandoff` (loop) -- pass. Mutation: `TraceLeaks` skips `^Ens.Util.LogD` -> `TestTraceLeaksFinds` red.
- `... class OcuTalon.Test.Channel.EmailLive:TestAddressAndUserOutOfTheTrace` (loop) -- pass. Mutation: `SaveEmail` adds `$$$LOGINFO` of `field("address")` -> red (`TraceLeaks`).
- `... class OcuTalon.Test.Web.SettingsApi` (once) -- pass.
- Retrofit runs, once each and one per call, BEFORE the product change and again after it: `... class OcuTalon.Test.Web.HookSettingsApi`, `... class OcuTalon.Test.Mcp.Attach`, `... class OcuTalon.Test.Mcp.Proxy`, `... class OcuTalon.Test.Mcp.Ops`, `... class OcuTalon.Test.Mcp.Approval` and `... class OcuTalon.Test.Mcp.ProxyJob`. `SettingsEmail`, `SettingsApi` and `EmailLive` are run above. All pass. A red before the change is a leak, so halt `blocked` (see the tasks). Mutation: `TraceLeaks` returns "" at once -> `TestTraceLeaksFinds` red.
- `... class OcuTalon.Test.Channel.EmailLive` (once; about 65 to 115 s) -- pass.
- `... class OcuTalon.Test.Channel.EmailOAuth` (once) and `... class OcuTalon.Test.Core.CommandsStep4` (once), one per call -- pass.
- `<vars> OCUTALON_RUN_TAG=e21s14iw ci/warm.sh down` (once, also after a failure).
- Fresh check (once each, no `OCUTALON_WARM`): `<vars> OCUTALON_RUN_TAG=e21s14i ci/iris.sh class OcuTalon.Test.Web.SettingsApi:TestChannelsRoute`, then `... class OcuTalon.Test.Channel.EmailLive:TestAddressAndUserOutOfTheTrace`, then `<vars> OCUTALON_RUN_TAG=e21s14i ci/iris.sh teardown`.
- `grep -Fxc -- "- Anyone with the trace role can read the content of every item that reaches OcuTalon in Visual Trace and the message viewer, such as a chat message's text and an email's sender, subject and text." docs/security-overview.md` (once) -- `1`. Mutation: the line removed -> `0`.
- `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` (once each) -- pass.
- `git diff -U0 -- src | grep -E '^[+-]\s*(Property|Index|<Value>|<Data|Storage|XData)'` (once) -- no output (no stored-data or section change).

**Implement-stage results (Rule 19: each mutation applied, observed red, reverted byte-identical):**
- Retrofit runs against the UNCHANGED product code (Api.cls, SettingsOps.cls untouched), all green, so no real leak: `Test.Web.HookSettingsApi`, `Test.Mcp.Attach` (about 163 s, as before the retrofit), `Test.Mcp.Proxy`, `Test.Mcp.Ops`, `Test.Mcp.Approval`, `Test.Mcp.ProxyJob`, `Test.Core.SettingsEmail`, `Test.Web.SettingsApi`, `Test.Channel.EmailLive`. The same classes, with `Test.Channel.EmailOAuth`, `Test.Core.CommandsStep4` and `Test.Core.SecretHandoff`, are green after the product change. The scan was not slowed, so no scan is cached.
- mutation: `SettingsApi:TestChannelsRoute` -- `"address", "user"` removed from the offer loop of `SaveChannels` -> red (the `@{` cases, "a body refused after the take", "they are references of the hand-off" and "no trace global holds the address or the user name"); reverted, cmp identical.
- mutation: `SettingsEmail:TestAddressAndUserByReference` -- the take step in `SettingsOps.TakeMailbox` keeps a plain string (no `AddField` on a failed take) -> red (plain address, plain user, lost user reference, never-offered reference); reverted, cmp identical.
- mutation: `SecretHandoff:TestTraceLeaksFinds` -- `TraceLeaks` skips `Ens.Util.LogD` -> red ("names Ens.Util.LogD"); `TraceLeaks` returns "" at once -> red (both names); reverted, cmp identical.
- mutation: `EmailLive:TestAddressAndUserOutOfTheTrace` -- `SaveEmail` adds `$$$LOGINFO` of `field("address")` (after `warm.sh down` and `up`) -> red ("no trace global holds the address"); reverted, cmp identical, then `warm.sh down`.
- mutation: `SettingsEmail:TestOnlineDemo` (the online demo takes nothing) -- `TakeMailbox` moved above the online-demo check of `SaveEmail` -> red ("the address reference was not taken", "nor the user name's"); reverted, cmp identical.
- mutation: `SecretHandoff:TestTraceLeaksFinds` (all four globals) -- `Ens.MessageBodyS` and `Ens.MessageHeaderD` removed from `TraceLeaks`' list -> red ("and Ens.MessageHeaderD for the header", "and Ens.MessageBodyS for the stream node"); reverted, cmp identical.
- mutation: AC 4 (`incoming`, `outgoing` and the other fields stay plain), pin `SettingsApi:TestChannelsRoute` -- `"incoming"` added to the offer loop of `SaveChannels` -> red ("while incoming and outgoing are plain" and the `@{` cases); reverted, cmp identical.
- mutation: the Public text line removed -> `grep -Fxc` is 0 (on a copy), 1 in the file.
- Fresh checks (tag `e21s14i`, no warm; run again after the review patches): `TestChannelsRoute` and `TestAddressAndUserOutOfTheTrace` passed, `iris.sh teardown` left nothing.
- After the review patches (warm tag `e21s14iw`, down afterwards): `SecretHandoff`, `SettingsEmail`, `SettingsApi`, `CommandsStep4` and `EmailLive` (115 s) pass. Scan cost: `Mcp.Attach` ran about 163 s before and 166 s after the retrofit, so no scan is computed once per test. `test-class-rules.sh` and `test-boundaries.sh` pass; the stored-data grep prints nothing.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `SaveChannels` now offers the mailbox address and user name to `SecretHandoff` like the password, so `SaveSettings.Changes` holds only references for them. `SettingsOps.SaveEmail` takes both with `TakeMailbox` before `EmailShape`; a plain string or a lost reference is refused naming the field, and the online demo still refuses first. Storage is unchanged. `TraceLeaks` (message bodies and streams, headers, log rows) is added to `Test.Core.SecretHandoff` and asserted beside every listed secret scan, with no real leak found against the unchanged product code. The Public text sentence is in `docs/security-overview.md`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: the route swap and docs for address and user.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`: `TakeMailbox`, called by `SaveEmail`; docs.
- `src/ocutalon/cls/OcuTalon/Core/SecretHandoff.cls`: doc only.
- `docs/security-overview.md`: the approved sentence after the `OcuTalonTraceViewer` bullet.
- `src/ocutalon/cls/OcuTalon/Test/Core/SecretHandoff.cls`: `Holds`, `TraceLeaks`, `Swap`, `NewestChanges`, `TestTraceLeaksFinds`.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsEmail.cls`, `Test/Web/SettingsApi.cls`, `Test/Channel/EmailLive.cls`, `Test/Core/CommandsStep4.cls`: the swap in the helpers, the new pins and the retrofit.
- `src/ocutalon/cls/OcuTalon/Test/Web/HookSettingsApi.cls`, `Test/Mcp/Attach.cls`, `Proxy.cls`, `JobFixture.cls`, `Ops.cls`, `Approval.cls`, `ProxyJob.cls`: the retrofit lines only.

**Review.** 20 findings from four layers: 5 patch entries applied (3 medium entries - the four-global positive control, the unknown-field case of `TestRefusedBodies` and the online demo's untaken references - and 2 low: the channels filter of `NewestChanges` and the AC 4 mutation line; the Catch around `TestTraceLeaksFinds`' cleanup is one more low), 1 deferred (low, in frontmatter), 14 rejected with their reasons in the triage log. No `high`.

**Follow-up review recommendation:** `false` (no `high` was patched, as the stage prompt's override (c) sets; patched by entry verdict: high 0, medium 3, low 3).

**Verification.** Retrofitted classes green against the unchanged product code and again after it; after the review patches `SecretHandoff`, `SettingsEmail`, `SettingsApi`, `CommandsStep4` and `EmailLive` pass (warm tag `e21s14iw`); the fresh checks of `TestChannelsRoute` and `TestAddressAndUserOutOfTheTrace` pass (tag `e21s14i`); `test-boundaries.sh` and `test-class-rules.sh` pass; the Public text grep is 1; the stored-data grep prints nothing. All stacks are torn down. Mutation lines are under Verification.

**Residual risks.** `EmailLive` reads `email.address` with `KeyIndexOpen` because `Data.Setting.Get` returned an empty value in the test process once (not investigated; the cache may be stale for the first value after a save). `EmailOAuth` was green after the product change and was not re-run after the review patches (they touch no file it uses). The AD-1 and AD-19 spine wording is the lead's.
