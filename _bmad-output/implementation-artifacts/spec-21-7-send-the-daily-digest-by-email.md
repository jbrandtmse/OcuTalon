---
title: 'Story 21.7: Send the daily digest by email'
type: 'feature'
created: '2026-11-11'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-6-send-email-over-smtp.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon can send email (21.6) but the daily digest never goes by email: Settings > Daily digest offers no email box, `digest.channels` refuses `email`, Notify's digest branch knows only `WebChatOut`, `SimPhoneOut` and `TelegramOut`, the renderer refuses channel `email`, and `EmailOut` takes only `SendEmail`. Also every mail `EmailOut` sends to the polled mailbox comes back through `EmailIn` as a new untrusted item (DW-1167); with a daily digest that is a daily loop.

**Approach:** Per the Planner's ruling Q1, Notify is the one routing point: a second Notify rule sends a `digest` Notification to `EmailOut` when `digest.channels` names `email` and the session is the mailbox owner. `EmailOut` gains a narrow third path for that Notification (recipient fixed to `email.address`, never taken from the message), renders through the new `email` channel of `OcuTalon.Msg.Catalog` (the `phone` rules) and `Channel.DigestText`, sends once and records a `Delivery`. Every `EmailOut` mail carries `X-OcuTalon-Ref`, and `EmailIn` skips a mail whose header names an email `Delivery` row. `Digest.Process` (Lane A) is not edited and learns nothing about email; it must hand every digest to Notify (DW-820's Lane A residual, item O1).

## Boundaries & Constraints

**Always:** Lane B files only; contended files get the small placed edits of Design Notes "Contended files". Recipient of a digest email = `Setting.Fresh("email.address")` only, and only when the Notification's `SessionRef` equals `Setting.Fresh("email.owner")`; nothing in the Notification names an address. 21.6's rules stay: TLS only, one try, one plain-text UTF-8 part, no attachment, counts-only logging, credential read at send, `not_available` on the online demo whatever the rows say. Producers never render (AD-32): `EmailOut` renders every `{key, slots}` of the digest through `Catalog.Render` (via `DigestText`) and the subject from a catalog key. No all-clear in the subject (AD-28). Online demo: Notify routes nothing to `EmailOut`, `EmailOut` stays disabled and refuses, no email box shows, the demo's digest keeps its channels. ASCII-only source; comments state the contract. CI sends only to the mock's SMTP stub.

**Never:** an edit under `Digest/**`, `Mcp/**`, `Fix/**`, `Bridge/**`, `Install/**`, `src/bridge/**` or a Lane A test; a recipient from the Notification, the model or an item; a `SendEmail` command or origin `system` for the digest (no approval exists for it); a new route, role, grant, resource, table, index, production item, `ci/units.sh` unit or group; a resend loop for a failed email digest; OAuth2 (21.3/21.8); a real mail server, address or credential in any test.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Digest by email | mailbox + outgoing saved by session S (`email.owner` S); `digest.channels` names every own channel of S plus `email`; S's digest composed | Notify sends it to its usual targets AND `EmailOut`; the stub holds one mail From/To `email.address`, subject E1, text = `DigestText.Text(Slots, "email")`, header `X-OcuTalon-Ref` = the new `Delivery` row's ChannelMessageId (owner S, channel `email`, Kind `digest`, DecisionRef, no text) | -- |
| Email only, or email beside a strict subset of own channels | `digest.channels` `email` / `web,email` with demo mode on | as row 1, EmailOut only for `email` alone (needs O1: Digest hands every digest to Notify) | today: Digest sends direct or fails `MESSAGENOCHANNEL`, so no email -- the blocking dependency |
| Not the owner | digest of session T, T not `email.owner` | Notify routes nothing to `EmailOut`; `EmailOut` called directly sends nothing | -- |
| Email not named / not connected | `digest.channels` without `email`; or `email.address` empty; or `EmailOut` has no alive job | no route to `EmailOut`; other targets unchanged | -- |
| Online demo | `onlineDemo` 1, any rows | no route to `EmailOut`; called directly: nothing sent | -- |
| Render or send failure | a piece that does not render; stub `refuse`/`auth`/`reject` | nothing sent (render) / one try failed; no `Delivery`; one warning with the class only | no retry, no resend |
| Other Notification kinds at `EmailOut` | Kind `tellnow` etc. | nothing sent, one warning | -- |
| Own mail polled back (DW-1167) | POP3 mail with `X-OcuTalon-Ref` = ChannelMessageId of an email `Delivery` row | recorded seen, no Item, counted | an unknown or forged Ref: one untrusted Item as before |
| Settings | admin saves channels incl. `email` | 200, stored in order `web,phone,telegram,email`, audited; `email` accepted like `phone` whether shown or not | LIVE fixture user 403; demo 409 as today |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- class doc :1-13; `Notification` rule :35-77 (8 digest `when`s :45-68, final empty `when` :69). Add a second `<rule name="DigestEmail">` (constraint `OcuTalon.Msg.Notification`, `when Kind="digest" && DigestEmail(Document.SessionRef)` -> `EmailOut`) rather than doubling the combinations: send actions of every matching rule append to the router's targets unless a `return` fires (`irislib/Ens/Rule/Generator.cls` :315-322, :367-401; measure, Task 0 a).
- `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls` -- `DigestNamed` :52-69 (list `web,phone,telegram` -> add `email`); new `DigestEmail(sessionRef)`: 1 only when not online demo, `DigestNamed("email")`, sessionRef = `email.owner`, `SettingsOps.IsAddress(email.address)` and `CommandsIn.ItemRunning("EmailOut")`; never throws. Names must be unique across function sets.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:286` -- `ItemRunning(item)` is `[ Private ]`; drop `Private` (Rule 2: reused, not copied).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- doc :13, :25; `CHANNELS` :39 (add `email`); `Build` :92-102 (`email` uses `text`, as `phone`). `CHANNELNAMES` :42 unchanged (no digest key has a `channel` slot).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- new key `email.digestSubject` (E1), placed at the end of the XData (35.3 inserts near :728 and edits doc :3).
- `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls` -- reused as is (`Text(slots, channel)`); doc line names `EmailOut` among its callers.
- `src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls` -- doc :1-26; `MessageMap` :83-89 (add `OcuTalon.Msg.Notification` -> `OnNotification`); `Handle` :106; `Send` :144-173 (build/deliver/record; extend to take from, recipients, subject, text, owner, claim, kind, decisionRef so both paths share it; the Ref is made before the send and set as header `X-OcuTalon-Ref` through `%Net.MailMessagePart.Headers` (`irislib/%Net/MailMessagePart.cls:139`; `%Net.SMTP.ValidateHeaders` :291); a claim row reuses its own ChannelMessageId); `Check` :182 (caps reused for the digest's subject/text). Sibling for the Notification branch: `Channel/SimPhone/Out.cls:72-73` (digest text via `DigestText`).
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls` -- `Record` :54 (kind, text, decisionRef args); indexes :47-49 (none on ChannelMessageId); new `ClassMethod SentByEmail(ref)` (1 when a row of channel `email` has that ChannelMessageId; SQL, no new index).
- `src/ocutalon/cls/OcuTalon/Channel/Email/Adapter.cls` -- `Read` :187-209 (both the headers-only and the full fetch paths set the new `Mail.SentRef` from `x-ocutalon-ref`; header key case measured, Task 0 b). `Channel/Email/Mail.cls` -- new `Property SentRef As %String(MAXLEN = 128)`. `Channel/Email/In.cls` `OnProcessInput` :32-55 -- `SentRef` known to `Delivery.SentByEmail` -> Quit OK with no Item (the adapter then records it seen, `Adapter.cls:161`); counts-only info line.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- channels validation :1024-1035 (`web,phone,telegram` -> add `email`, canonical order web, phone, telegram, email); `Sections` :849-851 default unchanged.
- `web/src/app/settings/settings-view.ts` -- `SETTINGS_TEXTS.dailyDigest` :62-72 (add `email`), `DIGEST_CHANNELS` :263, `digestChannelBoxes` :274 (gains `emailShown`), `storedChannels` :279, `digestChannelsBody` :288. `daily-digest-section.ts` -- inputs :162-169 (add `emailShown`), `boxes` :200, `body` :209, dirty :225. `settings-page.ts` -- `email` :234, digest inputs :75-77 (pass `emailShown` = address and outgoing both non-empty).
- Mock: `ci/mock/smtp.mjs` (state: add each mail's `headers` of interest, at least `xOcutalonRef`), `ci/mock/mail.mjs` (`<message>` gains optional `headers` {name: value}, header comment :2-19), tests `ci/mock/test/smtp.test.mjs`, `mail.test.mjs`.
- Lane A, read only: `Digest/Process.cls` `Channels` :728, `Named` :743 (filters to `web,phone,telegram`), `Deliver` :757 (Notify only when channels = own, else direct), `Own` :884; `Finish` :591-670 builds `Slots`.
- Tests to extend: `Test/Core/Routing.cls` `TestNotifyDigestTargets` :278, `TestFunctions` :317, `TestRuleTargetsAreProductionItems` :374; `Test/Msg/Catalog.cls` `TestEveryKeyOnEveryChannel` :123 (refused list drops `email`; key counts), `TestChannelNames` :667; `Test/Core/SettingsSave.cls:195-204` (`email` refused today -> accepted); `Test/Channel/EmailOut.cls` (+ `EmailOutProbe`); `Test/Channel/EmailLive.cls` (`TestToolSendReachesTheStub` :864 pattern); `Test/Channel/EmailIn.cls`, `EmailInPop3.cls`; `web/scripts/settings-view.test.mjs:298`, `ux-strings.test.mjs:223`; `web/e2e/settings/email.spec.ts`.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first on the lane-C warm stack; record under Design Notes "Measured"; label anything unmeasured (inference)): (a) the Notify routing engine with a second matching rule: the target list of a digest Notification (both rules' sends, order, one `Ens.Rule.Log` row) and the `Test.Core.Routing` `Route` string it gives; (b) `X-OcuTalon-Ref` set on `%Net.MailMessage.Headers` reaches the SMTP stub, and on POP3 `Fetch` (`message.Headers`) and `FetchMessageHeaders` (`headers(...)`) under which key case; (c) an async Notification to a definition-disabled `EmailOut` (queued until enabled?), which is why `DigestEmail` checks the job; (d) `Delivery.SentByEmail` cost with 10,000 Delivery rows (no index); (e) the `DigestText` output for `email` with LF through `%Net.SMTP` (stub text equals the rendering, trailing CRLF aside).
- `Msg/Catalog.cls`, `Msg/Catalog/Core.cls` -- channel `email` (phone rules); key `email.digestSubject` (E1, slots {}) -- AD-32, AC "render tests".
- `Core/Rule/Functions.cls`, `Core/Rule/Notify.cls`, `Core/CommandsIn.cls` -- `DigestNamed` knows `email`; `DigestEmail`; rule `DigestEmail`; `ItemRunning` public; docs -- Q1 one routing point.
- `Channel/Email/Out.cls`, `Data/Delivery.cls` -- `OnNotification`: online demo -> nothing; Kind not `digest` -> nothing (warning); `SessionRef` '= `Fresh(email.owner)` or `email.address` not an address -> nothing; subject = Render(E1, "", "email"), text = `DigestText.Text(Slots, "email")` (error -> nothing); caps as `Check`; shared `Send` with header; `Delivery.Record(SessionRef, "email", ref, "", "digest", "", DecisionRef)`; always answers OK, no response; counts-only logs. `SentByEmail`.
- `Channel/Email/{Adapter,Mail,In}.cls` -- DW-1167: carry `SentRef`; skip a known one (seen, no Item).
- `Core/SettingsOps.cls` -- accept `email` in `digest.channels`.
- `web/...settings-view.ts`, `daily-digest-section.ts`, `settings-page.ts` -- box `email` (E2) shown only when address and outgoing are saved; hidden keeps stored state; order web, phone, telegram, email.
- `ci/mock/smtp.mjs`, `mail.mjs` + tests -- headers in the SMTP state; optional `headers` on POP3 fixtures.
- Tests (each with its `mutation:` line): `Test.Msg.Catalog` (every key renders on `email` equal to `phone`; `email` no longer refused; E1 fixture); `Test.Core.Routing` (digest targets gain `EmailOut` exactly when named + owner + address + running + not demo; `DigestEmail` cases; target is a production item); `Test.Core.SettingsSave` (`email` accepted, order); `Test.Channel.EmailOut` (Notification path: owner/non-owner, demo, wrong kind, render error, caps, header on all three paths, Delivery Kind `digest` only on success, no address in log); `Test.Channel.EmailIn` (+POP3) (known Ref skipped and seen, unknown/forged Ref -> Item); `Test.Channel.EmailLive` (Integration ACs below); `web/scripts/settings-view.test.mjs`, `ux-strings.test.mjs`; `web/e2e/settings/email.spec.ts` E6.
- After the gate rulings: spine S1-S5 with `[ADDED <date>, Story 21.7]`, memlog line (lead), lint; `EXPERIENCE.md` rows for E1/E2 as ruled.

- **O1 ruling (orchestrator, 2026-11-12 ~01:40Z, veto item sent to the Contest Planner; `prompts/epic-21-rulings-217-o1.md`; DW-820):** one-time AD-33 Lane A exception (precedents 17.10, 35.3 R5, 22.4 R1): this story edits `src/ocutalon/cls/OcuTalon/Digest/Process.cls` so that `Deliver` hands EVERY composed digest to Notify whatever `digest.channels` names, Notify alone routes kind `digest` (honouring `digest.channels`, incl. `email`), and `Digest.Process.Own`, the `SendDigest` direct sends to WebChatOut/SimPhoneOut/TelegramOut and `ROUTEREASON` are deleted; the Lane A tests that pin `Own` and the direct sends are changed with it (Lane A test files under `Test/Digest/**`, only those that pin this). Before implement, re-check that no open epic branch or worktree touches `Digest/` or the Notify files (`git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<M>` for each open branch); a new hunk there is a Clarification. Reversal: if the Planner routes DW-820's residual to a Lane A story instead, 21.7 waits on that story's merge and drops this task.

- **Gate rulings (Contest Planner, owner's delegation, 2026-11-12 ~01:50Z; `prompts/epic-21-rulings-217.md`; binding; they win over any line above or in the matrix that differs):**
  - (O1 conditions) The digest a user already gets in the web chat and in Telegram stays byte-identical and is sent at the same moments: one regression test per channel (web chat, Simulated phone, Telegram) comparing the delivered text before and after the Notify-only route; the demo's "Send my digest now" e2e (`web/e2e/settings/settings.spec.ts` S11) passes unchanged. `MESSAGENOCHANNEL` behaviour (no channel available) stays covered by a test. 21.7 does NOT merge onto a cut 1.0.8 RC base (it goes into the next release after it; the lead reports this at PART READY).
  - (V1) The digest path is the THIRD path enumerated inside `EmailOut`, next to 21.6 ruling (a)'s tool and system paths: `EmailOut` works out the recipient itself from `email.address` (`Setting.Fresh`); nothing passed in (no recipient field, no header, no message property) can choose it. 21.6 conditions (b) header guard and caps, (c) TLS with host-name check and no plain fallback, (e) taint/clean-turn rule where it applies, (f) no double send (a digest is keyed to its digest send/Delivery so a resend of the same Notification sends nothing), and (g) `not_available` on the online demo apply to this path, each with a pinning test. Addition: at most 10 digest emails per mailbox per UTC day; the 11th is refused, nothing is sent, and the refusal is recorded (a `Delivery` row or log entry with no contents) -- a test sends 11.
  - (V4, DW-1167, narrower) `EmailIn` skips a mail only if ALL hold: its `X-OcuTalon-Ref` names a SENT email `Delivery` row; its From is the configured `email.address`; that Ref has not been skipped before (one use only, recorded). Each skip leaves a trace or log line with the Ref and no contents. Anything else (unknown, forged, reused Ref, other From) is taken in as an untrusted item as before. Tests for each of the three conditions failing.
  - (V5) The Ref is random (at least 120 bits; e.g. `Bridge.Ids.NewRef` if it gives >= 120 bits of randomness -- Task 0 records its entropy, else a `$SYSTEM.Encryption.GenCryptRand`-based value), never a sequence number or derived from the session or address, and goes on EVERY `EmailOut` mail (tool, system, digest; partner notices included if they ever use EmailOut). A test asserts the header on each path and that two sends get different Refs.
  - (E1) If the digest already formats its date for the chat heading, the subject is "Your OcuTalon digest for {date}" with that same date format (so mail apps do not thread every day's digest into one conversation); otherwise "Your OcuTalon digest" as drafted. Record which under Design Notes "Decided in-stage". E2 "Email" approved. R1 approved only if "Settings > Daily digest" matches the page's real labels; it goes into the README after 0.26's README merge (rebase the line onto the new README; if 0.26 has not merged when 21.7 commits, record R1 as pending in the spec and leave the README untouched).
  - V2, V3, V6, V7 approved as drafted; spine S1-S5 as drafted (additive), with V1's third path and V4/V5's conditions in S2.

**Acceptance Criteria:**
- (Integration) Given the mailbox and SMTP server saved on the CI stubs by owner session S and `digest.channels` naming S's own channels plus `email`, when S's admin submits `SendDigest` through `Commands.Submit` (origin `web_admin`), then real Digest -> real Notify -> real `EmailOut` deliver one mail to the stub, From and To `email.address`, subject E1, text equal to the `DigestText` rendering for `email` of the stored `Digest.Data.Sent` Slots, header `X-OcuTalon-Ref` equal to a new `Delivery` row of channel `email`, Kind `digest`; the web chat copy still arrives.
- (needs O1) Given `digest.channels` = `email` alone, or `web,email` with demo mode on, when S's digest is composed, then the same mail is delivered.
- Given a second session T (not `email.owner`), when T's digest is sent, then the stub receives nothing and T's other channels are unchanged (second-session isolation).
- Given the browser as the README admin with mailbox and outgoing saved, when Settings > Daily digest is opened, then an "Email" box shows (and not before outgoing is saved), checking it and saving stores `...,email`, and "Send my digest now" delivers the mail to the stub; the LIVE fixture user's POST with `email` is 403 and changes nothing.
- Given the online demo, then no email box or channels show, Notify routes no digest to `EmailOut`, and an `EmailOut` reached directly sends nothing.
- Given a POP3 mail carrying the `X-OcuTalon-Ref` of a sent email, when `EmailIn` polls, then it makes no Item and records the mail seen; a mail with an unknown or forged Ref still becomes one untrusted Item (DW-1167).
- Given every catalog key, when rendered on `email`, then the text equals the `phone` text (render tests cover every key `EmailOut` sends).
- Given CI, then every digest email goes to the mock's SMTP stub (the test asserts the `SMTPServer` row is `mock` first).
- Given the finished diff, then no Lane A path or Never-list item appears and each contended touch is the one Design Notes names.

- (O1, DW-820) Given a composed digest and any `digest.channels` value (only `email`; `email` with a strict subset of the own channels; only the own channels; none), when `Digest.Process.Deliver` runs, then it hands the digest to Notify once, Notify routes it to exactly the channels `digest.channels` names that are available (email only through 21.7's rule), `Digest.Process.Own` and the direct sends no longer exist, and the existing web/phone/telegram digest tests still pass through Notify.

- (ruling O1) Given the web chat and Telegram digests (and the Simulated phone's), when they are delivered through Notify only, then each text is byte-identical to before and sent at the same moment (regression test per channel); "Send my digest now" e2e passes unchanged; `MESSAGENOCHANNEL` stays tested.
- (ruling V1) Given `EmailOut`'s digest path, then the recipient is always `email.address` and nothing passed in can change it; 21.6 (b), (c), (f), (g) hold on this path; the 11th digest email to a mailbox in one UTC day is refused, recorded and not sent.
- (ruling V4) Given an inbound mail, then `EmailIn` skips it only when its `X-OcuTalon-Ref` names a sent email `Delivery`, its From is `email.address`, and the Ref was not skipped before; each skip is traced with the Ref and no contents; any other mail is an untrusted item as before.
- (ruling V5) Given any `EmailOut` mail, then it carries a random `X-OcuTalon-Ref` of at least 120 bits, different on every send, never derived from a sequence, session or address.
- (ruling E1) Given a digest email, then its subject is "Your OcuTalon digest for {date}" in the chat heading's date format when the digest formats one, else "Your OcuTalon digest".

## Spec Change Log

- 2026-11-12 (lead, spec gate): Contest Planner rulings applied (`prompts/epic-21-rulings-217.md`): O1 accepted with conditions; V1 approved as the third path inside `EmailOut` with a 10-per-UTC-day cap; V2, V3, V6, V7 approved; V4 narrowed (sent Delivery + From is the own address + one use, each skip traced); V5 random Ref >= 120 bits on every mail; E1 dated if the chat heading formats a date; E2 approved; R1 conditional and after 0.26's README merge. Written as tasks and ACs. The intent gap is resolved; status reset to `ready-for-dev` per the re-dispatch protocol (the plan was otherwise complete; the lead validated it).

- 2026-11-12 (lead): O1 RULED by the orchestrator (one-time AD-33 Lane A exception for `Digest/Process.cls` and the Lane A tests that pin it; DW-820 routed to this story by=orchestrator, resolved-by this key at adjudication); written as a task and an acceptance criterion. The spec stays `blocked` until the Contest Planner rules V1-V7, E1, E2, R1 and S1-S5 (and O1 itself as a veto item); then reset per the re-dispatch protocol.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-32 (only `*Out` render, through the one renderer; digest = one Notification of `parts`/`lines`; Lane B owns `Catalog.Render` and adds channels), AD-14 (Notify the one outbound routing rule; `digest` only to `digest.channels`; each `*Out` records its `Delivery`; the Email sub-bullets of 21.2/21.6), AD-1 (only business operations send outbound channel traffic; the digest email is a Notification, not a command, so no origin and no `CommandsIn`), AD-19 (`digest.channels` written only by `SettingsOps`), AD-25 (online demo), AD-28 (no all-clear except from `Checks.Render`), AD-22 (mock), AD-33 (ownership: Notify, Functions, Catalog, `EmailIn`/`EmailOut`, `Delivery` are Lane B; `Digest.Process` Lane A). No AC contradicts an AD Rule; S1-S5 are additive. AD-14's own text names the dependency: "until a Lane A story routes every digest through Notify (DW-820)".

**Ownership item O1 (blocking).** Today `Digest.Process.Deliver` hands a digest to Notify only when the channels it narrows to (`Named`, which keeps only web, phone, telegram) equal the session's own (`Own`); otherwise it sends to each item directly, and with none of its three named it fails `MESSAGENOCHANNEL`. So `email` alone, or `email` beside a strict subset of the own channels (demo mode on, or Telegram paired), never reaches Notify and no email goes. DW-820's residual (owner `burndown`, "for a Lane A story", no key) is the fix: Digest hands every composed digest to Notify, whatever `digest.channels` names, and Notify alone routes kind `digest`. This story must not edit `Digest/**`, so it waits on that change (or on an AD-33 exception). See Auto Run Result.

**Integration ACs (Rule 1):** the first AC (real `SendDigest` -> Digest -> Notify -> `EmailOut` -> stub) and the browser AC. **Consumes:** 21.6 (`EmailOut`, `Sender`, SMTP stub, `IsAddress`, `ItemRunning`), 21.2 (`EmailIn`, adapter, `MailSeen`, POP3 stub, `email.address`/`email.owner`), 18.2 (Notify digest branch, `DigestNamed`, Daily digest section), 17.10 (`DigestText`), Lane A `Digest.Process` (unchanged) and O1's contract. **Consumed-by:** 24.3 (pages by email through `EmailOut`'s Notification path and the `email` renderer; it widens the accepted kinds), 22.7 (its tool and fix emails carry the header, and DW-1167's skip covers them).

**Extend, don't copy (Rule 2):** Notify's digest branch and `DigestNamed` are extended (one more name, one more rule) like the web chat's, phone's and Telegram's targets; `EmailOut.OnNotification` follows `SimPhoneOut`'s digest branch and reuses `DigestText.Text`; the `email` channel reuses `Build`'s `text` field exactly as `phone`; `EmailOut.Send` is widened, not copied, for the third path; `CommandsIn.ItemRunning` is reused (made public), not copied into Functions; the email box extends `digestChannelBoxes` and the stored-order rule; mock edits extend `smtp.mjs`/`mail.mjs`.

**Ledger (Rule 17):** DW-1167 addressed: Approach, matrix row "Own mail polled back", the `X-OcuTalon-Ref` header and `EmailIn` skip tasks, the DW-1167 AC, veto V4/V5. (Its acceptance bullet sits in `epics.md` under Epic 22's preamble, after "Story 22.1 moved", not under Story 21.7 -- for the lead to move.)

**Decided in-stage:** (1) The email box shows only when address and outgoing are both saved (sending needs SMTP); the server accepts `email` whether or not it shows, as it accepts `phone` with demo mode off, so a hidden choice is kept and never blocks a save. (2) Default `digest.channels` unchanged: email is opt-in. (3) Only the mailbox owner session's digest goes by email; other sessions' never (the 21.6 tool rule). An ended owner session gets no digest at all (21.2's ownership; unchanged). (4) A separate Notify rule, not 16 combined `when`s. (5) `DigestEmail` checks that `EmailOut` has an alive job, so no digest waits in a disabled item's queue (Task 0 c). (6) Subject is a fixed catalog text, no date, no all-clear; no body footer. (7) `Delivery`: Kind `digest`, DecisionRef, no text, no address. (8) One try; a failed email digest is not resent (Digest's resend covers only its own channels) and is logged. (9) Header name `X-OcuTalon-Ref`, value the `Delivery` ChannelMessageId (a random 22-character Ref), on every `EmailOut` mail; made before the send. (10) `SentByEmail` by SQL with no new index (Task 0 d). (11) `EmailOut` takes only Kind `digest` Notifications here. (12) No channel-slot display name for `email`. (13) CI placement: `Test.Channel.*` in `lane-a@Channel` (`production`), `Test.Core.Routing`, `Test.Core.SettingsSave`, `Test.Msg.Catalog` where they are (`lane-b@Contract,Core,Data,Live` in `image` or their current shard), e2e E6 in `email.spec.ts` (`live:sign-in-2`, `shards-4`); no new unit or group.

**Contended files (35.3 on `origin/OCT-epic35`; checked with `git diff origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic35`):** `Core/SettingsOps.cls` (35.3 +111 webhook lines; 21.7 the channels validation lines only), `Core/CommandsIn.cls` (35.3 +4 route/doc lines; 21.7 one keyword at :286), `Msg/Catalog/Core.cls` (35.3 entries near :728 and doc :3; 21.7 one entry at the XData's end, doc untouched), `Test/Msg/Catalog.cls` (35.3 key counts 140->143 / 220->223; the second to merge adds its +1), `web/src/app/settings/settings-view.ts` (35.3 doc :19 and a `webhooks` block after `channels`; 21.7 the `dailyDigest` block and the digest helpers), `web/scripts/ux-strings.test.mjs` (one row each). Not touched: `SecretHandoff.cls`, `Web/Api.cls`, `Production.cls`, `channels-section.ts`, `settings.spec.ts` (E6 lives in `email.spec.ts`). Feature's 23.7 and 22.8 change no file under `Digest/` or `Core/Rule/` (`git diff HEAD...origin/feature/OCT_OcuTalon_MVP` touches only `Msg/Catalog/Watch.cls` and two watch commands): integrate forward before implement, then recount the catalog keys.

**Spine S-items (additive, for the Planner):** S1 AD-14 digest bullet: Notify also routes kind `digest` to `EmailOut` when `digest.channels` names `email`, the session is `email.owner`, `email.address` is set, `EmailOut` has an alive job and it is not the online demo (`Functions.DigestEmail`, rule `DigestEmail`). S2 AD-14 Email sub-bullet: `EmailOut` also takes a Notification of kind `digest` -- recipient only `email.address`, only for `email.owner`, subject `email.digestSubject`, text `DigestText` for `email`, `Delivery` Kind `digest`; every `EmailOut` mail carries `X-OcuTalon-Ref` = its `Delivery` ChannelMessageId; `EmailIn` skips a mail whose header names an email `Delivery` row (DW-1167). S3 AD-32 renderer bullet: channels `web`, `phone`, `mailbox`, `telegram`, `email` (`email` = the `phone` rules). S4 AD-14 "As built in Story 18.2" bullet: `digest.channels` may name `email`, which Digest ignores; the email copy needs O1. S5 AD-22: the SMTP stub's state shows the mail's `X-OcuTalon-Ref`; POP3 fixtures take `headers`.

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| O1 | Ownership/dependency: 21.7 needs `Digest.Process` (Lane A) to hand every digest to Notify, whatever `digest.channels` names (DW-820 residual); 21.7 does not edit `Digest/**` | route DW-820's residual to a Lane A story that lands before 21.7's implement (alternative: AD-33 exception for 21.7, as for 17.10) | unchanged: demo digests keep their channels |
| V1 | Outward action, new `EmailOut` path (outside 21.6 ruling (a)'s two paths): a Notify `digest` Notification is emailed only to `email.address`, only for the `email.owner` session; no recipient in the message, no command, no approval | approve | never: no route, `EmailOut` disabled and refuses |
| V2 | Routing change: Notify's new rule adds `EmailOut` for kind `digest` (AD-14) | approve | `DigestEmail` is 0 |
| V3 | Stored data: `digest.channels` accepts `email`; `Delivery` rows channel `email` Kind `digest` (no text, no address), existing retention | approve | none written |
| V4 | Inbound filter (DW-1167): `EmailIn` makes no Item for a mail whose `X-OcuTalon-Ref` names an email `Delivery` row (recorded seen); unknown or forged Refs are items as before | approve | `EmailIn` disabled |
| V5 | A header on every `EmailOut` mail (tool, system, digest): `X-OcuTalon-Ref: <22-char Ref>` (no address, no session) | approve | nothing sent |
| V6 | Model-written text by email: the digest's guarded saved-for-later summary (<= 240 chars, slot-cleaned) goes to the own address, as it goes to Telegram | approve | nothing sent |
| V7 | `CommandsIn.ItemRunning` becomes public (no behaviour change); grants: none new | approve | n/a |

## Public text

Not in UX, PRD or epics:
- E1 subject of the digest email (`email.digestSubject`): "Your OcuTalon digest"
- E2 the Daily digest box label: "Email"
- R1 (only if the Planner wants a README line; findability) appended to 21.2's P3 "Your own mailbox" bullet: "With an outgoing mail server saved, Settings > Daily digest can also send your digest to that address."

Findability: no More to try item (email is off on the online demo). Reused: the digest's `digest.*`/`checks.*` texts, `SETTINGS_TEXTS` saved/failed, Send my digest now.

## Verification

Run every command from the worktree root. `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=implement'`; warm tag `e21s7iw`, fresh tag `e21s7i`. One command per foreground call (`timeout: 600000`), each sized to about 150 s; never two test runs in one message; one `iris_execute_tests` per message with `server` `ocutalon-slot-c` and `namespace` `OCUTALON`. A fresh `ci/warm.sh up` takes about 110-195 s by itself.

**Commands:**
- `<vars> OCUTALON_RUN_TAG=e21s7iw ci/warm.sh up` (once) -- ready.
- `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s7iw ci/iris.sh class OcuTalon.Test.Msg.Catalog` (loop) -- pass. mutation: `email` left out of `CHANNELS` -> red.
- `... class OcuTalon.Test.Core.Routing` (loop) -- pass. mutation: `DigestEmail` ignores the owner check -> `TestNotifyDigestTargets` red.
- `... class OcuTalon.Test.Channel.EmailOut` (loop) -- pass. mutation: `OnNotification` takes the recipient from anything but `email.address` / skips the owner check -> red; header not set -> red.
- `... class OcuTalon.Test.Channel.EmailIn` and `... EmailInPop3` (loop, one per call) -- pass. mutation: `In` skips on any non-empty `SentRef` -> forged-Ref case red.
- `... class OcuTalon.Test.Channel.EmailLive` (loop) -- pass. mutation: rule `DigestEmail` removed -> the Integration AC red.
- `... class` `OcuTalon.Test.Core.SettingsSave`, `OcuTalon.Test.Core.SettingsRunTime`, `OcuTalon.Test.Core.RoutingProduction`, `OcuTalon.Test.Core.CommandsStep4` (once each, one per call) -- pass (shared surfaces).
- `node --test ci/mock/test/` and `node --test web/scripts/` (once each) -- pass; `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` (once each) -- clean.
- `<vars> OCUTALON_RUN_TAG=e21s7i ci/iris.sh build` (once), then `<vars> OCUTALON_RUN_TAG=e21s7i ci/iris.sh live sign-in-2 --part k/n` for the part whose PART line lists `settings/email.spec.ts` (once; 21.6 used 13/15) -- pass. mutation: `emailShown` always false -> E6 red.
- `<vars> OCUTALON_RUN_TAG=e21s7iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s7i ci/iris.sh teardown` (once each, also after a failure).
- `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh` (once each) -- pass.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once) -- only the 10 baseline low `placeholder` findings.

**Shared surfaces:** Notify's digest targets (`Test.Core.Routing` `TestNotifyDigestTargets`, `TestRuleTargetsAreProductionItems`, `RoutingProduction`); the renderer's channel list and key counts (`Test.Msg.Catalog`); the `digest.channels` validation (`SettingsSave` pins `email` refused today); `DIGEST_CHANNELS` and the box list (`settings-view.test.mjs`, `ux-strings.test.mjs`, `settings.spec.ts` S10's boxes); `EmailOut`'s MessageMap and Send (`Test.Channel.EmailOut`, `EmailLive`); `EmailIn` intake (`EmailIn`, `EmailInPop3`, `EmailLive` POP3 cases); the mock's state shapes (`ci/mock/test/`). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

(Lead, 2026-11-12: the plan halted on the O1 intent gap; O1 and the gate items are ruled (Spec Change Log), so the spec is reset to ready-for-dev.)
