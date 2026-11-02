# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane B pieces that were moved off the demo path, so they ship in 1.0.0. On a local or IPM install the page receives live events over a WebSocket, with polling as the fallback and as the only path on the online demo. A risky tool call's approval request reaches the simulated phone and the paired Telegram chat with Approve and Reject, edited in place when answered and when its result arrives, and also appears in the web chat as a card answered once across every copy. The page shows a resend that stopped partway correctly. The README leads a judge straight to the online demo and covers what 1.0.0 ships. Epic 31 merges when done, with no tag gate. For 1.0.0 it merges with Stories 31.1, 31.2, 31.5 (all done), 31.6 and 31.3. Story 31.4 (paired-chat isolation under load) is deferred to the first daily release after the v1.0.0 tag and re-opens the epic then.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs (done)
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject (part 1: stopped-partway result band, tool-call note to the next turn, layout fixes) (done)
- Story 31.3: The README leads to the demo, and the launched demo is measured
- Story 31.4: The paired chat stays isolated under load too (deferred until after the v1.0.0 tag)
- Story 31.5: A tool call's approval request reaches the phone with Approve and Reject (notices) (done)
- Story 31.6: A tool call's approval request appears in the web chat with Approve and Reject (card)

## Requirements & Constraints

- **Live updates:** messages, notifications and approval results reach the page within 2 seconds. CI checks the bound against the mock; the rehearsal measures it for real. If the socket closes or fails, the page switches to polling silently and reconnects in the background.
- **Approvals, every copy:** the web chat, the simulated phone and the paired chat all have inline Approve and Reject. The first answer wins across every copy, and a late press is refused. A tool call's request reads "Run {tool} on {server}" ("Run {tool}" when the server is unknown). Its inputs go through the redactor on one line, capped at 200 characters and ending in "…" when cut. The phone and the web chat use the same texts. The result arrives as a new message with no buttons.
- **Web card texts come from one place:** the card takes its first line and inputs from `BridgeSink`'s `ServerOf`/`InputsOf` helpers, made reachable for the card. Never write a second implementation, so the phone and card texts cannot drift.
- **After a page reload:** an answered, expired or finished tool-call card must not look pending. It shows no buttons and no "awaiting approval" label, badge or colour. A test pins this. The full answered line after a reload (`/state` serving answered tool-call requests) is out of scope and routed to after 1.0.0.
- **Held tool calls:** the plain-English reason for an old held tool call reaches the approval card and the result notice in the web chat as well. The phone, paired-chat and live-event half is already done.
- **Telegram buttons** carry the unguessable approval `Ref`. A press from any chat other than the paired one changes nothing. Until Story 31.4 lands, the public demo keeps Telegram pairing off through host configuration.
- **Secrets:** keys, tokens and passwords never appear in the page, logs, screenshots or the repository. The only exception is the README account's password, which the README shows.
- **README (1.0.0):** opens with "Try it in two minutes", the demo link, a note that sign-in details are on the splash, and the read-only Visual Trace account (trace links open it without a second sign-in). Its IPM section, taken from `docs/install-ipm.md`, gives the registry install (`zpm "install ocutalon"`) first and load-from-folder second. It explains how to change the default IRIS accounts' passwords in the Management Portal, keeps the BMAD Method and Claude Code credits and the not-affiliated note, and uses plain English outside the developer sections. It claims only what 1.0.0 ships, has only links that resolve and names no private infrastructure. It adds the MIT `LICENSE` ("Copyright (c) 2026 jbrandtmse") with its README line, and two screenshots in `docs/images/` (each under 300 KB, with alt text, captured by a Playwright spec on a throwaway stack). `docker/tests/test-readme.sh` pins all of these.

## Technical Decisions

- **One live-event model:** events are written only through `Live.Publish`, after the publisher's commit, in the envelope `{seq, stream, ts, type, payload}`, where each payload is the entity's full public view. Polling is the base contract. The WebSocket (`/ocutalon/OcuTalon.Web.Live.cls`, never opened with the online-demo flag set) uses the same envelope, cursors and idempotent client apply path. Each live-event type has one publisher.
- **Approvals:** the `ApprovalRequest` row is the truth, changed only through the `OcuTalon.Bridge.Approval` API. Answers from REST and Telegram go synchronously through `AnswersIn`. The session is resolved on the server only (`OcuTalon.Data.Ownership`); no endpoint accepts a `SessionRef`.
- **Notification ownership:** for kind `tool_call`, `OcuTalon.Core.BridgeSink` turns `approval.raised`, `approval.answered` and `approval.result` into `Notification`s of kinds `approval`, `answered` and `result`. They go through the adapterless `NoticesIn`, each carrying `ApprovalRef`, with `IncidentRef` empty. For kind `fix`, `IncidentManager` does this. `BridgeSink` is the only class that turns bridge events into `Live.Publish` calls. Story 30.3's real `approval.result` has merged, so the replay path is live.
- **Web notice cards:** `WebChatOut` is the only `notification` publisher. It keeps each web card on its `Delivery` row, and `FindByApproval` finds a card by approval `Ref`, channel and owner.
- **Rendering:** producers never render text. Only `*Out` operations do, through `OcuTalon.Msg.Catalog.Render(key, slots, channel)`, and they add Approve and Reject only for kinds that have an `ApprovalRef`. Story 31.6 reuses Story 31.5's catalog keys and texts.

## UX & Interaction Patterns

- Answered and result notices edit the original approval message on the phone and in Telegram. In the web chat, the tool-call result is a new message with no buttons.
- Answered statuses: "Approved from {channel} at {time}", "Rejected from {channel} at {time}. Nothing was changed.", "Expired at {time}. Nothing was changed." The press that lost the race gets "Already answered: approved from {channel} at {time}." Within 5 seconds every copy shows the answer. On the page, a status line has no final period unless it holds two sentences.
- The About dialog gains links to the bridge developer guide and the security overview. The demo guide's finish state gains "Use the same bridge in your own production ↗".

## Cross-Story Dependencies

- **31.6** follows 31.5 (done) and reuses its notices, texts and catalog keys. It depends on Epics 6, 16 and 30, all merged.
- **31.3** needs Epics 12 to 15 merged: the Telegram channel, the guide paths from Stories 13.3 and 14.2, and `docs/install-ipm.md` from Story 15.2 (in the order Story 15.3's guide uses). It turns on the Telegram cases of Stories 16.4 and 16.9 and their real Lane A paths. The measurement after launch is a 1.0.0 release check that the Contest Planner runs on the public demo host; no story waits on it.
- **31.4** needs Epic 12 and Story 29.4 merged. It is deferred until after the v1.0.0 tag, together with its ledger items.
- Stories 39.5 and 41.5 in later epics wait for Epic 31 to merge.
