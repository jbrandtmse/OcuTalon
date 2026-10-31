# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Release 1 (0.1.0, the floor) ships. The epic has five parts:

- The whole web demo path (UJ-1 without Telegram) passes end to end on real components in the REL-2 Playwright test, with nothing left on fixtures.
- An in-place upgrade from the previous release, and a container restart, keep every conversation, reminder, approval request, watch and setting.
- A clean-machine rehearsal on the real model measures the timing bounds.
- One scripted sequence takes the integration branch to a tagged release. It runs every gate (CI, the release-candidate evaluation, upgrade, rehearsal, checklist and the Contest Planner's hands-on pass) and stops for the author's word before every outward step.
- The release checklist covers naming, licence notices and public text.

Epic 11 is the release-1 merge point. Telegram (Epic 12) merges only after the `v0.1.0` tag and ships as 0.1.1.

## Stories

- Story 11.0: Epic 10 Deferred Cleanup (inserted; DW-237)
- Story 11.1: The web demo path passes end to end in the REL-2 test
- Story 11.2: Upgrades and restarts keep every record working
- Story 11.3: The clean-machine rehearsal installs and times the demo path
- Story 11.4: The release gets draft notes and a checklist
- Story 11.5: One scripted sequence cuts a release
- Story 11.6: A hands-on pass with real keys finds and fixes what the tests missed before 0.1.0

## Requirements & Constraints

**Story 11.0, one pairing hash helper (AD-4)**
- `Pairing.HashCode(code)` delegates to `Session.Hash(code)`, and an empty code still answers "".
- Every stored hash keeps its value byte for byte, and the Pairing and pairing-API tests stay green.

**The REL-2 demo path (Story 11.1)**
- **Which checks it turns on.**
  - Every UJ-1 step spec under `web/e2e/demo-path/` except the `telegram-*` files is turned on, and they pass in order: sign-in, watch, reminder, incident, approval, trace.
  - The online run's steps 2 to 6 in `web/e2e-online/demo-path.spec.ts` are turned on too (DW-221).
  - So is every check that a "turns on when … merges" clause in Epics 0 to 10 left off. The exception is a clause that names a story in Epic 30 or 31: that story turns it on (for example DW-99, which goes to Story 30.3).
- **Main path.**
  - The watch step shows the Act strip with its reasons and trace link, the "Orders production" check row with a real last run (DW-202, which also drops 8.2's fixture block), and an active Break the feed.
  - The reminder row appears.
  - Break the feed leads to one incident card awaiting approval, in the chat and on the simulated phone, and the rail shows "Approval requests (1)". The reminder lands during the wait.
  - Approve on the phone, then the result, then the trace.
- **Audit.** After the browser steps, the same job reads the IRIS audit log, polling with a timeout. It must find the approval's answered entry and the resend's action entry for the run's session, with no key, token, password or Telegram identity in either.
- **Failure paths.**
  - Reject, then Dismiss, then a replay that opens a new incident with its own request.
  - A mocked refusal shows the fallback card with its failure groups and no fix, and step 5 still opens the trace.
- **Coda.**
  - The newsletter is decided Ignore, and nothing reaches the phone.
  - The suspicious request leads to no approval request, resend or setting change.
  - The CI budget is 35 minutes per group (REL-4).
- **Against the real model** (release-candidate or rehearsal runs), assert only that a decision with reasons and a trace link appears, never which outcome. Specific outcomes are asserted only on the CI mock.
- **Ledger items it carries:**
  - **DW-294:** after a reload, an incident card's footer finds its diagnose decision. `/state` or the incident payload carries it, and the store reads it.
  - **DW-140 (U-118):** `cancel_reminder` takes one or more ids and sends one `CancelReminder` per id within one tool call, each with its own `IdempotencyKey`. AD-20's ceiling of 4 iterations does not change.
  - **DW-142 (U-118):** Chat's instruction lines say it can set, list and cancel reminders, and keep the no-commands rule for everything else. A live Haiku 5.5 check of the guide's step-2 sentence plus two paraphrases must pass before 0.1.0.
  - **DW-307:** under the mock, a prompt-selected B scenario also answers the Triage request, so triage ends as an invalid fallback.
  - **DW-340:** 03-reminder must accept step 2 as "upcoming" or "current".
  - **DW-316:** make Lane A's agent-step checker a public helper that `Test.Schedule.ReminderChat` calls.
  - **Flakes that block a green REL-2:**
    - DW-349: seed fixture check rows that are not due, for example `nextDueAt` = now + 1 h.
    - DW-376: the fixed wait on the Task Manager's `RunNow`.
    - DW-396: `test-ci-warm.sh`'s 1 s lock wait.

**Upgrade and restart harness (Story 11.2, `release/`)**
- **Setup.**
  - It runs only in throwaway compose projects with the CI override, never against a developer instance.
  - It builds the previous release's image from its tag on the machine it runs on.
  - Through the product's own API and the mock, it creates: a conversation of several turns, a reminder due after the upgrade, a pending approval request from a Break the feed run, and an Orders watch.
  - The settings change is made in a second project of the previous release: `SetDemoMode(0)`, release 1's only run-time settings writer.
- **The upgrade** starts the candidate's image on the same volume. The after-start steps run and re-arm `ApprovalHold` and `ReminderTimer` from their rows, and the installed version must equal the candidate's.
- **After the upgrade, each record must still work:**
  - The conversation's next turn answers in its history.
  - The reminder fires, marked late if it fell due during the upgrade.
  - The approval request is still pending with its original expiry. Approving it ends with "All 50 orders went through."
  - The watch picks up a new Break the feed run as a new incident.
  - In the second project, demo mode is still off, OCUORDERS is absent and the page shows no demo feature.
- **The restart test (FR-6).** The mock's log shows that the next turn's first request carries the earlier conversation, and a scenario whose question only the pre-restart conversation can answer passes.
- **Storage.**
  - The storage diff against the previous tag finds no renamed, retyped or removed stored property.
  - Every private global still resolves to the private database.
- **Reporting.**
  - It writes pass or fail per record to `release/records/<version>/rc<n>.md`, and any failure blocks the release.
  - It is required from 0.1.1. For 0.1.0, which has no previous release (no `v*` tag exists yet), it runs from a pre-release build of the integration branch, to prove the harness itself.
  - Pairings join the harness only from Story 12.7.

**Clean-machine rehearsal (Story 11.3, `release/`)**
- **Hosts.**
  - The author provides a clean macOS host, a clean Linux host and a driver host with Node.js and Playwright, and restores each clean host for every candidate. Their addresses and keys live in the author's configuration outside the repository.
  - Outbound access is limited to the model provider, and no other destination may be contacted.
- **Install.**
  - The script copies the candidate to each host as a `git bundle` and runs `install.sh` with the real key in `.env`.
  - It records the first start's duration, install included, for the README.
  - It never prints an `.env` value: `compose config` runs only with `--quiet`, and `inspect` only with `--format`.
- **Runs.** 20 runs of the web demo path per host, on Haiku 5.5, with no mock in the compose file, using Run again and the replay rule between runs.
- **Bounds (each met in at least 19 of 20 runs unless stated):**
  - NFR-7: Break the feed to the phone's notice takes at most 60 s. Each run splits it, from production message timestamps, into pick-up (≤ 15 s), the settle rule's end (≤ 30 s after the first failure), diagnosis (≤ 20 s) and delivery (≤ 5 s). The report gives the median against the typical target of about 35 s.
  - Step 1's decision takes at most 10 s.
  - The approval result reaches the page within 2 s.
  - Each reminder fires within 10 s of its due time.
  - No request is over 100,000 input tokens.
  - A tell-now sample email takes at most 5 s from decision to phone.
  - The report also records the first reply's time, and when the reminder lands relative to "All 50 orders went through.".
- **Failure.** Any failure blocks the release, and the report names the run, the step and the bound. The record describes a machine only by OS, CPU architecture and memory, and the release notes record both hosts.

**Notes and checklist (Story 11.4, `release/`)**
- **The notes generator.**
  - It drafts plain-language notes grouped by area, from the stories merged since the previous tag, claiming only what ships. Class names and error codes appear only in a developer section.
  - It includes the evaluation summary from `eval/release-candidate.json` (scores, mean and maximum cost, with `maxUSD` the gated figure, the largest request and any REL-5 override), the rehearsal timings and the upgrade result.
- **The checklist's automated items.**
  - The README and the About text carry the not-affiliated note verbatim.
  - The product name never contains "OpenClaw".
  - Every bundled third-party package, font and icon set keeps its licence notice.
  - The public-text check passes on every tracked file and on the draft notes.
  - No file from `irislib/` or `irissys/` is tracked.
  - DW-359: every README link and GitHub heading slug is rechecked on the public page. The repository stays private until the Open Exchange release.
- **Items the author confirms.**
  - No code, prompts or workflows copied from OpenClaw or an OpenClaw-style project, and none of its logo or artwork.
  - Nothing copied from InterSystems' AI Hub examples.
  - Before going public, a recorded review of every file under `_bmad-output/` and the agent instructions, for keys, local paths, private infrastructure and other entrants' names.
- **Outward actions.** The checklist states that posts, articles, the video and bonus claims are the author's own actions. No script posts anything.

**Release sequence (Story 11.5, `release/`)**
- **The version.**
  - Before the first public release it must be 0.1.x. 1.0.0 is accepted only when the author asks for it and confirms the 1.0.0 kit is in. A version that is already tagged is refused.
  - The sequence sets it in `src/module.xml` (which already reads 0.1.0). The package, the ready marker and the About dialog report it.
- **The cut.**
  - The sequence builds the web bundle and commits it on a new `release/<version>-rc<n>` branch. That commit is the cut: the candidate is its version plus the commit SHA, and the branch is never changed after it.
  - It checks the version inside the built image.
  - A failed gate means a fix on the integration branch, then `rc<n+1>`.
- **The record.** It lives on the integration branch, in `release/records/<version>/rc<n>.md`. It holds the SHA, each gate's result, the hands-on pass (each finding with its fix or its deferral) and the author's hands-on time, which must be at most 15 minutes, not counting CI or the pass.
- **Gates, in order:**
  1. the full CI run;
  2. the release-candidate evaluation with the demo incident gate;
  3. the upgrade harness;
  4. the rehearsal;
  5. the checklist;
  6. the hands-on pass.

  The REL-5 override is the only one accepted. The sequence refuses a candidate with an enabled item that answers "not implemented" (`Parameter STUB = 1`).
- **The hands-on gate.** The sequence stops and names the candidate to install. The resume command refuses to go on until the record holds a pass or a carry-over for this candidate.
  - A re-cut from the passed candidate plus cherry-picked fix commits carries the pass over, with the Contest Planner's note.
  - A re-cut from the integration branch's head needs a fresh pass.
  - A rehearsal record never carries a pass.
- **Outward steps.** Each one waits for the author's word (a declined step is skipped):
  1. Push the candidate branch.
  2. Open the release pull request.
  3. Merge to `main`, with the `ci.yml` and `lane-a.yml` checks required. On a private GitHub Free repository branch protection answers HTTP 403, so the sequence checks every job of the pull request's head commit itself and records that it did so.
  4. Tag the release.
  5. Merge `main` back into the integration branch.
  6. Update the online demo.

  The candidate's record may be committed and pushed whenever the sequence stops. The sequence never publishes the notes, pushes an image, signs in to a registry or prints an environment value.
- **The demo update hook (AD-25).**
  - It sends a `git bundle` of `v<version>` over SSH, then calls `ocutalon-demo update <version>` on the host.
  - Before launch the host answers `{"result":"updated",...}`. After launch it answers `{"result":"scheduled","at":...}`, and that time goes into the notes.
  - It then checks `ocutalon-demo status`'s JSON: the running and golden versions, or `pendingVersion` for a scheduled update.
  - With no demo host configured, it says so, and the notes say the online demo wasn't updated.
  - It is tested against a throwaway stand-in host.
- **A rehearsal of the sequence** runs on a rehearsal candidate with a fixture pass record before the real 0.1.0 cut.
- **DW-27.** Before the repository goes public, a fork pull request must not be able to merge without a demo-path run, through branch protection or a maintainer-run path. These settings are the owner's alone.

**Hands-on pass (Story 11.6)**
- The Contest Planner installs the 0.1.0 candidate from the README with Docker and a real key. It runs UJ-1's web route by hand, with no Telegram, and records each finding with its fix or its deferral.
- Its ledger items:
  - DW-299: the guide reaches its 56 px compact form while the Break the feed box shows, so the incident card's controls are in view at 1280×600.
  - DW-358: a live "cancel all my reminders" with three or more pending.
  - DW-365: a reused `fixSummary` count contradicts a later round.
- **Readiness ruling U-186 (veto).** Build every part that can be built now: the scripts, the harness, the notes, the checklist and the rehearsal mode. Park each human-only part with its own item:
  - Story 11.3's hosts and real-key runs;
  - Story 11.6's pass;
  - the live checks for DW-142 and DW-358;
  - the real 0.1.0 cut.

## Technical Decisions

- **Spine.** The contract is `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` (33 ADs). The key ones here are AD-5, AD-22, AD-23, AD-25, AD-29, AD-17, AD-19 and AD-26.
- **Footprint (AD-29).**
  - Epic 11 is Lane A's, on runner A (`ocutalon-slot-a`). `release/` is Lane A's folder.
  - As the release-1 merge point, Epic 11 may change either lane's files to make the end-to-end path pass. The orchestrator serializes it against overlapping epics, which today means Epic 12, Epic 30 and Story 10.4's README.
  - The `telegram-*.spec.ts` files are Lane A's from Epic 12, and they stay off.
  - Mock scenarios: Lane A adds files under `ci/mock/scenarios/A/`. Mock behaviour is Lane B's code.
- **State (AD-5).**
  - All state is on the durable volume, and every install replaces only code.
  - Storage is append-only, with committed `Storage` blocks. The CI diff compares against the highest earlier `v*` tag, and a shallow clone fails.
  - Only `ApprovalHold` and `ReminderTimer` hold long timers. Each mirrors its row, and the reconciler re-arms a pending row whose process is gone.
- **The after-start order (AD-23).**
  1. Clear the ready marker and readiness.
  2. Upgrade IPM and `ocutalon`, version-gated.
  3. Run the installer steps: Bridge installer, then `Public`, roles and users, Web, SSL, tasks, `Demo`, Config Store, audit events and Telegram items.
  4. `Production` (recovering a Troubled production).
  5. `Reconcile`.
  6. `SetReady`.
  7. The ready marker, holding the version.

  The log is `/durable/ocutalon-after-start.log`, with one `STEP` line per step and `RESULT OK <version>`. The health check passes only when the ready marker equals the image's version. A cached build context can bake stale sources, so release steps check the version inside the image.
- **Secrets and CI (AD-19, AD-22).**
  - Keys come only from `.env`, and are never in IRIS, a log, a commit or the trace.
  - Nothing runs `docker push` or a registry sign-in.
  - `compose config` runs only with `--quiet`, and `inspect` only with `--format`.
  - The AI Hub image never enters a cache or an artifact.
  - Fork pull requests never run on the IRIS runner.
  - Key-like patterns have one definition, `docker/tests/lib-keys.sh`.
  - The release-candidate eval is `eval/run.sh --release-candidate` (Stories 9.5 and 9.10).
- **Model.** Claude Haiku 5.5 is the default, with `max_tokens` 8,000 and no temperature, top_p or top_k.
- **Demo path in CI.** The unit `live:demo-path` runs first in the `browser` group, on a fresh throwaway. A skipped step never counts as a pass, and `@floor` tests must pass. Specs mark unfinished checks with `notBuilt(..., '<story>')`.
- **Audit (AD-17).** `Bridge.Audit` is the only writer. Tests read entries back by polling with a timeout, because IRIS writes some rows minutes late.
- **Live updates (AD-12).** Polling is the release-1 contract, and the online demo never opens the WebSocket.
- **Trace (AD-26).** `Web.TraceLink` builds every trace URL. An incident and its request row target the diagnosis session.
- **Demo host (AD-25).**
  - A reset restores the golden copy and refuses one whose version differs from the image's.
  - An update restores the copy, upgrades it in place, checks the version and captures a new copy, all within the reset window of at most 15 minutes.
  - The host's details never enter the repository.

## UX & Interaction Patterns

- **Exact texts on the main path:** "Approval requests (1)"; "Approved from the simulated phone at {time}"; Fixing; "All 50 orders went through."; then, on the card, "Recorded in the IRIS audit log." and Resolved. The rail's request row then leaves.
- **Rejection:** "Rejected from the simulated phone at {time}. Nothing was changed." The incident returns to Open, and Dismiss re-enables Break the feed.
- **Replay rule:** in demo mode, Break the feed closes a resolved incident first. Run again resets only the guide's markers.
- **Finish state:** "This run: {n} decisions · {tokens} tokens · {cost} on {model}." On a local install, the first trace link shows the "Sign in to Visual Trace" popover.
- **Break the feed before a watch** is inactive, with **Do step 1**.
- **Layout:** at 1280×600, the incident card's headline, cause, dry-run count, Approve and Reject show without scrolling.
- **Branding:** the tagline is "An AI assistant for InterSystems IRIS.". The note "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation." appears verbatim in the README and the About dialog.

## Cross-Story Dependencies

- **Merged foundations.**
  - Epics 0 to 10, 16 and 32 have merged, but Story 10.4, which re-opens Epic 10 for the README, is still in the backlog.
  - Epic 9's result file and key proof feed Stories 11.4 and 11.5.
  - Epic 30's Story 30.1 adds the thinking-history smoke test to the release-candidate eval when it merges.
- **Order inside the epic.**
  - Story 11.0 is trivial and comes first.
  - Story 11.1 is on the critical path: it turns REL-2 green.
  - Stories 11.2, 11.3 and 11.4 build the gates.
  - Story 11.5 calls the harness, the rehearsal, the generator and the checklist, so it comes after them.
  - Story 11.6 runs after Stories 11.1 to 11.5 have merged, with the sequence stopped at the hands-on gate.
- **Downstream.**
  - Epic 12 merges only after `v0.1.0`.
  - Story 12.7 extends Story 11.2's harness with pairings and runs the 0.1.1 pass.
  - Story 13.3 needs Story 11.4. Story 14.1 needs Story 11.5, and Story 14.2 needs Story 11.4. Story 15.3 hooks into Story 11.5's gate.
  - The step epics are gated on the `v0.1.0` and `v0.1.1` tags.
  - Story 31.3 repeats DW-359's check for 1.0.0.
- **Compiler notes.**
  - Since the October 29 tagline change, "OpenClaw" appears outside the planning files only in the not-affiliated note and in the tests that pin it. The checklist should allow those tests, and it can reuse `test-readme.sh`'s existing "OpenClaw outside the note" rule rather than copy it.
