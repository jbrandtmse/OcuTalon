# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane B pieces that were deliberately moved off the demo path so they land in 1.0.0: on a local or IPM install the page receives live events over a WebSocket (polling stays the fallback and the only path on the online demo); a risky tool call's approval request reaches the simulated phone and the paired Telegram chat with Approve and Reject and is edited in place when answered and when its result arrives; the page shows a stopped-partway resend correctly; the README leads a judge straight to the online demo and covers everything 1.0.0 ships; and the paired chat is proven isolated between concurrent online-demo sessions. Epic 31 merges when done and ships in 1.0.0. There is no longer a tag gate.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject (part 1: stopped-partway result, tool-call note to the next turn, layout fixes)
- Story 31.3: The README leads to the demo, and the launched demo is measured
- Story 31.4: The paired chat stays isolated under load too
- Story 31.5: A tool call's approval request reaches the phone with Approve and Reject (notices)

## Requirements & Constraints

- **Live updates:** messages, notifications and approval results reach the page within 2 seconds. Other channels show an approval's result within 5 seconds. CI checks these bounds against the mock, and the clean-machine rehearsal measures them for real. If push is unavailable, the page falls back to polling silently.
- **Interrupted live updates:** after 10 s with no answer, a closable info banner says "Reconnecting… New messages may be delayed.". At 30 s an unclosable danger banner says "Can't reach OcuTalon. Retrying every 10 seconds.". Missed content loads on recovery. These banners already exist (they belong to an earlier story), and the WebSocket must work with them unchanged.
- **Approvals:** every approval request appears in the web chat, on the simulated phone and in the paired chat with inline Approve and Reject. The first answer wins, and the other channels show who answered, from where and when. A late press gets a short "already answered" reply. A tool-call card shows "Run {tool} on {server}" and the exact inputs. Where no dry run exists, it says that approving runs exactly this call once.
- **Telegram buttons** carry an unguessable approval reference, never a sequential number. A press from any chat other than the paired one is refused and changes nothing.
- **Isolation (online demo):** each session has its own conversation, phone, mailbox, approvals and paired chat. No session can see or answer another session's requests. Production messages never carry a Telegram display name, user name, chat id or phone number, only an internal chat reference.
- **Secrets:** keys and tokens never appear in the page, Visual Trace, logs, audit entries, screenshots or the repository.
- **README (1.0.0):** it opens with "Try it in two minutes", the online demo link, and a note that the sign-in details are on the splash. It names the read-only Visual Trace account. Its IPM section puts the registry install first and the load-from-folder path second. It credits the BMAD Method and Claude Code, carries the not-affiliated note, and is in plain English, with no class names or error codes outside the developer sections. It claims only what 1.0.0 ships, every link in it resolves, and it names no private infrastructure. MIT `LICENSE` file; two screenshots of 300 KB or less each in `docs/images/`, with alt text; `docker/tests/test-readme.sh` pins these.
- **Layout fixes in 31.2 (DW-530/542/543)** go into 1.0.0 only if they cost no time. Otherwise they are re-owned to the first release after 1.0.0.

## Technical Decisions

- **One live-event model:** the `OcuTalon.Live.Event` rows are written only through `Live.Publish` after commit. Each row has a per-stream `Seq`, and the envelope is `{seq, stream, ts, type, payload}`. The stream is labelled `session` or `instance`, never with the stored `SessionRef`. Each payload is the entity's full public view, never a delta. The WebSocket and polling must not drift: both use the same envelope, cursors and idempotent client apply path, and the client reloads the snapshot when a `Seq` skips. Polling is the base contract and the WebSocket is an enhancement.
- **WebSocket:** `/ocutalon/OcuTalon.Web.Live.cls` (`%CSP.WebSocket`). It checks `Origin` before it accepts, serves only a signed-in session, and waits on the session's `$SYSTEM.Event` resource plus one instance resource, which `Live.Publish` signals after each commit. The `/ocutalon` shell forwards it, or it moves to its own app; the story decides which. With the online-demo flag set, the client never opens it, because an open socket keeps a licence connection alive with no timeout. A sign-out must stop the socket within one loop: sign-out sets a mark that each loop reads. The 60 s socket lifetime stays as a backstop.
- **Approvals:** the `ApprovalRequest` row is the truth, and state changes only through the `OcuTalon.Bridge.Approval` API (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`). Answers go through `AnswersIn` → `AnswerOps`, and the session comes from the server side only.
- **Notification ownership:** for kind `tool_call` (and for a fix request with no incident), `OcuTalon.Core.BridgeSink` turns the bridge's `approval.raised`, `approval.answered` and `approval.result` into `Notification`s of kind `approval`, `answered` and `result`. They go through the adapterless `NoticesIn`, each carrying `ApprovalRef`, with `IncidentRef` empty for a tool call. `IncidentManager` keeps doing the same for incident fixes. `BridgeSink` sends asynchronously, never waits more than 1 s on a lock, and is the only class that turns bridge events into `Live.Publish` calls. Its `OnEvent` errors are logged, never propagated.
- **Rendering:** producers never render text. Only `*Out` operations render, through `OcuTalon.Msg.Catalog.Render(key, slots, channel)`. They add Approve and Reject only for kinds `incident` and `approval` that have an `ApprovalRef`. Slots hold UTC times, integer counts and the `itemNoun` one/other forms.
- **Approved tool calls:** the result goes back through `ApprovalHold` and the HostSink. `Conversation` puts a code-written `SystemNote` (the tool, done or failed, and the time; never the tool's result text) into the next turn only.
- **Result band:** the page picks `result.stoppedPartway` (and its count-of-one form) when `Unreached` > 0, in the server's `Watch.Notice.ResultKey` order, and never `result.skipped`. The `incident` payload's `Requests[].Result` carries `Unreached`. A resend still running after FixExecutor's 60 s wait shows the card's fixing ("Still resending") line and no result band.
- **Ownership:** REST reads and commands go through `OcuTalon.Data.Ownership`, and no endpoint accepts a `SessionRef` from the client. Telegram identity lives only in the `Pairing` row. Pairing-code hashing has one helper (`Pairing.HashCode` must delegate to `Session.Hash`). Each live-event type has exactly one publisher, and only the owning lane edits a class.

## UX & Interaction Patterns

- The client's switch to polling is silent and it reconnects in the background, with the existing reconnect banners unchanged.
- In-place edits: answered and result notices edit the original approval message on the phone and in Telegram, not new messages.
- The About dialog gains the bridge developer guide and security overview links. The demo guide's finish state gains "Use the same bridge in your own production ↗". The finish state shows only after an approved fix and a resolved incident.
- Below 1024 px wide, only a compact header stays sticky, and it must stay within a quarter of the window's height.

## Cross-Story Dependencies

- **31.1** needs Epic 16 merged, because Stories 16.3 and 16.4 changed the live client it extends. It also touches `Data/Session.cls` for the sign-out mark: if another open epic holds that file, the mark stays a ledger entry.
- **31.2 / 31.5:** 31.5 was split from 31.2 and builds on it. Both need Epic 6 (approval notices), Epic 16 (Story 16.9's `BridgeSink`) and Epic 30. Story 30.3's real `approval.result` has merged, so the replay path is live and fixtures are no longer the only option.
- **31.3** needs Epics 12–15 merged: the Telegram channel, and Stories 13.3, 14.2 and 15.2, which provide the guide paths and `docs/install-ipm.md`. It turns on the Telegram cases of Stories 16.4 and 16.9 against their real Lane A paths. Its post-launch measurement is a 1.0.0 release check that the Contest Planner runs on the public demo host. No story waits on it.
- **31.4** needs Epic 12 and Epic 29 (Story 29.4's paired-chat cases) merged.
