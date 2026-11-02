# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic finishes the Lane B parts of the demo-path stories that were held back so the demo path could ship first. It does four things. Local and IPM installs get live events pushed over a WebSocket, with polling as the silent fallback. A risky tool call's approval request reaches the simulated phone and the paired Telegram chat with Approve and Reject, and that message is edited in place when the request is answered and when its result arrives. The README becomes the judge's 1.0.0 entry point. The paired Telegram chat is proven isolated between online-demo sessions under load. Every part lands before 1.0.0. Epic 31 merges when it is done and ships in 1.0.0; there is no `v0.1.1` gate any more.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject
- Story 31.3: The README leads to the demo, and the launched demo is measured
- Story 31.4: The paired chat stays isolated under load too

## Requirements & Constraints

- **Live updates:** messages, notifications and approval results reach the page within 2 seconds. Other channels show an approval's result within 5 seconds. CI checks both bounds against the mock, and the rehearsal measures them over real networks (19 of 20 runs).
- **Polling stays the contract:** it is the shared live path and must keep working on its own. The WebSocket is only an enhancement. With the online-demo flag set, the page never opens the WebSocket, because an open socket keeps a CSP session, and so a licence connection, alive with no timeout.
- **Socket fallback:** if the socket closes or fails, the page switches to polling silently and reconnects in the background. The existing reconnecting banners (info at 10 s, danger at 30 s) are unchanged.
- **Sign-out must stop the socket:** an open socket must send no further frame within one loop after sign-out. Use a server-side mark that the sign-out sets and each socket loop reads, and keep the 60 s socket lifetime as a backstop.
- **Approvals (tool calls):**
  - Each request offers inline Approve and Reject, and the first answer wins.
  - Other channels then show who answered and from where, and their buttons stop working.
  - Buttons carry an unguessable approval reference, never a sequential number.
  - A press from any chat other than the paired chat is refused and changes nothing.
- **Isolation:** one session's incident, notification or approval request never reaches another session's paired chat. No OCUTALON or OCUORDERS message body or header may carry a Telegram display name, user name, chat id or phone number; messages use only an internal `ChatRef`.
- **README (1.0.0):**
  - "Try it in two minutes" is at the top, with the online demo link and a note that the sign-in details are on the splash screen.
  - It names the read-only Visual Trace account.
  - It has an IPM install section that gives the registry install (`zpm "install ocutalon"`) first and loading from a folder second.
  - It adds the MIT `LICENSE` with the holder line "Copyright (c) 2026 jbrandtmse" and the licence line under "Credits and licences".
  - It shows two screenshots in `docs/images/`, each under 300 KB and with alt text, captured by Playwright.
  - It is plain English, keeps the BMAD Method and Claude Code credits and the not-affiliated note, claims nothing that 1.0.0 doesn't ship, names no private infrastructure detail, and every link resolves.
  - `docker/tests/test-readme.sh` pins the README's required content.
- **Release check, not story work:** measuring the launched demo on the public host is a 1.0.0 release check run by the Contest Planner. No story waits for it.

## Technical Decisions

- **Live event envelope:** `{seq, stream, ts, type, payload}`. There is one cursor per stream (`session`, `instance`), and payloads are full entity views keyed by a public `Ref`.
  - The client applies events idempotently and reloads the snapshot when a stream's `seq` skips.
  - The WebSocket must feed the same apply path as polling, so the two cannot drift apart.
  - Rows are written only through `OcuTalon.Live.Publish`, after commit.
- **WebSocket server:** `/ocutalon/OcuTalon.Web.Live.cls`, a `%CSP.WebSocket`.
  - It checks `Origin` before it accepts and serves only a signed-in session.
  - It waits on the session's `$SYSTEM.Event` resource plus one instance resource, which `Live.Publish` signals after each commit, and sends events that come after the client's cursors.
  - The `/ocutalon` shell either forwards the socket or the socket gets its own application; the story decides which.
  - Web and REST code may write only the session row, sign-in and sign-out effects, pairing-code hashes and UI-only markers.
- **Tool-call notices:**
  - The bridge reports `approval.raised`, `approval.answered` and `approval.result` to the HostSink. `OcuTalon.Core.BridgeSink` is the only place that turns these into `Live.Publish` calls. For approvals of kind `tool_call`, it also sends `Notification`s of kinds `approval`, `answered` and `result` through the adapterless `NoticesIn` service.
  - Each of these notifications carries `ApprovalRef`, with `IncidentRef` empty for a tool call.
  - For kind `fix`, `IncidentManager` sends the notices, not `BridgeSink`.
  - `BridgeSink` sends asynchronously and never waits on a lock for longer than 1 s. The bridge wraps every `OnEvent` call and never fails its caller.
  - `*Out` operations render only through `OcuTalon.Msg.Catalog.Render`, and add Approve and Reject for kinds `incident` and `approval` when `ApprovalRef` is set.
  - In-place edits find their message with `Data.Delivery.FindByApproval(approvalRef, channel, ownerRef)`. There is one delivery row per session copy, and a Telegram row's id is `<ChatRef>:<message_id>`.
- **Answers:**
  - `AnswersIn` resolves the answering session server-side: from the CSP session for the web and the phone, and from the press's `ChatRef` through the live `Pairing` for Telegram.
  - It returns result codes: `approved`, `rejected`, `already_answered`, `expired`, `not_paired`, `not_visible` and `unknown`.
  - The approval row is the truth, and its state changes only through the `OcuTalon.Bridge.Approval` API.
- **Ownership:** this epic works only in Lane B's files: `OcuTalon.Web`, `.Core`, `.Live`, `.Msg`, `.Data.*` (except bridge data), `web/` (except the rail's Telegram card and `web/e2e/demo-path/telegram-*.spec.ts`), `docker/`, most of `ci/` and the README.
  - `docs/install-ipm.md`, the bridge guide, the security overview and `release/` are Lane A's. Read them, don't edit them.
  - Owned rows carry `SessionRef` or `OwnerRef`.
  - On an online-demo sign-out, `SessionOps.End` cancels the session's pending approvals and removes its pairing.

## UX & Interaction Patterns

- The WebSocket fallback is invisible. Only the existing reconnecting banners speak, and missed content loads into place on recovery.
- An approval message on the phone or in Telegram is edited in place to show who answered, from where and when (for example "Approved from Telegram at 14:15"), and later its result.
- The About dialog gains links to the bridge developer guide and the security overview.
- The demo guide's finish state gains "Use the same bridge in your own production ↗", which opens in a new tab with the ↗ hidden from assistive technology.
- Layout fixes are optional and only if they cost no time:
  - DW-530: the stacked header must not stick past a quarter of the viewport height.
  - DW-542: the finish state at 640px wide.
  - DW-543: the welcome heading at 1280x800.

## Cross-Story Dependencies

- **Story 31.1:** needs Epic 16 merged, because Stories 16.3 and 16.4 changed the live client and the session handling.
- **Story 31.2:**
  - It extends Epic 6's approval notices and Story 16.9's `BridgeSink`.
  - It needs Epic 30 merged, for Story 30.3's real `approval.result` from the tool-call replay. Otherwise its tests call `BridgeSink.OnEvent` with fixture `approval.*` events of kind `tool_call`.
- **Story 31.3:**
  - It needs Epics 12 to 15 merged: Telegram, the bridge guide (13.3), the security overview (14.2) and `docs/install-ipm.md` (15.2/15.3).
  - It turns on Story 16.4's and Story 16.9's Telegram cases and their real Lane A paths.
- **Story 31.4:** needs Lane A's Epic 12 and Epic 29 merged. It turns on Story 29.4's paired-chat isolation cases.
