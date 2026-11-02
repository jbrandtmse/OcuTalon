# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane B pieces that were moved off the demo path, so they ship in 1.0.0. On a local or IPM install the page receives live events over a WebSocket, with polling as the fallback and as the only path on the online demo. A risky tool call's approval request reaches the web chat, the simulated phone and the paired Telegram chat with Approve and Reject, and is edited in place when it is answered and when its result arrives. The page shows a resend that stopped partway correctly. The README leads a judge straight to the online demo and covers what 1.0.0 ships. Epic 31 merges when done; there is no tag gate. For 1.0.0 it merges with Stories 31.1, 31.2, 31.5 and 31.3. Story 31.4 (paired-chat isolation under load) is deferred to the first daily release after the v1.0.0 tag and re-opens the epic then.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject (part 1: stopped-partway result band, tool-call note to the next turn, layout fixes)
- Story 31.3: The README leads to the demo, and the launched demo is measured
- Story 31.4: The paired chat stays isolated under load too (deferred until after the v1.0.0 tag)
- Story 31.5: A tool call's approval request reaches the phone with Approve and Reject (notices)

## Requirements & Constraints

- **Live updates:** messages, notifications and approval results reach the page within 2 seconds, and other channels show an approval's result within 5 seconds. CI checks these bounds against the mock on every run, and the clean-machine rehearsal measures them for real. If push is unavailable, the page falls back to polling without telling the user.
- **Reconnect banners already exist** and must keep working unchanged with the WebSocket. After 10 s with no answer, a closable info banner appears. At 30 s an unclosable danger banner replaces it. Missed content loads on recovery.
- **Approvals:** every request appears in the web chat, on the simulated phone and in the paired chat with inline Approve and Reject. The first answer wins across every copy, and the other copies show who answered, from where and when. A late press gets a short "already answered" reply. A tool call's request reads "Run {tool} on {server}" ("Run {tool}" when the server is unknown). Its inputs go through the redactor on one line, capped at 200 characters and ending in "…" when cut. Where there is no dry run, the request says that approving runs exactly this call once. The result arrives as a new message with no buttons.
- **Telegram buttons** carry the unguessable approval `Ref`, never a sequence number. A press from any chat other than the paired one is refused and changes nothing.
- **Isolation:** on the online demo each session has its own conversation, phone, mailbox, approvals and paired chat. Production messages never carry a Telegram display name, user name, chat id or phone number. Until Story 31.4 lands, the public demo keeps Telegram pairing off through host configuration.
- **Secrets:** keys, tokens and passwords never appear in the page, Visual Trace, logs, audit entries, screenshots or the repository. The README account's password is the only exception, and only where the README shows it.
- **README (1.0.0):**
  - It opens with "Try it in two minutes", the online demo link, a note that the sign-in details are on the splash, and the read-only Visual Trace account.
  - Its IPM section gives the registry install first and the load-from-folder path second.
  - It covers how to change the default IRIS accounts' passwords.
  - It credits the BMAD Method and Claude Code and carries the not-affiliated note. It is in plain English, with no class names or error codes outside the developer sections.
  - It claims only what 1.0.0 ships, every link in it resolves, and it names no private infrastructure.
  - It adds the MIT `LICENSE` file and two screenshots in `docs/images/` (each under 300 KB, with alt text). `docker/tests/test-readme.sh` pins all of these.
- **Layout fixes in Story 31.2** (the sticky stacked header within a quarter of the viewport, the guide's finish state at 640 px, the empty chat at 1280x800) go into 1.0.0 only if they cost Epic 31 no time. Otherwise they are re-owned to the first release after 1.0.0.

## Technical Decisions

- **One live-event model:**
  - `OcuTalon.Live.Event` rows are written only through `Live.Publish`, after the publisher's own commit. `Seq` is per stream, and the envelope is `{seq, stream, ts, type, payload}`. The stream is labelled `session` or `instance`, never with the stored `SessionRef`.
  - Each payload is the entity's full public view, never a delta.
  - Polling is the base contract. The WebSocket must use the same envelope, cursors and idempotent client apply path, and the client reloads the snapshot when a `Seq` skips.
- **WebSocket:**
  - The class is `/ocutalon/OcuTalon.Web.Live.cls` (`%CSP.WebSocket`). It checks `Origin` before it accepts and serves only a signed-in session.
  - It waits on the session's `$SYSTEM.Event` resource plus one instance resource, which `Live.Publish` signals after each commit.
  - The `/ocutalon` shell forwards it, or it moves to its own application; the story decides which.
  - With the online-demo flag set, the client never opens it, because an open socket holds a licence connection with no timeout.
  - Sign-out sets a server-side mark that each socket loop reads, so no frame is sent more than one loop after sign-out. The 60 s socket lifetime stays as a backstop.
- **Approvals:** the `ApprovalRequest` row is the truth. Its state changes only through the `OcuTalon.Bridge.Approval` API (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`). Answers from REST and Telegram go synchronously through `AnswersIn`, and the session is resolved on the server side only.
- **Notification ownership:**
  - For kind `tool_call`, `OcuTalon.Core.BridgeSink` turns the HostSink events `approval.raised`, `approval.answered` and `approval.result` into `Notification`s of kind `approval`, `answered` and `result`. It sends them through the adapterless `NoticesIn`, each carrying `ApprovalRef`, with `IncidentRef` empty.
  - For kind `fix`, `IncidentManager` does the same.
  - `BridgeSink` is the only class that turns bridge events into `Live.Publish` calls. It sends notices asynchronously and never waits more than 1 s on a lock. The bridge logs `OnEvent` failures and never propagates them.
  - Story 30.3's real `approval.result` has merged, so the replay path is live.
  - A held tool call's plain-English reason also reaches the approval card and the tool-call notices, not only the decision event.
- **Rendering:** producers never render text. Only `*Out` operations render, all through `OcuTalon.Msg.Catalog.Render(key, slots, channel)`. They add Approve and Reject only for kinds `incident` and `approval` that have an `ApprovalRef`. Slots hold UTC ISO times, integer counts and `itemNoun` one/other forms.
- **Approved tool calls:** the result returns through `ApprovalHold` and the HostSink. `Conversation` adds a code-written `SystemNote` (the tool, done or failed, and the time; never the tool's result text) to the next turn only.
- **Result band:** when a request's `Unreached` is above 0 (it is in the `incident` payload's `Requests[].Result`), the page shows `result.stoppedPartway` or its count-of-one form. It picks the key in the server's `Watch.Notice.ResultKey` order and never shows `result.skipped`. The web catalog key lists gain both forms. A resend still running after FixExecutor's 60 s wait shows the card's "Still resending" line and no result band.
- **Ownership:** REST reads and commands go through `OcuTalon.Data.Ownership`, and no endpoint accepts a `SessionRef` from the client. Telegram identity lives only in the `Pairing` row. Each live-event type has exactly one publisher, and only the owning lane edits a class.

## UX & Interaction Patterns

- The switch to polling is silent and the client reconnects in the background. The existing reconnect banners stay as they are.
- Answered and result notices edit the original approval message on the phone and in Telegram rather than sending a new one. In the web chat, the tool-call result is a new message with no buttons.
- The About dialog gains links to the bridge developer guide and the security overview. The demo guide's finish state gains "Use the same bridge in your own production ↗". The finish state appears only after an approved fix and a resolved incident.
- Below 1024 px wide, only a compact header is sticky, and it must stay within a quarter of the window's height.

## Cross-Story Dependencies

- **31.1** needs Epic 16 merged (its live client changes). It adds the sign-out mark to `Data/Session.cls`; if another open epic holds that file, the mark stays a ledger entry due before 1.0.0.
- **31.2 then 31.5:** 31.5 was split from 31.2 and builds on it. Both depend on Epic 6 (approval notices), Epic 16 (`BridgeSink`) and Epic 30 (the real `approval.result`, now merged).
- **31.3** needs Epics 12 to 15 merged: the Telegram channel, the guide paths from Stories 13.3 and 14.2, and `docs/install-ipm.md` from Story 15.2. Its IPM section follows the order of Story 15.3's guide. It turns on Stories 16.4's and 16.9's Telegram cases against their real Lane A paths. The measurement after launch is a 1.0.0 release check that the Contest Planner runs on the public demo host; no story waits on it.
- **31.4** needs Epic 12 and Story 29.4 (Epic 29) merged. It is deferred until after the v1.0.0 tag, with its ledger items.
