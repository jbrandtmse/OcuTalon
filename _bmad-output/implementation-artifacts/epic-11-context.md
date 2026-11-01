# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point. The web demo path (no Telegram) already passes end to end in the REL-2 Playwright test on real components. What remains is the release machinery in `release/`: an upgrade-in-place and restart harness, a clean-machine rehearsal (install, then timed demo-path runs checked against every bound) proved only on throwaways, a release checklist, draft notes, and one scripted sequence that cuts a candidate, runs every gate and stops for the author's word before any outward step. The first release is 1.0.0 (0.1.0 and 0.1.1 are never cut; no previous tag, so its notes cover every merged story). Epic 38 runs the real 1.0.0 check and cut through this epic's sequence.

## Stories

- Story 11.0: Epic 10 Deferred Cleanup (done)
- Story 11.1: The web demo path passes end to end in the REL-2 test (done)
- Story 11.7: The demo path's failure paths, quiet outcomes and online run pass in the REL-2 test (done)
- Story 11.10: The demo path's failure paths and quiet outcomes pass in the REL-2 test (done)
- Story 11.8: The chat cancels several reminders in one call and says it can set them (done)
- Story 11.9: Every check left off for release 1 turns on, and the CI flakes are fixed (done)
- Story 11.2: Upgrades and restarts keep every record working
- Story 11.3: The clean-machine rehearsal installs and times the demo path
- Story 11.11: The rehearsal runner times the demo path and checks every bound
- Story 11.12: The rehearsal runner repeats the demo path N times with Run again
- Story 11.4: The release gets draft notes and a checklist (checklist only, after the split)
- Story 11.13: The release gets draft notes
- Story 11.5: One scripted sequence cuts a release

## Requirements & Constraints

- **Dry runs only in this build.** Throwaway hosts and the CI mock, never a real key; reports say "dry run", never pass. Every command fits one 10-minute call. Tests never write into `release/records/` (always `--record <tmp>`).
- **Upgrade and restart (11.2).** In throwaway compose projects: conversations, reminders (late if due during the upgrade), pending approvals (original expiry, still approvable to "All 50 orders went through."), watches and demo mode off survive an in-place upgrade and a restart. Pairings join after 1.0.0 (Story 12.7). Its record section is `## Upgrade harness`.
- **Rehearsal bounds (11.11, 11.12).** Break the feed to notice split into pick-up 15 s, settle end 30 s, diagnosis 20 s, delivery 5 s (every run); notice 60 s, step 1 decision 10 s, approval result 2 s and tell-now 5 s each in 19 of 20 (floor(N/20) misses allowed); each reminder within 10 s; largest request under 100,000 input tokens; median, first reply and reminder-vs-result recorded. A miss names the run, step and bound. 11.12 runs N times on one install via Run again (steps 1 and 2 resent through the composer, relative counts, one tell-now item added per run, 07 and 08 run once; DW-522).
- **Checklist (11.4).** Automated: the not-affiliated note "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation." word for word in README and About (source and bundle); no product name holds that name, which appears only in the note outside `_bmad-output/` and `_bmad/`; licence notices kept; the public-text check passes on the tree and on the draft notes; no IRIS reference source tracked; no script publishes, changes repo settings or posts. Author-only rows: no copied code, no artwork, no AI Hub copy, the `_bmad-output/` and agent-instructions review, and the public-page README links recheck (DW-359). Posts, articles, video and bonus claims are the author's.
- **Notes (11.13).** Plain language, grouped by area, from stories merged since the previous tag, claiming only what ships; class names and error codes only in a developer section. Include the eval summary (scores, mean and max decision cost, largest request, REL-5 override reason), rehearsal timings and the upgrade result. The author edits and publishes; nothing else does.
- **Release sequence (11.5).** First release refuses any version but 1.0.0 and any tagged version. Candidate branch `release/<v>-rc<n>`, never changed after the cut; a failed gate means an integration-branch fix and `rc<n+1>`. Gates: full CI, release-candidate eval with the demo gate, upgrade harness, rehearsal, checklist, hands-on pass (resume command refuses without a pass or carry-over). REL-5's override is the only one accepted; refuse an enabled item answering "not implemented". Stops for the author's word before every outward step (push, PR, merge, tag, merge back, demo update); never publishes notes or to a registry. Author hands-on time at most 15 minutes, recorded. Record at `release/records/<v>/rc<n>.md` on the integration branch. The IPM artifact bundles the built page in `src/ocutalon/csp/` and is named in the record. A rehearsal candidate with a fixture pass record and stand-in demo host proves the sequence.
- **Secrets.** Never print an env or config value (`docker compose config --quiet`, `docker inspect --format` only); never push an image or sign in to a registry; records name machines only by OS, CPU and memory. Scan failures print `file:line`, never the text.

## Technical Decisions

- **Storage append-only (AD-5).** Never rename, retype or remove a stored property; the storage diff runs against the highest earlier `v*` tag. `Reconcile` re-arms `ApprovalHold` and `ReminderTimer`.
- **Upgrade path (AD-23).** After-start: clear ready marker, version-gated IPM upgrade, installer steps, `Production`, `Reconcile`, `SetReady` last. `src/module.xml` holds the version (11.5 sets it at the cut); check it inside the built image.
- **Shared library (11.3).** `release/lib-release.sh`: `release_config_read` (`REHEARSAL_` keys in `release.conf` outside the repo), `host_run <clean|driver>`, `record_path <v> <rc>`, `record_write <file> <section>` (replaces only its own `## ` section), and from 11.4 `notes_path <v> <rc>` -> `release/records/<v>/rc<n>-notes.md`. Scripts: Bash 3.2, ASCII, mode 100755, `umask 077`, main guard so they can be sourced. Lines `PASS|FAIL <id> <detail>`, then `RECORD <file>` and `RESULT <result>`.
- **Rehearsal (11.3, 11.11).** `release/rehearse.sh` phases `plan`, `install`, `runs`, `report`, `down`, `run`, keyed by `OCUTALON_RUN_TAG`; options `--version`, `--rc`, `--candidate`, `--record`, `--dry-run`, `--runs <n>`, `--plant <bound>` (dry only). Exits 0 real pass only, 1 fail/not run, 2 refusal, 3 dry run, 75 lane lock busy. `runs` is one run per call under `<state>/runs/<k>/`; a second `runs` refuses until 11.12. `bounds_eval` writes bound rows and a `### Runs` table into `## Clean-machine rehearsal`; tell-now reads `not run` until 11.12, so a real pass needs 11.12.
- **Checklist interface (11.4).** `release/checklist.sh --version <v> --rc <n> [--candidate <ref>] [--record <file>] [--notes <file>]` (`--notes` defaults to `notes_path`). Result `fail` if any automated row fails, else `not confirmed` while any author row lacks confirmation, else `pass`; exit 0 only for `pass`, 1 otherwise, 2 refusal with nothing written. Writes `## Release checklist` (Result, Candidate sha, Notes path, Run time, Author's actions line, item table). Reads, never writes, `## Author confirmations`: lines `- <id>: confirmed <YYYY-MM-DD>` for `no-copied-code`, `no-artwork`, `no-ai-hub-copy`, `public-review`, `public-links`, reconfirmed per rc. No network ever. Row functions such as `row_public_text` (runs `test-boundaries.sh`, then `local_path` and `key_like` on the notes) are sourceable.
- **Notes inputs (11.13).** Write the draft at `notes_path`; check it with `row_public_text` plus a developer-section rule. Read `eval/release-candidate.json` (`summary.scores`, `summary.attentionCost.meanUSD`/`maxUSD`, `summary.size.largestTokens`, `override.reason`; written by `bash eval/run.sh --release-candidate`, `--override "<reason>"`), the rehearsal's bound rows, `### Runs` table and first start, and `## Upgrade harness`'s `Result:` and rows. Merged stories are best read as `sprint-status.yaml` keys `done` at the candidate but not at the previous tag; areas need a mapping from epics; internal-work titles belong in the developer section.
- **Demo-host hook (AD-25, 11.5).** Over SSH (config outside the repo): copy a `git bundle` of `v<v>` (the commit for a rehearsal), run `ocutalon-demo update <v>` (`{"result":"updated",...}` while restricted, `{"result":"scheduled","at":...}` after launch, written into the notes), then check `ocutalon-demo status`. No host configured: the notes say the online demo wasn't updated. Tested against a throwaway stand-in.
- **Lanes (AD-29).** `release/` is Lane A's. Do not edit `README.md`, `docker/tests/test-readme.sh`, `docker/tests/lib-live.sh`, `test-pinned-sources.sh`, `release/standalone-bridge.sh`, `release/ipm*`, `.github/workflows/*`, or `src/module.xml` (until 11.5). `ci/units.sh`'s `CHECK_SCRIPTS` is shared by region; self-tests are hermetic `docker/tests/test-*.sh` in the hosted checks job.
- **Merging to `main`.** Only with `ci.yml` and `lane-a.yml` green; where branch protection answers HTTP 403, the sequence checks every job itself and records that. After a release, `main` merges back into the integration branch.

## Cross-Story Dependencies

- 11.11 builds on 11.3; 11.12 on 11.11 (fills tell-now). 11.2 and 11.4 write through 11.3's `lib-release.sh`.
- 11.13 depends on 11.4 (`notes_path`, `row_public_text`) and reads 11.2, 11.3/11.11/11.12 and Story 9.5's eval output; 11.4's checklist scans 11.13's draft.
- 11.5 composes 11.2, 11.3, 11.11, 11.12, 11.4 and 11.13 (its gate: `bash release/checklist.sh --version <v> --rc <n> --candidate release/<v>-rc<n>`, pass only on exit 0 with `Result: pass`) and Story 9.5's evaluation.
- Story 38.2 is the real rehearsal; Story 12.7 adds pairings to 11.2's harness; Story 15.3 installs 11.5's recorded artifact; Stories 13.3, 14.1 and 15.3 need Epic 11 merged.
