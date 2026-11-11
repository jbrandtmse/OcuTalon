# Epic 35 Context: Step 4's contracts: MCP servers attach, and webhooks bring events in (step 4)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 4's contract epic. It fixes step 4's names in the spine and in code so that Epics 21 (Lane B: email, webhook and MCP settings) and 22 (Lane A: MCP and source polls) can build in parallel. It also ships two working features. Registered MCP servers attach to the agents (done in 35.1). Webhooks, each with its own secret, turn any JSON event from another system into an untrusted item that gets an attention decision. Stories 35.1 and 35.2 are done and part-merged. Story 35.3 was parked for voting week and was un-parked on 2026-11-11. It builds the webhook end to end on the names, values and texts that 35.2 fixed.

## Stories

- Story 35.1: Fix step 4's contracts and register MCP servers (Lane A; done)
- Story 35.2: Fix Lane B's step 4 contracts (Lane B; done; its title still says "and send events to OcuTalon through a webhook" to keep its tracker key)
- Story 35.3: Send events to OcuTalon through a webhook (Lane B; follows 35.2; backlog, no spec yet)

## Requirements & Constraints

- **Create:** an admin creates a webhook in Settings > Channels with a name and a secret.
  - The secret is stored only as a salted hash. Its field is write-only and never shows the value again.
  - A value containing `@{` is refused.
  - The webhook's events belong to the admin's own session.
  - The change is audited without the secret.
  - The secret, and ideally its hash, never travels in a command or production message. The spine leaves that path to 35.3.
- **Accept:** a valid `POST` with the right secret and a JSON body under the cap gets 202 within 1 s, before any decision. `WebhookIn` then sends an untrusted Item to `Intake`, which decides afterwards. The event and its decision show in Visual Trace, in the event's own trace session.
- **Reject:**
  - An unknown webhook, a missing secret and a wrong secret all get the same 401. The secret is compared as a salted hash in constant time.
  - A body over the cap, or one that isn't JSON, is refused.
  - Nothing rejected becomes an item. Rejections are audited at a capped rate.
- **Unauthenticated-path test:** a test calls `/ocutalon/hook` and every other OcuTalon path without signing in. Only a webhook `POST` with its secret may be accepted, apart from the two exceptions the product already allows: the splash and sign-in pages, and the online demo's read-only status endpoint (`GET /ocutalon/public/status`). The criterion must name these exceptions or be restated.
- **Untrusted content:** a webhook payload can never approve, classify, change settings, add a server, pair a chat or be saved as a memory. On its own it leads only to read-only checks, a notification or the digest.
- **Texts:** ship only the webhook keys that 35.2 accepted, already in `OcuTalon.Msg.Catalog.Core` and `EXPERIENCE.md`:
  - `settings.webhooksHeading`, `webhooksHelp`, `webhookName`, `webhookSecret`, `webhookCreate`, `webhookAddress` (slot `address`) and `webhookNameTaken` (slot `name`);
  - the shared `settings.secretSet` and `settings.refusedExpansion`. `refusedExpansion` is stored with a `marker` text slot, so a producer passes `@{` as the slot value; its rendered text is the accepted wording.

  No story ships a text the author hasn't accepted. The hook's refusals have no body, so they need no text.
- **Online demo:** the proxy blocking the webhook path is the Contest Planner's release check, not this story's. Sprint planning flagged how the webhook behaves on the demo as a question for 35.3's spec gate.

## Technical Decisions

- **Spine:** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`. 35.3 builds what AD-13, AD-17, AD-19 and AD-24 (role list) record, with tables and the ERD (`Webhook`), the REST surface and cross-area rows, all marked `[ADDED 2026-11-09, Story 35.2]`. Build to those values; don't redefine them.
- **Hook application `/ocutalon/hook/`:**
  - It is created in `Install.Step.Web` (`Definitions`, `Apply`) as an unauthenticated application (`AutheEnabled` 64), outside the sign-in group, with no `Path`, `ServeFiles` 0 and `MatchRoles` `:OcuTalonWebhook`.
  - Its dispatch class is `OcuTalon.Web.Hook` (`%CSP.REST`, `UseSession` 0, its own `AccessCheck`).
  - It has one route, `POST /<ref>`. Every other method or path gets 404.
- **Request handling:**
  - The secret comes in the header `X-OcuTalon-Webhook-Secret`.
  - The body cap is 65,536 bytes, checked by the hook from the body's size. The API's 256 KB `BodyLimit` does not apply.
  - Checks run in this order: 401 (unknown ref, missing or wrong secret), then 413 (over the cap), then 400 (not a JSON object or array). Each refusal returns the status line only.
  - A valid request calls `WebhookIn` (adapterless, through `CreateBusinessService` and `ProcessInput` in the request's process). It sends the Item to `Intake` asynchronously, then returns 202 with no body.
- **Item:** `Channel` `webhook`, `Provenance` `untrusted`, `SessionRef` the owning session, `Subject` the webhook's name and `Text` the body as received. It runs in its own trace session whose SuperSession is the owning session's `TraceRef`. Start from the sibling `Channel/SimMailbox/In.cls`, which is untrusted, sends async to `Intake`, has its own trace session and a `Send` seam. Mapping each source's payload is deferred.
- **Table `OcuTalon.Data.Webhook`** (Lane B): `Ref`, unique `Name`, `SessionRef` of the owning admin session, `SecretHash`, `CreatedAt`. Only `SettingsOps` writes it; `Web.Hook` reads it. Creating it is a stored-data veto item at 35.3's spec gate.
- **`SecretHash`:**
  - The value is a random 16-byte salt and SHA-256(salt + the secret's UTF-8 bytes), stored as `salt.hash` in base64url.
  - The two hashes are compared over their whole length in constant time.
  - An unknown ref is compared against a fixed dummy hash, so it takes the same time.
  - Don't reuse `Data.Pairing.HashCode`, which is unsalted.
- **Creation route:** `POST /api/v1/settings/channels/webhooks` (name, secret), admin only, for the admin's own session, through `SettingsOps`. Today `POST /v1/settings/channels` answers 501 `NotBuilt`; the email values are Story 21.2's. Changing either route breaks `Test/Web/SettingsApi.cls` pins.
- **Rejection audit:** an `Action` entry through `OcuTalon.Bridge.Audit`, the only writer, with action `webhook_rejected`, channel `webhook`, target the ref (empty if unknown) and `counts.rejected`. At most one entry per 60 s per ref; unknown refs share one slot. The entry never holds the secret, a header, the body or the caller's address.
- **Role `OcuTalonWebhook`:** declared by `Install.Step.Web.Grants()` for the hook application alone; Lane A's roles step composes it. It holds only what the hook needs: read the row, record a rejection and hand off to `WebhookIn`. It never gets `%All` or an `%Ens_*` portal resource, and no user holds it. The grants (Read on the code database; Read and Write on the data and private databases) are an inference until Task 0 measures them.
- **Open items from 35.2's plan, for 35.3's plan:**
  - (a) Lane A's `Install/SecurityOverview.cls:418` heads its roles table "Roles added for every signed-in user", which is wrong for an unauthenticated application. This is a Lane A change or an intent gap. The security overview and `live:security-overview` need regenerating.
  - (b) These pins break: `Test/Web/Install.cls:53` (application list) and `:239-277` (`TestGrants`), `docker/tests/lib-live.sh:589-622` (`check_security`), and `docker/tests/test-online-demo.sh:469-472` ("exactly the five" applications).
  - (d) Task 0 runs on a throwaway: the least grants, the 202 within 1 s, and whether `%request.Content.Size` gives the size before parsing.
  - (e) The secret must stay out of every command and message.
  - (f) Whether to require a minimum secret length is a security choice for the veto window.
- **Lanes:** `Install/Step/Web.cls`, `Web/Api.cls`, `Web/Hook.cls`, `Data/Webhook.cls`, `Channel/Webhook/**`, `Core/SettingsOps.cls` and `web/src/app/settings/**` are Lane B's. The rest of `Install/**` and `Install/SecurityOverview.cls` are Lane A's.

## UX & Interaction Patterns

- Settings > Channels gets a "Webhooks" group. It has help text and a form with a name field, a write-only secret field and a "Create webhook" button. Under each webhook is its POST address, and a duplicate name gets a field error.
- A secret field that holds a value shows "Saved, and never shown again" and never shows the value.
- Today the page has `channels-section.ts` (Telegram, read-only), `settings-view.ts` (`SETTINGS_TEXTS`) and `refusal.ts`. The Catalog keys exist, but the page's own texts are still literals; 35.3 decides how the page reads them.

## Cross-Story Dependencies

- 35.3 consumes from 35.2: the spine entries (hook application, header, cap, ordering, hash format, audit cap, role, table, routes) and the webhook texts. It also relies on `Core.Admin.Held` and `Web.Api.IsAdmin()` for the admin check.
- The Item goes to existing Lane B and Lane A pipeline pieces: `Intake`, then `Decide`, then `OutcomeRouter`. 35.3 needs no new verb in `CommandsIn`.
- Outside this epic: Epics 21 and 22 wait for this epic to merge whole. Slack (Epic 27) arrives later through the same webhook route. The Contest Planner's demo-host release check covers the proxy blocking the webhook path.
