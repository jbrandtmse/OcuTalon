# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. A judge loads and retags the build 154 image, runs `docker compose up`, and gets OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with an empty, branded page behind sign-in. Its real job is to unblock two parallel build lanes. It creates every cross-lane release-1 contract with its final name, type and storage: messages, tables, live-event payloads, the catalog and its renderer, the REST skeleton, the bridge extension points and the cross-lane API signatures. It also stubs every release-1 production item inside lane-owned regions, and sets up CI with the model mock and a demo-path test. Lane A and Lane B can then each start their first story without editing the other's files. It is one runner, time-boxed to three days from the build start (October 21 at the latest), and it ends October 23 at the latest.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts
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
  - `src/bridge/` also loads alone with `$SYSTEM.OBJ.LoadDir`, and `OcuTalon.Bridge.Installer` sets it up. OcuTalon's installer calls it as its first step.
  - CI fails if any `OcuTalon.Bridge` class references another `OcuTalon` package. CI also fails if any class outside `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Docs`, `.Memory`, `.Mcp`, `.Install` and `.Test` (matched as whole package names) references `%AI` or `EnsLib.AI`.
  - `OwnerRef` is exactly a `SessionRef`, `instance` or `eval`.
- **AD-3 (namespaces and databases):**
  - OCUTALON has code, data, private and public (`OCUTALON_PUBLIC`, public Read) databases.
  - The public database holds only `OcuTalon.Web.Public` (the login page, the status endpoint, the `/ocutalon` dispatch class `Shell` and the generated `SignInAssets`), `OcuTalon.Data.Public` and `^OcuTalonPublic`.
  - Those packages may reference only `%CSP` (including `%CSP.REST`), dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (only inside a compile-time generator) and each other. They keep their own copies of the UX texts they render, and a test compares those copies with the catalog (Story 0.9).
  - The status class overrides `%CSP.REST.AccessCheck`.
  - Global mappings put `OcuTalonP.*` and `OcuTalonBP.*` (written with the dot, so `^OcuTalonPublic` stays in the public database), `^AI.Agent.Session*` and `^IRIS.IF.*` in the private database.
  - Mappings come first: the databases and mappings exist before any class compiles.
  - `OcuTalon.Production` is not autostart on Docker.
  - Only `OcuTalon.Install.*`, `OcuTalon.Bridge.Installer` (to `%SYS`) and `Install.Step.Demo` (to OCUORDERS) switch namespace in Epic 0's product code, each in one method with `New $NAMESPACE`. Test classes also switch to `%SYS` for their fixtures; that was accepted (DW-7).
  - On the non-Health image, `Interop=1` only enables Interoperability: there is no Foundation production, and the default web application is `/csp/<ns>`. Nothing may depend on either.
- **AD-5 (durable state):**
  - All state lives on the durable volume, and an install replaces only code.
  - Storage is append-only, and every such class's source carries its compiler-generated `Storage` block. Never edit a storage block by hand.
  - The production class holds structure only. Values go in System Default Settings, bridge tables or `OcuTalon.Data.Setting`.
- **AD-19 (configuration homes):**
  - Model keys and bot tokens are environment-only, read through `@{env:VAR}` or `$SYSTEM.Util.GetEnviron`.
  - Endpoint overrides are `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_EXTRA_CA_FILE` and `OCUTALON_TELEGRAM_API_BASE`. Only the CI override and the online demo set them.
  - The installer marks every value it writes `structural` (rewritten every start) or `seed` (written only when absent).
  - `OcuTalon.Data.Public.Settings` is the only reader and writer of `^OcuTalonPublic`, with no exception. It is fully implemented (Story 0.2): `Get`, `Set` for the fixed keys only, `ClearReady`, `SetReady` and `NextReset`. CI fails if any other class references `^OcuTalonPublic`.
  - `OcuTalon.Data.Setting.Get` serves product values through a 60-second cache.
- **AD-23 (image and installer):**
  - **Image:**
    - One Dockerfile is built `FROM ocutalon-iris-base:2026.3.0AI.154.0`.
    - Every compose file sets its own top-level `name:`, and the IRIS service sets `stop_grace_period: 60s`.
    - The mount directory is owned by UID 51773; without that, IRIS can't start on a fresh volume.
    - The judges' compose file publishes only the web port, `${OCUTALON_WEB_PORT:-52773}`, on every host interface, with no superserver port. This is the author's decision; the README warns that the portal is reachable from the LAN until the default passwords are changed.
    - The image's `CMD` deletes the ready marker with `iris-main --before`, before IRIS starts, so no health probe of a start sees the previous start's marker. It runs the after-start script with `--after`.
  - **The CPF merge** (`docker/merge.cpf`) creates the databases, namespace and mappings and enables `%Service_CallIn`, idempotently, at every start. On build 154, `iris-main` applies `ISC_CPF_MERGE_FILE` only at the first start and whenever the file changes, after IRIS is up, and `iris merge` skips a path whose `*.last_merge` record is unchanged. So the after-start script re-runs `iris merge` at every start, before its install steps, on a fresh temporary copy of the image's merge file. That also repairs a mapping removed by hand.
  - **The after-start script** runs under OS authentication, in this order:
    1. delete the ready marker again;
    2. re-run `iris merge` on the fresh copy;
    3. clear readiness through `Data.Public.Settings`, when that class exists;
    4. install IPM 0.10.10 into `%SYS`, mapped into OCUTALON only, and load the package, version-gated (`OCUTALON_DEV=1` reloads it every time). Before the gate, check that the public classes resolve to `OCUTALON_PUBLIC` and force a load if not;
    5. run the installer steps in the registry's fixed order (see Story 0.2 under Cross-Story Dependencies). It ends with `Production`, `Reconcile`, the private-data check and `Public`'s `SetReady`;
    6. write the ready marker, atomically.

    The script always exits 0. A failure logs the failing step and writes no marker. It logs one `STEP <name> OK|FAILED` line per step and a final `RESULT OK <version>` to `/durable/ocutalon-after-start.log`, which is rewritten at each start.
  - **The health check** opens no IRIS session. It passes only when `iris qlist | grep -q '\^running'` succeeds and the ready marker equals the image's version. Its `start_period` is at least 10 minutes.
  - **Static web files** go under the instance's durable data directory, in its `csp/ocutalon-web/` folder (through IPM's data-directory variable), never IPM's read-only CSP-directory variable. Not `csp/ocutalon/`: the non-Health image's default application `/csp/ocutalon` serves that folder without sign-in. Story 0.3 shipped `csp/ocutalon/`, and Story 0.5 moves it (DW-5).
  - **Version check:** check the version inside the built image, because a cached build context can bake in stale sources.
  - **Private-data check:** every start ends by confirming that the private globals resolve to the private database.
  - **Step registry:**
    - Every step extends `OcuTalon.Install.Step`, and `OcuTalon.Install.Registry` runs AD-23's fixed order. A step class outside the order only declares.
    - Areas declare `Grants()`, `Reconcile()`, `Tasks()` and `Purge(daysToKeep)`.
    - A `Grants()` entry is `{"role","resource","permission"}`; an empty `resource` declares the role alone.
    - A `Tasks()` entry is `{"name","taskClass","description","task":{...},"settings":{...}}`.
    - Role and task names start with `OcuTalon`.
    - The task step creates each task once and leaves an existing task alone.
    - An IPM install calls `Registry.Run("ipm")`.
- **AD-13 (web applications and sign-in):**
  - `/ocutalon` is a `%CSP.REST`-dispatched application with password authentication, `ServeFiles` 3 and the dispatch class `OcuTalon.Web.Public.Shell`. The shell's `Login()` renders `OcuTalon.Web.Public.Login` for every request without a session and serves only the sign-in images. After sign-in it runs the user-role check and serves the built Angular files through `%CSP.StreamServer`.
  - `/ocutalon/api` (`OcuTalon.Web.Api`, `%CSP.REST`, `/v1`) shares `/ocutalon`'s CSP session, with `SessionScope` strict and no CORS.
  - A third, unauthenticated application, `/ocutalon/public`, serves only `GET /status`. Its dispatch class is in `OcuTalon.Web.Public`, and it reads only the public settings.
  - `PermittedClasses` applies to the trace applications only.
  - `/ocutalon`, `/ocutalon/api` and the trace applications are in one sign-in group, `GroupById` `OcuTalon`, never `%ISCMgtPortal`.
  - `OcuTalonUser` holds no database resources directly; the applications grant them as application roles.
  - The login page `OcuTalon.Web.Public.Login` is a `%CSP.Login` subclass loaded from `OCUTALON_PUBLIC`, with no Angular. It keeps the form contract: fields `IRISUsername`, `IRISPassword` and `IRISLogin`, `InsertHiddenFields`, and `OnPreHTTP` calling the superclass. It loads no script or file from an authenticated path.
  - The login page carries its styles inline, generated at build time, with no `style=` attributes. Its CSP header is `default-src 'none'; script-src 'sha256-…'; style-src 'sha256-…'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`.
  - `InvalidLoginAction` stays 0. Upgrades compile in place, never delete-then-load.
  - Every state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, or it gets a 403.
  - The page sends the CSP `script-src 'self'`. Local sessions allow at least 8 hours idle.
  - The WebSocket (AD-12, built second) is forwarded by the shell or moved to its own application, as its story decides.
- **AD-24 (roles and trace applications):**
  - The roles are `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`.
  - The trace role holds only:
    - Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`;
    - Read on the data and code databases (never the private ones);
    - SQL `SELECT` on `Ens.MessageHeader`.
  - The trace applications `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` have no application roles and exactly the seven permitted classes: `%CSP.Broker`, `EnsPortal.VisualTrace`, `EnsPortal.SVG.VisualTrace`, `EnsPortal.VisualTraceLegend`, `EnsPortal.SVG.TraceLegend`, `EnsPortal.MessageContents` and `EnsPortal.MessageViewer`. The OCUORDERS application and grants exist only with demo mode on.
  - No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun` or `%Ens_ProductionConfig`.
  - No `OcuTalon.Data` or `OcuTalon.Bridge.Data` class extends a message base.
- **AD-12 (live events):**
  - `Live.Event` holds `Seq` (per stream, allocated under a lock held through the commit), `Stream`, `Ts`, `Type` and `Payload`.
  - Rows are written only through `Live.Publish`, after commit, and only for types in the event table.
  - Each payload is the full public view of one entity, keyed by `Ref`, as a `%JSON.Adaptor` class with a matching TypeScript interface.
  - Trace targets are `TraceHeaderId` and `TraceNamespace`.
  - Polling is the release-1 contract; the WebSocket comes second.
- **Contract semantics fixed in Epic 0:**
  - **`Commands.Submit` (AD-1):** sets `Origin` from the authenticated context, always `tool` while a bridge context is active. Origins are `web_user`, `web_admin`, `telegram`, `tool`, `timer` and `system`.
  - **`Reply.Busy` (AD-6):** set when `Decide` refused a `turn` after a 2-second lock wait. The `Reply` carries no text and no decision, and busy is never an error status.
  - **`Decision` (AD-20):** unique on (`ItemId`, `Kind`).
  - **Compaction prompt (AD-20):** a constant whose first line starts `OCUTALON-COMPACTION-V1`.
  - **Time conversion (AD-18):** `OcuTalon.Data.Time` is the only converter outside the bridge, and `OcuTalon.Bridge.Time` the only one inside it.
  - **Audit (AD-17):** `OcuTalon.Bridge.Audit` is the only audit writer, with source `OcuTalon` and types `Action`, `Approval`, `Pairing`, `Settings`, `MCP` and `Tool`. Tests read the audit log back by polling with a timeout, because some rows are written late.
  - **Extension bases (AD-31):** the bridge wraps every `OnEvent` call and never fails its caller. `Decide` runs `ReplyFilterClass` before recording anything.
  - **Rendering (AD-32):** producers never render text. Only `*Out` operations render, through `Catalog.Render` (implemented in Story 0.9), which uses `Data.Time`.
- **AD-22 (testing and CI):**
  - `%UnitTest` classes live in `OcuTalon.Test.<Area>`, sharded by area, one compose project per shard.
  - The mock is reached through the Anthropic provider's `base_url` over plain HTTP on the compose network.
  - The mock rejects `temperature`, `top_p`, `top_k` and output caps under 4,000.
  - A request picks its scenario by, in order: a `[[mock:<name>]]` marker, the exact text of a guide prompt contained in the message, then `MOCKKEY`. Never by prompt wording.
  - The mock logs header names and the key's length only. Its only state is a per-test countdown.
  - CI and scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format`, because both print `env_file` values.

### Cross-lane contract obligations (AD-29, AD-33)

- **Contracts before code:** create every release-1 contract with its final names and types: properties, enumerations and storage. Cross-lane APIs are signatures with stub bodies. Only `Commands.Submit` (0.6), `Data.Public.Settings` (done in 0.2) and `Msg.Catalog.Render` (0.9) are fully implemented. The full lists are in Stories 0.4 to 0.6 and 0.9.
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
- **Enumerations:** defined once in `OcuTalon.Msg.Enum`, with a bridge copy in `OcuTalon.Bridge.Msg.Enum`:
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
- **Identifiers:** every `Ref` is a 22-character base64url string with no padding, from `OcuTalon.Bridge.Ids.NewRef()`. Row ids never leave the server.
- **Times:** UTC ISO 8601 in storage and the API.
- **REST:**
  - Paths are `/ocutalon/api/v1/...`, with plural nouns and commands as `POST` on a resource.
  - Errors use the shape `{"error": {"code", "message"}}`, in plain English.
  - Unbuilt routes answer 501.
  - The live-event envelope is `{seq, stream, ts, type, payload}`.
- **Persistent classes:** every one that isn't a message sets `Parameter DEFAULTGLOBAL = ^OcuTalonP.<Short>` (`^OcuTalonBP.<Short>` in the bridge), from the short-name registry that Story 0.4 starts. CI fails on a duplicate. The compiler-generated `Storage` block is committed.
- **Hosts and errors:** hosts log with `$$$LOGINFO`, `$$$LOGWARNING` and `$$$LOGERROR`. Code uses `%Status` throughout and `$$$ThrowOnError` inside methods. Plain English appears only at the channel edge. Never read globals directly for settings.
- **Python:** only as `.py` resources under `src/ocutalon/python/`, never `[Language = python]`.
- **Angular:** standalone components and signals, hash routing, one typed API client and one live-event service. Fonts and icons are bundled, never loaded from a CDN, with their licence notices kept.
- **Tests:** `OcuTalon.Test.<Area>.<Subject>`, and Playwright under `web/e2e/` (demo path: `web/e2e/demo-path/`, one spec per UJ-1 step).
- **Source tree:**
  - `src/module.xml`, `src/bridge/cls/OcuTalon/{Bridge,BridgeExample}/` and `src/ocutalon/cls/OcuTalon/...`;
  - `web/`, `eval/`, `docker/` (Dockerfile, `merge.cpf`, after-start script, health check, `ipm/`) and `ci/` (override, mock, `ci/mock/scenarios/<A|B>/<name>.json`);
  - `docker-compose.yml` (no mocks), `docker-compose.dev.yml` and `.env.example`.

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

- **S1 (passed):**
  - IPM 0.10.10 installs offline into durable `%SYS`.
  - The one package installs and upgrades in place at start, bridge first, keeping data, and a failed load is rolled back.
  - The bridge also loads alone without IPM.
  - Hazards: a non-zero exit from the after-start script makes the container loop; IPM's CSP directory is read-only; the mount directory must be owned by the IRIS user; a class without its storage block remaps rows on reload; cached builds can be stale.
  - `qlist` uses `^` separators, so match `\^running`.
  - A first start takes about 1 minute on Apple silicon.
- **S3 (passed):** the Anthropic `base_url` reaches a mock over HTTP, so no CA or host alias is needed. `base_url` ends `/v1/`.
- **S12 (passed):** the non-Health image runs the same Dockerfile, with no Foundation installer (a first start of about 20 seconds). Its web server is on.
- **S16 (passed):**
  - The package-mapped login page and status class dispatch before sign-in with no roles, at install and after an upgrade, in both namespaces. S16 also confirmed the merge actions through `iris merge` on a running instance.
  - A mapping created after a compile hides the classes, hence the check that they resolve to `OCUTALON_PUBLIC` and the forced reload.
  - The status class must override `AccessCheck`.
- **S7 (partial):** one sign-in group opens the trace applications with no second sign-in. That requires exactly the seven permitted classes and the trace role's code-database Read and `Ens.MessageHeader` `SELECT`.
- **S14:** `^IRIS.IF.*` must map to the private database.
- **S2:** no sampling parameters, and an 8,000-token cap. The mock enforces both.
- **S18:** the mock includes a long `Retry-After` scenario, capped by the retry block's back-off.
- **S19 (later, Epic 15):** the package's CPF resource `src/cpf/ocutalon.cpf` must differ from `docker/merge.cpf` only by the `%Service_CallIn` and IPM lines.

## UX & Interaction Patterns

- **Built in Story 0.3:** the sign-in page and the app header. The full logo is at 320px above a card titled "Sign in to OcuTalon". The header shows the mark, the wordmark, the "Demo mode" badge (shown only with demo mode on locally) and the account menu with Sign out. The main page is empty, and Story 2.1 lays it out.
- **Texts the public package keeps its own copies of** (Story 0.9's comparison with the catalog covers them):
  - help line: "Use the IRIS account your install created; the README lists it."
  - wrong credentials: "That user name and password didn't work."
  - missing role: "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it."
- **Token stylesheet:** generated from `DESIGN.md`'s front matter and covering every token group. In the dark theme every `<name>` maps to `<name>-dark`, except the QR block, shadows, `brand-navy-dark` and the splash canvas. No text is under 12px. Icons are hidden from assistive technology. `prefers-reduced-motion` stops all animation. The focus ring is 2px solid `focus` at a 2px offset, with a `surface` halo.
- The sign-in page uses system font stacks, because `default-src 'none'` blocks font loads. The bundled fonts serve the Angular shell.

## Cross-Story Dependencies

- **Delivered so far: Story 0.1 (done).** Later stories build on these contracts:
  - **Image version:** the first `<Version>` of `src/module.xml` is baked into `/opt/ocutalon/version`, and the build fails if it is empty.
  - **Ready marker:** `/durable/ocutalon.ready` holds one line, the version. The after-start script writes it atomically: a temporary file in `/durable`, then `mv`.
  - **`docker/healthcheck.sh`:** passes only when `iris qlist` shows `^running` and the non-empty version file equals the marker. Its `OCUTALON_VERSION_FILE` and `OCUTALON_READY_MARKER` variables exist only for the hermetic test.
  - **`docker/merge.cpf`:** uses relative database directories, which land in `/durable/iris/mgr/ocutalon_{code,data,private,public}/` under `ISC_DATA_DIRECTORY=/durable/iris`. They stay relative so S19's package CPF file can be this file minus the CallIn and IPM lines. It also maps `^OcuTalonPublic` and the two public packages to the public database.
  - **`docker/Dockerfile`:** `ARG IRIS_IMAGE`, `/durable` owned by 51773, and the merge file, `module.xml`, health check and after-start script under `/opt/ocutalon/`. It then sets `USER 51773`, with `ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf`, and the `CMD` described under AD-23.
  - **`.dockerignore`:** `*`, then an allow-list of the copied files. Every file a later story copies into the image must be added to it.
  - **`docker-compose.yml`:** `name: ocutalon`, one service `iris` (`pull_policy: build`, `restart: unless-stopped`), `env_file` `.env` with `required: false`, the web port only, volume `durable:/durable`, and a health check with `start_period: 600s`.
- **Delivered so far: Story 0.2 (done).** Later Epic 0 stories build on these:
  - **After-start script:** `docker/after-start.sh` (with `docker/after-start.cos`). Its log, `/durable/ocutalon-after-start.log`, carries the `STEP`/`RESULT` lines.
  - **Step order** (`Registry.Order()`, classes `OcuTalon.Install.Step.<Area>`; each story fills its own step without re-ordering):
    1. `Bridge.Installer`: stub; 0.4 to 0.6, then Epic 1.
    2. `Public`: the online-demo flag only; 3.8 adds its values.
    3. `Roles`: built; 0.3 added the declarations.
    4. `Users`: built in 0.3.
    5. `Web`: built in 0.3; 0.5 adds `/ocutalon/public` and moves the bundle folder.
    6. `SSL`: stub; the first story that needs a client SSL configuration.
    7. `Tasks`: built; 1.11 and later areas declare.
    8. `Demo`: stub; 0.6.
    9. `Provider` (Config Store): stub; 1.1.
    10. `Audit`: stub; 0.4, then 3.7.
    11. `Telegram`: stub; 12.1.
    12. `Production`: a stub that starts nothing; 0.6.
    13. `Reconcile`: built; it calls the areas' declarations.
    14. `PrivateData`: built; it checks the private classes 0.4 adds first.
    15. `Ready` (`Public.Ready`): built.
  - **Structural or seed:** the public settings and the roles are rewritten every start; tasks are created once. The System Default Settings helper joins `OcuTalon.Install.Step` with Story 1.1.
  - **`OcuTalon.Data.Public.Settings`** (implemented): its fixed keys are `onlineDemo`, `demoUser`, `demoPassword`, `readonlyUser`, `readonlyPassword`, `resetIntervalHours`, `resetAnchor`, `lastReset`, `lastResetKind`, `proxyAddress`, `connectionCap`, `connectionReserve` and `messageAllowance`, plus `ready`. Any other key is refused. Times are UTC ISO 8601 with `Z`. Defaults are the `Public` step's job (3.8), not the accessor's. Its consumers are 0.4's `Setting.Get` (which delegates to it) and 0.5's `/ocutalon/public/status` (`ready`, `NextReset`). The login page reads no public setting yet; its first read is Story 16.2's splash on `onlineDemo`.
  - **Package layout:** `src/module.xml` (`ocutalon` 0.1.0) lists `OcuTalon.Bridge.PKG` from `src/bridge/cls`, then `OcuTalon.PKG` from `src/ocutalon/cls`. `.gitattributes` sets `src/** text=auto eol=lf`, so binaries under `src/` stay intact.
  - **`docker-compose.dev.yml`:** an override used as `-f docker-compose.yml -f docker-compose.dev.yml`. It is its own project, `ocutalon-dev`, with its own volume, sets `OCUTALON_DEV=1` and publishes the same web port.
  - **`docker/ipm/`:** the vendored IPM 0.10.10 release file (`zpm-0.10.10.xml`) and its `LICENSE`, shipped in `/opt/ocutalon/ipm/`. Story 10.2's README points to the notice.
  - **Tests:**
    - `%UnitTest` classes go under `src/ocutalon/cls/OcuTalon/Test/<Area>/`.
    - Bash tests are `docker/tests/test-*.sh`, each runnable alone and exiting 0 on success.
    - The live ones share `docker/tests/lib-live.sh`: `live_start` gives a throwaway project with no keys, and cleans it up.
    - `test-compose-start.sh` forces `iris-main`'s merge by removing or editing the `*.last_merge` record and counts the `Merging /opt/ocutalon/merge.cpf` lines in `messages.log`.
    - Test-only path variables follow `healthcheck.sh`'s convention.
- **Delivered so far: Story 0.3 (done).** Later stories build on these:
  - **Roles and the README account:**
    - The `Roles` step composes the `Users` and `Web` steps' `Grants()`. `OcuTalonUser` and `OcuTalonAdmin` hold nothing directly. `OcuTalonTraceViewer` holds AD-24's six resource grants plus `SELECT` on `Ens.MessageHeader`.
    - The `ocutalon`/`ocutalon` account holds all three roles, with a non-expiring password and no forced change. It is written as seed, so a changed password survives later starts.
    - `Users` and `Roles` are Lane A's; `Web`, `OcuTalon.Web.*` and `web/` are Lane B's.
  - **The three web applications** (built by `OcuTalon.Install.Step.Web`):
    - `/ocutalon` (dispatch `Shell`, `ServeFiles` 3, `Path` the bundle folder);
    - `/ocutalon/api` (dispatch `Api`, no `Path`);
    - `/ocutalon/trace/ocutalon/` (no dispatch class, `ServeFiles` 1, AD-24's seven permitted classes, no application roles).

    All three use password authentication, `GroupById` `OcuTalon`, `SessionScope` 2, an 8-hour timeout, no `LoginPage`, empty CORS lists and `CSPZENEnabled` 1. On build 154, a value of 0 stops signed-in requests from reaching the dispatch class. The first two share `CookiePath` `/ocutalon/` and `MatchRoles` `%DB_OCUTALON_{CODE,DATA,PRIVATE}`, the merge's roles, so AD-24's role list is unchanged. `Step.Web` also has `BundleCheck`, which names the missing path, and `GrantTraceSql`.
  - **`Web.TraceApp(namespace, .props)`** returns `/ocutalon/trace/<namespace in lower case>` and its properties. Story 0.6's `Demo` step builds the OCUORDERS application from it, and Story 4.1 adds or removes it as demo mode switches.
  - **`OcuTalon.Web.Public.Shell`:**
    - It adapts `%ZHSLIB.REST.AngularHandler`, which is HS-only and outside AD-3's allow-list, so it is not referenced.
    - Without a session it renders `Login` and serves only `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png` and `assets/brand/favicon-32.png`.
    - Signed in, it runs the role check and serves the bundle through `%CSP.StreamServer`, with 304 handling. A name that the stream server would resolve under `/csp/broker/` answers 404.
    - Class and ZEN URLs under `/ocutalon/` answer the sign-in page without a session and 404 when signed in.
  - **`OcuTalon.Web.Public.Login` and `SignInAssets`:** `SignInAssets.cls` is generated at build time and holds the sign-in CSS and script. The browser enforces them under compile-time hashes. Sign-in errors keep `%CSP.Login`'s error codes: any code other than the missing role shows the wrong-credentials text.
    - The sign-in POST has no CSRF token, because a dispatched sign-in emits none. `form-action 'self'` and strict `SessionScope` are the mitigations. The wider cross-site sign-in risk is open as DW-6 (decision pending).
    - Sign out uses `?IRISLogout=end`, which ends the whole group, until Story 2.2 moves it to the API.
  - **`OcuTalon.Web.Api`:** a `%CSP.REST` class with an empty `UrlMap`. Story 0.5 fills the routes and adds the role check in `OnPreDispatch`.
  - **The `web/` Angular shell:**
    - `npm --prefix web run build` runs `scripts/tokens.mjs --check`, then `scripts/brand.mjs`, then `ng build`, and writes `src/ocutalon/csp/`. That folder is git-ignored on development branches, and Story 11.5 force-adds it at release. The Dockerfile refuses an image without it.
    - IPM's `FileCopy` copies it into the durable data directory on install, upgrade and every `OCUTALON_DEV` load, and never prunes stale hashed files.
    - `scripts/tokens.mjs` generates `src/styles/tokens.css` and `SignInAssets.cls` from `DESIGN.md`'s front matter, and `--check` fails when the committed output is stale. `scripts/brand.mjs` copies the brand images from `logo/web/` into `public/assets/brand/`; those copies are build output and not committed. The scripts' tests are `node --test` files under `web/scripts/`.
    - The branch commits the sources, `package-lock.json`, the generated `tokens.css` and `SignInAssets.cls`, the vendored fonts, and the licences in `web/public/assets/licenses/`.
  - **Browser tests:** `web/playwright.config.ts` and `signIn()` in `web/e2e/sign-in/helpers.ts`, which Story 0.8 reuses. The sign-in specs are under `web/e2e/sign-in/`.
  - **`docker/tests/test-sign-in.sh`** runs the live test of rows 1 to 13. It sets `LIVE_REBUILD_WEB=1` before sourcing `lib-live.sh`, which rebuilds the bundle. It checks the security tables (`check_security`), then runs the Playwright sign-in specs.
    - The throwaway stack publishes its web port on 127.0.0.1 only, on the first free port in 52800–52819 (or `OCUTALON_TEST_WEB_PORT`).
    - It needs Node 24.15 or later and `npx --prefix web playwright install chromium`.
    - Related tests: `test-web-build.sh`, `test-install-upgrade.sh`, and the `%UnitTest` classes `Test.Web.Shell` and `Test.Web.Install`.
- **Developer slots:** both slots (`ocutalon-slot-a`, then `ocutalon-slot-b`) run 0.1's `merge.cpf`, copied to the slot's `config/`. Adjust a slot's mount or `ISC_DATA_DIRECTORY`, never the merge file. The slots use the base image without the after-start script: code goes in through the IRIS MCP tools, and installer steps are run explicitly. The after-start install and destructive tests run only in throwaway compose stacks and CI.
- **0.4:**
  - It keeps the messages, data tables, enums, `Ids`, `Time`, `Setting.Get`, `Bridge.Audit` and the storage/`DEFAULTGLOBAL` short-name registry.
  - Its contracts feed 0.5 (live payloads and their TypeScript interfaces), 0.6 (items and `Commands.Submit`) and 0.9 (`Data.Time`, which `Catalog.Render` uses).
  - The Item's and `ItemDecision`'s optional `CatalogKey` and `Slots` name keys that 0.9 creates.
- **0.5:**
  - It fills `Api`'s `UrlMap` (every release-1 route, with unbuilt ones answering 501) and the role check in `OnPreDispatch`, and adds `/ocutalon/public` to the `Web` step.
  - **DW-5:** it moves the bundle from the durable `csp/ocutalon/` folder to `csp/ocutalon-web/`. That changes `src/module.xml`'s `FileCopy` target, `Step.Web`'s `/ocutalon` `Path` and `BundleCheck`, and 0.3's tests (matrix row 14, `test-install-*.sh`). A live test on `iris-community:2026.3.0AI.154.0` pins both sides: `/csp/ocutalon/index.html` and `/csp/ocutalon/main-*.js` answer 404 without a session, and the bundle loads from the new folder through `/ocutalon/` after sign-in.
- **0.6:** its `Demo` step calls `Web.TraceApp("OCUORDERS")` with demo mode on. Its constants (`MOCKKEY`, tool names, compaction prefix) are what 0.7's mock keys on.
- **0.7 and CI:**
  - 0.7's checks gate everything above.
  - The CI override extends 0.1's compose file. CI runs `docker/tests/test-*.sh` (the live ones on the IRIS runner) and the `%UnitTest` shards, plus the public-package and `^OcuTalonPublic` checks.
  - From 0.3, CI also runs the web build, `tokens --check`, `node --test` and `test-sign-in.sh`, and the allow-list check covers `Shell`, `Login` and `SignInAssets`.
  - 0.7 also updates `_bmad/custom/skill-rules.md` (the IRIS test recipe, shard command, timings) and `_bmad/custom/parallel.yaml` (bootstrap, including `web/`'s dependencies, and runtime locks).
  - CI must run on `feature/OCT_OcuTalon_MVP` and `OCT-epic*` with no `cancel-in-progress`.
- **0.8:** runs in 0.7's IRIS job. It reuses 0.3's `playwright.config.ts` and `signIn()` and needs 0.5's `/state`.
- **0.9 (last story of Epic 0):**
  - It builds `OcuTalon.Msg.Catalog.Core` and `.Watch` with every release-1 and 0.1.1 key, and implements `Catalog.Render(key, slots, channel)`, tested on every key and channel.
  - It adds the test that compares the public package's copies of the sign-in texts (`Login`'s, Story 0.3) with the catalog.
  - It is Lane B's after Epic 0.
- **Epic 10 (from 0.1's compose file):** `install.sh` uses `IRIS_IMAGE`. The `env_file` with `required: false` needs Docker Compose 2.24 or later, so Story 10.1's `install.sh` refuses an older Compose and Story 10.2's README states the minimum. Story 10.2's README also carries the LAN-exposure warning for the published web port and the README account's password change.
- **Later epics:** Epic 1 (Lane A) and Epic 2 (Lane B) both start from Epic 0 and test against its stubs and the mock. Epic 15 derives `src/cpf/ocutalon.cpf` from `docker/merge.cpf` and calls `Registry.Run("ipm")`. Owners of the stubs and 0.3 hand-offs:
  - header, theme (`data-theme`), badge and About: Story 2.1
  - `SessionEvents`, and Sign out through the API: Story 2.2
  - `BridgeSink`: Story 2.6
  - `Delivery`: Story 2.7
  - `Allowance` and `Trace.Join`: Stories 2.4 and 2.9
  - `Bridge.Approval`: Epic 3
  - online-demo public keys: Story 3.8
  - OCUORDERS grants: Story 3.1
  - demo-mode switching: Story 4.1
  - `Checks.Render`: Epic 5
  - `ReplyGuard`: Story 5.7
  - the `lane-a.yml` bridge job: Story 1.3
  - Telegram `Included()` use: Story 10.3
  - the install script, completed: Epic 10
  - the login splash, online-demo timeouts (120 s) and busy state: Stories 16.2, 16.4 and 16.5
