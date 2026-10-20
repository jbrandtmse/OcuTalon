# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. A judge loads and retags the build 154 image, runs `docker compose up`, and gets OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with an empty, branded page behind sign-in. Its real job is to unblock two parallel build lanes: it creates every cross-lane release-1 contract with its final name, type and storage (messages, tables, live-event payloads, the catalog and its renderer, the REST skeleton, the bridge extension points, the cross-lane API signatures), stubs every release-1 production item inside lane-owned regions, and sets up CI with the model mock and a demo-path test, so each lane starts its first story without editing the other's files. One runner, time-boxed to three days from the build start; it ends October 23 at the latest.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts (done)
- Story 0.5: Live events and the REST skeleton (done)
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production (done)
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock (done; the mock itself moved to 0.11)
- Story 0.8: The demo-path test signs in and loads the page (next)
- Story 0.9: The message catalog and its one renderer
- Story 0.10: The Orders demo production runs in OCUORDERS
- Story 0.11: The CI model mock answers every scenario the stories need (last story of Epic 0)

## Requirements & Constraints

- **Install:** after a load and retag, a plain `docker compose up` gives a working install. The first start creates OCUTALON with Interoperability and its own databases. Later starts reapply the same configuration with no errors and no data loss. In demo mode (the Docker default), the Orders production runs in its own namespace, OCUORDERS.
- **Roles and sign-in:** the install creates the user, admin and trace roles. The README account (`ocutalon`/`ocutalon`) has a non-expiring password and no forced change, and the README says how to change it. No page or API answers without a session, except the login page (with its images) and `/ocutalon/public/status`.
- **Secrets:** model keys and bot tokens come only from environment variables. `.env` is git-ignored, and `.env.example` lists `ANTHROPIC_API_KEY` and `TELEGRAM_BOT_TOKEN` with no values. No key appears in logs, traces, audit entries or the repository.
- **Image and registry:** the AI Hub image, or any image built on it, is never pushed and never enters a CI cache or artifact. CI fails on any `docker push` or registry sign-in. The judges' compose file has no mock service.
- **Tracked files:** no tracked or new file holds a local machine path or a key-like string; a CI check scans the whole tree, the planning and bookkeeping folders included.
- **CI:** a full run takes at most 30 minutes. IRIS tests run on the self-hosted runner, everything else on paid hosted runners. Fork pull requests never reach the IRIS runner. The demo-path browser test runs on every pull request and every push to `main`, and a failure blocks the merge. `main` moves only through a release pull request.
- **Platform:** the same Dockerfile works unchanged on the non-Health build 154 image through the `IRIS_IMAGE` build argument.
- **Epic 0 is done when:** a clean first start reaches ready and a second upgrades in place; the production starts with every release-1 item running as a stub (`TelegramIn`, `TelegramOut` and `EvalIn` disabled); every class compiles with its storage block committed; CI runs with the mock and the boundary, storage, `DEFAULTGLOBAL` and public-text checks; the demo-path test signs in and loads the page; and neither lane needs the other's files for its first story.
- **First-start timing (0.8):** record the real package's first start on x64, install included, in the epic notes for the README. Raise any first start over about 12 minutes to the author.

## Technical Decisions

### Governing rules (by AD id)

- **AD-2 (one package, separable bridge):**
  - One IPM package, `ocutalon`. `src/module.xml` lists the bridge (`src/bridge/`: `OcuTalon.Bridge`, `OcuTalon.BridgeExample`) before everything else (`src/ocutalon/`), plus the Angular bundle (`FileCopy`).
  - `src/bridge/` also loads alone with `$SYSTEM.OBJ.LoadDir` into a namespace with Interoperability, and `OcuTalon.Bridge.Installer` sets it up; without Interoperability only `Bridge/Installer.cls` loads, and it refuses, naming the namespace.
  - CI fails if a bridge class references another `OcuTalon` package (`bridge-refs`, a source scan), or if a class outside `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Docs`, `.Memory`, `.Mcp`, `.Install` and `.Test` (whole package names) references `%AI` or `EnsLib.AI`, as a class or a table (`ai-allowlist`).
  - `OwnerRef` is exactly a `SessionRef`, `instance` or `eval`.
- **AD-3 (namespaces and databases):**
  - OCUTALON has code, data, private and public (`OCUTALON_PUBLIC`, public Read) databases.
  - The public database holds only `OcuTalon.Web.Public` (`Login`, `Status`, the `/ocutalon` dispatch class `Shell`, the generated `SignInAssets`, and `ApiBase`, the API's answer before sign-in), `OcuTalon.Data.Public` and `^OcuTalonPublic`: a request without a session can't read the code database.
  - Those packages may reference only `%CSP` (including `%CSP.REST`), dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (only in a compile-time generator) and each other. They keep their own copies of the UX texts they render, compared with the catalog by a test (0.9).
  - **The check (`Test.Web.Status`)** reads every class of both packages from the class dictionary: superclasses, types, `##class` calls, `$SYSTEM` members, dynamic dispatch. A system datatype class (`%String`, `%Status`) is allowed as a type; any other system class or another package's datatype class is not. Embedded SQL, globals, macros, indirection and the like aren't read (DW-20, escalated).
  - Global mappings put `OcuTalonP.*` and `OcuTalonBP.*` (with the dot, so `^OcuTalonPublic` stays public), `^AI.Agent.Session*` and `^IRIS.IF.*` in the private database. The databases and mappings exist before any class compiles.
  - Business processes store in `Ens.BusinessProcess`'s own extent, so they set no `DEFAULTGLOBAL`, and keep no private text in their properties; anything private goes in a private table.
  - `OcuTalon.Production` is not autostart on Docker.
  - Only `OcuTalon.Install.*`, `OcuTalon.Bridge.Installer` (to `%SYS`, in its one method) and `Install.Step.Demo` (to OCUORDERS) switch namespace in product code, each in one method with `New $NAMESPACE`. Test classes also switch to `%SYS` for fixtures (accepted, DW-7).
  - On the non-Health image, `Interop=1` creates no Foundation production and the default web application is `/csp/<ns>`; nothing may depend on either.
- **AD-5 (durable state):** all state lives on the durable volume, and an install replaces only code. Storage is append-only, and every such class's source carries its compiler-generated `Storage` block, never edited by hand. The production class holds structure only; values go in System Default Settings, bridge tables or `OcuTalon.Data.Setting`.
  - **Release diff** (`test-storage.sh`'s `release-diff`): each block's lines at the highest earlier `v*` tag stay a subsequence of its lines at HEAD, and every slot keeps its number and property; a shallow clone fails. A no-op (`PASS release-diff: no release tag yet`) until a tag exists.
  - **Round trip** (the IRIS `image` group, DW-11): each compiled `Storage` block, exported after the install, equals its committed file.
- **AD-19 (configuration homes):**
  - Model keys and bot tokens are environment-only. Endpoint overrides `OCUTALON_MODEL_BASE_URL` (ending `/v1/`), `OCUTALON_EXTRA_CA_FILE` and `OCUTALON_TELEGRAM_API_BASE` are set only by the CI override and the online demo.
  - The installer marks every value it writes `structural` (rewritten every start) or `seed` (written only when absent).
  - `OcuTalon.Data.Public.Settings` is the only reader and writer of `^OcuTalonPublic` (CI's `public-global` rule). `OcuTalon.Data.Setting.Get` serves product values through a 60-second cache.
- **AD-23 (image and installer):**
  - **Image:** one Dockerfile, `FROM ocutalon-iris-base:2026.3.0AI.154.0`. Every compose file sets its own top-level `name:`; the IRIS service sets `stop_grace_period: 60s`. The judges' compose file publishes only `${OCUTALON_WEB_PORT:-52773}` and names no file of `ci/`.
  - **The CPF merge** (`docker/merge.cpf`) creates the databases, namespace and mappings and enables `%Service_CallIn`, idempotently, every start.
  - **The after-start script** re-merges, installs IPM 0.10.10 into `%SYS`, checks that the public classes resolve to `OCUTALON_PUBLIC`, loads the package version-gated (`OCUTALON_DEV=1` reloads every time), runs the registry's steps and writes the ready marker atomically; a failure writes no marker. It logs `STEP <name> OK|FAILED` and `RESULT OK <version>` to `/durable/ocutalon-after-start.log`.
  - **The health check** opens no IRIS session: `^running` in `iris qlist` and the marker equal to the image's version; `start_period` at least 10 minutes.
  - **First start:** S1 measured about 1 minute on Apple silicon; 0.8 re-measures the real package on x64 for the README. Above about 12 minutes, the code-in-image option goes to the author.
  - **Static web files** go in the durable `csp/ocutalon-web/`, never `csp/ocutalon/` (served without sign-in on the non-Health image).
  - **Step registry:** every step extends `OcuTalon.Install.Step`; `OcuTalon.Install.Registry` runs the fixed order, and a step class outside it only declares. Areas declare `Grants()` (`{"role","resource","permission"}`; empty `resource` declares the role alone), `Reconcile()`, `Tasks()` (`{"name","taskClass","description","task":{...},"settings":{...}}`) and `Purge(daysToKeep)`. Role and task names start with `OcuTalon`. Tasks are created once. An IPM install calls `Registry.Run("ipm")`.
- **AD-13 (web applications, sign-in and the envelope):**
  - **One sign-in group** (`GroupById` `OcuTalon`, password): `/ocutalon` (dispatch `OcuTalon.Web.Public.Shell`), `/ocutalon/api` (`OcuTalon.Web.Api`, `/v1`, sharing `/ocutalon`'s CSP session) and the trace applications. `OcuTalonUser` holds no database resources; the applications grant them as application roles.
  - **`/ocutalon/public`** (unauthenticated, outside the group) serves only `GET /status` from the public settings, always with every key, `null` when unset: `{ready, nextReset, busy, lastReset, lastResetKind}`.
  - **Before and after sign-in:** `ApiBase` answers a request without a session with 401 `signed_out`; a signed-in user without the user role gets 403 `no_role` and keeps the session (a trace-only user stays signed in to the trace windows).
  - **SQL privilege:** `OcuTalonUser` holds no SQL grant on OcuTalon's tables, so the API's own queries over the signed-in user's rows are prepared without the privilege check (`%Prepare(text, 0)`), with fixed texts and every input a parameter; ownership is enforced in the queries. Don't grant `SELECT` to a role instead.
  - **The `unchecked-prepare` rule (DW-17):** allows them only in `Session.ForUser` and `Live.Event.Since`, keyed by class and method (`ALLOW_UNCHECKED`; a stale entry fails). It flags a `%Prepare` whose second argument, or a `%PrepareClassQuery` whose third, isn't the literal `1` (`$$$YES` is flagged too, DW-24), and `%ExecDirectNoPriv*`; an omitted argument is checked.
  - **Session lookup, Epic 0 interim:** until 2.2 builds `OcuTalon.Data.Ownership`, `/state` and `/events` find the caller's session by user name (`Session.ForUser`); 2.2 switches them to Ownership (DW-15).
  - **Login page** `OcuTalon.Web.Public.Login` (`%CSP.Login`, no Angular) loads nothing from an authenticated path.
  - **The browser envelope:** every state-changing call needs `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`, or it gets a 403. GET, HEAD and OPTIONS are exempt.
- **AD-24 (roles and trace applications):**
  - The roles are `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`. The trace role holds only Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`; Read on the data and code databases (never the private ones); SQL `SELECT` on `Ens.MessageHeader`.
  - The trace applications `/ocutalon/trace/ocutalon/` and `/ocutalon/trace/ocuorders/` have no application roles and exactly seven permitted classes, as `Web.TraceApp` sets them. The OCUORDERS application and grants exist only with demo mode on.
  - No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun` or `%Ens_ProductionConfig`. No `OcuTalon.Data` or `OcuTalon.Bridge.Data` class extends a message base.
- **AD-12 (live events):**
  - Rows are written only through `Live.Publish`, after the publisher's own commit, never inside a transaction. Only event-table types are accepted, each with exactly one publisher. `Seq` comes from a per-stream counter the purge never deletes.
  - The browser envelope labels the stream `session` or `instance`, never the stored `SessionRef`. Row ids never leave the server.
  - A payload is the full current public view of one entity, keyed by `Ref`, never a delta: a `%JSON.Adaptor` class `OcuTalon.Live.Payload.<Type>` of the publisher's lane, nested shapes under `.Payload.Part`, keys camelCase.
  - Trace targets are `TraceHeaderId` and `TraceNamespace` (the URL is the web layer's). Polling is the release-1 contract.
  - Status conditions are a closed catalog: `allowance`, `dailyCap`, `noModelKey`, `heartbeatStalled`, `telegramPaused`, `resetSoon`.
- **Contract semantics fixed in Epic 0:**
  - **`Commands.Submit` (AD-1):** the only way to submit a command. It validates the caller's origin, overwrites the payload's `Origin` with it (`tool` while a bridge context is active), and sends to `CommandsIn`; role checks stay with the admin-checked endpoints and `CommandsIn`. Origins: `web_user`, `web_admin`, `telegram`, `tool`, `timer`, `system`.
  - **`Reply.Busy` (AD-6):** set when `Decide` refused a `turn` after a 2-second lock wait; the `Reply` carries no text and no decision (`Reply.NewBusy()`), and busy is never an error status.
  - **`Decision` (AD-20):** unique on (`ItemId`, `Kind`).
  - **Time (AD-18):** `OcuTalon.Data.Time` is the only converter outside the bridge, `OcuTalon.Bridge.Time` (1.4) the only one inside it.
  - **Audit (AD-17):** `OcuTalon.Bridge.Audit` is the only audit writer; OcuTalon never changes instance-wide auditing. Tests poll the audit log with a timeout (rows appear 53 to 72 s late).
  - **Extension bases (AD-31):** the bridge wraps every `OnEvent` call and never fails its caller. `Decide` runs `ReplyFilterClass` before recording anything. The three settings are read only through `Bridge.Ext.Accessor.ClassFor`, which never falls back silently.
  - **Rendering (AD-32):** producers never render text. Only `*Out` operations render, through `Catalog.Render` (0.9), which uses `Data.Time`.
- **AD-22 (testing and CI):**
  - `%UnitTest` classes live in `OcuTalon.Test.<Area>`, sharded by area, one compose project per shard, on the self-hosted IRIS runner; web and mock code runs on hosted runners.
  - **As built (0.7):** the override `ci/compose.ci.yml`; one recipe, `ci/iris.sh`, always in throwaway projects; two lane-aligned shards inside five IRIS groups (`image` is the IRIS checks job); every live script on the Health image; step-level skips against the newest green push run, never on a pull request. `OCUTALON_EVAL` passes through (default 0); only Lane A's evaluation job sets 1.
  - **The mock (0.11)** is reached through the Anthropic provider's `base_url` over plain HTTP on the compose network (no private CA or host alias). It answers `POST /v1/messages` and `GET /v1/models/<id>`, and rejects `temperature`, `top_p`, `top_k` and output caps under 4,000 (S2: the product sends none, and an 8,000-token cap). Scenario choice: a `[[mock:<name>]]` marker in the newest user message with text, then a guide prompt's exact text contained in it (the `Agent.Input` preamble comes first), then the agent's `MOCKKEY`, never by wording. A summarizer request starts its `system` text with `OCUTALON-COMPACTION-V1` and gets AI Hub's summary schema (`facts_learned`, at least one `tool_actions` entry; one scenario off-schema). It logs header names and key length only; its only state is a per-test retry countdown set through a control endpoint.
  - **Scenario files:** `ci/mock/scenarios/<A|B>/<name>.json` with `name`, `match` (`marker`, `prompt` or `mockkey`; `telegram` from 10.3) and `replies` (each `status`, `headers`, `delayMs`, `stopReason`, and `text`, `toolUse` or `body`). Lane A adds only files under `A/`; new mock behaviour is Lane B's, asked for under AD-33.
  - CI and scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format` (both print `env_file` values).

### Cross-lane contract obligations (AD-29, AD-33)

- **Contracts before code:** every release-1 contract gets its final names, types and storage; cross-lane APIs are signatures with stub bodies. Fully implemented in Epic 0: `Commands.Submit`, `Data.Public.Settings`, 0.4's helpers, 0.5's live-event store and API skeleton, and `Msg.Catalog.Render` (0.9). The owning lane appends the rest.
- **Catalog (0.9):** every release-1 and 0.1.1 key, in `OcuTalon.Msg.Catalog.Core` (Lane B) or `.Watch` (Lane A). The item noun slot is `itemNoun: {"one", "other"}`.
- **One owner each:** after Epic 0, each item, class, table and event type has one owning lane, and only it edits; the other lane asks. A new item, table or event type joins the ownership tables in the same change.
- **Lane A owns:** `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Watch`, `.Fix`, `.Checks`, `.Digest`, `.Eval`, `.Channel.Telegram` (moved October 17) and `eval/`; the installer core (the registry, `docker/merge.cpf`, and the role, user, SSL, task, `Production` and `Public` steps); `ci/mock/scenarios/A/`; `release/`; and `.github/workflows/lane-a.yml` (standalone bridge, evaluation, and the 1.0.0 kit's FR-57 job).
- **Lane B owns:** `OcuTalon.Web` (with `.Web.Public`), the rest of `.Channel`, `.Core`, `.Schedule`, `.Demo`, `.Live`, `.Msg`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership` and `.Data.Public`; `web/`, the rest of `docker/` and `ci/` (the mock included), and `.github/workflows/ci.yml` (builds, shards, checks, the demo path); and the `Web` and `Demo` installer steps.
- **By area:** `OcuTalon.Test.<Area>`, `OcuTalon.Install.Step.<Area>` and `OcuTalon.Live.Payload.<Type>` (with its parts) follow their area's or publisher's lane.
- **Table owners:** Lane B: `Session`, `AddressCounter`, `StatusMark`, `GuideState`, `BreakFeedRun`, `Pairing`, `Turn`, `SimMessage`, `Delivery`, `Reminder`, `Setting` and `Live.Event`. Lane A: `BackgroundCheck`, `WatchMark`, `Incident`, `FailureGroup`, `FixRun`, `Digest.Data.Item` and every `Bridge.Data` class (`Decision`, `ApprovalRequest`, `Usage`, `Price`, `ConversationLink`, `ModelFamily`).
- **Production class:** one `ProductionDefinition` XData block, each lane's items between `<!-- lane A: begin -->`/`<!-- lane A: end -->` (the same for lane B), checked by `Test.Install.Production` and `.ProductionRules`. Every item is enabled except `TelegramIn` and `TelegramOut` (off until a release includes Telegram) and `EvalIn` (only with `OCUTALON_EVAL=1`). Unbuilt items answer "not implemented" and carry `STUB = 1`. Before a release cut, the owning lane disables, in its own region, any item whose story hasn't merged; 11.5 refuses an enabled stub.
- **`Decide` settings in Lane A's region:** `HostSinkClass` = `OcuTalon.Core.BridgeSink`, `ReplyFilterClass` = `OcuTalon.Checks.ReplyGuard`; `ClassificationClass` keeps the default until step 4.
- **HostSink payloads:** `decision.*` and `approval.*` carry `{ref}`, the record's public `Ref`; `turn.step` carries `{decisionRef, label}`, with the session as `ownerRef`; `budget.capped` has `ownerRef` `instance` and payload `{day}` (`YYYY-MM-DD`, instance zone).
- **Test-only global:** `^OcuTalonTest("TelegramIncluded")` is set only by `OcuTalon.Test` classes and never exists in the judges' install.

### Naming and storage conventions

- **Classes:** `OcuTalon.<Area>.<Name>`, one class per file. Cross-lane contracts go in `OcuTalon.Msg`/`OcuTalon.Data`, bridge contracts in `OcuTalon.Bridge.Msg`/`.Data`. Nothing under a system package name.
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
- **Tests:** `OcuTalon.Test.<Area>.<Subject>`, directly in the area folder; Playwright under `web/e2e/` (demo path: `web/e2e/demo-path/`, one spec per UJ-1 step). Mock scenarios are `ci/mock/scenarios/<A|B>/<name>.json`.

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
| GitHub Actions (pinned by commit SHA) | `actions/checkout` v7.0.1, `actions/setup-node` v7.0.0 (MIT) |
| `@types/node` (web lint only) | 24.19.1 (MIT, exact) |
| Default model, every agent | `claude-haiku-5-5` |

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
  - `docker/merge.cpf` keeps its database directories relative (S19: `src/cpf/ocutalon.cpf` differs only by the `%Service_CallIn` and IPM lines).
  - `.dockerignore` is `*` plus an allow-list: every file a later story copies into the image must be added to it.
  - `docker-compose.yml`: `name: ocutalon`, one service `iris` (`pull_policy: build`), `env_file` `.env` with `required: false`, volume `durable:/durable`, `start_period: 600s`.
- **Delivered: Story 0.2.**
  - `docker/after-start.sh` (with `.cos`); `docker-compose.dev.yml` (project `ocutalon-dev`, `OCUTALON_DEV=1`); `src/module.xml` (`ocutalon` 0.1.0) lists `OcuTalon.Bridge.PKG` then `OcuTalon.PKG`.
  - **Step order** (`Registry.Order()`, `OcuTalon.Install.Step.<Area>`; each story fills its own step without re-ordering): 1 `Bridge.Installer`; 2 `Public` (3.8 adds values); 3 `Roles`, 4 `Users`, 5 `Web` (built); 6 `SSL` (stub; first story needing client SSL); 7 `Tasks` (built; 1.11 and later declare); 8 `Demo` (stub; 0.10); 9 `Provider` (stub; 1.1); 10 `Audit` (3.7 with DW-10 extends it); 11 `Telegram` (stub; 12.1); 12 `Production` (built, 0.6); 13 `Reconcile`, 14 `PrivateData` and 15 `Ready` (built).
  - Public settings, roles and audit events are structural; tasks are created once. The System Default Settings helper comes with 1.1.
  - **`Data.Public.Settings`:** a fixed key set (the online-demo, reset, proxy and connection keys plus `ready`); any other key is refused.
  - **Tests:** `%UnitTest` classes under `src/ocutalon/cls/OcuTalon/Test/<Area>/`, compiled by the package install. Bash tests are `docker/tests/test-*.sh`, each runnable alone; live ones use `lib-live.sh`'s `live_start` (a throwaway project with no keys).
- **Delivered: Story 0.3.**
  - The `ocutalon` account holds all three roles, as seed. The `Roles` step composes the `Users` and `Web` steps' `Grants()`.
  - `Web.TraceApp(namespace, .props)` returns `/ocutalon/trace/<namespace in lower case>` and its properties (0.10, 4.1). Sign out uses `?IRISLogout=end` until 2.2. The sign-in POST has no CSRF token (DW-6).
  - **`web/`:** `npm --prefix web run build` (`tokens.mjs --check`, `payloads.mjs --check`, `brand.mjs`, `ng build`) writes `src/ocutalon/csp/`, git-ignored on development branches and force-added at release (11.5); the Dockerfile refuses an image without it.
  - **Browser tests:** `web/playwright.config.ts` (`testDir ./e2e`, `baseURL` from `OCUTALON_URL`) and `signIn()` in `web/e2e/sign-in/helpers.ts`. `docker/tests/test-sign-in.sh` seeds a live stack and runs `npm --prefix web run e2e`, every spec under `web/e2e/` (port `OCUTALON_TEST_WEB_PORT` or 52800–52819; Node 24.15+ and Playwright's chromium).
- **Delivered: Story 0.4.** Contract classes with final names, types and storage (properties are in the classes and their oracles):
  - **`OcuTalon.Msg` (Lane B):** `Item`, `ItemDecision`, `Notification`, `Outbound`, `Tick`, `CommandResult` and `Enum`; the abstract `Command` (`Origin`, `IdempotencyKey`, `SessionRef`) with one subclass per verb, routed by class (2.3); `IncidentCommand` (`Verb`: `dismiss`, `closeForReplay`, `closeQuiet`). Commands carry no IRIS user.
  - **`OcuTalon.Bridge.Msg` (Lane A):** `Request`, the abstract `Result` with `DecisionResponse` and `Reply`, `DecisionPayload` (`%JSON.Adaptor`), `AgentStep`, `Enum`. The tables are those of "Table owners" above.
  - **Shapes to follow:** sizes `Ref`/owner 22, `Utc` 20, local time 19, enum words 32, names 128, lines 1000, summaries 80, long text and JSON unlimited; money `%Numeric(SCALE = 6)`, rates `SCALE = 4`, confidence `SCALE = 2`. Every `%Boolean` has `InitialExpression = 0`. Every table with `Ref` has `Index RefIndex On Ref [ Unique ]`; indexes are `<Property>Index`. Reasons are newline-separated text, a JSON list only in `DecisionPayload`.
  - **Helpers:** `Bridge.Ids.NewRef()`; `Data.Time` (`NowUtc()`, `ToLocal(utc)` giving `""` for a non-`Utc` value, `Zone()`; `FromLocal` in 8.3); `Data.Setting.Get(key, default)`/`Seed(key, value)`; `Bridge.Audit.Events()`/`Write(type, data, description)`; `Data.Delivery.Record`/`FindByApproval` (failing stubs until 2.7); `Channel.Telegram.In` (stub; `Included()` is 0 unless the test global is set).
  - **`src/short-names.tsv`** (`short`, `global`, `class`, `lane`): a new persistent class adds its row in the same change, and its entry in `Test.Data.Tables`'s `Registry` XData.
  - **Oracles:** `Test.Msg.Contracts`, `Test.Bridge.Contracts`, `Test.Data.Tables` and `Test.Contract.Ac` (on `Test.Contract`'s `AssertContract`); a lane that appends to a contract updates its oracle, and the counts are floors.
- **Delivered: Story 0.5.**
  - **`OcuTalon.Live.Publish`:** `Publish(stream, type, payload, .seq) As %Status` (`stream` a `SessionRef` or `#INSTANCE`), outside any transaction, after your own commit; `LastSeq(stream)` throws when the lock isn't free in 5 s. `Live.Event.Since(stream, after, max, label)` pages one stream (`MAXEVENTS = 200`). Not yet in `Publish`: the guide hook (4.2) and the `$SYSTEM.Event` signal (2.11).
  - **Event table** (`Publish.TYPES`): 16 types; Lane A owns `incident`, `watch.progress` and `check`, Lane B the rest. `Payload.Incident.FromRow(row)` is the one incident builder. `%JSONNULL` 0: a missing key means empty. `web/scripts/payloads.mjs` generates `web/src/app/live/payloads.ts` (the build's `--check` fails when stale).
  - **`OcuTalon.Web.Api`'s 12 `/v1` routes:** `GET /state` and `GET /events?after=&afterInstance=` are built; the pairing routes answer 404 while `Included()` is 0; the other eight answer 501 `not_built`. `/state`'s `chat` and `rail` stay empty until 2.2. `Session.ForUser(irisUser, .sc)` finds or creates the user's one `Session` row.
  - **The page:** `web/src/app/api/api-client.ts` is the one typed client; the app loads `/state` once and sets `main[data-snapshot]` to `loading`, `loaded` or `failed`. `web/e2e/api/api.spec.ts` runs under `test-sign-in.sh`. The web gateway caches answers, 404s included: each probe uses a fresh URL.
- **Delivered: Story 0.6.**
  - **`OcuTalon.Production`:** 38 items with final names and classes (18 Lane A, 20 Lane B; 35 enabled). Pool 0 for adapterless services, 1 otherwise; it starts with no model key. The future pollers (`HeartbeatIn`, `StatusMonitor`, `FailurePoller`) are adapterless stubs. `OcuTalonApprovals` (Lane A, Workflow) is not a stub; `OutcomeRouter` and `Notify` (Lane B) are routing engines naming `OcuTalon.Core.Rule.Outcome` and `.Notify`, whose empty rule sets carry `STUB`.
  - **Stubs:** an unbuilt item's one handler is `Quit $$$ERROR($$$NotImplemented)` with `Parameter STUB = 1`; the owner deletes both lines when it builds the item.
  - **The `Production` step** (Lane A): every start writes the System Default Setting `Enabled` for `EvalIn` from `OCUTALON_EVAL` (1 only for `"1"`), never `EnableConfigItem` (a class save drops the lane markers; 12.1's Telegram switch can reuse this), then (re)starts the production, recovering a Troubled one first, and fails when another production runs.
  - **Model:** `AgentRunner.ResolveModel(item, production)`: the adapter's `Model` setting (item, then System Default Setting), else the agent class's `MODEL` (`claude-haiku-5-5`).
  - **Extension bases** (`Bridge.Ext.HostSink`, `.ReplyFilter`, `.Classification`, do-nothing defaults): `HostSink.OnEvent(type, ownerRef, payload)`, `EVENTS` and the payload builders. `Core.BridgeSink` (Lane B) does nothing until 2.6; `Checks.ReplyGuard` (Lane A) passes text through until 5.7. `Bridge.Ext.Accessor.ClassFor(setting, production = "", item = "Decide", Output sc)` needs no running production; a bad class gives `""` and an error.
  - **Agent runners (AD-6):** `TriageAgent`, `DiagnosisAgent` and `ChatAgent` are `Bridge.Operation.AgentRunner` with the adapter `Bridge.Adapter.Agent` (`AgentClass` = `OcuTalon.Agent.Triage`, `.Diagnosis`, `.Chat`). The agent classes carry `MODEL` and `MOCKKEY` (`triage`, `diagnosis`, `chat`); `INSTRUCTIONS` and `TOOLSETS` are 1.1's.
  - **`Bridge.Context`** (`^||OcuTalonBP.Context`): `Begin(request, superSession = "")`, `End()`, `Active()`, `Current()`, `Put(name, value)` for `FIELDS` names only. **`Core.Commands.Submit(command, origin, Output result)`** has no role check; `CommandsIn` answers "Not implemented" until 2.3.
  - **`OcuTalon.Tools.Names`:** the 11 release-1 tool names, defined once (`RELEASE1`): `set_reminder`, `list_reminders`, `cancel_reminder`, `start_watch`, `stop_watch`, `list_productions`, `dismiss_incident`, `check_status`, `read_failed_messages`, `read_event_log`, `read_item_settings`. **`Bridge.Compaction.Prompt()`**: S18's schema text, first line starting `OCUTALON-COMPACTION-V1`.
  - **Cross-lane API stubs** (owner lane and story), pinned by `Test.Contract.Ac`'s signature oracle, which the owning lane keeps green: `Bridge.Approval` (`Raise`, `Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`; A, 3.4–3.6, 7.3); `Agent.Input.Render` (A, 1.3); `Checks.Render` (A, 5.7); `Bridge.Budget.State` (A, 1.4); `Bridge.Keys.Status` (A, 1.6); `Bridge.Timeouts.Derive` (A, 1.7); `Bridge.ConfigStore.Merge` (A, 1.1); `Data.Session.Recipients` (B, 2.2); `Data.Ownership.TurnCost`, `.RunCost` (B, 2.2, 2.6). Open return shapes are `%DynamicObject` with camelCase keys, or `%List`.
  - **Tests:** `Test.Install.Production`'s `Items()` is the one test copy of the item ownership table; live checks use `lib-live.sh`'s `item_jobs` and `check_items_run`. A stub's test instance comes from `Ens.Host.GetShadowInstance("class||<class>")`, never `%New("")`.
- **Delivered: Story 0.7** (the recipe and its timings are also in Rule 21).
  - **Workflows:** both run on pushes to `main`, `feature/OCT_OcuTalon_MVP` and `OCT-epic*` and on every pull request, unfiltered; only a pull request cancels its superseded run. `ci.yml` (Lane B): hosted `checks` (`bash ci/checks.sh`, never skipped) and `web` (the in-place build through `test-web-build.sh`, `lint`, `test`, then the step "Mock tests: none until Story 0.11", which 0.11 replaces); and the `iris` matrix of five groups (`install`, `production`, `browser`, `shards`, `image`) on `[self-hosted, ocutalon]`, behind the job-level fork guard, with tag `<run id>-<attempt>-<group>`, `OCUTALON_LIVE_DEADLINE` 1200 s and an `if: always()` teardown. `lane-a.yml` (Lane A): an empty `standalone-bridge` job on the same runner with the fork guard, which 1.3 fills.
  - **The skip rule (`ci/changes.sh`):** `web` and each `iris` job skip their own steps, never the job, against the newest commit in HEAD's history whose push run of the same workflow succeeded: `web` runs when `WEB_INPUT_PATTERN` changed (web sources, Live payloads, `SignInAssets`, the UX design folder, `logo/`, `ci/`, the workflow), `iris` when anything outside `_bmad/` and `_bmad-output/` changed (the UX design folder counts). Pull requests, no base and API errors run everything.
  - **The recipe `ci/iris.sh`:** one `OCUTALON_RUN_TAG` per run (lower-case, at least 3 characters, no `slot`), one piece per call: `build` (rebuilds the web bundle; the base image is never pulled), `shard <lane-a|lane-b> [--reverse]` (a fresh throwaway; one `CLASS <name> passed|failed <s>s` line per class), `class <Class>`, `live <name>` (`docker/tests/test-<name>.sh`), `group <name>` (`UNIT` lines), `teardown` (only that tag's projects, volumes, networks and images).
  - **`ci/units.sh`, the one list:** `CHECK_SCRIPTS` (hermetic and static), `WEB_SCRIPTS` (`web-build`), the shards `lane-a` (Agent, Bridge, Install) and `lane-b` (Contract, Core, Data, Live, Msg, Web), and the groups `install` (install-start, install-upgrade), `production` (production, production-restart, audit), `browser` (sign-in, bundle-folder), `shards`, `image` (storage-roundtrip, build-inputs, compose-start). A new `Test.<Area>` joins exactly one shard, and a new `docker/tests/test-*.sh` exactly one list or group, or `test-ci-config.sh` fails; a group change also changes `ci.yml`'s matrix line.
  - **`ci/checks.sh`** runs `CHECK_SCRIPTS`, naming the failed ones. **`ci/compose.ci.yml`** (`name: ocutalon-ci`) adds only the `OCUTALON_EVAL` passthrough; `test-compose-file.sh` pins that, so 0.11 updates the pin when it adds `mock`.
  - **New checks:** `docker/tests/lib-scan.sh` (shared `scan_files`, `scan_rule`, `bridge_refs`); `test-class-rules.sh` (the four rules above); `test-ci-config.sh` (static pins of the workflows and lists); `test-ci-changes.sh`; `test-storage-roundtrip.sh` (live, `image`); `test-bootstrap.sh`; `release-diff`; `Test.Web.Status` over all six public classes. The path and key scans read every tracked or new file, bookkeeping included: a spec or log citing a machine path turns CI red.
  - **The throwaway lock:** `lib-live.sh` holds `throwaway-iris.lock` in the coordination folder while a stack runs, naming `OCUTALON_LOCK_OWNER`; a long wait exits 75 (retry).
  - **Web scripts:** `lint` type-checks `web/e2e/**` and `playwright.config.ts` strictly (`tsconfig.e2e.json`) plus `node --check` of the build scripts; `test` is `node --test scripts/*.test.mjs`.
  - **The browser group** (`sign-in`, `bundle-folder`) publishes web port 52810 plus the runner's number; 0.8's demo-path specs run there.
  - **First real run:** 27 min 37 s against REL-4's 30 (`iris (install)` 14 min 35 s the largest; a ready stack 174 s, about three times the ARM figure). Escalated to the burn-down decision sheet: DW-20 (forms the public-package check doesn't read) and DW-21 (the margin depends on dispatch order; worst case about 32 minutes). Regrouping `ci/units.sh` is the lead's; changing the 30 minutes is the owner's.
  - **Owner-only, parked:** `/epic-cycle`'s gate reads one run per commit while each push has two; the lead checks both by hand.
- **Owner veto window (Rule 22.3), open:** 0.5's API rulings; 0.6's `Submit` trusting the caller's origin outside a bridge context, and the recover keeping queued synchronous messages Suspended; 0.7's actions and `@types/node`, the scan scope, the IRIS jobs' `actions: read`, the skip rule and the stricter key scan.
- **Developer slots:** `ocutalon-slot-a` and `-b` run `merge.cpf` without the after-start script: code goes in through the IRIS MCP tools, and IRIS can't read the repository. The after-start install and destructive tests run only in throwaway stacks (`ci/iris.sh`) and CI.
- **0.8 (next, Lane B):** one spec per UJ-1 step under `web/e2e/demo-path/`, unbuilt steps skipped so later stories turn them on. It consumes:
  - the `browser` IRIS group and `ci/iris.sh live` (locally `live sign-in` with one tag, then `teardown`; in CI `iris (browser)`). `test-sign-in.sh` already runs every spec under `web/e2e/`, so new specs need no workflow change. A new `test-*.sh` joins exactly one group and costs a stack start (3 to 4 minutes on the runner) against REL-4's thin margin (DW-21);
  - 0.3's `signIn()` (`web/e2e/sign-in/helpers.ts`) and `test-sign-in.sh`'s seeded stack;
  - `web/e2e/` and `web/playwright.config.ts`; `lint` type-checks each new spec;
  - the README account `ocutalon`/`ocutalon`, and 0.5's `main[data-snapshot=loaded]`, which the spec waits for;
  - AD-23's first-start timing, which 0.8 records for the README (x64, install included; one over about 12 minutes goes to the author). A data point: in 0.7's first run a throwaway stack (image build, first start, install) was ready after 174 s on the x64 runner, two jobs at once.
  - A failure fails the run; blocking the merge needs 11.5's branch protection.
- **0.9 (Lane B's after):**
  - `OcuTalon.Msg.Catalog.Core` and `.Watch` with every release-1 and 0.1.1 key, including those 0.4's `CatalogKey` and `Slots` name; `Catalog.Render(key, slots, channel)` on `Data.Time`, tested on every key and channel; and the test comparing the public package's text copies with the catalog. Its test classes join the shards by area.
  - **DW-12:** Task 0 measures, on a throwaway stack started with a compose-level `TZ`, whether a production job's `Data.Time.ToLocal` and `Zone()` use the container's zone; if not, the renderer passes the instance zone explicitly (AD-18).
- **0.10:** fills step 8, `Install.Step.Demo`, which reads demo mode through `Setting.Get`. Demo mode on: OCUORDERS (code and data databases, mappings), `OcuTalon.Demo.Orders.Production` running there (message classes, a partner service, the real transform failing on the changed date format) and the trace application through `Web.TraceApp("OCUORDERS")`. Off: no OCUORDERS. `eval/` gets one recorded failure snapshot of a date-format batch. A new `Test.Demo` area joins `lane-b`; live scripts join a group.
- **0.11 (last, Lane B):** adds the one mock service, `mock`, to `ci/compose.ci.yml`, which every IRIS unit already uses, and replaces the web job's "Mock tests" step with its tests (`ci/` is already a web input). It keys on 0.6's constants: `MOCKKEY` `triage`, `diagnosis` and `chat`, the `Tools.Names` values its default scripts call, and `OCUTALON-COMPACTION-V1`. Its scenarios cover what 1.6 to 1.9 need: `refusal` and `max_tokens`, an empty reply, a provider error, "Invalid input", an answer held past the bridge timer, 429/529 with `Retry-After`, and the summary and off-schema summary.
- **Handoffs outside Epic 0 (not built here):**
  - **2.2:** `ApiClient` sends the browser envelope through an interceptor (DW-14); `/state` and `/events` resolve the session through `Data.Ownership` (DW-15); `chat` and `rail`, the live-event service, Sign out through the API, and the purge (rows only, never the counter). **16.3:** the per-sign-in branch for the shared online-demo account (DW-16).
  - **1.3** fills `standalone-bridge`; Epic 9 adds the evaluation job to `lane-a.yml` with `OCUTALON_EVAL=1`; 11.5 protects the branch over the `ci` and `lane-a` checks.
  - **Epic 10:** `install.sh` uses `IRIS_IMAGE` and refuses Compose older than 2.24; 10.2's README states that minimum, the LAN-exposure warning, the password change and the IPM licence notice.
- **Later owners of Epic 0's stubs:** Epic 1 the bridge, agents, runners, `Decide`, budget, keys, timeouts, compaction and tools; Epic 2 the page, `Ownership`, `CommandsIn` routing (2.3), the Lane B items, `BridgeSink` (2.6), `Delivery` (2.7); Epic 3 approvals; 4.1 demo-mode switching; Epics 5–7 the watch, checks and fix items (5.7 `ReplyGuard`, `Checks.Render`); 8.3 reminders; Epic 9 `EvalIn`/`EvalSink`; 10.3 and Epic 12 Telegram; 11.5 the `STUB` check; Epic 15 `src/cpf/ocutalon.cpf` and `Registry.Run("ipm")`.
