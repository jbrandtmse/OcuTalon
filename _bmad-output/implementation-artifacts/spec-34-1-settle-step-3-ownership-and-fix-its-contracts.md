---
title: 'Story 34.1: Settle step 3 ownership and fix its contracts'
type: 'feature'
created: '2026-11-04'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-34-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 3 (memory and documents) is half-named in the spine: AD-21 names the tables, `TurnToolsClass`, `DropSession` and the model path, but not the memory and document operations, the `document` event and its publisher, the tool names, the ranking parameters, how a reply marks what it used, or the PDF/Word extraction; no step 3 code exists, and nobody has checked that AI Hub's FastEmbed finds the model offline on an IPM install. Lane B's Story 34.2 and Epics 19 and 20 cannot start without those names.

**Approach:** First measure the FastEmbed model path on a fresh IPM-installed throwaway (Task 0; stop if it fails). Then confirm P6 in the PRD and spine, write every missing step 3 contract into the spine as plain unions (`### Spine edits`), and land Lane A's code as compiling stubs: two disabled operation items, the `Memory` and `Document` tables, the two `DropSession` stubs, the private-data check widened to knowledge-base tables, and a static rule that fails a `CREATE TABLE` without the private `DEFAULTGLOBAL`.

## Boundaries & Constraints

**Always:**
- Task 0 runs first. If its verdict is FAIL, no other task is written (AC stop rule); if it cannot run, HALT `blocked` with a `TOOLING:` condition.
- Spine additions are new rows, sub-bullets, sentences or appended clauses, each marked `[ADDED 2026-11-05, Story 34.1]` or `[AMENDED 2026-11-05, Story 34.1, ...]`; no existing sentence of a Rule, Binds, Prevents or convention row is changed; `lint_spine.py` shows no finding beyond its 8 pre-existing `placeholder` ones.
- New items sit inside `<!-- lane A: begin -->`/`<!-- lane A: end -->`, `Enabled="false"`, classes with `Parameter STUB = 1` answering `$$$ERROR($$$NotImplemented)` (5003).
- New tables set `DEFAULTGLOBAL` `^OcuTalonP.<Short>` from a row appended to `src/short-names.tsv`, carry their compiler-generated `Storage` block, and use no SQL reserved word (checked on slot C: none of the planned names is reserved).
- `DropSession` stubs return `$$$OK` and change nothing (no step 3 rows can exist before Epic 19), so a `SessionOps.End` that calls them keeps signing out.
- ASCII only in every file written; no local machine path; in committed text the lock folder is written `"$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c"`.
- Contended files get insertions only: the spine (away from Epic 39's lines near 559 and 596 and Epic 40's near 951, 1080 and 1303-1305), `Test/Data/Tables.cls` (two rows inserted mid-list, never at its end), `src/short-names.tsv` (append; `merge=union`).

**Never:**
- Edit a Lane B class or test (U-177): `Msg/**`, `Core/**`, `Web/**`, `web/**`, `Live/**` (including `Live/Publish.cls` and `Live/Payload/**`), `Data/Ownership.cls`, `docker/Dockerfile`, `Test/{Core,Web,Msg}/**`, `ci/units.sh`. Build none of Lane B's contracts (verbs, routing, routes, Dockerfile lines, payload class); only record them as Story 34.2's.
- Edit `EXPERIENCE.md` or any `epics.md` text (UX-DR144 included); they go to the lead as items.
- Build step 3 behaviour: no embedding, indexing, extraction, search, ranking, KB creation or drop, `TurnTools` base or setting, Python resource.
- Add an `AD-n` id, rename a CI job or iris group, or add a test area to `ci/units.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Production starts | package compiled; `OcuTalon.Production` starts | `MemoryOps`, `DocumentOps` have no job; every other item runs as before | none |
| Stub item answers | a request to a shadow `OcuTalon.Memory.Ops` / `OcuTalon.Docs.Ops` | status 5003, no response, no log row | by design |
| Sign-out calls drop stubs | `##class(OcuTalon.Docs).DropSession(ref)`, `##class(OcuTalon.Memory).DropSession(ref)` | `$$$OK`; no row of any table changes | none |
| Private KB table | a DDL table `OcuTalonKB.<T>` with `DEFAULTGLOBAL '^OcuTalonP.KB<T>'` exists | `Install.Step.PrivateData.Run()` is OK and lists its globals | none |
| Unprivate KB table | `OcuTalonKB.<T>` created without `DEFAULTGLOBAL` | `Run()` fails, naming the class and its global | start reports `STEP PrivateData FAILED` |
| KB DDL in source | a non-test code line in `src/` with `CREATE TABLE` lacking `DEFAULTGLOBAL` + `^OcuTalonP.` | `test-class-rules.sh` prints `FAIL` for rule `kb-ddl` with `file:line` | CI `checks` job red |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- 373 KB, read by range. Anchors: Invariants paragraphs 101-103; AD-1 113 (tool origins: "save or forget a memory"); AD-3 148 (`^IRIS.IF.*` mapped private); AD-4 167 and 177 (P23 owners; sign-out drops); AD-21 675-747 (Documents 680-684, Memory 685, Epic 41 block 686-729, vectors 730-734, model path 735); AD-23 private-data check 814; AD-25 golden copy (853-905, already consistent); AD-29 970 (Lane A owns `.Memory`, `.Docs`); AD-31 1017-1033 (`TurnToolsClass` named at 1022); AD-33 1058; Capability map 1081-1082 (Epic 40 edits 1080: do not touch); Conventions 1094-1143 (HostData row 1107); Stack 1166-1168 (pdfplumber, python-docx, fastembed already pinned); production items 1265-1294; Tables paragraph 1296; cross-area table 1298-1339 (DropSession row 1330); live events 1341-1357; erDiagram 1363-1394; Deferred 1540 (ranking) and 1545 (files).
- `_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md` -- FR-15 446-460 (reset bullet 460), FR-41 862, FR-42 875. Not contended.
- `src/ocutalon/cls/OcuTalon/Production.cls` -- Lane A region 15-62; `ReconcileIn` 59-61; stub form at 58: `<Item Name="Digest" ClassName="OcuTalon.Digest.Process" PoolSize="1" Enabled="false"/>`.
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls` -- stub pattern (doc comment states the future contract; `Parameter STUB = 1`); an operation stub uses `Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status { Quit $$$ERROR($$$NotImplemented) }` and needs no Storage block (as `Digest/Store.cls` at `91f89e20`).
- `src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls`, `.../Digest/Data/CheckRun.cls` -- table siblings: `Parameter DEFAULTGLOBAL` at line 8 with its registry comment, refs `%String(COLLATION = "EXACT", MAXLEN = 22)`, `Storage Default` at the end.
- `src/short-names.tsv` -- `short<TAB>global<TAB>class<TAB>lane`; no Memory/Document row yet.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- `XData Items` 649-676, row shape `{"lane","name","class","pool","enabled","stub","settings"}` in production order; `TestStubsAnswer` 157-202 (BO -> `OnMessage`, 5003, no response, no log rows).
- `src/ocutalon/cls/OcuTalon/Test/Install/ProductionRules.cls:146` -- Lane A prefixes already include `OcuTalon.Memory.` and `OcuTalon.Docs.` (no edit).
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- `TestEveryTableIsRegistered` 46-63 fails for any persistent `OcuTalon.Data.*` class without a row in `XData Registry` (620-744); insert after the `Handled` row (699-703). Contended (Epic 39 appends at the list's end).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls` -- `XData Signatures` 299-382, entry `{"class","method","args","returns"}`; floor `count >= 79` at 165 and "79 signatures" in the doc at 17-18.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Contracts.cls` -- sibling for the new contract test (extends `OcuTalon.Test.Contract`; `AssertContract("Contracts")`, `AssertSqlNames`, `TestRegistry` via `PrivateData.StorageGlobals`).
- `src/ocutalon/cls/OcuTalon/Install/Step/PrivateData.cls` -- `StorageGlobals` 27-46 (`%Dictionary.CompiledStorage ... %STARTSWITH 'OcuTalon.'`, keeps only `OcuTalonP.`/`OcuTalonBP.` globals at 40); `Check` 49-88 (resolution, then the data-database scan with `PREFIXES`, which already include `IRIS.IF.` and `AI.Agent.Session`). `irislib/%Dictionary/CompiledStorage.cls` (`ExtentLocation` :36) and `CompiledStorageIndex` (`Location` :21) hold DDL extent-set index globals.
- `src/ocutalon/cls/OcuTalon/Test/Install/PrivateData.cls` -- `PLANTED` :10, `TestPasses` :32, `TestPlantedGlobalFails` :38, `TestPrivateStorageGlobals` :54.
- `docker/tests/test-class-rules.sh` -- one scanner function per rule (`public_global` 84-91), fixtures via `write_class`/`expect_flagged`/`expect_clean` (289-309), `scan_rule` from `docker/tests/lib-scan.sh:25-60`; header rule list 2-32; in `CHECK_SCRIPTS` (hosted `checks` job). Only `CREATE TABLE` in `src/` today: fixture text `Test/Bridge/CodeRules.cls:794`.
- `irislib/%AI/RAG/VectorStore/IRIS.cls` -- `CreateTable` 75-127: `CREATE TABLE IF NOT EXISTS <T> (id VARCHAR(64) NOT NULL, text VARCHAR(32000) NOT NULL, vector VECTOR(DOUBLE, <dims>) NOT NULL, metadata VARCHAR(32000), source VARCHAR(512), PRIMARY KEY (id))` and `<T>_Config (model_name VARCHAR(255) NOT NULL, dimensions INTEGER NOT NULL)`, no `DEFAULTGLOBAL`; table names must match `^[A-Za-z_][A-Za-z0-9_]*$` per part (so no SessionRef in a table name).
- `irislib/%AI/RAG/Embedding/FastEmbed.cls` -- `Create()` makes the Rust provider (`$ZF(-6, ..., LLMRAGCREATEFASTEMBED)`), "downloads the model on the first call"; `EmbedBatch` throws. `irislib/%AI/RAG/KnowledgeBase.cls` -- `Build(emb, vs)` 69, `AddDocument(text, {"source":...})` 103. `%SYSTEM.Util` has `GetEnviron` (:92) and no setter, so a job sets the variable through Python `os.putenv`.
- `release/ipm-install.sh` -- the throwaway recipe Task 0 copies: sources `ci/iris.sh` (source-safe), `setup_tag; preflight; live_start ipm; live_add_file release/ipm/compose.ipm.yml; live_web_port; dc up -d --build --wait` (1420-1433), its `run` helper 150-162, install command `zpm "load /opt/ocutalon-ipm/src"` run in USER then OCUTALON; lib-live's trap removes the project and lock at exit.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:236-254` -- `End` (Lane B, read only; 34.2 adds the calls).

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0 -- FastEmbed model path on an IPM install (measure; stop rule).** Write a scratch script (stage scratchpad `e34s1implement/`, never committed) and run it in ONE foreground call (`timeout: 600000`) with `OCUTALON_LOCK_DIR=<lane-c lock folder> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=34 stage=implement' OCUTALON_RUN_TAG=e34s1f OCUTALON_LIVE_DEADLINE=570`. Print `TIME <step> <s>s` and one `CHK|<step>|...` line per observation. Steps:
  1. Stack: source the worktree's `ci/iris.sh`, then exactly as `release/ipm-install.sh` 1420-1433 (`setup_tag`, `preflight`, `live_start ipm`, `live_add_file release/ipm/compose.ipm.yml`, `live_web_port`, `dc up -d --build --wait`, `live_track_image`); `cid=$(dc ps -q iris)`. Session helper: `printf '%s\nHalt\n' "$cmd" | dc exec -T iris iris session IRIS -U <ns>`.
  2. Precondition: `dc exec -T iris printenv FASTEMBED_CACHE_DIR` exits 1, and `$SYSTEM.Util.GetEnviron("FASTEMBED_CACHE_DIR")` is empty.
  3. IPM install: `zpm "load /opt/ocutalon-ipm/src"` in USER (ends with the next-command sentence), then in OCUTALON (every `STEP <name> OK`, none FAILED). `F` = `$SYSTEM.Util.ManagerDirectory()_"fastembed/"`.
  4. Network on: `dc exec -T iris /usr/irissys/bin/irispython -c "import urllib.request as u; print(u.urlopen('https://huggingface.co', timeout=20).status)"` prints 200 (use `python3` if that path is absent).
  5. Download as the install step would (one OCUTALON job): `CreateDirectoryChain(F)`; `Set os=##class(%SYS.Python).Import("os") Do os.putenv("FASTEMBED_CACHE_DIR",F)`; `GetEnviron` shows F; `FastEmbed.Create()`; a VectorStore `Probe.FastEmbedDownload` (Dimensions 384) and KB `probe` built over it, one `AddDocument` (forces any lazy download). Each in Try/Catch writing `CHK|download|ok` or `CHK|download|error|<text>`. Then record `du -sk F`, `find F -type f | wc -l`, F's top two folder levels, and that no other cache exists (`ls -d <mgr>.fastembed_cache /tmp/fastembed_cache` both absent).
  6. Block: `docker network disconnect <net> "$cid"` for every network in `docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$cid"`; then `docker inspect` lists none and step 4's probe exits non-zero (record its error class).
  7. Control (new job, offline, no variable): `Create()` plus a KB `AddDocument` on `Probe.FastEmbedControl` -> expected `CHK|control|error|<text>`; record any folder it created.
  8. Test (new job, offline): `os.putenv("FASTEMBED_CACHE_DIR",F)` before any `%AI` call, `GetEnviron` check, `Create()`, VectorStore `Probe.FastEmbedPath` + KB + `AddDocument("The Results runbook: rotate the certificate, then resend.", {"source":"probe.md"})`, then `SELECT COUNT(*), MAX(VECTOR_DOT_PRODUCT(vector, vector)) FROM Probe.FastEmbedPath` -> expected `CHK|test|ok|<rows>=1+|<dot>0+`.
  9. Worker (offline): create routine `ZFEProbe` in OCUTALON (`%Routine`) whose `Run(dir,table)` does step 8 on `Probe.FastEmbedWorker`, records its `$JOB` and returns a status; `Set q=$SYSTEM.WorkMgr.%New() Do q.Queue("$$Run^ZFEProbe",F,"Probe.FastEmbedWorker") Set sc=q.WaitForComplete()` -> expected OK, rows >= 1, worker `$JOB` differs from the caller's.
  10. Order (recorded, not the stop rule): new job offline: build VectorStore `Probe.FastEmbedLate` first (loads the AI Hub library), then `putenv`, then `Create()` -> record ok or error.
  11. F's file count and size equal step 5's after steps 7-10 (no new download). Teardown: the script's exit trap, then `<prefix> ci/iris.sh teardown` with tag `e34s1f`; `docker ps -a --format '{{.Names}}' | grep e34s1f` prints nothing.
  **Verdict:** PASS when 8 and 9 are ok, 7 errors, 6's block is verified and 11 holds. FAIL when 8 or 9 errors, 7 succeeds, or F changed -> HALT `blocked`, `intent gap: AI Hub's FastEmbed does not find the model by <mgr>/fastembed/ offline on an IPM install (evidence 34-1-task0-fastembed-path.md); the author decides before any document code`, and write no other task. Steps 1-5 failing is not a verdict: HALT `blocked` with `TOOLING: Task 0 could not run: <step and error>`. Write `_bmad-output/implementation-artifacts/evidence/34-1-task0-fastembed-path.md` (structure of `33-1-task0-zone-measurement.md`: title, Date, Target (throwaway, tag, image build, IPM version), Repo, `## Verdict`, then one section per step with its CHK and TIME lines and error texts; container paths allowed, no host paths, ASCII).
- [ ] `_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md` -- after FR-15's reset bullet (460) add one bullet: "- **Step 3 data:** from step 3, a session's memories and documents are its own too (FR-41, FR-42), and the scheduled reset clears them with the session (P6, decided through P23 on October 17). [AMENDED 2026-11-05, Story 34.1: confirms P6; no other text changed]" -- P6 confirmation (FR-41 862 and FR-42 875 already state the owners; record both lines in the Spec Change Log as "already recorded").
- [ ] `ARCHITECTURE-SPINE.md` -- apply S1-S16 of `### Spine edits` with `### Spine content`, Task 0's result in S5; then `uv run --no-cache _bmad/scripts/memlog.py append --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 --type decision --text "Story 34.1: step 3 contracts (AD-21, AD-23, AD-31, AD-33 extensions; MemoryOps, DocumentOps, document event, Memory and Document tables, KB naming, tool names, ranking, reply citations and memories, extraction names; FastEmbed IPM path measured)"` and `lint_spine.py` (no new finding); refresh the spine's `updated:`.
- [ ] `src/ocutalon/cls/OcuTalon/Memory/Ops.cls` -- new `Ens.BusinessOperation` stub, `Parameter STUB = 1`, `OnMessage` answers 5003; doc comment states S3's contract (answers `SaveMemory`/`ForgetMemory` from `CommandsIn` with a `CommandResult`; built in Story 19.3).
- [ ] `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` -- the same for documents (answers `AddDocument`/`RemoveDocument`, keeps `Data.Document`, the `document` event's single publisher; built in Story 19.4).
- [ ] `src/ocutalon/cls/OcuTalon/Memory.cls` and `src/ocutalon/cls/OcuTalon/Docs.cls` -- new classes, each `ClassMethod DropSession(sessionRef As %String) As %Status { Quit $$$OK }`; doc comment: called by `SessionOps.End` on an online-demo sign-out, drops the session's memories (resp. its knowledge base `OcuTalonKB.S<id>`, `_Config` and `Document` rows), changes nothing until Story 19.5.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Memory.cls` -- new `%Persistent`, `DEFAULTGLOBAL "^OcuTalonP.Memory"`: `Ref`, `SessionRef` `%String(COLLATION = "EXACT", MAXLEN = 22)`; `Text` `%String(MAXLEN = 2000)`; `SavedAt` `%String(MAXLEN = 20)`; `ItemId` `%String(COLLATION = "EXACT", MAXLEN = 22)`; `Origin` `%String(MAXLEN = 16)`; `Embedding` `%Library.Vector(DATATYPE = "DOUBLE", LEN = 384)`; `Index RefIndex On Ref [ Unique ]`, `Index SessionRefSavedAtIndex On (SessionRef, SavedAt)`; compile, commit Storage.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Document.cls` -- new `%Persistent`, `DEFAULTGLOBAL "^OcuTalonP.Document"`: `Ref`, `OwnerRef`, `AddedBy` `%String(COLLATION = "EXACT", MAXLEN = 22)`; `Name` `%String(MAXLEN = 255)`; `ContentType` `%String(MAXLEN = 16)`; `Size` `%Integer`; `AddedAt` `%String(MAXLEN = 20)`; `State` `%String(MAXLEN = 16) [ InitialExpression = "indexing" ]`; `Reason` `%String(MAXLEN = 32)`; `KnowledgeBase` `%String(MAXLEN = 128)`; `Text` `%Stream.GlobalCharacter`; `Index RefIndex On Ref [ Unique ]`, `Index OwnerRefAddedAtIndex On (OwnerRef, AddedAt)`; compile, commit Storage.
- [ ] `src/short-names.tsv` -- append `Memory<TAB>^OcuTalonP.Memory<TAB>OcuTalon.Data.Memory<TAB>A` and `Document<TAB>^OcuTalonP.Document<TAB>OcuTalon.Data.Document<TAB>A` (`<TAB>` is a tab character).
- [ ] `src/ocutalon/cls/OcuTalon/Production.cls` -- Lane A region only, after `ReconcileIn` (61): `<Item Name="MemoryOps" ClassName="OcuTalon.Memory.Ops" PoolSize="1" Enabled="false"/>` and `<Item Name="DocumentOps" ClassName="OcuTalon.Docs.Ops" PoolSize="1" Enabled="false"/>`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- two oracle rows after `ReconcileIn`'s, `"enabled": 0, "stub": 1, "settings": []`; doc line naming them.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- insert the `Memory` and `Document` registry rows (`{"short","global","class"}`) right after the `Handled` row (699-703), touching no existing line; nothing else (contended).
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/PrivateData.cls` -- `StorageGlobals` also reads classes `%STARTSWITH 'OcuTalonKB.'` and, for those only, keeps every global of the class whatever its prefix (Data, Id, Index, Stream, `ExtentLocation` when set, and each `%Dictionary.CompiledStorageIndex.Location`), so a knowledge-base global outside `^OcuTalonP.` fails `Check`'s resolution test with the class named; existing behaviour for `OcuTalon.*` unchanged; doc comment names memory, document and knowledge-base globals and `^IRIS.IF.*` (S7).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/PrivateData.cls` -- `TestStep3Globals`: `StorageGlobals` lists `^OcuTalonP.MemoryD` and `^OcuTalonP.DocumentD` (and the stream global), and `PREFIXES`/`SAMPLES` still hold `IRIS.IF.`; `TestKnowledgeBaseTables`: in OCUTALON create `OcuTalonKB.Zz341` with `WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KBZz341'` -> `StorageGlobals` lists its globals and `Run()` is OK; create `OcuTalonKB.Zz341Bad` without it -> `Run()` fails naming it; both dropped in `OnAfterOneTest` whatever the outcome (hermetic).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Contract/Step3.cls` -- new, extends `OcuTalon.Test.Contract` (copy `Test.Digest.Contracts`' shape): `TestContracts` (`XData Contracts` for both tables, types and indexes, `AssertSqlNames`); `TestRefCollation`; `TestRegistry` (DEFAULTGLOBAL equals the tsv row, data global plus D, globals private); `TestDropSession` (both return OK for a fixture SessionRef; `Memory` and `Document` row counts unchanged).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls` -- append `{"class": "OcuTalon.Docs", "method": "DropSession", "args": "sessionRef", "returns": "%Status"}` and the same for `OcuTalon.Memory`; floor 79 -> 81 and the doc's count.
- [ ] `docker/tests/test-class-rules.sh` -- new rule `kb-ddl` (copy `public_global`'s shape and fixtures): (a) a code line (comments skipped) of a `.cls` or `.py` file under `src/`, outside `src/ocutalon/cls/OcuTalon/Test/`, that holds `CREATE TABLE` (any case) must hold `DEFAULTGLOBAL` and `^OcuTalonP.` (`^OcuTalonBP.` under `src/bridge/`) on the same line; (b) `%AI.RAG.VectorStore.IRIS` appears only in classes under `src/ocutalon/cls/OcuTalon/Docs/` or the Test package; bad, good and comment-only samples self-tested; header lists the rule.

**Acceptance Criteria:**
- Given Task 0's evidence, when the spine update is written, then AD-21's model-path bullet records the measured result (S5) and the verdict is PASS; on FAIL the run has stopped with the intent gap and nothing else is written.
- Given the PRD and spine after the edits, when the reviewer reads them against `### Spine edits` and the P6 checklist, then FR-15 holds the step 3 bullet, every S-row is present with its marker, no existing Rule, Binds, Prevents or convention sentence changed, and `lint_spine.py` shows only the 8 pre-existing findings.
- Given the compiled package, when the production starts, then `MemoryOps` and `DocumentOps` sit in Lane A's region with no job and `Test.Install.Production`, `Test.Install.ProductionRules` and `live:production` pass.
- Given the two new tables, when the checks run, then `test-storage.sh`, `Test.Contract.Step3` and `Test.Data.Tables` pass.
- Given Lane B calling `OcuTalon.Docs.DropSession(ref)` and `OcuTalon.Memory.DropSession(ref)`, when called, then they compile, return OK, change nothing, and `Test.Contract.Ac` pins both signatures.
- Given a start, when `PrivateData` runs, then it covers memory, document and knowledge-base globals and `^IRIS.IF.*`, and `Test.Install.PrivateData` and `live:install-start` (`STEP PrivateData OK`) pass.
- Given `test-class-rules.sh`, when a product line creates a table without the private `DEFAULTGLOBAL`, then rule `kb-ddl` fails; on the tree as committed it passes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-1 (verbs, origins), AD-2 (`%AI` allow-list: `OcuTalon.Docs`/`.Memory` packages; note the classes `OcuTalon.Docs` and `OcuTalon.Memory` sit in package `OcuTalon`, so `DropSession` must stay `%AI`-free, which SQL `DROP TABLE` is), AD-3 (private globals, `^IRIS.IF.*`), AD-4 (P23 owners, sign-out drops), AD-5 (append-only storage; Epic 41 appends `Source`, `Pinned`, `PinnedAt`; 19.3 appends the indexes), AD-12 (live events), AD-21, AD-23 (private-data check, model path, pinned pip installs), AD-25 (reset restores the golden copy; already consistent, no edit), AD-29 (lanes, regions, stubs, step-contract epics), AD-31 (`TurnToolsClass`), AD-33 (tables, single publisher, KB DDL check). Deferred rows 1540 and 1545 are touched (S15). No AC contradicts an AD Rule; no new AD is needed.

**P6 checklist (AC 1):** already recorded -- PRD FR-41 862, FR-42 875, glossary 165, Open Question 3 1699; UX `EXPERIENCE.md` 652, open items 1095 and 1110, assumptions 1122; UX-DR107 (epics 439), UX-DR144 (476), UX-DR153 (485); spine AD-4 167/177, AD-21 680-684 and 729, Capability map 1081. Added -- PRD FR-15 bullet (the reset clears step 3 data). AD-21's reset/sign-out alignment is already recorded at 684 and AD-4 177 (the reset runs nothing; sign-out drops through `DropSession`).

**Spine checklist (AC 2) -- already recorded:** `TurnToolsClass` (682, 1022), `OcuTalon.Data.Memory` (685), `OcuTalon.Memory.Embedder` (732), `OcuTalon.Memory.Embedding` (731), KB table names and `DEFAULTGLOBAL` (681), the `documents` tool and `TopK` <= 5 (683), `DropSession` (684, 101, 1330), model path (735), private-data check (814), KB DDL check (1058), Lane A's `.Memory`/`.Docs` (970), Stack rows pdfplumber 0.11.10, python-docx 1.1.2, fastembed 0.9.0 (1166-1168). Everything else is added by S1-S16.

**Decided in-stage:**
1. **Items:** `MemoryOps` (`OcuTalon.Memory.Ops`) and `DocumentOps` (`OcuTalon.Docs.Ops`), adapterless business operations like `WatchOps`. `DocumentOps` is the `document` event's single publisher; how it indexes without blocking commands (an async message to itself or a helper item) is Story 19.4's, and any item it adds joins the tables in that story's change.
2. **`TurnToolsClass` gets its contract only, no code:** its base, setting and implementation are all Lane A and first used by Story 19.5; adding a `Decide` property now would grow a business process's storage for no caller.
3. **Tables carry the cross-lane fields now** (what Lane B lists and what citations need); the HNSW and `%iFind` indexes are appended by Story 19.3, which measures where their globals land and extends the private-data check if a new prefix appears. `Embedding` is created now because AD-21 fixes its type.
4. **Document owner:** `OwnerRef` = the session's `SessionRef` on the online demo, the literal `instance` on a local install (shared, P23), as bridge records use it; `AddedBy` keeps the adding session.
5. **KB names:** `<id>` in `OcuTalonKB.S<id>` is the session's `OcuTalon.Data.Session` row id, because a SessionRef holds `-`, which an SQL identifier and AI Hub's name check refuse; ids are not reused before the reset, which removes every such table. Globals `^OcuTalonP.KB<suffix>` and `^OcuTalonP.KB<suffix>Config`.
6. **Reply marking:** code builds the reply's citations and memories from the turn's own tool results (never from model text): a passage counts as used when the `documents` tool returned it in that turn, a memory when `search_memories` returned it; at most 5 each.
7. **Ranking:** reciprocal-rank fusion with k = 60 over the 20 nearest by cosine (HNSW) and the 20 best `%iFind` hits, equal weights, top 5, ties to the newer `SavedAt`; the HNSW check runs at 10,000 memories of one owner.
8. **Verbs (Lane B, 34.2):** `SaveMemory` (`Text`; origin `tool`), `ForgetMemory` (`MemoryRef`; `tool`), `AddDocument` (`Name`, `ContentType`, `Content` stream; `web_user`), `RemoveDocument` (`DocumentRef`; `web_user`); Epic 41 adds its own origins.
9. **The contract test lives in `Test/Contract/`** (already in shard lane-b), so `ci/units.sh` (contended) is not edited; `Test.Memory`/`Test.Docs` areas start with Epic 19.
10. **Task 0 uses a fresh job and a WorkMgr worker** as "its own worker"; the install's download step itself is Story 19.2's, done as step 5 does it. The Python package reading that folder is not measured here (S5 marks it inference; Story 19.2 measures it).
11. **Stub `DropSession` returns OK**, not 5003, because `SessionOps.End` clears the resume cookie only when nothing failed.

**For the lead (items to raise; none blocks this plan):**
- **To the author (UX, contended with Epic 40, not edited here):** UX-DR144 still reads "PDF, Word from S6" and `EXPERIENCE.md` 963 "then PDF and Word from step 6"; the owner moved them to step 3 (PRD OQ3, 2026-10-25). Proposed: "accepting Markdown, plain text, PDF and Word (.docx) files." The UX also never states the local-install rule; proposed for the assumptions (1122): "On a local install, memories belong to each user and documents are shared by every user of the install (P23)."
- **Story 34.2 scope (same epic, veto (8) if you read it so):** `Live/Publish.cls` TYPES and the payload classes are Lane B's files, and `web/scripts/payloads.mjs` refuses a payload class missing from TYPES, so Story 34.2 creates `OcuTalon.Live.Payload.Document` with S2's fields and the `document:Document` TYPES entry; the class's owner is Lane A (its publisher) from Story 19.4.
- **Reply marking (decided 6)** says what the chips claim ("the passages the answer was given"); veto (5) if read as a product claim.
- **IPM and Python packages:** nothing installs `fastembed`, `pdfplumber` or `python-docx` on an IPM install (`src/module.xml` has no Python requirement); Stories 19.2/19.6 or FR-57 must say how.

**Lead rulings at the spec gate (2026-11-05, runner C, policy 5086036):**
- **UX wording for the author** (AC 3's "puts UX-DR144's 'PDF, Word from S6' to the author"): put to the author as inbox item U-279 (veto) with the proposed wording above. This story edits neither `EXPERIENCE.md` nor UX-DR144's text. Story 34.2 builds from epics.md (Markdown, plain text, PDF, Word).
- **Reply marking (decided 6):** kept as decided; recorded as veto item U-280 (claims about what the product does). Reversal: one Conventions row, before Story 20.2 builds the chips.
- **`OcuTalon.Live.Payload.Document` and the `document:Document` TYPES entry go to Story 34.2** (decide: the same epic, and within 34.2's AC "updated live from `document` events"). The lead carries it into 34.2's plan prompt.
- **IPM and Python packages:** no gap to file. Story 19.2's AC already has the package declare `fastembed==0.9.0` for an IPM install, and Story 19.6's declares `pdfplumber==0.11.10` and `python-docx==1.1.2` (decide; no ledger entry).
- **Task 0 runs in the implement stage as written**, first, with its stop rule. On FAIL the implement stage HALTs `blocked` with the intent gap and writes nothing else.

**Integration ACs (Rule 1):** No consumers in this story; the first consumer will be Story 34.2 (`SessionOps.End` calling both `DropSession` stubs; `CommandsIn` routing the four verbs to the `MemoryOps`/`DocumentOps` stubs, which answer 5003 until Epic 19).

**Consumed-by:**
- 34.2 -- `DropSession` stubs; item names for routing; verb names and origins; `document` event, publisher and payload fields; KB naming for listing.
- 19.2 -- `Memory.Embedding`, `Memory.Embedder`, the `<mgr>/fastembed/` path as measured.
- 19.3 -- `MemoryOps`, `Data.Memory`, `Memory.Search`/`.List`, tool names, ranking, volume, reply `memories`.
- 19.4 -- `DocumentOps`, `Data.Document`, KB tables, `document` event, reply `citations`.
- 19.5 -- `TurnToolsClass` contract, `DropSession` bodies, per-session table names.
- 19.6/19.7 -- `Docs.Extract`, `Docs.Extractor`, `ocutalon_extract.py`.
- 20.2 -- `HostData.citations`/`.memories` shape.
- 41.x -- `Data.Memory` (appends), `MemoryOps` (pin verbs).

**Consumes:** `OcuTalon.Install.Step.PrivateData` (extended); `OcuTalon.Test.Contract` base.

**Extend, don't copy (Rule 2):** tables follow `Digest/Data/Item.cls`/`CheckRun.cls`; the op stubs follow `Digest/Process.cls` (operation form of `Digest/Store.cls` at `91f89e20`); `Test.Contract.Step3` extends `OcuTalon.Test.Contract` and mirrors `Test.Digest.Contracts` (that class pins the Digest tables only); `PrivateData`, `Test.Install.PrivateData`, `Test.Contract.Ac`, `Test.Install.Production` and `test-class-rules.sh` (rule shaped on `public_global`) are extended.

**Declined ledger entries:** none (inbox empty).

**Contended files touched:** the spine (Epics 39, 40: S-rows away from their lines), `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` (Epic 39: two rows inserted after `Handled`), `src/short-names.tsv` (Epic 39: append, union-merged).

**Footprint extensions (Rule 11 b):** `src/ocutalon/cls/OcuTalon/Memory.cls`, `src/ocutalon/cls/OcuTalon/Docs.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/PrivateData.cls`, `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`, `src/short-names.tsv`, `docker/tests/test-class-rules.sh`, the PRD, `.memlog.md`, the evidence file.

### Spine edits

| # | Section | Edit | Class |
|---|---|---|---|
| S1 | Invariants, after 103 | New paragraph: step 3 edges | new name |
| S2 | AD-21 Documents, after 684 | Sub-bullets: names, tables, `document` event, PDF and Word | extension |
| S3 | AD-21 Memory, under 685 | Sub-bullets: `MemoryOps`, reads, tools, ranking, table, volume | extension |
| S4 | AD-21, after S3 | One bullet pointing at Conventions "Citations and memories" | extension |
| S5 | AD-21 model path, end of 735 | Appended clause: Task 0's measured result | extension |
| S6 | AD-31, after 1025 | Sub-bullet: the `TurnToolsClass` contract | extension |
| S7 | AD-23 private-data check, end of 814 | Appended clause: how KB globals are found | extension |
| S8 | AD-33, end of 1058 | Appended clause: the check is rule `kb-ddl` | extension |
| S9 | Conventions, after 1107 | New row "Citations and memories" | new row |
| S10 | Production items, after 1294 | New row: `MemoryOps`, `DocumentOps` | new row |
| S11 | Tables paragraph, end of 1296 | Appended sentence | new name |
| S12 | Cross-area table, after 1330 | New rows (below); clause appended to 1330 | new row |
| S13 | Live events, after 1357 | New row `document` | new row |
| S14 | erDiagram, after 1384 | `Session ||--o{ Document : "step 3"` and a marker comment | new name |
| S15 | Deferred 1540 and 1545 | Appended clauses | extension |
| S16 | front matter | `updated:` refreshed | -- |

### Spine content

- **S1.** "From step 3, `OcuTalon.Tools` may call `OcuTalon.Memory.Search` and `OcuTalon.Memory.List` (Lane A, Story 19.3; AD-21), and the web layer reads `OcuTalon.Data.Memory` and `OcuTalon.Data.Document` only through the ownership API (AD-4)."
- **S2.** *Names:* `DocumentOps` (`OcuTalon.Docs.Ops`, Lane A) answers `AddDocument` and `RemoveDocument` from `CommandsIn` synchronously with a `CommandResult`, keeps each document in `OcuTalon.Data.Document` (`Ref`, `OwnerRef`: the session's `SessionRef` on the online demo, `instance` on a local install; `AddedBy`, `Name`, `ContentType` `markdown`, `text`, `pdf` or `docx`, `Size` in bytes, `AddedAt`, `State` `indexing`, `ready` or `failed`, `Reason` a code, `KnowledgeBase` the table, `Text` the stored text; Story 19.4 appends the passage-to-section map), indexes asynchronously (how is Story 19.4's) and is the single publisher of the `document` event. It accepts Markdown, plain text, PDF and Word (.docx), PDF and Word up to 10 MB (FR-54); a refused file gets a row in state `failed` with its reason code, so the list shows it. A chunk's `source` is the document's `Ref`. *Tables:* `OcuTalonKB.Docs` and `OcuTalonKB.Docs_Config` on a local install; `OcuTalonKB.S<id>` and `_Config` per online-demo session, `<id>` the session's `OcuTalon.Data.Session` row id (a SessionRef holds `-`, which an SQL identifier refuses); globals `^OcuTalonP.KB<suffix>` and `^OcuTalonP.KB<suffix>Config`, created by `OcuTalon.Docs` before AI Hub's `Build()`, whose `CREATE TABLE IF NOT EXISTS` then does nothing. *Event:* payload `OcuTalon.Live.Payload.Document`: `ref`, `name`, `addedAt`, `size`, `state`, `reason`, and `removed` true on a removed document's last event; to the owning session's stream on the online demo and the instance stream on a local install. *PDF and Word (Story 19.6):* `OcuTalon.Docs.Extract` runs `src/ocutalon/python/ocutalon_extract.py` (pdfplumber 0.11.10 for PDF, python-docx 1.1.2 for .docx) in its own `%SYSTEM.WorkMgr` category, `OcuTalon.Docs.Extractor` (one worker), never in `DocumentOps`' own process (S11's Python hazard); the categories are created by the area's install step through `Config.WorkQueues`.
- **S3.** *`MemoryOps`* (`OcuTalon.Memory.Ops`, Lane A) answers `SaveMemory` and `ForgetMemory` (from Epic 41 also `PinMemory`, `UnpinMemory`) from `CommandsIn`; reads go through `OcuTalon.Memory.Search(sessionRef, query, limit, *rows)` and `.List(sessionRef, *rows)`. *Tools:* `save_memory`, `search_memories`, `list_memories`, `forget_memory` (added to `OcuTalon.Tools.Names` by Story 19.3), and the documents tool `documents`. *Table:* `Ref`, `SessionRef`, `Text` (at most 2,000 characters), `SavedAt`, `ItemId` and `Origin` of the turn that saved it, `Embedding` `VECTOR(DOUBLE,384)`; Story 19.3 appends the HNSW (cosine) and `%iFind` indexes and checks where their globals land. *Ranking:* reciprocal-rank fusion, k = 60, over the 20 nearest by cosine and the 20 best keyword hits, equal weights, top 5, ties to the newer `SavedAt`; the HNSW check runs at 10,000 memories of one owner.
- **S4.** "A reply marks the passages and memories it used as Conventions 'Citations and memories' says."
- **S5.** Appended: "[AMENDED 2026-11-05, Story 34.1, Task 0, evidence `34-1-task0-fastembed-path.md`] Measured on a clean build 154 instance after an IPM install, outbound network blocked: with `FASTEMBED_CACHE_DIR` set to `<mgr>/fastembed/` inside a fresh IRIS job and inside a `%SYSTEM.WorkMgr` worker before first use, AI Hub's FastEmbed finds the model downloaded there at install and embeds offline; without the variable it does not find it. (One more sentence states step 10's result: whether the variable must be set before the job's first `%AI` call.) The implement stage writes this clause from the evidence's Verdict; on any other result Task 0's stop rule applies and S5 is not written. The download at install is an installer step of the Memory area (Story 19.2), made the same way. That the Python package reads the same folder through `cache_dir` is inference until Story 19.2 measures it."
- **S6.** "`TurnToolsClass` (step 3, Story 19.5; S14): base `OcuTalon.Bridge.Ext.TurnTools`, `ClassMethod Tools(ownerRef As %String, kind As %String, Output tools As %ListOfObjects) As %Status`, whose default returns an empty list; the setting `TurnToolsClass` on `Decide` (category Extensions), read through `Ext.Accessor.ClassFor` (its `BASES` gains the pair); OcuTalon's class `OcuTalon.Docs.TurnTools` returns the owner's knowledge base for a `turn` request, else nothing. Story 34.1 adds no code for it."
- **S7.** "The check finds the knowledge-base tables in the class dictionary (classes of schema `OcuTalonKB`) and confirms every global they use, index and extent globals included and whatever its prefix, resolves to the private database; memory and document globals are those of `OcuTalon.Data.Memory` and `.Document` (Story 34.1)."
- **S8.** "The check is rule `kb-ddl` of `docker/tests/test-class-rules.sh`: every product `CREATE TABLE` line carries `DEFAULTGLOBAL` and `^OcuTalonP.`, and only `OcuTalon.Docs` classes name `%AI.RAG.VectorStore.IRIS` (Story 34.1)."
- **S9.** Row "Citations and memories": Lane A's runner side puts on the bridge `Reply`'s `HostData`, beside `checks`, `citations` (one `{documentRef, document, section, passage, chunkIndex}` per distinct passage the turn's `documents` tool calls returned, in order, at most 5; Story 19.4) and `memories` (one `{memoryRef, text, savedAt}` per memory `search_memories` returned in the turn, at most 5; Story 19.3), built by code from tool results, never from model text, and absent when empty; `Conversation` (Lane B, Story 20.2) carries both onto the outbound reply and `chat.message` after the reply filter; the page shows passage text as plain text, at most 6 lines.
- **S10.** Row: `MemoryOps`, `DocumentOps` (from step 3; disabled stubs until Stories 19.3 and 19.4) | `OcuTalon.Memory.Ops`, `OcuTalon.Docs.Ops` | A.
- **S11.** "From step 3, Lane A owns `OcuTalon.Data.Memory` (written by `MemoryOps`) and `OcuTalon.Data.Document` (written by `DocumentOps`), created by Story 34.1, and the knowledge-base tables `OcuTalon.Docs` creates at run time (AD-21)."
- **S12.** Clause on 1330: "stubs that return OK and change nothing: Story 34.1". Rows (class or API | lane | built in): `OcuTalon.Memory.Search`, `.List` (AD-21), called by the memory tools | A | Story 19.3. `OcuTalon.Memory.Embedding` and category `OcuTalon.Memory.Embedder` (AD-21) | A | Story 19.2. `OcuTalon.Docs.Extract`, category `OcuTalon.Docs.Extractor`, `src/ocutalon/python/ocutalon_extract.py` (AD-21) | A | Story 19.6. `OcuTalon.Bridge.Ext.TurnTools`, setting `TurnToolsClass`, `OcuTalon.Docs.TurnTools` (AD-21, AD-31) | A | Story 19.5. `OcuTalon.Live.Payload.Document` (AD-12, AD-21), read by the web layer | A (its publisher, `DocumentOps`) | Story 34.2 (class and `Live.Publish` TYPES entry, S2's fields), Story 19.4. Reply `HostData.citations` and `.memories` (Conventions "Citations and memories") | A (built), B (carried by `Conversation`) | Stories 19.3, 19.4; Story 20.2. Lane B contracts fixed by Story 34.2, recorded by Story 34.1: `OcuTalon.Msg.Command.SaveMemory` (`Text`; origin `tool`), `.ForgetMemory` (`MemoryRef`; `tool`), `.AddDocument` (`Name`, `ContentType`, `Content` stream; `web_user`), `.RemoveDocument` (`DocumentRef`; `web_user`), routed by `CommandsIn` to `MemoryOps` and `DocumentOps` (AD-1); the documents REST routes, added to the REST table; the Dockerfile lines `fastembed==0.9.0` with AllMiniLM-L6-v2 baked into a root-owned, read-only folder named by `FASTEMBED_CACHE_DIR`, `pdfplumber==0.11.10` and `python-docx==1.1.2` through the existing `pip install --target` line, licence notices kept (AD-23); `SessionOps.End` calling both `DropSession` methods (AD-4) | B | Story 34.2.
- **S13.** Row: `document` | `DocumentOps` | A (Story 34.1 names it; Story 19.4 publishes).
- **S14.** `Session ||--o{ Document : "step 3"` and `%% Document added [ADDED 2026-11-05, Story 34.1]`.
- **S15.** 1540: "[AMENDED 2026-11-05, Story 34.1: step 3's memory ranking is fixed in AD-21; fading and consolidation stay for step 7]". 1545: "[AMENDED 2026-11-05, Story 34.1: the extraction's names are fixed in AD-21]".

## Verification

Lane prefix `P` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=34 stage=implement'`. Every IRIS line runs alone, in the foreground, `timeout: 600000`. Warm stack: `P OCUTALON_RUN_TAG=e34s1iw ci/warm.sh up` once; at the end, also after a failure, `P OCUTALON_RUN_TAG=e34s1iw ci/warm.sh down` and `P OCUTALON_RUN_TAG=e34s1i ci/iris.sh teardown`. Slot C (`ocutalon-slot-c`, OCUTALON) may be used for quick compiles with `server` and `namespace` named on every MCP call.

**Commands:**
- (once, first) Task 0's script with `P` and `OCUTALON_RUN_TAG=e34s1f OCUTALON_LIVE_DEADLINE=570` -- expected: verdict PASS and evidence written; then `P OCUTALON_RUN_TAG=e34s1f ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: only the 8 pre-existing `placeholder` findings; no `ad_id` or `ad_fields` finding.
- (loop) `bash docker/tests/test-storage.sh`; `bash docker/tests/test-class-rules.sh` (rule `kb-ddl` PASS); `bash docker/tests/test-boundaries.sh`; `bash docker/tests/test-ci-config.sh` -- one call each, expected PASS.
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e34s1iw ci/iris.sh class <C>` for each of `OcuTalon.Test.Contract.Step3`, `OcuTalon.Test.Contract.Ac`, `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Install.ProductionRules`, `OcuTalon.Test.Install.PrivateData`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Digest.Contracts` -- one per call, expected `CLASS ... passed`.
- (once) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e34s1iw ci/iris.sh shard lane-a --part 1/4` to `--part 4/4`, then `shard lane-b --part 1/2` and `--part 2/2`, one call each -- expected: every class passed.
- (once) `P OCUTALON_RUN_TAG=e34s1i ci/iris.sh live production`, then `P OCUTALON_RUN_TAG=e34s1i ci/iris.sh live install-start` -- expected: pass; new items disabled; `STEP PrivateData OK`.

**Planned mutations (Rule 19):** items: `MemoryOps` `Enabled="true"` -> `Test.Install.Production` red; tables: drop the `Memory` tsv row -> `test-storage.sh` red, `Document.Name` MAXLEN 255 -> 128 -> `Test.Contract.Step3` red, remove the `Document` row from `Tables` Registry -> `Test.Data.Tables` red; drop stubs: `Memory.DropSession` returns 5003 -> `Test.Contract.Step3` red, rename `Docs.DropSession`'s argument -> `Test.Contract.Ac` red; private data: restore `StorageGlobals`' `OcuTalon.`-only filter -> `Test.Install.PrivateData` (KB case) red; CI rule: a `CREATE TABLE OcuTalonKB.S1 (id VARCHAR(64))` code line in `Docs/Ops.cls` -> `test-class-rules.sh` red; spine: remove AD-21's `**Rule:**` line -> `lint_spine` red (`ad_fields`). The P6, spine-content and Task 0 ACs are document ACs, pinned by the reviewer's read against the checklists and the evidence. Record each as `mutation: <change> -> <test went red>`.

**Shared surfaces:** the production's item list (`Test.Install.Production` oracle, `live:production`); `src/short-names.tsv` (`test-storage.sh`); `Test.Data.Tables` `XData Registry`; `Test.Contract.Ac` signatures and floor; `PrivateData.StorageGlobals`' list (read by `Test.Install.PrivateData`, `Test.Digest.Contracts`, `Test.Data.Tables`; a leftover `OcuTalonKB.*` table on a stack changes it, so the new test drops its tables whatever the outcome); `test-class-rules.sh`'s rule list; the spine's ownership tables and Deferred rows. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Manual checks:**
- The spine and PRD diffs hold only S1-S15 and the FR-15 bullet, each with its marker; no removed line.
- No file under `Msg/`, `Core/`, `Web/`, `web/`, `Live/`, `docker/Dockerfile`, `ci/units.sh` or `EXPERIENCE.md` changed.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
