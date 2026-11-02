---
title: 'Story 14.2: The security overview says what OcuTalon can do and what stops it'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: 'fc2fcddef4eb67360dc0041c9577005fb4a587ed'
baseline_commit: 'fc2fcddef4eb67360dc0041c9577005fb4a587ed'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `docs/security-overview.md` lists the tools, fix kinds and grants (Story 14.1), but its five hand-written sections are still placeholders. So a reviewer can't see the limits of the privilege check, the approval and audit rules, where data goes, how MCP tools are governed or what protects the online demo. Until AD-24's Limits paragraph is there, the narrow generated grants overstate least privilege (DW-598).

**Approach:** Replace each `<!-- HAND-WRITTEN (Story 14.2) -->` placeholder with its section. Every statement must be true of the code on this branch, using the fact lists below. Extend the `overviewdoc` rule so the build fails while a placeholder remains, and so it pins the fixed sentences and the numbers to their code values. Add two author rows to the release checklist. Bring the overview into the public-text check's ASCII scope.

## Boundaries & Constraints

**Always:**
- Edit only outside the generated markers. Keep the five existing `##` headings, in their order. Write each paragraph or list item on one line (no hard wraps), in ASCII only.
- AD-24's Limits paragraph goes word for word, as one line, under `## Limits of the privilege check`, backticks around `%All` included: "OcuTalon's production runs as IRIS's Interoperability system user, which holds `%All`. The service user is a privilege profile: the gate checks it before every tool call and the fix executor before every fix, but IRIS doesn't enforce it on the running code. The protections are the fixed tool inventory (no shell, no code, no data-changing SQL, tested), classification and approval, each fix kind's own validation, and the IRIS roles on the web and portal applications. Running tool code under the service user's own identity is deferred."
- Claim only what is merged on this branch, using the fact lists in Tasks. Where the AC and the code differ, the code wins (Design Notes, "As-built differences").
- `live:security-overview` still passes. It regenerates and compares the whole file, so `--write` leaves the hand-written text byte-identical.

**Never:**
- Edit text between the markers, the generator, any contended path, `ci/units.sh`, `README.md`, EXPERIENCE.md or any `web/**` file. Never edit Epic 31's files or the About dialog.
- Name a host, address, IP, domain, URL or other private infrastructure detail. Name no rival entry. Never write "IRIS Couch" or OpenClaw.
- Claim anything that isn't merged: no WebSocket, no Telegram channel, no settings page, no approver or viewer roles, no MCP connection, no email sending.
- State any number that the code doesn't hold.
- Run, cut, tag or push a release.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| DW-598 placeholder | A line of the overview holds `HAND-WRITTEN` | `ovw_doc_problems` prints "a hand-written placeholder remains" | The `overviewdoc` rule FAILs |
| Limits paragraph | The paragraph is changed (for example `%All` without backticks) or is outside its section | Prints "the privilege-limits paragraph is not there word for word" | FAIL |
| DW-46 kept sentence | The sentence is extracted from EXPERIENCE.md, as `chk_demo_mode` does | The overview holds it word for word, `{what was kept}` included. Otherwise it prints "the kept-OCUORDERS sentence is not there word for word" | FAIL |
| MCP, none built | `git grep -q call_mcp_tool -- src` finds nothing | The first non-blank line under `## MCP tools` starts with "This release can't connect to MCP servers." Otherwise it prints a problem line | FAIL |
| Numbers follow code | Values read with sed: `EXPIRYSECONDS` in `Bridge/Approval.cls` (86400), the two `NumberOfDaysToKeep` and `DaysToKeep` in `Install/Step/Retention.cls` (7, 90), `DEFAULTLIMIT` and `EMAILLIMIT` in `Core/Allowance.cls` (50, 20), `ADDRESSLIMITSEED` in `Data/Setting.cls` (5), `TYPES` in `Bridge/Audit.cls` | These appear in their sections: "Approval and audit" holds "<seconds/3600> hours" and each audit type in backticks. "Data" holds "<7> days" and "<90> days". "Online demo" holds "<50> messages", "<20> simulated incoming emails" and "<5> new sessions". A missing phrase prints a problem line naming it | FAIL |
| No infrastructure | A `://` or an IPv4-shaped number anywhere in the overview | Prints "a URL or address" | FAIL |
| Regenerate | `ci/iris.sh live security-overview` | PASS: the whole file equals a fresh generation | DRIFT and exit 1 |
| Checklist | A record without the two new confirmations | `CONFIRM overview-review` and `CONFIRM demo-protections`, and Result `not confirmed`. With all seven ids confirmed, Result `pass` | Exit 1 until confirmed |
| Public text | `docker/tests/test-boundaries.sh` | The overview is in the ASCII-rule scope and in its must-scan list | A non-ASCII byte gives FAIL ascii |

</intent-contract>

## Code Map

- `docs/security-overview.md:85-101` -- the five placeholders (lines 85, 89, 93, 97, 101), under `## Limits of the privilege check`, `## Approval and audit`, `## Data`, `## MCP tools` and `## Online demo`. Everything down to `<!-- END GENERATED privileges -->` (line 81) is generated or the intro. Do not touch it.
- `docker/tests/test-release-sequence.sh:29-30` (rule header), `:1806-1885` -- `ovw_doc_problems` (the checks of the overview's frame) and `t_overviewdoc` (seven controls, each a copy of the committed file with one fault, compared with `eq` against exactly one problem line).
- `docker/tests/test-readme.sh:542-556` -- `chk_demo_mode`: the sed that extracts the kept-OCUORDERS sentence from EXPERIENCE.md. Read only.
- `release/checklist.sh:30-33,57,84-91` -- the author rows: the header list, `CK_AUTHOR_IDS` and `ck_author_text`. `author_rows` `:420-447` reads them generically.
- `docker/tests/test-release-checklist.sh:134,142,516,536,560,663-676` -- `CONF_IDS`, the confirmation writer and every count of CONFIRM or result lines: "five CONFIRM lines" (four places), "LINES 7", "LINES 5" and the comment "(2 rows and 5 author rows)".
- `docker/tests/test-boundaries.sh:89` -- the `files` scope of the ASCII rules (`docs/` is not in it). `:98-107` -- the first must-scan list ("not scanned"); `:108-114` the list for paths and keys. `test-readme.sh` `chk_must_scan` reads only the second list ("for paths and keys").
- Facts and their evidence (read only):
  - Gate and policies: `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:57,126,170,172` (`REFUSED`, `SetAuthPolicy` Gate, `SetAuditPolicy` StepAudit); `Policy/Gate.cls:106,141-151,262-269` (fails closed; untrusted or tainted turns run only safe read-only tools; `CheckUserPermission`).
  - Quarantine: `Core/Conversation.cls:403-405`.
  - Untrusted items: `Core/Intake.cls:16-19` and `Core/Rule/Outcome.cls:22-26` (digest or notify).
  - Approvals: `Bridge/Approval.cls:51` (`EXPIRYSECONDS = 86400`), `:80-84,316-320,392-395,630-633`. `Fix/Executor.cls:18-25` (resources, `StartExecution`, the kind's `Recheck`). `Watch/Transitions.cls:13` (a rejection reopens the incident).
  - Kinds: `fix,tool_call` (`Bridge/Msg/Enum.cls:21`).
  - `ApprovalRole` seeded `OcuTalonUser`: `Bridge/Process/Decide.cls:195`. Owning session on the online demo, and no answer from a tool's job: `Core/AnswersIn.cls:4-8`. `OcuTalonApprovals` / `OcuTalonWorkflow`: `Bridge/Installer.cls:118-193`.
  - Audit: `Bridge/Audit.cls:14-41` (types, `COMMON = "irisUser,sessionRef,channel"`, shapes). `Redact.cls:6-32` (keys, tokens, passwords, chat ids and user names). Written types: Action (`Fix/Executor.cls:596`, `Bridge/Replay.cls:153`, `Demo/PartnerTrigger.cls:62`), Approval (`Approval.cls:507`), Settings (`Core/SettingsOps.cls:106`). Pairing (`Core/SessionOps.cls:136`) comes only from Telegram, a stub here. MCP and Tool are never written.
  - Accounts: `Install/Step/Users.cls:17-21,37,46,49,354`; `Install/Step/Web.cls:29-30,131-136`; `Web/Public/Shell.cls:6`; `Web/Api.cls:147`; `Core/Admin.cls` (the only `OcuTalonAdmin` use).
  - Namespaces: `Watch/Reader.cls:73-87,162-169`.
  - Storage: `docker/merge.cpf:2-17`; `Install/Step/PrivateData.cls:1-4`.
  - Model request: `Agent/Input.cls:2-9`, `Adapter/Agent.cls:479-482`, `Core/Conversation.cls:70,73`, `Watch/EvidencePack.cls:4-32`, `Install/Step/Provider.cls:32,100`.
  - Channels: Telegram is a stub (`Channel/Telegram/Out.cls:1`, `Production.cls:16-17`). There is no SMTP, webhook or MCP client.
  - Retention: `Install/Step/Retention.cls:18-81`; `Bridge/Purge.cls:13-32`; `Live/Event.cls:48`; `Install/Step/Audit.cls:8,35`. No purge of `Data/Turn` or `Data/Session`.
  - Demo: `Core/Allowance.cls:22-31,238`; `Data/Setting.cls:12-15`; `Web/SessionEvents.cls:87-96`; `Install/Step/Public.cls:36,116`; `Data/Ownership.cls:5-23`; `Tools/WatchAnswers.cls:97`; `docker/probe.sh:2-42`; `release/demo-host-checks.md` H2-H25; `Msg/Catalog/Core.cls:435` (the splash's warning about personal information).

## Tasks & Acceptance

**Execution:**
- [ ] `docs/security-overview.md` -- Replace each placeholder with the facts below, in plain prose or short lists, and add nothing else. -- AC 1-5, DW-46, DW-598.
  - **Limits of the privilege check.**
    1. The AD-24 paragraph, verbatim (Always).
    2. On every tool call, AI Hub (build 154) runs the two policies that OcuTalon installs on every agent:
       - the gate, its authorization policy, which fails closed and checks the call's classification, the service user's IRIS permissions on the tool's declared resources (`$SYSTEM.Security.CheckUserPermission`) and the turn's provenance;
       - the step audit policy, which records the call as an agent step.
    3. The runner refuses settings that would replace these policies or register AI Hub's own IRIS tools.
    4. No built-in tool declares a resource (the Built-in tools table), so no built-in tool needs a permission. The fix executor checks a fix kind's resources before every fix (the Fix kinds table).
    5. OcuTalon reads a namespace only when the service user may read that namespace's data database, and the list of productions is filtered the same way. So any OcuTalon user can see evidence from every namespace whose data the service user may read (the Privileges section; with demo mode on, OCUORDERS).
  - **Approval and audit.**
    1. Classification uses fixed rules in code, outside the model: a class parameter, or a per-call rule. Anything unclassified counts as risky. Every built-in tool is safe. Repair and resend, the one risky built-in action, goes through a fix kind with a dry run.
    2. Content that didn't come from the user (for example a simulated email, or a failed message's body):
       - It is decided in a fresh session as untrusted.
       - In such a turn, and in any turn that a tool result that isn't trusted output has tainted, only safe read-only tools run. Any other call is denied, nothing runs, and no approval request is raised.
       - Such content can lead only to read-only checks, a notification to the user or an item saved for the digest.
       - Quarantine: a tainted turn's AI session isn't kept, and the next turn starts fresh from a recap that code writes.
    3. Each risky action is one approval request, held as one IRIS Workflow task:
       - It is fixed to exact targets and shows its dry run (a fix) or the exact call (a tool call).
       - The first answer wins.
       - It is re-checked before acting: the row must still be approved and unexpired, the service user must hold the kind's resources, and the kind runs its own re-check.
       - It expires after "24 hours" (from `EXPIRYSECONDS`).
       - A rejection runs nothing.
    4. Who may answer:
       - a holder of the role named in the bridge's approval-role setting, which OcuTalon seeds with `OcuTalonUser`;
       - on the online demo, only the session that owns the request;
       - never a tool's own job.
       
       No person is a Workflow user: the Workflow role `OcuTalonApprovals` has one member, the login-disabled technical user `OcuTalonWorkflow`, so the Workflow inbox can't answer for anyone.
    5. The audit log: one writer, the IRIS audit log, source `OcuTalon`. Each type in backticks, with what it records:
       - `Action`: a fix run, a resend, a replayed tool call or Break the feed;
       - `Approval`: answered, expired, cancelled, started or finished;
       - `Pairing`: a chat paired, unpaired or refused;
       - `Settings`: setting, from, to;
       - `MCP`: a server added or removed;
       - `Tool`: a tool's classification.
       
       Every entry carries its time (the audit log's own timestamp), the IRIS user who acted or answered, the session and the channel. A redactor removes every key, access token, password and Telegram identity, and a sensitive setting's values are blanked. This release writes `Action`, `Approval` and `Settings` entries. The other three types belong to features that aren't in this release.
    6. Roles and accounts:
       - `OcuTalonUser` signs in to the page and answers approvals.
       - `OcuTalonAdmin` switches demo mode with the documented terminal command.
       - `OcuTalonTraceViewer` is the trace role: Use on the four `%Ens_*` resources, Read on the data and code databases, `SELECT` on `Ens.MessageHeader`, and nothing on the private database.
       - The local (README) account holds all three roles. The online demo account holds `OcuTalonUser` and `OcuTalonTraceViewer`. The read-only account holds `OcuTalonTraceViewer` alone.
       - The read-only account opens only Visual Trace and the message viewer, through OcuTalon's trace applications, whose permitted classes are exactly the seven trace-page classes. It can't use the OcuTalon page or its API.
       - As the Privileges tables show, no OcuTalon role holds `%All`.
  - **Data.**
    1. Storage:
       - All data stays in OcuTalon's own IRIS databases: code, data (messages and Interoperability state), private, and a small public database (the sign-in page, the public status and the public settings only).
       - Private records go to the private database through global mappings: conversations, sessions, decisions, incidents and AI sessions. A start check fails if one would land elsewhere.
    2. Data leaves the instance only:
       - In model requests to the configured provider (Anthropic; Claude Haiku 5.5 by default). A request carries the agent's fixed instructions, the local time, the user's message or the arriving item (quoted as data), the conversation's history or a recap written by code, the tool definitions and the tool results. For a diagnosis, the results are the failed messages, the event-log rows and the item settings, with credential settings left out and every value taken from the watched production passed through the redactor.
       - In messages on configured channels. In this release the only channel is OcuTalon's own web page, which IRIS serves to signed-in users.
       - In calls to configured MCP servers, which this release can't make.
    3. Model keys and bot tokens come only from environment variables. They are resolved only inside AI Hub's provider and are never stored in IRIS or shown. OcuTalon reports only whether a key is present.
    4. Demo mode (DW-46):
       - With demo mode on, the Orders demo runs in namespace OCUORDERS, with its own code and data databases and the read grants of the "With demo mode on" table.
       - Turning it off removes the namespace, its databases and those grants.
       - An OCUORDERS that OcuTalon didn't create, or that holds another production, is kept. Only OcuTalon's own access is removed, and the status note says, word for word: "OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal."
    5. Retention, by three daily tasks at 03:00 instance time:
       - heartbeat and background-check messages after "7 days";
       - every other production message and its Interoperability records after "90 days";
       - decisions, usage, closed incidents and digest items after 90 days;
       - live events after 24 hours;
       - AI sessions that no conversation points to after a day.
       
       The day counts are task settings, which an admin can change in the Task Manager. The chat history and the session records stay in the private database, and no scheduled purge removes them (veto item V1). Audit entries follow the instance's own audit retention. OcuTalon never changes the instance's auditing, and warns at start when auditing is off.
  - **MCP tools.**
    1. The first sentence: "This release can't connect to MCP servers." Then: "When a release adds MCP support, these rules apply:"
    2. The rules:
       - Only admins add or remove a server, only from the settings page, and nobody can on the online demo.
       - Servers are reached only over HTTPS, and each server has its own IRIS resource that the service user must hold.
       - A new server's tools arrive unclassified, which counts as risky.
       - Tools are identified by server and name and never take a built-in tool's classification.
       - A changed description or input schema makes a tool unclassified again. MCP annotations such as `readOnlyHint` are ignored.
       - An MCP tool that runs commands must be classified risky.
       - Every call passes the gate, an approval request when needed (showing the exact call), an audit entry (read-only calls included) and an agent step.
       - Results are untrusted content.
  - **Online demo.** The protections:
    1. Isolated sessions: each visitor sees only their own chat, decisions and approvals.
    2. A per-session message allowance, a public setting shown on the splash: "50 messages" an hour by default.
    3. "20 simulated incoming emails" per session per hour.
    4. "5 new sessions" per client address per hour.
    5. A daily cost cap. Over it, decisions use fixed rules until the next day.
    6. The read-only account opens only Visual Trace and the message viewer.
    7. Public accounts can't change their own passwords: a password-validation routine, a proxy that admits only the sign-in fields, and the probe's sign-in check.
    8. The IRIS container has no general internet. Model traffic, and Telegram and allow-listed MCP traffic in a release that has them, leave only through an outbound gateway that holds the real model key and the demo bot's token. The demo's IRIS holds only dummy values.
    9. Only the Orders production can be watched.
    10. OcuTalon puts no names, user names or phone numbers in production messages, which carry opaque references. The splash warns visitors not to type personal information, because Visual Trace is shared.
    11. Scheduled resets (every 4 hours by default) restore a clean copy with no visitor data.
    12. A monitoring probe checks the demo every 15 minutes.

    Close the section with one sentence: each protection listed here is checked against the running demo before every release.
- [ ] `docker/tests/test-release-sequence.sh` -- Extend `ovw_doc_problems` with every check of the matrix (except Regenerate, Checklist and Public text): one problem line per fault, nothing for the committed file. In `t_overviewdoc`, add one control per new check, each a copy of the committed file with exactly that fault, compared with `eq` against its single problem line, as the existing controls are. Update the rule's header comment. -- DW-598, AC 1-5. Extends the rule that Story 14.1 added.
- [ ] `release/checklist.sh` -- Append two author ids to `CK_AUTHOR_IDS`, add their `ck_author_text`, and update the header list:
  - `overview-review`: "The hand-written sections of docs/security-overview.md were reviewed against this release, and each statement is true of it; the public-text row passed on the overview."
  - `demo-protections`: "Each online-demo protection that docs/security-overview.md states was checked against the running online demo for this release."
  -- AC 5 (And), AC 6. Runner ruling 4.
- [ ] `docker/tests/test-release-checklist.sh` -- Add the two ids to `CONF_IDS`. Update every count (five to seven CONFIRM lines, in all four places; LINES 7 to 9; LINES 5 to 7) and their comments. Assert both new CONFIRM lines and each row's detail text in the record's table. -- AC 6. Shared surface.
- [ ] `docker/tests/test-boundaries.sh` -- Add `docs/security-overview.md` to the `scan_files` arguments of `files` and to the first must-scan list, and say so in the PASS scope text. -- AC 6: the public-text check covers the overview.

**Acceptance Criteria:**
- Given the edited overview, when `bash docker/tests/test-release-sequence.sh overviewdoc` runs, then it passes, and each new control yields exactly its own problem line.
- Given the edited overview, when `ci/iris.sh live security-overview` runs on a fresh lane-D throwaway, then it prints PASS: the generated regions are unchanged, and the hand-written text survives a regeneration byte for byte.
- Given a release record without the two new confirmations, when `release/checklist.sh` runs, then it prints `CONFIRM overview-review` and `CONFIRM demo-protections`, and the result is `not confirmed`.
- Given `docker/tests/test-boundaries.sh`, when it runs, then it passes with the overview in scope, and a planted non-ASCII byte in a copy fails the ascii rule.
- Given the overview, when a reviewer compares each section with the fact lists above, then every listed fact is there and nothing else is claimed (manual check).

## Spec Change Log

- 2026-11-02, runner, after dev_complete (owner answers through the orchestrator): U-223 (keep the no-purge sentence; every 'this release' line must stay true of 1.0.0 at rc1) -- the lead rephrased three Data and audit lines so they stay true when Telegram ships: the audit line now says Pairing, MCP and Tool entries are written only by the features that pair a chat, add or remove an MCP server, or change a tool's classification; the channels line reads 'on configured channels, such as OcuTalon's own web page'; the key line drops 'resolved only inside AI Hub's provider'. No new claim. U-224 (keep stating the host-side protections; the Planner checked H10, H12, H23 by hand on 2026-11-02) -- `release/demo-host-checks.md` marks H10, H12, H23 `pass 2026-11-02 (by hand, Contest Planner); re-check at the release deploy`, its intro and status-value sentences say so, and `docker/tests/test-online-host.sh` accepts that fourth status (a bare `pass` still fails). Footprint extension: `docker/tests/test-online-host.sh` (uncontended). Checked: `test-release-sequence.sh overviewdoc`, `test-boundaries.sh`, `test-online-host.sh` exit 0.

## Review Triage Log

### 2026-11-02 — Review pass
- verdicts: 16 triage rows (findings grouped by shared claim) — high 0, medium 0, low 16, false 0, maybe-false 0
- findings:
  - `[low]` `[patch]` Phrase checks are bare substring matches ("17 days" holds "7 days", "25 new sessions" holds "5 new sessions"; Blind, Edge, Verification-gap, Intent) -- `ovw_phrases` now requires no letter or digit right before the phrase; controls added for "17 days"; mutation recorded.
  - `[low]` `[reject]` Two 90-day bullets and the 7-day bullet are not pinned per bullet; a swap between them passes (Blind, Verification-gap, Intent) -- the matrix pins the section holding the numbers; per-bullet anchoring adds scope beyond the AC; reopen_if a code change moves a number between bullets unnoticed.
  - `[low]` `[reject]` Numbers not in the matrix are not tied to code (03:00, live events 24 hours, "a day", 4-hour reset, 15-minute probe, four resources, seven classes, build 154, Haiku default, "per hour", "three daily tasks") (Blind, Edge, Verification-gap, Intent) -- the matrix names exactly which values are pinned; the others are covered by the `overview-review` and `demo-protections` author rows (V2, V4); pinning more is a scope addition; I spot-checked 03:00, 24 hours and seven classes against the code and they match.
  - `[low]` `[reject]` `git grep call_mcp_tool` sees tracked files only, matches any mention, exits 128 on a git error, and the check goes quiet once MCP lands (Blind, Edge, Verification-gap) -- the command is the matrix's own; a built MCP client forces an overview rewrite anyway, and the `mcp.md` control then needs the same update; reopen_if an MCP story lands.
  - `[low]` `[reject]` The `mcp.md` control depends on repo state (Verification-gap) -- same cause as the row above.
  - `[low]` `[reject]` `hours=$((v / 3600))` truncates a non-whole-hour expiry; "1 hours" and "1 days" grammar (Blind, Edge) -- the code holds 86400 and 7/90; no user-reachable failure today (theoretical).
  - `[low]` `[reject]` The Retention sed takes one count per line; a whitespace-only line passes `grep -m 1 .` (Edge) -- each count sits alone on its line today; theoretical.
  - `[low]` `[reject]` The kept sentence is searched in the whole file, not the Data section; the extraction stops at an inner quote (Edge, Intent) -- the matrix says the overview holds it word for word; EXPERIENCE.md quotes it without an inner quote.
  - `[low]` `[reject]` `OVW_LIMITS` is a copy of the AD-24 text (Edge) -- the spec requires the paragraph word for word and pins that copy; the source is in a planning file that a stage does not amend.
  - `[low]` `[reject]` The MCP second sentence and the closing demo sentence are not pinned; no controls for the "the code has no X" branches or a missing section (Edge, Verification-gap) -- the matrix does not require them; the branches fail closed.
  - `[low]` `[reject]` Prose points: "three daily tasks" above five bullets, "every built-in tool is safe" beside "the one risky built-in action", "one writer, the IRIS audit log", "documented terminal command", undefined terms (Blind, Edge, Intent) -- the wording is the spec's own fact text (runner-ruled); changing it is a spec edit.
  - `[low]` `[reject]` The URL rule matches only `://` and IPv4 shapes, may match a four-part version string (Blind, Verification-gap) -- the matrix defines it so; no such string is in the file.
  - `[low]` `[reject]` The `demo-protections` and `overview-review` rows rest on an unevidenced author line; the row text names the public-text row without enforcing it (Blind, Intent) -- author rows are by design (runner ruling 4); the public-text row runs `test-boundaries.sh`, which scans the overview.
  - `[low]` `[reject]` The release-scope claims (written audit types, only channel) have no repo-state guard like the MCP one (Verification-gap, Intent) -- V4 is decided; the `overview-review` row gates the release.
  - `[low]` `[reject]` The mutation table has no `mutation:` lines, and no non-ASCII mutation for `test-boundaries.sh` (Verification-gap) -- closed in this pass: the `mutation:` block under Verification records every mutation, run again by the parent, plus the non-ASCII one.
  - `[low]` `[reject]` Intent-alignment readings A-F and the Regenerate row not run by the diff (Intent) -- descriptive; `live:security-overview` printed PASS on a fresh lane-D throwaway.

## Design Notes

**Governing ADs:**
- AD-24: the Limits paragraph, roles, accounts, trace applications, and the overview never overstating least privilege.
- AD-3: namespaces, private records, Watch.Reader's read check, Orders-only on the demo.
- AD-10: gate, provenance, taint, quarantine, the inventory.
- AD-11: Workflow approvals, expiry, first answer, approval role.
- AD-17: one audit writer, types, redaction.
- AD-19: keys from the environment, the online-demo values.
- AD-21: MCP rules.
- AD-25: demo topology, gateway, probe, resets, capacity.
- AD-27: retention tasks.
- AD-16: fix kinds' own validation.

No AC contradicts an AD.

**Overview path for Story 31.3's About-dialog link: `docs/security-overview.md`**

**Integration ACs:**
- `live:security-overview` regenerates the edited file and must print PASS (the whole-file `cmp`).
- `release/checklist.sh` `author_rows` reads the two new ids and writes them into the record's table.
- The checklist's `public-text` row runs `test-boundaries.sh`, which now scans the overview.
- No consumer of the path in this story. The first is Story 31.3.

**Consumed-by:**
- Story 31.3 (the About link to the path).
- Every release's checklist (the two author rows).
- Story 11.14 (it runs `release/security-overview.sh` on the candidate, unchanged).

**Consumes:** Story 14.1's file, markers, generator and `overviewdoc` rule; EXPERIENCE.md's kept-OCUORDERS sentence; the code values listed in the matrix.

**Extend, don't copy:**
- `ovw_doc_problems` and `t_overviewdoc` (Story 14.1) are extended.
- The checklist's `CK_AUTHOR_IDS` and `ck_author_text` (Story 11.4) are extended.
- `test-boundaries.sh`'s scope lists are extended.
- The one copy is `chk_demo_mode`'s single sed line. `test-readme.sh` can't be sourced (it runs on load) and pins the README.

**Footprint extensions:** `docker/tests/test-boundaries.sh` and `docker/tests/test-release-checklist.sh`. Neither is contended. No contended path is edited.

**Ledger inbox:**
- DW-46 is addressed by the Data fact 4 sentence and the matrix row "DW-46 kept sentence".
- DW-598 is addressed by the Limits paragraph and the matrix row "DW-598 placeholder".

**Runner rulings recorded:**
1. The overview is `docs/security-overview.md`. The edits stay outside the markers. The drift unit and `--write` keep the text (the path line above).
2. The privilege sentence is copied word for word from the epic's AC, backticks included.
3. Public text claims only what is merged. Differences are below.
4. Two author rows go in `release/checklist.sh`, in its style. No release is run.
5. The public-text check is `docker/tests/test-boundaries.sh` (the checklist's `public-text` row). It already scanned the overview for paths and keys, and now covers it for ASCII too. It is not contended.
6. DW-598's check is in `overviewdoc`.
7. No contended path is edited, and there is no `ci/units.sh` change or new unit.
8. Every value was read from code. No runtime-only value is stated, so no IRIS call was made (no Task 0).

**As-built differences (code over AC wording; none changes a product promise):**
- Audit: all six types are registered, but this release writes only `Action`, `Approval` and `Settings`. `Pairing` needs Telegram (a stub), and `MCP`/`Tool` need step 4.
- Data: the only channel is the web page. Telegram is a stub, and there is no SMTP, webhook or MCP client.
- The gate's permission check: no built-in tool declares a resource. The only resource check is the fix executor's `%Ens_MessageResend` U.
- `setting` approvals (AD-11 amendment) are not built. Only `fix` and `tool_call` exist.

**Veto items for the runner (public text that no source states; the default text above ships unless vetoed):**
- V1: chat history and session records have no scheduled purge (as built; NFR-19 is silent about them).
- V2: the host-side demo protections (no general internet, the gateway and its keys, the proxy's sign-in filter, resets that restore a clean copy) are stated per AD-25, while `release/demo-host-checks.md` marks H10, H12 and H23 pending. The new `demo-protections` row checks them before 1.0.0.
- V3: the MCP section states rules "when a release adds MCP support" after the can't-connect sentence.
- V4: Epic 12 (Telegram) or Epic 31 merging before 1.0.0 makes the Data and audit lines about channels and Pairing stale. The `overview-review` row catches it. The orchestrator may want to tell those runners.

**Runner rulings at the spec gate (2026-11-02, policy 5086036):**
- V1 (no scheduled purge for chat history and session records): veto ruling, keep the as-built sentence (inbox U-223). Reversal: remove the sentence and route a retention story.
- V2 (host-side demo protections stated per AD-25 while H10, H12, H23 are pending): veto ruling, keep the AC's list with the closing sentence and the `demo-protections` checklist row (inbox U-224). Reversal: state the unverified host-side items only as checked before each release.
- V3 (MCP rules after the can't-connect sentence): decide, keep; the AC specifies both the rules and the first sentence.
- V4 (Epic 12 or Epic 31 merging before 1.0.0 makes the channel and Pairing lines stale): decide; the `overview-review` row gates the release, and the runner re-checks the Data and audit lines at its integrate-forward if Epic 12 has merged by then. Not this stage's work.
- As-built differences (audit types written, channels, gate permission check, setting approvals): decide; the overview states the as-built fact, which never overstates the product.

**Decided in-stage:**
- (a) `epic-14-context.md` is reused although `epics.md` is newer: its only change is the DW-598 line, which was read from `epics.md` directly.
- (b) One line per paragraph, so the checks can match sentences with `grep -F`.
- (c) The MCP check applies only while `src` has no `call_mcp_tool`.
- (d) `test-boundaries.sh` takes the one file, not all of `docs/`, so Epic 15's `docs/install-ipm.md` is not pulled into the ASCII rule by this story.
- (e) Number phrases are pinned to code values with sed, not as literals, so a code change without an overview change fails.
- (f) The gateway line names Telegram and MCP traffic conditionally ("in a release that has them").

## Verification

Every IRIS command runs from the worktree root with this prefix, `timeout: 600000`, one command per call:
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=14 stage=implement'`

**Commands:**
- (loop) `bash docker/tests/test-release-sequence.sh overviewdoc` -- expected: PASS.
- (loop) `bash docker/tests/test-release-checklist.sh` -- expected: exit 0.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- (once) `bash docker/tests/test-readme.sh`, then `bash docker/tests/test-release-notes.sh`, one per call -- expected: exit 0 (the must-scan reader and the checklist sourcer).
- (once) `bash docker/tests/test-release-sequence.sh` -- expected: no FAIL.
- (once) `<prefix> OCUTALON_RUN_TAG=e14s2impl bash ci/iris.sh live security-overview`, then `<prefix> OCUTALON_RUN_TAG=e14s2impl bash ci/iris.sh teardown` -- expected: PASS, then torn down.

**Mutations (Rule 19), one per AC; each is applied, observed red, and reverted to a byte-identical tree:**

| AC | Change | Expected red |
|----|--------|--------------|
| 1, DW-598 | Put a placeholder line back, or drop the backticks around `%All` | `overviewdoc` |
| 2 | The overview says "48 hours", or `Tool` is dropped from the audit types | `overviewdoc` |
| 3, DW-46 | One word of the kept sentence is changed | `overviewdoc` |
| 4 | The can't-connect sentence is moved below the first line | `overviewdoc` |
| 5 | "30 simulated incoming emails", or an `https://` link is added | `overviewdoc` |
| 6 | `overview-review` is dropped from `CK_AUTHOR_IDS`; the overview is dropped from the scope of `test-boundaries.sh` | `test-release-checklist.sh`; `test-boundaries.sh` scope |

mutation: (each applied, red observed, reverted; tree byte-identical afterwards, 2026-11-02)
- AC 1, DW-598: a `HAND-WRITTEN` line appended; `%All` without backticks -- `overviewdoc` FAIL both times.
- AC 2: "48 hours" for the expiry; backticks dropped from `Tool` -- `overviewdoc` FAIL both times.
- AC 3, DW-46: "because" changed to "as" in the kept sentence -- `overviewdoc` FAIL.
- AC 4: a line inserted under `## MCP tools` before the can't-connect sentence -- `overviewdoc` FAIL.
- AC 5: "30 simulated incoming emails"; "25 new sessions"; "17 days" for the 7-day bullet; an added link -- `overviewdoc` FAIL each. Reverting `ovw_phrases` to a bare substring match turns the "17 days" control red.
- AC 6: `overview-review` dropped from `CK_AUTHOR_IDS` -- `test-release-checklist.sh` FAIL (base, author, tmpfail); the overview dropped from the `scan_files` arguments -- `test-boundaries.sh` FAIL scope ("not scanned"); a non-ASCII byte planted in the overview -- `test-boundaries.sh` FAIL ascii.

**Shared surfaces:**
- `release/checklist.sh` `CK_AUTHOR_IDS`, pinned by `test-release-checklist.sh` (`CONF_IDS`, the counts);
- the scope and must-scan lists of `test-boundaries.sh`, read by `test-readme.sh` `must-scan`;
- `ovw_doc_problems` and its controls (`overviewdoc`);
- `docs/security-overview.md` itself, an `IRIS_INPUT` of every CI group, so the push runs every group. It is also compared by `live:security-overview`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Manual checks:** read each section against its fact list. There must be no host, address, rival name, unmerged feature or number missing from code.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The five hand-written sections of `docs/security-overview.md` replace the placeholders, using only the spec's fact lists, with the AD-24 paragraph and the kept-OCUORDERS sentence word for word. V1 stays as ruled (the sentence "no scheduled purge removes them" is in, without the veto label). The `overviewdoc` rule now fails on a remaining placeholder, a changed Limits paragraph, a changed kept sentence, a missing MCP opening sentence (while src has no `call_mcp_tool`), a number or audit type that no longer follows the code, and a URL or address. Two author rows were added to the release checklist, and the overview joined the ASCII scope of `test-boundaries.sh`.

**Files changed.**
- `docs/security-overview.md`: the five sections (outside the generated markers).
- `docker/tests/test-release-sequence.sh`: `ovw_doc_problems` checks and 14 new `t_overviewdoc` controls; the header comment.
- `release/checklist.sh`: `overview-review` and `demo-protections` in `CK_AUTHOR_IDS` and `ck_author_text`.
- `docker/tests/test-release-checklist.sh`: seven ids, counts (CONFIRM lines 5 to 7, LINES 7 to 9 and 5 to 7, PASS lines 16 to 18), the two rows' detail text, the leap-day case confirming the new ids.
- `docker/tests/test-boundaries.sh`: the overview in the `scan_files` arguments, the first must-scan list and the PASS text.

**Review.** Patches applied: 1 (low): phrase checks match from a non-alphanumeric boundary, with a control for "17 days". Deferred: 0. Rejected: 15 findings, each with its reason in the triage log. Follow-up review recommended: false (one low patch).

**Verification.** `test-release-sequence.sh overviewdoc` PASS; `test-release-checklist.sh` exit 0; `test-boundaries.sh` exit 0; `test-readme.sh` exit 0; `test-release-notes.sh` exit 0; full `test-release-sequence.sh` exit 0 with no FAIL; `ci/iris.sh live security-overview` (tag e14s2impl, lane D) PASS, then `ci/iris.sh teardown` removed everything (0 leftovers). The mutations in `## Verification` were run by the subagent and again by the parent after the last patch; all were red and reverted.

**Residual risks.** Numbers outside the matrix (03:00, 4-hour resets, 15-minute probe, build 154) are held only by the author rows. The host-side demo protections (H10, H12, H23) are pending in `release/demo-host-checks.md`; the `demo-protections` row checks them before 1.0.0. Epic 12 or Epic 31 merging makes the channel and Pairing lines stale (V4).

**Footprint extensions:** `docker/tests/test-boundaries.sh`, `docker/tests/test-release-checklist.sh` (approved, uncontended).
