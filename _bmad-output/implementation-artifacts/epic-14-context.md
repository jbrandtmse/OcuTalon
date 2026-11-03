# Epic 14 Context: A security reviewer can approve OcuTalon

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Give a security reviewer one document in `docs/` that lets them approve OcuTalon without reading its code. Parts of it are generated from the product: every built-in tool with its classification, every fix kind, the roles, and the service user's privileges. The hand-written parts state the limits of the privilege check, the approval and audit rules, what data leaves the instance, how MCP tools are classified and the online demo's protections. Tests fail the build when the generated lists drift from what ships or from the installed grants. The overview belongs to the 1.0.0 kit (must, never cut) and is regenerated and reviewed with every release.

## Stories

- Story 14.1: The overview's tool and privilege lists are generated from the product
- Story 14.2: The security overview says what OcuTalon can do and what stops it

## Requirements & Constraints

- **Generated tool section:** read agents, toolsets and tools through `%AI.Catalog` (pattern `OcuTalon.%`) and expand each toolset into its tools. Write one row per built-in tool: name, source class, the agents that can call it, step label, classification (or its `Classify(arguments)` rule in words), whether its output is trusted, and its declared `RESOURCES`. `recent_activity` (`OcuTalon.Tools.RecentActivity`) must appear as read-only with trusted output, and the drift test must pin it.
- **Generated fix-kind section:** one row per class under `OcuTalon.Fix.Kind`, with its `RESOURCES`.
- **Generated privilege section:** the privileges of `OcuTalonService`, composed from every tool's and fix kind's `RESOURCES` plus the installer's `Grants()` declarations, and the grants of `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`. It must list the service role's demo-mode-only Read on `%DB_OCUORDERS_DATA`, so it never overstates least privilege.
- **Markers:** the generator rewrites only what sits between the generated-section markers. Hand-written text outside them stays exactly as it is.
- **Drift test (CI):** compares the committed sections with a fresh generation, and the generated tool list with the tools every running runner's ToolManager holds. It fails and names the tool on any add, remove, rename or reclassification.
- **Privilege test:** reads the IRIS security records on a running instance. `OcuTalonService` and each role must hold exactly the listed privileges, no more and no fewer.
- **Tool-inventory statement:** no built-in tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL, and AI Hub's shell, filesystem, SQL and web-search tools are never registered. Name the automated inventory test that checks this.
- **Release:** the scripted release sequence regenerates the sections and stops if the drift test or the privilege test fails. A release-checklist item reviews the hand-written sections. Another checks each stated online-demo protection against the running demo before 1.0.0 and every later release. The public-text check must pass on the overview. The overview names no host, address or other private infrastructure.
- **Privilege-limits paragraph, verbatim:** "OcuTalon's production runs as IRIS's Interoperability system user, which holds `%All`. The service user is a privilege profile: the gate checks it before every tool call and the fix executor before every fix, but IRIS doesn't enforce it on the running code. The protections are the fixed tool inventory (no shell, no code, no data-changing SQL, tested), classification and approval, each fix kind's own validation, and the IRIS roles on the web and portal applications. Running tool code under the service user's own identity is deferred."
- **Demo mode off with OCUORDERS kept:** the overview carries the same sentence as the README and the `demoKept` status note: "OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal."
- **Data section:** all data stays in OcuTalon's own IRIS databases, with private records in the private database. Data leaves only in model requests to the configured provider (say what a request carries), in messages on configured channels and in calls to configured MCP servers. Model keys and bot tokens come only from environment variables and are never stored or shown. Retention: heartbeat and background-check messages are purged after 7 days; decisions, incidents and their traces are kept 90 days by default; audit entries follow the instance's own audit retention.
- **Online demo protections to list:** isolated sessions; the per-session message allowance (a public setting, 50 an hour by default); 20 simulated incoming emails per session per hour; 5 new sessions per address per hour; the daily cost cap; a read-only account that opens only Visual Trace and the message viewer; public accounts can't change their own passwords; no general internet, with model, Telegram and allow-listed MCP traffic leaving only through a gateway that holds the real model key and the demo bot's token; only the Orders production can be watched; no names, user names or phone numbers in production messages; scheduled resets and the monitoring probe.

## Technical Decisions

- **The gate** (`OcuTalon.Bridge.Policy.Gate`, an AI Hub Authorization policy) decides every tool call and fails closed. Its four steps:
  1. classification by (source, name): a class parameter or `Classify(arguments)` for built-ins, a bridge setting for a developer's own tools, the admin's fingerprinted table for MCP tools; anything else is unclassified, which counts as risky;
  2. the service user's permissions on the tool's declared resources, through `$SYSTEM.Security.CheckUserPermission`;
  3. provenance and taint: an untrusted or tainted turn runs only read-only tools, and quarantine keeps that content out of later turns;
  4. a risky or unclassified call in a user's turn raises one approval request. Risky built-in actions always go through a fix kind with a dry run; exact-call replay is only for MCP and developer tools.
- **Fix kinds** implement `DryRun`, `Recheck` and `Execute` against fixed targets. The executor trusts only the approval row, which must be approved, not expired and not already executing, and checks that the service user holds the kind's `RESOURCES` (for resend, `%Ens_MessageResend`). Only the rollback kind declares `%Ens_ProductionConfig` WRITE, and the overview must list it.
- **Roles:** `OcuTalonUser`, `OcuTalonAdmin`, `OcuTalonTraceViewer`, plus later-step approver, viewer and MCP-client roles. The trace role holds only Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`; Read on the data and code databases of OCUTALON and OCUORDERS (never the private databases); and SQL `SELECT` on `Ens.MessageHeader`. Its OCUORDERS grants exist only with demo mode on. No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig` (except the rollback case above) or the Workflow inbox. `OcuTalonService` has login disabled, no services and a random password.
- **Grant composition:** each area declares `Grants()` entries `{"role","resource","permission"}`, and one Lane A installer step composes every role from all of them. The service user's grants come from the same `RESOURCES` parameters the overview reads.
- **Audit:** `OcuTalon.Bridge.Audit` is the only writer, with source `OcuTalon` and types `Action`, `Approval`, `Pairing`, `Settings`, `MCP` and `Tool`. Every entry names the acting IRIS user, their role, the `SessionRef` and the channel, and passes the redactor. Every MCP call is audited, read-only ones included. OcuTalon has no audit table of its own.
- **Namespaces:** `Watch.Reader` reads a namespace only if the service user may read its data database, so any OcuTalon user can see evidence from every such namespace. The overview must say so.
- **MCP:** only admins add or remove servers, only from the settings page, and nobody can on the online demo. Servers are reached only over HTTPS, and each has its own resource, `OcuTalon_MCP_<server>`. Tools arrive unclassified, are identified by server and name, and a changed description or schema makes a tool unclassified again. Every allowed call goes through `call_mcp_tool`, gets an audit entry and an agent step, and its results are untrusted. If the release has no MCP support, the MCP section must say first that the release can't connect to MCP servers.
- **Secrets:** admin-entered secrets live in IRIS credentials, the OAuth2 client and the Wallet. Webhook secrets are stored as salted hashes. Every secret field is write-only.

## UX & Interaction Patterns

- The About dialog links to the security overview. Story 14.2 supplies the overview's path; Lane B's Story 31.3 adds the link.

## Cross-Story Dependencies

- **Epic-level:** Epics 3, 5 and 7 must be in place, because they provide the roles, the tools and the fix kinds the overview lists.
- **Story 14.1** needs Epic 11 merged (the release sequence, Story 11.5).
- **Story 14.2** needs Epic 11 merged (the release checklist) and Epic 16 merged (the online demo's protections it lists). It builds on Story 14.1's generated sections and markers.
- 1.0.0 is the first release: 0.1.0 and 0.1.1 are no longer cut.
