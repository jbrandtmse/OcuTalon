---
title: "Product Brief Addendum: OcuTalon"
status: final
created: 2026-10-16
updated: 2026-10-16
---

# Addendum: OcuTalon product brief

This addendum holds depth that belongs in the PRD or architecture, or that earned a place but doesn't fit
the brief. "The author" means the author of the brief and owner of the project, as in the brief.

## Delivery model (the author, October 16)

This section expands the brief's Scope.

- The author's directive: define the full scope up front and don't shrink it for the contest. Release 1,
  the demo slice, comes first, followed by increments.
- Run the project the way OcuPilot was run. OcuPilot was the author's Contest 48 entry, and it took first
  place in the Experts nomination.
  - **The build order is the cut line,** with the rules in the brief's Scope.
  - **A written floor for release 1** (the minimum it must contain), reproducible on a clean install.
  - **Submit early.** OcuPilot shipped 1.0.0 a day before the deadline. Then run a release train through
    voting week, with the polish scope planned in advance.
  - `main` moves only through a release PR with every check green, and release branches are never touched
    after the cut.
  - CI runs on every push. Each release gets a clean-machine rehearsal and an in-place upgrade check.

### OcuPilot lessons that bear on OcuTalon's scope and timeline

- **Scope was about 2.4 times capacity.** Keeping the full scope and ordering it worked: everything that
  shipped was complete. Stories were never sized, though, and the plan was re-sequenced four times in six
  days. Size them this time.
- **Measured pace** was about 2.5 to 3 hours per story, so a 12-hour unattended window buys 3 to 4 stories.
- **Hands-on use with real API keys found nine problems the tests missed.** Plan for that hands-on pass and
  its fixes.
- **The demo and collateral were cut, then rebuilt in the last 48 hours.** The first-place margin was 2
  points, and the bonus points lost while the demo was cut nearly cost first place. Treat the demo as
  product, not collateral.
- **Going stealth protected the idea** but cost OcuPilot its placement floor in the Community nomination.

## Decisions taken as given (made before the brief; not reopened here)

| Decision | Outcome |
| --- | --- |
| Platform | IRIS for Health AI Hub, Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`); also test the `iris-community` (non-Health) AI Hub build 154 |
| Namespace | OcuTalon creates its own `OCUTALON` namespace with Interoperability enabled |
| Default model | Claude Haiku 5.5 (`claude-haiku-5-5`) for every agent. If the evaluation set shows Haiku falling short on diagnosis, Claude Sonnet 5.5 is used for diagnosis only (see the brief's Top risks). OpenAI, Gemini, and Bedrock are also supported. |
| Embeddings | FastEmbed (local, no API key), with the model baked into the image |
| Web app | Angular single-page app served by IRIS, with WebSocket push |
| Image | The AI Hub image, or anything built on it, never goes to a public registry; share the Dockerfile and compose file |
| Repository | Private (stealth) until OcuTalon's README is final. OcuPilot's stealth cost it the Community floor; see the lessons above. |
| Build | Starts October 21 with two parallel build runners, each on its own IRIS instance. Release 1 targets October 30 (no later than November 1), and 1.0.0 is submitted November 7. |

## Notes for the PRD and architecture

- **Telegram is in release 1** (the author, October 16). The scope brief had it as the first increment
  after release 1. The move adds to release 1's load, so size it carefully at sprint planning. It depends
  on two things: the author's Telegram bot token, and a Telegram route on the online demo's gateway. Both
  must be ready before the release 1 stories that need them.
- **Telegram pairing has three cases, and only one of them links a chat** (tested October 16 on the dev
  bots):
  - **A valid one-time code** (from the QR code's deep link, `t.me/<bot>?start=<code>`, which arrives as
    `/start <code>`) links that private chat to its web session.
  - **An unknown or expired code** gets a polite reply saying the code didn't work and how to get a new
    one. The chat is never linked.
  - **No code at all.** Someone who finds the bot by search and taps START sends a bare `/start`. They get
    a reply explaining how to pair: open the OcuTalon page and scan its QR code. The message is never
    silently ignored and never linked to a session.

  Related facts the PRD and architecture need:
  - A pairing code must fit Telegram's start parameter: at most 64 characters, using only `A-Z`, `a-z`,
    `0-9`, `_` and `-`.
  - A bot can never message someone first. It can only write to chats where the person has sent it
    something, which is why pairing starts from the user's side.
  - One pairing ties one Telegram chat to one session. That keeps judges apart on the shared demo, and the
    hourly reset clears every pairing.
- **One bot per poller.** Telegram lets only one process poll a bot token; a second poller gets "409
  Conflict" and steals messages. So there are three bots:
  - `@OcuTalonBot` for the online demo only;
  - `@OcuTalonDevBot` for dev slot A (`TELEGRAM_BOT_TOKEN`);
  - `@OcuTalonDevB_bot` for dev slot B (`TELEGRAM_BOT_TOKEN_SLOT_B`, passed to slot B's container as its
    `TELEGRAM_BOT_TOKEN`).

  CI mocks Telegram.
- **Telegram is optional on a local install.** Judges can't use the demo bot, because the demo server
  polls it. With no `TELEGRAM_BOT_TOKEN`, OcuTalon runs with Telegram turned off, and the web chat and
  simulated phone remain the default path. The README explains how a judge can create their own bot with
  BotFather and set the token.
- **What the reusable bridge contains:**
  - the agent's settings, as production settings;
  - the decision, as a typed message;
  - the agent's steps, recorded as trace entries;
  - approvals, held in IRIS Workflow.
- **The daily digest's all-clear needs a definition of "checked".** That means which productions, queues,
  and checks it includes, and how the digest says what was covered. A false all-clear is the fastest way
  to lose trust.
- **The MCP sources (email, Jira) depend on AI Hub's MCP client,** which hasn't been tested on build 154.
  On the online demo, only MCP servers on the demo gateway's allow-list work.
- **MCP extensibility needs governance rules of its own.** The brief states that tools from added MCP
  servers are governed like built-in tools (differentiator 3). Treat that as a requirement on OcuTalon. If
  AI Hub doesn't apply its policies to the tools of remote MCP servers natively (untested on build 154),
  OcuTalon must enforce them itself. The PRD should also settle two more questions:
  - How does OcuTalon decide whether a tool from a newly added server is risky? One option: treat an
    unclassified tool as risky until someone classifies it.
  - Who may add a server?
- **Claude Haiku 5.5's limits** shape the bridge's fallback route:
  - no temperature, top_p, or top_k;
  - thinking counts toward `max_tokens`;
  - refusals have no server-side fallback;
  - the price steps up at 100,000 tokens.

  The details are in section 4 ("AI Hub build 154: what works") of the internal OcuTalon BMAD handoff, which
  isn't published.
- **The cost target** (under a tenth of a cent per attention decision) assumes about 650 input tokens at
  $0.10 per million, plus up to about 1,000 output tokens at $0.50 per million, including thinking. That
  comes to about $0.0006 per decision. Check it against measured usage.

## Evidence for the problem (anecdotal)

This section backs the brief's "The problem" section.

- A Developer Community thread reports 75 email notifications for one connection problem. The built-in
  duplicate check (`IsRecentManagedAlert()`) needs identical alert text, so grouping takes custom code.
  https://community.intersystems.com/node/537251
- A Developer Community post says the Message Viewer is "not suitable" for resending more than 100
  messages, and recommends an ObjectScript loop instead. https://community.intersystems.com/print/410621
- An Ideas Portal request asks for a "resend original message to clear managed alert" button (status: In
  Progress). https://ideas.intersystems.com/ideas/DPI-I-638
- No survey of integration engineers on alert fatigue was found.

## Differentiation research (October 16)

This section is what the brief's "What makes this different" section rests on.

- **OpenClaw's hardening is opt-in.**
  - OpenClaw's README warns "Tools run on the host for the main session unless you configure sandboxing"
    and "Treat inbound messages as untrusted input."
  - Sandboxing and approvals for shell commands exist, but both default to off (`full` mode, `ask: off`).
  - Notable 2026 incidents: CVE-2026-25253 (one-click remote code execution), and malicious skills found in
    its skills marketplace.

  https://github.com/openclaw/openclaw · https://docs.openclaw.ai/gateway/sandboxing ·
  https://docs.openclaw.ai/tools/exec-approvals
- **Several OpenClaw clones also market security** (a container per chat, WASM sandboxes, supervised
  modes), so "safer than OpenClaw" alone isn't unique. https://composio.dev/blog/openclaw-alternatives
- **Approval-gated remediation is standard practice.** PagerDuty SRE Agent has permissions and remediation
  approvals. Datadog Bits acts inside guardrails and asks a human otherwise. Both work from outside the
  integration engine.
  https://www.pagerduty.com/blog/ai/sre-agent-enhancements-faster-triage-greater-access-controls-deeper-system-connectivity/ ·
  https://www.datadoghq.com/blog/bits-infrastructure-operations/
- **IRIS Managed Alerts already escalate,** so OcuTalon's on-call paging overlaps a built-in feature.
  OcuTalon adds grouping, a plain-English cause, and approved resend on top.
- **Other integration engines are moving toward agentic triage.** Examples are Rhapsody Axon and Boomi's
  Resolve Agent (the Boomi source wasn't recorded). No equivalent was found for HealthShare or Mirth. So
  differentiator 1, living inside the engine, is unique among tools for IRIS, not across all integration
  engines. https://rhapsody.health/get-a-demo-of-rhapsody-axon/
- **AI Hub's own pitch is "Build, Connect, and Govern AI Agents,"** so every entrant gets governed tools
  and approval steps from the platform. Early community posts about AI Hub already show governed,
  access-controlled toolkits. https://www.intersystems.com/resources/intersystems-iris-ai-hub/ ·
  https://community.intersystems.com/tags/ai-hub
- **The judges already know InterSystems' reference examples:**
  - an agent in a production;
  - OpenTelemetry spans;
  - an approval that holds a write tool;
  - an evaluation suite.

  OcuTalon has to go beyond these, not copy them. https://github.com/intersystems-community/iris-ai-examples
