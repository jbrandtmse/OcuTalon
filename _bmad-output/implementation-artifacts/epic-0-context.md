# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge or developer builds one image, runs `docker compose up`, gets OcuTalon in its own OCUTALON namespace and signs in to its page; both build lanes get every cross-lane contract, every release-1 production item as a stub, and CI with the model mock, so they can work in parallel. Epic 0 has since been re-opened (SC-5) for small cross-cutting fixes that only it may make: start-up robustness, the root Dockerfile, CI group balance and port collisions, the judges' README (header, checklist, contest name, video, incident path) and a measured comparison of the agent against the fixed rules.

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

## Requirements & Constraints

- **Install and start.** One image recipe; durable `%SYS` and databases on a named volume; a CPF merge at every start creates the namespaces, databases and mappings before anything compiles; the after-start script always exits 0, logs the failing step, and writes the ready marker only on success. Upgrades happen in place with data unchanged. A merge is retried only on ERROR #453, a bounded number of times, each retry logging exactly `STEP merge RETRY <n> after #453`; live checks accept exactly one such retry followed by `STEP merge OK`. `docker/merge.cpf` stays unchanged by these fixes.
- **Judges' install stays clean.** No mock in the judges' compose file; no `docker push` or registry sign-in anywhere; the AI Hub image never enters a cache or artifact; no tracked local path or key-like string; runners never hold a model key.
- **CI budget.** Every IRIS group finishes well under 35 minutes (jobs are cancelled at 40); units of about 1,000 s at most; a new group only when packing cannot fit. Test pins move with a change, never get deleted or weakened. Every story ends with every workflow green.
- **Test stacks.** Web ports bind to 127.0.0.1 only; `OCUTALON_TEST_WEB_PORT` remains an explicit override; the port guard waits up to 90 s (3 s poll, `ss -tan` ignoring TIME-WAIT on Linux), retries the bind error at most twice, then prints the loud `FAIL web port: …` line; other failures return at once; teardowns run in the foreground.
- **Public text is ruled.** README, EXPERIENCE and any user-visible string go to the Contest Planner as PUBLIC TEXT at the spec gate; ruled text is committed verbatim, never reworded to satisfy a check. `.github/workflows/*` and `release/**` hunks are RELEASE TOOL items for the Planner before merge. The README claims only what ships, keeps every number's source, stays in plain English, and keeps `docker/tests/test-readme.sh` rules passing (none deleted or weakened; link hosts limited to its allow-list).
- **Story 0.26 (README order and video).** Near the top: the full narrated video (https://youtu.be/HIyCG5E6-JQ, "One incident, approved from a phone, traced", 3:04) and its no-sign-in MP4 on the v1.0.6 release asset, the 35-second teaser as the secondary link, the video in the link bar. The README leads with the checkable incident path (failures, one incident, diagnosis, dry run, approval by web, phone or Telegram, fix, Visual Trace with tokens and cost), then "What's interesting", then "New since 1.0.0" grouped interop first, with personas, reminders and the digest last. The comparison work moved to Story 0.27.
- **Story 0.27 (measured comparison and DW-1171).**
  - A rules-only evaluation mode scores every existing case with the product's no-model fallback only (no model, no key), running in CI in the existing evaluation group with the most headroom (no new job or group).
  - A held-out set of about 12 new incidents and routine items, whose expected answers are already committed in 6af31dab (never rebased or amended; the sha is recorded in the spec); `docker/tests/test-eval-set.sh` checks its structure like the existing cases.
  - The report script sets agent and rules-only results side by side, per case and in total, including unsafe outcomes, and adds the row "Items that needed you now but weren't told now", counted over all cases.
  - FIRST README edit (DW-1171): in the Contest checklist, a new `Video` row right after "Online demo", linking the full video, the MP4 (`https://github.com/jbrandtmse/OcuTalon/releases/download/v1.0.6/ocutalon-1.0.6.mp4`) and the 35-second teaser (`https://youtu.be/wycbyfnXFMU`), wording verbatim from the ruling. The "For judges" Usability row's first sentence becomes the ruled sentence linking `#one-incident-end-to-end` and the full video, naming the More to try count ("fifteen", or "sixteen" once Story 35.3 is in; whichever merges second sets it), with the rest of the row unchanged. README tests pin the count against the catalog, check that the anchor resolves to a heading, and check that the Video row's links return 200.
  - The comparison (variant R on feature) is a new H3 at the end of "Measured": the ruled paragraph (main and held-out sets stated apart, the held-out commit linked), the ruled headers, seven ruled rows and the ruled sentence under the table; "What changes without the agent?" becomes the ruled pointer to it. Every fixed-rules cell comes from the committed rules-only report JSON that `eval/compare.mjs` reads, and a README test checks the column equals it. The agent half shows placeholders (or rules-only only) until the 1.0.8 release-candidate evaluation, run by the Planner's release fork. "never used for tuning" and "measured at release 1.0.8" must never reach main.

## Technical Decisions

- **Evaluation set.** Cases live under `eval/<case>/` (`case.json` with `name`, `kind`, `heldOut`, `description`, `snapshot`, `expectation`, `recordedBy`; recorded reader snapshots). Runs go through the product path via `EvalIn` (enabled only by `OCUTALON_EVAL=1`), minting fresh `ItemId`s with the recorded id as `SourceItemId`; owner `eval` writes no notification, delivery or live event. An item scores right when its outcome matches; an incident when cause category and element at fault both match. The release-candidate run (`eval/run.sh --release-candidate`) uses Claude Haiku 5.5 and writes `eval/release-candidate.json` (`ocutalon.evalResult/1`) and `.md`. Some cases are held out of prompt work, and targets are shares of the set.
- **Fixed-rules fallback.** Without a usable model reply, an item becomes `tellnow` flagged fallback with its reason; an incident is grouped by fixed rules (production item plus error pattern) with no cause claimed and no fix proposed; nothing acts. The rules-only mode must score exactly this behaviour.
- **CI.** `ci/iris.sh` runs IRIS units in throwaway compose projects on the self-hosted runner and locally; `ci/units.sh` defines groups and shards; `IRIS_GROUPS`, the `ci.yml` matrix and `ci/iris.sh groups` must agree, and jobs are named `iris (<group>)`. The CI mock (Node, `ci/mock/`, scenarios as JSON under `ci/mock/scenarios/<A|B>/`) picks scenarios by marker, guide prompt, then `MOCKKEY`, never by wording.
- **Contracts and ownership.** Each lane owns its production items in its own region of the one production definition; cross-lane APIs keep the signatures Epic 0 fixed; every persistent non-message class sets `DEFAULTGLOBAL` from the short-name registry with its storage block committed; only `OcuTalon.Data.Public.Settings` touches `^OcuTalonPublic`; catalog text comes from the one renderer.
- **Release history.** The Dockerfile sits at the repository root; harnesses accept `docker/Dockerfile` for v1.0.4 and earlier trees.

## UX & Interaction Patterns

- The README is a judge's first stop: "Try it in two minutes" at the top, centred header (logo by absolute raw URL, ruled tagline, badges), link bar, "For judges: where to look", Contest checklist naming the contest. Video and Visual Trace links open in a new tab.
- The demo guide's More to try panel groups items under ruled headings ("Incidents and fixes", "Memory and documents", "Safety and settings", "Usage and history"), driven by registry data; empty groups show no heading. README and EXPERIENCE keep the total item count, which the README's Usability row also states.

## Cross-Story Dependencies

- Story 0.27 is 0.26's split sibling and builds on its branch history (held-out answers in 6af31dab); the README video links of 0.26 are what 0.27's Video row and Usability sentence point to.
- The More to try count in Story 0.27's Usability sentence depends on Story 35.3 (fifteen before it, sixteen after); whichever merges second sets the number.
- The agent half of the comparison waits for the 1.0.8 release-candidate evaluation (Contest Planner's release fork); 0.26 must merge before the 1.0.8 cut.
- Stories 0.24 and 0.25 resolve DW-1099; 0.25 builds on 0.24's guard. Story 0.14 builds on 0.13. Story 0.20 builds on 0.15. README stories chain 0.17 → 0.18 → 0.19 → 0.21 → 0.23 → 0.26 → 0.27, each editing only its ruled lines.
