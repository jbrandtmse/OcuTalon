---
project: OcuTalon
date: 2026-10-18
trigger: implementation-readiness gate re-run (bmad-sprint-planning) returned FAIL on 2026-10-17, after the correct-course run of the same day
mode: direct fixes at the author's request ("fix these issues, updating the architecture spine and PRD accordingly")
status: applied (2026-10-18); not committed
---

# Sprint Change Proposal: readiness re-run fixes (October 18, 2026)

## 1. Issue summary

The October 17 correct-course run (`sprint-change-proposal-2026-10-17.md`) fixed the first gate's findings. A second gate run the same day still returned **FAIL**, with 7 high, 18 medium and 14 low findings. Each finding was checked against the current text, and none reopened a settled decision.

- **Problem type:** cross-lane contracts that no document fixes, a few contradictions, and stale copies of changed requirements. There is no new requirement, no pivot and no re-sizing.
- **The highest-impact gaps:**
  - Story 10.3 didn't give Epic 12 everything it needs from Lane B.
  - The online-demo flag was read before it was written.
  - Nothing defined the decision message from `Intake` to `DigestStore` and `EvalSink`.
  - AD-15 didn't cover overlapping approval requests.
  - The release sequence couldn't run as written.
  - P30's CI timing checks contradicted §5.
  - Later Lane B stories needed Lane A's Telegram code.
- **Settled and unchanged:**
  - plan, pace and lanes;
  - Telegram as Epic 12 in Lane A, shipping as 0.1.1;
  - Epic 0 contracts first;
  - P3 to P31 and decisions A1 to A11;
  - Epic 16's three story-level edges.
- **Epic and story counts:** still 29 epics and 163 stories. No story was added or removed, and none moved between lanes.

## 2. Decisions applied

Each id below is the finding's id from the re-run. The full findings, with evidence, are in the re-run report. The exact names and values are fixed once here, and every document uses them.

### High

- **G1. The Telegram split.** Lane B's Story 10.3 now builds everything Epic 12 calls:
  - `AnswersIn`'s Telegram entry. It takes the press's `ChatRef` and returns a result code: `approved`, `rejected`, `already_answered`, `expired`, `not_paired`, `not_visible`, `not_allowed` or `unknown`. `TelegramIn` turns `expired` into the request's expired status, "Expired at {time}. Nothing was changed."
  - The pairing-code endpoint's 409, sent while Telegram isn't on or is paused.
  - `/state`'s Telegram block (`included`, `state`, `botUserName`, `paired`, `displayName`, `pausedUntil`), recorded through `StatusMark.RecordTelegram(state, botUserName)`.
  - `Pairing.HashCode(code)` (SHA-256, base64url) and `Pairing.TakeReplySlot(chatRef)`.
  - `SessionOps` telling a chat that was dropped without its own action: after a page Unpair, or when the session pairs a second chat. A chat that moves to another session started that move itself, so it gets its normal pair reply.
  - The `Delivery` API, `Delivery.Record` and `Delivery.FindByApproval`. It is declared in Epic 0 and implemented in Story 2.7.
  - The mock's Telegram scenario form (match by Bot API method).
  - The QR-code library, the typed client methods, and the skipped `web/e2e/demo-path/telegram-*.spec.ts` files. Lane A owns those spec files from Epic 12.

  Related changes:
  - `TryConsume(SessionRef, Channel, Text)` records the refused turn. On the first refusal, the channel service sends the allowance notice; A9 is kept.
  - There is one release switch: the Telegram items run only when `Included()` returns 1 and a token is set.
  - `Included()` gets a test-only seam.
  - `TelegramIn` renders its own button-press alert. This is the one exception to the rendering rule.
- **G2. Install order.** The `Public` step now runs first among the installer steps. It writes the public settings and `Decide`'s budget host settings (`DailyCostCapUSD`, `GatewaySpendUSD`, `GatewaySpendDate`) before roles and users, web applications and `Production`. It sets readiness last. Every reader of the online-demo flag goes through `OcuTalon.Data.Public.Settings`.
- **G3. The decision message.** A new Lane B class, `OcuTalon.Msg.ItemDecision`, holds `ItemId`, `SourceItemId`, `OwnerRef`, `Channel`, `Summary`, `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason`. `Intake` sends it to `OutcomeRouter` (which forwards it to `DigestStore`) or to `EvalSink`. `Item` gains `SourceItemId`, which only `EvalIn` sets.
- **G4. Overlapping approval requests.** AD-15 gains four transition rows:
  - a later request approved while fixing waits, since one fix runs at a time per incident;
  - a later request rejected or expired while fixing leaves the incident fixing;
  - a rejection or expiry while another request is pending leaves it awaiting approval;
  - a final result with an approved request waiting sends that request's `Execute`.

  "Latest outcome" is defined, and a cancelled request is defined to send no outcome. Each approval request card carries its own result band.
- **G5. Release sequence.**
  - **Candidates.** Each candidate is a branch, `release/<version>-rc<n>`, identified by version and commit SHA. Pushing the candidate is the first outward step, on the author's word.
  - **Records** go in `release/records/<version>/rc<n>.md` on the integration branch.
  - **Hands-on gate.** The sequence stops at the hands-on gate and resumes once the pass is recorded. Only a build step's release needs a fresh pass.
  - **Proving the sequence.** Story 11.5 proves itself on a rehearsal candidate. Story 11.6 runs the real 0.1.0 cut.
  - **Clean hosts.** Story 11.3 reaches the clean hosts over SSH and copies the candidate as a git bundle.
- **G6. CI timing checks.** PRD §5 now says CI checks the FR-1, FR-8 and FR-18 limits (5 seconds) and the NFR-9 limit (2 seconds) against the mock on every run (P30). Stories 2.2, 2.7, 6.3, 12.4 and 12.7 add those checks. Stories 11.3 and 16.10 add "at least 19 of 20 runs".
- **G7. Later steps.** A new AD-29 rule: Lane B's first story in each step creates that step's command verbs, and a Lane A story that uses one declares a story-level edge to it. The Telegram parts of Stories 18.4, 24.3 and 25.5 move to Stories 17.6, 23.4 and 26.4. New story-level edges:
  - 17.6 → 18.1
  - 19.3 → 20.1
  - 22.2 → 21.1 (22.1's command handling moves to 22.2)
  - 23.4 → 24.1
  - 26.4 → 25.5

### Medium and low

- **M1, M2.** The epics' copies of the requirements and UX-DRs now match the current PRD and EXPERIENCE. Story 2.7 uses the current late-reminder text.
- **M3.** The `NoticedAt` filter is built in Story 2.2, by Lane B, which owns the ownership API.
- **M4.** An approved fix that can't start sends a final result ("Nothing was resent: {reason}. Nothing was changed."). `Checks` calls `OcuTalon.Fix.Run.Sweep()` on each heartbeat to send final results for in-progress and interrupted runs.
- **M5.** `DiagnosisPayload.ItemNoun` holds the singular and plural forms. The fallback notice takes its noun from `OcuTalon.Watch.ItemNoun`.
- **M6.** New UX-DR155 (notice without a fix) and UX-DR156 (later approval request), with render tests and complete Telegram key lists.
- **M7 (P32).** `/ocutalon/public/status` also reports the last reset's time and kind.
- **M8.** The daily-cap chat message is sent on the online demo only.
- **M9.** The 90-day purge task uses type `all`. All three purge tasks run daily at 03:00 instance time.
- **M10.** Epic 0 enables every stub except `TelegramIn`, `TelegramOut` and `EvalIn`. Before a release cut, any item whose story hasn't merged is disabled.
- **M11.** Epic 0 creates the bridge's extension base classes (`OcuTalon.Bridge.Ext.HostSink`, `.ReplyFilter`, `.Classification`) and stubs of `BridgeSink` and `ReplyGuard`. The HostSink payloads are now fixed per event:
  - `decision.*` and `approval.*` carry the record's public `Ref`;
  - `turn.step` carries `{decisionRef, label}`, with the session as `ownerRef`, so the bridge never needs OcuTalon's `Turn` table;
  - `budget.capped` carries `{day}`, with `ownerRef` `instance`.
- **M12.** Stories 2.7, 2.8, 2.9, 4.6, 16.4 and 16.9 gain fixture clauses. Stories 11.1 and 16.10 turn the real paths on.
- **M13.** AD-25 fixes the `ocutalon-demo status` JSON and the result of `update`, and exempts the update's own restore from the version check.
- **M15.** Command-verb edges; see G7.
- **M16.** Every "turns on when … merges" clause now names the story that turns it on. Story 15.3 picks up 9.1's IPM case.
- **M17.** One Telegram switch, the code hash, and the `Included()` test seam; see G1.
- **M18.** Stale later-step text fixed: the XData wording in 17.1 and 19.1, P6 in 19.1, and the story references in 26.2 and 16.7.
- **L1 to L14.** Wording and small contract fixes:
  - Story 16.7 lists every AD-19 variable.
  - `Purge(daysToKeep)` is used throughout.
  - "Written at every start" replaces "seeded".
  - §11.1 dates now say November 1.
  - Story 2.1's About links agree.
  - Story 8.1 says Epic 0 builds the task step.
  - Story 12.7 marks its fixture text.
  - Clearing readiness checks that the accessor class exists.
  - IncidentCommand's verbs are named, and there is a new IncidentOpenVariant enumeration.
  - `OCUTALON_EVAL` is passed through the CI override.
  - REL-2 says mocked Telegram applies from 0.1.1.
  - The Lane fields are bare.
  - Story 0.4 creates every release-1 catalog key.
- **Also fixed:** FR-60's pairing check applies once the previous release includes Telegram. The restart check includes it from 0.1.1, and the upgrade check from 0.1.2.
- **Also aligned while applying the fixes**, wherever a document stated the old rule:
  - **PRD.** FR-24: a rejection or expiry returns the incident to open unless another request is pending or a fix is running (AD-15). FR-6: the paired chat survives restarts from 0.1.1.
  - **Inventory.** UX-DR79 (one result band per request; the "Couldn't start" text) and UX-DR97 (the daily-cap chat message is online-demo only).
  - **Release-1 stories.**
    - Story 4.4 quotes the new Break the feed hint.
    - Story 4.5 turns on the phone half of 2.7's FR-1 CI check.
    - Story 11.2 states the new install order.
  - **Kit and later-step stories.**
    - Story 15.2 states the new install order and the single Telegram switch.
    - Story 16.8's resetting view also passes `?since=`.
    - Story 17.6 also takes `TelegramOut`'s digest rendering, and Story 23.4 also takes `TelegramOut`'s page delivery.
    - Story 19.3's edge names both the save-memory and forget verbs.
    - Story 21.4 points the add command to Story 22.2.
  - **Design and UX.**
    - DESIGN's incident-card bar rule names the no-fix variant.
    - The "Couldn't start" band uses the `result-partial` style.
    - Dismiss sits on the last request's band.
- **Left as is on purpose:** Stories 21.5 and 24.4 (Lane B) check that new catalog texts appear in Telegram. `TelegramOut` renders any catalog key generically (Story 12.6), so no Lane A file has to change for them.

### Verification round

Three independent read-only checks confirmed every finding resolved. They found 16 smaller follow-ups, which are applied as follows.

**PRD and spine**
- **FR-8 Reject bullet.** It now matches FR-24: the incident returns to open unless another request is pending or a fix is running. The copies at E 48, E 73 and UX-DR74 say the same.
- **REL-3.** The 15 minutes now exclude both CI and the REL-7 hands-on pass. Both copies are updated.

**Contracts**
- **`Delivery.FindByApproval(approvalRef, channel, ownerRef)`.** There is one row per session's copy, and a Telegram message id is `<ChatRef>:<message_id>`, so an edit can't reach another chat.
- **AD-15.** The final-result row applies only when no approved request is waiting, and a waiting request starts in order (earliest first).
- **Purge.** The 7-day task sets `BodiesToo`.
- **Item owner.** An Item's `SessionRef` may be `eval` (only `EvalIn` sets it). `Intake` copies it to `ItemDecision.OwnerRef`.
- **Item noun slot.** It is `itemNoun: {"one", "other"}`, and the form is picked by `count`.
- **Catalog keys.** Epic 0 creates every release-1 and 0.1.1 catalog key, including the answered statuses, the Results, and Telegram's pairing replies and press alerts (in `Catalog.Core`). Telegram gains an expired-press alert, "Expired at {time}. Nothing was changed."
- **`TakeReplySlot`.** It throttles only replies to other messages from an unpaired chat, not replies to a code, `/start` or `/help`.

**Stories**
- **Story 7.3.** An `Execute` waits while another fix of the incident runs.
- **Story 6.4.** Dismiss sits only on the last request's band.
- **Story 10.3.** It tests a counted and allowed Telegram call. Story 16.9 tests the Telegram refusal with a fixture.
- **Stories 2.8 and 4.2.** They read the Telegram flag safely before Story 10.3 lands.
- **Later-step `handled` notifications.** Stories 18.1 and 24.1 add a `handled` notification and a `Delivery` lookup by the notice's or page's `Ref`, so every copy updates after a Got it.

**Dependency edges**
- Story 23.8 needs Story 24.1.
- Story 26.2 needs Story 25.3.

**Release sequence**
- **Rehearsal.** A declined step is skipped. The stand-in builds from the rehearsal candidate's commit. A rehearsal never carries a pass over.
- **Records.** The candidate's record goes to the integration branch on the author's word whenever the sequence stops.
- **Results.** The rehearsal's and the harness's results go into the candidate's record, never onto the frozen candidate.

**Considered and dropped:** a CI trigger for candidate branches. Story 0.7 already runs CI on every push.

### Not changed: accepted by the author

- **M14.** Story 16.10's isolation and load tests wait behind its settled edge to Story 15.2, so they may run after the public launch (November 2 to 4) if Lane A is late. **The author accepted this on October 18:** it's fine if 16.10 runs late. Story 16.10 and its edge to Story 15.2 stay as they are.

## 2b. Second round: the gate re-run on October 18

A fresh four-part review of the whole plan on October 18 still returned **FAIL**: 5 high findings in release 1, 0.1.1 and the kit; 1 critical and 1 high in later steps; and about 20 medium ones. The author asked for all of them to be fixed before the tracking file is generated. Each was checked against the current text first. No settled decision was reopened, B15's partner edges included, and the plan still has 29 epics and 163 stories.

### High and critical

1. **Fixed notice text travels with its item.** `Item` and `ItemDecision` gain optional `CatalogKey` and `Slots`. `OutcomeRouter` uses them for tell-now and act. Otherwise it uses the tell-now key, with `{what happened}` taken from the item's `Summary` and `{reason}` from the decision's first reason. EXPERIENCE now records these sources.
2. **The README account opens Visual Trace.** On a local install it now also holds `OcuTalonTraceViewer` (**P33**, PRD FR-11).
3. **Epic 0 fixes the remaining cross-lane shapes:**
   - `Reply.Busy` (never an error status);
   - `Reply`'s full field list;
   - the `incident` live payload's fields;
   - the stored dry run's keys;
   - `Decision.TraceSessionId`;
   - the reminder verbs: `SetReminder` takes exactly one due form (`DueAt`, `DelaySeconds` or `LocalDueAt`), alongside `CancelReminder` and `ListReminders`;
   - one renderer, `OcuTalon.Msg.Catalog.Render`.

   The "the other lane appends" clauses are gone.
4. **`AnswersIn`'s Telegram result carries its slots:** the count and item noun, the winner, and the expiry time.
5. **`main` is merged back into the integration branch after each release,** so the next release pull request doesn't conflict.
6. **Step 6 no longer deadlocks.**
   - Story 26.1 runs on a developer image (`pdfplumber` 0.11.10 and `python-docx` 1.1.2) until Story 25.1 pins the packages, and it has stubs in code.
   - Stories 25.4 and 25.5 use fixture roles.
   - Story 26.2 runs the tests on the real image.
7. **Step 4 work has owners.**
   - `SettingsOps.RestartRunners()` (Story 21.1);
   - `Mcp.Ops.Tools(server)` (stub in 22.1, built in 22.2);
   - `BridgeSink` sends the notices for a fix request with no incident (Story 21.5).

### Medium

- **Notices and fix messages.** `answered` and `result` notifications carry `ApprovalRef` and `IncidentRef`, and buttons appear only on kinds `incident` and `approval`. Story 5.5 creates `OcuTalon.Fix.Msg.Execute` and `.FixResult`.
- **Lane order.** Story 3.1 sets the online-demo flag itself on its test stack instead of waiting for Story 3.8.
- **Evaluation.** Chat-turn cases reach `EvalSink` as Lane A's `OcuTalon.Eval.Msg.TurnResult`.
- **CI and README.**
  - The mock matches a guide prompt that the message contains.
  - The README's Telegram link shows only once Telegram is included.
  - The storage-diff check is a no-op until the first release tag.
- **The Demo step.** It has a fixed place in the start order. The OCUORDERS trace application and grants exist only with demo mode on, and the roles step rebuilds without them while the Demo step adds them back.
- **Small contracts.**
  - `BridgeSink` publishes nothing for evaluation runs.
  - The rail's Telegram card is its own component at `web/src/app/rail/telegram-card/`.
  - The FR-6 copy is fixed, the coverage lines are aligned, and the error-summary rule is copied into the stories.
- **Release sequence and demo host.**
  - Story 12.7's hand-run timings are recorded once, in the 0.1.1 candidate's record.
  - The re-cut base is defined.
  - The release hook copies a `git bundle` to the demo host.
- **Fixtures and file hand-offs.**
  - Story 16.3 uses a fixture pairing.
  - Story 15.2 writes `docs/install-ipm.md`, and Story 22.6 hands its README link to Story 24.1.
- **Epic 16's Depends on line** now says "Story X needs Story Y" for all three story-level edges. Its epic level still names only Epics 10 and 3.
- **Step 3 sign-out.** It drops a demo session's documents and memories through `OcuTalon.Docs.DropSession` and `OcuTalon.Memory.DropSession` (Story 19.5, called from 20.1).
- **Step 2 setting keys** are named in Story 17.1.

## 3. Documents changed

- **PRD:** `prd.md` (§4.3 status endpoint, P32; FR-6; FR-8; FR-11, P33; FR-24; FR-60; REL-2; REL-3; REL-10; §5 intro; §11.1 dates) and `.memlog.md`.
- **UX:** `EXPERIENCE.md` (result band per request, the "Couldn't start" result, slot sources, the local daily-cap state, guide wording) and `DESIGN.md` (result notice), with `.memlog.md`.
- **Architecture:** `ARCHITECTURE-SPINE.md` (update intent; AD ids stable), `ARCHITECTURE-NOTES.md` (P32 row) and `.memlog.md`.
- **Epics:** `epics.md`. The inventory, epic list and stories are changed. The headings and the Lane and Depends on line format are kept.

## 4. Next steps

1. The author reviews the changes. Nothing is committed.
2. Re-run `/bmad-sprint-planning` for the readiness gate and the tracking file.
3. For `/epic-cycle`:
   - Epic 16's edges (Story 16.7 on 11.5, Story 16.10 on 15.2, the demo-path runs on Story 11.1) stay story-level.
   - The new later-step edges in G7 are story-level too.
   - The 0.1.1 gate on Epics 17 and 18 is epic-level.
