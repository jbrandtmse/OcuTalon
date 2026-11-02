# OcuTalon security overview

The tool, fix kind and privilege sections below are written from the product by OcuTalon.Install.SecurityOverview and checked by automated tests.

<!-- BEGIN GENERATED tools: written by OcuTalon.Install.SecurityOverview, do not edit -->
## Built-in tools

No built-in tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL, and AI Hub's shell, filesystem, SQL and web-search tools are never registered. The automated tool-inventory test `OcuTalon.Test.Agent.Runners` (`TestToolInventory`) checks this on every running runner.

| Tool | Source class | Toolset | Agents | Step label | Classification | Read-only | Trusted output | Resources |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cancel_reminder` | `OcuTalon.Tools.ReminderTools` | `OcuTalon.Tools.Reminders` | `OcuTalon.Agent.Chat` | Cancelling a reminder | safe | no | yes | none |
| `check_status` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Reading the check results | safe | yes | yes | none |
| `dismiss_incident` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Dismissing an incident | safe | no | yes | none |
| `list_productions` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Listing the productions | safe | yes | yes | none |
| `list_reminders` | `OcuTalon.Tools.ReminderTools` | `OcuTalon.Tools.Reminders` | `OcuTalon.Agent.Chat` | Listing your reminders | safe | yes | yes | none |
| `read_event_log` | `OcuTalon.Tools.WatchReads` | `OcuTalon.Tools.Watch` | `OcuTalon.Agent.Diagnosis` | Reading the event log | safe | yes | no | none |
| `read_failed_messages` | `OcuTalon.Tools.WatchReads` | `OcuTalon.Tools.Watch` | `OcuTalon.Agent.Diagnosis` | Reading the failed messages | safe | yes | no | none |
| `read_item_settings` | `OcuTalon.Tools.WatchReads` | `OcuTalon.Tools.Watch` | `OcuTalon.Agent.Diagnosis` | Reading the item settings | safe | yes | no | none |
| `recent_activity` | `OcuTalon.Tools.RecentActivity` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Reading recent activity | safe | yes | yes | none |
| `set_reminder` | `OcuTalon.Tools.ReminderTools` | `OcuTalon.Tools.Reminders` | `OcuTalon.Agent.Chat` | Setting a reminder | safe | no | yes | none |
| `start_watch` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Starting a watch | safe | no | yes | none |
| `stop_watch` | `OcuTalon.Tools.WatchTools` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Stopping a watch | safe | no | yes | none |

<!-- END GENERATED tools -->

<!-- BEGIN GENERATED fix-kinds: written by OcuTalon.Install.SecurityOverview, do not edit -->
## Fix kinds

| Class | Name | Resources |
| --- | --- | --- |
| `OcuTalon.Fix.Kind.RepairResend` | `repair_resend` | `%Ens_MessageResend:U` |

<!-- END GENERATED fix-kinds -->

<!-- BEGIN GENERATED privileges: written by OcuTalon.Install.SecurityOverview, do not edit -->
## Privileges

### Roles

| Role | Resource | Permission | Declared by |
| --- | --- | --- | --- |
| `OcuTalonAdmin` | none | - | `Users` |
| `OcuTalonServiceRole` | `%Ens_MessageResend` | U | `Fix` |
| `OcuTalonTraceViewer` | `%DB_OCUTALON_CODE` | R | `Web` |
| `OcuTalonTraceViewer` | `%DB_OCUTALON_DATA` | R | `Web` |
| `OcuTalonTraceViewer` | `%Ens_MessageContent` | U | `Web` |
| `OcuTalonTraceViewer` | `%Ens_MessageHeader` | U | `Web` |
| `OcuTalonTraceViewer` | `%Ens_MessageTrace` | U | `Web` |
| `OcuTalonTraceViewer` | `%Ens_Portal` | U | `Web` |
| `OcuTalonUser` | none | - | `Users` |

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

| Web application | Roles added for every signed-in user |
| --- | --- |
| `/ocutalon` | `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA`, `%DB_OCUTALON_PRIVATE` |
| `/ocutalon/api` | `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA`, `%DB_OCUTALON_PRIVATE` |

<!-- END GENERATED privileges -->

## Limits of the privilege check

<!-- HAND-WRITTEN (Story 14.2) -->

## Approval and audit

<!-- HAND-WRITTEN (Story 14.2) -->

## Data

<!-- HAND-WRITTEN (Story 14.2) -->

## MCP tools

<!-- HAND-WRITTEN (Story 14.2) -->

## Online demo

<!-- HAND-WRITTEN (Story 14.2) -->
