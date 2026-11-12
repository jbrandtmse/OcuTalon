# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge or developer builds one image, runs `docker compose up`, gets OcuTalon in its own OCUTALON namespace and signs in to its page; both build lanes get every cross-lane contract, every release-1 production item as a stub, and CI with the model mock, so they can work in parallel. Epic 0 has since been re-opened (SC-5) for small cross-cutting fixes that only it may make: start-up robustness, the root Dockerfile, CI group balance and port collisions, and the judges' README. The current re-open stories (0.26 to 0.30) make the README lead with the full video and the incident path, add a measured comparison of the agent against the fixed rules, and cut the README to about 2,000 words by moving install, feature and admin material word for word into a new GUIDE.md.

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

## Requirements & Constraints

- **Install and start.** One image recipe; durable `%SYS` and databases on a named volume; a CPF merge at every start creates namespaces, databases and mappings before anything compiles; the after-start script always exits 0, logs the failing step, and writes the ready marker only on success. Upgrades happen in place with data unchanged. A merge is retried only on ERROR #453, a bounded number of times (`STEP merge RETRY <n> after #453`, then `STEP merge OK`).
- **Judges' install stays clean.** No mock in the judges' compose file; no `docker push` or registry sign-in; the AI Hub image never enters a cache or artifact; no tracked local path or key-like string; runners never hold a model key (agent-side numbers come only from the Contest Planner's release-candidate run).
- **CI budget.** Every IRIS group finishes well under 35 minutes; no new job or group unless packing cannot fit. Test pins move with their text, never get deleted or weakened. Every story ends with every workflow green.
- **Test stacks.** Web ports bind to 127.0.0.1; `OCUTALON_TEST_WEB_PORT` stays an explicit override; the port guard waits up to 90 s, then prints `FAIL web port: …`.
- **Public text is ruled.** README, GUIDE, EXPERIENCE and any user-visible string go to the Contest Planner as PUBLIC TEXT at the spec gate, and nothing of them is committed before the ruling; ruled text is committed verbatim, never reworded to satisfy a check. `.github/workflows/*` and `release/**` hunks are RELEASE TOOL items for the Planner before merge. The README claims only what ships, keeps every number's source, stays plain English (no class names or error codes outside developer sections), credits BMAD and Claude Code, and keeps the OpenClaw not-affiliated note. Link hosts stay within `test-readme.sh`'s allow-list.
- **0.26 (order and video).** Near the top: the full video (https://youtu.be/HIyCG5E6-JQ, "One incident, approved from a phone, traced", 3:04), its MP4 on the v1.0.6 release asset, the 35-second teaser as secondary link, the video in the link bar. Order: the checkable incident path, then "What's interesting", then "New since 1.0.0" grouped interop first, personas, reminders and the digest last. No feature removed, no claim added.
- **0.27 (measuring tools; lane B, worktree `epic-0b`).** A rules-only evaluation mode scores every case with the product's no-model fallback (no model, no key), in CI in the existing evaluation group with most headroom. A held-out set of about 12 cases, expected answers committed in 6af31dab (never rebased or amended), structure checked by `docker/tests/test-eval-set.sh`. `eval/compare.mjs` sets agent and rules-only results side by side per case and in total, including unsafe outcomes; the rules-only report it reads is committed under `eval/results/`.
- **0.28 (DW-1171).** Contest checklist: a ruled `Video` row right after "Online demo" (full video, MP4 `https://github.com/jbrandtmse/OcuTalon/releases/download/v1.0.6/ocutalon-1.0.6.mp4`, teaser `https://youtu.be/wycbyfnXFMU`). The For judges Usability row's first sentence becomes the ruled sentence linking `#one-incident-end-to-end` and the full video and naming the More to try count ("fifteen", "sixteen" once Story 35.3 is in), pinned against the catalog. The anchor and link-200 check is a networked script run from `release/checklist.sh`, not in per-push `CHECK_SCRIPTS`.
- **0.29 (comparison, variant R on feature).** A new H3 at the end of "Measured": ruled paragraph (main and held-out sets apart, held-out commit linked), ruled headers, seven ruled rows (including "Items that needed you now but weren't told now", counted over all cases, which `compare.mjs` reports), ruled sentence under the table; "What changes without the agent?" becomes the ruled pointer. Every fixed-rules cell comes from the committed rules-only report, and a README test checks the column equals it. "never used for tuning" and "measured at release 1.0.8" never reach main (variant F is the Planner's release fork's).
- **0.30 (shorter README).** README.md keeps: header, tagline, badges, lead paragraph, video lines, first screenshot; "Try it in two minutes" (link bar, demo paragraph, 4 numbered steps whose "(...)" links now point into GUIDE.md); "For judges: where to look"; "One incident, end to end"; "What's interesting" with the Visual Trace screenshot; "Measured" (with 0.29's comparison once landed); "Contest checklist"; "Credits and licences". "New since 1.0.0" keeps its heading with a pointer of at most 2 sentences; the only other new prose is a closing "More" paragraph of at most 4 lines linking GUIDE.md's main sections. `wc -w README.md` about 2,000, at most 2,300 (it was 6,373). GUIDE.md, titled `# OcuTalon guide: install, features and administration`, holds byte for byte except links: the "New since 1.0.0" body; What you can use it for; How you talk to it; What OcuTalon does; Install it yourself (all subsections); Set a model key; Sign in; Telegram; Stop, start and update; Troubleshooting; For admins and developers (Repository layout, Tests and CI). README links into GUIDE.md are absolute `https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#<anchor>`; relative links inside GUIDE.md are fine; every anchor in both files resolves and the link check covers GUIDE.md. `test-readme.sh` pins follow their text to its new file, add the word cap, find GUIDE.md and a README link to it, and keep every registry-driven count (sixteen and fifteen, the 0.28 rows). Release-tool and repository-layout checks accept GUIDE.md at the root. No app code, demo guide or catalog text changes.

## Technical Decisions

- **Evaluation set.** Cases live under `eval/<case>/` (`case.json` with `name`, `kind`, `heldOut`, `description`, `snapshot`, `expectation`, `recordedBy`; recorded reader snapshots). Runs go through the product path via `EvalIn` (enabled only by `OCUTALON_EVAL=1`) with fresh `ItemId`s and the recorded id as `SourceItemId`; owner `eval` writes no notification, delivery or live event. The release-candidate run (`eval/run.sh --release-candidate`, Claude Haiku 5.5) writes `eval/release-candidate.json` (`ocutalon.evalResult/1`) and `.md`.
- **Fixed-rules fallback.** Without a usable model reply, an item becomes `tellnow` flagged fallback; an incident is grouped by fixed rules (production item plus error pattern), with no cause claimed, no fix proposed, nothing acted on. The rules-only mode scores exactly this.
- **CI.** `ci/iris.sh` runs IRIS units in throwaway compose projects; `ci/units.sh` defines groups; `IRIS_GROUPS`, the `ci.yml` matrix and `ci/iris.sh groups` must agree. The CI mock picks scenarios by marker, guide prompt, then `MOCKKEY`, never by wording.
- **Ownership.** The README, `docker/` and the rest of `ci/` are Lane B's files; `eval/`, `OcuTalon.Eval` and `release/` are Lane A's; Epic 0's re-open stories cross both by ruling. Root layout: `src/`, `web/`, `eval/`, `docker/`, `ci/`, `docs/`, `release/`, `install.sh`, `Dockerfile`, `docker-compose.yml`, `.env.example`; GUIDE.md joins the root in 0.30. Section links use `https://github.com/jbrandtmse/OcuTalon#<anchor>` (`README_URL` in `web/src/app/links.ts`); the rail links the README's `#telegram` section.

## UX & Interaction Patterns

- The README is a judge's first stop: "Try it in two minutes" at the top with the online demo link, centred header (logo by absolute raw URL, badges), link bar, "For judges: where to look", Contest checklist naming the contest. Video and Visual Trace links open in a new tab.
- The More to try panel's item count (fifteen, sixteen after Story 35.3) is stated in the README's Usability row and must match the registry.

## Cross-Story Dependencies

- Order on lane A: 0.26 → 0.28 → 0.29 (after 0.27 merges, since it reads 0.27's committed rules-only report); 0.30 after 0.28, its plan may start at once, its implement waits for the Planner's PUBLIC TEXT ruling. 0.27 runs on lane B in `.worktrees/epic-0b` (branch `OCT-epic0b`).
- 0.30 moves text that 0.26, 0.28 and 0.29 placed: "Measured" (with 0.29's H3) and the Contest checklist stay in README.md; if 0.29 lands after 0.30, its H3 still goes in the README's "Measured".
- The More to try count in 0.28 and 0.30 depends on Story 35.3; whichever merges second sets it.
- The agent half of the comparison waits for the 1.0.8 release-candidate evaluation (the Planner's release fork); 0.26 and 0.28 had to make the 1.0.8 cut.
