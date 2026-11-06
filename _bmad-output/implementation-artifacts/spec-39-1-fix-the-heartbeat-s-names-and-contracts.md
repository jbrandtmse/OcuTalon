---
title: 'Story 39.1: Fix the heartbeat''s names and contracts'
type: 'feature'
created: '2026-11-03'
status: 'done'
baseline_revision: '34bbf984e0d00cb44a35dc4cc758781629732c9f'
baseline_commit: '34bbf984e0d00cb44a35dc4cc758781629732c9f'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: 'OcuTalon.Live.Payload.Heartbeat is not created in 39.1: a payload class cannot land without Lane B and Epic 31-contended edits in the same commit'
    severity: med
    footprint: in-epic
    location: 'src/ocutalon/cls/OcuTalon/Live/Payload/ (new class), Live/Publish.cls TYPES, Test/Live/Payloads.cls, web/src/app/live/payloads.ts'
    evidence: 'web/scripts/payloads.mjs (run by `npm run build`, so by every job that builds the bundle) fails closed on a payload class not in Live.Publish TYPES; Test.Live.Payloads.TestEventTable requires the direct classes of OcuTalon.Live.Payload to be exactly the 16 of TYPES, and TestContracts counts 30 classes. TYPES and payloads.ts are Lane B files contended by Epic 31 (the lead: do not edit Live/Publish.cls), and Test.Live is a Lane B test (U-177). The class, the `heartbeat:Heartbeat` TYPES pair, the two Test.Live.Payloads counts and the regenerated payloads.ts must land together, before Story 39.3 publishes the event (Publish refuses a type not in TYPES). Suggested owner: 39-3, with the Lane B append arranged by the lead (39.2 or a ruling). The spine row "Story 39.1" in the Built-in column for this class needs the lead''s correction.'
  - summary: 'UX lists no text for the "Run the heartbeat now" button while it is unavailable (cap reached or no key)'
    severity: low
    footprint: in-epic
    location: '_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md, Later Steps > Personality, the Heartbeat checklist card'
    evidence: 'The epic context says "unavailable with the reason when cap reached or no key"; the UX block gives only the cooldown text and the skip texts. Story 39.5 must reuse an accepted text or escalate, never invent one (UX-DR117). Suggested owner: 39-5.'
---

<intent-contract>

## Intent

**Problem:** The agent heartbeat's Lane A and Lane B stories need fixed names before either can build: the table, the run-now request, the beat class and the settings names. Today none of them exists in code, and the spine records neither the Lane B command verbs nor the per-person defaults.

**Approach:** Check the spine's ownership tables (all heartbeat rows are already there) and add the missing names under the 2026-10-31 amendments. Add `OcuTalon.Data.HeartbeatBeat`, `OcuTalon.Checks.Msg.BeatNow` and a do-nothing `OcuTalon.Checks.Beat`. Then wire `Checks.Process` so that a Tick calls `Beat.RunDue` last, inside its own Try/Catch, and a `BeatNow` is answered OK. Nothing new reaches `Intake`.

## Boundaries & Constraints

**Always:**
- Lane A files only, except the appended table entry in the shared oracle `Test/Data/Tables.cls` (precedent: Story 30.4). Report that file as a footprint extension.
- `HeartbeatBeat` holds exactly AD-18's 15 fields and sets `Parameter DEFAULTGLOBAL = "^OcuTalonP.HeartbeatBeat"`. Its row in `src/short-names.tsv` is `HeartbeatBeat	^OcuTalonP.HeartbeatBeat	OcuTalon.Data.HeartbeatBeat	A`. The class carries the storage block that the compiler generates, exported from slot D. The same goes for `BeatNow`: its message storage block is committed and it sets no `DEFAULTGLOBAL`.
- `Checks.Process` keeps its existing order (quiet sweep, then fixes, then due checks). `RunDue` runs after them, in its own Try/Catch. An error status or an exception there logs one Type 3 warning (`LOGBEAT`, redacted text), and the Tick still answers OK.
- A `BeatNow` calls `Beat.RunNow(SessionRef)` in its own Try/Catch and answers OK with no response object. A failure logs one Type 3 warning (`LOGBEATNOW`). No log line names a `SessionRef`.
- Each call into `Beat` goes through a private seam method on `Checks.Process`, as `FixRunSweep` does, so that the test probe can replace it.
- Comments state contracts only (Rule 14). Use ASCII only in product files, and write repository-relative paths in every committed file.

**Never:**
- No new production item, and no edit to `Production.cls` or `docker/tests/test-production.sh`. Its item list stays unchanged.
- Nothing is sent to `Intake` or any other item from a beat or a `BeatNow`. No `BackgroundCheck` row, check result or coverage entry is made for a beat (AD-28).
- No `Live/Payload/Heartbeat.cls`, and no edit to `Live/Publish.cls`, `Test/Live/**`, `web/**`, `Msg/Enum.cls`, `Core/**` or any other Lane B file. The `Msg.Command` verbs are Story 39.2's.
- No change to the rule of any AD, and no non-additive edit to the spine. No edit to `EXPERIENCE.md`.
- No install path change (`Install/**`, `src/module.xml`, `docker/**`), and no test run on slot D.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tick runs beats last | probe; one due zzprobe watch fed `read`/`running`; Tick at TICK | the row runs (passed), then `RunDue` is called once with TICK, after the row's read and after every send | none |
| Tick, RunDue throws | probe `BeatThrows` set to the test's marker | the Tick still answers OK, and one `LOGBEAT` warning holds the marker | caught; one Type 3 warning |
| Tick, RunDue error status | probe `BeatError` set to the marker | the Tick answers OK, and one `LOGBEAT` warning holds it | one Type 3 warning |
| BeatNow | `BeatNow` (fixture SessionRef, RequestedAt) via `OnRequest` | status OK and response ""; `RunNow` is called once with that SessionRef; no send, no row read, no `RunDue` | none |
| BeatNow, RunNow throws | probe `BeatNowThrows` set to the marker | status OK; one `LOGBEATNOW` warning holds the marker and not the SessionRef | caught |
| BeatNow in the running production (Integration) | a `BeatNow` sent synchronously from the `HeartbeatIn` service to `Checks` on a fresh throwaway | the send returns OK; the service's session has no message whose target is `Intake`, and no request from `Checks` | assertion failure |
| Stubs | `RunDue(TICK)`, `RunNow(ref)`, `Snapshot(ref, TICK)`, `Key("x")` | `$$$OK`, `$$$OK`, "", ""; no `HeartbeatBeat` row is made for the fixture ref | none |
| Setting names | `SettingKey(ref, "interval")`, `SettingKey(ref, "zz")` | `person.<ref>.heartbeat.interval` and "" | unknown name gives "" |
| Unknown request | `Ens.StringRequest` | still the error 5001 that names the class (existing `TestUnknownRequest`) | unchanged |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- Checks. `OnRequest` is at line 148 (Tick, CheckChanged, else 5001). `Tick` (159-187) has three Try/Catch blocks, and the new fourth block goes after line 185. `FixRunSweep`/`SendFixResult` (218-228) are the seam pattern to mirror. The `LOG*` parameters are at 116-134. The class doc (1-51) lists the handled requests; update it.
- `src/ocutalon/cls/OcuTalon/Checks/Msg/CheckChanged.cls` -- the sibling that `BeatNow` mirrors (Ens.Request, `SessionRef` MAXLEN 22, a storage block with `<Subscript>`, no DEFAULTGLOBAL).
- `src/ocutalon/cls/OcuTalon/Data/BackgroundCheck.cls`, `Data/WatchMark.cls` -- the Lane A table siblings: the DEFAULTGLOBAL doc line, UTC stamps as `%String(MAXLEN = 20)`, refs as `%String(MAXLEN = 22)`, the Storage block shape.
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` -- source types: `Outcome` `%String(MAXLEN = 32)`, `CostUSD` `%Numeric(SCALE = 6)`, `TraceSessionId` `%Integer`, `Fallback` `%Boolean` with InitialExpression 0.
- `src/short-names.tsv` -- the registry (union-merge). Append one row. `docker/tests/test-storage.sh` checks the rules registry-duplicate, registry-class, registry-row and prefix.
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- `TestEveryTableIsRegistered` (line 46) fails for any persistent `OcuTalon.Data.*` class missing from `XData Registry` (608+, last entry `LiveEvent`). `XData Contracts` (145+, last entry `OcuTalon.Data.FixRun`, about line 600) pins the fields. `Test.Contract.Ac.TestEveryStorageGlobalIsPrivate` reads the same Registry.
- `src/ocutalon/cls/OcuTalon/Test/Contract.cls` -- `AssertContract(xdata)` and `AssertMessageExtent(xdata)`, which the new test class reuses.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls` -- the shadow `Checks` with seams overridden. `Ordered`/`Order` is asserted at exactly 4 entries in `Runs.TestTickSendsTheSweptResults` (line 768), so beats must NOT go into `Order`. `Reset` and `Calls` are at lines 209 and 190.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- the probe tests (warm). Helpers: `Host` 903, `Owner` 912, `Watch` 926, `Feed`, `Tick` 1013, `Reads` 1097, `Warnings` 1110, `RemoveLogs` 1142. Its class doc lists the tests.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- the running-production tests (fresh only), through `Test.Watch.Case`. `Ready()`, `Session(name)` and the `HEARTBEAT`, `CHECKS` and `TICKWAIT` parameters and `SendTick` in `Test/Watch/Case.cls` (line 647) show how to send from `HeartbeatIn` to `Checks`.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` (TYPES, line 15), `web/scripts/payloads.mjs`, `Test/Live/Payloads.cls` (EXPECTED, TestEventTable, 30 contracts) -- read-only evidence for the Live.Payload.Heartbeat decision (Design Notes).
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-18 agent heartbeat (the "**Run now.**" sub-bullet, about line 558); AD-19 "**Areas:**" (about line 595); the ownership tables (production items about 1250, Tables line about 1272, cross-area rows 1296-1297, event row 1320, REST rows 1425-1426). There is no `.memlog.md` in this folder.
- `.claude/skills/bmad-architecture/scripts/lint_spine.py` -- the spine lint (run only).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/HeartbeatBeat.cls` (new) -- `Extends %Persistent`, Lane A. Doc: one row per session that has had a beat, written only by Checks (AD-18, AD-33). Add `Parameter DEFAULTGLOBAL = "^OcuTalonP.HeartbeatBeat"` and these properties, in this order:
  - `SessionRef` `%String(MAXLEN = 22)`;
  - `NextDueAt`, `LastBeatAt` `%String(MAXLEN = 20)`;
  - `LastItemId` `%String(MAXLEN = 22)`;
  - `LastOutcome` `%String(MAXLEN = 32)`;
  - `LastFallback` `%Boolean [ InitialExpression = 0 ]`;
  - `LastCostUSD` `%Numeric(SCALE = 6)`;
  - `LastDecisionRef` `%String(MAXLEN = 22)`;
  - `LastTraceSessionId` `%Integer`;
  - `LastSkipAt` `%String(MAXLEN = 20)`;
  - `LastSkipReason` `%String(MAXLEN = 32)`;
  - `LastRunNowAt`, `BackoffUntil` `%String(MAXLEN = 20)`;
  - `LastSnapshotKey`, `LastQuietKey` `%String(MAXLEN = 64)`.

  Stamps are UTC to the second. Add `Index SessionRefIndex On SessionRef [ Unique ]`. Compile it on slot D and write the generated Storage block back verbatim (`^OcuTalonP.HeartbeatBeatD/I/S`). -- AC 2, AD-3, AD-5, AD-18.
- `src/short-names.tsv` -- append the row above (tab-separated, trailing newline) -- AD-3.
- `src/ocutalon/cls/OcuTalon/Checks/Msg/BeatNow.cls` (new) -- `Extends Ens.Request`, mirroring CheckChanged. Properties: `SessionRef` `%String(MAXLEN = 22)` (the person's session, set by `CommandsIn` from the server-side session) and `RequestedAt` `%String(MAXLEN = 20)` (UTC). Doc: `CommandsIn` sends it for `RunHeartbeat` (Story 39.2), and Checks answers it OK. Compile it on slot D and commit its storage block. -- AD-18, AD-33.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` (new) -- plain class, Lane A. The stubs, which do nothing until Stories 39.3 and 39.4:
  - `ClassMethod RunDue(tickAt As %String) As %Status` and `RunNow(sessionRef As %String) As %Status` return `$$$OK`;
  - `Snapshot(sessionRef As %String, now As %String) As %String` and `Key(snapshot As %String) As %String` return "".

  It also holds the names as parameters: `KEYS = "on,interval,from,to,checklist"`, `INTERVALS = "30,60,120,240,480,1440"`, `DEFAULTON = 1`, `DEFAULTONDEMO = 0`, `DEFAULTINTERVAL = 30`, `DEFAULTFROM = "08:00"`, `DEFAULTTO = "20:00"`, `CHECKLISTMAX = 1000`. `ClassMethod SettingKey(sessionRef As %String, name As %String) As %String` returns `person.<sessionRef>.heartbeat.<name>` for a name in KEYS, else "". -- AC 2, AD-18, AD-19, AD-29.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- make these changes:
  - `OnRequest`: route `OcuTalon.Checks.Msg.BeatNow` to a private `BeatNow(request)`.
  - `Tick`: add a fourth Try/Catch after the due checks: `Set sc = ..BeatRunDue(tickAt)`, logging `LOGBEAT` on an error status or an exception.
  - `BeatNow`: Try `..BeatRunNow(request.SessionRef)`, log `LOGBEATNOW` on an error or an exception, then `Quit $$$OK`.
  - Seams: `BeatRunDue(tickAt) As %Status [ Private ]` and `BeatRunNow(sessionRef) As %Status [ Private ]` call `OcuTalon.Checks.Beat`.
  - Parameters: `LOGBEAT = "Checks could not run the heartbeat's due beats: "` and `LOGBEATNOW = "Checks could not run a requested heartbeat: "`.
  - Update the class doc (three requests; the Tick's fourth step). -- AC 2, AD-18.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls` -- add transient properties:
  - `Beats` (%DynamicArray of `{"tickAt", "reads": the number of Read calls so far, "sends": the Order size so far}`), `BeatThrows` and `BeatError` (marker text);
  - `BeatNows` (%DynamicArray of `{"sessionRef"}`) and `BeatNowThrows`.

  Override `BeatRunDue` and `BeatRunNow` to record only (never call the real `Beat`), then to throw or return an error status when asked. Leave `Order` unchanged. Update the doc. -- the test seam, which also keeps every probe Tick from running real beats in 39.3+.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- add three tests, update the doc, and remove the test's own `LOGBEAT`/`LOGBEATNOW` lines (match its marker) in `RemoveLogs`:
  - `TestTickRunsTheBeatsLast`, `TestBeatsThatFailAreLogged`: matrix rows 1-3;
  - `TestBeatNow`: rows 4-5.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- add `TestBeatNowIsAnswered` (matrix row 6, Integration AC): `If '..Ready() Quit`, take a fixture session, create the `..#HEARTBEAT` service, `SendRequestSync(..#CHECKS, beatNow, .response, ..#TICKWAIT)`. Assert the status is OK. Then, by SQL on `Ens.MessageHeader` for the service's `%SessionId`, assert zero messages with `TargetConfigName = 'Intake'` and zero requests whose source is `Checks`. Update the doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` (new) -- `Extends OcuTalon.Test.Contract`, with its own `XData Contracts` holding `OcuTalon.Checks.Msg.BeatNow` (super `Ens.Request`, the two props).
  - `TestBeatNowContract`: `AssertContract` plus `AssertMessageExtent`.
  - `TestStubsDoNothing`: matrix row 7; count the `HeartbeatBeat` rows of a fixture ref before and after.
  - `TestSettingNames`: row 8 and every parameter value.

  It needs no production (warm).
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- append a contract for `OcuTalon.Data.HeartbeatBeat` after `OcuTalon.Data.FixRun` in `XData Contracts` (super `%Persistent`, the 15 props as above, indexes `{"SessionRefIndex": "SessionRef unique"}`). Append `{"short": "HeartbeatBeat", "global": "^OcuTalonP.HeartbeatBeat", "class": "OcuTalon.Data.HeartbeatBeat"}` to `XData Registry`. -- AC 2; required by `TestEveryTableIsRegistered`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- additive only:
  - (a) In AD-18, directly after the "**Run now.**" sub-bullet, insert this line at the same indent (4 spaces):

    ```text
        - **Names** [ADDED 2026-11-03, Story 39.1, as its acceptance criteria list them]. Lane B's Story 39.2 creates, in `OcuTalon.Msg.Command`, the verbs `SetHeartbeat` (`On`, `Interval`, `From`, `To` and `Checklist`, plus the common command fields `Origin`, `IdempotencyKey` and `SessionRef`), which `CommandsIn` routes to `SettingsOps`, and `RunHeartbeat`, which it routes to `Checks` as a `BeatNow`, both from origin `web_user` only; and it appends the channel value `heartbeat` at the end of `Msg.Enum` CHANNEL. The per-person keys are `person.<SessionRef>.heartbeat.on`, `.interval`, `.from`, `.to` and `.checklist`, with the defaults and caps of AD-19.
    ```

  - (b) In AD-19, append this sentence to the end of the "**Areas:**" line, after a space:

    ```text
    The heartbeat's defaults are `1`, `30`, `08:00`, `20:00` and "" (empty), and `on` is `0` on the online demo (AD-18) [ADDED 2026-11-03, Story 39.1].
    ```

  - Leave the ownership tables unchanged: every heartbeat row is present (Design Notes).
  - Set the frontmatter `updated:` to the edit date and run the lint. There is no `.memlog.md`, so skip the memlog append (Rule 20). -- AC 1, Rule 20.

**Acceptance Criteria:**
- Given the AD-18, AD-19 and AD-33 amendments of 2026-10-31, when this story updates the spine, then its ownership tables still hold each heartbeat row (`HeartbeatBeat` on the Tables line; the `BeatNow` and `Live.Payload.Heartbeat` cross-area rows; the `heartbeat` event row; the `GET`/`PUT /api/v1/heartbeat` and `POST /api/v1/heartbeat/run` rows) with nothing added. It also holds `SetHeartbeat` with its five fields and the common fields, `RunHeartbeat`, the channel value `heartbeat` appended to `Msg.Enum` CHANNEL, the five `person.<SessionRef>.heartbeat.*` keys, and the defaults `1`, `30`, `08:00`, `20:00` and "" with AD-19's caps. `lint_spine.py` reports `"ok": true`.
- Given the package compiled on a fresh lane-D throwaway, when `Test.Data.Tables` runs, then `OcuTalon.Data.HeartbeatBeat` has exactly AD-18's 15 fields and its unique `SessionRefIndex`. Its DEFAULTGLOBAL is `^OcuTalonP.HeartbeatBeat`, and its data and index globals resolve to the private database. `bash docker/tests/test-storage.sh` passes with its new registry row and committed storage block.
- Given `OcuTalon.Checks.Beat`, when `RunDue`, `RunNow`, `Snapshot` and `Key` are called, then they do nothing: they return OK or "", and they write no row and send nothing.
- Given the probe Checks, when a Tick is handled, then `RunDue` is called once with the Tick's time, after the due checks. A failing `RunDue` is logged once, and the Tick still answers OK.
- Given the running production on a fresh throwaway, when `HeartbeatIn` sends `Checks` a `BeatNow`, then Checks answers OK and nothing reaches `Intake` (Integration AC: consumer `Checks` turns the new `BeatNow` contract into an observable OK answer with no send).
- Given the story's diff against `origin/feature/OCT_OcuTalon_MVP`, when it is compared, then `Production.cls`, `docker/tests/test-production.sh`, `Live/**`, `Test/Live/**` and `web/**` are unchanged.
- Given EXPERIENCE.md › Later Steps › Personality, when this story begins, then the heartbeat card's texts are recorded there under the marker `[ADDED 2026-10-31, owner decision, relayed by the Contest Planner (U-195) ...]`. Checked at planning (EXPERIENCE.md lines 963-979): **pass**. This story ships no user-facing text (UX-DR117).

- [x] [Smoke] `docker/tests/test-boundaries.sh` fails its rule "keys: nothing key-like" on `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls:1035` (`TestBeatLogsAreRedacted`'s fixture secret is one key-shaped literal) -- build the fixture by concatenation, as `Test/Watch/NoticeText.cls:581` and `Test/Watch/Evidence.cls:193` do (`"sk-"_"ant-..."`), keep the test's assertions unchanged, and re-run `bash docker/tests/test-boundaries.sh` (no FAIL) plus `OcuTalon.Test.Checks.Runs` on a lane-D warm throwaway.

### Review Findings

Code review 2026-11-03 (first review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 33 rows, 23 entries: high 0, medium 3, low 20). Rule 3: exempt (no user-facing surface). Rule 6: the spine edit is the two additive inserts and changes no AD Rule; AD-18 (fields, RunDue last in its own Try/Catch, BeatNow), AD-3, AD-5, AD-28, AD-29 and AD-33 hold.

- [x] [Review][Patch] (med; fix-risk low: test-only) `TestStubsDoNothing` could not fail on a row write: `Rows("")` bound "" as SQL NULL so it always counted 0, and the fixture ref was longer than `SessionRef` MAXLEN 22 so no row of it could be saved; now a `NewRef()` ref, a separate whole-table count and a cleanup of the ref's rows [src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls:17]
- [x] [Review][Patch] (med; fix-risk low: test-only) the `LOGBEATNOW` counts in `Runs.TestBeatNow` and `TestBeatLogsAreRedacted` counted any job's lines (not hermetic); `Beaten` now takes the method and counts only lines holding the test's marker [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls:1255]
- [x] [Review][Patch] (med; fix-risk low: tracking doc) AC 1's grep loop could not fail for `SetHeartbeat`/`RunHeartbeat` (both already in the baseline spine); the needles now occur only in this story's inserts, mutation recorded [spec ## Verification]
- [x] [Review][Patch] (low; fix-risk low) AC 6's `git diff origin/...` form compares the merge base with HEAD and cannot see an uncommitted change, and AC 6/7 had no mutation line; command corrected, mutation recorded, AC 7 recorded as a planning-time reading [spec ## Verification]
- [x] [Review][Patch] (low; fix-risk low) `CHECKLISTMAX` copied the 1,000 that AD-19 defines as the length of `Setting.Value` with no link; `TestSettingNames` now compares it with `Setting.Value`'s MAXLEN [src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls:53]
- [x] [Review][Patch] (low; fix-risk low) `Checks.Beat` extended `%RegisteredObject`; the spec says a plain class, as its siblings `Checks.Render` and `Watch.Settle` are [src/ocutalon/cls/OcuTalon/Checks/Beat.cls:4]
- [x] [Review][Patch] (low; fix-risk low) test doc lines narrated history ("QA additions (Story 39.1)", "(QA)"), Rule 14 [src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls:4, Runs.cls:47]
- [x] [Review][Defer] (low; fix-risk med; out-of-footprint) `lint_spine.py` reports `"ok": false` for 8 placeholder findings that are deliberate catalog slot syntax, pre-existing at baseline (lines 454, 1010, 1023, 1086, 1091), so AC 1's `"ok": true` reads as "no new finding" [ARCHITECTURE-SPINE.md] - deferred: pre-existing; DW-638 wontfix-accepted, reopen_if a new lint finding or a Rule 20 halt on them

Rejected:
- (low, by-design) `Heartbeat.TestBeatNowIsAnswered` counts Intake messages only in the service's session, while AD-18 sends a beat's Item in a session of its own: matrix row 6 fixes the session scope; in 39.1 nothing is sent; Story 39.3 makes `RunNow` send to Intake by design, and real Ticks send findings to Intake, so a namespace-wide count would be flaky now and inverted then.
- (low) the AD-18 "Names" line spells the five keys in full instead of the spec's short form: same meaning, additive, no AD Rule changed, and the spec's own needle `heartbeat.checklist` needs the long form; the fix would edit the spec. Accepted under the Rule 6 check.
- (low) the Auto Run Result is stale after QA (test counts, mutation count, test time): the fix edits the spec's build-auto record.
- (low) the earlier triage header's counts (22) differ from its rows (18, with same-root rows): the fix edits the spec's record.
- (false) the spec frontmatter says `done` while sprint-status says `review`: frontmatter `status` is build-auto's machine state, by process.
- (low) the DW-633 bullet in `epics.md` omits the spine Built-in cell and the Lane B arrangement: the 39.3 plan spawn receives the full ledger slice (Rule 17 1b), which carries both.
- (low) no story deletes a session's `HeartbeatBeat` row at sign-out: AD-19 deletes the values (Story 39.2's `SessionOps.End` AC), the row holds refs and times only, the demo reset removes it, and with the keys gone a demo session's `on` is 0, so `RunDue` skips it.
- (low, spec-bound) AD-19's defaults sentence and `Beat` give no demo sample checklist: the sentence is the spec's verbatim text, and the sample is UX text that 39.2's GET shows unstored.
- (low, theoretical) a `RunNow`/`RunDue` error text naming a SessionRef would reach the log, and the class doc's "No log line names a SessionRef" is not enforced: the text comes from Beat's stubs; Story 39.3 owns the text when it fills them.
- (low, theoretical) `Redact.Text` or `$$$LOGWARNING` throwing inside a Catch: the same shape as every sibling block of `Tick`.
- (low, spec-bound) an empty `BeatNow.SessionRef`, a dotted ref in `SettingKey`, `SessionRef` not Required: the Ref comes from the server-side session (`CommandsIn`, 39.2); the spec fixes the 15 fields and the one index.
- (low) AC 3's "send nothing" has no assertion on the stubs: Beat's class methods hold no business host, so they cannot send; `TestBeatNowIsAnswered` pins the `RunNow` path.
- (low) the spine's Built-in cell still names Story 39.1 for `Live.Payload.Heartbeat`: already DW-633 (routed 39-3).

#### Code review 2026-11-03 (re-review of rework 1, baseline 34bbf984)

Layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 9 rows (7 after joining two same-root pairs), 0 entries (high 0, medium 0, low 0). Clean review. Rule 3: exempt (a test fixture). Rule 6: no AD touched.

- Previous round's open item, `[Smoke]` key-like fixture: **fixed**. `TestBeatLogsAreRedacted` builds its secret as `"sk-"_"ant-api03-..."` (the same runtime string, so the test still redacts a key-shaped value); only the `Set secret` line changed, so the four `[ "QaSecret"` assertions are unchanged; `bash docker/tests/test-boundaries.sh` exits 0 with `PASS keys: nothing key-like` and no FAIL; `OcuTalon.Test.Checks.Runs` passed on a fresh lane-D throwaway (run tag `e39s1cr2`, 3.78 s, stack start 109 s). The rework's `mutation:` line is present and current.

Rejected:
- (false) the re-review should start from `3ffdc2f8`, leaving `f0e7943d`'s changes unreviewed: that commit is the sanctioned rework commit holding QA's tests, which the first review covered, and the first review's own patches, listed above and run warm after patching; the boundaries scan now passes on every file and `Checks.Runs` passes fresh.
- (low) the spec's frontmatter baseline now names the rework's baseline instead of the story's `3f5f7b3e`: the fix edits the spec's frontmatter, which the lead owns; the first review's baseline is recorded in this section and the cycle log.
- (low) the cycle log's `dev_complete` note says the build left `baseline_revision` unset, and the row lacks cycle 1's `nfr_tripwires=`/`loc_*` fields: lead-owned telemetry, outside this review's authority; no product effect.
- (low) the Rework 1 note does not say where the literal came from, and the cycle-1 Auto Run Result's "no FAIL line" claim predates QA's literal: the fix edits the spec's build-auto record; the claim was true for its pass.
- (false) frontmatter `status: done` while sprint-status says `review`: build-auto's machine state, by process (as at the first review).
- (false) the rework's warm run does not name its lane: its tags `e39s1rw1`/`e39s1rw1w` are lane-D tags, and this review ran the class again on lane D.
- (false) no review layers ran for the rework: this review is that review.

## Spec Change Log

- 2026-11-03, lead, rework iteration 1 (trigger smoke): the lead's pre-commit check run found one key-like literal in a QA test; one [Smoke] item added under Tasks & Acceptance.

- 2026-11-03, lead at spec validation: the (once) `bash ci/checks.sh` line split into three capped calls (the 10-minute foreground cap).

## Review Triage Log

### 2026-11-03 - Review pass
- verdicts: 22 findings - high 0, medium 2, low 18, false 2, maybe-false 0 (the intent-alignment layer reported readings only, no finding: it found the diff implements the narrow wiring-and-names reading, with the production-level Tick to real `RunDue` link not exercised because `RunDue` is a stub)
- findings:
  - `[low]` `[patch]` (blind-hunter, edge-case-hunter x2, verification-gap other) `Probe.BeatRunDue` read `..Order.%Size()` through a non-short-circuit `*`, which raises `<INVALID OREF>` when no send has created `Order` - fixed with `$Select($IsObject(..Order): ..Order.%Size(), 1: 0)`; the Tick's catch had been logging the OREF error instead of the injected marker on a send-free Tick
  - `[medium]` `[patch]` (blind-hunter, verification-gap) `BeatNow`'s error-status path was untested and the probe had no knob for it - added `BeatNowError` to the probe and a third case in `Runs.TestBeatNow`; mutation line written
  - `[low]` `[reject]` (blind-hunter, edge-case-hunter) a `RunNow`/`RunDue` error text that names the SessionRef is not scrubbed from the log - the text comes from `Beat`, which Story 39.3 fills; `Redact.Text` is the only filter and nothing in this story can put a Ref in it (theoretical here)
  - `[low]` `[patch]` (blind-hunter, verification-gap) `TestStubsDoNothing` compared a never-used fixture ref with itself - now compares the whole table's row count before and after, uses no counter global
  - `[low]` `[reject]` (blind-hunter) `Heartbeat.TestBeatNowIsAnswered` hard-codes `'Intake'` - the spec's matrix row names it; the response assertion was added with the control below
  - `[low]` `[reject]` (blind-hunter, edge-case-hunter) `Beat.SettingKey` accepts an empty or dotted `sessionRef` - the spec fixes it as `person.<sessionRef>.heartbeat.<name>` for a name in KEYS, the Ref comes from the server-side session, and 39.2 owns the caller (spec-bound)
  - `[low]` `[reject]` (blind-hunter, edge-case-hunter) `HeartbeatBeat.SessionRef` not Required and no `NextDueAt` index - the spec fixes AD-18's 15 fields and the one unique index; the due-scan index is 39.3's call when it writes `RunDue` (spec-bound)
  - `[low]` `[reject]` (blind-hunter) the spine "Names" insert omits `Beat`, `RequestedAt` and the seams - the spec gives the two inserts verbatim and forbids other spine edits (spec-bound)
  - `[low]` `[reject]` (edge-case-hunter) a `BeatNow` with an empty SessionRef reaches `Beat.RunNow` - `CommandsIn` sets it from the server-side session; `RunNow` is a stub, and its validation is Story 39.3's
  - `[medium]` `[patch]` (verification-gap) same root as the second row above (the unlogged `RunNow` error status)
  - `[low]` `[reject]` (verification-gap) the real `BeatRunDue`/`BeatRunNow` seams are not pinned to the right `Beat` method - the stubs have no observable effect to assert on; Story 39.3 pins the wiring when it fills them (reopen_if: `RunDue` or `RunNow` gains an effect)
  - `[low]` `[patch]` (verification-gap) the Intake/Checks counts in `TestBeatNowIsAnswered` had no positive control - added the count of requests to Checks (1) and an empty-response assertion; the no-send mutation went red on the Intake assertions
  - `[low]` `[patch]` (verification-gap) same root as `TestStubsDoNothing` above
  - `[low]` `[reject]` (verification-gap) two of the five grep needles (`SetHeartbeat`, `RunHeartbeat`) were already in the baseline spine - the fix is to edit the spec's Verification commands; the edit was read in the diff instead
  - `[low]` `[reject]` (verification-gap) AC 6 and AC 7 have no mutation line - both are diff or text checks, not tests
  - `[false]` `[reject]` (verification-gap) `TestSettingNames` pins literals against the same literals - the names, defaults and caps are the contract being pinned; the KEYS loop reads the parameter by design
  - `[false]` `[reject]` (verification-gap) `TestBeatsThatFailAreLogged` counts cumulatively - the count is asserted after each Tick (1, then 2), so a double log in one Tick fails the first check
  - `[low]` `[patch]` (verification-gap other) the Probe `Order` evaluation - same root as the first row

## Design Notes

**Governing ADs:**
- AD-18: the agent heartbeat, its table, RunDue after the due checks in its own Try/Catch, BeatNow, no scheduler.
- AD-19: per-person keys, defaults and caps.
- AD-29: lanes; Lane A names and Lane B creates the verbs; append-only shared files.
- AD-33: one owner per table, item and event, and the ownership tables.
- AD-3: `DEFAULTGLOBAL` and the short-names registry.
- AD-5: committed storage blocks and nothing "due" in memory.
- AD-28: a beat is no background check.
- AD-1 (BeatNow comes from `CommandsIn` in 39.2) is noted only.

**Spine check (AC 1).** Every heartbeat row the AC names is already in the tables: Tables "Lane A owns `HeartbeatBeat` (Story 39.1)"; the cross-area rows for `BeatNow` (`SessionRef`, `RequestedAt`) and `Live.Payload.Heartbeat`; the event row `heartbeat` (publisher `Checks`); and the two REST rows. `RunHeartbeat` appears in AD-18's Run now. Missing were `SetHeartbeat` and its fields, the `Msg.Enum` CHANNEL append, and the defaults, so Task (a) and Task (b) add only those, under the existing amendments.

**Decided in-stage:**
- `Live.Payload.Heartbeat` is not created in this story, although the spine's Built-in column says Story 39.1. No AC asks for it. A new payload class breaks `web/scripts/payloads.mjs --check`, and with it the web build, plus `Test.Live.Payloads.TestEventTable`/`TestContracts`, unless `Live.Publish` TYPES, `Test.Live.Payloads` and `web/src/app/live/payloads.ts` change in the same commit. All three are Lane B files, and two are Epic 31-contended (the lead: do not edit `Live/Publish.cls`). This is routed in `deferred` (suggested owner 39-3, with a Lane B append) for the lead to arrange, together with the Built-in cell. Reversible: the class is a later additive file.
- The stub return types are `%Status` for `RunDue` and `RunNow`, and `%String` for `Snapshot` and `Key`. `Beat` is Lane A's only (no cross-lane caller), so Stories 39.3 and 39.4 may refine them. No pin goes into `Test.Contract.Ac`.
- The setting names, defaults, interval list and checklist cap live as `Beat` parameters plus `SettingKey`, so later stories read one source instead of copying literals (Rule 2). Story 39.2 may read them; it edits nothing in `Beat`.
- The probe records beats in its own `Beats`/`BeatNows` arrays, never in `Order`, because `TestTickSendsTheSweptResults` pins `Order` at 4.
- No log line carries a `SessionRef` (AD-18 keeps it out of the event; the log follows suit).

**Extend, don't copy (Rule 2):**
- `BeatNow` mirrors `Checks/Msg/CheckChanged.cls`, and `HeartbeatBeat` mirrors `Data/BackgroundCheck.cls` and `Data/WatchMark.cls` (types, DEFAULTGLOBAL doc, storage).
- The seams mirror `FixRunSweep`/`SendFixResult`.
- The tests extend `Test.Checks.Runs`/`Probe`/`Heartbeat` and the `Test.Data.Tables` oracle, and the new `Test.Checks.Beat` reuses `Test.Contract.AssertContract`/`AssertMessageExtent`.

**Integration ACs:** `Checks.Process` is the in-story consumer. It calls `RunDue` on every Tick (probe, matrix rows 1-3), and it answers a real `BeatNow` in the running production with no send (matrix row 6).

**Consumed-by:**
- 39.2: `CommandsIn` sends `BeatNow` for `RunHeartbeat`. Its GET reads the `HeartbeatBeat` row and may read `Beat`'s defaults.
- 39.3: fills `RunDue`/`RunNow` and writes `HeartbeatBeat` rows (and needs `Live.Payload.Heartbeat`, deferred above).
- 39.4: fills `Snapshot`/`Key`.
- 39.5: reads the row's public view through 39.2/39.3.

**Consumes:** `Checks.Process`'s Tick handling (Epics 5, 8 and 30) only.

**Ledger inbox:** none.

**Footprint:** all paths are in Epic 39's paths_hint except `Test/Data/Tables.cls`, which is not contended (checked against `origin/OCT-epic12`, `13`, `31` and `40`). Report it under `footprint_extensions`. There is no contended-file edit; `Data/Ownership.cls` lists no tables and is untouched.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`. Each command is a foreground call with `timeout: 600000`, one test class per call, never two at once.

Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`; check it with `iris_server_info`, port 52793, build 154) is used only to load (`iris_doc_load`, absolute path, `baseDir` `<worktree>/src/ocutalon/cls`), compile, and export the Storage blocks of `HeartbeatBeat` and `BeatNow`. Tests run on throwaways only. Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s1implw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s1implw ci/iris.sh class <Class>`, one call each. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Checks.Beat`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Contract.Ac`
- (loop) `<lane> OCUTALON_RUN_TAG=e39s1impl ci/iris.sh class OcuTalon.Test.Checks.Heartbeat`, fresh (production code). Expected: passed.
- (loop) `bash docker/tests/test-storage.sh`. Expected: every rule passes, including the `HeartbeatBeat` row.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: `"ok": true`.
- (loop) `for n in '`SetHeartbeat` (`On`, `Interval`, `From`, `To` and `Checklist`, plus the common command fields `Origin`, `IdempotencyKey` and `SessionRef`)' '`RunHeartbeat`, which it routes to `Checks` as a `BeatNow`' 'Msg.Enum` CHANNEL' 'heartbeat.checklist' '`08:00`, `20:00`'; do grep -qF "$n" _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md || echo "MISSING $n"; done`. Expected: no output. [code review: the bare `SetHeartbeat` and `RunHeartbeat` needles were already in the baseline spine; each needle now occurs only in this story's inserts]
- (once) `git diff --exit-code "$(git merge-base origin/feature/OCT_OcuTalon_MVP HEAD)" -- src/ocutalon/cls/OcuTalon/Production.cls docker/tests/test-production.sh src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Test/Live web`. Expected: exit 0. [code review: the earlier `origin/feature/OCT_OcuTalon_MVP...` form compares the merge base with HEAD and cannot see an uncommitted change]
- (once) The hosted `checks` scripts, in parts (the whole `bash ci/checks.sh` takes about 16 minutes locally, over the 10-minute cap): list them with `. ci/units.sh; echo $CHECK_SCRIPTS`, then run them in three foreground calls of about a third of the list each, `for n in <part>; do bash docker/tests/test-$n.sh >/dev/null 2>&1 || echo "FAIL $n"; done` (each call under 8 minutes). Expected: no FAIL line. [lead edit at spec validation]
- (once) `<lane> OCUTALON_RUN_TAG=e39s1impl ci/iris.sh shard lane-a@Checks`, fresh. Expected: passed; record the time.
- (once) `<lane> OCUTALON_RUN_TAG=e39s1impl ci/iris.sh shard lane-b@Data`, then `shard lane-b@Contract,Live`, fresh, one call each. Expected: passed (`Test.Live.Payloads` unchanged at 16 types and 30 classes).
- (once) `<lane> OCUTALON_RUN_TAG=e39s1implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s1impl ci/iris.sh teardown`, also after a failure.

Pinning mutations to apply, observe red, revert and record (Rule 19):
- remove `LastQuietKey` → `Test.Data.Tables.TestContracts`;
- `Snapshot` returns "x" → `Test.Checks.Beat.TestStubsDoNothing`;
- move the beat block before the due checks → `Runs.TestTickRunsTheBeatsLast`;
- drop its Try/Catch → `Runs.TestBeatsThatFailAreLogged`;
- drop the `BeatNow` branch → `Heartbeat.TestBeatNowIsAnswered`.

Recorded mutations (Rule 19; each applied, observed red, reverted byte-identical):
- AC 2 (the 15 fields): mutation: removing the `LastQuietKey` property from `Data.HeartbeatBeat` made `Test.Data.Tables.TestContracts` fail ("property LastQuietKey is missing"); reverted, green.
- AC 3 (the stubs do nothing): mutation: `Beat.Snapshot` returning "x" made `Test.Checks.Beat.TestStubsDoNothing` fail ("Snapshot is empty"); reverted, green.
- AC 4 (RunDue after the due checks): mutation: moving the beat block before the due checks made `Runs.TestTickRunsTheBeatsLast` fail ("after the due row's read"); reverted, green.
- AC 4 (a failing RunDue is logged, the Tick answers OK): mutation: dropping the beat block's Try/Catch made `Runs.TestBeatsThatFailAreLogged` fail (the Tick threw the marker error); reverted, green.
- AC 5 (a BeatNow is answered OK): mutation: dropping the `BeatNow` branch of `OnRequest` made `Heartbeat.TestBeatNowIsAnswered` fail (error 5001 naming `OcuTalon.Checks.Msg.BeatNow`); reverted, green.
- AC 5 (nothing reaches Intake): mutation: `Process.BeatRunNow` sending an `Ens.StringRequest` to `Intake` made `Heartbeat.TestBeatNowIsAnswered` fail ("no message of the session is for Intake" and "and Checks sent no request"); reverted byte-identical, green.
- Matrix row 5, error-status path (a RunNow that answers an error status is logged, the answer is OK): mutation: dropping the `$$$ISERR` block of `Process.BeatNow` made `Runs.TestBeatNow` and `Runs.TestBeatLogsAreRedacted` fail ("and logs one more warning", counted by `Beaten(marker, .text, "BeatNow")`); reverted byte-identical, green. [re-observed at code review after the count was scoped to the test's marker]

QA additions (QA stage, run tags `e39s1qa`/`e39s1qaw`; every mutation applied, observed red, reverted byte-identical, green again):
- (QA) Files extended, no new file: `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` (`TestHeartbeatBeatRowAndUniqueness`: all 15 fields survive a save and reopen, the row sits in `^OcuTalonP.HeartbeatBeatD` and in no default global, a second row of the same SessionRef is refused, an empty row has `LastFallback` 0; more `TestSettingNames` edges: case, part of a name, trailing space or comma, a second session) and `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` (`TestBeatsRunWhateverEarlierStepsDo`, `TestBeatLogsAreRedacted`, `TestBeatNowKeepsEachSession`).
- AC 1 (the spine's names): mutation: deleting the AD-18 "Names" line made the Verification grep loop print `MISSING Msg.Enum` CHANNEL` and `MISSING heartbeat.checklist`; reverted. Limit: `SetHeartbeat` and `RunHeartbeat` also occur elsewhere in the spine, so those two needles stay green without the line; no bash unit is added (docker/tests/** is contended and under the stability watch, and a throwaway has no spine).
- AC 2 (SessionRefIndex is unique): mutation: dropping `[ Unique ]` from `Data.HeartbeatBeat` made `Test.Checks.Beat.TestHeartbeatBeatRowAndUniqueness` fail ("a second row of the same SessionRef is refused", "so the session still has one row").
- AC 2 (the registry row): mutation: the global `^OcuTalonP.HeartbeatBeats` in the `src/short-names.tsv` row made `bash docker/tests/test-storage.sh` fail (`registry-class`).
- AC 3 (SettingKey takes exact names only): mutation: `$ListFind` replaced by a substring test (`..#KEYS [ name`) made `Test.Checks.Beat.TestSettingNames` fail ("and a list of names", "so is a part of a name", "and with a comma after it").
- AC 4 (RunDue gets the Tick's time, a UTC stamp): mutation: `BeatRunDue(tick.TickAt)` instead of `tickAt` made `Runs.TestBeatsRunWhateverEarlierStepsDo` fail ("it gets a UTC stamp: not a stamp").
- AC 4 (the log line is redacted): mutation: dropping `Redact.Text` from the `LOGBEAT` error-status line made `Runs.TestBeatLogsAreRedacted` fail ("without the secret: ...").
- AC 4 (RunDue runs after an earlier step fails): mutation: a `Return $$$OK` in the Fixes catch of `Tick` made `Runs.TestBeatsRunWhateverEarlierStepsDo` fail ("RunDue is still called once").
- AC 5 (the BeatNow contract): mutation: `RequestedAt` as `%String(MAXLEN = 30)` in `Checks.Msg.BeatNow` made `Test.Checks.Beat.TestBeatNowContract` fail ("RequestedAt has MAXLEN '30', not '20'").
- QA runs, warm: `Test.Checks.Beat`, `Runs`, `Data.Tables` passed after the last revert. Added test time: under 1 s warm.

Code review additions (run tag `e39s1crw`, warm; each mutation applied, observed red, reverted byte-identical, green again):
- AC 3 (the stubs write no row): mutation: `Beat.RunNow` saving a `HeartbeatBeat` row for its `sessionRef` (status ignored) made `Test.Checks.Beat.TestStubsDoNothing` fail ("no HeartbeatBeat row is made for the fixture ref", "and the table holds as many rows as before"). Before the review patch the same mutation stayed green: the fixture ref was longer than `SessionRef`'s MAXLEN 22, and `Rows("")` bound "" as SQL NULL, so it always counted 0.
- AC 1 (the spine's names): mutation: deleting the AD-18 "Names" line made the loop above print `MISSING` for the `SetHeartbeat` (fields), `RunHeartbeat` (routing), `Msg.Enum` CHANNEL and `heartbeat.checklist` needles; the baseline spine misses all five needles; reverted byte-identical.
- AC 6 (the scoped paths are unchanged): mutation: a newline appended to `src/ocutalon/cls/OcuTalon/Live/Publish.cls` made the merge-base `git diff --exit-code` above exit 1; reverted byte-identical, exit 0.
- AC 7 (the UX texts are recorded): no mutation; a planning-time reading of EXPERIENCE.md, recorded pass, with no code or test to mutate.
- Runs after the patches, warm: `Test.Checks.Beat`, `Test.Checks.Runs`, `Test.Contract.Ac` passed.

Rework 1 (run tags `e39s1rw1`/`e39s1rw1w`; applied, observed red, reverted byte-identical):
- Smoke (no key-like literal in the story's files): mutation: writing `TestBeatLogsAreRedacted`'s fixture secret back as one literal made `bash docker/tests/test-boundaries.sh` print `FAIL keys: nothing key-like`; reverted, no FAIL.

**Shared surfaces:**
- `src/short-names.tsv`: +1 row, under test-storage.sh's registry rules.
- `Test.Data.Tables` Registry and Contracts: +1 each. The floors (`>= 23`, `>= 22`, `>= 45`) still hold.
- The requests `Checks.Process` accepts: +BeatNow; `TestUnknownRequest` is unchanged.
- `Test.Checks.Probe`: new properties; the `Order` shape is unchanged.
- Unchanged: the production item list (`test-production.sh`, `Production.cls`), `Live.Publish` TYPES (16), the `Live.Payload` classes (30 contracts) and `web/src/app/live/payloads.ts`.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.
- Added test time: about 2 s warm and about 3 s in `Checks.Heartbeat` (inference).

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** The heartbeat's names and contracts are in place and the Tick and `BeatNow` are wired as the spec lists them.
- `src/ocutalon/cls/OcuTalon/Data/HeartbeatBeat.cls` (new): AD-18's 15 fields, the unique `SessionRefIndex`, `DEFAULTGLOBAL ^OcuTalonP.HeartbeatBeat`, the storage block exported from slot D. `src/short-names.tsv` has its row.
- `src/ocutalon/cls/OcuTalon/Checks/Msg/BeatNow.cls` (new): `SessionRef` and `RequestedAt`, storage block committed.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` (new): do-nothing `RunDue`, `RunNow`, `Snapshot`, `Key`; the settings names, defaults and caps as parameters; `SettingKey`.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: `BeatNow` routed in `OnRequest`; `Tick` runs `BeatRunDue` last in a fourth Try/Catch (`LOGBEAT`); `BeatNow` logs `LOGBEATNOW` and answers OK; the two private seams.
- `ARCHITECTURE-SPINE.md`: the "Names" line in AD-18 and the defaults sentence in AD-19 (additive only). The "Names" line spells the five keys out in full, so that the spec's own grep for `heartbeat.checklist` passes.
- Tests: `Test/Checks/Probe.cls` (seam overrides), `Test/Checks/Runs.cls` (3 tests), `Test/Checks/Heartbeat.cls` (`TestBeatNowIsAnswered`), `Test/Checks/Beat.cls` (new, 3 tests), `Test/Data/Tables.cls` (contract and registry entry).

**Review.** 22 findings from three layers (the intent-alignment layer reported readings only): high 0, medium 2, low 18, false 2. Patches applied: the probe's `Order` read (low), the `RunNow` error-status test and the probe knob `BeatNowError` (medium), `TestStubsDoNothing` compared a never-used ref (low), the positive control and empty-response assertion in `TestBeatNowIsAnswered` (low). Deferred: none new (the two planned entries stay). Rejected, with reasons in the triage log: log leak of a Ref from a stub's error text, `SettingKey` validation, `Required`/`NextDueAt` index, more spine names, empty-SessionRef guard, seam wiring pin, grep needles and AC 6/7 mutation lines (spec-bound or no test to mutate), two false claims. Follow-up review recommended: false (one medium patched, test-only, mutation-verified).

**Decided in-stage.**
- Spine lint: `lint_spine.py` reports `"ok": false` for 8 low "unfilled template token" findings at lines 454, 1010, 1023, 1086 and 1091 (brace placeholders in the spine's own examples). The same 8 are in the baseline spine, and this story adds none. The Verification line "`"ok": true`" cannot be met without editing lines this story does not own, so the check was taken as "no new finding". The lead may want to clear those placeholders or relax the check.

**Verification.** The (loop) lines passed after the last patch: `Test.Checks.Beat`, `Runs`, `Data.Tables`, `Contract.Ac` (warm), `Test.Checks.Heartbeat` (fresh), `test-storage.sh`, the grep loop. The (once) lines passed: the scoped diff against `origin/feature/OCT_OcuTalon_MVP` is empty, all 28 hosted `checks` scripts (no FAIL line; parts took 1:51, 11:28 and 7:50), `shard lane-a@Checks` (6 classes, 137 s), `shard lane-b@Data` (12 classes, 151 s), `shard lane-b@Contract,Live` (7 classes, 139 s; `Test.Live.Payloads` unchanged). Warm stack down and tag teardown done. Slot D ran no test. The mutations (7 lines above) were applied, observed red and reverted byte-identical.

**Footprint extension (report):** `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` (one contract and one registry entry; not contended).

**Residual risks.** `RunDue` and `RunNow` are stubs, so the real `Process` to `Beat` wiring has no observable effect to assert on; Story 39.3 should pin it when it fills them. Test time added: about 2 s warm, about 3 s in `Checks.Heartbeat`; `shard lane-a@Checks` took 137 s fresh. The two deferred entries (`Live.Payload.Heartbeat`, and the UX text for the unavailable run button) are for the lead to harvest.

**Rework 1 (smoke).** `TestBeatLogsAreRedacted`'s fixture secret is built as `"sk-"_"ant-api03-..."` in `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` (assertions unchanged). `bash docker/tests/test-boundaries.sh` prints no FAIL (every file, so no other key-like literal remains); `OcuTalon.Test.Checks.Runs` passed on a warm stack. No review layers were run for this one-line test fixture change; follow-up review recommended: false (no patch at `high`). Warm stack and tags torn down.
