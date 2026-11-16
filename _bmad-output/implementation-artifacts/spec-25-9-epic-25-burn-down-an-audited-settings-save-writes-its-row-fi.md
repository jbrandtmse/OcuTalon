---
title: "Story 25.9: Epic 25 burn-down: an audited Settings save writes its row first and its audit entry last, in one transaction"
type: 'bugfix'
created: '2026-11-15'
status: 'done'
baseline_revision: '326853489a3c1c19eac21188bb0facdfb1b19f16'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Every audited Settings save in `OcuTalon.Core.SettingsOps` writes its `Settings` audit entry before its row. IRIS writes audit records outside the transaction (`%SYS.Audit` suspends it with `$zu(139,2)`), so `TROLLBACK` never removes an entry. A row write that fails after the audit leaves an entry for a change that never happened (DW-1392). Separately, AD-13 does not say that the web process may read Settings tables directly, which `SettingsOps.Values` and `PartnerContact.List()` already do (DW-1395).

**Approach:** Each in-scope save opens one transaction, writes its rows first, and then calls one new shared helper. The helper writes the audit entries and commits. If an entry can't be written, it rolls the rows back. A save whose rows live outside the transaction (the email section's credential, item rows and OAuth client) writes them first and audits them afterwards, and an audit failure puts them back, as the bridge values already do. Each save keeps its existing outcomes and messages. The plan has already written the Planner's AD-19 and AD-13 sentences into the spine, word for word. It also reconciled the Story 33.2 text and added this story's AD-33 bullet.

## Boundaries & Constraints

**Always:**
- **Order.** Inside one transaction: (1) write the rows; (2) write the audit entries; (3) if an audit write fails, `TROLLBACK` and report it; (4) only then `TCOMMIT`. A row write that fails rolls back and writes no audit entry.
- **Failure reports.** Use each save's existing outcome and message only: `failed` with `CommandsIn.#MESSAGEFAILED`; `not_audited` with `#MESSAGESECTIONNOTAUDITED`, or `#MESSAGENOTAUDITED` for demo mode; `name_taken`; `refused`. The existing log lines stay.
- **Audit content.** From and to values appear only in the IRIS audit log. A partner contact's entry still names only `partnerContact.<Ref>` and which fields changed. No value appears in a result, a log line or test output.
- **Files.** Lane A changes only the files in AD-33's Story 25.9 bullet, which are the Code Map's files. The ownership tables don't change.
- **Tests.** Every added or changed test creates and removes its own state, uses its own session Ref, and passes in either order. Each AC's pinning test has a demonstrated mutation in `## Verification`.
- **Rule 14.** Comments state the contract and never the history. Correct every "audit entry first" doc comment in place.

**Never:**
- No new user-visible text, `Parameter MESSAGE*`, outcome, route, role, reply shape, Data class or index.
- Do not edit `Watch/*`, `Fix/*` or `Live/Payload/*`. Stories 23.13 and 24.4a hold them.
- Do not take DW-1393 or DW-1394 (Story 23.13).
- Do not change the bridge-value saves (`SaveBridge`, `SaveModels` and their put-backs). They already write before they audit.
- Never touch `ocutalon-aihub-test`, any `ocupilot*` container, `iris-community-edition`, a dev slot or another lane's stacks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Save succeeds | A valid change, with a real `Bridge.Audit.Record` (probe answer `audit`=`record`) | The row changes and one entry per change is written, after the row. Same outcome and message as today | None |
| Row write fails | The probe's `apply`/`applyAt` answer is `error`, the new `SaveRow` seam answers `error`, or a real failure (a partner `Productions` value over its maximum length) | No entry for the test's session in the real IRIS audit log. Every row as before. `$TLevel` 0 | `failed`, or `name_taken` for a webhook name taken at save |
| Audit write fails | The probe's `audit`/`auditAt` answer is `error`, or a real `Record` refusal (no `ActingUser`) | Every row of the save as before, read fresh from storage | `not_audited`, with its existing message |
| Email: an outside write fails | The email probe's `credential`, `sds` or `start` answer fails | The keys and outside rows are put back. No entry for an outside value is written | `failed` (as today) |
| Email: an outside value's audit fails | The probe's `auditAt` lands on the first entry for an outside value (`email.incoming`, `outgoing`, `user`, `credential` or `clientSecret`) | Everything is put back as on the failure path. The key put-backs are audited as today | `not_audited` |
| Nothing changed | A save equal to the stored values | No transaction, no row write and no entry | `done` (as today) |

</intent-contract>

## Code Map

Line numbers are at `baseline_revision`.

- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (Lane B). The one product file. `WriteAudit` (L282) is the audit seam and `Apply` (L289) is the guarded key write. Sites in scope, each currently "audit, then row":
  - S1 `SwitchDemo` L231-256 (SetDemoMode, also reached from `Core.Admin.SetDemoMode`). Audit, then `Apply`, with no transaction, then `RunStep`.
  - S2 `WriteKeys` L362-391 (persona via `WritePersona` L352, which SetPersona and an approved proposal `Outcome` L637 use; heartbeat via `SaveHeartbeat` L393). The audit comes before `TSTART`.
  - S3 `SaveProduct` L1142-1180 (the step 2 sections; on-call through `SaveOnCall` L2552). Audit then `Apply` per change, inside `TSTART`.
  - S4 `SaveEmail` L1519-1658. Key loop L1576-1603: audit then `Apply` for every `todo` entry, including entries with `key ""` whose outside writes (credential, EmailIn/EmailOut rows, OAuth client) run after `TCOMMIT`, at L1608-1629.
  - S5 `RecordOAuth` L1690-1701. The `email.oauthOwned` entry, then `todo` push, then `Apply`, with no transaction. Its `email.oauthApp` entry already follows the IRIS call.
  - S6 `ForgetClient` L1661-1668. Audit, then `Apply("email.clientId", "")`.
  - S7 `CreateWebhook` L2301-2342. Audit, then `row.%Save()`. A failed save writes a compensating "undone" entry (L2331).
  - S8 `SetWebhookSecret` L2345-2373. Audit, then `row.%Save()`.
  - S9 `WritePartner` L3027-3075 (Story 24.2). Audit, then insert, update or delete, inside `TSTART`.
  - Class doc to correct: L4-6, L10, L16, L59-60, L104-105, L120-124, L348, L359, L1140-1141, L2551, L3024-3026.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls` (Lane B test). Its switches live in `^OcuTalonTest("SettingsOpsProbe","answer",<seam>)`:
  - `WriteAudit` override L112: answers `audit` (`error`, `throw`, `record`) and `auditAt`, counted in `^||OcuTalonSettingsOpsProbe("n","audit")`. Its `clash` hook stores a competing webhook during the audit write (L118).
  - `Apply` override L164: answers `apply` (`error`, `second`) and `applyAt`.
  - It records calls in `^OcuTalonTest(...,"calls",n)`, an ordinary global, which a `TROLLBACK` now undoes when the audit runs inside the transaction. Only the `^||` counters survive a rollback.
  - `SettingsEmailProbe.cls` extends it, adds the outside-write switches, and needs no change.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/AuditLog.cls` (read-only helper). `Now()` L23. `Entries(since, source, type, event, marker, username)` L30 reads `%SYS.Audit` by `UTCTimeStamp`, readable at once. `Wait(...)` L61.
- Tests that pin the old order, to update:
  - `Test/Core/SettingsOps.cls` L91-94 (the success table: "the audit came first", `seen` is the old value) and `TestApplyFails` L193 (L204-205).
  - `Test/Core/SettingsHeartbeat.cls` `TestKeyWriteFails` L278 (L294 `Audits()=2`) and `TestAuditFirstAndWithoutText` L223 (L242: it counts `^OcuTalonTest` call records, which are now rolled back).
  - `Test/Core/SettingsWebhooks.cls` `TestNameTakenAtSave` L102: it uses the `clash` hook inside `WriteAudit` and expects the undo entry. Also `TestCreateAuditsFirst` L48.
  - `Test/Core/SettingsPartners.cls` `TestRowWriteFailureRollsBack` L447 (L470 and L484: "the audit write was reached"). It proves the rollback only for the probe's global, never for the real log.
  - `Test/Core/SettingsEmail.cls`: the pinned entry orders at L513, L678, L692, L369, L823 and L834 (L127's order is unchanged), and `TestAllOrNothing` L436.
- Tests that stay valid and that this story extends:
  - `Test/Core/SettingsPersona.cls` `TestAuditFails` L222 and `TestKeyWriteFails` L239.
  - `Test/Core/SettingsSave.cls` `TestAllOrNothingAudit` L231 and `TestAllOrNothingApply` L245.
  - `Test/Core/SettingsOnCall.cls` L318.
  - `Test/Core/SettingsOps.cls` `TestAuditFails` L264 and `TestAuditAccepted` L238.
- Read-only evidence:
  - `irissys/%SYS/Audit.cls` L1585 (`$zu(139,2)`).
  - `src/bridge/cls/OcuTalon/Bridge/Audit.cls` `Record` L91 and `Write` L192.
  - `Data/Setting.cls` `Set` L81 clears only its own process cache before the upsert, so a rollback leaves no stale cached value.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - **Shared helper.** Add one private helper beside `WriteAudit`, for example `Method AuditCommit(level As %Integer, audits As %DynamicArray) As %Status`. It is called inside the caller's open transaction after the rows. It writes each `AuditData` object through `WriteAudit`, in order. On the first failure it rolls back to `level` and returns that status. Otherwise it `TCOMMIT`s and returns OK.
  - **Row seam.** Add one private seam, `SaveRow(row As %Persistent) As %Status`, that returns `row.%Save()`. A test subclass overrides it. Use it for the webhook saves.
  - **Rewrite S1-S9 to "row(s), then `AuditCommit`".** For each site:
    - Compute `from` values before the write.
    - A row failure rolls back and returns its existing outcome, with no entry.
    - An audit failure rolls back and returns `not_audited`.
  - **S1.** `RunStep` runs after the commit, unchanged.
  - **S4.**
    - Inside the transaction: `Apply` the keyed `todo` entries, then `AuditCommit` their entries.
    - Leave the outside writes, `RecordOAuth` and `StartItem` as they are.
    - Then write the outside entries (key `""`) in `todo` order. The first failure takes the existing failure path (OAuth undo, `PutBackEmail`, `ForgetClient`) and answers `not_audited`.
  - **S5.** `Apply` `email.oauthOwned` and `AuditCommit` in one transaction. Push to `todo` only after the commit.
  - **S7.** Drop the compensating "undone" entry: a failed save now writes nothing.
  - **Class doc.** Rewrite every "audit entry first" comment to the new contract.
  - **Rationale:** DW-1392. One helper (Rule 2) carries steps 2-4 of the ruling.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls`:
  - Override `SaveRow`. Answer `saveRow`=`error` returns an error status.
  - Move the `clash` hook from `WriteAudit` into `SaveRow`, so that the competing row is stored just before the save.
  - Document both in the class header.
  - Rationale: the webhook row-failure and name-taken cases need a seam before the row.
- **Test classes** (`Test/Core/SettingsOps.cls`, `SettingsPersona.cls`, `SettingsHeartbeat.cls`, `SettingsSave.cls`, `SettingsOnCall.cls`, `SettingsEmail.cls`, `SettingsWebhooks.cls`, `SettingsPartners.cls`):
  - Update the old-order pins listed in the Code Map to the new order, with accurate names. For example, rename `TestAuditFirstAndWithoutText` and `TestCreateAuditsFirst`.
  - For each site S1-S9, add or extend one row-failure case and one audit-failure case, in that site's existing class:
    - **Row failure:** the probe answers `audit`=`record`, the row write is forced to fail, and the test asserts the outcome and that `AuditLog.Entries(since, "OcuTalon", "Settings", "Settings", <the test's session Ref>)` is empty. It is paired with a control save in the same test whose entry that query does find.
    - **Audit failure:** the test asserts `not_audited` and that every row of the save is as before, read fresh from storage.
  - **Extend, don't copy.** Grow `TestRowWriteFailureRollsBack` for S9: replace "the audit write was reached" with "no audit write and no real entry". Build on `TestAllOrNothingAudit`/`Apply` for S3 and `TestAllOrNothing` for S4.
  - After a rolled-back save, never assert `^OcuTalonTest(...,"calls",n)`. Use the `^||` counters or the real log.
  - S5 and S6 each get a row-failure case in `SettingsEmail.cls` (`applyAt` on the `email.oauthOwned` or `email.clientId` write: no entry for it in the real log). Their audit-failure path is the existing `TestSignInStartUnaudited` and failed-start cases.
  - Rationale: the epic's tests, Rule 19 and Rule 2.
- **Spine.** Done by this plan: the AD-19 reconcile and new bullet, the AD-13 sub-bullet and the AD-33 Story 25.9 bullet. The implement stage only checks them with the grep in Verification. Rationale: DW-1392, DW-1395 and Rule 20.

**Acceptance Criteria:**
- **AC1 (DW-1392; S3).** Given a step 2 section or the on-call section, when the nth row write fails, then the save is `failed`, every key is as before, and the real audit log has no entry for the session. When the nth audit write fails, then it is `not_audited` and every key is as before.
- **AC2 (DW-1392; S9).** Given a partner-contact add or edit, when the row write fails (real `Productions` maximum length), then the save is `failed`, the row is as before, no audit write was attempted, and the real log has no `partnerContact.<Ref>` entry. Given an add, edit or remove, when the audit fails, then it is `not_audited` and the row is as before.
- **AC3 (DW-1392; S2).** Given a persona or heartbeat save (and an approved persona proposal), when a key write fails, then the save is `failed`, the keys are as before and the real log has no entry. When the audit fails, then it is `not_audited` and the keys are as before.
- **AC4 (DW-1392; S1).** Given `SetDemoMode`, when the `demo.mode` write fails, then it is `failed`, there is no entry and the step does not run. When the audit fails, then it is `not_audited` with `#MESSAGENOTAUDITED`, `demo.mode` is as before and the step does not run.
- **AC5 (DW-1392; S7, S8).** Given a webhook create or secret change, when the row save fails (`SaveRow`, or a name taken at save), then the result is `failed` or `name_taken`, there is no row change and no entry (no "undone" entry either). When the audit fails, then it is `not_audited` and the row and hash are as before.
- **AC6 (DW-1392; S4-S6).** Given an email save, when a key or outside write fails, then the save is `failed`, everything is put back, and no entry exists for an outside value that was not kept. When the audit of a key entry fails, then it is `not_audited` and nothing changed. When the audit of an outside value fails, then it is `not_audited` and everything is put back. `RecordOAuth` and `ForgetClient` write their key before their entry.
- **AC7 (DW-1392, DW-1395).** Given the spine, when it is grepped, then AD-19 holds the ruling's sentence verbatim, the Story 33.2 text reads "row and then its `Settings` audit entry" with its `[AMENDED 2026-11-15, Story 25.9 …]` marker, AD-13 holds the DW-1395 sentence verbatim, and AD-33 holds the Story 25.9 bullet.
- **AC8.** Given the diff, when it is inspected, then no `Parameter MESSAGE*`, route, role, reply shape or Data class changed, and the existing Web API and Settings browser specs pass unchanged.

## Spec Change Log

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 29 findings (blind 12, edge 10, verification-gap 7; the intent-alignment audit is descriptive and files none), grouped by root cause into the 13 rows below — high 0, medium 1, low 10, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` Entries written before a refused one stay in the real log (SaveProduct, the keyed part of SaveEmail), blind 1 and edge 1, 8 and 9 — IRIS writes audit records outside the transaction, so no code can take one back; `Record`'s refusals depend on the command, not the entry, so in practice the first entry fails or none does. The Design Notes record this as wontfix-theoretical (it becomes real only if `Record` could refuse one entry of a save and accept another).
  - `[low]` `[patch]` Email: outside entries written before a refused one stay beside the put-back (blind 2, edge 2, blind 3) — same root cause as the row above; the class comment "so that a value put back has no entry" overclaimed, so it now says that entries written before a refused one stand. No test: the case is wontfix-theoretical.
  - `[false]` `[reject]` A failed outside-entry audit after `StartItem` leaves the production running the new values (edge 3) — `PutBackEmail` ends with `StartItem()`, so the items are restarted on the put-back values.
  - `[false]` `[reject]` Per-process Setting cache holds a rolled-back value (edge 4) — `Data.Setting.Get` caches only public keys, which `Set` refuses to write, and `Set` clears its own entry; no key written here is cached.
  - `[low]` `[reject]` `AuditCommit` with `$TLevel` at or under `level`, `CreateWebhook`'s `NameTaken` throwing, `WriteKeys` receiving a thrown audit write (edge 5, 6, 7; blind 5) — no reachable path: the callee that rolls back bare does not exist, `NameTaken` is an index read the old code also ran outside any `Try`, and a thrown audit write is rolled back by `AuditCommit` and rethrown as before (`TestThrown`, heartbeat).
  - `[low]` `[reject]` Error logging twice and an unused `outcome` in `RecordOAuth` and `ForgetClient` (blind 4) — cosmetic; the existing log lines and outcomes stay as the spec requires.
  - `[low]` `[reject]` Missing mutation for `SetWebhookSecret` and for on-call's own test, hard-coded `applyAt` counts, probe `SaveRow` doc (blind 6, 7, 11; verification-gap other) — Rule 19 asks one demonstrated mutation per AC; AC1 goes through `SaveProduct` and AC5 through `CreateWebhook`; the counts' comment names the write order, and the class header documents the answers.
  - `[low]` `[reject]` `TestNameTakenAtSave` no longer models a committed competing row (blind 8) — the spec moves the `clash` hook into `SaveRow` on purpose; the name check before the rollback is recorded in the notes.
  - `[low]` `[reject]` The old-wording grep now expects 1 (blind 9) — the AD-19 sentence has its own grep (expected 1); stale `Auto Run Result` status (blind 10) is closed by this finalize.
  - `[medium]` `[patch]` `RecordOAuth` and `ForgetClient` have no refused-entry case (verification-gap 1) — added `TestOAuthOwnedAuditFails` and `TestForgetClientAuditFails` in `SettingsEmail`, each with a control, and demonstrated a mutation for each.
  - `[low]` `[patch]` `StepRan()` is never asserted true (verification-gap 2) — the control save of `TestApplyFails` asserts the step ran; mutation recorded under AC4.
  - `[low]` `[patch]` Two rollback-mutation reds in `SettingsWebhooks` are cascades (verification-gap other) — the record names them as such.
  - `[low]` `[reject]` AC7 and AC8 without a pinning mutation, S4 outgoing and client-secret entry positions, the 20 ms mark wait (verification-gap other) — AC7's mutation is recorded; AC8 is "no new test" by the spec; the other positions run the same code path as the three exercised ones; no false-green path was found.
  - `[low]` `[reject]` Intent-alignment: reading R1 implemented, no divergence of the surface (descriptive) — no action.

## Design Notes

- **Governing ADs (Rule 6):**
  - AD-19: the audited save order, as amended by this story, plus the bridge-value put-back rule that S4's outside writes follow.
  - AD-17: `Bridge.Audit` is the one writer. Tests read the real log back.
  - AD-13: the DW-1395 clarification.
  - AD-1: `SettingsOps` is the one writer, in the production job.
  - AD-29 and AD-33: the Lane B files under this story's bullet.
  - AD-22: real-runtime tests on throwaways.
- **Grep sites** (`rg 'Audit\)\.Record|Security\.Audit|WriteAudit\(|\.\.Audit\(' src` outside `Test/`, and every `TSTART`). In scope: S1-S9 above. Out of scope:
  - `SettingsOps.SaveBridge` L1183 and `PutBack` L1233, `SaveModels` L1250 and `PutBackModels` L1336, `PutBackEmail` L2044, and `RecordOAuth`'s `email.oauthApp` entry (L1693): already row-first. Each writes, then audits, and a failure puts back with an entry.
  - `SettingsOps.SignIn` L1797 and L1805: an unaudited tracking write of `email.oauthOwned` after a failed `RecordOAuth` (Story 21.3). It is not an audit-then-row write, and this story keeps it.
  - `Install/Step/Roles.cls` `Assign` L77-112 (`SaveRoles`): already row-first. It switches the role, then audits, and switches it back on an audit failure.
  - `Mcp/Ops.cls` `Register` L269, `Unregister` L306, `Classify` L419, `SaveSource` L448, `RemoveRow` L484 and `ClearRow` L675: already row-first (MCP and Tool entries, Lane A).
  - `Core/SessionOps.cls` L135, L187 and L521: Pairing entries, not a Settings save.
  - `Data/Webhook.cls` `RecordRejection` L248: a rate-capped Action entry for a rejected request, not a save.
  - `Demo/PartnerTrigger.cls` L62: an Action entry for a demo press, with no row.
  - `Mcp/Proxy.cls` L269: an MCP call entry, not a save.
  - `src/bridge/.../Approval.cls` L619 and `Replay.cls` L259: Approval and Action entries for request states, not Settings saves (Lane A bridge).
  - `Watch/Paging.cls` L387 and its callers `Watch/IncidentManager.cls` L2031 and L2104: Action entries for pages, not Settings saves; also contended (23.13 / 24.4a).
  - `Fix/Executor.cls` L831, `Fix/Run.cls` L429 and `Fix/Kind/Email.cls` L318: Action entries for fixes, not Settings saves; also contended (23.13 / 24.4a).
  - `TSTART` blocks with no audit write: `Watch/SettingHistory.cls` L108 and `Watch/IncidentManager.cls` L435, L577, L699, L909 and L1844 (contended, 23.13 / 24.4a); `Live/Publish.cls` L99 (contended, 23.13 / 24.4a); `Channel/Email/OAuth.cls` L256 and L379; `Channel/Operation.cls` L44; `Core/Allowance.cls` L101; `Install/Registry.cls` L98; `Core/SessionOps.cls` L203.
- **Rule 2:**
  - `AuditCommit` is the one shared piece: every site's audit-and-commit, which today is copied nine times.
  - `SaveRow` follows `WriteAudit`'s seam pattern.
  - The tests extend each site's existing class and probe. `TestRowWriteFailureRollsBack` grows rather than being copied.
- **Integration (Rule 1):** no new service. `AuditCommit` and `SaveRow` are private to `SettingsOps`. Consumed-by: none outside the class. Consumes: `Bridge.Audit.Record` (AD-17) and `Data.Setting`, `PartnerContact` and `Webhook`. The observable effect is pinned through the real audit log and real rows.
- **Decided in-stage:**
  - **Outside writes in S4.** The email credential, the EmailIn/EmailOut rows and the OAuth client cannot sit in the key transaction, because the production update runs after them. So they follow AD-19's bridge-value order: write, then audit, then put back on a failed audit. This is the spine's existing rule, not an exception to the ruling.
  - **Where S4's outside entries go.** They are written after `StartItem`, so that a failed start never leaves an entry for an outside value that was put back. The entry order within one email save therefore becomes: keys, then `RecordOAuth`'s entries, then outside values. The pins at `SettingsEmail.cls` L513, L678, L692, L369, L823 and L834 change accordingly.
  - **Partial outside-audit failure.** `Record`'s refusals depend on the command, not the entry, so in practice the first outside entry fails or none does. A failure after an earlier outside entry was written would leave that entry beside the put-back. That case is wontfix-theoretical: it becomes real only if `Record` could refuse one entry of a save and accept another.
  - **S1 is in scope despite having no transaction.** The ruling covers every audited Settings save, and a transaction around one row costs nothing.
  - **Tests for audit failures.** They use the probe's `audit`=`error` (or `Record`'s real refusal), because a failure of IRIS's own audit write can't be forced on a shared instance without turning auditing off.
  - **The working tree was dirty at step 1.** The only change was the lead's own `stage_spawned` and `epic_context_compiled` lines in `cycle-log-epic-25.md`, so planning went on.
  - **Spine lint.** The spine has no `.memlog.md`, so no memlog append was made. `lint_spine.py` gives the same result as at HEAD: `ok` false, from 12 low `placeholder` findings for literal tokens such as `{n}`. None of them is new.
- **Not edited:** `epics.md` L10794 (Story 39.2, done) says the heartbeat's audit entry is written first, then the keys. It is another epic's story block (Rule 11), and AD-19's amendment now governs. Recorded for the lead.
- **Ledger inbox:** DW-1392 is AC1-AC7. DW-1395 is AC7. None is declined.

## Verification

**Runtime:** Lane A throwaways only. No slot and no MCP target is needed. Prefix every `ci/iris.sh` call with:

`OCUTALON_LOCK_DIR=<the lane-a lock folder under .worktrees/.coordination/locks> OCUTALON_TEST_WEB_PORT=52801 OCUTALON_RUN_TAG=e25s9<x> OCUTALON_LOCK_OWNER='epic=25 stage=<stage>'`

- The warm tag is the stage tag followed by `w`, for example `e25s9iw`. Run `ci/warm.sh up` once, then each class as `OCUTALON_WARM=1 ci/iris.sh class <Class>`, one per call, and `ci/warm.sh down` at the end, also after a failure.
- Every call runs in the foreground with `timeout: 600000`.
- Test classes run in the `lane-b` shard (`Core` is in the piece `lane-b@Contract,Core,Data,Live`; `Web` is in `lane-b@rest`).

**Commands:**
- (loop) `OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Core.<C>`, one call per class, for C = `SettingsOps`, `SettingsPersona`, `SettingsHeartbeat`, `SettingsSave`, `SettingsOnCall`, `SettingsEmail`, `SettingsWebhooks` and `SettingsPartners`. Expected: each class passes, with no FAIL or SKIP.
- (loop) `grep -c "An audited save writes its row and then its audit entry inside one transaction" _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, and the same for the DW-1395 sentence and for `Story 25.9 (run by Lane A)`. Expected: 1 each. Also `grep -c "audit entry and then its row" _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, expected 1: the only match is the `[AMENDED 2026-11-15, Story 25.9 ...]` marker of the Story 33.2 text, which quotes the old wording.
- (once) Warm, one call each, for the neighbours that read the same saves: `OcuTalon.Test.Core.SettingsAudit`, `PersonaAnswers`, `Admin`, `CommandsHeartbeat`, `CommandsStep4`, `SettingsModels`, `OcuTalon.Test.Channel.EmailOAuth`, `EmailLive`, and `OcuTalon.Test.Web.PartnerSettingsApi`, `HookSettingsApi`, `PersonaApi`, `OnCallSettingsApi`, `SettingsApi`. Expected: all pass.
- (once) `bash ci/checks.sh`. Expected: every check passes, `test-boundaries` included (no local path in this spec).
- (once) Browser, fresh. Run `ci/iris.sh build` first. Then run the `live sign-in-2 --part k/n` parts that hold `web/e2e/settings/settings.spec.ts`, `webhooks.spec.ts`, `on-call.spec.ts`, `partner-contacts.spec.ts`, `email.spec.ts` and `roles.spec.ts`, one call each. Find k from the `e2e:sign-in-2` listing with `web/scripts/e2e-part.mjs`, writing the listing to a scratch folder outside the repo. Expected: every part green, so the UI saves are unchanged.
- (once) Fresh check (Rule 19, normally the lead's): `ci/iris.sh shard lane-b@Core --part k/n`, then the same parts with `--reverse`, sized so each part stays under about 8 minutes. Expected: every class passes in both orders.

**Shared surfaces:**
- The probe's seams, which the new `SaveRow` and the moved `clash` hook change. Readers: `SettingsWebhooks` and every `SettingsOpsProbe` user.
- The order of entries within one email save (`SettingsEmail` `Forms()` pins).
- The `^OcuTalonTest("SettingsOpsProbe","calls")` records, which a rollback now undoes for S1, S2, S7 and S8.

Every test added or changed passes on a fresh environment, in either order.

**Mutations** (one per AC). Apply each, observe red, revert, then confirm that `git status --short` and `git diff --stat` are unchanged:
- AC1: in `SaveProduct`, move the audit back before `Apply` (call `WriteAudit` per change before the write). Expected red: the S3 row-failure case (an entry is found for the session).
- AC2: in `WritePartner`, write the entry before the row. Expected red: `TestRowWriteFailureRollsBack` (an audit write and a real entry).
- AC3: in `WriteKeys`, audit before `TSTART`. Expected red: the persona and heartbeat row-failure cases.
- AC4: in `SwitchDemo`, audit before `Apply`. Expected red: the `TestApplyFails` row-failure case.
- AC5: in `CreateWebhook`, audit before `SaveRow`. Expected red: the webhook row-failure case.
- AC6: in `SaveEmail`, write the outside entries before the outside writes (back in the key loop). Expected red: the email outside-write failure case. Then audit `email.oauthOwned` before its `Apply` in `RecordOAuth`. Expected red: its row-failure case.
- AC1-AC6 (rollback): delete the rollback in `AuditCommit`. Expected red: every audit-failure case (a row changed). Record which ones went red.
- AC7: delete the AD-19 sentence from the spine. Expected: the grep count is 0.
- AC8: no new test. The Web API and browser specs that already exist are the check.

**Mutation records (implement stage, warm throwaway on the lane-a lock folder under `.worktrees/.coordination/locks`; each applied, observed red, reverted byte-identical with `git status --short` and `git diff --stat` unchanged):**
- mutation: AC1, `SaveProduct` writes each change's entry through `WriteAudit` before its `Apply` -> `SettingsSave` `TestAllOrNothingApply` (no audit write attempted and a real entry for the session, at all five positions) and `TestAllOrNothingAudit`, `TestThresholdsSaved`, `TestOnlyChangedValuesAreAudited`, `TestDigestSection` (a second entry per change)
- mutation: AC2, `WritePartner` writes the entry before the row -> `SettingsPartners` `TestRowWriteFailureRollsBack` (an audit write attempted, a real entry for the session, and a second entry in the control), also `TestAddEditRemoveAudited` and `TestNothingChanged` (two entries per save)
- mutation: AC3, `WriteKeys` writes the entry before `TSTART` -> `SettingsPersona` `TestKeyWriteFails` (no audit write attempted, real log empty, control finds its entry), `TestOutcomeApplies`, `TestOutcomeNotOurs`; `SettingsHeartbeat` `TestKeyWriteFails`, `TestAuditFailsAndWithoutText`, `TestAuditNamesChangedKeysOnly`
- mutation: AC4, `SwitchDemo` writes an entry before its `WriteKeys` -> `SettingsOps` `TestApplyFails` (no audit write attempted, real log empty, control finds its one entry), also `TestAuditAccepted`, `TestAuditFails`, `TestSameMode`
- mutation: AC5, `CreateWebhook` writes the entry before `SaveRow` -> `SettingsWebhooks` `TestCreateRowFailureWritesNoEntry`, `TestNameTakenAtSave`, `TestCreateAuditsAfterTheRow`
- mutation: AC6, `SaveEmail` writes the outside entries before the outside writes (an `AuditAll` of the key `""` entries ahead of the credential and rows) -> `SettingsEmail` `TestAllOrNothing` (the five stages, with and without an earlier mailbox: an outside entry is in the real log; and audit writes 3 to 5 no longer put the values back)
- mutation: AC6, `RecordOAuth` writes the `email.oauthOwned` entry before its key write -> `SettingsEmail` `TestOAuthOwnedRowFailureWritesNoEntry`, `TestProviderFirstSave`, `TestRemove`, `TestSignInStart`, `TestSignInStartFailsAfterEnable`
- mutation: AC6, `ForgetClient` writes the removal entry before its key write -> `SettingsEmail` `TestForgetClientRowFailureWritesNoEntry` (both counts)
- mutation: AC4, `SwitchDemo` runs `RunStep` after a failed write (review pass) -> `SettingsOps` `TestApplyFails`, `TestAuditAccepted`, `TestAuditFails` (the step did not run); the control save of `TestApplyFails` now asserts the step ran
- mutation: AC6, `RecordOAuth` ignores the status of its `WriteKeys` (review pass) -> `SettingsEmail` `TestOAuthOwnedAuditFails`, `TestOAuthOwnedRowFailureWritesNoEntry`
- mutation: AC6, `ForgetClient` writes the key with `Apply` and no entry (review pass) -> `SettingsEmail` `TestForgetClientAuditFails`, `TestForgetClientRowFailureWritesNoEntry`, `TestFailedReplaceShowsNotRegistered`
- mutation: AC1-AC6 (rollback), the rollback in `AuditCommit` deleted -> red in all eight classes: `SettingsOps` `TestAuditAccepted`, `TestAuditFails`, `TestThrown`; `SettingsPersona` `TestAuditFails`, `TestKeyWriteFails`, `TestOutcomeWriteFails`; `SettingsHeartbeat` `TestAuditFailsAndWithoutText`, `TestKeyWriteFails`; `SettingsSave` `TestAllOrNothingAudit`; `SettingsOnCall` `TestSaveAuditsEachChangeWithItsValues`; `SettingsEmail` `TestAllOrNothing`; `SettingsWebhooks` `TestCreateAuditsAfterTheRow`, `TestNameTakenAtSave`, `TestRotateAuditFails` (`TestCreateRowFailureWritesNoEntry` and `TestRotateRowFailureWritesNoEntry` were red too, but their own failure paths roll back in `CreateWebhook` and `SetWebhookSecret`, so that red is a cascade of a transaction an earlier case left open, not their own pin); `SettingsPartners` `TestAddEditRemoveAudited`, `TestRowWriteFailureRollsBack`
- mutation: AC7, the AD-19 bullet deleted from a scratch copy of the spine (the spine file itself was not edited) -> the grep count is 0 on the copy and 1 on the spine
- AC8: no new test; no `Parameter MESSAGE*`, route, role, reply shape or Data class is in the diff.

**Verification run (implement stage, the lead of this stage):** all on the final tree.
- (loop) The eight Settings classes (`SettingsOps`, `SettingsPersona`, `SettingsHeartbeat`, `SettingsSave`, `SettingsOnCall`, `SettingsEmail`, `SettingsWebhooks`, `SettingsPartners`) pass warm, one per call; the spine greps give 1 for the AD-19 sentence, 1 for the Story 25.9 bullet, 1 for the DW-1395 sentence and 1 for the old wording (the marker, see the notes below).
- (once) The neighbours pass warm, one per call: `Core.SettingsAudit`, `PersonaAnswers`, `Admin`, `CommandsHeartbeat`, `CommandsStep4`, `SettingsModels`, `Channel.EmailOAuth`, `EmailLive`, and `Web.PartnerSettingsApi`, `HookSettingsApi`, `PersonaApi`, `OnCallSettingsApi`, `SettingsApi`. `bash ci/checks.sh` passes (test-boundaries included).
- (once) Browser, fresh, after `ci/iris.sh build`: `live sign-in-2 --part 3/4` (holds `settings/email.spec.ts`; 69 tests) and `--part 4/4` (holds `on-call`, `partner-contacts`, `roles`, `settings` and `webhooks`; 58 tests) pass.
- (once) Fresh check (Rule 19): `shard lane-b@Core` in two parts forward and two parts with `--reverse`, each part 34 classes on its own fresh stack: all four pass (the only SKIPs are the existing production-dependent cases).

**Implement-stage notes:**
- Decided in-stage: the loop grep `grep -c "audit entry and then its row"` gives 1: the match is the `[AMENDED 2026-11-15, Story 25.9 ...]` marker of the Story 33.2 text, which quotes the old wording ("it read ..."). The expected count above is corrected to 1 and the spine is left as the plan wrote it.
- `CreateWebhook` reads `NameTaken` before it rolls back, so a name taken by another process's committed row (or by the probe's `clash` row, stored inside the transaction) is `name_taken`; after the rollback the competing row of the probe is gone, which no test needs.
- A test that reads a row back after a rolled-back save must not hold the row open (IRIS returns the same in-memory object for a row that is open, and a rollback does not reset it): the tests read each row fresh, in a scope of their own.
- Two audit-write timestamps can fall in the same millisecond as a following `AuditLog.Now()` mark; the tests that take the mark right after a save of the same session wait 20 ms first.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Every audited Settings save in `OcuTalon.Core.SettingsOps` now writes its rows first and its audit entries last, in one transaction: `AuditCommit` (the shared helper) writes the entries, rolls the rows back and reports if one is refused, and commits otherwise. A failed row write rolls back with no entry. Email's outside writes (credential, EmailIn/EmailOut rows, OAuth client) are audited after them and put back on a refused entry. The webhook saves go through the new `SaveRow` seam. No message text, route, role, reply shape or Data class changed. The spine's AD-19, AD-13 and AD-33 text was written by the plan and checked here.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`: `AuditAll`, `AuditCommit`, `SaveRow`; S1 to S9 rewritten to rows then entries; doc comments corrected.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls`: `SaveRow` override with the `saveRow` answer; the `clash` hook moved into it.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls`, `SettingsPersona.cls`, `SettingsHeartbeat.cls`, `SettingsSave.cls`, `SettingsOnCall.cls`, `SettingsEmail.cls`, `SettingsWebhooks.cls`, `SettingsPartners.cls`: old-order pins updated, a row-failure case (real log empty, with a control) and an audit-failure case per site.
- The spec: mutation records, verification record and this result.

**Review.** 4 layers, 29 findings in 13 root-cause rows: patches applied 4 rows (1 medium: refused-entry cases for `RecordOAuth` and `ForgetClient`; 3 low: step-ran assertion, an overclaiming comment, a mutation record), deferred 0, the other 9 rows rejected with their reasons in the Review Triage Log (the recurring root cause, an entry written before a refused one that no code can take back, is the Design Notes' wontfix-theoretical case).

**Follow-up review recommendation:** false (one medium and three low patched; no high).

**Verification performed.** The eight Settings classes, the thirteen neighbour classes, `bash ci/checks.sh`, `live sign-in-2 --part 3/4` and `4/4`, and the fresh check (`shard lane-b@Core`, two parts forward and two reversed, 68 classes) all pass on throwaways of the lane-a lock folder; every AC's mutation was applied, seen red and reverted byte-identical. After the review patches the two changed classes (`SettingsEmail`, `SettingsOps`) pass again warm. Everything this run started is torn down.

**Residual risks.**
- An entry written before a refused one of the same save stays in the real audit log (IRIS writes it outside the transaction); wontfix-theoretical until `Record` can refuse one entry of a save and accept another.
- One protocol slip by the implementation subagent: it sent two test-class runs in one message at the end (both passed); no git or remote action was taken (`HEAD` unchanged during the run).
