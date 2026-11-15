# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Incidents get more governed fixes and better cause-finding: suspend, resume, reroute and setting rollback as approved fixes, failures linked to recent setting changes, on-call paging with escalation, partner delay warnings sent only after approval, and a code-written summary when each incident closes. Queue backlog and saved SQL query watches report between digests (Could). Almost all of it has shipped. Story 23.8 (the SQL watch) is on hold. The next story is 23.13. It switches Story 23.5's partner warnings from Lane A's demo-only fixture to the partner contacts an admin sets in Settings, using Lane B's Story 24.2 table, which has merged. After 23.13, a warning on a real install goes only to the people that admin chose. On the online demo, warnings stay simulated.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Name the setting change behind an incident and offer its rollback (done)
- Story 23.4: Decide when to page the on-call person and when to escalate to the backup (done)
- Story 23.5: Draft partner delay notices that are sent only after approval (done)
- Story 23.6: Write an incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Watch a saved SQL query as a read-only SQL user (in progress, on hold)
- Story 23.9: Resume a suspended item after its incident closes (done)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (done)
- Story 23.11: Say in a partner notice only how the incident ended (done)
- Story 23.12: Take a rejected request off the status rail at once (done)
- Story 23.13: Partner warnings go to the Settings contacts (next)

## Requirements & Constraints

- **Only admin-configured contacts are ever sent to.** The approver sees the exact text and the exact recipients before anything is sent. Recipients are checked when the request is raised and again before sending. An address that isn't configured is refused and never used. A recipient removed since the dry run is skipped and reported.
- **The 23.13 switch:**
  - `Fix.PartnerContacts` reads a production's contacts from 24.2's table.
  - Its `TABLE` parameter is set to 1. That one switch also shows 24.2's Settings › Partner contacts section, which is hidden whenever `TABLE` isn't exactly 1. Pin both states.
  - DW-1394: at the real `TABLE = 1`, pin that the section shows, that both halves of `settings.partnersHelp` hold, and that warnings go only to listed contacts and only after approval. The help text is "Partner warnings go only to the people listed here, and only after you approve each one."
  - For an incident in a watched production, an approved warning goes only to the contacts set for that production.
- **DW-1254, contact ids:**
  - A partner warning names its contacts by id.
  - Contact names and addresses never appear in a traced message, a log or an audit entry beyond what DW-1254 allows. In Settings they travel only through `SecretHandoff`, which keeps them in memory only. Their audit entry holds `partnerContact.<Ref>` and which fields changed, never a value.
  - The leak scan must still pass after the switch.
- **DW-1393, de-duplication:** 24.2 accepts duplicate names and addresses, so `ForProduction` can return one address twice. De-duplicate recipients by address before drafting, raising and sending.
- **A warning never moves incident state.** The `partner_warning` kind has `MOVES` 0. Raising, approving, rejecting or expiring it changes no state and is not counted in the transition table.
- **Draft inputs come from code only:** the incident's count, times, affected flow, plain cause and 23.11's code-built Outcome line. They never include a message body, a sample error, a setting value or evidence. The notice body is approved model text, never a catalog template, and the executor sends it byte for byte.
- **The online demo:**
  - The partner-contact table is never written on the online demo.
  - Its Settings route answers 409 `not_available` before reading the body, and `GET /api/v1/settings` has no `partner-contacts` member there. The text is `settings.partnersOffOnDemo`: "…where partner warnings go to simulated contacts."
  - The demo's "Warn the partner" More-to-try step must keep working. The notice goes to the Simulated mailbox for the 23.10 recipient, "Orders Partner IT" <it@orders-partner.example>.
  - Sent notices count toward the demo's 20 simulated emails an hour.
  - No public text may say or imply that a real email was sent.
- **Delivery when demo mode is off:** with no SimMailbox, an approved notice is kept as an approved draft, with `result.partnerKept` saying email delivery isn't set up yet. It is never silently dropped. Real `EmailOut` delivery is parked until after voting.
- **Security:** an injected email can never add an address or trigger a warning; the gate denies an untrusted turn's `propose_fix`. `Execute` with no approved row sends nothing.
- Every user-facing text comes from an accepted catalog key.

## Technical Decisions

- **The kind (AD-16):**
  - The kind is `partner_warning`, with `TARGETTYPE` contact. Its targets are contact ids.
  - Its dry-run keys are `notice`, `recipients` and `simulated`. The approval payload's matching fields are `Notice`, `Recipients` and `Simulated`.
  - A `Ready` hook covers a kind whose delivery is not set up.
  - `FixExecutor` trusts only the approved row and delivers contact plans to `SimMailboxOut` as `Fix.Msg.PartnerNotice`. The subject comes from `partner.subject`.
  - The approver kind is `partner`.
- **Drafting (AD-15):** `IncidentManager` stays the only writer of incident state. It drafts a warning through an asynchronous self-sent `Watch.Msg.Draft` and an untrusted `Decide` turn with no actions, then raises the request as an extra approval in the incident.
- **Notices (AD-32):** producers never render text. Partner keys live under the `partner.` prefix in `Catalog.Watch`, and `press.approvedPartner` is in `Catalog.Core`.
- **24.2's table and reader (Lane B):**
  - The table is `OcuTalon.Data.PartnerContact`, in `^OcuTalonP.PartnerContact`. Its fields are `Ref`, `Name` (128), `Email` (254), `Productions` (a JSON array of namespace and production pairs), `CreatedAt` and `UpdatedAt`.
  - It is written only by `SettingsOps`. It has no purge, and a removed contact's row is deleted.
  - Lane A's only reader is `PartnerContact.ForProduction(namespace, production)`, which returns `[{id = row ID, name, address}]` in ID order. A contact matches only when one of its entries matches both values. The shape matches the fixture's `For(production)`.
  - The Settings route is `POST /api/v1/settings/partner-contacts`, kind `contacts`, admin only. The productions picker uses `ListProductions`.
  - `SettingsOps.PartnersShown` reads `$Parameter("OcuTalon.Fix.PartnerContacts","TABLE")` and returns 1 only for exactly 1. `TABLE` is a compile-time parameter.
- **Lane rules:**
  - Lane A owns `Fix/**`, `Watch/**` and the catalogs, and 23.13 edits `Fix.PartnerContacts`.
  - Lane A never edits Lane B's contracts, which include the partner-contact table, its route and `SettingsOps`.
  - Audit goes only through `OcuTalon.Bridge.Audit`.
  - Tests go in `OcuTalon.Test.Fix`. CI mock scenarios go under `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- The approval card shows the exact notice and every recipient, labelled simulated on the demo. After Approve, the Simulated mailbox shows the notice exactly as approved.
- Settings › Partner contacts sits after On call. Removing a contact asks `settings.partnerRemoveConfirm`: "Remove {name}? Partner warnings will stop going to {address}."

## Cross-Story Dependencies

- Lane B's Story 24.2 (the table, `ForProduction`, the Settings section and the `TABLE` read) has merged. Story 36.2 fixed the contract names.
- Story 24.4 (cards showing partner warnings) takes its recipients through 23.5's reader once 23.13 switches it.
- The epic chart puts 23.13 after 23.4 (done) and 23.8, but 23.8 is on hold. Whether 23.13 must wait for 23.8 needs a ruling.
- DW-1254's contact-id rest, DW-1393 and DW-1394 are routed to 23.13.
- Gaps:
  - The planning docs don't say how the reader picks the fixture on the online demo and in demo mode versus the table on a real install.
  - They don't say whether contact names may still go into the draft's facts, which is an untrusted Decide turn and so traced.
  - They don't say how the approver sees names and addresses if the warning carries only ids.
