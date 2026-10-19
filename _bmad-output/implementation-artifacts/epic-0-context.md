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
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production (done)
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock (the mock itself moved to 0.11)
- Story 0.8: The demo-path test signs in and loads the page
- Story 0.9: The message catalog and its one renderer
- Story 0.10: The Orders demo production runs in OCUORDERS
- Story 0.11: The CI model mock answers every scenario the stories need (last story of Epic 0)

## Requirements & Constraints

- **Install:** after a load and retag, a plain `docker compose up` gives a working install. The first start creates OCUTALON with Interoperability and its own databases. Later starts reapply the same configuration with no errors and no data loss. In demo mode (the Docker default), the Orders production runs in its own namespace, OCUORDERS.
- **Roles and sign-in:** the install creates the user, admin and trace roles. The README account (`ocutalon`/`ocutalon`) has a non-expiring password and no forced change, and the README says how to change it. No page or API answers without a session, except the login page (with its images) and `/ocutalon/public/status`.
- **Secrets:** model keys and bot tokens come only from environment variables. `.env` is git-ignored, and `.env.example` lists `ANTHROPIC_API_KEY` and `TELEGRAM_BOT_TOKEN` with no values. No key appears in logs, traces, audit entries or the repository.
- **Image and registry:** the AI Hub image, or any image built on it, is never pushed and never enters a CI cache or artifact. CI fails on any `docker push` or registry sign-in. The judges' compose file has no mock service.
- **Tracked files:** no tracked file holds a local machine path or a key-like string, and a CI check enforces this.
- **CI:** a full run takes at most 30 minutes. IRIS tests run on the dedicated self-hosted runner, everything else on paid hosted runners (cache npm; skip a job's own steps, never the workflow, when a push changes nothing it checks). Fork pull requests never reach the IRIS runner. The demo-path browser test runs on every pull request and every push to `main`, and a failure blocks the merge. `main` moves only through a release pull request.
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
  - `src/bridge/` also loads alone with `$SYSTEM.OBJ.LoadDir` into a namespace with Interoperability, and `OcuTalon.Bridge.Installer` sets it up; without Interoperability only `Bridge/Installer.cls` loads, and it refuses, naming the namespace.
  - CI fails if any `OcuTalon.Bridge` class references another `OcuTalon` package, or if any class outside `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Docs`, `.Memory`, `.Mcp`, `.Install` and `.Test` (whole package names) references `%AI` or `EnsLib.AI`. A load can't prove the first rule (the compiler accepts a call to a missing class), so its pin is a source scan.
  - `OwnerRef` is exactly a `SessionRef`, `instance` or `eval`.
- **AD-3 (namespaces and databases):**
  - OCUTALON has code, data, private and public (`OCUTALON_PUBLIC`, public Read) databases.
  - The public database holds only `OcuTalon.Web.Public` (`Login`, `Status`, the `/ocutalon` dispatch class `Shell`, the generated `SignInAssets`, and `ApiBase`, the API's answer before sign-in), `OcuTalon.Data.Public` and `^OcuTalonPublic`: a request without a session can't read the code database.
  - Those packages may reference only `%CSP` (including `%CSP.REST`), dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (only in a compile-time generator) and each other. They keep their own copies of the UX texts they render, compared with the catalog by a test (0.9).
  - Global mappings put `OcuTalonP.*` and `OcuTalonBP.*` (with the dot, so `^OcuTalonPublic` stays public), `^AI.Agent.Session*` and `^IRIS.IF.*` in the private database. The databases and mappings exist before any class compiles.
  - Business processes store in `Ens.BusinessProcess`'s own extent, so they set no `DEFAULTGLOBAL`, and keep no private text in their properties; anything private goes in a private table.
  - `OcuTalon.Production` is not autostart on Docker.
  - Only `OcuTalon.Install.*`, `OcuTalon.Bridge.Installer` (to `%SYS`, in its one method) and `Install.Step.Demo` (to OCUORDERS) switch namespace in product code, each in one method with `New $NAMESPACE`. Test classes also switch to `%SYS` for fixtures (accepted, DW-7).
  - On the non-Health image, `Interop=1` only enables Interoperability: no Foundation production, and the default web application is `/csp/<ns>`. Nothing may depend on either.
- **AD-5 (durable state):** all state lives on the durable volume, and an install replaces only code. Storage is append-only, and every such class's source carries its compiler-generated `Storage` block, never edited by hand. The production class holds structure only; values go in System Default Settings, bridge tables or `OcuTalon.Data.Setting`.
- **AD-19 (configuration homes):**
  - Model keys and bot tokens are environment-only (`@{env:VAR}` or `$SYSTEM.Util.GetEnviron`). Endpoint overrides `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_EXTRA_CA_FILE` and `OCUTALON_TELEGRAM_API_BASE` are set only by the CI override and the online demo.
  - The installer marks every value it writes `structural` (rewritten every start) or `seed` (written only when absent).
  - `OcuTalon.Data.Public.Settings` is the only reader and writer of `^OcuTalonPublic`; CI fails on any other reference. `OcuTalon.Data.Setting.Get` serves product values through a 60-second cache.
- **AD-23 (image and installer):**
  - **Image:** one Dockerfile, `FROM ocutalon-iris-base:2026.3.0AI.154.0`, mount directory owned by UID 51773. Every compose file sets its own top-level `name:`; the IRIS service sets `stop_grace_period: 60s`. The judges' compose file publishes only `${OCUTALON_WEB_PORT:-52773}`.
  - **The CPF merge** (`docker/merge.cpf`) creates the databases, namespace and mappings and enables `%Service_CallIn`, idempotently; the after-start script re-runs it every start, which also repairs a mapping removed by hand.
  - **The after-start script** (OS authentication) re-merges, installs IPM 0.10.10 into `%SYS` (mapped into OCUTALON only), checks that the public classes resolve to `OCUTALON_PUBLIC`, loads the package version-gated (`OCUTALON_DEV=1` reloads every time), runs the registry's steps and writes the ready marker atomically. It always exits 0; a failure writes no marker. It logs `STEP <name> OK|FAILED` and `RESULT OK <version>` to `/durable/ocutalon-after-start.log`.
  - **The health check** opens no IRIS session: `^running` in `iris qlist` and the marker equal to the image's version; `start_period` at least 10 minutes. Check the version inside the built image (a cached build context can bake in stale sources).
  - **Static web files** go in the durable data directory's `csp/ocutalon-web/`, never `csp/ocutalon/`, which the non-Health image's `/csp/ocutalon` serves without sign-in. Every start ends by confirming the private globals resolve to the private database.
  - **Step registry:** every step extends `OcuTalon.Install.Step`; `OcuTalon.Install.Registry` runs the fixed order, and a step class outside it only declares. Areas declare `Grants()` (`{"role","resource","permission"}`; empty `resource` declares the role alone), `Reconcile()`, `Tasks()` (`{"name","taskClass","description","task":{...},"settings":{...}}`) and `Purge(daysToKeep)`. Role and task names start with `OcuTalon`. Tasks are created once. An IPM install calls `Registry.Run("ipm")`.
  - **The `Production` step** (built in 0.6) is described under "Delivered: Story 0.6".
- **AD-13 (web applications, sign-in and the envelope):**
  - **One sign-in group** (`GroupById` `OcuTalon`, password authentication): `/ocutalon` (dispatch `OcuTalon.Web.Public.Shell`), `/ocutalon/api` (`OcuTalon.Web.Api`, `/v1`, sharing `/ocutalon`'s CSP session, no CORS) and the trace applications. `OcuTalonUser` holds no database resources directly; the applications grant them as application roles.
  - **`/ocutalon/public`** is unauthenticated and outside the group. It serves only `GET /status` from `OcuTalon.Web.Public.Status`, reads only the public settings, and always returns every key, `null` when unset: `{ready, nextReset, busy, lastReset, lastResetKind}`.
  - **Before and after sign-in:** `Api` extends `OcuTalon.Web.Public.ApiBase`, which answers a request without a session with 401 `signed_out`. A signed-in user without the user role gets 403 `no_role` and keeps the session, so a trace-only user stays signed in to the trace windows.
  - **SQL privilege:** `OcuTalonUser` holds no SQL grant on OcuTalon's tables, so the API's own queries over the signed-in user's rows are prepared without the privilege check (`%Prepare(text, 0)`), with fixed texts and every input a parameter; ownership is enforced in the queries. Don't grant `SELECT` to a role instead. Only `Session.ForUser`'s and `Live.Event`'s queries do this today; 0.7 enforces that allow-list (DW-17).
  - **Session lookup, Epic 0 interim:** until 2.2 builds `OcuTalon.Data.Ownership`, `/state` and `/events` find the caller's session by user name (`Session.ForUser`); 2.2 switches them to Ownership (DW-15).
  - **Login page** `OcuTalon.Web.Public.Login` (`%CSP.Login`, no Angular) loads nothing from an authenticated path and sends a hash-pinned `default-src 'none'` policy; the page sends `script-src 'self'`.
  - **The browser envelope:** every state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, or it gets a 403. GET, HEAD and OPTIONS are exempt.
- **AD-24 (roles and trace applications):**
  - The roles are `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`. The trace role holds only Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`; Read on the data and code databases (never the private ones); SQL `SELECT` on `Ens.MessageHeader`.
  - The trace applications `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` have no application roles and exactly seven permitted classes (`%CSP.Broker` and six `EnsPortal` trace and message-viewer pages, as `Web.TraceApp` sets them). The OCUORDERS application and grants exist only with demo mode on.
  - No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun` or `%Ens_ProductionConfig`. No `OcuTalon.Data` or `OcuTalon.Bridge.Data` class extends a message base.
- **AD-12 (live events):**
  - Rows are written only through `Live.Publish`, after the publisher's own change has committed, never inside a transaction. Only event-table types are accepted, each with exactly one publisher. `Seq` comes from a per-stream counter the purge never deletes, so a page's cursor stays valid.
  - The browser envelope labels the stream `session` or `instance`, never the stored `SessionRef`. Row ids never leave the server.
  - A payload is the full current public view of one entity, keyed by `Ref`, never a delta: a `%JSON.Adaptor` class `OcuTalon.Live.Payload.<Type>` owned by the publisher's lane, nested shapes under `OcuTalon.Live.Payload.Part`, JSON keys camelCase.
  - Trace targets are `TraceHeaderId` and `TraceNamespace` (the URL is the web layer's). Polling is the release-1 contract.
  - Status conditions are a closed catalog: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`.
- **Contract semantics fixed in Epic 0:**
  - **`Commands.Submit` (AD-1):** the only way to submit a command. It validates the caller's origin against the enumeration, overwrites the payload's `Origin` with it (or with `tool` while a bridge context is active), and sends to `CommandsIn`; role checks stay with the admin-checked endpoints and `CommandsIn`. Origins: `web_user`, `web_admin`, `telegram`, `tool`, `timer`, `system`.
  - **`Reply.Busy` (AD-6):** set when `Decide` refused a `turn` after a 2-second lock wait; the `Reply` carries no text and no decision (`Reply.NewBusy()`), and busy is never an error status.
  - **`Decision` (AD-20):** unique on (`ItemId`, `Kind`).
  - **Time (AD-18):** `OcuTalon.Data.Time` is the only converter outside the bridge, `OcuTalon.Bridge.Time` (1.4) the only one inside it.
  - **Audit (AD-17):** `OcuTalon.Bridge.Audit` is the only audit writer, its events registered by `Bridge.Installer` each start and checked by the `Audit` step. OcuTalon never changes instance-wide auditing. Tests poll the audit log with a timeout (rows appear 53 to 72 s late).
  - **Extension bases (AD-31):** the bridge wraps every `OnEvent` call and never fails its caller. `Decide` runs `ReplyFilterClass` before recording anything. The bridge reads the three settings only through `Bridge.Ext.Accessor.ClassFor`, which errors rather than falling back silently.
  - **Rendering (AD-32):** producers never render text. Only `*Out` operations render, through `Catalog.Render` (0.9), which uses `Data.Time`.
- **AD-22 (testing and CI):**
  - `%UnitTest` classes live in `OcuTalon.Test.<Area>`, sharded by area, one compose project per shard, on the self-hosted IRIS runner; web and mock code runs on hosted runners.
  - **The CI-only compose override** (0.7) extends 0.1's compose file and passes `OCUTALON_EVAL` through from the job's environment (default 0); only Lane A's evaluation job sets 1. 0.11 adds the one mock service to it.
  - **The mock (0.11)** is reached through the Anthropic provider's `base_url` over plain HTTP on the compose network, with no private CA or host alias. It answers `POST /v1/messages` and `GET /v1/models/<id>` (AI Hub's lookup when an agent starts), and rejects `temperature`, `top_p`, `top_k` and output caps under 4,000.
  - **Scenario choice, in order:** a `[[mock:<name>]]` marker in the newest user message with text; a guide prompt's exact text contained in the message (not at its start: the `Agent.Input` preamble comes first); then the agent's `MOCKKEY`. Never by prompt wording.
  - **Summaries:** recognised by `OCUTALON-COMPACTION-V1` at the start of the `system` text, so markers quoted in a summarized transcript don't fire again; answered in AI Hub's summary schema with `facts_learned` and at least one `tool_actions` entry; one scenario answers off-schema.
  - **Logs and state:** header names and key length only; its only state is a per-test retry countdown set through a control endpoint.
  - **Scenario files:** `ci/mock/scenarios/<A|B>/<name>.json` with `name`, `match` (`marker`, `prompt` or `mockkey`; `telegram` from 10.3) and `replies` (each `status`, `headers`, `delayMs`, `stopReason`, and `text`, `toolUse` or `body`). Lane A adds only files under `A/`; new mock behaviour is Lane B's, asked for under AD-33.
  - CI and scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format` (both print `env_file` values).

### Cross-lane contract obligations (AD-29, AD-33)

- **Contracts before code:** every release-1 contract gets its final names and types: properties, enumerations and storage. Cross-lane APIs are signatures with stub bodies. Fully implemented in Epic 0: `Commands.Submit` (0.6), `Data.Public.Settings` (0.2), 0.4's helpers, 0.5's live-event store and API skeleton, and `Msg.Catalog.Render` (0.9). The owning lane appends the rest.
- **Catalog (0.9):** every release-1 and 0.1.1 key, in `OcuTalon.Msg.Catalog.Core` (Lane B) or `.Watch` (Lane A). The item noun slot is `itemNoun: {"one", "other"}`.
- **One owner each:** after Epic 0, each item, class, table and event type has one owning lane, and only that lane edits it. The other lane asks, and the owner appends. A new item, table or event type is added to the ownership tables in the same change.
- **Lane A owns:** `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, `.Eval`, `.Channel.Telegram` (moved October 17) and `eval/`; the installer core (the registry, `docker/merge.cpf`, and the role, user, SSL, task, `Production` and `Public` steps); `ci/mock/scenarios/A/`; `release/`; and `.github/workflows/lane-a.yml`.
- **Lane B owns:** `OcuTalon.Web` (with `.Web.Public`), the rest of `.Channel`, `.Core`, `.Schedule`, `.Demo`, `.Live`, `.Msg`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership` and `.Data.Public`; `web/`, the rest of `docker/` and `ci/` (the mock included), and `.github/workflows/ci.yml`; and the `Web` and `Demo` installer steps.
- **By area:** `OcuTalon.Test.<Area>`, `OcuTalon.Install.Step.<Area>` and `OcuTalon.Live.Payload.<Type>` (with its parts) follow their area's or publisher's lane.
- **Table owners:** Lane B: `Session`, `AddressCounter`, `StatusMark`, `GuideState`, `BreakFeedRun`, `Pairing`, `Turn`, `SimMessage`, `Delivery`, `Reminder`, `Setting` and `Live.Event`. Lane A: `BackgroundCheck`, `WatchMark`, `Incident`, `FailureGroup`, `FixRun`, `Digest.Data.Item` and every `Bridge.Data` class (`Decision`, `ApprovalRequest`, `Usage`, `Price`, `ConversationLink`, `ModelFamily`).
- **Production class:** one `ProductionDefinition` XData block, each lane's items between `<!-- lane A: begin -->`/`<!-- lane A: end -->` (the same for lane B). Every item is enabled except `TelegramIn` and `TelegramOut` (off until a release includes Telegram) and `EvalIn` (only with `OCUTALON_EVAL=1`). Unbuilt items answer "not implemented" and carry `STUB = 1`. Before a release cut, the owning lane disables, in its own region, any item whose story hasn't merged; 11.5 refuses an enabled stub.
- **`Decide` settings in Lane A's region:** `HostSinkClass` = `OcuTalon.Core.BridgeSink`, `ReplyFilterClass` = `OcuTalon.Checks.ReplyGuard`; `ClassificationClass` keeps the default until step 4.
- **HostSink payloads:** `decision.*` and `approval.*` carry `{ref}`, the record's public `Ref`; `turn.step` carries `{decisionRef, label}`, with the session as `ownerRef`; `budget.capped` has `ownerRef` `instance` and payload `{day}` (`YYYY-MM-DD`, instance zone).
- **Test-only global:** `^OcuTalonTest("TelegramIncluded")` is set only by `OcuTalon.Test` classes and never exists in the judges' install.

### Naming and storage conventions

- **Classes:** `OcuTalon.<Area>.<Name>`, one class per file. Cross-lane contracts go in `OcuTalon.Msg`/`OcuTalon.Data`, bridge contracts in `OcuTalon.Bridge.Msg`/`.Data`. Nothing under a system package name; `irislib/` and `irissys/` are read-only references, never loaded.
- **Item names:** PascalCase. Services end `In` (`FailurePoller` and `StatusMonitor` are the exceptions), channel operations end `Out`, and the Workflow operation is `OcuTalonApprovals`.
- **Messages:** extend `Ens.Request` or `Ens.Response`, with plain-English properties. Session-owned messages carry `SessionRef`, items carry `ItemId`. Rules route only on named properties.
- **Enumerations:** defined once in `OcuTalon.Msg.Enum`; `OcuTalon.Bridge.Msg.Enum` copies only the seven the bridge uses (Outcome, Provenance, RequestKind, FallbackReason, ApprovalState, ApprovalKind, Channel), test-pinned equal. Enumeration-typed properties are plain `%String`, never `VALUELIST` copies.
  - Outcome: `ignore, digest, tellnow, act`; Provenance: `user, untrusted`; RequestKind: `decide, diagnose, turn, tool`
  - FallbackReason: `no_key, daily_cap, budget, too_large, timeout, rate_limited, error, refusal, cut_off, empty, invalid, unusable`
  - IncidentState: `open, awaiting_approval, fixing, resolved, closed`; IncidentOpenVariant: `fallback, no_fix, rejected, expired`
  - ApprovalState: `pending, approved, rejected, expired, cancelled, executing, done, failed`; ApprovalKind: `fix, tool_call`
  - NotificationKind: `tellnow, incident, approval, answered, result, reminder, fallback, allowance, pairing, status, digest`
  - CheckResult: `passed, failed, not_checked`; Channel: `web, phone, mailbox, telegram, email, webhook, slack, system`; Origin: as in AD-1.
- **Identifiers:** every `Ref` (and `ItemId`, `SessionRef`, `TraceRef`) is a 22-character base64url string with no padding, from `OcuTalon.Bridge.Ids.NewRef()`. Row ids never leave the server; `Ens` header and session ids may, for trace links.
- **Times:** UTC ISO 8601 to the second, `YYYY-MM-DDThh:mm:ssZ`, in storage and the API; rendered only through `OcuTalon.Data.Time`.
- **SQL reserved words:** a spine property name that is a reserved word keeps its name and gets an `SqlFieldName` (`Input` → `InputText`, `Count` → `FailureCount`).
- **REST:**
  - Paths `/ocutalon/api/v1/...`, plural nouns, commands as `POST` on a resource (`/approvals/:ref/answer`).
  - Errors are `{"error": {"code", "message"}}` in plain English: 400 `bad_cursor`; 401 `signed_out` (no `WWW-Authenticate`); 403 `no_role`, `not_json`, `no_request_header`, `wrong_origin`; 404 `not_found`; 405 `method_not_allowed`; 409 (already answered, not available); 429 (allowance, with `retryAt`); 500 `server_error`; 501 `not_built` for routes whose story hasn't shipped.
  - The live-event envelope is `{seq, stream, ts, type, payload}`, with camelCase payload keys.
- **Persistent classes:** every one that isn't a message or a business process sets `Parameter DEFAULTGLOBAL = ^OcuTalonP.<Short>` (`^OcuTalonBP.<Short>` in the bridge), with its row in `src/short-names.tsv` (one row per class, union-merged; CI fails on a duplicate). The compiler-generated `Storage` block is committed.
- **Hosts and errors:** hosts log with `$$$LOGINFO`, `$$$LOGWARNING` and `$$$LOGERROR`. `%Status` throughout, `$$$ThrowOnError` inside methods, plain English only at the channel edge. Never read globals directly for settings.
- **Python:** only as `.py` resources under `src/ocutalon/python/`, never `[Language = python]`.
- **Angular:** standalone components and signals, hash routing, one typed API client and one live-event service; fonts and icons bundled with their licences, never from a CDN.
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

- S1, S3, S12, S16, S7 (partial), S14, S2 and S18: their findings are built into the ADs above. S16: a mapping made after a compile hides the public classes, hence the resolution check. S2: no sampling parameters, an 8,000-token cap. S18: the compaction prompt's schema text. S19 (Epic 15): `src/cpf/ocutalon.cpf` differs from `docker/merge.cpf` only by the `%Service_CallIn` and IPM lines.

## UX & Interaction Patterns

- **Built in Story 0.3:** the sign-in page (full logo at 320px above a card titled "Sign in to OcuTalon") and the app header (mark, wordmark, the "Demo mode" badge shown only with demo mode on locally, and the account menu with Sign out). The main page is empty; Story 2.1 lays it out.
- **Texts the public package keeps its own copies of** (0.9's catalog comparison covers them):
  - help line: "Use the IRIS account your install created; the README lists it."
  - wrong credentials: "That user name and password didn't work."
  - missing role (also the API's `no_role` message, `Login.#ERRORNOROLE`): "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it."
  - signed out (the API's 401, in `ApiBase`): "You were signed out. Sign in again to continue."
- **Token stylesheet:** generated from `DESIGN.md`'s front matter, with `<name>-dark` tokens. No text under 12px; icons hidden from assistive technology; `prefers-reduced-motion` stops all animation. The sign-in page uses system fonts.

## Cross-Story Dependencies

- **Delivered: Story 0.1.**
  - The first `<Version>` of `src/module.xml` is baked into `/opt/ocutalon/version`; `/durable/ocutalon.ready` holds that version, written atomically.
  - `docker/merge.cpf` keeps its database directories relative (for S19).
  - `.dockerignore` is `*` plus an allow-list: every file a later story copies into the image must be added to it.
  - `docker-compose.yml`: `name: ocutalon`, one service `iris` (`pull_policy: build`), `env_file` `.env` with `required: false`, volume `durable:/durable`, `start_period: 600s`.
- **Delivered: Story 0.2.**
  - `docker/after-start.sh` (with `.cos`); `docker-compose.dev.yml` (project `ocutalon-dev`, `OCUTALON_DEV=1`); `src/module.xml` (`ocutalon` 0.1.0) lists `OcuTalon.Bridge.PKG` then `OcuTalon.PKG`.
  - **Step order** (`Registry.Order()`, `OcuTalon.Install.Step.<Area>`; each story fills its own step without re-ordering): 1 `Bridge.Installer`; 2 `Public` (3.8 adds values); 3 `Roles`, 4 `Users`, 5 `Web` (built); 6 `SSL` (stub; first story needing client SSL); 7 `Tasks` (built; 1.11 and later declare); 8 `Demo` (stub; 0.10); 9 `Provider` (stub; 1.1); 10 `Audit` (3.7 with DW-10 extends it); 11 `Telegram` (stub; 12.1); 12 `Production` (built, 0.6); 13 `Reconcile`, 14 `PrivateData` and 15 `Ready` (built).
  - Public settings, roles and audit events are structural; tasks are created once. The System Default Settings helper comes with 1.1.
  - **`Data.Public.Settings`:** a fixed key set (the online-demo, reset, proxy and connection keys plus `ready`); any other key is refused.
  - **Tests:** `%UnitTest` classes under `src/ocutalon/cls/OcuTalon/Test/<Area>/`. Bash tests are `docker/tests/test-*.sh`, each runnable alone, exit 0 on success; live ones use `docker/tests/lib-live.sh` (`live_start`: a throwaway project with no keys, cleaned up).
- **Delivered: Story 0.3.**
  - The `ocutalon` account holds all three roles, as seed. The `Roles` step composes the `Users` and `Web` steps' `Grants()`.
  - `Web.TraceApp(namespace, .props)` returns `/ocutalon/trace/<namespace in lower case>` and its properties; 0.10's `Demo` step and 4.1 use it. Sign out uses `?IRISLogout=end` until 2.2. The sign-in POST has no CSRF token (DW-6).
  - **`web/`:** `npm --prefix web run build` (`tokens.mjs --check`, `payloads.mjs --check`, `brand.mjs`, `ng build`) writes `src/ocutalon/csp/`, git-ignored on development branches and force-added at release (11.5); the Dockerfile refuses an image without it. Generators reuse `tokens.mjs`'s `emitOutputs` (write or check).
  - **Browser tests:** `web/playwright.config.ts` and `signIn()` in `web/e2e/sign-in/helpers.ts` (0.8 reuses both). `docker/tests/test-sign-in.sh` seeds a live stack and runs the Playwright specs (`LIVE_REBUILD_WEB=1`; port 52800–52819 or `OCUTALON_TEST_WEB_PORT`; Node 24.15+ and Playwright's chromium).
- **Delivered: Story 0.4.** Contract classes with final names, types and storage (properties are in the classes and their oracles):
  - **`OcuTalon.Msg` (Lane B):** `Item`, `ItemDecision`, `Notification`, `Outbound`, `Tick`, `CommandResult` and `Enum`; the abstract `Command` (`Origin`, `IdempotencyKey`, `SessionRef`) with one subclass per verb, routed by class (2.3); `IncidentCommand` (`Verb`: `dismiss`, `closeForReplay`, `closeQuiet`). Commands carry no IRIS user.
  - **`OcuTalon.Bridge.Msg` (Lane A):** `Request`, the abstract `Result` with `DecisionResponse` and `Reply`, `DecisionPayload` (`%JSON.Adaptor`), `AgentStep`, `Enum`. The tables are those of "Table owners" above.
  - **Shapes to follow:** sizes `Ref`/owner 22, `Utc` 20, local time 19, enum words 32, names 128, lines 1000, summaries 80, long text and JSON unlimited; money `%Numeric(SCALE = 6)`, rates `SCALE = 4`, confidence `SCALE = 2`. Every `%Boolean` has `InitialExpression = 0`. Every table with `Ref` has `Index RefIndex On Ref [ Unique ]`; indexes are `<Property>Index`. Reasons are newline-separated text, a JSON list only in `DecisionPayload`.
  - **Helpers:** `Bridge.Ids.NewRef()`; `Data.Time` (`NowUtc()`, `ToLocal(utc)` giving `""` for a non-`Utc` value, `Zone()`; `FromLocal` in 8.3); `Data.Setting.Get(key, default)`/`Seed(key, value)`; `Bridge.Audit.Events()`/`Write(type, data, description)`; `Data.Delivery.Record`/`FindByApproval` (failing stubs until 2.7); `Channel.Telegram.In` (stub; `Included()` is 0 unless the test global is set).
  - **`src/short-names.tsv`:** `short`, `global`, `class`, `lane`; 23 rows (0.6 added none); a new persistent class adds its row in the same change, and `Test.Data.Tables`'s `Registry` XData with it (slots can't read the repository).
  - **Oracles:** `Test.Contract` (`AssertContract`) with `Test.Msg.Contracts`, `Test.Bridge.Contracts`, `Test.Data.Tables` and `Test.Contract.Ac`; a lane that appends to a contract updates its oracle, and the counts are floors. `test-storage.sh` reads files only, each rule first run on a bad sample. `test-audit.sh` (live) polls up to `OCUTALON_AUDIT_POLL` (120 s).
- **Delivered: Story 0.5.**
  - **`OcuTalon.Live.Publish`:** `Publish(stream, type, payload, .seq) As %Status` (`stream` a `SessionRef` or `#INSTANCE`), outside any transaction, after your own commit; `LastSeq(stream)` throws when the lock isn't free in 5 s. `Live.Event.Since(stream, after, max, label)` pages one stream (`MAXEVENTS = 200`). Not yet in `Publish`: the guide hook (4.2) and the `$SYSTEM.Event` signal (2.11).
  - **Event table** (`Publish.TYPES`): 16 types; Lane A owns `incident`, `watch.progress` and `check`, Lane B the rest. `Payload.Incident.FromRow(row)` is the one incident builder. `%JSONNULL` 0: a missing key means empty.
  - **Generated TypeScript:** `web/scripts/payloads.mjs` writes `web/src/app/live/payloads.ts`; the build's `--check` forces regeneration with any payload change.
  - **`OcuTalon.Web.Api`'s 12 `/v1` routes:** `GET /state` and `GET /events?after=&afterInstance=` are built; the pairing routes answer 404 while `Included()` is 0; the other eight answer 501 `not_built`. `/state`'s `chat` and `rail` stay empty until 2.2.
  - **`Session.ForUser(irisUser, .sc)`** finds or creates the user's one durable `Session` row (the interim DW-15 replaces). `Test.Web.Status` scans `Status`'s and `ApiBase`'s sources against AD-3's allow-list.
  - **The page:** `web/src/app/api/api-client.ts` is the one typed client; the app loads `/state` once and sets `main[data-snapshot]` to `loading`, `loaded` or `failed`.
  - **Live tests:** `test-bundle-folder.sh` (non-Health image) and `web/e2e/api/api.spec.ts` (run by `test-sign-in.sh`). The web gateway caches answers, 404s included: each probe uses a fresh URL.
- **Delivered: Story 0.6.**
  - **`OcuTalon.Production`:** 38 items with final names and classes, 18 in Lane A's region and 20 in Lane B's; 35 enabled (off: `TelegramIn`, `TelegramOut`, `EvalIn`). Pool 0 for adapterless services, 1 otherwise. It starts with no model key. The future pollers (`HeartbeatIn`, `StatusMonitor`, `FailurePoller`) are adapterless stubs; their owners add the adapter and pool. `EnsLib` classes: `OcuTalonApprovals` (Lane A, Workflow, not a stub), `OutcomeRouter` and `Notify` (Lane B).
  - **Stubs:** every unbuilt item class's one handler is `Quit $$$ERROR($$$NotImplemented)`, and the class carries `Parameter STUB = 1`; the owner deletes both lines when it builds the item. Operations answer "ERROR #5003: Not implemented", a business process answers `<Ens>ErrBPTerminated` carrying it, and every job survives. The routers are `EnsLib.MsgRouter.RoutingEngine` with `BusinessRuleName` `OcuTalon.Core.Rule.Outcome` and `.Notify`, whose empty rule sets route nothing; `STUB` is on the rule class, and 11.5 reads it there too.
  - **The `Production` step** (Lane A): every start first writes the System Default Setting `Enabled` for `EvalIn` from `OCUTALON_EVAL` (1 only for `"1"`), which overrides the definition (never `EnableConfigItem`: a class save drops the lane markers; 12.1's Telegram switch can reuse this). Then: this production running → restart every item; another production running, Troubled or Suspended → fail naming it, touching nothing; Troubled → IRIS's recover, then start; Stopped or Suspended → start. It waits at most 60 s.
    - **Recover** puts in-progress messages back on their queues, keeps asynchronous queues for the next start, marks queued synchronous messages Suspended and discards private-queue messages (in-flight synchronous replies). It never cleans the production or kills application data.
    - **Runs:** an enabled item with a pool (system items such as `Ens.Actor` included) has an `Alive` job not in error; an adapterless service runs when enabled in the running production.
    - **Model:** every runner resolves one through `AgentRunner.ResolveModel(item, production)`: the adapter's `Model` setting (item, then System Default Setting), else the agent class's `MODEL` (`claude-haiku-5-5`). 1.1 adds seeding.
  - **Extension bases** (`Bridge.Ext.HostSink`, `.ReplyFilter`, `.Classification`, do-nothing defaults): `HostSink.OnEvent(type, ownerRef, payload)` with one parameter per event type, `EVENTS` and the payload builders. `Core.BridgeSink` (Lane B) does nothing until 2.6; `Checks.ReplyGuard` (Lane A) passes text through until 5.7.
  - **`Bridge.Ext.Accessor.ClassFor(setting, production = "", item = "Decide", Output sc)`** reads the production definition, so it works in any job and, given the production's name, needs none running. A missing class, or one not extending its base, gives `""` and an error, never the base, so a bad guard can't silently disable AD-28.
  - **Agent runners (AD-6):** `TriageAgent`, `DiagnosisAgent` and `ChatAgent` are `Bridge.Operation.AgentRunner` with the final adapter `Bridge.Adapter.Agent` (`AgentClass` = `OcuTalon.Agent.Triage`, `.Diagnosis`, `.Chat`), whose `OnInit` calls no AI Hub API. The agent classes carry `MODEL` and `MOCKKEY` (`triage`, `diagnosis`, `chat`); `INSTRUCTIONS` and `TOOLSETS` are 1.1's.
  - **`Bridge.Context`** (implemented, in `^||OcuTalonBP.Context`): `Begin(request, superSession = "")` replaces any context; `End()`, `Active()`, `Current()`; `Put(name, value)` accepts only `FIELDS` names (`ThreadSessionId` and `SuperSession` among them), a plain setter (the taint gate is 1.2's).
  - **`Core.Commands.Submit(command, origin, Output result) As %Status`** (implemented): refuses a missing command or origin; uses `tool` when `Context.Active()`, else `origin`, which must be in `Msg.Enum.ORIGIN` (else refused, nothing sent); overwrites `command.Origin` and sends it to `CommandsIn` through `Ens.Director.CreateBusinessService`. No role check. `CommandsIn` answers "Not implemented" until 2.3 adds thread joining and routing by verb.
  - **`OcuTalon.Tools.Names`:** the 11 release-1 tool names, snake_case, defined once (`RELEASE1` lists them): `set_reminder`, `list_reminders`, `cancel_reminder`, `start_watch`, `stop_watch`, `list_productions`, `dismiss_incident`, `check_status`, `read_failed_messages`, `read_event_log`, `read_item_settings`. Later steps' tools are named by their own stories.
  - **`Bridge.Compaction.Prompt()`** (implemented, ASCII `XData Prompt`): S18's schema text, first line starting `OCUTALON-COMPACTION-V1`.
  - **Cross-lane API stubs** (owner lane and story), pinned by `Test.Contract.Ac`'s signature oracle, which the owning lane keeps green: `Bridge.Approval` (`Raise`, `Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`; A, 3.4–3.6, 7.3); `Agent.Input.Render` (A, 1.3); `Checks.Render` (A, 5.7); `Bridge.Budget.State` (A, 1.4); `Bridge.Keys.Status` (A, 1.6); `Bridge.Timeouts.Derive` (A, 1.7); `Bridge.ConfigStore.Merge` (A, 1.1); `Data.Session.Recipients` (B, 2.2); `Data.Ownership.TurnCost`, `.RunCost` (B, 2.2, 2.6). Open return shapes are `%DynamicObject` with camelCase keys, or `%List`.
  - **DW-13 (done):** `test-storage.sh` also treats `Ens.BusinessProcess`, `Ens.MessageBody` and `Ens.StreamContainer` as storage roots, exempts message and process extents from `DEFAULTGLOBAL`, with a bad sample each.
  - **AD-2 pin:** `test-install-start.sh` row 5 scans the code lines under `src/bridge/cls/` for another `OcuTalon` package, as a class or a table name (`OcuTalon_Pkg`); 0.7's boundary check can reuse it.
  - **Tests:** `Test.Install.Production` (its `Items()` is the one test copy of the item ownership table, read by the shell in the container), `Test.Core.Commands`, `Test.Bridge.Ext`, `.Api`, `Test.Agent.Constants`. Live: `docker/tests/test-production.sh` (every item runs; stubs answer without killing jobs; the step fails on another running production) and `test-production-restart.sh` (after a kill, every item runs again), both through `lib-live.sh`'s new `item_jobs` and `check_items_run`. A stub's test instance comes from `Ens.Host.GetShadowInstance("class||<class>")`, never `%New("")`.
  - **Owner veto window (Rule 22.3), open:** 0.5's API rulings (envelope, no-role, `/ocutalon/public`, API-created `Session` rows, old-bundle deletion, error texts, `ApiBase` placement, unchecked-privilege queries); 0.6's `Submit` trusting the caller's origin outside a bridge context, and the recover keeping queued synchronous messages Suspended.
- **Developer slots:** `ocutalon-slot-a` and `-b` run 0.1's `merge.cpf` on the base image without the after-start script: code goes in through the IRIS MCP tools, installer steps run explicitly, and IRIS can't read the repository. The after-start install and destructive tests run only in throwaway compose stacks and CI.
- **0.7 (next):**
  - `ci.yml` (Lane B) runs the hosted jobs (web build with both `--check`s, lint, `node --test`, 0.11's mock tests) and the IRIS jobs on the self-hosted runner, each in its own compose project with the CI override: the `%UnitTest` shards and `docker/tests/test-*.sh`, the live ones included (`test-audit.sh`, `test-sign-in.sh`, `test-bundle-folder.sh`, `test-production.sh`, `test-production-restart.sh`). One script runs the same IRIS jobs locally in a throwaway project. `lane-a.yml` gets an empty bridge job (1.3 fills it).
  - **The checks job:** its lane-region check assigns lanes by item name (the `EnsLib` items name no lane); its public-package check covers `Shell`, `Login`, `SignInAssets`, `Status` and `ApiBase`.
  - **DW-11:** the IRIS checks job runs the load, compile and export round trip over every persistent class, failing when a compiled `Storage` block differs from its committed file.
  - **DW-17:** the checks job fails on any `%Prepare` (or `%SQL.Statement` prepare) with the privilege check off outside an allow-list naming only `OcuTalon.Data.Session.ForUser`'s and `OcuTalon.Live.Event`'s queries.
  - Both workflows run on every push to `feature/OCT_OcuTalon_MVP` and `OCT-epic*` and on every pull request, with no `cancel-in-progress` there. 0.7 also records the IRIS test recipe in `_bmad/custom/skill-rules.md` and updates `_bmad/custom/parallel.yaml` (`bootstrap` with `web/`'s dependencies and the IRIS reference folders, `runtime_locks` for throwaway stacks).
- **0.8:** runs in 0.7's IRIS job; reuses 0.3's `playwright.config.ts` and `signIn()`, and waits for 0.5's `main[data-snapshot=loaded]`. Unbuilt UJ-1 steps are skipped specs. It also records the x64 first-start time.
- **0.9 (Lane B's after):**
  - `OcuTalon.Msg.Catalog.Core` and `.Watch` with every release-1 and 0.1.1 key, including those 0.4's `CatalogKey` and `Slots` name; `Catalog.Render(key, slots, channel)` on `Data.Time`, tested on every key and channel; and the test comparing the public package's text copies (`Login`'s, `ApiBase`'s 401 text) with the catalog.
  - **DW-12:** Task 0 measures, on a throwaway stack started with a compose-level `TZ`, whether a production job's `Data.Time.ToLocal` and `Zone()` use the container's zone; if not, the renderer passes the instance zone explicitly (AD-18). It needs only 0.6's production jobs.
- **0.10:** fills step 8, `Install.Step.Demo`, which reads demo mode through `Setting.Get` and its seed. Demo mode on: OCUORDERS (code and data databases, mappings), `OcuTalon.Demo.Orders.Production` running there (message classes, a partner service, the real transform failing on the changed date format) and the OCUORDERS trace application through `Web.TraceApp("OCUORDERS")`. Off: no OCUORDERS. `eval/` gets one recorded failure snapshot of a date-format batch for Lane A's watch and diagnosis tests until Epic 9.
- **0.11 (last, Lane B):** adds the one mock service (AD-22) to 0.7's CI override, which 0.7's IRIS job already uses. It keys on 0.6's constants: `MOCKKEY` `triage`, `diagnosis` and `chat`, the `Tools.Names` values its default scripts call, and `OCUTALON-COMPACTION-V1`. Its scenarios cover what 1.6 to 1.9 need: `refusal` and `max_tokens`, an empty reply, a provider error, "Invalid input", an answer held past the bridge timer, 429/529 with `Retry-After`, and the summary and off-schema summary. Its tests run in 0.7's hosted jobs.
- **Handoffs outside Epic 0 (not built here):**
  - **DW-14 (2.2):** `ApiClient` sends the browser envelope on every state-changing call through an interceptor, starting with `POST /api/v1/session/end`, with a test of the server's 403s without it.
  - **DW-15 (2.2):** `/state` and `/events` resolve the caller's session through `Data.Ownership` from the CSP session, replacing `Session.ForUser($Username)`.
  - **DW-16 (16.3):** Ownership's one resolution method gains the per-sign-in (resume-cookie) branch, so two sign-ins of the shared online-demo account get different sessions.
  - Also 2.2's: filling `chat` and `rail`, the live-event service, `SessionEvents` calling `ForUser`, Sign out through the API, and the purge (rows only, never the counter).
  - **Epic 10:** `install.sh` uses `IRIS_IMAGE` and refuses Compose older than 2.24; 10.2's README states that minimum, the LAN-exposure warning, the password change and the IPM licence notice.
- **Later owners of Epic 0's stubs** (Epics 1 and 2 start from Epic 0 and test against its stubs and the mock): Epic 1 the bridge, agents, runners, `Decide`, budget, keys, timeouts, compaction and tools (1.1–1.12, with the `lane-a.yml` job in 1.3); Epic 2 the page, `Ownership`, `CommandsIn` routing (2.3), the Lane B items and publishers, `BridgeSink` (2.6), `Delivery` (2.7); Epic 3 approvals and audit shapes; 4.1 demo-mode switching; Epics 5–7 the watch, checks and fix items (`ReplyGuard` and `Checks.Render` in 5.7); 8.3 reminders; Epic 9 `EvalIn`/`EvalSink`; 10.3 and Epic 12 pairing and Telegram; 11.5 the `STUB` check; Epic 15 `src/cpf/ocutalon.cpf`, `Registry.Run("ipm")` and IPM autostart.
