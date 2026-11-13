# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge or developer builds one image, runs `docker compose up`, gets OcuTalon in its own OCUTALON namespace and signs in to its page. Both build lanes get every cross-lane contract, every release-1 production item as a stub, and CI with the model mock, so they can work in parallel. Epic 0 has since been re-opened (SC-5) for small cross-cutting fixes that belong to no feature epic: start-up robustness, CI balance and port guards, the judges' README, the measured comparison of the agent against the fixed rules, and release hotfixes. The newest re-open story, 0.35, tunes the attention (Triage) agent's instructions so that routine attention decisions meet their stated target (at least 22 of 24) in every release-candidate attempt, and the README stops showing a missed target.

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
- Story 0.27: The measuring tools for the agent-versus-fixed-rules comparison (rules-only mode, held-out set, report)
- Story 0.28: DW-1171: the Contest checklist gets a Video row; the For judges Usability row links the incident path and the full video
- Story 0.29: The README's comparison of the agent and the fixed rules, filled from the committed rules-only report
- Story 0.30: A shorter README for judges, with install, feature and admin material moved word for word to GUIDE.md
- Story 0.33: DW-1191: the webhook secret test's malformed-salt case can never equal the real salt
- Story 0.34: The install-path OAuth2 check skips the built web bundle, so a release candidate passes it
- Story 0.35: Routine attention decisions meet their target

## Requirements & Constraints

- **Story 0.35 is bound by a Contest Planner ruling** (`prompts/story-035-ruling-20261112.md`). Its plan goes to the Planner before any implement.
  - The plan reads the release-candidate evaluation runs of 1.0.4 to 1.0.8 and names each routine item the attention agent got wrong, in how many attempts, and why (the outcome it chose against the expected one). 1.0.8's attempts scored 21, 20 and 20 of 24.
  - Only the attention agent's instructions change. Each outcome's test is stated more clearly, and no example copies or paraphrases any main-set or held-out case.
  - The CI check that keeps held-out case text out of every prompt and mock scenario must also keep the main set's item texts out of the prompts.
  - The bar, on the real model (Claude Haiku 5.5), 3 evaluation attempts: main-set routine decisions at least 22 of 24 in all 3 attempts (stricter than REL-5's two of three); held-out items no worse than 1.0.8's 4 of 4; incidents unchanged (SM-2, at least 10 of 11); injection and S6 cases still lead to 0 actions; the demo gate still 30 of 30 on 10 runs. If any of these misses, the story does not merge and the numbers go to the Planner.
  - No public text changes. The README's numbers move only through the 1.0.9 release-candidate fill. Real-model runs stay inside the evaluation harness's spending caps.
- **Scoring.** An item is right when its outcome matches the recorded outcome. Outcomes are `ignore`, `digest`, `tellnow` and `act` (`OcuTalon.Msg.Enum`). The product's target is SM-1 (at least 90% of items).
- **Keys.** Runners never hold a model key. Real-model numbers come from a release-candidate run (`eval/run.sh --release-candidate`), which the Contest Planner's release fork or the owner runs, never per-push CI.
- **Public text and release tools are ruled.** README, GUIDE and any user-visible string go to the Contest Planner as PUBLIC TEXT at the spec gate, and are committed verbatim after the ruling. `.github/workflows/*` and `release/**` hunks go to the Planner as RELEASE TOOL items before merge.
- **Every story** ends with every workflow green. Test pins move with their text and are never deleted or weakened. No new CI job or group unless packing cannot fit, and every IRIS group stays well under 35 minutes.

## Technical Decisions

- **The attention agent** is `OcuTalon.Agent.Triage`, a declarative `%AI.Agent` with static `XData INSTRUCTIONS`, no tools, model `claude-haiku-5-5` and effort `low`. No sampling parameters are ever sent. The system prompt and tool list stay first and static so they can be cached; everything variable goes in the user message.
- **Instruction rules a change must keep:**
  - No `{{` anywhere in an INSTRUCTIONS block (a CI check, which also reads the persona paragraph).
  - The persona paragraph is fixed: a persona shapes the wording of Triage's reasons only, never an outcome or a confidence.
  - The reply is one JSON object validated against `OcuTalon.Bridge.Msg.DecisionPayload`, with plain-English reasons and a confidence from 0 to 1. Content that fails validation is `invalid` and falls back.
- **Input.** `OcuTalon.Agent.Input` is the one renderer of an Item into the user message (local-time preamble, quoting, provenance, then any persona, memory or precedent blocks as quoted data, then the item). Evaluation items go through the same path.
- **Fixed-rules fallback.** Without a usable reply, the item becomes `tellnow`, flagged as a fallback. The rules-only evaluation mode (Story 0.27) scores exactly this path.
- **Evaluation harness.**
  - Cases live in `eval/<case>/` (`case.json` with `name`, `kind`, `heldOut`, `description`, `expectation`, plus recorded snapshots). The held-out answers are in commit 6af31dab, which is never rebased or amended.
  - `EvalIn`, enabled only by `OCUTALON_EVAL=1`, sends each case through `Intake` with fresh `ItemId`s, the recorded id as `SourceItemId` and owner `eval`. Results go to `EvalSink`. Nothing writes a Notification, Delivery or live event, and no session cost or daily cap counts the run.
  - Per push, the harness runs against the CI mock. A release-candidate run makes up to three attempts, each with the 10-run demo gate, and writes `eval/release-candidate.json` (`ocutalon.evalResult/1`) and `.md`. `eval/compare.mjs` sets agent and rules-only results side by side.
- **CI mock.** A request picks its scenario by a `[[mock:<name>]]` marker, then by an exact guide prompt (scenarios under `ci/mock/scenarios/B/`), then by the agent's `MOCKKEY` (`triage`, `diagnosis`, `chat`). Prompt wording never picks a scenario, so rewording Triage's instructions does not change mock routing. Lane A adds scenarios only as files under `ci/mock/scenarios/A/`.
- **Ownership.** Agents, `eval/`, `OcuTalon.Eval` and `release/` belong to Lane A. The README, `docker/` and the rest of `ci/` belong to Lane B. Epic 0's re-open stories cross both by ruling, within each story's stated footprint.

## Cross-Story Dependencies

- **Story 0.35** is on lane A, after Story 0.29 and before Story 25.3.
  - It builds on 0.27's held-out set and rules-only mode, and on the existing prompt-leak CI check that keeps held-out text out of prompts and mock scenarios, which it extends to the main set's item texts.
  - Its measured result reaches the README only through the 1.0.9 release-candidate fill.
- **Story 0.29** reads the rules-only report that 0.27 commits under `eval/results/`.
- **Stories 0.28 and 0.30.** The More to try count they state (fifteen, or sixteen once Story 35.3 is in) follows the catalog. Whichever of 0.28 and 35.3 merges second sets it.
- **Story 0.34** was a 1.0.8 release-blocker hotfix, built in its own worktree (`OCT-epic0c`). Story 0.27 ran in `.worktrees/epic-0b` (branch `OCT-epic0b`).
