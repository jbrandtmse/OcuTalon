# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 31 holds the Lane B work that was moved off the demo path. Stories 31.1, 31.2, 31.3, 31.5, 31.6 and 31.7 shipped in 1.0.0: the WebSocket for live events, tool-call approvals on every channel, the 1.0.0 README and the unpair fix on the Telegram card. Epic 31 merged with only Story 31.4 still in backlog, and it now re-opens under SC-5 for that last story. Story 31.4 turns on Story 29.4's paired-chat cases. On the online demo, a judge's paired Telegram chat gets only that judge's incidents, notifications and approval requests. A button press from another visitor's paired chat answers nothing. No Telegram identity reaches any production message. Until 31.4 lands, the public demo runs with Telegram pairing turned off. Once it is in place, Telegram can be switched on for the demo host. 31.4 ships in the first daily release after the v1.0.0 tag.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs (done)
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject (part 1) (done)
- Story 31.3: The README leads to the demo, and the launched demo is measured (done)
- Story 31.4: The paired chat stays isolated under load too (this re-open)
- Story 31.5: A tool call's approval request reaches the phone with Approve and Reject (notices) (done)
- Story 31.6: A tool call's approval request appears in the web chat with Approve and Reject (card) (done)
- Story 31.7: After an unpair, the Telegram card shows its fresh code without a gap (done)

## Requirements & Constraints

- **What 31.4 turns on:** Story 29.4's paired-chat cases already exist and are switched off. They run against 0.1.1's Telegram channel on a test stack that has the online-demo start values, the CI model mock and mocked Telegram. Two browsers sign in with the same demo account, and each watches the Orders production.
- **Routing:** when session A presses Break the feed, A's incident, notification and approval request reach only A's paired chat. B's paired chat gets none of them.
- **Answers:** B's paired chat may press a button on A's approval request. That press is refused with a short reply and changes nothing. A can still answer from any of A's channels, and the first answer wins across every copy.
- **No identity in messages:** the paired mock chat's display name, user name, chat id and phone number are known to the test. Search every OCUTALON and OCUORDERS message body and header from the run: none of those values may appear, and neither may the visitor's IRIS user name. Production messages carry only the `SessionRef` and the internal chat reference, which is what the shared Visual Trace shows.
- **Secrets:** model keys and bot tokens come only from environment variables. They never appear in the web app, Visual Trace, logs, audit entries, release files or the repository.
- **Ledger entries owned by 31.4** (settle each at story time):
  - DW-237: `Pairing.HashCode` should call `Session.Hash` rather than keep its own SHA-256 base64url helper.
  - DW-474: the key-proof walk in `Test.Web.SessionEvents.ReferenceHits` gets Story 30.1's `$List` decode, plus any stream-chunk decode its measurement calls for.
  - DW-450: `Test.Eval.KeyProof` Walk copies the same global walk. It should share one helper with `ReferenceHits`.
  - DW-446: the probe reports healthy even when every turn is an error fallback, because degraded covers only `no_key`, `timeout` and `rate_limited`.
  - DW-485: `release/demo-host-check.sh` needs a check that a hyperevent-shaped POST (dummy `WARGC`, `WEVENT`, `WARG_1`) to each trace application's `%CSP.Broker.cls` gets neither the block status nor the block mark.
  - DW-511: `Test.Data.PublicSettings:TestNextReset` uses the assertion form `x ] y_"Z"`, which also passes in the very second the time is reached. Story 30.6's assert-concat rule allow-lists that line by name.
- **Public text:** 1.0.0's rule still holds: nothing public claims Telegram, pairing or phone approvals on the online demo, or paired-chat isolation under load, until this story lands. Changing any public wording is not one of this story's criteria. Never write "from your phone".

## Technical Decisions

- **Session ownership:** `OcuTalon.Data.Session` owns every per-person record, including the pairing. Production messages carry the `SessionRef`, never a user name, chat id or display name. A Telegram identity lives only in its `Pairing` row. Messages refer to a chat only by that row's `Ref` (`ChatRef`, on `Notification` and `Outbound`). The display name may reach the session's own page (`/state` and the `pairing` live event), never a production message.
- **One live pairing per chat:** a new pairing replaces the old one, and every change publishes a `pairing` event to each session whose state changed. Pairing codes are stored only as hashes and appear in no message, log, live event or audit entry. Both lanes hash through `OcuTalon.Data.Pairing.HashCode`.
- **Answering from Telegram:** `TelegramIn` calls `AnswersIn` synchronously with channel `telegram`, the approval `Ref`, the action and the press's `ChatRef`. `AnswersIn` resolves the session through the chat's live `Pairing` row and applies the ownership rules against the row's `OwnerRef`. It returns a result code, such as `not_visible` for another session's request, `not_paired`, `already_answered`, `expired` or `unknown`. The row changes state only through the `OcuTalon.Bridge.Approval` API, under its lock.
- **Recipients:** `OcuTalon.Data.Session.Recipients(ownerRef, incidentRef)` is the one resolver of notice recipients, shared by `IncidentManager`, `BridgeSink` and `AnswersIn`. REST reads and commands go through `OcuTalon.Data.Ownership`, and no endpoint accepts a `SessionRef` from the client.
- **Demo-host switch:** the public setting `telegramIncluded` is `1` only when `Telegram.In.Included()` returns 1 and a bot token is set on that start. `Install.Step.Public` writes it on every start, and only the online demo's splash reads it. Turning Telegram on for the demo is host configuration (setting the token), not a code change.
- **Lanes and footprint:** Epic 31 works in Lane B's files. These are Lane A's: `OcuTalon.Channel.Telegram`, the rail's Telegram card, `web/e2e/demo-path/telegram-*.spec.ts`, the Telegram mock scenarios under `ci/mock/scenarios/A/`, and `release/`. Under the Epic 29 exception, Lane B could change Story 29.4's load test and Story 29.3's host check in `release/`, but that exception belonged to Epic 29. The plan must therefore settle DW-485's footprint in `release/`.

## Cross-Story Dependencies

- 31.4 depends on Epics 12 and 29, both merged. Story 29.4 holds the paired-chat cases that 31.4 turns on. Story 31.5's tool-call notices already reach the paired chat.
- Epic 31 was part-merged for 1.0.0 with 31.4 in backlog. The epic is done, and merges again, once 31.4 is done. 31.4 ships in the first daily release after the v1.0.0 tag.
- Until 31.4 lands, the Contest Planner keeps Telegram pairing off on the public demo through host configuration.
