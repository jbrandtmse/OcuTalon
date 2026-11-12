---
title: 'Story 23.9: Resume a suspended item after its incident closes'
type: 'feature'
created: '2026-11-12'
status: 'done'
baseline_revision: 'c7427fa4f23d60edc729a10b338e84acd8ae400d'
baseline_commit: 'c7427fa4f23d60edc729a10b338e84acd8ae400d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-2-suspend-resume-and-reroute-with-a-dry-run.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** A suspend that OcuTalon ran (Story 23.2) can be undone in the chat only while its incident is not closed. The incident closes on its own after 15 quiet minutes or by Break the feed's replay, often minutes after the suspend, so the user loses the governed way back. The item then stays disabled, and Checks never reports it, because `Fix.Run.Suspended` keeps it as OcuTalon's own (DW-1068).

**Approach (recommended option (b); the Planner chooses at the spec gate, see Design Notes "Option (a) vs (b)"):** An incident that holds an active suspend does not close on its own. The 15-quiet-minutes close and the replay close are refused while one of its executed `suspend_item` runs is still the item's current suspension. Only a resume, followed by the usual quiet close, or the user's own Dismiss closes it. Once a dismissed incident's suspend is no longer held, Checks reports the still-disabled item once, with the time of the suspend.

## Boundaries & Constraints

**Always:**
- IncidentManager stays the only writer of the incident (AD-15). The hold is a fact of the transition table, read from OcuTalon's own rows (`Fix.Run`), and `Transitions.cls`, its unit test and AD-15's table change together.
- A resume stays one approved request with its own dry run that re-checks before running, through the existing 23.2 path. A second session, or a user outside the incident's ownership scope, can never raise it (`Asked`, `ResolveIncident`).
- Dismiss always closes (open, noticed or resolved), and a held incident stays dismissable on the page and in the chat.
- No new public text in this plan: every user-facing sentence is already ruled (`## PUBLIC TEXT for the Planner`). A changed or new string is applied only after the Planner rules on it verbatim.
- The online demo is unchanged: suspend and resume stay refused there (`ONLINESHARED`; DW-1059's sentence), so no incident there ever holds a suspend.

**Never:**
- No new `/api/v1` route and no changed payload, table, column, catalog key, live event or message class. No web change, no grant or role change.
- No change to `Fix.Executor`, the item kinds, `Watch.Summary`'s lines, the guide or Break the feed's code.
- No automatic resume, and no reopening of a closed incident.
- Nothing under `irislib/` or `irissys/`. No edit of a done story's spec. The Planner ruled option (b), the AD-15 amendment and the PRD and UX wording on 2026-11-12 (U-321, Design Notes); the lead has written them into the spine and the planning artifacts.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Quiet close held | resolved incident I, LastAt 16 min ago; I's done `suspend_item` run changed X; no later run changed X | `closeQuiet` → `not_allowed`; I stays `resolved`, no ClosedAt, no summary, nothing sent or published | No error expected |
| Replay close held | same I; Break the feed pressed (local demo mode) | `closeForReplay` → `not_allowed`; BreakFeedIn answers `incident_in_progress` (existing path), and no batch is sent | Existing 409 and hint |
| Open, held | I `open` (a later request rejected), noticed, demo mode off, quiet | `closeQuiet` → `not_allowed` | No error expected |
| Resume, then close | resume of X on I raised, approved and done (changed X) | the hold ends; the next `closeQuiet` closes I; the summary has requestedSuspend, itemSuspended, requestedResume, itemResumed and closedQuiet | No error expected |
| Dismiss held | the user dismisses I | `closed` (summary with the suspend lines and closedDismiss); the compact card keeps the `result.itemSuspended` band | No error expected |
| Checks after Dismiss (DW-1068) | production watch of I's production; X still disabled and in the previous `ours` | next run: one `watch.itemDisabled` Item for X, `{time}` = the suspend run's EndedAt; X leaves `ours`; the next run sends none | No error expected |
| Hold moved | X resumed by another incident J, or suspended again by J | I holds nothing (J holds X after J's suspend) | No error expected |
| Run that changed nothing | I's suspend run Completed 0 | I holds nothing; closes as today | No error expected |
| Other session | session B (not a recipient of A's held I) asks to resume X | tool `no_incident` / `Asked` `not_found`; nothing raised | Existing refusal |
| Hold unreadable | the FixRun read throws during `closeQuiet` | treated as held: `not_allowed`, one Type 3 warning (LOGHOLDS) | Warning, incident kept |
| Online demo | `onlineDemo` 1 | suspend refused (`ONLINESHARED`), so no hold exists; quiet and replay closes as today | Existing refusal |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Watch/Transitions.cls` -- the table. Header rows 8-22 (row 20 "resolved + dismiss, closeForReplay or closeQuiet -> closed", row 21 "open, noticed + dismiss -> closed; open, noticed + closeQuiet -> closed only when demoMode is 0"); facts doc 4-5. `Next` reads facts at 79-90 (`demo` at 86). The open-noticed branch is at 99-107, with closeQuiet at 102; the resolved branch at 133-138, with the closes at 136.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- `Facts` 1478-1501 (doc 1478-1481; `demoMode` read only for closeQuiet, 1500), the seam `DemoMode` 1512-1516 (the sibling for a new seam `Holds`), `Apply` 1436-1452, `Command` 1569-1595 (closeQuiet's quiet check 1585; refused -> `not_allowed` 1593), `Closing` 1458-1476 (summary on close). Class description: the IncidentCommand bullet 77-82 and the summary bullet 120-124. LOG parameters 226-293.
- `src/ocutalon/cls/OcuTalon/Fix/Run.cls` -- `Suspended(namespace, production, since, .fresh)` 59-101 (description 28-32). Its SELECT joins FixRun, ApprovalRequest and Incident (74), and the newest changing item-kind run per item decides (92-98). Extend it, don't copy.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- `Run` 546-604: `Fix.Run.Suspended` at 591, `Findings` at 592, and `FindingItem(row, KEYDISABLED, TEXTDISABLED, {"itemName"}, runAt)` at 599, whose time parameter already exists. `Findings` 631-696 (rule doc 631-640; `wasOurs` 670-676; per-name rule 683-691). The class description's Findings bullet is at 49-60. The quiet sweep `Sweep`/`Quiet` 448-488 sends closeQuiet to every non-closed quiet incident and ignores the answer.
- `src/ocutalon/cls/OcuTalon/Demo/BreakFeedIn.cls:94-113` -- the consumer of closeForReplay: a refusal answers `incident_in_progress` (110). No change. `Web/Api.cls:533` turns it into a 409, and `web/src/app/feed/break-feed-view.ts:26` shows the hint.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls:115-118` -- the finish (P24) counts `resolved`, so a held incident keeps the finish. No change.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls:248-258` (`IncidentLines`) shows a held incident's "resolved" line on each beat. `Checks/Process.cls:715-723` (`Unclosed`) and `Digest/NeedsYou.cls:53` do not count `resolved`. No change.
- Read-only: `Tools/WatchTools.cls:101` `FIXABLE` "open,resolved" (a held incident stays askable); `Tools/WatchAnswers.cls:112-149` `ResolveIncident`; `IncidentManager.Asked` 1063-1118 (recipients check 1069-1077; `already_asked` 1096-1100).
- Tests: `Test/Watch/Transitions.cls` (pure; `Rows` 100-127, `Holds` condition tokens), `Test/Watch/Lifecycle.cls` (`TestCloseForReplay` 207-226, `TestCloseQuiet` 228-281, host `..Incident`/`..Command`/`..Snapshot`), `Test/Watch/IncidentProbe.cls` (`DemoModeIs` 49 and `DemoMode` 255-260, the pattern for `HoldsIs`), `Test/Checks/Runs.cls` (`TestSuspendedByOcuTalonIsNotReported` 553-591 uses a CLOSED incident; the helper `Done` 594-599), `Test/Fix/Asked.cls` (`TestSuspendAndUndo` 97-140), `Test/Data/Fixture.cls` (`Incident` 116, `Approval` 137, `FixRun` 155, which sets EndedAt).

## Tasks & Acceptance

**Gate (met 2026-11-12, U-321):** the Planner ruled option (b), approved the AD-15 amendment and the PRD and UX wording as drafted, and P3; the lead wrote them into the spine and the planning artifacts and re-ran the pre-warm. Implement starts after Story 23.11 merges.

**Execution:**
- `src/ocutalon/cls/OcuTalon/Fix/Run.cls` -- extend `Suspended` with two outputs.
  - `holders`: a %DynamicObject from item to the IncidentRef of the run that suspended it.
  - `released`: a %DynamicObject from item to that run's EndedAt, for an item whose current suspension (its newest changing item-kind run is a `suspend_item`) is a run of a closed incident. Such an item leaves `names` and `fresh`.
  - Add `r.IncidentRef` and `i.State` to the SELECT.
  - Add `ClassMethod Holds(incident As OcuTalon.Data.Incident) As %Boolean`: 1 when `holders` names the incident for any item of its namespace and production.
  - Update the class description: the hold, and released.
- `src/ocutalon/cls/OcuTalon/Watch/Transitions.cls` -- add the fact `holds`.
  - `resolved` + closeQuiet or closeForReplay goes to `closed` only when holds is 0.
  - `open`, noticed + closeQuiet goes to `closed` only when demoMode is 0 and holds is 0.
  - Dismiss is unchanged.
  - Update header rows 20-21 and the facts doc.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- `Facts` reads `holds` only for closeQuiet and closeForReplay, through a new private method `Holds(incident)` placed next to `DemoMode`.
  - `Holds` wraps the new seam `ReadHolds(incident)` (which calls `Fix.Run.Holds`) in a Try. An exception counts as held and logs one Type 3 warning (new `LOGHOLDS` "IncidentManager could not read the suspends of incident ").
  - Update the Facts doc and the class description's IncidentCommand bullet.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- `Run` passes `Suspended`'s `released` to `Findings` (a new last argument, default "").
  - In `Findings`, a disabled name that `suspended` does not list, that is in the previous `ours`, and that `released` lists gives `{"kind": "disabled", "item", "at": <released time>}`, and it is not kept in `ours`. Every other name follows today's rule.
  - `Run` passes `one.at`, when present, as the Item's time.
  - Update the Findings doc and the class description bullet (49-60).
- `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls` -- add a `HoldsIs` property and a `ReadHolds` override, as `DemoModeIs`/`DemoMode` do: it gives `HoldsIs` when set, and otherwise `##super()`. Add a `FailHolds` flag that makes `ReadHolds` throw, so that the product's catch in `Holds` runs.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Transitions.cls` -- add the condition tokens `h0`/`h1`, and iterate holds in `TestRows` and `TestRefusedMoves`.
  - The resolved close rows (closeQuiet, closeForReplay) carry `h0`; resolved + dismiss carries none; open-noticed closeQuiet carries `d0 h0`.
  - Update the class description.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls` -- add a new `TestHeldBySuspend` with real rows (`Test.Data.Fixture` Approval and FixRun, done `suspend_item`, Completed 1).
  - closeQuiet on a quiet resolved incident and on an open noticed incident (demo off), and closeForReplay, each answer `not_allowed` with nothing changed (`..Snapshot`).
  - A done `resume_item` run that changed the item releases the hold, and closeQuiet then closes it. The stored Summary's parts include `summary.itemSuspended`, `summary.itemResumed` and `summary.closedQuiet`. The two requests' Refs go in the incident's RequestRefs, which the summary reads; `Fix.Run` reads FixRun.IncidentRef.
  - Dismiss closes a held incident.
  - A run with Completed 0 holds nothing. A later suspend by another incident moves the hold.
  - With `FailHolds`: `not_allowed` and one warning.
  - Register every ref for cleanup.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- `TestSuspendedByOcuTalonIsNotReported`: the incident becomes `resolved` (a closed incident's suspend is now released), and its assertions are otherwise kept.
  - Add `TestDismissedSuspendIsReportedOnce`: suspend sighted, then the incident closed → one Item for A with `time` = the run's EndedAt, `Reported` without A in `ours`; the next run sends none.
  - Add pure `Findings` cases for `released`.
  - Add `Suspended` cases for `holders`/`released`.
- `src/ocutalon/cls/OcuTalon/Test/Fix/Asked.cls` -- add `TestHeldIncidentResumeIsTheSessions`: on a resolved incident holding a suspend, the owner's resume ask is `raised` (one request with its dry run). A non-recipient session's ask is `not_found`, with nothing raised and no dry run asked.

- [ ] [Ruling U-321, P3] `src/ocutalon/cls/OcuTalon/Agent/Chat.cls:65` -- replace the second sentence ("To undo a suspend while its incident is open, call it with resume_item and the same item.") with, verbatim: "To undo a suspend while its incident is open, call it with resume_item and the same item; if the answer is no_incident, say that the incident is closed and that the item can be enabled again on the production's configuration page in the Management Portal." Update its instruction pins in `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls` (find them by the line's text; add a pin for the new clause if none covers it). A footprint extension (uncontended).
- [ ] [Ruling U-321, conditions] `Test.Watch.Transitions` covers every split AD-15 row (`resolved` and `open`, noticed: `dismiss`; `closeQuiet` and `closeForReplay` with and without a held suspend) and each refused move (`closeQuiet` / `closeForReplay` while held). One test or an existing pin proves the online demo unchanged (suspend and resume refused there, so no incident holds a suspend). `dismiss` always closes, held or not (a pin).

**Acceptance Criteria:**
- AC1: Given a resolved incident whose executed suspend still holds an item, when Checks' quiet sweep sends closeQuiet after 15 quiet minutes or Break the feed sends closeForReplay, then IncidentManager answers `not_allowed`, and the incident stays `resolved` with no ClosedAt, no summary and nothing sent (`Test.Watch.Lifecycle:TestHeldBySuspend`; `Test.Watch.Transitions`).
- AC2: Given an open, noticed incident that holds a suspend, with demo mode off, when closeQuiet arrives, then it is refused. Dismiss still closes any held incident (`TestHeldBySuspend`, `Test.Watch.Transitions`).
- AC3: Given a held incident, when the user asks to resume the item and the approved resume changes it, then exactly one resume request with its own dry run was raised and re-checked (23.2's path). The hold ends, and the next quiet close closes the incident with a summary that lists the suspend and resume lines (`Test.Fix.Asked:TestHeldIncidentResumeIsTheSessions`, `TestHeldBySuspend`, `Test.Watch.Summary` unchanged and green).
- AC4: Given a session that is not a recipient of a held incident, when it asks to resume the item, then nothing is raised (`not_found` at `Asked`; `no_incident` at the tool, through the ownership API) (`TestHeldIncidentResumeIsTheSessions`; existing `Test.Fix.AskedTurns` RP5, `Test.Core.CommandsRouting` RP2).
- AC5 (Integration, DW-1068 second half): Given a production watch and an item suspended by OcuTalon whose incident the user dismissed, when Checks next runs, then it sends exactly one `watch.itemDisabled` Item for the item, with `{time}` the suspend's end. A later run sends none, and an item that a resume enabled sends none (`Test.Checks.Runs:TestDismissedSuspendIsReportedOnce`).
- AC6 (Integration): Given real FixRun and ApprovalRequest rows (no `HoldsIs`), when closeQuiet reaches IncidentManager, then `Fix.Run.Holds` decides the answer. A later suspend of the item by another incident moves the hold to that incident, and a suspend run that changed nothing holds nothing (`TestHeldBySuspend`).
- AC7: Given the holds read fails, when closeQuiet arrives, then the incident stays and one Type 3 warning is logged (`TestHeldBySuspend`).
- DW-1068: After a suspend's incident closes, the user can't ask to resume the item, while `result.itemSuspended` says to, and Checks never reports the item as disabled. Covered as follows: the quiet and replay closes no longer end a held incident (AC1, AC2); the resume stays askable until the user's own Dismiss (AC3); the band's ruled text stays true; and Checks reports the item after that Dismiss (AC5).
- AC8: Given the online demo, when its suites run, then nothing changes: suspend and resume are refused (`Test.Fix.ItemKinds` `ONLINESHARED`), and Break the feed and the quiet close pass their existing tests (`Test.Demo.BreakFeedIn`, `TestCloseQuiet`, `TestCloseForReplay`).

### Review Findings

Code review 2026-11-12 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; full-opus). 22 raw rows, 5 entries after grouping (high 0, med 2, low 3), 15 rows rejected. Checked against U-321 and the amended AD-15: the two split rows, the hold bullet, Dismiss always closing, P3 verbatim and P1/P2 absent all match; no AD mismatch.

- [x] [Review][Decision] P3 says "the incident is closed" for every `no_incident`, but `resume_item` also gets `no_incident` while the session's incident is `awaiting_approval` or `fixing` — `Tools/WatchAnswers.cls:131` answers `no_incident` with the busy incident in `others` (the second resume ask of `Test.Fix.AskedTurns:TestUndoTurn`), so the model would tell the user a waiting incident is closed and send them to the Portal. The sentence is ruled verbatim (U-321), so the reviewer may not change it: med, fix-risk low, in-story (P3 footprint extension), `decision-pending` owner=burndown as DW-1186 for a Planner text call (e.g. "if the answer is no_incident and others is empty, ..."). [src/ocutalon/cls/OcuTalon/Agent/Chat.cls:65]
- [x] [Review][Patch] AC5's "an item that a resume enabled sends none" could not fail in `TestDismissedSuspendIsReportedOnce` (B is never in the stub's disabled list, so `Findings` never looks at it). Added an assertion that `Suspended`'s `released` is exactly `{"A": ended}` after the dismissal, and dropped the count label's B claim; mutation recorded in `## Verification`. med, fix-risk low, in-story. [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls:682]
- [x] [Review][Patch] The class descriptions of `Watch.Transitions` and `Watch.IncidentManager` defined the hold as "an item that one of its requests suspended is still suspended", looser than AD-15 and `Fix.Run` (the newest item-kind run that changed the item is a `suspend_item` of the incident; a later suspend by another incident moves it). Reworded to the AD-15 definition. low, fix-risk low. [src/ocutalon/cls/OcuTalon/Watch/Transitions.cls:5; src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:82]
- [x] [Review][Patch] The pin "closeForReplay of an open incident is refused whether it holds a suspend or not" passed only `holds` 0. Relabelled, and added the `holds` 1 pin. low, fix-risk low. [src/ocutalon/cls/OcuTalon/Test/Watch/Transitions.cls:91]
- [x] [Review][Patch] "Holds ... 0 for an incident of another production" used an incident with no runs, which is 0 whatever the production filter does (the filter is pinned by `TestSuspendedByOcuTalonIsNotReported`'s "nothing for another production" on the shared SELECT). Relabelled to what it checks. low, fix-risk low. [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls:613]

Rejected:
- `low` Blind 2 + Edge 1: a held item enabled by hand, disabled again (reported then at the run time) and then dismissed is reported a second time at the older suspend time - needs known limit 4's manual enable plus a manual re-disable before the Dismiss; the fix needs new per-item state in Reported.
- `low` Blind 3: the planned mutation list (AC1/AC2 test names, "AC8: none") disagrees with the run list - the recorded `mutation:` lines are accurate; the fix edits the spec's plan text.
- `false` Blind 5c + Auditor 5: the last `TestRefusedMoves` pin cites the online demo with `demoMode` 1 - it pins that demo mode with no hold still closes, which is the online demo's case; the ruling's condition rests on `Test.Fix.ItemKinds` `ONLINESHARED`.
- `low` Blind 6 + Auditor 3: AC5's test closes the incident by saving `State` instead of a real `dismiss` - the spec's task says "the incident closed"; `Suspended` reads only the stored state, and dismiss to closed is pinned by `TestHeldBySuspend`; a driver needs a second host fixture.
- `low` Blind 7: the Review Triage Log double-counts Intent 7/8 and has "Gap 3a" alone - bookkeeping of the implement pass; the fix edits the spec.
- `low` Edge 2: a released item whose suspend run has no EndedAt is never reported - already rejected (Blind 4 of the implement review): a done run with Completed above 0 has EndedAt.
- `low` Edge 3: a retention purge of a closed incident's newer run lets an older run decide the holder again - it needs a purge that removes a newer run of an item while an older run of it survives, and the item still disabled; the fix needs a tombstone.
- `low` Edge 5: a suspend and Dismiss inside one check interval are reported at the run time, not the suspend's - the spec's rule ("in the previous ours"); it is still reported once.
- `low` Edge 6: a failing holds read warns on every quiet sweep - spec-bound (matrix row "Hold unreadable", Decided in-stage 2).
- `low` Gap (hermeticity): `Zz.Holders`/`Zz.Dismissed` are fixed names with exact-JSON assertions - each test creates and cleans its own rows (`Fixture.Clean`), as the class's other tests do; only a killed earlier run on a reused stack would leave rows.
- `low` Auditor 1: AD-15's bullet names only `closeQuiet` after a resume, while its table also lets `closeForReplay` close once nothing is held - the code follows the table; the wording is the spine's (lead, Rule 20).
- `false` Auditor 2: `Holds` matches `FixRun.IncidentRef`, not the incident's `RequestRefs` - a FixRun is written with its own request's incident, so the two cannot differ.
- `low` Auditor 4: the "Replay close held" row is not driven through BreakFeedIn - already rejected (Intent 1); BreakFeedIn is unchanged and `TestCloseRefused` pins its refusal path.

## Spec Change Log

- 2026-11-12 (lead, U-321 at=2026-11-12T04:43:08Z#985): Contest Planner ruled option (b) under the owner's delegation. Written verbatim under Design Notes. Applied: AD-15 (two split close rows + the bullet "An incident that holds a suspend") in the spine; PRD FR-24 (three bullets) and FR-16 (Break the feed); EXPERIENCE.md:698 and :1210, each with `[AMENDED 2026-11-12, Story 23.9, Contest Planner ruling U-321 under the owner's delegation]`. P1 and P2 declined; P3 added as a task; the conditions added as a task; known limit 4 accepted.

## Review Triage Log

### 2026-11-12 - Review pass
- verdicts: 24 rows (a row groups findings that share a root cause) - high 0, medium 1, low 19, false 4, maybe-false 0
- findings:
  - `[low]` `reject` Blind 1: the P3 sentence says "closed" for every `no_incident` answer - the sentence is the Planner's ruled text (U-321, verbatim); a fix would edit ruled text.
  - `[low]` `reject` Blind 2 (and Edge 4, Intent 7): the hold is read from OcuTalon's rows, so an enable by hand in the Portal keeps the incident held until Dismiss - ruled known limit 4, accepted in U-321.
  - `[low]` `reject` Blind 3 (and Intent 8): on the first run after the upgrade an item in the previous `ours` whose incident is closed is reported once - this is the DW-1068 behaviour the story is for; no baseline wanted.
  - `[low]` `reject` Blind 4 and Edge 1: a released item whose suspend run has an empty EndedAt is never reported - a done run with Completed above 0 has EndedAt (Interrupt sets it for a cut run); not reachable in everyday use and the fix adds a guard.
  - `[low]` `reject` Blind 5 and Edge 2: an unreadable holds read warns on every attempt and also blocks closeForReplay and demo-mode closes - the spec rules a read failure as held with a Type 3 warning (Decided in-stage 2; matrix row "Hold unreadable").
  - `[low]` `reject` Blind 6: Facts runs the holds query for incidents the table refuses anyway - spec-bound (Decided in-stage 2 reads holds for the two verbs); a state guard adds a branch for a cheap indexed read.
  - `[false]` `reject` Blind 7: the last assertion of `TestDismissedSuspendIsReportedOnce` is cumulative - the count staying at 1 after the second run is exactly "sends none"; the mutation run on `one.at` and on `released` shows the test discriminates.
  - `[false]` `reject` Blind 8: the spec's `Status: ready-for-dev` under Auto Run Result - rewritten at finalize.
  - `[low]` `reject` Blind 9: some behaviours have no recorded mutation (released item leaving names/fresh, ours) - they are asserted in `TestSuspendedHoldersAndReleased` and `TestReleasedFindings`; Rule 19 is one mutation per AC, and AC5 and AC6 have theirs.
  - `[low]` `reject` Edge 3: Break the feed can close earlier resolved incidents and then be refused by a held one - refusals by awaiting or open incidents already behaved so before this story, and the spec forbids a change to Break the feed's code.
  - `[low]` `reject` Edge 5: a released item that is not in the previous `ours` is reported with the run time - the spec's Findings rule says "in the previous ours"; nothing else was sighted, so the plain rule applies.
  - `[medium]` `patch` Gap 1: the holds-read restriction to closeQuiet and closeForReplay was not pinned - mutating `closing` to 1 kept every test green. Patched: `TestHeldBySuspend` asserts that the dismiss under `FailHolds` logs no second warning; mutation demonstrated red, reverted (tree byte-identical), recorded in `## Verification`.
  - `[false]` `reject` Gap 2: `Holds` scoping to the production is not pinned - the production filter is in the SELECT that `names` and `holders` share, and `TestSuspendedByOcuTalonIsNotReported`'s "nothing for another production" pins it; a `Holds` that passed the wrong production would return 0 for every held incident and fail `TestHeldBySuspend`.
  - `[low]` `patch` Gap 3a: AC2 dismiss half, AC6 "changed nothing" half and AC8 had no recorded mutation. Patched: three mutations applied, observed red, reverted, recorded in `## Verification`.
  - `[low]` `reject` Gap 4: `HoldsIs 0` in the last `TestHeldBySuspend` case cannot detect an override that ignores it - the `HoldsIs 1` case exercises the seam, which mirrors `DemoModeIs`; low and the fix adds fixtures.
  - `[low]` `reject` Gap 5 and 6 (seam with one consumer; `If '$IsObject(host) Quit`): the seam mirrors `DemoModeIs`, and the host helpers assert the host exists.
  - `[false]` `reject` Gap 7 (hermeticity): none found; Gap notes only.
  - `[low]` `reject` Intent 1: the close triggers (`Sweep`, `BreakFeedIn`) are not driven against a held incident - the matrix row "Replay close held" is `incident_in_progress` through existing code, and `Test.Demo.BreakFeedIn` stays green; a driver test would need a second host fixture for a path with no change.
  - `[low]` `reject` Intent 2: callers keep their handling of `not_allowed`; the intent forbids changing Break the feed.
  - `[low]` `reject` Intent 3 and 4: Dismiss and the chat undo are tested at the manager, table and `Asked` levels - the ownership API and the page route are unchanged and covered by `Test.Core.CommandsRouting` and `Test.Fix.AskedTurns` (both green).
  - `[low]` `reject` Intent 5: the Checks finding is end-to-end only through a stubbed reader - matches the AC5 test design (the real reader is the 22.x suites' subject).
  - `[low]` `reject` Intent 6: the new chat sentence - it is P3, ruled verbatim in U-321.
  - `[low]` `reject` Intent 7: see Blind 2.
  - `[low]` `reject` Intent 8: see Blind 3.

## Design Notes

**Contest Planner ruling U-321 (owner's delegation, 2026-11-12 ~04:43Z; binding, verbatim):**
> # Story 23.9 ruling: inbox U-321 answer (Contest Planner, owner's delegation) — VERBATIM, binding
> 
> RULING U-321 (Story 23.9, DW-1068): OPTION (b). An incident that holds an active suspend is not closed by the 15-quiet-minutes close or the replay close; it closes only on Dismiss, or by the usual quiet close once a resume has ended the hold. Reasons: about 3 h, Lane A only, no web change, no changed ruled text in judging week; K1 result.itemSuspended and K2 README:70 stay true; (a) can be layered on later if wanted. AD-15 AMENDMENT APPROVED as drafted in the spec (the two split rows and the new bullet 'An incident that holds a suspend', dated 2026-11-12, Contest Planner ruling under the owner's delegation, re-architecture under U7). ASK-FIRST AMENDMENTS APPROVED verbatim as drafted: PRD FR-24 (three state bullets), FR-16 (Break the feed sentence), EXPERIENCE.md:698 and :1210. OPTIONAL TEXT: P1 NO (K1 already true; avoids Lane B catalog regen and 8 pins). P2 NO (README is being restructured by 0.30; K2 stays true). P3 YES, verbatim, as Agent/Chat.cls:65's second sentence with its instruction pins in Test/Agent/Instructions.cls; it settles K3's awaiting wording. Known limit 4 (an enable by hand in the Portal keeps the incident held until Dismiss; a resume ask gets the existing already-enabled answer) ACCEPTED. Conditions: AC1-AC5 as specced; Test.Watch.Transitions covers every split row and each refused move; the online demo stays unchanged (suspend and resume refused there), and a test or existing pin proves it; Dismiss always closes. Timing: not before 23.11 merges; it goes in 1.0.8 only if green on feature by the Thursday-afternoon PST cut, otherwise 1.0.9. These rulings don't limit dispatch.

**The binding rulings (verbatim, `prompts/epic-23-rulings-232.md`).** Item 2 (2026-11-10 ~06:40Z) was option (a), with conditions (i)/(ii). The DW-1068 RE-RULING (~07:20Z) replaced it with (c) for 23.2. Its follow-up paragraph reads:

> "Follow-up: file DW-1068 as a PARKED story, "resume after close". Its spec chooses between (a) a resume on a closed incident and (b) an incident with an active suspend stays open until resume or Dismiss (the Planner leans to (b)). Parked until after voting; not for 1.0.6 or 1.0.7."

The story was un-parked on 2026-11-11 (epics.md 7971). Standing: suspend and resume stay refused on the online demo (ONLINESHARED; DW-1059's text).

**Architecture decisions:**
- AD-15: the table, a single writer, the summary on close.
- AD-16: kinds and row-only execution; unchanged.
- AD-4: ownership of the resume ask; unchanged.
- AD-1: the ProposeFix path; unchanged.
- AD-18/AD-28: Checks findings and the quiet sweep.
- AD-32: catalog keys; none new.
- AD-29/AD-33: lanes. Every changed file is Lane A's, and there is no cross-lane file.

**Option (a) vs (b)**

*(a) A resume raised on a CLOSED incident.* `resume_item` would answer on a closed incident only when (i) the item is disabled now, and (ii) the newest changing item-kind run of the item in that production is a `suspend_item` of an incident the caller sees under the same scope (`Data.Ownership`). A foreign enable-then-disable after OcuTalon's suspend is invisible to OcuTalon's own rows (inference: only Checks' `ours` sees it, and only with a watch on the production). It would have one approval with its dry run, a re-check before running, and no state move.
- Server work:
  - `WatchTools.ProposeFix`: a `resume_item` fallback to the closed incident that holds the item.
  - `IncidentManager.Asked`: accept closed incidents for that case.
  - `Moves`/`Event`/`Aside`/`Closed`: a request raised after `ClosedAt` must be executed on approval, told on rejection or expiry and told its result, all without a move. Today `Closed` (1728-1751) refuses to carry anything out, by 23.5's design.
  - `Watch.Summary`: the summary already stored at close would be **updated**, rebuilt in the save that records the raise and the result, with the original closing line. No second summary notification would be sent, so Show details and `incident_summary` show the requested and resumed lines.
  - `Fix.Run`: a scoped "newest disable is ours" helper.
  - Purge: a pending request on a closed incident that is purged would lose its result. A guard is needed.
- Web (Lane B, AD-33 cross-lane):
  - `incident-card.ts:306-307` drops every request card of a compact (closed) card, so a pending resume could be answered only on Telegram or the Simulated phone (`phone-view.ts:166`). The status rail can't answer it (`status-rail.ts:291-294`).
  - (a) therefore needs the compact card to show request cards raised after the close, and `incident-view.ts:446-474` plus its pins changed: `incident-view.test.mjs:226,652`, `approval-sources.test.mjs:287` and `incident-sources.test.mjs:199`.
- Public text: `result.itemSuspended`, README.md:70 and Chat.cls:65 drop the "while open" limit (candidates a1-a3). The web catalog is regenerated (`web/src/app/msg/catalog.ts`, Lane B). About 8 test pins change: `Test/Msg/Catalog.cls:1692`, `Test/Fix/ItemKinds.cls:227`, `incident-view.test.mjs:704,711`, `ux-strings.test.mjs:864`, `catalog.test.mjs:223`, `approval-view.test.mjs:123` and `approval-card.spec.ts:433`. EXPERIENCE.md:698's Closed row gains Approve/Reject (a4).
- Effect: it removes the gap after any close, Dismiss included, which fully meets FR-26 "Suspend can be undone by resume".
- PRD and UX: no PRD bullet contradicts it. EXPERIENCE.md:698 changes.
- AD-15: a bullet "a resume raised after the close never moves the incident". It reverses "anything on a closed incident is refused" for that request.
- Guide finish: unchanged. A closed incident with no variant stays finished (Guide.cls:115-118).
- Demo: unchanged (refused).
- Checks half: the same `released` change as in (b), released at any close. Under (a), the quiet close is unattended, so the finding is more useful.

*(b) An incident that holds a suspend stays open until a resume or a Dismiss.* (Recommended, planned above.)
- Transitions: resolved + closeQuiet/closeForReplay and open-noticed + closeQuiet are refused while `holds`. Dismiss is unchanged.
- Dismiss of a held incident closes it with the item still disabled, so (b) alone does not remove the gap after a Dismiss. What the user sees then:
  - the compact card keeps the request's `result.itemSuspended` band (`bandsOf`, incident-view.ts:422-431), whose ruled text already says "After the incident closes, enable {item} again on the production's configuration page in the Management Portal";
  - the summary (written at the Dismiss) lists the suspend;
  - a resume ask answers `no_incident`, unless another open or resolved incident of the session matches;
  - Checks then reports the item once (AC5).
- Guide finish (P24): unchanged, since `resolved` counts (Guide.cls:115-118). On a local demo-mode install, Break the feed answers 409 with the existing hint "Finish the current Orders incident first: approve or reject its fix, or dismiss the incident." until a resume or a Dismiss (BreakFeedIn.cls:110; break-feed-view.ts:26). The guide's availability ignores `resolved` (Guide.cls:8-9), so the button stays active and each press shows the hint.
- A long-open incident in other views:
  - the heartbeat lists it as resolved on each beat (Beat.cls:248-258);
  - the digest (NeedsYou.cls:53) and check_status (`Unclosed`, Process.cls:715-723) don't count resolved;
  - the quiet sweep sends it a refused closeQuiet every minute (no log line), as it already does for awaiting and fixing incidents;
  - same-cause failures join it as later requests (AD-15 P27) instead of opening a new incident.
- Summary timing: written at the real close. After a resume, that is the next quiet sweep, usually within a minute of the resume's end, since LastAt is long past. The summary then includes the suspend and resume lines. After a Dismiss, it is written at the Dismiss.
- PRD and UX: (b) contradicts PRD FR-24's state bullets 4-6 and FR-16's Break the feed bullet ("it first closes that incident"), and EXPERIENCE.md:698 and :1210. These are ask-first amendments (Rule 5), worded below.
- Demo: unchanged (no hold can arise).
- Checks half: in scope (AC5).

*Cost estimate (implement + QA + review, one pass).*

| | (a) | (b) |
|---|---|---|
| Hours | about 6 h (5-7 h) | about 3 h (2.5-3.5 h) |
| Files | about 25, with 8 web files (Lane B) | 9, all Lane A, no web |
| Lines | about +700 | about +300 |
| New paths | four new IncidentManager paths and a summary rebuild | — |
| Public text | 3-4 changed ruled strings | none |
| Lane B | regenerated web catalog | — |

Basis: 23.10 (13 files, +118/-42) took 2 h 33 min to implement and 28 min for QA and review. 23.7 (43 files, +2280) took 63 min to implement and 31 min for QA and review, then a CI rework of 32 min. The first estimate for (a), about 5 h in 23.2's rework, did not include the web closed-card change, which the plan found (incident-card.ts:306-307). The Checks half is about 45 min of either figure.

*Recommendation: (b).* Reasons:
- It is half the cost and touches only Lane A, with no web change and no AD-33 exception.
- It keeps AD-15's invariant that nothing happens on a closed incident, and the one summary write.
- It needs no new or changed public text: the ruled band, README sentence and agent line stay true.
- It follows the Planner's lean.

Its honest cost: after a user's own Dismiss, the way back is the Management Portal, not a governed resume, so FR-26's "suspend can be undone by resume" holds only until the user dismisses. If the Planner wants that case governed too, (a) is the delta below. It can be added on top of (b) later, because the two don't conflict.

*Deltas if the Planner picks (a)* (replacing the (b) tasks other than the Checks half):
- `Tools/WatchTools.cls`: a resume_item fallback to the closed holding incident.
- `IncidentManager` `Asked`/`Moves`/`Event`/`Aside`/`Closed`: run, answer and tell requests raised after `ClosedAt` without a move.
- `Fix.Run`: a scoped newest-disable helper (`holders` already gives the incident).
- `Watch/Summary.cls`: rebuild on those moves.
- Web: `incident-card.ts`, `incident-view.ts` and 4 web test files, plus regenerating `msg/catalog.ts`.
- Text: a1-a4 applied after the ruling.
- Tests: `Test.Fix.Asked` and `Lifecycle` (closed-incident resume: approve executes and the incident stays closed; reject, expire and the result are told; second session), `Test.Watch.Summary` (rebuilt summary), web units, and an e2e for the compact card's request card. No route changes.

**AD-15 amendment (proposed; the lead writes it after the ruling, Rule 20).** In the table, the row `resolved | closeQuiet, dismiss or closeForReplay | closed` becomes two rows:
- `resolved | dismiss; closeQuiet or closeForReplay while it holds no suspend | closed`
- `open, noticed | dismiss; closeQuiet only with demo mode off and while it holds no suspend | closed`

New bullet: "**An incident that holds a suspend** [ADDED 2026-11-12, Story 23.9, Contest Planner ruling; the lead sets the ruling's date]. An incident holds a suspend while an item's newest item-kind run that changed it, in that production, is a `suspend_item` run of one of its requests (`Fix.Run`). It is closed only by `dismiss`, or by `closeQuiet` once a resume has ended the hold. After a held incident is dismissed, `Checks` reports the item once as disabled, at the suspend's time."

**This is a re-architecture under U7.** Criterion (b): it narrows the Rule's "resolved + closeQuiet or closeForReplay -> closed". Criterion (c): AD-15 is cited by 60 `done` specs. Option (a) is one too, since it reverses "anything on a closed incident is refused". Either option is the Planner's call under the owner's delegation, as 23.2's and 23.5's AD-15 additions were.

**PRD and UX amendments for (b) (ask-first, Rule 5; verbatim proposals; the lead applies them with `[AMENDED 2026-11-12, Story 23.9, Contest Planner ruling]` (the lead sets the ruling's date)):**
- PRD FR-24, bullet "a resolved incident is closed when ...": append "; while an item that OcuTalon suspended for it is still suspended, it closes only when the user dismisses it, or after the same 15 quiet minutes once the item is resumed".
- FR-24, the open-incident bullet: after "outside demo mode also after the same 15 quiet minutes" insert ", unless an item that OcuTalon suspended for it is still suspended".
- FR-24, the demo bullet: append ", unless an item that OcuTalon suspended for it is still suspended".
- FR-16, Break the feed: append to "If the session's Orders incident is resolved ... (FR-24)." the sentence "A resolved incident that still holds an item OcuTalon suspended is not closed; Break the feed then shows its hint."
- EXPERIENCE.md:698, Closed row: after "or by the replay rule `[ASSUMPTION: 15 minutes]`" insert "(while an item that OcuTalon suspended for it is still suspended, only by Dismiss)".
- EXPERIENCE.md:1210: append " (an incident that still holds a suspend closes only by Dismiss, or after the item is resumed)".

**Decided in-stage:**
1. The replay close is held too, so a new batch can't run while an Orders item is suspended. The existing hint covers it.
2. `holds` is read only for closeQuiet and closeForReplay, like `demoMode`. A read failure counts as held, which is the safe side.
3. The hold follows the item's newest changing run across the production's incidents, so a resume through another incident releases it.
4. Known limit: an enable by hand in the Management Portal is invisible to OcuTalon's rows. The incident then stays held until Dismiss, and a resume ask is refused with the existing "{item} is already enabled". This is accepted: IncidentManager reads OcuTalon's rows, not the production, and a live read is out of this story's scope.
5. The Checks finding reuses `watch.itemDisabled` with the suspend's EndedAt as `{time}`, which is the true disable time, so no new key is needed.
6. The Checks quiet sweep is not filtered, because the table is the one authority. This matches today's refused closeQuiet for awaiting and fixing incidents.

**Extend, don't copy.**
- `Fix.Run.Suspended` gains outputs and `Holds` wraps it; there is no second query.
- The `ReadHolds` seam mirrors `DemoMode`, `HoldsIs` mirrors `DemoModeIs`, and `Findings` gains one argument.
- The Lifecycle test reuses `Test.Data.Fixture`, as `Test.Checks.Runs:Done` does.

**Integration ACs:** AC5 (Checks consumes `Fix.Run.Suspended`'s released) and AC6 (IncidentManager consumes `Fix.Run.Holds`) run against real rows.
- **Consumes:** `Fix.Run.Suspended`, `Test.Data.Fixture`, `Transitions`, 23.2's `Asked`/`ProposeFix`, 23.6's `Watch.Summary` (unchanged), and 23.7's quiet sweep.
- **Consumed-by:**
  - Story 23.3: its rollback undo after close follows whichever option is ruled here. Under (b), a rollback would add its kind to the hold rule.
  - BreakFeedIn (existing, no change).

**Routes (real-HTTP rule):** no `/api/v1` route or payload changes, so no new real-HTTP test is needed. The resume goes through the chat, and the Break the feed route's existing 409 is reached in one more case, with no code change.

**Online demo:** unchanged. Item kinds are refused there, so no hold arises, and the quiet and replay closes and Break the feed behave as today.

**Contended paths (the lead re-checks; all additive hunks, proposed as a plain union):**
- Epic 22 (in progress; footprint `Checks/**`, `Test/Checks/**`, `Test/Fix/**`): `Checks/Process.cls`, with hunks at `Run` 591-599, `Findings` 631-696 and the description 49-60. `Test/Checks/Runs.cls`: the method at 553 changes, and new methods are appended. `Test/Fix/Asked.cls`: one new method, appended.
- Epic 28 (backlog; `Watch/**`): `Watch/Transitions.cls` and `Watch/IncidentManager.cls`. Not running.
- Epic 36 (backlog; `Test/Watch/**`): the three Test/Watch files.
- Planning artifacts: `prd.md` (FR-16, FR-24), `EXPERIENCE.md` (698, 1210) and the spine (AD-15).
- No footprint extension.

**Ledger:** DW-1068 is addressed by AC1-AC5 and its Tasks & Acceptance bullet. No other entry is owned.

## PUBLIC TEXT for the Planner

None of these may be committed before the Planner rules on them. The recommended plan (b) needs NO new or changed string. Each is listed verbatim with its location.

Kept as ruled, and still true under (b):
- K1 `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:865` `result.itemSuspended`: "{item} in {production} is suspended: it is disabled now. To undo it while this incident is open, ask me to resume {item}. After the incident closes, enable {item} again on the production's configuration page in the Management Portal."
- K2 `README.md:70` (sentence of the Suspend bullet): "Nothing changes until you approve, and while the incident is open a suspend is undone the same way, by asking OcuTalon to resume the item."
- K3 `src/ocutalon/cls/OcuTalon/Agent/Chat.cls:65` (agent text; the epic context lists it as awaiting ruled wording): "If the user asks to suspend or resume a production item, or to reroute an incident's failed messages to another item, call propose_fix with kind suspend_item, resume_item or reroute and the item (for reroute, the item to send them to). To undo a suspend while its incident is open, call it with resume_item and the same item. Say that nothing changes until the request is approved; with outcome refused, give the reason."
- K4, reused in a new case: `web/src/app/feed/break-feed-view.ts:26` "Finish the current Orders incident first: approve or reject its fix, or dismiss the incident." (Break the feed meets a held incident on a local demo-mode install).
- K5, reused in a new case: `Msg/Catalog/Watch.cls:28` `watch.itemDisabled` "The {itemName} in the {production} production was disabled at {time}.\nWhy now: you asked me to watch the {production} production.", with `{time}` the suspend's end.

Optional for (b) (not planned; the Planner may add them):
- P1 (replaces K1; cost +30 min: the catalog, a regenerated `web/src/app/msg/catalog.ts` (Lane B) and the 8 pins above): "{item} in {production} is suspended: it is disabled now. This incident stays open until you resume {item} or dismiss the incident: to undo the suspend, ask me to resume {item}. If you dismiss the incident first, enable {item} again on the production's configuration page in the Management Portal."
- P2 (appended to README.md:70 after K2): "An incident whose suspend is not undone stays open until you resume the item or dismiss the incident."
- P3 (Chat.cls:65, replaces its second sentence; the RE-RULING's optional line; a footprint extension `Agent/Chat.cls` and its instruction pins in `Test/Agent/Instructions.cls`): "To undo a suspend while its incident is open, call it with resume_item and the same item; if the answer is no_incident, say that the incident is closed and that the item can be enabled again on the production's configuration page in the Management Portal."

Only if the Planner picks (a):
- a1 (replaces K1): "{item} in {production} is suspended: it is disabled now. To undo it, ask me to resume {item}."
- a2 (replaces K2): "Nothing changes until you approve, and a suspend is undone the same way, by asking OcuTalon to resume the item, also after its incident has closed."
- a3 (Chat.cls:65, second sentence): "To undo a suspend, call it with resume_item and the same item, also after its incident has closed."
- a4 (EXPERIENCE.md:698, Closed row, Actions): "Show details; a resume request raised after the close shows its request card with Approve and Reject".

New reason strings: none under either option. (a)'s refusals reuse `MESSAGENOTFOUND` and the kind's "{item} is already enabled".

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`. Each call should finish in about 150 s; never put two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- Use the fresh tag `e23s9i` and the warm tag `e23s9iw`.
- At the end, also after a failure, run `ci/warm.sh down` (warm tag), then `ci/iris.sh teardown` with each tag.
- Every IRIS MCP call names `server` `ocutalon-slot-d` and `namespace` `OCUTALON`.

**Shared surfaces:**
- AD-15's transition rows (`Test.Watch.Transitions` `Rows`, every row and refused move).
- `Test.Checks.Runs:TestSuspendedByOcuTalonIsNotReported` (its incident was closed; it now uses resolved).
- `Checks.Process.Findings`' signature (pure-case callers in `Test.Checks.Runs`).
- `Fix.Run.Suspended`'s signature: callers are `Checks.Process` and `Test.Checks.Runs`. Search `Test/` for others.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `ci/warm.sh up` with `OCUTALON_RUN_TAG=e23s9iw`. Re-up (`down`, then `up`, one call each) after any change to `Watch/IncidentManager.cls`, `Checks/Process.cls` or `Fix/Run.cls`, so that the production's jobs hold the new code.
- (loop) Then run `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23s9iw ci/iris.sh class <Class>[:<Method>]`, one call each. Run a long class by method when a whole run would pass 150 s; the timing is not recorded.
  - `OcuTalon.Test.Watch.Transitions`
  - `OcuTalon.Test.Watch.Lifecycle:TestHeldBySuspend`, `:TestCloseQuiet` and `:TestCloseForReplay`
  - `OcuTalon.Test.Checks.Runs:TestSuspendedByOcuTalonIsNotReported`, `:TestDismissedSuspendIsReportedOnce` and `:TestFindingsRule`, and the new pure `Findings`/`Suspended` methods
  - `OcuTalon.Test.Fix.Asked`

  Expected: each prints `CLASS ... passed`.
- (once) On the warm stack: `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Demo.BreakFeedIn`, `OcuTalon.Test.Watch.Summary` and `OcuTalon.Test.Fix.ItemKinds` (whole classes, one per call; split by method if over the cap) -- expected: passed.
- (once) `OCUTALON_RUN_TAG=e23s9i ci/iris.sh class OcuTalon.Test.Watch.Lifecycle:TestHeldBySuspend` on a fresh stack -- expected: passed.
- (once) The `ci/checks.sh` scripts, one per call: `bash docker/tests/test-<name>.sh` for each name of `CHECK_SCRIPTS` (`ci/units.sh:6,12`):
  - boundaries, storage, class-rules, ci-config, ci-changes, compose-file, pinned-sources, after-start, healthcheck, lib-live, bootstrap;
  - demo-path-gate, ci-warm, probe, install-script, readme, eval-set, online-host, online-load, upgrade-harness, rehearsal, release-checklist;
  - release-notes, release-sequence, redact-shapes, cpf, bridge-example, bridge-guide, triage-heartbeat, eval-personas, heartbeat-overview, mcp-notices.

  Expected: each passes.
- No web file changes, so `npm --prefix web test` is not required. If implement touches any `web/` file, add a (once) line and run the WHOLE suite.
- Left to CI: the shards, `live:demo-path` and the lead's fresh-environment check, forward and `--reverse`.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- AC1: `Transitions` resolved branch ignores `holds` → `Test.Watch.Transitions:TestRows` and `Lifecycle:TestHeldBySuspend`.
- AC2: the open-noticed closeQuiet ignores `holds` → `TestRows` (`d0 h1`) and `TestHeldBySuspend`.
- AC3: `Holds` ignores resume runs (the hold never ends) → `TestHeldBySuspend` (closes after the resume).
- AC4: `Asked` skips the recipients check → `Test.Fix.Asked:TestHeldIncidentResumeIsTheSessions`.
- AC5: `Findings` ignores `released` → `Test.Checks.Runs:TestDismissedSuspendIsReportedOnce`; and the run time instead of `one.at` → its time assertion.
- AC6: `Suspended` keeps the first suspend's incident as the holder (not the newest) → `TestHeldBySuspend` (the moved hold).
- AC7: the catch in `Holds` counts as not held → `TestHeldBySuspend` (`FailHolds`).
- AC8: none (unchanged behaviour; the existing suites are the evidence).

**Mutations run (implement, warm tag e23s9iw; each applied, observed red, reverted with `cmp` against the backup showing the tree byte-identical):**
- mutation: AC1, `Transitions` resolved branch ignores `holds` (closeForReplay/closeQuiet accepted at h1) -> red: `Test.Watch.Transitions:TestRefusedMoves` (resolved + closeQuiet/closeForReplay at holds 1, and the two pins) and `Test.Watch.Lifecycle:TestHeldBySuspend`. `TestRows` stays green, because the mutation still accepts every h0 row it lists; the refused h1 moves are `TestRefusedMoves`'s.
- mutation: AC2, the open-noticed closeQuiet ignores `holds` -> red: `Test.Watch.Transitions:TestRefusedMoves` (17 fails, `d0 h1`) and `Lifecycle:TestHeldBySuspend` (3 fails).
- mutation: AC3, `Suspended` never ends a holder on a resume (the `Kill holder(item)` removed) -> red: `Lifecycle:TestHeldBySuspend` (the summary lacks itemResumed and closedQuiet, and the resume through another incident still holds).
- mutation: AC4, `Asked` skips the recipients check -> red: `Test.Fix.Asked:TestHeldIncidentResumeIsTheSessions` (3 fails).
- mutation: AC5, `Findings` ignores `released` (the branch off) -> red: `Test.Checks.Runs:TestDismissedSuspendIsReportedOnce` (the one Item, and the run after).
- mutation: AC5, `Run` passes the run time instead of `one.at` -> red: `Test.Checks.Runs:TestDismissedSuspendIsReportedOnce` ("with the end of the suspend as the time"; the suspend's EndedAt is fixed to 2030-04-30T08:15:42Z so that it differs from the run time).
- mutation: AC6, `Suspended` keeps the first suspend's incident as the holder -> red: `Lifecycle:TestHeldBySuspend` (the moved hold, 3 fails).
- mutation: AC7, the catch in `Holds` counts as not held -> red: `Lifecycle:TestHeldBySuspend` (`FailHolds`, 3 fails).
- mutation: AC2 (dismiss half), the resolved branch of `Transitions` closes on dismiss only when holds is 0 -> red: `Test.Watch.Transitions:TestRows` (every resolved + dismiss row at holds 1).
- mutation: AC6 (a suspend run that changed nothing holds nothing), the `r.Completed > 0` condition removed from `Fix.Run.Suspended` -> red: `Lifecycle:TestHeldBySuspend` ("a suspend run that changed nothing holds nothing").
- mutation: AC8 / ruling condition (online demo unchanged), the resolved branch requires demo mode 0 for closeQuiet and closeForReplay -> red: `Test.Watch.Transitions:TestRefusedMoves` (resolved + closeForReplay and closeQuiet at demoMode 1, holds 0, "is a row but was refused").
- mutation: Facts reads holds for every event (`closing` set to 1) -> red: `Lifecycle:TestHeldBySuspend` ("and the dismiss logged no further holds warning").
- mutation: P3, `Chat.cls` loses the no_incident clause -> red: `Test.Agent.Instructions:TestChat` (the new pin).
- AC8 / online demo: no mutation; `Test.Fix.ItemKinds` (`ONLINESHARED`, passed), `Test.Demo.BreakFeedIn`, `Lifecycle:TestCloseQuiet` and `TestCloseForReplay` (passed) are the evidence, and `Test.Watch.Transitions:TestRefusedMoves` pins that a resolved incident with `holds` 0 still closes by closeQuiet with demo mode on.

**Mutations re-run (QA, warm tag e23s9qw; each applied, observed red, reverted from a backup with `cmp` and `git status --short` showing the tree as before):**
- mutation (QA): AC1, the resolved branch of `Transitions` closes on closeQuiet and closeForReplay whatever `holds` is -> red: `Test.Watch.Transitions:TestRefusedMoves` and `Test.Watch.Lifecycle:TestHeldBySuspend`.
- mutation (QA): AC2, the open-noticed closeQuiet ignores `holds` -> red: `Test.Watch.Transitions:TestRefusedMoves` (`d0 h1`) and `Lifecycle:TestHeldBySuspend`.
- mutation (QA): AC3, `Fix.Run.Suspended` never ends a holder on a resume -> red: `Lifecycle:TestHeldBySuspend` (no close after the resume, no summary lines).
- mutation (QA): AC4, `IncidentManager.Asked` skips the recipients check -> red: `Test.Fix.Asked:TestHeldIncidentResumeIsTheSessions`.
- mutation (QA): AC5, `Checks.Process.Findings` ignores `released` -> red: `Test.Checks.Runs:TestDismissedSuspendIsReportedOnce`; and `Run` passes the run time instead of `one.at` -> red: the same method ("with the end of the suspend as the time").
- mutation (QA): AC6, `Suspended` keeps the first suspend's incident as the holder -> red: `Lifecycle:TestHeldBySuspend` (the moved hold).
- mutation (QA): AC7, the catch in `IncidentManager.Holds` counts as not held -> red: `Lifecycle:TestHeldBySuspend` (`FailHolds`).
- mutation (QA): P3, `Agent.Chat` loses the no_incident clause -> red: `Test.Agent.Instructions:TestChat`.
- QA judgement: every AC and matrix row has a pin and no assertion was found that cannot fail; the replay refusal's other end (BreakFeedIn answering incident_in_progress) is the existing `Test.Demo.BreakFeedIn:TestCloseRefused`. No test file was created or changed by QA (files created: none). After the reverts the warm stack ran `Test.Watch.Transitions`, `Test.Watch.Lifecycle`, `Test.Checks.Runs`, `Test.Fix.Asked` and `Test.Agent.Instructions` green.

**Mutations run (code review, warm tag e23s9cw; applied, observed red, reverted from a backup with `cmp`, `git status --short` and `git diff --stat` unchanged):**
- mutation: AC5 (an item that a resume enabled sends none), `Fix.Run.Suspended` never ends a holder on a resume (the `Kill holder(item)` removed) -> red: `Test.Checks.Runs:TestDismissedSuspendIsReportedOnce` ("only A is released: B, which a resume enabled, is not"). After the revert `Test.Checks.Runs`, `Test.Watch.Transitions` and `Lifecycle:TestHeldBySuspend` passed on the same stack.

## Auto Run Result

Status: done
Blocking condition: none

- Implemented option (b) as ruled (U-321): an incident that holds a suspend is not closed by closeQuiet or closeForReplay, and Dismiss always closes. Checks reports the item once after the incident closes, with the suspend's end as its time.
- Files changed:
  - `Fix/Run.cls`: `Suspended` gains `holders` and `released`; new `Holds`.
  - `Watch/Transitions.cls`: the `holds` fact and the split close rows.
  - `Watch/IncidentManager.cls`: `Facts` reads `holds` for the two close verbs through `Holds` and the seam `ReadHolds`; a failed read counts as held with one `LOGHOLDS` warning.
  - `Checks/Process.cls`: `Run` passes `released` to `Findings`, which reports a released item once at the suspend's time.
  - `Agent/Chat.cls` and `Test/Agent/Instructions.cls`: P3, verbatim, with its pin.
  - Tests: `Test/Watch/IncidentProbe.cls`, `Test/Watch/Transitions.cls`, `Test/Watch/Lifecycle.cls` (`TestHeldBySuspend`), `Test/Checks/Runs.cls`, `Test/Fix/Asked.cls` (`TestHeldIncidentResumeIsTheSessions`).
- Review: 24 triage rows from four layers; patches applied: 2 (a holds-read pin in `TestHeldBySuspend`; three missing mutation lines); deferred: 0; the other findings are rejected with their reasons in the Review Triage Log.
- Follow-up review recommended: false (one medium patched, no high).
- Verification: on the warm stack `Test.Watch.Transitions`, `Test.Watch.Lifecycle` (whole), `Test.Checks.Runs` (whole), `Test.Fix.Asked`, `Test.Agent.Instructions`, `Test.Demo.BreakFeedIn`, `Test.Watch.Summary`, `Test.Fix.ItemKinds`, `Test.Fix.AskedTurns`, `Test.Core.CommandsRouting` and `Test.Fix.Runs` passed; `Lifecycle:TestHeldBySuspend` passed on a fresh stack after the last patch; the 33 check scripts passed after the implementation pass, and `class-rules`, `boundaries` and `storage` were run again after the last patch. Every AC has a demonstrated mutation (see `## Verification`).
- Residual risks: the production's jobs were not exercised against the new code in a warm re-up (CI's live runs cover it); the shards, `live:demo-path` and the lead's fresh-environment check, forward and reverse, are left to CI.
