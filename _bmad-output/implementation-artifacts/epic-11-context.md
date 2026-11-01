# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point. With every floor epic (0 to 10) merged, it turns the whole web demo path (UJ-1 without Telegram) on end to end in the REL-2 Playwright test, on real components. It also builds the release machinery in `release/`: an upgrade-in-place and restart harness that shows every record survives, a clean-machine rehearsal script proved on throwaways, draft notes and a release checklist, and one scripted sequence that cuts a candidate, runs every gate and stops for the author's word before any outward step. The first release is 1.0.0. 0.1.0 and 0.1.1 are not cut. The real 1.0.0 check and cut (the real-key pass, the timed rehearsal on a real droplet and the Telegram pass) are Epic 38's, run through this epic's sequence.

## Stories

- Story 11.0: Epic 10 Deferred Cleanup (Pairing.HashCode delegates to Session.Hash)
- Story 11.1: The web demo path passes end to end in the REL-2 test
- Story 11.7: The demo path's failure paths, quiet outcomes and online run pass in the REL-2 test (now holds the real-model rule and the online-demo run; the failure paths and coda moved to 11.10)
- Story 11.10: The demo path's failure paths and quiet outcomes pass in the REL-2 test
- Story 11.8: The chat cancels several reminders in one call and says it can set them
- Story 11.9: Every check left off for release 1 turns on, and the CI flakes are fixed
- Story 11.2: Upgrades and restarts keep every record working
- Story 11.3: The clean-machine rehearsal installs and times the demo path (dry runs on throwaways)
- Story 11.4: The release gets draft notes and a checklist
- Story 11.5: One scripted sequence cuts a release

## Requirements & Constraints

- **Demo path (REL-2).** Every UJ-1 step spec under `web/e2e/demo-path/` except Telegram's runs in order and passes on the CI mock. The steps are sign-in, watch (Act strip, Orders check row), reminder, Break the feed to one incident awaiting approval, Approve on the simulated phone to "All 50 orders went through.", and the trace. After the browser steps, the IRIS audit log (polled with a timeout) must hold the approval's answered entry and the resend's action entry, with no key, token, password or Telegram identity in either. Against the real model, tests assert only that a decision with reasons and a trace link appears, never which outcome. The online-demo run lives in `web/e2e-online/`. A full CI run must stay within 35 minutes.
- **Turn-ons (Story 11.9).** Turn on every check left off by a "turns on when … merges" clause in Epics 0 to 10, except checks such a clause leaves for Epic 30 or 31. Fix the listed CI flakes so a candidate needs no reruns.
- **Upgrade and restart (FR-60, NFR-16, NFR-17).** These records must survive an in-place upgrade and a container restart: conversations (the next turn carries the history), reminders (fire late if they fell due), pending approvals (original expiry, still approvable), watches, a demo-mode-off setting and, from the release after 1.0.0, pairings. Story 12.7 extends the harness for pairings. 1.0.0 has no previous release, so the harness runs from a pre-release integration-branch build to prove itself. It becomes a required gate from the release after 1.0.0.
- **Rehearsal (REL-6, NFR-7 to NFR-10).** The script copies the candidate as a `git bundle`, runs `install.sh`, times the first start and the bounds over N runs (20 for a real rehearsal). Any missed bound fails the rehearsal and names the run, step and bound. This build has no clean host and no real key, so every test runs on throwaways with the CI mock, and the report marks those runs "dry run", never a pass. For 1.0.0 the real run uses one clean Linux droplet driven from the Contest Planner's Mac, with no macOS run (Story 38.2).
- **Notes and checklist (REL-8, CON-2, CON-5).** Notes are in plain language, grouped by area, and claim only what ships. Class names and error codes go only in a developer section. For 1.0.0 the notes cover every merged story. The checklist verifies:
  - the verbatim OpenClaw non-affiliation note in the README and the About text;
  - no "OpenClaw" in the product name;
  - every bundled third-party package, font and icon set keeps its licence notice;
  - the public-text check passes and no IRIS reference source is tracked;
  - the author's review of `_bmad-output/` before the repository goes public;
  - the README links resolve on the public page.
- **Release sequence (REL-1, REL-3, REL-7, REL-11).**
  - For the first release, the sequence refuses any version except 1.0.0, and it refuses any version already tagged. The candidate branch is `release/<version>-rc<n>` and never changes after the cut. A failed gate means a fix on the integration branch and a new `rc<n+1>`.
  - The gates are full CI, the release-candidate evaluation with the demo gate, the upgrade harness, the rehearsal, the checklist, and the hands-on pass (for 1.0.0, Stories 38.1 and 38.3). REL-5's is the only override it accepts.
  - It refuses a candidate with an enabled item that answers "not implemented" (`Parameter STUB = 1`).
  - The author's hands-on time is at most 15 minutes. The candidate's record lives at `release/records/<version>/rc<n>.md` on the integration branch.
  - The IPM artifact bundles the built web page in `src/ocutalon/csp/`, and the record names the artifact for Story 15.3. The registry publish stays the author's action.
- **Secrets and the image (NFR-11, CON-1).** No step prints an environment value: run `docker compose config` only with `--quiet` and `docker inspect` only with `--format`. No step pushes an image or signs in to a registry. Records describe machines only by OS, CPU architecture and memory.

## Technical Decisions

- **Storage is append-only (AD-5).** Never rename, retype or remove a stored property. The storage diff runs against the highest earlier `v*` tag. Every private global resolves to the private database. The rows are the truth for `ApprovalHold` and `ReminderTimer`, and the `Reconcile` declarations re-arm missing waiters from them.
- **Upgrade path (AD-23).** On start, the after-start script deletes the ready marker, runs the version-gated IPM upgrade, then runs the installer steps in fixed order:
  1. the bridge installer;
  2. `Public` (readiness stays cleared);
  3. roles and users;
  4. web applications;
  5. `Demo`;
  6. Config Store entries;
  7. audit events;
  8. Telegram items;
  9. `Production`;
  10. `Reconcile`;
  11. `SetReady`, last;
  12. the ready marker.

  Demo mode switches only through `OcuTalon.Core.Admin.SetDemoMode`. Release steps check the version inside the built image, because a cached build context can bake stale sources. `src/module.xml` holds the version.
- **CI mock (AD-22).** Scenarios are JSON files under `ci/mock/scenarios/<lane>/` and are selected in this order:
  1. a `[[mock:<name>]]` marker;
  2. a guide prompt (`B/` only), optionally narrowed with `match: {prompt, mockkey}` so it answers only the agent with that `MOCKKEY`; other agents fall through to the next rule (the U-194 amendment, CI-only);
  3. the agent's `MOCKKEY` default script (`triage`, `diagnosis` or `chat`).

  Lane A adds only files under `A/`. New mock behaviour is Lane B's.
- **Release-candidate evaluation.** `bash eval/run.sh --release-candidate` writes `eval/release-candidate.json` and `.md`, and `--override "<reason>"` records the author's override of a blocked result. The notes take their evaluation summary from these files.
- **Demo-host hook (AD-25).** The sequence reaches the demo host only over SSH, with the address and key from the author's configuration outside the repository.
  - It copies a `git bundle` of tag `v<version>`, then runs `ocutalon-demo update <version>`. The command prints `{"result":"updated",...}` while access is restricted and `{"result":"scheduled","at":...}` after launch.
  - It then reads `ocutalon-demo status` (a JSON object: running and golden versions, the last and next reset, `pendingVersion`, `access`).
  - Its tests run against a throwaway stand-in host. With no demo host configured, the notes say the online demo wasn't updated.
- **Lanes (AD-29).** `release/` is Lane A's. Epic 11 is the AD-29 exception: it may change either lane's files to make the demo path pass, and the orchestrator serializes it against overlapping epics. `ci.yml` is Lane B's and `lane-a.yml` is Lane A's. After a release, `main` is merged back into the integration branch. Step epics merge only once `release/1.0.0-rc1` exists.
- **Merging to `main`.** The merge goes to `main` only with the `ci.yml` and `lane-a.yml` checks green. While the repository is private (GitHub answers branch-protection queries with HTTP 403), the sequence checks every job itself and records that it did.

## Cross-Story Dependencies

- Story 11.1 needs Epics 0 to 10 merged. Stories 11.7, 11.10, 11.8 and 11.9 are splits of 11.1 and build on its turned-on specs.
- Story 11.8's live check on Claude Haiku 5.5 (DW-142, DW-358) runs in Story 38.1's pass on `release/1.0.0-rc1`, not in this epic.
- Story 11.5 composes Story 11.4 (notes and checklist), Story 11.2 (harness), Story 11.3 (rehearsal) and Story 9.5's release-candidate evaluation. Its rehearsal candidate proves the sequence before Epic 38 runs the real 1.0.0 cut through it.
- Story 11.3's real rehearsal is Story 38.2. Story 12.7 extends Story 11.2's harness with pairings. Story 15.3 installs the IPM artifact that Story 11.5 records. Stories 13.3, 14.1 and 15.3 need Epic 11 merged.
