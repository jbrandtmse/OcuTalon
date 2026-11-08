---
title: 'Answer from PDF and Word documents'
type: 'feature'
created: '2026-11-07'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-6-extract-text-from-pdf-and-word-files-with-embedded-python.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-4-answer-from-documents-with-citations.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/19-6-task0-extraction.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A PDF or Word (.docx) file added from the Documents page reaches `DocumentOps`, whose Text seam fails it with `not_built`, and `Docs.Passages.Split` refuses the content types `pdf` and `docx`; so Story 19.6's extraction is never used and no answer can cite a PDF or Word runbook. Four extraction gaps are routed here: two simultaneous reads run on two worker jobs (DW-827), one long C call (a decompression bomb) outlives the time limit (DW-828), Word content controls and nested tables are not read (DW-831), and a file's own `## ` lines would open sections (DW-832).

**Approach:** At the Text seam, `DocumentOps` sends `pdf` and `docx` bytes through `OcuTalon.Docs.Extract.Read` (the Extractor worker, never its own process) and indexes the returned text exactly like Markdown: the splitter reads `pdf` and `docx` as Markdown, so a PDF is sectioned by its `## Page n` lines and a Word file by its Heading 1 lines, and a failure becomes a failed row whose `Reason` is the extraction's code. `Docs.Extract` serialises reads with a lock; the worker bounds Flate decoding, escapes a file's own `## ` lines as `\## ` and reads content controls and nested tables. Tests drive PDF and Word runbooks through `Commands.Submit` -> `CommandsIn` -> `DocumentOps` -> `Decide` -> `ChatAgent` on the CI mock, and `live:documents` sends them through the real route.

## Boundaries & Constraints

**Always:**
- Python runs only in a worker of `OcuTalon.Docs.Extractor` (AD-6, AD-21). `Docs.Ops`, `Docs.Extract` and `Docs.Passages` hold no Python, no `%SYS.Python` and no `%AI` reference.
- `DocumentOps` stays the only writer of `Data.Document` and of the knowledge-base rows during a session's life, and the only publisher of `document` (AD-33). The add answers synchronously (AD-1): the extraction wait (`EXTRACTWAIT` 45 s, lock wait included) is well inside `CommandsIn`'s `TIMEOUT` of 120 s.
- A PDF or Word document is indexed by the same `IndexBatch`, `Store.Write` and `Store.Remove` as a Markdown one, with the same `source`, `chunk_index` and metadata, and its citations come from `Bridge.Citations` unchanged (at most 5, floor 0.4).
- A file that cannot be read gives a failed row whose `Reason` is the code `Docs.Extract` answered (one of its `CODES`), one `document` event, Ok 1 `added` with `MESSAGENOTINDEXED`, no knowledge-base row and no temporary file.
- At most one extraction runs at a time on the instance (DW-827), and no single decompression call in the worker can produce more than the remaining `MAXUNPACKED` budget (DW-828).
- User-facing text only from the ACs, `EXPERIENCE.md`, `epics.md`, DW-719's owner-ruled wording and the Planner's A1 ruling (19.6 spec); anything else is PUBLIC TEXT (Design Notes).
- Every test added or changed creates and removes its own state (`zz-docs-files*` sessions and names, documents, uploads, KB rows of its own `source`, events, `^OcuTalonTest` nodes, the `onlineDemo` setting snapshot and restore, the runners' keys pointed and put back) and passes on a fresh environment, in either order.

**Never:**
- No edit of a Lane B file (`Core/**`, `Web/**`, `web/**`, `Data/Upload.cls`, `Data/Ownership.cls`, `Msg/Command/**`, `Test/{Core,Web}/**`, `docker/Dockerfile`), except what the ruling on Q1 grants (Design Notes). No test-setup install of `pdfplumber` or `python-docx` (Lane B's Story 34.2 pins them in the image).
- No change to `Docs.Ops` outside the Text seam (the `Text` method, two parameters placed directly before it, the class-doc sentence :11-13 and `AddEval`'s doc line :211), and no change to `Docs/Store.cls`, `Docs.cls`, `Agent/Chat.cls`, `Test/Docs/{Store,Live,Turns,Chat}.cls` or `ci/units.sh` (Story 19.5's files).
- No per-session table, no `TurnToolsClass`, no online-demo add path (Story 19.5); no chip rendering (Story 20.2); no file from the chat or Telegram (Story 26.2); no OCR; no new reason code, command verb, production item, table, event, CI group or unit; no new `AD-n`.
- No edit of `release/*.sh`, `release/upgrade-harness.sh`, `release/demo-host-check.sh`, `eval/run.sh` or the IPM artifact or check scripts.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Add PDF (Integration: consumer DocumentOps reads Docs.Extract) | Local install; `AddDocument` from `web_user`, `Name` "Results runbook.pdf", `pdf`, the 2-page `Samples.PdfRunbook()` | The text comes through `Docs.Extract.Read` (its worker; `Docs.Ops` holds no Python, `Test.Docs.Python`). Ok 1 `added` with the `Ref`; the row is `indexing` with `Text` starting `## Page 1`, then `ready`; the KB rows have sections `Page 1` and `Page 2`; `Sections` matches; events `indexing` then `ready`. | none |
| Add Word | "Lab feed runbook.docx", `docx`, `Samples.DocxRunbook()` (Title, two Heading 1 sections, a table) | Sections "" (title), "Restarting the lab feed", "Checking the lab numbers"; the Title line and table rows (`a | b`) are passage text; `ready`. | none |
| File cannot be read | `PdfEncrypted()`, `PdfJunk()`, `PdfDrawing()`, `Ole("WordDocument")` sent as `docx`, `DocxDeclaring(MAXUNPACKED + 1)` | A failed row with `Reason` `encrypted`, `damaged`, `no_text`, `legacy_doc` or `contents_too_large`; one `failed` event; Ok 1 `added` with `MESSAGENOTINDEXED`; no KB row; no file left in `<temp>/ocutalon-extract/`. | none |
| Read times out at the seam | `Docs.Ops.Text(Pdf3, "pdf", .text, .reason, 2)` while a job holds the extraction lock | `reason` `timed_out`, `text` ""; one Type 3 warning that starts with `LOGEXTRACT` and holds the code | none |
| Not a PDF | The route's 10,485,760 zero bytes named `big.pdf` (`live:documents`) | `failed` / `wrong_type` (no PDF signature) | none |
| Own `## ` lines (DW-832) | A PDF page line and a Word paragraph `## Not a heading` | The stored text has `\## Not a heading`; no section "Not a heading"; a passage holds `## Not a heading`. | none |
| Content controls, nested tables (DW-831) | A .docx with a body-level `w:sdt` paragraph, an inline `w:sdt` run, a table nested in a cell and a text box; a .docx made only of content controls | Each text once, in document order (the nested table's cells inside the outer cell's text); the text box is not read; the controls-only file reads `ok`, not `no_text`. | none |
| Decompression bomb (DW-828) | `Samples.PdfBomb()`: one Flate content stream that inflates past `MAXUNPACKED` | `contents_too_large` within 15 s; the next read of `Pdf3` answers `ok:1` | none |
| One read at a time (DW-827) | A background job reads `PdfPages(40)`; the test reads `Pdf3` meanwhile; then a job that holds the lock and a read with timeout 2 | The test's read ends after the background read ends; the read that cannot get the lock answers `timed_out` in about 2 s and writes no file. | none |
| Cited (Integration: consumer ChatAgent) | Both runbooks ready; turns `[[mock:documents-pdf]]` and `[[mock:documents-word]]` through `Decide` -> `ChatAgent` | First citation `{documentRef: <pdf>, document: "Results runbook", section: "Page 2", ...}`, resp. `{..., document: "Lab feed runbook", section: "Restarting the lab feed"}`; at most 5; `Tainted` 1; the same runner job. | none |
| Not covered | Only the two files; `[[mock:documents-none]]` | No `citations` member; the reply is "None of your documents cover that." | none |
| Removed | `RemoveDocument` of the PDF, then `[[mock:documents-pdf]]` | No tool-result item and no citation has the PDF's `Ref`. | none |
| Online demo parity | `onlineDemo` 1; one session adds a `.md` and a `.pdf` | Both get the same Ok and Outcome; when added (Story 19.5), the same `OwnerRef` and `KnowledgeBase`, and the PDF's passages are in that table. | none |
| Real route | `live:documents`: `POST /v1/documents` of the PDF runbook, the Word runbook and `PdfEncrypted` | 200 `{"result":"done","ref"}` each; the list shows `ready`, `ready`, `failed|encrypted`; `DELETE` of all; the table holds no row. | the unit fails |
| Real image (AC4) | An Extractor worker on the image | `pdfplumber` 0.11.10 and `python-docx` 1.1.2, each imported from `/usr/irissys/mgr/python/` | none |

</intent-contract>

## Code Map

Line numbers are those of `OCT-epic19` at `c2912a43`.

Product (Lane A):
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls:304-338` -- the Text seam `Text(bytes, contentType, .text, .reason) As %Boolean` (ClassMethod; called by `OnAdd` :107 and `AddEval` :216): `pdf`/`docx` and any other type give `not_built` (:311-314). Class doc :11-13 names PDF and Word; `AddEval`'s doc :209-211 lists its reasons. `OnAdd` :108-110 writes the failed row (`Reject`) and answers Ok 1 `added` + `MESSAGENOTINDEXED`. `IndexBatch` :170 calls `Passages.Split(text, row.ContentType, ...)`, so the row's type reaches the splitter. `$$$LOGWARNING` + `Bridge.Redact.Text` is the warning form (:86).
- `src/ocutalon/cls/OcuTalon/Docs/Passages.cls:23,29-31,34,49,55` -- `TYPES` "markdown,text", the refusal, `markdown = (contentType = "markdown")`, the `## ` section rule and the `\## ` escape; doc :1-11.
- `src/ocutalon/cls/OcuTalon/Docs/Extract.cls:69-105` -- `Read`: type and size first (no worker, no file), `Purge`, the file, `Extractor.Submit("Read", timeout, ...)` :96, the delete :103; `TIMEOUT` 120 :27, `MAXUNPACKED` :24, `CODES` :37; doc :1-13.
- `src/ocutalon/cls/OcuTalon/Docs/Extractor.cls:24-46` -- the work item passes `maxUnpacked` to `extract()`; no change.
- `src/ocutalon/python/ocutalon_extract.py` -- `_finish` :35-44; `_read_pdf` :47-75 (page loop, `page_marker`, exceptions; `max_unpacked` not passed today); `_read_docx` :88-156 (`iter_inner_content` :110, table rows and the merged-cell rule :111-123, paragraphs and `_heading_prefix` :124-129); `extract` :159-185 (`max_unpacked` goes to docx only).
- `src/ocutalon/cls/OcuTalon/Memory/Worker.cls` -- `Submit` (timeout, `STOPONTIMEOUT` `Clear(0)`, `ReleaseGroupLocks`): read only.
- `src/ocutalon/cls/OcuTalon/Docs/Store.cls:160-171` -- `DocumentName` already drops `.pdf`/`.docx`: read only ([19.5]'s file).

Tests (Lane A):
- `src/ocutalon/cls/OcuTalon/Test/Docs/Ops.cls:14,352-364` -- `TestNotBuilt` and its doc line pin `failed|not_built` for `pdf`/`docx`: removed. Its private helpers `Add` :116, `Row` :141, `WaitState` :147, `Events` :166 are the pattern for the add-path tests.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Turns.cls:48-96,127-218,250-293,381-414` -- the turn template (Private helpers `Ready`, `AddDocument`, `Turn`, `Data`, `ToolResult`, `AssertSteps`, `SameJob`, `DropDocuments`; `TestCovered`, `TestRemoved`, `Holds`): read only ([19.5]).
- `src/ocutalon/cls/OcuTalon/Test/Docs/Passages.cls:148-156` -- `TestWrongType` lists `pdf` and `docx` among refused types.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Samples.cls:65,92-145,194,215,236,260-283` -- `TextPage`, `Pdf(.pages, count, padTo, encrypt)` (uncompressed streams), `PdfEncrypted`, `PdfPages`, `Zip`, `Paragraph`, `Table`, `Docx(body, ...)`.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Extract.cls:242-290` -- `GroupLocks` and `InWorker`: a test-class work item submitted to the Extractor (`Submit("##class(...).InWorker", ...)`) is the way to read Python facts in a worker.
- `src/ocutalon/cls/OcuTalon/Test/Memory/Fixture.cls` -- `OnImage`, `Prepare`/`Restore`; `src/ocutalon/cls/OcuTalon/Test/Core/InProduction.cls:100` (Lane B, extended only) -- `Guard`, `Session`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` (Epic 11 contended, read only) -- `PointKeys`, `RestoreKeys`, `KeysAre`, `NewRequest`, `Run`, `FindRequests`, `ToolResults`, `StepProblems`, `Jobs`, `SessionMark`, `DropSince`, `DeleteSteps`.

Mock, live unit, docs:
- `ci/mock/scenarios/A/documents-runbook.json` -- the scenario form; `ci/mock/test/constants.test.mjs:152-158` checks named scenarios only (no edit).
- `docker/tests/test-documents.sh:13-15,305-342,346-368` -- step 4 (`failed|not_built` at :328-331, `doc_count` 3 at :338), step 5 deletes; helpers `api_send` :45, `upload_body` :57, `doc_state`/`doc_is` :67-78, `run_class`/`check_live` :81-106, `iris_script`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:687-705` -- AD-21: "Names" (failed-row codes), "Adding and removing" ("`DocumentOps`' failed rows use `unreadable`, `not_built` ... or `failed`"), "PDF and Word (Story 19.6)".
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md:979,1138` and `_bmad-output/planning-artifacts/epics.md:476` -- DW-719's targets (Epic 40 has merged into this branch).

Lane B, read only (evidence):
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:41` (`TIMEOUT` 120), `Web/Documents.cls:26,33` (`FILEMAX`, `EXTENSIONS` with `.pdf:pdf,.docx:docx`), `docker/Dockerfile:22` (pip `--target /usr/irissys/mgr/python`).
- `web/src/app/documents/documents-view.ts:33-40` -- `REASON_TEXTS` knows `wrong_type`, `too_large`, `empty`, `unreadable`, `not_built`, `failed`; `reasonText` reads any other code as `failed` (Q1). Pins: `web/scripts/documents-view.test.mjs:38`, `web/scripts/ux-strings.test.mjs:679`.

File footprint (every file this story creates or edits; `[19.5]` = Story 19.5's Code Map lists it too):
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` (edit) [19.5]
- `src/ocutalon/cls/OcuTalon/Docs/Passages.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Docs/Extract.cls` (edit)
- `src/ocutalon/python/ocutalon_extract.py` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Docs/Files.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls` (new)
- `src/ocutalon/cls/OcuTalon/Test/Docs/Samples.cls` (edit)
- `src/ocutalon/cls/OcuTalon/Test/Docs/Ops.cls` (edit) [19.5]
- `src/ocutalon/cls/OcuTalon/Test/Docs/Passages.cls` (edit)
- `ci/mock/scenarios/A/documents-pdf.json` (new)
- `ci/mock/scenarios/A/documents-word.json` (new)
- `docker/tests/test-documents.sh` (edit)
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` (edit) [19.5]
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` (edit; contended with Epic 17, Q2)
- `_bmad-output/planning-artifacts/epics.md` (edit, the UX-DR144 line only)
- `_bmad-output/implementation-artifacts/evidence/19-7-task0-files.md` (new)
- Only if Q1 is ruled (a): `web/src/app/documents/documents-view.ts` (edit, Lane B grant), `web/scripts/documents-view.test.mjs` (edit, Lane B grant), `web/scripts/ux-strings.test.mjs` (edit, Lane B grant)

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first; product default 5). One fresh lane-C throwaway, `OCUTALON_RUN_TAG=e19s7i0`, the Verification lane variables, `OCUTALON_LOCK_OWNER='epic=19 stage=implement'`, with this story's classes and resource loaded. Record in `_bmad-output/implementation-artifacts/evidence/19-7-task0-files.md`, then `ci/iris.sh teardown`.
  - M1 (DW-828): the source of pdfminer.six 20260107's Flate decoding (`inspect.getsource` in an Extractor worker): whether every Flate decode, `decompress_corrupted` included, goes through the module attribute `zlib` of `pdfminer.pdftypes`; `PdfBomb()`'s read time and the worker's peak memory without the bound (timeout 30) and with it; the decoded bytes of `PdfRunbook()` and `PdfPages(200)`.
  - M2 (DW-831): what python-docx 1.1.2 gives for `DocxContentControls()` (`iter_inner_content`, `cell.text`, `paragraph.text`), and that the new walker reads each text once with no text-box duplicate.
  - M3: the `Commands.Submit` answer time of the PDF and Word runbooks, and two simultaneous reads with and without the lock.
  - M4: the scores of the scenario queries against the PDF page-2 passage and the Word "Restarting the lab feed" passage (each at least `CITEFLOOR` 0.4, else change the sample text), and the PDF query's best score on the Word file's passages.
  - Stop rule: HALT `blocked` / `intent gap` with the measurement, naming AD-21 ("PDF and Word", `TIMEOUT` with `Clear`) and AD-6, when neither the bounded `zlib` stand-in nor the fallback (Design Notes) stops `PdfBomb()` before 15 s.
- `src/ocutalon/python/ocutalon_extract.py`:
  - (DW-832) every line of a file's own text that starts with `## ` (PDF page text, Word paragraphs, table rows, content controls) is written `\## ...`; the page marker and Heading 1 lines are the only `## ` lines. Escape before the size count.
  - (DW-828) `_read_pdf(path, limit, max_unpacked, page_marker)`: for the read, `pdfminer.pdftypes.zlib` is a bounded stand-in (`decompress`, `decompressobj`, `error`, `MAX_WBITS`) whose every call asks zlib for at most the remaining budget plus one byte (`decompressobj().decompress(data, max_length)`) and raises a private error past it; the module is put back in a `finally`. The private error is not a `zlib.error`, so pdfminer's own fallback (`decompress_corrupted`, or an empty stream) never swallows it, and `_read_pdf` maps it, bare or wrapped in pdfplumber's `PdfminerException`, to `contents_too_large`. The budget is `max_unpacked` per file. `extract` passes `max_unpacked` to the PDF path too.
  - (DW-831) the .docx body is read by one walker over block content in document order: `w:p` (a python-docx `Paragraph`), `w:tbl` (a `Table`), `w:sdt` (its `w:sdtContent`, recursively), for the body, a cell and a content control alike. A paragraph's text is its runs, the runs of its hyperlinks and the runs of its inline content controls (nested ones included), in order, read with python-docx's `Run.text`; text boxes (`w:txbxContent`) are not read. A cell's text is its blocks' texts joined by a space; a nested table gives its cells' texts in row order, joined by a space (the merged-cell rule kept). Headings, the table row form (` | `) and every existing sample's output are unchanged.
  - ASCII, a docstring stating the contract; no network, no file write, no user text.
- `src/ocutalon/cls/OcuTalon/Docs/Extract.cls` -- (DW-827) `Read` takes the lock `^OcuTalon.Docs.Extract` (`Lock +...:timeout`) after the type and size checks and before `Purge`; a lock not got in time answers `timed_out` with no file and no worker; the work item gets the time that is left (at least 1 s); the lock is released on every path. Class doc: one read at a time on the instance, and the lock wait counts within `timeout`.
- `src/ocutalon/cls/OcuTalon/Docs/Passages.cls` -- `TYPES` "markdown,text,pdf,docx"; `pdf` and `docx` are read as `markdown` (their `## ` lines open sections, `\## ` is a passage line); doc :1-11 says so (the text that `Docs.Extract` writes).
- `src/ocutalon/cls/OcuTalon/Docs/Ops.cls` -- the Text seam only:
  - Directly before `Text`: `Parameter EXTRACTWAIT = 45;` (seconds a read may take, lock wait included, inside `CommandsIn`'s 120) and `Parameter LOGEXTRACT = "DocumentOps could not read a file: ";` (developer-facing).
  - `Text(bytes, contentType, Output text, Output reason, wait As %Integer = {..#EXTRACTWAIT})`: `pdf`/`docx` -> `##class(OcuTalon.Docs.Extract).Read(bytes, contentType, wait)`: `ok` gives `text`; otherwise `reason` is the answer's code, and `failed` or `timed_out` logs one warning `LOGEXTRACT` + the code and the redacted detail. A type that is none of the four gives `wrong_type`. `markdown`/`text` unchanged. Callers keep passing four arguments. Its doc comment states this.
  - Class doc :11-13: a pdf or docx document is read by `Docs.Extract` (in its worker) and indexed like Markdown; a file it cannot read is a failed row with its code. `AddEval`'s doc :211 adds "or a reason of Docs.Extract".
- `src/ocutalon/cls/OcuTalon/Test/Docs/Samples.cls` -- (append) `PdfRunbook()` (page 1 "Results runbook" and an intro line; page 2 "Rotating the Results certificate" and the three steps of the Markdown runbook), `DocxRunbook()` (Title "Lab feed runbook"; Heading 1 "Restarting the lab feed" with two steps; Heading 1 "Checking the lab numbers" with a 2x2 table), `PdfHashLine()`, `DocxHashLine()`, `DocxContentControls()`, `DocxOnlyControls()`, `PdfBomb()` (a `/Filter /FlateDecode` content stream built by hand: zlib header, one fixed-Huffman block of one literal and length-258/distance-1 copies, each copy 13 bits, so 8 copies are a repeating 13-byte pattern; about 1 MB that inflates to about 160 MB; end-of-block and Adler-32), and their `Expected*` texts. ObjectScript only, no copyrighted text.
- `src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls` (new; skips off-image like `Test.Docs.Extract`) -- `TestEscapedLines` (DW-832), `TestContentControls` (DW-831, both samples), `TestBombStops` (DW-828), `TestOneReadAtATime` (DW-827: a `Job` of a class method of this class reads `PdfPages(40)` and records its `$ZHorolog` start and end in `^OcuTalonTest`; the test waits for the lock owner, reads `Pdf3` and asserts its end is after the job's end; then a job holds the lock and `Read(Pdf3, "pdf", 2)` answers `timed_out` in under 6 s with no file), `TestImagePackages` (AC4: a test-class work item in the Extractor reports the two distributions' versions and folders). Each test removes its jobs' nodes and waits for its jobs to end.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Files.cls` (new; extends `OcuTalon.Test.Core.InProduction`; skips off-image) -- through the production, `Commands.Submit` as `web_user`: `TestAddPdf`, `TestAddWord`, `TestFileFailures` (the matrix row, each code, events, no KB row, no temporary file), `TestSeamTimeout` (the matrix row "Read times out at the seam"; the warning read from `Ens_Util.Log` after a mark, its rows removed), `TestCited`, `TestNotCovered`, `TestRemoved` (turns through `RunnerFixture.Run` on the CI mock; citations, tool results judged by the test's own `source`, `Tainted`, `StepProblems`, same job), `TestOnlineDemoParity`. Helpers follow `Test.Docs.Turns` and `Test.Docs.Ops` (copy with reason, Design Notes).
- `src/ocutalon/cls/OcuTalon/Test/Docs/Ops.cls` -- remove `TestNotBuilt` (:352-364) and its doc line (:14); nothing else.
- `src/ocutalon/cls/OcuTalon/Test/Docs/Passages.cls` -- `TestWrongType` lists `""`, `"html"` and `"text/plain"`; new `TestExtractedText`: `pdf` and `docx` texts section on `## Page n` / `## <heading>` lines, `\## ` is a passage line, a `# ` Title line is passage text.
- `ci/mock/scenarios/A/documents-pdf.json` (`documents` `{"query":"how do I rotate the Results certificate?"}`, then "The CI mock answered from the PDF runbook.") and `documents-word.json` (`{"query":"how do I restart the lab feed?"}`, then "The CI mock answered from the Word runbook.") (new).
- `docker/tests/test-documents.sh` -- header; step 1 also checks, once each and word for word, DW-719's two lines in `EXPERIENCE.md` and the UX-DR144 wording in `epics.md` (as it checks the ruled lines of `docs/`); step 4's `.pdf` of zeros ends `failed|wrong_type`; new step 4b: an `iris_script` prints the base64 of `Samples.PdfRunbook()`, `DocxRunbook()` and `PdfEncrypted()` (`CHK|` lines, nothing written to disk), each is posted as `{name, content}` ("Results runbook.pdf", "Lab feed runbook.docx", "locked.pdf"), 200 done, then `ready|`, `ready|` and `failed|encrypted` within 120 s; `doc_count` 6; step 5 deletes all six; `INFO` lines for the seconds.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions in AD-21 marked `[AMENDED 2026-11-08, Story 19.7, ...]`: the "PDF and Word" bullet (DocumentOps' Text seam, `EXTRACTWAIT`, pdf/docx read as Markdown, one read at a time by the lock, the Flate budget, content controls and nested tables, the `\## ` escape) and the "Adding and removing" sentence (failed rows also use the extraction codes). Lint after; no new finding.
- DW-719 (owner ruling U-279; Epic 40 merged): `EXPERIENCE.md:979` "accepting Markdown and plain text, then PDF and Word from step 6." -> "accepting Markdown, plain text, PDF and Word (.docx) files."; `EXPERIENCE.md` Assumptions, after :1138, the line "- On a local install, memories belong to each user and documents are shared by every user of the install (P23)."; `epics.md:476` "(picker or drag-and-drop; Markdown, plain text; PDF, Word from S6)" -> "(picker or drag-and-drop; Markdown, plain text, PDF and Word (.docx) files)".
- Only if Q1 is ruled (a): `web/src/app/documents/documents-view.ts` `REASON_TEXTS` gains the six codes with the texts under Design Notes, `web/scripts/documents-view.test.mjs` pins them, `web/scripts/ux-strings.test.mjs` gives each its ruling source.

**Acceptance Criteria:**
- Given a PDF or Word file added from the Documents page (the real route, `live:documents`) or through `Commands.Submit` as `web_user`, when `OcuTalon.Docs` indexes it, then its text comes from the Extractor worker, it joins the instance's knowledge base like a Markdown document, split by pages (`Page n`) or Heading 1 sections, and its status becomes `ready`, or `failed` with the extraction's reason code, which the Documents page shows as its reason (Q1).
- Given a question answered from a PDF or Word document, when the reply is built, then `HostData.citations` names each cited document and section (at most 5 passages per search, at most 5 citations), and with no relevant passage the reply carries no citation and says "None of your documents cover that.".
- Given the CI mock scenarios under `ci/mock/scenarios/A/`, when a PDF runbook and a Word runbook are added and asked about and the PDF is then removed, then each answer cites the right document and section, and the removed PDF is cited no more.
- Given the image with `pdfplumber==0.11.10` and `python-docx==1.1.2` pinned by Story 34.2, when Story 19.6's `Test.Docs.Extract`/`ExtractEdges` and this story's classes run on the IRIS runner, then they run on that image with no test-setup install, with no SKIP, and pass.
- Given the online demo, when a session adds a PDF and a Markdown file, then both are handled alike (`not_built` today; the session's own table once Story 19.5 has merged).
- Given two simultaneous reads, a decompression bomb, a Word file of content controls and nested tables, or a file line `## ...`, when extraction runs, then reads run one at a time, the bomb answers `contents_too_large` in under 15 s, every text is read once, and the line stays a passage line (DW-827, DW-828, DW-831, DW-832).
- Given DW-719's owner-ruled text, when a reader opens EXPERIENCE.md's Step 3 Documents or UX-DR144, then adding accepts "Markdown, plain text, PDF and Word (.docx) files." and the Assumptions hold the local-install ownership line.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions:** AD-1 (synchronous add answer), AD-4 (owner `instance`), AD-5 (rows survive), AD-6 (Python only in the Extractor worker), AD-10 (document results untrusted, unchanged), AD-12 (`document` event), AD-21 ("Documents (step 3)", "PDF and Word"), AD-22 (Test areas, mock scenarios under `A/`), AD-23 (image pins, no test-setup install), AD-29 (Lane A files), AD-33 (DocumentOps the single writer; `OcuTalon.Docs` owns the tables). No AC contradicts an AD; no NFR is unmeasurable.

**Integration ACs:** matrix rows "Add PDF" (consumer `DocumentOps` reads `Docs.Extract`, effect: a `ready` row and KB rows with page sections) and "Cited" (consumer `ChatAgent`, effect: `HostData.citations`), both on the real production and worker, no double; "Real route" through `live:documents`.

**Consumes:** 19.6 (`Docs.Extract.Read`, its codes, markers, limits and samples), 19.4 (the Text seam, `Passages.Split`, `IndexBatch`, `Store`, `Bridge.Citations`, the turn-test pattern, `live:documents`), 34.2 (the route's `pdf`/`docx` types and the image pins), 19.5 (per-session tables, for the demo clause).

**Consumed-by:** 20.2 (chips such as "Results runbook (section sign) Page 2"), 25.3 (a file reply's **Add to documents**: the same `AddDocument`), 26.2 (chat and Telegram files: `Docs.Extract`'s one-read-at-a-time lock and `Failure(code)`).

**Extend, don't copy:** the Text seam calls `Docs.Extract.Read` and the rest is 19.4's `IndexBatch`/`Passages`; `Passages` gains two type names, not a second splitter; the bound, the escape and the walker extend `ocutalon_extract.py`; the tests reuse `Samples`, `InProduction`, `RunnerFixture`, `Memory.Fixture` and the `InWorker` probe. Copy with reason: `Test.Docs.Files` copies `Test.Docs.Turns`' private turn helpers (`Ready`, `Turn`, `Data`, `ToolResult`, `AssertSteps`, `SameJob`) and an `AddDocument` that takes bytes and a type, because they are Private and `Test/Docs/Turns.cls` is in Story 19.5's Code Map; the Epic 19 burn-down can lift them into one fixture.

**Decided in-stage:**
- Extraction stays synchronous at the Text seam (the lead's "keep the Docs.Ops change to the Text seam"); `EXTRACTWAIT` 45 s, so two worst-case adds queued on `DocumentOps` (pool 1) still answer inside `CommandsIn`'s 120 s. Measured (19.6): 200,000 characters of dense text are read in about 2.5 s on ARM.
- A lock not got in time is `timed_out` (no new code). The lock name `^OcuTalon.Docs.Extract` is apart from 19.5's `^OcuTalon.Docs(<owner>)` locks.
- The PDF Flate budget is `MAXUNPACKED` (100 MB, the .docx guard) with the code `contents_too_large`. Fallback if M1 shows a `zlib` call the stand-in cannot reach: a pre-pass over the file's `stream ... endstream` ranges with `/FlateDecode`, each inflated through `decompressobj().decompress(data, budget)` before pdfplumber opens the file (encrypted streams are skipped: inference).
- A file's own line that starts with `\## ` is left as it is: the splitter shows it without its backslash and opens nothing (harmless).
- Word: table rows wrapped in a content control (repeating sections) stay out, as python-docx's `rows` gives them (residual, recorded in the evidence).
- A content type other than the four gives `wrong_type` (no caller sends one).
- `live:documents` checks the real route for PDF and Word (ready, encrypted, delete); citations are pinned in-stack by `Test.Docs.Files` (`chat.message` carries no citations until Story 20.2).
- `TestOnlineDemoParity` is falsifiable only once Story 19.5 has merged (both answers are `not_built` before): its `mutation:` line is recorded by whichever of 19.5 and 19.7 is integrated second.

**Ledger inbox:**
- DW-719: addressed (task "DW-719", AC7), text exactly as ruled.
- DW-827: addressed (the lock in `Docs.Extract.Read`, matrix "One read at a time"); AD-21's "one worker" now holds for simultaneous callers, so no wording amendment.
- DW-828: addressed (the bounded `zlib` stand-in, matrix "Decompression bomb").
- DW-831: addressed (the walker, matrix "Content controls, nested tables").
- DW-832: addressed (the escape in `ocutalon_extract.py`, matrix "Own `## ` lines").
- Declined DW-894: PDF and Word text is cut at `MAXTEXT` (200,000 characters), so a file is at most about 200 to 300 passages, ready in about 1 to 2 minutes at the measured 0.33 s each (inference); the batching seam is `Docs.Store.Write`'s per-passage embed loop, which Story 19.5 rewrites for per-session tables, so it belongs after 19.5 (recommended owner: the Epic 19 burn-down, one Embedder work item per Index batch).

**Shared with Story 19.5 (3 files):** `Docs/Ops.cls` (the `Text` method :304-338 and two parameters directly before it, the class-doc sentence :11-13 and `AddEval`'s doc :211; 19.5 edits `OnAdd`, `NewRow`, `IndexBatch`, `Fail`, `OnRemove`, `AddEval`'s body, `Publish` and the class doc's online-demo sentence :9-10, so the class doc and `AddEval`'s doc are the two places a merge may meet), `Test/Docs/Ops.cls` (only `TestNotBuilt` and doc line :14 removed; 19.5 edits `TestOnlineDemo` and doc :18), and the spine (separate AD-21 unions). Nothing else of 19.5's footprint is touched, so the two can run on two runners and merge as plain unions (recommendation; the lead decides).

**Contended files:** checked 2026-11-08 05:09Z after `git fetch` (`git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<M>`): Epic 11's diff is empty; Epic 31 has no branch; Epic 17's diff holds `EXPERIENCE.md` (17.10's hunk at :966-969), `epics.md` (its own blocks, near :6316 of the feature's copy) and the spine. This story touches `EXPERIENCE.md` (Q2), `epics.md` (the UX-DR144 line only) and the spine (plain unions); no other contended file. `Test/Agent/RunnerFixture.cls` (Epic 11) is read only.

**CI:** no new unit and no `ci/units.sh` edit. `Test.Docs.Files` and `Test.Docs.ExtractMore` join `shard:lane-a@rest` (group `shards-2`): about 60 to 90 s on x64 (inference: about 25 s on ARM times 3), so `shards-2` goes from 1,807 s (ci run 42445320545) to about 1,900 s; with Story 19.5's four classes and `live:session-data` (about 360 s by its plan) about 2,260 s, over 35 minutes, which 19.5 alone already reaches (about 2,170 s): a rebalance for the lead before the second of the two merges. `live:documents` (group `shards-3`, 1,976 s with the unit at 330 s) gains step 4b, about 30 to 50 s on x64 (inference), so `shards-3` about 2,010 to 2,030 s (under 35 minutes by about 70 s).

**PUBLIC TEXT needed:**
- Only if Q1 is ruled (a): the Documents page's six reason texts, the Planner's A1 reasons with the page catalog's final period (the period is the new part): `contents_too_large` "its text is too long to read.", `encrypted` "it's protected with a password.", `damaged` "it's damaged or incomplete.", `no_text` "it has no text to read, for example a scanned PDF without a text layer.", `legacy_doc` "it's an old Word file (.doc); save it as .docx and try again.", `timed_out` "reading it took too long.", each shown in the page's frame "Couldn't read it: {reason}".
- Not public: `LOGEXTRACT` and the mock scenarios' reply texts (developer-facing and CI-only).

**Questions for the lead (the blocking condition):**
- Q1 (Lane B, U-177). `web/src/app/documents/documents-view.ts` `REASON_TEXTS` reads every code it does not know as `failed`, so an encrypted, damaged, text-less, legacy `.doc`, too-long or too-slow file would show "Couldn't read it: something went wrong inside OcuTalon." instead of its reason (AC1 "or shows the failure reason"). Options: (a, recommended) a U-177 grant scoped like 19.4's Q4: the six entries above in `REASON_TEXTS`, their pins in `web/scripts/documents-view.test.mjs` and source rows in `web/scripts/ux-strings.test.mjs`, nothing else; (b) a Lane B story adds them, and until it merges the page shows the `failed` text for those codes (moves part of an AC: owner or veto); (c) `DocumentOps` stores `unreadable` or `failed` instead of the extraction codes (lossy and partly untrue: "OcuTalon found no text in it." for an encrypted file; not recommended).
- Q2 (contended path). DW-719's two edits of `EXPERIENCE.md` (:979 and one line after :1138) touch a file that Epic 17's open diff edits at :966-969. Recommended: a plain union (no overlapping or adjacent lines).

## Verification

Lane variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=implement'`. Every command runs in the foreground with `timeout: 600000` and is sized to about 150 s; if one is moved to the background, poll its output file in foreground loops under 150 s each and never start a second copy. One `iris_execute_tests` per message; `server` `ocutalon-slot-c` and namespace `OCUTALON` on every IRIS MCP call (check `iris_server_info` first). Targets: warm `e19s7iw`, fresh `e19s7i` (live unit, shard parts), `e19s7i0` (Task 0). A `.py` change refuses a warm run (`ci/warm.sh down`, then `up`); after a `Docs.Ops` change restart the `DocumentOps` item on the warm stack before a run, or it is a false green. The slot is used only for `iris_doc_load` compile checks (`Test.Docs.*` skip there).

**Commands:**
- `iris_doc_load` of the changed classes with `baseDir` `.../src/ocutalon/cls` on `ocutalon-slot-c` / `OCUTALON` (loop) -- expected: compiled, no error.
- `ci/warm.sh up` with `OCUTALON_RUN_TAG=e19s7iw` (once; again after each `.py` change), and `ci/warm.sh down` at the end and after a failure (once) -- expected: up, then torn down.
- `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s7iw ci/iris.sh class <C>` (loop), one call each, for C in `OcuTalon.Test.Docs.` `ExtractMore`, `Files`, `Passages`, `Ops`, `Extract`, `ExtractEdges`, `Python`, `Turns`, `Store`; `OcuTalon.Test.Eval.Documents`; `OcuTalon.Test.Bridge.CodeRules` -- expected: `CLASS ... passed`, no SKIP.
- `OCUTALON_LIVE_DEADLINE=1200 OCUTALON_RUN_TAG=e19s7i ci/iris.sh live documents` (once, again after a change it covers), then `ci/iris.sh teardown` with that tag -- expected: every PASS, `test-documents: all checks passed`.
- `OCUTALON_RUN_TAG=e19s7i ci/iris.sh shard lane-a --part k/12` for each k whose part holds a `Test.Docs.*` class (list them with `ci/iris.sh classes lane-a`), one call each (once) -- expected: every class passed on a fresh stack.
- `bash docker/tests/test-<n>.sh` for n = `class-rules`, `boundaries`, `ci-config`, `mock`, one call each (once) -- expected: PASS.
- `node --test web/scripts/ux-strings.test.mjs web/scripts/host-pages.test.mjs` (once, after the EXPERIENCE.md edit; with `web/scripts/documents-view.test.mjs` if Q1 is (a)) -- expected: pass.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once, before and after the spine edit) -- expected: no new finding.
- CI after the lead's push: record `iris (shards-2)` and `iris (shards-3)` seconds; `Test.Docs.Extract`, `ExtractEdges`, `ExtractMore` and `Files` pass with no SKIP (AC4).

**Mutations (one per AC; apply from a backup in the stage's scratch folder, observe red, revert, confirm `git status --short` and `git diff --stat` unchanged):**
- AC1: `Text` answers `not_built` for `pdf` again -> `Test.Docs.Files` TestAddPdf and TestAddWord red, and `live:documents` step 4b red; `Passages.TYPES` without `pdf` -> TestAddPdf red (failed/failed) and `Test.Docs.Passages` TestExtractedText red; `Text` maps every extraction code to `failed` -> TestFileFailures red; (Q1 a) `REASON_TEXTS` without `encrypted` -> `web/scripts/documents-view.test.mjs` red.
- AC2: `Text` keeps the extraction text but strips its `## ` marker lines -> TestCited red (section "" instead of "Page 2"); the `LOGEXTRACT` warning removed -> TestSeamTimeout red.
- AC3: `DocumentOps.OnRemove` skips `Store.Remove` (19.4's path, run after a restart of the item) -> TestRemoved red (the removed PDF is cited again); the Word sample's "Restarting the lab feed" written as Heading 2 -> TestCited red (section).
- AC4: a stand-in `pdfplumber` with `__version__` "0.0.0" put first on the worker's `sys.path` by the test's own work item -> TestImagePackages red.
- AC5: recorded by whichever of 19.5 and 19.7 is integrated second (Design Notes): `Text` answers `not_built` for `pdf` when `onlineDemo` is 1 -> TestOnlineDemoParity red.
- AC6: the lock removed from `Read` -> TestOneReadAtATime red; the bounded stand-in not installed -> TestBombStops red (`timed_out` or over 15 s); the escape removed -> TestEscapedLines red; the walker replaced by `iter_inner_content` -> TestContentControls red.
- AC7: "PDF and Word (.docx) files." -> "PDF and Word files." in `EXPERIENCE.md` -> `live:documents` step 1 red.

**Shared surfaces:** `Docs.Ops.Text`'s answer for `pdf`/`docx` (`Test.Docs.Ops` TestNotBuilt, removed; `live:documents` step 4); `Passages.TYPES` (`Test.Docs.Passages` TestWrongType); the output of `ocutalon_extract.py` for every existing sample (`Test.Docs.Extract`, `ExtractEdges`); the Extractor's concurrency (no test reads concurrently today); the rows of `OcuTalonKB.Docs` (tests judge only their own `source`); the `documents` list count of `live:documents`; the `A/` scenario names (`ci/mock/test/constants.test.mjs`, names only); the strings of `EXPERIENCE.md` (`web/scripts/ux-strings.test.mjs`, `host-pages.test.mjs`); `REASON_TEXTS` if Q1 is (a) (`documents-view.test.mjs`, `ux-strings.test.mjs`).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: Q1 (Lane B, U-177): the Documents page's reason catalog `web/src/app/documents/documents-view.ts` `REASON_TEXTS` (Lane B) reads every code it does not know as `failed`, so after this story an encrypted, damaged, text-less, legacy .doc, too-long or too-slow PDF or Word file would show "Couldn't read it: something went wrong inside OcuTalon." instead of its reason (AC1 "or shows the failure reason"); recommended (a): a U-177 grant scoped to six `REASON_TEXTS` entries (`contents_too_large`, `encrypted`, `damaged`, `no_text`, `legacy_doc`, `timed_out`) with the Planner's A1 reasons plus the catalog's final period (PUBLIC TEXT), their pins in `web/scripts/documents-view.test.mjs` and source rows in `web/scripts/ux-strings.test.mjs`, nothing else; alternatives (b) a Lane B story (the page shows the `failed` text for those codes until it merges) or (c) store `unreadable`/`failed` instead of the extraction codes (lossy, not recommended). Q2 (contended path): DW-719's two edits of `EXPERIENCE.md` (the Step 3 Documents 'Adding' bullet at :979 and one Assumptions line after :1138) touch a file that Epic 17's open diff (17.10) edits at :966-969; recommended: a plain union (no overlapping or adjacent lines).

**Plan state.** The plan is complete under the recommended rulings (Q1 (a), Q2 plain union): every task, the matrix, the mutations and the Verification commands are written for them, and the "Only if Q1 is ruled (a)" items drop out under (b) or (c) (under (c) the Text seam also maps the codes, and AC1's reason clause and its `documents-view.test.mjs` mutation change). Once both are ruled, the lead can record the rulings under Design Notes and set `status: ready-for-dev`; no re-plan is needed unless Q1 is ruled (c). The READY-FOR-DEVELOPMENT check otherwise passed: every task names a file and an action, the tasks are in dependency order (Task 0, the resource, `Docs.Extract`, `Passages`, the Text seam, samples, tests, mock, live unit, spine, docs), every AC is Given/When/Then and observed at the outermost surface available today (the real route, `HostData.citations` of a real turn, the worker on the image), and nothing else is open.

**Footprint shared with Story 19.5:** 3 files (`Docs/Ops.cls`, `Test/Docs/Ops.cls`, the spine), each in hunks apart from 19.5's (Design Notes "Shared with Story 19.5"). No `ci/units.sh` edit and no new CI unit; `shards-2` needs the lead's rebalance before the second of 19.5 and 19.7 merges (Design Notes "CI").

**Context note.** `epic-19-context.md` (committed 2026-11-07 20:09 local) is older than `epics.md` (19.5's planning amendment, 20:46); it was reused as the dispatch ordered, and this story's block in `epics.md` was read directly for the ACs and the ledger bullets.
