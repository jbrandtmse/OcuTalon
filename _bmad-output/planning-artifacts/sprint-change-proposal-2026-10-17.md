---
project: OcuTalon
date: 2026-10-17
trigger: implementation-readiness gate (bmad-sprint-planning) returned FAIL on 2026-10-17
mode: incremental for section A, batch for sections B and C
status: approved and applied (2026-10-17)
---

# Sprint Change Proposal: OcuTalon readiness-gate fixes (October 17, 2026)

## 1. Issue summary

The implementation-readiness gate failed on October 17, 2026, before any story was built and before `sprint-status.yaml` existed. The plan itself is sound and stays as it is. The failures are contracts between the two build lanes that no document fixes, plus a few stories that can't pass as written.

- **Problem type:** contract gaps and contradictions between the PRD, the UX spine, the architecture spine and the epics (no technical limitation, no new requirement, no pivot).
- **Evidence:** every finding was checked against the current text of the documents on October 17 by read-only checks, one per document, and against the IRIS reference source where it mattered (`Ens.Config.Production` for A4; `Ens.Util.Tasks.Purge` for A10). Findings that didn't hold as worded are marked in section 4.
- **Fixed author decisions (not reopened):** the plan and pace stay; Telegram is Epic 12 in Lane A after Epic 11 and ships as 0.1.1 before the online demo goes public; Epic 0 creates the shared release-1 tables first, and paired epics build against a contract with fixtures until the partner merges; P3 to P24 stand as accepted, with P12 a capacity floor only and P15 withdrawn.

## 2. Impact analysis

**Epic impact.** Every epic can still be completed as planned. No epic is added, removed, re-sized or moved between lanes, and the release-1 floor is unchanged.

- **New stories:** 10.3 (Lane B: the session side of Telegram, built in release 1 and switched off until the release includes Telegram) and 11.6 (Lane A: the author's REL-7 hands-on pass before 0.1.0). The epics now hold 163 stories.
- **Changed dependency lines:** Epic 16 (story-level edges to Stories 11.5 and 15.2 and to Epic 11's end-to-end path), Epics 17 and 18 (0.1.1 shipped), and Epics 18, 20, 21, 24 and 25 (their partner's first story).
- **Contracts fixed in Epic 0:** `Incident.NoticedAt`, the extended ApprovalState, the missing enumerations and `ModelFamily`, `ChatRef`, `Included()`, `Request.Summary`, `DecisionResponse`, `ApprovalStartIn`, `Tasks()`, `Purge(daysToKeep)`, the implemented `Data.Public.Settings`, lane regions in the production definition, and the mock's scenario format.

**Story impact.** Acceptance criteria changed in Stories 0.1 to 0.8, 1.1, 1.3, 1.4, 1.9, 1.11, 1.12, 2.1, 2.6, 2.8, 2.10, 3.4 to 3.6, 3.8, 4.1 to 4.4, 4.6, 4.7, 5.3 to 5.7, 6.1, 6.2, 6.4, 7.2, 7.5, 8.1, 8.2, 9.1, 9.2, 9.4, 9.5, 10.1, 11.1, 11.3 to 11.5, 12.1 to 12.5, 12.7, 13.3, 14.2, 15.2, 15.3, 16.1, 16.5 to 16.10, 25.3 and 26.2, plus the requirements inventory and the epic list.

**Artifact conflicts resolved.**

- **PRD:** FR-1, FR-8, FR-15, FR-18, FR-23, FR-24, FR-34, FR-59, NFR-9, NFR-23, REL-7, §0, glossary, §4.3, §4.4, §7.2, §7.4, §11.1, §11.2 (P25 to P31 and stale text).
- **UX:** EXPERIENCE.md (lifecycle table, two new catalog entries, slot sources, guide variants, voice rules, Telegram release, change 9) and DESIGN.md (Telegram card release).
- **Architecture spine:** AD-1, AD-4, AD-6, AD-10 to AD-13, AD-15, AD-16, AD-18 to AD-20, AD-22, AD-23, AD-25, AD-27 to AD-32, conventions, production diagram and flow, ownership tables, data model, REST surface.
- **Architecture notes:** §3 checkpoint line, §5 P6 and P25 to P31.

**Technical impact.** Planning documents only; no code exists yet. `sprint-status.yaml` doesn't exist yet, so checklist item 6.4 doesn't apply; sprint planning generates it from the updated epics.

**Findings that didn't hold as worded** (fixed where the underlying gap was real):

- C1: EXPERIENCE ~17 doesn't mention Telegram; that part was dropped, and the other UX places that tie Telegram to release 1 were fixed.
- C7: the PRD says "while IRIS was down", and EXPERIENCE says "while OcuTalon was offline"; both now follow the spine's rule (late if it fires more than 10 s after its due time).
- C8: the notes don't call change 9 "proposed"; they say P6 "waits for step 3 planning", which was equally stale (P23 decided it).
- B5: the spine's conventions row already defines Provenance, RequestKind, FallbackReason and ApprovalKind; only Story 0.4 lacked them.
- A1, first point: Story 5.4 sends the incident notice key (whose template ends "Approve?"); the approval itself is added in Story 7.2.
- A2: Story 16.1 doesn't build the reader; it "adds keys" and says Story 3.8 writes them (circular).
- B16: Stories 13.3 and 14.2 didn't supply the link targets themselves; they handed the links to "Lane B's owner".

**Found during the checks and fixed** (within the approved decisions):

- No story built Diagnosis's read-only watch tools (Story 5.4 now does; 1.1 and 1.9 use a fixture).
- `TelegramIn` would have written Lane B's `Pairing` table, and a message would have carried the Telegram chat id. Lane B's `OcuTalon.Data.Pairing.RecordChat`, a direct call, now records unpaired chats.
- Story 12.5's purge of `Pairing` moves to Lane B's Core area.
- Story 3.5 gains the `tool_call` replay exception.
- Spine AD-6's `SystemNote` example contradicted AD-30.
- Spine AD-22 still called P3 proposed.
- The Telegram Approve response hard-coded "50 orders".
- FR-23's "one approval request" contradicted later requests.
- The guide had no step 4 text after a no-fix notice; the UX and Story 4.7 now have one.
- Story 25.3's `TelegramIn` part moves to Lane A's Story 26.2.

## 3. Recommended approach

**Direct adjustment.** Every fix edits existing documents or adds a story inside its epic (new story numbers continue each epic's sequence). No rollback (nothing is built) and no MVP review (the release-1 floor, the lanes and the pace are unchanged).

## 4. Detailed change proposals

### Section A: decisions for the author

#### A1. Incident and approval lifecycle (Epics 5-7): APPROVED as recommended, quiet close option B

Verified: all seven points hold. The checks also found that the data model allows one `FixRun` per incident (conflicts with a later request) and that the PRD ties only a rejection, not an expiry, to the Open state.

Decisions:

1. **No-fix notice (P25).** A usable diagnosis that names a cause with no fix in the fixed set (any cause other than data format, including `unknown`) sends a notice of kind `incident` with its own catalog key and no `ApprovalRef`. Lifecycle row "Open, cause found, no fix" (chip Open; actions Dismiss, Show details). Catalog text:

   ```
   {count} {item noun} failed since {time}. {cause}. None of my fixes applies to this, so I'm not proposing one. Nothing was changed.

   Failures:
   {readable item name}: {count}, '{plain error summary}', first at {time}
   (one line per group)

   Details and trace: on your OcuTalon page.
   ```

   Unknown-cause first line: "{count} {item noun} failed since {time}. I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed." The web card announces "Incident: {headline}. No fix proposed." FR-24's notice criterion gains "or says that none of its fixes applies".

2. **Quiet close (P26), option B.** A resolved incident closes after 15 quiet minutes, by Dismiss or by the replay rule. An open incident (fallback, no fix, rejected, expired) closes by Dismiss; outside demo mode it also closes after 15 quiet minutes. Awaiting approval and fixing never close on their own. FR-24: "rejected or expired" returns the incident to Open.

3. **Transition table in AD-15** (from the UX lifecycle table); `IncidentManager`'s unit test covers every row and every refused move:

   | From | Event | To |
   | --- | --- | --- |
   | (none) | first failure of a new group | `open`, `NoticedAt` empty |
   | `open`, not noticed | notice sent with a fix and a valid dry run (`Raise`) | `awaiting_approval` |
   | `open`, not noticed | notice sent: fallback, or no fix | `open` (fallback or no fix) |
   | `awaiting_approval` | approved | `fixing` |
   | `awaiting_approval` | rejected or expired, no other request pending | `open` (rejected or expired) |
   | `fixing` | in-progress `FixResult` | `fixing` |
   | `fixing` | final `FixResult` (interrupted included) | `resolved`, or `awaiting_approval` if a later request is pending |
   | `awaiting_approval`, `fixing` or `resolved` | a later request is raised | `awaiting_approval` (`fixing` stays `fixing`) |
   | `resolved` | `closeQuiet`, `dismiss` or `closeForReplay` | `closed` |
   | `open`, noticed | `dismiss`; `closeQuiet` only with demo mode off | `closed` |

   Everything else is refused (for example `dismiss` while awaiting approval or fixing, anything on a closed incident). One rule decides the state: fixing while a fix runs; otherwise awaiting approval while any request is pending; otherwise the latest request's outcome (resolved after a finished fix, open after a rejection or expiry).

4. **`NoticedAt`.** `Incident.NoticedAt` (UTC, empty until the notice) is fixed in Story 0.4. The ownership API's incident reads, and so the snapshot, the guide and Break the feed's availability, return only noticed incidents; until then only `watch.progress` events show. `Guide.Compute`'s "a run with no incident notice" uses it. The UX row "Open (no fix proposed yet)" becomes "Before the notice: no card yet; the progress line shows".

5. **Later request (P27, FR-8).** Same-cause failures after the notice that no request covers settle by the same rule, then get their own dry run and request (notification kind `approval`, its own card in the incident card), while the incident is awaiting approval, fixing or resolved; an open incident only updates its count. Catalog text:

   ```
   {count} more {item noun} failed since {time}, with the same cause. I can {fix summary}. Approve?

   Dry run: {count} {item noun} affected. Example: {field} {before} becomes {after}. {what will be resent}; the originals stay unchanged. Nothing has changed yet.

   Details and trace: on your OcuTalon page.
   ```

   Story 5.3's "never a second notice" gains this exception; the data model allows one `FixRun` per approved request.

6. **ApprovalState** becomes `pending, approved, rejected, expired, cancelled, executing, done, failed` (conventions row and AD-11). `interrupted` stays a `FinishExecution` result: the row ends `failed`, and the `FixRun` records `interrupted`.

7. **Notification kinds (AD-32).** Every incident notice (with a fix, fallback or no fix) is kind `incident`; its catalog key tells the variants apart, and the first request's `ApprovalRef` travels on it. Kind `approval` is only for later requests and for tool calls.

Lands in: PRD FR-24, FR-8 (P25 to P27); UX lifecycle table and two catalog entries; spine AD-11, AD-15, AD-32, conventions, data model; epics 0.4, 4.2, 5.3 to 5.6, 6.1, 6.4, 7.2.

#### A2. The online-demo settings arrive too late: APPROVED as proposed

Verified: holds. Also found: AD-29's rule would have Lane B build the reader in its first epic (Epic 2), and no Epic 2 story does; Story 16.1 "adds keys" and says Story 3.8 writes them while 3.8 writes through keys 16.1 adds (circular); the spine, 3.8, 16.1 and 16.7 each list different values (the last reset's kind only in AD-25; the proxy address and the gateway spend have no home); the single-reference check as worded would also fail the writers (the `Public` step and the after-start script); the bridge can't read the spend (AD-2).

Decisions:

1. **Transport (AD-19).** Fixed environment variables that only the online demo's deployment sets; the after-start script's `Public` step reads them on every start (structural). Without `OCUTALON_ONLINE_DEMO` the instance isn't the online demo.

   | Variable | Value (default) | Goes to |
   | --- | --- | --- |
   | `OCUTALON_ONLINE_DEMO` | `1` turns the online demo on | public key |
   | `OCUTALON_DEMO_USER`, `OCUTALON_DEMO_PASSWORD`, `OCUTALON_READONLY_USER`, `OCUTALON_READONLY_PASSWORD` | the published accounts (shown on the splash; not secrets) | public keys, and the users step |
   | `OCUTALON_RESET_INTERVAL_HOURS` | (4) | public key |
   | `OCUTALON_RESET_ANCHOR`, `OCUTALON_LAST_RESET` | UTC ISO 8601 | public keys |
   | `OCUTALON_LAST_RESET_KIND` | `scheduled` or `unscheduled` | public key |
   | `OCUTALON_PROXY_ADDRESS` | the proxy's address (AD-13's forwarded-address rule) | public key |
   | `OCUTALON_CONNECTION_CAP`, `OCUTALON_CONNECTION_RESERVE`, `OCUTALON_MESSAGE_ALLOWANCE` | (8, 2, 50 an hour) | public keys |
   | `OCUTALON_DAILY_COST_CAP_USD` | (20) | bridge host setting |
   | `OCUTALON_GATEWAY_SPEND_USD`, `OCUTALON_GATEWAY_SPEND_DATE` | today's gateway spend and the instance-zone date it counts | bridge host setting |

2. **One key list in AD-19:** the public keys above plus readiness; the reader also computes the next reset. Stories 3.8, 16.1 and 16.7 cite it; 16.7 passes exactly these variables.
3. **Reader and writer built in Epic 0.** `OcuTalon.Data.Public.Settings` is implemented in Story 0.2 (not a stub), because the after-start script clears and sets readiness from Epic 0: `Get`, `Set` (fixed keys only), `ClearReady`, `SetReady`, `NextReset`. Lane B owns it after. The single-reference check names it as the only class that touches the global; every writer goes through it.
4. **Split.** Story 3.8 (Lane A, the `Public` step) reads the variables, writes the public keys through the accessor, and copies the daily cap and the gateway spend into the bridge's host settings, which `Budget.State()` reads. Story 16.1 (Lane B) reads them for the splash, the status endpoint and the next reset; its circular lines go.

Lands in: spine AD-19, AD-25 (start values), Story 0.7's check; epics 0.2, 0.7, 3.8, 16.1, 16.7.

#### A3. Telegram in Lane A needs Lane B code: APPROVED, option (b)

Verified: holds. Epic 12 reaches into SessionOps (12.4, 12.5), the pairing endpoints (12.3, 12.5), `StatusMark`, `StatusMonitor` and `/state` (12.2), Notify's pairing route and `ChatRef` on Lane B's `Msg` classes (12.4), and the CI mock with its override (12.1). The ownership tables still give `TelegramIn`, `TelegramOut`, `Pairing` and the `pairing` event to Lane B; Story 16.4 (Lane B) changes `SessionOps.End`; Story 25.3 (Lane B) changes `TelegramIn`. AD-29 already serializes the Telegram epic against overlapping Lane B epics, but under (a) that would serialize Epic 12 against Epic 16 and put the demo host's November 1 date at risk.

Decisions:

1. **Epic 0 fixes the contracts:** Story 0.4 adds `ChatRef` to `OcuTalon.Msg.Notification` and `OcuTalon.Msg.Outbound`, and the stub `OcuTalon.Channel.Telegram.In` gets a class method `Included()` that returns 0.
2. **New Lane B Story 10.3, "The session side of Telegram is ready and stays off"** (before Epics 11 and 12), tested on fixtures: SessionOps `pair` and `unpair` (audited, `pairing` event); `POST /api/v1/pairing/code` (hash in `Pairing`) and `DELETE /api/v1/pairing`, both 404 until `Included()` returns 1; `OcuTalon.Data.StatusMark.Record(condition, until)` and `telegramPaused` in StatusMonitor and `/state`; Notify's `pairing` route; the `/state` Telegram flag read from `Included()`; the CI mock's Bot API endpoints and the compose override's `OCUTALON_TELEGRAM_API_BASE`.
3. **Epic 12 stays inside AD-29's allowance:** TelegramIn turns `/start <code>`, `/stop` and button presses into `Commands.Submit` and `AnswersIn` calls and calls `StatusMark.Record`; Lane A's mock scenarios go under `ci/mock/scenarios/A/`; Story 12.7 sets `Included()` to 1 in the same change as the README's Telegram section.
4. **Ownership after Epic 12:** Lane A owns `OcuTalon.Channel.Telegram` (`TelegramIn`, `TelegramOut`), the rail's Telegram card, the README's Telegram section and the Telegram mock scenarios; Lane B keeps SessionOps, the `Pairing` and `StatusMark` tables, Notify, the pairing endpoints, `/state` and the mock service. The ownership tables move `TelegramIn` and `TelegramOut` to Lane A. Story 25.3's TelegramIn part (size check, download that never logs its address, the gateway file route) moves to Lane A's Story 26.2; 25.3 keeps the web upload.

Lands in: spine AD-29 and the ownership tables; epics 0.4, new 10.3, 12.1 to 12.7, 25.3, 26.2, and Epic 10's and Epic 12's epic-list entries.

#### A4. "One XData block per lane" can't work: APPROVED, one block with lane regions

Verified (irislib `Ens/Config/Production.cls`): IRIS loads a production only from its `ProductionDefinition` XData (`Ens.Util.XML.Reader.ObjectFromXData(…, "ProductionDefinition", …)`), and `SaveToClass` deletes that block and exports a new one, so a second block or a comment is ignored or lost.

Decision: one `ProductionDefinition` block with a comment-delimited region per lane (`<!-- lane A: begin -->` … `<!-- lane A: end -->`, the same for lane B); each lane edits only its region. A CI check (Story 0.7) fails when a region's markers are missing (which also catches a portal save), when an item sits outside both regions, or when an item's class belongs to the other lane per the ownership table.

Lands in: spine AD-29; epics 0.6, 0.7.

#### A5. Online-demo capacity: APPROVED as proposed

Verified: holds. Busy starts at 6 connections (cap 8 minus reserve 2) and each trace window holds one more, so 6 visitors plus 3 trace windows need 9. Accepted P12 already says "about 6 … (about 3 with Visual Trace open)"; NFR-23 and FR-15 drifted to "about 3 of them". FR-15's per-address limit (5 new sessions an hour) blocks 6 scripted visitors from one address.

Decisions (P28, restoring P12's wording; the floor doesn't change):

1. PRD NFR-23 and FR-15: "about 6 signed-in visitors, or about 3 with Visual Trace open".
2. Story 16.10 runs two cases through the real proxy, 6 visitors without trace and 3 with trace, each plus one more visitor who must see the busy text and never an error page. Each scripted visitor signs in from its own client address (separate driver hosts or source addresses); nothing bypasses the per-address counter. The driver hosts are an owner precondition (A8).
3. Story 16.10's post-launch measurement adds NFR-7 (Break the feed to the incident notice on the simulated phone, at most 60 s in at least 19 of 20 runs).

Lands in: PRD NFR-23, FR-15 (P28); epics 16.10.

#### A6. REL-7 hands-on pass before 0.1.0: APPROVED as proposed

Verified: holds. Epic 11 has no hands-on pass: 11.3 is automated, 11.5's gate list leaves it out, and only 12.7 has one (Telegram, for 0.1.1). With step 1 split across two releases, REL-7's "that step's release" is ambiguous.

Decisions:

1. **New Story 11.6, "A hands-on pass with real keys finds and fixes what the tests missed before 0.1.0":** the author runs UJ-1's web route by hand on a README Docker install of the release candidate with a real model key (sign in, watch, Break the feed, the notice on the phone, Approve and the result, Visual Trace, the sample emails, a reminder); each finding goes into the release checklist with its fix or the author's decision to defer it; the fixes merge before the release is cut. No Telegram (0.1.0 has none).
2. **Story 11.5's sequence** refuses to cut a release unless the checklist records the hands-on pass on that candidate's version with no open finding the author hasn't deferred. Story 12.7 supplies the pass for 0.1.1.
3. **PRD REL-7 (P29):** step 1's pass runs twice, before 0.1.0 on the web demo path, and before 0.1.1 with Telegram on iOS, Android and desktop clients.

Lands in: PRD REL-7 (P29); epics new 11.6, 11.5, Epic 11's epic-list entry.

#### A7. Rehearsal automation: APPROVED as proposed (all three)

Verified: holds. Story 11.3's clean machine has "no Node.js" yet a "rehearsal runner drives the web demo path through the page 20 times", with nothing saying what runs it or where; Story 12.7 runs 20 pairings and 20 approvals "with a real bot", which the Bot API can't do as a user; 11.3 and 12.7 accept 19 of 20 runs for limits the PRD states as a plain 5 seconds (FR-1, FR-8, FR-18, NFR-9); only NFR-7 and NFR-8 carry "19 of 20".

Decisions:

1. **Story 11.3:** Playwright runs on a separate driver host against the clean machine's published port; the clean machine stays as a judge's would. The driver host is an owner precondition (A8).
2. **Story 12.7:** the author runs the 20 pairings and 20 approvals by hand (about 40 minutes); the timings come from server-side timestamps (the update's arrival at `TelegramIn` to the page event and to the other copies). No user-client tool.
3. **PRD (P30):** measured over real networks (the clean-machine rehearsal and the online demo), FR-1's notification, FR-8's result on the other channels, FR-18's pairing and NFR-9 hold in at least 19 of 20 runs; CI checks each limit against the mock on every run.

Lands in: PRD FR-1, FR-8, FR-18, NFR-9 (P30); epics 11.3, 12.7.

#### A8. Demo-host interface and owner actions: APPROVED as proposed

Verified: holds. Story 11.5's hook names no interface to the demo host; AD-25 says the golden copy is "captured from a fresh install … with no sessions" and also "each release's demo update upgrades in place, then captures"; the busy marker header (16.5, 16.7, AD-25) is unnamed; 16.7 names the server, DNS and launch gate as the author's actions but not the demo bot and its token, and nothing assigns the clean hosts (11.3) or the branch protection 11.5 reads; the PRD says the demo runs restricted "from release 1" (FR-59, §7.4, §11.1) while release 1 is October 30 and 16.7 makes the host ready by November 1.

Decisions:

1. **Hook interface (AD-25):** the release sequence (`release/`, Lane A) reaches the demo host only over SSH (address and key in the author's configuration outside the repository), through two host commands that Story 16.7 maintains outside the repository: `ocutalon-demo update <version>` and `ocutalon-demo status` (JSON: running version, golden-copy version, last reset's time and kind, next reset). Before launch the update runs at once (access is restricted); after launch it runs at the next scheduled reset, and the hook writes that time into the draft notes. With no demo host configured, 11.5 says so, as today.
2. **Golden-copy sequence (AD-25), at a reset boundary:** restore the current golden copy; start it on the new image, which upgrades it in place with no visitor data; wait for ready and check the version; stop IRIS cleanly and capture the new golden copy (no marker, readiness cleared); start from that copy. The first golden copy comes from a fresh install; each later one is the previous copy upgraded in place. "A reset refuses a golden copy whose version differs from the image's" stays.
3. **Busy-marker header:** `X-OcuTalon-Busy: 1` (AD-25; Stories 16.5 and 16.7).
4. **Owner preconditions** stated in the stories: 16.7, the demo server and its DNS name by October 30, the demo bot (created by the author, used by no other instance) with its token and the real model key in the gateway, and SSH access for the hook; 11.3, a clean macOS host and a clean Linux host with Docker and outbound access limited to the model provider (and Telegram when a token is set), plus the Playwright driver host; 11.5, branch protection on `main` with the `ci.yml` and `lane-a.yml` checks required, before the sequence first runs; 12.7, a real bot token for the rehearsal and iOS, Android and desktop Telegram clients; 16.10, the separate client addresses (A5).
5. **PRD timing (P31):** the online demo runs with access restricted from November 1 at the latest, on the latest release, and goes public by the date in §7.4 (FR-59's delivery line, the §7.4 row, the §11.1 row). A 0.1.0 cut before the host exists is fine; 16.7's first deploy installs the current release.

Lands in: PRD FR-59, §7.4, §11.1 (P31); spine AD-25; epics 11.3, 11.5, 12.7, 16.5, 16.7, 16.10.

#### A9. The daily-cap message has no producer: APPROVED as proposed

Verified: holds. Story 16.9's "each session with activity gets the daily-cap allowance message once" has no sender; the gateway's 403 only makes each decision fall back; "activity" is undefined; the spine has no daily-cap message (only notes P16), and AD-20 doesn't name the sender of the session-allowance message either.

Decisions:

1. **Bridge event (AD-20, AD-31):** the first decision of the day that falls back with `daily_cap` (from IRIS's own precheck or from the gateway's 403) makes the bridge mark the day as capped, once, under a lock, and fire the HostSink event `budget.capped`. Because the bridge records a 403 too, `Budget.State()` then reports the cap reached, so the banner shows and later decisions fall back before sending, whichever path got there first.
2. **Sender (AD-31, AD-32):** `OcuTalon.Core.BridgeSink` (Lane B) turns `budget.capped` into one `Notification` per session with activity (kind `allowance`, the daily-cap catalog key from EXPERIENCE › Conversation), through `NoticesIn`, to the chat and the paired chat. A session that first becomes active afterwards gets it with its first `daily_cap` fallback (seen by BridgeSink in `decision.recorded`). Each session gets it once a day, recorded on its `Session` row.
3. **"Activity" (AD-20):** an open session whose user has sent a chat message, pressed Break the feed or answered a request since it began.
4. **Side fix:** the session-allowance message's sender is the channel service whose `Allowance.TryConsume` call was refused (`WebChatIn` or `TelegramIn`), on the first refusal in the window.

Lands in: spine AD-20, AD-31, AD-32; epics 1.4, 16.9.

#### A10. Retention setting: APPROVED, day counts as task properties

Verified: holds. Story 1.11 reads the 90-day period "from a product setting seeded at 90 days through `OcuTalon.Data.Setting.Get`"; `OcuTalon.Bridge.Purge` can't call it (AD-2); `Data.Setting` holds only values no bridge class reads; `Ens.Util.Tasks.Purge` keeps `NumberOfDaysToKeep` as a task property (irislib); AD-27 records fixed day counts; NFR-19 says "90 days by default".

Decision: the day counts are task properties that the installer's task step writes only when it creates each task (an upgrade keeps a changed value; an admin can change one in the Task Manager without a release): the two `Ens.Util.Tasks.Purge` tasks keep `NumberOfDaysToKeep` 7 and 90; `OcuTalon.Install.Task.Purge` gets `DaysToKeep` (90) and passes it to `OcuTalon.Bridge.Purge` and to each area's `Purge(daysToKeep)`. Live events (24 hours) and orphan AI sessions (one day) stay fixed. The `Setting.Get` read is dropped.

Lands in: spine AD-27; epics 0.2 (the `Purge(daysToKeep)` declaration), 1.11.

#### A11. Telegram before step 2: APPROVED, option (a) (both lanes, as the PRD says)

Verified: holds. PRD §7.2 says Telegram ships as 0.1.1 "before any step 2 work" (both lanes); AD-29's rule bars only Lane A ("Until Telegram ships, Lane A takes only 1.0.0 kit work, never step 2"), though its own Prevents line is lane-neutral; Lane B's Epic 18 depends only on Epic 16.

Decision: AD-29 says "Until Telegram ships (0.1.1), neither lane starts step 2 work." Epics 17 and 18 add "0.1.1 shipped (Story 12.7's hands-on pass and Story 11.5's release sequence)" to their Depends on lines. No schedule cost: with B's partner-story dependencies, Epic 18 already waits for Story 17.1, which follows Epics 12 to 15 in Lane A.

Lands in: spine AD-29; epics Epic 17 and Epic 18 epic-list entries.

### Section B: mechanical fixes (batch): APPROVED to the facilitator's judgement and applied

All verified against the current text unless marked. Each row: the fix, then where it lands.

**Epic 0**

| Id | Fix | Lands in |
| --- | --- | --- |
| B1 | Story 0.7's CI mock also serves `GET /v1/models/<id>`; recognises the compaction marker `OCUTALON-COMPACTION-V1` and returns the schema reply (plus the off-schema scenario); returns 429 and 529 with `Retry-After` under a per-test countdown set through its control endpoint; holds an answer past the bridge timer; returns the `refusal` and `max_tokens` stop reasons, an empty reply, a provider error and the "Invalid input" rejection (Stories 1.6 to 1.9; AD-22 already lists them). Fixed scenario-file format: one JSON file per scenario, `ci/mock/scenarios/<A or B>/<name>.json`, with `name`, `match` (`marker`, `prompt` or `mockkey`) and `replies` (each `status`, `headers`, `delayMs`, `stopReason`, and `text`, `toolUse` or `body`). Lane A extends the mock only by adding files under `ci/mock/scenarios/A/`; new mock behaviour is asked of Lane B (AD-33). | 0.7; AD-22 |
| B2 | Story 0.6 sets `Decide`'s extension-class settings in Lane A's region: `HostSinkClass` = `OcuTalon.Core.BridgeSink`, `ReplyFilterClass` = the AD-28 guard `OcuTalon.Checks.ReplyGuard`; `ClassificationClass` keeps the do-nothing default until step 4. The bridge reads these from `Decide`'s settings in any job through one bridge accessor, so a job such as `AnswersIn`'s (which calls `Approval.Answer`) reaches the HostSink too. | 0.6; AD-31 |
| B3 | New production item `ApprovalStartIn` (`OcuTalon.Bridge.Service.ApprovalStart`, adapterless business service, Lane A): `Raise` starts `ApprovalHold` through it, synchronously from inside `%CanExecute` (S4), from `IncidentManager` and from `Reconcile`. Stubbed in 0.6, built in 3.4, added to the ownership table and the production diagram. | 0.6, 3.4; AD-11, ownership table |
| B4 | Story 0.2: the step registry also declares `Tasks()` (beside `Grants()`, `Reconcile()` and `Purge(daysToKeep)`, A10), and the core's task step creates each declared task once (1.11 declares the purge tasks, 8.1 the heartbeat task); the script deletes the ready marker and clears readiness first; checks before the version gate that the public classes resolve to `OCUTALON_PUBLIC` and forces a load if not; a test proves a second start with a new version upgrades in place; the `Production` step is a stub until Story 0.6 builds it. | 0.2; AD-23, AD-29 |
| B5 | Story 0.4 adds `ModelFamily` to the `Bridge.Data` classes; the enumerations Provenance, RequestKind, FallbackReason and ApprovalKind (exactly as the spine's conventions row), the extended ApprovalState and `Incident.NoticedAt` (A1), `ChatRef` (A3); names Decide's responses: `OcuTalon.Bridge.Msg.DecisionResponse` (for `decide` and `diagnose`: `DecisionRef`, outcome, payload, fallback reason) and `OcuTalon.Bridge.Msg.Reply` (for `turn` and `tool`). Item summary: code writes it, not the model. The bridge request gains `Summary` (one line: sender and subject for mail, otherwise the first line of text, at most 80 characters, set by the channel service), which the `Decision` row keeps and the decision event carries as `ItemSummary`; `DigestStore` stores it. The decision event also carries `ItemId`, and `SimMessage` stores the email's `ItemId`, so the mailbox row finds its decision. | 0.4, 1.12, 2.6, 2.8, 4.6; AD-6, conventions |
| B6 | Story 0.3 creates the two trace applications (`/ocutalon/trace/ocutalon/`, `/ocutalon/trace/ocuorders/`) with AD-24's seven permitted classes and no application roles, in the sign-in group. "No other page answers without a session" excepts the login page and `/ocutalon/public/status` (AD-13). | 0.3 |
| B7 | Story 0.7's checks add AD-3's public-package reference check, AD-19's single-reference check for `^OcuTalonPublic` (only `OcuTalon.Data.Public.Settings` may touch it, A2) and A4's production-region check; 0.7 creates `.github/workflows/lane-a.yml` with an empty standalone-bridge job (Lane A owns it after; 1.3 fills it). Story 0.8: the demo-path test is one Playwright spec per UJ-1 step under `web/e2e/demo-path/`. | 0.7, 0.8, 1.3 |
| B8 | Values: README account `ocutalon` with password `ocutalon` (local installs; the README says how to change it); custom request header `X-OcuTalon-Request: 1`; retag target `ocutalon-iris-base:2026.3.0AI.154.0`; the probe's `no_decision` bound 120 s; "the reset's window" = from the scheduled time until `/ocutalon/public/status` reports ready, at most 15 minutes; the variable that enables `EvalIn` is `OCUTALON_EVAL=1`; busy marker `X-OcuTalon-Busy: 1` (A8). | spine AD-13, AD-22, AD-23, AD-25; 0.1, 0.2, 0.5, 9.1, 16.6, 16.8 |

**Dependencies and fixtures**

| Id | Fix | Lands in |
| --- | --- | --- |
| B9 | Story 2.10 tests against fixture returns of the Epic 0 stubs of `Keys.Status` and `Budget.State`; its no-key CI test turns on when Story 1.6 merges. | 2.10 |
| B10 | Story 6.4 tests against a fixture `IncidentManager` (answers `dismiss` synchronously; fixture result payloads); the real path turns on in Epic 11. | 6.4 |
| B11 | Story 8.2's check-row assertion runs against a fixture watch and fixture `Checks` rows, and turns on for real once Epics 5 and 8 have merged on the integration branch. | 8.2 |
| B12 | Story 1.12 sends a fixture decision straight to `DigestStore`; the `OutcomeRouter` path is checked when Story 2.7 merges. | 1.12 |
| B13 | Diagnosis's read-only watch tools: Story 5.4 builds them (`OcuTalon.Tools.Watch`: the failure group's messages, errors and trace excerpt, read only); Stories 1.1 and 1.9 test against a fixture toolset of that name until then. | 1.1, 1.9, 5.4 |
| B14 | Epic 16's Depends on line adds, story-scoped: Story 16.7 needs Story 11.5's demo update hook, Story 16.10 needs Story 15.2's README IPM text, and the demo-path runs in Stories 16.2 and 16.10 turn on with Epic 11's end-to-end path. These are story-level edges; Epic 16 still starts after Epic 10 and Story 3.8. | Epic 16 entry |
| B15 | Later-step Lane B epics add their partner's first story: 18 on Story 17.1, 20 on 19.1, 21 on 22.1, 24 on 23.1, 25 on 26.1 (and A11's 0.1.1 gate on 17 and 18). | epic-list entries |
| B16 | About-dialog links: Lane B's Story 16.10 adds the About dialog's bridge-guide and security-overview links and the finish state's "Use the same bridge in your own production" link once Stories 13.3 and 14.2 have merged (hidden until then); 2.1 and 4.7 say "Story 16.10 adds it"; 13.3 and 14.2 supply the target paths. | 2.1, 4.7, 13.3, 14.2, 16.10 |
| B17 | AD-29: "The owning lane implements each API in the epic whose story first needs it (for example `Bridge.Approval` in Epic 3, `Checks.Render` in Epic 5; `Commands.Submit` and `Data.Public.Settings` in Epic 0); until then callers test against the stub with fixtures." | AD-29 |
| B18 | Story 4.1 says that none of the demo endpoints of Stories 4.2, 4.3 and 4.6 exists yet; each of those stories adds its own "demo mode off answers 404" criterion (4.3 and 4.6 gain it). Story 0.5's 501 for unbuilt routes stands. | 4.1, 4.3, 4.6 |

**Epics 4 to 9, 11, 12 and 15**

| Id | Fix | Lands in |
| --- | --- | --- |
| B19 | Story 4.2: `Guide.Compute`'s output adds the finish-state condition (a run that ended with an approved fix and a resolved incident) and the step-4 variants (paired or not, after a rejection, after a fallback notice); 4.7 renders them. | 4.2, 4.7 |
| B20 | Story 4.3 adds the audit criterion: the run is audited as an `Action` naming the IRIS user, the `SessionRef` and the channel (AD-17). | 4.3 |
| B21 | Story 4.6: `SimMailboxOut` is fixture-only in release 1 (nothing routes mail to it before step 4); its input is `OcuTalon.Msg.Outbound` with channel `mailbox`. | 4.6 |
| B22 | Story 6.4 and UX-DR79 render the mixed, still-resending and interrupted results of Story 7.5. | 6.4, UX-DR79 |
| B23 | UX-DR110 adds the daily-cap message key. | UX-DR110 |
| B24 | UX catalog slot sources: `{what will be resent}` becomes fixed wording "I'll resend {resend count} repaired copies" (count from the dry run; the web "Will resend" line uses it); `{item noun}` stays sourced from the diagnosis's structured result; `{readable item name}` and `{plain error summary}` are code-written (the item's name; the error's first sentence, at most 80 characters, through the redactor), because the fallback notice can't use the model. | EXPERIENCE catalog; 6.2, 7.2 |
| B25 | Epic 9: Story 9.2's push-time evaluation runs in `lane-a.yml`; Story 9.1 tests the Docker install, and its IPM case turns on in Story 15.3; Story 9.5 writes its summary and any override reason into the evaluation result file that Story 11.4's generator reads. | 9.1, 9.2, 9.5, 11.4, 15.3 |
| B26 | Story 11.1 drops "mocked Telegram". | 11.1 |
| B27 | Story 12.1's `/state` Telegram flag and README section move to Story 12.7 (with A3's `Included()`). | 12.1, 12.7 |
| B28 | Stories 15.2 and 15.3 and AD-23: the shell path runs `iris merge`, then `zpm "enable -map -ns OCUTALON"`, then the install command in OCUTALON (S19). | 15.2, 15.3; AD-23 |

### Section C: stale text and small inconsistencies (batch): APPROVED to the facilitator's judgement and applied

| Id | Fix | Lands in |
| --- | --- | --- |
| C1 | Telegram is 0.1.1 and Lane A everywhere. Epics: §4.4 heading (~62) and the FR-18 to FR-22 tags; the Lane B list (~231) exempts `OcuTalon.Channel.Telegram` from Epic 12 on; the checkpoint line (~234) records the October 17 move; the tag legend (~307) adds **R1.1** (0.1.1, Epic 12), and UX-DR55, 56, 109, 114 and 136 move to R1.1; Epic 2's coverage drops UX-DR55 and 56; Stories 16.9 and 16.10 (~3968, ~3990) say "0.1.1's Telegram channel"; Epic 11's upgrade record list says "a pairing, once Telegram ships". Spine: the ownership row (A3), the production note (~842). PRD: ~20, ~184, ~488, ~1252, ~1265, the "If Telegram slips" block (~1266-1268, now the plan), ~1425, ~1434. EXPERIENCE: ~61, ~81-92, ~577, ~581 (Telegram parts arrive with 0.1.1; ~17 itself doesn't mention Telegram, so that part of the finding is dropped); DESIGN ~732 marks the Telegram card 0.1.1; NOTES ~97 marks the checkpoint superseded. | all four |
| C2 | Epics ~230: Lane A's list adds `release/` and `.github/workflows/lane-a.yml`. | epics |
| C3 | Epics ~225: Epic 0's list adds `Tick`, `Bridge.Approval`, `Agent.Input`, `Checks.Render`, `Commands.Submit` (implemented, not a stub), the Orders partner service, its real transform and one recorded failure snapshot, plus A2's accessor and A3's `ChatRef` and `Included()`. | epics |
| C4 | Contradictions: Story 1.2 (~984): the merge method only merges, and `SettingsOps` restarts the runners; Story 3.5 (~1847): for kind `tool_call` `ApprovalHold` sends the replay instead (Story 3.6, spine AD-11); Story 1.12 (~1294) names `OcuTalon.Digest.Data.Item`, already in the spine. | epics |
| C5 | FR-3's inventory entry (epics ~40) matches PRD FR-3: tokens per turn; a model-request step carries an estimated size. | epics |
| C6 | PRD ~433: `/ocutalon/public/status` is a second unauthenticated exception (session-free, read-only); ~434 adds the host's busy page beside the maintenance page. | PRD |
| C7 | Late reminders, one definition: late if it fires more than 10 s after its due time, whatever the reason. PRD ~708 and EXPERIENCE ~744 ("Reminder (late; it was due at {time}): {text}."). | PRD, UX |
| C8 | Change 9 adopted through P23: EXPERIENCE ~628, ~909, ~924, ~936; UX-DR107, 144, 148, 153; NOTES ~138 (P6 decided by P23). The finding said NOTES calls it "proposed"; it says "waits for step 3 planning", equally stale. | UX, epics, notes |
| C9 | EXPERIENCE ~620 and UX-DR86 drop "R1 if cheap" (FR-13 requires the suspicious sample in step 1). | UX, epics |
| C10 | Logs: the PRD memlog records P14 to P24 (P17 to P23 PRD text; P15 withdrawn with its NFR-21 rewrite; P14, P16, P24 UX-only) and the other unlogged October 17 PRD edits (§7.1 row, §7.2 split, §7.4 rows, §11.1 rows); the UX memlog records P16 and P24. | memlogs |
| C11 | Sourceless criteria, recorded: Story 12.2's split at line breaks cites the Bot API's 4,096-character limit (a single longer line splits at the limit); Story 10.1's `.env` from `.env.example` cites AD-19 and FR-38; Story 9.4's "no cause category above 8 of the first 10" becomes AD-22's evaluation-set rule. | epics, AD-22 |
| C12 | AD-1 (~99): demo mode also changes through the documented admin terminal command (AD-19). | spine |
| C13 | Story 4.4: only "Hide guide" collapses the guide; a window under 680 px tall switches to the compact row (EXPERIENCE ~461). | epics |
| C14 | EXPERIENCE ~163 closes the banned list: "all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about"; Story 5.7 cites it. | UX, epics |
| C15 | Found during the checks: spine ~205's `SystemNote` example becomes "such as the note that an approved call ran" (matches AD-30); spine ~526's "P3, proposed" becomes applied; the UX Telegram Approve response's "50 orders" becomes "{count} {item noun}"; FR-23's "one approval request" becomes "share its approval requests" (A1). | spine, UX, PRD |

## 5. Implementation handoff

**Scope: Moderate.** It is a backlog reorganization: two new stories, contract changes in Epic 0, and dependency lines. No fundamental replan.

**Approval.** The author approved every section A decision on October 17 (recorded above), and approved sections B and C to the facilitator's best judgement on the same day. The edits were applied the same day.

**Applied and recorded:**

- **PRD and addendum:** `prd.md` edited; `.memlog.md` records P14 to P24 (backfill), the other October 17 edits, and P25 to P31. The addendum needed no change.
- **UX:** `EXPERIENCE.md` and `DESIGN.md` edited; `.memlog.md` records P14, P16 and P24 (backfill) and this change set.
- **Architecture:** `ARCHITECTURE-SPINE.md` (update intent, AD ids stable) and `ARCHITECTURE-NOTES.md` edited; `.memlog.md` records each decision.
- **Epics:** `epics.md` edited. The heading formats ("## Epic N:", "### Story N.M: Title") and each epic's `**Lane:** X. **Depends on:** …` line format are kept, and new stories take the next number in their epic.

**Check run.** The sprint-planning dry run parses 29 epics and 163 stories, with only the two known heading warnings (the document title and "Epic List").

**Next steps:**

1. Run `/bmad-sprint-planning` for the readiness gate and the tracking file.
2. The author reviews the planning documents and commits them when ready (nothing is committed).
3. The build starts after both, by October 21 at the latest; the dates are ceilings.

**For `/epic-cycle`'s dependency review:**

- Epic 16's new edges (Story 16.7 on 11.5, Story 16.10 on 15.2, the demo-path runs on Epic 11) are story-level, written as such in its Depends on line. Approve them as story-level edges, not as epic-blocking ones, or Epic 16 would wait for Epic 15 and miss November 1.
- The 0.1.1 gate on Epics 17 and 18 is an epic-level edge.

**Owner actions now listed as story preconditions:**

| Action | Before |
| --- | --- |
| The demo server and its DNS name | October 30 (Story 16.7) |
| The demo bot and its token, the real model key in the gateway, SSH access for the release hook | Story 16.7 |
| A clean macOS host and a clean Linux host with Docker and restricted outbound access, plus a Playwright driver host | Story 11.3 |
| Branch protection on `main` with the `ci.yml` and `lane-a.yml` checks required | Story 11.5's first run |
| A real bot token for the rehearsal; iOS, Android and desktop Telegram clients | Story 12.7 |
| Separate client addresses for the load test | Story 16.10 |

**Success criteria:**

- The readiness gate passes.
- Each lane can start its first story without editing the other lane's files.
- Every story's criteria can be tested as written.

## 6. Checklist status

| Item | Status |
| --- | --- |
| 1.1 to 1.3 Trigger, problem, evidence | [x] Done: readiness-gate FAIL; contract gaps between lanes; every finding verified against the current text |
| 2.1 to 2.5 Epic impact | [x] Done: no epic invalidated, two stories added, dependency lines adjusted, no resequencing |
| 3.1 PRD | [x] Done: P25 to P31; the MVP floor unchanged |
| 3.2 Architecture | [x] Done: update intent, AD ids stable |
| 3.3 UX | [x] Done |
| 3.4 Other artifacts | [N/A] No code, CI or deployment files exist yet; their future contents are fixed in the stories |
| 4.1 Direct adjustment | [x] Viable: selected (effort medium, risk low) |
| 4.2 Rollback | [N/A] Nothing is built |
| 4.3 MVP review | [N/A] Not needed; the floor stands |
| 5.1 to 5.5 Proposal components | [x] Done |
| 6.1 to 6.3 Review and approval | [x] Done: section A decided item by item; B and C approved to the facilitator's judgement |
| 6.4 sprint-status.yaml | [N/A] Doesn't exist yet; sprint planning generates it |
| 6.5 Next steps | [x] Done (section 5) |
