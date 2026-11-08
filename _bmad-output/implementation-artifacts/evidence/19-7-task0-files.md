# Story 19.7 Task 0: Flate decoding, content controls, add and lock timings, scores

Measured 2026-11-08 by the Epic 19 lane-B runner (implement stage) on one warm lane-B throwaway (`OCUTALON_RUN_TAG=e19bs7i0`, started with `ci/warm.sh up` so that it could be entered between calls, removed with `ci/iris.sh teardown`): the AI Hub build 154 base image, Python 3.12.3, aarch64, pdfplumber 0.11.10, pdfminer.six 20260107, python-docx 1.1.2. The image was built from this worktree with the story's `ocutalon_extract.py` and `Test.Docs.Samples`. The probes (a few Python one-liners run with the image's `python3` and `PYTHONPATH=/usr/irissys/mgr/python`, and two scratch classes `ZzM3.*` loaded into the throwaway only) are not part of the product. Evidence only.

## Result against the stop rule

The stop rule (neither the bounded `zlib` stand-in nor the fallback stops `PdfBomb()` before 15 s) does NOT hold: the stand-in refuses `PdfBomb()` as `contents_too_large` in 0.26 s. The fallback (a pre-pass over the file's streams) is not needed. AD-21 ("PDF and Word", `TIMEOUT` with `Clear`) and AD-6 stand as written.

## M1 (DW-828): Flate decoding in pdfminer.six 20260107

- Source (`grep -rn zlib` over `pdfminer/` and `pdfplumber/` in `/usr/irissys/mgr/python`): the only module that names `zlib` is `pdfminer/pdftypes.py`, as the module attribute `zlib` (`import zlib`, line 3). Its three uses are `decompress_corrupted` (`zlib.decompressobj()`, `d.decompress(buffer)` one byte at a time, `except zlib.error`), `PDFStream.decode` (`zlib.decompress(data)`) and the `except zlib.error` handlers around it (one falls back to `decompress_corrupted`, the other to an empty stream). So every Flate decode, `decompress_corrupted` included, goes through `pdfminer.pdftypes.zlib`, and a stand-in that offers `decompress`, `decompressobj`, `error` and `MAX_WBITS` covers all of it. An error that is not a `zlib.error` is not swallowed by either handler.
- `PdfBomb()` (1,040,612 bytes; one Flate content stream of 1,040,010 bytes that inflates to 165,120,259 bytes of `A`; the stream was checked with the Python `zlib` module on the dev slot: all 165,120,259 bytes come out and the end of the stream with its Adler-32 is reached):
  - without the bound (pdfplumber alone, timeout 30): killed at 30 s, not finished; the process was at 242 MB after 1 s, 300 MB after 13 s and 324 MB after 22 s (still growing);
  - with the bound (`ocutalon_extract.extract`, `max_unpacked` 104,857,600): `contents_too_large` in 0.26 s; peak resident size of the process 231 MB (the imports included); 104,857,601 bytes inflated (the budget plus the one byte that proves the excess).
- Decoded bytes through the stand-in: `PdfRunbook()` 0 and `PdfPages(200)` 0 (their content streams carry no `/Filter`); both read as before (`PdfPages(200)` 199,987 characters cut, 3.14 s). The stand-in is put back after the read (`pdfminer.pdftypes.zlib` is the real module again).

## M2 (DW-831): python-docx 1.1.2 on `DocxContentControls()`

- `Document.iter_inner_content()` yields `Paragraph 'Before controls'`, `Paragraph 'Inline  end'` (the inline control's run is missing), `Table [['Outer\n', 'Side']]` (the nested table is missing), `Paragraph 'Around the box'`, `Paragraph 'After the box'`: the body-level control paragraph "Body control text" is not yielded. For `DocxOnlyControls()` it yields no item at all (the old reading answers `no_text`).
- The story's walker reads, in order, `Before controls`, `Body control text`, `Inline control end`, `Outer n1 n2 | Side`, `Around the box`, `After the box`: each text once, the nested table's cells inside the outer cell, the text box ("Box text") not read; `DocxOnlyControls()` reads `Only a control` and `And another` (`ok`, not `no_text`).
- The output for the other samples is unchanged: `DocxHeadings()`, the merged-cell sample's rule and `DocxRunbook()` read as the expected texts; `DocxHashLine()` and `PdfHashLine()` write the file's own `## ` lines as `\## `.
- Residual, as the spec says: table rows wrapped in a content control (repeating sections) stay out, as python-docx's `rows` gives them.

## M3: add times and one read at a time (DW-827)

- `Commands.Submit` of `AddDocument` as `web_user` on the warm stack: `PdfRunbook()` answered Ok 1 `added` in 0.58 s, `DocxRunbook()` in 1.67 s (the first read in a new worker); both reached `ready` with 2 and 3 knowledge-base rows (`Page 1`, `Page 2`; the Title passage, "Restarting the lab feed", "Checking the lab numbers").
- Two simultaneous reads, a job reading `PdfPages(40)` and the main process reading `Pdf3()` one second later:
  - without the lock (both through `Docs.Extractor.Submit`): the small read ended 1.67 s after the big one began, before the big one's end (3.25 s), on another worker job (4185 against 4001): two worker jobs at once;
  - with the lock (`Docs.Extract.Read`): the small read ended at 3.94 s, after the big one's end (3.33 s), on the same worker job (4001).

## M4: the scores (cosine, as `Bridge.Citations` reads them; `CITEFLOOR` 0.4)

- "how do I rotate the Results certificate?" against the PDF: page 2 0.6863 (cited), page 1 0.2982; against the Word file: at most 0.1813 ("Restarting the lab feed"), so the Word file adds no citation.
- "how do I restart the lab feed?" against the Word file: "Restarting the lab feed" 0.7495 (cited, first), the Title passage 0.5126 (also at or above the floor), "Checking the lab numbers" 0.2601; against the PDF: at most 0.2990.
- "how do I reset my password?": best 0.1132 (PDF page 2), below the floor for both files.
- So the sample texts need no change; the unrelated question stays under the floor.
