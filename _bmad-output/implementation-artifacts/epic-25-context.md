# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 25 is Lane B's half of step 6: the History page, sending a file from the web app or Telegram, approver and viewer roles in Settings with enforcement, and OcuTalon's reply to a sent file. All of that is merged, and so are the two burn-down stories that followed: 25.7 (CI port release) and 25.8 (the web gap-fill). The open work is Story 25.9, a server-side burn-down that keeps the audit log a true record of Settings changes. Every audited Settings save must write its row first and its audit entry last, inside one transaction, and roll the row back when the audit write fails. Today the order is reversed. IRIS writes audit records outside the transaction, so a row write that fails after the audit leaves an entry for a change that never happened. The same story writes two Contest Planner rulings into the architecture spine: an AD-19 amendment (the save order) and an AD-13 clarification (the web process may read Settings tables directly). It closes ledger items DW-1392 and DW-1395 and targets release 1.0.12 if it is ready in time.

## Stories

- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (done)
- Story 25.4: Assign approver and viewer roles in Settings (done)
- Story 25.5: Answer only with the right approver role, and say why otherwise (done)
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure (done)
- Story 25.7: Epic 25 burn-down: a cancelled CI job's stack no longer blocks its runner's web port (done)
- Story 25.8: Epic 25 burn-down: the web gap-fill (Usage withdraws its stale error, and a viewer gets no file-reply add or Documents drop) (done)
- Story 25.9: Epic 25 burn-down: an audited Settings save writes its row first and its audit entry last, in one transaction (backlog)

## Requirements & Constraints

- **The order, inside one transaction:** (1) write the row; (2) write the audit entry; (3) if the audit write fails, `TROLLBACK` the row and report the failure; (4) only then `TCOMMIT`. The reasoning: an audit entry for a change that never happened is a false record, but an unaudited change is worse.
- **Scope is every audited Settings save of the audit-then-row pattern.** That covers at least Story 24.2's partner contact save (`SettingsOps.WritePartner`) and `SaveProduct` (Stories 33.2 and 36.4). Grep for any other audited write that follows the same pattern, and list every one in the spec.
- **Tests, each mutation-proof:**
  - Force the row write to fail. No audit entry is written, and the failure is reported.
  - Force the audit write to fail. The row is unchanged, and the failure is reported.
  - Each test must fail when the ordering or the rollback is removed, and the story records that demonstrated mutation.
  - The existing rollback test proves the rollback only for its probe's global, not for the IRIS audit entry. The new tests must check the real audit log and the real row.
  - Every test creates and removes its own state and passes in either order.
- **Spine text, verbatim.** Add the AD-19 sentence and the AD-13 sentence exactly as the epic's acceptance criteria give them, with their `[ADDED 2026-11-15, …]` markers. The spine's current Story 33.2 save-order text says "each changed value's audit entry and then its row" for product keys. That text now contradicts AD-19, so the story must reconcile it.
- **Hard scope limits.** No new public text, and no change to any route, role or reply shape.
- **Audit content is unchanged.** From and to values appear only in the IRIS audit log. A partner contact's entry holds only `partnerContact.<Ref>` and which fields changed, never a value. A failure report, a log line or test output must not carry a setting value. Leak scans from Stories 24.2 and 36.4 cover the audit rows.

## Technical Decisions

- **Why the rollback cannot undo an audit entry.** `Bridge.Audit.Record` writes through `$SYSTEM.Security.Audit`. IRIS suspends the open transaction while it writes an audit record, so a `TROLLBACK` never removes the entry. Writing the row first leaves only one way to get a false entry: a commit that fails after the audit write. The AD-19 amendment accepts that case.
- **The single writer.** At run time `OcuTalon.Core.SettingsOps` is the only Settings writer. It runs in the production job, and a save reaches it as a `SaveSettings` command through `Commands.Submit`. It validates every field before it writes anything and drops unchanged values. A refused value changes nothing and writes no audit entry.
- **Bridge values do not use the product-key transaction.** `SettingsOps` writes them through `OcuTalon.Bridge.Settings`: every `Check` runs first, then each `Set` writes its audit entry. If a later `Set` fails, `SettingsOps` sets the earlier values back and audits the reversal. The spec decides whether that path falls under the grep's pattern.
- **AD-13 clarification.** The web process may read Settings tables directly, as `SettingsOps.Values` reads `Data.Setting` and as `GET /v1/settings` lists partner contacts through `PartnerContact.List()`. Every write still goes through the production. Reads of other product storage keep AD-13's rule: only the owning class's methods or `Ownership.Rows`.
- **Ownership.** `Data.Setting`, `PartnerContact` and `SettingsOps` belong to Lane B. The Planner gave the story to Lane A after Story 25.8, or to the first free lane. If another lane's files change, record an AD-33 exception that names them, as Story 25.8 did. The ownership tables don't change.
- **Runtime.** Tests run on real runtimes (Lane A throwaway stacks), with no shared slot or MCP target.

## Cross-Story Dependencies

- The saves being reordered come from Story 24.2 (partner contacts, Epic 24), Story 33.2 (`SaveProduct` and the step 2 keys) and Story 36.4 (the on-call keys, which arrive through `SecretHandoff`). Their existing tests and leak scans must stay green.
- Stories 25.4 and 26.4 also write `Settings` audit entries, for role assignments (`Install.Step.Roles.Assign`, in `%SYS`). The grep should check whether they follow the audit-then-row pattern.
- DW-1393 and DW-1394 (partner contact duplicates and the `TABLE` switch) belong to Story 23.13, not to this story.
