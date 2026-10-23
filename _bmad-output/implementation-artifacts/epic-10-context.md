# Epic 10 Context: Install in one command, with a README that gets a judge running

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge with the build 154 image loaded runs one script and gets a running OcuTalon. The script checks the image and the machine, retags the image, starts it, shows progress while it waits, and prints where to sign in. When the image, the CPU architecture, Docker or Compose is wrong, it stops with the exact fix. The release-1 README then tells a judge what to download, how to start, how to sign in and how to set the key, and claims only what the release ships. The epic also builds Lane B's session side of Telegram, switched off until a release includes Telegram, so Lane A's Telegram epic never has to change Lane B's files. Release 1 (Epic 11) depends on this epic. Clarity of Instructions and Developer Experience are judged on it.

## Stories

- Story 10.1: One script finds the image, starts OcuTalon and says where to sign in (built now)
- Story 10.2: The README gets a judge from download to sign-in (planned later, on runner B)
- Story 10.3: The session side of Telegram is ready and stays off (planned later, on runner B)

## Requirements & Constraints

**The install script (`install.sh` at the repository root, run from the root)**
- It runs on macOS and Linux, and on Windows under WSL. It must work in the shell that macOS ships (bash 3.2: no associative arrays, which is already the repository's rule).
- **Checks before anything changes.** Docker must be running, Compose v2 must be present, and Compose must be at least 2.24, because the compose file uses the long `env_file` form with `required: false` (DW-2). The script also needs a build 154 image whose CPU architecture matches the machine (arm64 or x64). Any failure stops the script before it retags or starts anything, with a plain message that names the problem and the exact fix: the archive to download for this CPU and its `docker load` command, how to start Docker, or how to install or upgrade Compose.
- **Finding the image.** It looks for repository `irishealth-community` with tag `2026.3.0AI.154.0`, under whatever registry prefix the archive gave it. It prefers that IRIS for Health image. With only the non-Health `iris-community:2026.3.0AI.154.0` loaded, it uses that image through the `IRIS_IMAGE` build argument. Either way, it says which image it used.
- **Retag and `.env`.** It retags to the name the Dockerfile's `FROM` expects. A retag that already exists stays as it is. With no `.env`, it creates one from `.env.example`. It never overwrites an existing `.env` and never prints a value from it. With no key, OcuTalon still starts, and the page shows the no-model-key banner.
- **Starting and waiting.** It runs `docker compose up` in the background. At least every 15 seconds, for up to 15 minutes, it prints the elapsed time and the compose health state. Once the container is healthy, it prints:
  - the page's address, on the host port that compose actually published (`OCUTALON_WEB_PORT` can change it from the default 52773);
  - the README account's user name and password.
- **When it fails.** After 15 minutes, or if the container stops, it exits non-zero. Its plain message gives the exact command to read the logs and points to the README's troubleshooting section. It leaves the container and the volume in place.
- **Safe to run again.** A rerun reuses the same named volume. If OcuTalon is already healthy, it prints the address and sign-in details at once. The script never removes a container, an image or a volume.
- **Never leak or publish.** It never runs `docker compose config` without `--quiet` and never runs `docker inspect` without `--format`, because both print values from `env_file`. It never pushes an image or signs in to a registry.
- **Plain English.** Every message is plain English, with no class names, error codes or stack traces.
- **Without the script.** After a manual load and retag, a plain `docker compose up` must give the same result.

**Tests and CI**
- **Hosted runners.** ShellCheck plus scripted tests with a stub `docker` cover every branch above, on hosted Linux and on hosted macOS with the macOS shell.
- **The IRIS runner.** One job runs the real script in a throwaway compose project until it reports healthy. It then removes the retag, retags with the README's manual command, and checks that a plain `docker compose up` reaches healthy on the same volume.
- **Time and boundaries.** A full CI run takes at most 35 minutes. Fork pull requests never run on the IRIS runner. The AI Hub image never enters a CI cache or artifact. A check fails on any image push or registry sign-in.

**README (10.2)**
- **The top.** It opens with "Try it in two minutes": the online demo link first, with a note that its sign-in details are on the splash screen, then the local path. Next come "What's interesting" (about 120 words at most), the "Contest task → where to see it" table, and the teaser video's link once the author gives it.
- **The install sections** state:
  - the image and build, where to get the image, and which archive to pick for each CPU;
  - the manual load and retag commands, the install script, and the plain `docker compose up` alternative;
  - how to check that OcuTalon is ready;
  - the measured first-start time;
  - the minimum Compose version (2.24);
  - a troubleshooting section, which the script points to.
- **Key and accounts.** It covers the key (`ANTHROPIC_API_KEY` in `.env`), the default model (Claude Haiku 5.5), what happens with no key, the README account and how to change it, and how Visual Trace opens.
- **The non-Health image** is supported, verified on ARM64. CI tests only the IRIS for Health image.
- **The port.** It warns that the web port is open on the LAN until the default and README-account passwords are changed, and tells the judge to change the README account's password after the first sign-in (DW-3, DW-6).
- **Demo mode.** It covers demo mode and `SetDemoMode`. Where it explains demo mode off, it quotes the owner's sentence about a kept OCUORDERS word for word (DW-45). Class names and error codes appear only in the admin and developer sections.
- **The page's README links.** A CI check fails when the page links to a README section that is missing. The Telegram link is left out while `Included()` returns 0.
- **Public text.** It credits the BMAD Method and Claude Code. It carries the not-affiliated note word for word and points to the third-party licence notices. It contains no key, local path, private infrastructure detail or other entrant's name. It names no other model provider and has no Telegram section yet.

**Telegram session side (10.3)**, all on fixtures:
- **Pairing in `SessionOps`.** It pairs and unpairs chats, comparing code hashes only, with one chat per session. Each change is audited with no Telegram identity, and a `pairing` event goes to every session whose state changed.
- **The `Pairing` helpers.** `Pairing.HashCode` (SHA-256, base64url), `RecordChat`, `TakeReplySlot` (at most one reply a minute to an unpaired chat) and `Purge`.
- **The pairing endpoints.** `POST /api/v1/pairing/code` (a 10-minute code; only its hash is stored) and `DELETE /api/v1/pairing`. Both answer 404 while `Included()` returns 0.
- **Routing and records.**
  - `Notify` routes a `pairing` notification to `TelegramOut`.
  - `Delivery` accepts channel `telegram`.
  - `StatusMark` records the pause and the Telegram state.
  - `/state` carries a `TelegramState` block.
- **`AnswersIn` result codes.** A Telegram press gets one of `approved`, `rejected`, `already_answered`, `expired`, `not_paired`, `not_visible`, `not_allowed` or `unknown`.
- **Lane B APIs.** `Allowance.TryConsume` and `Trace.Join` accept channel `telegram`.
- **The mock.** It serves the Bot API methods with `telegram` scenarios and logs the token by its length only.
- **In `web/`.** A pinned QR-code library, the API-client methods, and skipped `telegram-*.spec.ts` files.

## Technical Decisions

- **The image recipe, already built.**
  - `docker/Dockerfile` has `ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0` and `FROM ${IRIS_IMAGE}`.
  - `docker-compose.yml` passes `IRIS_IMAGE: ${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}` and uses `pull_policy: build`, `restart: unless-stopped` and `stop_grace_period: 60s`.
  - It sets `name: ocutalon`, the named volume `durable` mounted at `/durable`, and an optional `.env`.
  - It publishes only `${OCUTALON_WEB_PORT:-52773}:52773`, on every interface (the author's decision).
  - Its health check has a 600 s `start_period`.
  - Open point for the spec: the planning text has the script retag either image to `ocutalon-iris-base`, and the acceptance criterion says the non-Health image goes through `IRIS_IMAGE` (that is how the existing tests run it). The spec decides which, and how a non-Health choice holds for a rerun and for a plain `docker compose up`.
- **The health check, already built.**
  - `docker/healthcheck.sh` opens no IRIS session. It passes only when `iris qlist` shows `^running` and `/durable/ocutalon.ready` equals the image's `/opt/ocutalon/version`.
  - `iris-main --before` deletes the marker at each start.
  - The after-start script always exits 0, so a failed install shows only as not healthy, never as a stopped container.
  - It writes `STEP <name> OK|FAILED` lines and `RESULT OK <version>` to `/durable/ocutalon-after-start.log`, rewritten at each start. That log, beside `docker compose logs`, is where a failure shows.
- **The README account.** The users install step creates user `ocutalon` with password `ocutalon`, non-expiring, with no forced change. The page is the `/ocutalon/` web application.
- **First-start time.** The measured first start is about 1 minute on Apple silicon and 150 to 177 s on the x64 runner. The README quotes the figure from Epic 0's merge head, recorded in `epic-0-readme-notes.md`. Over about 12 minutes is a decision for the author, not a failure.
- **State and secrets.**
  - **Volume:** all state lives on the named volume, and every start replaces only code, so a rerun or a restart never loses data.
  - **`.env`:** model keys and bot tokens come only from `.env`. It is git-ignored and kept out of the build context by the `.dockerignore` allow-list.
  - **`.env.example`:** lists `ANTHROPIC_API_KEY` and `TELEGRAM_BOT_TOKEN` with no values, plus a commented `OCUTALON_WEB_PORT`. The CI-only and online-demo variables never belong in it.
- **The CI recipe.**
  - `ci/units.sh` defines every list:
    - `CHECK_SCRIPTS`: the hosted `checks` job runs `docker/tests/test-<name>.sh`.
    - `WEB_SCRIPTS`.
    - `IRIS_GROUPS` and `group_units`: the six-group `iris` matrix.
  - Every `docker/tests/test-*.sh` belongs to exactly one list, and `test-ci-config.sh` pins `.github/workflows/ci.yml` against the recipe.
  - Hosted jobs today run only on `ubuntu-24.04`. No macOS job and no ShellCheck step exists yet.
  - `ci/changes.sh` runs a group only when one of its inputs changed. No pattern matches a root `install.sh`, so a new unit or input must be declared in `IRIS_INPUT` or in the unit's list.
  - `test-boundaries.sh` enforces the push, sign-in, `config --quiet` and `inspect --format` rules. Its file list doesn't include `install.sh` yet.
- **Throwaways on the shared runner.**
  - Live units run through `docker/tests/lib-live.sh` in projects named `ocutalon-<label>-<tag>-<epoch>-<pid>`, with `compose.throwaway.yml` (no host port, no `env_file`, no restart) and `ci/compose.ci.yml`. The real-script job needs such a project, not the judges' `ocutalon`.
  - The runner hosts hold only the Health base, preloaded as `ocutalon-iris-base:2026.3.0AI.154.0`, and concurrent jobs share it. Teardown must never untag it, so the spec must design the "remove the retag and retag by hand" step without disturbing other jobs.
- **Ownership.** Lane B owns:
  - the install script and the README (except its Telegram section);
  - `docker/` (except `merge.cpf`) and `ci/` (except `ci/mock/scenarios/A/`);
  - `.github/workflows/ci.yml`.

  Epic 10 runs in Lane B's files. Story 10.1 fills runner C's idle window and needs no developer instance: stub `docker` and throwaways only.
- **Telegram (10.3).**
  - A pairing code never appears in a message, log, live event or audit entry; only its hash is stored.
  - Production messages refer to a chat only by `ChatRef`, and the Telegram identity lives only in the `Pairing` row.
  - The web layer may call `Included()` (an exception to the dependency rules).
  - The test-only global `^OcuTalonTest("TelegramIncluded")` is set only by `OcuTalon.Test` classes.

## UX & Interaction Patterns

- **While OcuTalon starts.** A starting local install has no page state. The script's terminal output is the only progress a judge sees, so it must read plainly.
- **Sign-in.** The sign-in page says "Use the IRIS account your install created; the README lists it." The first sign-in forces no password change.
- **The page's README links.** The no-model-key banner's "How to set a key" link and "Install it yourself" must reach existing README sections. The outcome terms are exactly Ignore, Digest, Tell now and Act.
- **Telegram texts.** The pairing replies and notices use the catalog keys from Epic 0 ("unpaired from the page", "other chat paired"). No reply to an unpaired chat reveals a session.

## Cross-Story Dependencies

- **Story 10.1** depends on no other epic. It builds on Epic 0's Dockerfile, compose file, health check, after-start script and CI recipe, as built and amended by Epic 32.
  - It fixes the manual retag command and the troubleshooting anchor, which Story 10.2's README states.
- **Story 10.2** waits for Epic 4 to merge, because it quotes Story 4.1's `SetDemoMode`. The links it checks come from Epic 2: the no-key banner and the rail's Telegram link, gated by `Included()`.
- **Story 10.3** waits for Epic 6 to merge, because it applies Story 6.2's answer rules.
  - It builds the unlink that Story 16.4's `SessionOps.End` reuses.
  - Whichever of 10.3 and Story 16.3 merges second settles the `/state` pairing check.
  - Lane A consumes this work from Epic 12 (Stories 12.1, 12.6, 12.7) and the purge task from Story 30.2. Story 16.9 tests refusals, and Story 25.3 adds `getFile`.
- **Epic 11** (release 1) depends on Epic 10: its clean-machine rehearsal and end-to-end path use the install script and the README.
