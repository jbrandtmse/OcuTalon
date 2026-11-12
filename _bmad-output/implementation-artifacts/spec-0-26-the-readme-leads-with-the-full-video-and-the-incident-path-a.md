---
title: 'Story 0.26: The README leads with the full video and the incident path, and a measured comparison replaces the worked-out one'
type: 'feature'
created: '2026-11-12'
status: 'done'
baseline_revision: 'b41f331b8c36695ebfb221494bc7d0046cf672de'
baseline_commit: 'b41f331b8c36695ebfb221494bc7d0046cf672de'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** The README buries the incident path a judge can check under the "New since 1.0.0" list and links only the 35-second teaser.

**Approach:** Part (a) of the Contest Planner's Story 0.26 scope, after the PUBLIC TEXT ruling of 2026-11-12 ~00:55Z, which split the story: the README gets the full video (3:04, YouTube and the v1.0.6 MP4) above the teaser and in the link bar, a new H2 "One incident, end to end" before "What's interesting", "New since 1.0.0" moved below "What's interesting" and regrouped under three H4s interop first, and "Two things to look at in the demo" removed (its two points are now steps of the incident path). The text is the Planner's ruled text, applied verbatim from `## Ruled README change` below. `docker/tests/test-readme.sh` pins the new order and links, and the two web README tests follow the ruled order. The measured comparison (rules-only mode, held-out set, report script, the comparison H3 and the "What changes without the agent?" pointer) is Story 0.27.

## Boundaries & Constraints

**Always:**
- The README change is exactly the ruled diff in `## Ruled README change`, applied verbatim (`git apply`; if the README moved since, the same text placed at the same anchors, byte for byte).
- No feature is removed and no claim is added, and every number keeps its source.
- Every existing `test-readme.sh` rule keeps passing, and none is deleted or weakened. A rule whose anchor moves (the teaser line's text, the H2 order, the region the `interesting` word cap counts) is updated to the new anchor with its intent and its numbers kept.
- Shell stays ASCII and bash 3.2 compatible. Each command a stage runs finishes in about 150 s.

**Never:**
- No change to the "What changes without the agent?" sentence, the Measured table, or any `eval/**` file (Story 0.27).
- No `.github/workflows`, `ci/`, `release/**` or `_bmad/**` change.
- No README text beyond the ruled diff. No absolute local path in any tracked file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ruled README | `bash docker/tests/test-readme.sh` on the README with the ruled diff | `test-readme: all rules passed` | No error expected |
| Video lines swapped or reworded | The full-video line below the teaser, or either line not word for word | `video` / `teaser` / `top` name the line | test fails |
| Link bar | The full-video entry missing, or after the teaser entry | `video` names the link bar | test fails |
| Incident path | A step missing, reordered or reworded, or the H2 not between "Try it in two minutes" and "What's interesting" | `path` / `top` name it | test fails |
| New since 1.0.0 | Back under "Try it", a group heading missing or reordered, a bullet missing, duplicated or out of the ruled order | `new-since` names it | test fails |
| "Two things to look at" | The pair is back | `path` names it | test fails |
| Web README tests | `node --test` on the usage/history docs tests | Pass with the ruled order | test fails |

</intent-contract>

## Code Map

- `README.md` -- the target; the ruled diff below.
- `docker/tests/test-readme.sh` -- 32 rules; a rule is `chk_<name>` plus `rule_<name>` with self-tests (`st`, `st_move`) and `finish`; `RULES` near the end. `top` pins the header block, the opening, the teaser line, one hero image and the first five H2s (`H_TRY`, `H_INT`, `H_MEAS`, `H_USE`, `H_TALK`); `teaser` pins `TEASER='Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU'` two lines below the opening; `interesting` caps "What's interesting" at 120 words (image lines not counted).
- `web/scripts/usage-docs.test.mjs:43`, `web/scripts/history-docs.test.mjs:52` -- find `\n### New since 1.0.0\n` and end at `\n#{1,3} ` (so `####` group headings are inside the section). They pin the order Usage after "Where an answer came from" and History after Usage; with the ruled order exactly these assertions fail (measured by the plan stage). `sources-docs.test.mjs` and `more-to-try-view.test.mjs` pin "fifteen more things to try" and the bullets, and still pass.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- no change: its only README pointer (line 532, "the online demo link at the top of the README") still holds.

## Tasks & Acceptance

**Execution:**
- `README.md` -- apply `## Ruled README change` verbatim (write the fenced diff to a scratch file in your own scratch folder, `git apply --whitespace=nowarn` it; confirm with `git diff --stat README.md`).
- `docker/tests/test-readme.sh`:
  - `TEASER` becomes the ruled teaser line `Or watch the 35-second teaser: https://youtu.be/wycbyfnXFMU`; add `FULLVIDEO` = the ruled full-video line, word for word.
  - `top`: between the header block and the first H2 the lines are the opening paragraph, the full-video line, the teaser line and exactly one image line, in that order (the image below the teaser, as now); the first six H2s are, in order: "Try it in two minutes", "One incident, end to end", "What's interesting", "Measured", "What you can use it for", "How you talk to it".
  - `teaser`: the full-video line two lines below the opening paragraph, then the teaser line two lines below it, each once, word for word.
  - `interesting`: the 120-word cap counts the section's own text before its first H3 (image lines not counted, as now); the section's only H3 is "New since 1.0.0". The cap's number and the facts list are unchanged.
  - New rule `video`: the full-video line holds the YouTube link https://youtu.be/HIyCG5E6-JQ and the MP4 https://github.com/jbrandtmse/OcuTalon/releases/download/v1.0.6/ocutalon-1.0.6.mp4; the link bar (the first line of "Try it in two minutes" that starts with `[Online demo]`) holds `[Video: one incident, traced (3:04)](https://youtu.be/HIyCG5E6-JQ)` directly before `[Video: the 35-second teaser](https://youtu.be/wycbyfnXFMU)`; the teaser URL appears only in the teaser line and the link bar.
  - New rule `path`: the H2 "One incident, end to end" holds its ruled intro line and the seven ruled numbered steps, word for word, in order; "Two things to look at in the demo" appears nowhere.
  - New rule `new-since`: "### New since 1.0.0" sits under "What's interesting" (after its image line, before "## Measured"), with its ruled intro line, then the three ruled `####` headings in order ("Your integrations", "Your documents and memory", "Personas, the heartbeat checklist and the digest"), and under them the 14 bullets by bold name, each exactly once, in the ruled order: Your integrations: A dry run that checks good messages; Incident summaries; Suspend, resume and reroute; Partner delay notices; Queue backlogs between digests; A History page; A Usage page. Your documents and memory: Answers from your own documents; Where an answer came from; Memory; The Memory card. Personas, the heartbeat checklist and the digest: Personas; A heartbeat checklist; A daily digest.
  - Every new or changed rule self-tests with one bad variant per way to break it (`st` / `st_move`), as the existing rules do; update `RULES` and the header comment.
- `web/scripts/usage-docs.test.mjs`, `web/scripts/history-docs.test.mjs` -- change only the order assertions to the ruled order (History after Queue backlogs between digests, Usage after History, as the ruled list has them); keep every bullet-text pin.

**Acceptance Criteria:**
- Given the README, when it is read from the top, then the ruled full-video line (YouTube and the v1.0.6 MP4) sits above the ruled teaser line, and the link bar holds the full video directly before the teaser; `test-readme.sh` passes `video`, `teaser` and `top` and fails on each of their bad copies.
- Given the README, when its sections are read in order, then they run: "Try it in two minutes"; "One incident, end to end" with its seven ruled steps; "What's interesting" with "New since 1.0.0" below it in the three ruled groups and the ruled order, all 14 items present; "Measured" (with no "Two things to look at"); `test-readme.sh` passes `path`, `new-since` and `interesting`, and every rule it held before still passes, unweakened.
- Given the web README tests, when they run, then they pass with the ruled order.
- Given CI on this story's head, when it finishes, then every workflow is green.

### Review Findings

Code review 2026-11-12 (four layers, full-opus tier; worktree `.worktrees/epic-0`, HEAD 068ece62). 0 decision-needed, 1 patch, 1 defer, 10 rejected. README.md untouched (ruled text).

- [x] [Review][Patch] `interesting`'s facts check read the whole section, so "Visual Trace" and "dry run" were satisfied by the image's alt text and the "New since 1.0.0" bullets and the section's own paragraph could drop either unflagged (low; the alt-text hole predates the story, the moved block widened it) [docker/tests/test-readme.sh:579] — fixed: `chk_facts` now reads the section's own text (before its first H3, image lines excluded); two self-tests strip each fact from that text only; header comment updated.
- [x] [Review][Defer] The Contest checklist has no Video row and the For judges Usability row links neither the full video nor "One incident, end to end" [README.md:409] — deferred: pre-existing, and any README text beyond the ruled diff needs a Contest Planner ruling; DW-1171 `decision-pending` owner 0-27 (fold into 0.27's README ruling).

Rejected:
- `low` Edge: a second "### New since 1.0.0" block under another H2 (e.g. Measured) is not flagged -- unlikely (README text is ruled and pinned), and the fix adds a guard; wontfix-theoretical, real if a merge leaves a duplicate block.
- `low` Edge+Blind: an unbolded bullet or a prose line inside the New since groups is not flagged -- the rule pins bullets by bold name, as the spec asks; unlikely, fix adds a guard.
- `low` Edge: a copy of the link bar elsewhere passes `video` (text, not position, compared) -- unlikely, negligible harm (the copy still has the full video before the teaser).
- `by-design` Blind: the incident is narrated in five places -- ruled text and structure.
- `by-design` Blind: "you approve in the web chat" next to step 5's chat/phone/Telegram, and the video's two names -- ruled text.
- `by-design` Blind: "Your integrations" grouping and order differ from the epics AC's "watching" first -- the Planner's ruled order supersedes (spec `## Ruled README change`).
- `by-design` Blind: the full-video line is pinned by `top`, `teaser` and `video` -- each pin is a spec Task; the over-long header line is cosmetic.
- `false` Blind: the usage-docs header comment is stale -- it describes that node test, which still does not pin the last position.
- `wontfix-theoretical` Blind: the MP4 asset and the YouTube video are not checked to exist -- hermetic by design; real if the v1.0.6 release asset is deleted or re-tagged.
- `false` VGap: AC 4 (CI green) has no pinning test -- a CI-state criterion, judged on the pushed head.

## Ruled README change

The Contest Planner's ruled text (prompts/story-026-rulings.md part (a), 2026-11-12 ~00:55Z: the video lines replaced with the Planner's exact two lines, the link bar as drafted, step 1's *Break the feed* in italics, step 3's ruled wording, steps 2 and 4 to 7 verbatim, "New since 1.0.0" with the H3, three H4s and every bullet verbatim and the Planner's order under "Your integrations", "Two things to look at in the demo" removed). Apply it verbatim:

```diff
--- a/README.md
+++ b/README.md
@@ -12,13 +12,15 @@
 
 Your integrations already tell you when something breaks, usually fifty times. OcuTalon reads the failures, works out the one cause, proposes the fix with a dry run, and only interrupts you when something needs you. Nothing risky runs without your yes: fixed rules that the model can't change decide what is risky, and every approval lands in the IRIS audit log. Every decision is in Visual Trace with its reasons and cost. Without a model it fails safe: it tells you everything and claims nothing.
 
-Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU
+Watch the full video (3:04), "One incident, approved from a phone, traced": https://youtu.be/HIyCG5E6-JQ, or download it as an MP4 file: https://github.com/jbrandtmse/OcuTalon/releases/download/v1.0.6/ocutalon-1.0.6.mp4
 
+Or watch the 35-second teaser: https://youtu.be/wycbyfnXFMU
+
 ![The OcuTalon page on the online demo: an incident card for 50 failed orders names the cause and shows a dry run of the fix waiting for approval; the simulated phone shows the same approval request.](docs/images/page-incident.png)
 
 ## Try it in two minutes
 
-[Online demo](https://demo.ocutalon.com) · [Video: the 35-second teaser](https://youtu.be/wycbyfnXFMU) · [Article: built the IRIS way, step by step](https://community.intersystems.com/post/ocutalon-personal-assistant-built-iris-way-step-step-visual-trace) · [Article: what it costs to run](https://community.intersystems.com/post/what-always-ai-assistant-costs-run-real-numbers-iris) · [Open Exchange](https://openexchange.intersystems.com/package/OcuTalon) · [Releases](https://github.com/jbrandtmse/OcuTalon/releases) · [CI](https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml?query=branch%3Amain) · [MIT License](LICENSE) · [For judges](#for-judges-where-to-look) · [Contest checklist](#contest-checklist)
+[Online demo](https://demo.ocutalon.com) · [Video: one incident, traced (3:04)](https://youtu.be/HIyCG5E6-JQ) · [Video: the 35-second teaser](https://youtu.be/wycbyfnXFMU) · [Article: built the IRIS way, step by step](https://community.intersystems.com/post/ocutalon-personal-assistant-built-iris-way-step-step-visual-trace) · [Article: what it costs to run](https://community.intersystems.com/post/what-always-ai-assistant-costs-run-real-numbers-iris) · [Open Exchange](https://openexchange.intersystems.com/package/OcuTalon) · [Releases](https://github.com/jbrandtmse/OcuTalon/releases) · [CI](https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml?query=branch%3Amain) · [MIT License](LICENSE) · [For judges](#for-judges-where-to-look) · [Contest checklist](#contest-checklist)
 
 Start with the online demo, at https://demo.ocutalon.com (nothing to install, and no Early Access image needed). Its sign-in details are on the splash screen. The splash screen also shows a read-only Visual Trace account, for opening Visual Trace in the portal yourself; on the demo, the trace links on the page open Visual Trace without a second sign-in.
 
@@ -39,30 +41,50 @@
 | Applicability | [What you can use it for](#what-you-can-use-it-for): a partner feed that breaks, a production watched quietly, and an AI step in your own production. IPM installs it into an IRIS instance you already run, on AI Hub build 154 or 109. It implements the community idea [DPI-I-689](https://ideas.intersystems.com/ideas/DPI-I-689). |
 | Usability | The demo guide walks one incident in about two minutes, and its More to try panel has fifteen more things to try ([New since 1.0.0](#new-since-100)). A dry run with counts comes first, and nothing risky runs without your yes. [Measured](#measured): 0 changes made without a person's approval, and 0 prompt-injection attempts that led to an action. A recorded evaluation set of over 50 cases ([eval](eval)) scores the real model. |
 
+## One incident, end to end
+
+The demo guide walks one incident in about two minutes, and you can check each step yourself on the online demo:
+
+1. **Failures.** *Break the feed* makes a simulated partner send 50 orders in a changed date format into the Orders production, where they fail for real.
+2. **One incident.** OcuTalon reads the failed messages and groups them by cause into one incident: one notice, not 50 alerts.
+3. **Diagnosis.** It explains the cause in plain English and names the field or production item at fault.
+4. **Dry run.** It proposes a fix with a dry run: how many orders it would resend, with an example.
+5. **Approval.** Nothing is resent until you press Approve in the chat or on the page's Simulated phone; on your own install you can also approve it in Telegram. Every answer lands in the IRIS audit log.
+6. **Fix.** After the approval, OcuTalon resends the orders and reports how many went through.
+7. **Visual Trace.** Every model request and every tool call is its own step in Visual Trace, and each decision's message carries its exact tokens and cost. The trace links on the page open it.
+
+## What's interesting
+
+OcuTalon runs as an IRIS Interoperability production, so the agent is an Interoperability workflow, and its work shows in Visual Trace, the tool you already use for your feeds. For each item that arrives, an IRIS AI Hub agent makes one attention decision, with its reasons and cost. Nothing risky runs without your yes: you get a dry run with counts first, you approve in the web chat, and every answer lands in the IRIS audit log. It was built this way so that you can audit and debug your assistant in the same place as the rest of your integrations. It implements the community idea [Use InterSystems Interoperability as a Traceability tool for GenAI LLM pipelines](https://ideas.intersystems.com/ideas/DPI-I-689).
+
+![Visual Trace of one whole decision: the incident manager hands the incident to the decision process, which calls the diagnosis agent, and each of the agent's model requests and tool calls shows as an agent step of its own; then come the dry run, the approval request held as a Workflow task and its answer, the fix run, and the notices to the web chat and the simulated phone, each a production message.](docs/images/vt-decision.png)
+
 ### New since 1.0.0
 
 Each item says where to try it on the online demo. Visual Trace there is shared, so save and add nothing personal.
 
-- **Memory.** Say "Remember that ..." in the chat, and it answers later questions from what it remembered. "What do you remember?" lists your memories, and you can tell it to forget one. The vectors are computed on your instance by FastEmbed in Embedded Python, and a search combines IRIS vector search with a keyword index. Forgetting deletes the memory, its search entries and any pin at once, so no later session start reads it; earlier messages of the current conversation aren't rewritten. Try it: More to try, *Ask it to remember something*.
-- **Answers from your own documents.** Add Markdown, plain-text, PDF or Word (.docx) files on the Documents page, then ask about them in the chat. The answer names the document and section it used, or says "None of your documents cover that." Try it: More to try, *Ask about a document*, which adds a sample runbook if you have no file to hand.
-- **A daily digest.** On your own install, OcuTalon sends a digest each morning, by default at 08:00 to the web chat, and to Telegram when it is paired: how IRIS is doing, a Passed, Failed or Not checked line for each watched production, what needs you, and yesterday's cost. The checks and the verdict come from OcuTalon's code, not the model. Try it on the online demo: ask "Send my digest now".
-- **Personas.** In the Persona card, choose how OcuTalon talks: Professional, Starship computer, Pirate, Kind friend, Another language, or Your own words (on your own install). A persona changes the wording, never what OcuTalon may do. Try it: More to try, *Change how OcuTalon talks*.
-- **A heartbeat checklist.** Write what to check in the Heartbeat checklist card, and OcuTalon looks at it on your schedule, from every 30 minutes to every 24 hours. Each check-in makes one attention decision, and the card shows its cost. Try it: More to try, *Run a heartbeat check-in*.
+#### Your integrations
+
 - **A dry run that checks good messages.** Before it offers to repair and resend, OcuTalon tries the repair on up to 20 of the newest messages from the same source that went through, and offers no fix if any of them would change. Try it: after the guide's incident, More to try, *Reject a fix*, then read the approval request on the Simulated phone.
-- **The Memory card.** In the Memory card, All memories lists what OcuTalon remembers, each marked Told or Learned, with Pin, Unpin and Forget on each and a search box. Pinned shows the facts read at the start of each conversation and how much of their 1,000-token limit they use. Try it: More to try, *Pin a memory*.
-- **Where an answer came from.** An answer from your documents ends with a chip for each source that names the document and section: press it to read the passage, or open the whole document on the Documents page. An answer that recalls a memory carries a From memory chip that shows what was remembered and when. Try it: More to try, *See where an answer came from*.
 - **Incident summaries.** When an incident closes, OcuTalon writes a summary from its own records, with no extra model request: the timeline, the cause and evidence, each approval with its channel and time, the messages affected and the incident's model cost. It arrives in the chat and on the Simulated phone (and in Telegram when it is paired on your own install), and you can ask for it again in the chat. Try it: after the guide's incident, More to try, *Read the incident summary*.
 - **Suspend, resume and reroute.** Ask OcuTalon in the chat to suspend or resume an item of a watched production, or to reroute an incident's failed messages to another item. Each comes as an approval request with its own dry run: the item's state before and after, or the count, the current and new target and one example. Nothing changes until you approve, and while the incident is open a suspend is undone the same way, by asking OcuTalon to resume the item. On the online demo every visitor shares the Orders production, so there it offers the reroute only. Try it: after the guide's incident, More to try, *Reject a fix*, then *Reroute the failed orders*.
 - **Partner delay notices.** Ask OcuTalon in the chat to warn the partner about an incident's delay. It drafts a short notice from the incident's count, times, affected flow and cause, never from a message's contents, and raises it as an approval request that shows the exact text and every recipient. Nothing is sent until you approve. In demo mode the partner contacts are simulated and the approved notice goes to the Simulated mailbox, not to a real inbox; without demo mode there are no partner contacts yet, so no notice is drafted. Try it: after the guide's incident, More to try, *Warn the partner*.
-- **A Usage page.** Open Usage in the header to see your tokens and cost by day, agent, channel or model, counted per turn and per decision, with each day's largest model request (an estimate) against the 100,000-token limit. On the online demo you see only your own session's use. Try it: More to try, *See tokens and cost*.
-- **A History page.** Open History in the header to look back at the decisions OcuTalon made on your messages, filtered by outcome, channel, date and fallback, each with its reasons and a link to its trace, and at your incidents with their state and, once closed, their summary. On the online demo you see only your own session's decisions and incidents. Try it: More to try, *Look back at past decisions*.
 - **Queue backlogs between digests.** Ask OcuTalon in the chat to watch the queue backlogs, and every minute it reads the queues of each production it can read (on the online demo, the Orders production's). When a queue holds more than 100 messages, or its oldest message has waited over 10 minutes (an admin can change both), OcuTalon decides once whether to tell you now, and again only after the queue has dropped below and backed up again. The check only reads, and a run that can't read a namespace shows Not checked, never Passed. Try it: More to try, *Watch queue backlogs*.
+- **A History page.** Open History in the header to look back at the decisions OcuTalon made on your messages, filtered by outcome, channel, date and fallback, each with its reasons and a link to its trace, and at your incidents with their state and, once closed, their summary. On the online demo you see only your own session's decisions and incidents. Try it: More to try, *Look back at past decisions*.
+- **A Usage page.** Open Usage in the header to see your tokens and cost by day, agent, channel or model, counted per turn and per decision, with each day's largest model request (an estimate) against the 100,000-token limit. On the online demo you see only your own session's use. Try it: More to try, *See tokens and cost*.
 
-## What's interesting
+#### Your documents and memory
 
-OcuTalon runs as an IRIS Interoperability production, so the agent is an Interoperability workflow, and its work shows in Visual Trace, the tool you already use for your feeds. For each item that arrives, an IRIS AI Hub agent makes one attention decision, with its reasons and cost. Nothing risky runs without your yes: you get a dry run with counts first, you approve in the web chat, and every answer lands in the IRIS audit log. It was built this way so that you can audit and debug your assistant in the same place as the rest of your integrations. It implements the community idea [Use InterSystems Interoperability as a Traceability tool for GenAI LLM pipelines](https://ideas.intersystems.com/ideas/DPI-I-689).
+- **Answers from your own documents.** Add Markdown, plain-text, PDF or Word (.docx) files on the Documents page, then ask about them in the chat. The answer names the document and section it used, or says "None of your documents cover that." Try it: More to try, *Ask about a document*, which adds a sample runbook if you have no file to hand.
+- **Where an answer came from.** An answer from your documents ends with a chip for each source that names the document and section: press it to read the passage, or open the whole document on the Documents page. An answer that recalls a memory carries a From memory chip that shows what was remembered and when. Try it: More to try, *See where an answer came from*.
+- **Memory.** Say "Remember that ..." in the chat, and it answers later questions from what it remembered. "What do you remember?" lists your memories, and you can tell it to forget one. The vectors are computed on your instance by FastEmbed in Embedded Python, and a search combines IRIS vector search with a keyword index. Forgetting deletes the memory, its search entries and any pin at once, so no later session start reads it; earlier messages of the current conversation aren't rewritten. Try it: More to try, *Ask it to remember something*.
+- **The Memory card.** In the Memory card, All memories lists what OcuTalon remembers, each marked Told or Learned, with Pin, Unpin and Forget on each and a search box. Pinned shows the facts read at the start of each conversation and how much of their 1,000-token limit they use. Try it: More to try, *Pin a memory*.
 
-![Visual Trace of one whole decision: the incident manager hands the incident to the decision process, which calls the diagnosis agent, and each of the agent's model requests and tool calls shows as an agent step of its own; then come the dry run, the approval request held as a Workflow task and its answer, the fix run, and the notices to the web chat and the simulated phone, each a production message.](docs/images/vt-decision.png)
+#### Personas, the heartbeat checklist and the digest
+
+- **Personas.** In the Persona card, choose how OcuTalon talks: Professional, Starship computer, Pirate, Kind friend, Another language, or Your own words (on your own install). A persona changes the wording, never what OcuTalon may do. Try it: More to try, *Change how OcuTalon talks*.
+- **A heartbeat checklist.** Write what to check in the Heartbeat checklist card, and OcuTalon looks at it on your schedule, from every 30 minutes to every 24 hours. Each check-in makes one attention decision, and the card shows its cost. Try it: More to try, *Run a heartbeat check-in*.
+- **A daily digest.** On your own install, OcuTalon sends a digest each morning, by default at 08:00 to the web chat, and to Telegram when it is paired: how IRIS is doing, a Passed, Failed or Not checked line for each watched production, what needs you, and yesterday's cost. The checks and the verdict come from OcuTalon's code, not the model. Try it on the online demo: ask "Send my digest now".
 
 ## Measured
 
@@ -81,11 +103,6 @@
 
 Where the money goes and how to cap it, with the numbers: [What an always-on AI assistant costs to run](https://community.intersystems.com/post/what-always-ai-assistant-costs-run-real-numbers-iris).
 
-Two things to look at in the demo:
-
-- It works from real failures. The broken partner feed sends real orders that fail in the Orders production; OcuTalon reads the failed messages and groups them by cause into one incident.
-- Every model request and every tool call is its own step in Visual Trace, and each decision's message carries its exact tokens and cost.
-
 ## What you can use it for
 
 - **The partner feed that breaks at 2am.** A trading partner changes a date format, and 50 orders fail. Instead of 50 alerts, you get one notice: the cause in plain English, the fix, and a dry run that shows what it would resend. Nothing is resent until you approve, and then OcuTalon reports how many orders went through. Break the feed in the online demo plays this out in two minutes. On your own install you can also approve it in Telegram on your phone, without a laptop or the Management Portal ([how to set up Telegram](#telegram)).
```

## Spec Change Log

- 2026-11-12 ~01:00Z, lead: written by the lead after the Contest Planner's PUBLIC TEXT ruling split the original Story 0.26 plan (now Story 0.27's draft spec, `spec-0-27-a-measured-comparison-of-the-agent-and-the-fixed-rules-repla.md`). This spec is part (a) only; its README text is the ruled text; its test-readme and web-test tasks come from the original plan's measured findings. The held-out expected answers (6af31dab) stay in this branch's history unrebased; they are taken out of this story's tree by a revert commit, because test-eval-set.sh's `cases` rule requires each held-out incident's snapshot.json, which Story 0.27 records; Story 0.27 restores them byte for byte (lead ruling, decide).

## Review Triage Log

### 2026-11-12 -- Review pass
- verdicts: 20 findings -- high 0, medium 0, low 13, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: Usability / Developer Experience rows of "For judges" do not point to the new section -- the README text is the Planner's ruled text and the spec forbids any text beyond the ruled diff.
  - `[low]` `[reject]` Blind: the intro "check each step yourself on the online demo" vs the Telegram clause of step 5 -- ruled wording, applied verbatim (byte-identical to the ruled diff, checked); editing it needs a new ruling.
  - `[low]` `[reject]` Blind: the incident narrated in three places -- ruled structure, each pinned by its own rule by design.
  - `[low]` `[reject]` Blind: usage-docs comment vs `new-since` flagging an unexpected bullet -- the comment is true for that node test; the exact-14-bullets pin is the spec's own Task ("each exactly once").
  - `[false]` `[reject]` Blind: `chk_facts` runs on the whole section -- the verification-gap layer showed the 5 facts were already satisfied before the change and Interoperability, AI Hub and audit log are only in the section's own text; nothing newly weakened.
  - `[low]` `[reject]` Blind: v1.0.6 MP4 URL hard-coded in mutation strings -- negligible; the release asset exists (reviewer checked with gh).
  - `[low]` `[reject]` Blind: one over-long header comment line -- cosmetic, no harm.
  - `[low]` `[reject]` Blind: no file size on the MP4 link / no pin of "3:04" -- ruled text; adding text is not allowed.
  - `[low]` `[reject]` Edge: awk bullet parse takes the name up to the first `.**` -- theoretical, the exact-name and order checks catch real moves.
  - `[false]` `[reject]` Edge: MP4 asset existence not tested -- hermetic by design; the asset exists on v1.0.6.
  - `[low]` `[reject]` Edge: two failure lines when the link bar is missing -- noise only, still red.
  - `[false]` `[reject]` Edge: teaser spacing measured from the first full-video copy -- the count check fails the duplicate.
  - `[low]` `[patch]` VGap: AC video had no `mutation:` line for the `video` rule -- added (MP4 link removed -> `top`, `video`, `teaser` red).
  - `[low]` `[patch]` VGap: the changed History order assertion had no mutation -- added (Queue backlogs and History swapped -> red in `history-docs.test.mjs`).
  - `[false]` `[reject]` VGap: AC CI-green has no pinning test -- a CI-state criterion; judged on the pushed head.
  - `[low]` `[reject]` VGap: MP4 asset URL pinned as a string only -- same as the Edge row, hermetic.
  - `[low]` `[patch]` VGap: two `teaser` self-test labels name the opening-to-teaser gap -- relabelled for the full-video line (cosmetic, same mutations).
  - `[false]` `[reject]` Intent: readings R1 to R4 -- descriptive; the diff implements the ruled text plus the pinning rules; the README is byte-identical to the ruled diff (checked with patch on the baseline README).
  - `[false]` `[reject]` Intent: tests pin source text, not the rendered page -- by design for test-readme.sh.
  - `[false]` `[reject]` Intent: `images` mutation rewritten to the hero image anchor -- the same mutation on the real README, no weakening.

## Design Notes

**Governing ADs:** none binds README text or test-readme.sh (AD-29: Epic 0 may edit any lane's files). No AD is amended.

**Decided by the lead (U5 decide):** the held-out files of 6af31dab are reverted in this story's tree (a forward revert commit, never a rebase or an amend of 6af31dab), because pushing them without their snapshots would turn test-eval-set.sh's `cases` rule red ("its snapshot is not a file of the folder" for the 4 held-out incidents). Story 0.27 reverts the revert first, so the bytes committed in 6af31dab are the ones it runs on (its SHA-256 pins prove it).

Integration (Rule 1/2): not service-introducing (README text and its tests). Consumed-by: none. Consumes: none.

Extend, don't copy: the new rules follow `top`, `teaser` and `measured`'s pattern (`chk_<name>`, `rule_<name>`, `st`, `st_move`, `finish`).

Ledger inbox: none.

Footprint extensions (outside the scope's list): `web/scripts/usage-docs.test.mjs`, `web/scripts/history-docs.test.mjs` (order assertions only).

## Verification

Shared surfaces: `test-readme.sh`'s H2 order list (`top`), the teaser line (`teaser`), the region of the `interesting` cap, the new rules `video`, `path` and `new-since`, and its `RULES` count; the web README tests' "New since 1.0.0" order.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands** (from the worktree root, one per call, each under about 150 s):
- `bash docker/tests/test-readme.sh` (loop, about 22 s) -- expected: `test-readme: all rules passed`.
- `(cd web && node --test scripts/sources-docs.test.mjs scripts/usage-docs.test.mjs scripts/history-docs.test.mjs scripts/more-to-try-view.test.mjs scripts/sample-runbook-view.test.mjs scripts/allowance-sources.test.mjs)` (loop) -- expected: 0 failed.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s) -- expected: `test-boundaries: all rules passed`.
- `/bin/bash docker/tests/test-readme.sh` (once) -- expected: the same under bash 3.2.
- `LC_ALL=C tr -d '\011\012\040-\176' < docker/tests/test-readme.sh | wc -c` (once) -- expected: 0.
- `git diff --name-only <baseline> -- .github ci release _bmad eval` (once) -- expected: empty.

Mutations (one per AC; record `mutation: <change> -> <test that went red>` here, revert, check `git status --short` and `git diff --stat` unchanged):
- AC video: swap the full-video and teaser lines -> `teaser` and `top`.
  mutation: swapped the text of the full-video line and the teaser line -> `top` and `teaser` red (tree restored byte-identical from a scratch backup).
  mutation: removed the MP4 link from the full-video line -> `top`, `video` and `teaser` red.
- AC order: move "New since 1.0.0" back under "Try it" -> `new-since` and `interesting`; drop one bullet -> `new-since`; restore "Two things to look at in the demo" -> `path`.
  mutation: moved the "New since 1.0.0" block to just before "One incident, end to end" -> `new-since` and `interesting` red.
  mutation: dropped the "Partner delay notices" bullet -> `new-since` red.
  mutation: added "Two things to look at in the demo:" under "Measured" -> `path` red.
- AC web tests: (covered by the order assertions' own red on the old order).
  mutation: moved the History bullet after the Usage bullet -> "comes after the History bullet" red in `usage-docs.test.mjs` (1 failed of 18 in the two files).
  mutation: swapped the Queue backlogs and History bullets -> "comes after the Queue backlogs bullet" red in `history-docs.test.mjs`.
- QA additions (QA), 4 mutations demonstrated on scratch copies of `test-readme.sh` (the README and the tree were not touched):
  mutation: (QA) removed the new count of teaser lines from `chk_top` -> `top` red ("the teaser line twice: not flagged").
  mutation: (QA) removed the `chk_block path` call from `chk_path` -> `path` red (the per-step "word added", "without its italics", "renumbered" and "swapped" self-tests, and the existing reworded ones).
  mutation: (QA) removed the order message from `chk_new_since` -> `new-since` red (the last-two, first-and-last, bullet-pair and Memory/Where-an-answer swap self-tests, and the existing ones).
  mutation: (QA) made `chk_video` ignore a teaser address outside the teaser line and the link bar -> `video` red (the teaser address in the full-video line and in the incident section, and the existing one).
- Code review (CR), the `interesting` facts check moved to the section's own text:
  mutation: (CR) `chk_facts` reading the whole section again (the code before the patch) -> `interesting` red ("Visual Trace only in the image and below the H3" and "dry run only in the image and below the H3" not flagged); with the patch, all rules pass under bash and /bin/bash 3.2.
- Files changed by QA (QA): `docker/tests/test-readme.sh` (strengthened `chk_top` to require exactly one teaser line before the first H2; 27 more self-tests in `top`, `video`, `path` and `new-since`). No other file; `README.md` untouched.

## Auto Run Result

Status: done
Blocking condition: none

Summary: the README now leads with the full video (3:04, YouTube and the v1.0.6 MP4) above the teaser and in the link bar; a new H2 "One incident, end to end" holds the seven ruled steps; "New since 1.0.0" sits under "What's interesting" in three ruled groups; "Two things to look at in the demo" is removed. The README is byte-identical to the ruled diff.

Files changed:
- `README.md` -- the ruled diff, verbatim.
- `docker/tests/test-readme.sh` -- `top`, `teaser`, `interesting` and `images` moved to the new anchors; new rules `video`, `path` and `new-since`, each with self-tests; `RULES` and header updated.
- `web/scripts/usage-docs.test.mjs`, `web/scripts/history-docs.test.mjs` -- order assertions only (History after Queue backlogs, Usage after History).

Review: 20 findings from four layers; 3 patched (two mutation lines in `## Verification`, relabelled `teaser` self-tests), 0 deferred, 17 rejected with their reasons in the triage log. Follow-up review recommended: false (patched: 0 high, 0 medium).

Verification: `bash docker/tests/test-readme.sh` all rules passed; web docs tests 0 failed; mutations recorded in `## Verification`.

Residual risk: the MP4 asset and the video length are not checked by the hermetic tests; CI on the pushed head is judged by the lead.
