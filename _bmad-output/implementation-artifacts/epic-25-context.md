# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 25 is Lane B's half of step 6: the History page, sending a file from the web app or Telegram, approver and viewer roles in Settings with enforcement, and OcuTalon's reply to a sent file. All of that is merged, as are the burn-down stories 25.7 (CI port release) and 25.8 (the web gap-fill). The open work is Story 25.9, a server-side burn-down that keeps the audit log a true record of Settings changes: every audited Settings save writes its row first and its audit entry last, inside one transaction, and rolls the row back when the audit write fails. Today the order is reversed, and because IRIS writes audit records outside the transaction, a row write that fails after the audit leaves an entry for a change that never happened. The story closes ledger items DW-1392 and DW-1395 and targets release 1.0.12 if it is ready in time.

## Stories

- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (done)
- Story 25.4: Assign approver and viewer roles in Settings (done)
- Story 25.5: Answer only with the right approver role, and say why otherwise (done)
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure (done)
- Story 25.7: Epic 25 burn-down: a cancelled CI job's stack no longer blocks its runner's web port (done)
- Story 25.8: Epic 25 burn-down: the web gap-fill (done)
- Story 25.9: Epic 25 burn-down: an audited Settings save writes its row first and its audit entry last, in one transaction (ready for dev)

## Requirements & Constraints

- **The order, inside one transaction:** (1) write the row(s); (2) write the audit entries; (3) if an audit write fails, `TROLLBACK` and report it; (4) only then `TCOMMIT`. A row write that fails rolls back and writes no audit entry. Reasoning: an entry for a change that never happened is a false record, and an unaudited change is worse.
- **Scope is every audited Settings save of the audit-then-row pattern**, found by grep and listed in the spec: in practice the audited saves in `OcuTalon.Core.SettingsOps` (demo mode, persona and heartbeat keys, `SaveProduct` for the step 2 and on-call sections, the email section and its OAuth/client writes, webhook create and secret change, and Story 24.2's partner contacts). Saves that already write before they audit (the bridge-value saves and their put-backs, role assignment, the MCP saves) stay unchanged.
- **Failure reports reuse what exists.** Each save keeps its current outcomes (`failed`, `not_audited`, `name_taken`, `refused`) and messages, and its log lines. A failed webhook save no longer writes a compensating "undone" entry; it writes nothing.
- **Hard scope limits.** No new user-visible text, `MESSAGE*` parameter, outcome, route, role, reply shape, Data class or index. Existing Web API and Settings browser specs must pass unchanged.
- **Audit content is unchanged.** From and to values appear only in the IRIS audit log. A partner contact's entry names only `partnerContact.<Ref>` and which fields changed. No setting value in a result, log line or test output; the leak scans from Stories 24.2 and 36.4 still cover the audit rows.
- **Tests, each mutation-proof:**
  - Force the row write to fail: the outcome is reported and the real IRIS audit log has no entry for the test's session (checked against a control save whose entry is found).
  - Force the audit write to fail: `not_audited`, and every row is as before, read fresh from storage.
  - Each test must go red when the ordering or the rollback is removed, and the story records the demonstrated mutation.
  - After a rolled-back save, don't assert probe call records kept in ordinary globals (a rollback now undoes them); use process-private counters or the real log.
  - Every test creates and removes its own state, uses its own session Ref, and passes in either order. Extend each site's existing test class rather than copying tests.
- **Comments state the contract, not the history.** Every "audit entry first" doc comment is corrected in place.

## Technical Decisions

- **Why rollback cannot undo an audit entry.** `Bridge.Audit.Record` (the one audit writer) goes through `$SYSTEM.Security.Audit`, and IRIS suspends the open transaction while writing the record, so `TROLLBACK` never removes it. Writing the row first leaves only one way to get a false entry: a commit that fails after the audit write, which the ruling accepts.
- **The spine already carries the rulings** (written during planning; the implementation only verifies them by grep):
  - The audited-save rule: an audited save writes its row and then its audit entry inside one transaction and rolls the row back if the audit write fails.
  - The Settings save order for product keys now reads row, then audit entry, with an amendment marker; no text saying "audit entry and then its row" may remain.
  - Reads of Settings tables: the web process may read them directly (as `SettingsOps.Values` reads `Data.Setting`); every write goes through the production. Reads of other product storage keep the existing rule: only the owning class's methods or `Ownership.Rows`.
  - An ownership-exception bullet for Story 25.9 naming the files it may change.
- **The single writer.** `SettingsOps` is the only Settings writer at run time, in the production job; a save reaches it as a `SaveSettings` command through `Commands.Submit`. It validates every field before writing and drops unchanged values; a refused or unchanged save opens no transaction and writes no entry.
- **One shared audit-and-commit helper, plus a row seam.** The audit-and-commit step, today copied across every site, becomes one private helper called inside the caller's open transaction after the rows; a private row-save seam (like the existing audit seam) lets the test probe force webhook row failures and stage a name clash just before the save.
- **Writes that cannot sit in the transaction** (the email section's credential, item rows and OAuth client, which the production update runs after) follow the bridge-value rule: write, then audit, then put everything back on a failed audit. Their entries come after the item restart, so a failed start never leaves an entry for a value that was put back.
- **Ownership.** `SettingsOps`, its probe and the Settings test classes belong to Lane B; Story 25.9 runs in Lane A and changes only the files its ownership-exception bullet names. The ownership tables don't change. Don't touch `Watch/*`, `Fix/*` or `Live/Payload/*` (held by Stories 23.13 and 24.4a).
- **Runtime.** Tests run on Lane A throwaway stacks, never a shared slot, MCP target or another lane's stacks.

## Cross-Story Dependencies

- The reordered saves come from Story 24.2 (partner contacts), Story 33.2 (`SaveProduct` and the step 2 keys), Story 36.4 (on-call keys via `SecretHandoff`), Story 39.2 (heartbeat keys), and the email and webhook settings stories; their existing tests and leak scans must stay green, with only the pins on the old order updated.
- The test probe's seams and the email save's entry order are shared surfaces: every user of the Settings probe and the email form tests read them.
- Role assignments (Stories 25.4 and 26.4) already write before auditing and are out of scope.
- DW-1393 and DW-1394 (partner contact duplicates and the `TABLE` switch) belong to Story 23.13, not to this story.
