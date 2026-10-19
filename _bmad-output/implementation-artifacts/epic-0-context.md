# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. A judge loads and retags the build 154 image, runs `docker compose up`, and gets OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with an empty, branded page behind sign-in. Its real job is to unblock two parallel build lanes. It creates every cross-lane release-1 contract with its final name, type and storage: messages, tables, live-event payloads, the catalog and its renderer, the REST skeleton, the bridge extension points and the cross-lane API signatures. It also stubs every release-1 production item inside lane-owned regions, and sets up CI with the model mock and a demo-path test. Lane A and Lane B can then each start their first story without editing the other's files. It is one runner, time-boxed to three days from the build start (October 21 at the latest), and it ends October 23 at the latest.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts (done)
- Story 0.5: Live events and the REST skeleton
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock
- Story 0.8: The demo-path test signs in and loads the page
- Story 0.9: The message catalog and its one renderer

## Requirements & Constraints

- **Install:** after a load and retag, a plain `docker compose up` gives a working install. The first start creates OCUTALON with Interoperability and its own databases. Later starts reapply the same configuration with no errors and no data loss. In demo mode (the Docker default), the Orders production runs in its own namespace, OCUORDERS.
- **Roles and sign-in:**
  - The install creates the user and admin roles plus the trace role.
  - The README account (`ocutalon`/`ocutalon`) has a non-expiring password and no forced change, and the README says how to change it.
  - No page or API answers without a session, except the login page (with its images) and `/ocutalon/public/status`.
- **Secrets:**
  - Model keys and bot tokens come only from environment variables.
  - `.env` is git-ignored, and `.env.example` lists `ANTHROPIC_API_KEY` and `TELEGRAM_BOT_TOKEN` with no values.
  - No key appears in logs, traces, audit entries or the repository.
- **Image and registry:** the AI Hub image, or any image built on it, is never pushed and never enters a CI cache or artifact. CI fails on any `docker push` or registry sign-in. The judges' compose file has no mock service.
- **Tracked files:** no tracked file holds a local machine path or a key-like string, and a CI check enforces this.
- **CI:**
  - A full run takes at most 30 minutes.
  - IRIS tests run on the dedicated self-hosted runner, and everything else runs on hosted runners.
  - Fork pull requests never reach the IRIS runner.
  - The demo-path browser test runs on every pull request and every push to `main`, and a failure blocks the merge.
  - `main` moves only through a release pull request.
- **Platform:** the same Dockerfile works unchanged on the non-Health build 154 image through the `IRIS_IMAGE` build argument.
- **Epic 0 is done when:**
  - a clean first start builds the image, installs the package and reaches ready, and a second start upgrades in place;
  - the production starts with every release-1 item running as a stub, except `TelegramIn`, `TelegramOut` and `EvalIn`, which stay disabled;
  - every class compiles with its storage block committed;
  - CI runs with the mock and with the boundary, storage, `DEFAULTGLOBAL` and public-text checks;
  - the demo-path test signs in and loads the page;
  - neither lane needs to edit the other's files for its first story.
- **First-start timing:** record the real package's first start on x64, install included, in the epic notes for the README. Raise any first start over about 12 minutes to the author.

## Technical Decisions

### Governing rules (by AD id)

- **AD-2 (one package, separable bridge):**
  - OcuTalon ships one IPM package, `ocutalon`. `src/module.xml` lists the bridge's resources (`src/bridge/`: `OcuTalon.Bridge`, `OcuTalon.BridgeExample`) before everything else (`src/ocutalon/`), plus the Angular app's built bundle (through `FileCopy`).
  - `src/bridge/` also loads alone with `$SYSTEM.OBJ.LoadDir` into a namespace with Interoperability (its messages extend `Ens.Request` and `Ens.Response`), and `OcuTalon.Bridge.Installer` sets it up. In a namespace without Interoperability only `Bridge/Installer.cls` loads, and it refuses, naming the namespace. OcuTalon's installer calls it as its first step.
  - CI fails if any `OcuTalon.Bridge` class references another `OcuTalon` package. CI also fails if any class outside `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Docs`, `.Memory`, `.Mcp`, `.Install` and `.Test` (matched as whole package names) references `%AI` or `EnsLib.AI`.
  - `OwnerRef` is exactly a `SessionRef`, `instance` or `eval`.
- **AD-3 (namespaces and databases):**
  - OCUTALON has code, data, private and public (`OCUTALON_PUBLIC`, public Read) databases.
  - The public database holds only `OcuTalon.Web.Public` (the login page, the status endpoint, the `/ocutalon` dispatch class `Shell` and the generated `SignInAssets`), `OcuTalon.Data.Public` and `^OcuTalonPublic`.
  - Those packages may reference only `%CSP` (including `%CSP.REST`), dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (only inside a compile-time generator) and each other. They keep their own copies of the UX texts they render, and a test compares those copies with the catalog (Story 0.9).
  - The status class overrides `%CSP.REST.AccessCheck`.
  - Global mappings put `OcuTalonP.*` and `OcuTalonBP.*` (written with the dot, so `^OcuTalonPublic` stays in the public database), `^AI.Agent.Session*` and `^IRIS.IF.*` in the private database. Mappings come first: the databases and mappings exist before any class compiles.
  - `OcuTalon.Production` is not autostart on Docker.
  - Only `OcuTalon.Install.*`, `OcuTalon.Bridge.Installer` (to `%SYS`, in its one method, which also registers the audit events) and `Install.Step.Demo` (to OCUORDERS) switch namespace in product code, each in one method with `New $NAMESPACE`. Test classes also switch to `%SYS` for their fixtures; that was accepted (DW-7).
  - On the non-Health image, `Interop=1` only enables Interoperability: there is no Foundation production, and the default web application is `/csp/<ns>`. Nothing may depend on either.
- **AD-5 (durable state):**
  - All state lives on the durable volume, and an install replaces only code.
  - Storage is append-only, and every such class's source carries its compiler-generated `Storage` block. Never edit a storage block by hand.
  - The production class holds structure only. Values go in System Default Settings, bridge tables or `OcuTalon.Data.Setting`.
- **AD-19 (configuration homes):**
  - Model keys and bot tokens are environment-only, read through `@{env:VAR}` or `$SYSTEM.Util.GetEnviron`.
  - Endpoint overrides are `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_EXTRA_CA_FILE` and `OCUTALON_TELEGRAM_API_BASE`. Only the CI override and the online demo set them.
  - The installer marks every value it writes `structural` (rewritten every start) or `seed` (written only when absent).
  - `OcuTalon.Data.Public.Settings` is the only reader and writer of `^OcuTalonPublic`, with no exception (built in 0.2). CI fails if any other class references `^OcuTalonPublic`.
  - `OcuTalon.Data.Setting.Get` serves product values through a 60-second cache (built in 0.4).
- **AD-23 (image and installer):**
  - **Image:** one Dockerfile, `FROM ocutalon-iris-base:2026.3.0AI.154.0`, with the mount directory owned by UID 51773 (or IRIS can't start on a fresh volume). Every compose file sets its own top-level `name:`, and the IRIS service sets `stop_grace_period: 60s`. The judges' compose file publishes only the web port, `${OCUTALON_WEB_PORT:-52773}`, on every host interface (the author's decision). The `CMD` deletes the ready marker with `iris-main --before` and runs the after-start script with `--after`.
  - **The CPF merge** (`docker/merge.cpf`) creates the databases, namespace and mappings and enables `%Service_CallIn`, idempotently. Build 154's `iris-main` applies it only when it is new or changed, so the after-start script re-runs `iris merge` at every start on a fresh temporary copy (an unchanged `*.last_merge` path is skipped), which also repairs a mapping removed by hand.
  - **The after-start script** runs under OS authentication: it deletes the marker, re-runs the merge, clears readiness (when `Data.Public.Settings` exists), installs IPM 0.10.10 into `%SYS` (mapped into OCUTALON only), checks that the public classes resolve to `OCUTALON_PUBLIC` (forcing a load if not), loads the package version-gated (`OCUTALON_DEV=1` reloads every time), runs the registry's steps in their fixed order (see Story 0.2 below) and writes the ready marker atomically. It always exits 0; a failure logs the failing step and writes no marker. It logs one `STEP <name> OK|FAILED` line per step and a final `RESULT OK <version>` to `/durable/ocutalon-after-start.log`, rewritten at each start.
  - **The Audit step** checks OcuTalon's own audit events, which `Bridge.Audit` declares and `Bridge.Installer` registers (AD-17, amended October 19).
  - **The health check** opens no IRIS session. It passes only when `iris qlist | grep -q '\^running'` succeeds and the ready marker equals the image's version. Its `start_period` is at least 10 minutes.
  - **Static web files** go in the durable data directory's `csp/ocutalon-web/` folder (IPM's data-directory variable), never IPM's read-only CSP-directory variable, and not `csp/ocutalon/`, which the non-Health image's `/csp/ocutalon` serves without sign-in (0.5 moves it, DW-5).
  - **Version check:** check the version inside the built image, because a cached build context can bake in stale sources.
  - **Private-data check:** every start ends by confirming that the private globals resolve to the private database.
  - **Step registry:** every step extends `OcuTalon.Install.Step`, and `OcuTalon.Install.Registry` runs AD-23's fixed order; a step class outside the order only declares. Areas declare `Grants()` (`{"role","resource","permission"}`; an empty `resource` declares the role alone), `Reconcile()`, `Tasks()` (`{"name","taskClass","description","task":{...},"settings":{...}}`) and `Purge(daysToKeep)`. Role and task names start with `OcuTalon`. The task step creates each task once and leaves an existing task alone. An IPM install calls `Registry.Run("ipm")`.
- **AD-13 (web applications and sign-in):**
  - `/ocutalon` (dispatched by `OcuTalon.Web.Public.Shell`), `/ocutalon/api` (`OcuTalon.Web.Api`, `/v1`, sharing `/ocutalon`'s CSP session, `SessionScope` strict, no CORS) and the trace applications use password authentication in one sign-in group, `GroupById` `OcuTalon`, never `%ISCMgtPortal`. A third, unauthenticated application, `/ocutalon/public`, serves only `GET /status` from a dispatch class in `OcuTalon.Web.Public` that reads only the public settings. `PermittedClasses` applies to the trace applications only.
  - `OcuTalonUser` holds no database resources directly; the applications grant them as application roles.
  - The login page `OcuTalon.Web.Public.Login` (a `%CSP.Login` subclass from `OCUTALON_PUBLIC`, no Angular) keeps the form contract: fields `IRISUsername`, `IRISPassword` and `IRISLogin`, `InsertHiddenFields`, and `OnPreHTTP` calling the superclass. It loads nothing from an authenticated path, inlines its build-time styles (no `style=` attributes) and sends `default-src 'none'; script-src 'sha256-…'; style-src 'sha256-…'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`.
  - `InvalidLoginAction` stays 0. Upgrades compile in place, never delete-then-load.
  - Every state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, or it gets a 403.
  - The page sends `script-src 'self'`. Local sessions allow at least 8 hours idle.
  - The WebSocket (AD-12, built second) is forwarded by the shell or moved to its own application, as its story decides.
- **AD-24 (roles and trace applications):**
  - The roles are `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`.
  - The trace role holds only: Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`; Read on the data and code databases (never the private ones); SQL `SELECT` on `Ens.MessageHeader`.
  - The trace applications `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` have no application roles and exactly the seven permitted classes: `%CSP.Broker`, `EnsPortal.VisualTrace`, `EnsPortal.SVG.VisualTrace`, `EnsPortal.VisualTraceLegend`, `EnsPortal.SVG.TraceLegend`, `EnsPortal.MessageContents` and `EnsPortal.MessageViewer`. The OCUORDERS application and grants exist only with demo mode on.
  - No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun` or `%Ens_ProductionConfig`.
  - No `OcuTalon.Data` or `OcuTalon.Bridge.Data` class extends a message base.
- **AD-12 (live events):**
  - `Live.Event` holds `Seq` (per stream, allocated under a lock held through the commit), `Stream`, `Ts`, `Type` and `Payload`.
  - Rows are written only through `Live.Publish`, after commit, and only for types in the event table.
  - Each payload is the full public view of one entity, keyed by `Ref`, as a `%JSON.Adaptor` class with a matching TypeScript interface. Payload JSON keys are camelCase: the property name with a lower-case first letter.
  - Trace targets are `TraceHeaderId` and `TraceNamespace`.
  - Polling is the release-1 contract; the WebSocket comes second.
- **Contract semantics fixed in Epic 0:**
  - **`Commands.Submit` (AD-1):** sets `Origin` from the authenticated context, always `tool` while a bridge context is active. Origins are `web_user`, `web_admin`, `telegram`, `tool`, `timer` and `system`.
  - **`Reply.Busy` (AD-6):** set when `Decide` refused a `turn` after a 2-second lock wait. The `Reply` carries no text and no decision (`Reply.NewBusy()`), and busy is never an error status.
  - **`Decision` (AD-20):** unique on (`ItemId`, `Kind`).
  - **Compaction prompt (AD-20):** a constant whose first line starts `OCUTALON-COMPACTION-V1`.
  - **Time conversion (AD-18):** `OcuTalon.Data.Time` is the only converter outside the bridge, and `OcuTalon.Bridge.Time` (Story 1.4) the only one inside it.
  - **Audit (AD-17, amended October 19):**
    - `OcuTalon.Bridge.Audit` is the only audit writer, for the bridge and OcuTalon, with source `OcuTalon` and types `Action`, `Approval`, `Pairing`, `Settings`, `MCP` and `Tool`; the events are `OcuTalon/<T>/<T>`.
    - `Bridge.Audit.Events()` declares them, and `Bridge.Installer` registers them in its one `%SYS` method at every install and start. They are structural: re-enabled each start. The `Audit` step only checks them. OcuTalon never changes instance-wide auditing.
    - Tests poll the audit log with a timeout: rows appear late (53 to 72 s measured).
  - **Extension bases (AD-31):** the bridge wraps every `OnEvent` call and never fails its caller. `Decide` runs `ReplyFilterClass` before recording anything.
  - **Rendering (AD-32):** producers never render text. Only `*Out` operations render, through `Catalog.Render` (implemented in Story 0.9, after the October 19 split for size), which uses `Data.Time`.
- **AD-22 (testing and CI):**
  - `%UnitTest` classes live in `OcuTalon.Test.<Area>`, sharded by area, one compose project per shard.
  - The mock is reached through the Anthropic provider's `base_url` over plain HTTP on the compose network.
  - The mock rejects `temperature`, `top_p`, `top_k` and output caps under 4,000.
  - A request picks its scenario by, in order: a `[[mock:<name>]]` marker, the exact text of a guide prompt contained in the message, then `MOCKKEY`. Never by prompt wording.
  - The mock logs header names and the key's length only. Its only state is a per-test countdown.
  - CI and scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format`, because both print `env_file` values.

### Cross-lane contract obligations (AD-29, AD-33)

- **Contracts before code:** create every release-1 contract with its final names and types: properties, enumerations and storage. Cross-lane APIs are signatures with stub bodies. Only `Commands.Submit` (0.6), `Data.Public.Settings` (0.2), 0.4's shared helpers and `Msg.Catalog.Render` (0.9) are fully implemented. Epic 0 fixes the cross-lane properties and the identity columns; the owning lane appends the rest, which append-only storage allows.
- **Catalog (Story 0.9):** create every release-1 and 0.1.1 key, in `OcuTalon.Msg.Catalog.Core` (Lane B) or `.Watch` (Lane A). The item noun slot is `itemNoun: {"one", "other"}`.
- **One owner each:** after Epic 0, each item, class, table and event type has one owning lane, and only that lane edits it. The other lane asks, and the owner appends. A new item, table or event type is added to the ownership tables in the same change.
- **Lane A owns:** `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, `.Eval` and `eval/`; the installer core (the registry, `docker/merge.cpf`, and the role, user, SSL, task, `Production` and `Public` steps); `ci/mock/scenarios/A/`; `release/`; and `.github/workflows/lane-a.yml`.
- **Lane B owns:** `OcuTalon.Web` (with `.Web.Public`), `.Channel`, `.Core`, `.Schedule`, `.Demo`, `.Live`, `.Msg`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership` and `.Data.Public`; `web/`, the rest of `docker/` and `ci/`, and `.github/workflows/ci.yml`; and the `Web` and `Demo` installer steps.
- **Ownership by area:** `OcuTalon.Test.<Area>`, `OcuTalon.Install.Step.<Area>` and `OcuTalon.Live.Payload.<Type>` follow their area's or publisher's lane.
- **Table owners:**
  - **Lane B:** `Session`, `AddressCounter`, `StatusMark`, `GuideState`, `BreakFeedRun`, `Pairing`, `Turn`, `SimMessage`, `Delivery`, `Reminder`, `Setting` and `Live.Event`.
  - **Lane A:** `BackgroundCheck`, `WatchMark`, `Incident`, `FailureGroup`, `FixRun`, every `Bridge.Data` class and `Digest.Data.Item`.
- **Production class:** one `ProductionDefinition` XData block, with each lane's items between `<!-- lane A: begin -->`/`<!-- lane A: end -->` (the same for lane B). Item classes and lanes follow the spine's production-item ownership table. Every item is enabled except `TelegramIn` and `TelegramOut` (off until a release includes Telegram) and `EvalIn` (only with `OCUTALON_EVAL=1`). Unbuilt items answer "not implemented" instead of failing.
- **`Decide` settings in Lane A's region:** `HostSinkClass` = `OcuTalon.Core.BridgeSink` and `ReplyFilterClass` = `OcuTalon.Checks.ReplyGuard`. `ClassificationClass` keeps the default.
- **HostSink payloads:**
  - `decision.*` and `approval.*` carry the record's public `Ref`.
  - `turn.step` carries `{decisionRef, label}`, with the session as `ownerRef`.
  - `budget.capped` has `ownerRef` `instance` and payload `{day}`.
- **Test-only global:** `^OcuTalonTest("TelegramIncluded")` is set only by `OcuTalon.Test` classes and never exists in the judges' install.

### Naming and storage conventions

- **Classes:** named `OcuTalon.<Area>.<Name>`, one class per file. Cross-lane contracts go in `OcuTalon.Msg`/`OcuTalon.Data`, and bridge contracts in `OcuTalon.Bridge.Msg`/`.Data`. Nothing goes under a system package name. `irislib/` and `irissys/` are read-only references and must never be loaded.
- **Item names:** PascalCase. Services end `In` (`FailurePoller` and `StatusMonitor` are the exceptions), channel operations end `Out`, and the Workflow operation is `OcuTalonApprovals`.
- **Messages:** extend `Ens.Request` or `Ens.Response`, with plain-English properties. Session-owned messages carry `SessionRef`, and items carry `ItemId`. Rules route only on named properties.
- **Enumerations:** defined once in `OcuTalon.Msg.Enum`; `OcuTalon.Bridge.Msg.Enum` copies only the seven the bridge's contracts use (Outcome, Provenance, RequestKind, FallbackReason, ApprovalState, ApprovalKind, Channel), test-pinned equal. Enumeration-typed properties are plain `%String`, with the values only in the enum class, never `VALUELIST` copies.
  - Outcome: `ignore, digest, tellnow, act`
  - Provenance: `user, untrusted`
  - RequestKind: `decide, diagnose, turn, tool`
  - FallbackReason: `no_key, daily_cap, budget, too_large, timeout, rate_limited, error, refusal, cut_off, empty, invalid, unusable`
  - IncidentState: `open, awaiting_approval, fixing, resolved, closed`
  - IncidentOpenVariant: `fallback, no_fix, rejected, expired`
  - ApprovalState: `pending, approved, rejected, expired, cancelled, executing, done, failed`
  - ApprovalKind: `fix, tool_call`
  - NotificationKind: `tellnow, incident, approval, answered, result, reminder, fallback, allowance, pairing, status, digest`
  - CheckResult: `passed, failed, not_checked`
  - Channel: `web, phone, mailbox, telegram, email, webhook, slack, system`
  - Origin: as in AD-1 above.
- **Identifiers:** every `Ref` (and `ItemId`, `SessionRef`, `TraceRef`) is a 22-character base64url string with no padding, from `OcuTalon.Bridge.Ids.NewRef()`. Row ids never leave the server; `Ens` header and session ids may, for trace links.
- **Times:** UTC ISO 8601 to the second, `YYYY-MM-DDThh:mm:ssZ`, in storage and the API, so string order is time order. Rendered only through `OcuTalon.Data.Time`.
- **SQL reserved words:** a spine property name that is an SQL reserved word keeps its name and gets an `SqlFieldName` (`Input` → `InputText`, `Count` → `FailureCount`).
- **REST:**
  - Paths are `/ocutalon/api/v1/...`, with plural nouns and commands as `POST` on a resource.
  - Errors use the shape `{"error": {"code", "message"}}`, in plain English.
  - Unbuilt routes answer 501.
  - The live-event envelope is `{seq, stream, ts, type, payload}`, with camelCase payload keys.
- **Persistent classes:** every one that isn't a message sets `Parameter DEFAULTGLOBAL = ^OcuTalonP.<Short>` (`^OcuTalonBP.<Short>` in the bridge), with its row in the short-name registry `src/short-names.tsv` (one row per class, union-merged). CI fails on a duplicate. The compiler-generated `Storage` block is committed.
- **Hosts and errors:** hosts log with `$$$LOGINFO`, `$$$LOGWARNING` and `$$$LOGERROR`. Code uses `%Status` throughout and `$$$ThrowOnError` inside methods. Plain English appears only at the channel edge. Never read globals directly for settings.
- **Python:** only as `.py` resources under `src/ocutalon/python/`, never `[Language = python]`.
- **Angular:** standalone components and signals, hash routing, one typed API client and one live-event service. Fonts and icons are bundled, never loaded from a CDN, with their licence notices kept.
- **Tests:** `OcuTalon.Test.<Area>.<Subject>`, and Playwright under `web/e2e/` (demo path: `web/e2e/demo-path/`, one spec per UJ-1 step).
- **Source tree:** `src/` (`module.xml`, `short-names.tsv`, `bridge/cls/OcuTalon/{Bridge,BridgeExample}/`, `ocutalon/cls/OcuTalon/...`), `web/`, `eval/`, `docker/` and `ci/` (override, mock, `ci/mock/scenarios/<A|B>/<name>.json`), `docker-compose.yml` (no mocks), `docker-compose.dev.yml` and `.env.example`.

### Stack pins

| Component | Pin |
| --- | --- |
| IRIS for Health AI Hub EA (primary) | `irishealth-community:2026.3.0AI.154.0` |
| IRIS non-Health image (via `IRIS_IMAGE`) | `iris-community:2026.3.0AI.154.0` |
| Retag target | `ocutalon-iris-base:2026.3.0AI.154.0` |
| IPM | 0.10.10, from a release file baked into the image |
| Angular and Angular CDK | 22.2.x |
| Component library | the Angular CDK plus custom components; no component kit |
| Icons | Lucide paths, vendored into `web/` (ISC, with Feather's MIT notice) |
| Fonts | Inter v4.1, Montserrat v7.222 and JetBrains Mono v2.304 woff2 files, vendored into `web/` (OFL-1.1, licence texts kept) |
| TypeScript | ~6.0.3 |
| Node.js (build and CI only) | 24 LTS |
| Playwright | 1.64.x |
| Default model, every agent | `claude-haiku-5-5` |

### Spikes Epic 0 relies on (all done on October 17)

- **S1 (passed):** IPM 0.10.10 installs offline; the package installs and upgrades in place, bridge first, and a failed load rolls back. Its hazards are built into AD-23 (exit 0, read-only CSP directory, mount ownership, committed storage blocks, stale cached builds, `^` in `qlist`). A first start takes about 1 minute on Apple silicon.
- **S3 (passed):** `base_url` (ending `/v1/`) reaches the mock over plain HTTP.
- **S12 (passed):** the same Dockerfile runs on the non-Health image (first start about 20 seconds, web server on).
- **S16 (passed):** the package-mapped public classes dispatch before sign-in with no roles, after install and upgrade; a mapping created after a compile hides them, hence the resolution check. The status class must override `AccessCheck`.
- **S7 (partial):** one sign-in group opens the trace applications with no second sign-in, given AD-24's seven classes and grants.
- **S14:** `^IRIS.IF.*` maps to the private database. **S2:** no sampling parameters, an 8,000-token cap. **S18:** a long `Retry-After` scenario, capped by the retry back-off.
- **S19 (Epic 15):** `src/cpf/ocutalon.cpf` differs from `docker/merge.cpf` only by the `%Service_CallIn` and IPM lines.

## UX & Interaction Patterns

- **Built in Story 0.3:** the sign-in page and the app header. The full logo is at 320px above a card titled "Sign in to OcuTalon". The header shows the mark, the wordmark, the "Demo mode" badge (shown only with demo mode on locally) and the account menu with Sign out. The main page is empty, and Story 2.1 lays it out.
- **Texts the public package keeps its own copies of** (Story 0.9's comparison with the catalog covers them):
  - help line: "Use the IRIS account your install created; the README lists it."
  - wrong credentials: "That user name and password didn't work."
  - missing role: "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it."
- **Token stylesheet:** generated from `DESIGN.md`'s front matter and covering every token group. In the dark theme every `<name>` maps to `<name>-dark`, except the QR block, shadows, `brand-navy-dark` and the splash canvas. No text is under 12px. Icons are hidden from assistive technology. `prefers-reduced-motion` stops all animation. The focus ring is 2px solid `focus` at a 2px offset, with a `surface` halo.
- The sign-in page uses system font stacks, because `default-src 'none'` blocks font loads. The bundled fonts serve the Angular shell.

## Cross-Story Dependencies

- **Delivered so far: Story 0.1 (done).**
  - **Version and marker:** the first `<Version>` of `src/module.xml` is baked into `/opt/ocutalon/version` (the build fails if it is empty); `/durable/ocutalon.ready` holds that version, written atomically (temporary file, then `mv`).
  - **`docker/healthcheck.sh`:** passes only when `iris qlist` shows `^running` and the non-empty version file equals the marker. Its `OCUTALON_VERSION_FILE` and `OCUTALON_READY_MARKER` variables exist only for the hermetic test.
  - **`docker/merge.cpf`:** relative database directories (`/durable/iris/mgr/ocutalon_{code,data,private,public}/` under `ISC_DATA_DIRECTORY=/durable/iris`), kept relative for S19. It maps `^OcuTalonPublic` and the two public packages to the public database.
  - **`docker/Dockerfile`:** puts the merge file, `module.xml`, health check and after-start script under `/opt/ocutalon/`, with `ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf`. **`.dockerignore`** is `*` plus an allow-list: every file a later story copies into the image must be added to it.
  - **`docker-compose.yml`:** `name: ocutalon`, one service `iris` (`pull_policy: build`, `restart: unless-stopped`), `env_file` `.env` with `required: false`, volume `durable:/durable`, `start_period: 600s`.
- **Delivered so far: Story 0.2 (done).**
  - **After-start script:** `docker/after-start.sh` (with `docker/after-start.cos`), logging the `STEP`/`RESULT` lines.
  - **Step order** (`Registry.Order()`, classes `OcuTalon.Install.Step.<Area>`; each story fills its own step without re-ordering):
    1. `Bridge.Installer`: registers the audit events (0.4); 0.5 and 0.6 as needed, then Epic 1.
    2. `Public`: the online-demo flag only; 3.8 adds its values.
    3. `Roles`: built; 0.3 added the declarations.
    4. `Users`: built in 0.3.
    5. `Web`: built in 0.3; 0.5 adds `/ocutalon/public` and moves the bundle folder.
    6. `SSL`: stub; the first story that needs a client SSL configuration.
    7. `Tasks`: built; 1.11 and later areas declare.
    8. `Demo`: stub; 0.6.
    9. `Provider` (Config Store): stub; 1.1.
    10. `Audit`: checks the events, failing with the missing or disabled event's name (0.4); 3.7 (with DW-10) extends it.
    11. `Telegram`: stub; 12.1.
    12. `Production`: a stub that starts nothing; 0.6.
    13. `Reconcile`: built; it calls the areas' declarations.
    14. `PrivateData`: built; it checks 0.4's private classes (`StorageGlobals`).
    15. `Ready` (`Public.Ready`): built.
  - **Structural or seed:** the public settings, roles and audit events are rewritten every start; tasks are created once. The System Default Settings helper comes with Story 1.1.
  - **`OcuTalon.Data.Public.Settings`** (implemented): fixed keys `onlineDemo`, `demoUser`, `demoPassword`, `readonlyUser`, `readonlyPassword`, `resetIntervalHours`, `resetAnchor`, `lastReset`, `lastResetKind`, `proxyAddress`, `connectionCap`, `connectionReserve` and `messageAllowance`, plus `ready`; any other key is refused. Defaults are the `Public` step's job (3.8). Consumers: 0.4's `Setting.Get` and 0.5's `/ocutalon/public/status` (`ready`, `NextReset`).
  - **Package layout:** `src/module.xml` (`ocutalon` 0.1.0) lists `OcuTalon.Bridge.PKG` from `src/bridge/cls`, then `OcuTalon.PKG` from `src/ocutalon/cls`. `docker-compose.dev.yml` is an override with its own project `ocutalon-dev` and volume, setting `OCUTALON_DEV=1`. `docker/ipm/` holds the vendored IPM release file and its `LICENSE`.
  - **Tests:** `%UnitTest` classes under `src/ocutalon/cls/OcuTalon/Test/<Area>/`. Bash tests are `docker/tests/test-*.sh`, each runnable alone and exiting 0 on success; the live ones share `docker/tests/lib-live.sh` (`live_start` gives a throwaway project with no keys, and cleans it up). Test-only path variables follow `healthcheck.sh`'s convention.
- **Delivered so far: Story 0.3 (done).**
  - **Roles and the README account:** the `Roles` step composes the `Users` and `Web` steps' `Grants()`; only `OcuTalonTraceViewer` holds grants directly (AD-24's). The `ocutalon` account holds all three roles, written as seed, so a changed password survives.
  - **The three web applications** (`OcuTalon.Install.Step.Web`): `/ocutalon` (dispatch `Shell`, `ServeFiles` 3, `Path` the bundle folder), `/ocutalon/api` (dispatch `Api`) and `/ocutalon/trace/ocutalon/` (`ServeFiles` 1, AD-24's seven classes). All use `SessionScope` 2, an 8-hour timeout, no `LoginPage`, empty CORS lists and `CSPZENEnabled` 1 (on build 154, 0 stops signed-in requests reaching the dispatch class). The first two share `CookiePath` `/ocutalon/` and `MatchRoles` `%DB_OCUTALON_{CODE,DATA,PRIVATE}`. `Step.Web` also has `BundleCheck` and `GrantTraceSql`.
  - **`Web.TraceApp(namespace, .props)`** returns `/ocutalon/trace/<namespace in lower case>` and its properties. Story 0.6's `Demo` step and Story 4.1 use it.
  - **`OcuTalon.Web.Public.Shell`:** adapts `%ZHSLIB.REST.AngularHandler` without referencing it (HS-only). Without a session it renders `Login` and serves only `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png` and `assets/brand/favicon-32.png`. Signed in, it runs the role check and serves the bundle through `%CSP.StreamServer`; `/csp/broker/` names, class and ZEN URLs answer 404 (the sign-in page without a session).
  - **`Login` and `SignInAssets`:** `SignInAssets.cls` is generated at build time with the sign-in CSS and script, enforced under compile-time hashes. Any `%CSP.Login` error code other than the missing role shows the wrong-credentials text. The sign-in POST has no CSRF token; the wider risk is open as DW-6. Sign out uses `?IRISLogout=end` until Story 2.2.
  - **`OcuTalon.Web.Api`:** a `%CSP.REST` class with an empty `UrlMap`, filled by 0.5.
  - **The `web/` Angular shell:** `npm --prefix web run build` (`tokens.mjs --check`, `brand.mjs`, `ng build`) writes `src/ocutalon/csp/`, git-ignored on development branches and force-added at release by Story 11.5; the Dockerfile refuses an image without it. IPM's `FileCopy` copies it into the durable data directory on every load and never prunes stale hashed files. `tokens.mjs` generates `src/styles/tokens.css` and `SignInAssets.cls` from `DESIGN.md`.
  - **Browser tests:** `web/playwright.config.ts` and `signIn()` in `web/e2e/sign-in/helpers.ts`, which Story 0.8 reuses. `docker/tests/test-sign-in.sh` runs the live sign-in specs (`LIVE_REBUILD_WEB=1`, on 127.0.0.1 at the first free port in 52800–52819 or `OCUTALON_TEST_WEB_PORT`; Node 24.15+ and Playwright's chromium).
- **Delivered so far: Story 0.4 (done).** The contract classes, with their final names, types and storage (properties are in the classes and their test oracles):
  - **`OcuTalon.Msg` (Lane B):** `Item`, `ItemDecision`, `Notification`, `Outbound`, `Tick`, `CommandResult` (`Ens.Response`) and `Enum`; the abstract `Command` (`Origin`, `IdempotencyKey`, `SessionRef`) with the ten verb classes `Command.SetReminder`, `.CancelReminder`, `.ListReminders`, `.Dismiss`, `.StartWatch`, `.StopWatch`, `.SetDemoMode`, `.Pair`, `.Unpair` and `.EndSession`, routed by class (Story 2.3); and `IncidentCommand` (extends `Command`; `Verb` from `Parameter VERBS = "dismiss,closeForReplay,closeQuiet"`, `IncidentRef`). Commands carry no IRIS user: `WatchOps` reads it from the `Session` row. `CatalogKey` and `Slots` are plain strings, so nothing needs a catalog class to compile.
  - **`OcuTalon.Bridge.Msg` (Lane A):** `Request` (SQL `InputText` for `Input`), the abstract `Result` (`Ens.Response`, the verdict and turn totals) with its subclasses `DecisionResponse` and `Reply` (`NewBusy()`), `DecisionPayload` (`%JSON.Adaptor`; `reasons` is a list), `AgentStep` and `Enum`.
  - **`OcuTalon.Data` tables:** Lane B's `Session`, `AddressCounter`, `StatusMark`, `GuideState`, `BreakFeedRun`, `Pairing`, `Turn`, `SimMessage`, `Delivery`, `Reminder` and `Setting`; Lane A's `BackgroundCheck`, `WatchMark`, `Incident` (SQL `FailureCount` for `Count`), `FailureGroup` and `FixRun`.
  - **`OcuTalon.Bridge.Data` tables (Lane A):** `Decision`, `ApprovalRequest`, `Usage`, `Price`, `ConversationLink` and `ModelFamily`.
  - **Shapes later tables and properties follow:** type sizes `Ref`/owner 22, `Utc` 20, local time 19, enumeration words 32, names 128, lines 1000, summaries 80, long text and JSON unlimited; money `%Numeric(SCALE = 6)`, rates `SCALE = 4`, confidence 0 to 1 at `SCALE = 2`; `ItemId` is a `Ref` everywhere. Every `%Boolean` has `InitialExpression = 0`. Every table with `Ref` has `Index RefIndex On Ref [ Unique ]`; indexes are named `<Property>Index`, composites by their joined properties (`ItemIdKindIndex`). Reasons are newline-separated text on messages and rows, and a JSON list only in `DecisionPayload`.
  - **`OcuTalon.Live.Payload.Decision`** (`%RegisteredObject`, `%JSON.Adaptor`; Lane B): the decision event's payload, with `ItemId`, `ItemSummary`, the verdict and totals, `RecordedAt`, `TraceHeaderId` (the `Decision`'s `TraceSessionId`) and `TraceNamespace`. It carries the model id, not a display name. Its TypeScript interface comes in 0.5.
  - **Helpers:**
    - `OcuTalon.Bridge.Ids.NewRef()`.
    - `OcuTalon.Data.Time`: `NowUtc()` (a copy of `Public.Settings.UtcNow`, which AD-3 forces), `ToLocal(utc)`, which accepts only the `Utc` form and gives `""` for anything else, and `Zone()`. `FromLocal` comes in Story 8.3.
    - `OcuTalon.Data.Setting.Get(key, default)` and `Seed(key, value)`: product keys are dotted (`digest.time`); the public keys are delegated uncached to `Public.Settings`; the cache is per process, for 60 s; only an absent or empty value gives the default; `Seed` is the install-time writer. An empty key gets the default from `Get` and an error status from `Seed`.
    - `OcuTalon.Bridge.Audit`: `Events()` (registered by `Bridge.Installer`) and `Write(type, data, description)`. `data` must be a `%DynamicObject` (anything else gets an error status before anything is written); an unregistered event returns the raw `0` of `$SYSTEM.Security.Audit`.
    - `OcuTalon.Data.Delivery.Record(ownerRef, channel, channelMessageId, approvalRef)` and `FindByApproval(approvalRef, channel, ownerRef)`: stubs. `Record` returns an error and `FindByApproval` returns `""`, so no caller mistakes the stub for a recorded delivery. Story 2.7 implements them.
    - `OcuTalon.Channel.Telegram.In`: a stub inbound service (`Parameter ADAPTER = Ens.InboundAdapter`, a do-nothing `OnProcessInput`). `Included()` returns 0 unless `^OcuTalonTest("TelegramIncluded")` is 1.
  - **`src/short-names.tsv`:** columns `short`, `global`, `class` and `lane`, 22 rows. Short names are unique across the whole file. A later persistent class adds its row in the same change. IRIS can't read the repository from a slot, so `Test.Data.Tables` carries the rows as its `Registry` XData, and `test-storage.sh` keeps the file and the classes in step.
  - **Test layout:**
    - `OcuTalon.Test.Contract` (abstract base): each test class holds its contracts as XData, and `AssertContract` compares them with the compiled class dictionary (superclasses in order, the abstract flag, property types and their size, scale, range and `%JSONFIELDNAME` parameters, the `%Boolean` initial 0, SQL names, indexes).
    - Its three oracles are `Test.Msg.Contracts`, `Test.Bridge.Contracts` and `Test.Data.Tables` (with the registry, private resolution and the `Delivery` stubs). A lane that appends to a contract updates its oracle's XData; the counts there (22 rows, 22 tables, 45 persistent classes) are floors. `Test.Contract.Checker` proves each pinned part is caught, and `Test.Contract.Ac` covers the acceptance rows. `Test.Data.Time`, `.Setting` and `.SettingValues` cover the helpers.
    - **`docker/tests/test-storage.sh`** reads files only. Its rules (`registry-duplicate`, `-class`, `-row`, `-param`, `scan`, `prefix`, `storage`, `datalocation`, `locations`) each run first against a bad sample. Today a class is storage-bearing when it reaches `%Persistent`, `Ens.Request` or `Ens.Response`.
    - **`docker/tests/test-audit.sh`** (live, through `lib-live.sh`): the six events exist and are enabled, a `Write` reads back within `OCUTALON_AUDIT_POLL` (120 s by default), and `Step.Audit` fails on a disabled or deleted event until `Bridge.Installer.Run()` restores it.
    - `test-install-start.sh` row 5 loads only `Bridge/Installer.cls` into the plain namespace (see AD-2).
- **Developer slots:** `ocutalon-slot-a` and `-b` run 0.1's `merge.cpf` from their `config/` (adjust a slot's mount, never the merge file), on the base image without the after-start script: code goes in through the IRIS MCP tools, installer steps run explicitly, and IRIS there can't read the repository. The after-start install and destructive tests run only in throwaway compose stacks and CI.
- **0.5:**
  - It fills `Api`'s `UrlMap` (every release-1 route, with unbuilt ones answering 501) and the role check in `OnPreDispatch`, and adds `/ocutalon/public` to the `Web` step.
  - It creates `Live.Event`, `Live.Publish` and every other `Live.Payload.<Type>`, and adds the TypeScript interface for 0.4's `Live.Payload.Decision`. It also decides how `/state` builds incident views from `Incident`, and where the session epoch lives on `Session`.
  - **DW-5:** it moves the bundle from the durable `csp/ocutalon/` folder to `csp/ocutalon-web/`. That changes `src/module.xml`'s `FileCopy` target, `Step.Web`'s `/ocutalon` `Path` and `BundleCheck`, and 0.3's tests (matrix row 14, `test-install-*.sh`). A live test on the non-Health `iris-community:2026.3.0AI.154.0` pins both sides: `/csp/ocutalon/index.html` and `/csp/ocutalon/main-*.js` answer 404 without a session, and the bundle loads from the new folder through `/ocutalon/` after sign-in.
- **0.6:**
  - The items use 0.4's messages. `TelegramIn` reuses `Channel.Telegram.In`, and `Commands.Submit` sends the `Command` subclasses.
  - Its `Demo` step reads demo mode through `Setting.Get` and its seed, and calls `Web.TraceApp("OCUORDERS")` with demo mode on.
  - Its constants (`MOCKKEY`, tool names, compaction prefix) are what 0.7's mock keys on.
  - **DW-13:** `test-storage.sh` treats every persistent root this story's classes extend (`Ens.BusinessProcess`, `Ens.MessageBody`, `Ens.StreamContainer`, besides `%Persistent`, `Ens.Request` and `Ens.Response`) as a storage root. It exempts the message and business-process extents from `DEFAULTGLOBAL`, as AD-3 does, with a bad sample for each.
- **0.7 and CI:**
  - 0.7's checks gate everything above.
  - The CI override extends 0.1's compose file. CI runs `docker/tests/test-*.sh` (the live ones, `test-audit.sh` among them, on the IRIS runner) and the `%UnitTest` shards. It also runs the public-package and `^OcuTalonPublic` checks, and the registry and storage checks: `src/short-names.tsv` and `test-storage.sh`.
  - **DW-11:** the IRIS checks job also runs the load, compile and export round trip over every persistent class. It fails when a class's compiled `Storage` block differs from its committed file (AD-5).
  - From 0.3, CI also runs the web build, `tokens --check`, `node --test` and `test-sign-in.sh`, and the allow-list check covers `Shell`, `Login` and `SignInAssets`.
  - 0.7 also updates `_bmad/custom/skill-rules.md` (IRIS test recipe, shard command, timings) and `_bmad/custom/parallel.yaml` (bootstrap with `web/`'s dependencies, runtime locks).
  - CI must run on `feature/OCT_OcuTalon_MVP` and `OCT-epic*` with no `cancel-in-progress`.
- **0.8:** runs in 0.7's IRIS job. It reuses 0.3's `playwright.config.ts` and `signIn()` and needs 0.5's `/state`.
- **0.9 (last story of Epic 0):**
  - It builds `OcuTalon.Msg.Catalog.Core` and `.Watch` with every release-1 and 0.1.1 key. The keys include those that 0.4's `CatalogKey` and `Slots` name, on `Item`, `ItemDecision`, `Notification` and `Outbound`.
  - It implements `Catalog.Render(key, slots, channel)` on 0.4's `Data.Time`, tested on every key and channel.
  - It adds the test that compares the public package's copies of the sign-in texts (`Login`'s, Story 0.3) with the catalog.
  - It is Lane B's after Epic 0.
  - **DW-12:** Task 0 measures, on a throwaway stack started with a compose-level `TZ`, whether a production job's `Data.Time.ToLocal` and `Zone()` use the container's zone. If they don't, the renderer passes the instance zone explicitly (AD-18).
- **Epic 10 (from 0.1's compose file):** `install.sh` uses `IRIS_IMAGE`. The `env_file` with `required: false` needs Docker Compose 2.24 or later, so Story 10.1's `install.sh` refuses an older Compose and Story 10.2's README states the minimum. Story 10.2's README also carries the LAN-exposure warning, the README account's password change and the IPM licence notice.
- **Later epics:** Epic 1 (Lane A) and Epic 2 (Lane B) both start from Epic 0 and test against its stubs and the mock. Epic 15 derives `src/cpf/ocutalon.cpf` from `docker/merge.cpf` and calls `Registry.Run("ipm")`. Owners of the stubs and hand-offs:
  - Epic 1: `Decide` on 0.4's `Request`, `Reply.NewBusy`, `DecisionResponse`, `Decision`, `Usage`, `Price`, `ModelFamily` and `ConversationLink`; the `lane-a.yml` bridge job (1.3), `Bridge.Time` (1.4), `Digest.Data.Item` (1.12)
  - Epic 2: header, theme, badge and About (2.1); `SessionEvents` and Sign out through the API (2.2); the command verbs' routing (2.3); `Allowance` (2.4); `BridgeSink` and the decision payload (2.6); `Delivery` (2.7); `Trace.Join` (2.9)
  - Epic 3: `Bridge.Approval`; OCUORDERS grants (3.1); the audit shapes, redaction and read-back (3.7, with DW-10: the `Audit` step warns and records a status when instance-wide auditing is off, never changing it); online-demo public keys (3.8)
  - demo-mode switching: Story 4.1
  - Epics 5 to 7: `Incident`, `FailureGroup`, `FixRun`, `BackgroundCheck` and `WatchMark`; `Checks.Render` (Epic 5); `ReplyGuard` (5.7)
  - `Reminder` and `Data.Time.FromLocal`: Story 8.3
  - `Pairing`'s code fields and Telegram's `Included()`: Story 10.3; `Pairing`, `StatusMark` and the Telegram items: Epic 12; the install script, completed: Epic 10
  - the login splash, online-demo timeouts (120 s) and busy state: Stories 16.2, 16.4 and 16.5
