---
title: 'The incident notice carries the dry run and one approval request'
type: 'feature'
created: '2026-10-27'
status: 'done'
baseline_revision: '6450a3318b57b88c470cd3f12d9f0f5dc5290bde'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Since Story 5.8, a usable data-format diagnosis (fix kind `repair_resend`, parameters checked by 7.1's kind) is stored and never noticed. Story 7.1 built the dry run that `FixExecutor` answers, but nothing asks for it. Nothing raises the approval request, sends the with-fix notice, or turns a rejection or an expiry into an answered status. So UJ-1 stops at the diagnosis.

**Approach:** At the notice step, `IncidentManager` asks `FixExecutor` for the dry run with `Fix.Msg.DryRun`. When the answer comes back, it calls `OcuTalon.Bridge.Approval.Raise` once. The row holds the fixed targets, the kind and its validated parameters, the `DryRun` JSON, the owner, `ResultTarget` and the incident's trace session. `IncidentManager` then appends the Ref to `Incident.RequestRefs` and moves the incident to `awaiting_approval`. It sends one kind-`incident` `incident.withFix` notification per recipient, carrying the `ApprovalRef` and the dry-run slots. A rejected or expired outcome moves the incident through AD-15's table and sends an `answered` notification. To hold the fix's kind, parameters and targets, the bridge's `ApprovalRequest` row gains three stored properties (V1). **Scope note:** this spec covers the proposed cut of the story. Its fifth group of criteria (later requests in the same incident) goes to a sibling story (see `## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The incident notice now proposes the fix. For a usable data-format diagnosis, `IncidentManager` asks `FixExecutor` for the dry run (`Fix.Msg.DryRun`, asynchronous, key `dryrun`, in the incident's trace session) and, when it answers, raises one `fix` approval request (`Approval.Raise`, `$TLevel` 0) holding the kind, the parameters, the targets and the dry run. It appends the Ref to `RequestRefs`, saves `awaiting_approval` with `NoticedAt`, and sends the `incident.withFix` notification (with `field`, `before`, `after` and `resendCount`) to each recipient. A refused dry run, nothing to resend, a failed `Raise` or a failed ask takes the no-fix notice (V2). A save that fails after `Raise` cancels the request. An accepted rejected or expired outcome sends an `answered` notification. `ApprovalRequest` gains `FixKind`, `FixParameters` and `FixTargets` (V1). The later-request flow is Story 7.6's.

**Files changed (under `src/`, `OcuTalon/` is `src/ocutalon/cls/OcuTalon/`):**
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls`: three stored properties, Storage values 21-23.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: `Validate` requires the three for `fix` and refuses them for `tool_call`; `Raise` doc.
- `OcuTalon/Watch/IncidentManager.cls`: `Propose`, `Proposed`, `NoFix`, `Unproposed`, the seams `SendDryRun`, `RaiseRequest`, `CancelRequest`, `AnswerNotice`; `Deliver` returns its status; `Event`/`Apply`/`Outcome` carry the answered notification.
- `OcuTalon/Watch/Notice.cls`: `WithFixSlots` takes the dry run; `Slots` takes a key.
- Tests: new `OcuTalon/Test/Fix/Raise.cls`; edited `Test/Watch/{Case,Closing,Diagnose,IncidentProbe,Incidents,Lifecycle,NoticeText,Notices,Tell}.cls`, `Test/Fix/DryRun.cls`, `Test/Bridge/Approval.cls`, `Test/Data/Tables.cls`.

**Review.** 4 layers, 34 findings (high 0, medium 0, low 26, false 8). Patches applied: 1 (a stale comment in `Test/Fix/Raise.cls`). Deferred: none. Rejected: 33, each with its recorded reason in the Review Triage Log. Follow-up review recommended: false (no high, no medium patched).

**Verification performed.** See the Task 0 measurements, the mutations and the results above: all `(loop)` and `(once)` commands passed in the implement pass (warm: 6 classes; fresh: 8 classes; shard lane-a parts 1-4; shard lane-b; `live storage-roundtrip`; `bash ci/checks.sh`). After the review patch (a comment), `Test.Fix.Raise` passed again on a fresh stack (61.6 s) and `bash ci/checks.sh` passed. Both throwaways were torn down.

**Residual risks.** (1) A lost dry-run answer leaves the incident unnoticed until Story 7.5's sweep. (2) A thrown error between `Raise` and the incident's save leaves an unlisted pending request until it expires. (3) The OCUORDERS snapshot checks in `Test.Fix.Raise` cannot fail until Story 7.3 gives `FixExecutor` an `Execute`; the Execute-header check is the live pin. (4) `TestTwoSessions` and `TestInstanceShared` assert their negatives inside the mock's 6 s delay. (5) Slot A holds this story's classes, loaded by the implement stage (its first load used the wrong base directory and was reloaded from this worktree).

**Footprint extensions (outside `Fix/**`, `Test/Fix/**`, `src/bridge/**`):** `OcuTalon/Watch/IncidentManager.cls`, `OcuTalon/Watch/Notice.cls`, `OcuTalon/Test/Watch/{Case,Closing,Diagnose,IncidentProbe,Incidents,Lifecycle,NoticeText,Notices,Tell}.cls`, `OcuTalon/Test/Bridge/Approval.cls`, `OcuTalon/Test/Data/Tables.cls`. No contended path was touched.
