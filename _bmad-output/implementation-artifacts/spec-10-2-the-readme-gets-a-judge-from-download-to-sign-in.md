---
title: 'The README gets a judge from download to sign-in'
type: 'feature'
created: '2026-10-28'
status: 'done'
baseline_revision: '5e488e5c1e3246bef0f3e94960c36c9c42cff6e5'
baseline_commit: '5e488e5c1e3246bef0f3e94960c36c9c42cff6e5'
review_loop_iteration: 0
followup_review_recommended: true
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-10-context.md']
warnings: ['oversized']
deferred:
  - 'github.com/jbrandtmse/OcuTalon answered HTTP 404 on 2026-10-28 (the repository is private until 0.1.0), so the README clone command and the page README_URL resolve only once the owner makes it public: the release checklist (Story 11.4) and the 1.0.0 README pass (Story 31.3) recheck every README link on the public page, where the GitHub heading slugs are also seen for the first time (Design Note 8)'
  - summary: >-
      The README's LAN warning names the default IRIS accounts but gives steps only for the README account.
    evidence: |-
      README.md "Sign in" says the Management Portal can be reached from the LAN until the passwords of the default IRIS accounts and of the README account are changed, and only the README account has a how-to. The wording is the author's decision in DW-3 (2026-10-18, 2026-10-19), which the spec fixes, so this story did not change it; whether the README should also say how to change the default accounts' passwords, or how to publish the port on 127.0.0.1 only, is a product and security-posture call.
    location: >-
      README.md (## Sign in)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The repository has no `README.md`. A judge cannot find out what OcuTalon does, where to get the build 154 image, how to start, sign in or set a key, and `install.sh` already sends every failed start to "the Troubleshooting section of README.md", which does not exist. The page's README links ("How to set a key", "Install it yourself", About, the guide's finish link) open a README that is not there, and nothing checks them.

**Approach:** Write the release-1 `README.md` at the root, and a hermetic check, `docker/tests/test-readme.sh`, in the hosted `checks` job. The check pins the README's structure, the facts it must state, the commands it must share with `install.sh`, the public-text rules, and that every README link the product can show reaches the README or one of its sections (`#telegram` only once `Included()` can return 1).

## Boundaries & Constraints

**Always:**
- **Top of the README, in this order:** `# OcuTalon`, then nothing but blank lines, then `## Try it in two minutes`, `## What's interesting`, `## Contest task → where to see it`. The teaser line `Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU` (a plain link, no embed, no thumbnail) is the last line of the third section, after the table.
- **Try it in two minutes:** the online demo first: `https://demo.ocutalon.com`, "nothing to install, and no Early Access image needed", and its sign-in details are on the splash screen. Then the local path as four numbered steps: load the image, run `./install.sh`, sign in, follow the demo guide on the page.
- **What's interesting:** 120 words at most. It says that OcuTalon runs as an IRIS Interoperability production, so the agent is an Interoperability workflow whose work shows in Visual Trace; that an IRIS AI Hub agent makes one attention decision per item, with its reasons and cost; that nothing risky runs without your yes (a dry run with counts first, approval in the web chat, every answer in the IRIS audit log); and why it was built that way.
- **The table:** one row each for the three task parts (an IRIS Interoperability workflow, an IRIS AI Hub agent, a decision-making task) and the five criteria (Complexity, Clarity of Instructions, Developer Experience, Applicability, Usability), each with the release-1 feature that meets it and where the online demo or the repository shows it.
- **The other H2 sections:** `## What OcuTalon does`, `## Install it yourself`, `## Set a model key`, `## Sign in`, `## Stop, start and update`, `## Troubleshooting`, `## For admins and developers`, `## Credits and licences` (Design Note 4 gives their content).
- **Exact strings,** each taken from its source: the four outcomes Ignore, Digest, Tell now and Act; `irishealth-community:2026.3.0AI.154.0` and `ocutalon-iris-base:2026.3.0AI.154.0`; Docker Compose 2.24 or later (DW-2); user `ocutalon`, password `ocutalon`; the commands `install.sh` prints (`docker compose up -d --force-recreate`, `docker compose up -d --build`, `docker compose logs iris`, `docker compose ps`; DW-134); `do ##class(OcuTalon.Core.Admin).SetDemoMode(<0 or 1>)`, which needs the OcuTalonAdmin role or `%All` (U-72); the kept-OCUORDERS sentence as EXPERIENCE.md writes it (DW-45); "Built with the BMAD Method and Claude Code."; and "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation."
- **Plain English.** Class names and error codes appear only inside `## For admins and developers`. The check's patterns: `##class(`; a dotted name of two or more parts that each start with an upper-case letter (a leading `%` allowed), such as `OcuTalon.Core.Admin` or `Security.Users` (so `README.md` and `demo.ocutalon.com` are not names); `ERROR #<digits>`; and `<` three or more upper-case letters `>`, such as `<UNDEFINED>`.
- **Every product claim** is something release 1 (0.1.0) ships: Epics 0 to 9 and 11, with the online demo from Epics 16 and 29. Each claim sentence is listed with its source in the spec's `## Verification` (Claims).
- **Every link exists:** an in-README anchor reaches a heading, a relative link reaches a file or folder of the repository, and an external link's host is on the allow-list (Design Note 9).
- **`test-readme.sh`:** bash 3.2 and BSD/GNU tools (install.sh's rules), starts nothing, and reads only text files of the tree (`lib-scan.sh`'s `scan_files`: tracked or new, never `.env`). Each rule first runs on a copy of its input broken for that rule, which it must flag, then on the real file. One `PASS`, `FAIL` or `SKIP` line per rule; exit 0 only when no rule fails.

**Never:**
- No `Telegram` in any case (so no `TELEGRAM_BOT_TOKEN` either) while `Included()` has its test-only body; no other model provider (whole words, any case: OpenAI, GPT, ChatGPT, Gemini, Mistral, Cohere, Llama, Ollama, Bedrock, Azure, DeepSeek, Grok); no "from your phone"; no "per step" cost or tokens.
- No `docker compose restart`, no "install.sh again", "rerun" or "re-run" anywhere (DW-134).
- No key or key-shaped example (`ANTHROPIC_API_KEY=<your key>` only), no local machine path, and no link to or name of another contest entry. No private infrastructure: the check refuses `ocutalon-ci`, `ocutalon-slot`, `.worktrees`, `.coordination`, `digitalocean`, `droplet`, `sfo2`, `Contest Planner`, `epic-cycle`, `self-hosted`, and any IPv4 address but `127.0.0.1` and `0.0.0.0`.
- No "Find a bug in AI Hub" or bonus section, and no link to the AI Hub bug reports (owner: 1.0.0 README).
- `OpenClaw` appears only in the not-affiliated note (no tagline in the README).
- No edit to `web/**`, `src/**`, `install.sh`, `.env.example`, `docker-compose.yml`, `.github/workflows/**`, or any contended path. No live CI unit is added.

## I/O & Edge-Case Matrix

The rules of `test-readme.sh`. The first row is the real tree; every other row is the broken input a rule's self-test feeds it, and the real README passes that rule.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Real README | The tree as committed | Every rule PASS; one `SKIP #telegram` naming `Included()`'s test-only body | exit 0 |
| Top order | A line before the first H2, or the three H2s swapped | FAIL `top` | exit 1 |
| Demo first | `./install.sh` before `https://demo.ocutalon.com`, or "nothing to install" / "no Early Access image" / "splash" missing | FAIL `try-it` | exit 1 |
| Word cap | What's interesting at 121 words, or missing Interoperability, Visual Trace, AI Hub, dry run, audit log | FAIL `interesting` | exit 1 |
| Table | A task part or criterion row missing | FAIL `contest-table` | exit 1 |
| Teaser | Line absent, changed, or outside the table's section | FAIL `teaser` | exit 1 |
| Install facts (DW-2) | `2.24`, the Health image name, the base name, `docker load -i`, `docker tag`, `docker compose up -d`, `docker compose ps`, the EAP portal, arm64/x64, the non-Health name, HealthShare, HSCUSTOM or ARM64 missing | FAIL `install` | exit 1 |
| Integration: install.sh's pointer | `install.sh` names "The Troubleshooting section of README.md"; README lacks `## Troubleshooting` | FAIL `install-pointer` (reads the section names out of `install.sh`) | exit 1 |
| Integration: install.sh's commands (DW-134) | A command `install.sh` prints after `run:` (today `docker compose up -d --force-recreate`, `docker compose up -d --build`, `docker compose logs iris`, `docker compose ps`) is missing from the README, the extraction finds none, or `docker compose restart` / `install.sh again` / `rerun` / `re-run` is present | FAIL `commands` | exit 1 |
| Key and account | `ANTHROPIC_API_KEY`, `.env.example`, Claude Haiku 5.5, fixed rules, `ocutalon`/`ocutalon`, "Sign in to Visual Trace" missing | FAIL `key-account` | exit 1 |
| LAN (DW-3) | `## Sign in` lacks the LAN / Management Portal warning or the link to the password subsection | FAIL `lan` | exit 1 |
| Demo mode (DW-45, U-72) | The SetDemoMode line not verbatim, `OcuTalonAdmin` or `%All` missing, `Admin.cls` lacks `ClassMethod SetDemoMode(`, or the kept sentence differs from EXPERIENCE.md's row | FAIL `demo-mode` | exit 1 |
| Developer-only names | `##class(` or `OcuTalon.Core.X` or `ERROR #5001` above `## For admins and developers` | FAIL `dev-only` | exit 1 |
| Public text | Note altered, OpenClaw elsewhere, BMAD Method or Claude Code credit missing, licence pointers missing, a provider name, "from your phone", "per step", a private-infrastructure word | FAIL `public-text` | exit 1 |
| Telegram | `Telegram` in the README while `Included()` is test-only | FAIL `no-telegram` | exit 1 |
| Integration: the page's links | A product README anchor (`#readme`, a `*_ANCHOR` constant, a `readmeSection(..., '<x>')` literal, a `jbrandtmse/OcuTalon#<x>` literal in `web/src/app` or non-test `src/**/*.cls`) with no README heading | FAIL `product-links`, naming the anchor | exit 1 |
| `Included()` changed | Its body is anything but `Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1` | `#telegram` is covered, and `Telegram` is allowed: a README with no `#telegram` heading FAILs `product-links` | exit 1 when missing |
| README links | `](#nowhere)`, `](docs/missing.md)`, or a link to a host not on the allow-list | FAIL `readme-links` | exit 1 |
| Duplicate headings | Two headings with one slug | FAIL `readme-links` | exit 1 |
| No README | `README.md` absent | FAIL every rule that reads it | exit 1 |

</intent-contract>

## Code Map

- `install.sh:317,337-339,353-362,398` -- the strings the README must share: the key line (`add it to .env and run: docker compose up -d --force-recreate`), `docker compose logs iris`, "The Troubleshooting section of README.md lists the usual causes and fixes.", `To apply an update, run: docker compose up -d --build`; `:393-395` the ready block. Read only.
- `docker/tests/test-install-script-live.sh:142-143` -- runs "the README's manual command" `docker tag <loaded Health ref> <base>`; the README's retag must have that form. Read only.
- `docker-compose.yml` -- `name: ocutalon`, service `iris`, `env_file` `.env` with `required: false` (Compose 2.24, DW-2), `${OCUTALON_WEB_PORT:-52773}:52773` on every interface (DW-3), volume `durable` (so `ocutalon_durable`). Read only.
- `.env.example` -- `ANTHROPIC_API_KEY=`, `TELEGRAM_BOT_TOKEN=` (never mentioned), `OCUTALON_WEB_PORT` comment. Read only.
- `web/src/app/links.ts:5` -- `README_URL = 'https://github.com/jbrandtmse/OcuTalon#readme'`. Consumers: `banners/banner-view.ts:64-67` (Install it yourself, How to set a key → `readme`), `about/about-dialog.ts:94`, `guide/demo-guide.ts:477`, `banners/banner-stack.ts:22` and `rail/telegram-card/telegram-card.ts:59` (`readmeSection(README_URL, TELEGRAM_ANCHOR)`), `rail/rail-view.ts:57,164-166` (`TELEGRAM_ANCHOR = 'telegram'`, `readmeSection`). All read only (banners/ and guide/ are contended).
- `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls:38` -- `READMELINK` = the same `#readme` address (server-side text). Read only.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:20-23` -- `Included()`: `Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1`. Read only.
- `src/ocutalon/cls/OcuTalon/Core/Admin.cls:20-26` -- `SetDemoMode`, OcuTalonAdmin or `%All` (U-72). `Core/SettingsOps.cls:27-31` -- the on, off and kept answers it prints ("Demo mode is on. The Orders production runs in namespace OCUORDERS. ...", "Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. ...", "Demo mode is off. {how} ..."). Read only.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md:702` -- the kept-OCUORDERS row, the sentence's one source (DW-45); `:123,142,165` About, tagline and note rules; `:868-871` the popover ("Sign in to Visual Trace"; local text). Read only.
- `web/src/app/chat/chat-view.ts:61` and epics.md:1748 -- the outcome meanings the page shows: Ignore "Recorded; nobody notified", Digest "Saved for later; nobody notified now", Tell now "Needs you now", Act "OcuTalon took or requested an action".
- `docker/tests/test-demo-switch.sh:150` -- measured: `dc exec -T iris iris session IRIS -U OCUTALON` logs in as irisowner (`%All`) and `SetDemoMode` runs. `docker/tests/test-install-upgrade.sh:158-163` -- measured: in `%SYS`, `Kill p Set p("Password")="..." Write ##class(Security.Users).Modify("ocutalon",.p)` prints 1 and an upgrade keeps the password.
- `docker/tests/lib-scan.sh:11-40` -- `scan_files`, `scan_rule` (bad sample, good sample, real files): the pattern `test-readme.sh` extends. `docker/tests/test-install-script.sh:251` -- a `check` helper and `out_has` style.
- `docker/tests/test-boundaries.sh:96-126` -- the scan scopes; README.md is already in `$all_files` (paths and keys) but not in the must-scan list at `:118-119`.
- `ci/units.sh:6` -- `CHECK_SCRIPTS`; `:81` `NOT_IRIS_INPUT_PATTERN` declares `README.md` and `docker/tests/test-*.sh`, so neither runs an IRIS group. `ci/checks.sh` runs each `docker/tests/test-<name>.sh`.
- `docker/tests/test-ci-config.sh:38` -- the units rule: every `docker/tests/test-*.sh` is in exactly one list.
- `_bmad-output/implementation-artifacts/epic-0-readme-notes.md` -- the table's blank row for Epic 0's merge head ("This row is the README's figure").
- `web/public/assets/licenses/` (Inter, JetBrains Mono, Montserrat OFL; Lucide ISC), `docker/ipm/LICENSE` (IPM, MIT), `web/angular.json:37` (`extractLicenses`: the build writes `3rdpartylicenses.txt` beside the page) -- the third-party notices the README points to. No root LICENSE exists.
- `src/ocutalon/cls/OcuTalon/Production.cls`, `src/ocutalon/cls/OcuTalon/Agent/`, `install.sh`, `.github/workflows/ci.yml`, `ci/`, `eval/`, `logo/` -- repository places the table may point to (all exist).

## Tasks & Acceptance

**Execution:**
- Task 0 (measure, once) -- the README walkthrough on a lane-C throwaway, before writing the commands it settles. A scratch script, `readme-walkthrough.sh` in the implement stage's own scratchpad folder (never committed), sources `docker/tests/lib-live.sh` (`live_start t10w`, `live_web_port`, its `dc`, its cleanup trap) and, with the lane's variables (Verification): builds and starts the stack and waits for healthy; records `dc ps`'s STATUS text once healthy; `dc logs iris` prints; `dc exec -T iris cat /durable/ocutalon-after-start.log` shows `STEP` lines and a `RESULT OK` line; `dc up -d --force-recreate` gives a new container ID on the same volume (`docker volume inspect --format '{{.CreatedAt}}'` unchanged) that reaches healthy; the README's password command, piped into `dc exec -T iris iris session IRIS -U %SYS` in its README form except that the random password comes from an environment variable and is never printed, prints 1, after which the sign-in POST (test-bundle-folder.sh's three lines) with the new password reaches `<app-root` and the old one does not. It never touches the root `.env`. Then `ci/iris.sh teardown` with the tag. Record the results under `## Verification`; a result that differs from Design Note 4 changes the README text, never the measurement.
- `_bmad-output/implementation-artifacts/epic-0-readme-notes.md` -- fill the README-figure row: 2026-10-21, `b6459b8` (Epic 0's head at its merge, 67989bb), self-hosted x64 runner `ocutalon-ci-1`, two jobs at once, build 1, ready 160, `ci` run 39545049306, job `iris (browser)` 119041216742, line `FIRST-START engine=x86_64 build=1s ready=160s`, no `WARN` line (measured at this plan from the run's log) -- AD-23 puts the figure there, and the README quotes it.
- `README.md` (new) -- write the release-1 README to the contract and Design Note 4. The four outcomes with the page's meanings; the install facts with DW-2's minimum; DW-3's LAN warning and the plain "change the README account's password after your first sign-in"; DW-134's commands; DW-45's sentence and U-72's roles in `### Demo mode`; the first-start figures of Design Note 5; the teaser line; the credits and the licence pointers.
- `docker/tests/test-readme.sh` (new, mode 100755, hermetic) -- every rule of the matrix, each self-tested on a broken copy first, as `lib-scan.sh`'s `scan_rule` does for line rules. Read inputs from the tree: `README.md`, `install.sh`, `Admin.cls`, `In.cls`, EXPERIENCE.md, `web/src/app/**/*.ts` (not `*.spec.ts`), `src/**/*.cls` (not `/Test/`). Slugs as GitHub makes them (Design Note 8). Header: what it pins, what it reads, the `Included()` rule.
- `ci/units.sh` -- append `readme` to `CHECK_SCRIPTS` (this story's entry only).
- `docker/tests/test-boundaries.sh` -- add `README.md` to the paths-and-keys must-scan list (`:118-119`) and its PASS text, so the most public file can never drop out of CON-5's scan.

**Acceptance Criteria:**
- Given the hosted `checks` job, when `bash ci/checks.sh` runs, then `test-readme.sh` passes on the committed README with one `SKIP #telegram` line, and each of its rules has flagged its broken copy first (FR-58, UX-DR98).
- Given `install.sh`'s pointer and printed commands (the Integration AC; consumer `install.sh`), when the README loses `## Troubleshooting` or one of those commands, or gains `docker compose restart`, then `test-readme.sh` exits 1 naming the rule (DW-134, DW-2).
- Given the page's README links (the Integration AC; consumers the no-model-key and allowance banners, About, the guide's finish link, the Telegram card and banner), when an anchor the product can show has no README section, then `test-readme.sh` exits 1 naming it; `#readme` passes while `README.md` exists; `#telegram` is skipped only while `Included()` has its test-only body, and is covered as soon as that body changes (FR-21, FR-58, UX-DR56).
- Given `test-boundaries.sh`, when it scans, then `README.md` is in its must-scan list for paths and keys, and the README holds neither.
- Given the README walkthrough of Task 0, when its results are recorded, then each command the README adds that no live unit runs (`docker compose ps`, `--force-recreate`, the after-start log, the password change) worked as the README says on a real stack.
- Given the README, when the lead's review reads it, then every product sentence appears in the Claims list with its release-1 source, and DW-2, DW-3, DW-45 and DW-134 are each met where the matrix says.

## Spec Change Log

## Review Triage Log

### 2026-10-28 — Review pass
- verdicts: 35 findings — high 0, medium 7, low 23, false 5, maybe-false 0
- findings (Blind Hunter 1 to 8, Edge Case Hunter 9 to 22, Verification Gap 23 to 30, Intent Alignment 31 to 35):
  - `[false]` `[reject]` 1. The start path names no branch or tag and the web bundle is gitignored — the release sequence (REL-3, Story 11.5) commits the built bundle on the candidate branch and merges it to `main`, whose clone the README shows; the rehearsal clones the candidate and runs `install.sh` (epics.md Story 11.5), so a clone of the released default branch builds.
  - `[low]` `[patch]` 2. The Troubleshooting intro promises more than it covers — the intro now says "usual causes and fixes", an entry for "Docker is not installed" is added; the part about unpinned headlines is row 15's.
  - `[low]` `[reject]` 3. Facts pinned as literals in the check, not read from `install.sh`, the compose file or the installer — beyond the matrix (the spec fixes the strings, `commands` already cross-reads `install.sh`, the compose literal is pinned by `test-ci-config.sh`); reopen_if a build bump leaves the README stale.
  - `[medium]` `[defer]` 4. The LAN warning names the default IRIS accounts and gives steps only for the README account — the wording is the author's DW-3 decision, which the spec fixes; recorded in `deferred:` (security posture, for the owner).
  - `[low]` `[patch]` 5. The password command has no escaping rule and no failure path — one sentence added (a double quotation mark is written twice; any output but `1` means unchanged), labelled inference.
  - `[low]` `[patch]` 6. First-start figures partly unsourced — the notes row now names the runner's 4 vCPU; the 78 s reading is Task 0's, in this spec (C68).
  - `[low]` `[reject]` 7. "What you need" omits RAM, disk, the EAP account and a wipe path — each would be a new claim the spec does not list (and RAM and disk are unmeasured for the judges' machines); the README already says not to add `-v`.
  - `[low]` `[reject]` 8. OcuTalon's own licence is not stated — the spec's Design Note 4 leaves it unsaid (the owner's call); named in the report to the owner.
  - `[false]` `[reject]` 9. Same as 1 (clone of the default branch) — refuted as 1.
  - `[medium]` `[defer]` 10. Same as 4 (default accounts' passwords) — grouped with 4.
  - `[medium]` `[patch]` 11. `docker compose exec` cannot read the start log of a container that has stopped — the "stopped" and "not ready" entries are split; the stopped one gives only `docker compose logs iris`.
  - `[low]` `[patch]` 12. Several `install.sh` messages have no entry — grouped with 2: the intro no longer claims coverage and the likeliest missing one is added.
  - `[low]` `[patch]` 13. The log "ends with RESULT OK" but its last line is `AFTER-START end` — the README says a line that begins with `RESULT OK`.
  - `[low]` `[patch]` 14. Same as 5 (password quoting and failure) — grouped with 5.
  - `[low]` `[reject]` 15. `install-pointer` pins only the heading, not the quoted message headlines — a reverse check would need ellipsis handling for the "Docker Compose ... is too old" headline and is beyond the matrix; reopen_if a reworded `die` message leaves the README stale.
  - `[low]` `[reject]` 16. `commands` pins only the `docker compose` commands after `run:`, not `sudo`, `docker load` or `docker tag` — the spec's DW-134 row names exactly those commands.
  - `[low]` `[patch]` 17. The "install.sh again" guard misses the backticked form — the pattern now allows a backtick, with a self-test; the message names the rule.
  - `[low]` `[reject]` 18. The demo-mode on and off answers are not compared with `SettingsOps.cls` — beyond the matrix (it names the kept sentence only); `SettingsOps`' own tests pin the product text; reopen_if the messages are reworded.
  - `[low]` `[reject]` 19. The anchor inventory reads only literal forms — the spec lists exactly these forms, and the check fails closed when `readme` or `telegram` is not found.
  - `[low]` `[patch]` 20. "78 seconds" and "4 CPUs" are not in the notes file — grouped with 6.
  - `[false]` `[reject]` 21. "Checks and tests run in CI on pushes and pull requests" — `ci.yml` runs on pushes to the listed branches and on every pull request; the nuance (branch list, skipped groups) does not make the sentence untrue.
  - `[low]` `[patch]` 22. The notes paragraph still says the lead fills the row — the sentence now says it was read at Story 10.2's plan.
  - `[medium]` `[patch]` 23. The contest-table self-tests never empty the feature cell or cut a row short — two broken copies added; both mutations demonstrated red.
  - `[medium]` `[patch]` 24. `teaser` (once, embed tags) and `top` (first line) have branches no broken copy reaches — a second teaser line, three embed tags and a wrong first line added; each mutation demonstrated red.
  - `[medium]` `[patch]` 25. `no-telegram` has no copy for the case where `Included()` has changed — a silent-case check added; the mutation demonstrated red.
  - `[medium]` `[patch]` 26. AC 5 has no pinning test and the README's terminal and password commands are pinned nowhere — a rule `admin-commands` pins the two sessions and the password line (AC 5's mutation line now names it); AC 6 is the lead's review, no test applies.
  - `[low]` `[reject]` 27. Install facts are literals — same as 3.
  - `[low]` `[patch]` 28. Two self-tests depend on the exact wording of `chat-view.ts` and `EXPERIENCE.md` — they now change a value whatever it says.
  - `[low]` `[reject]` 29. ShellCheck is not in `ci.yml`'s job for `test-readme.sh` — `.github/workflows/**` is outside this story's footprint, and the spec names ShellCheck a dev-tool loop command.
  - `[low]` `[patch]` 30. "4 CPUs" has no source — same as 6 and 20.
  - `[false]` `[reject]` 31. Against the real tree `product-links` resolves no heading beyond the README existing — the intent says `#readme` passes while `README.md` exists and `#telegram` is skipped while `Included()` is test-only (Design Note 1); the self-tests exercise the other paths.
  - `[false]` `[reject]` 32. Product claims have no code-level check — AC 6 is the lead's review of the Claims list, and the check pins what text can be pinned.
  - `[low]` `[reject]` 33. Troubleshooting headlines are not compared with `install.sh` — same as 15.
  - `[low]` `[reject]` 34. Several facts are checked anywhere in the file, not in their section — the spec's matrix scopes only the Sign in, Install and Try it facts; reopen_if a fact is dropped from its section while it appears elsewhere.
  - `[low]` `[patch]` 35. Three "Never" items have no rule — "find a bug" and "bonus" are now refused (self-tests added); another entry's name cannot be pinned (it is unknown to the check) and a bug-report link is refused by the host allow-list.

## Design Notes

**Governing ADs and conventions:**
- **AD-23:** the retag to `ocutalon-iris-base:2026.3.0AI.154.0`, Health preferred, the non-Health image by the same name, every-interface publishing with the README's LAN warning (DW-3), the README account `ocutalon`/`ocutalon` with no forced change, the 15-minute wait, and the first-start figure recorded in `epic-0-readme-notes.md` for the README.
- **AD-19:** keys only in `.env` (copied from `.env.example`); demo mode switched by `SetDemoMode`, which needs OcuTalonAdmin or `%All` (U-72); the web endpoints stay OcuTalonAdmin only.
- **AD-24:** the README account holds OcuTalonUser, OcuTalonAdmin and OcuTalonTraceViewer, so trace links open after the local sign-in popover.
- **AD-5:** state on the named volume; `down` without `-v`, `--force-recreate` and `--build` keep it.
- **AD-3:** OCUORDERS and its databases exist only with demo mode on.
- **AD-22:** checks in the hosted job; the README tells nobody to push, pull or cache the image.
- **AD-29, AD-33:** Lane B owns the README except its Telegram section, which Story 12.7 (Lane A) adds.
- **Convention "README link":** one address, `README_URL`; a section link puts the anchor in place of `#readme`.

**Decided in-stage:**
1. **The page's links stay `#readme`.** Story 2.10 decided that "How to set a key" and "Install it yourself" open `README_URL` and that this story's check covers that address (its Design Note 8). Moving them to section anchors needs `web/src/app/banners/**`, which is contended. `#readme` is the README itself on the repository page, so the check passes it while `README.md` exists.
2. **The Telegram switch is read statically.** The check normalizes the whitespace of `Included()`'s body and skips `#telegram`, and allows no `Telegram` word, only while the body equals the test-only form (`test-boundaries.sh` already pins that the global is read nowhere else). Any other body, or no `In.cls`, covers `#telegram` and lifts the word rule, so Story 12.7's change needs no edit of the check, only its README section.
3. **Two ways to fail closed.** The check fails if its link inventory no longer finds both `readme` and `telegram` (a renamed constant would otherwise hide every link), and if two headings share a slug.
4. **The README's sections and their content:**
   - **What OcuTalon does:** the attention decision with the four outcomes and the page's meanings; chat on a live page; Break the feed, the incident with its cause in plain English and a fix that waits for Approve or Reject in the chat or on the page's simulated phone; watching a production; reminders; with no key, fixed rules.
   - **Install it yourself:** `### What you need`: Docker Desktop (macOS, or Windows with a WSL 2 shell) or Docker Engine with the Compose plugin (Linux), Compose 2.24 or later, git, an arm64 or x64 CPU. macOS and Linux are what CI and the author test; WSL is the Windows path, and the README says plainly that CI does not test it.
     - `### Get the image`: IRIS for Health AI Hub Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`) from the InterSystems Early Access Program portal, `https://evaluation.intersystems.com/Eval/early-access/AIHub`, as the file ending in `docker.tar.gz` for this CPU: arm64 for Apple silicon and ARM Linux, x64 for Intel or AMD. `docker version --format '{{.Server.Arch}}'` tells which. Then `docker load -i <the archive file>`.
     - `### Start it with the install script`: `git clone`, `cd OcuTalon`, `./install.sh`, what it prints.
     - `### Start it by hand`: `docker tag <the name docker load printed> ocutalon-iris-base:2026.3.0AI.154.0` (the archive prints `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`, measured on the author's machine and printed in InterSystems' public template), optionally `cp .env.example .env`, `docker compose up -d`.
     - `### The IRIS (non-Health) image`: supported, because it differs only by the HealthShare libraries and HSCUSTOM; verified on ARM64; CI tests only IRIS for Health. By hand: `docker tag <its .../iris-community:2026.3.0AI.154.0 name> ocutalon-iris-base:2026.3.0AI.154.0`, then the same `docker compose up -d` (the same image ID that install.sh's build argument names; 10.1 Design Note 1).
     - `### Check that it is ready`: `docker compose ps` shows healthy (Task 0's text), then `http://localhost:52773/ocutalon/`; the figures of Note 5.
   - **Set a model key:** Anthropic, `ANTHROPIC_API_KEY=<your key>` in `.env`, copied from `.env.example` and ignored by git; a key from `https://console.anthropic.com`; default model Claude Haiku 5.5; with no key OcuTalon starts, every decision uses fixed rules and the page says so; after adding it, `docker compose up -d --force-recreate`, which is what the page's "restart OcuTalon" means.
   - **Sign in:** `http://localhost:52773/ocutalon/`, `ocutalon`/`ocutalon`, no forced change. DW-3: the web port is published on every network interface, so the IRIS Management Portal is reachable from your LAN until the default and README-account passwords are changed; change the README account's password after your first sign-in (a link to the admin subsection). The user name stays `ocutalon`. Visual Trace: a trace link opens the Management Portal in a new tab; the first time, the page shows "Sign in to Visual Trace", and the portal may ask you to sign in with the same account, which holds the trace role.
   - **Stop, start and update:** `docker compose down` and `docker compose up -d` keep the data on the volume; update: `git pull`, then `docker compose up -d --build`.
   - **Troubleshooting:** each entry names the symptom in `install.sh`'s words and the fix: no image or the wrong CPU; Docker not running; Compose missing or older than 2.24; "Docker Compose could not start OcuTalon" (most often the port is taken: set `OCUTALON_WEB_PORT` in `.env`, then `docker compose up -d`); "stopped before it was ready" or "not ready after 15 minutes" (`docker compose logs iris`, `docker compose exec iris cat /durable/ocutalon-after-start.log`, which has one line per install step; a slow machine can take longer, so check `docker compose ps` again); the page's no-model-key notice (link to Set a model key); a refused sign-in.
   - **For admins and developers:** `### Demo mode` (on for the Docker install; `docker compose exec iris iris session IRIS -U OCUTALON`, then the SetDemoMode line, then `halt`; the OS login is accepted because it holds `%All`; the on and off answers; demo mode off removes OCUORDERS, and when OCUORDERS holds something OcuTalon did not create it is kept and the answer quotes the DW-45 sentence, with `{what was kept}` named as what OcuTalon found). `### Change the README account's password` (`docker compose exec iris iris session IRIS -U %SYS`, then `kill p set p("Password")="<new password>" write ##class(Security.Users).Modify("ocutalon",.p)`, which prints 1, then `halt`; the measured form of `install-upgrade` row 15). `### Repository layout` (`src/ocutalon`, `src/bridge`, `web`, `docker`, `ci`, `eval`). `### Tests and CI` (`bash ci/checks.sh`; CI runs on every push).
   - **Credits and licences:** "Built with the BMAD Method and Claude Code." with links; the not-affiliated note; the notices of Code Map's licence row. No project licence is claimed (none exists; the owner's call).
5. **First-start figures.** About 1 minute on an Apple silicon Mac (53 s, Story 0.8, 2026-10-20) and about 3 minutes on an x64 Linux machine with 4 CPUs (160 s at Epic 0's merge head, read at this plan from run 39545049306); the script waits up to 15 minutes. Story 11.3 measures the release's own figure later.
6. **The password change lives in the admin section** because its command names a class. `## Sign in` says plainly to change it and links there. "How to change them" is the password: the README account's user name is fixed.
7. **No tagline.** The About dialog carries it, and a README tagline would need the note in the same block. The note sits in Credits, so `OpenClaw` appears only there.
8. **Slugs:** in the C locale, lower-case, drop every character but letters, digits, spaces, `-` and `_`, then spaces to `-`. "Contest task → where to see it" is `contest-task--where-to-see-it`. Headings use ASCII except that arrow. (inference: GitHub's rendering is observed only once the repository is public; Story 31.3's README pass sees it.)
9. **External hosts allowed** (every `http(s)://` in the file, links and code alike): `localhost`, `demo.ocutalon.com`, `youtu.be`, `github.com/jbrandtmse/OcuTalon`, `github.com/bmad-code-org`, `claude.com`, `console.anthropic.com`, `docs.anthropic.com`, `evaluation.intersystems.com`, `docs.intersystems.com`, `www.intersystems.com`, `docs.docker.com`, `learn.microsoft.com`. Community, Open Exchange and other entrants' hosts are left out, so no link reaches another entry. Names in prose are the author's review.
10. **The word cap** reads "about 120 words at most" as at most 120 whitespace-separated words of the section's body.
11. **Owner point 3** (no risky action without a yes) goes in What's interesting; point 1 beside the demo link; point 2 in What's interesting.
12. **A walkthrough, not a live CI unit.** Adding `--force-recreate` to `live:install-script-live` would add a restart to `image`, which ran at 1.15 times the six-job mean (DW-127's run), and push it past Story 32.3's 1.25 rule (inference: about 1.28). The other README commands already run in live units: `./install.sh`, the manual tag and plain `up` (`install-script-live`), the OCUTALON terminal and SetDemoMode (`demo-switch`), the password `Modify` (`install-upgrade` row 15).
13. **Implement-stage decisions (small, all in the README or the check).**
    - **The rules.** The check has 17 rules: the matrix's 16 plus `outcomes`, which reads the four meanings out of `web/src/app/chat/chat-view.ts` (the page's own strings) and requires them in the README, so the README cannot drift from the page. `top` also requires the eight other H2 sections to be present (not in a fixed order, so Story 12.7's `## Telegram` and Story 31.3's sections need no edit of the check).
    - **Self-tests and the real file.** Each rule's broken copies are derived from the real input by an awk edit, and a copy whose edit changed nothing counts as not flagged. The rule runs the real input first: a real fault is reported as itself (naming the missing section, command or anchor), and the broken-copy failure is reported only when the real input passes. The `Included()` self-tests use fixture classes, so they stay valid once Story 12.7 changes the real body.
    - **Architecture command.** The README tells which CPU Docker runs with `docker info --format '{{.Architecture}}'` (`aarch64` for arm64, `x86_64` for x64; measured as `engine=aarch64` here and `engine=x86_64` in Epic 0's notes), not `docker version --format '{{.Server.Arch}}'` as Design Note 4 had it, because `.Server.Arch` is a dotted name that the `dev-only` rule would refuse above the admin section.
    - **The after-start log.** Task 0 found it holds the whole start's output, with 21 `STEP` lines, then `RESULT OK 0.1.0`, not "one line per install step". The README says the lines that begin with `STEP` name each install step and a good start ends with `RESULT OK`.
    - **First-start figure.** Task 0 measured 78 s on the Apple silicon Mac (this stack also runs the CI mock), against Story 0.8's 53 s, so the README says "53 and 78 seconds in two measurements" for Apple silicon and "about 3 minutes (160 seconds)" for x64, not "about 1 minute". Story 11.3 replaces both.
    - **Kept sentence.** Where `SettingsOps` puts it, the answer is "Demo mode is off. " + the sentence + " Reload the OcuTalon page in a minute to see the change."; the README quotes the sentence alone, as a block quote, after saying the answer starts with "Demo mode is off.".
    - **No project-licence sentence.** The credits name only third-party notices. Saying that no project licence exists is the owner's call (Design Note 4), so the README says nothing either way.
    - **`*_ANCHOR` constants** are read from TypeScript files only: `OCUTALON_RESET_ANCHOR` in `Install/Step/Public.cls` is the online demo's reset anchor time, not a README anchor.
    - **Mutations run on a copy.** Every Rule 19 mutation edited a scratch copy of the tree (a `git init` of the tracked and new files), never the working tree, so `git status --short` and `git diff --stat` never changed.
    - **Matrix audit additions (the lead, after the handoff).** Three matrix rows had no covering test in the handoff's check, and the lead added them to `test-readme.sh`: the word cap at its edge (the section padded to exactly 121 words is flagged, to exactly 120 it is not), the two other places a page anchor is written (a `readmeSection(..., '<x>')` literal and a `jbrandtmse/OcuTalon#<x>` literal, each named when it has no heading), and "No README" (each of the 17 rules, run as if `README.md` were absent, must print a FAIL line that says so; a silent `FAIL no-readme` line names a rule that does not).
    - **Review-pass patches (the lead).** Troubleshooting: the intro no longer says every failure prints one of the listed messages; the "stopped" and "not ready" entries are split, because `docker compose exec` cannot read the start log of a container that has stopped (the stopped entry gives only `docker compose logs iris`); the log is described as holding a line that begins with `RESULT OK` (its last line is `AFTER-START end`); an entry for "Docker is not installed" is added (install.sh's message and fix). The password steps say that a double quotation mark in the new password is written twice and that any output other than `1` means the password was not changed (inference: ObjectScript string literals and the `%Status` return, not run through `Modify`). `epic-0-readme-notes.md`: the README-figure row names the runner's 4 vCPU (Rule 21) and the paragraph no longer says the lead fills the row. `test-readme.sh`: the self-tests that were missing are added (Verification), the self-tests that depended on the exact wording of the page and of EXPERIENCE.md now change a value whatever it says, `install.sh` followed by a backtick and "again" is refused, "find a bug" and "bonus" are refused, and a rule `admin-commands` (18 rules) pins the two terminal sessions and the password line as Task 0 ran them.
    - **Task 0 is not run again.** The walkthrough ran once, in the implement pass, before the review patches; none of them changes a command it measured (the `docker compose exec ... cat` command is now only in the entry for a container that is still running).
    - **Links added.** The README links Docker Desktop, Docker Engine, the Compose install page and WSL 2 on hosts of the allow-list; the other external links are the portal, the console, the BMAD Method, Claude Code and the teaser. Each answered HTTP 200 on 2026-10-28 (`console.anthropic.com` redirects to `platform.claude.com`); the repository itself answered 404 (see `deferred`).

**Rule 3:** the deliverable is text and a CLI check. `test-readme.sh` runs for real on the committed README in CI with exit-code assertions, the README's commands run in the live units of Note 12, and Task 0 covers the rest once.

**Integration ACs:** `test-readme.sh` is a check other stories' links must satisfy; its first consumers are in this story (the Integration ACs above).
- **Consumed-by:**
  - Story 12.7: adds the `#telegram` section and changes `Included()`, after which the check covers the link and allows the word.
  - Story 31.3: the 1.0.0 README (read-only account, IPM section) keeps every rule green.
  - Story 11.3: replaces Note 5's figures with its measurement.
  - Story 11.4: its checklist reads the README's note.
  - Later README-link stories (for example 36.2): the link rule covers them.
- **Consumes:** `install.sh` and its live unit (Story 10.1); `README_URL`, `TELEGRAM_ANCHOR`, `readmeSection` (Stories 2.1, 2.8, 2.10); `Included()` (Story 2.8); `SetDemoMode` (Story 4.1, U-72); the Demo step's kept sentence (Story 0.12); `lib-scan.sh` and `lib-live.sh`.

**Extend, don't copy:** `test-readme.sh` sources `lib-scan.sh` and uses `scan_rule` for its line rules (providers, private words, OpenClaw lines, class names). Its structural rules (sections, words, links) have no sibling, and follow the broken-copy-first discipline of `test-boundaries.sh`. Paths and keys stay `test-boundaries.sh`'s rule, which now names README.md, so they are not checked twice.

**Veto window (public text):** the README is new public text (category 5). The AC's "author's review" is that pass; the implement stage lists the README under its contract for the owner's veto, and the lead relays it.

**Declined:** none. DW-2, DW-3, DW-45 and DW-134 are addressed by the matrix rows and tasks that name them.

## Verification

Lane C variables for Task 0 and any throwaway: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c"`, `OCUTALON_TEST_WEB_PORT=52803`, `OCUTALON_LOCK_OWNER='epic=10 stage=implement'`, `OCUTALON_RUN_TAG=e10s2iw`. No IRIS class changes, so slot C is not touched.

**Commands:**
- (loop) `bash docker/tests/test-readme.sh` -- expected: every rule PASS, one `SKIP #telegram`, exit 0.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: exit 0; the scope line names README.md.
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: exit 0 (units: `test-readme.sh` is in `CHECK_SCRIPTS`).
- (loop) `uvx --from shellcheck-py==0.9.0.6 shellcheck docker/tests/test-readme.sh` -- expected: no findings (dev tool, as Story 10.1).
- (once) Task 0: `bash readme-walkthrough.sh` from the implement stage's scratchpad folder, run from the worktree root with the lane variables, `timeout: 600000`, then `ci/iris.sh teardown` with the same variables -- expected: every step as Task 0 says, teardown leaves nothing of the tag.
- (once) `bash ci/checks.sh` -- expected: `checks: all scripts passed`.

Shared surfaces: `CHECK_SCRIPTS` in `ci/units.sh` (test-ci-config.sh's units rule); `test-boundaries.sh`'s must-scan list and its scope line; the README-figure row of `epic-0-readme-notes.md` (no test reads it). Every test added or changed passes on a fresh environment, in either order.

Mutations (Rule 19; the implement stage writes one line per AC): for example, delete `## Troubleshooting` from README.md → `install-pointer` red; add `docker compose restart` → `commands` red; change `TELEGRAM_ANCHOR`'s value in a copy → `product-links` red; set `Included()`'s body to `Quit 1` in a copy → `product-links` red for `#telegram`; drop README.md from the must-scan list → `test-boundaries.sh` scope red.

**Results (implement stage, 2026-10-28).**
- `bash docker/tests/test-readme.sh`: 18 PASS lines (one per rule, `admin-commands` added in the review pass) and `SKIP #telegram: Included() has its test-only body, ...`, exit 0, under macOS bash 3.2 with BSD tools and under Ubuntu 24.04 (bash 5.2, mawk 1.3.4, GNU grep 3.11) in a throwaway container with the tracked tree copied in. 4 s.
- `bash docker/tests/test-boundaries.sh`: exit 0; the scope line ends "every tracked or new file is scanned for paths and keys, README.md among them".
- `bash docker/tests/test-ci-config.sh`: exit 0 (30 PASS lines; `units` PASS with `readme` in CHECK_SCRIPTS).
- `uvx --from shellcheck-py==0.9.0.6 shellcheck docker/tests/test-readme.sh`: no findings.
- `bash ci/checks.sh`: `checks: all scripts passed` (14 scripts, 2 min 29 s; `readme` 4 s).

**Task 0 (the README walkthrough), lane C, tag `e10s2iw`, port 52803, Apple silicon, Docker engine aarch64, Compose 5.5.0.** One throwaway stack (project `ocutalon-t10w-e10s2iw-...`, the judges' compose file plus lib-live's decoy-key and port overrides and the CI mock service), `live_first_start 400`, then the steps below, all PASS:
- First start: `FIRST-START engine=aarch64 build=12s ready=78s`, no `WARN` line.
- `docker compose ps` once healthy: `iris` service STATUS `Up About a minute (healthy)` (State running, Health healthy); after the recreate `Up 12 seconds (healthy)`.
- `docker compose logs iris` printed 2488 lines.
- `cat /durable/ocutalon-after-start.log`: the whole start's output (IPM and class-load chatter) with 21 `STEP` lines (merge, readiness, ipm, ipm-map, public-classes, package, Bridge.Installer, Public, Roles, Users, Web, SSL, Tasks, Demo, Provider, Audit, Telegram, Production, Reconcile, PrivateData, Ready), then `RESULT OK 0.1.0` and `AFTER-START end ... ready 0.1.0`. This differs from Design Note 4's "one line per install step": the README text follows the measurement (Decided in-stage 13).
- `docker compose up -d --force-recreate`: a new container ID, the volume's `CreatedAt` unchanged (2026-10-28T17:28:39Z), healthy again, and `ocutalon`/`ocutalon` still reached `<app-root`.
- The README's password command in `%SYS` (form `kill p set p("Password")=... write ##class(Security.Users).Modify("ocutalon",.p)`, the random password from an environment variable, never printed) printed `1`; the sign-in POST with the new password reached `<app-root` and with the old password did not (the run's negative control); the literal-quotes form with `"ocutalon"` printed `1` and `ocutalon`/`ocutalon` reached `<app-root` again.
- `ci/iris.sh teardown` with tag `e10s2iw`: 0 projects removed, 0 leftover containers, volumes, networks and images; the lane lock released (the folder was empty after); the root `.env` untouched; no slot, `ocupilot*` or other lane's resource used.

**Mutations (Rule 19), each applied to a scratch copy of the tree, never the working tree.**
- AC 1: mutation: in `test-readme.sh`, the `install-pointer` checker changed to accept any README (`grep -qxF -- "## $name"` to `grep -q ""`) -> `FAIL install-pointer: a broken copy was not flagged`, naming the two broken copies it no longer flags (the removed heading and the other section name); `test-ci-config.sh` with `readme` removed from `CHECK_SCRIPTS` -> `FAIL units` ("test-readme.sh is in 0 of CHECK_SCRIPTS, WEB_SCRIPTS and the groups, wanted 1").
- AC 2: mutation: `## Troubleshooting` deleted from README.md -> `FAIL install-pointer` ("install.sh points to the section 'Troubleshooting', and the README has no '## Troubleshooting' heading") and `FAIL top`; `Or run docker compose restart.` added -> `FAIL commands` with the README line number.
- AC 3: mutation: `TELEGRAM_ANCHOR`'s value in `web/src/app/rail/rail-view.ts` changed to `telegram-setup` -> `FAIL product-links` (no `#telegram` in the inventory, and the page links to `#telegram-setup` with no heading); `Included()`'s body in `In.cls` changed to `Quit 1` -> `FAIL product-links` ("the page links to '#telegram', and the README has no heading with that slug"), no `SKIP` line, and `no-telegram` passes (the word is allowed).
- AC 4: mutation: `README.md` added to `.gitignore` -> `test-boundaries.sh` `FAIL scope` ("not scanned for paths and keys: README.md"); the same with the `README.md` entry also removed from the must-scan list -> exit 0 (so the list entry is what pins it); a key-shaped string appended to README.md -> `FAIL keys` at README.md:246; a home-folder path appended -> `FAIL paths` at README.md:246.
- Review-pass additions (each mutation applied to `docker/tests/test-readme.sh` or `README.md` itself, backed up in the stage's scratchpad folder and restored byte-identical, `git status --short` and the files' SHA-256 unchanged): mutation: `chk_table`'s cell loop started at the third cell (`i = 2` to `i = 4`) -> `FAIL contest-table: a broken copy was not flagged` ("an empty feature cell"), and `bad = (NF < 5)` made `bad = 0` -> the same FAIL ("without its closing bar"); `chk_teaser`'s once test `-ne 1` made `-lt 1` -> `FAIL teaser` ("the teaser line twice"), and the embed pattern cut to `!\[` -> `FAIL teaser` ("an image tag", "a frame", "a video tag"); `chk_top`'s first-line test made `if (0)` -> `FAIL top` ("a first line that is not the title"); `chk_no_telegram` made to flag whatever `Included()` holds -> `FAIL no-telegram` ("the word is flagged although Included() no longer has its test-only body"); `chk_outcomes`' meaning test replaced by `false` -> `FAIL outcomes`; `chk_demo_mode`'s kept-sentence comparison replaced by `false` -> `FAIL demo-mode` ("the kept sentence changed in EXPERIENCE.md"); `install\.sh` followed by a backtick made `install\.sh` alone -> `FAIL commands` ("install.sh in backticks again"); `find a bug|bonus` removed from `public_text_scan` -> `FAIL public-text` ("a bug-hunt section", "a bonus section"); `admin-commands`: its facts emptied -> `FAIL admin-commands` (three facts "not flagged"), and in README.md `Modify("ocutalon",.p)` made `Modify("ocutalon",p)`, or `-U %SYS` made `-U SYS` -> `FAIL admin-commands`; README.md's first line made `# OcuTalon Two` -> `FAIL top`; the sentence ``Run `./install.sh` again`` added to README.md -> `FAIL commands`.
- AC 5: no automated test pins the walkthrough (it is a recorded measurement); its negative control is inside the run: after the password change the old password no longer reached `<app-root`. What a hermetic check can pin of it is pinned by the `admin-commands` rule (the review-pass line above): the two terminal sessions and the password line as Task 0 ran them.
- AC 6: the lead's review of the Claims list below; no mutation applies.
- Matrix rows, each by a one-line edit of README.md in a scratch copy, all exit 1 naming the rule: `top` (a stray line; two sections swapped), `try-it` (./install.sh before the demo link; "splash" removed), `interesting` (121 words; "audit log" removed), `contest-table` (Usability row removed), `teaser` (changed), `install` ("2.24" removed), `key-account` (empty key line), `lan` ("LAN" removed), `demo-mode` (kept sentence changed; SetDemoMode line changed), `dev-only` (a class name above the admin section), `public-text` (a provider; OpenClaw elsewhere; an IPv4 address), `no-telegram` (the word), `readme-links` (a dead anchor; a duplicate heading; an off-list host), `install-pointer` (the section renamed).
- Matrix audit additions (the lead; each applied to `docker/tests/test-readme.sh` itself, backed up in the stage's scratchpad folder and restored byte-identical, `git status --short` unchanged): mutation: `chk_interesting`'s limit changed from 120 to 121 -> `FAIL interesting: a broken copy was not flagged` ("exactly 121 words: not flagged"), and from 120 to 119 -> the same FAIL ("exactly 120 words is flagged"); the `readmeSection` line of `inventory()` deleted -> `FAIL product-links: a broken copy was not flagged` ("a readmeSection literal with no heading is not named"), and the address line deleted -> `FAIL product-links` (no `#readme` in the inventory); `rule_begin`'s missing-README test made never true (`-ne 1` to `-lt 0`) -> 17 `FAIL no-readme` lines, one per rule.

**Claims** (one line per product sentence of the README; "Sn.m" is Story n.m of epics.md, and every source ships in release 1, the online demo from Epics 16 and 29).
Try it in two minutes
- C1 "Start with the online demo, at https://demo.ocutalon.com (nothing to install, and no Early Access image needed)." -- Epic 16 goal (a visitor opens the online demo with no install and no key); S10.2 AC 1; REL-10. The address answered HTTP 200 on 2026-10-28.
- C2 "Its sign-in details are on the splash screen." -- Epic 16 (FR-59, UX-DR24 to UX-DR27: the splash's published details); S10.2 AC 1.
- C3 Step 1, load the build 154 image into Docker -- S10.2 AC 2; S10.1 (the script's checks); NFR-22.
- C4 Step 2, run `./install.sh` in the OcuTalon folder -- S10.1 (done).
- C5 Step 3, sign in at the local address with `ocutalon` and `ocutalon` -- AD-23 (the README account, no forced change); install.sh's ready block; the compose file's default port; Task 0.
- C6 Step 4, follow the demo guide at the top of the page -- S4.4 (the guide above the chat); S10.2 AC 1.
What's interesting
- C7 "OcuTalon runs as an IRIS Interoperability production, so the agent is an Interoperability workflow, and its work shows in Visual Trace, ..." -- PRD section 1 (the assistant is itself a production); S0.6 (every item is a production item); S1.5 (every model request and tool call is an agent step in Visual Trace).
- C8 "For each item that arrives, an IRIS AI Hub agent makes one attention decision, with its reasons and cost." -- S1.3; S1.4; FR-1, FR-2.
- C9 "Nothing risky runs without your yes: you get a dry run with counts first, you approve in the web chat, and every answer lands in the IRIS audit log." -- S7.1 (a dry run that changes nothing, with its count); S3.6 (a risky call waits); S6.2 (approve or reject from the web chat); S3.7 (the audit log).
- C10 "It was built this way so that you can audit and debug your assistant in the same place as the rest of your integrations." -- PRD section 1 (difference 2).
Contest task table
- C11 "OcuTalon is an Interoperability production: every item and every decision is a production message you can follow in Visual Trace." -- PRD section 1; S0.6; S1.5; S2.9.
- C12 "Break the feed also sends 50 orders through a second production, Orders, which OcuTalon watches." -- S4.3; S5.1; S0.10.
- C13 "Online demo: the trace link under a reply opens Visual Trace." -- S2.9; S2.13.
- C14 "Each item gets one attention decision from an AI Hub agent running Claude Haiku 5.5, with its reasons, confidence, tokens and cost." -- S1.1; S1.3; S1.4; S2.6.
- C15 "Every model request and tool call is an agent step in Visual Trace." -- S1.5.
- C16 "Online demo: 'Decision details' under a reply." -- S2.6 (the strip's "Decision details").
- C17 "The attention decision: Ignore, Digest, Tell now or Act." -- S1.3; S2.5 (the outcome chips).
- C18 "Anything risky waits for your approval, and content that did not come from you can only look, notify and save." -- S3.4; S3.6; S3.3.
- C19 "A recorded evaluation set scores the decisions." -- Epic 9 goal; S9.1 to S9.3; `eval/orders-date-format` exists.
- C20 "Online demo: the outcome on each reply and the Recent decisions list." -- S2.6; S2.8.
- C21 "An agent inside a production, a cause worked out from the failed messages, and a repair and resend fixed to exact targets that runs only after an approval." -- S5.4 (the diagnosis from the failed messages); S7.1 (fixed targets); S7.3 (approved repairs are re-checked and resent); S3.4.
- C22 "The first answer to an approval request wins." -- S3.5.
- C23 "Online demo: steps 3 to 5 of the demo guide." -- S4.4 (the steps Watch, Reminder, Break the feed, Approve, Open the trace).
- C24 "This README, one install script, a plain `docker compose up -d`, and the online demo's splash screen and demo guide." -- PRD section 8.1 (Clarity of Instructions); S10.1; S10.2; Epic 16; S4.4.
- C25 "One script finds the image, starts OcuTalon and says where to sign in, with the exact fix when a check fails." -- S10.1 (install.sh).
- C26 "Checks and tests run in CI on pushes and pull requests." -- S0.7 (`.github/workflows/ci.yml` triggers: push on the main branches, every pull request).
- C27 "Ask OcuTalon in plain words to watch a production." -- S5.1.
- C28 "It picks up new failures, groups the ones with one cause into an incident, and never gives a false all-clear." -- S5.2; S5.3; S5.7.
- C29 "Reminders fire on time and survive restarts." -- S8.3; S8.5.
- C30 "Online demo: step 1 of the demo guide, which watches the Orders production." -- S4.4 (step 1's prompt); S5.1 (the online demo watches only Orders).
- C31 "A local install can watch any production its service user may read." -- S5.1 (matches by display name across namespaces the service user may read).
- C32 "A two-minute demo guide with one-click prompts." -- S4.4 ("About 2 minutes"; Send for the two prompts).
- C33 "Causes are in plain English." -- S5.4; S5.8; NFR-24.
- C34 "You answer Approve or Reject in the chat or on the page's Simulated phone." -- S6.2; S6.3.
- C35 "Online demo: the demo guide and Break the feed." -- S4.4.
- C36 The teaser line -- the author's link (this spec's contract; Story 10.2 AC, FR-58); the video answered HTTP 200 on 2026-10-28.
What OcuTalon does
- C37 "OcuTalon is a personal assistant that runs inside InterSystems IRIS." -- PRD section 1.
- C38 "For every item that reaches it, OcuTalon makes one attention decision. The decision has one of four outcomes." -- S1.3.
- C39 Ignore "Recorded; nobody notified." -- `chat-view.ts` meaningIgnore (S2.6); the `outcomes` rule compares it.
- C40 Digest "Saved for later; nobody notified now." -- meaningDigest, same.
- C41 Tell now "Needs you now." -- meaningTellNow, same.
- C42 Act "OcuTalon took or requested an action." -- meaningAct, same.
- C43 "Each decision shows its reasons, its confidence and its cost." -- S2.6.
- C44 "You talk to OcuTalon in a web page that updates as things happen." -- Epic 2 goal; S2.2; S2.5.
- C45 "A reply shows its decision and a link that opens it in Visual Trace." -- S2.6; S2.9.
- C46 "In demo mode the page has a Break the feed button." -- S4.4.
- C47 "It makes a simulated partner send 50 orders in a changed date format into the Orders production, where they fail for real." -- S4.3.
- C48 "OcuTalon groups the failures into one incident, explains the cause in plain English and proposes a fix with a dry run: how many orders it would resend, with an example." -- S5.3; S5.4; S7.1 (the dry run's count and example).
- C49 "Nothing is resent until you press Approve in the chat or on the page's Simulated phone." -- S7.2; S6.2; S6.3.
- C50 "Reject leaves everything as it was." -- S6.4; S4.7 ("Rejected. Nothing was changed.").
- C51 "After an approval, OcuTalon reports how many orders went through." -- S7.4.
- C52 Watching a production, with the prompt "Watch the Orders production and only tell me if something needs me." and "Stop watching Orders." -- S5.1; S4.4 (the prompt's exact text).
- C53 Reminders: "Remind me in 1 minute to stretch.", on time, survive a restart, listed and cancelled in the chat -- S4.4 (the prompt); S8.3; S8.4; S8.5; S8.6.
- C54 "Without a model key, OcuTalon starts and every decision uses fixed rules. The page says so." -- S1.6; S2.10.
Install it yourself
- C55 What you need: Docker Desktop or Docker Engine with the Compose plugin, Compose 2.24 or later, git, an arm64 or x64 CPU -- S10.1 (install.sh's Compose check); S10.2 DW-2; NFR-22.
- C56 "macOS and Linux are what OcuTalon's author and its automated tests use. On Windows, work in a WSL 2 shell; the automated tests do not cover that." -- S10.2 Design Note 4 (NFR-22); ci.yml (ubuntu-24.04 and macos-15 jobs).
- C57 The build 154 image, `irishealth-community:2026.3.0AI.154.0`, from the Early Access Program portal, the `docker.tar.gz` file for the CPU -- S10.2 AC 2; AD-23; the portal address answered HTTP 200 on 2026-10-28.
- C58 `docker info --format '{{.Architecture}}'` prints `aarch64` for arm64 and `x86_64` for x64 -- measured (`engine=aarch64` in Task 0; `engine=x86_64` in Epic 0's notes).
- C59 `docker load -i <the archive file>` -- S10.1 (install.sh's own fix text).
- C60 What `./install.sh` does (checks, the name, `.env`, `docker compose up -d`, a progress line every 10 s, 15 minutes, prints the address, a failed check changes nothing) -- S10.1 (install.sh header and flow).
- C61 The ready block it prints -- install.sh (the ready block); `<time>` stands for its elapsed time.
- C62 By hand: `docker tag <the name docker load printed> ocutalon-iris-base:2026.3.0AI.154.0`, `cp .env.example .env`, `docker compose up -d` -- S10.1; `test-install-script-live.sh` ("the README's manual command"); AD-23.
- C63 The name the Health archive loads under, `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0` -- measured with `docker image ls` on the author's machine and again on 2026-10-28.
- C64 "The `cp` step is optional: without `.env`, OcuTalon starts with no model key." -- the compose file's `env_file` with `required: false`; S1.6.
- C65 The plain IRIS image, `iris-community:2026.3.0AI.154.0`: supported, verified on ARM64, differs only by the HealthShare libraries and HSCUSTOM, CI tests only IRIS for Health -- S10.2 AC 2 (NFR-21, P15 wording).
- C66 "`./install.sh` uses the plain IRIS image when no IRIS for Health image for your CPU is loaded." -- install.sh (its image choice).
- C67 `docker compose ps` is ready when STATUS ends in `(healthy)`, for example `Up About a minute (healthy)` -- Task 0 (measured).
- C68 "The first start took 53 and 78 seconds in two measurements on an Apple silicon Mac, and about 3 minutes (160 seconds) on an x64 Linux machine with 4 CPUs." -- Story 0.8's 53 s and Task 0's 78 s; `epic-0-readme-notes.md` (the README's figure, 160 s).
- C69 "The install script waits up to 15 minutes." -- install.sh (`OCUTALON_INSTALL_WAIT` 900 s).
Set a model key
- C70 "OcuTalon uses Anthropic's Claude models. The default model is Claude Haiku 5.5." -- S1.1.
- C71 Create a key at the console; copy `.env.example` to `.env`; git ignores `.env`; set `ANTHROPIC_API_KEY=<your key>` -- AD-19; `.env.example`; `.gitignore`; install.sh (it creates `.env`).
- C72 "Apply it: `docker compose up -d --force-recreate`. This is what the page means by 'restart OcuTalon'." -- DW-134; install.sh; S2.10 (the banner's text).
- C73 "Without a key, OcuTalon still starts. Every decision uses fixed rules, and the page shows a notice that says so." -- S1.6; S2.10.
Sign in
- C74 The README account `ocutalon`/`ocutalon`, and no password change is asked at the first sign-in -- AD-23; S0.3; the sign-in page text (EXPERIENCE.md).
- C75 The LAN paragraph (the web port on every network interface; the Management Portal reachable until the default and README-account passwords are changed; change the README account's password after the first sign-in) -- DW-3; the compose file's `ports` entry.
- C76 Visual Trace: a trace link opens the Management Portal in a new tab; "Sign in to Visual Trace"; the portal may ask for the same account, which holds the trace role -- S2.13; AD-24; EXPERIENCE.md (the sign-in popover).
Stop, start and update
- C77 `docker compose down` keeps the data on a volume, `-v` deletes it; `docker compose up -d` starts again; `git pull` then `docker compose up -d --build` updates and keeps the data and the changed password -- AD-5; DW-134; install.sh ("To apply an update"); `test-install-upgrade.sh` row 15 (an upgrade leaves the changed password).
Troubleshooting
- C77a "These are the usual causes and fixes. Most entries are messages that `./install.sh` prints when a check or the start fails; the last two are about the page." -- install.sh (its `die` messages; the closing "Troubleshooting section of README.md lists the usual causes and fixes").
- C78a "Docker is not installed (the docker command was not found)" -> install Docker Desktop (macOS, or Windows with WSL 2) or Docker Engine (Linux), then run `./install.sh` -- install.sh (that message and fix).
- C78 "No IRIS build 154 image is loaded in Docker" -> download, load, run `./install.sh` -- install.sh (that message and fix).
- C79 "...for another CPU than this machine's" and the existing-name case -> load the right archive; `docker tag` -- install.sh (those two messages and fixes).
- C80 "Docker is installed, but it is not running, or this user cannot reach it" -> start Docker; `sudo systemctl start docker`; `sudo usermod -aG docker $USER` and log in again -- install.sh (that message and fix).
- C81 "Docker Compose is missing" / "...is too old" -> install the plugin, 2.24 or later; version 1 does not work -- install.sh; DW-2.
- C82 "Docker Compose could not start OcuTalon" -> the port 52773 is most often taken; `OCUTALON_WEB_PORT=<port>` in `.env`, `docker compose up -d`; `docker compose logs iris` -- install.sh; `.env.example`; the compose file's port variable; Design Note 4.
- C83 "OcuTalon stopped before it was ready" -> `docker compose logs iris`; "OcuTalon was not ready after 15 min 0 s" -> logs, the after-start log (lines that begin with `STEP`, a line that begins with `RESULT OK`), `docker compose ps` again -- install.sh (those two messages and fixes); Task 0 (the log's contents).
- C84 The no-model-key notice -> Set a model key -- S2.10.
- C85 A refused sign-in -> the account, or the new password; how to set one -- AD-23; Task 0 (the password command).
For admins and developers
- C86 "Demo mode is on for the Docker install. It adds the demo guide, the Simulated phone and mailbox, and Break the feed, and it runs the Orders production in the namespace OCUORDERS." -- S4.1; Epic 4 goal; AD-3.
- C87 The terminal session in OCUTALON, the `SetDemoMode(<0 or 1>)` line, the OcuTalonAdmin role or `%All`, the OS login holding `%All` -- S4.1 (U-72); `Admin.cls`; `test-demo-switch.sh` (logs in as irisowner).
- C88 The on and off answers, verbatim -- `SettingsOps.cls` (MESSAGEON, MESSAGEOFF).
- C89 The kept-OCUORDERS case and its sentence, word for word -- DW-45; EXPERIENCE.md (the owner forms table); `SettingsOps.cls` (MESSAGEKEPT); the `demo-mode` rule compares it.
- C90 "A change takes up to a minute to show on the page." -- S4.1 (the 60-second Setting cache).
- C91 Change the README account's password: the `%SYS` session and the `Modify` line print 1; the user name stays -- Task 0 (measured); `test-install-upgrade.sh` row 15. "If it prints anything else, the password was not changed" and "write a double quotation mark twice" -- (inference: the `%Status` that `Modify` returns, and the ObjectScript string-literal rule; not run through `Modify`).
- C92 The repository layout (`src/ocutalon`, `src/bridge`, `web`, `docker`, `ci`, `eval`) -- the folders exist; their contents as the Code Map lists.
- C93 `bash ci/checks.sh` runs the checks that need no container, the README check among them; the workflow runs them on pushes and pull requests with the web build, the browser tests and the IRIS tests -- `ci/checks.sh`; `ci/units.sh`; `.github/workflows/ci.yml`.
Credits and licences
- C94 "Built with the BMAD Method and Claude Code." with links -- S10.2 AC (CON-2); both links answered HTTP 200 on 2026-10-28.
- C95 The not-affiliated note -- word for word from CON-2 and EXPERIENCE.md.
- C96 The third-party notices (fonts under the SIL Open Font License, Lucide under ISC, the web build's `3rdpartylicenses.txt`, IPM under MIT) -- `web/public/assets/licenses/`; `web/angular.json` (`extractLicenses`); `docker/ipm/LICENSE`.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented change.** The release-1 `README.md` (top order, online demo first, the 101-word "What's interesting", the contest table with the teaser as the last line of its section, and the nine other sections), the hermetic check `docker/tests/test-readme.sh` (18 rules, each self-tested on broken copies first, plus a fail-closed pass for a missing README), its place in the hosted `checks` job, `README.md` in `test-boundaries.sh`'s must-scan list, and the README-figure row of `epic-0-readme-notes.md`. Task 0 ran once on lane C (tag `e10s2iw`) and is recorded under `## Verification`; it changed the README in four places (Decided in-stage 13).

**Files changed.**
- `README.md` (new) -- the public README.
- `docker/tests/test-readme.sh` (new, mode 100755) -- the check; sources `lib-scan.sh`'s `scan_files` and `scan_rule`.
- `ci/units.sh` -- `readme` appended to `CHECK_SCRIPTS`.
- `docker/tests/test-boundaries.sh` -- `README.md` in the paths-and-keys must-scan list and its PASS text.
- `_bmad-output/implementation-artifacts/epic-0-readme-notes.md` -- the README-figure row (160 s, x64, run 39545049306) and the paragraph that named the lead as its author.
- This spec.

**Review.** Four layers, 35 findings (medium 7, low 23, false 5). Patches applied: 13 entries from 17 findings (medium 5: the stopped-container log command, the contest-table, teaser and top, and no-telegram self-tests, and the pin for the README's terminal and password commands; low 8). Deferred: 1 entry from 2 findings (the LAN warning's missing steps for the default accounts, medium). Rejected: 16 findings (5 false, 11 low), each with its reason in the Review Triage Log.

**Follow-up review recommended: true.** Five medium entries were patched. The unverified risk: the patches (nine added self-tests, the `admin-commands` rule, and the README's Troubleshooting and password text) have not been seen by an independent reviewer after the fact; each self-test was shown to bite by a named mutation, and the two password sentences are labelled inference (not run through `Modify`).

**Verification performed.** `bash docker/tests/test-readme.sh` (18 PASS, one `SKIP #telegram`, exit 0; also under macOS bash 3.2 and under Ubuntu 24.04 with mawk and GNU grep, using a stand-in for `git ls-files`), `bash docker/tests/test-boundaries.sh` (exit 0), `bash docker/tests/test-ci-config.sh` (exit 0), ShellCheck 0.9.0.6 on the new script (no findings), and `bash ci/checks.sh` once, after the last patch: `checks: all scripts passed` (2 min 31 s). Task 0 is recorded above; the matrix audit found three rows without a covering test (the word cap's edge, the other two anchor forms, no README), which the lead added; the mutation runs left `git status --short` and the files' SHA-256 unchanged.

**Residual risks.** The repository answers HTTP 404 until the owner makes it public (see `deferred:`), and GitHub's heading slugs are first seen on the public page (Design Note 8). The README is new public text for the owner's veto window. The claims about the online demo (Epics 16 and 29) and the evaluation set (Epic 9) are written for release 1, as the spec says, while those epics are not yet merged.
