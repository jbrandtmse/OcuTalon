---
title: "Product Brief: OcuTalon"
status: final
created: 2026-10-16
updated: 2026-10-17
---

# Product Brief: OcuTalon

*An OpenClaw-style assistant for InterSystems IRIS.*

## Executive summary

OcuTalon is a self-hosted personal assistant that lives inside InterSystems IRIS. You talk to it from a
web page, Telegram, email, or a webhook. It makes one decision over and over. For everything that arrives
(a message, the result of a background check, a production alert, a new ticket), it asks what deserves your
attention. Then it ignores the item, saves it for your daily digest, tells you now, or acts on it. Anything
risky waits for your approval. You extend it by adding Model Context Protocol (MCP) servers: each server's
tools become new skills and new sources for it to watch.

On most days that means one short message, the daily digest: how your IRIS system is doing, what OcuTalon
checked, that everything is fine, and the one email or ticket that does need you. On a bad day it becomes an
incident commander for your Interoperability productions:

- it groups 50 failures into one incident;
- it explains the cause in plain English ("the partner changed its date format at 14:12");
- it proposes a fix, with a dry run, and asks for your approval on your phone.

You approve; it repairs and resends the messages, then writes up what happened. The one-sentence demo:
*break the feed, and approve the fix from your phone.*

OcuTalon takes its idea from OpenClaw, the popular open-source assistant, but is rebuilt from scratch as an
IRIS Interoperability production. At its center is an agent built on IRIS AI Hub, InterSystems'
early-access platform for AI agents. Every decision is a production message carrying its reasons, its
confidence, and its token cost, so you can watch your assistant in Visual Trace like any other feed. It is
being built for InterSystems Programming Contest 49 (entries close November 8, 2026), demo first and then in
frequent releases. After the contest it is meant to be an assistant that its author, and friends in the
IRIS community, use every day.

## The problem

People who run IRIS Interoperability have two streams competing for their attention, and neither one
filters itself.

**When a feed breaks, IRIS tells you many times and explains nothing:**

- One connection problem can send 75 alert emails. The built-in duplicate check matches only identical
  text, so grouping them takes custom code.
- Finding the cause means digging through Visual Trace and the event log, and remembering what changed.
- Resending a few hundred messages takes a script, because the Message Viewer isn't built for it.
- Managed Alerts page and escalate, but about symptoms, not causes.

**Everything else asks for attention too:** email, tickets, chat, things you meant to remember. Most of it
doesn't need you today, but you can't tell which items do without reading them.

This pain is common across IRIS integration teams. The public evidence is community anecdote, not user
research; the addendum lists it.

## The solution

OcuTalon runs as a production in its own namespace on your IRIS instance. A heartbeat wakes it every
minute, and background checks, reminders, and arriving messages all feed into one decision. This section
describes the full product; Scope says when each part ships.

**The attention decision.** For each arriving item, an AI Hub agent chooses one of four outcomes:

- ignore it;
- save it for the daily digest;
- tell you now;
- act on it.

Each choice is a production message carrying its reasons, confidence, tokens, and cost.

**Approval.** Anything risky waits for a person. Approvals run on IRIS Workflow, and you can give one from
the chat, the demo page's simulated phone, or Telegram. Every action goes into the IRIS audit log.

**A normal day.** The daily digest reports your IRIS system's vital signs, lists what OcuTalon checked
(including connected sources such as email and Jira), and flags anything that needs you. It says everything
is fine only if every check passed. In between, OcuTalon keeps your reminders, remembers what you tell it in
your own IRIS database, and answers from your documents and runbooks with citations.

**A bad day: IRIS watch.** OcuTalon watches the productions you name.

- When messages fail, it groups them into one incident with a plain-English cause.
- It proposes a fix from a predefined set, each with a dry run: repair and resend, reroute, roll back a
  setting, suspend a partner, or draft a transform change for a developer to review.
- Once you approve, it acts and writes the incident summary.

It also pages the on-call person, escalates to a backup if nobody acknowledges in time, and warns
downstream partners. It links failures to recent setting changes ("the feed broke four minutes after this
setting changed").

**Extensible through MCP.** You add a skill or a source by adding an MCP server, such as one for Jira or
for your own systems. Its tools become OcuTalon's tools, under the same approval and audit rules.

## What makes this different

Today's tools each cover one of the two streams:

- **General assistants such as OpenClaw** read your email and run errands. They know nothing about
  productions, and their sandboxing and approvals for shell commands are off by default.
- **Operations agents from PagerDuty and Datadog** propose fixes and wait for approval. They work from
  metrics and logs outside the integration engine.

AI Hub also gives every contest entrant governed tools and approval steps, so approvals alone aren't the
difference. What OcuTalon has that the others don't:

1. **It lives inside the integration engine.** It reads the failed messages themselves, the trace, and the
   history of setting changes. That's how it can say "the partner changed its date format", where an
   outside agent sees only that errors went up.
2. **The assistant is itself a production.** Its decisions, reasons, steps, and costs are production
   messages, so you audit and debug your assistant in the same Visual Trace you use for your feeds.
3. **It's extensible, and governed by default.** Every tool call is checked against IRIS permissions and AI
   Hub policies, including calls to tools from MCP servers you add. Every action is audited, and OcuTalon
   can't run shell commands. *An OpenClaw your security team can approve.*
4. **What it remembers lives in your own database,** on infrastructure you already run, back up, and
   trust.
5. **The bridge is reusable.** The component that lets a production call the agent is documented so that
   others can drop it into their own productions.

The real advantage is execution, not a technical moat. The author brings three things:

- an IRIS MCP tool suite;
- the build process that won Contest 48;
- a demo kit that already runs an online demo that needs no API key.

## Who this serves

**First, the judges.** They are InterSystems experts who will try OcuTalon as users, in two minutes and
without an API key, on the online demo or after `docker compose up`. Every Interoperability customer they
know has error queues, so the problem will be familiar.

**Then the people it's built for:** IRIS developers, integration engineers, and administrators who own
productions and also have an inbox. It starts with the author, then reaches the wider IRIS community, whose
feedback and reviews shape it. For these users, success means three things:

- they stop reading alerts just to learn whether something is wrong;
- they trust that a quiet day really is quiet;
- they can fix a broken feed from their phone.

**People it touches:**

- the on-call backup it escalates to;
- downstream partners it warns about delays;
- a developer who reviews a proposed transform change;
- whoever has to agree that an AI assistant may act on a production, usually the security team.

## Success criteria

**The contest:**

- **Placement.** The goal is first place in the Experts nomination; the floor is a top-three Experts
  placement.
- **Release 1, the demo slice,** targets October 30 and ships no later than November 1.
- **1.0.0** is submitted on November 7, a day before entries close, then improved through frequent releases
  during voting week.
- **A first-time judge,** with no API key and no prior knowledge of OcuTalon, sees a decision with its
  reasons within about a minute and can open the trace.
- **Every release** passes the demo path, a clean-machine install, and an in-place upgrade from the
  previous release.

**The product:**

- **No false all-clear.** OcuTalon never says everything is fine while something it watches is failing,
  and every all-clear says what was checked.
- **Every decision explains itself.** Every decision carries the choice, reasons, confidence, and cost, and
  is visible in Visual Trace.
- **Measured, not assumed.** An evaluation set of about 20 attention decisions and 10 recorded incidents is
  built early and run in CI. Targets: at least 18 of the 20 decisions right, and the right cause for at
  least 8 of the 10 incidents.
- **Cheap enough to leave on.** A single attention decision costs less than a tenth of a cent on Claude
  Haiku 5.5, and no request goes over 100,000 tokens.
- **After the contest,** the author runs OcuTalon every day, and community members try it and come back
  with feedback and reviews.

## Scope

The full product is defined now and built in order. **The build order is the cut line.** Every step ends in
a release that could be submitted, and if time runs out, cuts come from the end, never the middle. A step
can take one release or several. Version 1.0.0 is whichever release is current on November 7.

**Step 1, release 1: the demo slice (the floor).** The two-minute demo works end to end on real components.
Nothing is faked except the clearly labeled simulated phone and mailbox.

1. The page shows the chat, a simulated phone and mailbox, and a Telegram QR code that pairs the judge's
   own Telegram chat with their session.
2. The judge types "Watch the Orders production and only tell me if something needs me", which sets up a
   background check.
3. The judge clicks **Break the feed**. Within a minute the phone shows the incident, its cause, and a
   proposed fix.
4. The judge approves, and the orders go through.
5. "Remind me in 1 minute to stretch" fires on time.
6. Visual Trace shows the conversation as production messages, with the cost of each turn.

Release 1 also includes:

- Telegram, with QR pairing and Approve buttons, so the demo works on a real phone;
- the reusable bridge;
- the heartbeat;
- approvals through Workflow;
- conversations that survive a restart;
- an install script that retags the image and runs `docker compose up`;
- CI with tests against a live IRIS instance.

**Then, in this order:**

- **Step 2:** the daily digest, and choosing the model in settings.
- **Step 3:** memory and documents: long-term memory with hybrid search, and runbooks with cited answers.
- **Step 4:** email, webhooks, and extension through MCP (for example, a Jira server as a new skill and
  source).
- **Step 5:** deeper IRIS watch:
  - paging with escalation;
  - warnings to partners;
  - incident summaries;
  - rerouting;
  - suspending and resuming a production item;
  - rolling back a setting;
  - linking failures to setting changes.
- **Step 6:** usage and cost views, decision and incident history, users and roles for approvals, and
  reading files and photos you send.
- **Step 7, if time allows:** Slack (webhook only), drafted transform changes, fading and consolidating old
  memories, and OcuTalon as an MCP server.

**Whatever step the build has reached, 1.0.0 includes:**

- the IPM package;
- the documented bridge, with an example of using it in another production;
- the online demo.

**Out for this contest:** browser automation, a skill builder, a knowledge graph, voice, calendars, SMS or
WhatsApp, and Slack socket mode.

## Top risks

| Risk | Mitigation |
| --- | --- |
| **Scope against time**, the author's main worry | The ordered build. Size the stories at sprint planning. Keep release 1 green. |
| **Diagnosis quality on a small, cheap model.** Haiku 5.5 is built for triage; linking failures to their cause is harder. | Build the evaluation set early. If Haiku falls short, use Claude Sonnet 5.5 for diagnosis only. |
| **An early-access platform with untested parts.** AI Hub's MCP client (needed for email and Jira), its handling of refusals, and its Config Store are untested on build 154, the AI Hub image the contest requires. | Test each one before the stories that depend on it. Treat an empty or refused reply as a failure, and fall back to fixed rules plus a person. |
| **A crowded governance story.** Governance is the platform's own pitch, and early entries already show governed toolkits. | Lead with what only an assistant inside the engine can do, and show governance that goes beyond holding an action for approval. |

## After the contest

OcuTalon becomes the assistant its author leaves running every day, shaped by the IRIS community's
reviews. It grows by adding MCP servers rather than by rewrites, and its bridge ships as a package that any
production can use.

One rule never changes: nothing risky happens until a person says yes, and everything OcuTalon does goes
into the audit log.

---

*OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.*
