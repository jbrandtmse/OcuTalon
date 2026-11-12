# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge or developer builds one image, runs `docker compose up`, gets OcuTalon in its own OCUTALON namespace and signs in to the page. Epic 0 is also the walking skeleton for both build lanes: it creates every cross-lane contract, runs every release-1 production item as a stub, and sets up CI with the model mock, so the lanes can work in parallel without editing each other's files. Since the lanes split, Epic 0 has been re-opened (SC-5) for cross-cutting work that belongs to neither lane: start robustness, CI capacity and port tooling, README presentation for judges, and evaluation tooling (rules-only mode, held-out set, measured comparison).

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace
- Story 0.2: The package installs and upgrades itself at every start
- Story 0.3: Sign in to an empty OcuTalon page
- Story 0.4: The cross-lane message and data contracts
- Story 0.5: Live events and the REST skeleton
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock
- Story 0.8: The demo-path test signs in and loads the page
- Story 0.9: The message catalog and its one renderer
- Story 0.10: The Orders demo production runs in OCUORDERS
- Story 0.11: The CI model mock answers every scenario the stories need
- Story 0.12: Epic 0 burn-down
- Story 0.13: A start retries the CPF merge when IRIS cannot quiesce
- Story 0.14: A start that recovers through the merge retry passes the live checks and the upgrade harness
- Story 0.15: The Dockerfile sits at the repository root
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers
- Story 0.18: The README shows judges where to look
- Story 0.19: The README names the contest
- Story 0.20: Rebalance the IRIS CI groups under the 35-minute budget
- Story 0.21: The README opens with a centred header: logo, tagline and badges
- Story 0.22: The More to try panel shows its items under group headings
- Story 0.23: The README header's logo and LICENSE badge link use absolute GitHub URLs
- Story 0.24: A test stack's web port can never collide with a port still being released
- Story 0.25: The web-port guard waits long enough for a stack still shutting down
- Story 0.26: The README leads with the full video and the incident path
- Story 0.27: A measured comparison of the agent and the fixed rules (the measuring tools)
- Story 0.28: The README's Contest checklist gets a Video row; the For judges row links the incident path and video
- Story 0.29: The README's comparison of the agent and the fixed rules, filled from the committed rules-only report
- Story 0.31: The memory-documents-remember eval accepts document, runbook or file

## Requirements & Constraints

- **Install and start:** one image build plus compose; durable `%SYS` and databases on a volume; restarts and upgrades lose no data. The health check opens no IRIS session and passes only when IRIS is running and the ready marker equals the image's version; `start_period` is at least 10 minutes (currently 600 s). The after-start script always exits 0; failure shows only as an unhealthy check with a `STEP <name> FAILED` log line.
- **Sign-in:** only signed-in users reach the app (except `/ocutalon/public/status`). The README account is `ocutalon`/`ocutalon` with the user, admin and trace-viewer roles.
- **Image stays private:** no `docker push` or registry sign-in anywhere; the AI Hub image never enters a CI cache or artifact; fork PRs never run on the IRIS runner.
- **No mocks for judges:** the judges' compose file has no mock service; mocks live only in the CI override.
- **Public text:** no keys, local machine paths, private infrastructure or other entrants' names in any tracked file. README and other public strings are committed verbatim as ruled by the Contest Planner; if a README rule refuses ruled text, the text is not reworded. New public strings go to the Planner as PUBLIC TEXT at the spec gate, before implement.
- **CI:** a full run within 35 minutes wall-clock; each IRIS group planned to well under that (about 29 minutes), shard units of about 1,000 s at most; no longer deadlines. Hosted jobs skip their own steps only when nothing they check changed. Every story ends with every workflow green. Any `.github/workflows/*.yml` or `release/**` hunk is a RELEASE TOOL item for the Planner before it merges.
- **Tests:** no test pin is deleted or weakened; a pin of an old layout or path moves to the new one. `docker/tests/test-boundaries.sh` passes.
- **Evaluation:** on every push the harness runs against the mock; on each release candidate it runs on Claude Haiku 5.5 (targets: 18 of the first 20 attention decisions right, 8 of 10 incident causes right). Runners never hold a model key; real-model runs are done by the Planner's release fork. Report-only cases sit outside the gating score.

## Technical Decisions

- **One IPM package** (`ocutalon`, `src/module.xml`) with a separable bridge (`OcuTalon.Bridge`, loadable alone); the bridge references no other OcuTalon package and only allow-listed `%AI` classes.
- **Start sequence:** the after-start script re-runs `iris merge` on a fresh copy of `docker/merge.cpf` at every start, then installs IPM 0.10.10 and the package (version-gated; `OCUTALON_DEV=1` reloads), then runs the installer-step registry in a fixed order (Bridge installer, Public, roles/users, web, SSL, tasks, Demo, Config Store, audit, Telegram, Memory, Production, Reconcile; Public sets ready last; then the marker). Steps report non-fatal issues with `Install.Step.Warn`. The merge retries only on ERROR #453, logging `STEP merge RETRY <n> after #453`; `check_log` accepts exactly one RETRY followed by `STEP merge OK`.
- **Storage is append-only:** every non-message persistent class sets `DEFAULTGLOBAL` to `^OcuTalonP.<Short>` (`^OcuTalonBP.<Short>` in the bridge), commits its compiler-generated `Storage` block, and resolves to the private database; CI diffs storage against the previous release tag.
- **Lane ownership:** each class, item, table and file has one owning lane. Lane A owns the bridge, agents, tools, watch, fix, checks, digest, memory/docs/MCP, `OcuTalon.Eval` and `eval/`, the installer core and `docker/merge.cpf`, and `.github/workflows/lane-a.yml`. Lane B owns `ci.yml`, the checks job, the demo path, the mock's behaviour, the web app and `Msg.Catalog.Render`. Lane A adds mock scenarios only as files under `ci/mock/scenarios/A/`. The production definition has one region per lane between `<!-- lane X: begin/end -->` markers. Epic 0 stories may touch both lanes' files, but only what each story names.
- **CI layout:** `ci/iris.sh` is the single recipe for IRIS units, always in throwaway compose projects (on the runner and on a developer machine); `ci/units.sh`, `IRIS_GROUPS`, the `iris` matrix and `ci/iris.sh groups` must agree; jobs are named `iris (<group>)`. Throwaways mount `./eval` read-only. `OCUTALON_TEST_WEB_PORT` stays an explicit override; web ports bind 127.0.0.1 only. Never run `docker compose config` without `--quiet` or `docker inspect` without `--format`.
- **Model mock:** Node stdlib in pinned `node:24.15.0-slim`; picks a scenario by a `[[mock:<name>]]` marker, then a guide prompt's exact text, then the agent's `MOCKKEY` (`triage`, `diagnosis`, `chat`), never prompt wording; rejects sampling parameters and output caps under 4,000; 500 when nothing matches.
- **Evaluation set:** `eval/<case>/` holds `case.json` (`name`, `kind`, `heldOut`, `description`, `snapshot`, `expectation`, `recordedBy`) and recorded snapshots. Runs go through the disabled-by-default `EvalIn` (enabled only by `OCUTALON_EVAL=1`) with owner `eval`, minting fresh `ItemId`s and keeping the recorded one as `SourceItemId`; they write no notification, delivery or live event. The rules-only mode scores with the product's own no-model fallback. `eval/compare.mjs` reads the committed rules-only report under `eval/results/`; held-out expected answers are committed in their own commit before any agent run. `docker/tests/test-eval-set.sh` checks set structure.

## UX & Interaction Patterns

- The branded sign-in page keeps the user name and clears the password on a wrong password, and shows a "no OcuTalon role" message to a user without the role. Its texts (including the "User name", "Password", "Show password" labels) are copies that a test compares with the catalog.
- All styling comes from the token stylesheet generated from `DESIGN.md`. Notice and reply texts come only from the message catalog (EXPERIENCE's Message Catalog), rendered through `Msg.Catalog.Render`.
- More to try: items are grouped under headings taken from registry data and one exported group-order constant (never hard-coded). Empty groups are hidden, headings take no focus, and no test pins a literal count of groups or items.

## Cross-Story Dependencies

- 0.14 builds on 0.13's retry log line. 0.20 is built on 0.15 and merges on the same head. 0.25 follows and reopens 0.24's port guard.
- README chain: 0.17 → 0.18 → 0.19 → 0.21 → 0.23 → 0.26 → 0.28 → 0.29. The More to try count in 0.28's row tracks Story 35.3. 0.22's groups are extended by Stories 37.2 and 25.2 and by in-flight items from 23.x and 41.13.
- Story 0.27 runs in the lane-B Epic 0 worktree (`OCT-epic0b`). Story 0.29 waits for 0.27's committed rules-only report, and 0.31 follows 0.27 there. The agent column of the comparison is filled at the 1.0.8 release-candidate evaluation by the Planner's fork. "never used for tuning" and "measured at release 1.0.8" must never reach `main`.
