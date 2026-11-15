---
title: "Story 36.6: Epic 36 burn-down: keep a stored on-call user's channels when the user list is unavailable"
type: 'bugfix'
created: '2026-11-14'
status: 'done'
baseline_revision: '8c46cffa9e72642c54b9fbde500c748ad0e72552'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-4-set-the-on-call-person-and-backup-in-settings.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `GET /v1/settings` answers the on-call member with `users: []` when the roster can't be had (SettingsOps busy or failed; DW-1308). The On call form then treats every stored user as unpaired: `roleFormOf` unchecks the stored Telegram box, `telegramState` shows the "no paired chat" line, and the next save sends `email` only. The person's Telegram channel is dropped without anyone being told.

**Approach:** This is web-only, with no new text and no server change (Planner option (a)). A stored user the list does not hold is not judged on the page: their Telegram box stays enabled, the stored boxes stay as stored, and no line shows. The server's save-time checks then decide. They refuse an unknown user (`primaryUser`/`backupUser`) and Telegram for an unpaired user (`primaryChannels`/`backupChannels`), and nothing is written.

## Boundaries & Constraints

**Always:**
- The change lives in `web/src/app/settings/on-call-view.ts` (`telegramState`). `roleFormOf`, `on-call-section.ts` `telegramText` and `focusSelector` follow from it with no logic change of their own.
- A user the list holds with `paired: false` keeps today's behaviour: Telegram unchecked and disabled, with the filled `telegramUnpaired` line.
- A person by email keeps `emailOnly`. Nobody keeps `enabled`.
- `defaultChannels` and `chose()` are unchanged: a newly chosen person starts with today's boxes (Telegram only for a listed paired user, or for nobody).
- Doc comments state the new contract and never the history (Rule 14).
- Live runs use lane-B throwaways only: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802`, with `OCUTALON_RUN_TAG` `e36s6*`.

**Never:**
- No change to any server class, `SETTINGS_TEXTS`, `web/angular.json`, `.github/workflows`, `release/**`, `ci/units.sh` or `_bmad/`.
- No new user-facing text, and no attempt to tell "list unavailable" from "user gone" on the page.
- No change to the Person select's options (`personOptions`) or to the dirty rule.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| List unavailable | `users: []`, stored primary `ocutalon` with `telegram,email` | Telegram checked and enabled, Email checked, no unpaired line. The form is clean. A save sends `primaryChannels: "telegram,email"` | The server decides at save |
| Backup the list lacks | `users: []`, stored backup user with `telegram,email` | The same as above, for the backup | The server decides at save |
| User gone, list available | Stored user with no Data.Session row; the list holds other users | Boxes kept as stored, no unpaired line. A save is refused with `primaryUser`, which shows `unknownUser` under the Person select | 400 `bad_settings`; nothing saved, nothing audited |
| Listed, unpaired (unchanged) | `users` holds `{bob, paired:false}`, stored `telegram,email` | Telegram unchecked and disabled, with the filled `telegramUnpaired` line | n/a |
| Listed, paired (unchanged) | `{alice, paired:true}` | Telegram enabled, stored boxes kept | n/a |
| Switch away from an absent stored user | The admin picks another person | That person's default boxes (unchanged). The absent stored user leaves the select, as in 36.4 today; Leave without saving restores the stored form | Unsaved prompt as today |

</intent-contract>

## Code Map

- `web/src/app/settings/on-call-view.ts` -- `telegramState` (L109-117) answers `unpaired` when `users.find(...)?.paired !== true`. A user the list does not hold therefore reads as unpaired, which is the defect. `roleFormOf` (L131-135) keeps `boxes.telegram` only when the state is `enabled`. The header comment (L9) and `telegramState`'s doc (L108) state the rule.
- `web/src/app/settings/on-call-section.ts` -- `telegramText` (L327-331) and the `[disabled]` binding (L121) both derive from `telegramState`. `chose()` (L360-365) takes `paired` from the list and calls `defaultChannels`; it stays as it is. The class doc (L42) says that Telegram is disabled "for a user without a paired chat".
- `web/scripts/on-call-view.test.mjs` -- this is the node test of the view. L120 pins the old rule (`telegramState('user','gone',USERS).kind === 'unpaired'`) and must flip. L156-161 covers the listed-unpaired and paired cases.
- `web/e2e/settings/on-call.spec.ts` -- the serial spec O1-O11 (sign-in-2, live part 13/15 with `settings.spec.ts`). O9 (L361-389) is the route-stub pattern to extend: the GET goes through `route.fetch()` and is rewritten, and the POST is captured and fulfilled 200 `{result:'done',sections:{}}`. The header list is at L9-27.
- `web/e2e/support/on-call.ts` -- provides `readOnCall`, `restoreOnCall`, `auditMark`, `auditSince`, `ON_CALL_API` and `bodyOfStored`.
- `web/e2e/support/iris.ts` -- `seedOtherSession(user)` (L822) makes a Data.Session row through `Test.Data.Fixture.Session`, and `cleanFixtureRows([ref])` (L701) deletes it. Reuse both; do not copy `session.spec.ts`'s local `dropSessionRows`.
- `web/e2e/sign-in/helpers.ts` -- provides `envelope()` (L93) and `README_ACCOUNT`.
- Read-only server evidence (do not edit): `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`. `OnCallRole` (L2473) refuses an unknown user with `named(user)`, and Telegram for a user with no paired chat with `named(channels)`. `OnCallUsers` (L2544) builds the roster from Data.Session rows that have an IrisUser. The verified tests are `Test.Core.SettingsOnCall.TestRefusals`, `TestTelegramNeedsAPairedChat` and `TestHandoffMissing`, and `Test.Web.OnCallSettingsApi.TestSubmitFailsOrThrows`.

## Tasks & Acceptance

**Execution:**
- `web/src/app/settings/on-call-view.ts` -- `telegramState`: for `person === 'user'`, answer `unpaired` only when the list holds the user (`users.find(...)`) and that entry's `paired` is not `true`; a user the list lacks reads `enabled`. Update its doc and the header bullet to say that a user the list lacks is not judged and the server's save-time check decides. -- This fixes DW-1308 with no new text.
- `web/src/app/settings/on-call-section.ts` -- doc only (L42): Telegram is disabled for a user the list shows without a paired chat, and for a person by email. -- The comment states the contract.
- `web/scripts/on-call-view.test.mjs` -- flip L120 to `enabled`, with the message "a user the list does not hold is not judged". Add these cases: `telegramState('user','alice',[])` is `enabled`; `onCallFormOf(values({users:[], primaryUser:'alice', primaryChannels:'telegram,email', backupUser:'gone', backupEmail:'g@x.io', backupChannels:'telegram,email'}))` keeps `telegram: true` for both roles; `onCallBody` of that form sends `telegram,email` for both; with `USERS`, a stored `gone` user keeps Telegram; bob (listed, unpaired) still reads false. -- Rule 19 node pin.
- `web/e2e/settings/on-call.spec.ts` -- add **O12** and **O13** and extend the header list. -- These are the ruling's tests (1) and (2).
  - **O12:** route-stub the GET as O9 does. Set the on-call member's `users` to `[]`; set `primaryUser` to `README_ACCOUNT.user` with `primaryEmail` `zz-o12p-<stamp>@example.com` and `primaryChannels` `telegram,email`; set `backupUser` `zz-o12-gone-<stamp>` with an address and `telegram,email`. Capture the POST and fulfil it with 200. Then open On call and assert, for each role: Telegram checked, Telegram enabled, no accessible description, Email checked. Assert that `hasn't paired Telegram` appears 0 times on the page. Change only the minutes, save, and expect the saved text. Assert that exactly one POST was made, with `primaryChannels: 'telegram,email'` and `backupChannels: 'telegram,email'`, and that `readOnCall` still equals `found`.
  - **O13 (real server, no stub):** `seedOtherSession('zz-o13-<stamp>')`, then save that user as the on-call person through `ON_CALL_API`, with `envelope()`, an address and channels `email` (expect 200). Then `cleanFixtureRows([ref])`, so the user has no session row. Read `stored = readOnCall()` and take `mark = auditMark()`. Open On call and assert: the Person select shows the gone user, Telegram is enabled and unchecked, and there is no unpaired line. Save without touching the person, then assert that `#oncall-primary-person-error` has the text `UNKNOWN_USER(name)`, that `readOnCall()` equals `stored`, and that `auditSince(mark, 0)` is `[]`. Run `cleanFixtureRows` in `finally`; afterEach restores `original`.

**Acceptance Criteria:**
- Given a stored on-call user (primary or backup) missing from `users`, when On call loads, then their stored boxes show (Telegram included), Telegram is enabled, and no "no paired chat" line shows; no `SETTINGS_TEXTS` key and no server file changes (outside `_bmad-output/`, `git diff --stat` touches only the four `web/` files under Execution).
- Given the list is unavailable and the admin saves without touching that person, when the POST is sent, then its body carries `primaryChannels` and `backupChannels` `telegram,email` (O12).
- Given a stored user with no session row, when the admin saves, then the page shows the existing unknown-user text under the Person select, and GET and the audit log are unchanged (O13, real server).
- Given a user the list holds unpaired, when On call loads or the user is chosen, then Telegram is unchecked and disabled with its line (O1 and the node tests, unchanged).
- The initial bundle stays at or below 921,000 bytes (`web/scripts/initial-bundle.test.mjs`).

### Review Findings

Code review 2026-11-14 (Tier 1, full mode, diff `8c46cffa..d69359da`; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, none failed). 25 raw findings, 20 after grouping: 0 decision-needed, 5 patch (applied), 3 defer (ledger, terminal), 12 rejected. Verdicts: high 0, medium 0, low 10, false 10. Rule 3: met (O13 and O16 run against the real server; QA's live part 12/15 on lane-B `e36s6q1`, 26 passed). Rule 6: no AD violated (AD-14, AD-19, AD-29). No `SETTINGS_TEXTS` key, `ux-strings.test.mjs` or server file changed.

- [x] [Review][Patch] The `on-call-view.ts` header bullet dropped the person-by-email case from `telegramState`'s contract [web/src/app/settings/on-call-view.ts:9] — restored ("not for a person by email, and not for a user the list shows without a paired chat").
- [x] [Review][Patch] Node case title lacked the possessive, and its mutation line quoted it truncated [web/scripts/on-call-view.test.mjs:175] — title now "keeps both roles' stored boxes, and sends them, while the list is unavailable"; the mutation line quotes it in full.
- [x] [Review][Patch] AC1's no-new-text clause had no `mutation:` line [web/scripts/on-call-view.test.mjs:36] — a `listUnavailable` key added to `SETTINGS_TEXTS.onCall` turned "are shown byte for byte" red; reverted, line recorded under Verification.
- [x] [Review][Patch] AC5 (bundle at most 921 kB) had no `mutation:` line [web/scripts/initial-bundle.test.mjs:21] — the Settings route made eager turned the test red at 978.39 kB; reverted, line recorded under Verification.
- [x] [Review][Patch] No re-run recorded after the QA additions — re-ran at review: `on-call-view.test.mjs` 25 pass, `npm --prefix web test` 2005 pass, lint pass, build initial total 878.98 kB and `initial-bundle.test.mjs` pass; tree byte-identical after each mutation.
- [x] [Review][Defer] List `[]` at load, Telegram checked for an unlisted user during a pending save, and an answer listing them unpaired leaves the box checked and disabled [web/src/app/settings/on-call-section.ts:395] — deferred: DW-1316 `wontfix-accepted` (narrow race; the next save is refused, not silent; re-pick or Leave without saving recovers).
- [x] [Review][Defer] O13/O16 leave an unknown on-call user if the run is hard-killed between the save and afterEach; a reused instance's next `restoreOnCall` then gets 400 [web/e2e/settings/on-call.spec.ts:513] — deferred: DW-1317 `wontfix-accepted` (`finally` and afterEach cover every normal failure; fresh lane-B and CI instances never hit it).
- [x] [Review][Defer] Story 36.4's spec and the epic context's kept rules still say Telegram only for a paired session — deferred: DW-1318 `wontfix-accepted` (fix edits other specs; the 36.6 entry in the epic context and the code docs carry the new rule).

Rejected:
- `low` The spec's Auto Run Result, Commands ("O1-O13", part 13/15) and Code Map predate QA's O14-O16 and the part move to 12/15 (blind-hunter, verification-gap, acceptance-auditor) — the fix edits the spec under review; Tests Added and the Verification mutation lines carry the current set.
- `low` The frontmatter `created` date (11-14) follows the 11-13 change-log entry (blind-hunter) — UTC vs local date; the fix edits the spec.
- `false` O14/O15 matchers omit the emails and persons (blind-hunter) — the address path does not depend on the list; O12 pins both roles' emails with the list unavailable, and O14/O15 pin the channels.
- `false` O14/O15 lack O12's "nothing was written" read (blind-hunter) — both stubs fulfil the POST and `posted.length === 1` holds; afterEach restores regardless, so no write can leak.
- `false` O13 lacks O16's "no error under the other role" check (blind-hunter) — O13's backup is Nobody, which the server never refuses by user (`TestRefusals`); no reachable double refusal.
- `false` The e2e header credits O12-O16 to Story 36.4 (blind-hunter) — "Story 36.4" names the section under test; per Rule 14 the header states what each case pins, not its history.
- `false` Re-picking a stored user the list lacks takes `chose()`'s unpaired default (edge-case-hunter) — unreachable: `personOptions` lists that user only while the role's form holds them, so no `change` event can choose them; `chose()` is unchanged by the spec.
- `false` `auditSince(mark, 0)` is one immediate read (edge-case-hunter, verification-gap) — the audit row is written synchronously before the answer, and the read follows the page showing the refusal; O3 uses the same pattern.
- `false` AC4's mutation line names O1, which needs an unpaired README admin (verification-gap) — the line states that condition, and the same mutation is recorded red in the environment-free node test (bob); O14 pins the listed-unpaired case too.
- `false` O13's `not.toBe('')` is weaker than `toBe(user)`, and O13/O16's `not.toBeChecked` passes under the old rule (verification-gap) — the 200 save binds the stored user, every later assertion keys on it, and `toBeEnabled` plus the zero-count line discriminate.
- `false` The spec says `done` while the tracker says `review` (acceptance-auditor) — the tracker is synced at the end of this review.
- `false` The matrix's "the form is clean" is not asserted (acceptance-auditor) — both the form and its baseline come from `onCallFormOf`, so the load is clean with or without the defect; nothing for a test to pin.

## Spec Change Log

- 2026-11-13: O13's fixture user is `zzo13<stamp>`, not `zz-o13-<stamp>`: `seedOtherSession` accepts only letters, digits and underscore. The behaviour is as specified.

## Review Triage Log

### 2026-11-13 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 11, false 8, maybe-false 0 (the 3 intent-audit rows are descriptive and closed by-design, graded false)
- findings:
  - `[low]` `[patch]` O12 matcher omits the stored emails and the new minutes (blind hunter) — added `primaryEmail`, `backupEmail` and `escalationMinutes` to the `toMatchObject`.
  - `[low]` `[patch]` O13 header comment says "keeps their stored boxes" but the real-server case stores `email` only (blind hunter) — reworded to "Telegram enabled and the stored Email box".
  - `[low]` `[reject]` O13 runs `cleanFixtureRows` twice (blind hunter) — the first call makes the row vanish, the second is the failure-path cleanup; harmless, and a comment would narrate.
  - `[low]` `[reject]` no unit test for `chose()` / `defaultChannels` with an unlisted user (blind hunter) — the spec leaves `chose()` and `defaultChannels` unchanged and an absent user can't be newly chosen.
  - `[false]` `[reject]` O13 never stores `telegram,email` for a gone user (blind hunter; edge-case hunter) — the spec fixes O13 at channels `email`; the stored-Telegram case is O12 and the node tests. Spec-bound.
  - `[low]` `[reject]` O12 does not assert the form is clean before the edit (edge-case hunter) — the dirty rule is unchanged and untouched; a guard assertion would need a new observable the spec does not name.
  - `[low]` `[patch]` O13 fixture name `zzo13<stamp>` differs from the spec's `zz-o13-<stamp>` (edge-case hunter) — `seedOtherSession` accepts letters, digits and underscore only; recorded under Spec Change Log.
  - `[false]` `[reject]` a listed-now-unpaired user shows the server's `noChannel` text at save with the list unavailable (edge-case hunter) — this is the design: the server decides at save (Design Notes).
  - `[low]` `[reject]` letter-case mismatch between a stored user and the list name (edge-case hunter) — the old `find` was case-sensitive too, and the stored name is chosen from the list; no reachable mismatch shown.
  - `[false]` `[reject]` the O12 POST route does not check the method (edge-case hunter) — only a POST goes to that URL; GET /v1/settings is a different URL.
  - `[low]` `[reject]` AC5 (bundle size) has no `mutation:` line (verification gap) — the change adds no code that moves the bundle; `initial-bundle.test.mjs` runs at 878.98 kB.
  - `[low]` `[reject]` AC1's "no server file changed" clause has no test (verification gap) — checked by `git diff --stat`, the clause is a scope statement, not behaviour.
  - `[low]` `[reject]` O12's last assertion (`readOnCall` equals `found`) cannot fail from the defect (verification gap) — it guards against a leaked stub; the assertions that pin AC2 are the POST count and body.
  - `[low]` `[reject]` the backup role has no real-server unknown-user case (verification gap) — the backup takes the same path as the primary; O12 and the node tests cover it.
  - `[false]` `[reject]` O13's discriminating assertion is `toBeEnabled` only (verification gap) — noted, and it is the one that goes red under the old rule; no action.
  - `[false]` `[reject]` AC3's mutation first reddened O11, not O13 (verification gap) — recorded under Verification with the narrowed variant that reddens O13.
  - `[false]` `[reject]` intent audit: O12 stubs the POST, so the real server's refusal for an empty roster is evidenced only by O13's gone-user case — by design (Design Notes: the page stops judging; the server decides).
  - `[false]` `[reject]` intent audit: O13 uses a non-empty roster and channels `email` — spec-bound.
  - `[false]` `[reject]` intent audit: `chose()` still reads a missing user as unpaired, so re-choosing a gone user starts with Telegram unchecked — spec-bound ("`defaultChannels` and `chose()` are unchanged").

## Design Notes

**Ruling (binding):** `.coordination/prompts/epic-36-rulings-20261113-2130.md`, "~02:00Z Nov 14" item 6 and "~03:00Z Nov 14", option (a). The ruling's "tell list-unavailable from no-users" condition is met without telling them apart: the page stops judging any user the list lacks, so both cases behave alike, and the server's save checks are the judge. **Owned ledger:** DW-1308 (the only entry in `LEDGER slice 36-6-…`) is addressed by this whole story.

**Governing ADs (Rule 6):**
- AD-14: Telegram only to a paired chat. It holds because the save check refuses Telegram for an unpaired user (`TestTelegramNeedsAPairedChat`), and paging falls back to email.
- AD-19: SettingsOps is the only writer and the validator.
- AD-29: Lane B files only.

No AD's Rule changes.

**Integration ACs, Consumes (Rules 1, 2):** the story adds no service or module. Consumes: Story 36.4's `GET /v1/settings` on-call member and `POST /v1/settings/on-call`. O13 exercises them against the real server, and O12 against the real page with a stubbed GET.

**Extend, don't copy:** O12 extends O9's stub pattern. O13 reuses `seedOtherSession` and `cleanFixtureRows`. The fix extends `telegramState` in place.

**Decided in-stage:**
- A newly chosen person keeps `defaultChannels` (lead brief: unchanged). In practice an absent user can't be newly chosen: they are listed only while selected.
- Switching away from an absent stored user removes them from the select (36.4's `personOptions` keys on the form's current user). The admin chose to change the person, so nothing is dropped silently; Leave without saving restores the stored form. This is unchanged and needs no new text.
- O12 also changes the minutes, so the save is a real edit that leaves the person untouched, which is DW-1308's path.

## Verification

`<lane-b>` = `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=<stage>'`; fresh tag `e36s6i` (QA `e36s6q`). `<main checkout>` is the main checkout's root, the first line of `git worktree list`; never write it out in a tracked file.
- Run one command per call, with `timeout: 600000`, and never two test calls in one message. `<scratch>` is the stage's own scratch folder.
- At the end, even after a failure, run `<lane-b> OCUTALON_RUN_TAG=e36s6i bash ci/iris.sh teardown`.

**Commands:**
- `node --test web/scripts/on-call-view.test.mjs` -- expected: pass.
- `npm --prefix web run lint` -- expected: pass.
- `npm --prefix web run build`, then `node --test web/scripts/initial-bundle.test.mjs` -- expected: pass (at most 921 kB).
- `<lane-b> OCUTALON_RUN_TAG=e36s6i bash ci/iris.sh build` -- expected: the bundle is rebuilt (Rule 21).
- `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json > <scratch>/l.json`, then `node web/scripts/e2e-part.mjs k/n <scratch>/l.json` -- expected: the PART line naming `settings/on-call.spec.ts` (13/15 last measured).
- `<lane-b> OCUTALON_RUN_TAG=e36s6i bash ci/iris.sh live sign-in-2 --part k/n` (that part) -- expected: pass, O1-O13.
- `npm --prefix web test` -- expected: pass.

**Shared surfaces:** the instance-wide `oncall.*` rows (each case saves and restores them; the spec is serial); the Data.Session roster (O13's fixture row lives only inside its case); the `telegramState` contract (`on-call-view.test.mjs` L120). Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; the implement stage records each as `mutation: <change> → <red test>`):**
- AC1/AC2: revert `telegramState` so that a user the list lacks is `unpaired` (the stored Telegram channel is dropped) → O12 red (Telegram unchecked; the body sends `email`) and `on-call-view.test.mjs` red.
- AC3: `fieldErrorText('primaryUser')` returns the `noChannel` text → O13 red.
- AC4: `telegramState` answers `enabled` for every user → `on-call-view.test.mjs` red (bob) and O1 red on an unpaired README admin.

**Mutation results (implement stage; each reverted by hand, `git diff` byte-identical to the fixed tree):**
- mutation: `telegramState` reverted so a user the list lacks is `unpaired` (`users.find(...)?.paired !== true`) → O12 red (`toBeChecked` failed on the stored Telegram box; O13 not reached in the serial run) and `on-call-view.test.mjs` red (3 cases: "is not judged for a user the list does not hold", "keeps the stored boxes of a user the list does not hold", "keeps both roles' stored boxes, and sends them, while the list is unavailable").
- mutation: `fieldErrorText('primaryUser')` returns the `noChannel` text → O11 red first (the serial run then skips O13); narrowed to a user named `zzo13*` so O11 passes → O13 red (expected the unknown-user text, received the `noChannel` text).
- mutation: `telegramState` never answers `unpaired` → `on-call-view.test.mjs` red (bob, "is disabled for a user who hasn't paired", and 3 more) and O1 red (`toBeDisabled` failed on the unpaired README admin).
- mutation (QA): `onCallFormOf` reads the backup against `[]` instead of `values.users` → `on-call-view.test.mjs` red ("judges the backup by the list as it judges the on-call person, whoever the other role is").
- mutation (QA): `roleFormOf` returns `mail: true` whatever the stored channels → `on-call-view.test.mjs` red ("keeps a stored Telegram-only channel of a user the list does not hold, with Email unchecked, and sends it alone").
- mutation (QA): `roleFormOf` returns `telegram: boxes.telegram` (a listed unpaired user's stored Telegram is kept checked) → O14 red (`not.toBeChecked` failed on the listed unpaired user's Telegram; O1 to O13 pass) and `on-call-view.test.mjs` red (3 cases).
- mutation (QA): `roleFormOf` returns `mail: boxes.mail || users.length === 0` (Email forced on while the list is empty) → O15 red (`not.toBeChecked` failed on the backup's Email; O1 to O14 pass) and `on-call-view.test.mjs` red (the Telegram-only case).
- mutation (QA): `fieldErrorText('backupUser')` returns the `noChannel` text → O16 red (expected the unknown-user text under the backup, received the `noChannel` text; O1 to O15 pass).
- mutation (code review, AC1 no-new-text clause): a `listUnavailable` key added to `SETTINGS_TEXTS.onCall` in `settings-view.ts` → `on-call-view.test.mjs` red ("are shown byte for byte"; 24 pass, 1 fail).
- mutation (code review, AC5): the Settings route in `app.config.ts` made eager (`component: SettingsPage` in place of `loadComponent`) → `initial-bundle.test.mjs` red ("holds at most 921 kB": the initial total is 978.39 kB).

## Auto Run Result

Status: done
Blocking condition: none

- Summary: `telegramState` no longer judges a stored user the list does not hold, so Telegram stays enabled with the stored boxes and no unpaired line; a listed user with `paired: false`, a person by email and nobody are unchanged. No server, text or config change.
- Files: `web/src/app/settings/on-call-view.ts` (fix, doc and header), `web/src/app/settings/on-call-section.ts` (class doc), `web/scripts/on-call-view.test.mjs` (flipped case plus three new), `web/e2e/settings/on-call.spec.ts` (O12, O13, header).
- Review: 19 findings (low 11, false 8). Patches applied: 3 (O12 matcher gains the stored emails and the new minutes; O13 header wording; fixture-name note in the Spec Change Log). Deferred: none. The other 16 rejected with reasons in the Review Triage Log.
- Follow-up review recommendation: false (no high patched, one medium at most: none).
- Verification: `node --test web/scripts/on-call-view.test.mjs` 23 pass; `npm --prefix web test` 2003 pass; lint pass; build initial total 878.98 kB (budget warnings pre-existing, no error), `initial-bundle.test.mjs` pass; `docker/tests/test-boundaries.sh` pass; live `sign-in-2 --part 12/15` on lane-B `e36s6i`: 23 passed (O1 to O13), run again after the review patches; throwaways torn down, no `e36s6` container left. Mutations (three) recorded under Verification, each reverted by hand and byte-identical.
- Residual risks: part number moved from 13/15 to 12/15 because the spec file grew (re-find the part after later edits). The commit step of Finalize was not run: the caller commits.

## Tests Added

QA stage (Story 36.6; web-only, no product code change; each new test has a mutation line under Verification):
- `web/scripts/on-call-view.test.mjs` (23 to 25 cases): "judges the backup by the list as it judges the on-call person, whoever the other role is" (backup alone with the on-call person Nobody: listed unpaired reads unchecked and sends Email alone, a listed-absent user keeps both boxes, a paired one keeps Telegram); "keeps a stored Telegram-only channel of a user the list does not hold, with Email unchecked, and sends it alone" (list `[]`, both roles).
- `web/e2e/settings/on-call.spec.ts`: **O14** (list holding users: a listed user who has not paired keeps Telegram unchecked and disabled with the one unpaired line, and a save sends Email alone for them, while a stored backup the list lacks keeps a Telegram-only channel, enabled, Email unchecked, with no line, and the save sends `telegram`; the "no paired chat" line is counted once on the page); **O15** (list unavailable, the on-call person Nobody, a stored backup with a Telegram-only channel: the box stays checked and enabled, Email stays unchecked, no line, and the save sends `telegram`); **O16** (real server: a stored backup whose session row is gone keeps Telegram enabled and the stored Email box, and a save is refused with the unknown-user text under the backup's Person select, with GET and the audit log unchanged).
- Live part 12/15 of sign-in-2 now holds 26 tests (was 23); passed on lane-B `e36s6q1`.
