---
title: 'Story 23.11: Say in a partner notice only how the incident ended'
type: 'bugfix'
created: '2026-11-12'
status: 'done'
baseline_revision: '4a1b0d0ec605238e2e8c0db452004ded1989d728'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-10-partner-notice-and-summary-polish-from-the-1-0-7-demo-pass.md'
warnings: [oversized]
deferred:
  - summary: >-
      The incident's plural item noun, supplied by the model in the diagnosis payload, now enters the trusted SystemNote of the partner-notice draft.
    evidence: |-
      Watch.Notice.Noun checks only that both forms are non-empty (no length or character check); IncidentManager stores diagnosis.itemNoun as given. The substitution is the Planner's ruled design. Settled by showing that the diagnosis payload check caps the noun, or by normalising it in SystemNote.
    location: >-
      src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls SystemNote
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Story 23.10's ruled instruction tells the model that a resolved incident's notice says "the affected orders went through after the fix", but the draft's facts carry only the incident's state. A resolved incident is any incident whose last run ended (`Watch.Transitions`: fixing + finished -> resolved, whatever the counts), so a partial fix, a reroute or a suspend gets the same success claim (DW-1165). The guide's demo path (Reject a fix, Reroute the failed orders, Warn the partner) hits it.

**Approach:** OcuTalon's code, not the model, adds one ruled "Outcome:" line to the draft's facts, built from the incident's own records (its requests, each request's `FixRun` counts, the incident's failure count). The ruled instruction sentence replaces 23.10's, verbatim. Any ending that the records do not map exactly onto one ruled line gets no Outcome line, and the instruction then forbids saying whether the orders went through.

## Boundaries & Constraints

**Always:**
- Use the ruled strings exactly (Contest Planner ruling 2a/2b, Design Notes):
  - "Outcome: all {N} affected {noun} went through after the fix."
  - "Outcome: {A} of the {N} affected {noun} went through after the fix, and {R} did not."
  - "Outcome: the {N} affected {noun} were resent by another route."
  - "Outcome: the affected flow was paused, and the {N} affected {noun} haven't gone through yet."
  - The instruction sentence (replacing 23.10's sentence at the end of `SYSTEMNOTE`, after one space): "If the incident is resolved, say how it ended using only the Outcome fact, and don't say that work is still going on or that updates will follow. If there is no Outcome fact, don't say whether the {noun} went through."
- The Outcome line is built only from rows: `Incident` (State, Count, RequestRefs), `ApprovalRequest` (FixKind, FixParameters, IncidentRef), `FixRun` (EndedAt, Total, Resent, Completed, FailedAgain, Skipped, Interrupted), `FailureGroup.ItemName` and the kind classes' parameters. The mapping is the one under Design Notes, "The Outcome mapping".
- The Outcome line names no item, route target, production or partner, and holds no setting value, message content, reason text or evidence. Only numbers vary.
- Model-facing changes go on the Planner's RC-eval checklist (Design Notes). CI proves only what the code sends to the model.

**Never:**
- Do not remove or change the existing "Failed item:" Facts line (Q1: the Contest Planner ruled KEEP), the other Facts lines or their order.
- Do not let the model compute or choose the Outcome. No new model call, sampling parameter, model or token change.
- No change to the incident's state, the transition table, `Fix.Executor*`, `Fix.Run`, `Watch.Summary`, `IncidentManager` (except the one `DraftRequest` SystemNote line the noun ruling adds, Design Notes), any catalog key or text, README, EXPERIENCE, web source, route, setting, table, grant, dependency or live-event type. No edit to `Msg/Catalog/Watch.cls` or `Test/Msg/Catalog.cls`.
- No edit under `irislib/`, `irissys/`, `docs/**` or the spine.

## I/O & Edge-Case Matrix

All rows: incident State `resolved`, Count 50, one failure group at `OrdersFromPartner`, unless the row says otherwise. "Run" is the one `FixRun` of the incident's one request of a kind with `MOVES` 1 (Total/Resent/Completed/FailedAgain/Skipped, Interrupted 0, EndedAt set).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Full fix | `repair_resend`, run 50/50/50/0/0 | "Outcome: all 50 affected orders went through after the fix." right after the "Incident state: resolved" line | No error expected |
| Partial fix | `repair_resend`, run 50/48/45/3/2 | "Outcome: 45 of the 50 affected orders went through after the fix, and 5 did not." | No error expected |
| Partial, none through | `repair_resend`, run 50/50/0/50/0 | "Outcome: 0 of the 50 affected orders went through after the fix, and 50 did not." | No error expected |
| Partial by count | Count 52; `repair_resend`, run 50/50/50/0/0 | "Outcome: 50 of the 52 affected orders went through after the fix, and 2 did not." | No error expected |
| Reroute | `reroute` (target `OrdersForReview`), run 50/50/40/10/0 | "Outcome: the 50 affected orders were resent by another route." (no item or target name) | No error expected |
| Reroute, not all | `reroute`, run 48/48/48/0/0 (dry run left 2 out) | no Outcome line | No error expected |
| Suspend | `suspend_item` of `OrdersFromPartner`, run Total 1, Completed 1 | "Outcome: the affected flow was paused, and the 50 affected orders haven't gone through yet." | No error expected |
| Suspend, other item / unchanged | `suspend_item` of `OrdersToWarehouse` (not a failed item); or Completed 0, Skipped 1 | no Outcome line | No error expected |
| No fix | no request, or only a rejected/expired request (no run), or only a `partner_warning` run | no Outcome line | No error expected |
| Other endings | `resume_item`; Interrupted > 0; couldn't start (Resent 0, request failed); nothing resent (Resent 0, Skipped = Total); unknown kind | no Outcome line | No error expected |
| Unknown counts | Count 0; run without EndedAt; Total > Count or Completed > Count | no Outcome line | No error expected |
| Several runs | two runs of moving kinds (for example a full fix, then a suspend) | no Outcome line | No error expected |
| Not resolved | State `open`, `awaiting_approval` or `fixing`, with a full-fix run | no Outcome line; Facts as 23.10 left it | No error expected |
| Instruction | any draft | `SYSTEMNOTE` = the Story 23.5 text + " " + the ruling 2b text | No error expected |
| Mock, per outcome | resolved incident with each of the four endings, cause marker `[[mock:<case>]]`, the ask turn | one pending `partner_warning` request to contact 1; the logged draft request holds exactly that Outcome line and the 2b sentence; the notice has no "looking into" / "will share updates", and "went through" only in the full-fix case | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls` (not contended):
  - class doc 8-9 (the Facts bullet);
  - `SYSTEMNOTE` 38: 23.10's sentence is the text after "don't promise when it will be fixed. ";
  - `Facts` 56-78: the "Incident state:" line is 70. The Outcome line goes right after it.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls` (read-only sibling):
  - `Build` 59-81: the request loop to follow: `RequestRefs` -> `ApprovalRequest.RefIndexOpen`, skip a row whose `IncidentRef` is not the incident's, then `FixRun.OfRequest`, then `Fix.Kind.ForName`;
  - `RunEvents` 183-210: the meaning of the counts. An item run (TARGETTYPE item) changed its item when `Completed > 0`; an interrupted run has `Interrupted > 0`; a contact run is a notice, not a fix.
- `src/ocutalon/cls/OcuTalon/Data/FixRun.cls` 1-56 -- the counts and EndedAt (a run without EndedAt has no result); `OfRequest` 66.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` doc 37-51 -- the endings:
  - couldn't start: Resent 0, request `failed`, Reason;
  - nothing resent: Resent 0, Skipped = Total, request `done`;
  - waited: Completed + FailedAgain = Resent, Skipped = Total - Resent;
  - still running after 60 s: no EndedAt, the incident stays `fixing`.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls` 41-66 -- `TARGETTYPE` (default message), `DIAGNOSED` (1 only for `repair_resend`), `MOVES` (0 only for `partner_warning`); `ForName` 104.
- The kinds:
  - `Fix/Kind/Reroute.cls` 1-12: the run's targets exclude the dry run's `leftOut`, so Total can be below Count;
  - `Fix/Kind/SuspendItem.cls`: the parameter `item`, `TARGETTYPE` item, `ENABLE` 0;
  - `Fix/Kind/ResumeItem.cls`: `ENABLE` 1.
- `src/ocutalon/cls/OcuTalon/Watch/Transitions.cls` 17 (fixing + finished -> resolved whatever the counts); `Watch/IncidentManager.cls`:
  - 467-468: Count grows with fresh failures while the incident is not closed (a copy's failure is not counted, `FixRun.CopyOf`);
  - 1653-1662 `Result`: Final or Interrupted -> finished;
  - `DraftRequest` (about 1233-1253): Text = `Facts`, SystemNote = `SYSTEMNOTE`. No change.
- Tests (contended, Epic 22 `Test/Fix/**`):
  - `Test/Fix/PartnerWarning.cls`:
    - header 5-25;
    - the SYSTEMNOTE pin 100;
    - `TestFacts` 106-131 (an open incident: its exact expected text stays unchanged);
    - helpers `Owner` 437, `Incident` 445 (group at `OrdersFromPartner`, default Count 3) and `Request` 475;
    - rows are cleaned through `..Refs` / `Fixture.Clean`. A `Fixture.FixRun` saved under the incident's Ref is deleted with it.
  - `Test/Fix/PartnerDraft.cls`: `TestDraftRequest` 120-150 (probe `BeginDraft`, `host.DraftRequests`, `request.input`); helpers `Host` 513, `Owner` 521, `Incident` 534, `Draft` 600.
  - `Test/Fix/PartnerTurns.cls`:
    - header 2-18;
    - `TestResolvedDraftSaysTheOrdersWentThrough` 182-210 (the old sentence literal at 206);
    - `Asked` 213 (trailing `marker`, `ResolvedIncident(a, marker)`);
    - `ResolvedIncident` 248: `..Fixture(session, "1,2,3", ...)`, so Count is 3 and the group is at `OrdersFromPartner`;
    - other callers: `Asked` at 58, 75 and 109; `ResolvedIncident` directly at 132 and 167.
  - Cleanup: `Test.Watch.Case.OnAfterOneTest` (247) deletes `FixRun` rows for each Ref in `..ItemIds`. Confirm that it also drops a fixture approval row of the session, or clean that row yourself.
  - Helpers: `Test.Data.Fixture.Approval` 137 and `FixRun` 155; the request + run + `RequestRefs` pattern in `Test/Watch/Summary.cls` `TestKindLines` 696-712 and `Link` 828.
- Mock:
  - `ci/mock/scenarios/A/partner-notice-resolved.json` (kept unchanged as the full-fix case; its reply contains "went through after it") and `partner-notice.json` (the shape to copy);
  - selection order is the marker first (`ci/mock/mock.mjs` 25-36);
  - B prompts are checked by containment. Checked at plan: none of the 19 B prompts is contained in the 2b sentence or in any Outcome line.

## Tasks & Acceptance

**Execution:**
- [x] `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls` (DW-1165):
  - add `ClassMethod Outcome(incident As OcuTalon.Data.Incident) As %String`. It returns the one ruled line, or "", exactly by the Design Notes mapping, with `{N}`, `{A}` and `{R}` as plain whole numbers;
  - in `Facts`, right after the "Incident state:" line, append `$Char(10)_line` when `Outcome` gives a line;
  - `SYSTEMNOTE`: replace 23.10's sentence, verbatim, by the 2b text;
  - the class doc's Facts bullet names the Outcome line (code-built from the incident's records, only when resolved), and `Outcome` gets a contract doc comment.
- [x] `ci/mock/scenarios/A/partner-notice-partial.json`, `partner-notice-rerouted.json`, `partner-notice-paused.json` -- new marker scenarios, the shape of `partner-notice.json`, one reply each:
  - partial: "Orders sent from your feed failed because the date format of the orders changed. After the fix, some of the affected orders were processed and the rest were not.";
  - rerouted: "Orders sent from your feed failed because the date format of the orders changed. The affected orders were resent by another route.";
  - paused: "Orders sent from your feed failed because the date format of the orders changed. The affected flow was paused, and the affected orders have not been processed yet.".

  `partner-notice-resolved.json` stays unchanged as the full-fix case.
- [x] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls`:
  - the SYSTEMNOTE pin (100) gains the 2b text in place of 23.10's sentence;
  - append the tests and a helper `Ran(owner, incident, kind, parameters, run, state)`. It makes one request (`Test.Data.Fixture.Approval`, default state `done`) and its `FixRun` (`Fixture.FixRun`), appends the request's Ref to the incident's `RequestRefs` and registers both rows for cleanup. The tests:
    - `TestOutcomeFullFix`: the Full fix row, and Facts holds the line right after "Incident state: resolved";
    - `TestOutcomePartialFix`: the Partial fix, Partial none through (zero completed) and Partial by count rows;
    - `TestOutcomeReroute`: the Reroute row (the line has no "OrdersForReview" and no "OrdersFromPartner") and the Reroute, not all row;
    - `TestOutcomeSuspend`: the Suspend row, and the Suspend, other item / unchanged rows;
    - `TestNoOutcome`: every No fix, Other endings, Unknown counts, Several runs and Not resolved row, plus a resolved incident with no fix and Count 0, and a run with all counts 0. Each gives "" and Facts without "Outcome:".
  - add the header bullets.
- [x] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls` -- append `TestDraftRequestCarriesOutcome` (the consumer): a resolved incident with a reroute run (Count, Total and Resent equal, target `OrdersForReview`) -> the one Decide request's `input` holds "Outcome: the <Count> affected orders were resent by another route." and no "OrdersForReview". A resolved incident with no run -> its `input` holds no "Outcome:". Add a header bullet.
- [x] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls`:
  - `ResolvedIncident` gains a trailing `ending As %DynamicObject = ""` ({kind, parameters, run}). When it is given, it adds one `done` request of that kind with the run counts and links it in `RequestRefs`. `Asked` gains the same trailing argument and passes it on (existing callers unchanged);
  - `TestResolvedDraftSaysTheOrdersWentThrough` passes a full-fix ending (3/3/3/0/0) and asserts:
    - the draft holds "Outcome: all 3 affected orders went through after the fix.";
    - the old sentence literal is replaced by the 2b text;
    - the notice contains "went through".
  - append `TestPartialFixDraft` (`partner-notice-partial`, repair_resend 3/3/2/1/0 -> "Outcome: 2 of the 3 affected orders went through after the fix, and 1 did not."), `TestReroutedDraft` (`partner-notice-rerouted`, reroute to `OrdersForReview` 3/3/3/0/0 -> the reroute line, and the draft request holds no "OrdersForReview") and `TestPausedDraft` (`partner-notice-paused`, suspend_item of `OrdersFromPartner`, Completed 1 -> the paused line). Each asserts:
    - one pending request to contact 1;
    - the notice has no "went through", "looking into" or "will share updates" (lower-cased);
    - exactly one logged draft request (the one whose messages hold "Write a short delay notice") holds the Outcome line and the 2b sentence.

    Factor the shared draft assertions into one appended helper, which the 23.10 test also calls;
  - header bullets for the changed and new tests.

**Acceptance Criteria:**
- AC1: Given a resolved incident whose one fix run resent and completed every one of its Count messages (none failed again or skipped), when its partner notice is drafted, then the facts carry "Outcome: all {N} affected {noun} went through after the fix." with N = Count, right after the state line. (`Test.Fix.PartnerWarning:TestOutcomeFullFix`)
- AC2: Given a resolved incident whose one fix run resent messages but completed fewer than Count, when the notice is drafted, then the facts carry "Outcome: {A} of the {N} affected {noun} went through after the fix, and {R} did not." with A = Completed, N = Count and R = N - A, including A = 0. (`TestOutcomePartialFix`)
- AC3: Given a resolved incident whose one run is a reroute that resent all Count messages, when the notice is drafted, then the facts carry "Outcome: the {N} affected {noun} were resent by another route.", with no item or target name. (`TestOutcomeReroute`; `PartnerDraft:TestDraftRequestCarriesOutcome` at the consumer)
- AC4: Given a resolved incident whose one run suspended one of the incident's failed items, when the notice is drafted, then the facts carry "Outcome: the affected flow was paused, and the {N} affected {noun} haven't gone through yet." (`TestOutcomeSuspend`)
- AC5: Given any other ending (no fix, resume, interrupted, couldn't start, nothing resent, several runs, a suspend of another item or one that changed nothing, a reroute that did not resend all) or unknown counts (Count 0, no EndedAt, counts above Count), or an incident that is not resolved, when the notice is drafted, then the facts carry no Outcome line. (`TestNoOutcome`)
- AC6: Given any draft, when the instruction is sent to the model, then `SYSTEMNOTE` ends with the 2b sentence verbatim and no longer holds 23.10's. The Outcome line carries no item, route target, production or partner name, setting value or message content. The existing "Failed item" line is unchanged, pending Q1. (The SYSTEMNOTE pin; the name assertions in AC3 and AC4 tests)
- AC7 (the ruled mock cases): Given the CI mock and a resolved incident with each of the four endings, when the user asks to warn the partner, then the draft request that the model receives holds that ending's exact Outcome line and the 2b sentence, and the notice raised for approval:
  - contains "went through" only in the full-fix case;
  - never contains "looking into" or "will share updates".

  (`Test.Fix.PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough`, `TestPartialFixDraft`, `TestReroutedDraft`, `TestPausedDraft`)
- DW-1165: closed by AC1-AC7. Facts now carry the ending, and the sentence no longer claims that the orders went through.

## Spec Change Log

- 2026-11-12 (lead, after the spec gate): the orchestrator's and the Contest Planner's rulings recorded under Design Notes; the Outcome lines and the 2b sentence take the existing facts' noun (`{noun}`), so `PartnerWarning.SystemNote(incident)` and a one-line `IncidentManager.DraftRequest` extension are added to the plan; Q1 keeps "Failed item".

- 2026-11-12 (plan): Story inserted 2026-11-12 from the Contest Planner's ruling on DW-1165 (~00:20Z, owner's delegation). Lane D, after 23.10 and before 23.9.

## Review Triage Log

### 2026-11-11 - Review pass
- verdicts: 19 findings - high 0, medium 4, low 11, false 3, maybe-false 1 (the intent-alignment layer reported readings only; the four review-layer reports merge to these rows)
- findings:
  - `[low]` `[reject]` blind: a count of 1 reads "all 1 affected orders" - ruled (Planner (2): N=1 accepted as is, plural noun always); the fix would edit the ruled strings.
  - `[maybe-false]` `[defer]` blind: the incident's plural noun (model-supplied `diagnosis.itemNoun`, no length or character check in `Watch.Notice.Noun`) now enters the trusted SystemNote; the substitution is the Planner's ruled design, what would settle it is whether the diagnosis payload check caps the noun.
  - `[low]` `[reject]` blind: the notice assertions in the PartnerTurns cases read the mock's canned replies - by design (ruling 2d, CI proves what the code sends; the model-facing wording is on the Planner's RC-eval list); the code is pinned by the logged-request assertions.
  - `[medium]` `[patch]` blind + gap: edge cases of `Outcome` untested (a fix with Completed = Count but one failed again; a duplicate ref is conservative and needs no row; a reroute with Completed above Count) - rows added to `TestNoOutcome`.
  - `[low]` `[reject]` blind: the reroute is detected by NAME - the spec's mapping says "NAME `reroute`"; no other kind reroutes.
  - `[false]` `[reject]` blind + edge: `DraftRequest` falls back to the raw `SYSTEMNOTE` when `SystemNote` is missing - the ruled hook ("when the kind class defines that method"); `PartnerWarning` is the only drafted kind and defines it, and `TestDraftRequestCarriesOutcome` asserts no `{noun}` token reaches the request.
  - `[low]` `[reject]` blind: a suspend in a `resolved` incident reads oddly - the paused line is ruled (2a).
  - `[false]` `[reject]` edge: `SystemNote` or `Noun` could throw in `DraftRequest` - `Facts` calls the same `Noun` in the same method, so no new failure path.
  - `[low]` `[reject]` edge: Count grown after the run gives the partial line - the mapping rule 5 says so (Completed < N whatever the reason).
  - `[low]` `[reject]` edge: Resent above Completed + FailedAgain - the executor's waited ending has them equal; the ruled test is Completed (the executor's own).
  - `[low]` `[reject]` edge: duplicate ref or a non-done request with a run - gives no line (conservative); a failed request with a run has Resent 0 and gives none.
  - `[low]` `[reject]` edge: a reroute whose copies failed again - ruled: the line says resent, not went through.
  - `[low]` `[reject]` edge: a suspended item re-enabled by hand before the incident resolves - speculative; a resume is a second moving run and gives no line.
  - `[false]` `[reject]` edge: the second `BeginDraft` in `TestDraftRequestCarriesOutcome` could be deduped - the test asserts a count of 2 and passes.
  - `[medium]` `[patch]` gap: the `MOVES` skip of a partner_warning run was pinned by no test - a full fix plus a later notice run row added to `TestOutcomeFullFix`; mutation recorded.
  - `[medium]` `[patch]` gap: the Total and Completed above Count guards were masked by later guards - two rows added to `TestNoOutcome`; mutations recorded.
  - `[medium]` `[patch]` gap: a request of another incident and a ref with no row untested - two rows added to `TestNoOutcome`; mutation recorded.
  - `[low]` `[patch]` gap: the Try/Catch on FixParameters unexercised - two rows added (not JSON; item not a string).
  - `[low]` `[reject]` gap: the notice assertions read canned mock replies and `TestDraftRequest` compares with `SystemNote(...)` - the literal checks sit in `TestDraftRequestCarriesOutcome` and `TestOutcomeUsesTheItemNoun`; no mutation line for the DraftRequest hook is needed beyond AC6/AC7.

## Design Notes

**The ruling (verbatim, Contest Planner under the owner's delegation, 2026-11-12 ~00:20Z):**

> A partner notice must never claim more than OcuTalon knows (the approval card doesn't excuse it; the demo makes it easy to hit: Reject a fix, Reroute the failed orders, Warn the partner).
>
> 1. 23.10 merges as is, on green.
> 2. FOLLOW-UP Story 23.11 (Epic 23 re-open), lane D, BEFORE 23.9. Target 1.0.8 if merged before the cut, else 1.0.9.
>    a. OcuTalon's code (not the model) adds an "Outcome:" fact to the draft's facts, built from the incident's own records. One line per case:
>       - fix resent every affected message, none failed again or skipped: "Outcome: all {N} affected orders went through after the fix."
>       - fix with some failed again or skipped: "Outcome: {A} of the {N} affected orders went through after the fix, and {R} did not."
>       - ended by a reroute: "Outcome: the {N} affected orders were resent by another route."
>       - ended by a suspend: "Outcome: the affected flow was paused, and the {N} affected orders haven't gone through yet."
>       - any other ending, or counts unknown: no Outcome line.
>    b. The ruled instruction sentence is replaced, VERBATIM, by: "If the incident is resolved, say how it ended using only the Outcome fact, and don't say that work is still going on or that updates will follow. If there is no Outcome fact, don't say whether the orders went through."
>    c. Facts never carry item or target names, setting values or message contents (existing notice rule).
>    d. Tests: one CI mock case per outcome ("went through" only in the all-through case; none contain "looking into" or "will share updates"), plus a unit test per outcome builder incl. zero counts and a resolved incident with no fix.
>    e. If the incident's records can't support a line exactly as written, the spec gate may adjust the wording to fit; changed wording goes to the Planner (PUBLIC TEXT) before commit.
>    f. RC-eval (Planner): the full-fix case and the reroute-ended case on the RC.
> 3. If 23.11 misses 1.0.8, the Planner checks Reroute then Warn the partner by hand on the 1.0.8 RC.
> 4. Catalog.cls with 35.3: plain union of separate hunks, approved; re-check at integrate.
> DW-1165: routed to the 23.11 key (by=owner) once the story exists.

**The Outcome mapping (Decided in-stage; it is the contract of `PartnerWarning.Outcome`):**
1. **Only a resolved incident has an ending.** State is not `resolved` -> "".
2. **The ending is the incident's one run.** Take the incident's requests as `Watch.Summary.Build` does: the `RequestRefs` entries whose row exists and names the incident, and that have a `FixRun`, of a kind whose `MOVES` is 1 (a `partner_warning` run never counts; an unknown kind counts, and then maps to ""). Exactly one such run, else "":
   - none: no fix;
   - two or more: their counts don't add up to one honest line. A full fix and then a suspend would otherwise say "haven't gone through".
3. **The run must have a result.** EndedAt set and Interrupted 0, else "".
4. **The numbers.** N = the incident's `Count` (the number the Failures line already gives; it includes failures counted after the request, and never a copy's). Count 0 -> "". Total > N or Completed > N -> "".
5. **By the kind:**
   - **The fix** (the kind is `DIAGNOSED`, TARGETTYPE message: today `repair_resend`). Resent 0 -> "" (it couldn't start, or resent nothing). Resent = Completed = N with FailedAgain = 0 and Skipped = 0 -> the full-fix line. Otherwise (Completed < N, whatever the reason: failed again, skipped, left out by the dry run, or failed after the request) -> the partial line with A = Completed and R = N - A. "Went through" means a copy reached Completed, the executor's own test (Executor doc 41-46).
   - **Reroute** (NAME `reroute`). Resent = N and Skipped = 0 -> the reroute line. Otherwise "" (a reroute that left some out would make "the N affected orders were resent" false). FailedAgain does not change it: the line says resent, not went through.
   - **Suspend** (TARGETTYPE item, `ENABLE` 0: `suspend_item`). Completed > 0, and the request's parameter `item` is one of the incident's failure groups' `ItemName`s -> the paused line, else "". A suspend of an unrelated item did not pause "the affected flow". With rule 2, no run of this incident resent anything, so "haven't gone through yet" is what the records hold.
   - **Any other kind** (`resume_item`, a future kind) -> "".
6. **Where.** The line goes right after "Incident state: resolved". An incident with no Outcome keeps 23.10's Facts byte for byte.

{N}, {A} and {R} come from integer columns only; nothing else varies. No ruled line needed a wording change under this mapping, so there is **no PUBLIC TEXT adjustment** (ruling 2e not used).

**Questions and observations for the Planner (the lead sends them; none blocks this plan):**
- **Q1 (ruling 2c vs the existing facts).**
  - **The conflict.** Ruling 2c, and Story 23.11's AC, say that the facts never carry item or target names, calling this the "existing notice rule". But since Story 23.5, `Facts` has carried "Failed item: <the failure groups' item names>".
  - **Its origin.** 23.5's spec, Tasks: "failed item(s) from `FailureGroup.OfIncident`", pinned in `TestFacts`. 23.5's epics AC reads "from the incident's count, times, affected flow and plain cause only, never a message body or setting value". 23.10's I/O matrix kept the line. AD-16's partner-warning bullet sets no facts rule.
  - **What the existing rule forbids.** 23.5 and 23.10, Boundaries: "no message body, sample error, setting value or evidence". It does not forbid item names.
  - **Recommendation.** Keep "Failed item". It is 23.5's "affected flow", and README:56 says the notice is drafted "from the incident's count, times, affected flow and cause". Read 2c as binding the new Outcome line, which carries no item, route target or production name (AC6).
  - **If the Planner rules the names out.** The change is the one `Facts` line and `TestFacts`' expected text: a small follow-up, or a rework of this story at the gate.
  - This story leaves the line unchanged (the lead's instruction).
- **Observation 1.** The ruled lines say "orders" for every production. A local install's incident with another item noun (its Failures line says, for example, "messages") still gets "orders" in the Outcome. The ruled 2b sentence also says "the orders", and 23.10's review accepted "orders" as ruled. Kept verbatim. If the Planner wants it, the noun could be the incident's item noun (`Watch.Notice.Noun`), which reads "orders" on the demo.
- **Observation 2.** N = 1 reads "all 1 affected orders went through" and "the 1 affected orders haven't gone through yet". Kept verbatim: the line is model-facing input, which the model paraphrases.
- **Observation 3.** README:56 lists what the notice is drafted from (count, times, affected flow, cause). With this story, a resolved incident's notice also uses how it ended. No README edit, because that is public text not ruled here; a possible addition is ", and, once it is resolved, how it ended".

**Rulings after the spec gate (binding; `.coordination/prompts/epic-23-story-2311-ruling.md`):**
- Orchestrator (~00:35Z): the contended hunks listed under Design Notes are approved as plain unions; re-check each branch (bash, split list) before implement.
- Contest Planner (~00:40Z, owner's delegation), spec accepted:
  - **Q1: KEEP "Failed item: <names>"** (23.5's approved affected flow; the existing rule was misstated). Ruling 2c binds only the new Outcome line: no item, target, production or partner names in it.
  - **(1) Noun:** use the noun the existing notice facts already use, in the Outcome lines AND in the 2b sentence ("...don't say whether the {noun} went through."). Pre-approved. The existing facts do carry one: `Watch.Notice.Noun(incident)`, which the Failures line uses (`noun.other`). So every ruled Outcome line reads "affected {noun}" with `{noun}` = `Noun(incident).other` (plural always, per (2)), and the sentence's last words read "whether the {noun} went through." On the demo the noun is "orders", so the demo wording and its pins stay exactly as planned. (No low DW: the facts carry a noun.)
  - **(2) N=1 accepted as is** (plural noun). **(3) No README edit in 23.11.** RC-eval swap accepted.
- What the noun ruling changes in the plan (the lead's amendment, 2026-11-12):
  - `SYSTEMNOTE` holds the 2b sentence with a literal `{noun}` token in place of "orders". Add `ClassMethod SystemNote(incident As OcuTalon.Data.Incident) As %String` to `Fix/Kind/PartnerWarning.cls`: `SYSTEMNOTE` with `{noun}` replaced by `Watch.Notice.Noun(incident).other`.
  - `Watch/IncidentManager.cls` `DraftRequest` (~1251, not contended) sets `request.SystemNote` from the kind's `SystemNote(incident)` when the kind class defines that method, else from `SYSTEMNOTE` as today (extend, don't copy; other kinds unchanged).
  - `Outcome` builds its lines with the same noun.
  - The B mock prompt `partner-notice-draft` must still be a prefix of the rendered SystemNote (it ends before the 2b sentence; check it).
  - Tests: the SYSTEMNOTE pin compares the Parameter text with the token; add one unit test with an incident whose `Noun` is not "orders" (e.g. a dry run or stored itemNoun of "messages") showing both an Outcome line and `SystemNote(incident)` use it, and that `SystemNote` for the demo incident ends "...whether the orders went through."; `PartnerDraft:TestDraftRequestCarriesOutcome` also asserts the request's SystemNote is the rendered one (no literal `{noun}`).

**For the Planner's RC-eval checklist (ruling 2f, model-facing; it replaces 23.10's item):**
1. **Full fix.** On the RC, run the guide incident, approve the repair (all 50 orders go through), then ask "Warn the partner about the delay.". The drafted notice says all 50 affected orders went through after the fix. It addresses Orders Partner IT, and it has no "looking into", no "will share updates" and no other words saying work is still going on.
2. **Reroute-ended (the demo path).** Break the feed, Reject the fix, Reroute the failed orders, then Warn the partner. The notice says the 50 affected orders were resent by another route. It does not say they went through, it names no route or item, and it does not say work is going on or updates will follow.

**Decided in-stage:**
1. The Outcome mapping above (rules 1-6), within ruling 2a's "any other ending, or counts unknown: no Outcome line".
2. `partner-notice-resolved.json` is **reused unchanged** as the full-fix case. Its reply already says the orders went through, and 23.10's test becomes the full-fix test by giving its incident a full-fix run. Three new scenarios cover the other outcomes, and their replies never say "went through".
3. The four end-to-end cases stay in `Test.Fix.PartnerTurns` (append-only, plus the 23.10 test's own lines), not in a new class. `ci/iris.sh class <Class>:<Method>` runs one method per call, so each call stays well under the cap. `Test.Fix` already runs in `shard:lane-a@Fix` (shards-11), so `ci/units.sh` is unchanged.
4. No mock case for "no Outcome". The ruling asks for one per outcome. The no-Outcome Facts are pinned by `TestNoOutcome`, and at the consumer by `PartnerDraft:TestDraftRequestCarriesOutcome`.
5. The existing `partner-notice` / `partner-notice-draft` replies ("We are looking into it and will keep you informed.") stay as they are. Their incidents have no fix run, so they are not outcome cases. They are CI-only canned text pinned by `NOTICE` (23.10, Decided in-stage 5).

**Ledger inbox (Rule 17):** DW-1165 is addressed by Tasks (the `PartnerWarning.cls` task) and AC1-AC7.

**Integration ACs (Rules 1-2):** `PartnerWarning.Outcome` is a new method of an existing kind.
- **Its consumer.** `Watch.IncidentManager.DraftRequest`, through `Facts`, sends it to the model. Pinned by `PartnerDraft:TestDraftRequestCarriesOutcome` (the probe's real `BeginDraft` -> `request.input`) and end to end by the four `PartnerTurns` cases (the real production, the mock's log).
- **Consumed-by:** `IncidentManager.DraftRequest` (Story 23.5's drafting, this story).
- **Consumes:** `FixRun` (Epic 7, Stories 7.3-7.5, 30.5), `ApprovalRequest` rows (AD-11), `Fix.Kind` parameters (Story 23.2), `Incident` / `FailureGroup` (AD-15). All are read-only.

**Extend, don't copy (Rule 2):**
- `Outcome` follows `Watch.Summary.Build`'s request loop (59-81) and `RunEvents`' item and contact reading (183-210). It reuses `FixRun.OfRequest` and `Fix.Kind.ForName` rather than extracting a shared iterator, because Summary's loop builds its timeline in the same pass, its helpers are private, and the shared part is a four-line lookup.
- `PartnerWarning.Ran` follows `Test.Watch.Summary`'s Request + `Link` + `Fixture.FixRun` pattern.
- `ResolvedIncident` and `Asked` gain an optional argument, as 23.10's marker did, so no fixture is copied.

**Architecture decisions:**
- AD-6 / AD-30: the draft is a bridge turn with a code-written SystemNote.
- AD-10 / AD-14: an untrusted, fresh turn.
- AD-11: the rows are the truth, read only.
- AD-15: states, `RequestRefs`; IncidentManager stays the only writer.
- AD-16: the `FixRun` / `FixResult` counts and their meaning (Skipped includes Unreached; an interrupted result; a couldn't-start Resent 0), and the partner-warning kind.
- AD-22: CI mock scenarios; the RC eval.
- AD-25: the online demo.
- AD-28's principle: no false all-clear, so a notice claims no success that the records do not hold.
- AD-29 / AD-33: lanes, contended files; `FixRun`'s one writer is untouched.

No AC contradicts an AD's Rule. No NFR is touched. No spine change (nothing of architectural weight beyond this kind's facts).

**Contended touches (Rule 11; the orchestrator rules them).** At plan time (HEAD `84c447ab`), `origin/OCT-epic22` and `origin/OCT-epic21` have no change on any path below since their merge base, and `origin/OCT-epic35` changes only `Test/Msg/Catalog.cls`, which this story does not touch.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls` (Epic 22):
  - other: the SYSTEMNOTE pin literal (100), and header bullets added (5-25);
  - appended block: the five `TestOutcome*`/`TestNoOutcome` methods and the `Ran` helper at the end of the class.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls` (Epic 22): appended block: `TestDraftRequestCarriesOutcome` at the end of the class; one header bullet.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls` (Epic 22):
  - other: header bullets (2-18);
  - in `TestResolvedDraftSaysTheOrdersWentThrough` (182-210): its `Asked` call, the sentence literal and about 4 assertion lines;
  - `Asked`'s signature and its `ResolvedIncident` call (213, 221);
  - `ResolvedIncident`'s signature plus about 8 lines that add the ending (248-251);
  - appended block: three test methods and one draft-assertion helper at the end of the class.
- `ci/mock/scenarios/A/partner-notice-partial.json`, `partner-notice-rerouted.json`, `partner-notice-paused.json` (Epics 21, 22): new files. `partner-notice-resolved.json` is unchanged.
- Not touched: `Msg/Catalog/Watch.cls` (Epics 22, 35) and `Test/Msg/Catalog.cls` (Epic 35). Ruling item 4's Catalog.cls union concerns 23.10/35.3, not this story.

Not contended: `Fix/Kind/PartnerWarning.cls`. `Fix/PartnerContacts.cls` and `Watch/Summary.cls` are not edited.

**ONLINE-DEMO behaviour:**
- The guide's demo path (Break the feed, Reject the fix, Reroute the failed orders, Warn the partner) ends with one reroute run: the rejected repair has no run, the batch is 50 orders (`Demo.PartnerTrigger` COUNT 50), and the reroute resends all 50 that failed at one item. So the draft's facts carry "Outcome: the 50 affected orders were resent by another route.", and the live model writes the notice from it (inference until the RC eval).
- A guide incident whose repair was approved and went through gets the full-fix line.
- Suspend and resume are refused on the online demo, so the paused line never appears there.
- Nothing new changes production state. There is no new route, setting, table, grant, catalog key or live-event type.
- The notice is still drafted live and approved as exact text before anything goes to the Simulated mailbox.

**Public text and veto items:**
- Public/model-facing text is only the ruled strings (2a lines, the 2b sentence), used verbatim. The mock replies are CI-only.
- Veto items: none (no security, privilege, stored-data shape, guarantee or dependency change).

**CI cost:** shards-11 (`shard:lane-a@Fix`, planned about 1,673 s of units) gains three end-to-end tests. Each is about 20-25 s on the developer machine, so about 60-75 s there and about 2-3 times that on a runner (inference until a run measures them).

## Verification

Run from the epic-23 worktree root. Run one command per call with `timeout: 600000`, sized to finish in about 150 s, and never put two test runs in one message. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`. Use the fresh tag `e23s11i` and the warm tag `e23s11iw`. Write the three scenario files before `ci/warm.sh up`, because a change under `ci/mock` refuses warm runs. At the end, also after a failure, run `ci/warm.sh down` (warm tag), then `ci/iris.sh teardown` with each tag.

**Shared surfaces:**
- the exact `SYSTEMNOTE` (the `PartnerWarning` pin at 100, the `PartnerTurns` literal; the B prompt `partner-notice-draft` must still be its prefix);
- the Facts lines (`TestFacts`: unchanged for incidents with no Outcome);
- the `Asked` / `ResolvedIncident` helper signatures (callers at 58, 75, 109, 132, 167 and 185 keep working with the defaults);
- the mock scenario set (`ci/mock/test/scenarios.test.mjs` validity; no count pins it).

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e23s11iw ci/warm.sh up`. Re-up (`down`, then `up`, one call each) after any change to `Fix/Kind/PartnerWarning.cls` or `ci/mock/**`, so the production's jobs and the mock hold the new code. Then run `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23s11iw ci/iris.sh class <spec>`, one call each:
  - `OcuTalon.Test.Fix.PartnerWarning`
  - `OcuTalon.Test.Fix.PartnerDraft`
  - `OcuTalon.Test.Fix.PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough`
  - `OcuTalon.Test.Fix.PartnerTurns:TestPartialFixDraft`
  - `OcuTalon.Test.Fix.PartnerTurns:TestReroutedDraft`
  - `OcuTalon.Test.Fix.PartnerTurns:TestPausedDraft`

  Expected: each prints `CLASS ... passed`.
- (loop) `bash docker/tests/test-mock.sh` -- expected: pass (the new scenarios are valid).
- (once) On the warm stack, one call each: `OcuTalon.Test.Fix.PartnerTurns:TestAskedTurnRaisesWithinBounds`, `:TestApprovedNoticeIsSentByteForByte`, `:TestDemoModeOffKeepsTheNotice`, `:TestInjectedTurn`, `:TestSecondSessionAsks` -- expected: passed (the helper change keeps them green).
- (once) `OCUTALON_RUN_TAG=e23s11i ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns:TestReroutedDraft` on a fresh stack -- expected: passed (the production's jobs run the new `Facts`).
- (once) `ci/checks.sh` is too long for one call, so run each script of `CHECK_SCRIPTS` in `ci/units.sh` as `bash docker/tests/test-<name>.sh`, one per call: boundaries, storage, class-rules, ci-config, ci-changes, compose-file, pinned-sources, after-start, healthcheck, lib-live, bootstrap, demo-path-gate, ci-warm, probe, install-script, readme, eval-set, online-host, online-load, upgrade-harness, rehearsal, release-checklist, release-notes, release-sequence, redact-shapes, cpf, bridge-example, bridge-guide, triage-heartbeat, eval-personas, heartbeat-overview, mcp-notices -- expected: each passes.
- No web source or web test changes, so `npm --prefix web test` is not required. If implement touches any `web/` file, add it as a (once) line and run the WHOLE suite.
- Left to CI: the shards (shards-11 runs `shard:lane-a@Fix`), the browser units, `live:demo-path` and the lead's fresh-environment check, forward and `--reverse`.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- AC1: the full-fix condition also requires FailedAgain > 0 (the line never given) -> `PartnerWarning:TestOutcomeFullFix`.
- AC2: R computed as FailedAgain + Skipped instead of N - A -> `TestOutcomePartialFix` (the Partial by count row).
- AC3: the reroute line built with the target name, or the Resent = N check dropped -> `TestOutcomeReroute`.
- AC4: the failed-item check dropped from the suspend case -> `TestOutcomeSuspend`.
- AC5: the single-run rule dropped (the last run used) -> `TestNoOutcome` (Several runs row).
- AC6: `SYSTEMNOTE` keeping 23.10's sentence -> the SYSTEMNOTE pin (`TestContract`) and `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough`.
- AC7: `Facts` without the Outcome line -> `PartnerTurns:TestReroutedDraft` (the logged draft request) and `PartnerDraft:TestDraftRequestCarriesOutcome`. Also `partner-notice-rerouted`'s reply given "They went through." -> `TestReroutedDraft`.

Recorded mutations (Rule 19; each applied, observed red, reverted from a backup, tree byte-identical):
- mutation: AC1: the full-fix condition requires FailedAgain > 0 instead of = 0 -> `PartnerWarning:TestOutcomeFullFix` red ("the full-fix line", "Facts holds it right after the state line")
- mutation: AC2: R computed as FailedAgain + Skipped instead of N - A -> `PartnerWarning:TestOutcomePartialFix` red (the Partial by count row)
- mutation: AC3: the reroute's Resent = N check dropped -> `PartnerWarning:TestOutcomeReroute` red ("a reroute that left two out gives no line")
- mutation: AC4: the failed-item check dropped from the suspend case -> `PartnerWarning:TestOutcomeSuspend` red ("a suspend of an item that did not fail gives no line")
- mutation: AC5: the single-run rule dropped (runs < 1 instead of runs '= 1, the last run used) -> `PartnerWarning:TestNoOutcome` red (the "a full fix and then a suspend" row)
- mutation: AC5: the partner_warning skip (the MOVES filter) dropped -> `PartnerWarning:TestOutcomeFullFix` red ("a notice sent after the fix does not count as a second run")
- mutation: AC5: the incident-ownership check of a request dropped -> `PartnerWarning:TestNoOutcome` red ("the full-fix request of another incident")
- mutation: AC5: the Total-above-Count guard dropped -> `PartnerWarning:TestNoOutcome` red ("a Total above Count with Completed below it"); the Completed-above-Count guard dropped -> `TestNoOutcome` red ("a reroute with a Completed above Count")
- mutation: AC6: `SYSTEMNOTE` keeping 23.10's sentence -> `PartnerWarning:TestContract` red (the SYSTEMNOTE pin) and `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough` red ("with the ruled sentence for an ending"), on a re-upped warm stack
- mutation: AC7: `Facts` without the Outcome line -> `PartnerDraft:TestDraftRequestCarriesOutcome` red and `PartnerTurns:TestReroutedDraft` red ("and the Outcome line ...", "and no other Outcome line"), on a re-upped warm stack
- mutation: AC7: `partner-notice-rerouted`'s reply given "They went through." -> `PartnerTurns:TestReroutedDraft` red ("the notice says the orders went through exactly when the incident was fixed in full"), on a re-upped warm stack

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** `PartnerWarning.Outcome(incident)` builds the one ruled Outcome line (or "") from the incident's own records and `Facts` appends it after the state line; `SYSTEMNOTE` carries the ruled 2b sentence with a `{noun}` token, `PartnerWarning.SystemNote(incident)` fills it with `Watch.Notice.Noun(incident).other`, and `IncidentManager.DraftRequest` uses the kind's `SystemNote(incident)` when the class defines it. The "Failed item" line is unchanged. DW-1165 closed by AC1-AC7.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls`: `Outcome`, `SystemNote`, the Facts line, the SYSTEMNOTE text, the class doc.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`: the one-line `DraftRequest` extension.
- `ci/mock/scenarios/A/partner-notice-{partial,rerouted,paused}.json`: the three new marker scenarios.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls`: the SYSTEMNOTE pin, six new tests (`TestOutcome*`, `TestNoOutcome`, `TestOutcomeUsesTheItemNoun`) and the `Ran`, `Link`, `Resolved`, `Counts`, `OutcomeOf`, `FactsOf` helpers.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls`: `TestDraftRequestCarriesOutcome`; `TestDraftRequest` compares with the rendered `SystemNote`.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls`: `Asked` / `ResolvedIncident` take an `ending`; the 23.10 test is the full-fix case; `TestPartialFixDraft`, `TestReroutedDraft`, `TestPausedDraft`, `AssertEnding`; `Warnings` filters `partner_warning` requests; `Fixtures` is cleaned after each test.

**Review.** 19 findings: patches applied 4 (all added test rows for `Outcome` branches no test pinned: the partner_warning skip, the Total and Completed above Count guards, a request of another incident, a ref with no row, unparsable and non-string suspend parameters, a fix with one failed again, a reroute with Completed above Count); deferred 1 (the model-supplied noun entering the SystemNote, unverified medium); rejected 14 with reasons in the triage log. Follow-up review recommended: false.

**Verification.** `(loop)`: `PartnerWarning`, `PartnerDraft`, `PartnerTurns` x4 cases and `docker/tests/test-mock.sh` passed on the warm stack (`PartnerWarning` again after the review patches). `(once)`: the five other `PartnerTurns` methods passed warm; `TestReroutedDraft` passed on a fresh stack; all 32 `CHECK_SCRIPTS` scripts passed (`eval-set` 210 s, `release-sequence` 235 s and `online-host` 113 s needed a longer call than the 150 s target). Mutations demonstrated for AC1-AC7 and for the four review-added rows (see Verification); each reverted byte-identical. No `web/` file changed. Warm stack and tags torn down.

**Residual risks.** Model-facing wording is proven only as far as what the code sends; the Planner's RC-eval items (full fix, reroute-ended) remain. The deferred noun finding.
