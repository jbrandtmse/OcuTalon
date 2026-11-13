# Epic 36 Context: Step 5's contracts: setting history, and the on-call person in Settings

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Fix step 5's cross-lane names in the spine so Lane A's Epic 23 and Lane B's Epic 24 can build without waiting on each other. Story 36.1 (Lane A, done) built per-production setting history; Story 36.2 (Lane B, done) named and created Lane B's step 5 contracts; Story 36.4 (Lane B, done in code) built the Settings "On call" section. Story 36.5 (Lane B, next) is the epic's burn-down story: it makes the Settings, History and Usage pages lazy so the initial web bundle regains headroom under its 1 MB cap, and 36.4 then merges on top of it after a rework. Story 36.3 (Lane B, last) links Epic 22's worked Jira example from the admin docs. The epic only groups the stories for merging: each story keeps its home lane's files.

## Stories

- Story 36.1: Record the setting history of each watched production (done)
- Story 36.2: Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb (done)
- Story 36.4: Set the on-call person and backup in Settings (done in code; rework pending)
- Story 36.5: Epic 36 burn-down: load the Settings, History and Usage pages lazily
- Story 36.3: Link the worked Jira example from the admin docs

## Requirements & Constraints

- **Lazy routes (36.5, binding Planner ruling; DW-1282):** the Settings route (with its sections) and the History and Usage routes load their components on demand as lazy chunks. The production build's initial bundle must be **at most 921 kB, measured**. `web/angular.json`'s initial budget stays `maximumError` **1MB** (36.4's raise to 1.05MB was reverted; raising a cap is outside a runner's authority; the 500 kB warning stays a warning). Each page renders as before (same headings, sections, data, no console error). New Playwright tests pin a **direct deep-link load and a reload** of /settings, /history and /usage; the existing node and Playwright tests for the three pages pass unchanged in behaviour. Standing rule until DW-1282 closes: new web code goes into lazy chunks.
- **Other lanes' lazy sections:** Story 25.4's Roles section (lane A) and Story 21.4's MCP section (lane C) are lazy chunks inside Settings and are not on this branch yet; they must stay compatible, and whoever pushes second integrates forward. Fallback (a), only if 36.5 can't be done cleanly: 36.4 lazy-loads only its own on-call section, under the cap.
- **36.4 rework (DW-1278, approved):** move `SettingsOps.OnCallUsers` (it walks the `Data.Session`/`Data.Pairing` storage globals from the web process on `GET /api/v1/settings`) behind SettingsOps in the background process, before 36.4 merges; it is 36.4's own code. Add the spine amendment marked `[AMENDED 2026-11-13, Story 36.4, Contest Planner DW-1278 ruling]`: AD-13 also covers direct global reads of product storage in the web process (spine ids claimed under the lock). Making the AD-13 lint check direct global reads in web classes is DW-1287, not 36.4.
- **On-call section (36.4, delivered):** each role is an OcuTalon user or an email address; Telegram only for a user with a paired session; escalation 1 to 1440 minutes (default 15); `SettingsOps` is the only writer; saves audited with from/to values only in the IRIS audit log (one leak-scan test pins it); non-admins 403; on the online demo the section is absent and a save answers 409 `not_available`. Texts ship verbatim from `SETTINGS_TEXTS`; any new text needs acceptance first.
- **Admin docs link (36.3):** with Epic 22 merged, link Story 22.6's worked Jira example under `docs/` from GUIDE.md's "For admins and developers" section (linked from README) and copy its sentence that an MCP tool running operating-system commands or arbitrary code must be classified risky; the link must resolve.
- **CI HOLD** (in force since 19:41Z): no pushes, reruns or merges until CI HOLD OFF is relayed. Lane B ends with `LOCAL READY: DW-1282 + 36.4 head=<sha>` and pushes once after the hold lifts.

## Technical Decisions

- **Routing today (for 36.5's plan):** all routes are in `web/src/app/app.config.ts` (`export const routes: Routes`, `provideRouter(routes, withHashLocation(), withRouterConfig({ canceledNavigationResolution: 'computed' }))`, so deep links are `#/settings`, `#/history`, `#/usage`). Every route is eager (`component:`); no `loadComponent`/`loadChildren` exists anywhere in `web/src/app`. Rows: `{ matcher: settingsMatch, component: SettingsPage, title: SETTINGS_TEXTS.title, canDeactivate: [unsavedGuard] }`, `documents` (DocumentsPage), `history` (HistoryPage, `HISTORY_TEXTS.title`), `usage` (UsagePage, `USAGE_TEXTS.title`), `**` (MainPage, the chat, no redirect). Components: `settings/settings-page.ts` (imports all section components eagerly), `history/history-page.ts`, `usage/usage-page.ts`; `<router-outlet />` is in `app.ts`.
- **Eager imports that keep code in the initial bundle:** `app.config.ts` imports `SETTINGS_TEXTS`/`settingsMatch` from `settings/settings-view.ts` (29 kB source), `HISTORY_TEXTS` from `history/history-view.ts` and `USAGE_TEXTS` from `usage/usage-view.ts` for titles and the matcher; `header/current-page.ts` imports `pageOf` from `settings-view.ts`. These views stay eager unless the titles/matcher/`pageOf` are split out; no other eager file imports from `settings/`, `history/` or `usage/`.
- **Other lanes' lazy-section pattern:** `settings-page.ts` in the epic-21 and epic-25 worktrees does `void import('./mcp-section')` / `import('./roles-section')` and holds the loaded component in a signal. `@defer` was measured worse for 36.4's section (chunk overhead put the initial bundle at 1,003 kB).
- **Bundle measurement:** `npm --prefix web run build` (runs the token/payload/catalog/brand checks, then `ng build`) prints the initial total; kB there is 1,000 bytes. Measured on this branch by 36.4's review: 1,007.44 kB initial (main 962.83 + styles 44.61) with every route eager; lazy-loading only the Settings route (`loadComponent`) gave 921.36 kB initial and a 90.23 kB settings chunk, so History and Usage must also go lazy to meet 921 kB. Smoke: the build against the 1MB cap plus the settings e2e part.
- **On-call storage and route (36.2/36.4):** `oncall.*` keys (AD-19) written only by `SettingsOps` via `POST /api/v1/settings/on-call` (section kind `oncall`); the admin-only user list comes from `SettingsOps.OnCallValues`/`OnCallProblems`, which call `OnCallUsers` (the DW-1278 target). A save is one `SaveSettings` (origin `web_admin`); `Data.Setting.Get` caches 60 s.
- **Setting history (36.1) and Lane B contracts (36.2), delivered:** snapshot tables `SettingSnapshot`/`SettingChange` from `Checks.Tick`; `page` notification kind, `Msg.Escalation`, `Command.AckPage`, `Command.SaveSqlWatch`, `SetReminder` fields; downstream stories 23.3, 23.4, 23.8, 24.2, 24.3, 24.4 build on them.

## UX & Interaction Patterns

- Lazy loading must be invisible: same page titles ("Settings · OcuTalon", "History · OcuTalon", "Usage · OcuTalon"), headings, sections and the unsaved-changes guard on Settings (`canDeactivate`, cancelled back keeps the page), and `#/settings/<slug>` keeps a section change on one page.
- Settings nav has 8 sections including "On call"; field errors mark the field and focus the first error; every control labelled and keyboard-operable.

## Cross-Story Dependencies

- **Order now:** 36.5, then the 36.4 rework (OnCallUsers in the background process, AD-13 amendment, 36.4 rebased on the lazy routes), then scoped re-reviews, smoke with the bundle measured, the fresh check; 36.3 last (waits on Epic 22's Story 22.6; no Jira example in `docs/` yet).
- **Epic 21 overlap (lane C, unmerged):** `settings-page.ts` (`@switch`, imports, the lazy MCP section), `settings-view.ts` (`SETTINGS_SECTIONS`, `SETTINGS_TEXTS`), `web/scripts/settings-view.test.mjs`, `Core/SettingsOps.cls` and `Test/Core/SettingsSave.cls` change in both lanes; expect merge conflicts. Lane A's 25.4 Roles section touches `settings-page.ts` the same way.
- DW-1287 (AD-13 lint for direct global reads in web classes) is separate burn-down work.
