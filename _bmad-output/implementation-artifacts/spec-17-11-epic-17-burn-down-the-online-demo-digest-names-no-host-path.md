---
title: 'Story 17.11: Epic 17 burn-down: the online-demo digest names no host path, address, user or key'
type: 'chore'
created: '2026-11-07'
status: 'done'
baseline_revision: 'ca94fe48bb27f29a67b469bc241453bf613dc755'
baseline_commit: 'ca94fe48bb27f29a67b469bc241453bf613dc755'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the online demo a visitor can ask for the digest, and it shows the demo instance's own vital signs and the Orders production's coverage row. The owner kept this (U-303) on one condition: the digest never names a host path, an IP address, a user name or a key. Nothing pins that today.

**Approach:** Add one test class. It turns the online demo on, plants a host path, an IP address, a user name and two key shapes (an `sk-ant-` key and a Telegram bot token) in the instance facts the digest reads (the session and watch rows, the vital signs, the production's live read). It then composes a visitor's digest through the real `Digest.Process` and `Checks.Coverage.Build` code and renders it with `Channel.DigestText.Text(slots, "web")`. None of the planted values may appear. The test changes no product code. A red on unchanged code is a real leak, a HIGH that this story fixes.

## Boundaries & Constraints

**Always:**
- The test composes the digest through the real `Digest.Process` `Composed`/`Finish` and the real `Checks.Coverage.Build`. Only the seams that `Test.Digest.ProcessProbe` and `Test.Digest.CoverageProbe` already provide are under test control: the vital signs, the live read, the gaps, and the recording of the sends. The text under test is `OcuTalon.Channel.DigestText.Text(slots, "web", .sc)` of the recorded Notification's Slots.
- The online demo is on for each test (`Data.Public.Settings` `onlineDemo` 1). After each test the key is put back to the value it had before.
- Every planted value is made up. The IP is from the documentation range 203.0.113.0/24. The user and the path are invented. The two key shapes are built at run time from fragments, as `Test.Bridge.Redact` builds them, so no source line holds key-like text (`test-boundaries.sh` scans the repository for it). No real demo host detail is used (AD-25).
- Assertion messages name a planted value only by its label ("the planted Telegram token shape"), never by its text. On a failure, neither the digest text nor a planted value goes into `^UnitTest.Result` or a CI log.
- Nothing is saved for later, so the digest makes no model request. No mock scenario is needed.
- The test creates and removes every row it reads: sessions, the watch, CheckRuns, Compose bodies, Sent rows and Ens.Rule.Log rows. It passes on a fresh stack, in either order, and on the dev slot.

**Never:**
- No product string, catalog entry or product class changes. The one exception is the leak fix below.
- If the pin is red on unchanged code, the leak is a HIGH. Fix it in this story with the smallest change in the composer, and add no new string. A fix that needs new user-facing text is a HALT with `intent gap`, and its condition begins `PUBLIC TEXT:` and gives the exact text. In `Digest/Process.cls`, a fix stays out of Epic 12's hunks (:32, :596, :668-695, :872-880).
- No browser test. No new probe class. No edit to `ProbeCase`, `ProcessProbe` or `CoverageProbe` (they are shared with other tests).
- These files are not edited: `Test/Channel/TelegramDigest.cls`, `Channel/SimPhone/Out.cls`, `web/e2e/support/floor.ts`, `web/playwright.config.ts`, `ci/iris.sh`, `ci/units.sh`, `web/e2e/heartbeat-card.spec.ts`, `release/*`, `eval/run.sh`, the IPM artifact and check scripts, any existing file under `ci/mock/scenarios/`, and anything under `_bmad/` or `.claude/`.
- No real model key and no real Telegram bot.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Failing digest (the pin, DW-898) | `onlineDemo` 1. The visitor session's IrisUser is USER. Its Orders watch has AskedBy USER and ten passed runs in the 10-minute window. Vital signs: OCUTALON_DATA 3% and OCUORDERS_DATA 4% free, with directories under PATH. The journal is 8% free, with its directory under PATH. License use is 95% and the system log has 2 severe lines. Live read: state troubled. One errored item, one disabled item and one queue (150 messages, the oldest 900 s old) are named CARRIERNAME. Two failures of the visitor's own trace have errorText CARRIER, and item and source CARRIERNAME. | One Notification is sent and `Text(slots, "web")` returns OK. The text holds `Failed: database space (OCUTALON_DATA 3% free, OCUORDERS_DATA 4% free, at` and `Failed: Orders production (Production troubled, 1 item in error, 1 item disabled, 2 new failures, 150 messages queued, a message waiting 15 minutes, at`. It holds none of PATH, IP, USER, ANTKEY or BOTTOKEN (compared without regard to case), no match of any KEYLIKE alternative, and no IPv4 shape. The Notification's whole Slots JSON (parts, lines and rows) holds none of them either. | A red on unchanged code is a real leak: a HIGH, fixed in this story |
| Passing digest | The same plants, but healthy readings: 3 days up, OCUTALON_DATA 40% free, journal 50% free, license 20%, no severe line, directories still under PATH. Live read: running. One queue named CARRIERNAME holds 3 messages, the oldest 30 s old. Two failures with CARRIER belong to another visitor's trace, so the online demo does not count them. | The text holds `Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%.`, `I checked the Orders production (all running, no errors, no backlog).` and `Everything I checked passed.`. It holds none of the planted values, no KEYLIKE match and no IPv4 shape, in the text or in the Slots | As above |

</intent-contract>

## Code Map

**Where instance facts enter the digest** (read during planning; recorded under Design Notes):
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`
  - `Vitals` :235-271: its raw strings are `databases[].name`, `databases[].directory` and `journal.directory` (:252). The rest are numbers.
  - `Database` :277-299 and `DatabaseName` :302-309: the name is the last folder of the directory, in upper case.
  - `Databases` :320-343.
  - `Failures` doc :23-35: the raw strings are errorText, item, source, bodyClass, the disabled and errored item names, and the queue names.
- `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls`
  - `Build` :128-160 (the Vitals seam :145, `VitalRows` :150, `WatchRow` :154).
  - `VitalRows` :201-234 reads only outcome, upSeconds, freePercent, usePercent and count.
  - `DatabaseRow` :237-269 puts `database.name` into FINDINGDATABASE at :253. This is the one raw instance string that reaches a slot.
  - `Live` :335-383: its findings are counts and code texts only (:363-379).
  - The seams: `Vitals` :444, `Read` :450 and `Gaps` :456.
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls`
  - `Composed` :420-451: with no saved item it goes to `Finish` with no model request (:434-436).
  - `Finish` :591-664: the parts :607-643 and the Slots `{parts, lines, rows}` :644.
  - `Vitals` :818-832: the figures are taken as numbers.
  - The `Rows` seam :846.
- `src/ocutalon/cls/OcuTalon/Digest/NeedsYou.cls` :1-12, `List` :27: a failed row is named "<entry>: <finding>".
- `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls` `Text` :17-41: it renders parts and lines only.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`
  - The `digest.*` keys :434-610.
  - The `checks.*` keys :54-82.
  - Text slots: entry, finding, checked, whatFailed and what.
  - `Catalog.Render` trims and strips control characters and redacts nothing (AD-32).

**Test scaffolding to reuse (read-only):**
- `src/ocutalon/cls/OcuTalon/Test/Digest/ProbeCase.cls`: the base to extend.
  - `OnBeforeOneTest` :23 and `OnAfterOneTest` :34: zone, probe resets, digest.channels, cleanup of `Sessions`/`Refs`.
  - Helpers: `Keep` :49, `Host` :67, `Compose` :77 (requested, 10-minute window ending 2030-06-03 09:00 New York), `Handle` :89, `Notice` :96, `Keys` :104 and `Every` :189 (ten passed runs).
  - `Session` :54 and `Watch` :174 take no user or fields, so the new class calls `Fixture.Session(USER)` and `Fixture.Check(...)` itself and appends to `..Sessions`/`..Refs`.
- `src/ocutalon/cls/OcuTalon/Test/Digest/ProcessProbe.cls`
  - `Rows` :291: when not fed, it calls `CoverageProbe.Build`, the real code over the probe's seams.
  - `SendNotice` :272 records the Slots (record field 5).
- `src/ocutalon/cls/OcuTalon/Test/Digest/CoverageProbe.cls`: `Feed` :56, `FeedRead` :68 (the spec shape in the class doc :5-7), `Healthy` :50, `Calls` :80, `Reset` :99, and the vitals call count `^||CoverageProbe("vitalsCalls")`.
- Patterns:
  - `Test/Digest/AllClear.cls` `Situation` :29 (watch, Every, FeedRead, Handle, Notice).
  - `Test/Digest/Coverage.cls` `TestLiveRead` :375 (a failure of the session is `{"superSession": <session TraceRef>}`; another session's is not counted on the online demo, `Checks.Process.ScopedFailures` :648-657) and `TestVitalFailures` :122 (the database finding).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`
  - `KEYLIKE` :44, the verbatim copy of `docker/tests/lib-keys.sh` KEY_LIKE_ERE. Read it with `$Parameter`; never copy it.
  - The fragment-built key shapes :85-101 and the `%Regex.Matcher` loop over its alternatives :411-416.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Due.cls` :42-83: how the `onlineDemo` key is saved and put back.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`: `Session(user)` :22 sets IrisUser, and `Check(session, ns, production, fields)` :70 sets AskedBy and other fields.
- `docker/tests/test-class-rules.sh` assert-concat: put the concatenation in parentheses, as in `$$$AssertTrue((text [ ("a"_b)), ...)`.
- `ci/units.sh` :20 (lane-a areas, Digest among them) and :94 (`shards-2` = `shard:lane-a@rest`): a new `Test/Digest` class joins `shards-2` with no edit.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Test/Digest/OnlineDemoFacts.cls` (new) -- `Extends OcuTalon.Test.Digest.ProbeCase`. The class doc says what it pins and what it needs (Rule 14), and the file is ASCII only. It adds:
  - `OnBeforeOneTest`/`OnAfterOneTest` that call `##super` and save `onlineDemo`, set it to 1, and put the saved value back.
  - The planted values as class methods, built at run time: USER, IP, PATH = `/home/` USER `/` IP `/mgr/`, ANTKEY = `"sk-" _ "ant-api03-" _` 40 `Z`, BOTTOKEN = `"987654321" _ ":" _ "AAH" _` 32 `z`. CARRIERNAME is USER `@` IP. CARRIER is one error text that holds all five values.
  - A helper that composes one digest (Fixture.Session(USER) and Keep, a second visitor session for the passing case, `Fixture.Check(session, "ZZNS", "Zz.Leak.Orders", {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": "Orders", "AskedBy": USER})`, `Every`, `CoverageProbe.Feed`/`FeedRead`, `Handle` on `Host()`, then `Notice(1)`).
  - A leak check that asserts, for the text and for the Slots JSON, each planted value by label, every KEYLIKE alternative and an IPv4 shape (`[0-9]{1,3}(\.[0-9]{1,3}){3}`).
  - `TestFailingDigest` and `TestPassingDigest` for the two matrix rows (DW-898).
  - Both tests first assert that the plants were consumed: one live read (`Calls().%Size() = 1`), the vital signs were read, `sc` is OK and the text is not empty. Then they assert the expected anchor lines and the absences.
- [ ] Mutations (Rule 19) -- apply each one on the warm stack, observe red, restore byte for byte (`cmp` against a backup), and see the class green again on the same stack. Record each under Verification:
  - (pinning) `Checks/Coverage.cls` :253 `{"name": (database.name), ...}` -> `{"name": (database.directory), ...}`: `TestFailingDigest` is red (the PATH, IP and USER legs, in the text and in the Slots).
  - `Checks/Coverage.cls` `Live`: after the failures part (:368) add `Set parts = parts_$ListBuild(failed.%Get(0).errorText)`: `TestFailingDigest` is red on all five values, KEYLIKE and IPv4.

**Acceptance Criteria:**
- Given the online demo and the planted host path, IP address, user name and key shapes in the instance facts the digest reads, when a visitor's digest is composed and rendered with `Channel.DigestText` for channel "web", then none of the planted values (and no key-like text and no IPv4 shape) appears in the text or in the Notification's Slots, the pin goes red under the database-directory mutation, and no product string changes (DW-898).
- Given the test on unchanged product code, when it runs, then it is green. If it is red, that is a real leak: the leak is fixed in this story as a HIGH, the pin is green after the fix, and the mutation still turns it red.
- Given a fresh stack, when `shard lane-a@Digest` runs forward and in reverse, then every class passes, `onlineDemo` reads as it did before each test, and `Test.Digest.Coverage` `TestLiveRead`'s "not the online demo" control passes.

### Review Findings

Code review, 2026-11-08 (UTC). Full-opus tier, four layers: Blind Hunter, Edge Case Hunter, Verification Gap and Acceptance Auditor. 27 raw findings became 5 entries (high 0, medium 1, low 4), and all five are patched. 16 rejected, 0 deferred, 0 decision-needed. No product code changed, and no leak was found.

- [x] [Review][Patch] The test never checked that the online demo was on [src/ocutalon/cls/OcuTalon/Test/Digest/OnlineDemoFacts.cls:168]. Medium, fix-risk low (test-only, one class), in-story, spec-clear (Decided 5). Sources: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor.
  - Problem: no assertion read `OnlineDemo()`. The passing case planted only another visitor's failures, and no instance counts those, so the `'onlineDemo` leg of `ScopedFailures` (`Checks/Coverage.cls` :355) was never reached. Forcing :355 to "not the online demo" left the class green (observed).
  - Patch: `Consumed` asserts that the online demo is on. The passing read also carries two failures scoped to the instance, each with the error-text carrier: one with no superSession and one of a trace that no session owns. The docs are corrected.
- [x] [Review][Patch] Nothing checked that the plants still match KEYLIKE and the IPv4 shape [OnlineDemoFacts.cls:171]. If an alternative in `lib-keys.sh` changed, its absence leg would silently stop being able to fail. Low, fix-risk low, in-story. Source: blind-hunter.
  - Patch: `Consumed` asserts that each KEYLIKE alternative and `IPV4` is found in `Carrier()`. The IPv4 regex is now one parameter.
- [x] [Review][Patch] The class doc gave the wrong reason for running on throwaways only ("key-shaped values in IRIS rows") [OnlineDemoFacts.cls:22]. The shapes live in process-private globals, and the risk on a shared runtime is the instance-wide `onlineDemo` flip. Low, fix-risk low; doc only. Source: blind-hunter.
- [x] [Review][Patch] The class doc said the failing text "holds the two failed lines" [OnlineDemoFacts.cls:13]. The plant fails five rows, and the test anchors two of them (database space and the production). Low, fix-risk low; doc only. Source: blind-hunter.
- [x] [Review][Patch] Only a reverse-order run guarded the `onlineDemo` restore, and CI never runs one [OnlineDemoFacts.cls:46]. Dropping the restore left the class green. Low, fix-risk low, in-story. Source: verification-gap.
  - Patch: `OnAfterOneTest` asserts that the key reads as it did before the test, the same check `Test.Install.Users` makes on its guard. A dropped restore is now red in forward order.

**Rejected:**
- `low`, Edge: the restore is skipped if `##super` throws in `OnAfterOneTest`. wontfix-theoretical:
  - the ProbeCase and ZoneCase teardowns delete through `%ExecDirect` and do not throw;
  - `Test.Digest.TelegramText` uses the same order.
  - It becomes real if a teardown step starts to throw.
- `low`, Edge: an error status from `##super` in `OnBeforeOneTest` skips both the test and the restore. wontfix-theoretical: `ZoneCase.OnBeforeOneTest` always returns OK, and the fix would add a guard. It becomes real if ZoneCase or ProbeCase start to return an error.
- `low`, Edge: no probe looks for a host-path tail ("/mgr/"). wontfix-theoretical: no code path strips a directory's host prefix and keeps its tail. The path, user, IP and IPv4 legs cover a directory leak, and the :253 mutation turns them red.
- `low`, Edge: `$$$AssertStatusOK` appends a failed status's text to the result. wontfix-theoretical: no status on these paths quotes an instance string.
  - The Slots have `MAXLEN = ""`.
  - Catalog `Fail` quotes a value only for channel and fallbackReason slots.
  - `Text`'s own error names no value.
  - It becomes real if a render error ever quotes the value of a text slot.
- `low`, Auditor: the passing case's plants cannot be told apart from the probe's defaults.
  - Both cases feed through one helper, and the failing anchors prove that path.
  - This review's `OnlineDemo` mutation turns the passing case red through its planted read.
  - Telling the vital signs apart would change the healthy figures the spec sets.
- `low`, Auditor: the failing case also creates the second visitor session. Harmless: both sessions are kept and cleaned up.
- `low`, Auditor: nothing in the class prevents a run on a slot. The lead's spec gate and the class doc govern this, and a guard would add a branch. Implement triaged it the same way.
- `low`, Blind: the Always line "and on the dev slot" contradicts the Spec Change Log. The fix would edit the spec's intent, and the Spec Change Log (lead gate) governs.
- `low`, Blind: the spec does not record the QA backup incident on `Digest/Process.cls`. The fix would edit the spec. `Process.cls` is identical to HEAD, and this stage's fresh-stack run (under Verification) does not depend on any warm stack.
- `low`, Blind: the Auto Run Result's "run again after the last patch" predates QA's change. The fix would edit build-auto's section; this stage's fresh run is recorded under Verification.
- `low`, Blind, Edge and Auditor: "Rejected: 11" should read 12. Cosmetic, and the fix would edit build-auto's Auto Run Result.
- `low`, Blind: QA's Slots-only mutation contradicts triage row "no cheap composer mutation reaches Slots only". Cosmetic, and the fix would edit the implement triage log.
- `low`, Blind and Auditor: the cycle log's `dev_complete` has an empty `loc_added=`. The cycle log is the lead's, and this stage writes no cycle-log entries.

## Spec Change Log

- 2026-11-08, lead spec gate: the test runs only on lane B's throwaways, never on `ocutalon-slot-b` (it plants key-shaped values in IRIS rows and sets `onlineDemo`); the slot keeps the compile check. No other change.

## Review Triage Log

### 2026-11-07 — Review pass
- verdicts: 17 findings — high 0, medium 1, low 13, false 3, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: mutation lines cite Coverage.cls by line number — the fix edits this spec's wording; the lines are the spec's own anchors (:253, :368).
  - `[low]` `[reject]` Blind: `plain` (backslash-stripped) and lowercase branches of `Absent` and a Slots-only leak are not shown by a mutation — both branches are defensive extras of one function that reddens the same way on the text and on the Slots; the prescribed mutations show red for both; no cheap composer mutation reaches Slots only.
  - `[low]` `[reject]` Blind: only header rows and four fields are planted in the live read — the class doc names exactly the planted fields, and `Watch.Reader.Failures` documents these as the raw strings.
  - `[false]` `[reject]` Blind: other channels are not covered — the intent pins "web", and the online demo is the polling web path; the Telegram text is pinned in Test.Channel.TelegramDigest (never edited here).
  - `[false]` `[reject]` Blind: `Consumed` reads `^||CoverageProbe("vitalsCalls")` directly — the spec names that exact global, and CoverageProbe must not be edited.
  - `[low]` `[patch]` Blind: `Digest` returns an unused `session`, and `Ago` is an instance method with no state — removed the field, made `Ago` a ClassMethod.
  - `[low]` `[reject]` Blind: the "15 minutes" anchor depends on wall-clock — the window is 60 s against a 0.1 s test; an unlikely flake, and the fix adds complexity.
  - `[low]` `[patch]` Edge: only whole planted values are checked, a truncated key or token id would escape — added the `sk-ant-` prefix and the Telegram bot id as fragment probes.
  - `[low]` `[reject]` Edge: other row kinds and fields of the live read are not planted — same as the Blind row above.
  - `[low]` `[reject]` Edge: the IPv4 pattern has no boundary — it is green on every digest shape measured (times and cost cannot match), and a boundary adds a regex nobody needs.
  - `[low]` `[reject]` Edge: the passing digest plants only the other visitor's failures — the matrix row asks exactly that (running, no errors, another visitor's failures).
  - `[low]` `[reject]` Edge: "makes no model request" is not asserted — no saved item means `Composed` goes to `Finish` with no request by construction (Process.cls :434-436), and the Notification count of 1 confirms the path.
  - `[false]` `[reject]` Edge: the spec says `Notice(1)` but the helper reads `Record` — the helper takes the raw Slots JSON string, which is stricter than the parsed object; a fix would only edit the spec.
  - `[low]` `[patch]` Verification-gap: restoring `onlineDemo` has no mutation line — demonstrated (drop the restore; `Coverage` `TestLiveRead` control red), line written under Verification.
  - `[medium]` `[patch]` Verification-gap: five of the seven KEYLIKE alternatives had no planted value, so 20 assertions could not fail — planted one fragment-built value per other alternative (labels only), re-ran the Coverage.cls :368 mutation: all seven alternatives red.
  - `[low]` `[patch]` Verification-gap: `TestPassingDigest` has no mutation of its own — demonstrated with the `ScopedFailures` mutation (red on the passing sentences), line written under Verification.
  - `[low]` `[reject]` Verification-gap, other findings: a package-level run on a slot would run the class, and no baseline exists if a crash left `onlineDemo` at 1 — the lead's spec gate and the class doc forbid slot runs; a crash baseline needs extra state for a rare case.
  - Intent-alignment: descriptive only, no finding (reading A is implemented; the raw-reading layer below the probe seams and the WebChat.Out card are outside this story by the spec; the stale Auto Run Result is rewritten at finalize).

## Design Notes

**What the measurement found (Task 0, during planning; no real leak today).**
- The digest's slot values that come from instance facts:
  - the vital figures, which are numbers;
  - the vital entries and findings, which are code texts and percentages;
  - `databases[].name` in the failed database finding;
  - the production row's entry ("<DisplayName> production"; on the online demo only the Orders production can be watched);
  - its findings, which are code texts and counts. CheckRun's Finding is built by `Checks.Process` from its FINDING*/REASON* parameters only (class doc :52-57).
- The raw host strings never reach a slot: `databases[].directory`, `journal.directory` and every string of the live read. They do not reach the Slots' rows either.
- The database name is the database's own name. `merge.cpf` creates the folders `ocutalon_code`/`_data`/`_private`/`_public` under the manager directory, and `Install.Step.Demo.Directory` :196 does the same for `ocuorders_code`/`_data`. So the name is the CPF database name, not a path. U-303 keeps "OcuTalon's databases and how full", so database names stay (Decided 1).
- Measured on `ocutalon-slot-b` (read only, `Watch.Reader.Vitals()`): OCUTALON_CODE/DATA/PRIVATE/PUBLIC with directories `/durable/iris/mgr/ocutalon_*/`, and journal `/durable/iris/mgr/journal/`. The directories are in the raw reading and nowhere in the rows.
- A grep finds no read in `Digest/*`, `Checks/Coverage.cls`, `Checks/Render.cls`, `Channel/DigestText.cls` or `Watch/Reader.cls` of `proxyAddress`, `demoUser`, `readonlyUser`, `IrisUser` or `AskedBy`. The online demo's own settings, where its address and users live, never reach the digest.
- Rendered times read like `Jun 3, 2030 at 08:59` or `20:32`, and the cost reads `$1234.50.`. So the IPv4-shape leg has no false match.

**Governing ADs (Rule 6):**
- AD-18: the coverage rows and vital signs come only from `Coverage.Build` and `Watch.Reader`.
- AD-28: the rows and all-clear come only from code. The test reads them and changes nothing.
- AD-32: the digest Slots and the renderer. `rows` is for the web card of Story 18.4, so the Slots are pinned too.
- AD-19: no key in IRIS. The planted shapes are fake and built at run time.
- AD-25: no demo infrastructure detail in the repository. All the values are made up.
- AD-22: tests use the CI mock and fixtures. This test makes no model call.
- AD-29: Lane A's Digest test area, Epic 17's own.
- No AC contradicts an AD.

**Ledger (Rule 17):** DW-898 is addressed by the OnlineDemoFacts task, the two matrix rows and the first AC.

**Integration ACs (Rule 1):** this story is test-only and introduces no service, module or shared component.
- Consumed-by: none.
- Consumes: `Checks.Coverage.Build` (Story 17.5), `Digest.Process` (Stories 17.6-17.7), `Channel.DigestText` (Story 17.10) and the online-demo flag (Epic 16).

**Extend, don't copy (Rule 2):**
- The class extends `Test.Digest.ProbeCase` and uses the existing probes as they are.
- KEYLIKE is read from `Test.Bridge.Redact`, with no third copy.
- The session and watch rows come from `Test.Data.Fixture`, called directly, because `ProbeCase.Session`/`Watch` take no user or fields and the shared base stays unedited.
- The test does not drive WebChatOut: `Test.Core.WebChatOut` `TestDigestCard` already pins that the card text equals `DigestText.Text(slots, "web")`.

**PUBLIC TEXT:** none.

**Decided in-stage:**
1. Database names stay in the digest. They are CPF database names, not paths, and U-303 keeps "OcuTalon's databases and how full".
2. The plants go where the online demo really holds a user, a path, an address or a key: the session's IrisUser, the watch's AskedBy, the vital-sign directories, and the live read's error texts and item and queue names. They do not go into the public settings, because the digest reads none of them (see the grep above), so a plant there could not go red under a composer mutation.
3. Both the text and the Slots JSON are checked, without regard to case. Database names are upper-cased, so a leaked value could come back in upper case.
4. Besides the five values, every KEYLIKE alternative and an IPv4 shape are checked, so a key or address that was not planted is caught too.
5. Two cases. The failing digest is the pin, because the database finding and the full live finding are its leak-prone paths. The passing digest covers the healthy sentence, the passed lines and the online-demo scoping of another visitor's failures.
6. Class `OcuTalon.Test.Digest.OnlineDemoFacts` is in the Digest area, so it runs in `shard:lane-a@rest` in group `shards-2` (about 28 min) and `ci/units.sh` is not edited. Its expected time is under 1 s locally and a few seconds on the CI runner (inference): `Test.Digest.AllClear` on `ocutalon-slot-b` (run 717) took 18-271 ms per probe-composed test. Its `TestRecordedCasesAgree` fails on the slot because it needs the eval/ mount, which only a throwaway has.
7. Visitor-typed and model-written text (the saved summary, and the Summaries of Decisions and incidents in needs-you) are not instance facts. The ruling scopes the pin to the instance facts, so this test does not plant them.

**Footprint (Rule 11):** one new file in Epic 17's own `Test/Digest`. `git diff --name-only HEAD...origin/OCT-epic<N>` for every OCT-epic branch on 2026-11-08 shows `Test/Digest/NeedsYou.cls` only (epics 0 and 12), and no branch touches `Checks/Coverage.cls`.

## Verification

Every `ci/*.sh` call sets `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=17 stage=implement'`.
- Tags: `e17s11iw` (warm) and `e17s11i` (fresh).
- Run one call at a time, in the foreground, with `timeout: 600000`, and size each call to about 150 s.
- Slot calls go to `ocutalon-slot-b` / `OCUTALON` only, after `iris_server_info` shows build 154. Make one `iris_execute_tests` per message.

**Commands:**
- (once) `iris_doc_load` of `OnlineDemoFacts.cls` on `ocutalon-slot-b`. Expected: it compiles.
- [Lead, spec gate 2026-11-08] The test is never run on `ocutalon-slot-b`: it plants key-shaped values in IRIS rows and sets `onlineDemo`, so it runs only on this lane's throwaways (warm and fresh, below). The slot is used for the compile check alone.
- (once) `OCUTALON_RUN_TAG=e17s11iw ci/warm.sh up`. Expected: a ready warm stack (about 110-135 s).
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s11iw ci/iris.sh class OcuTalon.Test.Digest.OnlineDemoFacts`. Expected: `CLASS ... passed`. The mutation runs use this command.
- (once) The same warm command, one class per call, for `OcuTalon.Test.Digest.Coverage`, `AllClear`, `Due` and `Compose`. Expected: each passes, unedited.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-ci-config.sh`, one per call. Expected: all PASS, "keys: nothing key-like" and assert-concat included.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s11i ci/iris.sh shard lane-a@Digest`, then the same with `--reverse`, then `OCUTALON_RUN_TAG=e17s11i ci/iris.sh teardown`, each in its own call. Use `--part k/2` when a call nears 150 s. Expected: every class passes.
- (once) `OCUTALON_RUN_TAG=e17s11iw ci/warm.sh down` at the stage's end, also after a failure.

**Shared surfaces:** none changed. The test sets the public key `onlineDemo` and puts it back after each test. That key is read by `Test.Digest.Coverage` `TestLiveRead`'s control and by `Test.Digest.Due`. ProbeCase takes the digest.channels row out of the way and puts it back.

Every test added or changed passes on a fresh environment, in either order.

**Mutations observed:**
- mutation: `Checks/Coverage.cls` :253 `{"name": (database.name), ...}` -> `{"name": (database.directory), ...}` -> `TestFailingDigest` red (the database-space anchor, and the host path, IP address, user name and IPv4 legs, in the text and in the Slots); `TestPassingDigest` stays green. Restored byte for byte (`cmp`), class green again on the same warm stack.
- mutation: `Checks/Coverage.cls` `Live`, after the failures part (:368), add `Set parts = parts_$ListBuild(failed.%Get(0).errorText)` -> `TestFailingDigest` red on every planted value and fragment, all seven KEYLIKE alternatives and the IPv4 shape, in the text and in the Slots (`TestPassingDigest` red too, as the line is unconditional). Restored byte for byte (`cmp`), class green again.
- mutation: `Checks/Process.cls` `ScopedFailures`, the condition `If (scope = sessionRef) || ((scope = ..#INSTANCE) && 'onlineDemo)` removed so that every failure counts -> `TestPassingDigest` red ("the production sentence" and "the reserved sentence"), `TestFailingDigest` green. Restored byte for byte (`cmp`), class green again.
- mutation: `OnlineDemoFacts` `OnAfterOneTest`, the `Set("onlineDemo", ..SavedOnline)` restore deleted -> `OnlineDemoFacts` `TestFailingDigest` red ("the test left the onlineDemo key as it found it"), in forward order. Corrected in code review, after the restore check was added. Before the check, `OnlineDemoFacts` stayed green, and only `Test.Digest.Coverage` `TestLiveRead` went red when it ran afterwards.

**QA stage (QA), warm tag `e17s11qw` on lane B; each mutation made from a backup in the stage scratch folder, restored byte for byte (`cmp`), tree back to the pre-mutation state:**
- Tests changed (QA): `src/ocutalon/cls/OcuTalon/Test/Digest/OnlineDemoFacts.cls` (`Consumed`: the "of the watched production" assertion no longer throws `<INVALID OREF>` when no live read happened, so a vacuous run reports every failed precondition and anchor). No new test file.
- mutation: `Checks/Coverage.cls` :253 `database.name` -> `database.directory` -> `OnlineDemoFacts` `TestFailingDigest` red (database-space anchor; host path, IP address, user name and IPv4 legs, in the text and in the Slots). AC 1 and the failing-digest row.
- mutation: `Checks/Coverage.cls` `Live`, after the failures part, `Set parts = parts_$ListBuild(failed.%Get(0).errorText)` -> `TestFailingDigest` and `TestPassingDigest` red on all five values, the fragment probes, all seven KEYLIKE alternatives and the IPv4 shape, in the text and in the Slots.
- mutation (Slots leg alone): `Checks/Coverage.cls` `Build`, after `VitalRows`, `If rows.%Size() > 0 Do rows.%Get(0).%Set("dir", reading.journal.directory)` -> only the "the Slots has no ..." legs red (host path, IP address, user name, IPv4) in both tests; every text leg green. A mutation that pushes a new row instead (`rows.%Push`) reddens the text too, because rows feed the lines.
- mutation (passing-digest row): `Checks/Process.cls` `ScopedFailures`, the scope condition removed so every failure counts -> `TestPassingDigest` red ("and the production sentence", "and the reserved sentence"); `TestFailingDigest` green.
- mutation (plants consumed): `Checks/Coverage.cls` `Build`, the `WatchRow` call replaced by a no-op -> both tests red on "one live read", "of the watched production" and the production anchors, with no throw.
- mutation (`onlineDemo` restored): `OnlineDemoFacts` `OnAfterOneTest` restore line deleted. On QA's version: `OnlineDemoFacts` green, then `Test.Digest.Coverage` `TestLiveRead` red on "control: this is not the online demo" and on the instance-failures assertion. Since code review: red in `OnlineDemoFacts` itself (see the code-review block below).
- Also green on the warm stack: `OnlineDemoFacts`, `Test.Digest.Coverage`; `test-boundaries.sh` and `test-class-rules.sh` pass; compile check on `ocutalon-slot-b` (build 154) OK.

**Code review stage, warm tag `e17s11cw` and fresh tag `e17s11c` on lane B.** Each mutation was made from a backup in the stage scratch folder and restored byte for byte (`cmp`). The product tree is unchanged at the end.
- Gap shown before the patch: `Checks/Coverage.cls` :355 `ScopedFailures(failed, check.SessionRef, ##class(OcuTalon.Watch.Reader).OnlineDemo())` -> `..., 0)`. QA's `OnlineDemoFacts` stayed green.
- mutation (online-demo scoping): the same :355 change on the patched class -> `TestPassingDigest` red ("and the production sentence", "and the reserved sentence"); `TestFailingDigest` green. Passing-digest row; it pins that the online demo does not count failures scoped to the instance.
- mutation (online demo on): `OnlineDemoFacts` `OnBeforeOneTest`, the `Set("onlineDemo", 1)` line deleted -> both tests red on "on the online demo", and `TestPassingDigest` also red on the production and reserved sentences.
- mutation (plants match KEYLIKE): `OnlineDemoFacts` `OtherKeys`, the DigitalOcean fill `b` -> `g` (not hex) -> both tests red on "a planted value matches KEYLIKE alternative 5", and on nothing else.
- mutation (AC 1, re-run on the patched class): `Checks/Coverage.cls` :253 `database.name` -> `database.directory` -> `TestFailingDigest` red on the database-space anchor and on the host path, IP address, user name and IPv4 legs, in the text and in the Slots. The failure lines name labels only.
- mutation (`onlineDemo` restored): `OnlineDemoFacts` `OnAfterOneTest`, the restore line deleted -> `TestFailingDigest` red on "the test left the onlineDemo key as it found it", in forward order. This was the last warm run; the stack was torn down after it.
- Green after the reverts: `OnlineDemoFacts` (warm), `Test.Digest.Coverage` (warm, run after it). Fresh stack: `ci/iris.sh class OcuTalon.Test.Digest.OnlineDemoFacts` passed (ready 116 s, class 0.44 s). `test-boundaries.sh` ("keys: nothing key-like", "ascii") and `test-class-rules.sh` (assert-concat) pass. Compile check on `ocutalon-slot-b` (build 154) OK; the class was not run there. Both tags were torn down.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** One new test class pins that the online-demo digest names no host path, IP address, user name or key. It plants made-up values in the instance facts the digest reads, composes the digest through the real `Digest.Process` and `Checks.Coverage.Build`, renders it with `DigestText.Text(slots, "web")`, and checks the text and the Notification's whole Slots JSON. On unchanged product code it is green: no leak today, and no product code changed.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Test/Digest/OnlineDemoFacts.cls` (new): `TestFailingDigest` (the pin) and `TestPassingDigest`; leak check of five planted values, two fragment probes, one key shape for each other KEYLIKE alternative, every KEYLIKE alternative and an IPv4 shape.
- This spec: status, the Review Triage Log and the Verification mutation lines.

**Review findings.** Patches applied: 5 (1 medium: plants for the five unplanted KEYLIKE alternatives; 4 low: unused return field and a ClassMethod, two fragment probes, two mutation lines demonstrated). Deferred: none. Rejected: 11 with the reasons in the triage log (low or false, or the fix edits this spec or a file on the Never list).

**Follow-up review recommended:** false (one medium patched).

**Verification.** Compile check on `ocutalon-slot-b` (build 154): OK. On the warm stack (lane B): `OnlineDemoFacts`, `Coverage`, `AllClear`, `Due` and `Compose` pass. `test-boundaries.sh`, `test-class-rules.sh` and `test-ci-config.sh` pass ("keys: nothing key-like", assert-concat included). Fresh stack: `shard lane-a@Digest` passes forward and in reverse (22 classes), run again after the last patch. The four mutations above were each applied, observed red, restored byte for byte and seen green again. Both stacks are torn down.

**Residual risks.** The "a message waiting 15 minutes" anchor depends on under 60 s between planting and reading. The test must never run on a dev slot (it plants key-shaped values and sets `onlineDemo`).
