---
title: 'Story 0.4: The cross-lane message and data contracts'
type: 'feature'
created: '2026-10-19'
status: 'done'
baseline_revision: '2d13b44847d41a0ae28614800b149cc60f34eaf4'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      Nothing in the install or the audit writer reports that instance-wide auditing is off, so on such an instance the six events register and no entry is ever written.
    evidence: |-
      Bridge.Installer.AuditEvents, CheckAudit, Step.Audit and Bridge.Audit.Write never read Security.System AuditEnabled; only test-audit.sh row 10 asserts it, on the two images. OcuTalon must not change the setting (AD-17); whether to warn, show it in the security overview or refuse is a product call (FR-9, "no false all-clear").
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Installer.cls:31
    severity: medium
  - summary: >-
      AC5 (every Storage Default block equals the compiler's output) is verified by a one-off load, compile and export, not by a check that runs in CI.
    evidence: |-
      test-storage.sh checks only that a Storage Default block exists and that its DataLocation is the global plus D. A later story that hand-edits a storage block, or leaves a class whose export differs from its file, fails no test. The spec scopes the round trip as (once); Story 0.7 owns the CI wiring.
    location: >-
      docker/tests/test-storage.sh
    severity: medium
  - summary: >-
      Data.Time.ToLocal and Zone() read the process TZ, and no test runs them in a production job started with the container's TZ (AD-18).
    evidence: |-
      Row 8 sets the TZ of the test process. Whether a production job inherits the container's TZ is not measured (inference). It would be settled by a throwaway start with a compose-level TZ and a ToLocal call from a production job. If false in practice, reminders and catalog times show the wrong local time (Stories 0.9, 8.3).
    location: >-
      src/ocutalon/cls/OcuTalon/Data/Time.cls:15
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Both build lanes start from Epic 0, but no shared message, table, enumeration, identifier, time, setting or audit contract exists yet. Without them, each lane would invent its own contracts and the two would collide.

**Approach:**
- Create every contract this story's acceptance criteria name, with final names and types and the properties another lane or story relies on (the contract tables under Design Notes).
- Commit each class's storage block and register its `DEFAULTGLOBAL` short name.
- Implement the shared helpers: `Bridge.Ids`, `Data.Time`, `Data.Setting.Get`, and `Bridge.Audit` with its registration at install.
- Declare `Data.Delivery`'s two cross-lane methods and `Channel.Telegram.In.Included()`.

## Boundaries & Constraints

**Always:**
- **Contract tables.** The contract tables are the property lists. Each class has exactly those properties, names, types and indexes, plus the ones it inherits. Doc comments state each property's contract in one line, using the AC and AD wording (Rule 14).
- **Messages** extend `Ens.Request` or `Ens.Response`. They share IRIS's `^Ens.MessageBody*` extent and have no `DEFAULTGLOBAL`.
- **Other persistent classes** extend `%Persistent`, never a message base (AD-24). Each sets `Parameter DEFAULTGLOBAL` to its row in `src/short-names.tsv`: `^OcuTalonBP.<short>` under `src/bridge/`, `^OcuTalonP.<short>` elsewhere (AD-3).
- **Storage blocks.** Every persistent and message class carries the `Storage Default` block the compiler generated on slot A, copied in verbatim and never edited by hand (AD-5).
- **The bridge** references no other OcuTalon package (AD-2).
- **Namespace switching.** Only `OcuTalon.Bridge.Installer` and `OcuTalon.Install.*` switch to `%SYS`, each in one method with `New $Namespace` (AD-3).
- **Times** are `Utc` strings (`YYYY-MM-DDThh:mm:ssZ`). **Refs** come from `Bridge.Ids.NewRef()`.
- **SQL names.** No table or field projects to an SQL reserved word (`$SYSTEM.SQL.IsReservedWord`). A reserved property name stays as it is and gets a `SqlFieldName`.
- **Runtime targets.**
  - Slot A only: every MCP call names `server: ocutalon-slot-a` and `namespace: OCUTALON`.
  - Slot A tests create only per-run `Zz<n>` fixtures (`$Increment(^OcuTalonTest(<area>, "n"))`, never reset) and restore `^OcuTalonTest("TelegramIncluded")`.
  - Audit-event registration and the full install run only in throwaway projects through `lib-live.sh`, one IRIS stack at a time (Rule 21).
- **ASCII source.** Any non-ASCII character is written as an escape (Rule 14).

**Never:**
- **Owned by later stories:**
  - the catalog classes and `Catalog.Render` (0.9);
  - `Live.Event`, `Live.Publish`, every other `Live.Payload` class, and every TypeScript interface (0.5);
  - the production items, the extension bases, 0.6's API stubs and `Commands.Submit` (0.6);
  - `Bridge.Time` (1.4);
  - `Digest.Data.Item` (1.12);
  - `Delivery`'s method bodies (2.7);
  - the `Pairing` and `StatusMark` methods (10.3);
  - `Data.Time.FromLocal` (8.3);
  - the audit data shapes, the redaction and the read-back helper (3.7).
- **Auditing.** Never turn instance-wide auditing on or off, and never change an IRIS (`%System`/`%Ensemble`) audit event.
- **References and secrets.** Never load anything from `irislib/` or `irissys/`, and never read `.env`.
- **Slots.** Never stop or recreate a slot.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–4, 6–9 and 13–15: `%UnitTest` classes on slot A.
- Row 5: `test-storage.sh`.
- Rows 10–12: `test-audit.sh`, in a throwaway project.
- Row 16: `test-install-start.sh`.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Contracts | both trees loaded on slot A | Every class in the contract tables has its superclass and exactly its listed properties, types, MAXLEN/SCALE and indexes. Each verb inherits `Origin`, `IdempotencyKey` and `SessionRef`. `Live.Payload.Decision` exports camelCase keys | none |
| 2 | Enumerations | `Msg.Enum`, `Bridge.Msg.Enum` | The twelve `Msg.Enum` parameters equal the conventions row exactly. The bridge's seven equal OcuTalon's | none |
| 3 | Busy reply | `Reply.NewBusy()` | `Busy` 1; `Text`, `DecisionRef`, `Outcome` and `Reasons` empty; `Fallback` 0; `%Save()` OK | none |
| 4 | Private records | every registry class compiled | `DEFAULTGLOBAL` equals the row's global; DataLocation is the global plus `D`; `GetGlobalDest` gives `OCUTALON_PRIVATE`; `PrivateData.Run()` is OK and `StorageGlobals` lists every registry global | none |
| 5 | Registry check | the real tree, then one synthetic sample per rule: a duplicate short name, global or class; a row whose class lacks the parameter; a parameter with no row; `^OcuTalonP.` under `src/bridge/`, or `^OcuTalonBP.` outside it; a storage-bearing class with no `Storage Default`; a DataLocation that isn't the global plus `D` | the real tree passes; each sample fails, naming the file and the rule | exit 1 |
| 6 | SQL names | every persistent OcuTalon class outside `OcuTalon.Test` | no table or field name is reserved | none |
| 7 | `NewRef` | 10,000 calls | all unique; each matches `^[A-Za-z0-9_-]{22}$` | none |
| 8 | Time | process TZ unset, then `America/New_York` (Task 0) | Unset: `ToLocal("2026-11-01T06:30:00Z")` gives `2026-11-01T06:30:00` and `Zone()` gives `UTC`. New York: `2026-11-01T05:30:00Z` and `06:30:00Z` both give `2026-11-01T01:30:00`; `2026-03-08T06:30:00Z` gives `01:30:00` and `07:30:00Z` gives `03:30:00`; `Zone()` gives `America/New_York`. `NowUtc()` matches the `Utc` form | `""` or junk gives `""` |
| 9 | Setting | a fixture key `zz.<n>`, seeded; then its row changed; its cache entry aged 61 s; a missing key; `onlineDemo`; a second `Seed`; `Seed("onlineDemo", …)` | the seeded value; still the old value within 60 s; the new value once aged; the `default` argument; the same value as `Public.Settings.Get`; the second `Seed` changes nothing | the refused key gives an error naming it |
| 10 | Audit registered | first start (throwaway) | six events, `OcuTalon/<T>/<T>` for `Action`, `Approval`, `Pairing`, `Settings`, `MCP` and `Tool`, all enabled; the STEP lines are unchanged | none |
| 11 | Audit write | `Write("Action", {"marker": <unique>}, "zz <unique>")` | OK; within Task 0's poll (120 s by default), one `%SYS.Audit` row with `EventSource` `OcuTalon`, `EventType` and `Event` `Action`, and `EventData` holding the marker | none |
| 12 | Audit structural | disable `OcuTalon/Tool/Tool` and run `Bridge.Installer.Run()`; then delete `OcuTalon/MCP/MCP` and run `Install.Step.Audit.Run()` | still six events, all enabled; then `Step.Audit` fails, naming `OcuTalon/MCP/MCP` | failing status |
| 13 | Audit API | `Bridge.Audit.Events()`; `Write("Zz", {})` | the six names, in the order above; an error naming `Zz` | error status |
| 14 | Telegram | the global absent, then 0, 2 and 1 | `Included()` gives 0, 0, 0, then 1; the earlier value is restored | none |
| 15 | Delivery stubs | `Record("zz","web","1","")`; `FindByApproval("zz","web","zz")` | an error status saying it isn't implemented yet; `""` | error status |
| 16 | Install | `test-install-start.sh` | the first start compiles every new class and passes, with the STEP list unchanged | none |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), read by line range:
  - AD-3 L121–148; AD-5 L174–183; AD-6 L185–216 (Request L207, responses L212, busy L215); AD-11 L309–323; AD-14 L384–395; AD-15 L396–436; AD-16 L438–451; AD-17 L453–461; AD-18 L463–473; AD-19 L475–515; AD-20 L517–541; AD-23 steps L608–616; AD-26 L714–732; AD-29 L754–768; AD-30 L770–790; AD-32 L809–818; AD-33 L820–828.
  - Conventions L864–885; ownership tables L1000–1063.
- **Epics** (`epics.md`): this story L848–878.
  - Consumers that fixed names: 1.10 L1321–1330 (reminder verbs); 2.3 L1459–1485 (routing by verb, origins); 2.6 L1561 (decision payload); 2.8 L1652; 5.1 L2265–2280 (watch verbs); 5.5 L2395–2405 (dismiss); 4.1 L2033 (demo mode); 8.3 L2850–2889; 10.3 L3149–3170 (pair and unpair); 16.4 L4037 (end session).
- **Existing code:**
  - `src/bridge/cls/OcuTalon/Bridge/Installer.cls`: `Run()` checks only the namespace. Today it is the only bridge class.
  - `src/ocutalon/cls/OcuTalon/Install/Step/Audit.cls`: an empty stub kept for this story; step 10 of `Registry.Order()`.
  - `Install/Step/PrivateData.cls`: `StorageGlobals` reads `%Dictionary.CompiledStorage` for `^OcuTalonP.`/`^OcuTalonBP.` globals; `Check` uses `GetGlobalDest`. Reuse both in row 4.
  - `Data/Public/Settings.cls`: `KEYS` (L9), `READY` (L12), `Get(key, .sc)` (L16). Its private `UtcNow` writes the same `Utc` form.
  - `Test/Install/Registry.cls:36`: the per-run fixture counter pattern. `Test/Install/PrivateData.cls`: compiling fixtures from text.
- **Shell tests** (`docker/tests/`):
  - `test-boundaries.sh`: each scanner first runs on a bad sample and a good sample; one PASS or FAIL line per rule; file:line output.
  - `lib-live.sh`: `live_start` :20, `dc` :136, `iris_script` :190, `wait_started_ready` :245.
  - `test-install-start.sh`: an exact STEP diff.
- **IRIS reference:**
  - `irislib/%SYSTEM/Security.cls:22`: `Audit(Source, Type, Name, EventData, Description)`; the description is cut at 128 bytes.
  - `irissys/Security/Events.cls`: `Create` :92, `Exists` :132, `Modify` :203. The event is `"Source/Type/Name"`, as `irislib/%Library/EnsembleMgr.cls:3963` uses it.
  - `irislib/%SYS/Audit.cls:93–160`: `EventSource`, `EventType`, `Event`, `EventData`, `Description`, `UTCTimeStamp`. Read back in `%SYS`.
  - `irislib/Ens/MessageBody.cls:5–9`: messages share one extent.
  - `irislib/%SYSTEM/Process.cls:1846`: `TimeZone(newTZ)` returns the old value.
- **Measured** on slot A, October 19:
  - build 154, Health, ARM64;
  - instance auditing on;
  - `Security.Events` not visible in OCUTALON, so registering needs `%SYS`;
  - TZ unset and `$ZTIMEZONE` 0;
  - `/usr/share/zoneinfo/America/New_York` present;
  - `$ZDATETIME($ZTIMESTAMP,3,7)` gives `2026-10-19T06:57:07Z`;
  - reserved words among the planned names: `COUNT`, `INPUT` (also `ON`, `TIME`, `USER`, `ROWS`).
- **Storage blocks:** load and compile on slot A, then copy each class's generated `Storage Default` block into its file (from `iris_doc_get` udl, or `iris_doc_export` into the scratchpad).

## Tasks & Acceptance

**Execution:**

**Task 0, measure.** Restore anything you change, and record each result under Verification. Anything not measured is `(inference)`.
- **Time zones** (slot A): does `$SYSTEM.Process.TimeZone("America/New_York")` change `$ZDATETIMEH(h,-3)` and `$SYSTEM.Util.GetEnviron("TZ")` in the same process? Restore with the returned value. If it doesn't, row 8's New York half runs in `test-audit.sh`'s throwaway, with `TZ=America/New_York` added through `live_add_file`.
- **Audit behaviour** (throwaway): what `$SYSTEM.Security.Audit` returns for an unregistered event (this goes into `Write`'s doc comment), and how long a written row takes to become readable (this sets row 11's poll).
- **Non-Health image:** is instance auditing on by default on `iris-community:2026.3.0AI.154.0`? If it is off, stop and report it as an intent gap: FR-9 needs auditing, and OcuTalon never changes it.

Bridge (`src/bridge/cls/OcuTalon/Bridge/`):
- `Ids.cls`: `NewRef()` takes 16 bytes from `$SYSTEM.Encryption.GenCryptRand` and returns them base64url-encoded, without padding.
- `Msg/Enum.cls`, `Msg/Request.cls`, `Msg/Result.cls`, `Msg/DecisionResponse.cls`, `Msg/Reply.cls` (with `ClassMethod NewBusy() As Reply`), `Msg/DecisionPayload.cls` and `Msg/AgentStep.cls`: as the contract tables give them. AD-6, AD-7, AD-9, AD-26.
- `Data/Decision.cls`, `Data/ApprovalRequest.cls` (with `Parameter DRYRUNKEYS = "affected,resend,leftOut,field,before,after,itemNoun"`), `Data/Usage.cls`, `Data/Price.cls`, `Data/ConversationLink.cls` and `Data/ModelFamily.cls`: contract tables and registry. AD-11, AD-16, AD-20.
- `Audit.cls`:
  - `Parameter SOURCE = "OcuTalon"` and `TYPES = "Action,Approval,Pairing,Settings,MCP,Tool"`;
  - `Events() As %List` returns the six `"OcuTalon/<T>/<T>"` names;
  - `Write(type, data As %DynamicObject, description = "") As %Status` refuses any other type with an error naming it. Otherwise it returns `$SYSTEM.Security.Audit(SOURCE, type, type, data.%ToJSON(), description)`.
  - AD-17.
- `Installer.cls`:
  - `Run()` checks the namespace, then calls `RegisterAudit()`.
  - `RegisterAudit()` and `CheckAudit()` both call one private method, `AuditEvents(create As %Boolean)`. It reads `##class(OcuTalon.Bridge.Audit).Events()` before it switches to `%SYS`. Then it either creates each missing event (enabled) and enables each disabled one, or fails naming the first event that is missing or disabled.
  - This is the class's only `%SYS` method. AD-2, AD-3, AD-17.

OcuTalon (`src/ocutalon/cls/OcuTalon/`):
- **Messages:**
  - `Msg/Enum.cls`, `Msg/Item.cls`, `Msg/ItemDecision.cls`, `Msg/Notification.cls`, `Msg/Outbound.cls` and `Msg/Tick.cls`;
  - `Msg/Command.cls` (abstract, `Parameter RESPONSECLASSNAME = "OcuTalon.Msg.CommandResult"`);
  - `Msg/IncidentCommand.cls` and `Msg/CommandResult.cls`;
  - the ten verbs, `Msg/Command/{SetReminder,CancelReminder,ListReminders,StartWatch,StopWatch,Dismiss,SetDemoMode,Pair,Unpair,EndSession}.cls`.
  - AD-1, AD-14, AD-15, AD-18, AD-30, AD-32.
- **Tables:** `Data/{Session,AddressCounter,StatusMark,GuideState,BreakFeedRun,Pairing,Turn,SimMessage,Delivery,Reminder,Setting,BackgroundCheck,WatchMark,Incident,FailureGroup,FixRun}.cls`. AD-4, AD-12, AD-15, AD-18, AD-33.
  - `Delivery.Record(ownerRef, channel, channelMessageId, approvalRef) As %Status` returns an error that it isn't implemented yet. `Delivery.FindByApproval(approvalRef, channel, ownerRef) As %String` returns `""`. AD-14.
  - `Setting`:
    - `Parameter CACHESECONDS = 60`.
    - `Get(key, default = "") As %String`. A public key (`Public.Settings` `#KEYS` or `#READY`) is read from `Public.Settings.Get`, uncached. Any other key is read from the row through a per-process cache, `^||OcuTalon.Setting(key) = $ListBuild(value, present, $ZHorolog)`. An absent or empty value returns `default`.
    - `Seed(key, value) As %Status` writes only when the key is absent, refuses public keys, and drops its own cache entry.
    - AD-19.
- `Data/Time.cls` (AD-18):
  - `NowUtc()`;
  - `ToLocal(utc)`, which gives local `YYYY-MM-DDThh:mm:ss` in the instance zone, and `""` for empty or unreadable input;
  - `Zone()`, which gives TZ, or `UTC` when TZ is unset.
- `Live/Payload/Decision.cls`: contract table. AD-12.
- `Channel/Telegram/In.cls`: `Extends Ens.BusinessService` with `Parameter ADAPTER`; `ClassMethod Included() As %Boolean` returns `$Get(^OcuTalonTest("TelegramIncluded")) = 1`. AD-29.
- `Install/Step/Audit.cls`: `Run()` returns `##class(OcuTalon.Bridge.Installer).CheckAudit()`. AD-23.

Repository:
- `src/short-names.tsv`: a header `short<TAB>global<TAB>class<TAB>lane`, then the 22 registry rows under Design Notes. AD-3.
- `.gitattributes`: add `src/short-names.tsv merge=union`.

Tests:
- `src/ocutalon/cls/OcuTalon/Test/Contract.cls`: an abstract `%UnitTest.TestCase`.
  - `AssertContract(xdataName)` reads a JSON XData of the subclass, `{"<class>": {"super", "props": {"<Name>": "<type spec>"}, "indexes": {"<Name>": "<props>[ unique]"}}}`. It compares the primary superclass, the property set (excluding properties inherited from `%` and `Ens` classes), the types, the MAXLEN/SCALE and the indexes with the compiled dictionary.
  - `AssertSqlNames(class)` covers row 6.
- `Test/Msg/Contracts.cls`: rows 1, 2 and 14, and the decision payload.
- `Test/Bridge/Contracts.cls`: rows 1–3, 7 and 13.
- `Test/Data/Tables.cls`: rows 1, 4, 6 and 15.
- `Test/Data/Time.cls`: row 8, restoring the process TZ.
- `Test/Data/Setting.cls`: row 9.
- `docker/tests/test-storage.sh`: row 5. It starts nothing. Each rule first runs on a synthetic bad sample in a temporary folder. It prints one PASS or FAIL line per rule.
  - A class is storage-bearing when it isn't abstract and its `Extends` chain, followed through `src/`, reaches `%Persistent`, `%Library.Persistent`, `Ens.Request` or `Ens.Response`.
  - An abstract class carries whatever block the compiler gave it.
- `docker/tests/test-audit.sh`: rows 10–12, label `t04`. It uses `live_start`, then `wait_started_ready`, then `iris_script`, with a unique marker, a 540 s deadline and the EXIT trap.

**Acceptance Criteria:**
- Given both source trees loaded and compiled on slot A, when the five test classes and `Test.Install.PrivateData` run, then rows 1–4, 6–9 and 13–15 hold.
- Given the repository, when `test-storage.sh` runs, then the real tree passes and every synthetic violation fails, naming its file and rule (row 5).
- Given a first start in a throwaway project, when the installer runs, then rows 10–12 and 16 hold.
- Given `IRIS_IMAGE=iris-community:2026.3.0AI.154.0`, when `test-audit.sh` runs, then it passes.
- Given the storage blocks in the files, when the trees are loaded, compiled and exported again on slot A, then no tracked file changes.

## Spec Change Log

Rule 22 rulings made during implementation:
- Rule 22 ruling: what the stub `Channel.Telegram.In` declares as `Parameter ADAPTER` -> `Ens.InboundAdapter`, with a do-nothing `OnProcessInput` (rejected: an adapterless service, because AD-14 has TelegramIn long-poll `getUpdates` through an inbound adapter; the Telegram epic replaces the value).
- Rule 22 ruling: `test-install-start.sh` row 5 loaded all of `src/bridge/` into the plain namespace OCUPLAIN and expected it to compile -> it now loads only `OcuTalon/Bridge/Installer.cls` there and still expects the refusal that names the namespace (rejected: keeping the full load, which cannot compile there because the bridge's messages extend `Ens.Request` and `Ens.Response`, which a namespace without Interoperability lacks; and giving the messages another base, which contradicts AD-6 and the contract tables). The Interoperability half of row 5 still loads the whole bridge.
- Rule 22 ruling: the five earlier test files `Test/Install/{Registry,Users}.cls` and `Test/Web/{Install,Shell,SignIn}.cls` carry a blank line after their `/// --- ... ---` section comment that the exporter drops -> the blank line is removed, so AC5's round trip (89 files) changes no tracked file (rejected: leaving them, which makes the round trip modify files of Stories 0.2 and 0.3).
- Rule 22 ruling: `Boolean` properties -> `[ InitialExpression = 0 ]` (rejected: empty, because row 3 needs `Fallback` 0 on a new `Reply` and a JSON export should say `false`, not omit the key).
- Rule 22 ruling: the names of the indexes -> `<Property>Index`, and the properties joined for a composite one (`ItemIdKindIndex`, `ApprovalRefChannelOwnerRefIndex`), `RefIndex` for `Ref` (rejected: opaque or numbered names, which the contract XData would not read well).
- Rule 22 ruling: untyped names in the contract tables -> `OriginChannel` is Word, like `Channel`; `ItemId` is Ref everywhere, as the identifiers convention says (rejected: Name, which would let an id exceed 22 characters).
- Rule 22 ruling: the contract XData of `Test.Contract` -> adds an optional `sql` key (`{"Input": "InputText"}`) and compares `%JSONFIELDNAME` beside MAXLEN, SCALE, MINVAL and MAXVAL; an empty value is written `KEY=` (rejected: leaving the SQL names and the JSON keys to a separate test each, which two classes would then have to keep in step with the property lists).
- Rule 22 ruling: where row 4 reads the registry -> `Test.Data.Tables` carries the 22 rows as its `Registry` XData (slot A cannot read `src/short-names.tsv`; `test-storage.sh` keeps the file and the classes in step) and asserts that every persistent class in `OcuTalon.Data` and `OcuTalon.Bridge.Data` has a row (rejected: a registry class, per the Design Notes; and scanning every package, which would make Lane A's later tables edit a Lane B test).
- Rule 22 ruling: the resolution check in row 4 -> compares where each class's own `DataLocation` and `IndexLocation` resolve with where the private sample `^OcuTalonP.Zz` resolves, which `PrivateData.Run()` proves is `OCUTALON_PRIVATE` (rejected: reading `Config.Databases`, which OCUTALON cannot see, or switching to `%SYS` in a test).
- Rule 22 ruling: `Data.Time.ToLocal` accepts only the `Utc` form (`YYYY-MM-DDThh:mm:ssZ`) and gives `""` for anything else, a time without the `Z` included (rejected: reading a zone-less time as UTC, which hides a caller that forgot the zone).
- Rule 22 ruling: `Bridge.Audit.Write` with a `data` that is not a dynamic object -> an error status (rejected: letting `<INVALID OREF>` escape from a business host).
- Rule 22 ruling: the poll of row 11 stays at the default 120 s, with `OCUTALON_AUDIT_POLL` to override it: the row was readable after 53 s, 72 s (Health) and 66 s (non-Health) (rejected: a shorter poll, which the measured delay does not allow).

Rule 22 rulings made at review (October 19):
- Rule 22 ruling: `Bridge.Audit.Write` accepts only an instance of `%Library.DynamicObject` -> any other value (a string, a `%DynamicArray`, a stream) gets an error status that says the data must be a dynamic object, before anything is written (rejected: `$IsObject` alone, which let a non-dynamic object throw `<METHOD DOES NOT EXIST>` out of the audit writer).
- Rule 22 ruling: the return of `Write` for an unregistered event stays the raw `0` of `$SYSTEM.Security.Audit` -> the Tasks fix the return value and the doc comment records the measurement (rejected: wrapping it in an error status that names the event, which changes specified behavior; reopen if Story 3.7's error text needs the event name).
- Rule 22 ruling: `Data.Setting.Get("")` gives the default and `Seed("", ...)` returns an error status -> an empty key never reaches the per-process cache, where it would raise `<SUBSCRIPT>` (rejected: leaving it to callers).
- Rule 22 ruling: `Install.Step.Audit` is tested on a disabled event, not only a deleted one -> `test-audit.sh` row 12 now has `Step.Audit.Run()` fail, naming `OcuTalon/Tool/Tool` and leaving it disabled, before `Bridge.Installer.Run()` re-enables it (rejected: leaving the "is disabled" branch unexercised).
- Rule 22 ruling: `Test.Contract` also compares the full list of superclasses in order, whether the class is abstract (`"abstract": 1` in the contract; a class is not abstract unless it says so), and an initial value of 0 on every `%Boolean` property -> the contract tests pin the shapes the Rule 22 rulings above chose (rejected: the primary superclass only, and the `Reply.Fallback` check alone). A compiled `%String` without `MAXLEN` reports `50`, not `""`, so the existing `MAXLEN=` comparison already tells an unlimited string from a default one (measured on slot A).
- Rule 22 ruling: the counts in `Test.Data.Tables` (22 registry rows, 22 tables, 45 persistent classes) become floors -> a later story that adds a persistent class edits its own XData, not a count in a shared test (rejected: exact counts, which make every later table a cross-lane edit).
- Rule 22 ruling: `test-storage.sh` gains `registry-param` (a storage-bearing class that does not reach `Ens.Request` or `Ens.Response` must set `Parameter DEFAULTGLOBAL`, AD-3) and `scan` (the real-tree scan must read `src/short-names.tsv` and at least one class and end without an error) -> each has a bad sample (rejected: leaving the missing-parameter hole to the install check, which sees only classes that already use the private prefixes; and letting a lost registry file print six PASS lines).
- Rule 22 ruling: the failure line of the row 11 poll states the budget the run's deadline left -> a truncated poll no longer reads as the full 120 s (rejected: extending the deadline, which the 600 s call cap does not allow).

## Review Triage Log

### 2026-10-19 — Review pass
- verdicts: 54 findings — high 0, medium 18, low 32, false 3, maybe-false 1
- findings:
  - `[medium]` `[patch]` Blind Hunter: `Bridge.Audit.Write` guards with `$IsObject` only, so a stream or `%DynamicArray` passes and `%ToJSON` throws — evidence: `Audit.cls` line 33 admits any object. Fixed: the guard compares `$ClassName(data)` with `%Library.DynamicObject`; `TestAuditApi` writes a string, a `%DynamicArray` and a stream and expects the error text (mutation: guard reduced to `$IsObject` -> sample 2 red and sample 3 throws).
  - `[low]` `[reject]` Blind Hunter: the unregistered-event result of `Write` is a raw `0` and nothing asserts it — the Tasks fix the return value and Task 0 records it in the doc comment; `test-audit.sh` prints it as INFO; reopen_if Story 3.7 needs the event named in the error text.
  - `[medium]` `[patch]` Blind Hunter: `CheckAudit`'s "is disabled" branch is never exercised — evidence: row 12 only deleted an event for `Step.Audit`. Fixed: row 12 runs `Step.Audit` on a disabled `OcuTalon/Tool/Tool` (mutation: `If exists && (event.Enabled || 'create) Continue` -> `test-audit.sh` row 12 red, 2 of 5 values differ).
  - `[medium]` `[defer]` Blind Hunter: nothing in the install or `Write` path reports that instance-wide auditing is off — real; AD-17 and the spec bar OcuTalon from changing the setting and Task 0 only measured the images; surfacing it is a product call for the security overview / Story 3.7 (deferred, see `deferred:`).
  - `[medium]` `[patch]` Blind Hunter: `TestSqlNames` pins 45 persistent classes — evidence: any later persistent class turns a shared Lane B test red. Fixed: floors (`>=`) in `Test.Data.Tables` (45, 22, 22).
  - `[low]` `[patch]` Blind Hunter: `Bridge.Msg.Result` being abstract is not asserted — fixed: `"abstract": 1` in the contract, compared by `Test.Contract` (mutation: `[ Abstract ]` removed from `Result` -> `Test.Bridge.Contracts` `TestContracts` red).
  - `[low]` `[patch]` Blind Hunter: `Bridge.Msg.DecisionPayload` has no `%JSON.Adaptor` coverage — fixed: the contract compares the full superclass list and `TestDecisionPayloadJson` imports and exports (mutation: `%XML.Adaptor` added to `Extends` -> `TestContracts` red). Dropping `%JSON.Adaptor` already fails the compile (`%JSONFIELDNAME` not declared).
  - `[low]` `[patch]` Blind Hunter: the `Boolean` `InitialExpression = 0` ruling is tested only for `Reply` — fixed: `Test.Contract` asserts it on every `%Boolean` of every contract class (mutation: clause removed from `Live.Payload.Decision.Fallback` -> `Test.Msg.Contracts` `TestContracts` red).
  - `[low]` `[patch]` Blind Hunter: `AgentStep.DurationMs` carries the turn-totals doc comment — fixed: the comment says the step.
  - `[medium]` `[patch]` Blind Hunter: `test-storage.sh` does not require `DEFAULTGLOBAL` on a non-message persistent class — evidence: only the reverse direction (parameter with no row) was checked, and `PrivateData` sees only classes that already use the private prefixes. Fixed: rule `registry-param` with a bad sample (mutation: the rule removed -> `FAIL registry-param: the checker does not flag the sample no-param-new`).
  - `[low]` `[reject]` Blind Hunter: the registry's `short` is not checked against the global's suffix — `wontfix-theoretical`: `short` has no consumer, and the uniqueness of short name, global and class is enforced; reopen_if a tool reads `short` to build a global.
  - `[low]` `[patch]` Blind Hunter: the row 11 poll budget is shared with the build and start deadline — fixed: the failure line states the budget the deadline left (the poll itself is capped by the 600 s call limit).
  - `[medium]` `[patch]` Edge Case Hunter: `Write` accepts any object — same root cause as the first Blind Hunter finding; fixed there.
  - `[medium]` `[patch]` Edge Case Hunter: `Setting.Get("")` / `Seed("", ...)` raise `<SUBSCRIPT>` on `^||OcuTalon.Setting("")` — confirmed on slot A (red run, `<SUBSCRIPT>Get+5`). Fixed: `Get` gives the default, `Seed` returns an error status; `TestEmptyKey` (mutation: guard removed -> `TestEmptyKey` red).
  - `[low]` `[reject]` Edge Case Hunter: two processes seeding one absent key lose on the unique index — `Seed` is the install-time writer and the after-start install runs one process; the fix adds a branch; reopen_if two processes seed at once.
  - `[false]` `[reject]` Edge Case Hunter: `MAXLEN=` in the contract matches a property with no `MAXLEN` — measured on slot A: a plain `%String` property reports `MAXLEN` `50` (defined), a Long reports `""`, so a property that lost `MAXLEN = ""` fails the comparison.
  - `[low]` `[reject]` Edge Case Hunter: `AssertMessageExtent` / `ReadContracts` throw instead of recording a failed assertion when a class or XData is missing — the method still ends red as an error; the guard adds branches to a test helper.
  - `[low]` `[reject]` Edge Case Hunter: the installer ignores the lookup status of `Security.Events.Exists` — a failed lookup is followed by `Create`, which reports its own error; unlikely and the fix adds branches.
  - `[low]` `[reject]` Edge Case Hunter: `AuditEvents` has no `Try`/`Catch` — the registry wraps every step and the standalone bridge install is run by an administrator; reopen_if the bridge's own listing installs without that.
  - `[medium]` `[patch]` Edge Case Hunter: `test-storage.sh` does not require `DEFAULTGLOBAL` on a non-message persistent class — same root cause as the tenth Blind Hunter finding; fixed there.
  - `[low]` `[reject]` Edge Case Hunter: the `abstract` pattern of `test-storage.sh` also matches `Abstract` inside a keyword value — theoretical: no class does; reopen_if one does.
  - `[low]` `[reject]` Edge Case Hunter: `DecisionPayload` keeps `%JSONIGNORENULL` 0, so an empty string imports as `$c(0)` — Epic 1's checker (AD-8) owns the import and chooses the parameters; an empty outcome is an `invalid` fallback either way.
  - `[low]` `[reject]` Edge Case Hunter: `Live.Payload.Decision` keeps `%JSONNULL` 0, so unset keys are omitted — Story 0.5 writes the TypeScript interface and the publisher and decides optional against null.
  - `[low]` `[reject]` Edge Case Hunter: `Item.Sender` / `Subject` have no `TRUNCATE` — the contract tables fix them as `Line` (MAXLEN 1000); intake truncates before it sends.
  - `[low]` `[reject]` Edge Case Hunter: enumerated properties have no `VALUELIST` or default — a Rule 22 ruling in this spec (plain `%String`; the values live in `Msg.Enum`).
  - `[medium]` `[patch]` Edge Case Hunter: `TestSqlNames` pins 45 — same root cause as the fifth Blind Hunter finding; fixed there.
  - `[low]` `[reject]` Edge Case Hunter: `Zone()` and `ToLocal` can disagree when TZ is invalid — the spec defines `Zone()` as TZ or `UTC`; an invalid TZ is theoretical.
  - `[low]` `[reject]` Edge Case Hunter: a `Ref` in a unique index with the default string collation (`SQLUPPER`, inference) compares case-insensitively — about 110 of 128 random bits remain and no lookup is helped; the fix touches about 30 properties.
  - `[low]` `[reject]` Edge Case Hunter: raw `0` from `Write` — same as the second Blind Hunter finding.
  - `[false]` `[reject]` Verification Gap: the `Long`/`Json` unlimited `MAXLEN` is not pinned — disproved by the slot A measurement above (a default `%String` reports `50`).
  - `[medium]` `[patch]` Verification Gap: the "Write matches a type exactly" assertion cannot fail — fixed: it asserts the error text names `'action'` (reasoned: a case-insensitive guard would otherwise pass).
  - `[medium]` `[patch]` Verification Gap: the non-object branch of `Write` has no test — fixed with the three samples above.
  - `[medium]` `[patch]` Verification Gap: the `CheckAudit` disabled branch has no test — fixed with the row 12 check above.
  - `[low]` `[patch]` Verification Gap: `DecisionPayload` is compared on its primary superclass only and has no JSON round trip — fixed above.
  - `[low]` `[patch]` Verification Gap: the `Boolean` initial value and the JSON `false` are pinned through `Reply.Fallback` only — fixed above.
  - `[low]` `[patch]` Verification Gap: `Setting.Seed` writing `UpdatedAt` is not asserted — fixed: `TestSeedOnlyWritesAnAbsentKey` matches the `Utc` form.
  - `[medium]` `[patch]` Verification Gap: the real-tree leg of `test-storage.sh` can pass without scanning anything — fixed: `check_tree` reports the `scan` rule when no class is listed or the scan exits non-zero, and `rows == 0` reports it too (mutation: the registry moved away -> `FAIL scan`, exit 1, where it printed six PASS lines).
  - `[medium]` `[defer]` Verification Gap: AC5 (storage blocks equal the compiler's output) is verified by a one-off procedure, not a recurring check — real; the spec scopes AC5 as `(once)` and Story 0.7 owns the CI wiring (deferred, see `deferred:`).
  - `[low]` `[patch]` Verification Gap: `NewBusy` "nothing else is set" is pinned for the listed fields only — fixed: `TestNewBusy` asserts every other flag is 0 and every other field empty (mutation: `NewBusy` sets `ToolsRun` -> `TestNewBusy` red).
  - `[medium]` `[patch]` Verification Gap, other: the `Write` guard admits any object — same root cause as the first Blind Hunter finding.
  - `[medium]` `[patch]` Verification Gap, other: hard-coded counts in `Test.Data.Tables` — same root cause as the fifth Blind Hunter finding.
  - `[low]` `[patch]` Verification Gap, other: `TestNewBusy` does not check the status of its `%DeleteId` — fixed: asserted.
  - `[low]` `[reject]` Verification Gap, other: no check of the AD-3 `%SYS` switch list or the AD-2 bridge boundary — neither an acceptance criterion nor an AD asks for one (AD-3 names a CI check for duplicate `DEFAULTGLOBAL` only), and `test-install-start.sh` row 5 compiles the bridge alone.
  - `[false]` `[reject]` Verification Gap, other: rows with no `mutation:` line — Rule 19 asks for one demonstrated mutation per acceptance criterion, and AC1 to AC5 each have lines.
  - `[low]` `[reject]` Intent Alignment: the contract oracle is a restatement in the test's XData — the spec asks for exactly that (a JSON XData of the subclass); the auditor compared the spec tables with the classes and the XData and found no mismatch.
  - `[low]` `[reject]` Intent Alignment: row 4 compares destinations with the private sample instead of the literal `OCUTALON_PRIVATE` — `GetGlobalDest` returns a directory and `PrivateData.Run()` proves the sample resolves to the private database (Rule 22 ruling logged); the two proofs are equivalent.
  - `[low]` `[reject]` Intent Alignment: the audit success path, read-back and registration are exercised only in `test-audit.sh` — the Matrix assigns rows 10 to 12 there.
  - `[maybe-false]` `[defer]` Intent Alignment: `ToLocal` uses the process TZ while AD-18 says the container's TZ, and no test runs it in a production job — if true (medium), a reminder shows the wrong local time; settling it takes a throwaway start with a compose-level `TZ` and a `ToLocal` call from a production job (deferred, see `deferred:`).
  - `[low]` `[reject]` Intent Alignment: slot A footprint beyond `Zz<n>` and `TelegramIncluded` — the Matrix rows 3 and 9 name the `Reply` save and `onlineDemo`; the test deletes the reply and restores the setting, and the process TZ is restored after every test.
  - `[low]` `[reject]` Intent Alignment: five earlier test files lose one blank line and `test-install-start.sh` row 5 loads one class into the plain namespace — logged Rule 22 rulings; behavior unchanged and the refusal is still tested.
  - `[medium]` `[defer]` Intent Alignment: storage blocks are checked against the compiler only by a one-off run — same root cause as the AC5 finding above.
  - `[medium]` `[patch]` Intent Alignment: pinned counts of 45 and 22 — same root cause as the fifth Blind Hunter finding.
  - `[low]` `[reject]` Intent Alignment: `test-audit.sh` also asserts `AuditEnabled` is 1 and that no seventh `OcuTalon` event exists — stricter than row 10 and harmless; AD-17 fixes six types.
  - `[low]` `[patch]` Intent Alignment: the `AgentStep.DurationMs` comment — same root cause as the ninth Blind Hunter finding.

## Design Notes

**ADs:**
- AD-2: bridge separation.
- AD-3: private records, the `%SYS` switch list, the short-name registry.
- AD-5: storage blocks, append-only.
- AD-6: Request, responses, `Busy`.
- AD-11 and AD-16: `ApprovalRequest`, `DryRun`.
- AD-14: Item, `Delivery`.
- AD-15: Incident, `IncidentCommand`.
- AD-17: audit.
- AD-18: `Data.Time`.
- AD-19: `Setting.Get`.
- AD-20: `Decision`, `Usage`, `Price`.
- AD-22 and AD-23: tests, the Audit step.
- AD-24: no table extends a message base.
- AD-26: `TraceSessionId`, trace targets.
- AD-29, AD-30, AD-32 and AD-33: the contract list, lanes and owners.
- The conventions rows.

**Type shorthand:**
- `Ref` and `Owner`: `%String(MAXLEN = 22)`. An `Owner` is a session `Ref`, `instance` or `eval`.
- `Utc`: `%String(MAXLEN = 20)`, `YYYY-MM-DDThh:mm:ssZ`. `Local`: `%String(MAXLEN = 19)`.
- `Word`: `%String(MAXLEN = 32)`, an enumeration value or short code. `Name`: `%String(MAXLEN = 128)`. `Line`: `%String(MAXLEN = 1000)`.
- `Long` and `Json`: `%String(MAXLEN = "")`.
- `Sum`: `%String(MAXLEN = 80)`.
- `Hdr`: `%Integer`, an Ens header or session id.
- `Int`: `%Integer`. `Bool`: `%Boolean`.
- `Usd`: `%Numeric(SCALE = 6)`. `Rate`: `%Numeric(SCALE = 4)`. `Conf`: `%Numeric(MINVAL = 0, MAXVAL = 1, SCALE = 2)`.

In every table below:
- A property with no type follows its name: `Ref` and `*Ref` are Ref (`OwnerRef` is Owner), `*At` are Utc, and `State`, `Kind`, `Outcome` and `FallbackReason` are Word.
- Every persistent table with `Ref` also has `Index RefIndex On Ref [ Unique ]`.

Two groups recur:
- **+Verdict** = `DecisionRef` Ref, `Outcome` Word, `Reasons` Long (one reason per line), `Confidence` Conf, `Fallback` Bool, `FallbackReason` Word.
- **+Totals** = `InputTokens`, `OutputTokens`, `CacheReadTokens`, `CacheWriteTokens`, `AgentStepCount`, `DurationMs` (Int), `CostUSD` Usd, `Model` Name.

**Contract tables, `OcuTalon.Msg`** (Lane B; all are `Ens.Request` unless noted):

| Class | Properties |
|---|---|
| `Item` | `ItemId` Ref, `SourceItemId` Name, `SessionRef` Owner, `Channel` Word, `Provenance` Word, `Text` Long, `Sender` Line, `Subject` Line, `FromGuide` Bool, `CatalogKey` Name, `Slots` Json |
| `ItemDecision` | `ItemId` Ref, `SourceItemId` Name, `OwnerRef` Owner, `Channel` Word, `Summary` Sum, `DecisionRef` Ref, `Outcome` Word, `Fallback` Bool, `FallbackReason` Word, `CatalogKey` Name, `Slots` Json |
| `Notification` | `SessionRef` Ref, `ChatRef` Ref, `Kind` Word, `CatalogKey` Name, `Slots` Json, `ApprovalRef` Ref, `IncidentRef` Ref, `DecisionRef` Ref |
| `Outbound` | `SessionRef` Ref, `ChatRef` Ref, `OriginChannel` Word, `Text` Long, `CatalogKey` Name, `Slots` Json, `CheckRows` Json |
| `Tick` | `TickAt` Utc, `PreviousTickAt` Utc, `CatchUp` Bool |
| `Command` (abstract) | `Origin` Word, `IdempotencyKey` Name, `SessionRef` Ref |
| `IncidentCommand` (extends `Command`) | `Verb` Word (`Parameter VERBS = "dismiss,closeForReplay,closeQuiet"`), `IncidentRef` Ref |
| `Command.SetReminder` | `Text` Line, plus exactly one of `DueAt` Utc, `DelaySeconds` Int or `LocalDueAt` Local |
| `Command.CancelReminder` / `Dismiss` | `ReminderRef` Ref / `IncidentRef` Ref |
| `Command.ListReminders` / `EndSession` | only the inherited fields |
| `Command.StartWatch` / `StopWatch` | `Namespace` Name, `Production` Name, and `DisplayName` Name on start |
| `Command.SetDemoMode` | `DemoMode` Bool |
| `Command.Pair` / `Unpair` | `CodeHash` Name and `ChatRef` Ref / `ChatRef` Ref |
| `CommandResult` (`Ens.Response`) | `Ok` Bool, `Message` Line, `Outcome` Word, `Ref` Ref, `DueAt` Utc, `Data` Json |
| `Enum` (not a message) | `OUTCOME`, `PROVENANCE`, `REQUESTKIND`, `FALLBACKREASON`, `INCIDENTSTATE`, `INCIDENTOPENVARIANT`, `APPROVALSTATE`, `APPROVALKIND`, `NOTIFICATIONKIND`, `CHECKRESULT`, `CHANNEL`, `ORIGIN`, each a comma list equal to the conventions row (FallbackReason: AD-8's twelve; NotificationKind: AD-32's eleven; Origin: AD-1's six) |
| `Live.Payload.Decision` (`%RegisteredObject`, `%JSON.Adaptor`) | `Ref`, `Kind`, `ItemId`, `ItemSummary` Sum, `Outcome`, `Reasons` Long, `Confidence` Conf, `Fallback` Bool, `FallbackReason`, +Totals, `RecordedAt`, `TraceHeaderId` Hdr (the `Decision`'s `TraceSessionId`), `TraceNamespace` Name; each JSON key is the property name with a lower-case first letter |

**Contract tables, the bridge** (Lane A):

| Class | Properties |
|---|---|
| `Msg.Request` | `Kind` Word, `Provenance` Word, `Input` Long (SQL `InputText`), `ItemId` Ref, `Summary` Sum, `DecisionRef` Ref, `OwnerRef` Owner, `TraceRef` Ref, `Channel` Word, `ThreadSessionId` Hdr, `SessionMode` Word, `SeedText` Long, `SystemNote` Long |
| `Msg.Result` (abstract, `Ens.Response`) | +Verdict, +Totals |
| `Msg.DecisionResponse` (extends `Result`) | `Payload` Json (the checked decision or diagnosis reply) |
| `Msg.Reply` (extends `Result`) | `Text` Long, `Tainted`, `SessionRotated`, `ToolsRun`, `SessionBroken`, `Busy` (Bool), `HostData` Json |
| `Msg.DecisionPayload` (`%RegisteredObject`, `%JSON.Adaptor`) | `Outcome` Word (`outcome`), `Reasons` `list Of %String(MAXLEN = 1000)` (`reasons`), `Confidence` Conf (`confidence`) |
| `Msg.AgentStep` | `DecisionRef` Ref, `Position` Int, `StepKind` Word (`model`, `tool`), `Label` Line, `Summary` Line, `DurationMs` Int, `Status` Word (`ok`, `denied`, `error`), `EstimatedTokens` Int |
| `Msg.Enum` | `OUTCOME`, `PROVENANCE`, `REQUESTKIND`, `FALLBACKREASON`, `APPROVALSTATE`, `APPROVALKIND`, `CHANNEL`, equal to `OcuTalon.Msg.Enum` |
| `Data.Decision` | `Ref`, `Kind` Word, `ItemId` Ref, `OwnerRef`, `Summary` Sum, `Outcome`, `Reasons`, `Confidence`, `Fallback`, `FallbackReason`, `Payload` Json, +Totals, `TraceSessionId` Hdr, `RecordedAt` Utc. Indexes: (`ItemId`, `Kind`) unique; `OwnerRef` |
| `Data.ApprovalRequest` | `Ref`, `Kind` Word, `IncidentRef` Ref, `OwnerRef`, `State` Word, `DryRun` Json, `ToolName` Name, `ToolArguments` Json, `RequiredRole` Name, `ResultTarget` Name, `TraceRef` Ref, `RaisedAt`, `ExpiresAt` Utc, `AnsweredAction`, `AnsweredChannel` Word, `AnsweredBy` Name, `AnsweredAt` Utc, `Result` Word (`done`, `failed`, `interrupted`), `FinishedAt` Utc. Indexes: `IncidentRef`; `OwnerRef` |
| `Data.Usage` | `DecisionRef`, `ItemId` Ref, `Kind`, `Agent`, `Channel` Word, `OwnerRef`, `Model` Name, `RequestCount`, `InputTokens`, `OutputTokens`, `CacheReadTokens`, `CacheWriteTokens`, `LargestRequestTokens` Int, `CostUSD` Usd, `Estimated` Bool, `RecordedAt` Utc. Indexes: `DecisionRef`; `OwnerRef` |
| `Data.Price` | `Model` Name (unique), `InputPerMTok`, `OutputPerMTok`, `CacheReadPerMTok`, `CacheWritePerMTok` Rate, `LongThresholdTokens` Int, `LongInputPerMTok`, `LongOutputPerMTok` Rate |
| `Data.ConversationLink` / `Data.ModelFamily` | `OwnerRef`, `Agent` Word, `SessionId` Name, with (`OwnerRef`, `Agent`) unique / `Family` Word (unique), `ModelPrefix`, `CapKey`, `EffortKey` Name |

**Contract tables, `OcuTalon.Data`** (`%Persistent`):

| Class (lane) | Properties; indexes |
|---|---|
| `Session` (B) | `Ref`, `TraceRef` (unique), `IrisUser` Name (indexed), `CreatedAt` |
| `AddressCounter` (B) | `AddressHash` Name (indexed), `CreatedAt` |
| `StatusMark` (B) | `Mark` Name (unique), `Value` Line, `RecordedAt` |
| `GuideState` (B) | `SessionRef` (unique), `RunEpoch` Int, `TraceOpened` Bool |
| `BreakFeedRun` (B) | `SessionRef` (indexed), `State` (`sending`, `sent`), `StartedAt` |
| `Pairing` (B) | `Ref` (the `ChatRef`), `SessionRef` (indexed), `ChatId` Word (indexed), `DisplayName` Name, `CreatedAt` |
| `Turn` (B) | `Ref`, `SessionRef` (indexed), `State` (`queued`, `running`, `done`), `Channel` Word, `FromGuide` Bool, `TriageDecisionRef`, `TurnDecisionRef`, `CreatedAt` |
| `SimMessage` (B) | `Ref`, `SessionRef` (indexed), `Kind` (`phone`, `mailbox`), `Direction` Word (`in`, `out`), `ItemId` Ref (indexed), `CreatedAt` |
| `Delivery` (B) | `OwnerRef` Owner, `Channel` Word, `ChannelMessageId` Name, `ApprovalRef`, `RecordedAt`; index (`ApprovalRef`, `Channel`, `OwnerRef`) |
| `Reminder` (B) | `Ref`, `SessionRef` (indexed), `Text` Line, `DueAt`, `State` (`pending`, `fired`, `cancelled`), `Late` Bool, `CreatedAt` |
| `Setting` (B) | `Key` Name (unique), `Value` Line, `UpdatedAt` |
| `BackgroundCheck` (A) | `Ref`, `SessionRef` (indexed), `Kind` (`production`), `Namespace`, `Production`, `DisplayName`, `AskedBy` Name, `NextDueAt`, `LastRunAt`, `Result` Word, `Finding` Line, `LastRunHeaderId` Hdr; index (`Namespace`, `Production`) |
| `WatchMark` (A) | `Namespace`, `Production` Name; (`Namespace`, `Production`) unique |
| `Incident` (A) | `Ref`, `OwnerRef` Owner (indexed), `Namespace`, `Production` Name, `State`, `OpenVariant` Word, `NoticedAt` (empty until the notice), `Count` Int (SQL `FailureCount`), `NoticeCount` Int, `FirstAt`, `LastAt`, `ItemNoun` Json (`{"one","other"}`), `Cause` Line, `CauseCategory` Word, `Element` Name, `FixSummary` Line, `Fallback` Bool, `FallbackReason` Word, `DecisionRef`, `TraceHeaderId` Hdr, `ClosedAt` |
| `FailureGroup` (A) | `IncidentRef` (indexed), `ItemName` Name, `ErrorPattern` Line |
| `FixRun` (A) | `ApprovalRef` (indexed), `IncidentRef` (indexed), `StartedAt` |

**Registry rows** (`src/short-names.tsv`, short = global suffix):
- Lane A, under `^OcuTalonBP.`: `Decision`, `Approval` (ApprovalRequest), `Usage`, `Price`, `ConvLink` (ConversationLink), `ModelFamily`.
- Lane A, under `^OcuTalonP.`: `Check` (BackgroundCheck), `WatchMark`, `Incident`, `FailGroup` (FailureGroup), `FixRun`.
- Lane B, under `^OcuTalonP.`: `Session`, `AddrCount` (AddressCounter), `StatusMark`, `Guide` (GuideState), `BreakFeed` (BreakFeedRun), `Pairing`, `Turn`, `SimMsg` (SimMessage), `Delivery`, `Reminder`, `Setting`.
- Short names are unique across the whole file.

**Rule 22 rulings:**
- **What the tables cover:** which properties does Epic 0 fix? → The cross-lane ones (AD-33: "Epic 0 fixes every property used across lanes"), plus the identity columns the sources name. The owning lane appends the rest, which append-only storage allows. Rejected: guessing every area-internal column now.
- **Verb class names:** → `StartWatch`, `StopWatch`, `Dismiss`, `SetDemoMode`, `Pair`, `Unpair`, `EndSession`. Story 2.3 routes `OcuTalon.Msg.Command.<Verb>` by class. Rejected: one class with a `Verb` property.
- **The IRIS user on commands:** → none. `WatchOps` reads it from the `Session` row (AD-4: messages carry `SessionRef`, never a user name). Rejected: an `IrisUser` property on `StartWatch`.
- **Enumeration-typed properties:** → plain `%String`; the values live only in `Msg.Enum`. Rejected: `VALUELIST` copies on about 30 properties.
- **The bridge's enumerations:** → the seven its own contracts use, with a test pinning them equal to OcuTalon's. Rejected: all twelve, because `IncidentState` and the others are OcuTalon's concepts.
- **Reasons:** → newline-separated `Long` on messages and rows, and a JSON list in `DecisionPayload`.
- **Times:** → second-precision `Utc`, the form `Public.Settings` writes, so string order is time order. Rejected: mixed millisecond forms.
- **Shared bases:** → `Bridge.Msg.Result` for `DecisionResponse` and `Reply`, and `IncidentCommand` extends `Command`. Its verbs are a parameter on it, because the conventions' enumeration row is exact. Rule 2.
- **SQL reserved words:** → keep the spine's property names and add `SqlFieldName` (`Input` becomes `InputText`, `Count` becomes `FailureCount`). Rejected: renaming the spine's properties.
- **The registry:** → `src/short-names.tsv`, union-merged, checked by a shell test (slot A can't read the repository). Rejected: a registry class, which would put both lanes in one class's XData.
- **The audit events:**
  - The events are `OcuTalon/<T>/<T>`.
  - `Bridge.Installer`, in its one `%SYS` method, creates them from `Bridge.Audit.Events()`. This reconciles AD-17's "it registers" with AD-3's switch list, and AD-2 needs the bridge's own installer to register them.
  - `Step.Audit` checks them. The events are structural: they are re-enabled at every start.
  - OcuTalon never changes instance auditing.
  - Rejected: `Bridge.Audit` switching namespace (AD-3), and `Step.Audit` registering a second time.
  - **VETO WINDOW** (security posture), for the lead's FYI.
- **The decision payload:** → created here, because the AC fixes `ItemId` and `ItemSummary` on it. It carries the model id, not a display name (conventions: display names live in the catalog and the web app). Its JSON keys are camelCase, like the spine's other JSON. 0.5 adds its TypeScript interface. Rejected: leaving it to 0.5, which would drop an AC clause.
- **Declined here, with their owners:**
  - `Digest.Data.Item` → 1.12 (area-internal, not `OcuTalon.Data`);
  - `Bridge.Time` → 1.4;
  - `Pairing`'s code fields → 10.3;
  - `Data.Time.FromLocal` → 8.3;
  - `Live.Event` → 0.5.
- **The `Delivery` stubs:** → `Record` returns an error and `FindByApproval` returns `""`, so a caller can't mistake the stub for a recorded delivery.
- **`Setting`:** → product keys are dotted (`digest.time`, Story 17.x). Public keys are delegated uncached. The cache is per process, for 60 s. `Seed` is the install-time writer.
- **Catalog placeholder:** → none needed. `CatalogKey` and `Slots` are strings, so nothing needs a catalog class to compile.

**Spine updates for the lead (Rule 20):**
- AD-17: "registered by `OcuTalon.Bridge.Installer`'s one `%SYS` method from `Bridge.Audit.Events()`".
- Conventions, payload JSON keys: camelCase.
- Conventions, times: `YYYY-MM-DDThh:mm:ssZ`.
- Conventions, SQL reserved words: handled with `SqlFieldName`.
- AD-3: the registry's path is `src/short-names.tsv`.

**Reuse (Rule 2):**
- **Copies the ADs force:**
  - `Data.Time.NowUtc` copies `Public.Settings.UtcNow` (AD-3: the public package can't call `Data.Time`);
  - `Bridge.Msg.Enum` copies part of `Msg.Enum` (AD-2), with a test pinning them equal.
- **Reused as they are:**
  - `Setting.Get` uses `Public.Settings.#KEYS`, `#READY` and `Get`;
  - row 4 uses `PrivateData.StorageGlobals`;
  - `test-audit.sh` uses `lib-live.sh`;
  - the fixture counter follows `Test.Install.Registry`;
  - one `Test.Contract` base serves three test classes.
- **One copy with a reason:** `test-storage.sh` copies `test-boundaries.sh`'s 10-line bad-sample runner, because that script has no library and sharing it would change it for no gain.

**Integration ACs:**
- `PrivateData` (consumer, Story 0.2) finds and passes every new private global (row 4).
- The installer (`Bridge.Installer`, `Step.Audit`) registers `Bridge.Audit`'s events, and `Write`'s entry is read back from the IRIS audit log (rows 10–12).
- `Setting.Get` serves `Public.Settings`' value (row 9).
- The after-start install compiles the whole package (row 16).

**Consumes:**
- 0.2: the registry order, `Step`, `PrivateData`, `Public.Settings`, `lib-live.sh` and `test-install-start.sh`.
- 0.1: `merge.cpf`'s private mappings.

**Consumed-by:**
- **0.5:** the TypeScript interface for `Live.Payload.Decision`; it creates every other payload. It also decides how `/state` builds incident views from `Incident`, and where the session epoch lives on `Session`.
- **0.6:**
  - `TelegramIn` reuses `Channel.Telegram.In`;
  - `Commands.Submit` sends the `Command` subclasses;
  - the items use these messages;
  - the `Demo` step reads demo mode through `Setting.Get` and its seed.
- **0.7:** the CI checks read `src/short-names.tsv` and run `test-storage.sh`.
- **0.9:** `Catalog.Render` uses `Data.Time`; `CatalogKey` names its keys.
- **Epic 1:** `Decide` uses `Request`, `Reply.NewBusy`, `DecisionResponse`, `Decision`, `Usage`, `Price`, `ModelFamily` and `ConversationLink`. 1.4 adds `Bridge.Time`; 1.12 adds `Digest.Data.Item`.
- **Epic 2:** 2.3 uses the verbs, 2.6 the decision payload, 2.7 `Delivery`.
- **3.7:** the audit shapes, redaction and read-back.
- **Epics 5 to 7:** `Incident`, `FailureGroup`, `FixRun`, `BackgroundCheck` and `WatchMark`.
- **8.3:** `Reminder` and `FromLocal`.
- **10.3 and Epic 12:** `Pairing`, `StatusMark` and `Included()`.

**Size, and where to split it (for the lead):** if one implement pass can't carry this story, split it:
- **0.4:** `OcuTalon.Msg`, `Bridge.Msg`, both enumeration classes, `Ids`, `Live.Payload.Decision` and `Telegram.In`; rows 1–3, 7 and 14.
- **0.10:** `Bridge.Data`, `OcuTalon.Data`, the registry and `test-storage.sh`, `Time`, `Setting` and audit; rows 4–6, 8–13, 15 and 16.

**Ledger inbox:** none.

## Verification

**Commands:**
- `(loop)` Check the target with `iris_server_info` (`server: ocutalon-slot-a`). Expected: build 154.
- `(loop)` `iris_doc_load` with `server: ocutalon-slot-a`, `namespace: OCUTALON`, `compile: true`, `flags: "ck"`, as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- `(loop)` `iris_execute_tests` at class level, one call each, each waiting for the one before: `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Bridge.Contracts`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Data.Time`, `OcuTalon.Test.Data.Setting`, `OcuTalon.Test.Install.PrivateData`, `OcuTalon.Test.Install.Registry`. Expected: 0 failed; no `Zz` fixture or `zz.` setting left; `^OcuTalonTest("TelegramIncluded")` as it was before.
- `(loop)` One per call: `bash docker/tests/test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-pinned-sources.sh`. Expected: exit 0 each.
- `(loop)` `bash docker/tests/test-audit.sh` (`timeout: 600000`). Expected: exit 0, with no `ocutalon-t04-*` project left.
- `(loop)` `bash docker/tests/test-install-start.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `bash docker/tests/test-install-upgrade.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-audit.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` Load the classes again, then export them. Then `git status --short` and `git diff --stat`. Expected: only the files under Tasks, and no change to any storage block after the second round trip.

**Shared surfaces:**
- the compiled storage that `PrivateData` scans (22 new private globals);
- the `^Ens.MessageBody*` extent (the new message subclasses);
- `Security.Events` (six `OcuTalon/*` events, on throwaways only);
- `Bridge.Installer.Run`, which now registers the events;
- the STEP list, unchanged;
- `.gitattributes`;
- `^OcuTalonTest("TelegramIncluded")`;
- the per-process `^||OcuTalon.Setting` cache.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate (Rule 19; apply, see red, revert, `git status --short` unchanged):**
- AC1: `Reply.Busy` renamed `IsBusy` → `Test.Bridge.Contracts` red.
- AC1: `expired` dropped from `INCIDENTOPENVARIANT` → `Test.Msg.Contracts` red.
- AC1: `NewBusy` sets `Text` → row 3 red.
- AC1: `NewRef` keeps the padding → row 7 red.
- AC1: `ToLocal` uses a fixed offset → row 8 red.
- AC1: `CACHESECONDS` 0 → row 9 red.
- AC1: `Included()` returns 1 without the global → row 14 red.
- AC2: `Incident`'s `DEFAULTGLOBAL` set to `^OcuTalonZz.Incident` → `test-storage.sh` red (prefix) and `Test.Data.Tables` red (resolves to OCUTALON_DATA).
- AC2: a registry row duplicated → `test-storage.sh` red.
- AC3: `Run()` without `RegisterAudit()` → `test-audit.sh` red (row 10).
- AC3: `Write` uses source `OcuTalonZz` → `test-audit.sh` red (row 11).
- AC4: AC3's mutations, run on the non-Health image.
- AC5: one storage block edited by hand → the round trip shows a diff.

**Task 0 measurements** (October 19, build 154, ARM64):
- Time zones (slot A, `OCUTALON`): `$SYSTEM.Process.TimeZone("America/New_York")` returned -1 (TZ was undefined), and in the same process `$SYSTEM.Util.GetEnviron("TZ")` then gave `America/New_York`, `$ZTIMEZONE` went from 0 to 300, and `$ZDATETIMEH("2026-11-01T05:30:00Z",3,7)` converted UTC to local time with daylight saving (05:30Z and 06:30Z on 2026-11-01 both gave 01:30; on 2026-03-08, 06:30Z gave 01:30 and 07:30Z gave 03:30). `$ZDATETIMEH(h,-3)` was not measured: `ToLocal` uses `$ZDATETIMEH(utc,3,7,,,,,,,"")`, whose error argument `""` makes `"junk"`, month 13 and 30 February give `""`. `TimeZone("")` restores the process (`GetEnviron("TZ")` is `""` again). So row 8's New York half runs on slot A. `$ZDATETIME($ZTIMESTAMP,3,7)` is not used for `NowUtc`, because a process zone would convert it again; `NowUtc` uses format 1 and appends `Z`.
- Audit behaviour (throwaway projects): `$SYSTEM.Security.Audit("OcuTalon","Zz","Zz","x","...")` for an unregistered event returns `0` (no error text, no row); for a registered, enabled event, `Write` returns a success. A registered event writes at once after `Security.Events.Create`, with no restart. A written row became readable in `%SYS.Audit` after 53 s and 72 s on the Health image and 66 s on the non-Health image (each measured by polling about every 3 s), so the poll stays at 120 s.
- Non-Health image: instance auditing is on by default on `iris-community:2026.3.0AI.154.0` (`Security.System` `AuditEnabled` is 1 after the first start, and nothing in OcuTalon's files sets it); `test-audit.sh` passed on it. No intent gap.

**Mutations demonstrated** (Rule 19; each applied, red observed, reverted byte for byte with `cmp`):
- mutation: AC1, `Reply.Busy` renamed `IsBusy` -> `Test.Bridge.Contracts` `TestContracts` and `TestNewBusy` red.
- mutation: AC1, `expired` dropped from `INCIDENTOPENVARIANT` -> `Test.Msg.Contracts` `TestEnumerations` red.
- mutation: AC1, `NewBusy` sets `Text` -> `Test.Bridge.Contracts` `TestNewBusy` red.
- mutation: AC1, `NewRef` keeps the padding (`=` no longer removed) -> `Test.Bridge.Contracts` `TestNewRef` red.
- mutation: AC1, `ToLocal` subtracts a fixed 5 hours -> `Test.Data.Time` `TestUnsetZone` and `TestNewYorkZone` red.
- mutation: AC1, `CACHESECONDS` 0 -> `Test.Data.Setting` `TestSeededValueAndCache` and `TestCacheSeconds` red.
- mutation: AC1, `Included()` returns 1 without the global -> `Test.Msg.Contracts` `TestTelegramIncluded` red.
- mutation: AC1 (row 6), `Incident.Count` without `SqlFieldName = FailureCount` -> `Test.Data.Tables` `TestSqlNames` and `TestContracts` red.
- mutation: AC2, `Incident`'s `DEFAULTGLOBAL` and storage globals set to `^OcuTalonZz.Incident` -> `test-storage.sh` red (`registry-class`, `prefix`, `datalocation`) and `Test.Data.Tables` `TestPrivateRecords` red (the data and index globals resolve outside the private database).
- mutation: AC2, a registry row duplicated -> `test-storage.sh` red (`registry-duplicate`, naming the line).
- mutation: AC3, `Run()` without `RegisterAudit()` -> `test-audit.sh` red at row 10 (`STEP Audit FAILED ... OcuTalon/Action/Action is not registered`; the start ends not ready).
- mutation: AC3, `Write` uses source `OcuTalonZz` -> `test-audit.sh` red at row 11 (`Write` returns 0, no row within 120 s).
- mutation: AC4, the two AC3 mutations on `iris-community:2026.3.0AI.154.0` -> `test-audit.sh` red both times, as on the Health image.
- mutation: AC5, `Session`'s `CreatedAt` slot removed from its storage block by hand -> the export of the compiled class differs from the file (the compiler appends the slot again).
- mutation: AC1, the class check dropped from `Write`'s guard (`$IsObject` alone) -> `Test.Bridge.Contracts` `TestAuditApi` red (a `%DynamicArray` is audited without the error text; a stream throws `<METHOD DOES NOT EXIST>`).
- mutation: AC1, `[ Abstract ]` removed from `Bridge.Msg.Result` -> `Test.Bridge.Contracts` `TestContracts` red ("the class is not abstract").
- mutation: AC1, `%XML.Adaptor` added to `Bridge.Msg.DecisionPayload`'s `Extends` -> `Test.Bridge.Contracts` `TestContracts` red (the superclass lists differ).
- mutation: AC1, `NewBusy` sets `ToolsRun` -> `Test.Bridge.Contracts` `TestNewBusy` red ("ToolsRun is 0").
- mutation: AC1, `InitialExpression = 0` removed from `Live.Payload.Decision.Fallback` -> `Test.Msg.Contracts` `TestContracts` red ("Fallback has no initial value 0").
- mutation: AC1, the empty-key guard removed from `Setting.Get` -> `Test.Data.Setting` `TestEmptyKey` red (`<SUBSCRIPT>Get+5`).
- mutation: AC3 (row 12), `CheckAudit` ignores a disabled event (`If exists && (event.Enabled || 'create) Continue`) -> `test-audit.sh` red at row 12 ("2 of 5 values differ": `Step.Audit` neither fails nor names the event).
- mutation: AC2, the `registry-param` report removed from `test-storage.sh` -> its own bad sample fails ("the checker does not flag the sample no-param-new").
- mutation: AC2, `src/short-names.tsv` moved away -> `test-storage.sh` red (`FAIL scan`, exit 1) where it printed six PASS lines; restored byte for byte.

**Recorded runs** (final state, after the review patches): `Test.Msg.Contracts` 6/6, `Test.Bridge.Contracts` 5/5, `Test.Data.Tables` 5/5, `Test.Data.Time` 4/4, `Test.Data.Setting` 5/5, `Test.Install.PrivateData` 5/5, `Test.Install.Registry` 11/11 on slot A; `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-pinned-sources.sh`, `test-audit.sh` (Health, 49 s read-back, and non-Health, 53 s), `test-install-start.sh` and `test-install-upgrade.sh` exit 0; the round trip (load, compile, export) of the 89 classes under `OcuTalon` leaves all 89 files identical. Slot A afterwards: no `zz.` setting, no `Zz` class, no `Reply` row, `TZ` unset, `^OcuTalonTest("TelegramIncluded")` absent as before. No `ocutalon-t0*` container, volume or network remains.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 0.4 adds the cross-lane contracts on top of Stories 0.1 to 0.3: 16 bridge classes and 73 OcuTalon classes load and compile on slot A (89 classes under `OcuTalon`, all identical to their files after a load, compile and export round trip).
- The bridge gets `Ids`, `Audit`, the `Msg` contracts and enumerations, six `Data` tables, and an `Installer` that registers the six `OcuTalon/<T>/<T>` audit events from its one `%SYS` method.
- OcuTalon gets the message contracts, the ten command verbs, the 16 tables with `Setting` and the `Delivery` stubs, `Data.Time`, `Live.Payload.Decision` and `Channel.Telegram.In`.
- The registry is `src/short-names.tsv`, checked by `test-storage.sh`. `Step.Audit` now checks the events.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/{Ids,Audit}.cls`, `Installer.cls` (modified: registers and checks the events), `Msg/*` (7 classes) and `Data/*` (6 tables): the bridge contracts.
- `src/ocutalon/cls/OcuTalon/Msg/*` (6 messages, `Command`, `IncidentCommand`, `CommandResult`, `Enum`, 10 verbs), `Data/*` (16 tables, `Time`, `Setting`), `Live/Payload/Decision.cls`, `Channel/Telegram/In.cls`: the OcuTalon contracts.
- `src/ocutalon/cls/OcuTalon/Install/Step/Audit.cls` (modified: returns `CheckAudit()`), `src/short-names.tsv` (22 rows), `.gitattributes` (union merge for the registry).
- `src/ocutalon/cls/OcuTalon/Test/{Contract,Msg/Contracts,Bridge/Contracts,Data/Tables,Data/Time,Data/Setting}.cls`: five test classes and the shared contract check.
- `docker/tests/test-storage.sh` (new), `test-audit.sh` (new), `test-install-start.sh` (modified: row 5 loads only the installer into the plain namespace).
- `Test/Install/{Registry,Users}.cls`, `Test/Web/{Install,Shell,SignIn}.cls`: one blank line each removed so the round trip changes no tracked file.

**Review findings.** 54 findings from four layers: high 0, medium 18, low 32, false 3, maybe-false 1 (the rows are in the Review Triage Log).
- Patched (7 medium groups, 8 low): `Write` accepts only a dynamic object; `Setting.Get`/`Seed` refuse an empty key; the "is disabled" branch of `Step.Audit` has a live test; the shared counts in `Test.Data.Tables` became floors; `test-storage.sh` requires `DEFAULTGLOBAL` on non-message persistent classes and can no longer pass without reading the registry; the "type exactly" assertion names the type; `Test.Contract` also pins the superclass list, abstractness and the `Boolean` initial value; `TestNewBusy` pins every other field; `Seed` asserts `UpdatedAt`; a `DecisionPayload` JSON test; the row 11 failure line states the budget; the `AgentStep.DurationMs` comment.
- Deferred (3, in `deferred:`): instance auditing off is not reported; AC5 has no recurring check (Story 0.7); `ToLocal` is not run in a production job with the container's TZ.
- Rejected with their reasons in the log: raw `0` from `Write` (spec-bound), a case-insensitive `Ref` collation, `%JSONNULL`/`%JSONIGNORENULL` choices (Stories 0.5 and Epic 1), `TRUNCATE` and `VALUELIST` on contract properties (spec-bound rulings), `Seed` concurrency, `Try`/`Catch` in the installer, test-helper robustness, the `short` against the global's suffix, an AD-3 `%SYS` switch check, and the descriptive intent-alignment divergences. Two findings were false: the Long/Json `MAXLEN` claim (a default `%String` reports 50, measured) and the "no `mutation:` line per row" claim.
- Follow-up review recommended: `true`. Medium patches: 7 (the `Write` guard, `Setting` empty key, the disabled-branch test, the count floors, `registry-param`, the `scan` rule, the exact-type assertion). The risk no layer has seen is the patch hunks themselves: the awk rules in `test-storage.sh` and the stricter comparisons in `Test.Contract` were checked only by my own mutations, not by an independent read.

**Verification performed.** All on the final tree, after the last patch.
- Slot A (build 154, port 52790): the bridge and OcuTalon trees load and compile with 0 errors; `Test.Msg.Contracts` 6/6, `Test.Bridge.Contracts` 5/5, `Test.Data.Tables` 5/5, `Test.Data.Time` 4/4, `Test.Data.Setting` 5/5, `Test.Install.PrivateData` 5/5, `Test.Install.Registry` 11/11, one class per call. No `Zz` fixture, `zz.` setting or `Reply` row is left; the process TZ and `^OcuTalonTest("TelegramIncluded")` are as before.
- Shell: `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-pinned-sources.sh` exit 0.
- Throwaway projects, one at a time: `test-audit.sh` exit 0 on the Health image (row read back after 49 s) and on `iris-community:2026.3.0AI.154.0` (53 s); `test-install-start.sh` and `test-install-upgrade.sh` exit 0. No `ocutalon-t0*` container, volume or network is left.
- Round trip: 89 of 89 exported classes equal their files. The matrix rows 1 to 16 each map to a test that ran and passed; every acceptance criterion has demonstrated `mutation:` lines in `## Verification`.

**Residual risks.**
- The audit read-back takes 49 to 75 s against a 120 s poll, so a very slow runner could time out; the failure line now says how much budget the deadline left.
- `Write` returns the bare `0` of `$SYSTEM.Security.Audit` for an unregistered event, which is a failing status with no text.
- The Rule 22.3 VETO WINDOW item (security posture: the installer registers the audit events) stays open for the lead's FYI.
- The five earlier test files lost one blank line each; please eyeball those one-line diffs.
