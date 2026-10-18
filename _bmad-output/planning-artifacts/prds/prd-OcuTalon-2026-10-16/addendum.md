---
title: OcuTalon PRD Addendum
status: final
created: 2026-10-16
updated: 2026-10-17
---

# Addendum: OcuTalon PRD

This addendum holds depth that belongs to architecture and implementation rather than to the PRD: platform facts tested on AI Hub build 154, mechanisms, and options considered. Requirement IDs refer to `prd.md`. Where this file and the PRD differ, the PRD wins.

- **Layout.** §1 to §3 hold platform facts, §4 to §17 hold mechanisms in the order of the PRD's features, and §18 lists the options considered.
- **Tested or not.** Facts are tested on build 154 unless marked untested. The open items below list everything still to test or decide.
- **Superseded by the architecture.** The architecture spine (`../../architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`) settled every open item below on October 17 and is the source for mechanisms. Notes it overtook are marked *Superseded* or *Decided* in place and kept for history.

## Open items

*All of these were settled on October 17, before the epics were written: see the spine's Spikes table and the ADs named in place below.*

**To test**, each before the work that depends on it:

| Item | When | Where |
| --- | --- | --- |
| How AI Hub surfaces a refusal or a `max_tokens` stop | Start of step 1 (FR-4) | §2 |
| Whether the provider config can pass `output_config.effort` | Architecture | §2 |
| The IRIS (non-Health) build 154 image | Done October 17; treated as equivalent to IRIS for Health (NFR-21) | §1 |
| Where FastEmbed looks for its cache when the database is on durable storage | Step 3 (FR-41) | §11 |
| The MCP client, and whether AI Hub policies cover remote tools | Before step 4 | §13 |
| `%AI.MCP.Service` and `iris-mcp-server` | Before step 7 | §13 |

**To decide in architecture:**

| Item | Where |
| --- | --- |
| What to do with the IRIS for Health template production | §1 |
| Whether the bridge ships as its own IPM module (Open Question 6) | §4 |
| How the production watch reacts within 15 seconds (FR-23) | §9 |
| How waiting reminders and approval requests survive upgrades (FR-60) | §10 |
| Durable storage or a plain container for the judges' install | §14 |
| Plan B if CI can't mock the Anthropic path (REL-4) | §16 |

## 1. Platform facts

- **Images.** IRIS for Health AI Hub Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`) is the primary image. The IRIS (non-Health) build 154 image is supported too: it differs only by the HealthShare libraries and the HSCUSTOM namespace (NFR-21).
  - The built-in web server is on, so no separate web gateway container is needed.
  - The documentation online is written for a later build (162), so check every API against build 154 before relying on it.
- **Namespace (FR-56).** Out of the box, Interoperability is enabled only in USER, so OcuTalon creates the OCUTALON namespace with a CPF merge file at startup (`ISC_CPF_MERGE_FILE`).
  - OCUTALON has separate code and data databases on durable storage.
  - The merge re-applies cleanly on every start.
  - `%Service_CallIn` must be enabled for Embedded Python.
- **IRIS for Health installer.** Enabling Interoperability in a namespace runs the "Foundation" installer, which creates a template production and roles. OcuTalon's own production replaces the template as the namespace's production; architecture decides whether to remove the template. *Decided (AD-3): the template stays installed and stopped.*
- **One production per namespace.** A namespace runs one production at a time, so the Orders production lives in its own namespace (FR-16, FR-56; §7).
- **Default password.** The predefined `_SYSTEM` password (`SYS`) may be expired at first start. The install sets the account and password the README names, so no first sign-in forces a password change (FR-14, FR-55).
- **Harmless startup noise:** `<METHOD DOES NOT EXIST>Sharding+2^STU` and `<CLASS DOES NOT EXIST>GetCacheDirs`.
- **Startup time.** With durable storage and the namespace merge, the first start takes 5 to 8 minutes on an Apple silicon Mac; allow more on slower hosts. Later starts take about 3 minutes. The image has no health check of its own, so the compose file defines one (§14). *Measured later (AD-23): about a minute for a first start with the real install path on Apple silicon.*
- **Linux hosts.** The container runs as UID 51773, so bind-mounted folders must be writable by it (for example, `setfacl -R -m u:51773:rwX <folder>`).
- **CPU architecture.** Image archives come per architecture (arm64 or x64). The README tells judges which to download, and the install script checks for a match (FR-55).

## 2. Claude Haiku 5.5 through AI Hub (NFR-1 to NFR-6)

### Request rules

- **Never set `temperature`, `top_p` or `top_k`.** Haiku 5.5 returns HTTP 400 for any non-default value. The AI Hub documentation shows `agent.Temperature = 0.7` and sampling parameters in session configs; don't copy them. Steer behaviour from the prompt instead.
- **Thinking is on by default (adaptive), counts toward `max_tokens`, and is billed as output.**
  - Thinking can use up a small cap: one test answer was cut off at exactly `max_tokens: 300`.
  - Set `max_tokens` to about 4,000 or more for chat and agent turns (NFR-2).
  - AI Hub manages thinking blocks in tool loops, and a tool call with thinking inside a business process worked.
- **No effort setting.** AI Hub exposes no `effort` or `thinking` setting, so Haiku runs at its default effort, medium.
  - Architecture should check whether the provider config can pass `output_config.effort`.
  - If it can, use `low` for triage and `high` for diagnosis. If not, medium is acceptable.
  - *Decided (AD-7): effort passes as `extra_params.output_config.effort`: Triage `low`, Diagnosis `high`.*
- **Refusals have no server-side fallback.** A refusal is HTTP 200 with `stop_reason: "refusal"` and a category: `cyber`, `bio`, `frontier_llm` or `general_harms`.
  - Security logs or audit data read by IRIS watch could occasionally trip `cyber`.
  - How AI Hub surfaces a refusal or a `max_tokens` stop is untested. In tests, `%AI.LLM.Response` exposed only `Content`, `ToolCalls` and `Usage`. **Test refusal and `max_tokens` surfacing at the start of step 1** (FR-4). *Settled (AD-8): the reply's `finish_reason` reports both.*

### Prompt rules

- **User text never goes inside a tool result (NFR-6).** Haiku 5.5 is trained to distrust tool-result content as a prompt-injection defence. A Telegram message that arrives mid-task must reach the model as a message in the user role.
- **Arriving content is data (FR-7, NFR-14).** When making the attention decision for an item that didn't come from the user, frame its content as quoted data, and offer the agent only read-only tools, plus "notify" and "save for digest".

### Cost and tokens

- **Price.** $0.10 per million input tokens and $0.50 per million output tokens, while the prompt is 100,000 tokens or less.
  - Above that, the whole request costs five times as much ($0.50 / $2.50).
  - The context window is 1M tokens, and the maximum output is 128K.
  - Cache reads cost 0.1× the input price. Cache writes cost 1.25× (5-minute) or 2× (1-hour).
- **Staying under 100,000 tokens (NFR-3):**
  - Scope the tools per turn: offering hundreds of tool descriptions can cost about 190K tokens per model request.
  - Keep the knowledge base's `TopK` small: 5 chunks came to about 6,300 tokens.
  - Cap tool results, since failed message bodies can be large.
  - Compact long conversations.
- **Prompt caching.** Haiku 5.5 caches prompts of 512 tokens or more, so the ~600-token triage prompt qualifies.
  - Enable the session cache config everywhere: `{"cache": {"enabled": 1, "cache_system_prompt": 1, "cache_tool_definitions": 1}}`.
  - Keep the system prompt and tool list stable, and put anything variable (dates, IDs) after them.
  - Verify with `cache_read_tokens` on a second identical model request. One test wrote 6,008 tokens to the cache on turn 1 and read all of them on turn 2.
  - Caches are per model, so mixing models costs cache reuse. Measure Haiku first.
- **Measured triage.** 0.9 to 2.4 seconds and about 600 to 700 input tokens per decision. The first test got all three of its decisions right.
- **The cost target (NFR-4).** About 650 input tokens at $0.10 per million, plus up to about 1,000 output tokens (thinking included) at $0.50 per million, comes to about $0.0006 per decision. Check it against measured usage.

### Other models

- **Other providers (FR-39).** AI Hub sends `max_tokens` to GPT-5 models, which reject it ("use max_completion_tokens"). Send GPT-5 models the cap as `max_completion_tokens` through `extra_params` instead (NFR-2 as amended by P17, October 17; the architecture's AD-7 records the field).
- **Sonnet for diagnosis.** If the evaluation set shows Haiku falling short on causes, switch the diagnosis agent to Claude Sonnet 5.5 (`claude-sonnet-5-5`, $2 / $10 per million) through the bridge's production setting (FR-5).

## 3. AI Hub patterns (FR-2, FR-3, FR-6)

- **Programmatic agent:**
  - Create the provider with `##class(%AI.Provider).Create("anthropic", {"api_key": ($system.Util.GetEnviron("ANTHROPIC_API_KEY"))})`, then the agent with `##class(%AI.Agent).%New(provider)`.
  - Set `Model` and `SystemPrompt`, then call `%Init()`, which is required.
  - Call `CreateSession({...})`, then `Chat(session, text)`, which returns a `%AI.LLM.Response` with `Content` and `Usage`.
- **Usage fields:** `prompt_tokens`, `completion_tokens`, `total_tokens`, `cache_read_tokens` and `cache_creation_tokens`; OpenAI also reports `reasoning_tokens`. The bridge computes cost from these (FR-2).
- **Declarative agent:** a class extending `%AI.Agent`, with `Parameter PROVIDER`, `MODEL`, `APIKEY = "@{env:ANTHROPIC_API_KEY}"` and `TOOLSETS`, and an `XData INSTRUCTIONS` block in Markdown. It worked inside a production job.
- **Toolset:** a class extending `%AI.ToolSet`, with an `XData Definition` in XML (`<ToolSet Name=..><Tool Name=.. Method=../></ToolSet>`).
  - Each method's `///` comment becomes the tool's description.
  - Tools run in the calling business process's own job and namespace.
- **Tool calls do not appear in Visual Trace,** so the bridge records agent steps itself (FR-3).
- **Conversations that survive restarts (FR-6):** `%AI.Agent.Session`.
- **`base_url` for Anthropic.** *Superseded (AD-7, AD-22, AD-25):* this note said the Anthropic provider has no `base_url`, so CI and the online demo would reach their stand-ins by resolving the API host name to them with a private CA. Build 154's Anthropic provider does take `base_url`, and CI and the online demo reach their stand-ins through it.
- **TLS with a private CA:** the provider needs the full `tls` block, `{"http_config": {"tls": {"ca_certificates": [...], "accept_invalid_certs": false, "accept_invalid_hostnames": false}}}`.
  - If the block leaves out those flags, the provider fails with "missing field accept_invalid_certs".
  - A missing CA file is an error.

## 4. The bridge (FR-1 to FR-5, FR-7, FR-37, FR-48)

- **Parts:**
  - a business process that calls the agent;
  - production settings: the agent class, the toolset, the model per agent, the token budget per decision, the timeout, the fallback route, the approval role, and the classification of the developer's own tools;
  - a typed decision message;
  - trace entries for agent steps;
  - approval requests held in IRIS Workflow.
- **Packaging (Open Question 6, decided October 17):** OcuTalon's one IPM package contains the bridge and installs it itself, because an Open Exchange listing carries one IPM package. The bridge's classes also load on their own without IPM, for the developer guide. A separate bridge product with its own package and listing is a follow-on.
- **The IRIS-watch tools:** a native ObjectScript toolset over message headers, the event log, queues, `Ens.Director`, production settings and resend. They are not external MCP servers running inside the container.
  - Each tool is classified safe or risky in code (FR-7).
  - Tools are keyed by source and name, so an MCP tool can't shadow a built-in one (FR-48).
- **The all-clear (FR-37):**
  - code computes the all-clear flag from the check results and renders the all-clear sentence;
  - the model writes the rest of the digest;
  - the model's text is checked, so it never holds an all-clear the flag doesn't allow.

## 5. Approvals (FR-7, FR-8, FR-11)

- **Setting up:**
  - create roles and users with `EnsLib.Workflow.RoleDefinition.CreateRole`, `EnsLib.Workflow.UserDefinition.CreateUser` and `RoleDefinition.AddUserToRole`;
  - the `EnsLib.Workflow.Operation` item must have the same name as the role.
- **Raising and completing:**
  - the business process sends an `EnsLib.Workflow.TaskRequest` (`%Subject`, `%Message`, `%Actions="Approve,Reject"`) with `SendRequestAsync`;
  - code completes it with `AssignTask(user)` and `CompleteTask("Approve")`;
  - `OnResponse` receives `%Action` and `%UserName`.
- **One task, several channels.** The web chat, the simulated phone and Telegram all complete the same Workflow task, so the first answer winning (FR-8) follows from the task's state.
- **Fixed targets (FR-8):**
  - the task stores the exact message IDs or settings and the exact change;
  - on approval, the action runs from that stored definition, with no model request;
  - each target is re-checked against the state the dry run saw, and changed targets are skipped.
- **Expiry.** A scheduled job expires tasks older than the FR-8 limit.
- **Upgrades.** Approval requests that are still waiting are business process instances, and they must survive upgrades (§10).

## 6. Web app (FR-12 to FR-15, FR-17)

- **The app.** An Angular single-page app served by IRIS's built-in web server.
- **Updates.** REST handles requests from the page, and `%CSP.WebSocket` pushes updates (tested on build 154). Polling is the fallback. *Decided (AD-12): polling first, the WebSocket second, and only polling on the online demo.*
- **No Node.js at install.** The built bundle is committed on release branches, so a Docker install needs no Node.js.
- **Simulated panels.** The simulated phone and mailbox are business services and operations in the production, like real channels, which is why they look the same in Visual Trace.
- **Trace links.** The trace links open the portal's Visual Trace view for the turn's Interoperability session or message.
- **Session ownership from step 1 (FR-15).** Session isolation ships in the 1.0.0 kit, but it touches every record. So build session ownership into the data model in step 1, and the kit needs no retrofit. Every record a session creates carries its session, extending the tagging of demo orders (§7) to:
  - conversations;
  - background checks;
  - reminders;
  - approval requests;
  - pairings.

## 7. The demo production (FR-16)

- **The production.** Orders runs in its own namespace, with a simulated partner that sends orders through a real transform.
- **Break the feed.** It asks the simulated partner for one batch of 50 orders, tagged with the session, in a different date format.
  - The transform fails for real.
  - The partner holds no global "broken" state.
- **Session scope.** A session's watch, incident and resend cover only that session's tagged orders (FR-15).
- **The button's state.** Whether the button is active (only while the session is watching and has no open incident) is decided on the server, so a double click can't make two batches.

## 8. Telegram (FR-18 to FR-22)

- **Transport:**
  - IRIS long-polls `getUpdates` with `%Net.HttpRequest`, so no public URL or webhook is needed;
  - replies use `sendMessage`;
  - an SSL configuration is created in `%SYS` with `Security.SSLConfigs.Create`;
  - outbound HTTPS to the Telegram API works on build 154.
- **Text.** Send replies as plain text, or escape them for the chosen parse mode. Model-written text full of punctuation otherwise breaks MarkdownV2, and `sendMessage` rejects it.
- **Pairing:**
  - The QR code encodes `https://t.me/<bot>?start=<code>`, which Telegram delivers as `/start <code>` with the chat ID.
  - A start parameter is at most 64 characters from `A-Z a-z 0-9 _ -`. A 22-character URL-safe random string carries 132 bits.
  - A bot can never message someone first. It can only write to chats where the person has sent it something.
- **Approve and Reject:** inline keyboard buttons whose callback data holds a random reference to the approval request, never its sequential ID.
  - The handler checks that the press came from the paired chat, completes the Workflow task, and edits the message to show the result.
  - A press with a reference that a scheduled reset has cleared does nothing.
- **Identity.** Only an internal chat reference goes into production messages and the trace. The Telegram display name is kept with the session's pairing and is shown only on the web page (FR-15, FR-18).
- **One poller per token.** A second process polling the same token gets `409 Conflict` and takes updates away from the first.
  - Each running instance has its own bot: one for the online demo, and one for each development instance.
  - CI mocks the Telegram API.
  - On a 409, pause and retry after the back-off (FR-22).
- **Bot settings.** Groups are disabled for the bots in BotFather. Group messages are also ignored in code (FR-19).
- **Optional.** With no `TELEGRAM_BOT_TOKEN`, the Telegram service is not started.

## 9. IRIS watch (FR-23 to FR-25)

- **Reach.** IRIS watch reads productions in other namespaces on the same instance (FR-23). Its tools run in the calling business process's namespace (§3), so a tool that reads another namespace must switch to it, and the service user needs read access there.
- **Reacting within 15 seconds (FR-23).** The watch doesn't wait for the one-minute heartbeat. Two candidates for architecture:
  - forward the watched production's alerts to OcuTalon as they are raised;
  - or run a light watch service that checks message headers and the event log every 5 to 10 seconds.

  The heartbeat still checks the production's overall state every minute. *Decided (AD-15): a light watch service, `FailurePoller`, every 3 seconds.*
- **Settle rule (FR-24).** The notice waits until the burst settles, with the values set in FR-24. This stops a mid-burst notice from saying "20 failed" while 50 are on their way.
- **Diagnosis output.** A structured result (cause category, the element at fault, evidence references and the proposed fix) plus the plain-English sentence. The evaluation set scores the structured part (FR-62).
- **Repair (FR-25).** A fixed, parameterised reformat of one field, for example a date pattern from the partner's format to the expected one.
  - It produces new message bodies. IRIS resend sends them as new messages, and the originals are kept.
  - The model chooses the parameters and never writes code.

## 10. Scheduling (FR-32 to FR-34, FR-60)

- **The heartbeat.** An adapterless business service (`PoolSize=0`), called every minute by an IRIS Task Manager task through `Ens.Director.CreateBusinessService` and `ProcessInput`. Task Manager schedules tasks only in whole minutes, so one minute is the shortest interval.
- **Reminders.** Each reminder is a business process waiting on a timer, which is durable, survives restarts, and shows in Visual Trace.
- **Background checks.** The heartbeat reads them as records. Each run is a production message, and only new findings become items.
- **Upgrade hazard (FR-60).** Waiting business process instances (reminders and approval requests) must survive a release that recompiles their classes. Either keep those classes compatible across releases, or store reminders and approval requests as data rows driven by a durable scheduler. Architecture decides, and FR-60's test proves the choice. *Decided (AD-5): rows are the truth, and a reconciler re-arms waiters on every start.*

## 11. Memory, documents and files (FR-41, FR-42, FR-54)

- **Embeddings.** FastEmbed through `%AI.RAG.Embedding.FastEmbed` (AllMiniLML6V2, 384 dimensions, no key).
  - The model (about 90 MB) downloads on first use into the database folder's `.fastembed_cache`. The Docker build must warm it, because the online demo's IRIS has no internet (N8).
  - When the database folder is on durable storage, FastEmbed may not look for the cache where the image layer warmed it. Point FastEmbed at a cache path inside the image, or copy the cache at first start. FR-41's offline first-use test proves it. *Settled (AD-21): the model is baked read-only into the folder named by `FASTEMBED_CACHE_DIR`.*
- **Memory has its own table,** with an HNSW vector index and a full-text index, for hybrid search. AI Hub's own vector table has neither index, and its search runs outside SQL. Vectors come from `EmbedBatch`. *Superseded (AD-21): `EmbedBatch` fails on build 154, so memory vectors come from the Python `fastembed` package in a worker.*
- **Documents use AI Hub's knowledge base:**
  - `%AI.RAG.KnowledgeBase` over `%AI.RAG.VectorStore.IRIS`;
  - `Build(emb, vs)` runs in each process;
  - `AddDocument(text, {"source": ...})`, then `AddToAgent(agent)`, which adds a `search_runbooks` tool with a default `TopK` of 5;
  - chunks carry `source` and `chunk_index`, for citations;
  - chunking is automatic, splits at `##` headings, and can't be configured.
- **Files and photos (FR-54):**
  - `pdfplumber` runs through Embedded Python, and works on build 154. Install it at image build with `python3 -m pip install --break-system-packages --target /usr/irissys/mgr/python pdfplumber`, because there is no `irispip`.
  - Ship the Python as `.py` resources loaded with `##class(%SYS.Python).Import(...)`, not as `[Language = python]` methods.
  - With `ISC_DATA_DIRECTORY` set, Embedded Python's path includes both the image layer's `/usr/irissys/mgr/python` and the durable mount's `mgr/python` folder (for example `/durable/iris/mgr/python`), tested October 16. Packages installed at image build work in the product image, and development instances can install into the durable folder so packages survive re-creating the container.
  - A long-running IRIS process caches Python's directory listings, so a newly installed package needs a fresh process, or a call to `importlib.invalidate_caches()`.

## 12. Channels (FR-44 to FR-46)

- **Email:**
  - `EnsLib.EMail.InboundAdapter` is POP3 only, with OAuth2, so Gmail and Microsoft 365 work. `EnsLib.EMail.OutboundAdapter` sends by SMTP.
  - IMAP would need Embedded Python (`imaplib`) and is out of scope for the contest.
  - An MCP email server is an optional showcase if the MCP client passes its test.
- **Webhook.** A REST endpoint. Each webhook's secret is compared in constant time.
- **Slack.** The Events API webhook brings events in, and `chat.postMessage` sends replies out. There is no socket mode, because `%Net.WebSocket.Client` fails on build 154 (`<READ>`/`<WRITE>` right after opening).

## 13. MCP (FR-47 to FR-51)

- **The client.** AI Hub toolsets can include remote MCP servers (`<MCP><Remote>`). This is untested on build 154; test it before step 4. *Settled (AD-21): AI Hub lists a server's tools, and OcuTalon calls them through its governed proxy tool.*
- **Governance.** Whether AI Hub applies its policies to remote MCP tools is untested. Either way, OcuTalon wraps every MCP tool call in its own permission, classification, approval and audit checks (FR-49).
- **Classification fingerprint.** A fingerprint of each tool's description and input schema is stored at classification. A changed fingerprint makes the tool unclassified (FR-48).
- **The online demo.** Only MCP servers on the gateway's allow-list can be reached (§15).
- **OcuTalon as a server (step 7):** `%AI.MCP.Service` plus `iris-mcp-server`, both untested.
- **Anonymous access in `iris-mcp-server`.** InterSystems' AI Hub development template (moved to build 154 on October 16) sets `allow_anonymous = true` in `iris-mcp-server`'s HTTP config.
  - Without the setting, MCP clients that send no `Authorization` header are blocked.
  - Authenticated endpoints stay protected by the web gateway.
  - Take this into account in the MCP test before step 4 and in step 7.
  - FR-51 requires IRIS authentication for OcuTalon's own server, so don't copy the setting there without an architecture decision.

## 14. Install and Docker (FR-55 to FR-57)

- **The judges' image.** A Dockerfile `FROM irishealth-community:2026.3.0AI.154.0` installs OcuTalon with IPM, adds the Python packages, and warms FastEmbed during the build. A build argument selects the non-Health image (NFR-21).
- **Retagging.** The install script finds a loaded image that matches the build 154 AI Hub repository and tag, checks its architecture, retags it to the name the compose file expects, and runs `docker compose up`.
- **Health check.** The compose file defines one that passes when IRIS is running (`iris qlist` reports `running`) and the OCUTALON namespace is ready, with a `start_period` of at least 10 minutes.
  - The install script relies on it.
  - So does a judge's plain `docker compose up`.
  - So does CI's `docker compose up --wait`.
- **Storage.** Whether the judges' install uses durable storage or a plain container is decided in architecture. *Decided (AD-23): durable storage on a named volume.*

## 15. The online demo (FR-12, FR-15, FR-59)

- **The gateway.** The demo server's IRIS has no internet access. An outbound gateway answers for the model API and the Telegram API and, from step 4, for allow-listed MCP servers.
  - It allows only those destinations.
  - It swaps a dummy key for the real one.
  - IRIS reaches it as described in §3.
- **Resets.** A reset restores a golden copy. Resets run on the schedule FR-59 sets, and also after two failed monitoring probes in a row. Expect a short outage during each reset, and show the countdown to the next reset on the page (FR-15).
- **The read-only account.** An account whose role is limited to viewing Visual Trace and messages, with no Interoperability operator, SQL, security or settings privileges.
- **Other settings:**
  - the splash screen gives the demo sign-in and the read-only account;
  - access is restricted until the author launches the demo;
  - the instance's time zone is US Eastern (FR-12);
  - a monitoring probe runs the start of the demo path every 15 minutes.

## 16. CI and releases (REL-1 to REL-11)

- **The IRIS runner:**
  - tests that need a live IRIS run on a dedicated self-hosted runner that holds the image privately;
  - each job runs `docker compose up --wait` (§14), the tests, and teardown;
  - the runner is never the online demo server;
  - fork pull requests never run on it, and outside contributors need approval.
- **Hosted runners.** Jobs that don't need IRIS run on GitHub-hosted runners.
- **The mocked model (REL-4).** CI reaches the mock the same way the demo reaches its gateway (§3), with a CI-only private CA. *Superseded (AD-22): through the provider's `base_url` over plain HTTP, with no private CA.* The mock:
  - rejects any request with sampling parameters (NFR-1), or without an adequate output cap (NFR-2);
  - returns, on demand, refusals, empty replies, `max_tokens` stops, errors, slow replies and rate limits (FR-4).

  If CI can't mock the Anthropic path this way, plan B is to exercise the OpenAI-provider mock as well, and to validate the bridge's request building directly.
- **Mocks stay out of the product.** Mocks live in a CI-only compose override, never in the compose file judges use (CON-3).
- **Live runs.** Smoke tests and the evaluation set run with the real key, kept as a secret, on `main` and on release candidates.
- **Speed.** Sharding the test suite from day one keeps a full run near 30 minutes. Timing bounds are measured in the rehearsal, not asserted in sharded CI.

## 17. Data retention (NFR-19)

- The standard Interoperability purge task runs on a schedule, with the retention periods NFR-19 sets for each kind of message.
- History (FR-53) reads from OcuTalon's own decision and incident records, so it outlives the message purge.

## 18. Options considered

- **Telegram webhooks rather than polling.** Rejected, because webhooks need a public URL, which a local install lacks. Polling works everywhere.
- **Email through an MCP server only.** Rejected as the base, because the MCP client is untested. Native POP3 and SMTP are the base, and an MCP email server is an optional showcase.
- **Memory in AI Hub's knowledge base.** Rejected, because it has no HNSW or full-text index, so it can't do hybrid search. The knowledge base is kept for documents.
- **Slack socket mode.** Not possible, because the platform's WebSocket client fails.
- **Counting an unclassified MCP tool as read-only.** Rejected: an unclassified tool counts as risky (N15).
- **A production watch driven only by the one-minute heartbeat.** Rejected, because it can't meet the one-minute incident notice (NFR-7) once diagnosis time is added.
- **A model-written all-clear.** Rejected: code decides the all-clear (FR-37), because a false all-clear is the fastest way to lose trust.
