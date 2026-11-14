# The bridge developer guide

The bridge is the part of OcuTalon that puts an AI decision inside an InterSystems IRIS Interoperability production, where you can audit it. A business process, `OcuTalon.Bridge.Process.Decide`, sends one request to an AI Hub agent, checks the reply, applies fixed rules outside the model, records the decision with its reasons, its tokens and its cost, and shows every step in Visual Trace. A tool that changes something waits for a person's approval as an IRIS Workflow task.

You can install the bridge on its own, in a production of your own, and this guide shows how with a small example that you start and send an item to. OcuTalon installs this same bridge as part of its own package. A separate bridge package and listing are a follow-on.

The commands of the marked blocks below are run line by line, as written, by the project's own automated check, in a clean namespace of a newly built test instance, so they stay true as the code changes. A second automated check compares the reference sections with the code, so a setting, a message field or a value that this guide does not name is a failing check.

## Install and run the example

### What you need

- InterSystems AI Hub, build 154, on IRIS for Health or on IRIS. Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet.
- An Interoperability namespace. In the Management Portal, open System Administration, then Configuration, then System Configuration, then Namespaces, and create a namespace with its own databases. Choose the option that enables the namespace for Interoperability productions. A namespace that is not enabled for it is refused by the installer.
- An account that can run the installer. It sets up security objects (audit events and a user), so run the steps below as an administrator.
- A model key from your model provider. This guide uses the `ANTHROPIC_API_KEY` variable (see "The key").
- The bridge source. The commands below use `/opt/ocutalon/src/bridge`, the folder where OcuTalon's image keeps it. Use the path of the `src/bridge` folder of your own copy of the repository instead.

Open a terminal session in your Interoperability namespace, for example with `iris session <instance> -U <namespace>` or with the terminal of the Management Portal. Each block below is a few commands, one per line. Paste the lines of a block in order. Each block ends by setting the variable `sc` to the status of its one action, and the text after the block says what a good result prints.

### 1. Load the bridge

The bridge loads from its source folder with `$SYSTEM.OBJ.LoadDir`. It needs no IPM and no other OcuTalon package.

<!-- guide-run: load -->
```objectscript
Set sc=$SYSTEM.OBJ.LoadDir("/opt/ocutalon/src/bridge","ck-d",.errors,1)
Write $SYSTEM.Status.IsOK(sc)
```

A good result prints `1`. The folder holds two packages, `OcuTalon.Bridge` (the bridge) and `OcuTalon.BridgeExample` (the example). Nothing else of OcuTalon is loaded.

### 2. Run the installer

`OcuTalon.Bridge.Installer` prepares the namespace and the instance for the bridge. It is safe to run again: it creates what is missing, and it writes its own structural rows back to their shipped state each time (the three model families, the audit events, and the Workflow user as the one member of its role, with its login disabled), so do not edit those. A price row that exists is left alone, so you can edit a price. It sets up:

- the audit events of `OcuTalon.Bridge.Audit`, registered and enabled (IRIS user-defined audit events);
- the approvals' Workflow role, `OcuTalonApprovals`, and its one Workflow user, `OcuTalonWorkflow`, with an IRIS user of the same name whose login is disabled and that holds no role (so no person can answer as the Workflow user);
- the model families (anthropic, gpt-5 and a default), each with the key that carries the output cap, and for the anthropic family the key that carries the effort, which are the defaults of how a request to each model is written;
- the prices of the two Claude models that the bridge ships with, in US dollars per million tokens.

It writes no System Default Settings row. The settings below keep the defaults that this guide lists until you write a row.

<!-- guide-run: install -->
```objectscript
Set sc=##class(OcuTalon.Bridge.Installer).Run()
Write $SYSTEM.Status.IsOK(sc)
```

A good result prints `1`. An error status names the namespace when it is not an Interoperability namespace.

IRIS writes an audit entry only while instance-wide auditing is on, and the bridge never changes that setting. Read it with `OcuTalon.Bridge.Installer.InstanceAuditing`: the call `Set sc=##class(OcuTalon.Bridge.Installer).InstanceAuditing(.on)` leaves `on` as `1` when auditing is on and `0` when it is off. To turn it on, open the Management Portal, System Administration, Security, Auditing, and choose Enable Auditing. With auditing off, the bridge still works and still records every decision in its own tables, but IRIS keeps none of its audit entries.

### The key

The model key is the environment variable `ANTHROPIC_API_KEY` of the IRIS process, set before IRIS starts (for a container, in its environment). The bridge reads it only through the placeholder `@{env:ANTHROPIC_API_KEY}` and never stores it: no setting, row, log or trace holds a key value. Set the variable before you run the `provider` block in step 3: the save checks the placeholder, so with the variable unset that block prints `0` and writes no row. If the variable is missing when a request is made, the request takes the fallback route with the reason `no_key`.

### 3. Point the runner at the provider

The example's one agent runner is the production item `TriageAgent`. AI Hub reads the runner's provider from the setting `ProviderConfig`. Write it as a System Default Settings row for the example production, as you would for a production of your own. The row holds the provider, the key placeholder and the timeouts.

The `http_config` of the row comes from `Timeouts.Derive`, which works out the request timeout and the retry rules that fit the bridge timer (60 seconds by default). Without it, AI Hub's own defaults apply (see "Timeouts"). Run this block once: the row exists after a first run, so a second run prints `0` and leaves it as it is. To change the row later, edit it in the Management Portal (Interoperability, Configure, System Default Settings).

<!-- guide-run: provider -->
```objectscript
Set pc={"model_provider":"anthropic","api_key":"@{env:ANTHROPIC_API_KEY}"}
Do pc.%Set("http_config",##class(OcuTalon.Bridge.Timeouts).Derive(60).%Get("http_config"))
Set r=##class(Ens.Config.DefaultSettings).%New()
Set r.ProductionName="OcuTalon.BridgeExample.Production",r.ItemName="TriageAgent",r.HostClassName="*",r.SettingName="ProviderConfig"
Set r.SettingValue=pc.%ToJSON()
Set sc=r.%Save()
Write $SYSTEM.Status.IsOK(sc)
```

A good result prints `1`.

### 4. Start the example

<!-- guide-run: start -->
```objectscript
Set sc=##class(Ens.Director).StartProduction("OcuTalon.BridgeExample.Production")
Write $SYSTEM.Status.IsOK(sc)
```

A good result prints `1`. The production has twelve items, ten of which run as jobs: the example's service `ExampleItemIn` takes items in; `ExampleTriage` turns an item into a request for the bridge; `Decide` is the bridge's process; `TriageAgent` runs the agent; `AgentSteps` records the agent's steps; `ExampleRouter` routes on the decision to one of the three outputs `ExampleNotifyOut`, `ExampleDigestOut` and `ExampleFallbackOut` (an `ignore` decision goes to none); and `ApprovalStartIn`, `ApprovalHold` and `OcuTalonApprovals` hold the approvals. Wait until the production shows as running in the Management Portal before you send an item.

### 5. Send an item

<!-- guide-run: send -->
```objectscript
Set sc=##class(OcuTalon.BridgeExample.ItemIn).Send("Invoice question","A customer asks where the invoice for order 1234 is.","untrusted",.iid)
Write $SYSTEM.Status.IsOK(sc)," ",iid
```

A good result prints `1`, a space and the item's reference. `Send` takes a subject, a body and the item's provenance (`user` for text a person wrote, `untrusted` for everything else), and leaves the item's reference in the last argument. Within a minute the agent has made its decision and the router has sent it to its output (an `ignore` decision goes to none).

### 6. Open the decision in Visual Trace

In the Management Portal, open the message viewer of the Interoperability menu, and find the newest message from `ExampleItemIn` to `ExampleTriage`. Click the row, then the Trace tab, then View Full Trace, or click the row's Session number. The header id is not a link. Visual Trace draws the whole decision as one session: the item, the request to `Decide`, the request to `TriageAgent` and its reply, one `OcuTalon.Bridge.Msg.AgentStep` message for each step of the agent to `AgentSteps`, the `OcuTalon.Bridge.Msg.DecisionResponse` that answers the request, and, unless the outcome is `ignore`, the routed message to an output. The trace's list also shows the bridge timer, which `Decide` sets as an `Ens.AlarmRequest` to `Ens.Alarm`. Open the `DecisionResponse` to read the outcome, the reasons, the confidence, the four token counts and the cost.

## Govern the example's tools

The example's tools are `example_count_items` (it only reads), `example_forward_item` and `example_archive_item` (each changes something). The tools hold no classification of their own. Two settings of `Decide` tell the bridge how to treat them: `ToolClassification` classifies two of the tools, and `ApprovalRole` names the role that may approve a held call. Both are read live, so run these two blocks at any time, before or after you start the example, with no restart. Run each block once: a second run prints `0` and leaves the row as it is. To change a value later, edit its row in the Management Portal (Interoperability, Configure, System Default Settings).

<!-- guide-run: tool-classification -->
```objectscript
Set tools=[{"class":"OcuTalon.BridgeExample.Tools","tool":"example_count_items","classification":"safe","readOnly":1},{"class":"OcuTalon.BridgeExample.Tools","tool":"example_forward_item","classification":"risky"}]
Set r=##class(Ens.Config.DefaultSettings).%New()
Set r.ProductionName="OcuTalon.BridgeExample.Production",r.ItemName="Decide",r.HostClassName="*",r.SettingName="ToolClassification"
Set r.SettingValue=tools.%ToJSON()
Set sc=r.%Save()
Write $SYSTEM.Status.IsOK(sc)
```

<!-- guide-run: approval-role -->
```objectscript
Set r=##class(Ens.Config.DefaultSettings).%New()
Set r.ProductionName="OcuTalon.BridgeExample.Production",r.ItemName="Decide",r.HostClassName="*",r.SettingName="ApprovalRole"
Set r.SettingValue="ExampleApprovers"
Set sc=r.%Save()
Write $SYSTEM.Status.IsOK(sc)
```

A good result of each block prints `1`. After the two rows are written, the Portal may show a notice that `Decide` needs an update. You can ignore it, because the bridge reads both settings live. The bridge then applies fixed rules to every call (see "Tool classification" for the rules). In a turn whose provenance is `user`:

- `example_count_items` is `safe` and read-only, so it runs.
- `example_forward_item` is `risky`, so a call is held for approval.
- `example_archive_item` has no entry, so it is unclassified, which counts as risky: a call is held for approval too.

In an untrusted turn, such as the item of step 5, which is sent as `untrusted`, only `example_count_items` can run: a call of either of the other two is denied and no approval request is raised. A held call can come only from an item sent with the provenance `user`.

A held call does not run. The bridge records an approval request, starts an IRIS Workflow task for the role `OcuTalonApprovals`, and tells the model that the call was held. When the request is approved, the bridge replays that one call once, with no model request. When it is rejected, or the request expires after 24 hours, the call never runs.

The role that may answer is the `ApprovalRole` setting, `ExampleApprovers` in the block above. The bridge does not create it, because the role is yours. Create it, and give it to each person who may answer:

1. In the Management Portal, open System Administration, then Security, then Roles, and create the role `ExampleApprovers`. It needs no resource.
2. Open System Administration, then Security, then Users, and add the role to each user who may answer.

A person answers through code that calls `OcuTalon.Bridge.Approval.Answer` with that person's IRIS user. `Answer` checks the role of the user it is given and does not compare it with the user of the session that calls it, so your code passes the signed-in user (for example `$USERNAME` in that person's own session) and limits who can call it. This snippet is an illustration of the call, not one of the steps above; run it from a privileged session, with your own values:

```objectscript
Set ref="<the Ref of the ApprovalRequest row>"
Set result=##class(OcuTalon.Bridge.Approval).Answer(ref,"approve","system","<the answering IRIS user>","",.winner)
Write result
```

The pending requests are the rows of the table `OcuTalon_Bridge_Data.ApprovalRequest` with State `pending`; each has a `Ref`, the `ToolName` and the `RequiredRole`. The result is one of `done`, `already_answered`, `expired`, `not_found` and `not_allowed`. The channel argument is one of the channels in "Messages and enumerations"; the fifth argument is the answering session's reference, named in the audit entry, or empty; `winner` holds the answer that won when the result is `already_answered`.

## Reference

### Settings

The bridge is configured only by settings. Each is a setting of a production item, or a System Default Settings row for the item, and the default applies until you set one. These settings are read each time they are used, so a change needs no update: `DecisionTokenBudget`, `RequestTokenLimit`, `DailyCostCapUSD`, `GatewaySpendUSD`, `GatewaySpendDate`, `InstanceZone`, `ServiceUser`, `ApprovalRole`, `ToolClassification`, `ClassificationClass` and `TurnToolsClass` of `Decide`, and `ReplyClass` and `RetryItem` of a runner. `Decide` reads `DecisionTokenBudget` and `RequestTokenLimit` this way only when it runs in a job of its own (a pool size of 1 or more, as in the example); in the shared actor pool, update the production after you change them. `HostSinkClass` is read each time too, except for the events that `Decide` fires itself, which follow a change only after `Decide` restarts. Every other setting takes effect when its item restarts: after you write or change one, update the production, for example with `Do ##class(Ens.Director).UpdateProduction()`. For `TimerSeconds`, see "Timeouts".

The settings of the `Decide` item:

| Setting | Default | What it does |
|---|---|---|
| `TimerSeconds` | 60 | How long `Decide` waits for the runner's reply, in whole seconds, from 12 seconds to 110 seconds. When it passes, the fallback route is taken with the reason `timeout`, unless the second-model retry is sent. The retry waits the lesser of `TimerSeconds` and 110 seconds minus the first attempt's timer. See "Timeouts" and "Second-model retry". |
| `DecisionTokenBudget` | 0 (none) | The token budget of each attempt of a decision, checked against the attempt's estimate before it is sent. A request whose estimate is above it takes the fallback route with the reason `budget`, and is never sent. A second-model retry is checked against it again, on its own estimate. The budget is not a total over both attempts. |
| `RequestTokenLimit` | 100000 | The largest request, in tokens. A request above it takes the fallback route with the reason `too_large`. An empty value, 0 or a value above 100000 counts as 100000. |
| `DailyCostCapUSD` | 0 (off) | The most the bridge may spend in a day, in US dollars. At the cap, requests take the fallback route with the reason `daily_cap`. |
| `GatewaySpendUSD` | empty | The spend that an outbound gateway reports for the day in `GatewaySpendDate`. Only a deployment with such a gateway sets it. |
| `GatewaySpendDate` | empty | The date, YYYY-MM-DD, that `GatewaySpendUSD` counts. |
| `InstanceZone` | empty (the container's time zone) | The time zone in which the bridge works out a day, an IANA name such as `Europe/Berlin`; the day of the daily cost cap ends at midnight in it. Read it with `OcuTalon.Bridge.Time.Zone` and change it with `OcuTalon.Bridge.Time.SetZone`, which refuses a name that is no zone; it applies to the next conversion with no restart. |
| `ServiceUser` | `OcuTalonService` | The IRIS user whose privileges the bridge checks for a tool that declares resources. OcuTalon's own install creates `OcuTalonService`. On your own instance, set it to an IRIS user of your own. The bridge checks it only for a tool that declares resources, and a user that does not exist holds nothing, so such a tool is denied. |
| `ApprovalRole` | `OcuTalonUser` | The role a person needs to answer an approval request. OcuTalon's own install creates `OcuTalonUser`. On your own instance, set the role you create, as the example does. An empty value refuses to raise a request. |
| `ToolClassification` | empty | The classification of your own tools. See "Tool classification". |
| `HostSinkClass` | `OcuTalon.Bridge.Ext.HostSink` | The class that receives the bridge's events. See "The extension classes". |
| `ReplyFilterClass` | `OcuTalon.Bridge.Ext.ReplyFilter` | The class that filters model-written text before a result leaves `Decide`. |
| `ClassificationClass` | `OcuTalon.Bridge.Ext.Classification` | The class that classifies tools beyond code and settings. |
| `TurnToolsClass` | `OcuTalon.Bridge.Ext.TurnTools` | The class that gives one request tools of its own, such as a knowledge base of the person's documents. See "The extension classes". |
| `McpServersClass` | `OcuTalon.Bridge.Ext.McpServers` | The class that names the MCP servers an agent attaches and receives the report of each attach. See "The extension classes". |

The settings of a runner item (the example's `TriageAgent`, which is an `OcuTalon.Bridge.Operation.AgentRunner`):

| Setting | Default | What it does |
|---|---|---|
| `AgentClass` | none | The agent class the runner runs, a subclass of `%AI.Agent`. This is an AI Hub setting. |
| `AgentAllowList` | the default is empty, which refuses every class | The agent classes the runner may run, comma-separated, each an exact class name. An empty list refuses every class. |
| `ProviderName` | none | The name of an AI Hub provider to use. Set it or `ProviderConfig`. This is an AI Hub setting. |
| `ProviderConfig` | none | The provider, the key placeholder and the timeouts, as inline JSON or as `@{config:<name>}`. This is an AI Hub setting. The example writes it in step 3. |
| `Model` | the agent's `MODEL` | The model of this runner. A row for it replaces the agent's `MODEL` for that runner (`claude-haiku-5-5` for the example). This is an AI Hub setting. |
| `Effort` | empty | How much effort an Anthropic model puts in: `low`, `medium` or `high`. Empty sends none. |
| `ReplyClass` | none | The class the runner's reply is checked against, for a decision. The example uses `OcuTalon.Bridge.Msg.DecisionPayload`. |
| `RetryItem` | empty | It names the retry runner of that runner: another enabled `OcuTalon.Bridge.Operation.AgentRunner` item of the production, whose `Model` setting is the second model. An empty value means no second model. See "Second-model retry". |

The allow-list is the safeguard that stops a setting from running an arbitrary class as an agent. For a production of your own, set `AgentAllowList` to your agent class, as the example's production does. The list that OcuTalon's own install writes for OcuTalon's runners holds OcuTalon's three agents; on your own instance you extend the list with your own class.

The agent's toolsets are the agent's `TOOLSETS` parameter: the example agent's is `OcuTalon.BridgeExample.ToolSet`. The output cap of a request is 8000 tokens. The bridge sets no `temperature`, `top_p` or `top_k` on any request.

Cost is priced from the price rows the installer seeds for `claude-haiku-5-5` and `claude-sonnet-5-5`. A model with no price row has an empty cost, never zero.

### Settings the bridge refuses

The bridge governs the agent's tools, so it refuses AI Hub's own settings that would give the agent tools or rules of its own. These runner settings must stay empty, and a runner whose setting is not empty is refused with an error that names the setting: `AuthPolicy`, `AuditPolicy`, `DiscoveryPolicy`, `IrisTools`, `AdditionalTools`, `IrisSkills`, `AdditionalSkills`, `SystemPrompt` and `SessionConfigString` (which may also hold `{}`). The agent's instructions, tools and skills come from its class.

### Timeouts

`TimerSeconds` is the one timer. A decision with a second-model retry has two attempts, which share the 110 seconds: the retry waits the lesser of `TimerSeconds` and 110 seconds minus the first attempt's timer (see "Second-model retry"). Two things depend on it, and `OcuTalon.Bridge.Timeouts` works both out so that no other place holds a second copy of a number:

- `Timeouts.Derive(timer)` returns the `timeout_ms` of the agent session (the timer minus 5 seconds, which bounds the tool loop) and the `http_config` of the provider: a `request_timeout_secs` and a whole `retry` block. The example's `provider` block writes `Derive(60).http_config` into the row.
- AI Hub waits for a provider's Retry-After header for as long as 30 seconds, and has its own default request timeout, when `http_config` has no complete `retry` block. Give the provider both.

The timer can be 12 seconds at the least and 110 seconds at the most. After you change `TimerSeconds`, edit the `ProviderConfig` row so that its `http_config` is the new `Derive(timer)`'s (for a retry runner, `Derive(Timeouts.RetryTimer(timer))`'s, see "Second-model retry") and update the production, or keep the provider in the Config Store as an entry and let `Timeouts.Apply(timer)` change the timer, the entries and the runners together. Apply needs each runner's `ProviderConfig` to be `@{config:<name>}`, and restarts `Decide` and the runners.

### Messages and enumerations

**`OcuTalon.Bridge.Msg.Request`** is what a caller sends to `Decide`. Its properties:

| Property | Meaning |
|---|---|
| `Kind` | One of the request kinds below. |
| `Provenance` | `user` or `untrusted`. |
| `Input` | The rendered text the agent reads. |
| `ItemId` | The item's reference. |
| `Summary` | One line the caller writes, up to 80 characters. Never model text. |
| `DecisionRef` | Set by `Decide` before it sends. |
| `OwnerRef` | The owner: a session's reference, `instance` or `eval`. |
| `TraceRef` | The reference of the session whose trace holds the messages. |
| `Channel` | One of the channels below. |
| `ThreadSessionId` | The caller's own trace session id. |
| `SessionMode` | `continue` or `fresh` (empty means `continue`). |
| `SeedText` | A recap the runner sends on a fresh turn of a conversation. |
| `SystemNote` | Text the runner sends before the input. |
| `Compact` | `Decide` sets it to 1 for a turn that is large enough to compact. |
| `RetryOf` | `Decide` sets it, on the one retry request it sends, to the first runner's item. A value that a caller sets is ignored. See "Second-model retry". |

**`OcuTalon.Bridge.Msg.DecisionResponse`** is the answer for a decision. It carries the result fields below and `Payload`, the checked reply as JSON. The fields that every result carries:

| Property | Meaning |
|---|---|
| `DecisionRef` | The reference of the decision's record. |
| `Outcome` | One of the outcomes below. |
| `Reasons` | The reasons, one per line. |
| `Confidence` | The model-reported confidence, 0 to 1. |
| `Fallback` | 1 when the fallback route was taken. |
| `FallbackReason` | One of the fallback reasons below, empty when `Fallback` is 0. |
| `InputTokens` | Input tokens of the turn: prompt, cache-read and cache-write together. |
| `OutputTokens` | Output tokens of the turn. |
| `CacheReadTokens` | Cache-read input tokens. |
| `CacheWriteTokens` | Cache-write input tokens. |
| `AgentStepCount` | The number of agent steps. |
| `DurationMs` | The duration of the turn in milliseconds. |
| `CostUSD` | The cost of the turn in US dollars. |
| `Model` | The model that answered. After a second-model retry, the second model; when the retry's timer passes before its reply arrives, the model of the last model request counted for the decision, which can be the first model. Empty when no model was asked. |

**`OcuTalon.Bridge.Msg.AgentStep`** is one step of an agent turn, sent to `AgentSteps`:

| Property | Meaning |
|---|---|
| `DecisionRef` | The decision the step belongs to. |
| `Position` | The step's position in the turn. |
| `StepKind` | `model` or `tool`. |
| `Label` | The readable name of the step. |
| `Summary` | A redacted one-line summary. |
| `DurationMs` | The duration of the step in milliseconds. |
| `Status` | `ok`, `denied` or `error`. |
| `EstimatedTokens` | An estimate, from AI Hub's callback data, of the size of the step's model request in tokens. It is not the tokens used, which are counted per turn. |

**`OcuTalon.Bridge.Msg.DecisionPayload`** is what the agent answers with, one JSON object with three fields: `outcome` (one of the outcomes below), `reasons` (a list of short sentences, at least one that is not blank) and `confidence` (a number from 0 to 1). A reply with another field, a field of the wrong type or a missing confidence is `invalid`.

The enumerations (`OcuTalon.Bridge.Msg.Enum`):

- Outcomes: `ignore`, `digest`, `tellnow`, `act`.
- Provenance: `user`, `untrusted`.
- Request kinds: `decide`, `diagnose`, `turn`, `tool`.
- Fallback reasons: `no_key`, `daily_cap`, `budget`, `too_large`, `timeout`, `rate_limited`, `error`, `refusal`, `cut_off`, `empty`, `invalid`, `unusable`.
- Approval states: `pending`, `approved`, `rejected`, `expired`, `cancelled`, `executing`, `done`, `failed`.
- Approval kinds: `fix`, `tool_call`, `setting`.
- Channels: `web`, `phone`, `mailbox`, `telegram`, `email`, `webhook`, `slack`, `system`, `heartbeat`.

The user rule: for a `decide` request whose provenance is `user`, `Decide` changes an `ignore` or `digest` outcome to `tellnow` and puts first the reason "The outcome was changed because a message the user writes is always answered." The item of step 5 is sent as `untrusted`, so there an `ignore` decision goes to no output.

### The fallback route

When the model cannot give a usable answer, `Decide` does not guess. When a second model is set, `Decide` may first try the request once on it, as "Second-model retry" says, and takes the fallback route only when no retry is sent or the retry gives no usable answer either. It records one decision with the outcome `tellnow`, `Fallback` 1 and the reason (after a retry, the last attempt's), keeps no model text, and answers with it, so that the person is told. A fallback starts no tool, fix or approval. The reasons:

- `no_key`: the key placeholder names a variable that is not set.
- `daily_cap`: the daily cost cap is reached.
- `budget`: the request is above `DecisionTokenBudget`.
- `too_large`: the request is above `RequestTokenLimit`.
- `timeout`: the timer passed before a reply arrived.
- `rate_limited`: the provider answered that the rate limit is exceeded.
- `error`: the provider call failed for any other reason.
- `refusal`: the model refused.
- `cut_off`: the reply was cut off before it ended.
- `empty`: the reply had no text.
- `invalid`: the reply did not pass the `ReplyClass` check.
- `unusable`: the agent used up its iterations or its loop stalled, or the provider gave no finish reason.

The example routes a fallback to `ExampleFallbackOut`, and it is in the decision's record and in Visual Trace with its reason.

### Tool classification

The bridge's gate decides every tool call, outside the model, before the tool runs. Its fixed rules, in order:

1. Classification. A tool is read-only (`safe` and `readOnly`), `safe`, or `risky`. Anything unclassified counts as risky. A tool is identified by its source class and its name, nothing in the call or the model's text changes it. The class's own code decides first (an `[ Internal ]` class method `Classify<NAME>` or `Classify`, or a class parameter `CLASSIFICATION<NAME>` or `CLASSIFICATION`, where NAME is the tool's name in upper case with `_` and `-` removed; what code declares is final). Then the `ToolClassification` setting of `Decide`: a JSON array of entries `{"class","tool","classification"}` with the optional flags `readOnly` and `trustedOutput` (each 1 or 0). Then the `ClassificationClass` extension. The setting never changes a classification that code gives. In this release, changing this setting writes no OcuTalon audit entry. Each tool call is recorded as a step of its decision unless the decision times out, and an approval and an approved call's run each write an audit entry.
2. Permissions. For a tool that declares `RESOURCES`, the `ServiceUser` must hold each privilege, or the call is denied.
3. Untrusted content and taint. A turn is untrusted when its provenance is not `user`, and tainted once a tool result that the bridge does not trust has reached the model. In an untrusted or tainted turn only a read-only tool runs; every other call is denied with the sentence "this turn holds content that did not come from the user, so only read-only tools can run in it and nothing was run; describe the action to the user as an offer they can ask for in their own turn.", and no approval request is raised.
4. The result. A safe call runs. Every other call is held: the bridge raises one approval request of kind `tool_call` and denies the call with "held for your approval; nothing was run."

### Workflow approvals

A held call becomes a row of `OcuTalon.Bridge.Data.ApprovalRequest` and an IRIS Workflow task for the role `OcuTalonApprovals`. The one member of that role is the technical Workflow user `OcuTalonWorkflow`, whose IRIS user cannot sign in. No person is a Workflow user, so nobody can answer from the Workflow inbox. A person answers only through `OcuTalon.Bridge.Approval.Answer`, which checks that the IRIS user it is given holds the request's `RequiredRole` (the `ApprovalRole` setting), saves the answer, completes the task, writes an Approval audit entry that names the person and the channel, and fires an event to the host sink.

The result of `Answer` is `done`, `already_answered` (with the answer that won), `expired`, `not_found` or `not_allowed`. A request that is not answered within 24 hours expires. An approved `tool_call` is replayed once; a rejected or expired one never runs.

### The extension classes

The bridge reaches your code only through five classes, each with a do-nothing default, so that the bridge runs alone. You extend a class and name the subclass in its `Decide` setting:

- `OcuTalon.Bridge.Ext.HostSink` (`HostSinkClass`): `OnEvent(type, ownerRef, payload)` receives the bridge's events: `turn.step`, `decision.recorded`, `approval.raised`, `approval.answered`, `approval.expired`, `approval.cancelled`, `approval.result` and `budget.capped`. It does nothing by default.
- `OcuTalon.Bridge.Ext.ReplyFilter` (`ReplyFilterClass`): `Filter(text, hostData)` returns the text to use in place of model-written text. For a chat turn, `hostData` is the reply's `HostData` JSON; otherwise it is empty. It returns the text unchanged by default.
- `OcuTalon.Bridge.Ext.Classification` (`ClassificationClass`): `Classify(source, name, arguments)` returns `safe` or `risky`, or empty for none; the gate calls it with the source and the name. It returns empty by default.
- `OcuTalon.Bridge.Ext.TurnTools` (`TurnToolsClass`): `Tools(ownerRef, kind, tools)` returns the tools to add to one request, each an object with `AddToManager(manager)`, such as an AI Hub knowledge base. When it returns any, the runner gives that request a new tool manager with the agent's own tools, the tools attached when the agent was built, these tools, the gate and the step audit, and puts the agent's own manager back afterwards; an agent that declares skills cannot take tools of its own this way. It returns none by default. Classify each tool it returns safe (a `ToolClassification` row): a call held for approval runs later on the agent's own tool manager, which does not hold these tools.
- `OcuTalon.Bridge.Ext.McpServers` (`McpServersClass`): `Servers(servers)` returns the MCP servers to attach, each an object with `server` and `config` (the name of a Config Store entry `AI.MCP.<name>`); `OnAttach(server, report)` receives the report of each attach: `status` (`attached` or `unavailable`), `reason`, the `tools` attached, the `refused` ones (a name that one of the agent's own tools, or the proxy `call_mcp_tool`, already has) and, for an attached server, their `fingerprints`. `Probe(server, config)` says whether a server answers before its tools are offered, and must return within a few seconds; `ProxyToolSet()` names the toolset of the one governed tool, `call_mcp_tool`, through which every MCP call runs; `ServerOf(toolref)` names the server of a toolref; and `ToolsReadOnly(server)` says whether every tool of a server is classified read-only. The agent's own tool manager holds no MCP server: each request gets a manager of its own with the proxy and the servers whose probe answered, an agent that declares skills gets no MCP tools, and an unavailable server never fails the build. It attaches nothing by default.

### Rules for your own tools

A tool is a public class method of a subclass of `%AI.Tool`, the way the example's `OcuTalon.BridgeExample.Tools` is written. The agent's toolset, a subclass of `%AI.ToolSet` named in the agent's `TOOLSETS`, gives each tool its name and the method that runs it: the example's `OcuTalon.BridgeExample.ToolSet` names the method `CountItems` `example_count_items`. That name is the one that `ToolClassification` and `STEPLABEL<NAME>` use.

- A tool runs inside a callback of AI Hub, where a session call can deadlock the job. It makes no `%AI` call and runs no embedded Python.
- It returns a dynamic object, or plain text.
- It declares a step label for Visual Trace, with the class parameter `STEPLABEL<NAME>` (the tool's name in upper case with `_` and `-` removed). The label holds no argument and no model text.
- It needs no classification in code. Classify it in the `ToolClassification` setting, and an unclassified tool is held for approval.
- A public method of a tool class becomes a tool, so the class has no other public method.

### Experimental

Two parts of AI Hub that the bridge builds on are experimental in build 154, so they may change:

- `OcuTalon.Bridge.Adapter.StepRenderer` extends `%AI.Shell.StreamRenderer`, which is experimental. It records one model step for every model response.
- The bridge adds its gate and its step audit to every agent with `ToolManager.SetAuthPolicy` and `ToolManager.SetAuditPolicy`, which are experimental.

## Where to go next

OcuTalon's own README describes the product that is built on this bridge. The bridge's classes are in `src/bridge/cls/OcuTalon/Bridge`, and the example is in `src/bridge/cls/OcuTalon/BridgeExample`.

## Second-model retry

A decision that gets no usable answer from the first model can be tried once on a second model before `Decide` takes the fallback route. Nothing turns this on by default: the install sets no second model, so `Decide` behaves as "The fallback route" says.

- `RetryItem` is a setting of a runner item, and `Decide` reads it. It names the retry runner of that runner: another enabled `OcuTalon.Bridge.Operation.AgentRunner` item of the production, whose `Model` setting is the second model. An empty value means no second model, and it is empty by default. A value that names the runner itself, a missing, disabled or non-runner item, or (for a decision or a diagnosis) an item whose `ReplyClass` is refused is not used: `Decide` logs one warning that names the setting and takes the fallback route. A retry runner's own `RetryItem` is never followed, so a retry is never retried. Write `RetryItem` as any setting in "Settings" is written. `Decide` reads it live, so it needs no update; a retry runner item that you add to the production starts when you update the production. The retry runner is set up like any runner: `AgentClass`, `AgentAllowList`, `ProviderConfig`, and `ReplyClass` for a decision or a diagnosis.
- `RetryOf` is a property of `OcuTalon.Bridge.Msg.Request`. `Decide` sets it, on the one retry request it sends, to the first runner's item. A value that a caller sets is ignored: `Decide` clears it on every first send and every re-send, and a request that carries one does not skip the wait for a conversation that is in use. The retry runner acts on `RetryOf` only when the named runner's `RetryItem` names it; for any other `RetryOf` it returns an error and sends nothing.

The retry is the same request, with the same `DecisionRef` and `ItemId`, sent once. The retry runner takes its session config from its own model's family, and the bridge sets no `temperature`, `top_p` or `top_k` on it. The retry runner has its own key check and its own budget and size checks before the request is sent.

The reasons that are retried once are `timeout`, `rate_limited`, `error`, `refusal`, `cut_off`, `empty`, `invalid`, `unusable` and `no_key` (for `no_key`, the retry runner's own key is the one that is checked). After `rate_limited`, `Decide` re-sends to the same runner as before while time remains, and the retry follows when no re-send fits. These are never retried:

- `daily_cap`, `budget` and `too_large`.
- An attempt in which a tool ran (`ToolsRun`).
- A turn of a saved conversation that failed because the provider rejected the stored conversation (its error holds "Invalid input"), and a request of the kind `tool`.
- A model test request (its `ItemId` starts with `test.`), so that the test says whether the first model answered.
- The retry itself. `Decide` does not send it again after `rate_limited`, and a fallback after it carries its reason.

A timer that fired leaves it unknown whether a tool ran, so an attempt whose timer fired is retried only when no tool can have changed anything. A `turn` whose timer fired is never retried: it takes the fallback route with the reason `timeout` (`rate_limited` when it had been re-sent after a rate limit). A `decide` or `diagnose` request whose timer fired is retried only when every tool of its agent is read-only by what the tool classes declare, and a toolset that this cannot be judged for counts as not read-only.

The two attempts share the 110 seconds. The first attempt keeps its timer T1: `TimerSeconds`, or 20 seconds more (at most 110) for a turn that is compacted first, and 0 when the first attempt was refused before it was sent. The retry waits T2, the lesser of `TimerSeconds` and 110 seconds minus T1. The retry is sent only when T2 is at least 12 seconds: when the first attempt waited the default 60 seconds, the retry waits 50 seconds, and when T1 is more than 98 seconds the retry is never sent. When it is not sent, the fallback route is taken with the first attempt's reason, and the decision's reasons read: "The second model was not tried, because too little time was left within the decision's 110-second limit." The retry runner's timeouts come from `Timeouts.RetryTimer(timer)`, the greater of 12 and the lesser of the timer and 110 minus the timer: its session's `timeout_ms` derives from it, and its `http_config` should be `Timeouts.Derive(Timeouts.RetryTimer(timer)).http_config`. `Timeouts.Apply(timer)` writes that `http_config` only for a retry runner whose name is its runner's name with `Retry` added (for the example, `TriageAgentRetry`) and whose `ProviderConfig` is `@{config:<name>}`. For any other retry runner, write it yourself, as step 3 does for `TriageAgent`. A reply that reaches `Decide` after its timer counts its cost and is dropped.

The decision is still one record and one answer. Its tokens, cost and steps are the sums of both attempts, its `Model` is as the `Model` field of `OcuTalon.Bridge.Msg.DecisionResponse` says, and, when both attempts fail, its reason is the last attempt's.

A retried turn of a conversation that the bridge saves runs without the conversation lock, in a new AI session. `Decide` seeds it with a code-written recap of the stored conversation as it stood before the turn (or with `SeedText` when the turn starts fresh), and the turn's input follows; nothing that the first attempt produced goes in. Only `Decide` moves a conversation to another AI session, and only when it accepts a reply as the decision's answer: a reply that reached it within its timer, is usable and is not tainted. A reply that `Decide` does not accept, the first attempt's or the retry's, moves nothing: the conversation stays in the AI session it was in.
