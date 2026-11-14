# Epic 36 Context: Step 5's contracts: setting history, and the on-call person in Settings (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Fix step 5's cross-lane names in the spine and in code so that Lane A's Epic 23 and Lane B's Epic 24 can build paging, escalation, rollback and SQL query watches in parallel. Without that, the two would deadlock, because an epic merges only whole. Along the way OcuTalon gains per-production setting history (Lane A) and an admin-only On call section in Settings (Lane B). The epic only groups the merge: each story keeps its home lane's files and text. Stories 36.1, 36.2, 36.4, 36.5, 36.6 and 36.7 are done. Only Story 36.3 remains. It links the worked Jira MCP example, which Epic 22 has now merged, from the admin docs, and states which MCP tools must be classified risky.

## Stories

- Story 36.1: Record the setting history of each watched production
- Story 36.2: Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb
- Story 36.4: Set the on-call person and backup in Settings
- Story 36.3: Link the worked Jira example from the admin docs
- Story 36.5: Epic 36 burn-down: load the Settings, History and Usage pages lazily
- Story 36.6: Epic 36 burn-down: keep a stored on-call user's channels when the user list is unavailable
- Story 36.7: Epic 36 burn-down: an upgrade removes the previous builds' bundle files from the served web folder

## Requirements & Constraints

- **Admin docs link (36.3, open):** with Epic 22 merged, link the worked Jira example at the path Story 22.6 supplies under `docs/` from the admin section. Copy that example's sentence that an MCP tool running operating-system commands or arbitrary code must be classified risky. The link must resolve. The "no shell" requirement needs both the admin guide and the security overview to say this. The security overview already does (Lane A's file). The admin guide's line is 36.3's job. The docs claim only what the release ships.
- **Paging channels (decided, built into 36.2 and 36.4):** by default a page goes to the on-call person and the backup by Telegram and by email, and each person can choose Telegram, email or both. Telegram reaches only a user whose session has a paired chat, so anyone else is paged by email. An acknowledgement on any channel stops escalation, and email never acknowledges. Escalation defaults to 15 minutes. IRIS Managed Alerts are never turned off.
- **On-call contact data:** saves are audited with from and to values ONLY in the IRIS audit log. They appear in no other log, trace, digest, notice or eval output (one leak-scan test pins this). Non-admins get 403. On the online demo the section is refused with 409 `not_available` and is absent from `GET /api/v1/settings`.
- **36.6 (delivered):** when the user list is unavailable (`users: []`), a stored user keeps their channel boxes and the stored Telegram channel is sent on save. The fix is web-only, with no new text. The server's save-time checks still refuse an unknown user.
- **36.7 (delivered; no public claim and no release-note line):** an upgrade removes only the hashed bundle files that match the installer's STALEFILES pattern and that the new build lacks. `release/upgrade-harness.sh` keeps a permanent stale-file row.

## Technical Decisions

- **AD-29: lanes and the step rule.** Lane B owns the README, the install script, `docker/`, `web/` and the rest of `ci/`. Since Story 0.30 the README keeps only the judges' sections. The install, setup and admin sections live in the root `GUIDE.md` ("For admins and developers"). Lane A owns these in `docs/`: the bridge guide, the security overview, `docs/install-ipm.md` and Lane A's worked examples (Story 22.6's Jira example is `docs/mcp-jira-example.md`). Story 36.3 keeps Lane B's files, as 36.2 does. It links and quotes Lane A's example but never edits it or the security overview. A lane that needs a change in the other lane's file asks the owner for it. Step rule: each step's contract-naming story (Lane A, 3x.1) and command-verb story (Lane B, 3x.2) sit together in the step-contract epic. That epic merges before both feature epics, and Lane A never edits Lane B's step names. Step epics are merge-gated on `release/1.0.0-rc1`.
- **Doc links:** a product link to a GUIDE section uses `GUIDE_URL` plus the anchor, and a link to the README top keeps `README_URL` (`web/src/app/links.ts`).
- **Setting history (36.1):** snapshots are taken only when the production-change counter or start mark moved, or once an hour. Each difference becomes one `SettingChange` row, and rows are purged after 90 days. A credential value is blank and never leaves its table. The `%Ens_ProductionConfig:W` grant and the rollback kind belong to Story 23.3.
- **Lane B step-5 names (36.2):** the `page` notification kind, `Msg.Escalation`, the `AckPage` and `SaveSqlWatch` verbs, the escalation kind on `Reminder`, the on-call keys (`oncall.primary|backup.user|email|channels`, `oncall.escalationMinutes` 1 to 1440) and the partner-contact table. Lane A never edits them.
- **On-call section (36.4):** `POST /api/v1/settings/on-call` (`Web.OnCallSettings`). The body goes through `SecretHandoff`, so `SaveSettings.Changes` holds only a handoff URI. The user list comes back through the `ListOnCallUsers` read verb and a handoff, and `users: []` means the list failed. Refusals name fields only, never values. Direct global reads from the web process count as unchecked paths.
- **Lazy pages (36.5) and reload (36.7):** Settings, History and Usage are `loadComponent` routes. The initial bundle stays at or under 921 kB, and the 1MB `maximumError` budget is never raised. A chunk that fails to load after an upgrade triggers one full reload, guarded per address in `sessionStorage`.

## Cross-Story Dependencies

- 36.3 depended on Epic 22 (Story 22.6). Epic 22 is merged and integrated forward onto this branch, and `docs/mcp-jira-example.md` exists with the risky sentence.
- Epics 23 and 24 (and Stories 23.3, 23.4, 23.8, 24.2, 24.3 and 24.4) build on 36.1's and 36.2's contracts. 36.7 blocked the 1.0.10 release candidate and is done.
