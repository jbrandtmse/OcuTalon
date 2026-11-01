# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane B work that was moved out of the demo path so it lands in 1.0.0. On local and IPM installs the page receives live events over a WebSocket, with polling as the silent fallback. A risky tool call's approval request reaches the simulated phone and the paired Telegram chat with Approve and Reject, and is edited in place when it is answered and when its result arrives. The README is completed for 1.0.0 so a judge can reach the online demo in two minutes, and the paired chat is shown to stay isolated per session under load. Epic 31 merges when it is done and ships in 1.0.0. The old merge gate on `v0.1.1` was dropped. The online demo still only polls.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject
- Story 31.3: The README leads to the demo, and the launched demo is measured
- Story 31.4: The paired chat stays isolated under load too

## Requirements & Constraints

- **Live delivery:** messages, notifications and approval results reach the page within 2 seconds. Other channels show an approval's result within 5 seconds. CI checks these bounds against the mock on every run; real-network timing is measured in the rehearsal and on the demo.
- **WebSocket scope:** the WebSocket serves local and IPM installs only. With the online-demo flag set, the page never opens it and only polls, because an open socket keeps its session, and so a licence connection, alive. If the socket closes or fails, the page switches to polling without showing anything and reconnects in the background. The "Reconnecting…" and "Can't reach OcuTalon" banners belong to Story 2.11, not to this epic.
- **Sign-out:** an open socket must stop sending frames within one loop after sign-out. Sign-out sets a server-side mark that each socket loop reads. The 60 s socket lifetime stays as a backstop (DW-457, ruling U-174).
- **Tool-call approvals:** they behave like fix approvals. The phone and the paired chat get buttons, first answer wins, and the message is edited in place on answer and on result.
- **Paired chat under load:** session A's incident, notification and approval reach only A's paired chat. A button press from B's chat on A's request is refused and changes nothing. No OCUTALON or OCUORDERS message body or header carries a paired chat's display name, user name, chat id or phone number.
- **README for 1.0.0:**
  - "Try it in two minutes" sits at the top, with the online demo link and a note that the sign-in details are on the splash screen.
  - It names the read-only Visual Trace account and says trace links on the demo open without a second sign-in.
  - It adds an IPM install section: the registry install first, then load-from-folder.
  - It describes only what 1.0.0 ships.
  - It keeps the BMAD Method and Claude Code credits and the not-affiliated note.
  - It is plain English, with no class names or error codes outside the developer sections, no private infrastructure details, and every link resolving.
  - It adds an MIT `LICENSE` with the holder line "Copyright (c) 2026 jbrandtmse" and a one-line licence credit.
  - It shows two screenshots (the demo-path page, and Visual Trace of one decision), each under 300 KB, with alt text and no secrets. They are captured by Playwright on a throwaway stack.
  - It adds steps to change the default IRIS passwords (DW-360).
- **About dialog and guide:** the About dialog gains the bridge guide and security overview links. The guide's finish state gains "Use the same bridge in your own production ↗".
- **Not a story criterion:** Story 31.3's measurement on the public online demo is a release check at 1.0.0, done by the author. No story waits for it.
- **Ledger items in scope:** DW-457, DW-397, DW-497, DW-530 (only at no date cost; otherwise re-owned to the first daily release after 1.0.0), DW-360, DW-416, DW-432, DW-474, DW-446, DW-237 and DW-485.

## Technical Decisions

- **The live-event contract:**
  - `OcuTalon.Live.Event` rows hold a per-stream `Seq`, and are written only by `Live.Publish` after commit.
  - The browser envelope is `{seq, stream, ts, type, payload}`, where stream is `session` or `instance`.
  - Payloads are full entity views keyed by `Ref`, never deltas.
  - The page loads `GET /api/v1/state`, then follows per-stream cursors. It applies events idempotently and reloads the snapshot when a stream's `Seq` skips.
  - WebSocket and polling must go through the same apply path.
- **The WebSocket server:**
  - It is `/ocutalon/OcuTalon.Web.Live.cls`, a `%CSP.WebSocket` class.
  - It checks `Origin` before it accepts, serves only a signed-in session, and waits on the session's `$SYSTEM.Event` resource and one instance resource. `Live.Publish` signals both after each commit.
  - It sends events after the client's cursors.
  - The `/ocutalon` shell (`OcuTalon.Web.Public.Shell`) forwards the WebSocket, or the WebSocket gets its own application; the story decides. Ruling U-175 points 31.1 at the shell route now that Epic 29 has merged.
  - Trace URLs are added by `OcuTalon.Web.TraceLink` on every live path.
- **The web applications:** `/ocutalon` and `/ocutalon/api` share one CSP session and one sign-in group (`OcuTalon`). Strict session scope, no CORS.
- **The notification contract:**
  - Every non-reply outbound message is an `OcuTalon.Msg.Notification` carrying `SessionRef`, `Kind`, `CatalogKey`, `Slots`, `ApprovalRef`, `IncidentRef` and `DecisionRef`.
  - Producers never render text. Only the `*Out` operations render, through `OcuTalon.Msg.Catalog.Render`.
  - Approve and Reject buttons appear only for kinds `incident` and `approval` when `ApprovalRef` is set.
- **Who sends approval notices:**
  - `BridgeSink` (Lane B) is the only class that turns bridge HostSink events (`approval.raised`, `approval.answered`, `approval.result` and the rest) into `Live.Publish` calls.
  - For kind `tool_call` (and, from step 4, a fix with no incident), `BridgeSink` sends `approval`, `answered` and `result` Notifications through the adapterless `NoticesIn` service. Each carries `ApprovalRef`, with an empty `IncidentRef`.
  - For kind `fix`, `IncidentManager` sends these notices, carrying both refs.
  - `setting` requests send their own notices, so `BridgeSink`'s rules don't change.
  - `BridgeSink` sends asynchronously and never waits on a lock for more than 1 s. The bridge wraps `OnEvent` and never fails its caller.
  - HostSink payloads carry the public `Ref`. `BridgeSink` reads the row through the ownership API.
- **Approvals:**
  - `ApprovalRequest` state changes only through the `OcuTalon.Bridge.Approval` API, under a per-`Ref` lock.
  - Telegram presses resolve through `AnswersIn` using `ChatRef`, never a chat id. `AnswersIn` returns result codes such as `already_answered`, `not_visible` and `unknown`.
- **Session ownership:**
  - Every per-person record carries `SessionRef`.
  - Telegram identity lives only in the `Pairing` row, and production messages refer to a chat only by `ChatRef`.
  - An online-demo sign-out runs `SessionOps.End`, which removes the pairing, cancels reminders, stops watches and cancels pending approvals.
- **Ownership rules:** only the owning lane edits a class. `BridgeSink`, `NoticesIn`, `Web.SessionEvents`, `Data.Session` and `Data.Pairing` are Lane B's. `WatchOps`, the Telegram channel, the bridge guide (Story 13.3), the security overview (Story 14.2) and `docs/install-ipm.md` (Story 15.2) are Lane A's.
- **Reuse:** `Pairing.HashCode` must delegate to `Session.Hash` rather than add a second SHA-256 base64url helper (DW-237).

## UX & Interaction Patterns

- If live updates are interrupted, the page falls back to polling with nothing shown. The banners after 10 s and 30 s are Story 2.11's, and they must keep working with the socket present.
- Live events carry chat messages, decisions, notifications, incident and approval changes, checks, reminders, pairing, status conditions, the reset schedule and guide state. Guide state is derived on the server only.
- The About dialog's links, in order: README, bridge guide, security overview. The guide's finish state lists "Use the same bridge in your own production ↗", which opens in a new tab.
- Stacked-header overflow (DW-530): above a quarter of the viewport, the header scrolls with the page, or the Demo view switch moves into a menu below 1024px, whichever is cheaper.

## Cross-Story Dependencies

- **Story 31.1:** needs Epic 16 (done) and Epic 29 (now merged; the shell route and `Data/Session.cls` were contended). DW-457 stays in this story unless another open epic holds `Data/Session.cls` at re-plan.
- **Story 31.2:** needs Epic 6 (done), Epic 16 (done; Story 16.9's `BridgeSink`) and Epic 30 (backlog). Story 30.3 supplies the real `approval.result` from the tool-call replay. Until it merges, tests call `BridgeSink.OnEvent` with fixture `approval.*` events of kind `tool_call`.
- **Story 31.3:** needs Lane A's Epics 12 to 15 merged (all backlog): the Telegram channel and Stories 13.3, 14.2, 15.2 and 15.3. It then turns on Story 16.4's and Story 16.9's Telegram cases (`WatchOps` stopping a signed-out session's watches; an approval that completes while both caps hold).
- **Story 31.4:** needs Epic 12 (backlog) and Story 29.4 (merged). It turns on Story 29.4's paired-chat cases.
