# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane B pieces that were moved off the demo path, so they ship in 1.0.0. On a local or IPM install the page receives live events over a WebSocket, with polling as the fallback and as the only path on the online demo. A risky tool call's approval request reaches the simulated phone and the paired Telegram chat with Approve and Reject, edited in place when answered and when its result arrives, and also appears in the web chat as a card answered once across every copy. The page shows a resend that stopped partway correctly. The README leads a judge straight to the online demo and covers what 1.0.0 ships. Epic 31 merges when done, with no tag gate. For 1.0.0 it merges with Stories 31.1, 31.2, 31.5, 31.6 and 31.3. Story 31.4 (paired-chat isolation under load) is deferred to the first daily release after the v1.0.0 tag and re-opens the epic then.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject (part 1: stopped-partway result band, tool-call note to the next turn, layout fixes)
- Story 31.3: The README leads to the demo, and the launched demo is measured
- Story 31.4: The paired chat stays isolated under load too (deferred until after the v1.0.0 tag)
- Story 31.5: A tool call's approval request reaches the phone with Approve and Reject (notices)
- Story 31.6: A tool call's approval request appears in the web chat with Approve and Reject (card)

## Requirements & Constraints

- **Live updates:** messages, notifications and approval results reach the page within 2 seconds. CI checks the bound against the mock; the rehearsal measures it for real. If the socket closes or fails, the page switches to polling silently and reconnects in the background. The existing reconnect banners (10 s info, 30 s danger) stay unchanged.
- **Approvals:** every copy (web chat, simulated phone, paired chat) has inline Approve and Reject; the first answer wins across every copy, and a late press is refused. A tool call's request reads "Run {tool} on {server}" ("Run {tool}" when the server is unknown). Its inputs go through the redactor on one line, capped at 200 characters and ending in "…" when cut. The phone and the web chat use the same texts. The result arrives as a new message with no buttons.
- **After a page reload** (Story 31.6), an answered, expired or finished tool-call card must not look pending: no buttons and no "awaiting approval" label, badge or colour. A test pins it. The full answered line after a reload is out of scope (routed to after 1.0.0).
- A held tool call's plain-English reason reaches the approval card and the tool-call notices, not only the decision live event.
- **Telegram buttons** carry the unguessable approval `Ref`. A press from any chat other than the paired one changes nothing. Until Story 31.4 lands, the public demo keeps Telegram pairing off through host configuration.
- **Secrets:** keys, tokens and passwords never appear in the page, logs, screenshots or the repository; the README account's password is the only exception, where the README shows it.
- **README (1.0.0):** opens with "Try it in two minutes", the demo link, a note that sign-in details are on the splash, and the read-only Visual Trace account. Its IPM section gives the registry install first and load-from-folder second. It covers changing the default IRIS accounts' passwords, keeps the BMAD Method and Claude Code credits and the not-affiliated note, is plain English outside developer sections, claims only what 1.0.0 ships, has only resolving links and names no private infrastructure. It adds the MIT `LICENSE` ("Copyright (c) 2026 jbrandtmse") with its README line, and two screenshots in `docs/images/` (under 300 KB each, with alt text, captured by a Playwright spec). `docker/tests/test-readme.sh` pins all of these.
- **Layout fixes in Story 31.2** (the stacked sticky header within a quarter of the viewport, the guide's finish state at 640 px, the empty chat at 1280x800) go into 1.0.0 only if they cost Epic 31 no time; otherwise they are re-owned to after 1.0.0.

## Technical Decisions

- **One live-event model:** events are written only through `Live.Publish`, after the publisher's commit, in the envelope `{seq, stream, ts, type, payload}`, each payload the entity's full public view. Polling is the base contract; the WebSocket uses the same envelope, cursors and idempotent client apply path. Each live-event type has one publisher.
- **WebSocket:** `/ocutalon/OcuTalon.Web.Live.cls` (`%CSP.WebSocket`). It checks `Origin` before accepting, serves only a signed-in session, and waits on the session's `$SYSTEM.Event` resource plus one instance resource that `Live.Publish` signals after each commit. With the online-demo flag set the client never opens it. Sign-out sets a server-side mark each socket loop reads, so no frame is sent more than one loop after sign-out; the 60 s socket lifetime stays as a backstop.
- **Approvals:** the `ApprovalRequest` row is the truth, changed only through the `OcuTalon.Bridge.Approval` API. Answers from REST and Telegram go synchronously through `AnswersIn`; the session is resolved server-side only (`OcuTalon.Data.Ownership`; no endpoint accepts a `SessionRef`).
- **Notification ownership:** for kind `tool_call`, `OcuTalon.Core.BridgeSink` turns `approval.raised`, `approval.answered` and `approval.result` into `Notification`s of kind `approval`, `answered` and `result`, sent through the adapterless `NoticesIn`, each carrying `ApprovalRef` with `IncidentRef` empty. For kind `fix`, `IncidentManager` does it. `BridgeSink` is the only class turning bridge events into `Live.Publish` calls. Story 30.3's real `approval.result` has merged, so the replay path is live.
- **Web notice cards:** `WebChatOut` is the one `notification` publisher; it keeps each web card on its `Delivery` row, and `FindByApproval` finds a card by approval `Ref`, channel and owner.
- **Rendering:** producers never render text; only `*Out` operations do, through `OcuTalon.Msg.Catalog.Render(key, slots, channel)`, adding Approve and Reject only for kinds with an `ApprovalRef`.
- **Approved tool calls:** `Conversation` adds a code-written `SystemNote` (the tool, done or failed, and the time; never the result text) to the next turn only.
- **Result band:** when a request's `unreached` is above 0, the page shows `result.stoppedPartway` (or its count-of-one form), picked in the server's `Watch.Notice.ResultKey` order, never `result.skipped`. A resend still running after FixExecutor's 60 s wait shows the card's still-resending line and no result band.

## UX & Interaction Patterns

- Answered and result notices edit the original approval message on the phone and in Telegram; in the web chat the tool-call result is a new message with no buttons.
- The About dialog gains the bridge developer guide and security overview links; the demo guide's finish state gains "Use the same bridge in your own production ↗".
- Below 1024 px wide, the sticky header must stay within a quarter of the window's height.

## Cross-Story Dependencies

- **31.1** needs Epic 16 merged. It adds the sign-out mark to `Data/Session.cls`; if another open epic holds that file, the mark stays a ledger entry due before 1.0.0.
- **31.2 → 31.5 → 31.6:** split in sequence. 31.5 owns the phone and paired-chat notices; 31.6 follows it and reuses its notices, texts and catalog keys. They depend on Epic 6, Epic 16 (`BridgeSink`) and Epic 30 (merged).
- **31.3** needs Epics 12 to 15 merged: the Telegram channel, guide paths from Stories 13.3 and 14.2, and `docs/install-ipm.md` from Story 15.2 (order as in Story 15.3's guide). It turns on Stories 16.4's and 16.9's Telegram cases. The post-launch measurement is a 1.0.0 release check the Contest Planner runs; no story waits on it.
- **31.4** needs Epic 12 and Story 29.4 merged; deferred until after the v1.0.0 tag with its ledger items.
- Stories 39.5 and 41.5 (later epics) wait on Epic 31 merging.
