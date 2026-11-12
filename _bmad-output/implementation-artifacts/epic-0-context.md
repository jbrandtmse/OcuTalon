# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. One image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start. It provides a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so the build lanes can work in parallel. Stories 0.1 to 0.25 are done. Epic 0 is re-opened (lane A, after Story 0.25) for Story 0.26, which must merge before the 1.0.8 cut. It does two things. First, the README leads with the full narrated video and the incident path a judge can check, with the "New since 1.0.0" list regrouped interop first. Second, the "without the agent" comparison, which was worked out by hand, is replaced by a measured one: a rules-only evaluation mode, a held-out set of new cases, and a side-by-side report.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts (done)
- Story 0.5: Live events and the REST skeleton (done)
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production (done)
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock (done)
- Story 0.8: The demo-path test signs in and loads the page (done)
- Story 0.9: The message catalog and its one renderer (done)
- Story 0.10: The Orders demo production runs in OCUORDERS (done)
- Story 0.11: The CI model mock answers every scenario the stories need (done)
- Story 0.12: Epic 0 burn-down (done)
- Story 0.13: A start retries the CPF merge when IRIS cannot quiesce (done)
- Story 0.14: A start that recovers through the merge retry passes the live checks and the upgrade harness (done)
- Story 0.15: The Dockerfile sits at the repository root (done)
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction (done)
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers (done)
- Story 0.18: The README shows judges where to look (done)
- Story 0.19: The README names the contest (done)
- Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget (done)
- Story 0.21: The README opens with a centred header: logo, tagline and badges (done)
- Story 0.22: The More to try panel shows its items under three group headings (done)
- Story 0.23: The README header's logo and LICENSE badge link use absolute GitHub URLs (done)
- Story 0.24: A test stack's web port can never collide with a port that is still being released (done)
- Story 0.25: The web-port guard waits long enough for a stack that is still shutting down (done)
- Story 0.26: The README leads with the full video and the incident path, and a measured comparison replaces the worked-out one (backlog)

## Requirements & Constraints

**The video comes first.**
- Near the top, the README links the full narrated video: https://youtu.be/HIyCG5E6-JQ, "One incident, approved from a phone, traced", 3:04.
- It also links the same video as a no-sign-in MP4, the asset on the v1.0.6 GitHub release.
- The 35-second teaser becomes the secondary link, and the video joins the link bar.
- `docker/tests/test-readme.sh` pins both video links, the teaser as the secondary link, and the link-bar entry.

**The README's order.**
1. The incident path a judge can check: failures, then one incident, the diagnosis, the dry run, the approval (web, phone or Telegram), the fix, and Visual Trace with tokens and cost.
2. "What's interesting".
3. "New since 1.0.0", moved below "What's interesting" and grouped interop first: watching, suspend/resume/reroute, partner notice, history, usage, documents and memory. Personas, reminders and the digest come last, in one short group.

The reorder removes no feature and adds no claim, and every number keeps its source. `test-readme.sh` pins the new order. Its existing rules keep passing, and none is deleted or weakened. That includes the link allow-list, the header-block allowances and the top rule after the header. If a rule refuses the ruled text, the text is not reworded.

**The rules-only mode.**
- The new mode scores every existing case under `eval/` with OcuTalon's fixed rules only, with no model and no key, so it runs in the lane and in CI.
- The fixed rules are the product's fallback when no model answers. An item becomes tell now, marked fallback, with its reason. An incident's failures are grouped by the same production item and error pattern, with no cause claimed and no fix proposed. Nothing is acted on.
- The mode runs in CI in the existing evaluation group with the most headroom. It adds no new job or group.

**The held-out set.**
- About 12 new incidents and routine items are added under `eval/`.
- Their expected answers are committed in their own commit, before any agent run, and the spec records that commit's sha.
- The set is never used for tuning (keep a few cases held out of prompt work).
- `docker/tests/test-eval-set.sh` checks the held-out cases' structure the same way it checks the existing ones.

**The comparison report.**
- The report script sets agent and rules-only results side by side, per case and in total, and includes unsafe outcomes.
- The README's "without the agent" table shows measured numbers with the date, the model and the set size, whatever the numbers are.
- Until the agent half runs at the 1.0.8 release-candidate evaluation, the table carries placeholders, or only the rules-only half, as the Contest Planner rules.

**Scoring.**
- An item is right when its outcome matches the recorded one.
- An incident is right when both the cause category and the element at fault match the recorded ones.
- Each run records the scores, the cost of every decision (mean and maximum) and the largest model request.

**Gates.**
- The README diff, the comparison table's wording and the held-out case list go to the Contest Planner as PUBLIC TEXT at the spec gate, with placeholders for the measured numbers. None of it is committed before the ruling.
- Any `.github/workflows` hunk is a RELEASE TOOL item for the Contest Planner before it merges.
- Every workflow is green on the story's head.

**Footprint.** `README.md`, `EXPERIENCE.md` (only if a line moves), `eval/**`, `eval/run.sh` or the report script, `docker/tests/test-readme.sh` and `docker/tests/test-eval-set.sh`.

## Technical Decisions

- **The evaluation path.**
  - `eval/` holds recorded Items, incidents and reader snapshots. Each case's `case.json` already carries a `heldOut` flag beside `kind`, `expectation{causeCategory, elementAtFault, fixKind}` and `recordedBy`.
  - Runs enter through `EvalIn`, which only `OCUTALON_EVAL=1` enables, and results land in `EvalSink` under the reserved owner `eval`. An evaluation run writes no `Notification`, `Delivery` or live event.
  - Every push runs the evaluation against the CI mock. Throwaways mount `./eval` read-only, so neither the image nor the judges' compose file holds it.
- **No model key on a runner.** The agent half runs only through `bash eval/run.sh --release-candidate`, which writes `eval/release-candidate.json` (`ocutalon.evalResult/1`) and `.md`. The Contest Planner's release fork runs it at the 1.0.8 candidate. The key proof scans results with `docker/tests/lib-keys.sh`'s key patterns, so the new report and its outputs must never hold key-like text.
- **Release targets the comparison sits beside.** At least 90% of items right, at least 80% of incident causes right, every decision under $0.001 on Claude Haiku 5.5, and no request over 100,000 tokens. The README's current Measured numbers come from release 1.0.4's real-model run.
- **Ownership.** `eval/` and `OcuTalon.Eval` are Lane A's, which matches this story's lane. Epic 0 may edit any lane's files in one story. Never write a local absolute path into a tracked file. Shell tests stay ASCII-only and run on bash 3.2 with BSD or GNU tools.
- **Plain language.** The README claims only what a release ships, in plain English, with no class names or error codes outside its developer sections.

## Cross-Story Dependencies

- **Builds on the README stories.** Story 0.17 (the Measured table), Story 0.18 (the link bar, "For judges: where to look", "New since 1.0.0", "What changes without the agent?" and the link allow-list), Story 0.19 (the contest line), and Stories 0.21 and 0.23 (the pinned header block). Their pins move with the new order and are not weakened.
- **Builds on Epic 9** (the evaluation set, `eval/run.sh`, the release-candidate run and the key proof) and on Story 0.10 (the first case's file format).
- **The agent half** of the comparison depends on the 1.0.8 release-candidate evaluation, which happens outside the runner. The story is sequenced after Story 0.25 and must merge before the 1.0.8 cut.
