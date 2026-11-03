---
title: 'Story 13.4: The guide and the overview say exactly what is audited, and the guide''s gaps are closed'
type: 'chore'
created: '2026-11-03'
status: 'done'
baseline_revision: '1642a21ac2842c44ba1a2c4bc4d98afe8260490c'
baseline_commit: '1642a21ac2842c44ba1a2c4bc4d98afe8260490c'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** U-229's sentence "each tool call is still audited" is false as written: in the overview "audited" means an IRIS audit entry, and the bridge writes one only for Approval, Action, Pairing and Settings. The Contest Planner's bare-container run of `docs/bridge-guide.md` (U-233, PASS on ac3f9c58) also found five small gaps where the guide's text does not match what a reader sees.

**Approach:** Replace the U-229 sentence, word for word, in its three places (the overview's L100, the guide's Classification item and the `U229=` pin), after checking each clause against the code. Close gaps (b) to (e) and settle (g) in the guide's prose. Extend `docker/tests/test-bridge-guide.sh` so that each new statement is pinned and each pin fails on a wrong text.

## Boundaries & Constraints

**Always:**
- The sentence is exactly the Contest Planner's wording, U-237's answer (option (c), inbox 2026-11-03T10:46:10Z#712), which replaces both U-236's wording and the provisional one: "In this release, changing this setting writes no OcuTalon audit entry. Each tool call is recorded as a step of its decision unless the decision times out, and an approval and an approved call's run each write an audit entry." It sits on one line in each file. A clause that is not true stops the story with a clarification and is never reworded.
- Plain English and ASCII only. No key, local path, URL, IP address, instance name, "IRIS Couch" or OpenClaw. Each new sentence states only what the code does today.
- Every other "this release" statement in both files stays true. The overview's generated regions (L5-L81) and the `overviewdoc` pins stay unchanged.

**Never:**
- No change to a marked guide block (`<!-- guide-run: ... -->` and its fence), to any `src/**` file, to `release/**`, to `.github/**`, or to any `docker/tests/**` script other than `test-bridge-guide.sh`.
- No change in `docs/security-overview.md` other than L100's sentence. Epic 15 has an open change at L148, and Epic 14's generator owns the generated regions.
- No runnable guide block that reaches a held call, and no bridge self re-arm at production start. Both go to the ledger (`owner=burndown`, note "first daily release after 1.0.0"), filed by the runner at its gate.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Sentence in place | the guide and the overview each hold the amended U-229 on one line, the overview's inside `## Approval and audit` | `u229` PASS | none |
| Old sentence | either file still holds "...; each tool call is still audited." | `u229` FAIL naming the file | break sample in the script |
| One word changed | "writes no" becomes "writes an" in the guide | `u229` FAIL | break sample derived from `U229` |
| Split line | the two sentences on two lines | `u229` FAIL (the pin is one line) | break sample |
| Outside the section | the sentence only outside `## Approval and audit` | `u229` FAIL | existing break sample |
| Gap phrase missing | the guide lacks the allow-list default, View Full Trace, the header-id note, `Ens.Alarm`, the Portal notice or `Decide`'s USERANSWERED reason | `reference` FAIL naming the phrase | one break sample each |

</intent-contract>

## Code Map

**Files changed (the whole footprint):**
- `docs/security-overview.md:100`: the hand-written Approval and audit paragraph, outside the generated regions (markers at L5-L81). Only its U-229 sentence changes.
- `docs/bridge-guide.md`: L99 (step 6), L124 (after the governance blocks), L177 (`AgentAllowList` default cell), L256-L266 (the place for the user rule), L291 (the Classification item, U-229).
- `docker/tests/test-bridge-guide.sh`: `U229=` (L39), `PROSE_PHRASES` (L46-L59), `reference_problems` (L305-L323) with its keep sample (L340-L347) and break samples (L353-L377), and `u229_problems` with its fixtures (L392-L417). Header L16.

**Evidence for the U-229 clauses (read-only):**
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:188`: the one `$SYSTEM.Security.Audit` call outside the tests. Every OcuTalon audit entry goes through `Audit.Record`.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:21,106`: the only non-test `Record("Settings", ...)` caller. `ALLOWLIST = "demo.mode"`.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls:306` and `Approval.cls:230`: `ToolClassification` and `ApprovalRole` are read at each use through `Ext/Accessor.cls:19-28` (`Ens.Director.GetItemSettingValue`), so the two settings are read live.
- `src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls:18-39`: `%LogExecution` (ok or error) and `%LogDenial` (denied) put every tool call into the step buffer. The platform contract is `irislib/%AI/Policy/Audit.cls:17-55`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - L339 `EmitSteps` and L459-L530 `StepMessages`: the steps become `AgentStep` messages to `AgentSteps`;
  - L44 and L69-L71, with L331-L337: a timer that fired, and a late reply, send no steps.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls:277-302` `Answer`, then `Audited` at L488-L512, which writes `Record("Approval", ...)` at L507.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls:88` calls `Record`, which writes `Record("Action", ...)` at L153.
- `release/standalone-bridge.sh:787` (held, then replayed: `Forwarding the item=denied;Forwarding the item=ok`), `:857` (untrusted denials as steps) and `:933-937` (answered-approved, started, finished-done and action entries read back from `%SYS.Audit`).

**Evidence for the gaps (read-only):**
- (b) `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:75-76` (no initial value; "Empty refuses every class") and `CheckSettings` L142-L149. The example sets the list itself (`BridgeExample/Production.cls:30`).
- (c) `irislib/Ens/BusinessProcess.cls:189-196`: `SetTimer` sends an `Ens.AlarmRequest` to `Ens.Alarm`. `irislib/Ens/Director.cls:761` auto-adds `Ens.Alarm`. `Decide.cls:288` sets the bridge timer. `irislib/EnsPortal/Template/filteredViewer.cls:64` holds the caption "View Full Trace". The click path is the Planner's observation from the U-233 run.
- (d) `Decide.cls:136` `USERANSWERED` = "The outcome was changed because a message the user writes is always answered."; `Decide.cls:1222-1225` applies it to a `decide` request with provenance `user`. `BridgeExample/Triage.cls:38` sends kind `decide`.
- (e) Same as the live-read evidence above. 13.3's job check 4 proves the rows are read live.
- (g) `Approval.cls:769-813` `Reconcile` and its header L22-L31. `irislib/Ens/Director.cls:470-477` and `irislib/Ens/Alarm.cls:228-233,383-400`: a stop suspends the alarms and a start restores them. Story 11.2, Task 0 (e) measured `LiveHold(ref)` as `11` before and `11` after an in-place upgrade: the hold is kept, not re-armed (`spec-11-2-...md:616`).

## Tasks & Acceptance

**Execution:**
- `docs/security-overview.md` -- On L100, replace "In this release, changing this setting writes no OcuTalon audit entry; each tool call is still audited." with the ruled U-229 sentence (U-237's answer; Boundaries). Change nothing else -- AC 1.
- `docs/bridge-guide.md` -- (a) On L291, make the same replacement. (b) L177: set the `AgentAllowList` Default cell to "the default is empty, which refuses every class". (c) Step 6 (L99): replace "Click its header id, then open the Trace." with the real path: click the row, then the Trace tab, then View Full Trace, or click the row's Session number; the header id is not a link. Add that the trace's list also shows the bridge timer, the `Ens.AlarmRequest` that `Decide` sends to `Ens.Alarm`. (d) In "Messages and enumerations", after the enumerations, add one paragraph on the user rule: for a `decide` request whose provenance is `user`, `Decide` changes an `ignore` or `digest` outcome to `tellnow` and puts first the reason "The outcome was changed because a message the user writes is always answered."; steps 4 to 6 send the item as `untrusted`, so there an `ignore` decision goes to no output. (e) In the paragraph after the two governance blocks (L124), add one sentence: the Portal's notice that `Decide` needs an update, shown after the two rows are written, can be ignored, because the bridge reads both settings live. (g) Nothing: the guide says nothing about `Approval.Reconcile` (orchestrator ruling on Q2, decide). No marked block changes -- AC 1, AC 2.
- `docker/tests/test-bridge-guide.sh` -- Set `U229=` to the ruled sentence (one line; U-237's answer). In `u229`: keep `over-bad`; replace `guide-bad` with three break samples, each of which must be flagged: the old 13.3 sentence, the amended sentence with "writes no" changed to "writes an" (made from `$U229` with sed), and the two sentences on two lines. In `reference`: add to `PROSE_PHRASES` "the default is empty, which refuses every class", "View Full Trace", "The header id is not a link", "AlarmRequest\` to \`Ens.Alarm\`" (with its backticks) and "needs an update". Read `USERANSWERED` from `Decide.cls` with sed, and fail when it cannot be read or when the guide lacks it. Add each new item to the keep sample and give it one break sample. Update header line 16 to say what the pin holds -- AC 1, AC 2; Rule 19.

**Acceptance Criteria:**
- AC 1. Given `docs/security-overview.md`, `docs/bridge-guide.md` and `test-bridge-guide.sh`, when the story merges, then all three hold the ruled U-229 sentence (U-237's answer, Boundaries) exactly. `u229` passes, and it fails on the old sentence, on a one-word change and on a sentence split over two lines. `git diff` of the overview shows one changed line (L100). `overviewdoc` (`test-release-sequence.sh`) passes, and `live:security-overview` shows no DRIFT.
- AC 2. Given the guide, when a reader follows it, then: the `AgentAllowList` default cell says "the default is empty, which refuses every class"; step 6 gives the row, Trace tab and View Full Trace path, or the Session number, says that the header id is not a link, and names the `Ens.AlarmRequest` to `Ens.Alarm`; the reference states the user rule with `Decide`'s exact reason; and the Govern section has the one Portal-notice sentence. `reference` passes, and it fails when any one of these is removed.
- AC 3. Given the push, when CI runs, then every workflow is green, lane-a's standalone-bridge job included (no marked block changed), and `bash docker/tests/test-bridge-guide.sh` exits 0.

## Spec Change Log

- 2026-11-03, runner (lead): the plan HALTed (intent gap, U-229 clause 2). Applied the orchestrator's rulings: Q1 U-237 (provisional sentence, then replaced by the Planner's answer, option (c), 10:46:10Z#712), Q2 decide (the guide says nothing about `Reconcile`), (c) the Planner's click path as given. Status reset to `ready-for-dev`: the rest of the plan was complete and only the sentence changed.

## Review Triage Log

### 2026-11-03 - Review pass
- verdicts: 12 findings (layer reports grouped by root cause) - high 0, medium 2, low 9, false 1, maybe-false 0
- findings:
  - `[medium]` `[patch]` (verification-gap, edge-case) the user rule, the click path's Trace tab and Session number, and the Portal advice are pinned only by a generic phrase or not at all -- six phrases added to `PROSE_PHRASES` with one break sample each; two mutations run on the real guide and recorded in `## Verification`.
  - `[low]` `[patch]` (blind-hunter, verification-gap) "Steps 4 to 6 send the item as `untrusted`" is inaccurate; only step 5 sends an item -- reworded to "The item of step 5 is sent as `untrusted`" (matches the guide's Govern section) and pinned.
  - `[medium]` `[patch]` (verification-gap) mutation lines missing for the new pins -- two added; the other break samples are the script's own fixtures.
  - `[low]` `[reject]` (blind-hunter) the audit sentence omits the audit-off case and says "an approval" -- the sentence is the Planner's exact wording (U-237), never reworded; the guide's own Installer section states the auditing condition.
  - `[low]` `[reject]` (blind-hunter) the `AgentAllowList` Default cell is a sentence -- the cell wording is fixed by AC 2.
  - `[low]` `[reject]` (blind-hunter) the bridge timer is not explained, and the Portal sentence gives no action and sits mid-paragraph -- a new claim would need a veto item; AC 2 fixes the content.
  - `[low]` `[reject]` (blind-hunter, edge-case) phrase pins match anywhere in the guide, not inside one section; `u229` matches anywhere in the guide -- the existing design of `reference` and `u229`; the whole phrases now pinned are specific enough, and no stale copy of the old sentence exists in docs.
  - `[false]` `[reject]` (edge-case) an escaped quote in `USERANSWERED` would be compared doubled -- the value holds no quote today; theoretical.
  - `[low]` `[reject]` (edge-case) a call can be unrecorded without a timeout (unparseable Steps, failed send) -- logged as an IRIS-side warning, ruled wontfix-theoretical for the sentence in the spec's Design Notes.
  - `[low]` `[reject]` (edge-case) the click path rests on the Planner's observation -- ruled and used as given.
  - `[low]` `[reject]` (verification-gap) `break_ref` accepts any problem; `(g)` has no negative pin; the CI-green criterion has no mutation -- the keep sample is proven clean first; (g) is the absence of text; AC 3 is a CI outcome.
  - `[low]` `[reject]` (intent-alignment, descriptive) readings R1 to R4; the diff implements R1 plus the USERANSWERED code link and R4 "say nothing"; a live Portal check is outside the footprint.

## Design Notes

**Governing ADs (Rule 6):**
- AD-2 (the standalone path and its guide);
- AD-5 (state survives restarts; the startup reconciler, which is Q2);
- AD-8 (the timer and the late reply, which is Q1);
- AD-9 (steps from AI Hub's hooks, emitted by `Decide`);
- AD-10 (the gate; denials as steps);
- AD-11 (approvals, `Answer`, `Reconcile`);
- AD-17 (one audit writer and its types);
- AD-19 (settings homes; read live);
- AD-22 and AD-29 (the static checks);
- AD-26 (the trace session);
- AD-30 (the user rule; "answered twice or not at all").

No AC contradicts an AD's Rule. Q1 is a gap between the sentence's clause 2 and AD-8 and AD-9 as built.

**U-229 clause check (the HALT reason is clause 2):**
1. "Changing this setting writes no OcuTalon audit entry": **true**. The setting is a System Default Settings row or an item setting, written by the platform. No OcuTalon code observes the write. The only audit writer is `Audit.cls:188` through `Record`. The only `Settings` caller outside the tests is `SettingsOps.cls:106`, limited to `demo.mode` (L21). No code writes `Record("Tool"|"MCP", ...)`.
2. "Each tool call is recorded as a step of its decision": **not true as worded** (the plan HALTed on it; U-237, answered by the Planner, below). The ruled clause "Each tool call is recorded as a step of its decision unless the decision times out" is **true**: every reply that reaches `Decide` before its timer goes through `EmitSteps` first (`Decide.cls:339`, before the busy check and before any re-send weighing), whichever outcome follows. The excluded case is exactly the timeout: when the bridge timer fires, the decision ends with a fallback and no step is sent, for held and denied calls too, and a late reply is discarded (`Decide.cls:331-337`, `:44`, `:69-71`). Decided in-stage: "the decision times out" reads as "its bridge timer fires", which records FallbackReason `timeout`, or `rate_limited` once re-sends ran out (`Decide.cls:67-69`); in both the decision ran out of time. A step whose `Steps` value does not parse, or whose send fails, is a logged warning (`Decide.cls:42-43`): an IRIS-side failure, not a design path (wontfix-theoretical for the sentence). A recorded-row answer and a precheck fallback ran no runner, so no tool call exists to record.
   - What holds: every call, including a held or denied one, reaches the step buffer (`StepAudit.cls:18-39`). When the runner's reply arrives before the timer, `Decide` sends each step as an `AgentStep` (`Decide.cls:339`, `:459-530`). Live proof: `standalone-bridge.sh:787,857`.
   - What does not: when the bridge timer fires first, `OnResponse` takes the timer branch (`Decide.cls:331-337`), records the fallback and sends no step. The framework discards the late reply, and "no step is sent for it" (`Decide.cls:44`, `:69-71`). Its steps are not counted in the decision's `AgentStepCount` either.
   - It is reachable with shipped values. `timeout_ms` "bounds the tool loop (it does not stop a request in flight)" (`Timeouts.cls:7`). One Chat request can take up to 52 s for a 60 s timer (`Timeouts.cls:8-10`), so a fast first request, a tool call and a slow second request end after the timer. A request that waits in a busy runner's queue past the timer still runs its tools (`AgentRunner.cls:24-31` has no staleness check).
   - Under the orchestrator's reading ("the `AgentStep` messages Visual Trace shows"), those calls have no step. The late reply's `Steps` probably stay in the discarded runner reply in the message store (inference, unmeasured), which is not "a step of its decision".
3. "An approval writes an audit entry": **true**. `Answer` (`Approval.cls:277-302`) calls `Audited`, which writes `Record("Approval", ...)` at L507 (change `answered`; a rejection writes one too). Live: `standalone-bridge.sh:933-937`.
4. "An approved call's run writes an audit entry": **true**. `Replay.Run` (`Replay.cls:88`) calls `Record`, which writes `Record("Action", ...)` at L153 for every run that started. `StartExecution` and `FinishExecution` add Approval entries `started` and `finished`, so "an audit entry" means at least one. A refused start runs nothing and writes no Action. Live: `standalone-bridge.sh:933-937`.

**Other "this release" statements (all stay true; no edit):**
- overview L134, "a release without those features writes none of them": `Pairing` is written by `SessionOps.cls:443`, and there is no `MCP` or `Tool` writer;
- overview L156 and L178, "this release can't make/connect to MCP servers": there is no MCP code in `src` (no `Mcp` package, no `call_mcp_tool`);
- overview L200, "in a release that has them": a conditional;
- overview L206, the release check of the demo: Epic 14's text, not about audit, unchanged;
- guide L291 is the U-229 sentence itself. The guide has no other "release" statement.

**L100 is hand-written.** It lies outside the `BEGIN/END GENERATED` markers (L5-L81). `live:security-overview` compares only the generated regions, and `overviewdoc` pins only "24 hours", the audit types in backticks and the headings, so neither is touched.

**(g) Reconcile finding.**
- After a clean production stop and start, a pending hold stays live without `Reconcile`. The BP instance is persistent. A stop suspends its 24-hour alarm and a start restores it (`Director.cls:470-477`, `Alarm.cls:228-233,383-400`). The Workflow task persists. 11.2's Task 0 (e) measured the same hold id before and after an in-place upgrade. `Reconcile` skips a row that has a live hold (`Approval.cls:809`), so the original hold survived on its own.
- `Reconcile` is the only path that re-arms a hold that is gone after an abnormal end (killed jobs, a cleaned production, deleted app data; pass 2, `Approval.cls:798-811`). It is also the only path that cancels an orphaned Workflow task (pass 1), and that resends an approved `tool_call` whose replay did not start (pass 3; header L23-L24).
- A lost hold fails safe: nothing runs unapproved. It is a liveness gap: a pending row with no hold never expires by timer.
- So the AC's binary has two defensible readings (Q2). Code reading is conclusive for both cases, so no Task 0 is planned unless Q2 picks the sentence: then Task 0 checks, on a lane-B throwaway (tag `e13s4i`), that a terminal call of `Reconcile()` in `OCUBRIDGE` returns OK on a bare bridge.

**Integration ACs (Rule 1/2):** this story adds no service, module or shared component.
- **Consumed-by:** lane-a's standalone-bridge job (`release/standalone-bridge.sh`, the block-by-block guide run; no block changes), `docker/tests/test-bridge-guide.sh`, the release checklist row `bridge-guide`, and Story 31.3's link to `docs/bridge-guide.md` (the path is unchanged).
- **Consumes:** the code cited in the Code Map, read-only.

**Extend, don't copy (Rule 2):** the new pins extend `PROSE_PHRASES`, `reference_problems` and the `u229` fixtures. No new rule function is added. The `USERANSWERED` read follows `names_of`'s sed pattern.

**Ledger inbox (Rule 17):** none. DW-606 is the orchestrator's and is not touched.

**Out of scope (burn-down, filed by the runner, `owner=burndown`, "first daily release after 1.0.0"):** AgentSteps for a timed-out decision's and a late reply's tool calls, then the clause "unless the decision times out" dropped from both docs (U-237's answer); (f) runnable guide blocks that reach a held call (a `user` item that leads to a forward, reading the pending Ref, calling `Answer`); a bridge self re-arm at production start (evidence: the (g) finding above, the abnormal-end case).

**Decided in-stage:**
1. The `AgentAllowList` "What it does" cell keeps "An empty list refuses every class."; only the Default cell changes, to the AC's words.
2. The user rule goes in the reference ("Messages and enumerations", after the enumerations) and names steps 4 to 6 there. Steps 4 to 6 keep "(an `ignore` decision goes to none)", which is true for their `untrusted` item.
3. The `u229` pin keeps `grep -F` of the whole two-sentence string on one line. A split-line sample documents that requirement.
4. `type: chore` (docs and test pins).

**size_estimate hours=2** (guide prose 0.75 h, test pins and mutations 0.75 h, verification runs about 0.5 h including one 6-minute standalone-bridge run).

**Public-facing text:** items (a) to (e), and (g)'s sentence if Q2 rules it, are fixed by the ACs and U-236. No other new claim.

**Rulings (orchestrator, 2026-11-03, after the plan's HALT on d151eafb):**
- **Q1, U-237 (the orchestrator's item; never under `applied:`), answered by the Contest Planner with option (c), their own wording (inbox 2026-11-03T10:46:10Z#712), replacing the provisional wording:** the sentence in all three places is "In this release, changing this setting writes no OcuTalon audit entry. Each tool call is recorded as a step of its decision unless the decision times out, and an approval and an approved call's run each write an audit entry." The clause-by-clause evidence is above (clause 2 with the timeout case: `Decide.cls:331-337`, `:44`, `:69-71`, `Timeouts.cls:7-10`). Clause evidence unchanged: (1) `demo.mode` is the only Settings audit caller (`SettingsOps.cls:21,106`); (2) the timer path above; (3) `Approval.cls:507`; (4) `Replay.cls:153`. Burn-down (runner, at its gate, `owner=burndown`, "first daily release after 1.0.0"): record the tool calls of a timed-out decision, and of a late reply, as AgentSteps, then drop "unless the decision times out" from both docs.
- **Q2, decide:** the guide says nothing about `Approval.Reconcile`. A clean stop and start restores the hold's alarm. The abnormal-end case (killed jobs or a cleaned production: `Reconcile` is the only re-arm of a lost hold and the only resend of an approved call whose replay never started; it fails safe) is filed by the runner at its burn-down gate as the "bridge self re-arm" entry, `owner=burndown`, note "first daily release after 1.0.0", alongside (f).
- **(c):** the click path (the row, the Trace tab, View Full Trace, or the Session number; the header id is not a link) is the Planner's, from the U-233 run on a real Portal, used as given. The code confirms only the caption "View Full Trace" (`irislib/EnsPortal/Template/filteredViewer.cls:64`) and the bridge timer's `Ens.AlarmRequest` to `Ens.Alarm` (`irislib/Ens/BusinessProcess.cls:189-196`, `Decide.cls:288`).

## Verification

`<lane B>` = `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=13 stage=<stage>'`.
- `<tag>` is `e13s4` plus the stage letter (`i`, `q`, `r`).
- Every IRIS run goes to a lane-B throwaway. Slot B is untouched: there is no class change.
- Run each command in the foreground of its own call with `timeout: 600000`. Make one IRIS run per message, and tear down only your own tag, after a failure too.

**Commands:**
- `(loop)` `bash docker/tests/test-bridge-guide.sh` -- expected: `blocks`, `reference`, `u229` and `public` PASS, each after its break samples are flagged.
- `(once)` `bash docker/tests/test-release-sequence.sh` -- expected: `overviewdoc` and every other rule PASS.
- `(once)` `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-ci-config.sh` -- expected: PASS.
- `(once)` `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh live security-overview`, then `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh teardown` -- expected: PASS, no DRIFT line.
- `(once)` `<lane B> OCUTALON_RUN_TAG=<tag> bash release/standalone-bridge.sh`, then `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh teardown` -- expected: `standalone-bridge: all checks passed` (about 6 minutes; no block changed).
- `(once)` `git diff --stat` -- expected: only the three footprint files and this spec. `git diff -U0 docs/security-overview.md` shows one changed line (L100). `git diff docs/bridge-guide.md` shows no line inside a marked block.

**Pinning mutations (Rule 19; apply, observe red, revert, confirm `git status --short` and `git diff --stat` unchanged; record each as `mutation: ... -> ...`):**
- AC 1: in the overview, "writes no" becomes "writes an". Expected red: `u229` naming the Approval and audit section. Repeat in the guide: `u229` naming the guide.
  mutation: overview "writes no OcuTalon" -> "writes an OcuTalon" => u229 FAIL ("the Approval and audit section of docs/security-overview.md lacks the U-229 sentence"); same in the guide => u229 FAIL ("docs/bridge-guide.md lacks the U-229 sentence"); restored, git status and diff identical.
- AC 1: restore the old 13.3 sentence in the guide. Expected red: `u229`.
  mutation: guide ruled sentence -> "...writes no OcuTalon audit entry; each tool call is still audited." => u229 FAIL (guide lacks the sentence); restored.
- AC 2 (b): the Default cell goes back to "see below". Expected red: `reference`, naming the allow-list phrase.
  mutation: guide AgentAllowList Default "the default is empty, which refuses every class" -> "see below" => reference FAIL ("the guide lacks the prose phrase 'the default is empty, which refuses every class'"); restored.
- AC 2 (c): "View Full Trace" is removed. Expected red: `reference`.
  mutation: guide "View Full Trace" -> "the trace" => reference FAIL ("the guide lacks the prose phrase 'View Full Trace'"); restored.
- AC 2 (d): one word of the user-rule reason changes in the guide. Expected red: `reference`, naming USERANSWERED.
  mutation: guide "is always answered" -> "is answered" => reference FAIL ("the guide lacks the USERANSWERED reason of Decide"); restored.
- AC 2 (e): the Portal-notice sentence is removed. Expected red: `reference`.
  mutation: guide Portal-notice sentence removed => reference FAIL ("the guide lacks the prose phrase 'needs an update'"); restored.
- AC 2 (d, e): the user rule's outcome change and the Portal advice are pinned as whole sentences.
  mutation: guide "changes an `ignore` or `digest` outcome to `tellnow`" -> "leaves the outcome alone" => reference FAIL (lacks that prose phrase); guide "You can ignore it, because the bridge reads both settings live" -> "Restart the production" => reference FAIL; restored from backup, git status and diff identical.

**Shared surfaces:**
- the `U229` pin and its fixtures;
- `PROSE_PHRASES` and the `reference` keep sample of `test-bridge-guide.sh`;
- the hand-written Approval and audit paragraph of `docs/security-overview.md` (`overviewdoc`, `live:security-overview`). It is an input of every iris group, so this push runs every group.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** The U-237 sentence is in the overview (L100, one changed line), the guide's Classification item and the `U229=` pin. The guide closes gaps (b) to (e): the allow-list default, the click path with the header-id note and the bridge timer's `Ens.AlarmRequest` to `Ens.Alarm`, the user rule with `Decide`'s exact reason, and the Portal-notice sentence. (g): nothing about `Approval.Reconcile`. `test-bridge-guide.sh` pins each statement and flags a wrong text.

**Files changed:**
- `docs/security-overview.md`: L100's U-229 sentence only.
- `docs/bridge-guide.md`: Classification item, allow-list Default cell, step 6, the Govern paragraph, the user-rule paragraph. No marked block changed.
- `docker/tests/test-bridge-guide.sh`: `U229`, header, `PROSE_PHRASES`, the `USERANSWERED` read, keep sample and break samples, `u229` fixtures (old sentence, one word, split line, old sentence in the overview).

**Review:** 12 findings; 3 patched (pins for the user rule, Trace tab, Session number and Portal advice; "Steps 4 to 6" corrected to step 5; two mutation lines), 0 deferred, 9 rejected with reasons in the Review Triage Log. Follow-up review not recommended.

**Verification:** `test-bridge-guide.sh` all rules passed (blocks, reference, u229, public); `test-release-sequence.sh` all rules (overviewdoc PASS); `test-boundaries.sh` and `test-ci-config.sh` passed; `ci/iris.sh live security-overview` passed (no DRIFT); `release/standalone-bridge.sh` "all checks passed" (lane B, tag e13s4i, torn down). Overview diff: one hunk.

**Residual risks:** the click path rests on the Contest Planner's observation (only the caption is confirmed in code). The burn-down ledger entries (steps for a timed-out decision, runnable guide blocks that reach a held call, bridge self re-arm) are for the runner to file at its gate.
