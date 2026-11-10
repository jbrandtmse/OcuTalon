# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so the build lanes can work in parallel. Stories 0.1 to 0.22 are done. Epic 0 is re-opened once more (lane C, after Story 0.22, for release 1.0.7) for Story 0.23: Open Exchange's README import mangles relative HTML paths (another entry's relative `<img src>` came out as a doubled, broken raw URL), so the README header's logo `src` and LICENSE badge `href` become absolute GitHub URLs, letting the listing show the logo instead of a broken image.

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
- Story 0.23: The README header's logo and LICENSE badge link use absolute GitHub URLs (backlog)

## Requirements & Constraints

**Ruled public text (0.23).** The scope is the Contest Planner's ruling, and the two new URLs are the ruled public text, committed byte for byte:
- Logo `src`: `docs/images/ocutalon-logo.png` becomes `https://raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images/ocutalon-logo.png`.
- LICENSE badge link: `href="LICENSE"` becomes `href="https://github.com/jbrandtmse/OcuTalon/blob/main/LICENSE"`.

If a README rule refuses the ruled text, the conflict goes back to the Planner. The text is not reworded.

**Scope of change.** Only README.md lines 1 and 10, and `docker/tests/test-readme.sh`.
- On line 1 only the logo's `src` changes. `alt="OcuTalon logo"`, `width="160"`, `height="160"` and the rest of the line stay.
- On line 10 only the `href` changes.
- No other README line changes. In particular, the body's relative Markdown `[LICENSE](LICENSE)` links stay as they are.

**README check.** `test-readme.sh` pins the header block verbatim, so its header pins take the two new URLs. A self-test must still show that a header logo with a different `src` is flagged. No rule is weakened:
- The header logo's file is still read by the image checks: it exists under `docs/images/` and stays under the size limit, now reached from the absolute URL.
- Every new host allowance (raw.githubusercontent.com is not allowed today) stays confined to the header block.

**Done means:** `bash docker/tests/test-readme.sh` passes every rule and every self-test, `docker/tests/test-boundaries.sh` passes, and CI is green.

## Technical Decisions

- **Header allowance mechanism (from 0.21).** The header is recognised by position and exact text: a quoted-heredoc `HEADER` constant and `header_end`. Header-only image hosts live in a separate list (`HEADER_IMAGE_HOSTS`), apart from the global `ALLOWED_HOSTS`. When the header doesn't match, nothing is exempt.
- **Never delete or weaken a rule or self-test, and never add a rule to `RULES`.** Changed rule messages or self-test labels count as public text, so they go to the Planner.
- **Script portability.** `test-readme.sh` stays ASCII-only and runs on bash 3.2 with BSD or GNU tools. For example, BSD `head -n 0` fails, so use `awk`.
- **Not a release tool.** The `test-readme.sh` hunk needs no RELEASE TOOL review (ruled for 0.21).
- **Lane ownership.** Epic 0 may edit files from any lane in one story. Never write a local absolute path into a tracked file.

## Cross-Story Dependencies

- **Built on 0.21** (the centred header, its pins, the header allowances and the `a header logo with a different src` self-test) and **0.18** (the README link allow-list). Both are merged.
- **Sequenced after 0.22** on lane C, and targeted at release 1.0.7.
- **The raw URL already works.** The orchestrator checked that `docs/images/ocutalon-logo.png` is on main and that its raw URL answers 200 image/png. The URL points at `main`, so it shows the logo merged there, not the branch's copy.
- **Known flakes.** Inherited CI flakes (for example DW-973, DW-774, DW-689 and DW-1026) can turn a run red without a cause in this story. Classify them; do not change the story to work around them.
