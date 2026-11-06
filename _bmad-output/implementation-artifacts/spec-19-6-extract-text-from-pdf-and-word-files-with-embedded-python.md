---
title: 'Extract text from PDF and Word files with Embedded Python'
type: 'feature'
created: '2026-11-06'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-2-compute-embeddings-offline-in-a-worker.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/34-2-task0-licences.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 3 must read PDF and Word files, but nothing extracts their text yet: the image has `pdfplumber` 0.11.10 and `python-docx` 1.1.2 (Story 34.2) and no code uses them. The IPM install's root `requirements.txt` pins only `fastembed`, so an IPM install gets unmeasured dependencies, no licence gate and no PDF or Word packages (DW-791). The Memory embedder builds its two keyword calls from Python `eval` strings, a form the Conventions "Python" row does not name (DW-792). The IPM docs do not say that the install downloads packages and a model (DW-784).

**Approach:** Add a standalone extraction service. `OcuTalon.Docs.Extract` is the caller side and holds no Python. It writes the file to a private temporary file and queues one work item to `OcuTalon.Docs.Extractor`, a `%SYSTEM.WorkMgr` category with one worker. The worker imports the new resource `src/ocutalon/python/ocutalon_extract.py` with `%SYS.Python.Import`. The result is text with page or heading markers, cut at a fixed size with a note, or a reason code with a plain reason. Nothing is stored. The queue-and-wait code moves from `Memory.Embedder` into a shared base class, and the Embedder's two lambdas move into a second resource, `ocutalon_memory.py`. In a separate task under U-294, the IPM path gets the whole licence-measured pin set and a licence gate on what IPM installed, and the docs get their PUBLIC TEXT.

## Boundaries & Constraints

**Always:**
- Python runs only in a worker of `OcuTalon.Docs.Extractor` or `OcuTalon.Memory.Embedder` (AD-6). `Docs.Extract`, the shared base `OcuTalon.Memory.Worker` and every caller hold no Python, no `%SYS.Python` and no `%AI` reference. `Docs.Extract` and `Memory.Worker` join `Test.Bridge.CodeRules` `CALLBACKHELPERS`, so the callback scan reads them.
- OcuTalon's own Python lives only in `.py` resources under `src/ocutalon/python/`, imported with `%SYS.Python.Import`. There are no `[Language = python]` methods and no `builtins.eval`/`exec` of Python source (Conventions "Python" row). The `.py` files hold no user-facing text. Every user-facing text (reasons, the cut note, the page marker) is an ASCII class parameter of `Docs.Extract` (Rule 14).
- Extraction stores nothing, whether it succeeds or fails. Its temporary file is deleted before `Read` returns. It writes no global, row or log, and it makes no network call.
- The machine reason codes are fixed by this story and are independent of the wording. Each code's text fits "I couldn't read that file: {reason}." (UX-DR147).
- Sizes: input bytes at most `MAXBYTES` = 10,485,760, pinned equal to Lane B's `Web.Documents` `FILEMAX` by a test, never read from it in product code. Text at most `MAXTEXT` = 200,000 characters before the cut note.
- The IPM path installs exactly the licence-measured set: the root `requirements.txt` pin lines equal the pin lines of `docker/licences/constraints-arm64.txt` and `constraints-x64.txt`, which are identical today (36 distributions). The licence gate runs on what IPM installed.
- Every test added or changed creates and removes its own state: sample streams in memory, its own temporary files, `zz-docs-*` names and its own `^OcuTalonTest` nodes. It passes on a fresh environment, in either order. The tests run on the real image with no test-setup install.

**Never:**
- Nothing from Story 19.4: no `DocumentOps` body, no knowledge base, no `documents` tool, no `Data.Document` write, no reply-filter or bridge change, and no `Production.cls` change. No new tool, command verb, production item, table or event.
- No edit of a Lane B file (U-177). That covers `docker/Dockerfile`, `docker/licences/**` (Story 34.2/34.3's gate, constraints and allowed set, which are read and copied only), `Web/**`, `Core/**`, `Test/{Core,Web}/**` and `web/**`. Also no edit under `release/` beyond the U-294 task below.
- No new `AD-n` id. Spine edits are plain unions marked `[AMENDED 2026-11-06, Story 19.6, ...]`.
- No real-model run (the release-candidate eval is the owner's action item). No OCR. No legacy `.doc` reading. No file sent from the chat or Telegram (Story 26.2).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| PDF with text | 3-page PDF, one accented word (the word "cafe" with an e-acute, written with `$Char(233)`) | `{ok:1, markers:"page", cut:0}`. Text is each page's text under its marker line (`PAGEMARKER` with n: `## Page 1` ...), in page order. The accent is kept. `job` is a worker's `$JOB`, not the caller's. | none |
| Word with headings | .docx: Title, Heading 1 "Rotating the certificate", Heading 2, paragraphs, a 2x2 table | `{ok:1, markers:"heading"}`. Title -> `# T`, Heading n -> n+1 `#` (at most 6), so a Heading 1 is a `##` section line (Story 19.4's splitter). Paragraphs and table rows (cells joined by ` | `) come in document order. | none |
| Cut | PDF or .docx with more than 200,000 characters of text | `cut:1`. The text is cut at the last line break at or before `MAXTEXT` (else at `MAXTEXT`), then a blank line and `CUTNOTE`. The worker stops reading pages once over the limit. | none |
| At the limit | PDF of exactly 10,485,760 bytes (text page plus an unreferenced padding stream) | Read like any PDF, within `TIMEOUT` | none |
| Too large | 10,485,761 bytes, either type | `{ok:0, reason:"too_large"}`. No worker is called and no file is written. | none |
| Contents too large | .docx whose zip entries declare more than `MAXUNPACKED` = 104,857,600 bytes in all | `contents_too_large`; python-docx is never opened on it | none |
| Wrong type | `contentType` other than `pdf`/`docx`; or bytes with no PDF, ZIP or OLE2 signature; or a zip without `word/document.xml`; or an OLE2 file with neither stream name below | `wrong_type` | none |
| Encrypted | PDF with an `/Encrypt` dictionary that the empty user password does not open; .docx that is an OLE2 container with an `EncryptedPackage` stream | `encrypted` | none |
| Damaged | `%PDF-1.4` followed by junk; `PK\x03\x04` followed by junk; zero bytes | `damaged` | none |
| No text layer | PDF whose pages only draw lines; .docx with no text | `no_text` | none |
| Legacy .doc | OLE2 signature with a `WordDocument` stream and no `EncryptedPackage` | `legacy_doc` | none |
| Time limit | A PDF that takes over 5 s (Task 0 sizes it), `Read(..., timeout 1)` | `timed_out` within about 3 s. The busy worker is stopped (`Clear`), the temporary file is gone, and the next `Read` of the 3-page PDF answers `ok:1` in normal time. | none |
| Worker failure | The worker cannot import the resource, or throws something else | `{ok:0, reason:"failed", detail:<status text>}`, never a throw. `detail` is for the operator, never shown to a user, and holds no key, token or environment value. | none |
| Nothing stored | Any row above | No file in `<temp>/ocutalon-extract/` from the call. `^OcuTalonP.Document*` and `^OcuTalonP.KB*` are unchanged. A planted file over an hour old in that folder is deleted by the next `Read`. | none |
| Integration: consumer Memory.Embedding (Rule 1) | `Memory.Embedding.Embed` and the Memory step's `Download` after the move to `Memory.Worker` and `ocutalon_memory.py` | The same 384-value vectors (`Test.Memory.Embedding`). `live:memory-offline` passes. IPM check 30 downloads the model through the resource. | the existing tests fail |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Memory/Embedder.cls:80-104` -- `Submit(entry, timeout, .result, args...)`, the queue-and-wait code to share. It makes a `$SYSTEM.WorkMgr.%New("", 1, ..#CATEGORY)` group and calls `WaitOne`. On a timeout it returns error 5001 "The work item <entry> did not finish within <n> seconds" (`Test.Memory.Embedding:TestSubmitTimeout` and `Test.Memory.Diagnostics:TestSubmitTimeout` assert that text). `:122` and `:162` are the two `builtins.eval` lambdas (DW-792): `TextEmbedding(MODEL, cache_dir=folder, local_files_only=True)` and `snapshot_download(SOURCE, cache_dir=folder, allow_patterns=patterns)`. Build 154's `%SYS.Python` passes no keyword arguments from ObjectScript.
- `src/ocutalon/cls/OcuTalon/Memory/Embedding.cls:48-61` -- the caller-side sibling, with no Python. Its `Embed` calls `Embedder.Submit("Embed", ...)` and must keep working unchanged.
- `src/ocutalon/cls/OcuTalon/Install/Step/Memory.cls:14-35` -- `Run` and `EnsureCategory(name, maxActive, default)` through `Config.WorkQueues` in `%SYS`. Its doc names 19.6 as the reuse (Rule 2 sibling). Category creation goes here, so `Install.Registry` and its order pins stay unchanged.
- `irislib/%SYSTEM/AbstractWorkMgr.cls:124-139` -- `Clear(timeout)` waits up to `timeout` seconds, then kills the group's busy workers and recreates the group: "all work on the group has terminated". `irislib/%SYSTEM/WorkMgr.cls:252` -- `IsWorkerJob()`. `irislib/%SYS/System.cls:16` -- `TempDirectory()`.
- `src/ocutalon/cls/OcuTalon/Docs.cls`, `Docs/Ops.cls`, `Data/Document.cls` -- 19.4's stubs and table: read only here. `Document.Reason` is `MAXLEN = 32`, so every code fits. `Text` is a character stream.
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls:26,42-46` (Lane B, read only) -- `FILEMAX` 10485760 and the codes `wrong_type`, `too_large` and `empty`. Extraction's `too_large` and `wrong_type` reuse those code names.
- `docker/Dockerfile:11-30` (Lane B, read only) -- `fastembed==0.9.0 pdfplumber==0.11.10 python-docx==1.1.2` in one pip line, with `-c constraints-<arch>.txt`. `gate.py check` and `gate.py notices` write `/opt/ocutalon/THIRD-PARTY-NOTICES`. Both packages are already in the image, so AC4's "test setup installs ... until 34.2 pins both" does not apply: no test-setup install. `:31` copies `src/` to `/opt/ocutalon/src/`, so `src/ocutalon/python/` reaches the image.
- `docker/licences/{constraints-arm64.txt,constraints-x64.txt,gate.py,allowed.txt}` (read only) -- 36 pins each. The pin lines are identical: only the three comment lines differ. CI confirmed x64 (DW-765, run 42128738213). `gate.py check <dir> <constraints>` reads only `*.dist-info` folders (`:212-226`), so loose `.py` files beside them are ignored. It fails on an outside licence, an unpinned or differing distribution, and a missing pin. `gate.py notices <dir> <file>` writes the notices.
- `requirements.txt` (root) -- today one line, `fastembed==0.9.0`. IPM 0.10.10 runs `pip install -t <mgr>/python -r requirements.txt --only-binary=:all:` from the loaded module's root (19.2's decode of `%IPM.Lifecycle.Base`), so comment lines are fine. The image path has none in `src/`, so after-start installs nothing.
- `module.xml`, `src/module.xml` -- identical except `SourcesRoot` and the csp `FileCopy` prefix. `docker/tests/test-pinned-sources.sh:74-78,210` is the drift rule, which today rewrites only the csp line. `docker/tests/test-cpf.sh:9,111` allows `FileCopy` only after the `<CPF>` line. `docker/tests/test-compose-file.sh:403` greps the csp line. IPM knows `${MGRDIR}` (`docker/ipm/zpm-0.10.10.xml:36`). `docker/after-start.cos:8` runs `%IPM.Main.Shell("load "_pkgdir)`, so a manifest `FileCopy` also runs on the Docker path. Embedded Python's path includes `<mgr>/python` of the durable mount (PRD addendum section 11). Whether a worker sees it is Task 0 M1.
- `release/ipm-install.sh:86-95,464-488,1205-1216,1486,1613` -- the header's check list, `stage_requirements`, `check_memory` (check 30), check 31's `memory_fingerprint`, and the two staging calls. The container's `<mgr>` comes from `$SYSTEM.Util.ManagerDirectory()`. `release/ipm/Dockerfile` has an allow-listed context of `src/` only, so the gate files are staged into the container the way `requirements.txt` is.
- `release/lib-release.sh:100-141` -- `ipm_artifact_check`. It checks `module.xml`'s name, version, csp `FileCopy` and bundle files, and does not check `requirements.txt`.
- `docker/tests/test-release-sequence.sh:2862-2864` -- the QA pins: `requirements.txt` is exactly `fastembed==0.9.0`, and the Dockerfile's pip line contains it. These change. `:1855-1900` holds the `ipmcheck` step's tests. The release `ipmcheck` step runs the whole `release/ipm-install.sh` with deadline 1980 s. CI's `ipm-install` job (`.github/workflows/lane-a.yml:75-91`) has `timeout-minutes: 35`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls:82` -- `CALLBACKHELPERS` ends with `...,OcuTalon.Memory.Embedding,OcuTalon.Memory,OcuTalon.Tools.HostData"`. `:114` is `PYTHON`. `:196-241` is `TestCallbackRule`. `:775` is `TestToolCodeScan` (the FR-10 tool inventory: `$ZF`, XECUTE, `$SYSTEM.OBJ`, Python, SQL writes). `:109` is `TOOLVERBS`, unchanged. Epic 17 edits other lines of this file.
- `src/ocutalon/cls/OcuTalon/Test/Memory/{Fixture,Embedding,Diagnostics}.cls` -- `Fixture.OnImage()` (the `/opt/ocutalon/version` file), the named off-image skip, `Fixture.Slow` (a work item that hangs), the worker-job assertion, and `Diagnostics`' `Secrets` scanner (DW-793). These are the patterns to reuse.
- `ci/units.sh:20` -- the `lane-a` areas `"... Eval Channel Memory"`. A new area lands in `shard:lane-a@rest` (group `shards-2`, about 1,820 s). Epic 39 edits only `CHECK_SCRIPTS` here.
- `README.md:157-180,314-327`, `docs/install-ipm.md:5-11,126-186,228-284` -- the IPM section, the credits bullets (`docker/tests/test-readme.sh:34-44,1023-1040` pins their structure) and the two sample-output blocks. Epic 17 inserts `STEP Digest OK` lines at `install-ipm.md:166` and `:270`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:693` (AD-21 "PDF and Word (Story 19.6)") and `:800` (AD-23's Python sentence) -- where the unions go.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first; product default 5). Use one fresh lane-C throwaway, `OCUTALON_RUN_TAG=e19s6i0`, with the Verification lane variables, the two resources and the classes loaded. Record the results in `_bmad-output/implementation-artifacts/evidence/19-6-task0-extraction.md`, then `ci/iris.sh teardown`.
  - M1, deployment: a single-file `FileCopy` of each resource to `${mgrdir}python/<file>`. Measure where it lands on the Docker path (after-start's `zpm load`), whether a worker of each category imports it, and whether it lands before the Configure phase's `Invoke` of `Registry.Ipm`. The Memory step's `Download` imports `ocutalon_memory` there. Also run IPM path A of `release/ipm-install.sh` with the manifests changed, and record that a reinstall overwrites the files.
  - M2, libraries: on the hand-built samples, the exception that pdfplumber 0.11.10 raises for each failure sample; python-docx 1.1.2's `Document.iter_inner_content()` and its style names for the samples' styles; the time to read the 10 MB sample; and the page count of the slow sample that takes over 5 s.
  - M3, time limit: after a `timed_out`, `Clear(1)` ends the busy worker (its job no longer exists), and the next `Read` answers normally with no crash. Also record whether two concurrent `Read`s share the one worker.

  **Stop rules:** HALT `blocked` / `intent gap` with the measurement and a recommendation when either holds:
  - neither the `FileCopy` nor the fallback (Design Notes) puts the resources on both paths' worker `sys.path` before the Memory step runs (name the Conventions "Python" row and AD-23);
  - `Clear` cannot stop a busy Python worker without harm (name AD-21's "one worker" and AD-6).
- `src/ocutalon/cls/OcuTalon/Memory/Worker.cls` (new, abstract, no Python) -- move `Embedder.Submit`'s body here unchanged, on `..#CATEGORY` and `$ClassName()`, and keep its timeout text. Add `Parameter STOPONTIMEOUT = 0`: when 1, a timeout calls `queue.Clear(1)` before returning. On a timeout, `Submit` sets `result` (top node) to `timeout`. Add a doc comment (contract only).
- `src/ocutalon/cls/OcuTalon/Memory/Embedder.cls` -- `Extends OcuTalon.Memory.Worker`. Delete its own `Submit`; callers keep calling `Embedder.Submit`. Replace the two `eval` lambdas with `##class(%SYS.Python).Import("ocutalon_memory").load_model(..#MODEL, folder)` and `.download(..#SOURCE, folder, patterns)`. Behaviour is unchanged (DW-792).
- `src/ocutalon/python/ocutalon_memory.py` (new) -- `load_model(model, folder)` returns `fastembed.TextEmbedding(model, cache_dir=folder, local_files_only=True)`. `download(source, folder, patterns)` returns `huggingface_hub.snapshot_download(source, cache_dir=folder, allow_patterns=list(patterns))`. ASCII, with a docstring stating the contract.
- `src/ocutalon/python/ocutalon_extract.py` (new) -- `extract(path, limit, max_unpacked, page_marker)` returns a dict: `{"ok", "text", "cut", "markers"}` or `{"ok": False, "reason", "detail"}`.
  - The signature decides the parser: `%PDF-` in the first 1,024 bytes, `PK\x03\x04`, or OLE2 `D0CF11E0A1B11AE1`. OLE2 holding the UTF-16LE stream name `EncryptedPackage` is `encrypted`; holding `WordDocument` it is `legacy_doc`; anything else is `wrong_type`.
  - PDF: open with pdfplumber. Password failures give `encrypted`; parse failures (M2's classes) give `damaged`. Each page's `extract_text()` goes under `page_marker.format(n=...)`. Stop once over `limit`. Text that is only white space gives `no_text`.
  - DOCX: `zipfile` first. The sum of `file_size` over `max_unpacked` gives `contents_too_large`; no `word/document.xml` gives `wrong_type`; a bad zip gives `damaged`. Then `docx.Document(path)` and `iter_inner_content()`, with headings and tables as in the matrix.
  - Normalize `\r\n` to `\n` and strip NUL. No network, no file write, and no user text (the marker comes in as an argument).
- `src/ocutalon/cls/OcuTalon/Docs/Extractor.cls` (new; `Extends OcuTalon.Memory.Worker`) -- `CATEGORY = "OcuTalon.Docs.Extractor"`, `MAXACTIVEWORKERS = 1`, `DEFAULTWORKERS = 1`, `STOPONTIMEOUT = 1`. Work item `Read(path, limit, maxUnpacked, pageMarker) As %Status` imports `ocutalon_extract`, calls `extract`, and copies the dict into `%result` (`ok`, `text`, `cut`, `markers`, `reason`, `detail`, `job` = `$Job`). A Python exception is an error status. This is the only class of the Docs area that references `%SYS.Python`.
- `src/ocutalon/cls/OcuTalon/Docs/Extract.cls` (new; no Python) -- `Read(content As %Stream.Object, contentType As %String, timeout As %Integer = {..#TIMEOUT}) As %DynamicObject`. It never throws and stores nothing.
  - Check the type and the size first (no worker): `wrong_type`, `too_large`, and `damaged` for zero bytes.
  - Purge files of `<TempDirectory()>/ocutalon-extract/` older than one hour.
  - Copy the stream to a new unique file there, `Submit` to `Docs.Extractor`, and delete the file in every case.
  - Map the result through the public pure method `Answer(sc, .result) As %DynamicObject`, so that every branch is tested without a worker. A timeout gives `timed_out`. Another `Submit` error gives `failed` with `detail`. `ok` text gets `CUTNOTE` appended when cut.
  - `Reason(code) As %String` gives the plain reason. `Failure(code) As %String` gives `FAILUREFRAME` ("I couldn't read that file: {reason}.", UX-DR147) filled in.
  - Parameters: `MAXBYTES`, `MAXTEXT`, `MAXUNPACKED`, `TIMEOUT` = 120, `PAGEMARKER`, `CUTNOTE`, and one `REASON<CODE>` per code (the PUBLIC TEXT below).
- `src/ocutalon/cls/OcuTalon/Install/Step/Memory.cls` -- `Run` also calls `..EnsureCategory` for `Docs.Extractor`'s category, worker values and parameters, before `EnsureConfig`. The doc says it now does four things.
- `module.xml`, `src/module.xml` -- after the csp line, one `FileCopy` per resource. In `src/module.xml`: `<FileCopy Name="ocutalon/python/ocutalon_extract.py" Target="${mgrdir}python/ocutalon_extract.py"/>` and the same for `ocutalon_memory.py`. In the root manifest, the same with `src/` before `Name`. Use the Task 0 M1 form, or the Design Notes fallback with no manifest change.
- `docker/tests/test-pinned-sources.sh` -- the drift rule rewrites every `FileCopy Name="src/` to `Name="` (not only the csp line). Add a sample case with a second `FileCopy` that differs on one side. The rule is unchanged if M1 chose the fallback.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls:82` -- a list append (contended, allowed form): `,OcuTalon.Memory.Worker,OcuTalon.Docs.Extract` at the end of `CALLBACKHELPERS`, and the matching clause on the doc line at `:81`.
- `ci/units.sh:20` -- a one-name append: ` Docs` at the end of the `lane-a` areas.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Samples.cls` (new) -- deterministic sample builders that return `%Stream.TmpBinary`. They use no Python, no internet and no copyrighted text. A hand-written PDF writer covers: text pages, a WinAnsi accent, a drawing-only page, an `/Encrypt` trailer with fixed hex `/O` and `/U`, junk after the header, a padding stream to an exact size, and N pages. A stored-zip writer with `$ZCRC(data, 7)` writes `[Content_Types].xml`, `_rels/.rels`, `word/document.xml` and `word/styles.xml`, and can declare a large `file_size`. It also builds OLE2-signature samples with the two stream names, and junk.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls` (new) -- one test per matrix row. It also covers:
  - `TestRunsInAWorker`: `job` differs from `$Job`, and `IsWorkerJob` is 1 in the worker.
  - `TestNeverInTheCaller`: after PDF and .docx reads, the caller's `sys.modules` holds neither `pdfplumber`, `docx` nor `ocutalon_extract`.
  - `TestCategory`: after `Install.Step.Memory.Run`, `Config.WorkQueues` `OcuTalon.Docs.Extractor` has `MaxActiveWorkers` 1.
  - `TestResourcesCurrent`: a worker's `ocutalon_extract.__file__` folder is `<mgr>/python/` (or M1's folder), and both files equal `/opt/ocutalon/src/ocutalon/python/*`.
  - `TestNoticesKept`: `/opt/ocutalon/THIRD-PARTY-NOTICES` names `pdfplumber 0.11.10` and `python-docx 1.1.2`.
  - `TestLimitsPinned`: `MAXBYTES` equals `Web.Documents.#FILEMAX`.
  - `TestReasonsFitTheFrame`: each code's text is non-empty and ASCII, starts with a lower-case letter, has no final period, and its `Failure()` sentence is at most 120 characters.
  - `TestNothingStored`: no file left, globals unchanged, and a planted old file purged.
  - `TestWorkerFailure`: `Docs.Extractor.Submit("Read", ...)` with a missing path returns an error status, and `Extract.Answer` maps each branch (ok, reason, `timeout`, another error) without a worker.
  - `TestDetailHoldsNoSecret`: the `failed` detail of that worker failure passes `Test.Memory.Install`'s public `Leaks`/`Secrets` scanner.

  The class skips off-image with one named skip, like `Test.Memory.Embedding`.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Python.cls` (new) -- the only non-Test classes whose code lines (comments excluded: `Memory.Embedding`'s doc names `%SYS.Python` today) reference `%SYS.Python` are `Memory.Embedder` and `Docs.Extractor`. Neither calls `eval` or `exec` (DW-792). Every file under `src/ocutalon/python/` that the image holds is ASCII. Read the class sources the way `Test.Bridge.CodeRules` reads them (`Test.Bridge.Source`; Rule 2).
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions marked `[AMENDED 2026-11-06, Story 19.6, ...]`. Afterwards lint the spine; it must show no new finding.
  - AD-21's PDF/Word bullet: the caller/worker split (`Docs.Extract` / `Docs.Extractor` on `Memory.Worker`), the reason codes, `MAXBYTES`/`MAXTEXT`/`MAXUNPACKED`, the markers, `TIMEOUT` with `Clear`, and the temporary file.
  - AD-23's Python sentence: how the resources reach `sys.path` (the M1 result), and that the IPM path pins the constraints files' set with the gate run on it.
- U-294 task (DW-791; a SEPARATE task done after the rest, as in Story 19.2, so a reversal drops only it):
  - `requirements.txt`: a header comment (the source, and "a version change here changes both constraints files and re-measures the licences in the same commit"), then the 36 pin lines of the constraints files.
  - `release/ipm-install.sh`:
    - `stage_licence_gate` copies `gate.py`, `allowed.txt` and the `uname -m` constraints file into a scratch folder of the container, as root, read-only.
    - New check 32: after path A's second run and after part p's install, `gate.py check <mgr>/python <constraints>` passes and `gate.py notices` writes a non-empty file naming all 36 distributions.
    - Check 30 adds the `pdfplumber` 0.11.10 and `python-docx` 1.1.2 versions.
    - New check 33: `Docs.Extract.Read` of `Test.Docs.Samples`' 3-page PDF and headings .docx answers `ok:1` with markers. This proves that the resources and the category reach an IPM install.
    - Check 31 adds: the resources are unchanged after the reinstall.
    - Header lines for 32 and 33.
  - `release/lib-release.sh` `ipm_artifact_check`: the artifact holds a top-level `requirements.txt` equal to the candidate tree's, and its `module.xml` has the resources' `FileCopy` lines (ruling item below).
  - `docker/tests/test-release-sequence.sh`: replace `:2862-2864`. The pin lines of `requirements.txt` equal those of each constraints file. They include each pin of the Dockerfile's pip line. The file is tracked. Add `ipm_artifact_check` cases with no and with a different `requirements.txt`.
- DW-784 docs (each line as the PUBLIC TEXT ruling gives it):
  - `README.md`: one paragraph at the end of "Install it with IPM", and one bullet after the Python-packages bullet in "Third-party licence notices".
  - `docs/install-ipm.md`: one "What you need" bullet, and both sample-output blocks re-shot from this story's real `release/ipm-install.sh p` and `a` outputs (ANSI removed, no local value). Keep `bash docker/tests/test-cpf.sh` and `test-readme.sh` green.

**Acceptance Criteria:**
- Given a PDF or .docx file of at most 10 MB, when any caller asks `Docs.Extract.Read` for its text, then:
  - pdfplumber 0.11.10 or python-docx 1.1.2 runs in a worker of `OcuTalon.Docs.Extractor`, never in the calling process, from `ocutalon_extract.py` imported with `%SYS.Python.Import`;
  - the text comes back with page or heading markers;
  - it is cut at 200,000 characters with the cut note when longer.

  A tool inside a turn is covered: the caller-side classes are in `CALLBACKHELPERS` and hold no Python.
- Given an encrypted, damaged, text-less, legacy `.doc`, oversized or too-slow file, when extraction ends, then it answers `ok:0` with its reason code and a plain reason that fits "I couldn't read that file: {reason}.". Nothing is stored, and the worker is free again after a timeout.
- Given an IPM install, when the package installs, then:
  - `requirements.txt` declares `pdfplumber==0.11.10`, `python-docx==1.1.2`, `fastembed==0.9.0` and every other distribution of the constraints files, at their versions;
  - `release/ipm-install.sh` (the `ipmcheck` unit) runs `gate.py check` on what IPM installed and fails outside the allowed families, or on any unpinned or differing distribution;
  - the licence files are kept (`gate.py notices` names all 36), as `/opt/ocutalon/THIRD-PARTY-NOTICES` does on the image.
- Given `OcuTalon.Test.Docs` with generated samples, when it runs on the real image (a lane-C throwaway, then CI `shards-2`) with no test-setup install, then each text and each failure reason comes back right and the work runs in the worker. `Test.Bridge.CodeRules` (`TestCallbackRule`, `TestToolCodeScan`) passes, and still finds no tool that runs operating-system commands or arbitrary code.
- Given the Embedder after DW-792, when memory embeds and the model downloads, then no OcuTalon class calls Python `eval`/`exec`, and the vectors, `live:memory-offline` and IPM check 30 are unchanged.
- Given the Planner's ruled PUBLIC TEXT and the measured figures, when a reader opens the README's "Install it with IPM" section or `docs/install-ipm.md`, then both say that the install downloads Python packages and the embedding model (size, typical time) and needs network access to PyPI and the model host. The sample outputs are this story's real `release/ipm-install.sh` runs, and `test-readme.sh` and `test-cpf.sh` pass.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions:**
- AD-6: Python only in WorkMgr workers, and the callback scan.
- AD-21: "PDF and Word (Story 19.6)"; Documents' failed-row codes stay `DocumentOps`' (19.4/19.7).
- AD-22: `OcuTalon.Test.<Area>`, the image and throwaways.
- AD-23: image pins, `.py` resources, the IPM install.
- AD-29: Lane A files; Dockerfile and licences read only.
- AD-33: no new item, table or event.
- Conventions: "Python". Stack: pdfplumber 0.11.10 MIT, python-docx 1.1.2 MIT, fastembed 0.9.0 Apache-2.0 (no new dependency or licence).

**Integration ACs:** No product consumer of `Docs.Extract` in this story; the first consumer will be Story 19.7. Within the story, the matrix row "Integration: consumer Memory.Embedding" exercises the shared `Memory.Worker` and `ocutalon_memory.py` through the real embedder.

**Consumed-by:**
- 19.7: `DocumentOps` reads PDF and Word through `Extract.Read`. It maps the codes to `Document.Reason`; the web page's text per code is Lane B's.
- 26.2: files sent from the chat or Telegram, with `Failure(code)` for the frame.
- Any later worker category: `Memory.Worker` and `Install.Step.Memory.EnsureCategory`.

**Consumes:**
- 34.2: the image pins and the notices.
- 34.3: the constraints files and `gate.py`.
- 19.2: `Embedder`, `EnsureCategory`, `ipm-install` checks 30 and 31, and `live:memory-offline`.

**Extend, don't copy:**
- `Memory.Worker` takes `Embedder.Submit`'s body, so there is no second queue-and-wait.
- The category reuses `Install.Step.Memory.EnsureCategory`.
- `Extract`/`Extractor` mirror `Embedding`/`Embedder`.
- The tests reuse `Test.Memory.Fixture.OnImage`, `Test.Memory.Install`'s secret scanner (`Leaks`/`Secrets`) and `Test.Bridge.Source`.
- `stage_licence_gate` follows `stage_requirements`.

**Decided in-stage:**
- Names. `Docs.Extract` is the AD-21 service name and the caller side. `Docs.Extractor` is both the category and its worker class, like `Memory.Embedder`. The shared base lives in `Memory` because the Embedder is its first user, and Docs already depends on Memory.
- The category is created by `Install.Step.Memory`, AD-21's "the area's install step" for both categories. This avoids a new registry step and the order pins in `Test.Install.Registry`, `lib-live.sh` and `test-install-upgrade.sh`.
- Transport. The bytes go through a temporary file, because a WorkMgr argument should stay small and 10 MB exceeds a string. The folder is `TempDirectory()/ocutalon-extract/`. Files are deleted in every case, and leftovers older than an hour are purged at each call.
- A timeout stops the busy worker (`STOPONTIMEOUT`, Embedder 0, unchanged), so one slow file cannot block the one worker. A timeout is told apart by `result` = `timeout`, not by matching text.
- The signature decides the parser; the declared type only gates `pdf`/`docx`.
- A PDF that pdfminer opens with the empty user password (owner password only) is read, which is pdfminer's own behaviour. There is no sample for it, because valid owner-only encryption needs the RC4 key schedule in the sample writer (inference, not tested).
- Markers are Markdown lines, so Story 19.4's `##` sections give PDF pages and Word Heading-1 sections without a second splitter.
- Limits:
  - `MAXTEXT` 200,000 characters, about 200 of 19.4's 1,000-character passages; the worker stops early.
  - `TIMEOUT` 120 s, the Embedder's value; Task 0 M2 times the 10 MB sample.
  - `MAXUNPACKED` 100 MB, a zip-bomb guard.
- Codes: `too_large`, `contents_too_large`, `wrong_type`, `encrypted`, `damaged`, `no_text`, `legacy_doc`, `timed_out`, `failed`. They are recorded in AD-21; the wording is PUBLIC TEXT.
- DW-792's lambdas go into their own resource, `ocutalon_memory.py`, which matches its module, rather than into `ocutalon_extract.py`. The DW wording names "the .py resource this story creates": both are this story's, deployed the same way.
- Deployment.
  - Primary: one `FileCopy` per file into `<mgr>/python/`, which is already on Embedded Python's path.
  - Fallback if M1 refutes it: `Install.Step.Memory` copies the files from the IPM module root into `<mgr>/python/` before `EnsureModel`, with no manifest change.
  - Single files, not the folder, so that an uninstall can never remove the pip packages beside them.
- "A tool inside a turn": no tool calls extraction in this story. The proof is the scan of `Extract`/`Worker` in `CALLBACKHELPERS`, the worker job, and the caller's `sys.modules`. The live in-callback test belongs to the first tool consumer, Story 26.2. A test-only toolset would mean a contended Chat/runner change.
- Samples are generated in ObjectScript, not committed as binaries and not made with Python in the test process, so `TestNeverInTheCaller` stays falsifiable.
- `Test.Docs` joins `lane-a` and so `shard:lane-a@rest` (`shards-2`). The extra seconds are recorded. The rule (orchestrator, this stage): a UNIT over 1,000 s on a clean run is split; a GROUP only above 35 minutes on two clean runs.

**Declined:** none. DW-784, DW-791 and DW-792 are addressed above: DW-791 by the U-294 task and AC3, DW-792 by the Embedder task, `Test.Docs.Python` and AC5, DW-784 by the docs task and its PUBLIC TEXT.

**arm64 and x64 pins:** identical. Both constraints files pin the same 36 versions, and CI confirmed x64 (DW-765). `test-release-sequence.sh` fails if they ever differ, and a difference is reported before commit.

**`CALLBACKHELPERS` / `TOOLVERBS` / `TRUSTEDTOOLS` / Reminders tool list:**
- `CALLBACKHELPERS` gains `OcuTalon.Memory.Worker` and `OcuTalon.Docs.Extract` (a list append at the end).
- `TOOLVERBS` (`Test/Bridge/CodeRules.cls`), `TRUSTEDTOOLS` (`Test/Bridge/Gate.cls`) and `Test/Tools/Reminders.cls`' tool list are unchanged: no tool or verb is added.

**Needs a ruling:**
- `docs/install-ipm.md` (Epic 17 contended; Epic 11's list) -- DW-784 re-shoots both sample-output blocks. That collides with Epic 17's two `STEP Digest OK` inserts (`:166`, `:270`), and the story adds one "What you need" bullet. Recommended: a plain union at integrate-forward that keeps the re-shot block and puts Epic 17's line at its place in the step order.
- `README.md` (Epic 11 contended, not in flight) -- one paragraph inside "Install it with IPM" and one bullet under "Third-party licence notices". Neither is at the end of the file.
- `release/ipm-install.sh` (checks 30 to 33 and staging) and `requirements.txt` -- read as covered by U-294 condition 1 (DW-791's routing), kept as a separate task; confirmation asked.
- `release/lib-release.sh` `ipm_artifact_check` -- the `requirements.txt` and `FileCopy` checks go beyond "ipmcheck runs the gate", but they are what makes the registry path install the measured set. Recommended: allowed under U-294.

**PUBLIC TEXT needed:**
- Reasons (`Docs.Extract` `REASON*`), each read as "I couldn't read that file: {reason}." -- proposed:
  - `too_large` 'it is over the 10 MB limit'
  - `contents_too_large` 'its contents are too large to read'
  - `wrong_type` 'it is not a PDF or Word (.docx) file'
  - `encrypted` 'it is protected with a password'
  - `damaged` 'it is damaged or incomplete'
  - `no_text` 'it has no text to read, for example a scanned PDF without a text layer'
  - `legacy_doc` 'it is an old Word file (.doc), so save it as .docx and try again'
  - `timed_out` 'reading it took too long'
  - `failed` 'something went wrong while reading it'
- `Docs.Extract` `CUTNOTE` -- proposed: '[OcuTalon read only the first 200,000 characters of this file.]'
- `Docs.Extract` `PAGEMARKER` (it becomes a citation's section, for example "Results runbook, Page 3", in Story 19.7) -- proposed: '## Page {n}'
- `README.md`, end of "Install it with IPM" -- proposed: 'The second run also downloads OcuTalon's Python packages from PyPI (fastembed, pdfplumber and python-docx with their dependencies, about 270 MB once installed) and the embedding model from Hugging Face (about 90 MB), so the instance needs network access to pypi.org, files.pythonhosted.org and huggingface.co. This typically adds about 3 minutes to the install.'
- `README.md`, "Third-party licence notices", new bullet -- proposed: 'An IPM install puts the same Python packages, at the same versions, into the instance's `mgr/python` folder, each with its licence files.'
- `docs/install-ipm.md`, "What you need", new bullet -- proposed: 'Network access from the instance to PyPI (pypi.org and files.pythonhosted.org) and to Hugging Face (huggingface.co): the second command downloads OcuTalon's Python packages, about 270 MB once installed, and the embedding model, about 90 MB. On a typical connection this takes about 3 minutes.'
- The figures are inference: 357 MB for the arm64 image's pip layer with the model, 89,052 KB for the model (34.2 evidence), and the time is a guess. The implement stage replaces each figure with its measured value before the lead sends the text:
  - installed size: `du -sk <mgr>/python` after path A;
  - model: `du -sk <mgr>/fastembed`;
  - download: the summed wheel sizes of `pip download --only-binary=:all: --no-deps -r requirements.txt -d <scratch>` in the same throwaway;
  - time: path A's second-run `TIME` with packages against the same run's step times, on ARM and on the CI x64 `ipm-install` log.

**Residual risks:**
- The exact 36 pins assume Python 3.12 wheels, the AI Hub build 154 interpreter. Another interpreter may find no wheel and fail pip.
- A running worker keeps an older resource in `sys.modules` until it is recycled (inference).
- PDF decompression bombs are bounded only by the time limit.
- The release-candidate real-model eval before the release that carries Epic 19 stays the owner's action item; this story runs no real model.

## Verification

Lane variables go on every `ci/iris.sh`, `ci/warm.sh`, `release/ipm-install.sh` and `release/rehearse.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=implement'`.

Every call runs in the foreground with `timeout: 600000`. If the harness moves a call to the background after about 180 s, poll its output file in foreground loops under 170 s each, and never start a second copy. One `iris_execute_tests` per message; `server` and `namespace` on every IRIS MCP call.

Runtime targets, all lane C:
- warm throwaway `e19s6iw` (`ci/warm.sh up` once, `down` at the end, also after a failure);
- fresh `e19s6i` (live units, shards, IPM runs);
- `e19s6i0` (Task 0).

A change to a `.py` file or a manifest refuses a warm run: `ci/warm.sh down`, then `up`. The dev slot `ocutalon-slot-c` (namespace `OCUTALON`) is used only for `iris_doc_load` compile checks. There `Test.Docs` skips, because the slot has no package or pdfplumber. The slot is left as found.

**Commands:**
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s6iw ci/iris.sh class <C>` (loop), one call each, for C in `OcuTalon.Test.Docs.Extract`, `.Docs.Python`, `.Memory.Embedding`, `.Memory.Diagnostics`, `.Memory.Install`, `.Memory.Search`, `.Bridge.CodeRules`, `.Install.Registry`, `.Install.PrivateData` -- expected: CLASS passed, with no SKIP.
- `OCUTALON_LIVE_DEADLINE=1200 OCUTALON_RUN_TAG=e19s6i ci/iris.sh live memory-offline` (once) -- expected: every PASS and `MEMORY-OFFLINE engine=aarch64 ok=1`.
- `OCUTALON_RUN_TAG=e19s6i ci/iris.sh live install-start`, then `live install-upgrade` (once each) -- expected: PASS (the Memory step on fresh and upgraded stacks).
- `OCUTALON_RUN_TAG=e19s6i ci/iris.sh shard lane-a --part k/12` for k = 1..12, and `shard lane-b --part k/4` for k = 1..4, one call each (once) -- expected: every class passed. Then `ci/iris.sh teardown`.
- `OCUTALON_RUN_TAG=e19s6i bash release/ipm-install.sh a`, then `p`, then `b`, one call each (once; with the U-294 task) -- expected:
  - `a`: checks 30, 32 and 33 PASS;
  - `p`: checks 26 to 29, plus 32 after part p's install, PASS;
  - `b`: check 31 PASS (about 11 minutes or more: poll as above);
  - record each `TIME` line.
- `OCUTALON_RUN_TAG=e19s6ir bash release/rehearse.sh run --dry-run --rc 1`, one call per phase until `down` (once) -- expected: a dry-run result; record the install phase's seconds.
- `docker build --no-cache -f docker/Dockerfile -t ocutalon-e19s6i-nocache .` (once) -- record the seconds of the pip-and-model step (the clean host's download), then `docker rmi ocutalon-e19s6i-nocache`.
- One call each (once), expected PASS: `bash docker/tests/test-ci-config.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-pinned-sources.sh`, `test-cpf.sh`, `test-compose-file.sh`, `test-storage.sh`, `test-ci-changes.sh`, `test-release-sequence.sh` (all under `docker/tests/`), and `test-readme.sh` once the README lines land.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once, after the spine edit) -- expected: no new finding.
- CI (condition 2 of U-294):
  - `iris (shards-2)` runs `Test.Docs.*`. Record `shard:lane-a@rest`'s seconds; a unit over 1,000 s on a clean run goes to the lead's standing split.
  - Record the `lane-a` workflow's `ipm-install` job minutes on two clean runs. Over 35 minutes goes to the standing split (a ruling), never a timeout raise.
  - A full `release/ipm-install.sh` over 1,800 s is reported, because the release `ipmcheck` deadline is 1,980 s.

**Mutations (one per AC; the implement stage applies each from a backup, observes red, reverts, confirms the tree byte-identical, and records the result here):**
- AC1: make `Extract.Read` call `Docs.Extractor.Read` in-process instead of `Submit` -> `TestRunsInAWorker` and `TestNeverInTheCaller` red. Drop the page marker -> `TestPdfPages` red. Drop the cut note -> `TestCut` red.
- AC2: let `Read` skip deleting its file -> `TestNothingStored` red. Classify OLE2 as `wrong_type` always -> `TestLegacyDoc`/`TestEncryptedDocx` red. Set `STOPONTIMEOUT` to 0 -> `TestTimeLimit` red (the next read waits or times out).
- AC3: drop one pin line of `requirements.txt` -> `test-release-sequence.sh` red, and IPM check 32 red (unpinned distribution). Drop the `stage_licence_gate` call -> check 32 FAIL.
- AC4: add a `##class(%SYS.Python).Import("os")` line to `Docs.Extract` -> `Test.Bridge.CodeRules:TestCallbackRule` red (it is listed) and `Test.Docs.Python` red. Remove the resource `FileCopy` -> `TestResourcesCurrent` red.
- AC5: put one `builtins.eval` back in the Embedder -> `Test.Docs.Python` red.
- AC6: drop a `STEP <name> OK` line of `Registry.Order()` from one re-shot block -> `test-cpf.sh` red; drop the IPM section's link to `docs/install-ipm.md` -> `test-readme.sh` red.

**Shared surfaces:**
- `CALLBACKHELPERS` (`TestCallbackRule`).
- The `lane-a` areas and the shard class lists (`test-ci-config.sh`).
- Both manifests (`test-pinned-sources.sh`, `test-cpf.sh`, `test-compose-file.sh:403`, `ipm_artifact_check` and its tests).
- Root `requirements.txt` (`test-release-sequence.sh`, IPM check 30).
- `Embedder.Submit` and its timeout text (`Test.Memory.Embedding`, `Test.Memory.Diagnostics`).
- `Install.Step.Memory`'s steps (`Test.Memory.Install`).
- The `Config.WorkQueues` categories (no test counts them).
- `<mgr>/python`'s contents (IPM checks 30 to 33).
- The README IPM and credits sections (`test-readme.sh`).
- The sample outputs of `docs/install-ipm.md` (`test-cpf.sh` 9, 11 and 12).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned and halted after planning, as the dispatch asked. Implementation does not depend on the "Needs a ruling" or "PUBLIC TEXT needed" items under Design Notes: the U-294 task and the DW-784 docs task are separate and come last, and the reason codes and their tests do not depend on the wording.
