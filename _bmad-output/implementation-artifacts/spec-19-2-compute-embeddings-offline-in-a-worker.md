---
title: 'Compute embeddings offline in a worker'
type: 'feature'
created: '2026-11-05'
status: 'done'
baseline_revision: 'a9f6c0a47bb6248fb44545aa54c11a0c4b80cc0f'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/34-1-task0-fastembed-path.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized']
deferred:
  - 'release/rehearse.sh memory-offline: proved on stub hosts only (docker/tests/test-rehearsal.sh); a dry run on a real stack and the real rehearsal must show that the clean host publishes its web port again after docker network connect --alias iris (the sign-in step is the check)'
  - summary: >-
      No test calls OcuTalon.Memory.Embedding from inside an AI Hub callback, the S11 surface that the story exists for.
    evidence: |-
      The callback check (Test.Bridge.CodeRules:TestCallbackRule, with Memory.Embedding among CALLBACKHELPERS) proves only that the class holds no Python text; the unit tests call Embed and Submit from ordinary test sessions. Whether queueing and waiting on WorkMgr from inside a tool's callback avoids the build-154 crash is shown only when Story 19.3's Memory tools call Embed. Settle it with a live test (a tool call in a throwaway) that saves and searches a memory.
    location: >-
      src/ocutalon/cls/OcuTalon/Memory/Embedding.cls
    severity: medium
  - summary: >-
      docs/install-ipm.md does not say that an IPM install fetches fastembed through requirements.txt, downloads the model (about 97 MB) into the manager directory's fastembed/ folder, or what WARN Memory means.
    evidence: |-
      The page only gains STEP Memory OK lines in its sample output. The wording would be new public text, so it needs a PUBLIC TEXT proposal and a story that owns the page (Epic 11 or 15).
    location: >-
      docs/install-ipm.md
    severity: low
  - 'docs/install-ipm.md shows the IPM install output without a WARN Memory line and with STEP Memory OK 0.1s: Epic 11 should re-shoot the examples from a run with the staged requirements (release/ipm-install.sh output) when it next touches the page'
---

<intent-contract>

## Intent

**Problem:** Step 3's memory needs vectors computed on the instance, with no key and no internet, but nothing in OcuTalon embeds text yet: AI Hub's `FastEmbed.EmbedBatch` throws on build 154, and on build 154 a process that runs Python both inside and outside an AI Hub callback crashes (S11), so a tool cannot simply call Python.

**Approach:** Add `OcuTalon.Memory.Embedding`, an `%Embedding.Interface` class whose every call is computed by the Python `fastembed` 0.9.0 package in a `%SYSTEM.WorkMgr` worker of category `OcuTalon.Memory.Embedder`, from the model folder the image bakes (`FASTEMBED_CACHE_DIR`) or the one an IPM install downloads into `<mgr>/fastembed/`; add the Memory area's install step that creates the category, the `%Embedding.Config` row and the model folder; and prove it offline on a fresh Docker install with the network blocked.

## Boundaries & Constraints

**Always:**
- Python runs only in an `OcuTalon.Memory.Embedder` worker, never in the calling process; the calling classes (`OcuTalon.Memory.Embedding` and every tool, policy or renderer class) hold no Python method and no `%SYS.Python` / `$SYSTEM.Python` reference (AD-6, AD-21).
- The worker passes the model folder as the package's `cache_dir` and sets `FASTEMBED_CACHE_DIR` to the same folder inside the worker before the model's first use (AD-21). The folder is `OcuTalon.Memory.Embedder`'s one rule: the IRIS process's `FASTEMBED_CACHE_DIR` when set and non-empty (the image: `/opt/fastembed`), else `$SYSTEM.Util.ManagerDirectory()_"fastembed/"`.
- Vectors are AllMiniLM-L6-v2, 384 dimensions, `DOUBLE`, equal to AI Hub's FastEmbed vector for the same text (every component within 1e-6).
- The category allows at most 2 active workers (`MaxActiveWorkers` 2, `DefaultWorkers` 1); the model loads at most once per worker process.
- A failure (worker error, missing model, timeout) returns an error `%Status` / throws to the caller; it never crashes or hangs the caller (bounded wait).
- The install step never downloads when the model is already in the folder, so later starts and upgrades download nothing; on the image it never downloads at all.
- Every test added or changed creates and removes the state it asserts on (fixture rows, test tables, copied folders).

**Never:**
- No `[ Language = python ]` method and no own `.py` file in this story: the worker drives `fastembed` through `%SYS.Python` from ObjectScript.
- No change to `docker/Dockerfile`, `docker/after-start.cos` or any other Lane B file (U-177); no edit under `release/` without the ruling named in Design Notes.
- No second copy of the model, no `specific_model_path` workaround, and no network fallback in the embedder: if `cache_dir` cannot read the folder offline, Task 0's stop rule applies.
- No memory save, search, list or forget behaviour (Story 19.3), no knowledge-base table in product code (Story 19.4), no new user-facing text (a step warning carries the underlying error's own text).
- No new `AD-n` id (the lead's); spine edits are plain unions with `[AMENDED 2026-11-06, Story 19.2, ...]` markers.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Embed ASCII text | `Embedding("the Results partner's contact is Lee", <config>)` on the image | `%Vector` of 384 DOUBLE values, equal (1e-6) to AI Hub FastEmbed's vector for the same text | none |
| Embed non-ASCII / long text | a text with an accented Latin letter and a CJK character (authored as `$Char` escapes, Rule 14) and a text over 256 word pieces | 384 values each, equal (1e-6) to AI Hub's | none |
| Runs in a worker | any caller | the worker's `$JOB` differs from the caller's; the caller never imports Python | none |
| SQL consumer (Integration) | `SELECT EMBEDDING(?, 'OcuTalonMemory')` and an `%Library.Embedding` column (`MODEL` `OcuTalonMemory`) of a test fixture class | both return the same vector as `OcuTalon.Memory.Embedding.Embedding` for that text | none |
| Bad configuration | `IsValidConfig` with another model or dimension | returns 0 with an `errorMsg` | the `%Embedding.Config` trigger refuses the row |
| Worker fails | model folder missing or unreadable | error `%Status` / exception carrying the worker's error text; caller process keeps running | bounded wait, no retry loop |
| Step on the image | `FASTEMBED_CACHE_DIR=/opt/fastembed` holds the model | `STEP Memory OK`, category and config row present, nothing downloaded, no `WARN Memory` | none |
| Step, model present elsewhere | folder already holds `models--Qdrant--all-MiniLM-L6-v2-onnx` | OK, no download (proved offline in `live:memory-offline`) | none |
| Step, model missing, download possible | IPM install with network, `fastembed` installed | the model is downloaded once into `<mgr>/fastembed/` with the Dockerfile's `snapshot_download` call, in a worker; OK | none |
| Step, model missing, download impossible | no network, or `fastembed` / `huggingface_hub` not installed (today's FR-57 image) | `STEP Memory OK` followed by one `WARN Memory <underlying error text>`; the install completes; a later install retries | never `FAILED` for the download |
| Step run twice | upgrade or restart | category and config row updated to the declared values, idempotent | none |
| Offline first use (AC3) | fresh Docker install, all networks of the iris container disconnected after ready | embed works; an `OcuTalon.Data.Memory` fixture row stored with its embedding is the top hit of a `VECTOR_COSINE` query for a paraphrase; AI Hub's FastEmbed embeds a document chunk into a test vector-store table from the same baked folder | the unit fails if any outbound connection succeeds |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/Memory.cls:29` -- `Embedding As %Library.Vector(DATATYPE = "DOUBLE", LEN = 384)`; `DEFAULTGLOBAL "^OcuTalonP.Memory"`; indexes `RefIndex`, `SessionRefSavedAtIndex` (no HNSW yet, Story 19.3). Read-only here; the offline test writes and deletes one fixture row.
- `src/ocutalon/cls/OcuTalon/Memory.cls`, `Memory/Ops.cls` -- Story 34.1 stubs (`DropSession`, `STUB = 1`); untouched.
- `irislib/%Embedding/Interface.cls:10,15` -- `ClassMethod Embedding(input, configuration) As %Vector`, `ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean`.
- `irislib/%Embedding/Config.cls:27-64` -- row trigger checks the class and `IsValidConfig`; `VectorLength` must be set (384) for any class but SentenceTransformers; rows live in `^rINDEXSQL("Embedding")`.
- `irislib/%Library/Embedding.cls:24-35` -- column type: `MODEL` (config name), `SOURCE`; calls the class's `Embedding`.
- `irislib/%Embedding/SentenceTransformers.cls:45-107` -- sibling over Python (config parsing, per-process model cache keyed by model and folder); mirror its config/validation shape, not its `[Language = python]` method.
- `irislib/%AI/RAG/Embedding/FastEmbed.cls:20-54` -- AI Hub's FastEmbed is the Rust bridge (`MODELNAME "AllMiniLML6V2"`, 384); `EmbedBatch` throws; it reads only `FASTEMBED_CACHE_DIR`. Its vectors are obtained through `%AI.RAG.VectorStore.IRIS`, as 34.1's Task 0 step 5 did.
- `irislib/%SYSTEM/WorkMgr.cls:48,57-59,243` -- `%New(qstruct, numberjobs, category)`, `Queue`, `WaitOne(timeout, .sc, .args, .result)`; workers persist per category until the idle timeout. `irissys/Config/WorkQueues.cls` -- `Create`/`Exists`/`Modify` (in `%SYS`), `MaxActiveWorkers`, `DefaultWorkers`, `Timeout`.
- `_bmad-output/implementation-artifacts/evidence/34-1-task0-fastembed-path.md` -- the measured recipe: `F = $SYSTEM.Util.ManagerDirectory()_"fastembed/"`, `os.putenv` before `FastEmbed.Create()`, the worker probe (step 9), the network block by `docker network disconnect` (step 6).
- `docker/Dockerfile:20-30,49` (Lane B, read-only) -- the pip line into `/usr/irissys/mgr/python`, the `snapshot_download('Qdrant/all-MiniLM-L6-v2-onnx', cache_dir='/opt/fastembed', allow_patterns=[...])` call to reuse verbatim in the step's download, root-owned 444/555, `ENV FASTEMBED_CACHE_DIR=/opt/fastembed`.
- `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsImage.cls:23-26` -- the off-image skip (`/opt/ocutalon/version` absent) to reuse in the Memory tests (slots have no `fastembed`).
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls:12-15` -- `Order()`; `Run`, `RunStep`, `Ipm` (`:83-101`, runs the steps on an IPM install); `src/ocutalon/cls/OcuTalon/Install/Step.cls` -- base (`Run`, `Warn`); sibling steps `Install/Step/PrivateData.cls` (has `Run`), `Install/Step/Demo.cls:198` (`ManagerDirectory()` use).
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:123-130` -- `TestOrder` pins the list and the count 15.
- `docker/tests/lib-live.sh:678-683` -- `expected_run`, the exact STEP list every live install check diffs; `docker/tests/test-install-upgrade.sh:215` -- regex of the steps that must not run after `STEP SSL FAILED`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls:82,115,196-242,1131-1161` -- the callback check: `CALLBACKHELPERS`, `PYTHON` pattern (`language\s*=\s*python|%sys\.python|\$system\.python`), `TestCallbackRule`, `IsCallbackClass`/`CallbackProblem`. Already flags Python in tool, policy and renderer classes and in the listed helpers.
- `ci/units.sh:20` (lane-a areas), `:89` (`shards-4` units); `docker/tests/test-ci-config.sh:717-762` enforces every `Test/<Area>/` in one shard and every `test-*.sh` in one place.
- `ci/iris.sh:169` -- the `%UnitTest.Manager` call a live script can reuse to run a class in its own stack; `docker/tests/test-security-overview.sh` -- sibling single-stack live unit (`live_start`, `dc`, `iris_script`, EXIT trap).
- `module.xml` (root, SourcesRoot `src`) -- what the release `ipm` step packs (`release/release.sh:758,774-830`, `--network none`); `src/module.xml` -- what the image's after-start and the FR-57 job load. IPM 0.10.10 runs `pip install -t <mgr>/python -r requirements.txt --only-binary=:all:` from the loaded module's root on every install/load/update unless `-bypass-py-deps` (decoded `%IPM.Lifecycle.Base` `InstallOrDownloadPythonRequirements`).
- `release/ipm-install.sh` + `release/ipm/Dockerfile` (lane-a.yml job `ipm-install`, x64) -- FR-57's IPM install; its image has no `fastembed`; it reads `Registry.Order()` dynamically and its `:827` sed edits only the tail `"PrivateData", "Ready")`.
- `release/rehearse.sh:156,1169` -- `REH_ROWS`, the install phase's step loop.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first; product default 5) -- on one fresh lane-C throwaway built from this worktree (`OCUTALON_RUN_TAG=e19s2i0`, the lane's variables, `OCUTALON_LOCK_OWNER='epic=19 stage=implement'`), after the install reaches ready: with the network up, copy `/opt/fastembed` into a folder under `<mgr>` and also run the Dockerfile's `snapshot_download` call into `<mgr>/fastembed/` in a worker; then `docker network disconnect` every network of the iris container and confirm a name lookup fails; then measure, each in an `OcuTalon.Memory.Embedder`-style worker: M1 Python `fastembed` 0.9.0 with `cache_dir=/opt/fastembed` (read-only) and `FASTEMBED_CACHE_DIR` set loads offline and returns 384 values (record the model name that resolves to the folder `models--Qdrant--all-MiniLM-L6-v2-onnx`, whether anything is written into the folder, whether `HF_HUB_OFFLINE=1` is needed, the time to the first vector, the worker's memory); M2 the max component difference against AI Hub's FastEmbed for the three matrix texts; M3 M1 again with `cache_dir=<mgr>/fastembed/` as the download made it, and AI Hub's FastEmbed reading it in a worker with the variable set. Tear down with `ci/iris.sh teardown`. Record in `_bmad-output/implementation-artifacts/evidence/19-2-task0-fastembed-cache-dir.md`. **Stop rule:** if M1 or M3 fails offline, or M2 exceeds 1e-6, stop the story and HALT `blocked` / `intent gap` naming AD-21 ("Memory vectors" and "The FastEmbed model") with the measurement and a recommended amendment; no workaround.
- `src/ocutalon/cls/OcuTalon/Memory/Embedder.cls` (new) -- the worker side: `ModelFolder()` (the folder rule above), the worker entry that sets `FASTEMBED_CACHE_DIR`, loads the model once per process (`cache_dir` = the folder) and returns the vector, and the download entry used by the step; the only class of the area that references `%SYS.Python`.
- `src/ocutalon/cls/OcuTalon/Memory/Embedding.cls` (new) -- `Extends %Embedding.Interface`: `Embedding(input, configuration)` queues one work item to category `OcuTalon.Memory.Embedder`, waits with a bounded timeout and returns the `%Vector`; `IsValidConfig` accepts only AllMiniLM-L6-v2 / 384; no Python reference.
- `src/ocutalon/cls/OcuTalon/Install/Step/Memory.cls` (new) -- `Run()`: create or modify the `Config.WorkQueues` category (in `%SYS`, `MaxActiveWorkers` 2, `DefaultWorkers` 1); upsert the `%Embedding.Config` row `OcuTalonMemory` (class `OcuTalon.Memory.Embedding`, `VectorLength` 384); ensure the model folder (present: nothing; missing: download in a worker; download impossible: `Warn` with the underlying error text, return OK). A folder argument lets tests point it at a temporary folder.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls` -- add `"Memory"` to `Order()` between `"Telegram"` and `"Production"` (the category must exist before Story 19.3's `MemoryOps` starts); footprint extension.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls` -- `TestOrder`: the new list and count 16 (shared surface).
- `docker/tests/lib-live.sh` -- `expected_run`: `'STEP Memory OK'` after `'STEP Telegram OK'`; `docker/tests/test-install-upgrade.sh:215` -- `Memory` in the regex (shared-surface pins; footprint extensions).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- append `OcuTalon.Memory.Embedding` to `CALLBACKHELPERS` (one-name append to a contended file, Epic 17), so the existing callback check proves the class a tool will call holds no Python; extend its doc comment's helper list in one clause.
- `src/ocutalon/cls/OcuTalon/Test/Memory/Embedding.cls` (new) -- dimensions, identity with AI Hub (three matrix texts), runs in a worker (`$JOB`), `EMBEDDING()` SQL and an `%Library.Embedding` column of a test fixture class, `IsValidConfig`, worker failure returns an error; skips off-image.
- `src/ocutalon/cls/OcuTalon/Test/Memory/Install.cls` (new) -- the step: category and config row after `Run()`, twice idempotent; `ModelFolder()`; present folder -> no download; missing folder with download impossible -> one `Warn`, OK.
- `src/ocutalon/cls/OcuTalon/Test/Memory/Offline.cls` (new) -- store and recall: one `Data.Memory` fixture row with its embedding is the top `VECTOR_COSINE` hit for a paraphrase (row deleted after); AI Hub's FastEmbed embeds a chunk into a test vector-store table (`DEFAULTGLOBAL` under `^OcuTalonP.`, dropped after) from the baked folder, and from a temporary copy under `<mgr>` in a worker with the variable set; identity again; skips off-image.
- `docker/tests/test-memory-offline.sh` (new) -- live unit: one fresh throwaway, wait ready, disconnect every network of the iris container, prove an outbound lookup fails, run `OcuTalon.Test.Memory.Offline` and `OcuTalon.Install.Step.Memory` `Run()` (expect OK and no `WARN Memory`) in the stack, print `MEMORY-OFFLINE engine=<uname -m> ok=<0|1>`; EXIT trap tears down.
- `ci/units.sh` -- append `Memory` to lane-a's areas (runs in `shard:lane-a@rest`) and `live:memory-offline` to `shards-4` (one-name appends; contended with Epic 39).
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-21: replace "That the Python package reads the same folder through `cache_dir` is inference until Story 19.2 measures it." with Task 0's measured result, and add the names (`OcuTalon.Memory.Embedder` class and `ModelFolder()` rule, config row `OcuTalonMemory`, step `Memory`, 2 workers); keep the x64 sentence, naming `live:memory-offline` in `iris (shards-4)` as where it is measured; AD-23: `Memory` between `Telegram` and `Production` in the step list. Lint after.
- Ruling-gated (do only if the lead's ruling arrives; the rest never depends on it) -- root `requirements.txt` (`fastembed==0.9.0`), `release/release.sh` (`-bypass-py-deps` on the `ipm` step's offline `zpm load`), `release/ipm/Dockerfile` + `release/ipm-install.sh` (stage `requirements.txt`, check the pip install, `STEP Memory` with no `WARN Memory`, the model once in `<mgr>/fastembed/`, nothing new after a reinstall), `release/rehearse.sh` (`memory-offline` step and row); see Design Notes.

**Acceptance Criteria:**
- Given the image with Story 34.2's Dockerfile lines, when OcuTalon embeds text, then `OcuTalon.Memory.Embedding` returns 384-dimension vectors from Python `fastembed`, equal to AI Hub's AllMiniLM-L6-v2 vectors for the same text (1e-6), and `EMBEDDING()` and an embedding column return the same vector.
- Given any caller, when it needs a vector, then the work runs in a worker of category `OcuTalon.Memory.Embedder` (at most 2 active), never in the calling process, and `OcuTalon.Test.Bridge.CodeRules:TestCallbackRule` (with `OcuTalon.Memory.Embedding` among its helpers) finds no Python method or `%SYS.Python` reference in a tool, policy, renderer or helper class.
- Given a fresh Docker install with every network of the iris container disconnected, when a memory row is stored with its vector and recalled, and a document chunk is embedded by AI Hub's FastEmbed, then both work from the baked model, and `live:memory-offline` passes in CI's `iris (shards-4)` job on x64 with `MEMORY-OFFLINE engine=x86_64 ok=1`.
- Given the Memory area's install step, when it runs on an install whose model folder holds the model, then it downloads nothing and warns nothing, on a start and on an upgrade alike; when the model is missing and a download is possible it downloads it once into `<mgr>/fastembed/`; and the worker passes that folder as `cache_dir` and sets `FASTEMBED_CACHE_DIR` inside itself before first use.
- Given the IPM package (ruling-gated part), when it is installed, then it declares `fastembed==0.9.0` through `requirements.txt` and the FR-57 job shows the install and a single model download.

## Spec Change Log

- 2026-11-06 (lead, before implement): the orchestrator's rulings recorded under Design Notes "Rulings" (U-294 release tooling allowed as a separate task; `shards-4` confirmed). The ruling-gated task is now in scope.

## Review Triage Log

### 2026-11-06 - Review pass
- verdicts: 37 findings - high 0, medium 12, low 18, false 7, maybe-false 0 (rows marked carried repeat an earlier row's verdict and route)
- findings:
  - `[false]` `[reject]` BH: requirements.txt is never checked in the real package -- IPM 0.10.10's `%IPM.Lifecycle.Base:%Export` (read from the loaded class in a throwaway) lists "requirements.txt" among the root files it packs, so the artifact carries it
  - `[false]` `[reject]` BH: `-bypass-py-deps` is not shown to exist in the bundled IPM -- the loaded `InstallOrDownloadPythonRequirements` reads `pParams("BypassPyDeps")` and logs "because -bypass-py-deps is set"
  - `[medium]` `[patch]` BH: HasModel treats a partial download as a model -- SNAPSHOTFILES now names all five files (the baked folder holds all five); TestHasModel red under the old list
  - `[low]` `[patch]` BH: the telemetry opt-out in Download is set after the import -- the variable is set before `huggingface_hub` is imported; the comment says so
  - `[false]` `[reject]` BH: FASTEMBED_CACHE_DIR handling in Embed is redundant -- the spec requires the set (AD-21), and measured: without `cache_dir` the package ignores the variable, so it serves AI Hub's FastEmbed in the same worker
  - `[medium]` `[defer]` BH: several paths have no test -- the callback surface goes to `deferred:` (Story 19.3's tool path); the Submit timeout branch is rejected as low (WaitOne is the platform's bounded wait, no seam without product surface); the Download success path is pinned by `release/ipm-install.sh` check 30 (mutation recorded)
  - `[low]` `[patch]` BH: Submit reports a timeout as "returned no result" and claims a release it does not make -- the message says "did not finish within N seconds" and the unbacked claim is removed
  - `[low]` `[defer]` BH: docs/install-ipm.md lacks the new install behaviour -- new public text needs a PUBLIC TEXT proposal and an owner story; in `deferred:`
  - `[low]` `[reject]` BH: the step can block an install for up to ten minutes -- wontfix-theoretical: the Hugging Face client's own connect and read timeouts end a stalled download, and no hang was shown
  - `[low]` `[patch]` BH: the spine row says Embed returns the vector as a status -- the row states the signatures exactly
  - `[medium]` `[patch]` EH: HasModel partial snapshot -- carried, same root cause as the BH row
  - `[low]` `[reject]` EH: `$VOP fromstring` on nan or inf -- wontfix-theoretical: no model output of AllMiniLM-L6-v2 is nan or inf in any measured run
  - `[low]` `[reject]` EH: non-dynamic object or empty input to Embedding -- not reachable from EMBEDDING() or an embedding column, which pass text; an empty text embeds as a valid vector
  - `[medium]` `[patch]` EH: the network-cut probes have no positive control -- test-memory-offline.sh runs `python3 -c "import socket"` after the cut and fails if it does not run; rehearse.sh prints MEMOFF-NO-PROBE and fails the step; test-rehearsal.sh has a stub for it
  - `[low]` `[reject]` EH: an SSH drop in the rehearsal leaves the networks cut -- reopen_if the rehearsal host is found with the iris container disconnected; the next step (sign-in) fails visibly and `docker network connect` is the repair
  - `[medium]` `[patch]` EH: HubWorker leaves FASTEMBED_CACHE_DIR in a reused worker -- the work item puts the variable back before it returns
  - `[false]` `[reject]` EH: install and runtime may disagree on the model folder -- every IRIS process of an instance inherits the container's environment, and the rule reads the same variable in both
  - `[false]` `[reject]` EH: `-bypass-py-deps` against the pinned IPM -- carried, see the BH row
  - `[low]` `[reject]` EH: MaxActiveWorkers is a target, not a hard cap -- the spec names MaxActiveWorkers 2 as the limit (by-design)
  - `[low]` `[reject]` EH: IsValidConfig accepts a config with no dimensions -- the matrix requires refusing another model or dimension, which it does; recorded under Decided in-stage
  - `[medium]` `[patch]` VG: AC2 is pinned at Submit, not at Embedding.Embed -- Embed returns the worker's job; TestRunsInAWorker calls Embed; mutation red
  - `[medium]` `[patch]` VG: nothing observes the category of the worker -- WorkerInCategory reads ^IRIS.WorkQueue; default-category mutation red
  - `[medium]` `[patch]` VG: no test embeds from a folder other than the process's variable -- TestFolderArgument (a copy under a per-process name); two mutations red
  - `[medium]` `[patch]` VG: TestHubFromACopyInAWorker leaks the variable and has no control -- the leak is closed (EH row); the empty-folder control is rejected: on a stack with a network AI Hub's FastEmbed would download into the empty folder, and on the offline unit the copy test is the control
  - `[low]` `[reject]` VG: the Submit timeout and bounded-wait paths have no test -- needs a slow work item, which is product surface for a test; reopen_if a caller is seen waiting past its timeout
  - `[medium]` `[patch]` VG: the offline network cut has no positive control -- carried, patched under the EH row
  - `[low]` `[patch]` VG: AC4 and AC5 mutation lines -- written (AC4 folder, variable and snapshot; AC5 demonstrated on `release/ipm-install.sh a`)
  - `[medium]` `[defer]` VG other: no test calls Embed from an AI Hub callback -- carried, in `deferred:`
  - `[low]` `[carried]` VG other: the "released" comment on Submit -- carried, patched under the BH row
  - `[low]` `[reject]` VG other: TestModelFolderRule's first assertion restates the rule -- the PATH and unset-variable assertions do the discriminating work
  - `[low]` `[reject]` VG other: test-rehearsal asserts only the generic prefix -- each stub kind has its own guard in step_memoryoffline and the row text is pinned by the record
  - `[false]` `[reject]` VG other: Memory tests skip off the image -- the spec says so; the live unit and CI run on the image with no skip
  - `[medium]` `[defer]` IA: the callback surface is not exercised -- carried, in `deferred:`
  - `[low]` `[reject]` IA: the scan covers Memory.Embedding only -- by design: the spec names Embedding as the helper and Embedder as the one class that may hold Python
  - `[low]` `[reject]` IA: store and recall bypass the tool path -- by design, recorded under Decided in-stage (Story 19.3 adds the tool path)
  - `[low]` `[reject]` IA: load-once and the 2-worker cap are not asserted against real workers -- Task 0 measured load-once on the shipped worker shape; the category row is asserted by Test.Memory.Install and the category of the worker by TestRunsInAWorker
  - `[false]` `[reject]` IA: edits beyond the Memory area -- the release tooling is ruled U-294; the other files are the spec's named pins; docs/install-ipm.md is reported as a contended file

## Design Notes

**Architecture decisions:** AD-6 (Python only in a WorkMgr worker; the callback check), AD-21 (Memory vectors; The FastEmbed model), AD-22 (tests in `OcuTalon.Test.<Area>`, live units in throwaways, CI units), AD-23 (image pins, after-start and IPM install run the same step order; IPM `Registry.Ipm`), AD-29 (Lane A files; `release/` is Lane A's but gated by the dispatch), AD-31 (no bridge change: the embedder is host code), AD-33 (no new item, table or event; `Data.Memory` stays MemoryOps' from Story 19.3). Conventions: "Python" row (no `[Language = python]`; no own `.py` needed here), Stack rows "Embedding model" and "fastembed 0.9.0".

**Integration ACs:** the SQL consumer row of the matrix (`EMBEDDING()` and an `%Library.Embedding` column read from this class on a real instance). First product consumer: Story 19.3.

**Consumed-by:** 19.3 -- `MemoryOps` embeds a saved memory and `Memory.Search` embeds the query through `OcuTalon.Memory.Embedding` from inside a tool's callback; its offline store and recall can run in `live:memory-offline`. 19.4 -- `DocumentOps` sets `FASTEMBED_CACHE_DIR` from `OcuTalon.Memory.Embedder.ModelFolder()` in its own job before AI Hub's `FastEmbed.Create()`. 19.6 -- the `Config.WorkQueues` category pattern of `Install.Step.Memory` for `OcuTalon.Docs.Extractor`.

**Consumes:** Story 34.1 (`OcuTalon.Data.Memory`, the names, the measured path), Story 34.2 (`fastembed==0.9.0` and `/opt/fastembed` in the image), Epic 15 (`Registry.Ipm`, the FR-57 job).

**Extend, don't copy:** `OcuTalon.Memory.Embedding` extends `%Embedding.Interface` and follows `%Embedding.SentenceTransformers`' config shape; `Install.Step.Memory` extends `OcuTalon.Install.Step` like `PrivateData`; the callback check is extended (one helper name), not duplicated; `test-memory-offline.sh` reuses `lib-live.sh` and the shape of `test-security-overview.sh`, and runs its class with `ci/iris.sh`'s `%UnitTest.Manager` call.

**Decided in-stage:**
- AC3's "a memory is stored and recalled" is met at this story's layer (a `Data.Memory` fixture row and a cosine query), because save and recall are Story 19.3's; 19.3 adds its tool path to the same unit.
- The worker drives `fastembed` from ObjectScript through `%SYS.Python`; no own `.py` resource until Story 19.6.
- "Identical" is every component within 1e-6 (Task 0 records the real maximum).
- Workers: `MaxActiveWorkers` 2, `DefaultWorkers` 1. Config row name `OcuTalonMemory`. Step position before `Production`.
- The step's download is the Dockerfile's own `snapshot_download` call into `<mgr>/fastembed/`, run in a worker; a download that cannot run is a `Warn` with the underlying error's text, never `FAILED`, so today's FR-57 job (no `fastembed`) stays green and a later install retries.
- `docker/tests/lib-live.sh` and `test-install-upgrade.sh` get only the step-order pin (Rule 19), reported as footprint extensions; `Install/Registry.cls` likewise.
- `live:memory-offline` joins `shards-4`, the group with the most room (about 1,410 s plus about 300 s).
- (Implement) The worker passes the model folder with a one-line `eval` of a `lambda` (with an explicit globals dict), because `%SYS.Python` from ObjectScript passes no keyword argument on build 154 (a `kw(...)...` argument is ignored: measured on the slot) and `TextEmbedding(..., cache_dir=...)` and `snapshot_download(..., cache_dir=..., allow_patterns=...)` need keywords. It is the only Python source text in the story, inside `OcuTalon.Memory.Embedder`, which is not a callback class; there is still no `[ Language = python ]` method and no `.py` file.
- (Implement) The worker also passes `local_files_only=True` to `TextEmbedding` (Task 0: a missing model then fails at once instead of after 39 s of download tries), and `Embedder.Embed` returns an error status ("holds no models--Qdrant--...") before any Python when `HasModel(folder)` is false, which keeps a missing folder from being made by the package.
- (Implement) `Embedder.ModelFolder(variable)` takes the variable's name with `FASTEMBED_CACHE_DIR` as its default, and `Install.Step.Memory.EnsureModel(folder)` returns 1 when it attempted a download: both are seams for the tests (a process cannot set its own environment variable here, and an offline unit cannot see a download that falls back to the local cache).
- (Implement) `live:memory-offline` also asserts that the manager directory holds no `fastembed` folder after the first start. Without it the spec's AC3 mutation would not be caught: with a network at the first start a step that looks in `<mgr>/fastembed/` downloads the model there, and the offline embeds then pass from that copy.
- (Implement, review) `Embedding.Embed` has a third output, the worker's `$JOB`, so that the pinning test observes the routing through the public entry point; `Embedder.Embed` also returns the worker's `FASTEMBED_CACHE_DIR` as `%result("variable")`; `HasModel` needs the five files that a download fetches (the baked folder holds all five); the tests read the worker's category from `^IRIS.WorkQueue("Worker", ...)` (a test-only reliance on WorkMgr's own global).
- (Implement) `IsValidConfig` accepts `{"modelName": "sentence-transformers/all-MiniLM-L6-v2"}` with `dimensions` optional (384 when given); its `errorMsg` texts ("'modelName' must be ...", "'dimensions' must be 384") are developer-facing configuration errors, not product text.
- (Implement) `Embedding.Embed(text, .vector)` returns the vector as a status for callers that prefer no exception (Story 19.3's tools); `Embedding(input, configuration)` is the `%Embedding.Interface` method and throws.
- (Implement) A test never removes what the install made: `Test.Memory.Fixture.Prepare` makes the category and the row only when absent and `Restore` removes only those; `Test.Memory.Install` saves the category's values and the row's fields and puts them back. The embedding-column test builds its fixture class at run time (`OcuTalon.Test.Memory.ZzEmbedded`, removed after), because a `%Library.Embedding` property reads its `MODEL` row at compile time and a class compiled at install would fail before the Memory step has made the row.
- (Implement) The test tables are named with short suffixes (`^OcuTalonP.KBZzMid`, `KBZzMoff`, `KBZzMcopy`): the extent manager adds `.1.P1` to a DEFAULTGLOBAL and a global name over 31 characters is refused.
- (Implement, U-294 task) `release/ipm/Dockerfile` is unchanged: its build context is allow-listed by `.dockerignore` and `docker/tests/test-compose-file.sh` pins that list, so `release/ipm-install.sh` stages the root `requirements.txt` into the container (`stage_requirements`, as root, mode 444, beside `src/module.xml`) after each stack start instead of copying it at build. The checks are 30 and 31 of that script. `release/rehearse.sh` gets the `memory-offline` step between `install` and `sign-in` (row `memory-offline` in `REH_ROWS`); the later phases' guards still test the four original rows, because a failed `memory-offline` makes `sign-in` not run and so fail the guard.
- (Implement) `docs/install-ipm.md` (Epic 11's file) gets one line, `STEP Memory OK 0.1s`, after `STEP Telegram OK` in each of its two Configure examples, because `docker/tests/test-cpf.sh` rule 9 requires every name of `Registry.Order()` in order in each block; it is a pin of the step order, listed with the other pins.

**Needs a ruling:**
- release/release.sh -- the IPM `requirements.txt` that declares `fastembed==0.9.0` must sit at the root (the published module's root); the `ipm` step's `zpm load` of the root runs with `--network none`, so pip would fail there: add `-bypass-py-deps` to that load (and its pin in `docker/tests/test-release-sequence.sh`). The root file lands only with this ruling.
- release/ipm/Dockerfile and release/ipm-install.sh -- stage `requirements.txt` beside `src/module.xml` and check the pip install, the single model download and no re-download on a reinstall; cost: pip fetches about 200 MB per install path inside the 35-minute job.
- release/rehearse.sh -- a `memory-offline` step after `install` (disconnect the clean host's iris container, run `OcuTalon.Test.Memory.Offline` through the `exec` channel, reconnect before `sign-in`) and its `REH_ROWS` row, with `docker/tests/test-rehearsal.sh`'s dry-run pin.
- CI group size -- the project block bars a group over 1,000 s, and every group is already over it (`shards-4` about 1,410 s); the plan uses `shards-4`.

**Rulings (orchestrator, 2026-11-06):**
- U-294 (veto; the owner or the Planner may reverse it before the epic merges): the release tooling above is ALLOWED as Epic 19 footprint work -- the root `requirements.txt` (`fastembed==0.9.0`); `-bypass-py-deps` on `release/release.sh`'s offline `zpm load` and its pin in `docker/tests/test-release-sequence.sh`; `release/ipm/Dockerfile` and `release/ipm-install.sh` staging `requirements.txt` and checking the single model download; the `memory-offline` step in `release/rehearse.sh` and its `docker/tests/test-rehearsal.sh` pin. Keep it a SEPARATE task, done after the rest, so a reversal drops it cleanly; the rest of the story never depends on it.
- CI group: `live:memory-offline` (about 300 s) joins `shards-4`. The project rule is: a UNIT over 1,000 s on a clean run is split, and a GROUP only above 35 minutes on two clean runs; `shards-4` is about 1,410 s clean, about 1,710 s with the unit. The project block's "never a group over 1,000 s" line is superseded by this ruling.
- Contention checked at 2026-11-06T05:00Z: Epic 39 changes only the `CHECK_SCRIPTS` line of `ci/units.sh`, Epic 17 neither file; `docker/tests/lib-live.sh` is untouched by both. The one-name appends stand.

**Declined DW-732:** the folder is owned by `irisowner`, the IRIS instance's own OS user, which already writes the durable code database and `<mgr>`, and it sits in the image layer, reset on every container recreate, so tightening it adds no boundary; the change would also be `docker/Dockerfile` (Lane B, U-177). Reopen if the IRIS process ever runs as a user other than the folder's owner.

## Verification

Lane variables on every `ci/iris.sh` / `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=implement'`; every call in the foreground with `timeout: 600000`. Warm stack: `OCUTALON_RUN_TAG=e19s2iw ci/warm.sh up` once, `ci/warm.sh down` at the end.

**Commands:**
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s2iw ci/iris.sh class OcuTalon.Test.Memory.Embedding` (loop) -- expected: CLASS passed, no SKIP.
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s2iw ci/iris.sh class OcuTalon.Test.Memory.Install` (loop) -- expected: passed.
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s2iw ci/iris.sh class OcuTalon.Test.Memory.Offline` (loop) -- expected: passed.
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s2iw ci/iris.sh class OcuTalon.Test.Bridge.CodeRules` (loop) -- expected: passed.
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s2iw ci/iris.sh class OcuTalon.Test.Install.Registry` (loop) -- expected: passed.
- `OCUTALON_RUN_TAG=e19s2i ci/iris.sh live memory-offline` (loop; destructive: a fresh throwaway with its network cut) -- expected: every PASS, `MEMORY-OFFLINE engine=aarch64 ok=1`; then `OCUTALON_RUN_TAG=e19s2i ci/iris.sh teardown`.
- `bash docker/tests/test-ci-config.sh` (loop) -- expected: PASS units.
- `OCUTALON_RUN_TAG=e19s2i ci/iris.sh live install-start` (once; install, throwaway) -- expected: PASS, the log lists `STEP Memory OK`.
- `OCUTALON_RUN_TAG=e19s2i ci/iris.sh live install-upgrade` (once; upgrade, throwaway) -- expected: PASS.
- `bash release/ipm-install.sh a` with the lane variables and `OCUTALON_RUN_TAG=e19s2i` (once; IPM install, throwaway; with the U-294 task) -- expected: PASS (about 5 minutes), including check 30: `STEP Memory OK` with no `WARN Memory`, `fastembed` 0.9.0 installed by IPM from the staged `requirements.txt`, the model once in `<mgr>/fastembed/`. Mode `b` (about 11 minutes: the harness moves it to the background, poll its output file) adds check 31: the next-version reinstall leaves `<mgr>/fastembed/` unchanged. Without the U-294 task the same run would show one `WARN Memory` (no `fastembed` on that image).
- `OCUTALON_RUN_TAG=e19s2i ci/iris.sh shard lane-a --part k/4` for k = 1..4, one per call (once) -- expected: every class passed.
- `OCUTALON_RUN_TAG=e19s2i ci/iris.sh shard lane-b --part k/2` for k = 1..2, one per call (once) -- expected: every class passed.
- `bash docker/tests/test-lib-live.sh`, `bash docker/tests/test-ci-changes.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, one per call (once) -- expected: PASS.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once, after the spine edit) -- expected: no new finding.
- CI: `iris (shards-4)` prints `MEMORY-OFFLINE engine=x86_64 ok=1` (the x64 result of AD-21); `iris (shards-2)` runs `OcuTalon.Test.Memory.*`; lane-a `ipm-install` stays green.

**Shared surfaces:** the installer step order (`Install.Registry.Order`, pinned by `Test.Install.Registry:TestOrder`, `lib-live.sh` `expected_run`, `test-install-upgrade.sh:215`; `release/ipm-install.sh` reads it dynamically); `ci/units.sh` lane-a areas and `shards-4` units (`test-ci-config.sh`); `CALLBACKHELPERS` of `Test.Bridge.CodeRules`; the `Config.WorkQueues` categories and `%Embedding.Config` rows (no test counts them). Every test added or changed passes on a fresh environment, in either order.

**Mutations (one per AC, recorded with the result by the implement stage; each was applied, observed red, reverted from a backup, and the tree confirmed byte-identical, 2026-11-06):**
- AC1: `mutation:` perturb the first component of the vector in `Embedding.Embed` by 1e-3 -> `Test.Memory.Embedding` red: `TestIdentityWithAiHub` fails for all three chunks (distances .00099999, .00100001 and .00100004 against the 1e-6 limit) and `TestSqlConsumers` fails; green again after the revert.
- AC2: `mutation:` call `Embedder.Embed` inline in `Memory.Embedding:Embed` instead of queueing it with `Submit` -> `Test.Memory.Embedding:TestRunsInAWorker` red ("which is not the calling process" and "is a worker of the category"); `mutation:` make `Embedder.Submit` use the default category (`$SYSTEM.WorkMgr.%New("", 1)`) -> `TestRunsInAWorker` red ("is a worker of the category OcuTalon.Memory.Embedder", read from `^IRIS.WorkQueue("Worker", ...)`); and `mutation:` add `##class(%SYS.Python).Import("fastembed")` to `Memory.Embedding` -> `Test.Bridge.CodeRules:TestCallbackRule` red ("no tool, toolset, policy or renderer class, nor a class that they call, refers to %AI beyond its Class line, or uses Python").
- AC3: `mutation:` make `ModelFolder()` ignore `FASTEMBED_CACHE_DIR` -> `live:memory-offline` red, through the check "the manager directory holds no fastembed folder": with the network up at the first start the mutated step downloads the model into `<mgr>/fastembed/`, so the offline embeds still pass and only that check catches it (see Decided in-stage).
- AC4: `mutation:` remove the "folder already holds the model" return from `Install.Step.Memory:EnsureModel` (the step always downloads) -> `Test.Memory.Install:TestPresentFolder` red (a download is attempted, and the folder gains files because the warm stack has a network) and `live:memory-offline` red through the check that the offline `Run()` attempts no download (`EnsureModel` answers 1). The unit's other checks stay green under this mutation: with the network cut `snapshot_download` returns the complete local cache without error, so the spec's expected "offline `Run()` warns" does not happen.
- AC4 (folder and variable): `mutation:` drop the worker's `FASTEMBED_CACHE_DIR` set in `Embedder:Embed` -> `Test.Memory.Embedding:TestFolderArgument` red ("whose FASTEMBED_CACHE_DIR is the copy"); `mutation:` drop `cache_dir=folder` from the `TextEmbedding` call -> `TestFolderArgument` red (the model cannot be loaded from the copy: without `cache_dir` the package ignores the variable); `mutation:` reduce `SNAPSHOTFILES` to the model and the tokenizer -> `Test.Memory.Install:TestHasModel` red ("a snapshot without a configuration file is not").
- AC5: `mutation:` remove the `stage_requirements` call after path A's ready in `release/ipm-install.sh` -> `bash release/ipm-install.sh a` red: check 30 fails twice ("the output has no STEP Memory OK, or has a WARN Memory line" and "IPM installed fastembed 0.9.0 from requirements.txt ... (3 of 3 values differ)"); green again after the revert (restored from a backup, byte-identical).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Memory vectors are computed offline in a `%SYSTEM.WorkMgr` worker of category `OcuTalon.Memory.Embedder` with Python `fastembed` 0.9.0, driven through `%SYS.Python` from ObjectScript. `OcuTalon.Memory.Embedding` (an `%Embedding.Interface` class, no Python) serves `EMBEDDING()`, embedding columns and `Embed`; `OcuTalon.Memory.Embedder` is the worker side (model folder rule, load once per worker, download entry); `Install.Step.Memory` creates the category and the `OcuTalonMemory` row and ensures the model folder (a download that cannot run is one `WARN Memory`). Task 0 passed: offline, `cache_dir=/opt/fastembed` (read-only) and `<mgr>/fastembed/` both load and return 384 values, at most 1.29e-7 from AI Hub's vector; `HF_HUB_OFFLINE` is not needed (`_bmad-output/implementation-artifacts/evidence/19-2-task0-fastembed-cache-dir.md`). The U-294 release tooling is the last, self-contained task.

**Files.** New: `src/ocutalon/cls/OcuTalon/Memory/{Embedder,Embedding}.cls`, `Install/Step/Memory.cls`, `Test/Memory/{Fixture,Embedding,Install,Offline}.cls`, `docker/tests/test-memory-offline.sh`, root `requirements.txt` (U-294), the Task 0 evidence. Changed: `Install/Registry.cls` (`Memory` before `Production`), `Test/Install/Registry.cls`, `Test/Bridge/CodeRules.cls` (one helper name), `docker/tests/lib-live.sh` and `test-install-upgrade.sh` (step pins), `ci/units.sh` (lane-a area, `live:memory-offline` in `shards-4`), the spine (AD-21, AD-23, the contracts row), and the U-294 files `release/release.sh` (`-bypass-py-deps`), `release/ipm-install.sh` (checks 30, 31), `release/rehearse.sh` (`memory-offline` step), `docker/tests/test-release-sequence.sh` and `test-rehearsal.sh`; `docs/install-ipm.md` (two `STEP Memory OK` lines, needed by `test-cpf.sh` rule 9).

**Review.** 37 findings from four layers: 9 patched entries (partial-snapshot `HasModel`, telemetry order, timeout message, spine wording, network-probe positive control, `HubWorker` variable leak, the Embed routing and category pin, the folder-argument test, AC4 and AC5 mutation lines), 2 deferred (callback surface for Story 19.3; install page text), the rest rejected with reasons in the triage log. Patched by verdict: medium 5 entries, low 4.

**Follow-up review recommended: true.** Five medium entries were patched; the unverified risk is that the new tests read the worker's category from WorkMgr's own global `^IRIS.WorkQueue`, and the x64 result is unobserved until CI's `iris (shards-4)` prints `MEMORY-OFFLINE engine=x86_64 ok=1`.

**Verification (aarch64, lane C).** Warm: `Test.Memory.Embedding`, `Test.Memory.Install`, `Test.Memory.Offline`, `Test.Bridge.CodeRules`, `Test.Install.Registry` passed after the patches; all mutations above red then green. `ci/iris.sh live memory-offline` passed (`MEMORY-OFFLINE engine=aarch64 ok=1`). `live install-start` passed on the second run (the first failed a 200 s restart wait with the machine at load 10; no code failure), `live install-upgrade` passed, `release/ipm-install.sh a` passed (`STEP Memory OK`, no `WARN Memory`, the model once). `shard lane-a --part 6/8` and `7/8` passed (the parts that hold `Test.Install.*`, `Test.Memory.*`, `Test.Install.Registry`; part 1/8 also passed; `CodeRules` passed warm); the other parts and `shard lane-b` were not rerun after the patches (the machine ran at load 10, a part took 6 to 11 minutes) and are CI's job. Static: `test-ci-config`, `test-class-rules`, `test-boundaries`, `test-lib-live`, `test-ci-changes`, `test-release-sequence`, `test-rehearsal` pass; the spine lint shows 10 findings before and after (none new).

**Residual risks.** The rehearsal step is proved on stub hosts only (deferred entry). CI's x64 run of `live:memory-offline`, `ipm-install` (mode a passed here) and the shards are unobserved.
