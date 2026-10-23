# Unattended inbox -- run 20261021T1347Z-1-16,29-32

Answer an item with `bash _bmad/scripts/unattended-inbox.sh <this directory> answer U-<n> "<answer>" --by owner`, or run `/epic-cycle --review`. This file is generated: a hand edit is saved aside and never applied.

**Hold requested 2026-10-23T01:29:12Z: owner: almost out of quota; pause to switch accounts (relayed by the Contest Planner; the owner: "We're almost out of quota and need to pause OcuTalon so that I can switch accounts.")**

## Veto window

### U-16 | veto | Story 1.4 | 2026-10-22T07:56:08Z
question: Moving an acceptance clause inside Epic 1: Story 1.4 builds OcuTalon.Bridge.Budget.MarkCapped (the day marked capped once, under a lock; budget.capped fired once a day, ownerRef instance, payload {day}) and pins it in process, while its two triggers, the daily_cap precheck and the gateway's HTTP 403 'daily cost cap reached', and the live test that forces both paths through the mock and finds one event move to Story 1.6, which already owns that precheck and that classification. epics.md Story 1.4's last criterion is amended and Story 1.6 gains the bullet (spec decision 1).
options: keep | reverse: stage both triggers in Story 1.4 in an error-ending form (a daily_cap check in Decide.OnRequest and an OnError hook on the 403's text, both calling MarkCapped), which Story 1.6 then turns into fallbacks
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#63; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-17 | veto | Story 1.4 | 2026-10-22T07:56:08Z
question: Prices: only the 5-minute cache-write rate is stored. epics.md Story 1.4's seed clause 'cache writes at 1.25 times (5-minute) or 2 times (1-hour) the input price' becomes 'cache writes at 1.25 times the input price (the 5-minute tier, the only one AI Hub writes)'. AI Hub's cache config has no TTL key and GetStats() reports no TTL split, so no token could be priced at the 1-hour rate; Epic 0's merged Price schema (one CacheWritePerMTok per model, pinned by Lane B's Test.Data.Tables) is read as AD-19's 'cache-write tiers', and the spine is not edited (spec decision 2, Rule 5 apply-and-report).
options: keep | reverse: add a CacheWrite1hPerMTok column to Price, seeded at 2 times the input price, with a change to Lane B's Test.Data.Tables pin (needs the orchestrator)
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#64; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-18 | veto | Story 1.4 | 2026-10-22T07:56:08Z
question: Stored data: Decide gains the stored settings DailyCostCapUSD, GatewaySpendUSD and GatewaySpendDate (storage slots 5-7, appended by the compiler; AD-19 names them); the capped day's mark is a new private global ^OcuTalonBP.UsageCapped(day) (AD-3); the runner writes a Usage row for every returned Chat and for a thrown one that spent tokens; a Decision row carries the totals, with an empty cost (never 0) when a row's cost is unknown; Installer.Run() seeds the Claude Haiku 5.5 and Claude Sonnet 5.5 Price rows only where missing, with Sonnet's cache rates derived from the same multiples (0.20, 2.50) and no long tier for it (spec decisions 3, 6, 7, 14).
options: keep | reverse: change the row writers (no shipped rows exist yet) or drop the properties and regenerate Decide's storage
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#65; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-19 | veto | Story 2.3 | 2026-10-22T08:29:53Z
question: Ruled (veto): CommandsIn's eight plain-English CommandResult texts are new (not in the UX or PRD), e.g. 'That can't be done from the chat. Nothing was changed.', 'Only an OcuTalon admin can change settings. Nothing was changed.', 'This part of OcuTalon isn't built yet. Nothing was changed.', 'Something went wrong inside OcuTalon, so the command may not have finished.' They reach the model as tool results, the admin terminal and later REST error bodies. Two security-posture choices, both narrowing only: an active bridge context makes the origin 'tool' at the gate too, and routing matches exact verb class names (anything else refused). Texts are class parameters of OcuTalon.Core.CommandsIn (spec-2-3).
options: keep (a): as ruled | reverse (b): name replacement texts or rules; each is one parameter or one table entry
recommendation: keep (a)
blocks: nothing now; a reversal is a small fix story
answer: keep (a) (by Contest Planner, 2026-10-23T01:30:37Z#72; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-20 | veto | Story 2.4 | 2026-10-22T11:43:05Z
question: Ruled (veto): (1) schema: Lane B's Turn table gains ItemId, ClientId, Text, ReplyText, ReplyCatalogKey, FallbackReason, TraceHeaderId, Tainted and Attempt (storage slots 10-18) plus a unique ItemIdIndex and a ClientIdIndex, so each turn keeps my message and its reply as sent (DW-61; the snapshot shows them after a reload; nothing but test fixtures wrote Turn before, so nothing migrates). Msg.Item gains ClientId (slot 12, additive). (2) new public text: REST 400 bad_message 'A message needs a clientId and some text.' (spine Conventions REST row amended).
options: keep (a): as ruled | reverse (b): drop or rename fields, or reword the text (a small fix story; the text is one parameter)
recommendation: keep (a)
blocks: nothing now
answer: keep (a) (by Contest Planner, 2026-10-23T01:30:37Z#73; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-21 | veto | Story 1.5 | 2026-10-22T13:43:19Z
question: Stored data: the bridge's Reply gains Steps (a JSON array of the turn's step records; storage slot 9, appended), Decide sends each step as an AgentStep message that stores redacted, cut summaries of tool inputs, results and errors (kept by Ens's purge like any message), and the Usage row's LargestRequestTokens becomes the largest of the measured last request and the step estimates, set after a throw too (DW-77, AD-20 unchanged) (spec decisions 1, 2, DW-77).
options: keep | reverse: drop Reply.Steps and send the steps another way, or store fewer step fields; LargestRequestTokens back to the measured last request
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#66; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-22 | veto | Story 1.5 | 2026-10-22T13:43:19Z
question: Security posture: the one redactor OcuTalon.Bridge.Redact (Conventions: Redaction) masks sensitive JSON keys and secret patterns in plain text (model key, access token, password, Telegram chat id and display name) as [redacted], redacts before it cuts, and fails closed (a fixed '[redacted ...]' text when it cannot finish); the mock scenario steps-secrets.json writes its fake key and bot token with one JSON \u escape so the committed file passes the repository's key-like-string scan (spec decision 9).
options: keep | reverse: change the redactor's rules, or keep the fake secrets out of committed files (generate them in the test)
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#67; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-23 | veto | Story 1.5 | 2026-10-22T13:43:19Z
question: Public-facing text not in the UX: the agent-step labels and summaries a judge reads in Visual Trace ('Model request <n>', 'About <t> tokens sent (an estimate)', 'Running a tool', the tool inputs-and-results form) and the convention that a tool's label is a STEPLABEL<NAME> or STEPLABEL class parameter, now a Consistency Conventions row in the spine (spec decision 4).
options: keep | reverse: reword the labels or summaries (text only; no structure change)
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#68; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-24 | veto | Story 2.5 | 2026-10-22T17:01:13Z
question: Ruled (veto): /state's chat keeps only the session's newest 100 entries (turns and noticed incidents, oldest first; snapshot shape unchanged) so a growing local session never makes the snapshot unbounded (DW-65). Older turns stay stored and in Visual Trace, but a reload no longer shows them in the page; paging would need new UI text and a new API, so it would be its own story. Also decided: reply links open in a new tab, as Story 2.5's criteria and UX-DR60 say, although EXPERIENCE.md:391 / UX-DR127 limit new tabs to Visual Trace and README links (UX doc conflict noted for the UX owner).
options: keep (a): 100-entry cap, as ruled | reverse (b): a different cap, or paging as a new story | (c) reply links in the same tab
recommendation: keep (a)
blocks: nothing now; a different cap is one parameter (Web.Api CHATMAX)
answer: keep (a) (by Contest Planner, 2026-10-23T01:30:37Z#74; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-25 | veto | Story 1.6 | 2026-10-22T20:34:49Z
question: Stored data and how failures show: the bridge's Reply gains FailureText (a redacted failure text of at most 2,000 characters; storage slot 10), Decide gains the setting DecisionTokenBudget (default 0, off; storage slot 8), and a Chat that throws now leaves the runner's message Completed with a warning (its failure Reply carries the redacted text, the buffered steps and the usage to Decide, which records a fallback flagged in Visual Trace) instead of an Errored header (spec decisions 2, 5; DW-83).
options: keep | reverse: keep the runner's header Errored and carry the steps another way; drop FailureText or DecisionTokenBudget
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#69; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-26 | veto | Story 1.6 | 2026-10-22T20:34:49Z
question: Money posture (DW-76): a set daily cost cap fails OPEN, with each fault logged as a warning, when a Usage row's cost is unknown (a model with no Price row) or a budget setting (DailyCostCapUSD, GatewaySpendUSD, GatewaySpendDate) cannot be read; failing closed would block every decision with a false reason. A local install's cap is off by default, and the online demo's gateway enforces its own cap (spec decision 4).
options: keep | reverse: fail closed (every decision falls back with daily_cap while a fault stands)
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (fail open: the online demo's gateway enforces its own hard daily cap, and an unknown model is priced high there) (by Contest Planner, 2026-10-23T01:30:37Z#71; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-27 | veto | Story 2.5 | 2026-10-22T22:46:30Z
question: Ruled (veto, security posture and visible text): a labelled link in OcuTalon's reply now shows the host it opens after the label, e.g. 'the guide (example.org)', with punycode for non-ASCII hosts, so a model-written label cannot hide where a link goes; a bare URL shows as itself. Also for the UX owner: chat entries show only hour and minute (the spec's format), so entries from earlier days carry no date.
options: keep (a): as ruled | reverse (b): show the label alone (as the UX shows), or render the full address | (c) add a date to older entries (a UX change; a small story)
recommendation: keep (a)
blocks: nothing now; reply-text.ts holds the rule
answer: keep (a) (by Contest Planner, 2026-10-23T01:30:37Z#75; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-28 | veto | Story 2.6 | 2026-10-22T23:33:19Z
question: Ruled (veto): (1) schema: Lane B's Turn gains CheckKey and CheckRows so a reply's check rows survive a restart; (2) composed page text built from the UX's own strings and patterns but not written out in it: '{label}...' and '{label} . 12 s' (spoken '12 seconds'), durations like '1 min 3 s', and a fallback-only decision strip (Tell now, Fallback, the reason; no confidence, cost or Details when a fallback reply has no decision row); (3) every outcome chip, the empty panel's included, gains the pointer tooltip. Also recorded in the spine (Conventions): chat.message carries the shown decision, turn cost and check rows; a 'HostData' row names check results HostData.checks and a check row {result, entry, finding, checkedAt}, as Stories 2.6 and 5.7 describe.
options: keep (a): as ruled | reverse (b): drop the stored check rows (lost on restart), reword any composed text, or limit the tooltip
recommendation: keep (a)
blocks: nothing now; each is a small fix story
answer: keep (a) (by Contest Planner, 2026-10-23T01:30:37Z#76; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

### U-29 | veto | Story 1.6 | 2026-10-22T23:49:35Z
question: A cut-off tool call: the spec's matrix row 'A cut-off tool call ... Never a usable answer' is restated to what build 154 allows. AI Hub runs a tool call that the provider cut at max_tokens and goes on, and Chat returns the later reply's stop reason (end_turn), so that turn's final reply is the answer; a final reply cut at the cap is still never an answer (cut_off, AC1). TestCutOffToolCall pins the measured behaviour; whether a cut tool call's arguments can be truncated on the real API is not measured (spec deferred item 1).
options: keep | reverse: only an AI Hub change (a stop reason per response) can make every cut-off tool call a fallback
recommendation: keep
blocks: nothing (ruled; work continues)
answer: keep (by Contest Planner, 2026-10-23T01:30:37Z#70; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf.")

## Holds

### U-31 | hold | Run 20261021T1347Z-1-16,29-32 | 2026-10-23T02:36:43Z
question: The run is held as you ordered (almost out of quota; account switch). Resume after the switch, bringing in Lane C?
options: resume: after the Contest Planner's Lane C planning commit, run /epic-cycle 1-16,29-32 --unattended interactively in a fresh session launched with --permission-mode bypassPermissions; it re-approves the graph with you; or keep holding
recommendation: resume with Lane C as planned
blocks: every epic (Epics 1 and 2 held)
answer: (none yet -- answer with the script or --review)

## Run reports

### U-30 | report | Run 20261021T1347Z-1-16,29-32 | 2026-10-23T02:36:43Z
question: Run report at the second hold (2026-10-23): since the resume of 2026-10-22 01:04Z, Epic 1 finished Stories 1.2-1.5 (1.6 past code review, hold patch) and Epic 2 finished 2.1-2.5 (2.6 implemented, unreviewed); run total: Epic 32 merged (3 stories) plus 10 stories done in Epics 1 and 2. CI hosts upgraded to Premium Intel (12 services); intermittent ci-c start timeouts before that, re-run as infra. 14 veto items open (U-16 to U-29): at 20 the merges hold (veto_open_max), so please review them before Epic 1 closes. Decision sheet ahead: DW-92 (owner: report the cut-off tool call to InterSystems), DW-93, DW-54 (Epic 1), DW-75 (Epic 2). Lane C comes in at the next resume (graph re-approval).
options: read
recommendation: read; review the open veto items; resume after the account switch with Lane C
blocks: nothing
answer: (none yet -- answer with the script or --review)

## Resolved
- U-1 | parked | Story 32.3: Story 32.3 (split from 32.1's second criterion): how should 'no IRIS job runs longer than about 10 minutes' be met? 32.1's plan measured that moving whole units cannot meet it on the current hosts: on run 39594299887 (five IRIS stacks on ocutalon-ci-b) live:install-start alone took 681 s, so the job holding it takes about 12 min whatever the grouping (best six-group split 13.6 min); at the lightest load seen (two stacks on ci-b) the floor is 10.1 min and the best split 11.3 min (inference: scaled); on ocutalon-ci-c install-start took 847 s alone. -> (a) Restate the 10-minute IRIS-job ceiling as a balance rule: no IRIS job more than about 25% over the mean of the six, with each job's time, runner and host recorded; a slowest job over about 10 minutes goes to the owner as a CI-capacity item. 32.1 and 32.2 proceed. (by Contest Planner, 2026-10-21T15:49:47Z#6; quoting the owner: "a"); resolved by orchestrator, 2026-10-21T22:09:40Z -- epic 32 applied it (32.3 restated as the balance rule)
- U-2 | veto | Story 1.1: Credential handling: the bridge Config Store Merge accepts api_key only as exactly one @{env:NAME} placeholder (NAME [A-Za-z0-9_]+) and refuses a literal key or any other @{ in any field, failing with nothing written (spec decision 10; AD-19 tightened, not changed). -> keep (by Contest Planner, 2026-10-21T22:15:31Z#13; quoting the owner: "Please answer any of the questions that the orchestrator escalates to you to the best of your ability while I'm gone."); resolved by orchestrator, 2026-10-21T22:42:30Z -- kept (veto window closed by the owner's delegate)
- U-3 | veto | Story 1.1: Credential handling in a test: OcuTalon.Test.Agent.KeyScan sets a fake, non-key-like ANTHROPIC_API_KEY value (ocutalon-keyscan-<NewRef>) through embedded Python in the throwaway test process only, restores the previous value afterwards, and asserts the value is stored nowhere (spec decision 13). -> keep (by Contest Planner, 2026-10-21T22:15:31Z#14; quoting the owner: "Please answer any of the questions that the orchestrator escalates to you to the best of your ability while I'm gone."); resolved by orchestrator, 2026-10-21T22:42:30Z -- kept (veto window closed by the owner's delegate)
- U-4 | veto | AD-22: AD-22's 'CI as built' bullet now names the six IRIS groups (install-fresh with live:install-start; install-upgrade with live:install-upgrade and live:audit; production; browser; shards; image) in place of five, as Story 32.1's criterion requires; the Rule text is otherwise unchanged and the old wording is quoted in the AMENDED marker. Rule 21's Groups bullet and a measured sixth-run record were updated with it. -> keep (by Contest Planner, 2026-10-21T22:15:31Z#15; quoting the owner: "Please answer any of the questions that the orchestrator escalates to you to the best of your ability while I'm gone."); resolved by orchestrator, 2026-10-21T22:42:30Z -- kept (veto window closed by the owner's delegate)
- U-5 | veto | Story 1.2: Stored message schema: the bridge's Reply gains FinishReason (%String, MAXLEN 32, the provider's stop reason from Response.Extra, empty when none; storage regenerated), and a new message class OcuTalon.Bridge.Msg.ToolInventory lets a test read a running runner's live tool list (spec decisions 7 and 11). -> keep (by Contest Planner, 2026-10-21T22:15:31Z#16; quoting the owner: "Please answer any of the questions that the orchestrator escalates to you to the best of your ability while I'm gone."); resolved by orchestrator, 2026-10-21T22:42:30Z -- kept (veto window closed by the owner's delegate)
- U-6 | veto | Story 1.2: Credential handling in tests: CI starts with no key on purpose, so the live runner tests Merge each runner's Config Store entry to api_key @{env:OCUTALON_MOCK_KEY_HEADER} (a non-secret CI-only variable, value 1) in the throwaway only, restart the runners, and restore the entries afterwards; in-process tests use the same placeholder inline (spec decision 12). -> keep (by Contest Planner, 2026-10-21T22:15:31Z#17; quoting the owner: "Please answer any of the questions that the orchestrator escalates to you to the best of your ability while I'm gone."); resolved by orchestrator, 2026-10-21T22:42:30Z -- kept (veto window closed by the owner's delegate)
- U-7 | veto | Story 32.3: Your balance rule (U-1, 'a': no IRIS job more than about 25% over the mean of the six) is judged on the grouping, i.e. each group's unit time normalized to one host, because the repository cannot choose which runner host a job lands on. Raw job times, runners and hosts are recorded every run, and the host disparity (ocutalon-ci-c runs a stack 1.4 to 2 times as long as ocutalon-ci-b; the first six-group run was 1.33x raw, 1.21x normalized) goes to you as the CI-capacity item with any job over about 10 minutes. -> keep (by Contest Planner, 2026-10-21T22:15:32Z#18; quoting the owner: "Please answer any of the questions that the orchestrator escalates to you to the best of your ability while I'm gone."); resolved by orchestrator, 2026-10-21T22:42:30Z -- kept (veto window closed by the owner's delegate)
- U-8 | report | CI capacity: Measured CI on the new hosts (Epic 32): ocutalon-ci-c starts IRIS stacks too slowly. On run 39675383146 (commit e366e33, no other run on the runners) all three IRIS jobs on ci-c failed the 400 s first-start limit (install-start, production, production-restart, sign-in), while the three on ocutalon-ci-b passed. Run 39657913372 failed the same way with six stacks on ci-c. On the first six-group run (39633794167) a stack on ci-c ran 1.4 to 1.9 times as long as on ci-b, and the job holding install-start takes about 11 min even on ci-b. Re-runs of the failed jobs have passed so far, so both lanes see intermittent reds that a re-run clears. -> (no answer); resolved by orchestrator, 2026-10-21T22:42:40Z -- handled: the Contest Planner (owner's delegate) capped ci-c to 4 services, 10 in all; recorded in Rule 21 (cc69839); a faster-disk plan is the owner's spend decision
- U-9 | veto | Story 2.1: Which address does the About dialog's README link open? No planning document names one, and the repository URL appears in no shipped file yet (owner identity in public-facing text). -> keep (a): README_URL https://github.com/jbrandtmse/OcuTalon#readme; the repository goes public before submission, and the online demo launches no earlier than that (by Contest Planner, 2026-10-22T00:16:55Z#31; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf."); resolved by orchestrator, 2026-10-22T01:04:27Z -- kept (veto window closed by the owner's delegate)
- U-10 | hold | Run 20261021T1347Z-1-16,29-32: The run is held as you ordered (weekly quota at 97%; account switch). Resume it after the switch? -> (no answer); resolved by orchestrator, 2026-10-22T01:04:27Z -- resumed by the owner after the account switch
- U-11 | report | Run 20261021T1347Z-1-16,29-32: Run report at the hold: since 13:47Z (about 10.5 h), Epic 32 merged with 3 stories (32.1-32.3; CI on six groups with per-group skips); Epic 1 has 1.1 done and green, 1.2 past code review (hold patch); Epic 2 has 2.1 implemented (pushed, before QA). 10 inbox items: U-1 answered (balance rule), U-2..U-8 resolved (vetoes kept, ci-c capped to 10 services), U-9 open (README link 404 until the repo is public), U-10 this hold. CI: intermittent infra reds on ocutalon-ci-c (disk), re-runs pass. Pace: about 5 stories in 10.5 h across two lanes, slowed by the launch fixes and CI host contention; the Nov 1 online demo depends on Lane B reaching Epic 16 (after 2, 4, 6). -> (no answer); resolved by orchestrator, 2026-10-22T01:06:26Z -- read on the owner's side (the Contest Planner's post-switch window)
- U-12 | veto | Story 1.3: Stored data: Decide gains the stored setting TimerSeconds (integer, default 60, allowed 1-110; storage slot 4, appended by the compiler, AD-5), and the first Decision rows are kept as: reasons one per line (a line break inside a model reason becomes a space, blank reasons dropped, the code-written user-rule line first), Payload = the checked model payload with the filtered reasons and the model's own outcome (for audit), a turn row with outcome tellnow and no reasons, confidence or payload, and the confidence rounded to two decimals (spec decisions 5, 7, 8). -> keep (by Contest Planner, 2026-10-22T02:19:09Z#39; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf."); resolved by orchestrator, 2026-10-22T02:19:33Z -- kept (veto window closed by the owner's delegate)
- U-13 | veto | Story 1.3: Security posture in CI: the standalone-bridge script (release/standalone-bridge.sh, run by lane-a.yml) enables Ens's testing service through one $Production TestingEnabled System Default Settings row, only in its own throwaway namespace OCUBRIDGE, to call the example production, which has no business service of its own; the shipped OcuTalon.BridgeExample.Production keeps TestingEnabled=false and holds no provider settings (spec decision 15). -> keep (the shipped production keeps TestingEnabled=false; the row exists only in CI's throwaway OCUBRIDGE) (by Contest Planner, 2026-10-22T02:19:09Z#40; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf."); resolved by orchestrator, 2026-10-22T02:19:33Z -- kept (veto window closed by the owner's delegate)
- U-14 | veto | Story 2.2: Ruled (veto): Story 2.2's snapshot AC asks for the conversation with each turn's reply and its notice cards, but no table holds a turn's text or a notice card's text yet. The runner moved those two parts to Epic 2's own later stories: turn and reply text to Story 2.4 (DW-61), notice-card storage to Story 2.7 (DW-62). Story 2.2 builds the merge, the turn and incident entries and the builder 2.4 extends. All of Epic 2 merges together, so the 2026-10-30 milestone still gets the whole AC. -> keep (a) (by Contest Planner, 2026-10-22T02:57:22Z#46; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf."); resolved by orchestrator, 2026-10-22T02:57:36Z -- kept (veto window closed by the owner's delegate)
- U-15 | stopped | Story 2.2: May Story 2.2 amend AD-13's unchecked-prepare allow-list (docker/tests/test-class-rules.sh ALLOW_UNCHECKED, today only Session.ForUser and Live.Event.Since) to add one private method, OcuTalon.Data.Ownership:Rows? Story 2.2 must read the session's turns, reminders, checks, decisions, incidents, approvals and pairing with the owner check in each WHERE clause; OcuTalonUser holds no SQL grant, as AD-13 requires, and AD-13 itself names Ownership as the API Story 2.2 switches /state and /events to. It is an extension (Binds and Prevents unchanged), but AD-13 is cited by done specs 0.2, 0.3, 0.5, 0.7, 0.8 and 2.1, so the doctrine's U7 counts it as a re-architecture, which the run may not amend on its own. -> a: amend AD-13 to add OcuTalon.Data.Ownership:Rows, keyed by class and method, with one ALLOW_UNCHECKED line. Conditions: (1) Rows takes the caller's SessionRef/OwnerRef as a required argument that it never takes from request input, and every statement it prepares has the owner check in its WHERE clause; (2) the SQL text is fixed inside Ownership per row kind, never built from caller-supplied text, field or table names; (3) a test proves isolation: a second session reading through Ownership gets none of the first session's rows, for every row kind; (4) no embedded-SQL or other unchecked path is added elsewhere, as option (b) would. Record it as an AMENDED marker on AD-13 citing this item. (by Contest Planner, 2026-10-22T02:57:22Z#45; quoting the owner: "I have delegated authority to the Contest Planner. That agent is allowed to make decision on my behalf."); resolved by orchestrator, 2026-10-23T02:36:17Z -- epic 2 applied it: AD-13 allow-list gains Ownership.Rows under the four conditions; code review confirmed all four

<!-- journal: 79 lines -->
