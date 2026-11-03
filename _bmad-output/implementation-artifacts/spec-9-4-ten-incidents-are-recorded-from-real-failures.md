---
title: 'Story 9.4: Ten incidents are recorded from real failures (part 1: the recorder, the demo incident and the replay test)'
type: 'feature'
created: '2026-10-28'
status: 'done'
baseline_revision: '2b7203dbc9a0c45abb9ba1e9644e4756d52e16b8'
baseline_commit: '2b7203dbc9a0c45abb9ba1e9644e4756d52e16b8'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The set holds one incident, `eval/orders-date-format/`, written by a test class's own snapshot code (Story 0.10). The product has no recorder, so an incident can't be captured the way the product reads it. Nothing proves that a recorded snapshot gives the diagnosis the same evidence pack as the live failures did.

**Approach:** This plan covers part 1 of a split (Design Notes, Decided in-stage 1). It adds:
- the recorder `OcuTalon.Eval.Record`. It captures an incident's failures from a production through `OcuTalon.Watch.Reader.Evidence`, passes the reader's answer through `OcuTalon.Bridge.Redact`, refuses a file with a local path or a non-ASCII character, and writes `snapshot.json` and `case.json` (with the expected cause category, element at fault and fix kind) to the case's folder;
- `OcuTalon.Test.Eval.Record`. It records the demo incident with the recorder from the Orders production in OCUORDERS after the partner sends 50 orders in MM/DD/YYYY. It proves that `EvidencePack.Build` gives a pack from the file just written that equals the pack from the live reader, and that the committed demo snapshot gives the same pack apart from row ids and times;
- the repository checks: every incident file is redacted, ASCII and free of credential settings, and the demo case is the one the demo incident gate runs.

The nine feed incidents (AC3 and its "And") move to a sibling story.

## Boundaries & Constraints

**Always:**
- **A recording is the reader's own answer.** `Eval.Record` writes what `Reader.Evidence` returned (format `ocutalon.readerSnapshot/1`), after `Bridge.Redact.Text`. It adds and drops nothing, and it never writes a pack.
- **Packs are compared only when the same `EvidencePack.Build` built both in the same run,** as `%ToJSON()` text. No pack is ever kept in a file.
  - The live pack is `Build` of the reader's answer before anything changes it.
  - The replay pack is `Build` of `EvidencePack.Load` of the written file. It must equal the live pack exactly.
  - The committed check removes only `VOLATILE` from both packs: `firstAt`, `lastAt`, `sample.headerId`, `sample.at`, and `headerId` and `timeCreated` of each `trace` entry.
- **`Eval.Record` refuses** with an error status that names the reason, and writes nothing, when:
  - the case is not valid (Matrix);
  - the reader's outcome is not `read`, or the answer holds no failure;
  - the redactor returns its `UNCHECKED` text;
  - the case or snapshot text holds a non-ASCII character;
  - it holds a local machine path, by the patterns of `test-boundaries.sh` `local_path`.
- **The expectation rules:**
  - `causeCategory` is one of `DiagnosisPayload.CAUSECATEGORIES`;
  - `elementAtFault` is not blank;
  - `fixKind` is not empty exactly when the category is `DiagnosisPayload.FIXCATEGORY`.
  - ObjectScript never names `FIXKINDS`, which Epic 7's branch deletes.
- **Failures are induced only in throwaways.** `Test.Eval.Record`:
  - fails every test with the reason where `/opt/ocutalon/eval/` is not mounted or Orders does not run in OCUORDERS;
  - holds the Orders WatchMark while it sends, and releases it afterwards;
  - deletes its messages and its folder.
- Every new file is ASCII, and comments state contracts (Rule 14).

**Never:**
- **Never edit these files:**
  - `eval/orders-date-format/*`, except a reverted mutation (Decided in-stage 2);
  - Epic 7's files: `Watch/*`, `Agent/Diagnosis.cls`, `Data/Incident.cls`, `Data/FailureGroup.cls`, `src/bridge/**`, `Fix/**`, `Test/Watch/**`;
  - Lane B classes (`Core/*`, `Msg/*`, Lane B `Data/*`, `Demo/*`) and `Test/Demo/*`;
  - `Production.cls`, `ci/units.sh`, `ci/iris.sh`, `ci/mock/**`, `.github/workflows/*`, `docker-compose.yml`, `ci/compose.ci.yml` and `docker/tests/lib-*.sh`;
  - any other `docker/tests/*.sh` except `test-eval-set.sh` and the header comment of `record-eval.sh`;
  - `Eval/In.cls`, `Eval/Sink.cls`, `Eval/Data/CaseResult.cls` and `eval/run.sh`.
- **Never write an `Incident` or `FailureGroup` row.** `IncidentManager` is their only writer (AD-15, AD-33).
- **Never build part 2:** no feed production, new namespace, grant, new `eval/` case, recording driver, or count, spread or held-out rule for incidents.
- **Never run tests, induce failures or start a production on slot B.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Demo capture | 50 failed headers at `OrdersFromPartner` (status 8) of one SuperSession in OCUORDERS; `Capture(case, "OCUORDERS", "OcuTalon.Demo.Orders.Production", "OrdersFromPartner", "h<id>,...", folder, .pack)` | `<folder>/orders-date-format/snapshot.json` holds the reader's answer, redacted: format, `source`, 50 failures with bodies and the transform's error, event-log rows, `items` = [OrdersFromPartner] with no credential setting, and a trace. `case.json` holds `{name, kind "incident", heldOut, description, snapshot "snapshot.json", expectation, recordedBy}`. `pack` is the live pack | — |
| Replay | The file just written | `Build(Load(file))` equals the live pack, exactly | — |
| Committed current | `eval/orders-date-format/snapshot.json`, and a fresh capture of its recipe | Both packs are equal once `VOLATILE` is removed | — |
| Sensitive value | A snapshot whose failure body holds `"Password": "zz-secret-1"` and whose error holds `token=zzsecret0123456789` | The file holds `[redacted]` and neither secret. Its replay pack equals `Build` of the raw snapshot | — |
| Local path | A body or error holding a home-folder path such as `/Users/<name>/x`, `/home/<name>/x` or `C:\Users\<name>` (`/home/irisowner/` is allowed; tests build such samples by concatenation, as `docker/tests/test-boundaries.sh` does, so no committed file holds a real-looking local path) | Refused: "a local machine path". Nothing written | error status |
| Not ASCII | A body value holding `$Char(233)` | Refused: "a character that is not ASCII". Nothing written | error status |
| Bad case | A name that is not lower-case kebab; an unknown `causeCategory`; a blank `elementAtFault`; a `fixKind` for a category with no fix, or none for `data_format_change` | Refused, naming the field. Nothing written | error status |
| Nothing to record | A production that is not the namespace's own (`not_current`), or keys that give no failure | Refused: "nothing to record: <outcome or no failure>". Nothing written | error status |
| No recipe | An incident case in `eval/` with no recipe in `Test.Eval.Record` (or a recipe with no case) | `TestCommittedIsCurrent` fails, naming it | — |
| Repository check | An incident snapshot with no failure, an empty `source` field, a credential-named setting or a non-ASCII byte; a `DEMOCASE` with no case or another expectation | `test-eval-set.sh` prints `FAIL cases` or `FAIL demo` with `file: rule` | — |

</intent-contract>

## Code Map

Line anchors are from HEAD `0259a1f`. Story 9.7 is implemented first and edits `Eval/Report.cls`, `Test/Eval/Cases.cls` and `test-eval-set.sh`, so find each anchor by its symbol.

**Read only, the evidence path:**
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`:
  - `:190` `Evidence(namespace, production, item, keys, Output snapshot) As %String` returns `read`, `unreadable` or `not_current`; any other fault throws.
    - Keys are `h<header id>` or `l<log id>`, comma-separated; failures come in key order.
    - `items` holds only the named item, read from the production definition's explicit settings (`:400`).
    - The trace is the first failure's session, `TOP TRACEMAX` (20).
    - Times are `YYYY-MM-DDThh:mm:ssZ`. The reader redacts nothing (`:35-36`).
  - `:157-164` `Readable`: the service user needs Read on the namespace's default global database resource. OCUORDERS has it (`Install/Step/Demo.cls` `WithOrdersData`).
  - `:56` `CREDENTIALPARTS` and `:218` `CredentialName(name)` (public).
- `src/ocutalon/cls/OcuTalon/Watch/EvidencePack.cls`:
  - `:24` `SNAPSHOTFORMAT`;
  - `:84` `Build(source, Output pack) As %Status`: an `Incident` (the live branch, `:104`, reads only the oldest key, `:110`) or a reader snapshot (`:119` `Recorded`);
  - `:145` `Detail` (sample = `failures[0]`, settings, trace);
  - `:238` `Load(file, Output snapshot) As %Status`.
  - Every string goes through `Redact.Text` (`:211-229`).
  - Epic 7's branch only adds `FromInput`/`ObjectEnd` (`git diff 855c37e OCT-epic7`), so `Build` is the same after the merge.
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls`:
  - `:43` `Text(text)`: JSON is parsed, sensitive keys are scrubbed at any depth, patterns are replaced, and the result is serialized compact;
  - it is idempotent; `:28` `UNCHECKED`; `:25` `REDACTED`.
  - Measured on slot B (`ocutalon-slot-b`, 154U, `OCUTALON`, read only): `Text` returns an excerpt in the demo snapshot's shape unchanged (failure fields, body, error sentence, item settings, trace).
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - `:16` `CAUSECATEGORIES`, `:19` `FIXKINDS` (Epic 7 deletes it), `:22` `FIXCATEGORY`;
  - `:69-78`: only `data_format_change` takes a fix kind.
- `docker/tests/test-boundaries.sh:32-37` `local_path`, the patterns to mirror; `:39-40` `key_like`. Both already scan `eval/**`.
- `src/ocutalon/cls/OcuTalon/Bridge/Ids.cls:7` `NewRef()` (in `src/bridge`): a SuperSession reference for a batch.

**Reuse, the Orders demo (Lane B test helpers, all public; the class asks every sender of failing Orders messages to use them):**
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls`:
  - `:386` `HoldFailures()` and `:394` `ReleaseFailures()`;
  - `:417` `AwaitPolls(polls)`;
  - `:463` `IncidentsSince(start)`;
  - `:582` `WaitCount(ref, item, status, count)` (60 s at most);
  - `:594` `Running()`;
  - `:602` `Send(count, dateFormat, ref, orderDate)` ("" when accepted);
  - `:632` `Headers(ref)` (`id`, `target`, `status`, ...).
  - Its own `Record`/`Snapshot` (`:548`, `:705`) are Story 0.10's recorder and are not used.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls:365` `RemoveMessages(superSessions, namespace)`.
- The pins on the committed demo files (why they stay byte-identical):
  - `Test/Watch/Evidence.cls:133` (Epic 7's) asserts `50|2026-10-20T10:37:45Z|2026-10-20T10:37:45Z`;
  - `Test/Demo/Production.cls:260-291` `TestSnapshotIsReadableAndCurrent` asserts `items.%Size() = 3` and compares `Projection` (`:502`) with a fresh `Snapshot()`;
  - `Test/Agent/Decide.cls:113` reads the file.

**Extend:**
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls`: `:37` `CASEKINDS` and `:53` `INCIDENTKIND`. Add `DEMOCASE` beside them.
- `src/ocutalon/cls/OcuTalon/Eval/In.cls:22` `FOLDER` (`/opt/ocutalon/eval/`) and `:97` `CaseNames(folder, names)` (name order). Read only.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`:
  - its helpers `Read` (`:302`), `Plain` (`:310`), `Hosts` (`:325`), `Folder` (`:355`) and `Names` (`:363`);
  - `TestCaseRecords` (`:234`) is the pattern for a per-case loop.
- `docker/tests/test-eval-set.sh`:
  - the header is `:9-41`, and the file variables are `:58-60`;
  - `enum_value` is `:63-65`;
  - `check-cases.mjs` starts at `:69`. Its constants are `:78-82`, and its incident branch is `:155-175`;
  - `check-set.mjs` is `:244-287`, the pattern for a new program;
  - the samples: `incident()` is `:330-333`, the good tree `:370-371` (`incident-good`'s snapshot is only `{format}`), the incident variants `:456-468`, and `setGood`/`setTree` `:381-397`;
  - `run_node` and `check_*` are `:561-569`;
  - `rule()` is `:664`;
  - the enumerations are `:706-736` (the self-checks use `enum.bad`/`enum.good`), and the rule list is `:738-743`.
- `docker/tests/record-eval.sh:10`: the header line "Story 9.4's Eval.Record replaces this script."

## Tasks & Acceptance

**Execution:**

**Task 0 (measurement, implement stage, on the warm stack).**
- **(a)** Compare the committed demo snapshot's pack with a fresh capture's.
  - List every field that differs outside `VOLATILE`. None is expected, because both hold the reader's field names, the definition's one setting, the same four body properties and one trace header `(inference)`.
  - If any field outside `VOLATILE` differs, HALT `blocked`, naming it. Never widen `VOLATILE`, and never re-record the demo file (Decided in-stage 2).
- **(b)** Show that both demo files are fixed points of `Redact.Text`. This is measured for an excerpt only, so it is confirmed by `TestIncidentFiles`. The same HALT applies if it fails.
- **(c)** Record how long `Test.Eval.Record`'s `OnBeforeAllTests` takes. It is part of the CI `shards` job's time.

1. **`src/ocutalon/cls/OcuTalon/Eval/Record.cls` (new; Lane A product code; no SQL, no production item).**
   - **Parameters:**
     - `RECORDEDBY = "OcuTalon.Eval.Record (Story 9.4)"`;
     - `NAMEPATTERN` (lower-case kebab);
     - `LOCALPATH`: the `local_path` patterns as one regex for `$Locate`. A backslash may be written once or doubled (JSON). `/home/irisowner/` is allowed (`(?!irisowner)`, measured on slot B);
     - the refusal texts.
   - **`Capture(case As %DynamicObject, namespace, production, item, keys, folder, Output pack As %DynamicObject) As %Status`:**
     - calls `Reader.Evidence`, and refuses unless the outcome is `read` with at least one failure;
     - sets `pack` from `EvidencePack.Build` of that answer, before any change;
     - then calls `Write`. On any error `pack` is "".
   - **`Write(case, snapshot As %DynamicObject, folder) As %Status`:**
     - Validates, in this order:
       - the case;
       - the snapshot's `format` (`SNAPSHOTFORMAT`) and its non-empty `failures`;
       - `Redact.Text(snapshot.%ToJSON())`, which must not be `UNCHECKED`;
       - the redacted text and the case text, which must be ASCII and hold no `LOCALPATH`.
     - Only then it creates `<folder>/<name>/` and writes:
       - `snapshot.json`, the redacted text;
       - `case.json`, `{name, kind: "incident", heldOut (boolean, default false), description, snapshot: "snapshot.json", expectation {causeCategory, elementAtFault, fixKind}, recordedBy: RECORDEDBY}`.
     - Each file is compact JSON followed by LF. An existing file is replaced.
   - **The class description** states the contract and that recordings are made in throwaways or on an author's instance, never by the product's flows.
   - **Why:** AC1 and AC2.
2. **`src/ocutalon/cls/OcuTalon/Eval/Report.cls` (extend).** Add `Parameter DEMOCASE = "orders-date-format";`, "the incident case that the demo incident gate runs (Story 9.5)", and one line of the class description. **Why:** AC2.
3. **`src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls` (new; lane-a shard, area Eval; throwaways and CI only).**
   - **Parameters:**
     - `RECIPES = "orders-date-format"`: the incident cases this class re-induces. The sibling adds its nine;
     - `VOLATILE` (Boundaries);
     - `TMP = "/tmp/zz-eval-record/"`.
   - **`OnBeforeAllTests`:**
     - sets `Missing` unless `Eval.In.#FOLDER` exists and `Test.Demo.Production.Running()`;
     - removes whatever a killed run left under `TMP` (the folder is this class's own);
     - holds with `HoldFailures()`;
     - notes the start (`Data.Time.NowUtc()`);
     - then, for each recipe:
       - `Induce(name, .namespace, .production, .item, .keys)`;
       - builds the live pack itself from `Reader.Evidence` and `Build`, independently of `Eval.Record`;
       - calls `Capture` into `TMP_<run>/`, with the case read from `eval/<name>/case.json` (name, heldOut, description, expectation);
       - keeps the live pack, the captured pack and the folder.
   - **`Induce("orders-date-format")`:**
     - `ref = Bridge.Ids.NewRef()`, kept in `Refs`;
     - `Send(50, "MM/DD/YYYY", ref, "2026-10-16") = ""`;
     - `WaitCount(ref, "OrdersFromPartner", 8, 50) = 50`;
     - the keys are `h<id>` of `Headers(ref)` with target `OrdersFromPartner` and status 8, in ascending id order;
     - the target is OCUORDERS, `OcuTalon.Demo.Orders.Production`, `OrdersFromPartner`.
     - An unknown name is an error.
   - **`OnAfterAllTests`:** `Test.Data.Fixture.RemoveMessages(Refs, "OCUORDERS")`, `ReleaseFailures()` when it held, and removes `TMP_<run>/`.
   - **Tests:**
     - **`TestCaptureWritesCase`** (AC1, AC2): the files of the Matrix's demo row, field by field. Also:
       - `case.json` equals the committed case except `recordedBy`;
       - the committed expectation is `data_format_change`/`OrderDate`/`repair_resend`;
       - `Report.#DEMOCASE` is `orders-date-format`;
       - both files are ASCII.
     - **`TestReplayEqualsLive`** (AC4, Integration): `Build(Load(written))` equals the live pack, and so does `Capture`'s pack.
     - **`TestCommittedIsCurrent`** (AC4):
       - the incident cases of `eval/` and `RECIPES` are the same set, in both directions;
       - for each, `Build(Load(eval/<name>/snapshot.json))` equals the live pack once `VOLATILE` is removed.
     - **`TestNoIncidentMade`** (hermeticity): `AwaitPolls(1) >= 1`, and `IncidentsSince(start) = 0`.
     - **`TestWriteRedacts`** (no production): the Matrix's sensitive row, on a synthetic snapshot.
     - **`TestWriteRefuses`** (no production): each local-path, non-ASCII and bad-case row. Each gives an error, and the case folder does not exist.
     - **`TestCaptureRefuses`:** production `Zz.NoProduction` (`not_current`), and keys "" (no failure). Each gives an error and writes nothing.
   - **Why:** AC1, AC2 and AC4.
4. **`src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` (extend; warm-safe).**
   - Add **`TestIncidentFiles`**. For every case of kind `incident` in `eval/`:
     - `case.json` and its snapshot are `Plain`;
     - each is a fixed point of `Redact.Text` (`Text(compact) = compact`, where compact is `%FromJSONFile(...).%ToJSON()`);
     - no `items[].settings` name is one that `Reader.CredentialName` flags;
     - no text matches `Eval.Record.#LOCALPATH`;
     - every host that `Hosts` finds is example.com or a `.example` host.
   - It asserts that at least one incident case was checked.
   - **Why:** AC1's "And".
5. **`docker/tests/test-eval-set.sh` (extend).**
   - **`enumerations`:**
     - also reads `DEMOCASE` (`REPORT_FILE`) and `CREDENTIALPARTS` (a new `READER_FILE`);
     - when `FIXKINDS` is absent, it takes the `Parameter NAME = "..."` values of `src/ocutalon/cls/OcuTalon/Fix/Kind/*.cls` (Decided in-stage 7), with a self-check on temporary files, like `enum.good`;
     - updates the missing messages.
   - **`cases`, for an incident snapshot:**
     - `source.namespace`, `source.production` and `source.item` are not empty;
     - `failures` is a non-empty array, each element with a non-empty `targetConfigName` and `error`;
     - no `items[].settings` name holds a `CREDENTIALPARTS` word (any case);
     - `case.json` and the snapshot are ASCII.
     - `incident-good`'s snapshot gains `source`, one failure and `items`.
     - New variants: `bad-snapshot-no-failure`, `bad-snapshot-no-source`, `bad-snapshot-credential-setting` and `bad-snapshot-not-ascii`.
   - **The new rule `demo`**, a new program `check-demo.mjs` on the `set` pattern:
     - `eval/<DEMOCASE>/case.json` exists;
     - it is of kind `incident`;
     - its expectation is exactly `data_format_change`, `OrderDate` and `repair_resend`.
     - It has a good tree and the variants `bad-demo-missing`, `bad-demo-element` and `bad-demo-kind`.
   - **The header** documents both rules.
   - **Why:** AC1's "And", and AC2.
6. **`docker/tests/record-eval.sh` (header comment only).** Replace the claim "Story 9.4's Eval.Record replaces this script." with this contract:
   - `OcuTalon.Eval.Record` records the other incidents;
   - this script stays the recorder of `eval/orders-date-format/snapshot.json` while `Test.Watch.Evidence` and `Test.Demo.Production` pin that recording;
   - `Test.Eval.Record` compares its pack with a fresh recording on every CI run.

   The path is in `NOT_IRIS_INPUT_PATTERN`, so no CI group runs for it. **Why:** Rule 14.

**Acceptance Criteria:**
- **AC1, the recorder.** Given the Orders production in OCUORDERS of a throwaway with a batch's 50 failures, when `Eval.Record.Capture` captures them into a folder, then:
  - the case's folder holds `snapshot.json`: the reader's answer, redacted (the failed headers and bodies, their errors, the event-log entries, the item's settings with no credential-type setting, and a trace excerpt);
  - it holds `case.json`, with the expected cause category, element at fault and fix kind;
  - a case or snapshot it may not write is refused with the reason, and nothing is written.

  Tests: `Test.Eval.Record` `TestCaptureWritesCase`, `TestWriteRedacts`, `TestWriteRefuses` and `TestCaptureRefuses`.
- **AC1 "And", redaction and public text.** Given `eval/`, when `Test.Eval.Cases`, `test-eval-set.sh` and `test-boundaries.sh` run, then every incident case's files:
  - are ASCII;
  - are fixed points of `Bridge.Redact.Text`;
  - hold no credential-named setting, no host other than example ones, and no local path or key.

  Tests: `TestIncidentFiles`, `test-eval-set.sh` `cases` and `test-boundaries.sh`.
- **AC2, the demo incident.** Given the demo incident, when `Test.Eval.Record` records it with `Eval.Record` from the Orders production in OCUORDERS after the partner sends 50 orders in MM/DD/YYYY, then:
  - its case record is the committed one, except `recordedBy`;
  - its expectation is `data_format_change`, `OrderDate` and `repair_resend`;
  - `Eval.Report.DEMOCASE`, the case the demo incident gate runs, names it.

  Tests: `TestCaptureWritesCase` and `test-eval-set.sh` `demo`.
- **AC4, the replay.** Given a recorded snapshot, when `EvidencePack.Build` reads it in a replay, then the pack equals the one built from the live reader when the incident was recorded:
  - exactly, for the file just written;
  - apart from `VOLATILE`, for every committed incident snapshot, which its recipe re-induces in the same run;
  - and an incident case with no recipe fails the test.

  Tests: `TestReplayEqualsLive` and `TestCommittedIsCurrent`.
- **Integration (Rule 1).** Given a case written by `Eval.Record`, when the product's pack builder (`EvidencePack.Load` and `Build`, as `IncidentManager` uses it) reads the file, then it produces the live pack. Test: `TestReplayEqualsLive`, on a real throwaway.
- **Hermeticity.** Given a fresh throwaway, when `Test.Eval.Record` and `Test.Eval.Cases` run forward and in reverse, then:
  - each passes;
  - no Orders incident is made;
  - no OCUORDERS message of its batch is left, and its folder under `/tmp/zz-eval-record/` is removed;
  - `Test.Demo.Production` and `Test.Watch.Evidence` still pass afterwards on the same stack.

### Review Findings

Code review 2026-10-29 (bmad-code-review, review_mode full; layers blind-hunter BH, edge-case-hunter EC, verification-gap VG, acceptance-auditor AA, all on the full tier). 28 findings: 13 survive triage as 7 entries (high 0, medium 2, low 5), 15 are rejected. Each line: severity, fix-risk, footprint, spec-status, disposition.
Rule checks: Rule 6, every AC against AD-22, AD-15, AD-6, AD-29, AD-33 and AD-16, with no mismatch (`Eval.Record` writes no row, the recordings run only in throwaways, and no ObjectScript names `FIXKINDS`); Rule 1, the Integration AC is pinned by `TestReplayEqualsLive` on a real throwaway; Rule 3, a non-user-facing author tool, and in any case it is exercised by real `Capture` calls against the Orders production with produced-file assertions; Rule 5, no NFR is worked around; Rule 2, the one unstated copy is DW-385 below (the `LOCALPATH` regex is a cross-language mirror that the spec names, with `test-boundaries.sh` kept as the authority, so it is not a helper copy); Rule 14, the changed sources are ASCII.

- [x] [Review][Patch] The clean-up hides its own failures: `Clean` drops the statuses of `ReleaseFailures` and `RemoveMessages`, `OnAfterAllTests` drops the status of `FixtureSettings(0)` and always returns `$$$OK`, so `TestCleanRemovesBatch`'s `AssertStatusOK(closing.OnAfterAllTests())` cannot fail; and the mark is released only after the messages are removed, so a throw there leaves the WatchMark held for 600 s (BH1+VG3+EC2) [src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls:116] -- medium; fix-risk low (test class only; release-before-delete is what `ReleaseFailures` documents as safe once the batches are complete); in-story; clear; patch now.
- [x] [Review][Patch] `TestCaptureDropsCredentialSettings` clears `SettingsAdded` before its restore has succeeded, so `OnAfterAllTests`' restore never retries a failed one, and no test runs that backstop (VG1+EC3) [src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls:566] -- low; fix-risk low (two lines and one pin in `TestCleanRemovesBatch`); in-story; clear; patch now (mechanical, Rule 15 two-way door). Verified as the lead asked: the restore is complete for the current definition (all five names out, nothing else touched, the running production untouched) and also runs after a failed assertion or an error inside the test's `Try`; only a failed restore itself was not retried.
- [x] [Review][Patch] The restore check "the definition holds the settings it held before" has no `mutation:` line (VG2a) [src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls:568] -- low; fix-risk low; in-story; clear; Rule 19: close in this pass (mutation line under `## Verification`).
- [x] [Review][Patch] `Eval.Record`'s class description says "Both refuse ... when the reader's outcome is not read" (only `Capture` reads), leaves out the refusals of Decided in-stage 13 and the blank folder, and its validity parenthetical reads as the refusal; `Capture`'s doc says "nothing is written" on any error, which holds for a refusal, not for an I/O error after the first file (BH8+AA1+EC7) [src/ocutalon/cls/OcuTalon/Eval/Record.cls:10] -- low; fix-risk low (comments only); in-story; clear; patch now (Rule 14).
- [x] [Review][Patch] `Test.Eval.Record`'s class description puts `TestCaptureRefuses` among the tests "on synthetic snapshots", but it calls `Capture` against the Orders production (AA2) [src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls:14] -- low; fix-risk low (comment); in-story; clear; patch now (Rule 14).
- [x] [Review][Patch] `record-eval.sh`'s header names only `TestSnapshotIsReadableAndCurrent` as the reason to rerun it, though `Test.Eval.Record` `TestCommittedIsCurrent` now catches the same drift (BH6, part a) [docker/tests/record-eval.sh:9] -- low; fix-risk low (header comment, in the story's footprint); in-story; clear; patch now.
- [x] [Review][Defer] `FixtureSettings` and `DefinedSettings` (QA) are near-copies of Epic 7's private `Test.Watch.Evidence` helpers of the same names (BH3+AA3) [src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls:683] -- deferred: medium (Rule 2); fix-risk low; out-of-footprint (the sibling is `Private` in `Test/Watch/Evidence.cls`, Epic 7's read-only file, so extending it is not open to this story: that is the copy's reason); routed as DW-385, owner 9-6 (the first story of this epic after Epic 7's merge), to make the Orders-definition fixture one public helper that both classes call.

**Applied** (all six patches, with option 1 of the patch menu):
- `Test/Eval/Record.cls`: `Clean` returns a status (it releases the mark first, then deletes the folder and the messages) and `OnAfterAllTests` returns it together with its restore's status; `SettingsAdded` is cleared only after a restore that succeeded, in `TestCaptureDropsCredentialSettings` and in `OnAfterAllTests`; `TestCleanRemovesBatch` also puts the fixture settings in and has the closing instance take them out (its own `SettingsAdded` covers a failure halfway); the class description and the `SettingsAdded`, `OnAfterAllTests` and `Clean` doc comments say so.
- `Eval/Record.cls`: the class description lists `Write`'s refusals and `Capture`'s own, and `Capture`'s doc says that nothing is written when it refuses (comments only).
- `docker/tests/record-eval.sh`: the header's rerun sentence also names `Test.Eval.Record` `TestCommittedIsCurrent` (header comment only).
- Run evidence (lane B; tags `e9s4cw` warm and `e9s4c` fresh): warm, `Test.Eval.Record` passed after the patches (14.2 s), each of the three mutations under `## Verification` went red and was green again after its revert, then `Test.Demo.Production` (34.8 s), `Test.Watch.Evidence` (2.4 s) and `Test.Eval.Cases` (4.4 s) passed on the same stack; fresh, `Test.Eval.Record` passed (14.2 s, ready after 82 s), `lane-a` part 5/8 passed forward (10 classes, every `Test.Eval` class among them, ready after 91 s) and part 4/8 passed reversed (10 classes, every `Test.Eval` class among them); `bash ci/checks.sh` passed (exit 0), `test-boundaries.sh` included. Both stacks are torn down and the lane-b lock folder is empty. Slot B was not used.

**Rejected** (verdict and reason, one line each):
- BH2 / AA4 / VG (killed run): the saved Orders definition is not on `Shared surfaces:`, and a killed run's fixture settings are not cleaned by `OnBeforeAllTests` -- low: the list is a spec edit (for the lead: QA's test adds the saved Orders definition to the shared surfaces, already shared with `Test.Watch.Evidence`); a killed run is not an everyday event, its leftovers fail loudly (`TestCommittedIsCurrent`, the restore check) and the next run removes them; a cleaner adds a guard.
- BH4 / EC8: the spec's counts are stale after QA (seven tests, 19 mutations, the follow-up note, the slot-B list, Decided in-stage 18's reason) -- low: a spec edit, in `## Auto Run Result`, build-auto's section.
- BH5: AD-22's as-built line still forecasts that `Eval.Record` replaces `record-eval.sh` -- the lead's ruling: no spine edit in this story (left for an attended update).
- BH6, parts b and c: the header does not warn that a rerun changes the pinned times, and "records the other incidents" is still future work -- (b) covered by the header's sentence that `Test.Watch.Evidence` and `Test.Demo.Production` pin the recording; (c) spec-bound, Task 6's text.
- BH7: `Write` refuses local paths but not the `key_like` shapes that `Redact.Text` does not replace (`dop_v1_` tokens, PEM private-key headers) -- low: no recording source of this release can hold them (the demo and 9.9's own test feed); `test-boundaries.sh` `key_like` still fails such a file; a new refusal adds a guard. It becomes real when a recording is made from a real production (FR-62, Story 17.7), whose author should then mirror `key_like` as `LOCALPATH` mirrors `local_path`.
- EC1: `Make`'s read and `Capture`'s read may differ -- false: `Ens.Actor` logs the error (`irislib/Ens/Actor.cls:482`) before it sets the Error status (`:483`) that `WaitCount` waits for, `AlertOnError` is off, and the partner sends asynchronously (no response header), so both reads see the same rows.
- EC4: keys of another item's headers are accepted -- low, spec-bound: the spec's refusals are the outcome and at least one failure; the keys are the author's.
- EC5: a relative folder is written below the process's directory -- low: the only callers pass `/tmp/...`; a check adds a guard.
- EC6: `check-cases.mjs` skips the credential rule when `items` is not an array or a `settings` is not an object -- low: the IRIS-side `CaseProblems` throws on such a file and flags it ("could not be read").
- EC9: the header's "on every CI run" is not true when `ci/changes.sh` skips the shards group -- false: every input of the comparison (`src/`, `eval/`, the image) is a declared input of that group, so a run that skips it has nothing that could change its result.
- VG2b: `DefinedSettings` compares names only, and a pre-existing setting with a fixture name would be lost -- low, theoretical: `OrdersFromPartner` holds only `TargetConfigName`, which `Test.Demo.Production` pins; real if the Orders item ever gains a setting with one of the five fixture names.
- VG4: `Capture` returning `pack = ""` when `Write` refuses is untested -- false: the layer's demonstration (swap `Write` and `Set pack = built`) still returns `""`, because the `Catch` resets `pack`.
- VG (shared surfaces): the same spec edit as BH2.

## Spec Change Log

## Review Triage Log

### 2026-10-29 -- Review pass
- verdicts: 39 findings -- high 0, medium 2, low 25, false 12, maybe-false 0
- findings (layers in order: blind-hunter BH, edge-case-hunter EC, verification-gap VG, intent-alignment IA):
  - `[low]` `[reject]` BH1 `fixKind` is not checked against the fix kinds in `CaseRecord` -- spec-bound: Design Notes 6 keeps `FIXKINDS` out of ObjectScript (Epic 7 deletes it) and says the repository check names the fix kind; `cases` flags `bad-fixkind`. The fix would name `FIXKINDS`.
  - `[low]` `[reject]` BH2 `Write` checks less than CI (case.json not run through `Redact.Text`; no host or credential-name check) -- the spec lists exactly the checks of `Write`; the text of case.json is the author's own, and `TestIncidentFiles` and the `cases` rule catch the rest; a guard plus test is more than a direct correction for an unlikely case.
  - `[low]` `[reject]` BH3 file replacement is not atomic, and a name can overwrite another kind's folder -- spec: "An existing file is replaced"; an author tool run in a throwaway; the fix adds temp files, renames and a kind check.
  - `[false]` `[reject]` BH4 a missing `heldOut` becomes false -- the spec says `heldOut (boolean, default false)`.
  - `[false]` `[reject]` BH5 tests that need no production sit behind `Guard()` -- the spec says `Test.Eval.Record` "fails every test with the reason" where eval/ is not mounted or Orders does not run.
  - `[false]` `[reject]` BH6 `OnBeforeAllTests` wipes the shared `TMP` -- Task 3 says it removes what a killed run left under `TMP`, "the folder is this class's own"; a throwaway runs one class at a time.
  - `[low]` `[reject]` BH7 `TestIncidentFiles` reads the snapshot unguarded -- a malformed committed snapshot makes the method error (loudly, red) after its own assertion failed; `cases` flags the file first; the fix adds guards.
  - `[low]` `[reject]` BH8 the host rule only sees hosts after `@` or `://`, and flags `partner.example.com` -- Task 4 defines the rule as "every host that `Hosts` finds" (Decided in-stage 12, the rule of 9.3's item cases); the one committed incident has no host-shaped value; the sibling story (9.9) decides how bare hosts of its feed's settings are treated. Grouped with EC11 and VG2 (shared root cause).
  - `[false]` `[reject]` BH9 the `Fix/Kind/` fallback is speculative -- Task 5 and Decided in-stage 7 require it, with a self-check on temporary files.
  - `[low]` `[reject]` BH10 `LOCALPATH` is a hand copy with no sync check, and `/home/irisownerX` passes -- the shell scan has the same prefix exemption (`grep -v '/home/irisowner'`); the spec says "by the patterns of `test-boundaries.sh` `local_path`".
  - `[low]` `[reject]` EC1 same as BH1.
  - `[low]` `[reject]` EC2 `Write` accepts a snapshot with no `source`, empty strings or failures without `targetConfigName`/`error` -- the reader always sets them; the spec lists `Write`'s checks (format and non-empty failures); the `cases` rule flags the file.
  - `[low]` `[reject]` EC3 `Write` accepts credential-named settings -- `Reader.Evidence` drops them; `Redact.Text` replaces the value of a sensitive key; the name is flagged by `TestIncidentFiles` and the `cases` rule.
  - `[low]` `[reject]` EC4 keys that give only some failures are accepted -- the spec requires at least one failure; `Reader.Evidence` is the product's reader.
  - `[low]` `[reject]` EC5 same as BH3 (non-atomic replace).
  - `[low]` `[reject]` EC6 same as BH3 (name collision).
  - `[low]` `[reject]` EC7 same as BH10.
  - `[low]` `[reject]` EC8 a Windows path with doubled backslashes in the source text escapes `LOCALPATH` -- the spec accepts a backslash "once or doubled"; a doubled backslash in raw text is not a path the project's logs hold.
  - `[low]` `[reject]` EC9 same as BH7.
  - `[low]` `[reject]` EC10 a host followed by sentence punctuation is flagged with a trailing dot -- a loud false positive naming the host; `TestCaseRecords` (9.3) compares the same way.
  - `[low]` `[reject]` EC11 same as BH8 (bare hosts and IPs).
  - `[low]` `[reject]` EC12 the snapshot's ASCII check runs only once the format is right -- a snapshot of another violation is reported for that violation first and for ASCII on the re-run.
  - `[medium]` `[patch]` VG1 the Hermeticity criterion has no pinning test for the clean-up (messages, folder, hold) and no mutation line -- real: no assertion could fail if `OnAfterAllTests` leaked 50 failed headers or lost the hold. Patched: `Clean` is a class method that `OnAfterAllTests` calls, `TestCleanRemovesBatch` runs it on a batch of one order, `OnBeforeAllTests` records `HoldChecked` and `TestNoIncidentMade` asserts it; four mutation lines.
  - `[low]` `[reject]` VG2 same as BH8.
  - `[medium]` `[patch]` VG3 nothing pins that `snapshot.json` is the reader's whole answer (the pack never reads the event log or most failure fields) -- real: a `Write` that dropped an event-log row passed every test. Patched: `Make` keeps the reader's answer and `TestCaptureWritesCase` asserts the file equals `Redact.Text` of it plus a line feed; mutation line.
  - `[low]` `[reject]` VG4 `TestIncidentFiles`' ASCII, host, path and credential-name assertions have no mutation line -- Rule 19 asks one demonstrated mutation per AC; AC1 "And" has two (fixed point, credential rule).
  - `[low]` `[reject]` VG5 the "no credential-type setting" assertion of `TestCaptureWritesCase` holds for any reader on the Orders item (its only setting is `TargetConfigName`) -- it asserts the Matrix row's stated outcome; the reader's removal of credential settings is pinned by `Test.Watch.Evidence` `TestReaderDropsCredentialSettings`.
  - `[low]` `[reject]` VG6 `$IsObject(live.settings)` passes for `{}` -- the settings of the Orders item are not empty and `TestCommittedIsCurrent` compares them; VG itself calls it not a live problem.
  - `[low]` `[reject]` VG7 same as BH1.
  - `[false]` `[reject]` VG8 same as BH9.
  - `[false]` `[reject]` IA1 capture and replay are only verified in a throwaway stack -- by design (Rule 21, AD-22: failures are induced only in throwaways, never on a slot).
  - `[false]` `[reject]` IA2 the synthetic tests share the real-stack guard -- same as BH5.
  - `[false]` `[reject]` IA3 `TestIncidentFiles` can pass with no assertion when there are no case names -- `Names` asserts "eval/ holds case folders" before it returns "", so the class fails; the "redacted" check is on the IRIS side by Task 4.
  - `[false]` `[reject]` IA4 the committed snapshot differs from a fresh capture at file level -- Task 0 (a) compares packs; the measured differences are outside neither the pack nor `VOLATILE`; Decided in-stage 2.
  - `[false]` `[reject]` IA5 the committed check compares with the live pack, not the replay pack -- the Matrix row "Committed current" says the live pack; `TestReplayEqualsLive` ties the replay pack to it.
  - `[false]` `[reject]` IA6 `DEMOCASE` has no consumer here and the `demo` rule is stricter than the Matrix -- the consumer is Story 9.5; Task 5 says the expectation is "exactly" the three values.
  - `[low]` `[patch]` IA7 the redactor's `UNCHECKED` refusal has no test (and the empty-keys refusal was unconfirmed) -- real: the refusal is listed in Boundaries and no test fails without it; the empty-keys refusal passed in every run. Patched: a body nested deeper than `Redact.MAXDEPTH` in `TestWriteRefuses`; mutation line.
  - `[false]` `[reject]` IA8 the fix-kind enumeration reads `FIXKINDS` here and `Fix/Kind/` only after Epic 7 -- Decided in-stage 7; the fallback has its self-check.
  - `[low]` `[reject]` IA9 the path patterns are a port, not shared code -- same as BH10; the spec chose "mirror the patterns".

## Design Notes

**Architecture decisions (Rule 6):**

| AD | What it governs here |
|---|---|
| AD-22 | The set's recorded reader snapshots. Recording happens in throwaways only (the slot never). The comparison with a fresh recording runs on every CI run, and `eval/` is mounted read-only. Lane A's `Eval.*` |
| AD-15 | `EvidencePack.Build` builds one pack from the live reader or a recorded snapshot, and `Reader.Evidence` is the reader. Credential-type settings are removed, and the strings are redacted |
| AD-6 | The pack is the diagnosis input, and `EvidencePack` writes nothing. `Eval.Record` is not a tool method and runs outside AI Hub's callbacks |
| AD-29, AD-33 | Lane A files only. No new item, table or event type, so the ownership tables don't change. No `Incident`/`FailureGroup` writes |
| AD-16 | Only `data_format_change` takes a fix kind (`repair_resend`) |
| NFR-11, CON-5 | No key, credential, local path or personal data in a recorded file |

No AC of this part contradicts an AD.

**Decided in-stage:**
1. **The split, proposed under the lead's instruction.** One pass can't carry the recorder, the feed production, nine recordings, the checks and the replay. The feed alone has open platform questions (below).
   - **This part keeps:**
     - AC1 and its "And" (the recorder, redaction and public text);
     - AC2 (the demo incident);
     - AC4 (the replay).
   - **Moved verbatim to a sibling planned next in this epic** (proposed: Story 9.9, "The other nine incidents come from real failures in a test feed", before 9.5):
     - "**Given** the other incidents, at least nine **When** they are recorded **Then** each comes from a real failure induced in a test feed production, `OcuTalon.Test.Eval.Feed`, that only the throwaway test stack installs and the judges' compose file never contains, and no cause category accounts for more than 8 of the first 10 incidents, so a diagnosis that always gives the same answer can't reach SM-2, AD-22's evaluation-set rule (FR-62, CON-3, AD-22)";
     - its "**And** at least two of them are marked as held out from prompt work (FR-62)".
   - **AC4 and AC1's "And" still reach the sibling's recordings.** `TestCommittedIsCurrent` fails an incident case that has no recipe, and `TestIncidentFiles` and the `cases` rule check every incident file.
   - **Release:** nothing leaves release 1.0.0. Moving an AC to a not-yet-planned story is a veto-window item, which the lead records. 9.5's dependencies gain the sibling.
   - **The sibling's open questions, found in this investigation:**
     - (a) One production per namespace (`irislib/Ens/Director.cls:39-41`). OCUTALON runs `OcuTalon.Production` and OCUORDERS runs Orders. So the feed needs its own namespace, created in the throwaway by test code (no precedent; `Install/Step/Demo.cls` `System(1)` at `:279`, `:282` and `:301` is the pattern), or it takes Orders' place for a while (the `Test.Watch.Case` stop/start pattern, `:863-879`).
     - (b) `Reader.Evidence` returns `unreadable` unless the service user holds Read on the namespace's data-database resource (`Reader.cls:157-164`). A new namespace needs a grant to the service role in the throwaway, like `WithOrdersData`. That is a veto-window item (privileges).
     - (c) Only `data_format_change` takes a fix kind, so every other incident records `fixKind` "". `setting_change` incidents need step 5's setting-change history (AD-15 S15; FR-62 "from step 5"; Story 17.7), so none fits yet.
     - (d) Fast failures. HTTP 503 and connect errors retry until `FailureTimeout` (`irislib/EnsLib/HTTP/OutboundAdapter.cls:552`, `:576`; `irislib/Ens/BusinessOperation.cls:51`, `:61`), so a feed operation sets a small `FailureTimeout` and `RetryInterval`.
     - (e) The judges' image compiles every `OcuTalon.Test.*` class (`src/module.xml` `OcuTalon.PKG`; the Dockerfile copies `src/`). So "never contains" means:
       - no compose reference;
       - no `Production.cls` item;
       - no install step names it;
       - no namespace outside a throwaway.
       - `test-compose-file.sh` is not Epic 9's to edit, so the static checks go into `test-eval-set.sh`.
     - (f) "The first 10" is name order: `Report` reads `ORDER BY CaseName`, and `In.CaseNames` lists folders in name order.
     - (g) A recording driver: `eval/` is read-only in throwaways, so the files are copied out (`dc cp` or `exec cat`, then `jq .`). Either `record-eval.sh` gains a mode for the feed's cases (it is in `NOT_IRIS_INPUT_PATTERN`, `ci/units.sh:79`, and `test-ci-changes.sh:248`), or a new script needs its own `NOT_IRIS_INPUT_PATTERN` entry.
     - (h) CI time: `Test.Eval` runs in `lane-a`, in the `shards` job (26 min 23 s on `98f69be`; REL-4 35 min).
     - (i) The mock's default diagnosis answers `data_format_change`/`OrderDate` (`ci/mock/scenarios/A/diagnosis.json`). That matters to 9.6's mock scores, not here.
2. **The demo files stay Story 0.10's recording, byte-identical.**
   - Re-recording would change the file's times and item list, which other tests pin:
     - `Test.Watch.Evidence:133` (Epic 7's file) pins the times;
     - `Test.Demo.Production`'s `TestSnapshotIsReadableAndCurrent` pins `items` = 3 and its `Projection`.
   - No AC needs a re-recording:
     - AC2's recording happens in the test run;
     - AC4's committed check proves that the committed file still gives the live pack, apart from `VOLATILE`.
   - So `record-eval.sh` stays its recorder, and its header is corrected (Task 6). If Task 0 (a) or (b) finds a real difference, the stage HALTs. It never edits the file around the pins.
3. **The live pack** is `Build` of `Reader.Evidence`'s answer for the same keys. The test builds it itself, independently of `Eval.Record`, before redaction. That is the reader `EvidencePack.Build` reads (AD-15).
   - It is not `Build(incident)`. That branch needs an `Incident` and a `FailureGroup` row, which only `IncidentManager` writes (AD-15, AD-33) and which Epic 7 is rewriting.
   - That branch reads the oldest key through the same `Reader.Evidence` (`EvidencePack.cls:110`). The equal shape of its pack is `Test.Watch.Evidence.TestLivePack`'s.
   - Both packs come from the same `Build` in the same run, so Epic 7's merge can't make the test stale (the lead's instruction).
4. **`VOLATILE`** is the list of pack fields that a re-induced incident cannot repeat: row ids and times. The strict comparison masks nothing.
5. **Refuse, don't strip.**
   - A local path or a non-ASCII character fails the capture with the reason, and the author fixes the case.
   - The redactor's replacements (keys, tokens, sensitive-key values) are kept. `Build` redacts the same values in the live pack (`Clean`/`Cleaned`), and `TestWriteRedacts` proves the packs equal.
6. **The expectation rules** use `CAUSECATEGORIES` and `FIXCATEGORY`, which Epic 7 keeps. They never use `FIXKINDS`: Epic 7 deletes it, and a compile-time `#FIXKINDS` would break the class after the merge. The fix kind's name is checked by the repository check.
7. **The `FIXKINDS` fallback in `test-eval-set.sh`.** Epic 7's branch deletes `FIXKINDS` and adds `Fix/Kind/RepairResend.cls` (`NAME = "repair_resend"`).
   - Without the fallback, `enumerations` fails after the merge ("FIXKINDS is missing") and the script exits.
   - The fallback reads `Fix/Kind/*.cls` only when `FIXKINDS` is absent, so today's result is unchanged. It is a small change in a file this story extends anyway.
8. **`DEMOCASE` lives on `Eval.Report`.** 9.5 extends `Report` with the gate, so it and the checks read this one name.
9. **Compact JSON.** `Eval.Record` writes `%ToJSON()` text followed by LF. The sibling's driver formats committed recordings with `jq .`, as `record-eval.sh` did. `recordedBy` is always `RECORDEDBY`.
10. **The capture folder** is `/tmp/zz-eval-record/<run>/` in the container, because `eval/` is mounted read-only. The run is the test's own Ref.
11. **Recipes.** The `RECIPES` parameter and the `Induce` dispatch in `Test.Eval.Record` hold how each committed incident is re-induced. The sibling adds one recipe per case.
12. **Hosts in incident files** follow 9.3's rule for item cases (example.com or `.example`, `Hosts`). The sibling may allow a local partner endpoint, if a feed error names one.
13. **Extra refusals in `Write`.** A blank `description`, a `heldOut` that is not a boolean and a `fixKind` that is not a string are refused too, naming the field. The `cases` rule fails on a case that has them, so the recorder never writes one. `Capture` checks the case before it reads the production.
14. **`Test.Eval.Cases.Read` and `Plain` are public** (they were private), so `Test.Eval.Record` reuses them instead of copying them. No behaviour changed.
15. **`test-eval-set.sh` extras.** `fix_kinds_of <class file> <folder>` is the one function that reads the fix kinds (`FIXKINDS`, else the `NAME` of each class of the folder); the real read and the self-check use it, so removing the fallback fails the self-check. The `demo` rule also has the variants `bad-demo-category`, `bad-demo-fixkind` and `bad-demo-extra-field`, and `cases` also has `bad-snapshot-failures-text`, `bad-snapshot-failure-no-error`, `bad-snapshot-failure-no-target`, `bad-snapshot-no-source-object`, `bad-snapshot-credential-setting-case` and `bad-incident-case-not-ascii`.
16. **Compile check on slot B.** Slot B lacked Story 9.7's `Eval/Msg/TurnResult.cls`, which `Report.cls` needs. That committed class was loaded and compiled there, with `Eval/Record.cls`, `Eval/Report.cls`, `Test/Eval/Record.cls` and `Test/Eval/Cases.cls`. No test or production ran on the slot; the regex parameters were evaluated there with `Write` only.
17. **Reverse run.** `--reverse` reverses the whole class list before it takes a part, so part 5/8 reversed holds no `Test.Eval` class; part 4/8 reversed holds all nine. Both ran.
18. **Clean-up and hold pins (review pass).** `Test.Eval.Record.Clean(refs, folder, held)` is the clean-up that `OnAfterAllTests` runs, as a class method so that `TestCleanRemovesBatch` can run it on a batch of one order of its own (that test holds the failures again afterwards, and also keeps its reference in `Refs`). `OnBeforeAllTests` records `HoldChecked` (the mark is more than 300 s ahead right after the hold, before the first order is sent), because another test's re-hold would hide a missing hold from a check made later. `Make` keeps the reader's answer in `Recorded` so that `TestCaptureWritesCase` can compare `snapshot.json` with `Redact.Text` of it. `TestWriteRefuses` also refuses a body nested deeper than `Redact.MAXDEPTH` (the redactor's `UNCHECKED`). The class takes about 5 s longer (14 to 15 s).

**Task 0 results (warm and fresh stacks of the implement stage):**
- **(a)** The committed demo snapshot's pack and a fresh capture's pack are equal once `VOLATILE` is removed (`TestCommittedIsCurrent` passed). With `VOLATILE` emptied for one measurement, the differing fields were exactly `firstAt`, `lastAt`, `sample.headerId` (the JSON type differs), `sample.at`, `trace[0].headerId` and `trace[0].timeCreated`: nothing outside `VOLATILE`. No HALT.
- **(b)** Both demo files are plain ASCII, fixed points of `Redact.Text`, hold no local path and no host, and the item has no credential setting (`TestIncidentFiles` passed on the warm and fresh stacks, forward and reversed). No HALT.
- **(c)** `Test.Eval.Record` takes 8.4 to 11.7 s as a class (warm), 11.1 s as a class on a fresh stack and 10.3 s and 10.6 s inside the shard, forward and reversed. Almost all of it is `OnBeforeAllTests` (50 orders sent and failed, one live read, one capture). `lane-a` part 5/8 took 122 s forward (the CI `shards` job runs the whole shard).

**Ledger inbox:** none.

**Integration and linkage (Rules 1 and 2):**
- **Consumes:**
  - `Watch.Reader.Evidence` and `CredentialName`;
  - `Watch.EvidencePack.Build`, `Load` and `SNAPSHOTFORMAT`;
  - `Bridge.Redact.Text`, `UNCHECKED` and `REDACTED`;
  - `DiagnosisPayload.CAUSECATEGORIES` and `FIXCATEGORY`;
  - `Bridge.Ids.NewRef`;
  - `Eval.In.FOLDER` and `CaseNames`;
  - `Test.Demo.Production`'s public helpers and `Test.Data.Fixture.RemoveMessages`. All are used read only, except the WatchMark hold that `Test.Demo.Production` prescribes.
- **Consumed-by:**
  - **Story 9.9 (the sibling):** it records nine incidents with `Capture` through its driver, and adds their recipes;
  - **Story 9.6:** `IncidentManager` builds packs from these snapshots with the same `Build`;
  - **Story 9.5:** the demo incident gate runs `Report.DEMOCASE` 10 times;
  - **Story 17.7:** it records setting-change incidents with `Capture`;
  - an author recording a case from real use (FR-62).
- **The consumer in this story:** the product's `EvidencePack.Load` and `Build` reading the written file (the Integration AC).

**Siblings (extend, don't copy):**
- `Eval.Record` does not extend `Test.Demo.Production.Snapshot`/`Record` (Story 0.10). Product code never calls a test class, and a recording must be the reader's own answer. `Snapshot()` is not: it runs its own SQL, takes every item and reads four fixed body properties.
- `Test.Eval.Record` reuses the Orders helpers instead of copying them.
- The pack comparison is new. `Test.Demo.Production.Projection` projects snapshots, but the pack is what the diagnosis reads, and one `Build` makes both packs.
- `TestIncidentFiles` reuses `Plain`, `Hosts`, `Read`, `Folder` and `Names`.
- The `demo` rule follows the `set` rule's pattern.

**Veto-window items:** the split (Decided in-stage 1). Nothing else:
- the files keep `ocutalon.readerSnapshot/1` and 9.1's case format;
- there is no new privilege, no public text and no secret handling;
- `Eval.Record` only redacts, and refuses.

**Footprint extensions:** `docker/tests/record-eval.sh`, header comment only (allowed by the lead; reported).

**Spine (Rule 20), the lead's call.** AD-22's as-built line forecasts that "record-eval.sh records the snapshot … until Story 9.4's Eval.Record replaces it". As built in this part:
- `Eval.Record` records through `Reader.Evidence`;
- the demo file stays `record-eval.sh`'s while its pins stand;
- `Test.Eval.Record` compares each committed incident's pack with a fresh recording on every CI run.

## Verification

`<B>` stands for:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

QA and review use their own stage names and tags: `e9s4q`/`e9s4qw` and `e9s4c`/`e9s4cw`.

- **Run discipline:** run every command from the epic-9 worktree root (the lead names its absolute path in each stage prompt; never write it into a committed file), in the foreground of its own call with `timeout: 600000`. Prefer calls under 3 minutes. A call that the harness moves to the background is waited on by reading its output file in short calls, never by starting a second copy. Only one `iris_execute_tests` per message.
- **IRIS MCP:** only to compile-check `Eval/Record.cls` and the test classes on slot B (`server` `ocutalon-slot-b`, namespace `OCUTALON`, after `iris_server_info` shows build 154U). Run no test there, and induce nothing.
- **Tags:** fresh `e9s4i`, warm `e9s4iw`.

**Shared surfaces:**
- the OCUORDERS messages and the Orders WatchMark. They are held and released as `Test.Demo.Production` prescribes, and shared with it, with `Test.Demo.BreakFeedProduction`, with `Test.Watch.*` and with the floor specs;
- `test-eval-set.sh`'s rules and samples (`incident-good`'s snapshot, the new variants, the rule `demo`, the `enumerations` messages);
- `Eval.Report`'s parameters (`DEMOCASE`);
- the `lane-a` shard's class list (`Test.Eval.Record`) and its CI time;
- `eval/` does not change;
- the saved Orders production definition in OCUORDERS, whose item settings `TestCaptureDropsCredentialSettings` adds and removes (restored in-test and by `OnAfterAllTests` as a backstop; added by the lead after code review).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-b`, then compile `Eval/Record.cls`, `Eval/Report.cls`, `Test/Eval/Record.cls` and `Test/Eval/Cases.cls` on slot B, namespace `OCUTALON` -- expected: build 154U, and every class compiles.
- (once) `<B> OCUTALON_RUN_TAG=e9s4iw ci/warm.sh up` -- expected: `LOCK acquired warm-iris`, ready.
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: every rule PASS, `demo` included (about 5 s).
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s4iw ci/iris.sh class OcuTalon.Test.Eval.Record` -- expected: passed. Record Task 0 (a) and (c).
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s4iw ci/iris.sh class OcuTalon.Test.Eval.Cases` -- expected: passed, with `TestIncidentFiles` (Task 0 (b)).
- (once) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s4iw ci/iris.sh class OcuTalon.Test.Demo.Production`, then the same for `OcuTalon.Test.Watch.Evidence`, each in its own call -- expected: both pass on the stack that `Test.Eval.Record` used, so the pins and the WatchMark are intact.
- (once) `<B> OCUTALON_RUN_TAG=e9s4i ci/iris.sh class OcuTalon.Test.Eval.Record` -- expected: passed on a fresh stack (about 90 to 150 s).
- (once) `<B> OCUTALON_RUN_TAG=e9s4i ci/iris.sh shard lane-a --part k/8`, for the part or parts whose `CLASS` lines hold the `Test.Eval` classes (part 5/8 on 9.3's head), then the same part again with `--reverse`, each in its own call -- expected: every class passes (about 100 to 170 s each; record the times).
- (once) `bash ci/checks.sh` -- expected: every block passes (`boundaries`, `eval-set`, `class-rules`, `ci-config` and `ci-changes` included).
- (once, last; also after a failure) `<B> OCUTALON_RUN_TAG=e9s4iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s4i ci/iris.sh teardown` -- expected: the lane-b lock folder holds no lock of this stage.

**Planned mutations (Rule 19).** For each one: apply it, observe the red, revert, confirm that `git status --short` and `git diff --stat` are as before, and write the `mutation:` line here. A data mutation of `eval/orders-date-format/*` must end byte-identical.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `Capture` passes only the first key to the reader | `TestCaptureWritesCase` (1 failure, not 50) and `TestReplayEqualsLive` |
| AC1 | `Write` skips `Redact.Text` | `TestWriteRedacts` |
| AC1 | `Write` drops the `LOCALPATH` check | `TestWriteRefuses` |
| AC1 "And" | the committed demo snapshot's first body gains `"Password": "zz"` | `TestIncidentFiles` (not a fixed point) |
| AC1 "And" | the snapshot rule ignores a credential-named setting | `test-eval-set.sh` `cases` (`bad-snapshot-credential-setting`) |
| AC2 | `DEMOCASE` becomes `orders-date` | `test-eval-set.sh` `demo` and `TestCaptureWritesCase` |
| AC2 | `Write` leaves `expectation` out of `case.json` | `TestCaptureWritesCase` |
| AC4 | `Write` empties `trace` before it writes | `TestReplayEqualsLive` |
| AC4 | the committed demo snapshot's first `OrderDate` becomes `10/17/2026` | `TestCommittedIsCurrent` |
| AC4 | `RECIPES` is empty | `TestCommittedIsCurrent` (`orders-date-format` has no recipe) |
| enumerations | the `FIXKINDS` fallback is removed | `test-eval-set.sh` `enumerations` self-check |

mutation: `Capture` passes only the first key to the reader -> `TestCaptureWritesCase` (1 failure, not 50) and `TestReplayEqualsLive` (`.count` differs) went red
mutation: `Write` skips `Redact.Text` -> `TestWriteRedacts` went red
mutation: `Write` drops the `LOCALPATH` check -> `TestWriteRefuses` went red (every path row, and "nothing was written")
mutation: the committed demo snapshot's first body gains `"Password": "zz"` -> `TestIncidentFiles` went red (not a fixed point of `Redact.Text`)
mutation: the snapshot rule ignores a credential-named setting (the check in `check-cases.mjs` disabled) -> `test-eval-set.sh` `cases` went red (`bad-snapshot-credential-setting` and `bad-snapshot-credential-setting-case` not flagged)
mutation: `DEMOCASE` becomes `orders-date` -> `test-eval-set.sh` `demo` and `TestCaptureWritesCase` went red
mutation: `Write` leaves `expectation` out of `case.json` -> `TestCaptureWritesCase` went red
mutation: `Write` empties `trace` before it writes -> `TestReplayEqualsLive` (`.trace.0` missing) and `TestCaptureWritesCase` went red
mutation: the committed demo snapshot's first `OrderDate` becomes `10/17/2026` -> `TestCommittedIsCurrent` went red (`.sample.body.OrderDate` differs)
mutation: `RECIPES` is empty -> `TestCommittedIsCurrent` went red (`orders-date-format` has no recipe), with `TestCaptureWritesCase`
mutation: the `FIXKINDS` fallback is removed (the loop of `fix_kinds_of`) -> `test-eval-set.sh` `enumerations` self-check went red
mutation: `Capture` skips the check of the reader's outcome -> `TestCaptureRefuses` went red
mutation: (measurement, not a pin) `VOLATILE` emptied -> `TestCommittedIsCurrent` went red at exactly the six volatile fields
mutation: (Hermeticity) `Clean` skips deleting the batch's messages -> `TestCleanRemovesBatch` went red ("Clean deleted the headers of the batch")
mutation: (Hermeticity) `Clean` skips deleting the folder -> `TestCleanRemovesBatch` went red ("and the folder")
mutation: (Hermeticity) `Clean` skips releasing the mark -> `TestCleanRemovesBatch` went red ("and released the Orders WatchMark")
mutation: (Hermeticity) `OnBeforeAllTests` skips `HoldFailures` -> `TestNoIncidentMade` went red ("the Orders WatchMark was held ahead before the first order was sent"); the class was run green first, so no leftover mark could explain it
mutation: (AC1) `Write` drops an event-log row before it redacts -> `TestCaptureWritesCase` went red ("snapshot.json is the reader's own answer ..."); the packs of `TestReplayEqualsLive` stayed green, because `Build` never reads the event log
mutation: (AC1) `Write` skips the `UNCHECKED` refusal -> `TestWriteRefuses` went red (the body nested deeper than `Redact.MAXDEPTH`)
Each mutation was reverted from a backup, and the checksums of every changed file and of `eval/orders-date-format/*` matched the manifest taken before the first mutation (`git status --short` and `git diff --stat` unchanged).

**Run record (implement stage):**
- warm (`e9s4iw`): `Test.Eval.Record` passed, `Test.Eval.Cases` passed, `Test.Demo.Production` passed (35 s), `Test.Watch.Evidence` passed;
- fresh (`e9s4i`): `Test.Eval.Record` passed (11.1 s, ready after 87 s); `lane-a` part 5/8 passed (10 classes, 122 s); `lane-a` part 5/8 `--reverse` passed (10 classes, none of them an Eval class, 121 s); `lane-a` part 4/8 `--reverse` passed (10 classes, all nine `Test.Eval` classes, 114 s);
- `bash docker/tests/test-eval-set.sh` (every rule, `demo` included), `bash docker/tests/test-boundaries.sh` and `bash ci/checks.sh` passed;
- both stacks were torn down and the lane-b lock folder is empty.

**Run record (review pass, after the last patch):**
- compile check on `ocutalon-slot-b` (`OCUTALON`, build 154U): `Eval/Record`, `Eval/Report`, `Test/Eval/Cases` and `Test/Eval/Record` compile; no test ran there;
- `bash docker/tests/test-eval-set.sh` (every rule, `demo` included), `bash docker/tests/test-boundaries.sh` and `bash ci/checks.sh` (exit 0) passed;
- warm (`e9s4iw`, a new stack): `Test.Eval.Record` passed (12 to 15 s), `Test.Eval.Cases` passed (3.6 s), then `Test.Demo.Production` (33 s) and `Test.Watch.Evidence` (2 s) passed on the same stack, so the pins and the WatchMark are intact; the six review-pass mutations above ran there, each followed by a green run of the class before the next one (the hold mutation after a green run, so no leftover mark could explain its red);
- fresh (`e9s4i`): `Test.Eval.Record` passed (13.4 s, ready after 89 s); `lane-a` part 5/8 passed forward (10 classes, 143 s, all nine `Test.Eval` classes among them: `Record` 13.7 s, `Run` 7.4 s, `Cases` 3.7 s); part 4/8 passed reversed (10 classes, 130 s, `Record` 14.8 s) -- the same part reversed (5/8) holds no `Test.Eval` class (Decided in-stage 17);
- both stacks were torn down and the lane-b lock folder is empty.

**QA stage (tags `e9s4qw` warm, `e9s4q` fresh; no new file, tests added to the two existing classes):**
- Test files changed (QA):
  - `src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls` (QA): `TestWriteKeepsCaseFields`, `TestWriteRefusesMore`, `TestCaptureRefusesBadCaseFirst` and `TestCaptureDropsCredentialSettings` are new; `TestCleanRemovesBatch` now ends the batch with the `OnAfterAllTests` of a second instance, so that the wiring of `Clean` is pinned too.
  - `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` (QA): `TestIncidentChecksFlagViolations` is new; the checks of `TestIncidentFiles` moved into `IncidentProblems` (same checks), so that the same code runs on incident cases that the new test writes below `/tmp/zz-eval-cases/` and removes.
- Gaps the QA tests close (each was green before, with the mutation applied): `heldOut` passed through as true; `Capture` refusing a bad case before it reads the production; a local path or a non-ASCII character in the case's own text; the temporary-folder alternatives of `LOCALPATH`; a snapshot that is not an object or whose failures are text; a blank folder; the replacement of existing files; `OnAfterAllTests` calling `Clean` with the run's folder and hold; credential-named settings in the definition of the failing item (the Orders item has only `TargetConfigName`, so the earlier assertion could not see the reader drop anything); and the ASCII, redaction, path, host and credential-name rules of `TestIncidentFiles`, which only ran on a clean tree.
- Hermeticity of the new tests: `TestCaptureDropsCredentialSettings` adds four credential settings and one plain one to the saved Orders definition and takes them out again (also from `OnAfterAllTests` through `SettingsAdded`), as `Test.Watch.Evidence` does; `TestIncidentChecksFlagViolations` and the other new tests make their folders below `/tmp` and remove them; none depends on another test's state or on the order.

mutation: (QA, AC1) `Write` always writes `heldOut` false -> `TestWriteKeepsCaseFields` went red (the only test; every earlier test stayed green)
mutation: (QA, AC1) `Capture` skips its own check of the case -> `TestCaptureRefusesBadCaseFirst` went red (the reasons became "nothing to record: not_current" and "nothing to record: no failure"); no earlier test went red
mutation: (QA, AC1) `Write` checks the snapshot for a local path but not the case -> `TestWriteRefusesMore` went red (the description and elementAtFault rows)
mutation: (QA, AC1) `Write` drops the non-ASCII check -> `TestWriteRefuses` (body, description) and `TestWriteRefusesMore` (elementAtFault) went red
mutation: (QA, AC1) `CaseRecord` accepts a fixKind for a category with no fix -> `TestWriteRefuses` went red
mutation: (QA, AC1) `Capture` drops its no-failure refusal -> `TestCaptureRefuses` went red (the reason text; `Write` still refused, with another reason)
mutation: (QA, AC1) `WriteFile` leaves an existing file as it is -> `TestWriteKeepsCaseFields` went red (the second Write's case.json and snapshot.json). Removing only the `Delete` is an equivalent mutation (the stream truncates the file), which stayed green and is not counted
mutation: (QA, AC1) `LOCALPATH` loses the `var` and `etc` alternatives of its private-folder pattern -> `TestWriteRefusesMore` went red
mutation: (QA, AC1) `LOCALPATH` loses the look-behind of its var/folders pattern -> `TestWriteRefusesMore` went red (a folder below another one named var/folders is refused)
mutation: (QA, AC1) `Capture` puts a credential-named setting back into the reader's answer -> `TestCaptureDropsCredentialSettings` went red (the item's settings, and the names in the file and the pack), with `TestCaptureWritesCase` ("with no credential-type setting" and the exact snapshot)
mutation: (QA, Hermeticity) `OnAfterAllTests` does not call `Clean` -> `TestCleanRemovesBatch` went red (headers, folder and mark); the earlier test called `Clean` directly and did not reach `OnAfterAllTests`
mutation: (QA, Hermeticity) `OnAfterAllTests` passes no folder to `Clean` -> `TestCleanRemovesBatch` went red ("and the folder")
mutation: (QA, AC1 "And") the check of `TestIncidentFiles` skips the local-path rule -> `TestIncidentChecksFlagViolations` went red (snapshot and case rows)
mutation: (QA, AC1 "And") it skips the ASCII rule -> `TestIncidentChecksFlagViolations` went red (snapshot and case rows)
mutation: (QA, AC1 "And") it skips the fixed-point rule -> `TestIncidentChecksFlagViolations` went red (the password row)
mutation: (QA, AC1 "And") it skips the host rule -> `TestIncidentChecksFlagViolations` went red
mutation: (QA, AC1 "And") it skips the credential-name rule -> `TestIncidentChecksFlagViolations` went red (ApiKey and BOTTOKEN rows)
mutation: (QA, AC1 "And") it does not flag a snapshot file that is missing -> `TestIncidentChecksFlagViolations` went red
mutation: (QA, AC2) the `demo` rule of `test-eval-set.sh` compares only the cause category -> `test-eval-set.sh` `demo` went red (`bad-demo-element`, `bad-demo-extra-field` and `bad-demo-fixkind` not flagged)
mutation: (QA, AC1 "And") the `cases` rule of `test-eval-set.sh` no longer checks each failure's targetConfigName and error -> `test-eval-set.sh` `cases` went red (`bad-snapshot-failure-no-error` and `bad-snapshot-failure-no-target` not flagged)
Each QA mutation was applied from a script with a backup, reverted from the backup, and the checksums of every file under `Eval/`, `Test/Eval/`, `test-eval-set.sh` and `eval/orders-date-format/*`, `git status --short` and `git diff --stat` matched the baseline taken before the first mutation (the baseline was taken again once, after `TestCaptureDropsCredentialSettings` was added). `mutations_demonstrated=20`.

mutation: (code review, Hermeticity) `Clean` returns an error status -> `TestCleanRemovesBatch` went red ("the end of a run that held the failures, sent a batch and left the fixture settings"), and the run's own `OnAfterAllTests` status was reported as an error of the class
mutation: (code review, Hermeticity) `OnAfterAllTests` skips its restore of the fixture settings -> `TestCleanRemovesBatch` went red ("and took the fixture settings out of the definition")
mutation: (code review, Hermeticity) the restore at the end of `TestCaptureDropsCredentialSettings` fails -> `TestCaptureDropsCredentialSettings` went red ("the settings are taken out of the definition again" and "the definition holds the settings it held before"), with `TestCleanRemovesBatch`, whose `before` held the leftover settings
Each code-review mutation ran on the warm stack `e9s4cw`, was reverted from a backup, and the class was green again on the same stack before the next one; the checksums of every file under `Eval/`, `Test/Eval/`, `test-eval-set.sh`, `record-eval.sh` and `eval/orders-date-format/*` matched the manifest taken before the first mutation.

**Run record (QA):**
- compile check on `ocutalon-slot-b` (`OCUTALON`, build 154U): `Test/Eval/Record` and `Test/Eval/Cases` compile; no test ran there. The load also put the unchanged `Test/Eval/*` classes on the slot;
- warm (`e9s4qw`): `Test.Eval.Cases` (4.4 s) and `Test.Eval.Record` (13 to 16 s) pass, then `Test.Demo.Production` (34 s) and `Test.Watch.Evidence` (2.5 s) on the same stack, so the Orders definition and the pins are intact after `TestCaptureDropsCredentialSettings`; every mutation above ran there;
- fresh (`e9s4q`): `lane-a` part 5/8 forward passed (10 classes, 138 s, `Record` 14.3 s, `Cases` 4.5 s) and part 4/8 `--reverse` passed (10 classes, 119 s, `Record` 13.0 s, `Cases` 4.3 s);
- `bash docker/tests/test-eval-set.sh`, `bash docker/tests/test-boundaries.sh` and `bash ci/checks.sh` pass; both stacks are down and the lane-b lock folder is empty.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Part 1 of Story 9.4 is built.
- `OcuTalon.Eval.Record` captures an incident's failures through `Watch.Reader.Evidence`, passes the reader's answer through `Bridge.Redact.Text`, refuses (with the reason, writing nothing) a case that is not valid, an outcome that is not `read`, no failure, an `UNCHECKED` redaction, a non-ASCII character and a local machine path, and writes `snapshot.json` and `case.json`.
- `OcuTalon.Test.Eval.Record` re-induces the demo incident (50 orders in MM/DD/YYYY in the Orders production of OCUORDERS, WatchMark held) and proves that `Build(Load(written file))` and `Capture`'s pack equal the live pack exactly, and that the committed demo snapshot's pack equals it once `VOLATILE` is removed.
- `TestIncidentFiles` and `test-eval-set.sh` (`cases` snapshot rules, the new `demo` rule, the `Fix/Kind/` fallback for `FIXKINDS`) check every incident file; `Eval.Report.DEMOCASE` names the demo incident.
- Task 0: the committed demo snapshot and a fresh capture differ only in `VOLATILE`; both demo files are fixed points of `Redact.Text`; `eval/orders-date-format/*` is byte-identical.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Eval/Record.cls` (new): the recorder, `Capture` and `Write`.
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls`: `Parameter DEMOCASE`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls` (new): seven tests, the demo recipe, `Clean`, and the synthetic-snapshot helpers.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`: `TestIncidentFiles`; `Read` and `Plain` are public.
- `docker/tests/test-eval-set.sh`: the snapshot rules and variants, the `demo` rule, the fix-kind fallback and its self-check, the header.
- `docker/tests/record-eval.sh`: header comment only (a reported footprint extension).
- This spec: Task 0 results, Decided in-stage 13 to 18, `mutation:` lines, the triage log and run records.

**Review findings.** 39 findings from four layers: medium 2, low 25, false 12 (the Review Triage Log holds every row).
- Patches applied (3): the clean-up and hold pins for the Hermeticity criterion (`Clean`, `TestCleanRemovesBatch`, `HoldChecked`; medium), the exact comparison of `snapshot.json` with `Redact.Text` of the reader's answer (medium), and a test of the redactor's `UNCHECKED` refusal (low). Each has a demonstrated mutation.
- Deferred: none.
- Rejected with reasons (36): spec-bound behaviour (the `fixKind` name is checked by the repository check, the Write checks the spec lists, `heldOut` default, the `Guard()` on every test, the `Fix/Kind/` fallback, the `TMP` wipe), a loud failure on a malformed hand-edited file (BH7, EC9), non-atomic replace and name collision of an author tool, the `irisowner` prefix and doubled-backslash cases that mirror `test-boundaries.sh`, and descriptive intent-alignment observations.

**Follow-up review recommended: true.** Two medium findings were patched. The named unverified risk is that `TestCleanRemovesBatch` and the exact snapshot comparison were written in the review pass and have had no second look: `TestCleanRemovesBatch` releases the Orders WatchMark and holds it again inside the class, and the exact comparison assumes two reads of the same failures return identical text (true on every run so far: 8 class runs, 2 shard runs and 6 mutation runs).

**Verification performed.** `test-eval-set.sh`, `test-boundaries.sh` and `ci/checks.sh` pass. On a warm and a fresh throwaway (lane B): `Test.Eval.Record`, `Test.Eval.Cases`, `Test.Demo.Production` and `Test.Watch.Evidence` pass, and `lane-a` parts 5/8 (forward) and 4/8 (reversed) pass. 19 mutations were demonstrated red and reverted byte-identical. See the run records under `## Verification`.

**Residual risks.**
- `TestIncidentFiles`' host check only sees hosts after `@` or `://` (Task 4's rule, from 9.3): a bare host in an item setting passes. The sibling story (9.9), whose recordings come from a feed with settings, should decide this.
- `Eval.Record` does not check the fix kind's name (it may not name `FIXKINDS`); the `cases` rule of `test-eval-set.sh` does.
- The `Fix/Kind/` fallback has only its self-check until Epic 7's branch merges.
- `Test.Eval.Record` adds about 15 s to the `lane-a` shard (the `shards` job).
- Slot B holds the committed `Eval/Msg/TurnResult.cls` and the four classes of this story, loaded for the compile check (Decided in-stage 16).
