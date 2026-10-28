---
title: 'The README gets a judge from download to sign-in'
type: 'feature'
created: '2026-10-28'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-10-context.md']
warnings: ['oversized']
deferred: []
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

Claims (the implement stage fills): one line per product sentence of the README, with its release-1 source (epic goal or story AC).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned on 2026-10-28 from `b154dd979402ba770a7be916f47d49b940c3a56a` (branch OCT-epic10) and halted after planning, as the dispatch asked. Facts measured or read at this plan: Epic 0's x64 first start (160 s, run 39545049306, `b6459b8`); the EAP portal address (InterSystems' public ai-hub-dev-template README, fetched 2026-10-28); the name the Health archive loads under (`docker image ls` on the author's machine, read only). The ledger inbox (DW-2, DW-3, DW-45, DW-134) is addressed in full, with nothing declined. Slot C was checked with `iris_server_info` (build 154U, ARM64) and read once (`Security.Users`, not used because a slot is not a fresh install). Nothing was started, changed or committed.
