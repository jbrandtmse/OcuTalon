---
title: 'Story 9.4: Ten incidents are recorded from real failures (part 1: the recorder, the demo incident and the replay test)'
type: 'feature'
created: '2026-10-28'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
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

## Spec Change Log

## Review Triage Log

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
- `eval/` does not change.

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
