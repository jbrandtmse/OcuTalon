# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point. With Epics 0 to 10 merged, the whole web demo path (UJ-1 without Telegram) passes end to end in the REL-2 Playwright test on real components (done: 11.0, 11.1, 11.7, 11.8, 11.9, 11.10). What remains is the release machinery in `release/`: an upgrade-in-place and restart harness, a clean-machine rehearsal (install, then timed demo-path runs checked against every bound) proved only on throwaways, draft notes and a checklist, and one scripted sequence that cuts a candidate, runs every gate and stops for the author's word before any outward step. The first release is 1.0.0 (0.1.0 and 0.1.1 are never cut). Epic 38 does the real 1.0.0 check and cut (real-key pass, timed rehearsal on a real droplet, Telegram pass) through this epic's sequence.

## Stories

- Story 11.0: Epic 10 Deferred Cleanup (done)
- Story 11.1: The web demo path passes end to end in the REL-2 test (done)
- Story 11.7: The demo path's real-model rule and online run pass in the REL-2 test (done)
- Story 11.10: The demo path's failure paths and quiet outcomes pass in the REL-2 test (done)
- Story 11.8: The chat cancels several reminders in one call and says it can set them (done)
- Story 11.9: Every check left off for release 1 turns on, and the CI flakes are fixed (done)
- Story 11.2: Upgrades and restarts keep every record working
- Story 11.3: The clean-machine rehearsal installs the candidate (dry runs on throwaways)
- Story 11.11: The rehearsal runner times the demo path and checks every bound (one timed run per call)
- Story 11.12: The rehearsal runner repeats the demo path N times with Run again
- Story 11.4: The release gets draft notes and a checklist
- Story 11.5: One scripted sequence cuts a release

## Requirements & Constraints

- **Dry runs only in this build.** No clean host and never a real key: rehearsal tests use throwaways and the CI mock, and report and record say "dry run", never pass. The real 20 runs are Story 38.2's (one Linux droplet, the Contest Planner's Mac as driver, no macOS run). Every command must fit one 10-minute call.
- **Upgrade and restart (11.2; FR-60, NFR-16, NFR-17).** In throwaway compose projects only: conversations (next turn carries history), reminders (fire, late if due during the upgrade), pending approvals (original expiry, still approvable to "All 50 orders went through."), watches, and demo mode off (via `SetDemoMode(0)` in a second project) survive an in-place upgrade and a container restart. Pairings join from the release after 1.0.0 (Story 12.7). For 1.0.0 the harness proves itself from a pre-release integration-branch build; it becomes a required gate after 1.0.0.
- **Rehearsal timing (11.11; NFR-3, NFR-7 to NFR-10, P30, UX-DR102).** Split Break the feed to notice, from millisecond production message headers, into pick-up (15 s), settle end (30 s), diagnosis (20 s), delivery (5 s), each in every run; notice 60 s in 19 of 20; median recorded against about 35 s; step 1 decision 10 s (19 of 20, page clock); first reply recorded; approval result 2 s from the Approve press (19 of 20); each reminder within 10 s of due; reminder vs the result recorded; largest model request under 100,000 input tokens. "19 of 20" allows floor(N/20) misses. A failed run or missed bound fails the rehearsal and names the run, step and bound.
- **Repeats (11.12).** N runs (20 for real) on one install, using Run again and the replay rule between runs; every 11.11 bound over the whole run set, plus the tell-now notice's 5 s in 19 of 20. Its dry-run proof plants a missed bound in a later run. Facts it must face: Run again reopens only guide steps 3 to 5, so each repeat must also send steps 1 and 2 through the composer; a replay needs the previous incident resolved and a press within 180 s of an unnoticed run is refused; the REL-2 assertions are first-run counts (counts must be relative); no tell-now item exists in the demo path yet, so 11.12 adds one per run; 07 and 08 run once per install (07's replay request stays pending, 08's samples are already in the mailbox), so 11.12 decides which specs repeat (DW-522).
- **Notes and checklist (11.4; REL-8, CON-2, CON-5, REL-11).** Plain-language notes grouped by area, claiming only what ships, class names and error codes only in a developer section; 1.0.0's cover every merged story; include the eval summary, rehearsal timings, upgrade result and any REL-5 override. Checklist: the verbatim OpenClaw non-affiliation note in README and About, no "OpenClaw" in the product name, licence notices kept, public-text check passes, no IRIS reference source tracked, the author's review of `_bmad-output/` and agent instructions before going public, README links recheck on the public page (DW-359), and posts, articles, video and bonus claims stay the author's.
- **Release sequence (11.5; REL-1, REL-3, REL-7, REL-11).** First release refuses any version but 1.0.0 and any tagged version. Candidate branch `release/<version>-rc<n>`, never changed after the cut; a failed gate means an integration-branch fix and `rc<n+1>`. Gates: full CI, release-candidate eval with the demo gate, upgrade harness, rehearsal, checklist, hands-on pass (1.0.0: Stories 38.1 and 38.3). REL-5's override is the only one accepted; refuse an enabled item answering "not implemented". Author hands-on time at most 15 minutes, recorded. Record at `release/records/<version>/rc<n>.md` on the integration branch. The IPM artifact bundles the built web page in `src/ocutalon/csp/` and is named in the record for Story 15.3; the registry publish stays the author's.
- **Secrets (NFR-11, CON-1, CON-5).** Never print an env or config value: `docker compose config` only with `--quiet`, `docker inspect` only with `--format`. Never push an image or sign in to a registry. Records name machines only by OS, CPU architecture and memory.

## Technical Decisions

- **Storage append-only (AD-5).** Never rename, retype or remove a stored property; the storage diff runs against the highest earlier `v*` tag; private globals resolve to the private database. `Reconcile` re-arms `ApprovalHold` and `ReminderTimer` from their rows.
- **Upgrade path (AD-23).** The after-start script clears the ready marker, runs the version-gated IPM upgrade, the installer steps in fixed order, `Production`, `Reconcile`, `SetReady` last. Check the version inside the built image. `src/module.xml` holds the version.
- **Incident timing (AD-15).** `FailurePoller` every 3 s; settle is 10 s quiet or 30 s after the first failure; the notice sets `NoticedAt`.
- **Rehearsal interface (11.3).** `release/rehearse.sh` phases `plan`, `install`, `report`, `down`, `run` (install, runs, report, always down), each its own process keyed by `OCUTALON_RUN_TAG`; options `--version`, `--rc`, `--candidate`, `--record`, `--dry-run`. `release/lib-release.sh` gives `release_config_read` (`REHEARSAL_` keys in one `release.conf` outside the repo), `host_run <clean|driver>` (every remote action), `record_path` and `record_write` (replaces only its own `## ` section; 11.2 writes through it too). FAIL lines read `FAIL run <run> step <step> bound <bound>: <detail>`. Exits: 0 real pass only, 1 fail or not run, 2 refusal, 3 dry run, 75 lane lock busy.
- **Runner interface (11.11, consumed by 11.12, 11.4, 11.5).**
  - `runs` phase: one run per call, bounded by `OCUTALON_E2E_TIMEOUT_MS` (480000). Run 1 is the REL-2 project verbatim on the fresh install, driven locally (`REHEARSAL_DRIVER_SSH=local`); a second `runs` refuses naming 11.12 (exit 2), which 11.12 replaces. Files under `<state>/runs/<k>/`: `report.json`, `e2e.log`, `summary.log`, `marks.page`, `marks.server`, `verdict`, `exec.count`. The verdict is `demo-path-summary.mjs --only-telegram-skips`.
  - `exec [<namespace>]`: IRIS session through `host_run clean`; the specs reach IRIS only this way (`OCUTALON_E2E_IRIS_EXEC`), and `exec.count` proves use.
  - Page marks via `web/e2e/support/rehearsal.ts` (`mark`, `markWhen`), inert unless `OCUTALON_E2E_MARKS` is set: `step1_sent`, `step1_decision_seen`, `step1_reply_seen`, `approve_pressed`, `approval_result_seen`. A read-only collector prints `CHK|mark|...` server marks. One clock per value; never page minus server.
  - `bounds_eval <state> [<planted id>]` reads every `runs/*`, writes `<state>/bounds` and `<state>/runs.table`. Bound ids: `notice`, `pick-up`, `settle-end`, `diagnosis`, `delivery`, `median`, `decision`, `first-reply`, `approval-result`, `reminder`, `reminder-result`, `largest-request`, `tell-now` (`not run` until 11.12).
  - `--runs <n>` (real at least 20; dry 1 to 20) and `--plant <bound id>` (dry only). `report` may run again and rebuilds the section: bound rows plus a `### Runs` table. Real mode reads `Result: not run` while runs < `--runs` or tell-now is `not run`, so a real pass needs 11.12.
- **Release-candidate evaluation.** `bash eval/run.sh --release-candidate` writes `eval/release-candidate.json` and `.md`; `--override "<reason>"` records REL-5's override. The notes read these.
- **11.5's rehearsal gate.** `OCUTALON_RUN_TAG=<t> bash release/rehearse.sh run --version <v> --rc <n>` (`--dry-run` for its rehearsal candidate); passes only on exit 0 with `Result: pass`. Not a CI unit; tests never write into `release/records/` (pass `--record <tmp>`).
- **Demo-host hook (AD-25).** Over SSH only (config outside the repo): copy a `git bundle` of `v<version>`, run `ocutalon-demo update <version>` (`{"result":"updated",...}` while restricted, `{"result":"scheduled","at":...}` after launch), then check `ocutalon-demo status`. Tested against a throwaway stand-in. No demo host configured: the notes say the online demo wasn't updated.
- **Lanes (AD-29).** `release/` is Lane A's; Epic 11 may change either lane's files, serialized against overlapping epics. Avoid open epics' files (`docker/tests/lib-live.sh`, `telegram-page.spec.ts`, `release/standalone-bridge.sh`, `release/ipm*`, `src/module.xml` until 11.5, `.github/workflows/*`). After a release, `main` merges back into the integration branch.
- **Merging to `main`.** Only with `ci.yml` and `lane-a.yml` green; while the repo is private (branch protection answers HTTP 403) the sequence checks every job itself and records that.

## Cross-Story Dependencies

- 11.11 builds on 11.3's script and record section; 11.12 builds on 11.11's `runs`, collector, marks and `bounds_eval`, and fills the tell-now row. 11.3's `lib-release.sh` is shared with 11.2's harness.
- 11.4's notes read the rehearsal's bound rows, `### Runs` table and first start from the record, the upgrade result and the eval files.
- 11.5 composes 11.4, 11.2, 11.3, 11.11, 11.12 and Story 9.5's evaluation; its rehearsal candidate proves the sequence before Epic 38's real cut.
- Story 38.2 is the real rehearsal; Story 12.7 extends 11.2's harness with pairings; Story 15.3 installs the artifact 11.5 records; Stories 13.3, 14.1 and 15.3 need Epic 11 merged.
