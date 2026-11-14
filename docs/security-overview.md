# OcuTalon security overview

The tool, fix kind and privilege sections below are written from the product by OcuTalon.Install.SecurityOverview and checked by automated tests.

<!-- BEGIN GENERATED tools: written by OcuTalon.Install.SecurityOverview, do not edit -->
## Built-in tools

No built-in tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL, and AI Hub's shell, filesystem, SQL and web-search tools are never registered. The automated tool-inventory test `OcuTalon.Test.Agent.Runners` (`TestToolInventory`) checks this on every running runner.

| Tool | Source class | Toolset | Agents | Step label | Classification | Read-only | Trusted output | Resources |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `call_mcp_tool` | `OcuTalon.Tools.McpCall` | `OcuTalon.Tools.McpProxy` | none | Running an MCP tool | per call: the admin's classification of the server's tool at its current fingerprint; unclassified counts as risky | no | no | none |
| `cancel_reminder` | `OcuTalon.Tools.ReminderTools` | `OcuTalon.Tools.Reminders` | `OcuTalon.Agent.Chat` | Cancelling a reminder | safe | no | yes | none |
| `check_status` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Reading the check results | safe | yes | yes | none |
| `dismiss_incident` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Dismissing an incident | safe | no | yes | none |
| `documents` | `%AI.RAG.KnowledgeBase` | `OcuTalon.Docs.Store` | `OcuTalon.Agent.Chat` | Running a tool | safe | yes | no | none |
| `forget_memory` | `OcuTalon.Tools.MemoryTools` | `OcuTalon.Tools.Memory` | `OcuTalon.Agent.Chat` | Forgetting a memory | safe | no | yes | none |
| `incident_summary` | `OcuTalon.Tools.RecentActivity` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Reading the incident summary | safe | yes | no | none |
| `list_memories` | `OcuTalon.Tools.MemoryTools` | `OcuTalon.Tools.Memory` | `OcuTalon.Agent.Chat` | Listing your memories | safe | yes | yes | none |
| `list_productions` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Listing the productions | safe | yes | yes | none |
| `list_reminders` | `OcuTalon.Tools.ReminderTools` | `OcuTalon.Tools.Reminders` | `OcuTalon.Agent.Chat` | Listing your reminders | safe | yes | yes | none |
| `propose_fix` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Asking to approve a fix | safe | no | yes | none |
| `propose_persona` | `OcuTalon.Tools.PersonaTools` | `OcuTalon.Tools.Persona` | `OcuTalon.Agent.Chat` | Suggesting a persona | safe | no | yes | none |
| `read_event_log` | `OcuTalon.Tools.WatchReads` | `OcuTalon.Tools.Watch` | `OcuTalon.Agent.Diagnosis` | Reading the event log | safe | yes | no | none |
| `read_failed_messages` | `OcuTalon.Tools.WatchReads` | `OcuTalon.Tools.Watch` | `OcuTalon.Agent.Diagnosis` | Reading the failed messages | safe | yes | no | none |
| `read_item_settings` | `OcuTalon.Tools.WatchReads` | `OcuTalon.Tools.Watch` | `OcuTalon.Agent.Diagnosis` | Reading the item settings | safe | yes | no | none |
| `recent_activity` | `OcuTalon.Tools.RecentActivity` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Reading recent activity | safe | yes | yes | none |
| `save_memory` | `OcuTalon.Tools.MemoryTools` | `OcuTalon.Tools.Memory` | `OcuTalon.Agent.Chat` | Saving a memory | safe | no | yes | none |
| `search_memories` | `OcuTalon.Tools.MemoryTools` | `OcuTalon.Tools.Memory` | `OcuTalon.Agent.Chat` | Searching your memories | safe | yes | yes | none |
| `send_digest` | `OcuTalon.Tools.DigestTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Sending your digest | safe | no | yes | none |
| `send_email` | `OcuTalon.Tools.EmailTools` | `OcuTalon.Tools.Email` | `OcuTalon.Agent.Chat` | Sending an email | per call: safe when every recipient is the user's own email address; otherwise risky, so it waits for approval | no | yes | none |
| `set_reminder` | `OcuTalon.Tools.ReminderTools` | `OcuTalon.Tools.Reminders` | `OcuTalon.Agent.Chat` | Setting a reminder | safe | no | yes | none |
| `start_watch` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Starting a watch | safe | no | yes | none |
| `stop_watch` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Stopping a watch | safe | no | yes | none |

One tool has no class of its own: `documents`, the search over your added documents that AI Hub's knowledge base gives the Chat agent. AI Hub sends no source class with its calls, so the gate classifies this one tool, and no other, by the bridge's classification setting: safe and read-only, but its output is never trusted, so a turn that searches your documents is treated as holding untrusted content. The gate also limits each search to 5 passages. Any other call that arrives without a source class stays unclassified and counts as risky.

<!-- END GENERATED tools -->

<!-- BEGIN GENERATED fix-kinds: written by OcuTalon.Install.SecurityOverview, do not edit -->
## Fix kinds

| Class | Name | Classification | Resources |
| --- | --- | --- | --- |
| `OcuTalon.Fix.Kind.Email` | `email` | risky | none |
| `OcuTalon.Fix.Kind.PartnerWarning` | `partner_warning` | risky | none |
| `OcuTalon.Fix.Kind.RepairResend` | `repair_resend` | risky | `%Ens_MessageResend:U` |
| `OcuTalon.Fix.Kind.Reroute` | `reroute` | risky | `%Ens_MessageResend:U` |
| `OcuTalon.Fix.Kind.ResumeItem` | `resume_item` | risky | `%Ens_ConfigItemRun:U` |
| `OcuTalon.Fix.Kind.SuspendItem` | `suspend_item` | risky | `%Ens_ConfigItemRun:U` |

On the online demo, OcuTalonServiceRole does not hold %Ens_ConfigItemRun:U, so OcuTalon can't suspend or resume items there.

<!-- END GENERATED fix-kinds -->

<!-- BEGIN GENERATED privileges: written by OcuTalon.Install.SecurityOverview, do not edit -->
## Privileges

### Roles

| Role | Resource | Permission | Declared by |
| --- | --- | --- | --- |
| `OcuTalonAdmin` | none | - | `Users` |
| `OcuTalonServiceRole` | `%Ens_ConfigItemRun` | U | `Fix` |
| `OcuTalonServiceRole` | `%Ens_MessageResend` | U | `Fix` |
| `OcuTalonTraceViewer` | `%DB_OCUTALON_CODE` | R | `Web` |
| `OcuTalonTraceViewer` | `%DB_OCUTALON_DATA` | R | `Web` |
| `OcuTalonTraceViewer` | `%Ens_MessageContent` | U | `Web` |
| `OcuTalonTraceViewer` | `%Ens_MessageHeader` | U | `Web` |
| `OcuTalonTraceViewer` | `%Ens_MessageTrace` | U | `Web` |
| `OcuTalonTraceViewer` | `%Ens_Portal` | U | `Web` |
| `OcuTalonUser` | none | - | `Users` |
| `OcuTalonWebhook` | `%DB_OCUTALON_CODE` | R | `Web` |
| `OcuTalonWebhook` | `%DB_OCUTALON_DATA` | RW | `Web` |
| `OcuTalonWebhook` | `%DB_OCUTALON_PRIVATE` | RW | `Web` |

### With demo mode on

| Role | Resource | Permission |
| --- | --- | --- |
| `OcuTalonServiceRole` | `%DB_OCUORDERS_DATA` | R |
| `OcuTalonTraceViewer` | `%DB_OCUORDERS_CODE` | R |
| `OcuTalonTraceViewer` | `%DB_OCUORDERS_DATA` | R |

### SQL privileges

| Role | Privilege | Object | Namespace | When |
| --- | --- | --- | --- | --- |
| `OcuTalonTraceViewer` | SELECT | `Ens.MessageHeader` | OCUTALON | always |
| `OcuTalonTraceViewer` | SELECT | `Ens.MessageHeader` | OCUORDERS | demo mode on |

### Service user

| User | Roles | Login |
| --- | --- | --- |
| `OcuTalonService` | `OcuTalonServiceRole` | disabled |

### Application roles

| Web application | Sign-in | Roles added to its requests |
| --- | --- | --- |
| `/ocutalon` | password | `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA`, `%DB_OCUTALON_PRIVATE` |
| `/ocutalon/api` | password | `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA`, `%DB_OCUTALON_PRIVATE` |
| `/ocutalon/hook` | none (unauthenticated) | `OcuTalonWebhook` |

<!-- END GENERATED privileges -->

## Limits of the privilege check

OcuTalon's production runs as IRIS's Interoperability system user, which holds `%All`. The service user is a privilege profile: the gate checks it before every tool call and the fix executor before every fix, but IRIS doesn't enforce it on the running code. The protections are the fixed tool inventory (no shell, no code, no data-changing SQL, tested), classification and approval, each fix kind's own validation, and the IRIS roles on the web and portal applications. Running tool code under the service user's own identity is deferred.

On every tool call, AI Hub (build 154) runs the two policies that OcuTalon installs on every agent:

- the gate, its authorization policy, which fails closed and checks the call's classification, the service user's IRIS permissions on the tool's declared resources (`$SYSTEM.Security.CheckUserPermission`) and the turn's provenance;
- the step audit policy, which records the call as an agent step.

The runner refuses settings that would replace these policies or register AI Hub's own IRIS tools.

No built-in tool declares a resource (the Built-in tools table), so no built-in tool needs a permission. The fix executor checks a fix kind's resources before every fix (the Fix kinds table).

OcuTalon reads a namespace only when the service user may read that namespace's data database, and the list of productions is filtered the same way. So any OcuTalon user can see evidence from every namespace whose data the service user may read (the Privileges section; with demo mode on, OCUORDERS).

## Approval and audit

Classification uses fixed rules outside the model: a class parameter or a per-call rule in code, and, for a developer's own tools, the bridge's classification setting, which never changes a classification that code gives. In this release, changing this setting writes no OcuTalon audit entry. Each tool call is recorded as a step of its decision unless the decision times out, and an approval and an approved call's run each write an audit entry. Anything unclassified counts as risky. Every built-in tool is safe. Repair and resend, the one risky built-in action, goes through a fix kind with a dry run.

Content that didn't come from the user (for example a simulated email, or a failed message's body):

- It is decided in a fresh session as untrusted.
- In such a turn, and in any turn that a tool result that isn't trusted output has tainted, only safe read-only tools run. Any other call is denied, nothing runs, and no approval request is raised.
- Such content can lead only to read-only checks, a notification to the user, an item saved for the digest or, for a failed message, a proposed fix that waits for a person's approval.
- Quarantine: a tainted turn's AI session isn't kept, and the next turn starts fresh from a recap that code writes.

Each risky action is one approval request, held as one IRIS Workflow task:

- It is fixed to exact targets and shows its dry run (a fix), or the tool, its MCP server when it has one, and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call).
- The first answer wins.
- It is re-checked before acting: the row must still be approved and unexpired, the service user must hold the kind's resources, and the kind runs its own re-check.
- It expires after 24 hours.
- A rejection runs nothing.

Who may answer:

- a holder of the role named in the bridge's approval-role setting, which OcuTalon seeds with `OcuTalonUser`;
- on the online demo, only the session that owns the request;
- never a tool's own job.

No person is a Workflow user: the Workflow role `OcuTalonApprovals` has one member, the login-disabled technical user `OcuTalonWorkflow`, so the Workflow inbox can't answer for anyone.

The audit log has one writer, the IRIS audit log, source `OcuTalon`. The types and what each records:

- `Action`: a fix run, a resend, a replayed tool call or Break the feed;
- `Approval`: answered, expired, cancelled, started or finished;
- `Pairing`: a chat paired, unpaired or refused;
- `Settings`: setting, from, to;
- `MCP`: a server added or removed;
- `Tool`: a tool's classification.

Every entry carries its time (the audit log's own timestamp), the IRIS user who acted or answered, the session and the channel. A redactor removes keys, access tokens, passwords and Telegram identities by their names and shapes, and a sensitive setting's values are blanked. Pairing, MCP and Tool entries are written only by the features that pair a chat, add or remove an MCP server, or classify an MCP tool, so a release without those features writes none of them.

Roles and accounts:

- `OcuTalonUser` signs in to the page and answers approvals.
- `OcuTalonAdmin` switches demo mode with the documented terminal command.
- `OcuTalonTraceViewer` is the trace role: Use on the four `%Ens_*` resources, Read on the data and code databases, `SELECT` on `Ens.MessageHeader`, and nothing on the private database.
- Anyone with the trace role can read the content of every item that reaches OcuTalon in Visual Trace and the message viewer, such as a chat message's text and an email's sender, subject and text.
- An email OcuTalon sends to the connected mailbox's own address keeps its subject and text in the trace, like a chat message. An email to anyone else keeps them only in its approval record. No email's recipients are in the trace. The trace does keep the chat's messages as written, so an address or text that you or OcuTalon wrote in the chat is in it.
- The local (README) account holds all three roles. The online demo account holds `OcuTalonUser` and `OcuTalonTraceViewer`. The read-only account holds `OcuTalonTraceViewer` alone.
- The read-only account opens only Visual Trace and the message viewer, through OcuTalon's trace applications, whose permitted classes are exactly seven: the six trace and message-viewer pages and `%CSP.Broker`. It can't use the OcuTalon page or its API.
- As the Privileges tables show, no OcuTalon role holds `%All`.

## Data

Storage:

- All data stays in OcuTalon's own IRIS databases: code, data (messages and Interoperability state), private, and a small public database (the sign-in page, the public status and the public settings only). Audit entries go to the instance's own audit log.
- Private records go to the private database through global mappings: conversations, sessions, decisions, incidents and AI sessions. A start check fails if one would land elsewhere.
- On an IPM install, OCUTALON also maps IPM's repository definitions (the globals `^IPM.Repo.Definition*`) from the namespace where the first install command ran, as they are, so the two namespaces share one list of repositories; uninstalling OcuTalon removes only that mapping.
- On an install where an admin signs a mailbox in with Google or Microsoft 365, IRIS's OAuth2 redirection endpoint `/csp/sys/oauth2` is turned on for as long as that sign-in is configured, and turned off again when it is removed, unless another OAuth2 client still needs it. The client secret is kept only in IRIS's OAuth2 client, and the tokens only in IRIS's OAuth2 token store. None of this runs on the online demo.

Data leaves the instance only:

- In model requests to the configured provider (Anthropic; Claude Haiku 5.5 by default). A request carries the agent's fixed instructions, the local time, the user's message or the arriving item (quoted as data), the conversation's history or a recap written by code, the tool definitions and the tool results. Daily notes and precedents also go to the configured provider inside requests: a person's turn that starts a session carries their daily notes for today and yesterday, which code builds from OcuTalon's own records, and the decision on an arriving item carries up to three of the person's earlier answers on items from the same sender or source. For a diagnosis, the results are the failed messages, the message headers of their trace, the event-log rows and the item settings, with credential settings left out and every value taken from the watched production passed through the redactor. A heartbeat check-in (a beat) sends the person's checklist and a status snapshot to the configured provider, at most once per interval. Run now sends the same kind of beat, at most once every 2 minutes per session and only within the daily cost cap.
- In messages on configured channels: OcuTalon's own web page, which IRIS serves to signed-in users, and, on an install with a Telegram bot token, the chat paired with a session, through the Telegram Bot API (its chat replies, notices, reminders and approval requests, and the answers to them).
- In calls to configured MCP servers, which this release can't make.

Model keys and bot tokens come only from environment variables. They are never stored in IRIS or shown. OcuTalon reports only whether a key is present.

Demo mode:

- With demo mode on, the Orders demo runs in namespace OCUORDERS, with its own code and data databases and the read grants of the "With demo mode on" table.
- Turning it off removes the namespace, its databases and those grants.
- An OCUORDERS that OcuTalon didn't create, or that holds another production, is kept. Only OcuTalon's own access is removed, and the status note says, word for word: "OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal."

Retention, by three daily tasks at 03:00 instance time:

- heartbeat and background-check messages after 7 days;
- every other production message and its Interoperability records after 90 days;
- decisions, usage, closed incidents and digest items after 90 days;
- live events after 24 hours;
- AI sessions that no conversation points to after a day.

The 7-day and 90-day counts are task settings, which an admin can change in the Task Manager. The chat history and the session records stay in the private database, and no scheduled purge removes them. Audit entries follow the instance's own audit retention. OcuTalon never changes the instance's auditing, and warns at start when auditing is off.

## MCP tools

This release can't connect to MCP servers. When a release adds MCP support, these rules apply:

- Only admins add or remove a server, only from the settings page, and nobody can on the online demo.
- Servers are reached only over HTTPS, and each server has its own IRIS resource that the service user must hold.
- A new server's tools arrive unclassified, which counts as risky.
- Tools are identified by server and name and never take a built-in tool's classification.
- A changed description or input schema makes a tool unclassified again. MCP annotations such as `readOnlyHint` are ignored.
- An MCP tool that runs commands must be classified risky.
- Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry (read-only calls included) and an agent step.
- Results are untrusted content.

## Online demo

The protections:

- Isolated sessions: on the OcuTalon page, each visitor sees only their own chat, decisions and approvals.
- A per-session message allowance, a public setting shown on the splash: 50 messages an hour by default.
- 20 simulated incoming emails per session per hour.
- 5 new sessions per client address per hour.
- A daily cost cap. Over it, decisions use fixed rules until the next day.
- The read-only account opens only Visual Trace and the message viewer.
- Public accounts can't change their own passwords: a password-validation routine, a proxy that admits only the sign-in fields, and the probe's sign-in check.
- The IRIS container has no general internet. Model traffic, and Telegram and allow-listed MCP traffic when the demo has them, leave only through an outbound gateway that holds the real model key and, when the demo has a bot, its token. The demo's IRIS holds only dummy values.
- Only the Orders production can be watched.
- OcuTalon puts no names, user names or phone numbers in the production messages of a visitor's session, which carry opaque references. The splash warns visitors not to type personal information, because Visual Trace is shared.
- Scheduled resets (every 4 hours by default) restore a clean copy with no visitor data.
- A monitoring probe checks the demo every 15 minutes.

Each protection listed here is checked against the running demo before every release.
