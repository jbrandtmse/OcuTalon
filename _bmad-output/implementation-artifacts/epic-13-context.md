# Epic 13 Context: Any production can use the bridge

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the bridge is a reusable product, not an OcuTalon internal. A production developer with no OcuTalon installed loads the bridge's classes without IPM, runs its installer, configures it purely through production settings and runs an example production whose own agent, tools, decisions, agent steps and approvals show up in Visual Trace. The bridge developer guide (`docs/bridge-guide.md`) documents all of it, and CI runs its commands verbatim on a clean instance. Stories 13.1 to 13.3 are done. The epic is re-opened for Story 13.4, a fix-forward from a bare-container run of the guide: the guide and the security overview must say exactly what is audited, and the guide's steps must match what a reader actually sees. 13.4 is in 1.0.0's scope and must merge before rc1, because every "this release" statement has to be true when rc1 is cut.

## Stories

- Story 13.1: The example production makes its own decision through the bridge (done)
- Story 13.2: The example's own tools wait for approval when they are risky (done)
- Story 13.3: The bridge developer guide, proved on a clean instance (done)
- Story 13.4: The guide and the overview say exactly what is audited, and the guide's gaps are closed

## Requirements & Constraints

- **What "audited" means.** In the overview, "audited" means an entry in the IRIS audit log (source `OcuTalon`). The bridge writes one only for `Approval`, `Action` (replay, executor, partner trigger), `Pairing` and `Settings`. A plain tool call is recorded as an agent step of its decision, not as an audit entry. The old U-229 clause "each tool call is still audited" is therefore false.
- **The amended U-229 sentence (13.4).** It must read exactly the same in three places: the overview's approval-and-audit paragraph, the guide's tool-classification reference and the `U229=` pin (and its negative fixture) in `docker/tests/test-bridge-guide.sh`. The text is: "In this release, changing this setting writes no OcuTalon audit entry. Each tool call is recorded as a step of its decision, and an approval and an approved call's run each write an audit entry." Check each clause against the code first, with file:line evidence in the spec's Design Notes. If any clause turns out false, stop and send a clarification. Never reword it.
- **The guide's gaps to close (13.4):**
  - The `AgentAllowList` default cell says the default is empty, which refuses every class.
  - Step 6 gives the real route to a trace: the message viewer row, then the Trace tab, then View Full Trace, or the Session number. The header id is not a link. The trace list also shows the bridge timer's `AlarmRequest` to `Ens.Alarm`.
  - The reference states Decide's rule: for a `user` request, an `ignore` or `digest` decision becomes `tellnow`, with the reason shown in the trace ("The outcome was changed because a message the user writes is always answered."). This matters because the run steps say an ignore decision goes to no output.
  - The Govern section adds one sentence: after the two settings rows are written, the Portal's notice that Decide needs an update can be ignored, because the settings are read live.
  - Find out whether a bare-bridge production needs `Approval.Reconcile` after a production start. Today only OcuTalon's own install calls it. If it is needed, add one sentence telling bridge users to run it. If not, the guide says nothing. Either way, record the finding and its evidence in Design Notes.
- **Footprint (13.4):** only `docs/bridge-guide.md`, the overview's single U-229 sentence and `docker/tests/test-bridge-guide.sh`. Runnable guide blocks that reach a held call, and any self re-arm by the bridge at production start, go to the ledger with `owner=burndown` and the note "first daily release after 1.0.0".
- **Must stay green:** every changed guide block still passes the standalone-bridge job's block-by-block run, `test-bridge-guide.sh` passes, the overview's generated lists and `overviewdoc` pins pass, every other "this release" statement in both files stays true, and CI is green on every workflow.
- **Public text:** the guide stays plain English, with no keys, local paths, instance names or private infrastructure.

## Technical Decisions

- **The guide is executable.** Each install or governance command block is marked `<!-- guide-run: <name> -->` on the line just before an `objectscript` fence. Each block has exactly one `Set sc=` command.
  - The block names are `load`, `install`, `provider`, `start` and `send` (the install section, in that order), plus `tool-classification` and `approval-role`.
  - `release/standalone-bridge.sh` pulls the blocks out of the guide at run time and runs them verbatim in a throwaway namespace `OCUBRIDGE`. It never copies a guide line into the script.
  - The `blocks` rule in `test-bridge-guide.sh` catches drift between the guide and the script.
  - Changing a block's text changes what CI runs. Prose edits around a block are safe.
- **Settings are read live.** `ToolClassification` and `ApprovalRole` are System Default Settings rows read through `Ext.Accessor.ValueFor`, so no restart is needed. A value put in the production definition would hide the row.
  - The classification gate checks in this order: what the class's code declares, then the setting, then `ClassificationClass`.
  - Unclassified counts as risky. On an `untrusted` or tainted turn only read-only tools run.
- **Audit and redaction** go only through `OcuTalon.Bridge.Audit.Record(type, data)` and `OcuTalon.Bridge.Redact`. Every agent step goes to `AgentSteps`. Tokens and cost are counted per turn and per decision, never per step.
- **Approvals:** `Approval.Raise` starts an `ApprovalHold` through `ApprovalStartIn`. The request's state changes only through the `Approval` API (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`), and every change is audited.
  - The startup reconciler re-arms a pending row whose waiter process is gone and cancels orphaned Workflow tasks. This is the behaviour 13.4's `Reconcile` question is about.
  - `Answer` checks roles through `GetUserRecursedRoleSet`, which needs `%Admin_Secure:USE`. The example uses role `ExampleApprovers` and answers with channel `system`.
- **Timeouts:** the guide's `provider` block writes `Timeouts.Derive(60).http_config` into the inline `ProviderConfig`. Story 13.1's 12-second timer row must keep falling back with `timeout`.
- **Proof run:** a full `release/standalone-bridge.sh` run takes about 4 to 6 minutes. Keep test runs short and split long ones.

## Cross-Story Dependencies

- 13.4 corrects text that 13.3 wrote (the guide, the U-229 sentence and its pins) and documents behaviour that 13.1 and 13.2 built. It changes no bridge or example class.
- Epic 14 owns `docs/security-overview.md`. 13.4 may change only the one U-229 sentence in it and must leave its generated regions alone.
- Lane B's Story 31.3 links to the guide's stable path `docs/bridge-guide.md`, so the path must not change.
- The release checklist's `bridge-guide` row passes only when `test-bridge-guide.sh` passes. rc1 is gated on 13.4 merging.
