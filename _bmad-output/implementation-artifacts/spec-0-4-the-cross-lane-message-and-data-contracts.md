---
title: 'Story 0.4: The cross-lane message and data contracts'
type: 'feature'
created: '2026-10-19'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
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

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
