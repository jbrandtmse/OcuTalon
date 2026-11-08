---
title: 'Story 18.2: Set the time zone and the daily digest at run time'
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: '8e5e9f1842becc37445ab1a01ba4a42782b77e07'
baseline_commit: '8e5e9f1842becc37445ab1a01ba4a42782b77e07'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-18-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/33-1-task0-zone-measurement.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The Playwright cases S9 to S12 (Time zone, Daily digest, Send my digest now, Channels) have no observed mutation line, because the browser tier runs only in CI.
    evidence: |-
      Rule 19 asks for a mutation observed red. S9 to S12 are written but were not run here (group shards-4, live:sign-in-2). Their pure-function twins in
      web/scripts/settings-view.test.mjs have the AC 5 mutation. Settle it in the CI pass: drop the saved-text check or the InstanceZone body field and watch S9 go red.
    location: >-
      web/e2e/settings/settings.spec.ts:S9-S12
    severity: low
  - summary: >-
      Data.Time.Zone() falling back to OsZone() is pinned only through OsZone(), because /etc/localtime cannot be redirected in a test.
    evidence: |-
      On a UTC host both sides of the Zone() assertion are UTC, so deleting the OsZone() step in Zone() stays green. A seam (a link parameter on Zone) would
      settle it; the spec fixed the strategy (matrix row "TZ unset, OS zone"), so this is a spec-level limit. The spec's ledger also notes residual (a): a zone that is set
      and then cleared converts in UTC on a TZ-unset non-UTC host (Bridge.Time.Apply, Lane A).
    location: >-
      src/ocutalon/cls/OcuTalon/Data/Time.cls:Zone
    severity: low
---

<intent-contract>

## Intent

**Problem:** An admin can't change the instance's time zone or the daily digest from the web app. The Settings page shows "This part of OcuTalon isn't built yet." for Daily digest, Time zone and Channels, and there is no **Send my digest now** button. Underneath, three things are missing. `OcuTalon.Data.Time` still reads the zone from `TZ`, so a saved zone reaches message text only after the bridge happens to apply it first in the same job. `FromLocal` returns either instant of the repeated fall-back hour, depending on what the job converted just before (DW-643). And `Notify` sends a `digest` on the generic route instead of to `digest.channels` (DW-820).

**Approach:** Most of the server side already exists: the zone and digest save paths (Stories 17.4 and 33.2), the `SendDigest` verb, and `Digest`'s own narrowing to the chosen channels (Story 17.6). This story fills the gaps:

- `Data.Time` follows `Bridge.Time` (calls `Apply()`, takes `Zone()` from the bridge first, falls back to the OS zone, and picks fold 0 in the repeated hour).
- `Notify` gets a `digest` branch that reads `digest.channels`.
- A web route submits `SendDigest`.
- The page gets three sections: Time zone, Daily digest (with **Send my digest now**) and Channels (read-only Telegram state).
- A real-runtime test changes all three values on a running production and watches them apply within a minute, with no restart, and audited.

## Boundaries & Constraints

**Always:**
- Every save goes through the one writer, `SettingsOps`, as a `SaveSettings` command with origin `web_admin`. Settings audits each changed value (`Settings` audit entry); a refused value changes nothing and writes no entry.
- Zone values go through the bridge allow-list: `Bridge.Settings.Check`/`Set` reach `Bridge.Time.CheckZone`/`SetZone`. This is already built. Call it as it is.
- `Data.Time` stays the only converter outside the bridge. It calls `##class(OcuTalon.Bridge.Time).Apply()` first in `ToLocal`, `FromLocal` and `ForMessage`, and never uses `$ZTIMEZONE` or Python.
- Stored and sent times stay UTC. Pending reminders keep their stored `DueAt`. Page times stay in the browser's zone.
- A `digest` Notification goes to the session's own channels that `digest.channels` also names:
  - "own" means: web always, phone while demo mode is on, Telegram while the session is paired.
  - When `digest.channels` has no row, the default is `SettingsOps`' declared one.
  - A name that isn't one of the three never adds a target.
  - A digest never falls through to the generic route.
- New user-facing strings are exactly those under PUBLIC TEXT (proposed), as ruled. `web/scripts/ux-strings.test.mjs` sources every one of them.
- No key or token value appears on the page, in an API answer, in an audit entry or in a log. The Channels section reads only the `/v1/state` Telegram block, which carries no token.
- Tests restore what they change: `InstanceZone`, `digest.time`, `digest.channels`, demo mode, and the process zone. Tests that need the running production run on a lane-D throwaway, never on a slot.

**Never:**
- Edit Lane A files (U-177). Out of bounds: `src/bridge/**`, `Digest/**`, `Checks/**`, `Channel/Telegram/**`, `Channel/DigestText.cls`, `Msg/Catalog/Watch.cls`, `Agent/**`, `Tools/**`, `Watch/**`, `Install/**` and Lane A test folders.
- Edit the contended Epic 17 paths: `Channel/WebChat/Out.cls`, `Test/Core/WebChatOut.cls`, `web/src/app/chat/**` and `web/e2e/chat/notice.spec.ts`.
- Change `Core/CommandsIn.cls`. The `SendDigest` route is already built.
- Edit `release/**` or `eval/run.sh`.
- Build any restart path. Story 33.1 measured that the zone applies at run time, so the AC's fallback clause does not apply.
- Delete `Digest.Process.Own` or the direct sends. Those are Lane A's (see the declined DW-820 half).
- Show, enter or store the Telegram bot token.
- Add a zones-list endpoint or a schema change.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Zone follows bridge | `InstanceZone` saved as `Asia/Kolkata`; a job's first call is a `Data.Time` call (no earlier `Bridge.Time` call) | `ToLocal`, `ForMessage` and `FromLocal` convert in Kolkata. `Zone()` = `Asia/Kolkata` | none |
| Zone cleared | `InstanceZone` = "" after a zone was applied | conversions go back to the inherited `TZ`. `Zone()` reports `TZ` | none |
| TZ unset, OS zone (DW-34) | `InstanceZone` "", `TZ` unset, `/etc/localtime` resolves to `/usr/share/zoneinfo/X` | `Zone()` = `X`. The UTC aliases (`Etc/UTC`, `Etc/UCT`, `Etc/Universal`, `Etc/Zulu`, `UTC`, `UCT`, `Universal`, `Zulu`) report `UTC`. An unresolvable link reports `UTC` | never throws |
| Fold 0 (DW-643) | `FromLocal` of a repeated-hour time (New York `2026-11-01T01:30:00`, Berlin `2026-10-25T02:30:00`, Sydney `2026-04-05T02:30:00`), after each of six preceding calls: none (fresh), a winter or a summer `ToLocal`, a winter or a summer `FromLocal` (Task 0's `Probe.Ambig` orders), and a conversion in another zone | always the first instant (`2026-11-01T05:30:00Z`, `2026-10-25T00:30:00Z`, `2026-04-04T15:30:00Z`) | none |
| Gap kept | NY `2026-03-08T02:30:00` | `07:30:00Z`, as today | none |
| Digest route (DW-820) | Notification `Kind=digest`, demo on, session unpaired; `digest.channels` = `web` | WebChatOut only | none |
| Digest route default | no `digest.channels` row | the same targets as the generic route | none |
| Digest route empty | `digest.channels` = `phone` with demo off; or `telegram` with the session unpaired | no target. The generic route is never taken | none |
| Send now | admin presses **Send my digest now** | `POST /v1/settings/daily-digest/send` gives 202 `{"result":"sending"}`. One `SendDigest` (origin `web_admin`, the CSP session's `SessionRef`, a fresh `IdempotencyKey`). The button follows the busy pattern | non-Ok gives 500 `server_error`, logged; the page shows the proposed failure text. A non-admin gets 403 `not_admin` |
| Hidden channels kept | demo mode off, so the phone box is hidden; the stored value is `web,phone` | saving with web checked keeps `phone` in the body | a body with no channel gets 400 `bad_settings` (the existing field error) |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- `ToLocal` :54, `FromLocal` :68-82 (the doc at :66 promises the first instant), `ForMessage` :88, `Zone()` :106-110 (reads `TZ`). None of them calls `Apply()` yet.
- `src/bridge/cls/OcuTalon/Bridge/Time.cls` (read only) -- `Zone()` :29, `CheckZone` :36, `SetZone` :53 (needs an active production), `Apply()` :72-90 (keeps its state in `^||OcuTalon.Bridge.Time`; with an empty name and no earlier apply it does nothing).
- `_bmad-output/implementation-artifacts/evidence/33-1-task0-zone-measurement.md` -- :10/:14 run time with no restart fallback; :55-72 the fold table; :218 how `Data.Time` should call `Apply`.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- the `Notification` rule, first match wins. Add the `digest` branch before the generic whens.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls` -- `DemoOn`, `TelegramOn`, `TelegramPaired`. Extend it with the digest-channel function (Rule 2).
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `XData Sections` :779-799 (`daily-digest` with its defaults; `time-zone` is a bridge section), `Section(slug)` :808, `Values()` :825. No change; the Notify function reads the default through `Section`.
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls` (read only) -- `Named` :741, `Channels` :726, `Deliver` :755 (Notify only when the channels equal `Own`), `Own` :882, `Requested` :391 (answers `Ok 1, Outcome sending`).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- routes :186-193; `IsSettingsUrl` :251 (the admin gate for every `/v1/settings/...` path); `SaveSection` :778; the sibling to extend is `RunHeartbeat` :1446 (202). `/v1/state` :993-1002 carries `telegram`.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls` (read only) -- `Preamble` :55 uses `Data.Time.ToLocal` and `Zone()`.
- Tests:
  - `Test/Data/Time.cls` -- `TestUnsetZone` and `TestNewYorkZone` assert the old `Zone()`.
  - `Test/Schedule/ReminderZone.cls` -- the New York fold case at :30.
  - `Test/Bridge/ZoneCase.cls` (Lane A base; extend it, don't edit it).
  - `Test/Core/Routing.cls` -- `TestNotifyTargets` :191 (digest on the generic route at :216), `TestFunctions` :246, `TestRuleTargetsAreProductionItems` :310.
  - `Test/Web/SettingsApi.cls` -- `TestNonAdminIs403Everywhere` (the seven POST routes).
  - `Test/Core/InProduction.cls` (production test base).
  - `Test/Digest/Send.cls` :125-135 -- the pattern for a backdated fixture session and a `SendDigest` submit; read only.
  - `Test/Digest/Compose.cls` :741 `TestOwnMatchesNotify` (Lane A) -- must stay green unchanged.
- `web/src/app/settings/settings-page.ts` -- nav :41-49 and the `@switch` that falls to `notBuilt`; `keepDemoMode`-style updaters :205.
- `web/src/app/settings/settings-view.ts` -- `SETTINGS_TEXTS` :19-52 and `SETTINGS_SECTIONS`.
- `web/src/app/settings/check-thresholds-section.ts` -- the section sibling to extend (inputs, `saved`/`dirtyChange`/`denied`).
- `web/src/app/shared/server-button.ts` -- the busy pattern.
- `web/src/app/rail/telegram-card/telegram-card-view.ts` (import, don't edit) -- `TELEGRAM_CARD_TEXTS.paused`/`tryingAgainAt`, `telegramPaused`, `telegramCardView`.
- The rail's `readmeSection(README_URL, TELEGRAM_ANCHOR)` and `RAIL_TEXTS.telegramNotSetUp`/`telegramHowTo` -- the README link.
- `web/src/app/api/api-client.ts` :55 `saveSettings`, :206 `runHeartbeat`; `api-types.ts` :177-188 `SettingsSections`.
- `web/e2e/settings/settings.spec.ts` -- S1 :86-95 expects Daily digest and Time zone to be not built. It runs in the sign-in-2 project.
- `web/scripts/settings-view.test.mjs`, `web/scripts/ux-strings.test.mjs` (`SOURCES` :170, `IMPORTED` :67).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- (DW-34, DW-643):
  - `ToLocal`, `FromLocal` and `ForMessage` call `Bridge.Time.Apply()` first.
  - `Zone()` returns, in this order: `Bridge.Time.Zone()` when it is non-empty and `CheckZone` accepts it; else `TZ`; else `OsZone()`; else `UTC`.
  - Add `ClassMethod OsZone(link As %String = "/etc/localtime") As %String`: `%File.ResolvePath(link)` with the `/usr/share/zoneinfo/` prefix removed, the UTC aliases reported as `UTC`, and "" when it can't resolve.
  - `FromLocal`: after today's conversion `u`, return the earliest of `u-3600`, `u-1800` and `u` whose `ToLocal` gives back `local`. The gap behaviour stays as it is. Correct the doc comments to the contract.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls` -- add `DigestNamed(channel As %String) As %Boolean`: 1 when `channel` is in `Data.Setting.Get("digest.channels", <SettingsOps.Section("daily-digest") channels default>)`, compared trimmed and lowercased. Any error gives 0 (footprint extension; DW-820).
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- (DW-820) a `digest` branch ahead of the generic whens. It sends to each of WebChatOut (`DigestNamed("web")`), SimPhoneOut (`DemoOn() && DigestNamed("phone")`) and TelegramOut (`TelegramPaired(ref) && DigestNamed("telegram")`), and to nothing when none holds.
  - Within one `<rule>`, Ens takes the first `<when>` that matches. Use explicit when-combinations, or check against `irislib` (`Ens/Rule/*`) whether sends from several rules add up, before relying on that.
  - Update the class doc.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- route `POST /v1/settings/daily-digest/send` -> `SendDigest()`, modelled on `RunHeartbeat`:
  - The `SessionRef` comes from `Ownership.SessionRef`, plus a fresh `IdempotencyKey`, then `Commands.Submit(command, "web_admin", .result)`.
  - Ok gives 202 `{"result":"sending"}`. Anything else gives 500 `server_error`, logged.
  - The admin gate already covers the path.
- `web/src/app/api/api-client.ts`, `api-types.ts` -- add `sendDigest()` (POST, 202) and the `'time-zone'` body type.
- `web/src/app/settings/time-zone-section.ts` (new) -- a select of `Intl.supportedValuesOf('timeZone')`, plus the stored value if it isn't in that list, plus the empty "Server default" option, preselected from `bridge.InstanceZone`. It saves `{InstanceZone}` with the section pattern (Save changes, saved/failed texts, field error, dirty).
- `web/src/app/settings/daily-digest-section.ts` (new):
  - A time input, `HH:MM`.
  - Channel boxes: the web chat always; the simulated phone only while demo mode is on; Telegram only when Telegram is included and on or paused.
  - Hidden channels keep their stored state in the body, which is always in the `web,phone,telegram` order.
  - Save through `saveSettings('daily-digest', ...)`.
  - A separate `<app-server-button>` **Send my digest now** calls `sendDigest()` and shows the proposed confirmation or failure text.
- `web/src/app/settings/channels-section.ts` (new) -- read only, from `LiveState`'s `telegram` block and status conditions, through `telegramCardView`/`telegramPaused`:
  - Not set up (`off`/`rejected`): "Telegram not set up" with "How to set it up" (the README `#telegram` link, opening in a new tab the way the rail does).
  - Paused: "Telegram paused" and "Trying again at {time}" (page time).
  - Otherwise: the proposed on text.
  - `included=false`: no Telegram block.
  - No Save button, no token field.
- `web/src/app/settings/settings-page.ts`, `settings-view.ts` -- `@case` for `channels`, `daily-digest` and `time-zone`; `keepDailyDigest`/`keepTimeZone` updaters; new texts in `SETTINGS_TEXTS`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Time.cls` -- update the two `Zone()` tests to the new order, with no bridge row.
- `src/ocutalon/cls/OcuTalon/Test/Data/TimeSource.cls` (new; extends `Test.Bridge.ZoneCase`; throwaway and CI only, because `SetZone` needs the production):
  - the matrix rows Zone follows bridge, Zone cleared, TZ unset OS zone (through `OsZone` on a zoneinfo path and on `/etc/localtime`), Fold 0 (3 zones x 6 call orders) and Gap kept;
  - a 290-instant walk across the 2025 changes comparing `Data.Time` with `Bridge.Time` after `SetZone("America/New_York")` and then `SetZone("Europe/Berlin")`, with `Data.Time` converting first after each change;
  - `Agent.Input.Preamble` shows the new zone and local time;
  - a pending reminder's stored `DueAt` is unchanged by a zone change while its `ForMessage` text moves.
- `src/ocutalon/cls/OcuTalon/Test/Core/Routing.cls` -- `TestNotifyTargets`: kind `digest` across demo on/off, included or not, paired or not, and `digest.channels` (no row, each single channel, `web,phone`, all three), cleared and restored per test. `TestFunctions` adds `DigestNamed`.
- `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` -- add the send route to `TestNonAdminIs403Everywhere`. `TestSendDigest`: an admin's POST answers 202 `{"result":"sending"}` and the production records one requested `Sent` row for the CSP session.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsRunTime.cls` (new; extends `Test.Core.InProduction`; throwaway and CI only) -- see AC 4.
- `web/scripts/settings-view.test.mjs` -- the channel-box visibility rules, hidden channels kept and the body order, zone options (current value kept, empty option), and the new text pins.
- `web/scripts/ux-strings.test.mjs` -- `SOURCES` entries for every new string (`ux:` where EXPERIENCE.md has it verbatim, else `ruled:` with the Planner's ruling label).
- `web/e2e/settings/settings.spec.ts` -- in S1, leave only Budgets as not built. Add S9 (Time zone save shows the saved text, and the GET returns the zone, then puts it back), S10 (Daily digest save and the channel boxes for the stack's demo mode) and S11 (Send my digest now: busy, then the confirmation).
- (No spine edit in this story: struck by the lead at the spec gate. AD-18 already says the run-time source is "an IANA zone name, or empty for the container's `TZ`", which with `TZ` unset is the inherited OS zone, so the DW-34 fallback complies as written (doctrine U7 step 1). The proposed clarifying sentence goes to the orchestrator (U14); do NOT edit `ARCHITECTURE-SPINE.md` and do NOT run `lint_spine.py` for it.)

- [x] [Smoke] S9 fails in the lead's per-story smoke (fresh lane-D live:sign-in-2 --part 3/3, OCUTALON_LIVE_DEADLINE=1200): `page.getByLabel('Time zone', { exact: true })` resolves to 2 elements (the Time zone section, a region named by its heading, and the select), a Playwright strict-mode violation -- `web/e2e/settings/settings.spec.ts:553` and `:566` -- target the select unambiguously (e.g. `getByRole('combobox', { name: 'Time zone', exact: true })`, scoped to the section if needed), with no product change; S10-S12 and S1-S8 passed in the same run. Check the other new specs (S10-S12) for the same label/region ambiguity.

**Acceptance Criteria:**
- **AC 1.** Given an admin picks a zone in Time zone and saves, when the save answers, then:
  - the page shows "Saved. Applies within a minute. Recorded in the audit log.";
  - `SettingsOps` has written it through `Bridge.Settings`;
  - with no restart, `Data.Time` in a production job converts message times, "Thursday at 10" phrasing, the digest due time and the model preamble in the new zone, and `Test.Data.TimeSource`'s DST walk agrees with `Bridge.Time` under the changed zone;
  - pending reminders keep their UTC `DueAt`, and page times stay in the browser's zone (`page-time.ts` unchanged).
- **AC 2.** Given the Daily digest section, when an admin sets the time and channels and saves, then:
  - `digest.time` and `digest.channels` are stored as product values;
  - a `digest` Notification sent to the `Notify` item reaches only the chosen channels the session has, from the next digest (within the 60-second `Setting.Get` cache).
- **AC 2a (Integration, Rule 1).** Given the running production, when `Digest` sends (consumer `Digest.Process.Deliver` with `digest.channels` equal to `Own`, through `Notify`; or a strict subset, direct), then the fixture session's `kind digest` Delivery rows exist only for the chosen channels.
- **AC 3.** Given an admin presses **Send my digest now**, when the request answers, then:
  - the button followed the busy pattern;
  - one `SendDigest` with origin `web_admin` was submitted for the admin's session;
  - the digest's `kind digest` Delivery rows appear only on the chosen channels. The button is pinned by S11; the route and the submit by `Test.Web.SettingsApi` `TestSendDigest`; the arrival by `Test.Core.SettingsRunTime`.
- **AC 4.** Given `Test.Core.SettingsRunTime` saves the zone, the digest time and the digest channels through `Commands.Submit` (origin `web_admin`), when it watches for at most 75 s, then:
  - demo mode is on for the run: if the stack has it off, the test sets the `demo.mode` row to `1` and puts it back afterwards;
  - a reminder Notification sent to the `SimPhoneOut` item (through a service, as `Test.Core.RoutingProduction` sends) gives a SimPhone message whose time is in the new zone;
  - with `digest.channels` = `web`, a backdated fixture session gets one scheduled digest:
    - its `Sent.DueAt` is the new `digest.time` in the new zone;
    - the test picks the time and the backdating so that the session is due under the new values and not under the values held before, whatever the wall clock;
    - its `kind digest` Delivery rows are on web only, with none on phone;
    - the test sends Ticks through `Checks`, as `Test.Digest.Send` does;
  - next, a `SendDigest` submitted the way `Api.SendDigest` submits it (origin `web_admin`) gives one requested digest, whose `kind digest` Delivery rows are again on web only (AC 3's arrival);
  - three `Settings` audit entries are read back from the IRIS audit log;
  - the production's start time is unchanged.
- **AC 5.** Given the Channels section opens, when Telegram is not set up, on, or paused, then it shows that state (with the README link, or with "Trying again at {time}"), and no token is shown or asked for.

### Review Findings

Code review 2026-11-08 (four layers, review tier full-opus; 39 raw rows, 18 entries after grouping, 18 rows rejected). Every patch was applied in the review pass; dispositions follow Rule 15.

- [x] [Review][Patch] HIGH `Test.Web.Api` `TestRoutes` still expected 25 routes; the URL map has 26 with the send route, so `shard:lane-b` would go red (verification-gap, acceptance-auditor) [src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:953] -- added `POST /v1/settings/daily-digest/send SendDigest` in map order, 26. Fix-risk low (list and count). Contended with OCT-epic41, which edits the same line (its own four routes; the merge is 30).
- [x] [Review][Patch] HIGH S11's second press clicked an `aria-disabled` button, which Playwright waits on until the 45 s timeout, because the gate opens only after it (edge-case-hunter) [web/e2e/settings/settings.spec.ts:627] -- `click({ force: true })`, as `heartbeat-card.spec.ts` does. Fix-risk low.
- [x] [Review][Patch] MED `Data.Time.Zone()` did not call `Bridge.Time.Apply()`, so after `InstanceZone` was cleared a process that had applied a zone reported the stale `TZ` (`/v1/state` `instanceZone`, `ListReminders`) until its next conversion (blind-hunter, edge-case-hunter) [src/ocutalon/cls/OcuTalon/Data/Time.cls:118] -- `Zone()` applies first; `TestZoneCleared` now reads `Zone()` before any conversion (mutation below). Fix-risk low.
- [x] [Review][Patch] MED `SettingsRunTime` skipped the process-zone restore when `$SYSTEM.Process.TimeZone()` gave "" (measured on slot D: a fresh process gives "", not -1), leaking the test zone into later classes (edge-case-hunter; Rule 19 hermeticity) [src/ocutalon/cls/OcuTalon/Test/Core/SettingsRunTime.cls:72] -- the restore is unconditional (`PutZone` maps -1 and "" alike). Fix-risk low.
- [x] [Review][Patch] MED No test reached the send route through the URL map as an admin, though AC 3 names "the route" (acceptance-auditor) [src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:953] -- closed by the `TestRoutes` patch, which pins the route-to-`SendDigest` entry.
- [x] [Review][Patch] LOW S12 chose "paused" from `telegram.pausedUntil`, which the page never reads (blind-hunter, edge-case-hunter, verification-gap) [web/e2e/settings/settings.spec.ts:652] -- it now reads the snapshot's active `telegramPaused` condition, the card's own rule.
- [x] [Review][Patch] LOW The Daily digest form opened dirty when the saved channels were only hidden ones (for example `phone` with demo mode off), so leaving asked about unsaved changes with no edit (edge-case-hunter) [web/src/app/settings/daily-digest-section.ts:216] -- `isDigestFormDirty` compares the time and the shown boxes only (unit test and mutation below).
- [x] [Review][Patch] LOW The DST walk's Berlin half crossed none of Berlin's 2025 changes, and Bridge.Time converted first at each instant (verification-gap) [src/ocutalon/cls/OcuTalon/Test/Data/TimeSource.cls:147] -- per-zone windows (Berlin 2025-03-29 and 2025-10-25, still 290 instants), Data.Time first.
- [x] [Review][Patch] LOW `Test.Web.BodyLimit` `POSTROUTES`, "every POST route", lacked the send route (verification-gap) [src/ocutalon/cls/OcuTalon/Test/Web/BodyLimit.cls:14] -- appended, 18. Contended with OCT-epic41 (it appends its own; the merge is 19).
- [x] [Review][Patch] LOW S10's clean-up checked only that the time came back (blind-hunter) [web/e2e/settings/settings.spec.ts:606] -- also checks the channels.
- [x] [Review][Defer] LOW `Api.SendDigest`'s non-Ok 500 branch has no test (verification-gap) [src/ocutalon/cls/OcuTalon/Web/Api.cls:1496] -- deferred: DW-942 wontfix-accepted (needs a submit seam; unreachable today).
- [x] [Review][Defer] LOW The two new forms' refusal wiring (400 field error and focus, 403) runs in no test (blind-hunter, verification-gap) [web/src/app/settings/time-zone-section.ts:213] -- deferred: DW-943 wontfix-accepted.
- [x] [Review][Defer] LOW AC 2a's through-Notify path is pinned in halves, never in one real Digest send (acceptance-auditor) [src/ocutalon/cls/OcuTalon/Test/Core/SettingsRunTime.cls:186] -- deferred: DW-944 wontfix-accepted (Test.Digest.Send pins Digest to Notify; this class pins Notify to Delivery).
- [x] [Review][Defer] LOW The spine's REST surface table lacks the send route; its channels row is stale (acceptance-auditor) [ARCHITECTURE-SPINE.md, REST table] -- deferred: DW-945 wontfix-accepted, for the lead's close-time AD-14 edit.
- [x] [Review][Defer] LOW S10 and S12 follow the stack's ambient demo and Telegram state, one branch per run (verification-gap) [web/e2e/settings/settings.spec.ts:575] -- deferred: DW-946 wontfix-accepted (the pure twins pin every branch).
- [x] [Review][Defer] LOW Rule 2: `SettingsRunTime` copies Lane A's private Sent helpers and `SettingsApi` has its own `WaitSent` (reviewer) [src/ocutalon/cls/OcuTalon/Test/Core/SettingsRunTime.cls:293] -- deferred: DW-947 wontfix-accepted.
- [x] [Review][Defer] LOW Rule 2: the new sections repeat the sections' refusal block (reviewer) [web/src/app/settings/daily-digest-section.ts:275] -- deferred: DW-948 wontfix-accepted, reopen when Story 18.3 adds a fifth copy.
- [x] [Review][Defer] MED After `Bridge.Time.Apply` puts an inherited unset `TZ` back as `TZ=""` (UTC), `Zone()` names the OS zone on a TZ-unset non-UTC host (edge-case-hunter) [src/bridge/cls/OcuTalon/Bridge/Time.cls:Apply] -- deferred: an occurrence on DW-34 (Lane A, `Bridge.Time.Apply`; the residual (a) the Design Notes give the lead).

Rejected:
- low: the zone list can show `Asia/Kolkata` beside the browser's `Asia/Calcutta` (blind-hunter) -- cosmetic, and both names have zone files; an alias map adds complexity; a name the container lacks gets `CheckZone`'s refusal (Decided in-stage 6).
- by-design: a Telegram box that hides while the form is open falls back to the stored value (blind-hunter) -- Decided in-stage 4, hidden channels keep their stored state.
- by-design: the Channels section shows nothing for a release without Telegram (blind-hunter) -- the spec says "included=false: no Telegram block"; the unloaded case is transient.
- by-design: `ForMessage` calls `Apply()` before its `ToLocal` calls (blind-hunter) -- the Tasks require it; the extra calls are a cached setting read.
- low: assertions repeated between `Test.Data.Time` and `Test.Data.TimeSource` (blind-hunter) -- no named harm.
- by-design: a copied `/etc/localtime` or a symlinked zone folder gives `UTC` (edge-case-hunter) -- the matrix row says an unresolvable link reports UTC.
- wontfix-theoretical: `posix/` or `right/` link targets (edge-case-hunter) -- the images link to the plain zone files; real once an image ships a `right/` link.
- by-design: folds over 60 minutes (Antarctica/Troll) (edge-case-hunter, twice) -- the Tasks fix the candidates at 3600 and 1800 s.
- by-design: Notify and Digest read `digest.channels` through their own 60 s caches (edge-case-hunter) -- AC 2 states the cache window.
- by-design: an empty digest `<when>` leaves no trace (edge-case-hunter) -- the spec says no target.
- low: production caches keep the test's digest rows for up to 60 s after `SettingsRunTime` (edge-case-hunter) -- already triaged at implement; no later class in the shard reads them through the production.
- false: AC 4's phone text and start time lack mutation lines (verification-gap) -- Rule 19 needs one per AC; AC 4 has three, and the spec says why these two can't be mutated.
- low: `TestReminderKeepsDueAt`'s DueAt and State asserts can't fail (verification-gap) -- already triaged; the `ForMessage` pair carries the AC 1 mutation.
- low: `TestUnsetZone`/`TestZoneFromOs` derive their expected value from `OsZone()` (verification-gap) -- not the pinning test; QA's seam test pins DW-34 with a mutation.
- false: `The simulated phone` and `Telegram on` are under `ux` (acceptance-auditor) -- the binding ruling puts strings EXPERIENCE.md holds under `ux`, and the test enforces it; the key label was given verbatim.
- low: DW-939 still reads open (acceptance-auditor) -- the lead's `ledger_adjudicated` gate closes it; the frontmatter is build-auto state.
- false: the added `UTC` choice is unruled text (acceptance-auditor) -- an IANA zone identifier shown as a value, like the browser's list.

## Spec Change Log
- 2026-11-08, rework iteration 1 (lead, trigger=smoke): the per-story smoke ran settings.spec.ts on a fresh lane-D stack; S9 failed on an ambiguous label locator (one [Smoke] item under Tasks & Acceptance). Scope: that item only.
- 2026-11-08, rework iteration 1 implement pass: S9's two `getByLabel('Time zone')` sites now use `getByRole('combobox', { name: 'Time zone', exact: true })`; S10-S12 checked, no other label meets a same-named region (`Send at` labels only the time input). No product change; the implement handoff subagent was not used (a two-line test edit, the rest of the story left as committed).
- 2026-11-08, PUBLIC TEXT ruling (Contest Planner under the owner's delegation, relayed by the orchestrator): rows 1-6 and 14 confirmed verbatim (reused); rows 8-13 and 15-17 approved as written; row 7 reworded to "Message times, reminders, the daily digest and the current time that OcuTalon gives the model use this zone. Times on this page stay in your browser's zone." All pinned with fixed strings; `ux-strings` ruling key `planner-2026-11-08-18.2`.
- 2026-11-08, AD-14 (Contest Planner ruling, relayed by the orchestrator): the interim sub-bullet at spine line 476 is reworded by the LEAD at this story's close/integrate-forward as an as-built correction, marker `[AMENDED 2026-11-08, Story 18.2, Contest Planner ruling]`. Not a stage edit: implement, QA and review do not touch the spine. AD-18's clarifying sentence waits for an attended `bmad-architecture` Update (nothing to do in this story).

- 2026-11-08, spec gate (lead, Epic 18 runner): struck the AD-18 spine edit from Tasks & Acceptance. Reason: doctrine U14 (a runner never amends an AD itself) and U7 step 1 (comply first): AD-18's Rule already covers an empty `InstanceZone` with `TZ` unset as the container's inherited zone. The clarifying sentence and AD-14's interim sub-bullet ("Until Story 18.2, Digest narrows ...") were sent to the orchestrator. Planned behaviour is unchanged.

## Review Triage Log

### 2026-11-08 — Review pass (rework 1, S9 locator)
- verdicts: 5 findings — high 0, medium 0, low 5, false 0, maybe-false 0
- findings:
  - `low` `reject` The same role locator appears twice in S9 — two sites on purpose (before and after a reload); a shared helper adds structure for no named harm.
  - `low` `patch` No comment says why the role is needed — added a one-line contract comment at the first site in `web/e2e/settings/settings.spec.ts`.
  - `low` `patch` (verification-gap) S9 has no `mutation:` line — written in `## Verification` as "not observed locally (DW-938)", per the pre-answered override; the existing frontmatter `deferred:` item for S9 to S12 stands.
  - `low` `reject` (verification-gap) S9's preselect assertion can pass on a stack with an empty stored zone — pre-existing assertion, not changed by this diff; the post-reload check is non-vacuous; a fix needs a new precondition (more than a direct correction).
  - `low` `reject` (verification-gap) S9's restore sits in `finally` and could leak a zone if it fails — one worker, no race; the reviewer itself found it acceptable.
  - Edge-case hunter: no findings. Intent-alignment auditor: no divergence (the diff implements the narrow selector fix, page-wide form A1; S10-S12 need no edit).

### 2026-11-08 — Review pass
- verdicts: 24 rows covering the 32 findings the layers reported (the same defect reported by two layers shares one row, with every source named) — high 0, medium 6, low 17, false 1, maybe-false 0; the intent-alignment layer reported readings and divergences, no defects
- findings:
  - `[low]` `[reject]` Zone() names the OS zone while a TZ-unset non-UTC host converts in UTC (Blind Hunter 1, Edge 1, Edge 10) — spec-decided (Decided in-stage 1, matrix row DW-34); the set-then-cleared residual is already ledgered in Design Notes for the lead (Lane A, `Bridge.Time.Apply`); a TZ-unset process otherwise converts in its inherited OS zone; fix would need a Lane A change.
  - `[medium]` `[patch]` Midnight flake in `SettingsRunTime`: the digest time (now minus 2 h) lands on the previous local day for Kolkata or Kathmandu for about 2 h of each UTC day (Blind Hunter 2) — the test now picks, from six fixed-offset zones, one whose local day is at least 2 h old and whose offset differs from the one in force; passed twice.
  - `[low]` `[reject]` `TestOsZone` zoneinfo assertions are unguarded (Blind Hunter 3) — the zone tests need /usr/share/zoneinfo anyway (`CheckZone`), and every CI image has it.
  - `[low]` `[reject]` `TestReminderKeepsDueAt` DueAt and State asserts cannot fail (Blind Hunter 4, Verification Gap 4) — spec-prescribed guard; the `ForMessage` pair can fail (AC 1 mutation) and the mutation note says which part is structural.
  - `[medium]` `[patch]` The Time zone select has no UTC (Chromium and Node list only Asia/Calcutta and no UTC) and S9 chose Asia/Kolkata, which the browser does not list (Blind Hunter 5, Edge 8, Verification Gap 10) — `zoneOptions` now adds UTC when the browser list lacks it (unit-tested), S9 uses Asia/Tokyo and Europe/Berlin. Verified with `Intl.supportedValuesOf` in Node 26.
  - `[medium]` `[patch]` The Channels section has no browser test (Blind Hunter 6, Verification Gap 3) — S12 added (not built text gone, no Save button, no field, and the state that `/v1/state` holds: none, paused, not set up with the `#telegram` link in a new tab, or on); runs in CI.
  - `[low]` `[patch]` Duplicate import from live-state in `settings-page.ts` (Blind Hunter 7, Edge 9) — merged into one import.
  - `[low]` `[reject]` Unused `TimeZoneBody` type (Blind Hunter 8) — the type was asked for by the Tasks as documentation of the body; removing it is churn.
  - `[low]` `[patch]` Garbled sentence in the `Test.Web.SettingsApi` header (Blind Hunter 9) — reworded.
  - `[low]` `[reject]` `DigestNamed` repeats lookups across the eight whens (Blind Hunter 10, Edge 7) — correct and cheap (cached `Setting.Get`); a single target function is a larger change than a direct fix.
  - `[low]` `[reject]` `FromLocal` costs up to two extra `ToLocal` calls, and only 30- and 60-minute folds (Blind Hunter 11, Edge 3) — the algorithm is the spec's; only Antarctica/Troll has a fold over an hour.
  - `[low]` `[reject]` `OsZone` can return posix/ or right/ names (Edge 2) — /etc/localtime points at the plain zone file in the images; a bad name still passes `CheckZone` as a no-op.
  - `[medium]` `[patch]` Unchecking the only shown channel box saved the hidden channels alone, so a digest went to no one (Edge 4) — `digestChannelsBody` now returns an empty body when no shown box is checked, which the server refuses with the existing field error (spec matrix row "a body with no channel gets 400"); unit-tested.
  - `[low]` `[reject]` An empty digest `<when>` leaves no trace (Edge 5) and the `DigestNamed` catch logs nothing (Edge 6) — the spec says the digest goes to no target and any error gives 0.
  - `[low]` `[false]` The claim that Zone() disagrees with conversions (Edge 10) — same as the first row.
  - `[low]` `[reject]` `OsZone`/`Zone()` OS-fallback assertions restate the implementation (Verification Gap 1) — the strategy is the spec's; the strongest check available is recorded as a deferred item.
  - `[low]` `[reject]` No test for the `CheckZone` guard on a hand-written bridge zone (Verification Gap 2) — writing an invalid row needs the bridge's row writer (Lane A); `Bridge.Time.Apply` has the same guard under `Test.Bridge.*`.
  - `[medium]` `[patch]` AC 4 had one mutation line (Verification Gap 5) — two more observed and recorded (Apply removed, and the audit writer); the StartTime and phone-text asserts could not be mutated and are said so.
  - `[low]` `[defer]` S9 to S12 have no observed mutation (Verification Gap 6) — Playwright runs in CI only; deferred with what would settle it.
  - `[low]` `[patch]` The 30-minute fold (`u-1800`) was exercised by no case (Verification Gap 7) — `Australia/Lord_Howe` added to `TestFoldZero`; dropping 1800 goes red.
  - `[medium]` `[patch]` `TestFoldZero` reused process state, so only the first iteration was "fresh" (Verification Gap, other 1) — `Forget()` before every iteration; the Lord Howe mutation went red in the fresh order too.
  - `[low]` `[false]` Zone() does not call Apply (Verification Gap, other 3) — Zone() reads the bridge row and then the process environment, neither of which Apply changes, so it is right without a conversion first.
  - `[low]` `[reject]` `SettingsRunTime` leaves production jobs' 60 s digest cache warm (Verification Gap, other 4) — the classes that run after it in `Core` do not read the digest rows through the production.
  - `[false]` `[reject]` The intent-alignment layer's divergences (the run-time test saves through `Commands.Submit`, not through the HTTP route; S11 stubs the POST) — descriptive, and each is the spec's own division of pinning tests (AC 3 text).

## Design Notes

**Architecture decisions (Rule 6):** AD-1 (SendDigest is a production message), AD-2 (OcuTalon may call the bridge, never the reverse), AD-4 (`web_admin` takes the CSP session's Ref), AD-12 (Telegram state from `/v1/state`), AD-13 (admin gate), AD-14 (Notify's `digest` sub-bullet), AD-17 (one audit writer), AD-18 (the instance zone at run time, fold 0, the DST comparison test), AD-19 (`SettingsOps` is the one writer), AD-22 (production tests run on throwaways), AD-29 and AD-33 (lanes, U-177), AD-32 (the digest notification).

**Already met (evidence, not rebuilt):**
- The zone save runs through the allow-list and is audited: `SettingsOps.SaveBridge` :977-1022 and Lane A's `Test.Bridge.SettingsApply` `TestIntegrationSettingsOps`.
- The digest keys are saved, validated, stored in order and audited: `Test.Core.SettingsSave` `TestDigestSection`, `Test.Core.SettingsAudit` `TestDigestKeyAudited`.
- `SendDigest` from `web_admin` is accepted: `CommandsIn.cls:200` and `Test.Core.SettingsCommands`.
- Digest already narrows to `digest.channels`: `Digest.Process.Channels`/`Deliver`, Story 17.6.
- **The AC's fallback clause does not apply.** Story 33.1's Task 0 says "No restart fallback is needed" (evidence :14) and measured run-time changes of 0.07-1.16 s. So there is no restart sentence and no restart test.

**Decided in-stage:**
1. `Zone()` order and the UTC alias list, as in the Tasks, so Docker installs keep reporting `UTC` (`Test.Agent.Render` stays green).
2. Fold 0 is found by round-trip candidates. Only `ToLocal`, which Task 0 found right in every order, decides.
3. The digest-channel function goes in `Functions.cls` (extending the sibling) rather than a new function set.
4. Channel boxes: phone only in demo mode; Telegram only when included and on or paused. Hidden boxes keep their stored state.
5. Send route path and 202 `sending`, with a fresh key per press. A press after the 10-second busy notice may send a second digest; this is accepted.
6. Zone list from `Intl.supportedValuesOf`. Names the container lacks are refused by `CheckZone`'s field error.
7. Channels is read only. `POST /v1/settings/channels` stays 501, which `TestBridgeRoutesAre501` keeps.
8. Arrival is observed through Delivery rows. Until Epic 17 (17.10) merges and Story 18.4 renders the digest, WebChatOut and SimPhoneOut record a row with no visible text, so the browser tests assert the button and not the card.
9. `Test.Core.SettingsRunTime` turns demo mode on through the `demo.mode` row, not through the Demo step, and puts it back. Notify's `DemoOn` and Digest's `Own` read only that row. It sends the reminder straight to `SimPhoneOut`, so the zone check doesn't depend on the stack's mode.

**Consumes:**
- `Bridge.Time.Zone/CheckZone/SetZone/Apply` and `Bridge.Settings` (17.4)
- `SettingsOps` save path and Sections (33.2)
- `CommandsIn` `SendDigest` (33.2)
- `Digest.Process` (17.6)
- `StatusMark` Telegram state through `/v1/state` (10.3)
- `telegramCardView` and `ServerButton`

All are exercised against the real running production in `Test.Core.SettingsRunTime` and `Test.Web.SettingsApi`.

**Consumed-by:**
- `Digest.Process.Deliver` today, when the channels equal `Own`.
- Lane A's DW-820 follow-up, which sends every digest through `Notify`.
- Story 18.4, whose digest card and phone digest arrive through this route, and whose Playwright test covers these sections.
- Story 18.3, which adds Models and Budgets to the same page.

**Ledger (Rule 17):**
- DW-34: addressed by the `Data.Time.Zone`/`OsZone` task and the TZ unset row.
  - Residuals outside Lane B, for the lead to route to Lane A:
    - (a) `Bridge.Time.Apply` puts an inherited empty `TZ` back as `TimeZone("")`, which is UTC, not `/etc/localtime` (17.4 Edge 8). On a TZ-unset non-UTC host, a zone that is set and then cleared converts in UTC while `Zone()` reports the OS zone.
    - (b) The 17.5 occurrence: `Watch.Reader` stamps.
- DW-643: addressed (the Fold 0 row; `Test.Schedule.ReminderZone` then passes on its own merits).
- Declined DW-815: the fold of the coverage lines lives in `Checks.Coverage`/`Digest.Process`, and its count line in `Msg.Catalog.Watch`. All of these are Lane A's (U-177), and the new line is public text. It belongs to the Epic 17 follow-up (Lane A).
- DW-820, Notify half: addressed (the Notify and Functions tasks; AC 2 and 2a).
- Declined DW-820, Digest half: deleting `Digest.Process.Own`, `SendDigest`'s direct sends, `ROUTEREASON`, and `Test.Digest.Compose.NotifyChannels`/`TestOwnMatchesNotify` (and routing `Resent` through Notify) is Lane A's (`Digest/**`, `Test/Digest/**`). A Lane A story does it after this merges. AD-14's interim sub-bullet ("Until Story 18.2, Digest narrows ...") then needs the lead's rewording, which is not a stage edit.

**Access:** unchanged (admin-only via Story 33.2's check). The new route sits under `/v1/settings/`, so `IsSettingsUrl` gates it. No role, grant or origin changes. There is no VETO ITEM.

**Footprint extensions (Rule 11 b):** `Core/Rule/Functions.cls`, `web/scripts/settings-view.test.mjs` and `web/scripts/ux-strings.test.mjs`. None of them is in an open branch's diff (checked 2026-11-08). The spine is not edited (struck at the spec gate; see the Spec Change Log).

**PUBLIC TEXT (RULED 2026-11-08 by the Contest Planner under the owner's delegation, relayed by the orchestrator; use these strings exactly, pinned by fixed-string tests):**

| # | String | Source | File |
|---|--------|--------|------|
| 1 | Send my digest now | EXPERIENCE.md :972, verbatim | `settings-view.ts` |
| 2 | Telegram not set up | EXPERIENCE.md :383 (existing `RAIL_TEXTS`) | reused |
| 3 | How to set it up | EXPERIENCE.md :383 (existing) | reused |
| 4 | Telegram paused | EXPERIENCE.md :386 (existing `TELEGRAM_CARD_TEXTS`) | reused |
| 5 | Trying again at {time} | EXPERIENCE.md :386 (existing) | reused |
| 6 | Time zone (field label) | section label, existing | `settings-view.ts` |
| 7 | Message times, reminders, the daily digest and the current time that OcuTalon gives the model use this zone. Times on this page stay in your browser's zone. | RULED (reworded by the Planner) | `settings-view.ts` |
| 8 | Server default | RULED | `settings-view.ts` |
| 9 | Send at | RULED | `settings-view.ts` |
| 10 | In the instance's time zone. Applies from the next digest. | RULED (AC 2) | `settings-view.ts` |
| 11 | Send to | RULED | `settings-view.ts` |
| 12 | The web chat | RULED | `settings-view.ts` |
| 13 | The simulated phone | RULED (demo mode only) | `settings-view.ts` |
| 14 | Telegram | EXPERIENCE.md :188 | `settings-view.ts` |
| 15 | Sending your digest now. | RULED | `settings-view.ts` |
| 16 | Couldn't send your digest. Try again. | RULED | `settings-view.ts` |
| 17 | Telegram on | RULED | `settings-view.ts` |


**PUBLIC TEXT ruling for the implement stage (binding):** rows 1-6 and 14 are confirmed verbatim as reused UX strings; rows 7-13 and 15-17 are approved as written in the table above (row 7 as REWORDED there). Write them byte for byte, and pin every one with a fixed-string assertion (a test that compares the exact string, not a pattern). In `web/scripts/ux-strings.test.mjs` put the new strings that EXPERIENCE.md does not hold under `ruled`, keyed `'Story 18.2 ruling planner-2026-11-08-18.2 (the Contest Planner under the owner\'s delegation, 2026-11-08, relayed by the orchestrator: the Time zone help text (reworded by the ruling) and its Server default choice, the Daily digest labels Send at and Send to, its help line, the web chat and simulated phone channel names, the send-now confirmation and failure, and the Channels section\'s Telegram on)'`; the reused ones stay under `ux`. No other new user-facing string may ship.

The texts "Saved. Applies within a minute. Recorded in the audit log.", "Couldn't save. Nothing was changed.", "Save changes" and the busy notice are reused unchanged.

## Verification

Lane D variables (`$LANE_D` below):
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=18 stage=<stage>' OCUTALON_RUN_TAG=e18s2<stage letter>w`

**Runtime:**
- Slot D (`ocutalon-slot-d`, `OCUTALON`): compile changed classes with `iris_doc_load`.
- Every production test (zone saves need the active production, and nothing restarts it): one lane-D warm throwaway.

**Commands** (one per call, each about 150 s or less):
- `$LANE_D ci/warm.sh up` (setup) -- expected: the stack is ready.
- `$LANE_D OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Data.Time` (loop) -- expected: `CLASS ... passed`.
- `$LANE_D OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Data.TimeSource` (loop) -- expected: passed.
- `$LANE_D OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Schedule.ReminderZone` (loop) -- expected: passed.
- `$LANE_D OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Core.Routing` (loop) -- expected: passed.
- `$LANE_D OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Core.SettingsRunTime` (loop) -- expected: passed, in under 120 s.
- `$LANE_D OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Web.SettingsApi` (loop) -- expected: passed.
- `node --test web/scripts/settings-view.test.mjs` (loop) -- expected: all pass.
- `node --test web/scripts/ux-strings.test.mjs` (loop) -- expected: all pass.
- One `$LANE_D OCUTALON_WARM=1 ci/iris.sh class <C>` per line (once), for `C` in:
  - `OcuTalon.Test.Bridge.Time`
  - `OcuTalon.Test.Agent.Render`
  - `OcuTalon.Test.Tools.Reminders`
  - `OcuTalon.Test.Digest.Compose`
  - `OcuTalon.Test.Digest.Send`
  - `OcuTalon.Test.Core.SettingsSave`
  - `OcuTalon.Test.Core.SettingsAudit`
  - `OcuTalon.Test.Schedule.Reminders`
  - `OcuTalon.Test.Demo.SimPhoneOut`
  - `OcuTalon.Test.Core.RoutingProduction`

  Expected: all passed. A class that cannot finish in about 150 s is left to CI and named in the report.
- `npm --prefix web run lint` (once) and `npm --prefix web run build` (once) -- expected: exit 0.
- `bash docker/tests/test-boundaries.sh` (once) -- expected: pass.
- `$LANE_D ci/warm.sh down` (teardown).

**Left to CI** (they don't fit one call):
- Playwright S1, S9-S11 (`live:sign-in-2`, group `shards-4`).
- The full `shard:lane-a` and `shard:lane-b`.
- The fresh-environment check.

`Test.Core.SettingsRunTime` adds about 80-100 s to `shard:lane-b` (group `image`) (inference). It is in the Core area, so it needs no `ci/units.sh` change.

**Mutations (Rule 19, to apply and record):**
- AC 1: drop the `Apply()` call in `ToLocal` -> `TimeSource` walk red.
- Fold 0: return `u` only -> `TimeSource` fold red.
- AC 2: remove the digest branch -> `Routing` red.
- AC 2a/4: make `DigestNamed` return 1 -> `SettingsRunTime` channels red.
- AC 3: send origin `web_user` -> `SettingsApi` `TestSendDigest` red.
- AC 5: show the on text when paused -> `settings-view` red.

**Recorded mutations (implement stage, 2026-11-08; each applied, observed red, then reverted with the file's hash unchanged):**
- mutation: AC 1: dropped the `Apply()` call in `Data.Time.ToLocal` -> `Test.Data.TimeSource` red (`TestZoneFollowsBridge`, `TestZoneCleared`, `TestAgreesWithBridgeAfterSetZone` first-conversion asserts, `TestPreamble`).
- mutation: Fold 0: `FromLocal` ends `Quit utc` (the converted instant only) -> `Test.Data.TimeSource` `TestFoldZero` red (Berlin and Sydney in every order but one, New York after a winter `FromLocal`).
- mutation: AC 2: removed the eight `digest` whens from `Core.Rule.Notify` -> `Test.Core.Routing` `TestNotifyDigestTargets` red (the generic route is taken).
- mutation: AC 2a/4: `Functions.DigestNamed` ends `Quit 1` -> `Test.Core.SettingsRunTime` red on "its kind digest Delivery rows are on web only, with none on phone" (the digest sent to Notify reached the phone as well).
- mutation: AC 3: `Api.SendDigest` submits with origin `web_user` -> `Test.Web.SettingsApi` `TestSendDigest` red (500 `server_error`, no Sent row).
- mutation: AC 5: the paused Channels view returns the on view -> `web/scripts/settings-view.test.mjs` "says paused with the retry line ..." red.
- mutation: AC 4, the zone and the scheduled digest's `DueAt`: removed the three `Bridge.Time.Apply()` calls from `Data.Time` -> `Test.Core.SettingsRunTime` red ("its ToLocal converts in it", no scheduled digest is sent within 75 s, so `DueAt`, the clock and the requested digest fail).
- mutation: AC 4, the audit entries: `Bridge.Audit.Record` made to return OK before writing (restored byte-identical) -> `Test.Core.SettingsRunTime` red on "three Settings entries are read back from the audit log". (The same change to `SettingsOps.WriteAudit` was not seen by the running production host and stayed green, so it is not offered as evidence.)
- mutation: Fold 0, 30-minute fold: `FromLocal`'s loop reduced to `For back = 3600` -> `Test.Data.TimeSource` `TestFoldZero` red for Australia/Lord_Howe (5 of 6 orders).
- AC 4 `StartTime` unchanged and the phone text: no mutation could be applied from here (a restart is not buildable; the phone text is also produced by the same `ForMessage`). The phone assertion stayed green with `Apply` removed because the SimPhoneOut job already follows the bridge in this build.
- AC 1 "pending reminders keep their `DueAt`" (`TestReminderKeepsDueAt`): the `DueAt` and `State` asserts are a structural guard (nothing in `Data.Time` or the bridge writes a reminder); the 10:00/19:30 `ForMessage` pair is the part that goes red under the AC 1 mutation.

**QA stage (2026-11-08; lane-D warm throwaway `e18s2qw`, started and torn down by the QA stage; every mutation applied, observed red, reverted, and `git status --short` / file hashes confirmed unchanged):**
- (QA) `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `Zone(osLink = "/etc/localtime")`, a seam that `Zone()` passes to `OsZone` (behaviour unchanged for every caller). `src/ocutalon/cls/OcuTalon/Test/Data/TimeSource.cls` `TestOsZone` now pins the DW-34 fallback through `Zone`: a Berlin zoneinfo link gives `Europe/Berlin`, an unresolvable link gives `UTC`, and a saved zone still wins over the link. (No new test file; DW-939 settled.)
- mutation: DW-34 fallback: `Zone()` stops calling `OsZone(osLink)` (sets "") -> `Test.Data.TimeSource` `TestOsZone` red ("with no row and no TZ, Zone() takes the zone of the operating system's link (DW-34)").
- mutation: AC 3 (re-observed): `Api.SendDigest` submits with origin `web_user` -> `Test.Web.SettingsApi` `TestSendDigest` red (no requested Sent row).
- mutation: AC 2 (re-observed, different edit): removed the empty `Kind=digest` fall-through `<when>` from `Core.Rule.Notify` -> `Test.Core.Routing` `TestNotifyDigestTargets` red (a digest with no channel takes the generic route).
- mutation: AC 5 (re-observed): `channelsView` ignores the paused card kind -> `web/scripts/settings-view.test.mjs` "says \"paused\" with the retry line while the pause condition holds, whatever the state is" red.
- mutation: AC 1, S9 (browser tier, locator fix): `web/e2e/settings/settings.spec.ts` S9 now targets the select with `getByRole('combobox', { name: 'Time zone', exact: true })` at both sites; mutation (revert either site to `getByLabel('Time zone', { exact: true })`, or drop the saved-text check) -> S9 red -- not observed locally (DW-938). The spec parses (`playwright test --list --project=sign-in-2`, 21 tests) and `npm --prefix web run lint` passes; the browser run is the lead's re-smoke.
- Baseline on `e18s2qw` after the seam: `Test.Data.TimeSource`, `Test.Data.Time`, `Test.Core.Routing`, `Test.Core.SettingsRunTime` (70 s), `Test.Web.SettingsApi`, `Test.Schedule.ReminderZone`, `Test.Agent.Render`, `Test.Bridge.Time` passed; `node --test web/scripts/settings-view.test.mjs web/scripts/ux-strings.test.mjs` 42 pass; `bash docker/tests/test-boundaries.sh` passed.
- DW-938 not settled: Playwright S9 to S12 cannot run inside the 150 s rule. The warm stack publishes no port and holds no fixture users, and its web bundle is part of the image (a changed web file refuses a warm run). The only runner is the `live:sign-in-2` unit (`docker/tests/test-sign-in-2.sh`), which builds its own image and throwaway, waits up to 400 s for the first start, creates the fixture users, then runs the whole project; it is one script with no split point (`--part k/n` cuts only the browser step). So no S9 mutation line; S9 to S12 stay in CI (group `shards-4`), with their pure-function twins in `settings-view.test.mjs` (AC 5 mutation above).

**Code review (2026-11-08; slot D for `Test.Web.Api` `TestRoutes`, `Test.Web.BodyLimit`, `Test.Data.Time`; lane-D warm throwaway `e18s2cw`, started and torn down by the review, for `Test.Data.TimeSource`, `Test.Core.SettingsRunTime` (70 s), `Test.Web.Api`, `Test.Agent.Render`, `Test.Tools.Reminders`; all passed after the patches; `node --test web/scripts/settings-view.test.mjs` 30 pass, `ux-strings` 13 pass, `npm --prefix web run lint` and `build` exit 0, `test-boundaries.sh` passed):**
- mutation: AC 1, `Zone()` after a clear: removed the `Bridge.Time.Apply()` line from `Data.Time.Zone` -> `Test.Data.TimeSource` `TestZoneCleared` red ("Zone() reports the inherited TZ, before any conversion follows the change"); restored byte-identical, green again.
- mutation: AC 2, the Daily digest form's dirty rule: `isDigestFormDirty` made to compare the save body (`isDigestDirty` of `digestChannelsBody`, the rule before the patch) -> `web/scripts/settings-view.test.mjs` "keeps the form clean on open when the saved channels are hidden ones ..." red; restored byte-identical.
- S10, S11 and S12 were changed but not run here (DW-938: CI only, group `shards-4`).

**Shared surfaces:**
- Notify's targets for kind `digest` (`Test.Core.Routing`; `Test.Digest.Compose` `TestOwnMatchesNotify`, which must stay green unchanged).
- `Functions`' function list (`TestFunctions`).
- `Data.Time.Zone()` (`Test.Data.Time`, `Test.Agent.Render`, the web bootstrap `instanceZone`).
- `FromLocal`'s repeated-hour result (`Test.Schedule.ReminderZone`).
- The settings POST route list (`TestNonAdminIs403Everywhere`).
- The settings page's not-built list (`settings.spec.ts` S1).
- `SETTINGS_TEXTS` and `ux-strings` `SOURCES`.
- The instance-wide rows `InstanceZone`, `digest.time` and `digest.channels`, and demo mode.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Rework 1 pass (smoke, S9 locator).** This pass covers only the open [Smoke] item. `web/e2e/settings/settings.spec.ts`: S9's two `getByLabel('Time zone', { exact: true })` sites now use `getByRole('combobox', { name: 'Time zone', exact: true })` (the section region shares the name; the role keeps the locator on the select), with a one-line comment. S10-S12 checked: no ambiguity, no edit. No product change. Review: 5 findings, all low; 2 patched (the comment, the S9 `mutation:` line as "not observed locally (DW-938)"), 3 rejected with reasons in the triage log; follow-up review recommended: false (no high patched). Verification: `playwright test e2e/settings/settings.spec.ts --list --project=sign-in-2` parses (21 tests), `npm --prefix web run lint` and `bash docker/tests/test-boundaries.sh` pass; the browser run is the lead's re-smoke. Residual risk: S9 is unobserved in a browser until that re-smoke.

**Summary.** `Data.Time` follows `Bridge.Time` (Apply first, bridge zone, then TZ, then the OS zone, then UTC) and reads the first instant of a repeated hour whatever the process converted before. `Notify` has a `digest` branch that reads `digest.channels` (`Functions.DigestNamed`). `POST /v1/settings/daily-digest/send` submits one `SendDigest` (origin `web_admin`). The Settings page has the Time zone, Daily digest (with Send my digest now) and Channels sections. `Test.Core.SettingsRunTime` changes all three values on the running production without a restart.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Time.cls`: Apply calls, Zone() order, OsZone, fold 0.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls`, `Core/Rule/Notify.cls`: DigestNamed and the digest branch.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: the send route.
- `web/src/app/api/api-client.ts`, `api-types.ts`: `sendDigest()` and the time-zone body type.
- `web/src/app/settings/{time-zone,daily-digest,channels}-section.ts` (new), `settings-page.ts`, `settings-view.ts`: the three sections and their texts.
- Tests: `Test/Data/Time.cls`, `Test/Data/TimeSource.cls` (new), `Test/Core/Routing.cls`, `Test/Core/SettingsRunTime.cls` (new), `Test/Web/SettingsApi.cls`, `web/scripts/{settings-view,ux-strings,announce-focus-sources,demo-view-sources}.test.mjs`, `web/e2e/settings/settings.spec.ts` (S1, S8, S9 to S12).

**Review.** 32 findings in 24 triage rows: 9 patches applied (6 medium: the midnight flake, the zone list with UTC and S9's zone, S12, hidden-only channels, TestFoldZero state, AC 4 mutation lines; 3 low: the Lord Howe case, the import, the header sentence), 1 deferred (S9 to S12 mutation lines; the OS-zone pin is the second deferred item), 3 refuted as false, the rest rejected with the reasons in the triage log. Follow-up review recommended: yes. Unverified risk: S9 and S12 and the changed zone list were not run in a browser here; they run in CI (group shards-4).

**Verification.** Lane-D warm throwaway `e18s2iw` (started and torn down by this stage): `Test.Data.Time`, `Test.Data.TimeSource` (0.07 s), `Test.Schedule.ReminderZone`, `Test.Core.Routing`, `Test.Core.SettingsRunTime` (70 s), `Test.Web.SettingsApi` and the once-classes passed at the implement pass (`Test.Bridge.Time` 2.2 s, `Test.Agent.Render`, `Test.Tools.Reminders` 7.9 s, `Test.Digest.Compose`, `Test.Digest.Send` 12.4 s, `Test.Core.SettingsSave`, `Test.Core.SettingsAudit`, `Test.Schedule.Reminders` 82 s, `Test.Demo.SimPhoneOut`, `Test.Core.RoutingProduction`). After the review patches: TimeSource, Time, SettingsApi, ReminderZone and SettingsRunTime re-run green. `npm --prefix web test` (1560), `npm --prefix web run lint`, `npm --prefix web run build`, `bash docker/tests/test-boundaries.sh` all pass.

**Residual risks.** Playwright S1, S9 to S12, the full `shard:lane-a` and `shard:lane-b` and the fresh-environment check are left to CI. DW-34 residual (a) and the 17.5 occurrence are Lane A's. Deferred items are in the frontmatter.
