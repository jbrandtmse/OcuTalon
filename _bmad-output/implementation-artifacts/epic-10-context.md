# Epic 10 Context: Install in one command, with a README that gets a judge running

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge with the build 154 image loaded runs one script and gets a running OcuTalon. A release-1 README then takes them from download to sign-in and claims only what release 1 ships. The epic also builds Lane B's session side of Telegram, switched off until a release includes Telegram, so that Lane A's Telegram epic (Epic 12, shipped as 0.1.1) changes only its own files. Release 1 (Epic 11, cut as 0.1.0) depends on this epic. The Clarity of Instructions and Developer Experience criteria are judged largely on what it produces.

## Stories

- Story 10.1: One script finds the image, starts OcuTalon and says where to sign in (done)
- Story 10.2: The README gets a judge from download to sign-in
- Story 10.3: The session side of Telegram is ready and stays off

## Requirements & Constraints

**README (release-1 sections only; the rest of the README arrives with the 1.0.0 kit)**
- **The top, in this order:**
  1. "Try it in two minutes": the online demo link `https://demo.ocutalon.com` first (its sign-in details are on the splash), then the local path: load the image, run `./install.sh`, sign in, follow the demo guide.
  2. "What's interesting", about 120 words at most.
  3. A "Contest task → where to see it" table. It maps the three task parts (an IRIS Interoperability workflow, an IRIS AI Hub agent, a decision-making task) and each judging criterion (Complexity, Clarity of Instructions, Developer Experience, Applicability, Usability) to the feature that meets it and where the online demo or the repository shows it.
  4. The teaser video's link, only once the author gives it. There is no placeholder before then.
- **Outcomes:** name the attention decision and its four outcomes, exactly Ignore, Digest, Tell now and Act.
- **Install sections.** They work on macOS, Linux and Windows under WSL, and state:
  - the image, IRIS for Health AI Hub Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`), where to get it, and which archive to choose for arm64 or x64;
  - the manual load and retag commands, the install script, and the plain `docker compose up` alternative;
  - how to check that OcuTalon is ready, and the measured first-start time;
  - the minimum Docker Compose version, 2.24 (DW-2);
  - a **Troubleshooting** section.

  The plain IRIS (non-Health) build 154 image is supported and verified on ARM64. It differs only by the HealthShare libraries and HSCUSTOM. The README says how to start with it by hand. CI tests only the Health image.
- **Key and account:**
  - the provider and `ANTHROPIC_API_KEY` in `.env`, copied from `.env.example`;
  - the default model, Claude Haiku 5.5;
  - with no key, OcuTalon still starts and every decision uses fixed rules;
  - the README account, user `ocutalon` with password `ocutalon` and no forced change, and how to change its password;
  - how Visual Trace opens on a local install (a sign-in popover; the README account holds the trace role).
- **The commands `install.sh` prints (DW-134).**
  - After adding a key: `docker compose up -d --force-recreate`.
  - To apply an update: `docker compose up -d --build`.
  - Never tell the judge to run `./install.sh` again for either, because a rerun leaves a healthy OcuTalon alone. Never use `docker compose restart`, which does not re-read `.env`.
- **LAN warning (DW-3).** The web port is published on every host interface, so the Management Portal is reachable from the LAN until the default and README-account passwords are changed. Tell the judge plainly to change the README account's password after the first sign-in.
- **Admin and developer sections:**
  - Demo mode is on for the Docker install. An admin switches it with `do ##class(OcuTalon.Core.Admin).SetDemoMode(<0 or 1>)`, which needs the OcuTalon admin role or `%All`.
  - Where the README explains demo mode off, it quotes the kept-OCUORDERS sentence word for word (DW-45).
  - Class names and error codes appear only in these sections.
- **Links.** Every README link the release-1 page can show, such as "How to set a key" and "Install it yourself", must reach an existing section, and a CI check fails when one doesn't. The `#telegram` link is left out of the check while `Included()` returns 0.
- **Public text.** Plain English throughout, and every sentence and table row claims only what ships and links only to what exists. The README:
  - credits the BMAD Method and Claude Code;
  - carries "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation." word for word, and points to the third-party licence notices;
  - contains no key, local path, private infrastructure detail or other entrant's name;
  - names no other model provider and has no Telegram setup yet.

**Telegram session side (all on fixtures; nothing switched on in release 1)**
- **`SessionOps` pairs and unpairs.**
  - It compares hashes only and checks the code's expiry and single use.
  - One chat goes with one session, and a chat has one live pairing.
  - Every outcome is audited, and unknown or used codes link nothing.
  - A `pairing` event goes to every session whose state changed, the old one too when a chat moves.
  - `SessionOps` returns the outcome, and `TelegramIn` (Lane A, later) writes the reply.
  - An unlink the chat didn't start sends a `pairing` `Notification` with the dropped chat's `ChatRef`.
- **DW-200.** `AnswersIn`'s Telegram entry passes `Approval.Answer` an empty sessionRef or the paired session's 22-character Ref, never a `ChatRef` or a chat id. Its tests pin that an unresolvable one answers `not_allowed`. The entry returns the closed result-code set, with the slots each code needs.
- **DW-231.** Fold Story 4.4's `break-feed-api.ts` `press()` and Story 4.7's guide-marker calls into `ApiClient`, so the page has one typed API client. Until then, keep the same envelope interceptor and headers (`Content-Type`, `X-OcuTalon-Request`).
- **Mock.** The CI mock serves the Bot API methods OcuTalon calls, with `match: telegram` scenarios, and logs the token by length only, including inside `/bot<token>/`.

## Technical Decisions

- **Commands (AD-1).**
  - State changes enter as production messages through `OcuTalon.Core.Commands.Submit`. A pairing completes only through `SessionOps`, with origin `telegram`.
  - REST code may write only a pairing code's hash, beside the sign-in session row and the UI markers.
  - The web layer may call `OcuTalon.Channel.Telegram.In.Included()`, and channel services may call `Core.Allowance` and `Core.Trace`, both as named exceptions to the dependency rules.
- **Pairing secrecy (AD-4).**
  - A code never appears in a message, header, log, live event or audit entry. Both lanes hash through `Pairing.HashCode` (SHA-256, base64url), only the hash is stored, and the plaintext appears only in the HTTP response.
  - Production messages carry `SessionRef` and `ChatRef`, never a chat id or display name. The Telegram identity lives only in the `Pairing` row, and the display name reaches only the session's own page.
- **The switch (AD-29, AD-23).**
  - `Included()` returns 0 unless the test-only global `^OcuTalonTest("TelegramIncluded")` is 1, which only `OcuTalon.Test` classes set. The Telegram items stay disabled.
  - Lane A owns, from Epic 12: `OcuTalon.Channel.Telegram`, `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`.
- **Approvals (AD-11).** The `ApprovalRequest` row is the truth. `AnswersIn` resolves the session first: for Telegram, from the press's `ChatRef` through the live `Pairing` row. It then calls `AnswerOps`, which calls `Approval.Answer`, with the IRIS user and `SessionRef` taken from the server side only.
- **Audit (AD-17).** Write only through `OcuTalon.Bridge.Audit.Record`. A `Pairing` entry has `change` and `reason` plus `irisUser`, `sessionRef` and `channel`, and never a chat id or display name.
- **Live and status (AD-12, AD-18).**
  - `Live.Publish` runs after commit, never inside a transaction, and `SessionOps` is the only `pairing` publisher.
  - `telegramPaused` belongs to the closed status catalog.
  - `StatusMark` is written only through `Record` and `RecordTelegram`.
  - `/state`'s `TelegramState` block (`included`, `state` `off`/`on`/`rejected`, `botUserName`, `paired`, `displayName`, `pausedUntil`) is also the source of `Guide.Compute`'s "Telegram is on".
  - The TypeScript payload interfaces are generated by `web/scripts/payloads.mjs`, whose `--check` runs in the build.
- **Routing and text (AD-14, AD-32).**
  - `Notify` sends kind `pairing` with a `ChatRef` to `TelegramOut` alone.
  - A Telegram `Delivery` id is `<ChatRef>:<message_id>`.
  - Producers send catalog keys and slots only. The pairing texts are already in `Catalog.Core`, and only `*Out` operations render, through `Catalog.Render`.
- **Storage (AD-5).** Storage is append-only, with the compiler-generated `Storage` block committed. CI diffs storage against the previous release tag.
- **REST conventions.**
  - Paths are `/ocutalon/api/v1/...`, and errors are `{"error":{"code","message"}}` in plain English.
  - A state change needs JSON, `X-OcuTalon-Request: 1` and a matching `Origin`.
  - The pairing endpoints answer 404 while `Included()` returns 0. The code endpoint answers 409 when the state isn't `on` or a pause is set.
  - Refs are 22-character base64url values from `Ids.NewRef()`. Times are UTC ISO 8601.
- **The web app.**
  - Standalone components and signals, one typed API client, and the Angular CDK plus custom components with no component kit.
  - The QR code is drawn in the browser by a library Story 10.3 pins to an exact version and records as a Stack row. Its licence must be MIT, BSD, Apache-2.0 or ISC.
  - README links use `README_URL` (`https://github.com/jbrandtmse/OcuTalon#readme`, in `web/src/app/links.ts`), with a section's anchor in place of `#readme`. The Telegram section is `#telegram`.
- **Stack in use.** Angular and the Angular CDK 22.2.x, TypeScript ~6.0.3, Node 24 LTS (build and CI only), Playwright 1.64.x, and the mock on `node:24.15.0-slim`, pinned by digest.
- **Secrets and CI (AD-19, AD-22).**
  - Keys and tokens come only from `.env`. `OCUTALON_TELEGRAM_API_BASE` is set only by the CI override and the online demo.
  - The mock exists only in `ci/compose.ci.yml`.
  - CI never runs `docker push`, signs in to a registry, runs `compose config` without `--quiet` or runs `inspect` without `--format`.
  - The AI Hub image never enters a cache or an artifact.
  - The CI budget is 35 minutes.
- **Install facts the README quotes (AD-23).**
  - Either image is retagged to `ocutalon-iris-base:2026.3.0AI.154.0`. The `IRIS_IMAGE` build argument selects the non-Health image.
  - Only `${OCUTALON_WEB_PORT:-52773}` is published, on every interface.
  - The health check allows 10 minutes or more, and the script waits 15.
  - The first start takes about 1 minute on Apple silicon and 150 to 177 s on the x64 runner (`epic-0-readme-notes.md`).
  - All state is on the named volume.
- **Ownership (AD-29, AD-33).** Lane B owns:
  - the README (except its Telegram section) and `install.sh`;
  - `docker/` (except `merge.cpf`) and `ci/` (except `ci/mock/scenarios/A/`);
  - `.github/workflows/ci.yml` and `web/`;
  - `OcuTalon.Core`, `.Web`, `.Live` and `.Msg`;
  - the `Pairing`, `StatusMark` and `Delivery` tables.

  Epic 10 runs on runner C, in Lane B's files.

## UX & Interaction Patterns

- **Sign-in page:** "Use the IRIS account your install created; the README lists it." The first sign-in never forces a password change.
- **No-model-key banner (step 1):** "OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon.", with the "How to set a key" README link. README and Visual Trace links open in a new tab and say so.
- **Telegram in the rail:** a release without Telegram (0.1.0) shows no Telegram section at all. "Telegram not set up" with "How to set it up" (`#telegram`) appears only once Telegram is included.
- **Telegram texts:** plain text with no Markdown or emoji. Groups and channels get no reply, and no reply to an unpaired chat reveals a session, a name or any state.
- **Terms:** exactly Ignore, Digest, Tell now and Act, plus "Break the feed", "Simulated" and "Approval requests".

## Cross-Story Dependencies

- **Story 10.1 is done.** `install.sh` sends failures to "the Troubleshooting section of README.md" and prints the manual `docker tag`, `--force-recreate` and `--build` commands. Story 10.2's README must match them.
- **The story waits are met.** Story 10.2's (Epic 4, for `SetDemoMode`) and Story 10.3's (Epic 6, for Story 6.2's answer rules) are satisfied: Epics 4, 6 and 8 have merged.
- **Story 10.3 and Epic 16.**
  - Story 10.3 builds the `SessionOps` unlink and its `Pairing` audit entry, which Story 16.4's `SessionOps.End` reuses.
  - Epic 16 hasn't merged, so Story 16.3 will check the real `Pairing` row, and Story 10.3 turns nothing on.
  - DW-231's guide half touches `web/src/app/guide/**`, which Epic 16 may also edit. Settle that when Story 10.3 is planned.
- **Downstream.** Epic 11 depends on Epic 10. Epic 12 builds on Story 10.3 and merges only after `v0.1.0` is tagged. Story 12.7 turns on `Included()` and adds the README's `#telegram` section. Story 16.9 tests the Telegram allowance refusal, Story 30.2 adds the purge task, and Story 25.3 adds `getFile`.
