# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge or developer builds one image, runs `docker compose up`, gets OcuTalon in its own OCUTALON namespace and signs in to its page. Both build lanes get every cross-lane contract, every release-1 production item as a stub, and CI with the model mock, so they can work in parallel. Epic 0 has since been re-opened (SC-5) for small cross-cutting fixes that only it may make: start-up robustness, the root Dockerfile, CI group balance and port collisions, the judges' README, and a measured comparison of the agent against the fixed rules. The open work is that comparison: the rules-only measuring tools (Story 0.27), the README's Video row and Usability sentence (Story 0.28), and the README comparison filled from the committed report (Story 0.29).

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
- Story 0.26: The README leads with the full video and the incident path, and a measured comparison replaces the worked-out one
- Story 0.27: A measured comparison of the agent and the fixed rules replaces the worked-out one
- Story 0.28: DW-1171 follow-up: the README's Contest checklist gets a Video row, and the For judges Usability row links the incident path and the full video
- Story 0.29: The README's comparison of the agent and the fixed rules, filled from the committed rules-only report

## Requirements & Constraints

- **Rules-only evaluation (0.27).** A new mode scores every existing evaluation case with OcuTalon's fixed rules only (the product's no-model fallback), with no model and no key, so it runs in the lane and in CI. It runs in CI inside the existing evaluation group with the most headroom (no new job or group). Its report, the JSON that `eval/compare.mjs` reads, is committed under `eval/results/`.
- **Held-out set (0.27).** About 12 new incidents and routine items (four held-out snapshots) are added under `eval/`. Their expected answers were already committed in 6af31dab, before any agent run, and that commit must never be rebased or amended. The spec records the sha. The set is never used for prompt tuning. `docker/tests/test-eval-set.sh` checks its structure the way it checks the existing cases.
- **Report (0.27).** The report script sets agent and rules-only results side by side, per case and in total, including unsafe outcomes. `compare.mjs` also reports the row "Items that needed you now but weren't told now", counted over all cases. This is the measure for missed "needs you" items, which counts as a regression even when overall accuracy holds.
- **No model key on runners.** The agent half of the comparison runs at the 1.0.8 release-candidate evaluation, in the Contest Planner's release fork.
- **README (0.28, 0.29).** Use the ruled wording verbatim and never reword it to satisfy a check.
  - 0.28: add the Video row right after "Online demo". In the For judges Usability row, the first sentence becomes the ruled sentence linking `#one-incident-end-to-end` and the full video. Its More to try count is "fifteen", or "sixteen" once Story 35.3 is in, and a test pins it against the catalog. The network check (the anchor resolves, the Video links return 200) runs from `release/checklist.sh` and is not in per-push CI.
  - 0.29: the comparison goes in a new H3 at the end of "Measured", with the ruled paragraph, headers, seven rows and the sentence under the table. Every fixed-rules cell comes from the committed report, and a README test checks that the column equals it.
  - "never used for tuning" and "measured at release 1.0.8" must never reach main.
- **Gates.** Public text (README, EXPERIENCE, user-visible strings, held-out case list) goes to the Contest Planner as PUBLIC TEXT at the spec gate, before implement. Any `.github/workflows/*` or `release/**` hunk goes to the Planner as RELEASE TOOL before merge. Test pins move with a change and are never deleted or weakened. Every story ends with every workflow green.
- **Standing rules.**
  - The judges' compose file holds no mock.
  - No `docker push` or registry sign-in anywhere.
  - No tracked local path or key-like string.
  - Every IRIS CI group finishes well under 35 minutes.
  - `docker/merge.cpf` and `docker/after-start.sh` stay unchanged.

## Technical Decisions

- **Evaluation cases.** Each case lives in `eval/<case>/`:
  - `case.json`: `name`, `kind`, `heldOut`, `description`, `snapshot`, `expectation{causeCategory, elementAtFault, fixKind}` and `recordedBy`.
  - `snapshot.json`: format `ocutalon.readerSnapshot/1`.
  - Throwaways mount `eval/` read-only, so neither the image nor the judges' compose file holds it.
- **Scoring.** An item is right when its outcome matches the recorded one. An incident is right when both its cause category and its element at fault match. Targets are shares of the set.
- **Fixed-rules fallback, which the rules-only mode must reproduce.**
  - An item becomes `tellnow`, flagged as a fallback with its reason, and nothing acts.
  - An incident groups failures by production item and error pattern within the settle window, claims no cause and proposes no fix.
- **Evaluation path.** Runs go through `EvalIn`, an adapterless service that `OCUTALON_EVAL=1` enables, with owner `eval`. Each run mints fresh `ItemId`s and keeps the recorded id as `SourceItemId`. Results go to `EvalSink`, never to notifications, deliveries or live events.
- **Release-candidate run.** `eval/run.sh --release-candidate` runs on Claude Haiku 5.5 and writes `eval/release-candidate.json` (`ocutalon.evalResult/1`) and its `.md`. `eval/key-proof.sh` proves that no key leaks.
- **CI mock.** The mock picks a scenario by marker, then by guide prompt, then by `MOCKKEY`, never by prompt wording. Scenarios are JSON files under `ci/mock/scenarios/<A|B>/`. The 0.29 ruling also says a CI check keeps the held-out cases' names and text out of every prompt and mock scenario.
- **IRIS CI groups.** `IRIS_GROUPS`, the `ci.yml` matrix and `ci/iris.sh groups` must agree, and every job is named `iris (<group>)`.

## Cross-Story Dependencies

- **Story 0.27** is Part B of a three-way split of Story 0.26's comparison. It runs on lane B in the second Epic 0 worktree (`.worktrees/epic-0b`, branch `OCT-epic0b`, cycle log `cycle-log-epic-0b.md`). Its files are 0.26's set (`README.md`, `EXPERIENCE.md` only if a line moves, `eval/**`, `docker/tests/test-readme.sh`, `docker/tests/test-eval-set.sh`), plus the evaluation classes its plan names.
- **Story 0.28** runs after 0.26 merges and before 0.27. Whichever of 0.28 and Story 35.3 merges second sets the More to try count.
- **Story 0.29** (lane A) waits for 0.28 and for 0.27's merge, because it reads 0.27's committed rules-only report.
- **The agent column** waits for the 1.0.8 release-candidate evaluation.
- **Earlier re-opens:**
  - Story 0.14 builds on 0.13, and 0.20 builds on 0.15.
  - Story 0.25 builds on 0.24's port guard.
  - The README stories chain: 0.17, 0.18, 0.19, 0.21, 0.23, 0.26, 0.28, 0.29.
