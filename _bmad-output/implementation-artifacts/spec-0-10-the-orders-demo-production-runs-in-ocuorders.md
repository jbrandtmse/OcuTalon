---
title: 'Story 0.10: The Orders demo production runs in OCUORDERS'
type: 'feature'
created: '2026-10-20'
status: 'done'
baseline_revision: 'e674ae3656a49c95cf8c67d1557cc2e3200d3a4d'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: >-
      A failed order's header has Status 8 (Error), IsError 0 and an empty ErrorStatus, and its error text exists only as the event-log row inside the "Terminating BP" wrapper, where the spec's matrix row 10 said IsError 1 and GetErrorText with the bare sentence.
    evidence: |-
      Measured in a throwaway (Task 0.3b): IsError and ErrorStatus are set only on error response headers (Ens.MessageHeader NewErrorResponse), and the partner sends asynchronously. The event-log row (Type 2, ConfigName OrdersFromPartner) reads "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'. > ERROR #5001: ...". The Rule 22 ruling is in the Spec Change Log; the spine and epics.md do not mention IsError. Lane A's reader (Stories 5.1, 5.2, 5.4 and the fallback line of 6.1) must key on Status 8 and the event log, parse the sentence out of the wrapper, and the matrix row 10 wording of this spec should be restated by the lead.
    location: >-
      src/ocutalon/cls/OcuTalon/Demo/Orders/Translator.cls
    severity: medium
  - summary: >-
      The non-Health image path of the Demo step (the ENSTEMP and SECONDARY databases, and the SECONDARY resource and role that the off path removes) has no run in the repository or in CI.
    evidence: |-
      CI and ci/iris.sh hold only the Health base image and never pull; the only evidence is the hand run of Task 0 step 4 recorded under Verification (W2' equals W0' and W3' equals W1' after the removal was added). Deleting the removal of those objects keeps every repository check green on the Health image.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls (System, off path)
    severity: medium
  - summary: >-
      The branches of Demo.Orders() and Demo.System() that run only from a foreign or partial state have no test: a foreign production in OCUORDERS, RecoverProduction, the start-timeout error, a database entry with another directory, a mapping Modify, and the cleanup of a directory that has no CPF entry.
    evidence: |-
      Rows 1 to 8 start only from everything absent or everything present, and a search of the test trees and docker/tests for these error texts finds nothing. Deleting the foreign-production guard keeps rows 1 to 8 green. The fixtures need a foreign state in an existing row of the install scripts (the spec forbids new restarts and units), in the style of test-production.sh's ZzOther.Production.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls (Orders, System)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The demo path has no production to watch and break.
- Story 0.2 left `OcuTalon.Install.Step.Demo` as a stub, and no demo-mode setting exists yet.
- OCUORDERS, the Orders production and its real transform don't exist.
- `eval/` holds no recorded failure for Lane A's watch and diagnosis tests.

**Approach:**
- **The Demo step.** At every start it seeds and reads the demo-mode setting. With demo mode on, it creates OCUORDERS through the `Config` classes and enables Interoperability there without a HealthShare Foundation. It adds the trace application and the trace role's OCUORDERS grants, then starts `OcuTalon.Demo.Orders.Production`. With demo mode off, it removes everything it created.
- **The Orders production.** It holds a simulated partner service, a business process that runs a real DTL transform, and a target operation. An order whose date is `MM/DD/YYYY` fails in the transform as a real IRIS error. An order whose date is `YYYY-MM-DD` goes through.
- **The snapshot.** `eval/orders-date-format/` holds one recorded 50-order failure: a reader snapshot plus its expectation. Throwaways mount the folder read-only at `/opt/ocutalon/eval`, so IRIS tests can read it.
- **Tests.** Unit tests run on slot A. The end-to-end tests run in a throwaway's OCUORDERS. The on, off and upgrade checks ride on the existing restarts of the `install` group's two live scripts.

## Boundaries & Constraints

**Always:**
- **Namespace switching (AD-3).**
  - `Install.Step.Demo` switches namespace in exactly two methods, each with `New $NAMESPACE`: one to `%SYS`, one to OCUORDERS.
  - Code that runs while `$NAMESPACE` is OCUORDERS calls only `OcuTalon.Demo.Orders.*`, `Ens*`/`EnsLib*` and `%` classes. Only those resolve there (the package mapping).
  - This rule covers the step's OCUORDERS method and the test helpers.
- **The `OcuTalon.Demo.Orders` package** references only its own classes, `Ens*`/`EnsLib*` and `%` classes (spine L90).
  - Its messages extend `Ens.Request` and commit their compiler-generated `Storage` blocks. They set no `DEFAULTGLOBAL` (AD-3, AD-5).
  - They carry no names, user names, phone numbers or `SessionRef`.
- **Idempotent every start.** The step re-runs safely at every start, and again whenever 4.1 switches demo mode.
  - It creates only what is missing, and never recreates a database file that exists (AD-5).
  - It touches only what it owns: the namespace OCUORDERS whose databases are `OCUORDERS_CODE` at `<mgr>ocuorders_code/` and `OCUORDERS_DATA` at `<mgr>ocuorders_data/`, and the objects named in Tasks.
- **Both images.** The step works on the Health image and the non-Health one. Nothing depends on a Foundation artefact or a `/csp/<ns>` default application.
- **Source text.** Comments state contracts (Rule 14). Write non-ASCII as escapes. Every class compiles on slot A with no warning.
- **Runtime targets (Rule 21).**
  - Slot A (`ocutalon-slot-a`, namespace `OCUTALON` named on every MCP call) is for loads and `%UnitTest` runs, one class per call.
  - Anything that creates or deletes a namespace or a database, or needs OCUORDERS, runs only in throwaways through `ci/iris.sh` or `lib-live.sh`, one stack at a time.

**Never:**
- **Files left unchanged.** Change none of these:
  - `docker/merge.cpf`: it never creates OCUORDERS (AD-23);
  - the judges' `docker-compose.yml`, `docker/Dockerfile` and `.dockerignore`: `eval/` stays out of the image;
  - `ci/compose.ci.yml`;
  - `OcuTalon.Production`, the registry's order, the `Roles` step and the after-start scripts.
- **No autostart and no Foundation.** The Orders production is not marked autostart. No Foundation installer runs for OCUORDERS. OcuTalon deletes no Foundation artefact (AD-3).
- **No model and no keys.** No model request. No key in any file. Never read `.env`.
- **No new CI unit.** No new live unit, compose stack, CI group or `ci.yml` change. No new restart in the live scripts.
- **No Lane A product class.** None is built (`OcuTalon.Eval`, `.Watch`, `.Fix`).
- **Never on a slot.** OCUORDERS is never created on a slot, and no slot is stopped or recreated. `ocutalon-aihub-test`, `ocupilot*` and `iris-community-edition` are never touched.
- **Never edited:** `.claude/`, `CLAUDE.md`, `irislib/` and `irissys/`.
- **Forbidden output.** No `docker compose config` without `--quiet`, and no `docker inspect` without `--format`. No local machine path in any tracked file.

## I/O & Edge-Case Matrix

Where the rows run ("script row" means a row of a live script, not of this matrix):
- Rows 1–5 and 8: `docker/tests/test-install-start.sh` and `test-install-upgrade.sh`, the `install` group.
- Rows 6, 7 and 16–19: `OcuTalon.Test.Demo.Step`, `.Test.Demo.Orders` and `.Test.Contract.Ac`, on slot A and in `lane-b`.
- Rows 9–15: `OcuTalon.Test.Demo.Production`, shard `lane-b`, throwaway only.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|---|
| 1 | Docker first start | Fresh volume | See "Row 1 in full" below this table | Any part fails: `STEP Demo FAILED <one line>`, no ready marker |
| 2 | A later start, demo mode on | Script row 4's stop and start; `test-install-upgrade.sh`'s recreates | Nothing is recreated: the database files and the data are kept (row 8's probe). The production is started again, and its items run | — |
| 3 | Switch off | `demo.mode` set to `0`, then script row 2's restart | See "Row 3 in full" below this table | — |
| 4 | Off at later starts | Script row 3's recreate with the dev compose file | Still absent, and the step is a no-op | — |
| 5 | Switch on again | `demo.mode` set to `1`, then script row 4's recreate | Recreated: the surfaces equal row 1's exactly, and the production runs | — |
| 6 | No image version file (the IPM case) | `DefaultMode(<absent file>)` | 0. A fresh seed writes `0`, and `Plan(0, 0, 0)` does nothing | — |
| 7 | A foreign OCUORDERS | `Plan(on, exists=1, owned=0, .sc)`; `Owned("USER")` | On: "error", with `sc` = "Namespace OCUORDERS exists and uses databases that OcuTalon did not create, so the Demo step leaves it alone.", which `Run` returns, so the log shows `STEP Demo FAILED` with it. Off: "leave", with `sc` OK. `Owned` of a namespace whose databases aren't the step's own is 0 | — |
| 8 | Upgrade, demo mode on | `test-install-upgrade.sh`'s v1 and v3 recreates | The probe order's errored header from the first start is still in OCUORDERS. The `demo.mode` row's `UpdatedAt` is unchanged, and the production runs | — |
| 9 | One order in the expected format | `Partner.Send(1,"YYYY-MM-DD",ref,"2026-10-16")` | Its `PartnerOrder` header at `OrdersFromPartner` completes with no error. A `WarehouseOrder` with `OrderDate` = `$ZDATEH("2026-10-16",3)` completes at `OrdersToWarehouse`. `SuperSession` = `ref` | — |
| 10 | One order in the changed format | `Partner.Send(1,"MM/DD/YYYY",ref,"2026-10-16")` | One errored header at `OrdersFromPartner` (`IsError` 1), body `OrderDate` "10/16/2026". `GetErrorText` = "ERROR #5001: The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'." No `WarehouseOrder`. `SuperSession` = `ref`, and its session differs from row 9's | the real transform error |
| 11 | No partner state | `Send(3,"MM/DD/YYYY",refA)`, then `Send(2,"YYYY-MM-DD",refB)` | `refA`: 3 errored. `refB`: 2 completed, 0 errored. Each order is in its own session | — |
| 12 | Bad batch | Count 0, 1001 or "x"; format "DD.MM.YYYY"; order date "10/16/2026"; trace reference "abc" | `Send` returns an error naming the value, and nothing is sent (no new header for the reference) | plain English |
| 13 | A repaired copy (7.3) | Row 10's failed header. `Ens.MessageHeader.ResendDuplicatedMessage(id,,"OrdersFromPartner",copy)`, where the copy has `OrderDate` "2026-10-16" | The copy completes, and a `WarehouseOrder` reaches `OrdersToWarehouse`. The original stays errored. The copy keeps `SuperSession` | — |
| 14 | The eval snapshot | `/opt/ocutalon/eval/orders-date-format/{case.json,snapshot.json}` in the throwaway | See "Row 14 in full" below this table | missing file or a mismatch: red |
| 15 | No OCUORDERS | `Test.Demo.Production` on slot A | Every test fails with "OCUORDERS does not exist: this class runs in throwaways and CI only (Rule 21)" | by design |
| 16 | The transform alone | `Transform.Transform(order,.out)` in OCUTALON with `OrderDate` "2026-10-16", "10/16/2026", "", "2026-02-30", "2026-1-6", "16.10.2026" | OK and the `%Date` for the first. Each of the others gives row 10's error text with its own value | — |
| 17 | The batch alone | `Partner.Orders(batch,.orders)` | Count 3, "MM/DD/YYYY", "2026-10-16": "PO-0001" to "PO-0003", each dated "10/16/2026", with the fixed Sku and Quantity cycle. An empty order date gives today's local date. Row 12's bad values give their errors | — |
| 18 | The seed | `Mode()` with the row absent, then with `0` and with `1` | Absent: it writes `DefaultMode()` and returns it. Present: returns the value (on iff "1") and leaves the row untouched. The row's prior state is restored | — |
| 19 | Signatures and contracts | `Test.Contract.Ac`, `Test.Demo.Orders` | `Partner.Send(count,dateFormat,traceRef,orderDate)` returns `%Status` (floor 48). `PartnerOrder` and `WarehouseOrder` have exactly their contracts and the `Ens.MessageBody` extent | renamed or reordered: red |

**Row 1 in full.** After the fresh start:
- `demo.mode` = `1`.
- OCUORDERS exists. Globals are `OCUORDERS_DATA` and routines `OCUORDERS_CODE`, at `<mgr>ocuorders_data/` and `<mgr>ocuorders_code/`.
- The resources `%DB_OCUORDERS_CODE` and `%DB_OCUORDERS_DATA` exist, with no public permission.
- In OCUORDERS:
  - the packages `OcuTalon.Demo.Orders` resolve to `OCUTALON_CODE`;
  - `OcuTalon.Web.Public` and `OcuTalon.Data.Public` resolve to `OCUTALON_PUBLIC`;
  - `^OcuTalonPublic` resolves to `OCUTALON_PUBLIC`.
- Interoperability is enabled, and no HealthShare mapping or instance marker exists for OCUORDERS.
- The Orders production runs, with `OrdersFromPartner` and `OrdersToWarehouse` alive.
- `/ocutalon/trace/ocuorders` has `TraceApp`'s properties.
- `OcuTalonTraceViewer` adds `%DB_OCUORDERS_CODE:R,%DB_OCUORDERS_DATA:R`, and SQL `SELECT` on `Ens.MessageHeader` in OCUORDERS.
- The log has `STEP Demo OK`.

**Row 3 in full.** After the restart:
- OCUORDERS, both databases, their directories and their resources are gone.
- So are its mappings, the Interop markers, `%EnsRole_ProdPrivs_OCUORDERS`, and every web application of the namespace.
- The trace role's OCUORDERS grants are gone, and so is every `Security.SQLPrivileges` row of the namespace.
- The surfaces equal row 1's with every line naming OCUORDERS dropped.

**Row 14 in full.**
- `case.json` has kind `incident`, `heldOut` false, and the expectation `data_format_change`, `OrderDate`, `repair_resend`.
- `snapshot.json` has 50 failures at `OrdersFromPartner`, each with `OrderDate` "10/16/2026" and row 10's error. It also holds the three items' settings and a trace excerpt.
- Its projection equals the projection of a fresh 50-order recording.

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line:
  - **AD-3, L122–150:**
    - OCUORDERS, its package mapping and the Demo step's job, L141;
    - the switching list, L142–147;
    - the service user's read on a data database, L148;
    - the Foundation sentence, L150 ("OcuTalon never deletes Foundation artefacts", "Nothing in OcuTalon depends on either").
  - **AD-4, L156–157:** "demo orders" among a session's records; `TraceRef` as the demo tag.
  - **AD-5, L175–185:** OCUORDERS's data database is durable, with no private database; storage is append-only.
  - **AD-19, L497:** demo mode in `Data.Setting`, as a seed.
  - **AD-22, L575–598:** the evaluation set in `eval/`, L592–595.
  - **AD-23, L599–644:** the Demo step's place and its off rule, L614; the IPM install with demo mode off, L635.
  - **AD-24, L645–672:** the trace role's OCUORDERS grants and the trace applications, L652–658.
  - **AD-26, L724–728:** `SuperSession` is set inside `OnProcessInput`.
  - **AD-29, L764:** Epic 0's scope includes the Orders production and the snapshot. Lane A owns `eval/`, L770.
  - **Other lines:**
    - the dependency diagram, L90 (Orders → Ens only);
    - the Demo flow, L1009;
    - the source tree, L1151 (`eval/`);
    - S8, the resend into OCUORDERS, L449–450 and L1220.
- **Epics** (`_bmad-output/planning-artifacts/epics.md`):
  - **The story and its source:** this story is at L1019–1032; the split is at L937.
  - **Earlier stories:**
    - 0.2 L792 (the step order);
    - 0.3 L838 (the OCUORDERS trace application).
  - **Consumers:**
    - 3.1 L1842–1843 (the trace grants);
    - 4.1 L2072–2085 (`SetDemoMode`, `SettingsOps` reruns the step);
    - 4.3 L2138–2144 (`PartnerTrigger` and the partner contract);
    - 5.1 L2313 ("Orders" matched by display name);
    - 5.2 L2353;
    - 5.4 L2400, L2414 and L2421–2423 (the snapshot's use);
    - 7.1 L2691, L2699 and L2702 (the field and the formats);
    - 7.3 L2772–2774;
    - 7.4 L2787–2800 (500 orders);
    - 9.2 L3017 (an expectation is required);
    - 9.4 L3064–3069 (`Eval.Record`'s contents);
    - 11.2 L3301;
    - 15.2 L3905–3910 (IPM: OCUORDERS absent, and `SetDemoMode(1)` creates it).
- **PRD** (`_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md`): FR-16 L452–467 (L457: on for Docker, off for IPM; L461: "none of these exist, and nothing else changes"; L467: nothing canned); FR-56 L1023; REL-4 L1289–1293; CON-3 L1223–1225.
- **UX** (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`): L276 ("Data format change · order date · 50 failures…"), L286 (raw errors and item names appear as IRIS shows them), L769 ("order date 10/16/2026 becomes 2026-10-16"), L789–795 (the fallback line: the item name and the error's first sentence).
- **Code (product):**
  - **`src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls`:** the stub, filled in place. Its doc line 2 still names Story 0.6.
  - **`Install/Step.cls`:** the base class (`Run`, `Grants`, `Reconcile`, `Tasks`, `Purge`). It has no helpers.
  - **`Install/Registry.cls`:**
    - `Order()`, L12–15: Demo is the 8th of 15;
    - `RunStep`, L117–131: Try/Catch, `STEP <name> OK|FAILED`;
    - `Run(caller)`, L41: it runs only in OCUTALON.
  - **`Install/Step/Web.cls`:**
    - `TRACEROLE`, L17;
    - `TraceApp(namespace, .props)`, L128, which returns `/ocutalon/trace/<ns lower>`;
    - `Apply(name, .props)`, L161, which switches to `%SYS` itself;
    - `GrantTraceSql(role)`, L274, which works in the current namespace;
    - `Grants()`, L78, whose comment says "The OCUORDERS grants are the Demo step's".
  - **`Install/Step/Roles.cls`:** `Apply`, L57–83, rewrites every role to exactly its composed resources at every start. So the Demo step adds its grants back after it.
  - **`Install/Step/Production.cls`:**
    - `Start(wait)`, L50–83: the state machine;
    - `NotRunning()`, L87–110: the item-run predicate with `Ens.Job:Enumerate` and the `$$$Config*` macros (`Include Ensemble`);
    - `WAITSECONDS` 60 and `STOPSECONDS` 30;
    - `Other()`, L157.

    Its methods are hard-coded to `OcuTalon.Production` and don't resolve in OCUORDERS.
  - **`Data/Setting.cls`:** `Get(key, default)`, L26–40, with its 60-second process cache; `Seed(key, value)`, L44–55, which writes only when absent and drops this process's cache entry. It has no setter: `SettingsOps` (4.1) owns writes.
  - **`Data/Public/Settings.cls` L9:** `KEYS`. `demo.mode` is not public.
  - **`Demo/BreakFeedIn.cls`** (an adapterless `Ens.BusinessService` stub) and **`Demo/PartnerTrigger.cls`** (an `Ens.BusinessOperation` stub). Both are OCUTALON items owned by 4.3. They are the siblings for the Orders host classes.
  - **`Core/Intake.cls`:** the business-process sibling. It has no persistent property, and its `Storage Default` is `<Type>%Storage.Persistent</Type>`.
  - **`src/bridge/cls/OcuTalon/Bridge/Ids.cls` `NewRef()`:** the 22-character references.
  - **`src/module.xml`:** `OcuTalon.PKG` (`ocutalon/cls`) already compiles `OcuTalon.Demo.Orders.*` into `OCUTALON_CODE`.
- **Code (tests):**
  - **`Test/Contract.cls`:** `AssertContract`, L19; `AssertMessageExtent`, L31 (no `DEFAULTGLOBAL`, data at `^Ens.MessageBodyD`); `Read`, L72. The new orders test extends it.
  - **`Test/Contract/Ac.cls`:** `TestCrossLaneSignatures`, L140–162 (floor `count >= 47` at L162); XData `Signatures`, L289.
  - **`Test/Install/Production.cls`:**
    - `DefinitionText()`, L279, which reads the compiled `ProductionDefinition` XData;
    - `Describe(item As Ens.Config.Item)`, L287.
  - **`Test/Install/Registry.cls` `TestRolesStep`, L102–115:** runs the real `Roles.Run()`, which strips the trace role's OCUORDERS grants in a throwaway until the next start.
  - **The namespace-switch pattern in tests:** `Test/Web/Install.cls` L430–487, `Test/Install/Users.cls` L86–131 (DW-7, accepted).
- **Shell:**
  - **`docker/tests/lib-live.sh`:**
    - `live_start`, L53–84;
    - `dc`, L239;
    - `iris_script <ns>`, L303;
    - `check_session`, L465;
    - `session_value`, L473;
    - `security_app_props`, L481, which hard-codes `NameSpace=OCUTALON`;
    - `check_security`, L493–518, which pins the trace role exactly at L503 and four applications;
    - `set_probes` and `check_probes`, L522–552;
    - `expected_run`, L569–575, which already lists `STEP Demo OK`;
    - `live_pop_file`, L590;
    - `item_jobs`, L596–601 (OCUTALON only);
    - `check_items_run`, L610;
    - `check_clean_start`, L640 (OCUTALON's event log only).
  - **`docker/tests/test-install-start.sh`:**
    - row 1 (fresh), L65–119;
    - row 2 (stop and start), L123–148;
    - row 3 (dev-file recreate), L152–171;
    - row 4 (recreate, then delete the public `Settings` class, then stop and start), L175–193;
    - row 5, L200–255.
  - **`docker/tests/test-install-upgrade.sh`:**
    - the first start, L97–110;
    - row 6 (v1), L151–166;
    - row 15, part 2, with `check_security`, L170–181;
    - row 7 (broken SSL; `Demo` is not run), L185–233;
    - v3, L236–244.
  - **`docker/tests/test-sign-in.sh` L54:** `check_security`.
  - **`docker/tests/test-production.sh` L296–349:** `ZzOther.Production`, the fixture-loading sibling.
  - **`docker/tests/test-boundaries.sh`:**
    - `scan_files`, L96–99: paths and keys cover the whole tree, `eval/` included, while ASCII covers only the listed folders;
    - the must-scan lists, L107–123 (`all_files` at L118);
    - `key_like`, L40.
  - **`docker/tests/compose.throwaway.yml`:** the test-only override in every throwaway (`lib-live.sh` L81, `ci/iris.sh` L360). No test pins its contents exactly; `test-compose-file.sh` L239 only parses it.
  - **`docker/tests/test-compose-file.sh` L210–239:** pins `ci/compose.ci.yml` exactly, with no volume.
- **Recipe:**
  - `ci/units.sh` L15–21: `lane-b` is "Contract Core Data Live Msg Web", and gets Demo;
  - `docker/tests/test-ci-config.sh` L549–597: each `Test/<Area>/` folder is in exactly one shard, and only `test-*.sh` scripts count as units;
  - `ci/changes.sh` L107: `eval/` and `Demo/` set `iris=true`;
  - `_bmad/custom/skill-rules.md` L254: Rule 21's "29 classes: 9 in `lane-a`, 20 in `lane-b`".
- **IRIS build 154 APIs (`irislib/`, `irissys/`; read only):**
  - **`%Library.EnsembleMgr`:**
    - `EnableNamespace(pTargetNS, pVerbose, .pIsPrimary, pFromInstall, …)`, L1738. It needs a live namespace first (L1741).
    - The Health branch: L1774–1782 (portal prefix) and L1816–1818. With `pFromInstall` 0 it calls `%ZHSLIB.HealthShareMgr.EnableHealthShareNamespace`, which installs a Foundation.
    - `createPortal`, L2648 (`/csp/<prefix><ns>` and a directory under `<data>csp/`).
    - On the non-Health image only: `createNewDBForEnsTemp` (L1857) and `CreateNewDBForSecondary` (L1866). They create `<datadb>ENSTEMP` and `<datadb>SECONDARY` in subdirectories of the data database.
    - `DisableNamespace`, L1892, kills only the `^%SYS` markers.
    - `IsEnsembleNamespace`, L79; `deleteNamespace`, L3330 (the removal model); `CleanupProdPrivs`, L3469.
  - **The role-name macro:** `%sySecurity.inc` L230, `$$$InteropNSRole(ns)` = `"%EnsRole_ProdPrivs_"_ns`.
  - **`SYS.Database`:**
    - `CreateDatabase(Directory, Size, BlockSize, Encrypted, Resource, …)`, L590 (the directory must exist, L589);
    - `DeleteDatabase(Directory)`, L619, which needs no dismount;
    - `%ExistsId` and `%OpenId`.
  - **`Config.Databases`:** "does NOT perform any actual operations on database files" (L8–9). Property `Directory`.
  - **`Config.CommonMultipleMethods`:** `Create(Name, .p)`, L43; `Delete`, L71; `Exists`, L96.
  - **`Config.Namespaces`:** properties `Globals` and `Routines`; `Interop` is transient, L120.
  - **The mapping classes:** `Config.CommonMapMethods.Create(Namespace, Name, .p)`, L49, with property `Database`. A global mapping's name has no caret (`OcuTalonPublic`).
  - **`Security`:**
    - `Security.Resources.Create(Name, Description, PublicPermission)`, L83;
    - `Security.Roles.Get` and `Modify` (`p("Resources")`);
    - `Security.SQLPrivileges` (IdKey `Namespace, SQLObject, Privilege, Grantee, Grantor`), stored in `%SYS`;
    - `Security.Applications`.
  - **`$SYSTEM.SQL.Security.GrantPrivilege(ObjPriv, ObjList, Type, User)`** (`%SYSTEM/SQL/Security.cls` L130) acts on the current namespace.
  - **`Ens.Director`:**
    - `StartProduction`, L15;
    - `StopProduction(timeout, force)`, L216;
    - `GetProductionStatus`, L531;
    - `IsProductionRunning`, L601;
    - `RecoverProduction`, L688;
    - `CreateBusinessService(name, .svc)`, L1450.

    All of them act on the current namespace.
  - **DTL:**
    - The generated `Transform(source, .target, aux)`, `Ens/DataTransformDTL.cls` L180.
    - An `<assign>` whose value throws ends the transform with that error status: `Ens/DTL/Assign.cls` L231–234 and `Ens/DTL/Transform.cls` L293–305.
  - **The routing engine:** `EnsLib/MsgRouter/RoutingEngine.cls` L393–399 wraps a transform error as "Not routing to target(s) … because of error in Transform …", and swallows it unless `ActOnTransformError` is set.
  - **Business service:** `Ens/BusinessService.cls` L98–99 (`preProcessInput` clears `%SuperSession`); `Ens/Host.cls` L58–65 (`%SuperSession`).
  - **Message header:** `Ens/MessageHeader.cls` `ResendDuplicatedMessage(id, .newId, target, body, …)`, L443. `Ens/MessageHeaderBase.cls`: `Status` L31, `IsError` L34, `ErrorStatus` L37, `SuperSession` L79, and `TimeCreated` (UTC) L25.
- **Read-only evidence (plan stage, October 20):**
  - **Slot A** (`ocutalon-slot-a`) is build 154 Health, with ENSEMBLE and HEALTHSHARE.
    - Namespaces: `%SYS`, `HSCUSTOM`, `HSLIB`, `HSSYS`, `HSSYSLOCALTEMP`, `OCUTALON` and `USER`. There is no OCUORDERS.
    - OCUTALON's mappings include the Foundation's (`HS`, `HSMOD`, `SchemaMap` and `%pkg.isc` to HSLIB). So the CPF merge's `Interop=1` installed a Foundation there.
  - **Images.** `ocutalon-iris-base:2026.3.0AI.154.0` is the Health image, arm64. `iris-community:2026.3.0AI.154.0` (non-Health) is present on this machine.
  - **Existing state.** No demo-mode key exists and nothing seeds one. `/state` has no demo field (the badge is 2.1's).
  - **The ledger.** `LEDGER slice 0-10-the-orders-demo-production-runs-in-ocuorders` is empty. DW-13 (the storage roots) is `resolved-by` 0.6.
  - **CI.** The `iris (install)` group took 12 min 45 s on run 39365579762 (`install-start` 369 s, `install-upgrade` 323 s), and 11 min 51 s on run 39374739457. A later start or recreate takes about 47–58 s on x64.

## Tasks & Acceptance

**Execution:**

**Task 0: measure first** (Rule 22.2.5). Record every value under Verification, and label anything not measured `(inference)`. Use one throwaway at a time with tag `v10a`. A scratch script lives outside the repo and sources `docker/tests/lib-live.sh`, as 0.9's DW-28 experiment did.

1. **Before any product code**, write `demo_surfaces` and its `--wide` variant into `lib-live.sh` (as specified under "Live checks" below).
2. **Baseline W0.** Start a throwaway of the tree as it is (the Demo step still a stub) and record `demo_surfaces --wide`. Then tear it down.
3. **Once the "Orders production" and "The Demo step" tasks below are done, on the Health base image:**
   - **(a) The first start with demo mode on.** Record:
     - `W1`;
     - `STEP Demo`'s seconds;
     - whether OCUORDERS got any HealthShare artefact: an `HS`, `HSMOD`, `SchemaMap` or `%pkg.isc` mapping, `^%SYS("HealthShare","Instances","OCUORDERS")`, or a Foundation production class;
     - every web application, role, resource, database and `Security.SQLPrivileges` row it created, with the portal application's `AutheEnabled` and `Path`.
   - **(b) One order in each format.** Record each header's `Status`, `IsError`, `ErrorStatus` text, `TargetConfigName`, `SuperSession` and `SessionId`. Record the event-log rows the error wrote (type, `ConfigName`, text). Also record:
     - whether `SELECT COUNT(*) FROM OcuTalon_Demo_Orders.PartnerOrder` works in OCUORDERS;
     - whether compiling the Orders production class in OCUTALON registers anything there;
     - whether a method of the same class can be called after `$NAMESPACE` switches to OCUORDERS.
   - **(c) Off, then on.** Set `demo.mode` to `0` and restart, then record `W2` and `STEP Demo`'s seconds. Compare W0 with W2: each difference is a leftover. Set `1` and restart, then record `W3` and compare W3 with W1.
   - **(d) The comparison route.** In the same throwaway, create a scratch namespace `ZZINTEROP` with scratch databases through `Config.Namespaces.Create` with `Interop=1`. Record whether a Foundation was installed and how long it took. The throwaway's teardown removes it.
4. **The same on the non-Health image.** Run with `IRIS_IMAGE=iris-community:2026.3.0AI.154.0` exported. Record W0', W1', W2' and the `ENSTEMP`/`SECONDARY` databases' names and directories.
5. **The mount.** Once the `compose.throwaway.yml` task below is done, confirm that the `eval/` bind mount is visible at `/opt/ocutalon/eval` in a throwaway and byte-equal to the repository's files (`sha256sum`).
6. **Act on what you measured:**
   - Every leftover from steps 3c and 4 becomes an explicit removal in the Demo step's `System(0)` and a line of `demo_surfaces`.
   - If the portal application answers without sign-in (`AutheEnabled` includes 64), the on path sets it to 32. This is a VETO WINDOW FYI.
7. **HALT `blocked` with `intent gap`** in any of these cases, with the recommended amendment from Design Notes:
   - (i) The Foundation-less route still installs HealthShare artefacts in OCUORDERS, or the production can't run without them. This names AD-3 L150.
   - (ii) A leftover can't be removed without changing something the step didn't create. This names FR-16's "nothing else changes".
   - (iii) The package-mapped classes don't resolve in OCUORDERS, or the production can't start there. This names AD-3 L141.

**Orders production (Lane B, `OcuTalon.Demo.Orders`).** Each class has a contract doc comment.
- **`src/ocutalon/cls/OcuTalon/Demo/Orders/PartnerOrder.cls` (new):** extends `Ens.Request`. It holds the order as the partner sends it:
  - `OrderNumber`, `OrderDate` and `Sku`: `%String(MAXLEN = 20)`;
  - `Quantity`: `%Integer(MINVAL = 1)`.

  It sets no `DEFAULTGLOBAL`, and its generated `Storage` block is committed.
- **`.../WarehouseOrder.cls` (new):** extends `Ens.Request`. It is the transformed order: `OrderNumber`, `Sku` (as above), `OrderDate As %Date` and `Quantity As %Integer(MINVAL = 1)`. Its storage is committed. The name avoids the SQL reserved word `ORDER`.
- **`.../Batch.cls` (new):** extends `%RegisteredObject`, not a message, so it has no storage. Properties:
  - `Count As %Integer`;
  - `DateFormat As %String`: `YYYY-MM-DD` or `MM/DD/YYYY`;
  - `OrderDate As %String`: `YYYY-MM-DD`, where "" means the partner's today;
  - `TraceRef As %String`: "" or 22 characters.
- **`.../Partner.cls` (new):** the simulated partner, an adapterless `Ens.BusinessService` (sibling `Demo/BreakFeedIn.cls`).
  - **Parameters:** `ITEM = "PartnerOrdersIn"`, `FORMATS = "YYYY-MM-DD,MM/DD/YYYY"`, `MAXCOUNT = 1000`, and a fixed `SKUS` list of 5.
  - **The setting:** `Property TargetConfigName As Ens.DataType.ConfigName` with `Parameter SETTINGS = "TargetConfigName:Basic"`.
  - **`ClassMethod Orders(batch As Batch, Output orders) As %Status`** is pure and validates first. Each failure is `$$$GeneralError` with one of these texts, where `<x>` is the value given:
    - "The batch size must be a whole number from 1 to 1000, not '<x>'."
    - "The date format must be YYYY-MM-DD or MM/DD/YYYY, not '<x>'."
    - "The order date must be a date written YYYY-MM-DD, not '<x>'."
    - "The trace reference must be empty or 22 characters of A-Z, a-z, 0-9, - and _, not '<x>'."

    Order `i` gets:
    - `OrderNumber` "PO-" followed by `i` as four digits;
    - `OrderDate` in the batch's format (from `OrderDate`, or `$ZDATE($HOROLOG,3)` when empty);
    - `Sku` = the `((i-1)#5+1)`th of `SKUS`;
    - `Quantity` = `(i-1)#4+1`.
  - **`OnProcessInput(pInput As Batch, Output pOutput)`:** for each order, `Set ..%SessionId = ""`, then `Set ..%SuperSession = pInput.TraceRef` inside `OnProcessInput` (AD-26), then `SendRequestAsync(..TargetConfigName, order)`. It keeps no state between calls.
  - **`ClassMethod Send(count As %Integer, dateFormat As %String, traceRef As %String = "", orderDate As %String = "") As %Status`:** the cross-lane entry, to be called in OCUORDERS. It builds a `Batch`, calls `Orders` to validate, then calls `Ens.Director.CreateBusinessService(..#ITEM, .svc)` and `svc.ProcessInput(batch)`.
- **`.../Transform.cls` (new):** extends `Ens.DataTransformDTL`. Its source is `PartnerOrder` and its target `WarehouseOrder` (`create='new'`). It copies `OrderNumber`, `Sku` and `Quantity`, and sets `target.OrderDate` from `..OrderDate(source.OrderDate)`.
  - `ClassMethod OrderDate(value As %String) As %Date` accepts only `?4N1"-"2N1"-"2N` with a valid `$ZDATEH(value,3,,,,,,,-1)`.
  - Otherwise it does `$$$ThrowStatus($$$ERROR($$$GeneralError, "The order date was not in the expected format. Expected YYYY-MM-DD, got '"_value_"'."))`.
- **`.../Translator.cls` (new):** the transform's host, a custom `Ens.BusinessProcess` (sibling `Core/Intake.cls`). Its setting `TargetConfigName` is `[ Transient ]`, so there is no storage slot, and its `Storage Default` is committed.
  - `OnRequest(request As PartnerOrder, Output response)` calls `##class(Transform).Transform(request, .order)`, returns its error unchanged, and else does `SendRequestAsync(..TargetConfigName, order, 0)`.
  - Any other request class gives an error naming it.
- **`.../Warehouse.cls` (new):** the target, an adapterless `Ens.BusinessOperation` (sibling `Demo/PartnerTrigger.cls`). `OnMessage(request As WarehouseOrder, Output response)` accepts the order and returns OK.
- **`.../Production.cls` (new):** extends `Ens.Production`. XData `ProductionDefinition`: `Name` = the class, `TestingEnabled="false"`, `<Description>Orders</Description>`, and three items, all enabled:
  - `PartnerOrdersIn`: `Partner`, `PoolSize="0"`, setting `TargetConfigName`=`OrdersFromPartner`;
  - `OrdersFromPartner`: `Translator`, `PoolSize="1"`, setting `TargetConfigName`=`OrdersToWarehouse`;
  - `OrdersToWarehouse`: `Warehouse`, `PoolSize="1"`.

**The Demo step (Lane B):**
- **`src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls`:** fill in place, with `Include Ensemble`. Update the class doc, which still names Story 0.6.
  - **Parameters:** `MODEKEY = "demo.mode"`, `NAMESPACE = "OCUORDERS"`, `PRODUCTION = "OcuTalon.Demo.Orders.Production"`, `CODEDB = "OCUORDERS_CODE"`, `DATADB = "OCUORDERS_DATA"`, `VERSIONFILE = "/opt/ocutalon/version"`, `WAITSECONDS = 60`, `STOPSECONDS = 30`.
  - **`Run()`.** It calls `Plan(Mode(), ##class(%SYS.Namespace).Exists(NAMESPACE), Owned(), .sc)`, then acts on the result:
    - **"create":**
      1. `System(1)`.
      2. `Web.TraceApp(NAMESPACE, .props)` then `Web.Apply(name, .props)`.
      3. `Orders(1)`.
    - **"remove":**
      1. If OCUORDERS exists and is an Interop namespace, `Orders(0)`.
      2. `System(0)`.
    - **"leave":** return OK.
    - **"error":** return `sc`.
  - **`Plan(on As %Boolean, exists As %Boolean, owned As %Boolean, Output sc As %Status) As %String`:** pure.
    - On, and exists but not owned: "error", with row 7's text.
    - On otherwise: "create".
    - Off, and exists but not owned: "leave".
    - Off otherwise: "remove". This also cleans the step's own leftovers when the namespace is gone.
  - **`Mode() As %Boolean`:** `Setting.Seed(MODEKEY, DefaultMode())`, then `Setting.Get(MODEKEY)`. It returns 1 iff the value is "1". The seed also drops this process's cache entry, so 4.1's rerun reads the value it wrote.
  - **`DefaultMode(versionFile = {..#VERSIONFILE}) As %Boolean`:** `##class(%File).Exists(versionFile)`.
  - **`WithOrders(resources As %String, on As %Boolean) As %String`:** pure and idempotent. It adds `%DB_OCUORDERS_CODE:R` and `%DB_OCUORDERS_DATA:R` to a role's resource list, or removes them; any other entry stays as it was.
  - **`Directory(db As %String) As %String`:** `<ManagerDirectory()>ocuorders_code/` or `ocuorders_data/`, normalized.
  - **`Owned(namespace As %String = {..#NAMESPACE}) As %Boolean`**, with no switching. It is 1 when the namespace's default globals destination (`%SYS.Namespace.GetGlobalDest`, for a global no mapping names) is `"^^"_Directory(DATADB)`, and its default routine destination (`GetRoutineDest`) is `"^^"_Directory(CODEDB)`. It is 0 for a namespace that doesn't exist.
  - **`System(on) [ Private ]`:** its one `%SYS` method.
    - **On:**
      1. **Resources.** Each `%DB_OCUORDERS_<X>` without public permission, if absent.
      2. **Databases.** The directory (`CreateDirectoryChain`), then `SYS.Database.CreateDatabase(dir,,,,resource)` only when `IRIS.DAT` is absent.
      3. **Config entries.** `Config.Databases.Create` if absent; an existing entry with another directory is an error naming it.
      4. **The namespace.** `Config.Namespaces.Create` (`Globals` `OCUORDERS_DATA`, `Routines` `OCUORDERS_CODE`) if absent.
      5. **Mappings.** The four mappings of row 1, each created if absent, or modified when its database differs.
      6. **Interoperability.** If `'##class(%Library.EnsembleMgr).IsEnsembleNamespace(NAMESPACE)`, then `EnableNamespace(NAMESPACE, 0, , 1)`.
      7. **The portal application.** Task 0.6's setting, if it applies.
      8. **The trace role.** `Security.Roles.Get(Web.#TRACEROLE)`, then `WithOrders(…,1)`, then `Modify` only when it changed.
    - **Off:**
      1. **Applications.** Delete every web application whose `NameSpace` is OCUORDERS. Remove the portal application's `Path` directory only when it is `<data>csp/ocuorders/`.
      2. **The trace role.** `WithOrders(…,0)`.
      3. **The namespace.** `Config.Namespaces.Delete`.
      4. **Interop markers.** `EnsembleMgr.DisableNamespace(NAMESPACE)` if `^%SYS("Ensemble","InstalledNamespace",NAMESPACE)` exists. Delete `$$$InteropNSRole(NAMESPACE)` if it exists.
      5. **SQL privileges.** Delete every `Security.SQLPrivileges` row whose `Namespace` is OCUORDERS.
      6. **Databases.** For each database innermost first (the non-Health `…ENSTEMP` and `…SECONDARY` from Task 0, then DATA, then CODE), only when its directory is the step's own or a subdirectory of it:
         1. `Config.Databases.Delete`;
         2. `SYS.Database.DeleteDatabase(dir)` when `IRIS.DAT` exists;
         3. `%File.RemoveDirectoryTree(dir)`.
      7. **Resources.** Delete the step's resources, and any same-named role.
      8. **Task 0's leftovers.**

      Every action runs only when its object exists, so the off path is a no-op when nothing is there.
  - **`Orders(on) [ Private ]`:** its one OCUORDERS method. It calls no method of its own class while there.
    - **On:**
      - **The SQL grant.** `$SYSTEM.SQL.Security.CheckPrivilege(role,1,"Ens.MessageHeader","s")`, else `GrantPrivilege("SELECT","Ens.MessageHeader","TABLE",role)`.
      - **The production.** `GetProductionStatus(.name,.state)`:
        - Running and ours: leave it;
        - Running, Troubled or Suspended with another non-empty name: an error naming it, and nothing is stopped;
        - Troubled: `RecoverProduction()`, then `StartProduction(PRODUCTION)`;
        - Stopped or Suspended: `StartProduction(PRODUCTION)`.

        Then it polls once a second up to `WAITSECONDS` until `IsProductionRunning` names ours and every enabled item with a pool has an Alive job that isn't error, halted or terminated. That is a stated copy of `Production.NotRunning` (Design Notes).
    - **Off:** if ours is Running or Troubled, `StopProduction(STOPSECONDS, 1)`. Another production in OCUORDERS is an error, and nothing is stopped. Then `RevokePrivilege` of the grant.
  - **Errors** are `%Status` in plain English, and each names the object. Rule 2: `Web.TraceApp` and `Web.Apply` are reused.

**Tests (Lane B, new area `OcuTalon.Test.Demo`):**
- **`src/ocutalon/cls/OcuTalon/Test/Demo/Orders.cls` (new):** extends `OcuTalon.Test.Contract` (Rule 2). It runs on slot A and in `lane-b`.
  - **XData `Contracts`:** the two message classes (row 19), checked with `AssertContract` and `AssertMessageExtent`.
  - **`TestTransformAcceptsTheExpectedFormat`** and **`TestTransformFailsOnTheChangedFormat`** (row 16).
  - **`TestBatch`** (rows 12 and 17).
  - **`TestProductionDefinition`:** reads the compiled `ProductionDefinition` XData, correlated to `Ens.Config.Production` through `%XML.Reader`. The sibling is `Test.Install.Production.DefinitionText`, whose private helpers are lane A's, so they are not called. It asserts:
    - exactly the three items, with their classes, pools, `Enabled` and settings;
    - `TestingEnabled` 0;
    - the description "Orders";
    - every item class in `OcuTalon.Demo.Orders`.
- **`.../Test/Demo/Step.cls` (new):** on slot A and in `lane-b`.
  - **`TestDefaultMode`:** a `%File.TempFilename` file present gives 1; absent gives 0.
  - **`TestMode`** (row 18): saves the `demo.mode` row's state (absent, or its value and `UpdatedAt`) in `OnBeforeAllTests`, and restores it in `OnAfterAllTests`.
  - **`TestWithOrders`:** add, idempotent add, remove, remove when absent, and `%DB_OCUORDERS_DATA:RW` normalized to `R` on add.
  - **`TestDirectory`:** both directories are under `$System.Util.ManagerDirectory()`.
  - **`TestPlan`** (rows 6 and 7): all eight combinations of `on`, `exists` and `owned`, with row 7's exact error text.
  - **`TestOwned`** (row 7): `Owned("USER")` and `Owned("%SYS")` are 0, and `Owned("ZZNOSUCHNAMESPACE")` is 0. The positive case is `Test.Demo.Production`'s.
  - It never calls `Run`, `System` or `Orders`, and creates no namespace.
- **`.../Test/Demo/Production.cls` (new):** runs in throwaways only (row 15). Its header says so.
  - **Setup.** `OnBeforeAllTests` checks that OCUORDERS exists and the Orders production runs; if not, every test fails with row 15's text.
  - **Fixtures.** Each test makes its references with `Bridge.Ids.NewRef()` before it switches. Switching happens only in private helpers, which call only the classes of the Always rule and return plain values or `%DynamicObject`s. `OnAfterAllTests` deletes the headers and bodies whose `SuperSession` is one of the run's references.
  - **Waiting.** Each wait polls `Ens.MessageHeader` by `SuperSession` (`%SQL.Statement`) for up to 60 s.
  - **`TestTheStepOwnsOrders`:** `Install.Step.Demo.Owned()` is 1, and `Mode()` is 1, in the throwaway.
  - **`TestOneOrderInEachFormat`** (rows 9 and 10): the AC's test and an Integration AC.
  - **`TestPartnerKeepsNoState`** (row 11).
  - **`TestBadBatchSendsNothing`** (row 12, in OCUORDERS).
  - **`TestRepairedCopyGoesThrough`** (row 13): an Integration AC for 7.3.
  - **`TestSnapshotIsReadableAndCurrent`** (row 14): an Integration AC for 5.4. It reads both files through `%Stream.FileCharacter` and `%FromJSON`, and asserts the case and snapshot fields. Then it sends a fresh 50-order batch (`MM/DD/YYYY`, order date 2026-10-16), waits for 50 errors, and asserts `Projection(Snapshot(ref))` = `Projection(committed)`.
  - **`ClassMethod Snapshot(traceRef) As %DynamicObject`:** builds the snapshot of Design Notes in one OCUORDERS method.
  - **`ClassMethod Projection(snapshot) As %DynamicObject`:** runs in OCUTALON and keeps:
    - the failures sorted by `OrderNumber`, each with its source, target, body class, status, `isError`, error and body;
    - the items as recorded;
    - the trace entries' type, source, target, body class, status and `isError`;
    - the sorted event-log pairs of `type` and `configName`;
    - the count.
  - **`ClassMethod Record(file) As %Status`:** sends the recording batch, waits for its errors, and writes `Snapshot()` to `file`.
- **`src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`:** add `{"class": "OcuTalon.Demo.Orders.Partner", "method": "Send", "args": "count,dateFormat,traceRef,orderDate", "returns": "%Status"}`. Raise the floor to `count >= 48`, and add "the Orders partner's Send from Story 0.10" to the header bullet.

**Throwaway fixtures and the snapshot:**
- **`docker/tests/compose.throwaway.yml`:** add `volumes: - ./eval:/opt/ocutalon/eval:ro` to `iris`. The path resolves from the first compose file's folder, the repository root (Task 0.5 confirms). Extend the header comment: the evaluation set is mounted read-only for IRIS tests, and is never in the image.
- **`docker/tests/record-eval.sh` (new):** not a CI unit; its name is not `test-*`. It sources `lib-live.sh` and runs `live_start r10e`, `dc up -d --build`, and `wait_started_ready 400`. Then:
  1. `iris_script OCUTALON` runs `##class(OcuTalon.Test.Demo.Production).Record("/tmp/ocutalon-snapshot.json")`;
  2. `dc exec -T iris cat` of that file is passed through `jq .` into `eval/orders-date-format/snapshot.json`;
  3. it prints the file's failure count.

  The EXIT trap tears down. Its header says when to rerun it: whenever `TestSnapshotIsReadableAndCurrent` reports a mismatch because the production changed.
- **`eval/orders-date-format/case.json` (new):**

  ```json
  {"name": "orders-date-format", "kind": "incident", "heldOut": false,
   "description": "50 orders from the simulated partner with the order date as MM/DD/YYYY; the Orders transform expects YYYY-MM-DD.",
   "snapshot": "snapshot.json",
   "expectation": {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"},
   "recordedBy": "docker/tests/record-eval.sh (Story 0.10)"}
  ```

  It is pretty-printed by `jq`.
- **`eval/orders-date-format/snapshot.json` (new):** written only by `record-eval.sh`, never by hand. It is ASCII and holds no absolute path.

**Live checks (Lane B, the `install` group; no new restart):**
- **`docker/tests/lib-live.sh`:**
  - **`security_app_props`** takes an optional 10th argument, the namespace (default OCUTALON).
  - **`check_security`** adds the following and updates its comment:
    - `%DB_OCUORDERS_CODE:R,%DB_OCUORDERS_DATA:R` to the trace role's pin, in IRIS's sorted order;
    - `CHK|trace-sql-select-orders|` with `CheckPrivilege(…,"OCUORDERS")`;
    - the application `/ocutalon/trace/ocuorders` with `NameSpace=OCUORDERS`.
  - **`item_jobs [ns]`** takes an optional namespace (default OCUTALON).
  - **`set_demo_mode <0|1>`** writes the `demo.mode` row in OCUTALON through `Data.Setting`'s object API, with `UpdatedAt` from `Data.Time.NowUtc()`. It is a test-only writer, and passes on `CHK|demo-mode|1`.
  - **`demo_surfaces <file> [--wide]`** prints, in `%SYS`, sorted lines of:
    - `ns|<name>|<globals>|<routines>`;
    - `db|<name>|<dir>`;
    - `res|<name>|<publicPermission>`;
    - `role|<name>`, and `roleres|<role>|<resource:perm>` for each resource;
    - `app|<name>|<namespace>|<AutheEnabled>`;
    - `userrole|<user>|<role>`;
    - `sqlpriv|<ns>|<object>|<privilege>|<grantee>`;
    - `map|<ns>|pkg|<name>|<db>` and `map|<ns>|glo|<name>|<db>`, for every namespace;
    - `ens|<ns>` and `ensrun|<ns>`, from `^%SYS("Ensemble","InstalledNamespace"|"RunningNamespace")`;
    - `hs|<ns>`, from `^%SYS("HealthShare","Instances")`;
    - `dir|<entry>`, for every directory under `<mgr>` whose name starts with `ocu` (case-insensitive);
    - `cspdir|<entry>`, for two levels under `<data>csp/`, entries naming `ocu` only.

    The directory lines are limited to `ocu*` so that IRIS's own folders, which come and go, can't make the comparison flaky. `--wide` (Task 0 only) lists every directory under `<mgr>` and `<data>csp/`, and adds `cpf|<line>` for the `[Namespaces]`, `[Databases]` and `[Map.*]` lines of the instance's CPF file.
  - **`check_demo_on <label>`** pins row 1 with `check_session`. The production check uses `item_jobs OCUORDERS`.
  - **`check_demo_off <label>`** pins row 3's absences with `check_session` in `%SYS`.
  - **`compare_surfaces <label> <expected> <actual> [--drop-orders]`:** with `--drop-orders`, it removes every line matching `ocuorders` (case-insensitive) from the expected file. It also passes only when the actual file has no such line.
- **`docker/tests/test-install-start.sh`:** update the header's row list.
  - **Row 1:** after its checks, `check_demo_on "row 1"` and `demo_surfaces "$tmp/surfaces.row1"`.
  - **Row 2:** before its `dc stop`, `set_demo_mode 0`. After its checks:
    - `check_demo_off "row 2"`;
    - `demo_surfaces "$tmp/surfaces.row2"`;
    - `compare_surfaces "row 2: nothing else changes" "$tmp/surfaces.row1" "$tmp/surfaces.row2" --drop-orders`.
  - **Row 3:** `check_demo_off "row 3"`.
  - **Row 4:** `set_demo_mode 1` right before its first `dc up -d`. After that start, before the class is deleted:
    - `check_demo_on "row 4"`;
    - `demo_surfaces "$tmp/surfaces.row4"`;
    - `compare_surfaces "row 4: recreated as at the first start" "$tmp/surfaces.row1" "$tmp/surfaces.row4"`.

  Row 4's existing restart and log check stay.
- **`docker/tests/test-install-upgrade.sh`:**
  - **At the first start**, next to `set_probes`, an orders probe in OCUORDERS:
    1. `Partner.Send(1,"MM/DD/YYYY","<ref from $P>")`, where the reference is 22 characters derived from the project name;
    2. wait for its errored header;
    3. record its id and the `demo.mode` row's `UpdatedAt`.
  - **After row 6's and v3's starts**, `check_session` that:
    - the header exists in OCUORDERS with `IsError` 1;
    - `UpdatedAt` is unchanged;
    - `item_jobs OCUORDERS` lists both pooled items.

  Row 15's `check_security` takes the updated pin.
- **`docker/tests/test-boundaries.sh`:** add `eval/orders-date-format/case.json` and `eval/orders-date-format/snapshot.json` to the paths-and-keys must-scan list (L118).

**Pipeline:**
- **`ci/units.sh`:** `lane-b` becomes "Contract Core Data Demo Live Msg Web".
- **`_bmad/custom/skill-rules.md`:** in Rule 21's fresh-environment line only, "32 classes: 9 in `lane-a`, 23 in `lane-b`". No local path.

**Acceptance Criteria:**
- **AC1, demo mode on (FR-16, FR-56; AD-3, AD-23, AD-24).**
  - Given a fresh Docker volume (demo mode's default), when the after-start runs the Demo step, then row 1 holds.
  - Given demo mode on and OCUORDERS present, when a later start runs the step (script row 4's restart, the upgrade's starts), then it recreates nothing, keeps the data, and the production runs again (rows 2 and 8).
- **AC2, the setting (AD-19).** Given no `demo.mode` row, when the step runs, then it seeds `1` where `/opt/ocutalon/version` exists and `0` where it doesn't. Given a row, the step leaves it untouched, so a switched value survives restarts and upgrades (rows 3, 6, 8 and 18).
- **AC3, the real transform (the story's AC).** Given the Orders production running in OCUORDERS, when a test sends one order in each format through `Partner.Send`, then only the changed one fails, at `OrdersFromPartner`, as a real transform error with row 10's text. The other completes at `OrdersToWarehouse`, and both carry the caller's `TraceRef` as `SuperSession` (rows 9, 10 and 16).
- **AC4, the partner (Integration AC; consumer 4.3).** Given two batches with different formats sent one after the other, when they are processed, then each order fails or passes by its own batch's format alone. Each order has its own session, and a bad batch sends nothing (rows 11, 12 and 17).
- **AC5, the repaired copy (Integration AC; consumer 7.3).** Given a failed order, when a copy with the date `YYYY-MM-DD` is resent to `OrdersFromPartner` with `ResendDuplicatedMessage`, then it completes at `OrdersToWarehouse`, and the original stays errored (row 13).
- **AC6, demo mode off (FR-16 L461; AD-3, AD-24).** Given demo mode switched off, when the next start runs the step, then rows 3 and 4 hold: everything row 1 created is gone, and nothing else on the surfaces changes. Switched on again, the next start recreates exactly row 1's surfaces (row 5).
- **AC7, ownership.** Given a namespace OCUORDERS whose databases the step didn't create, when the step plans, then it refuses to create with row 7's text and leaves the namespace alone when off. Given the step's own OCUORDERS in a throwaway, `Owned()` is 1 (row 7).
- **AC8, the snapshot (Integration AC; consumer 5.4; AD-22).** Given the committed `eval/orders-date-format/`, when `Test.Demo.Production` reads it inside a throwaway at `/opt/ocutalon/eval`, then it holds the recorded 50-order failure and its expectation. Its projection equals a fresh recording's. Both files pass the key and path scans, and `test-boundaries.sh` must scan them (row 14).
- **AC9, the contract.** Given `Test.Contract.Ac` and `Test.Demo.Orders`, when they run, then `Partner.Send` keeps its parameters and return type, and the two message classes keep their contracts and the `Ens.MessageBody` extent (row 19).

## Spec Change Log

Implement stage, October 20. Each ruling is one the standing grant (Rule 22) lets the stage make; the measurements behind them are under Verification, "Task 0 measurements".

- Rule 22 ruling: what the "errored header" of rows 10, 13 and 14 (AC3, AC5, AC8) is -> a PartnerOrder that fails in `Translator` ends in header `Status` 8 (Error) at `OrdersFromPartner`, with `IsError` 0 and an empty `ErrorStatus`; the error text is the event-log row of `Type` 2 (Error) for that item and session, "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'.    > ERROR #5001: ..." (the transform's sentence appears twice). `IsError` and `ErrorStatus` are set only on error response headers (`NewErrorResponse`), and the partner sends asynchronously with no response. Tests assert `Status` 8 and the sentence in the log; the snapshot records `status` "Error", `isError` as the header holds it (false) and `error` as that log text; `Projection` compares all three. (rejected: a synchronous partner call, which would put the error on a response header but block `Send` per order and change the async contract of the Tasks; a custom response from `Translator`, which is not the "real transform error" of the story.) Consumers: Story 5.1/5.4's reader must key on `Status` and the event log, not `IsError`, and parse the first sentence out of "due to error: ERROR #5001: ...".
- Rule 22 ruling: the destination strings of `Owned()` and of the live checks -> `"^"_directory` (one caret), as `%SYS.Namespace.GetGlobalDest` and `GetRoutineDest` return them for a local database (measured: `^/durable/iris/mgr/ocutalon_data/`), not the `"^^"_directory` the Tasks wrote. (rejected: `"^^"`, which no destination ever equals.)
- Rule 22 ruling: how the production gets its definition in OCUORDERS -> `Orders(1)` calls `Ens.Config.Production.LoadFromClass(PRODUCTION)` before `StartProduction` whenever the production is not running, because the class is compiled in OCUTALON and `StartProduction` refuses a name with no `Ens.Config.Production` row in its namespace (`Ens.Director` L15). The row therefore follows the class after an upgrade. (inference: `StartProduction` was not run without it.) (rejected: leaving the row to whatever compiled it, which no namespace but OCUTALON does.) Side effect measured: compiling the Orders production in OCUTALON also registers an `Ens.Config.Production` row there; `OcuTalon.Production` stays the running production.
- Rule 22 ruling: calling this class from the two switching methods -> neither `System` (in %SYS) nor `Orders` (in OCUORDERS) can call any method of `OcuTalon.Install.Step.Demo` while there: measured `<CLASS DOES NOT EXIST>` in both, and `Security.*`, `Config.*` and `SYS.*` do not exist in OCUTALON. So the directories and the other `Web`/`Settings` constants are read before the switch (parameters compile inline), and `System` goes back to the caller's namespace for its one pure call, `WithOrders`, and returns to %SYS. (rejected: a second copy of `WithOrders` inside `System`, which tests would not pin; the rule held in a string parameter and `XECUTE`d; a third switching method.)
- Rule 22 ruling: how the step names the public global when it maps it -> `OcuTalon.Data.Public.Settings` gains `Parameter GLOBALNAME = "OcuTalonPublic"` and `System` reads it, because the class rule `public-global` (AD-19) allows that name on a code line of `src/` only in that class. `Test.Web.PublicTexts` classifies the new parameter (19 not-text parameters, was 18). (rejected: assembling the name from two strings in the step, which dodges the rule; relaxing the rule.)
- Rule 22 ruling: what Task 0.6 turned into -> the portal application `/csp/ocuorders` has `AutheEnabled` 32 on both images, so the on path sets nothing (no VETO WINDOW item for it). The one leftover found was on the non-Health image: the resource `%DB_OCUORDERS_DATASECONDARY` and its same-named role, left by the first `System(0)`. `System(0)` now deletes the resource and role of every owned database it removes (`%DB_` plus the database's name, for names that start with OCUORDERS); with that, W2 equals W0 and W3 equals W1 byte for byte on both images. The tripwires (i), (ii) and (iii) did not fire.
- Rule 22 ruling: a seed that cannot be written -> `Mode()` throws the seed's error, so `Run` fails and nothing is removed; reading "off" because the row could not be written would delete the demo. (rejected: returning 0.)
- Rule 22 ruling: Row 1's check of the production's jobs -> `check_orders_jobs` ignores the jobs of the Interoperability system items (`Ens.Actor`, `Ens.Alarm`, `Ens.MonitorService`, `Ens.ScheduleHandler`), which every Interop namespace runs, and requires exactly `OrdersFromPartner` and `OrdersToWarehouse` besides them. The upgrade probe's "IsError 1" is "Status 8" (first ruling).
- Rule 22 ruling: the lists of the SQL privileges and the applications to delete -> read with `%SQL.Statement` filtered by `Namespace`/`NameSpace` (the privilege table holds about 50,000 rows on the Health image, which `Security.SQLPrivileges:List` would scan at every start with demo mode off); privileges are deleted with `Security.SQLPrivileges.%DeleteId`, which the measurements show works.
- Test and fixture changes the spec did not list, each forced by a shared surface: `docker/tests/test-compose-start.sh` leaves the mounted `/opt/ocutalon/eval` out of its image-files listing and asserts that the built image holds no such folder; `Test.Demo.Orders.TestTransformFailsOnTheChangedFormat` does not assert that no `WarehouseOrder` is built, because a DTL with `create='new'` builds the target before its first assignment; `Snapshot(traceRef, batch)` takes the batch as an optional second argument, so that `source.batch` is the recorded batch.
- The `(loop)` row "`ci/iris.sh class OcuTalon.Test.Demo.Production`, 6 tests passing" holds (it also fails all 6 with row 15's text where OCUORDERS is absent: measured in a throwaway with demo mode off). `Test.Demo.Production` is not run on slot A, as the Verification targets say.

## Review Triage Log

### 2026-10-20 — Review pass
- verdicts: 44 findings — high 0, medium 6, low 30, false 8, maybe-false 0
- groups (shared root cause): G1 E11+I1 (the errored header has no IsError); G2 B4+V1 (compare_surfaces diff branch unpinned); G3 B8+E6+E7+V5 (upstream header not waited for); G4 B2+E5 (foreign OCUORDERS_* names on the off path); G5 V3+I8 (state-machine branches from a foreign or partial state untested); G6 V2+I6 (non-Health image has no repo run); G7 B1+E12 (doc comments misplace the error text)
- findings (Blind Hunter B1-B10, Edge Case Hunter E1-E14, Verification Gap V1-V8, Intent Alignment I1-I12, in the order the layers reported):
  - `[low]` `[patch]` B1 Translator and Transform comments say the failed header shows the error text / its first sentence names the date — the text is the event-log row inside the "Terminating BP" wrapper; both comments rewritten to say so (G7).
  - `[low]` `[reject]` B2 `System(0)` deletes `%DB_OCUORDERS_*` resources and roles without an ownership check when the namespace is absent — needs a hand-made database with exactly these names and no OCUORDERS namespace; off-path Task 7 deletes the step's resources unconditionally; the guard would add a branch for a state not shown (G4).
  - `[low]` `[reject]` B3 `Run` has no lock — no caller in this story runs it twice at once; `SettingsOps` (4.1) owns the write and the rerun, and the Design Notes already hand 4.1 the DW-28 race.
  - `[medium]` `[patch]` B4 no hermetic test for the new `lib-live.sh` helpers — `compare_surfaces` decides AC6's "nothing else changes"; nine cases added to `docker/tests/test-lib-live.sh` (equal, gone line, new line, OCUORDERS line left, plain equal, plain differing, empty actual, empty expected, unknown option), mutation recorded (G2).
  - `[low]` `[reject]` B5 `demo_surfaces --wide` is unused — the spec requires the variant for Task 0 (spec-bound, `by-design`), and Task 0 used it.
  - `[low]` `[reject]` B6 `Partner.Send` builds the orders twice — the spec has `Send` validate through `Orders` and `OnProcessInput` build; at most 2 x 1000 small objects, negligible.
  - `[low]` `[reject]` B7 snapshot field types differ (`headerId` string, `sessionId` number, `enabled` 1) — no named harm today; the Design Notes let 5.4 adopt or rename the format when it fixes the payload, and a change means re-recording the file.
  - `[low]` `[patch]` B8 the tests assert the upstream header's status without waiting for it — `WaitCount(..., "OrdersFromPartner", 9, 1)` added to `TestOneOrderInEachFormat` and `TestRepairedCopyGoesThrough` (G3).
  - `[false]` `[reject]` B9 the step hard-codes `/opt/ocutalon/version` while the scripts honour `OCUTALON_VERSION_FILE` — only the hermetic script tests set it, with no IRIS behind them; no Docker start sets it; the spec's Rule 22 ruling fixes the path.
  - `[low]` `[patch]` B10 `record-eval.sh` checks `jq` and `case.json` after `live_start` — both checks moved before it.
  - `[low]` `[patch]` E1 a 22-letter accented trace reference passes the `U`/`L` pattern — `Partner.Orders` now uses `$Match(ref, "^[A-Za-z0-9_-]{22}$")`; `TestBatch` gets a 22 x `$Char(233)` case, mutation recorded.
  - `[low]` `[reject]` E2 production states other than Running, Troubled, Suspended and Stopped are not handled — NetworkStopped, Backup and shard states cannot occur on a single Docker instance (`wontfix-theoretical`).
  - `[low]` `[reject]` E3 a killed `EnableNamespace` leaves a half-enabled namespace that is never repaired — needs a kill inside a call that takes about one second; a rerun of the step with `IsEnsembleNamespace` true is the documented idempotence (`wontfix-theoretical`).
  - `[low]` `[reject]` E4 a pre-existing `%DB_OCUORDERS_*` resource with public permission is kept — the spec creates a resource only when absent; a hand-made resource is outside what the step owns.
  - `[low]` `[reject]` E5 a foreign `OCUORDERS_*` database loses its resource when demo mode is off — same as B2 (G4).
  - `[low]` `[patch]` E6 `TestOneOrderInEachFormat` reads the upstream header without a wait — fixed with B8 (G3).
  - `[low]` `[patch]` E7 `TestRepairedCopyGoesThrough` reads the resent header without a wait — fixed with B8 (G3).
  - `[low]` `[reject]` E8 `failed.id` on an empty header hides the timeout — the preceding assertion already reports "the order fails" as the failure; the test is red either way.
  - `[low]` `[reject]` E9 `Snapshot` with an empty body class aborts — every failure it reads is a `PartnerOrder` header (`TargetConfigName` and `Status 8` filter), so the class is never empty (`wontfix-theoretical`).
  - `[low]` `[reject]` E10 `Record` appends to an existing file — `record-eval.sh` calls it once in a fresh throwaway, where `/tmp/ocutalon-snapshot.json` does not exist; `reopen_if` a second caller of `Record` appears.
  - `[medium]` `[defer]` E11 the upgrade probe and the tests assert `Status` 8 where the matrix says `IsError` 1 — the platform sets `IsError` and `ErrorStatus` only on error response headers, and the partner sends asynchronously (G1; deferred item 1; the Rule 22 ruling is in the Spec Change Log).
  - `[low]` `[patch]` E12 the Translator comment claims the header shows the error text — fixed with B1 (G7).
  - `[false]` `[reject]` E13 `Owned()` compares one caret where the Tasks wrote two — the code matches the measured destination (`^<dir>`); the Tasks text was wrong and the Rule 22 ruling for it is logged.
  - `[low]` `[patch]` E14 nothing pins the portal application's `AutheEnabled` — `check_demo_on` now pins `CHK|portal-authe|32` for `/csp/ocuorders` (Task 0.6 measured 32), run under the AC1 mutation below.
  - `[medium]` `[patch]` V1 the `compare_surfaces` mutations went red only through the OCUORDERS-leftover branch — the `diff` branch is now covered hermetically and its mutation (the `diff` replaced by a no-op) goes red at three checks (G2).
  - `[medium]` `[defer]` V2 the non-Health path (`ENSTEMP` and `SECONDARY` databases, their resource and role) has no repository run — CI holds only the Health base image and never pulls (deferred item 2; Task 0 measured it by hand).
  - `[medium]` `[defer]` V3 the foreign-production refusal, `RecoverProduction`, the start-timeout error, a database entry with another directory, a mapping `Modify` and the cleanup of a directory without a CPF entry have no test — the fixtures need a foreign state in the `install` scripts' rows, and the spec forbids new restarts and units (deferred item 3).
  - `[low]` `[reject]` V4 `Translator.OnRequest`'s wrong-class branch is untested — a business process needs a configured instance to construct; `reopen_if` S8's resend can put another body class at `OrdersFromPartner`.
  - `[low]` `[patch]` V5 the status read without a wait (race) — fixed with B8 (G3).
  - `[low]` `[patch]` V6 AC1's recorded mutation went red at the "start ended ready" check, not at `check_demo_on` — a second AC1 mutation (the `OcuTalon.Web.Public` mapping aimed at `OCUTALON_CODE`, the step still OK) goes red at `check_demo_on` rows 1 and 4; the other listed clauses need no mutation of their own (one per AC, Rule 19).
  - `[low]` `[reject]` V7 `Record` and `record-eval.sh` run in no CI unit — by design (the spec: not a unit); both ran in this pass and pass.
  - `[low]` `[reject]` V8 `test-boundaries.sh` does not ASCII-scan `eval/` — the scan scopes are the spec's; `record-eval.sh` refuses a non-ASCII or absolute-path snapshot, and `case.json` and the recorded `snapshot.json` were checked ASCII with no path.
  - `[medium]` `[defer]` I1 header `Status` and the event log stand where the matrix says `IsError` and `GetErrorText` — same root cause as E11 (G1, deferred item 1); neither the spine nor `epics.md` mentions `IsError` or `ErrorStatus`, so no AD or AC is contradicted; the Rule 22 ruling authorizes the measured behaviour.
  - `[low]` `[reject]` I2 row 14's check is a containment of the sentence in the wrapped log text — follows the ruling; row 16 pins the exact text at the transform.
  - `[low]` `[reject]` I3 row 9's `errorText` is empty for both orders — `Status` 9 against 8 is asserted beside it.
  - `[false]` `[reject]` I4 row 6 "does nothing" read as the net effect — `TestPlan` pins `Plan(0,0,0)` as "remove", a no-op when nothing exists, which is the spec's Plan.
  - `[false]` `[reject]` I5 row 2's demo checks sit at row 4's recreate, not at its final stop and start — the Live checks list puts them there, and the upgrade script's v1 and v3 starts assert the production runs again.
  - `[low]` `[reject]` I6 the automated runs use the Health image only — same as V2 (G6).
  - `[false]` `[reject]` I7 `record-eval.sh` starts a stack — the spec adds it as a non-unit script; no CI unit, group or `ci.yml` change.
  - `[low]` `[reject]` I8 no test drives `Run` against a foreign OCUORDERS or an `Orders(1)` timeout — same as V3 (G5); `Plan`'s refusal text is pinned by `TestPlan`.
  - `[false]` `[reject]` I9 `check_security` is shared with `test-sign-in.sh` — the spec lists `test-sign-in.sh` as a user of the updated pin, and it passed.
  - `[false]` `[reject]` I10 files outside the intent's list (`test-compose-start.sh`, `Data/Public/Settings.cls`, `Test/Web/PublicTexts.cls`, `skill-rules.md`) — each is a forced shared-surface change logged in the Spec Change Log; none is on the Never list.
  - `[false]` `[reject]` I11 `System` assigns `$NAMESPACE` back to the caller's namespace for one pure call — exactly two methods use `New $NAMESPACE`; the Rule 22 ruling is logged.
  - `[low]` `[patch]` I12 `Test.Demo.Production` gives row 15's "does not exist" text when OCUORDERS exists but the production does not run — the two causes now have their own messages; row 15's text stays for the missing namespace.
- patches applied: 8 entries (G7, G2, G3, B10, E1, E14, V6, I12), all low except G2 (medium); the `(loop)` lines and the `(once)` lines of `## Verification` were run again after them.

## Design Notes

**ADs:**
- **AD-3:** OCUORDERS, its databases and mappings, the Demo step, namespace switching and the Foundation rule.
- **AD-4:** `TraceRef` as the demo tag; no names in production messages.
- **AD-5:** the durable data database; append-only storage blocks; the production class holds structure.
- **AD-19:** demo mode as a seed product value in `Data.Setting`.
- **AD-22:** the evaluation set in `eval/`; tests in shards.
- **AD-23:** the step's fixed place; off removes everything; an IPM install has demo mode off.
- **AD-24:** the trace role's OCUORDERS grants and the trace application, only with demo mode on.
- **AD-26:** `SuperSession` is set in `OnProcessInput`.
- **AD-16 and S8:** a resend into OCUORDERS with the body class resolved there.
- **AD-15:** `EvidencePack.Build` reads a recorded snapshot; `ItemNoun` maps the demo's message class.
- **AD-29 and AD-33:** Epic 0 builds the Orders production and the snapshot. `.Demo` is Lane B's; `eval/` is Lane A's after Epic 0.
- **AD-2:** no bridge class is touched.

No AC contradicts an AD, and no NFR is unmeasurable. AD-3's "OcuTalon never deletes Foundation artefacts" (L150) would collide with the off AC only if OCUORDERS held a Foundation. The no-Foundation route prevents that, and Task 0.7(i) is the tripwire.

**Recommended amendments for Task 0's HALTs** (the lead decides; Rule 5):
- (i) AD-3 L150 gains: "OCUORDERS's Foundation artefacts, which the Demo step installed, are removed with it."
- (ii) AD-3 names the leftover as accepted residue, and FR-16's "nothing else changes" gets the matching note.
- (iii) AD-3 L141 changes to "the Demo step loads `OcuTalon.Demo.Orders` into `OCUORDERS_CODE`" instead of the package mapping.

**Rule 22 rulings** (question → choice (rejected: …)):

*The setting and the step:*
- **The demo-mode key** → `demo.mode`, values "1" and "0", on iff "1". (Rejected: a public setting, which `Setting.Seed` refuses and AD-19 doesn't list; `true`/`false`, which no other setting uses.)
- **How the seed tells Docker from IPM** → `/opt/ocutalon/version` exists only in OcuTalon's image (Dockerfile L20), for every process in the container. (Rejected:
  - telling steps their caller, which changes 0.2's contract that `Run()` takes no argument and `caller` names only the refusal;
  - a compose environment variable, a new AD-19 configuration home that the judges' pinned compose file would carry;
  - `OCUTALON_IMAGE_VERSION`, which only the after-start session's environment has, and a 4.1 rerun from a production job doesn't.)
- **Who seeds** → the Demo step, in `Mode()`, at every run (rejected: the `Public` step, whose values are structural).
- **How Interoperability is enabled** → the Config classes for the databases, the namespace and the mappings (AD-3), then `%Library.EnsembleMgr.EnableNamespace(ns, 0, , 1)`. The install flag means no Foundation installer runs on the Health image; on the non-Health image the call is the same as without the flag (L1774–1782 and L1816 vs L1857). (Rejected: `Config.Namespaces` with `Interop=1`. On the Health image it installs a Foundation in OCUORDERS `(inference: OCUTALON's Foundation mappings on slot A after the CPF merge's Interop=1)`. That costs about 40 s more per first start on Apple silicon `(inference: S1's 60 s vs S12's 20 s)`, and leaves artefacts that AD-3 says OcuTalon never deletes, so the off path couldn't remove OCUORDERS. Task 0.3d measures it.)
- **"Each in one method" (AD-3 L142)** → one switching method per target namespace: `System` to `%SYS` (as every `Install.*` class) and `Orders` to OCUORDERS (AD-3's Demo entry). (Rejected: one method that switches twice, which is longer and mixes two namespaces' code.)
- **Database names, places and resources** → `OCUORDERS_CODE` and `OCUORDERS_DATA` at `<mgr>ocuorders_code/` and `<mgr>ocuorders_data/`, on the durable volume. The resources `%DB_OCUORDERS_CODE` and `%DB_OCUORDERS_DATA` have no public permission, as `merge.cpf` does for OCUTALON's code and data databases.
- **What the step owns** → only the namespace whose default destinations are its own two directories, and the objects named in Tasks. A foreign OCUORDERS makes the on path fail and the off path leave it alone. (Rejected: deleting any OCUORDERS, which could destroy a user's namespace on an IPM install, 15.2.)
- **What off removes** → everything row 3 lists, completed by Task 0's leftovers. That covers the `%SYS` rows keyed by namespace (`Security.SQLPrivileges`), which outlive a deleted namespace `(inference: the IdKey begins with Namespace)`.
- **How the production starts** → not autostart; the step starts it, as the `Production` step does for `OcuTalon.Production` (AD-3). A running Orders production is left running, because a Docker start always begins with it stopped. Troubled is recovered. Another production in OCUORDERS is never stopped.

*The production's shape:*
- **Where the transform runs** → a custom business process, `Translator`, which calls the DTL and returns its error unchanged. (Rejected: `EnsLib.MsgRouter.RoutingEngine` with a rule, which wraps the error as "Not routing to target(s) … because of error in Transform …" (L397). The failure's first sentence would then name the router, not the order date, for 5.4's fallback line, and it needs a rule class and `ActOnTransformError`.)
- **Item names** → `PartnerOrdersIn` (a service, so it ends `In`, Conventions L877), `OrdersFromPartner` (the process where orders fail, matching 0.9's fixture line) and `OrdersToWarehouse`. The production's description is "Orders", for 5.1's display-name match.
- **Message classes** → `PartnerOrder` (`OrderDate` as text, so a wrong format can arrive) and `WarehouseOrder` (`OrderDate` as `%Date`). Neither carries `SessionRef`: the session's tag is the header's `SuperSession` = `TraceRef` (AD-4 L157). (Rejected: a `SessionRef` property. It would make the simulated partner know OcuTalon's session ids, put them in bodies that every visitor can open in the shared trace (AD-24), and step outside L90's Orders → Ens rule.)
- **Sessions** → one session per order, all with the batch's `SuperSession`. Each failed order is its own trace session, as separate partner messages are.
- **The partner's API** → `Partner.Send(count, dateFormat, traceRef, orderDate)`, called in OCUORDERS, with:
  - a count from 1 to 1000 (7.4 resends 500);
  - the formats `YYYY-MM-DD` and `MM/DD/YYYY`;
  - an optional order date. "" is the partner's own local date, `$ZDATE($HOROLOG,3)`. (Rejected: `Data.Time`, which the Orders package may not reference (L90).)

  4.3's `PartnerTrigger` calls it with 50 and `MM/DD/YYYY`.
- **The error text** → "The order date was not in the expected format. Expected YYYY-MM-DD, got '<value>'.", as `$$$GeneralError`. Its first sentence is 0.9's fixture summary, and it says what the transform expects, as a real validation does. VETO WINDOW FYI.

*The evaluation set:*
- **Its layout** → one folder per case, `eval/<case>/`, holding `case.json` (`name`, `kind`, `heldOut`, `description`, `snapshot`, `expectation{causeCategory, elementAtFault, fixKind}`, `recordedBy`) and `snapshot.json`. The expectation codes are snake case, like `Msg.Enum`: `data_format_change`, `OrderDate` (the property, which 7.1 requires), `repair_resend`. 5.4 adopts or renames them when it fixes `DiagnosisPayload`'s values. Lane A owns `eval/` after Epic 0.
- **The snapshot format** (`snapshot.json`; times UTC `YYYY-MM-DDThh:mm:ssZ`, from the headers' UTC times):
  - `format`: "ocutalon.readerSnapshot/1";
  - `recordedAt`;
  - `source`: `{namespace, production, item, batch{count, dateFormat, orderDate}}`;
  - `failures[]`: each `{headerId, sessionId, superSession, timeCreated, timeProcessed, sourceConfigName, targetConfigName, bodyClass, bodyId, status, isError, error, body{OrderNumber, OrderDate, Sku, Quantity}}`, where `error` is `GetErrorText`, as IRIS shows it (UX L286), and `status` is the display value;
  - `eventLog[]`: each `{id, timeLogged, type, configName, sourceClass, sourceMethod, sessionId, text}`, for the batch's sessions;
  - `items[]`: each `{name, className, enabled, poolSize, settings{}}`, from the production definition. A setting whose name contains `Credentials`, `Password`, `Token` or `Key` (case-insensitive) is removed;
  - `trace[]`: the first failure's session, `{headerId, type, sourceConfigName, targetConfigName, bodyClass, status, isError, timeCreated}` in order.

  This covers 9.4's list, and 5.4's counts, first and last times, a sample body and its error.
- **How IRIS tests reach `eval/`** → a read-only bind mount of `./eval` at `/opt/ocutalon/eval`, in `docker/tests/compose.throwaway.yml`, which every throwaway layers (`lib-live.sh`, `ci/iris.sh`). So shards and live units read the committed files, and neither the image nor the judges' compose file holds `eval/`. (Rejected:
  - `!eval` in `.dockerignore`, which puts test data in the judges' image and changes AD-23's image contents;
  - `ci/compose.ci.yml`, which is pinned to hold only the project name and `OCUTALON_EVAL`, while the mount is a test fixture like the throwaway's port and key resets;
  - piping files in per test, which every consumer would repeat and a `%UnitTest` can't do.)
- **How the snapshot is recorded and kept honest** → `record-eval.sh` records a real batch in a throwaway. `TestSnapshotIsReadableAndCurrent` compares the committed file's projection with a fresh recording's on every CI run, so a change to the production's behaviour turns it red until the file is recorded again. (Rejected: a hand-written file, which would be canned; a byte-for-byte comparison, which ids and times make impossible.)

*Testing:*
- **The live checks** → they ride on `test-install-start.sh`'s existing rows 2, 3 and 4, and `test-install-upgrade.sh`'s existing starts. That adds no stack and no restart. (Rejected: new restarts for off and on, about 2 minutes more on x64; a new live unit, 3 to 4 runner-minutes against REL-4.)
- **Where the transform is tested** (the lead's question):
  - its unit test (`Test.Demo.Orders`, row 16) runs in OCUTALON on slot A, calling the DTL's `Transform` directly with no production;
  - the end-to-end test (`Test.Demo.Production`) runs in a throwaway's OCUORDERS, in shard `lane-b`. It fails rather than skips when OCUORDERS is missing, so a broken Demo step can never give a green shard.
- **"Nothing else changes"** → a surfaces listing that drops the lines naming OCUORDERS. Every object the step creates has OCUORDERS in its name, its namespace or its resource. Task 0's wide W0 and W2 comparison checks for objects outside the listing.

**VETO WINDOW FYIs (Rule 22.3), for the Contest Planner after the commit:**
- **Security posture.** With demo mode on, `EnableNamespace` creates the Interop portal application of OCUORDERS (`/csp/ocuorders`; on the Health image too, because of the install flag), and `%EnsRole_ProdPrivs_OCUORDERS`. If Task 0 finds that the application answers without sign-in, the step makes it password-only. The trace grants and the trace application are the spine's (AD-24).
- **Data loss.** Demo mode off deletes `OCUORDERS_DATA`'s file and its demo orders, as AD-3 and AD-23 direct. Reversing it would mean keeping the files and only unmounting.
- **Public-facing text.** The transform's error text and the three item names appear in the evidence panel and the fallback notice (UX L286, L789).

**Owner-only (Rule 22.4), for the Contest Planner; planned around, not decided:**
- **REL-4's 30 minutes** against this story's added install time (estimate below). DW-21 is already escalated, and the lead may append an occurrence after the first CI run.
- **The README's first-start figure (10.2).** `FIRST-START` now includes creating OCUORDERS. The lead's merge-head row in `epic-0-readme-notes.md` records it.

**Integration ACs (Rule 1):** AC4 for 4.3, AC5 for 7.3 and AC8 for 5.4. Each consumer's effect is exercised by `Test.Demo.Production` against the real production in OCUORDERS.

**Consumed-by:**
- **Demo mode:**
  - **4.1:** `SettingsOps` writes `demo.mode` ("1" or "0", `##class(OcuTalon.Install.Step.Demo).#MODEKEY`), then calls `Install.Step.Demo.Run()`. `/state` reports the value.
    - A stop right after a start may race the scheduler (DW-28); 4.1 measures it.
    - The 60-second cache: `Mode()` reseeds, which drops the caller's own cache entry.
  - **2.1:** the "Demo mode" badge reads `demo.mode`.
  - **15.2:** an IPM install has no `/opt/ocutalon/version`, so the seed is `0`. `SetDemoMode(1)` there runs the same step. The Orders production's autostart on an IPM install is 15.x's.
- **The Orders production:**
  - **4.3:** `PartnerTrigger` switches to OCUORDERS and calls `Partner.Send(50, "MM/DD/YYYY", traceRef)`. A production job of OCUTALON calling `CreateBusinessService` in OCUORDERS isn't measured here; 4.3 measures it.
  - **4.7, and 0.8's unbuilt demo-path steps 2, 3 and 6:** the production to watch and break.
  - **3.1:** the trace role's OCUORDERS grants are built here. Its "a test with demo mode off finds no OCUORDERS grant" is row 3.
- **Lane A's watch, diagnosis and repair:**
  - **5.1:**
    - The production is `OcuTalon.Demo.Orders.Production` in OCUORDERS, with the description "Orders".
    - The service user's read on `%DB_OCUORDERS_DATA` must be added after the Demo step, as the trace grants are, because `Roles` runs first and the resource is absent with demo mode off.
  - **5.2 and 5.3:** the failures are at `OrdersFromPartner`, with one error pattern, and tagged by `SuperSession`. Lane A's tests need OCUORDERS, so they run in throwaways, never on a slot.
  - **5.4:**
    - `EvidencePack.Build` reads `eval/orders-date-format/snapshot.json` (at `/opt/ocutalon/eval` in throwaways).
    - `ItemNoun` maps `OcuTalon.Demo.Orders.PartnerOrder` to "order"/"orders".
    - The mock scenario under `ci/mock/scenarios/A/` is 5.4's.
  - **6.1:** the evidence line.
  - **7.1:** the field is `PartnerOrder.OrderDate`, before "10/16/2026" and after "2026-10-16". The readable "order date" comes from splitting the camel case (recommended).
  - **7.3:** a resent copy goes through (AC5).
  - **7.4:** up to 1000 orders per `Send`.
- **The evaluation set:**
  - **9.1–9.5:** the case format above. 9.4's `Eval.Record` replaces `record-eval.sh`, and if it changes the format, it moves or retires `TestSnapshotIsReadableAndCurrent` by an AD-33 request.
- **Upgrade and reset:**
  - **11.2:** OCUORDERS is kept across an upgrade (row 8).
  - **16.x:** the reset finds a session's demo orders by `SuperSession`.

**Consumes:**
- **0.2:** the registry, `Install.Step` and `Data.Setting` (`Seed`, `Get`).
- **0.3:** `Web.TraceApp`, `Web.Apply`, `Web.#TRACEROLE` and the README account's roles.
- **0.6:** the `Production` step's state machine and item-run predicate (copied; see Reuse).
- **0.7:** `ci/iris.sh`, `ci/units.sh`, `lib-live.sh` and the storage checks.
- **0.9:** the fixture line "OrdersFromPartner: 50, 'The order date was not in the expected format', …".

**Reuse (Rule 2):**
- **Reused or extended:**
  - `Web.TraceApp` and `Web.Apply` are reused;
  - `Test.Demo.Orders` extends `Test.Contract`;
  - `lib-live.sh`'s `security_app_props`, `check_security` and `item_jobs` are extended;
  - the live checks extend the two install scripts' existing rows.
- **Stated copies:**
  - `Orders()` holds a copy of `Production.Start`'s state machine and `NotRunning`'s predicate (about 25 lines), because `OcuTalon.Install.*` doesn't resolve in OCUORDERS and AD-3 wants the switch in one method;
  - `Orders()` also calls `GrantPrivilege` inline instead of `Web.GrantTraceSql`, for the same reason;
  - `Test.Demo.Orders` reads the production definition through `%XML.Reader`, because `Test.Install.Production`'s private helpers belong to a Lane A test.

**Ledger inbox:** the slice for this key is empty (checked at plan time).

**Spine updates for the lead (Rule 20):**
- **AD-3:**
  - OCUORDERS's databases, directories and resources;
  - Interop through `EnableNamespace` with the install flag (no Foundation on either image);
  - the list of what off removes;
  - the ownership guard;
  - "each in one method" read as one method per target namespace.
- **AD-4:** Orders bodies carry no `SessionRef`; the session's tag is `SuperSession` = `TraceRef`.
- **AD-19:** `demo.mode` ("1" or "0"), seeded by the Demo step, with Docker told by `/opt/ocutalon/version`.
- **AD-22:**
  - the `eval/<case>/` layout and the `case.json` and `snapshot.json` formats;
  - the throwaway mount at `/opt/ocutalon/eval`;
  - the recorder until 9.4.
- **Structural Seed:**
  - the Orders production's items: `PartnerOrdersIn`, `OrdersFromPartner`, `OrdersToWarehouse` and their classes;
  - the Demo flow's `PartnerTrigger` → `Partner.Send`.

**Time budget (REL-4; inference until Task 0 and the first CI run measure it):**
- **Per start.** Creating OCUORDERS takes about 8–15 s on Apple silicon (two databases, a namespace, four mappings, `EnableNamespace` without a Foundation, and a production start), and about 20–60 s on the x64 runner (×2.4–3.9, Rule 21). A later start adds about 3–5 s on Apple silicon and 8–20 s on x64 (a production start).
- **CI.** Every throwaway's first start pays the creation cost, because demo mode is on by default (12 first starts per run). Estimated:
  - `iris (install)` grows by about 2–5 minutes (12 min 45 s → 15–18 min);
  - each other group grows by about 1–3 minutes;
  - in all, about 7–15 runner-minutes (43 → 50–58).
- **Wall-clock.** It may reach about 26–31 minutes, against REL-4's 30. DW-21's worst case rises by the same amount.
- **Mitigation.** None is applied, because the demo path comes first (22.2.1) and every throwaway should run the judges' configuration. If the first CI run exceeds 30 minutes, regrouping is the lead's call (DW-21), and the 30 minutes is the owner's. (Rejected: a CI-only switch to start with demo mode off, which is a new AD-19 configuration home and would test a configuration the judges don't run.)
- **README.** The first-start figure grows by the creation time.

**Size and split line:**
- **Scope.** About 9 new product classes, 3 new test classes, 1 extended test, 1 new script, 2 data files, and changes to 6 shell or recipe files.
- **The estimate.** It is at the upper edge of one implement pass, comparable to 0.6 and 0.7.
- **The split, if the lead rules one.** Story 0.12 takes the evaluation snapshot: `eval/`, `record-eval.sh`, the throwaway mount, `TestSnapshotIsReadableAndCurrent`, AC8 and row 14. 0.10 keeps the step, the production, AC1–AC7 and AC9. 0.12's first consumer stays 5.4.

## Verification

**Runtime targets:**
- **Slot A**, `ocutalon-slot-a`: MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call. First, `iris_server_info` must show build 154.
  - `iris_doc_load` with base `src/ocutalon/cls`.
  - `iris_execute_tests`: one class per call and one call per message.
  - Never `Run`, `System` or `Orders` of the Demo step, and never `Test.Demo.Production`.
- **Throwaways**, only through `ci/iris.sh` or `lib-live.sh` (the scratch Task 0 script and `record-eval.sh` included):
  - tag `v10a` (QA `v10q`, review `v10r`);
  - `OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`;
  - one stack at a time, each removed by its trap and then by `ci/iris.sh teardown` with the same tag.

  The non-Health runs set `IRIS_IMAGE=iris-community:2026.3.0AI.154.0`.
- **Nothing else.** No push and no `gh workflow run`.

Every command finishes inside one foreground call (`timeout: 600000`).

**Commands:**
- `(loop)` **Slot A loads.** `iris_doc_load` of `src/ocutalon/cls` with flags `ck`, with no error or warning in the new or changed classes.
- `(loop)` **Slot A tests**, one call each, all passing:
  - `OcuTalon.Test.Demo.Orders`;
  - `OcuTalon.Test.Demo.Step`;
  - `OcuTalon.Test.Contract.Ac`;
  - `OcuTalon.Test.Data.Setting`;
  - `OcuTalon.Test.Web.Install`;
  - `OcuTalon.Test.Install.Registry`.
- `(loop)` `bash ci/checks.sh`. Expected: exit 0 (storage, class rules, boundaries with the `eval/` must-scan, `ci-config` with the Demo area).
- `(loop)` **Build.** `OCUTALON_RUN_TAG=v10a OCUTALON_LOCK_OWNER='epic=0 stage=implement' bash ci/iris.sh build`. Expected: exit 0.
- **Throwaway units**, each `(loop)` with the same environment, one call each:
  - `bash ci/iris.sh class OcuTalon.Test.Demo.Production`. Expected: 6 tests passing.
  - `bash ci/iris.sh live install-start`. Expected: exit 0, with the new demo-on, demo-off and surfaces PASS lines.
  - `bash ci/iris.sh live install-upgrade`. Expected: exit 0, with the orders probe kept and the updated `check_security`.
  - `bash ci/iris.sh live sign-in`. Expected: exit 0, through the updated `check_security`.
  - `bash ci/iris.sh shard lane-b`. Expected: exit 0, 23 classes.
  - `bash ci/iris.sh teardown`. Expected: nothing of `-v10a-` left.
- `(once)` **Task 0.** Steps 1–6, both images, each run its own call.
- `(once)` **Recording.** `bash docker/tests/record-eval.sh`, then `bash ci/checks.sh` again (the scans over the new files).
- `(once)` **Other live units.** `ci/iris.sh live production`, `live storage-roundtrip` and `live compose-start` stay green with OCUORDERS present. `live demo-path`'s `FIRST-START` line is recorded against 0.8's 47–53 s.
- `(once)` **Fresh-environment check** (Rules 19 and 21), one per call: `shard lane-a`, `shard lane-b --reverse` and `shard lane-a --reverse`; then `teardown`.
- `(once)` **The mutations below.**

**Shared surfaces:**
- **The step registry:** `Demo` filled in place, with the order and `expected_run` unchanged.
- **Production items:**
  - `OcuTalon.Production`'s item list is unchanged;
  - the new production-item list of `OcuTalon.Demo.Orders.Production` (three items) is pinned by `Test.Demo.Orders`.
- **The storage roots:** two new `Ens.Request` classes and one business process, with committed blocks and no new `DEFAULTGLOBAL` row. `test-storage-roundtrip.sh` exports them from OCUTALON.
- **`ci/units.sh`'s lists:** `lane-b` gets `Demo`. Rule 21's counts become 32 classes, 9 in `lane-a` and 23 in `lane-b`.
- **OCUORDERS itself:** created by every throwaway's start. Its messages from tests carry per-run `TraceRef`s and are deleted by their tests.
- **The trace role's resources and the web-application list:** `check_security`'s pin, used by `install-upgrade` and `sign-in`. `Test.Install.Registry.TestRolesStep` strips the OCUORDERS grants in `lane-a` throwaways until the next start, and no `lane-a` test asserts them.
- **The `demo.mode` row:** saved and restored by `Test.Demo.Step`; written by `set_demo_mode` only in throwaways.
- **`Test.Contract.Ac`'s `Signatures`:** floor 48.
- **`compose.throwaway.yml`'s mount**, in every throwaway.
- **`test-boundaries.sh`'s must-scan list.**
- **The README first-start figure.**

No test depends on another. Every fixture is unique to its run: `TraceRef`s from `NewRef()`, and the upgrade probe's reference derived from the project name.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, observe red, revert, and confirm `git status --short` and `git diff --stat` are unchanged):
- **AC1:** the `OcuTalon.Demo.Orders` package mapping not created → `live install-start` red at `check_demo_on "row 1"` (the package destination, and the production not running).
- **AC2:** `Mode()` writes the default whenever it runs instead of `Seed` → `live install-start` red at `check_demo_off "row 2"` (OCUORDERS back). `Test.Demo.Step` is red at `TestMode`.
- **AC3:** `Transform.OrderDate` also accepts `MM/DD/YYYY` → `Test.Demo.Production` red at `TestOneOrderInEachFormat`, and `Test.Demo.Orders` red at `TestTransformFailsOnTheChangedFormat`.
- **AC4:** `Partner` keeps the first batch's `DateFormat` in a global and reuses it → red at `TestPartnerKeepsNoState`.
- **AC5:** `Warehouse.OnMessage` returns an error → red at `TestRepairedCopyGoesThrough`.
- **AC6:** `System(0)` skips deleting the namespace's web applications → `live install-start` red at `compare_surfaces "row 2"` (an `app|…|OCUORDERS` line left).
- **AC7:** `Plan` returns "create" for an existing namespace it doesn't own → `Test.Demo.Step` red at `TestPlan`. `Owned()` always returns 1 → red at `TestOwned`.
- **AC8:** the transform's error text changed to "…was not valid" → `TestSnapshotIsReadableAndCurrent` red at the projection comparison. One character changed in `case.json`'s expectation → red at the case fields.
- **AC9:** `Send`'s `traceRef` renamed → `Test.Contract.Ac` red at `TestCrossLaneSignatures`.

### Task 0 measurements (implement stage, October 20; throwaways tagged v10a, one at a time)

Everything below was measured in a throwaway of this tree unless it is marked `(inference)`. W0, W1, W2 and W3 are `demo_surfaces --wide` listings; "byte-equal" is `cmp` on the two files.

- **Baselines.** Health image (`ocutalon-iris-base:2026.3.0AI.154.0`), Demo step still a stub: W0 = 52,652 lines (51,752 without `--wide`); first start ready in 47 s. Non-Health image (`iris-community:2026.3.0AI.154.0`, via `IRIS_IMAGE`; W0' from a git archive of the committed tree): W0' = 1,154 lines; ready in 32 s.
- **3a, the first start with demo mode on, Health image.** `STEP Demo OK 1.3s` (it includes enabling Interoperability, the trace application and the production start with its items alive); the whole start was ready in 53 s (W0: 47 s). OCUORDERS got no HealthShare artefact: no `HS`, `HSMOD`, `SchemaMap`, `%pkg.isc` or `HS.Local` mapping, no `^%SYS("HealthShare","Instances","OCUORDERS")`, no `hs|` line (so tripwire (i) did not fire; the production runs). W1 minus W0 is 409 lines, every one naming OCUORDERS apart from the `cpf|` mapping lines of `--wide`: 2 applications (`/csp/ocuorders`, `AutheEnabled` 32, `Path` `<data>csp/ocuorders`; `/ocutalon/trace/ocuorders`, 32), 2 databases at `<mgr>ocuorders_code/` and `<mgr>ocuorders_data/`, those 2 directories and the folder `csp/ocuorders`, the namespace (globals OCUORDERS_DATA, routines OCUORDERS_CODE), 2 resources (public permission 0), 3 roles (`%DB_OCUORDERS_CODE` and `%DB_OCUORDERS_DATA`, each RW on its own resource, and `%EnsRole_ProdPrivs_OCUORDERS`), the trace role's 2 resources, the `ens|` and `ensrun|` markers, 125 mapping lines (the 4 of row 1, `Ens`, `EnsLib`, `EnsPortal`, `CSPX.Dashboard` and the routine `Ens*` to ENSLIB, and the namespace's global mappings), 131 `cpf|` lines and 134 `sqlpriv|` rows (133 of the `%EnsRole_*` roles, 1 of `OcuTalonTraceViewer`).
- **3b, one order in each format** (`Partner.Send(1, ...)` in OCUORDERS). In YYYY-MM-DD: the PartnerOrder header (`PartnerOrdersIn` to `OrdersFromPartner`) `Status` 9 (Completed), `IsError` 0; then a WarehouseOrder header (`OrdersFromPartner` to `OrdersToWarehouse`) `Status` 9; one session; `SuperSession` = the reference. In MM/DD/YYYY: one PartnerOrder header, `Status` 8 (Error), `IsError` 0, `ErrorStatus` empty, a different session, `SuperSession` = the reference, and no WarehouseOrder. The event log holds one row of `Type` 2 (Error), `ConfigName` OrdersFromPartner, `SourceClass` Ens.Actor, `SourceMethod` MessageHeaderHandler, text "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'.    > ERROR #5001: ..." (see the first ruling of the Spec Change Log). `SELECT COUNT(*) FROM OcuTalon_Demo_Orders.PartnerOrder` works in OCUORDERS (2 rows after the two orders; WarehouseOrder 1). Compiling the Orders production in OCUTALON registers an `Ens.Config.Production` row there (`OcuTalon.Production` stays the running one). A method of `OcuTalon.Install.Step.Demo` cannot be called after `$NAMESPACE` is OCUORDERS (`<CLASS DOES NOT EXIST>`); `OcuTalon.Demo.Orders.*` resolves. The same holds for %SYS (scratch class on slot A, deleted) and `Security.*` does not exist in OCUTALON.
- **3c, off then on, Health image.** `demo.mode` 0 and a restart: `STEP Demo OK 3.7s`, W2 byte-equal to W0 (52,652 lines, `cpf|`, `dir|` and `cspdir|` lines included). `demo.mode` 1 and a restart: `STEP Demo OK 2.0s`, W3 byte-equal to W1 (53,061 lines). No leftover; tripwire (ii) did not fire. Anything outside the listing, such as other `^%SYS` nodes, was not compared `(inference: none)`.
- **3d, the comparison route (Health image).** `Config.Namespaces.Create` with `Interop=1` for a scratch ZZINTEROP took 10.3 s (the Demo step: 1.3 s) and installed a Foundation: `^%SYS("HealthShare","Instances","ZZINTEROP")`, the `HS`, `HSMOD`, `SchemaMap` and `%pkg.isc` mappings, 4 applications (`/csp/healthshare/zzinterop` with `AutheEnabled` 8224, `.../bulkfhir` with 64 and no sign-in, `.../bulkfhir/api` and `.../services` with 32), 20,660 `sqlpriv|` rows for the namespace. Against W1 the listing gained 9 namespaces (ZZINTEROP and 8 more), 21 databases (the 2 scratch ones included), 28 applications, 87 roles, 207 resources, 1,121 mapping lines and 71,020 `sqlpriv|` rows. That is why the step uses `EnableNamespace(..., 0, , 1)`.
- **4, the non-Health image.** W1' = 1,512 lines; `STEP Demo OK 1.4s`; ready in 29 s (W0': 32 s). Besides row 1's objects, `EnableNamespace` creates `OCUORDERS_DATAENSTEMP` at `<mgr>ocuorders_data/ocuorders_dataenstemp/` and `OCUORDERS_DATASECONDARY` at `<mgr>ocuorders_data/ocuorders_datasecondary/`, and the resource and same-named role `%DB_OCUORDERS_DATASECONDARY`. The first `System(0)` left that resource, role and role-resource (W2' differed from W0' in those 3 lines); with the removal added: off `STEP Demo OK 5.4s`, W2' byte-equal to W0'; on again 1.7 to 2.7 s, W3' byte-equal to W1'.
- **5, the mount.** In a throwaway, `/opt/ocutalon/eval/orders-date-format/{case.json,snapshot.json}` have the same SHA-256 as the repository's files, `touch` there answers "Read-only file system", and a container run from the built image alone has no `/opt/ocutalon/eval`.
- **6.** No setting for the portal application (`AutheEnabled` 32 on both images). The leftover of step 4 is removed in `System(0)` and is a line of `demo_surfaces` (`res|`, `role|`, `roleres|`).

### Results (implement stage; local developer machine, Apple silicon, warm layer cache)

- **Slot A** (build 154, `OCUTALON`): `iris_doc_load` of `src/ocutalon/cls` with `ck`: 174 classes, no error or warning. Passing, one class per call: `Test.Demo.Orders` 5 of 5, `Test.Demo.Step` 6 of 6, `Test.Contract.Ac` 6 of 6, `Test.Data.Setting` 5 of 5, `Test.Web.Install` 9 of 9, `Test.Install.Registry` 11 of 11. Slot A holds no OCUORDERS and no `demo.mode` row afterwards.
- `bash ci/checks.sh`: exit 0 (about 32 s), after the recording. `ci/iris.sh build`: exit 0.
- **Throwaway units:** `class OcuTalon.Test.Demo.Production` passed (6 tests, 2 s in the class, 54 s with the stack); `live install-start` passed in 170 s (2:49.9; 151 s on October 19); `live install-upgrade` passed in 168 s (2:48.3; 164 s); `live sign-in` passed in 65 s; `shard lane-b` passed, 23 classes, 61 s; `shard lane-a` passed, 9 classes, 54 s; `shard lane-b --reverse` and `shard lane-a --reverse` passed (61 s, 54 s); `live production` 90 s, `live storage-roundtrip` 67 s (56 storage blocks equal their files, the 3 new classes among them), `live compose-start` 73 s, `live demo-path` 61 s with `FIRST-START engine=aarch64 build=1s ready=52s` (0.8: 47 to 53 s) all passed. `ci/iris.sh teardown` for the tag left nothing.
- **REL-4.** The `install` group takes about 338 s here against 315 s before (+23 s: the demo-on and demo-off checks, the surface listings, the orders probe, and `STEP Demo` 1.3 to 5.4 s per start). On the x64 runner, at the 2.4 to 3.9 factor of Rule 21, that is about +55 to +90 s for the group `(inference)`, so `iris (install)` of 12 to 13 minutes goes to about 13 to 14.5 minutes `(inference)`; the other groups pay only `STEP Demo` and the 6 s of a first start per stack `(inference)`.

- **Review pass, second run after the patches** (same machine): slot A load of the 8 `Demo.Orders` and 3 `Test.Demo` classes with `ck`, no warning, `Test.Demo.Orders` 5 of 5; `bash ci/checks.sh` exit 0 (including `test-lib-live.sh` with its nine new `compare_surfaces` checks); `class OcuTalon.Test.Demo.Production` passed (53 s with the stack); `live install-start` 163 s, 56 PASS lines; `live install-upgrade` 168 s, 34 PASS lines (the `install` group about 331 s against 315 s before this story: +16 s locally); `live sign-in` 64 s; `shard lane-b` 61 s, 23 classes. `(once)`: `record-eval.sh` 56 s (50 failures, ASCII, no path), `live production` 82 s, `live storage-roundtrip` 63 s, `live compose-start` 68 s, `live demo-path` 60 s (`FIRST-START engine=aarch64 build=1s ready=53s`), `shard lane-a` 54 s (9 classes; one pre-existing SKIP in `Test.Install.Production.TestStepHelpers`, which this story does not touch), `shard lane-b --reverse` 61 s, `shard lane-a --reverse` 57 s; `ci/iris.sh teardown` for tag v10a left nothing.

### Mutations demonstrated (Rule 19; each applied, red observed, reverted, and the file byte-identical with `git status --short` and `git diff --stat` unchanged)

- mutation: AC1 - the `OcuTalon.Demo.Orders` mapping removed from the four in `System(1)` -> `live install-start` red at row 1: `STEP Demo FAILED ERROR #5809: Object to Load not found, class '%Dictionary.CompiledClass', ID 'OcuTalon.Demo.Orders.Production'`, the start ends "not ready", so the script stops at "row 1 the first start did not end ready" before `check_demo_on` (the step fails earlier than the check the plan expected).
- mutation: AC2 - `Mode()` writes the default into the row at every run instead of leaving it -> `live install-start` red at `check_demo_off "row 2"` (15 of 15 values, OCUORDERS back) and at "row 2: nothing else changes" (278 lines name OCUORDERS), and `Test.Demo.Step` red at `TestMode` (the values '1', '2' and 'yes' are not kept).
- mutation: AC3 - `Transform.OrderDate` also accepts a `MM/DD/YYYY` date -> `Test.Demo.Orders` red at `TestTransformFailsOnTheChangedFormat`, and `Test.Demo.Production` red at `TestOneOrderInEachFormat` ("the bad order fails at OrdersFromPartner").
- mutation: AC4 - `Partner.Orders` keeps the first batch's `DateFormat` in a global and reuses it -> `Test.Demo.Production` red at `TestPartnerKeepsNoState` ("all 3 orders of the first batch fail").
- mutation: AC5 - `Warehouse.OnMessage` returns an error -> `Test.Demo.Production` red at `TestRepairedCopyGoesThrough` ("the repaired copy reaches the warehouse"), and at `TestOneOrderInEachFormat`.
- mutation: AC6 - `System(0)` does not delete the namespace's web applications -> `live install-start` red at "row 2: nothing else changes" (`app|/csp/ocuorders|OCUORDERS|32` and `app|/ocutalon/trace/ocuorders|OCUORDERS|32` left behind) and at `check_demo_off "row 2"` (apps 2, not 0).
- mutation: AC7 - `Plan` takes the "create" branch for an existing namespace it does not own -> `Test.Demo.Step` red at `TestPlan` ("on 1, exists 1, owned 0 is error"); `Owned()` always returns 1 -> red at `TestOwned`.
- mutation: AC8 - the transform's error text changed to "The order date was not valid." -> `Test.Demo.Production` red at `TestSnapshotIsReadableAndCurrent` ("a fresh recording has the committed snapshot's projection"); one character of `case.json`'s expectation changed ("OrderDatf") -> red at the same test ("the expected element at fault is OrderDate").
- mutation: AC9 - `Partner.Send`'s `traceRef` renamed `ref` -> `Test.Contract.Ac` red at `TestCrossLaneSignatures` ("takes (count,dateFormat,traceRef,orderDate) in that order").
- mutation: AC1 (review pass) - the `OcuTalon.Web.Public` mapping of `System(1)` aimed at `OCUTALON_CODE`, the step itself still OK -> `live install-start` red at `check_demo_on` in row 1 and in row 4 ("1 of 16 values differ": `dest-web-public`); the new `portal-authe` line of `check_demo_on` is part of the 16.
- mutation: AC4 (review pass) - `Partner.Orders` checks the trace reference with the letters pattern `?22(1U,1L,1N,1"-",1"_")` instead of `$Match(ref, "^[A-Za-z0-9_-]{22}$")` -> `Test.Demo.Orders` red at `TestBatch` ("bad batch 9 is refused naming its value" and "bad batch 9 builds no order": 22 x `$Char(233)`).
- mutation: AC6 (review pass) - `compare_surfaces`'s `diff` replaced by a no-op -> `test-lib-live.sh` red at three checks (a line gone, a line new, and surfaces that differ without `--drop-orders`); before this the recorded AC6 mutations went red only through the "OCUORDERS line left behind" branch.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The Demo step now creates and removes OCUORDERS at every start, by the demo-mode setting `demo.mode`. The Orders production runs there: a simulated partner, a business process with a real DTL transform, and a warehouse operation. An order dated `MM/DD/YYYY` fails in the transform with a real IRIS error, and one dated `YYYY-MM-DD` goes through. One recorded 50-order failure is committed under `eval/orders-date-format/` and mounted read-only into throwaways. The on, off and upgrade checks ride on the `install` group's two live scripts with no new restart.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls`: the Demo step (`Run`, `Plan`, `Mode`, `DefaultMode`, `WithOrders`, `Directory`, `Owned`, `System`, `Orders`).
- `src/ocutalon/cls/OcuTalon/Demo/Orders/{PartnerOrder,WarehouseOrder,Batch,Partner,Transform,Translator,Warehouse,Production}.cls`: the Orders production (new).
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls`: `Parameter GLOBALNAME`, for the `public-global` class rule.
- `src/ocutalon/cls/OcuTalon/Test/Demo/{Orders,Step,Production}.cls`: the new `Test.Demo` area (slot A and `lane-b`; the production tests run in throwaways).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`, `Test/Web/PublicTexts.cls`: the `Partner.Send` signature with the floor 48; the 19th non-text parameter.
- `docker/tests/lib-live.sh`: `set_demo_mode`, `demo_surfaces`, `compare_surfaces`, `check_demo_on`, `check_demo_off`, `check_orders_jobs`; `security_app_props`, `check_security` and `item_jobs` extended.
- `docker/tests/test-install-start.sh`, `test-install-upgrade.sh`: the demo-on, demo-off, surfaces and orders-probe checks on the existing restarts.
- `docker/tests/test-lib-live.sh`: hermetic cases for `compare_surfaces` (review patch).
- `docker/tests/compose.throwaway.yml`: the read-only `./eval` mount at `/opt/ocutalon/eval`.
- `docker/tests/record-eval.sh`: the recorder of the snapshot (new; not a CI unit).
- `docker/tests/test-boundaries.sh`, `test-compose-start.sh`: the `eval/` files in the must-scan list; the image-files listing leaves the mount out and asserts the image holds none.
- `eval/orders-date-format/case.json`, `snapshot.json`: the evaluation case and its recorded snapshot (new).
- `ci/units.sh`: `Demo` joins `lane-b`. `_bmad/custom/skill-rules.md`: Rule 21's class count (32: 9 in `lane-a`, 23 in `lane-b`).

**Review findings.** 44 findings from four layers: high 0, medium 6, low 30, false 8.
- Patches applied (8 entries): the Translator and Transform comments say where the error text lives; hermetic `compare_surfaces` cases in `test-lib-live.sh`; the two tests wait for the upstream header; `record-eval.sh` checks its tools before it starts a stack; the trace reference is checked with an ASCII regex; `check_demo_on` pins the portal application's `AutheEnabled` 32; AC1's second mutation; separate messages for a missing namespace and a production that does not run.
- Deferred (3, in the frontmatter `deferred:` list): the errored-header ruling for Lane A's reader (medium); the missing repository run of the non-Health path (medium); the untested foreign-state branches of `Orders` and `System` (medium).
- Rejected (low or false, each with its reason in the Review Triage Log): the foreign-name resource deletion on the off path, the missing lock, `--wide` unused, the double order build in `Send`, the snapshot field types, the version-file override, theoretical production states, a half-enabled namespace, a pre-existing public resource, the empty-header and the existing-file cases, the `^^` text of the Tasks, `Translator`'s wrong-class branch, the executed host of `Record`, the ASCII scan scope of `eval/`, and the intent-alignment readings.
- Follow-up review recommended: `false` (one medium entry was patched, no high).

**Verification performed** (local developer machine, Apple silicon; commands and timings are under `## Verification`, "Results"):
- Slot A: `src/ocutalon/cls` loaded with `ck`, no error or warning; `Test.Demo.Orders` 5, `Test.Demo.Step` 6, `Test.Contract.Ac` 6, `Test.Data.Setting` 5, `Test.Web.Install` 9 and `Test.Install.Registry` 11 passing, one class per call; slot A holds no OCUORDERS and no `demo.mode` row.
- `bash ci/checks.sh` exit 0, three times (after the handoff, after the patches, after the recording).
- Throwaways of tag v10a, one at a time: `class Test.Demo.Production`, `live install-start` (163 s), `live install-upgrade` (168 s), `live sign-in`, `shard lane-b` (23 classes), then `record-eval.sh`, `live production`, `live storage-roundtrip`, `live compose-start`, `live demo-path` (`FIRST-START ... ready=53s`), `shard lane-a`, `shard lane-b --reverse` and `shard lane-a --reverse`, all passing; `ci/iris.sh teardown` left nothing.
- Task 0 was measured on both images (Health and non-Health); none of its three tripwires fired.
- Mutations: one per AC, plus three in the review pass, each red and reverted byte-identical.

**Residual risks.**
- **Lane A's reader.** A failed order's header has `Status` 8, `IsError` 0 and no `ErrorStatus`; the error text is the event-log row, wrapped as "Terminating BP ... due to error: ...". Matrix row 10 of this spec says `IsError` 1, which the platform cannot give with an asynchronous partner. The lead should restate row 10 and hand the finding to Stories 5.1, 5.2 and 5.4 (deferred item 1).
- **REL-4.** The `install` group grows by about 16 to 23 s locally; at Rule 21's x64 factor that is about +40 to +90 s (inference). Every first start also pays the OCUORDERS creation. The first CI run measures it.
- **Eval mount on the x64 runner.** Not measured: the mounted files must be readable by the IRIS user, and a restrictive umask on the checked-out `eval/` files would turn `TestSnapshotIsReadableAndCurrent` red.
- **Non-Health image.** Verified by hand only (deferred item 2).
- **Veto window items (Rule 22.3), for the Contest Planner.** The error text and the three item names (public-facing text); demo mode off deletes `OCUORDERS_DATA` and its orders (data loss, as AD-3 and AD-23 direct); the portal application `/csp/ocuorders` answers with a password only (`AutheEnabled` 32), so no setting was needed.
