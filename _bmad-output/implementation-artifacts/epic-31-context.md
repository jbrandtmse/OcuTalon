# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 31 holds the Lane B work the owner moved off the demo path. All of it is 1.0.0 work. On a local or IPM install, the page gets live events over a WebSocket. The WebSocket is added beside polling. Polling stays the release-1 contract and the only live path on the online demo. A risky tool call's approval request reaches the simulated phone and the paired chat with Approve and Reject, and the message is edited in place when the request is answered and when its result arrives, so a tool call is answered the same way as a fix. The 1.0.0 README sends a judge straight to the online demo and describes what 1.0.0 ships. On the online demo, each visitor's paired Telegram chat stays separate from every other visitor's under load.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject
- Story 31.3: The README leads to the demo, and the launched demo is measured (owns DW-360)
- Story 31.4: The paired chat stays isolated under load too

## Requirements & Constraints

**The owner's live-path rule.** Polling is release 1's contract. The WebSocket is post-demo hardening: it is added beside polling and never replaces it, so polling, its reconnecting banners and its tests stay as they are. With the online-demo flag set, the page never opens the WebSocket and only polls. The reason: an open socket keeps its CSP session, and so one of the Community licence's 8 connections, alive with no timeout. The epic merges into the integration branch only after `v0.1.1` is tagged, so the WebSocket never ships in 0.1.1.

**Live delivery (31.1).** Messages, notifications and approval results reach the page within 2 seconds. CI checks this against the mock on every run, and the rehearsal measures it over real networks (at least 19 of 20 runs). When the socket closes or fails, the page switches to polling with no message and reconnects in the background. CI proves two cases: an event published while the socket is open arrives through the socket, and with the socket blocked, polling still delivers it.

**Tool-call approvals (31.2).** The first answer wins. Within 5 seconds the other channels show the result and where it came from ("Approved from Telegram at 14:15"), and their buttons stop working. A late press gets a short "already answered" reply. Until Story 30.3 merges, tests call `BridgeSink.OnEvent` with fixture `approval.*` events of kind `tool_call`. The epic's dependency line asks for Epic 30 to merge first, so that the real `approval.result` path is turned on within the story itself.

**README for 1.0.0 (31.3).**
- "Try it in two minutes" stays at the top, with the online-demo link the author gives and a note that the sign-in details are on the splash screen.
- It names the read-only Visual Trace account and says that trace links on the demo open it without a second sign-in.
- It adds the IPM install section from `docs/install-ipm.md`.
- It updates the release-1 top section and contest-task table for what 1.0.0 adds, and claims nothing that 1.0.0 doesn't ship.
- It keeps the BMAD Method and Claude Code credits and the not-affiliated note. It is plain English, with no class name or error code outside its developer sections, no key, local path or private infrastructure detail, and every link resolves.
- `LICENSE` at the repository root holds the standard MIT text with the holder line "Copyright (c) 2026 jbrandtmse". One README line goes under "Credits and licences": "OcuTalon is under the MIT License: [LICENSE](LICENSE)."
- Two screenshots go under "What's interesting", each with plain-English alt text: (1) the page on the demo path, with the incident card, its dry run with counts and the approval request; (2) Visual Trace of one decision, with model requests and tool calls shown as steps. The files live in `docs/images/`, each under 300 KB. A Playwright spec captures them on a throwaway stack (the mocked model is fine). They show no key, no secret, no password except the README account's, and no private host name.
- `docker/tests/test-readme.sh` pins the LICENSE text, the README line and both screenshot files and their links.
- DW-360: next to the README account's how-to, the README explains how to change the default IRIS accounts' passwords in the Management Portal.
- The measurement on the public online-demo host is a 1.0.0 release check that the Contest Planner runs. It is not story work, and no story waits for the launch.

**Paired-chat isolation (31.4).** Session A's incident, notification and approval request reach only A's paired chat, and B's paired chat gets none of them. A button press from B's chat on A's request is refused and changes nothing. No OCUTALON or OCUORDERS message body or header carries the paired mock chat's display name, user name, chat id or phone number: production messages hold only an internal chat reference. Each button carries an unguessable reference, never a sequential number.

## Technical Decisions

**WebSocket server (31.1).**
- The handler is `OcuTalon.Web.Live`, a `%CSP.WebSocket` class at `/ocutalon/OcuTalon.Web.Live.cls`. `%CSP.WebSocket` was tested on build 154.
- `/ocutalon` is a `%CSP.REST`-dispatched shell (`OcuTalon.Web.Public.Shell`), so the story decides whether the shell forwards the socket or the socket gets its own application.
- It serves only a signed-in session and checks `Origin` before it accepts. There is no CORS allow-list.
- It waits on the session's `$SYSTEM.Event` resource and on one instance resource. `OcuTalon.Live.Publish` signals both after each commit.
- It sends each new event after the client's cursors, one cursor per stream, in the same envelope `{seq, stream, ts, type, payload}` that polling uses. The stream is labelled `session` or `instance` and never carries the stored `SessionRef`. Row ids never leave the server. `OcuTalon.Web.TraceLink` adds trace URLs on the socket, as it does on `/state` and polling.
- Session resolution goes through `OcuTalon.Data.Ownership`, from the CSP session, never from request input. Unchecked SQL prepares are allowed only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`, and a CI check fails any other one.
- WebSocket code may read tables. It writes nothing beyond the web layer's few allowed writes (sign-in and sign-out rows, the pairing code's hash, UI-only markers).

**WebSocket client (31.1).**
- The Angular page has one live-event service. Socket events go through the same idempotent apply path as polling: each event replaces the entity with the same public `Ref` by its full current view, and the page reloads the snapshot when a stream's `seq` skips. Each event is therefore announced once, through `Announcer`, and the focus rules still apply.
- The story builds on the live client as Stories 16.3 and 16.4 left it (the session epoch, 401 handling and the idle cap).

**Tool-call notices (31.2).**
- `OcuTalon.Core.BridgeSink`, the bridge's `HostSinkClass` and Lane B's, is the only place that turns bridge events into `Live.Publish` calls.
- For approvals of kind `tool_call`, on `approval.raised`, `approval.answered` and `approval.result`, it sends `OcuTalon.Msg.Notification`s of kinds `approval`, `answered` and `result` through the adapterless `NoticesIn` service. Each carries `ApprovalRef`, and `IncidentRef` stays empty.
- Kind `fix` stays with `IncidentManager` (Lane A). A fix request with no incident belongs to step 4 (Story 21.5), not to this story.
- `approval.*` payloads carry only the record's public `Ref`. `BridgeSink` reads the row through the ownership API and keeps no copy of bridge records.
- `BridgeSink` sends notices asynchronously and waits on no lock for longer than 1 second. The bridge wraps each `OnEvent` call in its own error handling and never fails its caller.
- A tool call's request is raised inside a user's turn. Notices sent from inside a turn join the turn's trace thread through the bridge context's `ThreadSessionId`, never through another `Trace.Join`.
- Producers never render text. A notification carries `CatalogKey` and `Slots` (times as UTC ISO 8601, counts as integers), and only the `*Out` operations render, through `OcuTalon.Msg.Catalog.Render`. Lane B's keys live in `OcuTalon.Msg.Catalog.Core`.
- Approve and Reject are added only for kinds `incident` and `approval` that have `ApprovalRef` set, never for `answered` or `result`.
- An in-place edit finds the delivered message through `OcuTalon.Data.Delivery.FindByApproval` (exact approval `Ref`, channel and owner; the newest row), as Story 6.3 does for fix requests.

**Lane footprint.**
- The epic works in Lane B's files: `OcuTalon.Web`, `.Core`, `.Live`, `.Msg`, `web/`, `docker/`, the rest of `ci/` and the README.
- Lane A owns `release/`, the bridge developer guide, the security overview and `docs/install-ipm.md` (Story 31.3 reads it and links to it). From the Telegram epic on, Lane A also owns `OcuTalon.Channel.Telegram`, the rail's Telegram card, `web/e2e/demo-path/telegram-*.spec.ts` and the README's Telegram section.
- Story 29.4's load test, whose paired-chat cases Story 31.4 turns on, lives in `release/`. The Epic 29 exception that lets Lane B edit it covers Epic 29 only. Story 31.4 must turn those cases on without editing Lane A's files, or raise the footprint at planning.

## UX & Interaction Patterns

- **A lost socket:** the page falls back to polling with no message. Story 2.11's banners (info at 10 s, danger at 30 s) stay as they are.
- **The phone:** a tool call's request shows **Approve** on the left and **Reject** beside it, with the same text the paired chat gets. When the request is answered, the buttons are replaced in place by the status in message form ("Approved from Telegram at 14:15 ET."), and the result edits the message again. A late press shows "Already answered: approved from the web chat at {time}."
- **Announcements:** the page speaks through one polite region, and each event is announced from one place. The first snapshot is silent. Focus moves only when an update removes the focused element.
- **Links (31.3):** the About dialog gains the bridge developer guide and security overview links, and the demo guide's finish state gains "Use the same bridge in your own production ↗". The links use the paths that Stories 13.3 and 14.2 supply, and are added once both have merged. README links use the one `README_URL` address, with a section anchor in place of `#readme`.

## Cross-Story Dependencies

- **Merge gate:** the whole epic merges only after `v0.1.1` (Epic 12, Telegram) is tagged.
- **31.1:** needs Epic 16 merged (done). Stories 16.3 and 16.4 changed the live client that this story extends, and Story 2.11's polling client stays the base.
- **31.2:** extends Epic 6's approval notices (Story 6.3, done) and Story 16.9's `BridgeSink` (Epic 16, done). It also needs Epic 30 merged (Story 30.3's real `approval.result`, Lane A, still backlog); until then its tests use fixture events.
- **31.3:** needs Epics 12 to 15 merged: the Telegram channel (12), the guide's path (13.3), the security overview's path (14.2) and `docs/install-ipm.md` (15.2), all still backlog. It turns on Story 16.4's and Story 16.9's Telegram cases and their real Lane A paths: `WatchOps` stopping a signed-out session's watches, and an approval that completes while both caps hold. It updates release 1's README from Story 10.2.
- **31.4:** needs Lane A's Epic 12 and Epic 29 (Story 29.4) merged, both still backlog. Telegram reaches the demo host only with 1.0.0, because the demo goes public around November 1 without it.
- The planning docs set no order among the four stories.
