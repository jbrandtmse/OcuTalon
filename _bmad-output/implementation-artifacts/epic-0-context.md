# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. A judge loads and retags the build 154 image, runs `docker compose up`, and gets OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with an empty, branded page behind sign-in. Its real job is to unblock two parallel build lanes. It creates every cross-lane release-1 contract with its final name, type and storage: messages, tables, live-event payloads, the catalog and its renderer, the REST skeleton, the bridge extension points and the cross-lane API signatures. It also stubs every release-1 production item inside lane-owned regions, and sets up CI with the model mock and a demo-path test. Lane A and Lane B can then each start their first story without editing the other's files. It is one runner, time-boxed to three days from the build start (October 21 at the latest), and it ends October 23 at the latest.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts (done)
- Story 0.5: Live events and the REST skeleton (done)
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock
- Story 0.8: The demo-path test signs in and loads the page
- Story 0.9: The message catalog and its one renderer
- Story 0.10: The Orders demo production runs in OCUORDERS

## Requirements & Constraints

- **Install:** after a load and retag, a plain `docker compose up` gives a working install. The first start creates OCUTALON with Interoperability and its own databases. Later starts reapply the same configuration with no errors and no data loss. In demo mode (the Docker default), the Orders production runs in its own namespace, OCUORDERS.
- **Roles and sign-in:** the install creates the user, admin and trace roles. The README account (`ocutalon`/`ocutalon`) has a non-expiring password and no forced change, and the README says how to change it. No page or API answers without a session, except the login page (with its images) and `/ocutalon/public/status`.
- **Secrets:** model keys and bot tokens come only from environment variables. `.env` is git-ignored, and `.env.example` lists `ANTHROPIC_API_KEY` and `TELEGRAM_BOT_TOKEN` with no values. No key appears in logs, traces, audit entries or the repository.
- **Image and registry:** the AI Hub image, or any image built on it, is never pushed and never enters a CI cache or artifact. CI fails on any `docker push` or registry sign-in. The judges' compose file has no mock service.
- **Tracked files:** no tracked file holds a local machine path or a key-like string, and a CI check enforces this.
- **CI:** a full run takes at most 30 minutes. IRIS tests run on the dedicated self-hosted runner, everything else on hosted runners. Fork pull requests never reach the IRIS runner. The demo-path browser test runs on every pull request and every push to `main`, and a failure blocks the merge. `main` moves only through a release pull request.
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
  - One IPM package, `ocutalon`. `src/module.xml` lists the bridge (`src/bridge/`: `OcuTalon.Bridge`, `OcuTalon.BridgeExample`) before everything else (`src/ocutalon/`), plus the Angular bundle (`FileCopy`).
  - `src/bridge/` also loads alone with `$SYSTEM.OBJ.LoadDir` into a namespace with Interoperability (its messages extend `Ens.Request`/`Ens.Response`), and `OcuTalon.Bridge.Installer` sets it up. Without Interoperability only `Bridge/Installer.cls` loads, and it refuses, naming the namespace. OcuTalon's installer calls it first.
  - CI fails if any `OcuTalon.Bridge` class references another `OcuTalon` package, or if any class outside `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Docs`, `.Memory`, `.Mcp`, `.Install` and `.Test` (whole package names) references `%AI` or `EnsLib.AI`.
  - `OwnerRef` is exactly a `SessionRef`, `instance` or `eval`.
- **AD-3 (namespaces and databases):**
  - OCUTALON has code, data, private and public (`OCUTALON_PUBLIC`, public Read) databases.
  - The public database holds only `OcuTalon.Web.Public` (`Login`, `Status`, the `/ocutalon` dispatch class `Shell`, the generated `SignInAssets`, and `ApiBase`, the API's answer before sign-in), `OcuTalon.Data.Public` and `^OcuTalonPublic`. Code that answers before sign-in must live there: a request without a session can't read the code database.
  - Those packages may reference only `%CSP` (including `%CSP.REST`), dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (only in a compile-time generator) and each other. They keep their own copies of the UX texts they render, compared with the catalog by a test (0.9). `Shell` and `Status` override `%CSP.REST.AccessCheck`.
  - Global mappings put `OcuTalonP.*` and `OcuTalonBP.*` (with the dot, so `^OcuTalonPublic` stays public), `^AI.Agent.Session*` and `^IRIS.IF.*` in the private database. The databases and mappings exist before any class compiles.
  - `OcuTalon.Production` is not autostart on Docker.
  - Only `OcuTalon.Install.*`, `OcuTalon.Bridge.Installer` (to `%SYS`, in its one method, which also registers the audit events) and `Install.Step.Demo` (to OCUORDERS) switch namespace in product code, each in one method with `New $NAMESPACE`. Test classes also switch to `%SYS` for fixtures (accepted, DW-7).
  - On the non-Health image, `Interop=1` only enables Interoperability: no Foundation production, and the default web application is `/csp/<ns>`. Nothing may depend on either.
- **AD-5 (durable state):** all state lives on the durable volume, and an install replaces only code. Storage is append-only, and every such class's source carries its compiler-generated `Storage` block, never edited by hand. The production class holds structure only; values go in System Default Settings, bridge tables or `OcuTalon.Data.Setting`.
- **AD-19 (configuration homes):**
  - Model keys and bot tokens are environment-only (`@{env:VAR}` or `$SYSTEM.Util.GetEnviron`). Endpoint overrides `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_EXTRA_CA_FILE` and `OCUTALON_TELEGRAM_API_BASE` are set only by the CI override and the online demo.
  - The installer marks every value it writes `structural` (rewritten every start) or `seed` (written only when absent).
  - `OcuTalon.Data.Public.Settings` is the only reader and writer of `^OcuTalonPublic`; CI fails on any other reference. `OcuTalon.Data.Setting.Get` serves product values through a 60-second cache.
- **AD-23 (image and installer):**
  - **Image:** one Dockerfile, `FROM ocutalon-iris-base:2026.3.0AI.154.0`, mount directory owned by UID 51773. Every compose file sets its own top-level `name:`; the IRIS service sets `stop_grace_period: 60s`. The judges' compose file publishes only `${OCUTALON_WEB_PORT:-52773}`, on every host interface.
  - **The CPF merge** (`docker/merge.cpf`) creates the databases, namespace and mappings and enables `%Service_CallIn`, idempotently; the after-start script re-runs it every start on a fresh copy (build 154 applies it only when changed), which also repairs a mapping removed by hand.
  - **The after-start script** (OS authentication) re-merges, installs IPM 0.10.10 into `%SYS` (mapped into OCUTALON only), checks that the public classes resolve to `OCUTALON_PUBLIC`, loads the package version-gated (`OCUTALON_DEV=1` reloads every time), runs the registry's steps and writes the ready marker atomically. It always exits 0; a failure writes no marker. It logs `STEP <name> OK|FAILED` and `RESULT OK <version>` to `/durable/ocutalon-after-start.log`.
  - **The health check** opens no IRIS session: `^running` in `iris qlist` and the marker equal to the image's version; `start_period` at least 10 minutes.
  - **Static web files** go in the durable data directory's `csp/ocutalon-web/` (IPM's data-directory variable), never IPM's read-only CSP-directory variable, and never `csp/ocutalon/`, which the non-Health image's `/csp/ocutalon` serves without sign-in.
  - Check the version inside the built image (a cached build context can bake in stale sources). Every start ends by confirming the private globals resolve to the private database.
  - **Step registry:** every step extends `OcuTalon.Install.Step`; `OcuTalon.Install.Registry` runs the fixed order, and a step class outside it only declares. Areas declare `Grants()` (`{"role","resource","permission"}`; empty `resource` declares the role alone), `Reconcile()`, `Tasks()` (`{"name","taskClass","description","task":{...},"settings":{...}}`) and `Purge(daysToKeep)`. Role and task names start with `OcuTalon`. Tasks are created once. An IPM install calls `Registry.Run("ipm")`.
- **AD-13 (web applications, sign-in and the envelope):**
  - **One sign-in group** (`GroupById` `OcuTalon`, never `%ISCMgtPortal`, password authentication): `/ocutalon` (dispatch `OcuTalon.Web.Public.Shell`, `Path` the durable `csp/ocutalon-web/`), `/ocutalon/api` (`OcuTalon.Web.Api`, `/v1`, sharing `/ocutalon`'s CSP session, `SessionScope` strict, no CORS) and the trace applications. `PermittedClasses` applies to the trace applications only. `OcuTalonUser` holds no database resources directly; the applications grant them as application roles.
  - **`/ocutalon/public`** is unauthenticated and outside the group (`AutheEnabled` 64, `UseSession` 0, `no-store`). It serves only `GET /status` from `OcuTalon.Web.Public.Status`, reads only the public settings, and always returns every key, `null` when unset: `{ready, nextReset, busy, lastReset, lastResetKind}` (`scheduled` or `unscheduled`).
  - **The API before and after sign-in:** `Api` extends `OcuTalon.Web.Public.ApiBase`, which answers a request without a session with 401 `signed_out` (an `Api.Login` override never runs without a session on build 154). A signed-in user without the user role gets 403 `no_role` and keeps the session, so a trace-only user stays signed in to the trace windows.
  - **SQL privilege:** `OcuTalonUser` holds no SQL grant on OcuTalon's tables, so the API's own queries over the signed-in user's rows are prepared without the privilege check (`%Prepare(text, 0)`), with fixed texts and every input a parameter; ownership is enforced in the queries. Don't grant `SELECT` to a role instead.
  - **Session lookup, Epic 0 interim:** until Story 2.2 builds `OcuTalon.Data.Ownership`, `/state` and `/events` find the caller's session by user name (`Session.ForUser`). 2.2 switches them to Ownership, resolving the session from the CSP session (AD-4), before any shared online-demo account exists (DW-15).
  - **Login page** `OcuTalon.Web.Public.Login` (`%CSP.Login`, no Angular, built in 0.3) keeps `%CSP.Login`'s form contract, loads nothing from an authenticated path and sends a hash-pinned `default-src 'none'` policy. `InvalidLoginAction` stays 0. Upgrades compile in place, never delete-then-load.
  - **The browser envelope:** every state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, or it gets a 403. GET, HEAD and OPTIONS are exempt.
  - The page sends `script-src 'self'`. Local sessions allow at least 8 hours idle. The WebSocket (AD-12, Story 2.11) lives outside `/ocutalon/api`.
- **AD-24 (roles and trace applications):**
  - The roles are `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`. The trace role holds only Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`; Read on the data and code databases (never the private ones); SQL `SELECT` on `Ens.MessageHeader`.
  - The trace applications `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` have no application roles and exactly seven permitted classes: `%CSP.Broker`, `EnsPortal.VisualTrace`, `EnsPortal.SVG.VisualTrace`, `EnsPortal.VisualTraceLegend`, `EnsPortal.SVG.TraceLegend`, `EnsPortal.MessageContents` and `EnsPortal.MessageViewer`. The OCUORDERS application and grants exist only with demo mode on.
  - No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun` or `%Ens_ProductionConfig`. No `OcuTalon.Data` or `OcuTalon.Bridge.Data` class extends a message base.
- **AD-12 (live events):**
  - `Live.Event` holds `Seq`, `Stream` (a `SessionRef` or `instance`; exact-collated, because refs are case-sensitive), `Ts`, `Type` and `Payload`. Row ids never leave the server.
  - Rows are written only through `Live.Publish`, after the publisher's own change has committed; `Publish` refuses to run inside an open transaction. Only event-table types are accepted, each with exactly one publisher.
  - `Seq` comes from a per-stream counter, `^OcuTalonP.LiveEventC(stream)` (private), set under the stream's lock held through the insert and commit, so a stream's rows commit in `Seq` order. The purge (2.2) deletes rows, never the counter, so `Seq` never restarts and an open page's cursor stays valid. `LastSeq` waits, under a shared lock, for an open `Publish`, so `/state` never hands out a cursor ahead of the committed rows.
  - The browser envelope labels the stream `session` or `instance` (the cursor it advances), never the stored `SessionRef`.
  - A payload is the full current public view of one entity, keyed by `Ref`, never a delta: a `%JSON.Adaptor` class `OcuTalon.Live.Payload.<Type>` owned by the publisher's lane, with nested shapes as part classes under `OcuTalon.Live.Payload.Part`. JSON keys are the property name with a lower-case first letter. The TypeScript interfaces are generated by `web/scripts/payloads.mjs`, whose `--check` runs in the build.
  - Trace targets are `TraceHeaderId` and `TraceNamespace`; the web layer adds the URL (`Web.TraceLink`, 2.9). Polling is the release-1 contract; the WebSocket comes second and is never opened on the online demo.
  - Status conditions are a closed catalog: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`.
- **Contract semantics fixed in Epic 0:**
  - **`Commands.Submit` (AD-1):** sets `Origin` from the authenticated context, always `tool` while a bridge context is active. Origins: `web_user`, `web_admin`, `telegram`, `tool`, `timer`, `system`.
  - **`Reply.Busy` (AD-6):** set when `Decide` refused a `turn` after a 2-second lock wait; the `Reply` carries no text and no decision (`Reply.NewBusy()`), and busy is never an error status.
  - **`Decision` (AD-20):** unique on (`ItemId`, `Kind`). **Compaction prompt:** a constant whose first line starts `OCUTALON-COMPACTION-V1`.
  - **Time conversion (AD-18):** `OcuTalon.Data.Time` is the only converter outside the bridge, `OcuTalon.Bridge.Time` (1.4) the only one inside it.
  - **Audit (AD-17):** `OcuTalon.Bridge.Audit` is the only audit writer (events `OcuTalon/<T>/<T>` for `Action`, `Approval`, `Pairing`, `Settings`, `MCP`, `Tool`), registered by `Bridge.Installer` each start and only checked by the `Audit` step. OcuTalon never changes instance-wide auditing. Tests poll the audit log with a timeout (rows appear 53 to 72 s late).
  - **Extension bases (AD-31):** the bridge wraps every `OnEvent` call and never fails its caller. `Decide` runs `ReplyFilterClass` before recording anything.
  - **Rendering (AD-32):** producers never render text. Only `*Out` operations render, through `Catalog.Render` (0.9), which uses `Data.Time`.
- **AD-22 (testing and CI):**
  - `%UnitTest` classes live in `OcuTalon.Test.<Area>`, sharded by area, one compose project per shard.
  - The mock is reached through the Anthropic provider's `base_url` over plain HTTP on the compose network. It rejects `temperature`, `top_p`, `top_k` and output caps under 4,000.
  - A request picks its scenario by, in order: a `[[mock:<name>]]` marker, the exact text of a guide prompt contained in the message, then `MOCKKEY`. Never by prompt wording.
  - The mock logs header names and the key's length only; its only state is a per-test countdown.
  - CI and scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format` (both print `env_file` values).

### Cross-lane contract obligations (AD-29, AD-33)

- **Contracts before code:** every release-1 contract gets its final names and types: properties, enumerations and storage. Cross-lane APIs are signatures with stub bodies. Fully implemented in Epic 0: `Commands.Submit` (0.6), `Data.Public.Settings` (0.2), 0.4's helpers, 0.5's live-event store and API skeleton, and `Msg.Catalog.Render` (0.9). Epic 0 fixes the cross-lane properties and identity columns; the owning lane appends the rest.
- **Catalog (0.9):** every release-1 and 0.1.1 key, in `OcuTalon.Msg.Catalog.Core` (Lane B) or `.Watch` (Lane A). The item noun slot is `itemNoun: {"one", "other"}`.
- **One owner each:** after Epic 0, each item, class, table and event type has one owning lane, and only that lane edits it. The other lane asks, and the owner appends. A new item, table or event type is added to the ownership tables in the same change.
- **Lane A owns:** `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, `.Eval` and `eval/`; the installer core (the registry, `docker/merge.cpf`, and the role, user, SSL, task, `Production` and `Public` steps); `ci/mock/scenarios/A/`; `release/`; and `.github/workflows/lane-a.yml`.
- **Lane B owns:** `OcuTalon.Web` (with `.Web.Public`), `.Channel`, `.Core`, `.Schedule`, `.Demo`, `.Live`, `.Msg`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership` and `.Data.Public`; `web/`, the rest of `docker/` and `ci/`, and `.github/workflows/ci.yml`; and the `Web` and `Demo` installer steps.
- **By area:** `OcuTalon.Test.<Area>`, `OcuTalon.Install.Step.<Area>` and `OcuTalon.Live.Payload.<Type>` (with its parts) follow their area's or publisher's lane.
- **Table owners:** Lane B: `Session`, `AddressCounter`, `StatusMark`, `GuideState`, `BreakFeedRun`, `Pairing`, `Turn`, `SimMessage`, `Delivery`, `Reminder`, `Setting` and `Live.Event`. Lane A: `BackgroundCheck`, `WatchMark`, `Incident`, `FailureGroup`, `FixRun`, every `Bridge.Data` class and `Digest.Data.Item`.
- **Production class:** one `ProductionDefinition` XData block, each lane's items between `<!-- lane A: begin -->`/`<!-- lane A: end -->` (the same for lane B), classes and lanes per the spine's production-item table. Every item is enabled except `TelegramIn` and `TelegramOut` (off until a release includes Telegram) and `EvalIn` (only with `OCUTALON_EVAL=1`). Unbuilt items answer "not implemented" instead of failing.
- **`Decide` settings in Lane A's region:** `HostSinkClass` = `OcuTalon.Core.BridgeSink`, `ReplyFilterClass` = `OcuTalon.Checks.ReplyGuard`; `ClassificationClass` keeps the default.
- **HostSink payloads:** `decision.*` and `approval.*` carry the record's public `Ref`; `turn.step` carries `{decisionRef, label}`, with the session as `ownerRef`; `budget.capped` has `ownerRef` `instance` and payload `{day}`.
- **Test-only global:** `^OcuTalonTest("TelegramIncluded")` is set only by `OcuTalon.Test` classes and never exists in the judges' install.

### Naming and storage conventions

- **Classes:** `OcuTalon.<Area>.<Name>`, one class per file. Cross-lane contracts go in `OcuTalon.Msg`/`OcuTalon.Data`, bridge contracts in `OcuTalon.Bridge.Msg`/`.Data`. Nothing under a system package name; `irislib/` and `irissys/` are read-only references, never loaded.
- **Item names:** PascalCase. Services end `In` (`FailurePoller` and `StatusMonitor` are the exceptions), channel operations end `Out`, and the Workflow operation is `OcuTalonApprovals`.
- **Messages:** extend `Ens.Request` or `Ens.Response`, with plain-English properties. Session-owned messages carry `SessionRef`, items carry `ItemId`. Rules route only on named properties.
- **Enumerations:** defined once in `OcuTalon.Msg.Enum`; `OcuTalon.Bridge.Msg.Enum` copies only the seven the bridge uses (Outcome, Provenance, RequestKind, FallbackReason, ApprovalState, ApprovalKind, Channel), test-pinned equal. Enumeration-typed properties are plain `%String`, never `VALUELIST` copies.
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
- **Times:** UTC ISO 8601 to the second, `YYYY-MM-DDThh:mm:ssZ`, in storage and the API; rendered only through `OcuTalon.Data.Time`.
- **SQL reserved words:** a spine property name that is a reserved word keeps its name and gets an `SqlFieldName` (`Input` → `InputText`, `Count` → `FailureCount`).
- **REST:**
  - Paths `/ocutalon/api/v1/...`, plural nouns, commands as `POST` on a resource (`/approvals/:ref/answer`).
  - Errors are `{"error": {"code", "message"}}` in plain English: 400 `bad_cursor`; 401 `signed_out` (no `WWW-Authenticate`, so browsers never open their own password prompt); 403 `no_role`, `not_json`, `no_request_header`, `wrong_origin`; 404 `not_found`; 405 `method_not_allowed`; 409 (already answered, not available); 429 (allowance, with `retryAt`); 500 `server_error`; 501 `not_built` for routes whose story hasn't shipped.
  - The live-event envelope is `{seq, stream, ts, type, payload}`, with camelCase payload keys.
- **Persistent classes:** every one that isn't a message sets `Parameter DEFAULTGLOBAL = ^OcuTalonP.<Short>` (`^OcuTalonBP.<Short>` in the bridge), with its row in `src/short-names.tsv` (one row per class, union-merged; CI fails on a duplicate). The compiler-generated `Storage` block is committed.
- **Hosts and errors:** hosts log with `$$$LOGINFO`, `$$$LOGWARNING` and `$$$LOGERROR`. `%Status` throughout, `$$$ThrowOnError` inside methods, plain English only at the channel edge. Never read globals directly for settings.
- **Python:** only as `.py` resources under `src/ocutalon/python/`, never `[Language = python]`.
- **Angular:** standalone components and signals, hash routing, one typed API client and one live-event service. Fonts and icons are bundled, never from a CDN, with their licence notices kept.
- **Tests:** `OcuTalon.Test.<Area>.<Subject>`, and Playwright under `web/e2e/` (demo path: `web/e2e/demo-path/`, one spec per UJ-1 step). Mock scenarios are `ci/mock/scenarios/<A|B>/<name>.json`.

### Stack pins

| Component | Pin |
| --- | --- |
| IRIS for Health AI Hub EA (primary) | `irishealth-community:2026.3.0AI.154.0` |
| IRIS non-Health image (via `IRIS_IMAGE`) | `iris-community:2026.3.0AI.154.0` |
| Retag target | `ocutalon-iris-base:2026.3.0AI.154.0` |
| IPM | 0.10.10, from a release file baked into the image |
| Angular and Angular CDK | 22.2.x (CDK plus custom components; no component kit) |
| Icons and fonts | Lucide paths; Inter v4.1, Montserrat v7.222, JetBrains Mono v2.304 woff2; all vendored into `web/` with licences |
| TypeScript | ~6.0.3 |
| Node.js (build and CI only) | 24 LTS |
| Playwright | 1.64.x |
| Default model, every agent | `claude-haiku-5-5` |

### Spikes Epic 0 relies on (done October 17)

- S1, S3, S12, S16, S7 (partial), S14, S2 and S18: their findings are built into the ADs above. S16: a mapping made after a compile hides the public classes, hence the resolution check. S2: no sampling parameters, an 8,000-token cap. S19 (Epic 15): `src/cpf/ocutalon.cpf` differs from `docker/merge.cpf` only by the `%Service_CallIn` and IPM lines.

## UX & Interaction Patterns

- **Built in Story 0.3:** the sign-in page (full logo at 320px above a card titled "Sign in to OcuTalon") and the app header (mark, wordmark, the "Demo mode" badge shown only with demo mode on locally, and the account menu with Sign out). The main page is empty; Story 2.1 lays it out.
- **Texts the public package keeps its own copies of** (0.9's catalog comparison covers them):
  - help line: "Use the IRIS account your install created; the README lists it."
  - wrong credentials: "That user name and password didn't work."
  - missing role (also the API's `no_role` message, `Login.#ERRORNOROLE`): "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it."
  - signed out (the API's 401, in `ApiBase`): "You were signed out. Sign in again to continue."
- **Token stylesheet:** generated from `DESIGN.md`'s front matter, with dark-theme `<name>-dark` tokens. No text under 12px; icons hidden from assistive technology; `prefers-reduced-motion` stops all animation. The sign-in page uses system font stacks (`default-src 'none'` blocks fonts).

## Cross-Story Dependencies

- **Delivered: Story 0.1.**
  - The first `<Version>` of `src/module.xml` is baked into `/opt/ocutalon/version`; `/durable/ocutalon.ready` holds that version, written atomically.
  - `docker/merge.cpf` keeps its database directories relative (for S19).
  - `.dockerignore` is `*` plus an allow-list: every file a later story copies into the image must be added to it.
  - `docker-compose.yml`: `name: ocutalon`, one service `iris` (`pull_policy: build`), `env_file` `.env` with `required: false`, volume `durable:/durable`, `start_period: 600s`.
- **Delivered: Story 0.2.**
  - `docker/after-start.sh` (with `.cos`); `docker-compose.dev.yml` (project `ocutalon-dev`, `OCUTALON_DEV=1`); `src/module.xml` (`ocutalon` 0.1.0) lists `OcuTalon.Bridge.PKG` then `OcuTalon.PKG`.
  - **Step order** (`Registry.Order()`, `OcuTalon.Install.Step.<Area>`; each story fills its own step without re-ordering): 1 `Bridge.Installer` (audit events; 0.6 as needed, then Epic 1); 2 `Public` (online-demo flag; 3.8 adds values); 3 `Roles` and 4 `Users` (built, 0.3); 5 `Web` (built, 0.3; 0.5 added `/ocutalon/public`, the new bundle folder and the old-folder cleanup); 6 `SSL` (stub; first story needing client SSL); 7 `Tasks` (built; 1.11 and later declare); 8 `Demo` (stub; 0.10); 9 `Provider` (stub; 1.1); 10 `Audit` (checks the events, naming a missing or disabled one; 3.7 with DW-10 extends it); 11 `Telegram` (stub; 12.1); 12 `Production` (stub that starts nothing; 0.6); 13 `Reconcile` (built); 14 `PrivateData` (built; `StorageGlobals`); 15 `Ready` (built).
  - Public settings, roles and audit events are structural; tasks are created once. The System Default Settings helper comes with 1.1.
  - **`Data.Public.Settings`:** a fixed key set (the online-demo, reset, proxy and connection keys plus `ready`); any other key is refused. Defaults are the `Public` step's job (3.8).
  - **Tests:** `%UnitTest` classes under `src/ocutalon/cls/OcuTalon/Test/<Area>/`. Bash tests are `docker/tests/test-*.sh`, each runnable alone, exit 0 on success; live ones use `docker/tests/lib-live.sh` (`live_start`: a throwaway project with no keys, cleaned up).
- **Delivered: Story 0.3.**
  - The `ocutalon` account holds all three roles, as seed. The `Roles` step composes the `Users` and `Web` steps' `Grants()`; only `OcuTalonTraceViewer` holds grants directly.
  - **`Step.Web`** builds every application from `Common` plus overrides (`CSPZENEnabled` 1 everywhere: 0 stops signed-in requests reaching the dispatch class on build 154); `/ocutalon` and `/ocutalon/api` share `CookiePath` `/ocutalon/`. `Web.TraceApp(namespace, .props)` returns `/ocutalon/trace/<namespace in lower case>` and its properties; 0.10's `Demo` step and 4.1 use it.
  - **`Shell`** (adapting `%ZHSLIB.REST.AngularHandler` without referencing it, HS-only) renders `Login` without a session and serves only the brand images; signed in it runs `Shell.HasRole()` and serves the bundle. The sign-in POST has no CSRF token (DW-6). Sign out uses `?IRISLogout=end` until 2.2.
  - **`web/`:** `npm --prefix web run build` (`tokens.mjs --check`, `payloads.mjs --check`, `brand.mjs`, `ng build`) writes `src/ocutalon/csp/`, git-ignored on development branches and force-added at release (11.5); the Dockerfile refuses an image without it. IPM's `FileCopy` copies it to the durable `csp/ocutalon-web/` on every load and never prunes stale hashed files. `tokens.mjs` exports `emitOutputs(name, outputs, check)`, the write-or-check routine other generators reuse.
  - **Browser tests:** `web/playwright.config.ts` and `signIn()` in `web/e2e/sign-in/helpers.ts` (0.8 reuses both). `docker/tests/test-sign-in.sh` seeds a live stack and runs the Playwright specs (`LIVE_REBUILD_WEB=1`; port 52800–52819 or `OCUTALON_TEST_WEB_PORT`; Node 24.15+ and Playwright's chromium).
- **Delivered: Story 0.4.** Contract classes with final names, types and storage (properties are in the classes and their oracles):
  - **`OcuTalon.Msg` (Lane B):** `Item`, `ItemDecision`, `Notification`, `Outbound`, `Tick`, `CommandResult` and `Enum`; the abstract `Command` (`Origin`, `IdempotencyKey`, `SessionRef`) with verbs `Command.SetReminder`, `.CancelReminder`, `.ListReminders`, `.Dismiss`, `.StartWatch`, `.StopWatch`, `.SetDemoMode`, `.Pair`, `.Unpair`, `.EndSession`, routed by class (2.3); `IncidentCommand` (`Verb` from `VERBS = "dismiss,closeForReplay,closeQuiet"`, `IncidentRef`). Commands carry no IRIS user (`WatchOps` reads it from `Session`). `CatalogKey` and `Slots` are plain strings.
  - **`OcuTalon.Bridge.Msg` (Lane A):** `Request`, the abstract `Result` with `DecisionResponse` and `Reply`, `DecisionPayload` (`%JSON.Adaptor`), `AgentStep`, `Enum`.
  - **Tables:** Lane B's `Session`, `AddressCounter`, `StatusMark`, `GuideState`, `BreakFeedRun`, `Pairing`, `Turn`, `SimMessage`, `Delivery`, `Reminder`, `Setting`; Lane A's `BackgroundCheck`, `WatchMark`, `Incident` (`FailureCount`), `FailureGroup`, `FixRun`; `Bridge.Data` (Lane A): `Decision`, `ApprovalRequest`, `Usage`, `Price`, `ConversationLink`, `ModelFamily`.
  - **Shapes to follow:** sizes `Ref`/owner 22, `Utc` 20, local time 19, enum words 32, names 128, lines 1000, summaries 80, long text and JSON unlimited; money `%Numeric(SCALE = 6)`, rates `SCALE = 4`, confidence at `SCALE = 2`. Every `%Boolean` has `InitialExpression = 0`. Every table with `Ref` has `Index RefIndex On Ref [ Unique ]`; indexes are `<Property>Index`. Reasons are newline-separated text, a JSON list only in `DecisionPayload`.
  - **Helpers:** `Bridge.Ids.NewRef()`; `Data.Time` (`NowUtc()`, `ToLocal(utc)` giving `""` for a non-`Utc` value, `Zone()`; `FromLocal` in 8.3); `Data.Setting.Get(key, default)`/`Seed(key, value)` (dotted product keys, public keys delegated uncached to `Public.Settings`, per-process 60 s cache); `Bridge.Audit.Events()`/`Write(type, data, description)` (`data` a `%DynamicObject`); `Data.Delivery.Record`/`FindByApproval` (failing stubs until 2.7); `Channel.Telegram.In` (stub service; `Included()` is 0 unless the test global is set).
  - **`src/short-names.tsv`:** `short`, `global`, `class`, `lane`; 23 rows after 0.5's `LiveEvent`; short names unique; a new persistent class adds its row in the same change. `Test.Data.Tables` carries the rows as `Registry` XData (slots can't read the repository).
  - **Test layout:** `Test.Contract` (abstract; `AssertContract` compares XData contracts with the compiled dictionary) and its oracles `Test.Msg.Contracts`, `Test.Bridge.Contracts`, `Test.Data.Tables`. A lane that appends to a contract updates its oracle's XData; the counts (23 registry rows, 23 tables across `Data`, `Live` and `Bridge.Data`, 45 persistent classes) are floors. `docker/tests/test-storage.sh` reads files only; each rule runs first against a bad sample; today a class is storage-bearing when it reaches `%Persistent`, `Ens.Request` or `Ens.Response` (DW-13 widens it in 0.6). `docker/tests/test-audit.sh` (live) polls up to `OCUTALON_AUDIT_POLL` (120 s).
- **Delivered: Story 0.5.**
  - **`OcuTalon.Live.Event`** (`^OcuTalonP.LiveEvent`, row `LiveEvent`, Lane B): `MAXEVENTS = 200`; `Since(stream, after, max, label)` returns one stream's page in `Seq` order.
  - **`OcuTalon.Live.Publish`:** `Publish(stream, type, payload, .seq) As %Status`, where `stream` is a `SessionRef` or `#INSTANCE` (`instance`); call it outside any transaction, after your own commit. `LastSeq(stream)` throws when the lock isn't free in 5 s (a 500, never a wrong cursor). Also `PayloadClass(type)`, `IsStream(stream)`. Not yet in `Publish`: the guide hook (4.2) and the `$SYSTEM.Event` signal (2.11).
  - **Event table** (`Publish.TYPES`, `type:Class` under `OcuTalon.Live.Payload`): Lane B `chat.message:ChatMessage`, `notification:Notification`, `phone:Phone`, `mailbox:Mailbox`, `decision:Decision`, `approval:Approval`, `turn.step:TurnStep`, `reminder:Reminder`, `pairing:Pairing`, `status:Status`, `reset:Reset`, `breakfeed.progress:BreakFeedProgress`, `guide.state:GuideState`; Lane A `incident:Incident`, `watch.progress:WatchProgress` (`STAGES = "noticed,settling,diagnosing"`), `check:Check`.
  - **Payload fields:** the cross-lane payloads (`incident`, `watch.progress`, `check`, and `pairing` for Lane A's later Telegram card) fix every field the spine and consumer stories name; Lane B's own payloads fix their key and the epics' fields, and owner stories append. `Payload.Incident.FromRow(row)` is the one incident builder, for `IncidentManager` (5.4) and `/state` (2.2), so an event and the snapshot can't drift; `/state` lists only noticed incidents, through `Ownership` (AD-15).
  - **Parts** (`Live.Payload.Part.<Name>`, each its payload's lane): `ItemNoun` and `TraceTarget` are shared and Lane B's; the `Incident*` parts are Lane A's; `DryRun` (the keys of `ApprovalRequest.DRYRUNKEYS`) and `StatusSlots` are Lane B's.
  - **Empty values:** `%JSONNULL` 0, so IRIS omits empty strings and lists; every TypeScript field is optional, and a full-view replace treats a missing key as empty.
  - **Generated TypeScript:** `web/scripts/payloads.mjs` writes `web/src/app/live/payloads.ts` from the payload classes and `Publish.TYPES` and enforces the camelCase rule; the build's `--check` makes a payload change regenerate in the same change. `web/src/app/api/api-types.ts` has `LiveItem<T>` (a discriminated union over types), `LiveEnvelope<T>` and `StateSnapshot`.
  - **`OcuTalon.Web.Api`** extends `Web.Public.ApiBase`; the role check runs in `OnPreDispatch` (`Shell.HasRole()`, `Login.#ERRORNOROLE`), the envelope check on every state-changing call (media type and origin compared case-insensitively, a charset allowed; origin = scheme from `%request.Secure` plus `HTTP_HOST`). Its 12 `/v1` routes: `GET /state` and `GET /events` (built); `POST /pairing/code` and `DELETE /pairing` (404 while `Telegram.In.Included()` is 0, else 501; 10.3); and 501 `not_built` for `POST /messages`, `/approvals/:ref/answer`, `/incidents/:ref/dismiss`, `/demo/break-feed`, `/mailbox/incoming`, `/mailbox/samples/:name`, `/guide/markers` and `/session/end`. No WebSocket route (2.11).
  - **`/state`:** `{version, instanceZone, epoch, streams: {session, instance}, chat: [], rail: {approvals: [], checks: [], reminders: [], decisions: []}}`; `streams` holds each `LastSeq`; `version` is the IPM module's `VersionString` (`""` without IPM, as on a slot); `chat` holds `LiveItem`s and `rail`'s arrays are typed by payload, all empty until 2.2.
  - **`/events?after=<sessionSeq>&afterInstance=<instanceSeq>`:** `{epoch, events: [{seq, stream, ts, type, payload}]}`, session events first, then instance, each in `Seq` order, at most 200 per stream. Each cursor is a whole number of 1 to 15 digits, else 400 `bad_cursor`. `epoch` is in every poll (16.4). Rows come through `Live.Event.Since`, not `Ownership`: the stream is the ownership.
  - **`Session.ForUser(irisUser, .sc)`** finds or creates the user's one durable `Session` row, with `Epoch` on the row; 2.2's `SessionEvents` calls it at sign-in. It is the interim DW-15 replaces.
  - **`Web.Public.Status`** and `/ocutalon/public` (`Common` plus `AutheEnabled` 64, empty `GroupById`, `CookiePath` `/ocutalon/public/`, `ServeFiles` 0): `busy` follows AD-13's formula with the stored cap and reserve, false without a valid cap; 16.5 owns the busy header and splash. `Test.Web.Status` scans `Status`'s and `ApiBase`'s sources against AD-3's allow-list.
  - **The page:** `web/src/app/api/api-client.ts` is the one typed client; the app loads `/state` once and sets `main[data-snapshot]` to `loading`, `loaded` or `failed`. The live-event service, error UI and envelope interceptor (DW-14) are 2.2's.
  - **Bundle folder (DW-5, done):** `FileCopy` targets `csp/ocutalon-web/`. `Step.Web.Run` first calls `Prepare(dataDirectory)` (`BundleCheck` of the new folder, then `RemoveOldBundle`), so tests run it on a fixture data directory. `RemoveOldBundle` acts only when `csp/ocutalon/index.html` holds `<base href="/ocutalon/">`, deletes only OcuTalon's own files (and `index.html` last, so an interrupted run repeats), and never the folder itself.
  - **Tests:** `Test.Live.Publish`, `.Payloads`; `Test.Web.Api` (via `Test.Web.StubRequest`), `.Status`; `web/scripts/payloads.test.mjs`; `web/e2e/api/api.spec.ts`, run by `test-sign-in.sh` (which also creates the fixture user `ZzFirstCall`, user role, no session row); `docker/tests/test-bundle-folder.sh` (live, non-Health image: the old `/csp/ocutalon/` files 404 without a session, before and after a restart; the bundle loads through `/ocutalon/` after sign-in). Each probe uses a fresh URL: the web gateway caches answers, 404s included.
  - **Owner veto window (Rule 22.3), open:** the envelope and no-role rules, `/ocutalon/public`, API-created `Session` rows, old-bundle deletion, the API's error texts, `ApiBase` in the public database, the unchecked-privilege queries.
- **Developer slots:** `ocutalon-slot-a` and `-b` run 0.1's `merge.cpf` on the base image without the after-start script: code goes in through the IRIS MCP tools, installer steps run explicitly, and IRIS can't read the repository. The after-start install and destructive tests run only in throwaway compose stacks and CI.
- **0.6 (next; its demo-mode group moved to 0.10):**
  - **DW-13 (routed here):** `docker/tests/test-storage.sh` treats every persistent root this story's classes extend (`Ens.BusinessProcess`, `Ens.MessageBody`, `Ens.StreamContainer`, besides `%Persistent`, `Ens.Request`, `Ens.Response`) as a storage root, exempts the message and business-process extents from `DEFAULTGLOBAL` as AD-3 does, and has a bad sample for each.
  - The items use 0.4's messages; `TelegramIn` reuses `Channel.Telegram.In`; `Commands.Submit` sends the `Command` subclasses.
  - Its stub items are 0.5's publishers-to-be (through `Live.Publish`, outside a transaction). `Data.Ownership` (`TurnCost`, `RunCost`) is among its stubbed signatures; it doesn't replace `Session.ForUser` yet (2.2).
  - Its constants (`MOCKKEY`, tool names, compaction prefix) are what 0.7's mock keys on.
- **0.7 and CI:**
  - 0.7's checks gate everything above. The CI override extends 0.1's compose file. CI runs `docker/tests/test-*.sh` (the live ones, `test-audit.sh`, `test-sign-in.sh` and `test-bundle-folder.sh` among them, on the IRIS runner), the `%UnitTest` shards, the public-package and `^OcuTalonPublic` checks (allow-list over `Shell`, `Login`, `SignInAssets`, `Status`, `ApiBase`), and the registry and storage checks (`src/short-names.tsv`, `test-storage.sh`).
  - **DW-11:** the IRIS checks job also runs the load, compile and export round trip over every persistent class, failing when a compiled `Storage` block differs from its committed file (AD-5).
  - CI also runs the web build (with `tokens --check` and `payloads --check`) and `node --test` (with `payloads.test.mjs`).
  - 0.7 also updates `_bmad/custom/skill-rules.md` (IRIS test recipe, shard command, timings) and `_bmad/custom/parallel.yaml` (bootstrap with `web/`'s dependencies, runtime locks).
  - CI must run on `feature/OCT_OcuTalon_MVP` and `OCT-epic*` with no `cancel-in-progress`.
- **0.8:** runs in 0.7's IRIS job; reuses 0.3's `playwright.config.ts` and `signIn()`, and waits for 0.5's `main[data-snapshot=loaded]`.
- **0.9 (Lane B's after):**
  - `OcuTalon.Msg.Catalog.Core` and `.Watch` with every release-1 and 0.1.1 key, including those 0.4's `CatalogKey` and `Slots` name on `Item`, `ItemDecision`, `Notification` and `Outbound`.
  - `Catalog.Render(key, slots, channel)` on 0.4's `Data.Time`, tested on every key and channel.
  - The test comparing the public package's text copies (`Login`'s, and `ApiBase`'s 401 text) with the catalog.
  - **DW-12:** Task 0 measures, on a throwaway stack started with a compose-level `TZ`, whether a production job's `Data.Time.ToLocal` and `Zone()` use the container's zone; if not, the renderer passes the instance zone explicitly (AD-18). It needs only 0.6's production jobs, not 0.10.
- **0.10 (last story of Epic 0):**
  - Fills step 8, `Install.Step.Demo`, which reads demo mode through `Setting.Get` and its seed. Demo mode on: OCUORDERS (code and data databases, mappings), `OcuTalon.Demo.Orders.Production` running there (message classes, a partner service, the real transform failing on the changed date format) and the OCUORDERS trace application through `Web.TraceApp("OCUORDERS")`. Off: no OCUORDERS.
  - `eval/` gets one recorded failure snapshot of a date-format batch, which Lane A's watch and diagnosis tests use until Epic 9.
- **Epic 0's handoffs to Story 2.2 (outside Epic 0; not built here):**
  - **DW-14:** `ApiClient` sends the browser envelope on every state-changing call (an interceptor adds `Content-Type: application/json` and `X-OcuTalon-Request: 1`), starting with `POST /api/v1/session/end`, with a test of the server's 403s without it.
  - **DW-15:** `/state` and `/events` resolve the caller's session through `Data.Ownership` from the CSP session, replacing `Session.ForUser($Username)`, so two visitors on one shared account never see each other's events.
  - Also 2.2's: filling `chat` and `rail`, the client's live-event service, `SessionEvents` calling `ForUser`, Sign out through the API, and the purge (rows only, never the counter).
- **Epic 10:** `install.sh` uses `IRIS_IMAGE` and refuses Compose older than 2.24 (`env_file` `required: false`); 10.2's README states that minimum, the LAN-exposure warning, the password change and the IPM licence notice.
- **Later epics:** Epic 1 (Lane A) and Epic 2 (Lane B) both start from Epic 0 and test against its stubs and the mock. Epic 15 derives `src/cpf/ocutalon.cpf` from `docker/merge.cpf` and calls `Registry.Run("ipm")`. Owners of the stubs and hand-offs:
  - Epic 1: `Decide` on 0.4's `Request`, `Reply.NewBusy`, `DecisionResponse`, `Decision`, `Usage`, `Price`, `ModelFamily` and `ConversationLink`; the `lane-a.yml` bridge job (1.3), `Bridge.Time` (1.4), `Digest.Data.Item` (1.12)
  - Epic 2: header, theme, badge and About (2.1); 2.2 as above; command routing (2.3); `Allowance` (2.4); the publishers of their types (2.4–2.10); `BridgeSink` and the decision payload (2.6); `Delivery` (2.7); `Trace.Join` and trace URLs (2.9); the WebSocket and `Publish`'s signal (2.11)
  - Epic 3: `Bridge.Approval`; OCUORDERS grants (3.1); audit shapes, redaction and read-back (3.7, with DW-10's warning when instance-wide auditing is off); online-demo public keys (3.8)
  - demo-mode switching (4.1); `Publish`'s guide hook and `GuideState`'s fields (4.2)
  - Epics 5 to 7: `Incident`, `FailureGroup`, `FixRun`, `BackgroundCheck`, `WatchMark`; the `incident` payload's builder and parts, `WatchProgress` and `Check` (5.3–5.6, 6.1); `Checks.Render` (Epic 5); `ReplyGuard` (5.7)
  - `Reminder`, its payload and `Data.Time.FromLocal`: 8.3
  - the pairing routes, the `pairing` payload, `Pairing`'s code fields and `Included()`: 10.3; `Pairing`, `StatusMark` and the Telegram items: Epic 12
  - the origin check's forwarded scheme (16.3); epoch changes and online-demo timeouts (16.4); the login splash and busy state on `/ocutalon/public/status` (16.2, 16.5, 16.8)
