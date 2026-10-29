---
title: 'Story 9.9: The other nine incidents come from real failures in a test feed'
type: 'feature'
created: '2026-10-29'
status: 'done'
baseline_revision: 'bf6e4ef7f43c660af1131208757dc93ee50e9bbe'
baseline_commit: 'bf6e4ef7f43c660af1131208757dc93ee50e9bbe'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The set holds one incident, the demo's (`eval/orders-date-format/`). AD-22 and FR-62 need at least ten, recorded from real IRIS failures, so that a diagnosis that always gives the same answer can't reach SM-2. They also need at least two held out from prompt work. Story 9.4 built the recorder `OcuTalon.Eval.Record` and the per-push replay test `OcuTalon.Test.Eval.Record`, but nothing produces real failures other than the Orders demo.

**Approach:**
- **The feed.** A test-only production `OcuTalon.Test.Eval.Feed` runs in a namespace of its own, `EVALFEED`. A fixture class creates that namespace inside a throwaway test stack and removes it afterwards; it refuses anywhere else. The feed has nine failing items, each failing through IRIS's own machinery:
  - a datatype or required-property validation;
  - the HTTP adapter's connect or status error, against a partner listener inside the feed;
  - an ObjectScript error.
- **The recordings.** A new mode of the manual recorder, `docker/tests/record-eval.sh feed`, records the nine cases with `Eval.Record.Capture` into `eval/`.
- **Per push.** `Test.Eval.Record` re-induces all ten incidents and compares packs, as 9.4 does for the demo. It also checks that the feed stays in throwaways and leaves nothing behind.
- **Repository checks.** `test-eval-set.sh` pins three things:
  - the cause spread: at most 8 of the first 10 incidents share a category;
  - the two held-out cases;
  - CON-3: no shipped or installing file names the feed.

## Boundaries & Constraints

**Always:**
- **Real failures only.** Every feed failure's error text is IRIS's own. No feed class builds an error status that names the cause. Each of the nine failures comes from one of these:
  - `%ValidateObject` of a typed record (a datatype error, a MINVAL error or a required property);
  - `EnsLib.HTTP.OutboundAdapter` (a refused connection, a host that does not resolve, HTTP 503 or HTTP 500 from the feed's own partner listener);
  - an ObjectScript `<UNDEFINED>`, trapped by Ens.
- **One case per item.** Each case's failures are status-8 headers at the case's own item, one session per message. They share the case's SuperSession (`Bridge.Ids.NewRef()`), and the reader picks event-log rows by session (`Reader.cls:404-432`), so no case's snapshot sees another case's rows.
- **The feed is installed only inside a throwaway test stack.** `Fixture.Install` refuses, writes nothing and names the reason unless `Eval.In.#FOLDER` (`/opt/ocutalon/eval/`, mounted only by `docker/tests/compose.throwaway.yml`) exists. Its only callers are `Test.Eval.Record` (lane-a shard: throwaways and CI) and `record-eval.sh feed` (its own throwaway).
- **`Remove` leaves nothing.** It removes everything `Install` made:
  - the production, the namespace and its web applications;
  - the Interoperability markers and role;
  - the database entry and its folder;
  - the resource. Deleting the resource also deletes the role grant (`Security.Resources.Delete`, `irissys/Security/Resources.cls:100`).

  It is idempotent and returns its status.
- **Least privilege.** The one grant is Read on `%DB_EVALFEED_DATA` to the service role (`Install.Step.Users.#SERVICEROLE`):
  - nothing else, and never `%All`;
  - that resource grants no public permission;
  - the grant lives only between `Install` and `Remove`.
- **Feed data is synthetic.** It holds no names and no hosts other than `127.0.0.1` and example hosts. Field names and values avoid `Redact`'s sensitive keys and patterns (`Bridge/Redact.cls:32`, `:190-216`) and `Reader.#CREDENTIALPARTS` (`Watch/Reader.cls:56`), so each recording keeps its clue and is a fixed point of `Redact.Text`.
- **Committed recordings stay what the recorder wrote.** They are `Eval.Record.Write`'s output formatted with `jq .`, and `recordedBy` is `Eval.Record.#RECORDEDBY`. Committed case files are never hand-edited apart from a reverted mutation.
- **Recordings are compared, never masked further.** Each committed feed snapshot's pack equals a fresh induction's pack once `VOLATILE` is removed, and is never compared with more fields masked. `VOLATILE` is never widened (9.4, Decided in-stage 4).
- **Files and comments.** Every new file is ASCII, and comments state contracts (Rule 14). The spread and held-out numbers are the AC's: 10, 8, 9 and 2.

**Never:**
- Never edit `eval/orders-date-format/*`, except a reverted mutation.
- Never edit:
  - Epic 7's files: `Watch/*`, `Agent/Diagnosis.cls`, `Data/Incident.cls`, `Data/FailureGroup.cls`, `src/bridge/**`, `Fix/**`, `Test/Watch/**`, `Test/Bridge/*`;
  - 9.8's `Watch/Ops.cls` and `Watch/FailurePoller.cls`;
  - Lane B classes and `Test/Demo/*`;
  - `Install/**` and `Production.cls`;
  - `docker-compose.yml`, `ci/compose.ci.yml`, `docker/merge.cpf`, `ci/iris.sh`, `ci/units.sh`, `ci/mock/**`, `docker/tests/lib-*.sh`;
  - any other `docker/tests/*.sh` except `test-eval-set.sh` and `record-eval.sh`;
  - `.github/workflows/*` and the spine;
  - `Eval/In.cls`, `Eval/Sink.cls`, `Eval/Report.cls`, `Eval/Data/*` and `eval/run.sh`.
- `Eval/Record.cls` stays unchanged: no change is needed. Any need for one is an `intent gap` HALT.
- Never install, start or record the feed on slot B, the demo host or a judge's install. Never create a namespace, database, resource or grant on a slot. Never induce failures there.
- Never use `EnsLib.Testing.Service`. The feed's `TestingEnabled` is false (CON-3).
- Never write an `Incident` or `FailureGroup` row. Nothing watches the feed: no `BackgroundCheck` row names it.
- Never place the feed in OCUORDERS or OCUTALON, and never stop the Orders production.
- Never write a local absolute path into a committed file. Write sample paths as `/Users/<name>/` placeholders, and build test samples by concatenation.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Format change, number | 3 `LabResult` with `ResultValue` "7,5", "12,1", "4,0" to `ResultsToChart` | 3 status-8 headers at `ResultsToChart`; the error holds `#7207` (not a valid number) for `ResultValue`; case `results-decimal-comma` | - |
| Format change, time | 3 `Shipment` with `ShippedAt` as epoch seconds (e.g. "1792138500") to `ShipmentsToLedger` | 3 failures, error holds `#7208` (timestamp) for `ShippedAt`; case `shipments-epoch-time` | - |
| Validation, required | 3 `Claim` with `MemberId` "" to `ClaimsToBilling` | 3 failures, error holds `#5659` naming `MemberId`; case `claims-member-missing` | - |
| Validation, range | 3 `Shipment` with `Weight` "-2.5" to `ReturnsToLedger` | 3 failures, error holds `#7204` (below MINVAL 0) for `Weight`; case `returns-negative-weight` (held out) | - |
| Connection refused | 3 `LabResult` to `LabResultsOut` (127.0.0.1:9382, nothing listens) | 3 failures within about `FailureTimeout` (2 s) each; error holds `#6059` and `127.0.0.1:9382`; case `lab-results-refused` | - |
| Host not found | 3 `Shipment` to `CarrierBookingOut` (`carrier.example`) | 3 failures; error holds `#6059` and `carrier.example`; case `carrier-host-not-found` (held out) | Task 0 (e) fallback |
| Partner 503 | 3 `Claim` to `PayerClaimsOut` (127.0.0.1:9381 `/payer/claims`, the feed's `PartnerSite`) | 3 failures after the retries; error holds `ErrHTTPStatus` and `503`; case `payer-unavailable` | - |
| Partner 500 | 3 `LabResult` to `ReferenceLabOut` (127.0.0.1:9381 `/reference-lab/results`) | 3 failures, no retry; error holds `ErrHTTPStatus` and `500`; case `reference-lab-server-error` | - |
| Unknown | 3 `Claim` to `ClaimsToArchive` | 3 failures; error holds `<UNDEFINED>` on an internal variable that no field or setting names; case `claims-archive-internal-error` | - |
| Not a throwaway | `Fixture.Install(<a folder that does not exist>)` | Error "Only a throwaway test stack installs the test feed: ..."; namespace and database entries unchanged | error status |
| Leftover | `Install()` while `EVALFEED` already exists (a killed run, or a second call) | The leftover is removed first, then the feed is installed and runs | error status if removal fails |
| Remove | `Remove()` after `Install()`, then `Remove()` again | Each step's state is gone (see the Remove row of Tasks); role resources as before `Install`; `Reader.Productions()` lists no `EVALFEED` entry; the second call returns OK | error status |
| Spread | the first 10 incident cases by name, 9 of one category | `test-eval-set.sh` `incidents`: `FAIL` naming the category and count | - |
| Held out / count / source | 1 held-out feed case; 9 incident cases in all; a non-demo incident whose `source.production` is not the feed | `incidents`: `FAIL` with `file: rule` | - |
| CON-3 static | `docker-compose.yml`, `Production.cls` or an `Install/` file names `OcuTalon.Test.Eval.Feed` or `EVALFEED` | `test-eval-set.sh` `feed`: `FAIL <path>: names the test feed (CON-3)` | - |
| Driver | `record-eval.sh feed` on a machine with the base image | 9 folders `eval/<name>/{case.json,snapshot.json}`, pretty-printed, ASCII, no home folder; exit 0 | A failed recording or a file that fails a check: nothing is written, exit 1 |

</intent-contract>

## Code Map

Line anchors are from HEAD `f2cf277`. Story 9.8 is planned but not built; if it lands first, find each anchor by its symbol.

**Read only, the evidence path (all as 9.4 used them):**
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`:
  - `:190` `Evidence(namespace, production, item, keys, Output snapshot) As %String`. Only `h<id>` keys make failures (`:285`). The error text is the session's Type 2 row by MessageId (`:310-330`).
  - `:404-432`: the event log is every row of each failure's session, at most 100.
  - `:391-403`: `items` holds only the named item, with its explicit definition settings.
  - `:157-165` `Readable`: `GetNSInfo` gives the namespace's resource, and `CheckUserPermission(ServiceUser, resource, "R")` decides.
  - `:258-266`: `not_current`.
  - `:63` `Productions()` lists every readable Interoperability namespace. This is a shared surface while the feed exists.
- `src/ocutalon/cls/OcuTalon/Watch/EvidencePack.cls`:
  - `:119-136`: the Recorded branch;
  - `:141`: the head (namespace, production, `item` = the first failure's target, count, times, `errorPattern`);
  - `:145-202`: sample, settings of `pack.item`, trace;
  - `:238` `Load`.
- `src/ocutalon/cls/OcuTalon/Eval/Record.cls`:
  - `:54` `Capture(case, namespace, production, item, keys, folder, Output pack) As %Status`;
  - `:75` `Write`;
  - `:104-129`: the case rules;
  - `:22` `RECORDEDBY`, `:39` `LOCALPATH`, `SNAPSHOTFILE`.
- `src/ocutalon/cls/OcuTalon/Eval/In.cls`: `:34` `FOLDER`, `:148-168` `CaseNames` (name order). `src/ocutalon/cls/OcuTalon/Eval/Report.cls`: `:75` `INCIDENTKIND`, `:78` `DEMOCASE`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:43` `SERVICEROLE` (read the parameter, as `Install/Step/Tools.cls:46` does).
- `docker/merge.cpf:3` `OCUTALON_CODE`, the code database that the feed namespace maps the feed's package from.

**The patterns to follow (copies, with the reason under Siblings):**
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` `System` (`:219`, private, fixed to OCUORDERS):
  - creation: resource `:236-244`, directory `:196-198`/`:251`, `SYS.Database.CreateDatabase` `:256`, `Config.Databases.Create` `:268-269`, `Config.Namespaces.Create` `:275-280`, `Config.MapPackages` `:282-297`, `EnableNamespace(ns, 0, , 1)` `:300-303`;
  - removal: web applications `:330-347`, `Config.Namespaces.Delete` + `DisableNamespace` + the Interoperability role `:369-381`, databases innermost first `:403-433`, resources `:452-471`;
  - `Orders` `:546-581`: `LoadFromClass`, `StartProduction`, and the wait until every enabled item's job is alive.
- `src/ocutalon/cls/OcuTalon/Demo/Orders/Partner.cls:70-73`: the SuperSession pattern of an adapterless sender (`%SessionId=""`, `%SuperSession=ref`, `SendRequestAsync`); `:90-95` `CreateBusinessService`.
- `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls:582-650`: `WaitCount`, `Count`, `Headers`. They use `%ExecDirect` in a switched namespace and are fixed to OCUORDERS.
- `src/ocutalon/cls/OcuTalon/Demo/Orders/PartnerOrder.cls`: an `Ens.Request` with a committed `Storage Default` block (`test-storage.sh` requires one for every `Ens.Request` subclass, `Test/` included; no short-names row).
- IRIS:
  - `irislib/EnsLib/HTTP/OutboundAdapter.cls:552` (`EnsErrHTTPStatus`) and `:576` (Retry on 503 and on a connect error);
  - `irislib/Ens/BusinessOperation.cls:51` `RetryInterval`, `:61` `FailureTimeout`, `:165`/`:249-250` (the deadline and the `ErrFailureTimeout` wrapper);
  - `irislib/EnsLib/HTTP/InboundAdapter.cls:212-216` (`Attributes("ResponseCode")` gives the status line);
  - `irislib/Ens/MessageHeader.cls:61-63`: a body that fails `%Save` never becomes a header, so validation happens inside the receiving item;
  - `irislib/Ens/Util/Error.cls:17-27` `EnsSystemError`: without `^Ens.Debug("LogETN")` the date and number are "-", so the text is stable;
  - `irislib/%Library/EnsembleMgr.cls:1738` `EnableNamespace`, `:1892` `DisableNamespace`;
  - `irissys/SYS/Database.cls:590`/`:619`;
  - `irissys/Security/Roles.cls:174`/`:259`;
  - `irissys/Security/Resources.cls:83`/`:100`;
  - `irislib/Ens/Director.cls:39-41`: one production per namespace.

**Extend:**
- `src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls`:
  - `:33` `RECIPES`, `:81-119` `OnBeforeAllTests`, `:123-131` `OnAfterAllTests`;
  - `:147-173` `Make` (generic; it reads the committed case through `Cases.Read`);
  - `:177-198` `Induce` (demo only);
  - `:254-274` `TestReplayEqualsLive` and `:278-307` `TestCommittedIsCurrent` (both loop over `RECIPES`);
  - `:626` `Guard`, `:618` `Entry`, `:644` `AssertSamePack`, `:673` `Stable`;
  - `:326-355` `TestCleanRemovesBatch` (its `closing` instance must not remove the feed).
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`: `:416-424` `TestIncidentFiles`, `:487-550` `IncidentProblems`, `:618-629` `Hosts` (only after `@` or `://`; a bare setting value is not seen), `:595` `Read`, `:603` `Plain`. `:77-120` `TestRecordedCases` already asserts that each incident is skipped with its kind in the reason.
- `docker/tests/test-eval-set.sh`:
  - header `:2-59`, setup `:60-79`, `enum_value` `:82-84`;
  - `check-cases.mjs` `:105-259` (incident branch `:195-236`), `check-demo.mjs` `:374-410` (the pattern for a new program);
  - `mksamples.mjs` `:412-753`: builders `:427-467`, `good()` `:505-519`, `demoTree` `:546-552`, `variant` `:563-570`, demo variants `:717-722`;
  - `tree_files` `:759-765`, `run_node` `:767-772`, `check_*` `:774-777`, `rule()` `:872-911`;
  - the enumerations gate `:913-959`, which hands `mksamples` its values at `:961-962`;
  - the rule registrations `:968-974`.
- `docker/tests/record-eval.sh`: the header `:2-15`, `live_start` `:24`, the start `:28-37`, `session_value` `:40-43`, the copy and checks `:45-55`. It is already in `NOT_IRIS_INPUT_PATTERN` (`ci/units.sh:79`), and `test-ci-changes.sh:248` pins "runs no group".
- `docker/tests/lib-live.sh`: `session_value` `:487-489`. It re-runs a script that printed no CHK line, up to 3 times (`iris_script` `:307-317`). `eval/run.sh:21-23` shows the early-CHK guard.

**Shared surfaces read by other tests (see `## Verification`):**
- `src/ocutalon/cls/OcuTalon/Test/Watch/Tools.cls:254` `TestListProductions` and `Test/Watch/Case.cls:203`, which read `Reader.Productions()`;
- `Test/Watch/Grant.cls`, which pins the service role's OCUORDERS grant;
- `Test/Install/Users.cls`, which pins the service role.

## Tasks & Acceptance

**Execution:**

**Task 0 (measurements, implement stage; the recording run, then the warm and fresh stacks of lane B).** It runs as soon as Tasks 1 to 6 exist, because its measurements need the feed and the driver. Its HALT conditions gate the commit-ready result of Tasks 7 to 9.
- **(a)** For each feed recipe, compare the committed pack with a fresh induction's pack with `VOLATILE` emptied for one warm run, as 9.4 did. The differing fields must be within `VOLATILE`'s six. If any other field differs, HALT `blocked`, naming the case and the field. Never widen `VOLATILE`.
- **(b)** Show that the mapping of package `OcuTalon.Test.Eval` makes the class `OcuTalon.Test.Eval.Feed` and the sub-package `OcuTalon.Test.Eval.Feed.*` visible in `EVALFEED` (inference: a package mapping covers its sub-packages). The feed starts there only if it does. If it does not, HALT `blocked` with the measurement.
- **(c)** Record:
  - the time of `Install`, of the sends until every case has failed, and of `Remove`;
  - `Test.Eval.Record`'s class time, warm and on a fresh stack (9.4: 11 to 15 s);
  - the estimate of the CI cost, at 1 to 3.9 times the local work.

  If the class takes more than 75 s on a fresh local stack (the feed adds more than about 60 s), HALT `blocked` with the times. The lead then chooses between more CI capacity and a manual-only comparison (Decided in-stage 9).
- **(d)** Record one error text per mechanism, from the recorded files. Check each case's `errorHas` markers against them.
  - If a feed recording names a host after `://` or `@`, apply Decided in-stage 12.
  - If a marker differs from the plan, set it to the measured IRIS error code or status. Never make it weaker than the mechanism.
- **(e)** The DNS case: the seconds each message takes to fail, and whether its error text is the same in two inductions. If either message takes more than 10 s, or the texts differ, apply the fallback of Decided in-stage 11.
- **(f)** Confirm that `Remove` leaves the service role's `Resources` exactly as they were before `Install` (`TestFeedRemoved`).

1. [x] **The feed's message and record classes (new; `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/`).**
   - `LabResult`, `Shipment` and `Claim`:
     - each `Extends (Ens.Request, %JSON.Adaptor)`;
     - every property is a `%String`, so that a body always saves;
     - fields: `LabResult` {ResultId, PatientRef, TestCode, ResultValue, Units}, `Shipment` {ShipmentId, OrderNumber, ShippedAt, Weight, Carrier}, `Claim` {ClaimId, MemberId, ServiceDate, Amount, PayerCode};
     - each carries `Parameter RECORDCLASS` naming its typed record;
     - each has a committed `Storage Default` block, generated by a compile on slot B (Verification). No `DEFAULTGLOBAL`, because these are messages.
   - The typed records, `%RegisteredObject` with no storage:
     - `ChartResult`: `ResultValue As %Numeric`; the rest `%String`;
     - `LedgerEntry`: `ShippedAt As %TimeStamp`, `Weight As %Numeric(MINVAL = 0)`;
     - `BillingClaim`: `MemberId As %String [ Required ]`, `Amount As %Numeric`.
     - Each has `ClassMethod From(request)` that copies its own properties from the request's properties of the same names.
   - `Batch` (`%RegisteredObject`): `Target`, `TraceRef`, `Messages` (a list of `Ens.Request`).
   - **Why:** AC1.
2. [x] **The feed's items (new; same folder).**
   - `Sender` (`Ens.BusinessService`, no adapter): `OnProcessInput(batch)` sends each message with `SendRequestAsync(batch.Target, message)`, after `%SessionId = ""` and `%SuperSession = batch.TraceRef`, as `Demo.Orders.Partner` does.
   - `Partner` (`Ens.BusinessService`, `ADAPTER = EnsLib.HTTP.InboundAdapter`): the feed's stand-in partner.
     - It answers with `Attributes("ResponseCode")` = `503 Service Unavailable` for a URL under `/payer/`, `500 Internal Server Error` under `/reference-lab/`, else `200 OK`.
     - It returns OK in every case, so that it logs no error of its own.
   - `Intake` (`Ens.BusinessOperation`, no adapter): `OnMessage` quits with `$ClassMethod($Parameter(request, "RECORDCLASS"), "From", request).%ValidateObject()`.
   - `PartnerOut` (`Ens.BusinessOperation`, `ADAPTER = EnsLib.HTTP.OutboundAdapter`, `INVOCATION = Queue`): POSTs the request's `%JSONExportToString` text to the adapter's URL and quits with the adapter's status. The adapter's own Retry rules apply.
   - `Archive` (`Ens.BusinessOperation`): `OnMessage` reads an internal local variable that is never set, so it fails with `<UNDEFINED>` (Ens traps it as `<Ens>ErrException`). No message field or setting is involved.
   - **Why:** AC1, the Matrix's mechanism rows.
3. [x] **`src/ocutalon/cls/OcuTalon/Test/Eval/Feed.cls` (new; `Ens.Production`).**
   - The XData `ProductionDefinition` has `Name="OcuTalon.Test.Eval.Feed"`, `TestingEnabled="false"` and a description saying it is the evaluation set's test feed (throwaways only). Its items:
     - `FeedIn` (`Sender`, PoolSize 0);
     - `PartnerSite` (`Partner`, adapter `Port` 9381);
     - `ResultsToChart`, `ShipmentsToLedger`, `ReturnsToLedger` and `ClaimsToBilling` (`Intake`);
     - `LabResultsOut` (`PartnerOut`, `HTTPServer` 127.0.0.1, `HTTPPort` 9382, `URL` /lab/results, `FailureTimeout` 2, `RetryInterval` 1);
     - `CarrierBookingOut` (carrier.example, 80, /bookings, 2, 1);
     - `PayerClaimsOut` (127.0.0.1, 9381, /payer/claims, 2, 1);
     - `ReferenceLabOut` (127.0.0.1, 9381, /reference-lab/results);
     - `ClaimsToArchive` (`Archive`).
   - Every case item has PoolSize 1.
   - **Why:** AC1, AC2.
4. [x] **`src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls` (new; no `Method Test`, so it is not a test case: `ci/iris.sh:130-147`).**
   - **Parameters:** `NAMESPACE = "EVALFEED"`, `DATABASE = "EVALFEED_DATA"`, `RESOURCE = "%DB_EVALFEED_DATA"`, `PRODUCTION = "OcuTalon.Test.Eval.Feed"`, `CODEPACKAGE = "OcuTalon.Test.Eval"`, `CODEDATABASE = "OCUTALON_CODE"`, `WAITSECONDS = 60`, and the refusal text.
   - **`XData Cases` (JSON):** one entry per case of the table under Design Notes. Each entry holds:
     - `name`, `heldOut`, `description`, `expectation{causeCategory, elementAtFault, fixKind}`;
     - `item`, `messageClass`, `messages` (3 objects of fixed synthetic field values);
     - `errorHas` (the markers).
   - **Methods:**
     - `Definitions()` (the parsed array) and `Names()` (comma-separated, in name order).
     - **`Install(folder = {##class(OcuTalon.Eval.In).#FOLDER}) As %Status`:**
       - It refuses (nothing done) unless the folder exists.
       - It then removes a leftover with `Remove()`.
       - It creates, in `%SYS` with `New $NAMESPACE`:
         - the resource (no public permission);
         - the directory `<manager directory>evalfeed_data/`;
         - the database, its `Config.Databases` entry and the namespace (Globals and Routines both `DATABASE`);
         - the package mapping `CODEPACKAGE` -> `CODEDATABASE`;
         - `EnableNamespace(NAMESPACE, 0, , 1)`;
         - the grant: the service role's `Resources` gain `RESOURCE:R`.
       - In `NAMESPACE` it calls `Ens.Config.Production.LoadFromClass(PRODUCTION)` and `StartProduction`, and waits up to `WAITSECONDS` until every enabled pooled item's job is alive.
       - While in `%SYS` or `NAMESPACE` it calls no OcuTalon class outside the feed.
     - **`Remove() As %Status`:** it removes, each step skipped when there is nothing to remove:
       - the production (`StopProduction(10, 1)` in `NAMESPACE`);
       - the web applications whose namespace is `NAMESPACE`;
       - the namespace, then `DisableNamespace`, then the Interoperability role;
       - every `Config.Databases` entry at or below the directory, innermost first, with `SYS.Database.DeleteDatabase` and the folder;
       - the resource.
     - **`Start(Output refs As %DynamicObject) As %Status`:** for each definition, a new ref (`Bridge.Ids.NewRef()`, made before the switch), its messages built with `%JSONImport`, and one `Batch` to `FeedIn` (`Ens.Director.CreateBusinessService` in `NAMESPACE`).
     - **`Keys(name, ref, Output namespace, Output production, Output item, Output keys) As %Status`:** waits up to `WAITSECONDS` for the definition's count of status-8 headers of the ref at its item, and gives `h<id>` keys in ascending order. Short of the count, it is an error naming the count seen.
     - **`Record(folder, Output names) As %Status`** (the driver's entry): `Install`, `Start`, then for each case `Keys` and `Eval.Record.Capture`, with the case built from its definition.
       - It requires `Build(Load(<written snapshot>))` to equal Capture's pack as `%ToJSON()` text: the replay at recording time.
       - It always ends with `Remove`, whose status is appended.
   - The class description states the contract: throwaways only, the grant, and what `Remove` removes.
   - **Why:** AC1, AC2, Hermeticity.
5. [x] **`src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls` (extend).**
   - **`Recipes()`** = `RECIPES` (the Orders recipe; the parameter keeps its value) plus `Feed.Fixture.Names()`. `OnBeforeAllTests`, `TestReplayEqualsLive` and `TestCommittedIsCurrent` loop over `Recipes()`.
   - **`OnBeforeAllTests`:** after the hold, it runs `Fixture.Remove()`, which clears a killed run's leftover and its grant. Only then does it record the service role's `Resources` in `RoleBefore`. It then runs `Fixture.Install()`, sets `FeedInstalled`, runs `Fixture.Start(.refs)` into `FeedRefs`, and then `Make`s every recipe. A failure sets `Missing`, as today.
   - **`Induce`:** a feed name gives `Fixture.Keys(name, FeedRefs.<name>, ...)`.
   - **`OnAfterAllTests`:** it appends `Fixture.Remove()`'s status when `FeedInstalled` is 1. A `closing` instance in `TestCleanRemovesBatch` has it 0.
   - **New tests:**
     - **`TestFeedCasesRecorded`** (AC1, AC4):
       - there are at least 9 definitions, with unique names, none of them `DEMOCASE`, each item an item of the feed's definition, and at least 2 held out;
       - for each feed case, in this run's recording (the reader's answer in `Recorded.<name>`) and in its committed `snapshot.json`:
         - the `source` is {`EVALFEED`, `OcuTalon.Test.Eval.Feed`, its item};
         - it holds the definition's count of failures, every one at its item, each error holding every `errorHas` marker;
         - its item's `HTTPServer` setting, where present, is `127.0.0.1` or an example host;
         - the committed `case.json` equals the definition's case (name, kind `incident`, heldOut, description, `snapshot.json`, expectation, `RECORDEDBY`), compared as JSON.
     - **`TestFeedOnlyInThrowaway`** (AC2):
       - `Fixture.Install(<a folder of the test's own that does not exist>)` returns the refusal, and whether `EVALFEED` and the `DATABASE` entry exist is unchanged;
       - the compiled `ProductionDefinition` XData of `OcuTalon.Production` (read with `%Dictionary.XDataDefinition`, so no other test's edit of the saved definition can sway it) names no class that starts `OcuTalon.Test.`;
       - the feed's definition has `TestingEnabled` false and no `EnsLib.Testing.Service` item.
     - **`TestFeedRemoved`** (AC2, Hermeticity; self-contained):
       - `Install()` succeeds over the running feed (the leftover row), and the feed runs in `EVALFEED`;
       - then the `OnAfterAllTests` of a second instance of this class, with only `FeedInstalled` 1, returns OK. This is 9.4's `TestCleanRemovesBatch` pattern, so the wiring to `Remove` is pinned too.
       - After it: no namespace, no `DATABASE` entry, no directory, no resource, the role's `Resources` equal `RoleBefore`, no `^%SYS("Ensemble","InstalledNamespace",NAMESPACE)`, no web application of the namespace, and no `EVALFEED` entry in `Reader.Productions()`;
       - a further `Fixture.Remove()` returns OK;
       - this instance's `FeedInstalled` becomes 0.
   - The class description lists the new tests and the feed.
   - **Why:** AC1, AC2, AC4, the Integration and Hermeticity criteria.
6. [x] **`docker/tests/record-eval.sh` (extend; a reported footprint extension).**
   - With no argument it does exactly what it does today. With the argument `feed` it starts one throwaway the same way (label `r99f`).
   - It runs, through `session_value OCUTALON`, a script that prints an early CHK line (`eval/run.sh`'s guard against a re-run) and then calls `##class(OcuTalon.Test.Eval.Feed.Fixture).Record("/tmp/zz-eval-feed/", .names)`. It prints `ok <names>` or the error.
   - It copies each case's two files out with `dc exec -T iris cat`, `tr -d '\r'` and `jq .`.
   - It refuses, writing nothing and exiting 1, when the recording failed, when a name is `orders-date-format`, or when a file is not JSON, not ASCII, or names `/Users/` or `/home/` (today's checks).
   - Only then does it write every `eval/<name>/`. It prints `record-eval: <n> feed cases written`.
   - Any other argument exits 2.
   - The header documents both modes. It says that `Test.Eval.Record` re-induces every committed incident on every CI run, and that this script is rerun when `TestCommittedIsCurrent` reports drift.
   - **Why:** AC1 (how the committed files are made).
7. [x] **`eval/<name>/` (new, nine folders; written only by Task 6's run).** Commit what the driver wrote, unchanged. `eval/orders-date-format/*` stays byte-identical. **Why:** AC1, AC3, AC4.
8. [x] **`docker/tests/test-eval-set.sh` (extend).**
   - **`enumerations`** also reads `PRODUCTION` and `NAMESPACE` from `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/Fixture.cls` (`FIXTURE_FILE`), with missing messages, and hands them and `CAUSECATEGORIES` to the programs and to `mksamples`.
   - **New rule `incidents`** (a program `check-incidents.mjs` on the `demo` pattern). It reads the top-level incident cases of `eval/` (not `mock-wrong`), in byte order of name, and fails when any of these holds:
     - there are fewer than 10 incident cases;
     - a category accounts for more than 8 of the first 10;
     - fewer than 9 incident cases other than `DEMOCASE` have a snapshot whose `source.production` and `source.namespace` are the feed's;
     - a non-demo incident is not from the feed;
     - fewer than 2 feed incidents are held out.

     Samples: a good tree (the demo plus 9 feed cases with this story's spread and 2 held out) and the variants `bad-incidents-few`, `bad-incidents-category`, `bad-incidents-held-out` and `bad-incidents-source`.
   - **New rule `feed`** (CON-3):
     - Every tracked and not-ignored file (`scan_files`, as `test-boundaries.sh` builds `$all_files`) that names `OcuTalon.Test.Eval.Feed` or the whole word `EVALFEED` fails, unless its path is under `src/ocutalon/cls/OcuTalon/Test/`, `eval/`, `_bmad-output/` or `_bmad/`, or is `docker/tests/record-eval.sh` or `docker/tests/test-eval-set.sh`.
     - So `docker-compose.yml`, the Dockerfile, `docker/merge.cpf`, `src/ocutalon/cls/OcuTalon/Production.cls`, `Install/**`, `ci/**` and `.github/**` never name it.
     - Samples run on a sample tree with `find` (never `expect.txt`): a good tree (the feed named in a test class and an eval snapshot) and the variants `bad-feed-compose`, `bad-feed-production` (an item of class `OcuTalon.Test.Eval.Feed.Sender`) and `bad-feed-install`.
   - The header documents both rules.
   - **Why:** AC2, AC3, AC4.
9. [x] **`src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` (only under Decided in-stage 12).** `IncidentProblems`' host rule also accepts exactly `127.0.0.1`, for incident files only. Not triggered for `127.0.0.1` (no recording names it after `://` or `@`); the file changed for the object reference of Decided in-stage 17 instead. **Why:** AC1's public-text rule, with the feed's own loopback partner.

**Acceptance Criteria:**
- **AC1, nine real feed incidents.**
  - **Given** a throwaway stack in which `Test.Eval.Record` (or `record-eval.sh feed`) installs `OcuTalon.Test.Eval.Feed` in `EVALFEED`, **when** each of the nine recipes sends its 3 messages and its failures are recorded with `Eval.Record.Capture`, **then** each committed case comes from real failures at its own item: status-8 headers whose IRIS error text holds the case's markers.
  - Its `case.json` is the definition's.
  - Its pack equals a fresh induction's pack apart from `VOLATILE`.
  - Its replay equals the live pack exactly.

  Tests: `TestFeedCasesRecorded`, `TestCommittedIsCurrent` and `TestReplayEqualsLive`.
- **AC2, CON-3.**
  - **Given** the repository, **when** `test-eval-set.sh` `feed` runs, **then** no file that ships or installs the product (the judges' `docker-compose.yml`, `OcuTalon.Production`, the install steps, the image and CI files) names the feed or its namespace.
  - **And given** a throwaway, **when** `Test.Eval.Record` runs, **then**:
    - `Install` refuses without the throwaway's eval mount and creates nothing;
    - OCUTALON's production holds no test item;
    - the feed's testing switch is off;
    - after `Remove` no feed namespace, database, resource or grant remains.

  Tests: `feed`, `TestFeedOnlyInThrowaway` and `TestFeedRemoved`.
- **AC3, the spread.** **Given** `eval/`, **when** `test-eval-set.sh` `incidents` runs, **then**:
  - it holds at least 10 incident cases, at least 9 of them recorded from the feed;
  - no cause category accounts for more than 8 of the first 10 by name.

  This story's 10 give data format 3, validation 2, connection 2, partner outage 2 and unknown 1. Test: `incidents` with its variants.
- **AC4, held out.** **Given** the nine feed cases, **when** `incidents` and `TestFeedCasesRecorded` run, **then** at least two are `heldOut: true` (`carrier-host-not-found`, `returns-negative-weight`). Tests: `incidents` (`bad-incidents-held-out`) and `TestFeedCasesRecorded`.
- **Integration (Rule 1).**
  - **Given** a committed feed case, **when** the product's pack builder (`EvidencePack.Load` and `Build`, as `IncidentManager` uses them) reads it, **then** it gives the live pack (`TestReplayEqualsLive`, on a real throwaway).
  - **And when** `Eval.In` and `Eval.Report.Run` read the set with ten incident cases, **then**:
    - each new case is skipped with the incident reason (`Test.Eval.Cases` `TestRecordedCases`);
    - `eval/run.sh` reports no problem ("eval/run: all checks passed").
- **Hermeticity.**
  - **Given** a fresh throwaway, **when** `Test.Eval.Record` and `Test.Eval.Cases` run forward and in reverse, **then** each passes and the feed is removed.
  - **And** on the same stack afterwards, `Test.Watch.Tools`, `Test.Watch.Grant`, `Test.Demo.Production` and `Test.Watch.Evidence` still pass, so the listable productions, the service role, the Orders WatchMark and the demo pins are intact.

## Spec Change Log

## Review Triage Log

### 2026-10-29 - Review pass
- verdicts: 36 findings - high 0, medium 1, low 32, false 2, maybe-false 1
- findings:
  - `[low]` `[patch]` (blind) `Fixture.Record` empties the caller's folder before `Install` can refuse - `Record` now calls `Install` first and empties the folder once it has not refused.
  - `[low]` `[patch]` (blind) the CON-3 rule is case-sensitive, so the folder `evalfeed_data` passes - the rule uses `grep -i`; sample `bad-feed-lowercase`.
  - `[low]` `[patch]` (blind) `Cases.Hosts` exemption also hides `word(N@host)` - the exemption is now only the shape `::Property(N@Class)`; probe for `contact(5@api.zzhost.org)`.
  - `[low]` `[patch]` (blind) nothing checks the pin directly - the markers of `claims-member-missing` are `#5659` and `MemberId(128@`; `TypedRecord` says so.
  - `[low]` `[reject]` (blind) the held-out `carrier-host-not-found` has the evidence shape of the visible `lab-results-refused` - AC4 names these two cases, so changing them alters specified behavior (by-design).
  - `[low]` `[reject]` (blind) the argument contract of `record-eval.sh` has no test - a stub-based rule is about 25 lines for a 5-line guard of a manual script; unlikely to be met (wontfix-accepted, reopen_if the guard is edited).
  - `[low]` `[patch]` (edge) the `feed` rule misses the lowercase folder and the class written as a path - same root as the second row: `grep -i`, the class pattern `[./]`, samples `bad-feed-lowercase` and `bad-feed-class-path`.
  - `[low]` `[patch]` (edge) `Record` removes the caller's folder before the throwaway guard - same root as the first row.
  - `[low]` `[patch]` (edge) a failed pin is silent - same root as the fourth row; the marker makes it loud for the one case that prints the number, where a throw in `NewPinned` would also break the cases that do not.
  - `[low]` `[patch]` (edge) the `Hosts` exemption hides `contact(5@evil.org)` - same root as the third row.
  - `[low]` `[reject]` (edge) `Keys` waits 60 s for a case with 3 sequential messages - the slowest case takes about 15 s (measured); a resolver slower than that also exceeds FailureTimeout first (wontfix-theoretical).
  - `[low]` `[patch]` (edge) the host assertion passes when the item is missing from the snapshot - `AssertFeedSnapshot` asserts that the snapshot holds the item.
  - `[low]` `[reject]` (edge) `record-eval.sh` overwrites a non-feed folder of the same name - the nine names are fixed in the fixture and the script refuses the demo's; a collision needs a deliberate choice of name (wontfix-theoretical).
  - `[false]` `[reject]` (edge) `carrier.example` may resolve - `.example` is a reserved name (RFC 2606) and `#6059` was recorded in every induction.
  - `[low]` `[reject]` (edge) the `feed` pattern has no trailing word boundary - a shipped file would need a word such as `EVALFEEDBACK`; the failure is a loud false positive that a rename removes (wontfix-theoretical).
  - `[low]` `[reject]` (edge) `Install` tests only that the folder exists - that is the guard as the spec defines it (the folder only `compose.throwaway.yml` mounts); by-design.
  - `[false]` `[reject]` (edge) `FeedInstalled` is set before `Install` - intended and stated in `InstallFeed`: `OnAfterAllTests` removes what a half-made install left.
  - `[low]` `[patch]` (edge) the header of `record-eval.sh` lost `TestSnapshotIsReadableAndCurrent` - restored.
  - `[medium]` `[patch]` (verification-gap) the first-ten window of `incidents` is pinned by no sample - the good tree holds eight later incidents of one category, so a check over the whole set is flagged; mutation line written. The explicit name sort is redundant with the byte-ordered file list and is not pinned separately.
  - `[low]` `[patch]` (verification-gap) the underscore form of the namespace and the `_bmad/*` exemption are pinned by no sample - samples `bad-feed-resource-name` and `_bmad/custom/rules.md` in the good tree.
  - `[low]` `[reject]` (verification-gap) `Fixture.Record` and `record-eval.sh feed` have no per-push test - a manual recorder whose output is re-checked on every CI run by `TestCommittedIsCurrent`; a test needs a second feed install (about a minute a run) (wontfix-accepted, reopen_if `Record` changes or a re-recording is refused).
  - `[low]` `[patch]` (verification-gap) the `MIN_FEED` clause cannot fail on its own - sample `bad-incidents-feed-count`; mutation line written.
  - `[low]` `[patch]` (verification-gap) `bad-incidents-category-window` cannot tell the window from the whole set - same root as the medium row.
  - `[low]` `[patch]` (verification-gap) the host assertion passes vacuously - same root as the twelfth row.
  - `[maybe-false]` `[reject]` (verification-gap) `StartProduction` treats a registered job as alive, so a send may precede the listener on 9381 - not reproduced; if true, a refused first attempt adds an event-log row and the retry reaches the 503, and the pack holds no event log (low).
  - `[low]` `[patch]` (verification-gap) the pin needs fewer than 128 held object references - same root as the fourth row.
  - `[low]` `[reject]` (verification-gap) `TestFeedRemoved` does not assert the feed ran before its own `Install`, and relies on later tests reading only `Recorded` - the mutation "`Install` skips removing a leftover" pins the precondition, and no later test reads the live feed.
  - `[low]` `[reject]` (verification-gap) parts of AC2 and AC3 have no mutation line of their own - Rule 19 asks for one demonstrated mutation per AC; AC2 has four and AC3 five.
  - `[low]` `[reject]` (verification-gap) the second `Hosts` probe has no mutation for an over-wide exclusion - the exclusion is now tight and a third probe pins the unspaced form (same root as the third row).
  - `[low]` `[reject]` (verification-gap) the `feed` rule has no "files were scanned" guard - an empty scan makes every other rule of the script fail too.
  - `[low]` `[patch]` (verification-gap) the exclusion hides `contact(5@real-host.com)` - same root as the third row.
  - `[low]` `[reject]` (intent-alignment) `returns-negative-weight` sends -2.5, -1.0 and -0.5 where the matrix names -2.5 - every message is negative, and the observable (`#7204` for `Weight`) is the matrix's.
  - `[low]` `[reject]` (intent-alignment) the connection failures end about 5 s apart, the matrix says about 2 s - measured and recorded under Task 0 (c) and (e); inside the 10 s limit of Task 0 (e).
  - `[low]` `[reject]` (intent-alignment) the `incidents` source check also tests the namespace - stricter than the matrix, no harm.
  - `[low]` `[reject]` (intent-alignment) `Test/Eval/Cases.cls` changed though the intent does not name it - inside the footprint `Test/Eval/**`; the change is needed for the object reference in the required-property text (Decided in-stage 17).
  - `[low]` `[reject]` (intent-alignment) no test asserts "no Incident row" or distinct sessions - met by omission (nothing watches the feed) and by construction (`Sender` sends each message in a session of its own); the snapshots show the sessions.

## Design Notes

**Architecture decisions (Rule 6):**

| AD | What it governs here |
|---|---|
| AD-22 | The evaluation set's recorded reader snapshots, and the rule "no cause category accounts for more than 8 of the first 10". CON-3: the feed only in throwaways, never `EnsLib.Testing.Service`, the testing switch off. Recording happens in throwaways only, and the comparison with a fresh recording runs on every CI run |
| AD-15 | `Reader.Evidence` is the reader, and `EvidencePack.Build` builds the pack from the live reader or the recorded snapshot (the Integration AC) |
| AD-3 | A production is read only while it is its namespace's own, and only when the service user holds Read on that namespace's data database (the grant). The rule that only listed classes switch namespace binds product classes; test classes switch freely (`Test/Demo/Production.cls`, `Test/Watch/Case.cls`) |
| AD-24 | No grant beyond Read on the feed's own database resource, and none outside a throwaway, so the generated security overview (an install-time artefact) never meets it |
| AD-16 | Only `data_format_change` takes a fix kind (`repair_resend`) |
| AD-29, AD-33 | Lane A's `OcuTalon.Test.Eval` and `eval/`. The feed is a test production, so no ownership table changes; `OcuTalon.Test.Bridge.ZzStoppedProduction` is the precedent of a test production in the package |
| NFR-11, CON-5 | No key, credential, local path or personal data in a recorded file: the synthetic data, `TestIncidentFiles`, `cases` and `test-boundaries.sh` |
| Conventions | "Watch failures" (a status-8 header is a failure), "Service role, OCUORDERS read" (the grant's pattern, here test-only), "Redaction" |

No AC contradicts an AD, and no NFR is unmeasurable as worded (Rules 5 and 6). The spine changed after `epic-9-context.md` was compiled (9.8's eval-watch convention). This plan read the cited ADs and conventions from the spine itself.

**Decided in-stage:**
1. **No further split.** The story has one criterion and its "And". Each seam would cut one sentence: the feed, CON-3, the spread and the held-out cases are all in it. The estimate is about 1,300 hand-written lines (14 small feed classes, a fixture of about 300 lines, about 200 in `Test.Eval.Record`, about 200 in `test-eval-set.sh`, about 50 in `record-eval.sh`), plus nine generated case folders. That is 9.4 part 1's size, which one pass carried. Nothing leaves 1.0.0.
2. **A namespace of its own (`EVALFEED`), not Orders' place.** IRIS runs one production per namespace. Stopping Orders on every CI run would disturb `Test.Demo.Production`, `Test.Watch.*` and the floor specs, which need it running.
3. **One database, `EVALFEED_DATA`, holds both globals and routines.** Its resource is `%DB_EVALFEED_DATA`, with no public permission. The package mapping `OcuTalon.Test.Eval` -> `OCUTALON_CODE` makes the production class and the sub-package visible (Task 0 (b)). The whole package `OcuTalon.Test.Eval` is mapped, because a mapping of `OcuTalon.Test.Eval.Feed` covers `OcuTalon.Test.Eval.Feed.*` but not the class `OcuTalon.Test.Eval.Feed` (inference, from `%SYS.Namespace.GetPackageDest`). The other test classes that this makes visible there are never run there.
4. **The grant.** `Remove` takes it back by deleting the resource, which also deletes it from every role. So a killed run's grant is gone after the next `Install`, with no saved "before" value to lose. `RoleBefore` is the test's evidence only.
5. **Where the recipes live.** They are in the fixture's `XData Cases`, one source for both the driver and the per-push test. `Make` stays generic and still builds its capture's case from the committed `case.json`. `TestFeedCasesRecorded` ties the committed case to the definition.
6. **Three messages per case** give the pack a count and a time span at little cost. The retrying operations use `FailureTimeout` 2 and `RetryInterval` 1, so a failure ends in about 2 to 3 s (the lead's note). These settings appear in the evidence, as such settings do in real productions.
7. **Element at fault.** It is the field for `data_format_change` and `validation_error` (Diagnosis INSTRUCTIONS: "the field, item or setting that is at fault"). For `connection_failure`, `partner_outage` and `unknown` it is the failing item, which is the pack's `item`. The expectations are the author's recorded truth (FR-62). Story 9.5 measures how well Haiku 5.5 meets them, and prompt work never sees the two held-out cases.
8. **`setting_change` is not recorded.** The pack has no setting-change history until step 5 (AD-15 S15; Story 17.7 adds those incidents), so such a case could not be diagnosed fairly.
9. **The comparison runs on every push** in `Test.Eval.Record` (lane-a shard, `shards` job). That keeps 9.4's `TestCommittedIsCurrent` contract: every committed incident has a recipe that is re-induced in the same run.
   - The latest green `ci` run (`6cd40f9`, run 40827075509) took `iris (shards)` 27 min 24 s and `iris (image)` 27 min 34 s, against REL-4's 35.
   - The feed adds an estimated 20 to 30 s locally: install about 3 to 5 s, the sends until every case fails about 9 s (timer-bound), the captures, the remove and `TestFeedRemoved`'s reinstall. On CI that is about 1 to 2 min, so `shards` comes to about 29 min (inference).
   - Task 0 (c) measures it and HALTs above 75 s per class locally. Then the lead's alternative is a manual-only comparison through `record-eval.sh feed` with the per-push file checks.
   - The lead's CI gate measures the real job.
10. **The driver is a mode of `record-eval.sh`, not a new script.** That keeps one manual recorder and its existing `NOT_IRIS_INPUT_PATTERN` entry and pin. The default mode is unchanged.
11. **DNS fallback.** If Task 0 (e) finds the `carrier.example` failure slow (over 10 s a message) or unstable, `CarrierBookingOut` points at `127.0.0.1` port 9383, where nothing listens. The case is then named `carrier-connection-refused`, still held out, with the same category and element.
12. **Hosts.** The feed uses only `127.0.0.1` and `carrier.example` (allowed). As settings values they are bare, and 9.4's `Hosts` rule sees only text after `@` or `://`, so `TestFeedCasesRecorded` pins the feed's `HTTPServer` values itself (9.4's residual risk, now decided). Only if a recording names `127.0.0.1` after `://` or `@` (Task 0 (d)) does `IncidentProblems` accept exactly that host for incident files (Task 9).
13. **Names.** The cases are named for what fails, in lower-case kebab. The partner listener port is 9381, and 9382/9383 are ports where nothing listens. Message ids are fixed per case (for example `LR-1001`), so bodies repeat on every induction.
14. **"Every other incident is from the feed" is this release's rule.** The AC says so of the other incidents. A later story that records an incident elsewhere relaxes `incidents`' source check in its own change: a case from real use (FR-62), or Story 17.7's setting changes, if they are not recorded in the feed.
15. **CON-3 at three levels:**
    - the static `feed` rule, every push, in the hosted `checks` job;
    - the runtime refusal and the clean `Remove` (`Test.Eval.Record`);
    - the throwaway's eval mount as the guard. The judges' image compiles every `OcuTalon.Test.*` class (`src/module.xml`, the Dockerfile copies `src/`), as it already does for `ZzStoppedProduction`, but nothing there installs or starts the feed.
16. **`Eval.Record` is unchanged.** `Capture` takes any namespace, production and item.
17. **An object reference is not a host (implement stage).** The IRIS text of a required property is `Property 'Pkg.Class::MemberId(6@Pkg.Class)' required`, so `claims-member-missing` has an `@` followed by a class name, which 9.4's `Hosts` read as the host `ocutalon.test.eval.feed.billingclaim` and `TestIncidentFiles` flagged. `Test.Eval.Cases.Hosts` now drops an object reference, `(<digits>@<ClassName>)` right after an identifier character, before it looks for `@` and `://`; `TestIncidentChecksFlagViolations` pins both sides (the reference is no address, an address in parentheses after a space is still one). This is the only change to `Cases.cls`; Decided in-stage 12's `127.0.0.1` rule was not needed.
18. **The object-reference number is pinned (implement stage).** The number in that text (`MemberId(6@...)`) is the job's object-reference number of the typed record. It was 6 in a fresh job and changed in some inductions under CPU load (12, 16 and 21 were seen), so `TestCommittedIsCurrent` could report `claims-member-missing` at `.sample.error` for one run in a few dozen. A fixed record per job (made in `OnInit`) did not remove it. `TypedRecord.NewPinned` now gives every typed record the object-reference number `REFNUMBER` (128): it takes instances until one has the number, releases the others and then that one, and the next `%New()` gets the number again (released numbers are reused last in, first out; measured in a throwaway: 3 released numbers came back in reverse order). The error text is IRIS's own and the same on every run: `...::MemberId(128@OcuTalon.Test.Eval.Feed.BillingClaim)`. The case, its marker `#5659` and Matrix row are unchanged; only the recording of `claims-member-missing` was redone (`record-eval.sh feed`). If a job ever holds numbers above 128, the record gets the number IRIS gives it and `TestCommittedIsCurrent` reports the drift.

**Measured in-stage (Task 0; lane B, build 154U; warm stack `e9s9iw`, fresh stacks `e9s9i`):**
- **(a) Packs.** With `VOLATILE` emptied for one warm run, the committed pack and a fresh induction's pack of each feed case differ at `.firstAt .lastAt .sample.at .trace.0.timeCreated` only, all within `VOLATILE`'s six (`sample.headerId` and `trace.0.headerId` do not differ: every `Install` makes a new database, so the ids repeat). The demo differs at those and `.sample.headerId(type) .trace.0.headerId`, as in 9.4. No HALT.
- **(b) Mapping.** After `Install`, in `EVALFEED` the classes `OcuTalon.Test.Eval.Feed`, `.Feed.Sender`, `.Feed.Fixture`, `.Feed.LabResult` and `OcuTalon.Test.Eval.Record` exist, and `OcuTalon.Eval.Record` does not: the mapping of the package `OcuTalon.Test.Eval` covers the class of that name below it and the sub-package. No HALT.
- **(c) Times.** Warm: `Install` 1.6 to 1.8 s, the sends until every case had failed 15.25 s, `Remove` 2.1 s, the whole of `Fixture.Record` 23.8 s. `Test.Eval.Record` as a class: warm 43.1 to 45.1 s (58 s under load from another stack), fresh stack 42.38 s as one class and 41.75 s (forward, part 5/8) and 44.02 s (reversed, part 4/8) in the lane-a shard (9.4: 11 to 15 s), so the feed adds about 30 s: the three retrying items take about 5 s a message one after another (15 s of the 30), then two installs and two removals (`TestFeedRemoved` installs again). The fresh stack takes 84 to 99 s to be ready. At 1 to 3.9 times, the CI cost is 0.5 to 2 min on the 27 min 24 s `shards` job (REL-4: 35 min). The 75 s guard did not fire.
- **(d) Texts, one for each mechanism.**
  - `%ValidateObject`, datatype: `ERROR #7207: Datatype value '7,5' is not a valid number`, then a line `> ERROR #5802: Datatype validation failed on property 'OcuTalon.Test.Eval.Feed.ChartResult:ResultValue', with value equal to "7,5"`; the same for `#7208` (`'1792138500' is not a valid timestamp format`) and `#7204` (`'-2.5' less than MINVAL allowed of 0`);
  - `%ValidateObject`, required: `ERROR #5659: Property 'OcuTalon.Test.Eval.Feed.BillingClaim::MemberId(128@OcuTalon.Test.Eval.Feed.BillingClaim)' required` (6 before Decided in-stage 18);
  - `EnsLib.HTTP.OutboundAdapter`, connect: `ERROR #6059: Unable to open TCP/IP socket to server 127.0.0.1:9382` (and `carrier.example:80`); the event log also holds `ErrFailureTimeout: FailureTimeout of 2 seconds exceeded in OcuTalon.Test.Eval.Feed.PartnerOut; ...` after it, and the reader picks the first row;
  - `EnsLib.HTTP.OutboundAdapter`, status: `ERROR <Ens>ErrHTTPStatus: Received non-OK status 503 from remote HTTP server: 'HTTP/1.1 503 Service Unavailable'` (and 500);
  - ObjectScript: `ERROR <Ens>ErrException: <UNDEFINED>OnMessage+1^OcuTalon.Test.Eval.Feed.Archive.1 *archiveSlot -- logged as '-' number - @' Set total = archiveSlot + 1'`.

  Every plan marker holds, so no `errorHas` value changed. The only `@` in a recording is the object reference of Decided in-stage 17; no recording has `://`, so Task 9's `127.0.0.1` rule was not needed.
- **(e) DNS.** `carrier.example` fails like the refused port: each message takes about 5 s (the three end 5 s apart), well under 10 s, and its text is the same in every induction (the committed text and the fresh text are equal in all runs of `TestCommittedIsCurrent`). The fallback of Decided in-stage 11 was not needed. On a CI host with no resolver the time may differ; the text does not carry the cause.
- **(f) The grant.** The service role's Resources are `%DB_OCUORDERS_DATA:R` before `Install`, `%DB_EVALFEED_DATA:R,%DB_OCUORDERS_DATA:R` while the feed exists and `%DB_OCUORDERS_DATA:R` after `Remove`; `TestFeedRemoved` pins it.
- **Final timings (after the review patches; same machine, other lanes busy).** `Test.Eval.Record`: warm 40.8 to 44.6 s (55.8 to 73.4 s under 40 busy loops on 16 cores); fresh stack as one class 58.49 s; in the lane-a shard 43.06 s (forward, part 5/8, 139 s for 10 classes) and 57.80 s (reversed, part 4/8, 162 s for 10 classes); `Test.Eval.Cases` 7.2 to 7.7 s (forward in part 4/8: 123 s for 10 classes). The 75 s guard did not fire (the slowest fresh figure is 58.49 s). `record-eval.sh feed` took about 2 min each time.
- **Recording.** `record-eval.sh feed` (fresh stack `e9s9i`): `record-eval: 9 feed cases written`, 1 min 59 s, exit 0. `eval/orders-date-format/*` is byte-identical.
- **Object-reference number.** Before the pin: 15 warm inductions with no load gave 6 in every failure; under 48 busy loops on 16 cores 40 inductions gave one with 12 12 12 and one with 6 6 21; a fixed record per job gave 12 in one of 14. After the pin (Decided in-stage 18): the recording on a fresh stack has 128 in all three failures, the other eight cases differ from the earlier recording in `VOLATILE` fields only, and `Test.Eval.Record` passed on 5 further warm runs, 3 of them under 40 busy loops on 16 cores (55 to 73 s).
- **Other checks on fresh stacks.** Lane-a shard parts 5/8 (146 s, 10 classes) and reversed 4/8 (148 s, 10 classes) pass; `eval/run.sh` (1 min 31 s) prints `eval/run: all checks passed` and lists the ten incident cases as skipped; `ci/iris.sh live storage-roundtrip` passes for all 88 stored classes (the three message classes included); the warm run of `Test.Watch.Tools`, `Test.Watch.Grant`, `Test.Demo.Production` and `Test.Watch.Evidence` right after a green `Test.Eval.Record` passes.

**The cases (Fixture `XData Cases`; `recordedBy` is `Eval.Record.#RECORDEDBY`; three messages each):**

| Folder | Item | Category | Element | Fix | Held out | `errorHas` (plan; Task 0 (d)) |
|---|---|---|---|---|---|---|
| `carrier-host-not-found` | `CarrierBookingOut` | connection_failure | CarrierBookingOut | | yes | `#6059`, `carrier.example` |
| `claims-archive-internal-error` | `ClaimsToArchive` | unknown | ClaimsToArchive | | no | `<UNDEFINED>` |
| `claims-member-missing` | `ClaimsToBilling` | validation_error | MemberId | | no | `#5659`, `MemberId` |
| `lab-results-refused` | `LabResultsOut` | connection_failure | LabResultsOut | | no | `#6059`, `127.0.0.1:9382` |
| `payer-unavailable` | `PayerClaimsOut` | partner_outage | PayerClaimsOut | | no | `ErrHTTPStatus`, `503` |
| `reference-lab-server-error` | `ReferenceLabOut` | partner_outage | ReferenceLabOut | | no | `ErrHTTPStatus`, `500` |
| `results-decimal-comma` | `ResultsToChart` | data_format_change | ResultValue | repair_resend | no | `#7207`, `ResultValue` |
| `returns-negative-weight` | `ReturnsToLedger` | validation_error | Weight | | yes | `#7204`, `Weight` |
| `shipments-epoch-time` | `ShipmentsToLedger` | data_format_change | ShippedAt | repair_resend | no | `#7208`, `ShippedAt` |

Descriptions are one plain sentence of what was sent and what the item expects. For example: "Three lab results from the test feed with the result value written with a decimal comma (7,5); the chart operation expects a decimal point."

**Ledger inbox:** none.

**Integration and linkage (Rules 1 and 2):**
- **Consumes:**
  - 9.4's `Eval.Record.Capture`, `RECORDEDBY`, `SNAPSHOTFILE` and `Test.Eval.Record` (`Make`, `Stable`, `AssertSamePack`, `Guard`);
  - `Watch.Reader.Evidence` and `Productions`, `EvidencePack.Build` and `Load` (read only);
  - `Eval.In.FOLDER` and `CaseNames`, `Eval.Report.DEMOCASE` and `INCIDENTKIND`;
  - `Install.Step.Users.SERVICEROLE`, `DiagnosisPayload.CAUSECATEGORIES` and `FIXCATEGORY`;
  - `Test.Eval.Cases.Read`.
- **Consumed-by:**
  - **Story 9.6:** `IncidentManager` diagnoses the ten incident cases on the mock. Note: the mock's default diagnosis answers `data_format_change`/`OrderDate`, so the mock scores are low by design. DW-353 also applies.
  - **Story 9.5:** SM-2 and the held-out score over the ten on Haiku 5.5.
  - **Story 17.7:** setting-change incidents, recorded the same way (the fixture can take further items).
- **The consumers in this story:** `EvidencePack.Load`/`Build` (`TestReplayEqualsLive`), and `Eval.In`/`Report.Run` (`TestRecordedCases`, `eval/run.sh`).

**Siblings (extend, don't copy):**
- Extended:
  - `Test.Eval.Record` (`Recipes`, `Induce`, both clean-up hooks);
  - `record-eval.sh` (a mode);
  - `test-eval-set.sh` (rules on the `demo` pattern).
- **Copies, each with its reason:**
  - The fixture's create and remove steps follow `Install.Step.Demo.System`. Those methods are private and fixed to OCUORDERS, and `Install/**` is Epic 15's and read-only here. A shared namespace helper would be the Demo step's owner's change (Lane B): for the lead to route if wanted.
  - The job-alive wait follows `Demo.Orders` start.
  - `Keys` follows `Test.Demo.Production.WaitCount`, `Count` and `Headers` (Lane B's, fixed to OCUORDERS).
  - `Sender` repeats 3 lines of `Demo.Orders.Partner` (Lane B's demo class).
- Not copied: `Test.Watch.Case`'s private role helpers (Epic 7's). Deleting the resource makes them unnecessary.

**Veto-window items (for the lead to record):**
- **Privileges.** The test-only grant of Read on `%DB_EVALFEED_DATA` to `OcuTalonServiceRole`:
  - only inside throwaway stacks (`Test.Eval.Record` in the lane-a shard, and `record-eval.sh feed`);
  - only between `Install` and `Remove`;
  - only on the feed's own database;
  - never in the product's install, on a slot or on the demo host (the install refuses without the throwaway's eval mount).
- **The expectation convention of Decided in-stage 7** is a decide. There is no stored-data change: the files keep `ocutalon.readerSnapshot/1` and 9.1's case format. There is no public product text.

**Footprint extensions:**
- `docker/tests/record-eval.sh` (the lead allowed it; reported);
- the new sub-package folder `src/ocutalon/cls/OcuTalon/Test/Eval/Feed/` (inside `Test/Eval/**`).

**Spine (Rule 20), the lead's call.** AD-22's evaluation-set bullet could record the feed:
- `OcuTalon.Test.Eval.Feed` in namespace `EVALFEED`, installed by test code in throwaways only;
- `record-eval.sh feed` as its recorder;
- the per-push re-induction.

## Verification

`<B>` stands for:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

QA and review use their own stage names and tags: `e9s9q`/`e9s9qw` and `e9s9c`/`e9s9cw`.

- **Run discipline:**
  - Run every command from the epic-9 worktree root (the lead names its path in each stage prompt; never write it into a committed file).
  - Run each command in the foreground of its own call with `timeout: 600000`, and prefer calls under 3 minutes. A call that the harness moves to the background is waited on by reading its output file in short calls, never by starting a second copy.
  - Make one `iris_execute_tests` call per message, and pass `server` and `namespace` on every IRIS MCP call.
- **IRIS MCP:** only `iris_server_info` and compile checks on slot B (`server` `ocutalon-slot-b`, namespace `OCUTALON`, build 154U). Never call `Fixture.Install`, `Start` or `Record` there, run a test there, or create anything there.
- **Tags:** fresh `e9s9i` (the recording run included), warm `e9s9iw`.

**Shared surfaces:**
- `eval/` gains nine incident folders. They are read by:
  - `Test.Eval.Cases` (`TestRecordedCases`, `TestIncidentFiles`) and `Test.Eval.Record` (`TestCommittedIsCurrent`);
  - `test-eval-set.sh` (`cases`, `incidents`, `feed`) and `test-boundaries.sh`;
  - `eval/run.sh` and `Report` (skipped as not run yet).

  Item, injection and turn counts are unchanged.
- `Test.Eval.Record`'s recipes and its time in the lane-a shard (the CI `shards` job).
- `test-eval-set.sh`'s rules, samples and enumeration messages.
- These exist only while the feed is installed, inside `Test.Eval.Record` and the driver:
  - the namespace `EVALFEED`, the database `EVALFEED_DATA` and the resource `%DB_EVALFEED_DATA`;
  - the service role's `Resources`;
  - `Watch.Reader.Productions()` (read by `Test.Watch.Tools` and `Test.Watch.Case`), `^%SYS("Ensemble","InstalledNamespace")` and the namespace's web applications.

  `TestFeedRemoved` pins their removal.
- The Orders WatchMark and the OCUORDERS messages are used as 9.4 uses them.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-b`, then load and compile every new or changed class under `src/ocutalon/cls/OcuTalon/Test/Eval/` on slot B, namespace `OCUTALON`. Copy the generated `Storage Default` blocks of `LabResult`, `Shipment` and `Claim` into their files. Expected: build 154U, port 1991, every class compiles.
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: every rule PASS, `incidents` and `feed` included (about 5 to 10 s). `incidents` fails until the recording is in `eval/`.
- (once, after the classes compile; again only after a fix to the feed) `<B> OCUTALON_RUN_TAG=e9s9i bash docker/tests/record-eval.sh feed` -- expected: `record-eval: 9 feed cases written`, exit 0, about 2 to 4 min (one stack start plus the recording). Then `git status --short -- eval/` lists only the nine new folders, and `git diff --stat -- eval/orders-date-format` is empty (Task 0 (b), (d), (e)).
- (once) `<B> OCUTALON_RUN_TAG=e9s9iw ci/warm.sh up` -- expected: `LOCK acquired warm-iris`, ready. If a warm run later refuses because of a change outside `src/`, run `ci/warm.sh down`, then `up`.
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s9iw ci/iris.sh class OcuTalon.Test.Eval.Record` -- expected: passed (Task 0 (a), (c), (f)).
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s9iw ci/iris.sh class OcuTalon.Test.Eval.Cases` -- expected: passed.
- (once) On the same warm stack, right after a green `Test.Eval.Record`, run `OcuTalon.Test.Watch.Tools`, then `OcuTalon.Test.Watch.Grant`, `OcuTalon.Test.Demo.Production` and `OcuTalon.Test.Watch.Evidence`, each in its own call -- expected: all pass.
- (once) `<B> OCUTALON_RUN_TAG=e9s9i ci/iris.sh class OcuTalon.Test.Eval.Record` -- expected: passed on a fresh stack (about 2 to 3 min); record the class time (Task 0 (c)).
- (once) `<B> OCUTALON_RUN_TAG=e9s9i ci/iris.sh shard lane-a --part k/8`, for the part whose `CLASS` lines hold the `Test.Eval` classes (5/8 on 9.4's head; the feed adds no test case, so the parts should not move), then `--reverse` for the part that holds them reversed (4/8 on 9.4's head), each in its own call -- expected: every class passes (about 100 to 170 s each); record the times.
- (once) `<B> OCUTALON_RUN_TAG=e9s9i bash eval/run.sh` -- expected: `eval/run: all checks passed`, with the nine new cases among the skipped (about 3 to 5 min).
- (once) `bash docker/tests/test-boundaries.sh`, then `bash ci/checks.sh` -- expected: every block passes (`boundaries`, `eval-set`, `class-rules`, `storage`, `ci-config` and `ci-changes` included).
- (once, last; also after a failure) `<B> OCUTALON_RUN_TAG=e9s9iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s9i ci/iris.sh teardown` -- expected: the lane-b lock folder holds no lock of this stage, and no `EVALFEED` exists anywhere but in torn-down throwaways.

**Planned mutations (Rule 19).** For each one: apply it, observe the red, revert, confirm that `git status --short` and `git diff --stat` are as before, and write the `mutation:` line here. A data mutation of a committed case must end byte-identical (back it up first).

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `Intake` quits with `$$$ERROR($$$GeneralError, "ResultValue is not a valid number")` instead of `%ValidateObject()` | `TestFeedCasesRecorded` (`#7207` missing) |
| AC1 | `Partner` answers `200 OK` under `/payer/` | the class (`payer-unavailable` not induced: `Missing`) |
| AC1 | the committed `results-decimal-comma/snapshot.json`'s first `ResultValue` becomes `7.5` | `TestCommittedIsCurrent` (`.sample.body.ResultValue` differs) |
| AC1 | the definition of `claims-member-missing` gets `elementAtFault` `ClaimId` | `TestFeedCasesRecorded` (committed case differs) |
| AC1 | `payer-unavailable` is removed from `XData Cases` | `TestCommittedIsCurrent` (the case has no recipe) |
| AC1 | `Write` empties `trace` | `TestReplayEqualsLive` for every feed recipe |
| AC2 | `Install` skips its throwaway check | `TestFeedOnlyInThrowaway` |
| AC2 | the `feed` rule skips `docker-compose.yml` | `test-eval-set.sh` `feed` self-check (`bad-feed-compose` not flagged) |
| AC2 | `Remove` skips deleting the resource | `TestFeedRemoved` (resource and role resources) |
| AC2 | `Remove` skips `Config.Namespaces.Delete` | `TestFeedRemoved` |
| AC3 | the `incidents` limit becomes 9 | `incidents` self-check (`bad-incidents-category` not flagged) |
| AC4 | the held-out count check is dropped | `incidents` self-check (`bad-incidents-held-out`) |
| AC4 | the committed `carrier-host-not-found/case.json` has `heldOut` false | `incidents` (1 held out) and `TestFeedCasesRecorded` |
| Hermeticity | `OnAfterAllTests` skips `Fixture.Remove()` | `TestFeedRemoved` (the namespace and the grant remain after the second instance's `OnAfterAllTests`) |
| Hermeticity | `Install` skips removing a leftover | `TestFeedRemoved` (`Install()` over the running feed fails) |

mutation: `Intake` quits with `$$$ERROR($$$GeneralError, "ResultValue is not a valid number")` instead of `%ValidateObject()` -> `TestFeedCasesRecorded` (the four Intake cases lack their markers) and `TestCommittedIsCurrent` (`.errorPattern .sample.error`) went red
mutation: `Partner` answers `200 OK` under `/payer/` (the prefix changed) -> the class went red: `payer-unavailable` was not induced (0 failed headers after 60 s), `Missing` was set, and every test failed with that reason
mutation: committed `results-decimal-comma/snapshot.json` first `ResultValue` `7,5` -> `7.5` -> `TestCommittedIsCurrent` went red (`differs at .sample.body.ResultValue`); the file was restored byte-identical
mutation: definition of `claims-member-missing` has `elementAtFault` `ClaimId` -> `TestFeedCasesRecorded` went red ("the committed case.json is the case of the definition")
mutation: `payer-unavailable` removed from `XData Cases` -> `TestCommittedIsCurrent` ("the incident case has a recipe in Recipes()") and `TestFeedCasesRecorded` (8 cases, not 9) went red
mutation: `Eval.Record.Write` sets `trace` to `[]` before it writes -> `TestReplayEqualsLive` went red for every recipe (`differs at .trace.0(missing)`, the demo and the nine feed cases) and `TestCaptureWritesCase` too; `Eval/Record.cls` was restored (`git status` shows it unchanged)
mutation: `Install` skips its throwaway check -> `TestFeedOnlyInThrowaway` went red (the refusal is missing)
mutation: the `feed` rule of `test-eval-set.sh` skips `docker-compose.yml` -> `feed` went red: "the rule does not flag the sample bad-feed-compose"
mutation: `Remove` skips deleting the resource -> `TestFeedRemoved` went red (leftovers `resource,grant`; the role's Resources differ; Install fails with #891)
mutation: `Remove` skips `Config.Namespaces.Delete` -> `TestFeedRemoved` went red (#429 "Cannot delete database EVALFEED_DATA, in use"; leftovers `namespace,database,directory,resource,grant`)
mutation: the `incidents` limit `MAX_SHARE` 8 -> 9 -> `incidents` went red: "the rule does not flag the sample bad-incidents-category" (and `bad-incidents-category-window`)
mutation: the held-out count check of `incidents` dropped -> `incidents` went red: "the rule does not flag the sample bad-incidents-held-out" (and `bad-incidents-held-out-demo`)
mutation: committed `carrier-host-not-found/case.json` `heldOut` true -> false -> `incidents` ("fewer than 2 held-out incident cases come from the test feed") and `TestFeedCasesRecorded` ("the committed case.json is the case of the definition") went red; the file was restored byte-identical
mutation: `OnAfterAllTests` skips `Fixture.Remove()` -> `TestFeedRemoved` went red (leftovers after the second instance's `OnAfterAllTests`, the role's Resources, `Reader.Productions`)
mutation: `Install` skips removing a leftover -> `TestFeedRemoved` went red ("Install succeeds over the running feed" fails with #891 "Resource %DB_EVALFEED_DATA already exists")
mutation: `Test.Eval.Cases.Hosts` loses its object-reference exclusion (Decided in-stage 17) -> `TestIncidentChecksFlagViolations` ("an object reference in an error text is not an address") and `TestIncidentFiles` went red
mutation: `TypedRecord.NewPinned` returns `..%New()` without pinning (Decided in-stage 18) -> `TestCommittedIsCurrent` (`claims-member-missing: ... differs at .sample.error`) and `TestFeedCasesRecorded` (`claims-member-missing (this run)`: the marker `MemberId(128@` is missing) went red
mutation: `check-incidents.mjs` counts every incident case instead of the first ten (`slice` dropped) -> `incidents` went red: the good sample, whose eight later incidents share one category, was flagged ("10 of the first 10 ... connection_failure")
mutation: `MIN_FEED` 9 -> 0 in `check-incidents.mjs` -> `incidents` went red: the sample `bad-incidents-feed-count` was flagged but not for its reason
mutation: the `feed` rule's `grep -Iqi` becomes `grep -Iq` -> `feed` went red: "the rule does not flag the sample bad-feed-lowercase"
mutation: the `feed` rule's namespace pattern excludes `_` before `EVALFEED` -> `feed` went red: "the rule does not flag the sample bad-feed-resource-name"
mutation: the `feed` rule loses its `_bmad/*` exemption -> `feed` went red: "the rule flags the good sample: _bmad/custom/rules.md"
mutation: the `feed` rule's class pattern matches dots only (not slashes) -> `feed` went red: "the rule does not flag the sample bad-feed-class-path"

## Auto Run Result

Status: done
Blocking condition: none

**Summary of the implemented change.** The evaluation set now holds ten incidents recorded from real IRIS failures:
- the test feed `OcuTalon.Test.Eval.Feed` (nine items that fail through `%ValidateObject`, `EnsLib.HTTP.OutboundAdapter` against the feed's own partner listener, and an ObjectScript `<UNDEFINED>`), in the namespace `EVALFEED` that `Test.Eval.Feed.Fixture` makes and removes in throwaway stacks only (refused where the throwaway's `eval/` mount is missing);
- the one grant, Read on `%DB_EVALFEED_DATA` to `OcuTalonServiceRole`, between `Install` and `Remove`;
- `docker/tests/record-eval.sh feed`, which wrote the nine `eval/<name>/` folders;
- `Test.Eval.Record` re-inducing all ten incidents on every run, with `TestFeedCasesRecorded`, `TestFeedOnlyInThrowaway` and `TestFeedRemoved`;
- the `incidents` (spread, held-out cases, source) and `feed` (CON-3) rules of `test-eval-set.sh`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Test/Eval/Feed.cls` and `Feed/*.cls` (14 classes): the production, its items, messages, typed records and `Fixture`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls`: `Recipes()`, `InstallFeed`, feed hooks and the three new tests.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`: `Hosts` leaves out the object reference of a required-property text (Decided in-stage 17).
- `docker/tests/record-eval.sh`: the `feed` mode.
- `docker/tests/test-eval-set.sh`: the `incidents` and `feed` rules, their samples and the feed enumerations.
- `eval/<name>/{case.json,snapshot.json}` for nine cases, as the recorder wrote them; `eval/orders-date-format/*` is unchanged.

**Review findings.** 36 findings from four layers: patches applied 17 (1 medium, 16 low), none deferred, 19 rejected with their reasons in the Review Triage Log. The patches: the CON-3 rule now matches in any letter case and the class written as a path; samples pin the window of the first ten, the feed count, the underscore form and the `_bmad` exemption; `Fixture.Record` refuses before it empties a folder; `Hosts` exempts only `::Property(N@Class)`; `AssertFeedSnapshot` asserts that the item is in the snapshot; the `record-eval.sh` header names both tests again. Before review, one flake of the plan was found and removed (Decided in-stage 18).

**Follow-up review recommendation.** `false`: no high finding was patched and one medium was.

**Verification performed (lane B, runner B; tags `e9s9i`, `e9s9iw`).**
- `bash docker/tests/test-eval-set.sh`: every rule passes, including `incidents` and `feed`; seven mutations of the new samples went red and were reverted.
- `record-eval.sh feed` (fresh stack, run twice, the last one after the final patch): `record-eval: 9 feed cases written`, exit 0; `git diff --stat -- eval/orders-date-format` is empty.
- Warm: `Test.Eval.Record` (40.8 to 44.6 s), `Test.Eval.Cases`, then `Test.Watch.Tools`, `Test.Watch.Grant`, `Test.Demo.Production` and `Test.Watch.Evidence` each in its own call: all passed. Three more warm runs of `Test.Eval.Record` under 40 busy loops on 16 cores passed.
- Fresh stack: `Test.Eval.Record` passed (58.49 s); lane-a shard part 5/8 (139 s), reversed part 4/8 (162 s) and forward part 4/8 (123 s): 10 classes each, all passed.
- `eval/run.sh`: `eval/run: all checks passed`, the ten incident cases among the skipped.
- `bash docker/tests/test-boundaries.sh` and `bash ci/checks.sh`: all blocks passed.
- Teardown: both tags removed, the lane-b lock folder is empty, no `e9s9` container remains.
- The slot (`ocutalon-slot-b`) was used for compile checks only.

**Residual risks.**
- CI time: `Test.Eval.Record` takes 41 to 58 s here against 11 to 15 s before the feed (75 s guard not reached). The estimate for the `shards` job is 0.5 to 2 min (inference); the lead's CI gate measures the real job.
- The pin of the object-reference number relies on released numbers being reused last in, first out (measured on build 154U in a throwaway). If a job ever holds numbers above 128, `TestFeedCasesRecorded` reports `claims-member-missing` at once.
- `Fixture.Record` and `record-eval.sh feed` run by hand only; `TestCommittedIsCurrent` re-checks their output on every CI run.
- On a CI host with no resolver the `carrier-host-not-found` failures may take longer than 5 s a message; the error text does not carry the cause.
- The feed's partner (port 9381) is a listener of the feed inside the throwaway; a runner that uses that port for something else would fail the class with the reason in `Missing`.
