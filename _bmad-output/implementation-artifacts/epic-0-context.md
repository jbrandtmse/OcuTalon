# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge runs one image build and `docker compose up`, gets OcuTalon in its own OCUTALON namespace and signs in to its page, while both build lanes get every cross-lane contract, every release-1 production item as a stub, and CI with a model mock so they can work in parallel. The walking skeleton is long done; Epic 0 is now re-opened (SC-5) for cross-cutting items no single feature epic owns: start-up robustness, CI capacity and tooling, README and judge-facing evidence, and the evaluation tooling behind the README's measured comparison of the agent against the fixed rules.

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
- Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget
- Story 0.21: The README opens with a centred header: logo, tagline and badges
- Story 0.22: The More to try panel shows its items under three group headings
- Story 0.23: The README header's logo and LICENSE badge link use absolute GitHub URLs
- Story 0.24: A test stack's web port can never collide with a port that is still being released
- Story 0.25: The web-port guard waits long enough for a stack that is still shutting down
- Story 0.26: The README leads with the full video and the incident path
- Story 0.27: A measured comparison of the agent and the fixed rules (the measuring tools)
- Story 0.28: The README's Contest checklist gets a Video row, and the For judges Usability row links the incident path and the full video
- Story 0.29: The README's comparison of the agent and the fixed rules, filled from the committed rules-only report
- Story 0.31: The memory-documents-remember eval accepts document, runbook or file
- Story 0.32: CI time budgets get a 40% margin over their green medians, and the two load timeouts get MEASURED lines

## Requirements & Constraints

- `main` is always releasable; every story ends with CI green on every workflow (`ci` and `lane-a`).
- The demo-path browser test runs on every pull request and push to `main`; a failure blocks the release. Skipped steps never count as passes.
- A full CI run takes at most 35 minutes wall-clock. A shard unit should be about 1,000 s at most; add a new group only when packing can't get there. No job is given a longer deadline to hide slowness.
- CI time budgets (unit, suite, ready-wait timeouts) must stay finite so a real hang still fails; a budget may be raised or its unit split, but no test is deleted, skipped, tagged off or shortened. Measured times are printed as `MEASURED ...` lines so later audits can read them from CI logs.
- Test pins are never deleted or weakened: a pin of an old value or layout moves to the new one in the same change.
- The AI Hub image is never pushed, cached or stored as a CI artifact; no script signs in to a registry; fork PRs never reach the self-hosted runner.
- The judges' compose file holds no mocks; mocks live only in CI configuration.
- Runners never hold a model key. Model-backed evaluation runs only at a release candidate, by the Contest Planner's release fork; everything else runs against the mock or rules-only.
- Release-candidate evaluation targets: attention decisions right for at least 90% of items, incident causes right for at least 80% of incidents and all 10 demo-incident runs; a candidate below target gets two more runs and passes on two of three.
- Public text (README, web app, release notes, every tracked file) is plain language with no keys, local paths, private infrastructure or other entrants' names. Ruled README text is committed verbatim; if a check refuses ruled text, the text is not reworded.
- No sampling parameters on any model request; the mock rejects them and output caps under 4,000 tokens.

## Technical Decisions

- **Image and start.** One root `Dockerfile` builds `FROM` the retagged build 154 image (`ocutalon-iris-base:2026.3.0AI.154.0`). `docker/after-start.sh` re-runs the CPF merge at every start, installs the single IPM package and runs the installer-step registry in order, and writes the ready marker last; it always exits 0 and, on failure, logs `STEP <name> FAILED` and leaves the health check unhealthy. The merge is retried only on ERROR #453, logging `STEP merge RETRY <n> after #453`; live checks accept exactly one such retry followed by `STEP merge OK`. The compose `start_period` (600 s) bounds a first start including one retry.
- **CI layout.** Hosted runners run web build, lint, unit and mock tests; IRIS units run on self-hosted runners via one recipe, `ci/iris.sh`, always in throwaway compose projects (never a developer instance), with `ci/compose.ci.yml` layered as the CI override. `ci/units.sh`, `IRIS_GROUPS`, the `iris` matrix and `ci/iris.sh groups` must agree; jobs report as `iris (<group>)`. Hosted jobs skip their own steps only when nothing they check changed since the last green push run.
- **Port guard.** Throwaway stacks guard their web port: wait up to 90 s (3 s polls, `ss -tan` on Linux, every state except TIME-WAIT), retry the start up to twice on the exact bind error, then print a loud `FAIL web port:` line. `OCUTALON_TEST_WEB_PORT` remains an explicit override; ports stay on 127.0.0.1. Teardowns run in the foreground before the next unit starts.
- **Model mock.** Node standard-library service; picks a scenario by `[[mock:<name>]]` marker, then guide-prompt text, then the agent's `MOCKKEY` (`triage`, `diagnosis`, `chat`), never by prompt wording. One JSON file per scenario under `ci/mock/scenarios/<A|B>/`; Lane A only adds files under `A/`, and new mock behaviour belongs to Lane B.
- **Evaluation set.** `eval/<case>/` holds `case.json` and recorded reader snapshots. Runs go through the disabled-by-default `EvalIn` service (enabled only by `OCUTALON_EVAL=1`), mint fresh `ItemId`s, keep the recorded id as `SourceItemId`, and route results to `EvalSink` under owner `eval`, writing no notification, delivery or live event. A rules-only mode scores every case with the product's fixed-rule fallback, with no model and no key. A held-out set's expected answers were committed in their own commit before any agent run and are never tuned against. `eval/compare.mjs` sets agent and rules-only results side by side per case and in total, including unsafe outcomes and "Items that needed you now but weren't told now"; the committed rules-only report under `eval/results/` is the only source for the README's fixed-rules column. Report-only cases stay outside the SM-1 count. `docker/tests/test-eval-set.sh` checks case structure.
- **Contracts and ownership.** Each production item, table and event type has one owning lane; each lane edits only its own region of the production definition. Persistent classes set `DEFAULTGLOBAL` from the short-name registry and commit their storage blocks; storage only ever appends across releases.

## UX & Interaction Patterns

- README changes are judge-facing public text: wording, link targets and anchors come from the Contest Planner's rulings, and `docker/tests/test-readme.sh` pins them (link allow-list, header block, video links, section order, counts read from the registry or catalog rather than literals).
- The sign-in page's texts are copies of catalog texts and a test keeps them equal.
- The demo guide's More to try panel groups items from registry data and one ordered group constant; headings take no focus, empty groups show no heading.
- CI log messages are internal and need no public-text ruling.

## Cross-Story Dependencies

- Story 0.29 (lane A) needs Story 0.27's committed rules-only report and `compare.mjs`; it follows Story 0.28.
- Story 0.32 (lane B, this worktree) follows Story 0.31; it covers DW-1082 (install-upgrade row 6 ready budget 200 s to 300 s, with a MEASURED line) and DW-1195 (live:sign-in suites at least 1.4x their green median, about 950 s, or split). It must not rename, add or remove any CI job or group.
- Any `.github/workflows/*.yml` or `release/**` hunk is a RELEASE TOOL item for the Contest Planner before it merges; changes to CI hosts (runner counts or capacity) are the Planner's server work, never made in a story.
- Changes to the self-hosted runner setup also update `_bmad/custom/skill-rules.md` (the IRIS test recipe and timings) and `_bmad/custom/parallel.yaml`.
- Lane worktrees: lane B runs in `.worktrees/epic-0b` (branch `OCT-epic0b`, cycle log `cycle-log-epic-0b.md`), the second Epic 0 worktree beside lane A's.
