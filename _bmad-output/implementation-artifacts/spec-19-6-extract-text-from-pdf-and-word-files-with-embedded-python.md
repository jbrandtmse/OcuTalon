---
title: 'Extract text from PDF and Word files with Embedded Python'
type: 'feature'
created: '2026-11-06'
status: 'done'
baseline_revision: '4e29a8f2f5be07c11466283e90c7547b158d73fd'
baseline_commit: '4e29a8f2f5be07c11466283e90c7547b158d73fd'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-2-compute-embeddings-offline-in-a-worker.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/34-2-task0-licences.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The category setting MaxActiveWorkers 1 of OcuTalon.Docs.Extractor does not serialise reads: two concurrent Docs.Extract.Read calls ran on two worker jobs at the same time (Task 0 M3), so AD-21's "one worker" holds for the category setting and not for the number of simultaneous workers.
    evidence: |-
      evidence/19-6-task0-extraction.md M3: two clients that each made their own work group got two worker jobs and finished in parallel (about 4 s each); Test.Docs.Extract:TestCategory asserts the setting (MaxActiveWorkers 1), as the spec asks. Memory use is about 220 MB for each worker. Decide in Story 19.7 whether Docs.Extract needs a lock around Submit (a process-shared lock would serialise the callers).
    location: >-
      src/ocutalon/cls/OcuTalon/Docs/Extract.cls
    severity: low
  - summary: >-
      Clear on a timed-out read waits for a work item that is inside one long C call (a 30 s time.sleep held Clear for 29 s), so a PDF whose time goes into one C call (a decompression bomb) can keep Read past its limit.
    evidence: |-
      evidence/19-6-task0-extraction.md M3: pdfplumber's page loop (Python code) is stopped in 1 to 3 s; only a single C call that does not return delays the stop. The matrix row "within about 3 s" is measured for the page loop only (inference for a bomb: the spec's Residual risks name it).
    location: >-
      src/ocutalon/cls/OcuTalon/Memory/Worker.cls
    severity: low
  - summary: >-
      On an IPM install, pip -t leaves the older copies of six distributions that <mgr>/python already holds (certifi, charset_normalizer, idna, requests, typing_extensions, urllib3) beside the pinned dist-info, so the pinned version's files may not be the ones imported.
    evidence: |-
      release/ipm-install.sh path A (this story): the gate on everything in <mgr>/python fails (11 places: 5 unpinned dependencies of IPM itself, 6 older versions of pinned names); check 32 therefore gates what the install added and the pins (NOTE lines list the rest). Whether the import resolves the old or the new code of those six was not measured; a pip --upgrade in IPM's requirements step is not available to a module.
    location: >-
      requirements.txt
    severity: medium
  - summary: >-
      The README and docs/install-ipm.md list three hosts (pypi.org, files.pythonhosted.org, huggingface.co); huggingface_hub 1.33 with hf-xet may also use CDN or Xet hosts, and the docs do not say what a blocked download looks like (the Memory step only warns).
    evidence: |-
      Blind Hunter finding, unverified. Would be settled by running the model download behind a host allow-list, or by reading the real hosts from a verbose download in a throwaway. The sentence is PUBLIC TEXT pending the Planner's ruling.
    location: >-
      README.md, docs/install-ipm.md
    severity: medium (unverified)
  - summary: >-
      Word text inside body-level content controls (w:sdt) and inside nested tables is not read, because iter_inner_content yields only body paragraphs and tables and cell.text skips nested tables; a file made only of content controls answers no_text.
    evidence: |-
      python-docx 1.1.2 behaviour (Edge Case Hunter); no sample covers it. Settle with a template-style .docx sample in Story 19.7 or when a real file shows it.
    location: >-
      src/ocutalon/python/ocutalon_extract.py
    severity: low
  - summary: >-
      A .dotx/.docm (python-docx ValueError), a .docx with an encrypted zip entry (RuntimeError) or an unsupported zip compression (NotImplementedError) is raised and reported as failed, not as wrong_type, encrypted or damaged.
    evidence: |-
      Edge Case Hunter; the answer is honest (failed) and nothing is stored. A mapping of these exceptions is a wording decision for the reasons list.
    location: >-
      src/ocutalon/python/ocutalon_extract.py
    severity: low
  - summary: >-
      A line in the file's own text that starts with "## " is indistinguishable from a marker line, so Story 19.4's splitter would open a section there.
    evidence: |-
      Edge Case Hunter; inherent in Markdown markers (the spec's decided design). Story 19.4 decides whether to escape or ignore such lines.
    location: >-
      src/ocutalon/python/ocutalon_extract.py
    severity: low
  - summary: >-
      Test.Docs.Extract:TestNothingStored compares an empty knowledge-base half (no KB table exists before Story 19.4) and only the $Data flag of the Document globals, so a stray write elsewhere is not caught.
    evidence: |-
      Verification-gap finding; the KB tables arrive in Story 19.4, which should add the KB half to the signature.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:399
    severity: low
  - summary: >-
      TestTimeLimit asserts only that a timed-out read ended in under 20 s (the matrix says about 3 s), and no test pins local_files_only=True or allow_patterns in ocutalon_memory.py.
    evidence: |-
      Verification-gap findings. The 20 s bound follows the loaded-host measurement in the evidence file; a tight bound would be flaky. The two keyword arguments change behaviour only when the model is absent.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:207
    severity: low
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

**Review patches (pass 1; the Review Triage Log rows name them):**
- P1 `src/ocutalon/cls/OcuTalon/Memory/Worker.cls` -- `Submit`: `GroupLocks()` before the queue and `ReleaseGroupLocks` after a timeout run inside a Try that fails quiet (a failed scan means no release), so `Submit` never throws; on a timeout set `result` to `timeout` and `timedOut` first, and call `queue.Clear(0)` in its own Try.
- P2 `src/ocutalon/python/ocutalon_extract.py` and `Test/Docs/Samples.cls`, `Test/Docs/Extract.cls` -- a Word table row reads a merged cell once (consecutive cells with the same cell element are one); add a sample with a horizontally merged cell and a test (`TestDocxMergedCell` or a case in `TestDocxHeadings`).
- P3 `ocutalon_extract.py` -- a paragraph whose `style` is `None` is a plain paragraph (no `AttributeError`).
- P4 `ocutalon_extract.py` -- a wrapped `PDFEncryptionError` (not only `PDFPasswordIncorrect`) is `encrypted`.
- P5 `release/ipm-install.sh` -- delete the unused `manager_directory` call and its die in `stage_licence_gate`.
- P6 `release/lib-release.sh` and `docker/tests/test-release-sequence.sh` (the B4 hunk only) -- `ipm_artifact_check` also requires the FileCopy's Target `${mgrdir}python/<file>`; the test cases use a wrong Target.
- P7 `_bmad-output/implementation-artifacts/evidence/19-6-task0-extraction.md` -- add the IPM path A result (the four M1 facts) and a "Measured figures" section (installed 251,202,444 bytes, wheels 75,994,243 bytes in 36 files, model 91,103,785 bytes, second command 58 to 63 s quiet and 87 to 90 s loaded, pip and download about 21 s, no-cache build's pip-and-model step 26.0 s) so that the 250 MB, 90 MB and 1 minute of the README and docs have a source.
- P8 `Docs/Extract.cls` -- the class comment says the purge happens when a call writes a file (not at the start of each call).
- P9 `Test/Docs/Extract.cls`, `Samples.cls` -- (a) literal assertions: the PDF text starts with `## Page 1` and the cut text ends with the literal note text; (b) a `DocxBroken` sample (a zip whose `word/document.xml` entry is junk) read as `damaged` in `TestDamaged`; (c) `TestCut` for the Word big text asserts `markers` is `none`; (d) `TestCategory` sets the Extractor category to 5 and 3 before `Install.Step.Memory.Run` and asserts 1 and 1.
- Each new or changed pinning test gets its `mutation:` line in `## Verification` (apply from your own backup, observe red, revert byte-identical).

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

### Review Findings

Code review 2026-11-06 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; full-opus tier). 0 decision-needed, 15 patch (all applied), 4 defer (ledgered `wontfix-accepted`), 17 rejected; 0 high.

- [x] [Review][Patch] (medium) The nine reasons were the proposed strings, not the Planner's PUBLIC TEXT ruling A1, and `too_large` could not name the size [src/ocutalon/cls/OcuTalon/Docs/Extract.cls:45] -- conformed byte for byte; `REASONTOOLARGESIZE` (the web catalog's "that file is {size}; the limit is 10 MB.") is used by `Reason(code, size)` / `Failure(code, size)` when the caller passes the size, with `SizeText` writing it as the web app's `formatSize` does; `REASONWRONGTYPE` is the catalog's text byte for byte.
- [x] [Review][Patch] (medium) No fixed-strings test pinned the reasons, the frame, the cut note, the page marker or the README/docs lines (Rule 19) [src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:400] -- `TestReasonsAreTheRuledText` (every string and eleven size cases, literal) and four `t_static` checks in `docker/tests/test-release-sequence.sh` (A4, A5, A6 whole lines, and the two catalog reasons present in both `web/src/app/documents/documents-view.ts` and `Docs/Extract.cls`); each group's mutation is in `## Verification`.
- [x] [Review][Patch] (medium) The README paragraph (A4) and the install page bullet (A6) ended with the proposed sentences [README.md:182] -- now "In our test installs this added about 1 minute." and "In our test installs this took about 1 minute." (singular for n = 1; see the change log).
- [x] [Review][Patch] (low) The two catalog reasons end with a period, so the chat frame would end in ".." and `TestReasonsFitTheFrame`'s "no final period" would fail [src/ocutalon/cls/OcuTalon/Docs/Extract.cls:140] -- `Failure` gives a reason's final period up to the frame's own; the test now asserts the sentence does not end with two periods.
- [x] [Review][Patch] (medium) `Test.Memory.Install:OnAfterAllTests` ran `New $Namespace` inside an `ElseIf`, so the rest of the method ran in %SYS and failed with `<CLASS DOES NOT EXIST>` whenever the extraction category was absent before the class (observed on the warm stack); `Fixture.Restore` also resolved `##class(...).#CATEGORY` in %SYS (observed) [src/ocutalon/cls/OcuTalon/Test/Memory/Install.cls:57] -- the delete moves into `Fixture.Restore` (`state("docs")`), which reads both category names before the switch.
- [x] [Review][Patch] (low) DW-834: a .docm/.dotx, a password-protected zip entry and an unknown compression method were reported `failed` [src/ocutalon/python/ocutalon_extract.py:136] -- mapped to `wrong_type`, `encrypted` and `damaged` (also `zlib.error`/`EOFError` as `damaged`; `NotImplementedError` caught before its base `RuntimeError`), each matched on its message and anything else still raised; four samples and `ExtractEdges:TestWordFileVariants`.
- [x] [Review][Patch] (low) A zip whose first 1,024 bytes hold `%PDF-` was sent to pdfplumber [src/ocutalon/python/ocutalon_extract.py:170] -- the ZIP and OLE2 signatures at byte 0 are tested before the PDF window; a case in `TestPdfSignatureWindow`.
- [x] [Review][Patch] (low) `ipm_artifact_check` checked each resource's FileCopy line but not that the artifact holds the file [release/lib-release.sh:130] -- it also reports a missing resource and other bytes than the candidate's (B4 hunk), with two `ipmlib` cases; IPM path p passed with it on a real package.
- [x] [Review][Patch] (low) This story's spine unions said the purge runs "at each call", "one `## Page n` line per page" and that the IPM-install overwrite was measured [ARCHITECTURE-SPINE.md:693] -- corrected to what the code and the evidence say; the lint shows no new finding.
- [x] [Review][Patch] (low) The evidence's stop rule 1 bracket stated the success condition, promised four path-A facts that were not all measured, and did not say the figures came from public PyPI and Hugging Face [_bmad-output/implementation-artifacts/evidence/19-6-task0-extraction.md:7] -- reworded.
- [x] [Review][Patch] (low) `ExtractEdges:TestEmbedderResource` ran the memory resource's stand-ins in an extraction worker, loading fastembed there [src/ocutalon/cls/OcuTalon/Test/Docs/ExtractEdges.cls:289] -- it submits through `Memory.Embedder`.
- [x] [Review][Patch] (low) `TestCategory` left the category at 5 and 3 when `Run` failed (Rule 19) [src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:316] -- it puts the declared values back at its end.
- [x] [Review][Patch] (low) The matrix's "no file is written" for `too_large` was not observable [src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:145] -- `TestTooLarge` plants a file over an hour old and asserts that a too-large read leaves it (it never reaches the purge).
- [x] [Review][Patch] (low) `MAXTEXT`'s doc comment described `MAXUNPACKED` [src/ocutalon/cls/OcuTalon/Docs/Extract.cls:19] -- one comment each.
- [x] [Review][Patch] (low) The AC6 figures-match test had no recorded mutation [docker/tests/test-release-sequence.sh:2906] -- recorded below (the A4 mutation also turns it red).
- [x] [Review][Defer] (low) `STOPONTIMEOUT`/`Clear(0)` has no test that fails without it [src/ocutalon/cls/OcuTalon/Memory/Worker.cls:45] -- deferred: DW-841 `wontfix-accepted` (the AC is pinned by `TestTimeLimit`; the work group release also ends the worker, measured).
- [x] [Review][Defer] (low) Check 32's before/after filter has no static test [release/ipm-install.sh:523] -- deferred: DW-842 `wontfix-accepted`.
- [x] [Review][Defer] (low) Check 31 shows the resources unchanged, not overwritten, after a reinstall [release/ipm-install.sh:1351] -- deferred: DW-843 `wontfix-accepted` (the spine now labels the IPM-install overwrite as inference).
- [x] [Review][Defer] (low) `TestTimeLimit` assumes the previous read's idle worker takes the slow read [src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:222] -- deferred: DW-844 `wontfix-accepted`.

Existing entries, no new row: DW-829 (escalated; the A5 sentence and AD-23's "exactly the licence-measured set" bear on it, report only), DW-827 (AD-21's "one worker"; routed to 19.7), DW-831 (text boxes join nested tables and content controls), DW-834 (patched above, for the lead's adjudication), DW-835 (QA's `TestEmbedderResource` closes its keyword-argument half; the 20 s bound is DW-844's neighbour and stays as filed).

Rejected:
- (low, by-design) A text cut far after its last line break keeps only the text before that break -- the matrix fixes "the last line break at or before MAXTEXT"; paragraphs are joined by line breaks, so only one paragraph of over 200,000 characters meets it.
- (false, by-design) A main part named other than `word/document.xml` -- the spec fixes the name; Word, Strict OOXML and LibreOffice write it.
- (low) A vertically merged cell repeats its text in each row it spans -- a faithful row reading; nested tables and text boxes are DW-831's root cause.
- (low, theoretical) A caller timeout over `MAXAGE` lets another call purge an in-flight file -- no caller passes one (`TIMEOUT` 120); real if a caller passes over 3,600 s.
- (low, theoretical) A DST jump or an unreadable modification date makes a fresh file look old -- containers run in UTC and a read lasts at most 120 s; real on a DST time zone with concurrent reads across the jump.
- (low, theoretical) A character stream with characters above 255 -- the answer is `failed` (honest) and no consumer exists yet; real if Story 19.7 passes a character stream.
- (low, theoretical) A work group lock with several owners -- the measured lock is exclusive to the caller.
- (low, theoretical) A stale notices file from an earlier call -- check 32 runs once per fresh container; real if it ever runs twice in one container.
- (low) `wrong_type`'s ruled text names Markdown and plain-text, which `Extract.Read` itself refuses -- the Planner ruled the catalog text; the extraction callers route those types elsewhere (noted for the lead).
- (low) The re-shot install-page block shows version 1.0.1 -- it is this story's real run output (ruling B1).
- (low) `TestAtTheLimit`'s time assertion can only fail with the `ok` assertion; `ExtractEdges`' `reason '= code` assertions -- redundant or weak, but each is falsifiable for its recorded mutation.
- (low) Implement-stage mutation records use "Result:" rather than the `mutation:` token -- every AC has a recorded, observed mutation.
- (low) Check 32 skips an older pre-existing copy of a pinned name -- measured and designed (DW-829).
- (low) The x64 install time is not measured -- read from the CI `ipm-install` log after the push (U-294 condition 2).
- (low) The spec's frontmatter `status`, its Auto Run Result's residual paragraph, the task text's `Clear(1)` and the spec/ledger severity mismatch -- the fix edits the spec's intent or the lead's bookkeeping.
- (low) No consumer test for the Embedder vectors beyond the existing ones, and AD-6 conformance -- both hold (the auditor found no violation).
- (low) The spine's "one worker" stated as fact -- DW-827 owns it.

## Spec Change Log

- 2026-11-07 (lead): the Planner's install-figure ruling (about 01:32Z): A4 ends "In our test installs on an Apple silicon Mac, the downloads took about 20 seconds and the whole second run about 1 to 1.5 minutes." and A6 ends "... the whole second command about 1 to 1.5 minutes."; "about 250 MB" and "about 90 MB" kept. The figures-match test now reads four figures (sizes, download time, run time); mutation: README "about 20 seconds" -> "about 25 seconds" -> `test-release-sequence.sh static` red, restored byte-identical. x64 figure: from CI's ipm-install log, for the Planner (no x64 clause added).

- 2026-11-06 (code review): the Planner's PUBLIC TEXT ruling applied. The nine reasons, the frame, the cut note and the page marker are the ruled strings, pinned by `TestReasonsAreTheRuledText`; `Reason`/`Failure` take an optional `size` so that `too_large` is the web catalog's "that file is {size}; the limit is 10 MB." when the size is known (the size written as the web app's `formatSize` writes it) and "it's over the 10 MB limit" otherwise; `Failure` gives a reason's own final period up to the frame's, so a catalog reason does not end the chat sentence with "..". The README paragraph (A4) and the install-page bullet (A6) end with the ruled sentences with n = 1, written "about 1 minute" (singular), pinned by `t_static`. Decided in-stage (small, reversible): the singular, the period hand-over and the optional `size` argument.

- 2026-11-06 (lead, after implement): the Planner's PUBLIC TEXT ruling recorded under Design Notes; the code review stage conforms the built strings to it with fixed-strings tests (the implement built the proposals).

- 2026-11-06 (lead, before implement): orchestrator rulings B1-B3 and the pending B4 / PUBLIC TEXT recorded under Design Notes "Rulings"; a test that README.md and docs/install-ipm.md quote the same measured figures is added to scope.

## Review Triage Log

### 2026-11-06 -- Review pass
- verdicts: 50 findings -- high 0, medium 7, low 38, false 3, maybe-false 2
- findings:
  - `[low]` `[defer]` (Blind) README/spine "same versions" while six older copies stay beside the pinned dist-info -- the deferred list already holds this (medium, import resolution unmeasured); the README bullet is PUBLIC TEXT pending the Planner, who is told in the Auto Run Result.
  - `[low]` `[defer]` (Blind) spine says "one worker" but MaxActiveWorkers 1 does not serialise reads -- already the first item of `deferred:` (Task 0 M3); the "one worker" wording is the spine's existing text.
  - `[maybe-false]` `[defer]` (Blind) the documented three hosts may miss CDN or Xet hosts and the blocked-download behaviour is not described -- deferred as medium (unverified); the real host list was not measured.
  - `[low]` `[reject]` (Blind) "about 1 minute" is not the added time on a fast host (about 21 s of pip and download in a 58 to 63 s second run) -- the figure is a conservative rounding for an ordinary connection and the sentence is PUBLIC TEXT; the missing record of the measured sizes and times is patched (evidence file), see the row for the missing evidence.
  - `[medium]` `[patch]` (Blind) Worker.Submit's GroupLocks and ReleaseGroupLocks run outside the Try, so a ^$LOCK read that raises makes Submit throw -- patch P1: both inside the Try and failing quiet. (The every-call scan cost is `[low]` `[reject]`: the table is small and the snapshot must precede the queue.) [fixed: scan and release in Try, result and timeout set before Clear, Clear in its own Try.]
  - `[medium]` `[patch]` (Blind) merged Word table cells are read once per grid column (row.cells repeats the cell) -- patch P2: dedupe consecutive cells with the same cell element, with a merged-cell sample. [fixed: same-cell dedupe plus DocxMergedCell sample and TestDocxMergedCell.]
  - `[low]` `[reject]` (Blind) OLE2 kind found by a substring search of the whole file -- a legacy .doc would need the UTF-16 stream name inside its text; fix means parsing the directory.
  - `[low]` `[patch]` (Blind) stage_licence_gate calls manager_directory and dies on an empty answer but never uses the value -- patch P5: delete the unused call. The doc-comment position and the two ways of reading the manager directory are `[low]` `[reject]` (cosmetic). [fixed: unused manager_directory call deleted.]
  - `[low]` `[patch]` (Blind) ipm_artifact_check checks the FileCopy name and not its Target -- patch P6, in the separable B4 hunk, with its test. [fixed: Target checked in ipm_artifact_check, with a wrong-Target test case.]
  - `[low]` `[reject]` (Blind) trailing newline before the cut note and pdfplumber pages not flushed -- cosmetic, and the memory growth is not shown.
  - `[low]` `[patch]` (Blind) the Task 0 evidence promises the IPM path A facts and holds none; the measured figures have no record -- patch P7: add both to the evidence file. [fixed: evidence file holds the IPM path A section and the measured figures.]
  - `[low]` `[reject]` (Blind) the test's GroupLocks copies the production method -- a test that called the production method would test itself.
  - `[medium]` `[patch]` (Edge) GroupLocks before the Try can throw (Worker.cls:26) -- same root cause as the Blind row, patch P1. [fixed: scan and release in Try, result and timeout set before Clear, Clear in its own Try.]
  - `[low]` `[patch]` (Edge) Clear(0) throwing before result and timedOut are set turns a timeout into failed -- patch P1: set them first and give Clear its own Try. [fixed: scan and release in Try, result and timeout set before Clear, Clear in its own Try.]
  - `[low]` `[reject]` (Edge) the lock scan on every Submit -- see the Blind row; table size is small.
  - `[low]` `[patch]` (Edge) item.style is None when styles.xml has no default paragraph style, raising AttributeError -- patch P3. [fixed: a style of None is a plain paragraph (no sample; inference).]
  - `[low]` `[defer]` (Edge) .dotx/.docm, encrypted zip entry and odd compression are reported as failed -- deferred (low); honest answer, wording decision.
  - `[low]` `[defer]` (Edge) text in content controls (w:sdt) is skipped -- deferred (low), with nested tables.
  - `[medium]` `[patch]` (Edge) merged cells repeated; nested tables ignored -- merged cells in patch P2; nested tables in the deferred row above.
  - `[low]` `[patch]` (Edge) an unsupported-encryption PDF (a PDFEncryptionError other than PDFPasswordIncorrect) is called damaged -- patch P4: any PDFEncryptionError is encrypted. [fixed: any PDFEncryptionError is encrypted (no sample; inference).]
  - `[low]` `[reject]` (Edge) TypeError, ValueError and similar from extract_text() give failed instead of damaged -- failed is a valid, honest code and the guard list would be a guess.
  - `[low]` `[reject]` (Edge) the cut may leave a bare marker line at the end -- cosmetic; a bare marker is an empty last section.
  - `[low]` `[defer]` (Edge) lines of the file's text starting with "## " look like markers -- deferred (low) to Story 19.4's splitter.
  - `[false]` `[reject]` (Edge) a lone surrogate in extracted text breaks the crossing -- not shown reachable: pdfminer's text comes from decoded cmap code points, and a failure would only give failed.
  - `[false]` `[reject]` (Edge) PDF signature test before ZIP -- a .docx's first 1,024 bytes hold part names and not a literal %PDF-; Acrobat's own window is also 1,024 bytes.
  - `[false]` `[reject]` (Edge) the main part is assumed to be word/document.xml -- Word, Strict OOXML and LibreOffice all write that name; the spec fixes it.
  - `[low]` `[reject]` (Edge) timeout 0, negative or empty from a caller -- no caller passes one (the default is a parameter), nothing to guard yet.
  - `[low]` `[patch]` (Edge) Purge runs only on the path that writes a file, while the class comment says at the start of each call -- patch P8: the comment says what happens (leftovers only come from that path). [fixed: class comment.]
  - `[low]` `[reject]` (Edge) the temporary file and folder have default permissions -- a chmod needs $ZF, which TestToolCodeScan forbids in a callback helper; the container has one OS user.
  - `[low]` `[patch]` (Edge, claim) Word style None, same root cause as the style row -- patch P3. [fixed: a style of None is a plain paragraph (no sample; inference).]
  - `[low]` `[defer]` (Edge, claim) "one worker" -- the deferred list's first item.
  - `[low]` `[patch]` (Edge, claim) Purge at the start of each call -- patch P8. [fixed: class comment.]
  - `[low]` `[reject]` (Edge, claim) Embedder behaviour is not unchanged (lock scan, timeout result node) -- the scan and the node are the recorded Task 0 finding; Embedding and Diagnostics tests passed after the move.
  - `[low]` `[reject]` (Edge, claim) "private" temporary file -- see the permissions row.
  - `[medium]` `[patch]` (Gap) PAGEMARKER and CUTNOTE are only compared with themselves, so "## Page 1" is not pinned -- patch P9a: literal assertions. [fixed: literal assertions.]
  - `[medium]` `[patch]` (Gap) the python-docx failure branch (a zip-valid .docx python-docx cannot open) has no sample -- patch P9b: DocxBroken sample, asserted damaged. The PDF fallback branch (line 72) is `[low]` `[reject]`: no sample reaches it. [fixed: DocxBroken sample, damaged in TestDamaged.]
  - `[low]` `[patch]` (Gap) markers none for a Word file with no headings is not asserted -- patch P9c. Heading 7 cap, early stop, NUL and CR normalisation are `[low]` `[reject]`: they need timing or byte-level samples for little risk. [fixed: markers asserted.]
  - `[medium]` `[patch]` (Gap) TestCategory passes without the new EnsureCategory line because the test class creates the category first -- patch P9d: put the category to 5 and 3 before Run and assert 1 and 1. [fixed: TestCategory perturbs the category before Run.]
  - `[low]` `[defer]` (Gap) TestNothingStored compares an empty KB half -- deferred (low).
  - `[low]` `[defer]` (Gap) the "about 3 s" bound is asserted as under 20 s -- deferred (low).
  - `[low]` `[reject]` (Gap) TestDetailHoldsNoSecret reads a path-only detail -- the product puts no environment value in detail; no mutation can be named.
  - `[low]` `[reject]` (Gap) TestCategory restores nothing -- throwaway stacks only; Test.Memory.Install restores for itself.
  - `[low]` `[defer]` (Gap) AC5 has no mutation for local_files_only and allow_patterns -- deferred with the 3 s row (low).
  - `[maybe-false]` `[reject]` (IA) IPM "exactly the measured set" holds at the file level and not at the import level -- the same fact as the first deferred row of this log (six older copies), already deferred.
  - `[low]` `[reject]` (IA) docs: only the match between README and docs is tested, not the truth of the figures -- the figures are the measured ones (evidence patch P7); a test cannot measure a download.
  - `[low]` `[reject]` (IA) every sample is hand-built, none from Word or Acrobat -- the spec decides ObjectScript-built samples (Design Notes).
  - `[low]` `[reject]` (IA) the time-limit bound is 20 s in the test, not about 3 s -- the deferred row for the 3 s bound.
  - `[low]` `[reject]` (IA) the lock release in Memory.Worker is not in the intent -- a recorded Task 0 finding in Design Notes, with a test and a mutation line.
  - `[low]` `[reject]` (IA) scope edges (no consumer test; lib-release.sh under B4) -- both are as the spec and the rulings say.
  - `[low]` `[reject]` (IA) no new vector-equality test for the Embedder -- the existing Test.Memory.Embedding, live:memory-offline and IPM check 30 are the spec's consumer row and ran green.

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
- Clear(0), not Clear(1) (Task 0 M3). `Memory.Worker` calls `queue.Clear(0)` on a timeout when `STOPONTIMEOUT` is 1: `Submit` has already waited the whole limit, `Clear(1)` added 2 to 3 s (4.3 to 5.3 s from the call), `Clear(0)` ended the read 2.3 s after the call with the same stop. Releasing the work group also ends a busy worker, so `STOPONTIMEOUT` 0 is not observable through the next read; `TestTimeLimit` therefore checks that the busy worker's job is gone.
- A timed-out read leaves a work group lock with the caller (build 154, measured after Task 0; see the evidence file's last section), so `Memory.Worker.Submit` releases the work group locks that the process holds after a timeout and did not hold when it began. `TestTimeLimit` asserts it, and removing the release fails the test and the class (a lock left after the test case).
- Review patch P1: `Memory.Worker.Submit` scans for held group locks and releases them inside Try blocks that fail quiet, so a failed scan means no release and `Submit` never throws; on a timeout the `timeout` result and the error status are set before `Clear(0)` runs in its own Try. No test names a `^$LOCK` failure (it cannot be provoked from a test); `TestTimeLimit` and the lock-release mutation above cover the normal path.
- Review patches P3 and P4 (a paragraph with no style is a plain paragraph; any wrapped `PDFEncryptionError` is `encrypted`) have no test, because the spec asks for none: a `None` style needs a styles part with no default paragraph style, and a PDF with an unsupported encryption needs an encryption writer that the sample builder does not have. They are inference, as the owner-password-only case is.
- Empty PDF pages get no marker line (an empty section would be a citation to nothing); the page number stays the page's real number. A PDF with text on no page is `no_text`.
- `markers` is `none` for a .docx that has no heading or title paragraph.
- Check 32 gates what IPM installed (U-294 condition 1, measured): `<mgr>/python` of the plain image also holds 11 distributions that the image's AI Hub packages and IPM's own dependencies put there before the install (5 are not pinned, 6 are older versions of pinned names), so a gate on the whole folder fails by design. `stage_licence_gate` stages the gate and the constraints file, `snapshot_python_before` records the folder just before the install command, and check 32 gates every dist-info except one that was there before and is no pin. `ipm_artifact_check` and its tests are the separable last hunk (ruling B4).
- The test of the two files' figures sits in `test-release-sequence.sh` (README.md is not on the image, and `test-readme.sh` is Epic 11's).
- `Test.Memory.Install` also saves and restores the `OcuTalon.Docs.Extractor` category, because `Run()` now makes it.
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

**Rulings (2026-11-06, orchestrator; the PUBLIC TEXT and B4 are with the Contest Planner). They answer the "Needs a ruling" items above:**
- B1 (docs/install-ipm.md re-shoot, DW-784): RULED a plain union. The re-shot sample-output blocks stay; whichever epic integrates second puts Epic 17's "STEP Digest OK" line back at its place in the step order. Footprint extension.
- B2 (README.md, Epic 11's file, not in flight): ALLOWED as a footprint extension: exactly one paragraph at the end of "Install it with IPM" and one bullet under "Third-party licence notices"; nothing else in README.md changes.
- B3: CONFIRMED. `release/ipm-install.sh` (checks 30-33 and the staging) and the root `requirements.txt` are covered by U-294 condition (1), as its separate last task.
- B4 (`release/lib-release.sh` `ipm_artifact_check`): PENDING with the Planner. Build it as its own separable last task, kept apart from the rest (its own hunk, its own tests), so it can be dropped cleanly.
- PUBLIC TEXT (the nine reasons, the cut note, the page marker, the README paragraph and bullet, the install-ipm.md bullet): build with the strings as proposed under Design Notes; they may still change by the Planner's ruling (a forward edit). The README and docs/install-ipm.md quote the SAME measured figures (package size, model size, typical time): measure them in this story and add a test that the two files' figures match each other.

**PUBLIC TEXT ruling (2026-11-06, the Contest Planner under the owner's delegation; every string is exact; pin each with a fixed-strings test). It replaces the proposed strings above:**
- A1, the extraction reasons, one frame per place. Frames: on the Documents page the page's existing U-284 frame "Couldn't read it: {reason}" (the web app's, Lane B, not this story); in a chat reply, where OcuTalon speaks, "I couldn't read that file: {reason}.". `too_large` and `wrong_type` reuse U-284's catalog reasons: "that file is {size}; the limit is 10 MB." and "it isn't a Markdown, plain-text, PDF or Word (.docx) file."; where {size} isn't available on a path, `too_large` is "it's over the 10 MB limit". The new reasons: `contents_too_large` "its text is too long to read"; `encrypted` "it's protected with a password"; `damaged` "it's damaged or incomplete"; `no_text` "it has no text to read, for example a scanned PDF without a text layer"; `legacy_doc` "it's an old Word file (.doc); save it as .docx and try again"; `timed_out` "reading it took too long"; `failed` "something went wrong while reading it". Match the apostrophe bytes of the existing U-284 catalog strings, authored via escapes per Rule 14 if they are not ASCII.
- A2 (approved): "[OcuTalon read only the first 200,000 characters of this file.]"
- A3 (approved): "## Page {n}"
- A4 (README, end of "Install it with IPM"): approved as proposed with the measured figures, except the last sentence, which becomes: "In our test installs this added about {n} minutes."
- A5 (README, "Third-party licence notices"): approved as written: "An IPM install puts the same Python packages, at the same versions, into the instance's `mgr/python` folder, each with its licence files." (The lead raised DW-829 with the Planner: pip -t leaves six older copies beside the pinned ones, so this sentence's accuracy is in question; build it as written pending that answer.)
- A6 (docs/install-ipm.md, "What you need"): approved as proposed with the measured figures, except the last sentence, which becomes: "In our test installs this took about {n} minutes."
- Conditions on the figures: every size and time is measured and the story record says how and from which path (local or offline paths only, never the public IPM registry pm.community.intersystems.com; figures that came from public PyPI say so); README.md and docs/install-ipm.md quote the same figures, with a test that they match; any figure more than 20% off the proposal (270 MB, 90 MB, 3 minutes) goes to the Planner as PUBLIC TEXT before the push (the lead does that).
- B4: ALLOWED under U-294 (1): `ipm_artifact_check` proves that the registry artifact carries `requirements.txt` and the FileCopy.

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
  - Result (implement stage, applied from a backup, reverted byte-identical): the in-process call turned `TestNeverInTheCaller`, `TestPdfPages` (the job), `TestRunsInAWorker` and `TestTimeLimit` red; `PAGEMARKER` set to an empty text turned `TestPdfPages` red (through its assertion that the marker holds `{n}`; the expected text is built from the parameter); removing the cut-note line from `Answer` turned `TestCut` and `TestWorkerFailure` red.
- AC2: let `Read` skip deleting its file -> `TestNothingStored` red. Classify OLE2 as `wrong_type` always -> `TestLegacyDoc`/`TestEncryptedDocx` red. Set `STOPONTIMEOUT` to 0 -> `TestTimeLimit` red (the next read waits or times out).
  - Result: no delete turned every read-checking test red (`TestNothingStored` among them); OLE2 as `wrong_type` (a fresh stack, as it is a resource change) turned `TestEncryptedDocx` and `TestLegacyDoc` red. `STOPONTIMEOUT` 0 alone stayed green: releasing the work group at the end of `Submit` also ends the busy worker (measured), and the next read goes to a new worker anyway. `STOPONTIMEOUT` 0 together with holding the work group in a `%` variable (so that neither `Clear` nor the release stops the worker) turned `TestTimeLimit` red (the busy worker's job still exists, and the next read has the same worker).
- AC3: drop one pin line of `requirements.txt` -> `test-release-sequence.sh` red, and IPM check 32 red (unpinned distribution). Drop the `stage_licence_gate` call -> check 32 FAIL.
  - Result: dropping the `anyio` pin turned `test-release-sequence.sh` (`static`) red (35 of 36 pins) and left IPM check 32 green (pip picks the newest `anyio`, which is the pinned one); changing the `certifi` pin to an older version turned check 32 red (the gate: installed 2026.7.22, pinned 2026.10.23; the notices name 35 of 36). Dropping the `stage_licence_gate` call for path A's stack ended check 32 in a failure (the gate files are not there) and the script's later checks with it.
- AC4: add a `##class(%SYS.Python).Import("os")` line to `Docs.Extract` -> `Test.Bridge.CodeRules:TestCallbackRule` red (it is listed) and `Test.Docs.Python` red. Remove the resource `FileCopy` -> `TestResourcesCurrent` red.
  - Result: the `Import("os")` line turned `TestCallbackRule` and `TestPythonOnlyInTheWorkers` red; removing the two `FileCopy` lines of `src/module.xml` (a fresh stack) turned `TestResourcesCurrent` and the reads red.
- AC5: put one `builtins.eval` back in the Embedder -> `Test.Docs.Python` red.
  - Result: `TestNoEvalOrExec` red.
- AC6: drop a `STEP <name> OK` line of `Registry.Order()` from one re-shot block -> `test-cpf.sh` red; drop the IPM section's link to `docs/install-ipm.md` -> `test-readme.sh` red.
  - Result: dropping `STEP Telegram OK` from the first re-shot block turned `test-cpf.sh` rule 9 red; removing the link turned `test-readme.sh` `ipm` red.
- Lock release (found after Task 0): removing the `ReleaseGroupLocks` call from `Memory.Worker.Submit` -> `TestTimeLimit` red (a new work group lock) and the class red (the unit-test manager reports a global left locked).
- B4 (`ipm_artifact_check`, its own hunk): drop the `requirements.txt` comparison -> `test-release-sequence.sh` `ipmlib` red (result: red on "another requirements.txt").
- Review patches (pass 1; each applied from a backup, observed red, reverted byte-identical, `git status --short` and the checksums of the modified files equal before and after):
  - P2: make the table row loop in `ocutalon_extract.py` keep every cell (`if cell._tc is previous` made `if False`) -> `TestDocxMergedCell` red ("the merged cell is read once"; the sample's merged cell is repeated without the dedupe). A fresh warm stack, as it is a `.py` change.
  - P9a: `PAGEMARKER` set to `# Page {n}` -> `TestPdfPages` red ("it starts with the literal marker line of page 1", alone); `CUTNOTE` with `200 000` for `200,000` -> `TestCut` red ("which is the literal note text", for both kinds).
  - P9b: remove `etree.XMLSyntaxError` from the .docx `except` of `ocutalon_extract.py` -> `TestDamaged` red ("a zip whose word/document.xml is not XML"; the junk part is raised and reported as failed).
  - P9c: make the .docx `markers` always `heading` -> `TestCut` red ("a Word file with no heading has no markers"; applied with P2 and P9b in one `.py` mutation run, each test named its own assertion).
  - P9d: remove the `Docs.Extractor` `EnsureCategory` call from `Install.Step.Memory.Run` -> `TestCategory` red ("with 1 active worker" and "and 1 default worker", as the test first puts the category to 5 and 3).
  - P6: revert the `ipm_artifact_check` resource `grep` to the Name alone -> `test-release-sequence.sh ipmlib` red ("python: a FileCopy of a resource to another Target").

**QA stage (QA):** files created or changed by the QA stage: `src/ocutalon/cls/OcuTalon/Test/Docs/ExtractEdges.cls` (new, 11 tests; area `Docs`, so lane-a / `shards-2` runs it) and `src/ocutalon/cls/OcuTalon/Test/Docs/Samples.cls` (`Docx` takes an optional `moreStyles` list; no other change). Run on warm `e19s6qw`: `Test.Docs.ExtractEdges`, `Test.Docs.Extract`, `Test.Docs.Python` and `Test.Bridge.CodeRules` passed. The tests assert reason codes and structure and none pins a user-facing string. Mutations (each applied from a backup in the QA scratch folder, observed red, reverted; the checksums of `Docs/Extract.cls` and the two `.py` files and `git status --short` equal before and after; the `.py` ones on a fresh warm stack, in two batches so that each test names its own mutation):
- mutation: `_finish` cut test `len(text) > limit` -> `>=` -> `TestAtTheTextLimit` red ("and not cut", "its whole text comes back").
- mutation: cut without a line break `text[:limit]` -> `text[:limit - 1]` -> `TestCutWithoutLineBreak` red ("the text is cut at MAXTEXT characters").
- mutation: page marker number `number` -> `len(parts) + 1` -> `TestPageNumbersAreReal` red ("keeps its real number 3").
- mutation: heading cap `min(n + 1, 6)` -> `min(n + 1, 7)` -> `TestHeadingLevels` red.
- mutation: `PDF_SIGNATURE in head` -> `head.startswith(PDF_SIGNATURE)` -> `TestPdfSignatureWindow` red ("a PDF with 100 bytes before %PDF- is not called a wrong type").
- mutation: OLE2 check order swapped (legacy_doc before encrypted) -> `TestEncryptedBeatsLegacy` red.
- mutation: unpacked size `sum(...)` -> `max(...)` -> `TestContentsTooLargeAddsEntries` red.
- mutation: `unpacked > max_unpacked` -> `>=` -> `TestContentsAtTheLimit` red (alone; applied in its own batch because `max` hides it).
- mutation: remove `.replace("\r\n", "\n")` from `_finish` -> `TestLineEndsNormalised` red ("a CR LF pair is one line feed").
- mutation: `Extract.Read` size line `$Select($IsObject($Get(content)): content.Size, 1: 0)` -> `content.Size` -> `TestReadNeverThrows` red (damaged and wrong_type expectations).
- mutation: drop `, local_files_only=True` from `ocutalon_memory.load_model` and `list(patterns)` -> `patterns` in `download` -> `TestEmbedderResource` red ("asks for local files only", "the allow-patterns as a list"; this closes the deferred keyword-argument gap with stand-ins, so no model is loaded and nothing is downloaded).

**Code review stage (mutations; each applied from a backup in the stage's scratch folder, observed red, reverted byte-identical, `git status --short` and the file's checksum equal before and after; the class ones on the warm stack `e19s6cw`, green again after the revert, the `.py` ones on a fresh `e19s6c` throwaway):**
- mutation: `REASONENCRYPTED` "it's" -> "it is" -> `TestReasonsAreTheRuledText` red ("encrypted", "a framed reason").
- mutation: `Failure` keeps the reason's final period -> `TestReasonsAreTheRuledText` red ("a framed catalog reason ends with one period", "a framed too_large with a size") and `TestReasonsFitTheFrame` red ("wrong_type: the sentence does not end with two periods").
- mutation: `SizeText` KB without rounding up (`bytes \ 1024`) -> `TestReasonsAreTheRuledText` red ("1 bytes", "1025 bytes", "1048575 bytes").
- mutation: `Purge` moved before the type and size checks of `Read` -> `TestTooLarge` red ("writes no file (it does not reach the purge)").
- mutation: the README A4 sentence "about 1 minute." -> "about 1 minutes." -> `test-release-sequence.sh static` red ("(DW-784, A4) the README's IPM paragraph is the ruled text" and the AC6 figures-match "quote the same package size, model size and install time").
- mutation: the A6 sentence "this took" -> "this takes" -> `static` red ("(DW-784, A6)"); the A5 bullet "licence files." -> "licence file." -> `static` red ("(DW-784, A5)").
- mutation: `REASONWRONGTYPE` without its final period -> `static` red ("(A1) the web catalog and Docs.Extract both hold").
- mutation: `ipm_artifact_check` without the missing-resource line, then without the other-bytes line -> `test-release-sequence.sh ipmlib` red each time ("python: an artifact without the resource file", "python: an artifact with other bytes in the resource").
- mutation (one `.py` batch, each assertion named): the `ValueError`, `RuntimeError` and `NotImplementedError` branches always raise, `zlib.error`/`EOFError` dropped from the damaged tuple, and the PDF window tested before the ZIP signature -> `ExtractEdges:TestWordFileVariants` red (all four samples) and `TestPdfSignatureWindow` red ("a zip with %PDF- in its first bytes").
- `Test.Memory.Install` with the extraction category deleted first: the original `OnAfterAllTests` -> class error `<CLASS DOES NOT EXIST>` (as was the first patch, through `Fixture.Restore`); the patched class passes and leaves the category absent, as it found it.
- Runs after the patches: warm `Test.Docs.Extract`, `Test.Docs.ExtractEdges`, `Test.Docs.Python`, `Test.Bridge.CodeRules`, `Test.Memory.Install`, `Test.Memory.Embedding`, `Test.Memory.Diagnostics` passed; `test-release-sequence.sh` (all 26 rules, 371 s), `test-readme.sh`, `test-cpf.sh`, `test-boundaries.sh`, `test-class-rules.sh` passed; the spine lint shows no new finding; IPM path p (fresh, local package, 622 s: checks 26 to 29, 32 and 33 and the artifact check passed) and IPM path b (fresh, local package, `OCUTALON_LIVE_DEADLINE=1980`, 870 s: every check passed, check 24 "RL fired once" and check 31 included).

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

Status: done
Blocking condition: none

**Summary.** Story 19.6 adds `OcuTalon.Docs.Extract` (caller side, no Python) and `OcuTalon.Docs.Extractor` (worker, category `OcuTalon.Docs.Extractor`, one worker) on the new shared base `OcuTalon.Memory.Worker`, with `ocutalon_extract.py` (pdfplumber 0.11.10, python-docx 1.1.2) and `ocutalon_memory.py` (the Embedder's two former `eval` strings, DW-792). Both resources reach `<mgr>/python` by a single-file `FileCopy` in both manifests (Task 0 M1). U-294 (separate task): the root `requirements.txt` pins the 36 licence-measured distributions; `release/ipm-install.sh` gains `stage_licence_gate`, check 32 (licence gate and notices on what IPM installed) and check 33 (a real PDF and .docx read), and extends checks 30 and 31. DW-784: one README paragraph and bullet, one `docs/install-ipm.md` bullet and re-shot sample blocks. B4 (separable): `ipm_artifact_check` checks the resources' FileCopy (name and Target) and `requirements.txt`.

**Files changed** (one line each): `src/ocutalon/cls/OcuTalon/Memory/Worker.cls` (shared queue-and-wait, STOPONTIMEOUT, group lock release), `Docs/Extract.cls`, `Docs/Extractor.cls`, `src/ocutalon/python/ocutalon_extract.py`, `ocutalon_memory.py`, `Memory/Embedder.cls` (extends Worker, no eval), `Install/Step/Memory.cls` (Extractor category), `Test/Docs/{Samples,Extract,Python}.cls`, `Test/Memory/Install.cls` (saves and restores the new category), `Test/Bridge/CodeRules.cls` (CALLBACKHELPERS append), `ci/units.sh` (Docs area), `module.xml` and `src/module.xml`, `requirements.txt`, `release/ipm-install.sh`, `release/lib-release.sh`, `docker/tests/test-pinned-sources.sh` and `test-release-sequence.sh`, `README.md`, `docs/install-ipm.md`, the spine (AD-21 and AD-23 unions), and the evidence file `evidence/19-6-task0-extraction.md`.

**Review.** 50 findings: 0 high, 7 medium, 38 low, 3 false, 2 maybe-false. Patches applied: P1 to P9 (7 medium and 3 low entries by verdict; the rows are in the Review Triage Log). Deferred (6 new items, in the frontmatter list beside the 3 the implement pass recorded): network host list (medium, unverified), content controls and nested tables, other exceptions mapped to failed, forged marker lines, TestNothingStored's empty KB half, the 20 s bound and the unpinned keyword arguments. Rejected findings carry their reason in each log row.

**Follow-up review recommended: true.** Seven medium entries were patched (two or more). Unverified risk: P3 (a paragraph with no style) and P4 (any `PDFEncryptionError` is `encrypted`) have no sample, and P1's Try wrapper around the lock scan cannot be provoked from a test.

**Verification.**
- Before the patches (implement pass): `Test.Docs.Extract`, `.Docs.Python`, `Test.Memory.Embedding/Diagnostics/Install/Search`, `Test.Bridge.CodeRules`, `Test.Install.Registry/PrivateData` passed; `live:memory-offline` ok=1, `install-start`, `install-upgrade`, IPM `a` and `p`, the no-cache Docker build, shards `lane-a` 1 to 12 and `lane-b` 1 to 4 (on the warm stack, not on a fresh throwaway) passed; the ten `docker/tests` scripts passed; the spine lint shows no new finding. IPM `b` failed only check 24 ("RL pending, wanted fired"), the same on an unmodified HEAD copy (pre-existing on this loaded host). `rehearse.sh run --dry-run` ended `fail` on a reminder timing bound; it builds from committed HEAD, so it does not exercise this change.
- After the patches: the class loop (`Test.Docs.Extract`, `.Docs.Python`, `Test.Memory.Embedding/Diagnostics/Install`, `Test.Bridge.CodeRules`) passed on the warm stack; `test-release-sequence.sh` and `test-pinned-sources.sh` passed; `live:memory-offline` ok=1; IPM `a` passed (checks 30, 32 and 33); lead re-ran `test-boundaries`, `test-class-rules`, `test-ci-config`, `test-readme` and `test-cpf` (all pass). The other `(once)` lines (shards, install-start/upgrade, IPM p and b, rehearse, no-cache build) were not repeated after the patches: the patches touch the Worker, the two Python resources, the Docs classes, `stage_licence_gate` and the B4 hunk, which the re-run lines cover.
- Mutations: one line per AC and per new test in `## Verification`, each applied from a backup, red, and reverted.
- Protocol slip: the patch subagent sent two class runs (`Memory.Embedding`, `Memory.Diagnostics`) in one message; both passed.

**Residual risks.** Condition 2 of U-294 (the `shard:lane-a@rest` seconds and the `ipm-install` job minutes on two clean CI runs) and the x64 install time are not measured here (no CI run); the README and docs figures (about 250 MB, about 90 MB, about 1 minute) are ARM-only measurements. The README bullet "same versions" and the three-host sentence are PUBLIC TEXT pending the Planner, and the older-copies and host-list deferrals bear on them. `MaxActiveWorkers` 1 does not serialise concurrent reads (deferred). The matrix's "within about 3 s" holds only on a quiet host (2.3 s); `TestTimeLimit` allows 20 s.
