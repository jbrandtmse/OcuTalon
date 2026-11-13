---
title: 'The mailbox address and user name stay out of the trace'
type: 'bugfix'
created: '2026-11-13'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
warnings: ['oversized']
deferred: []
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

**Acceptance Criteria:**
- Given an admin, when they POST `/v1/settings/channels` with a valid address and user, then the stored `SaveSettings` message holds only handoff references for them, neither value is in any message body, message header or `Ens.Util.Log` row, and no handoff resource is left (DW-1255; pin `SettingsApi:TestChannelsRoute`).
- Given a real save through the running production, when it is done, then neither value is in any traced message, log row, Settings audit entry or `^OcuTalon*` global, except the address in its one `email.address` row in the private database. The credential holds the user name, and GET still shows both (pin `EmailLive:TestAddressAndUserOutOfTheTrace`).
- Given a `SaveSettings` with a plain address or user, or a lost reference, when `SettingsOps` handles it, then it is refused naming the field and nothing is written (pin `SettingsEmail:TestAddressAndUserByReference`).
- Given the other fields, when any save runs, then `incoming`, `outgoing`, `signIn`, `clientId` and `origin` are plain in `Changes`, and every existing test of `SettingsEmail`, `SettingsApi`, `EmailLive`, `EmailOAuth` and `CommandsStep4` passes with only the helper changes above.
- Given `docs/security-overview.md`, when a reader reads the roles list, then it holds the Public text sentence word for word, after the `OcuTalonTraceViewer` bullet (DW-1255, ruling item 5).

## Spec Change Log

## Review Triage Log

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

**Shared surfaces:** the shape of `SaveSettings.Changes` for slug `channels`. It is built or asserted by `Test.Core.SettingsEmail` (`Save`), `Test.Core.CommandsStep4` (`SaveMailbox`), `Test.Channel.EmailLive` (`Connect`, `Resave`, `ConnectOAuth`, l.837, l.1979), `Test.Web.SettingsApi` (`TestChannelsRoute`, `SaveSettingsHold`) and, read-only, `web/e2e/settings/email.spec.ts` (route input unchanged). Every test added or changed passes on a fresh environment, in either order, with unique values per run and every reference taken back.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s14iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s14iw ci/iris.sh class OcuTalon.Test.Web.SettingsApi:TestChannelsRoute` (loop) -- pass. Mutation: `"address", "user"` removed from the offer loop of `SaveChannels` -> red (the message holds the address; the save is refused).
- `... class OcuTalon.Test.Core.SettingsEmail` (loop) -- pass. Mutation: the new take step accepts a plain string -> `TestAddressAndUserByReference` red.
- `... class OcuTalon.Test.Core.SecretHandoff` (loop) -- pass. Mutation: `TraceLeaks` skips `^Ens.Util.LogD` -> `TestTraceLeaksFinds` red.
- `... class OcuTalon.Test.Channel.EmailLive:TestAddressAndUserOutOfTheTrace` (loop) -- pass. Mutation: `SaveEmail` adds `$$$LOGINFO` of `field("address")` -> red (`TraceLeaks`).
- `... class OcuTalon.Test.Web.SettingsApi` (once) -- pass.
- `... class OcuTalon.Test.Channel.EmailLive` (once; about 65 to 115 s) -- pass.
- `... class OcuTalon.Test.Channel.EmailOAuth` (once) and `... class OcuTalon.Test.Core.CommandsStep4` (once), one per call -- pass.
- `<vars> OCUTALON_RUN_TAG=e21s14iw ci/warm.sh down` (once, also after a failure).
- Fresh check (once each, no `OCUTALON_WARM`): `<vars> OCUTALON_RUN_TAG=e21s14i ci/iris.sh class OcuTalon.Test.Web.SettingsApi:TestChannelsRoute`, then `... class OcuTalon.Test.Channel.EmailLive:TestAddressAndUserOutOfTheTrace`, then `<vars> OCUTALON_RUN_TAG=e21s14i ci/iris.sh teardown`.
- `grep -Fxc -- "- Anyone with the trace role can read the content of every item that reaches OcuTalon in Visual Trace and the message viewer, such as a chat message's text and an email's sender, subject and text." docs/security-overview.md` (once) -- `1`. Mutation: the line removed -> `0`.
- `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` (once each) -- pass.
- `git diff -U0 -- src | grep -E '^[+-]\s*(Property|Index|<Value>|<Data|Storage|XData)'` (once) -- no output (no stored-data or section change).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
