# Story 19.6 Task 0: deployment of the Python resources, library behaviour, and the time limit

Measured 2026-11-06 by the Epic 19 runner (lane C) on one lane-C throwaway (`OCUTALON_RUN_TAG=e19s6i0`, the AI Hub build 154 base image, Python 3.12.3, aarch64), started with `ci/warm.sh up` so that it could be entered between calls and removed with `ci/iris.sh teardown`. The throwaway's image was built from this worktree with placeholder resources `src/ocutalon/python/ocutalon_extract.py` and `ocutalon_memory.py` (each only a `MARK` constant) and the two manifests carrying one single-file `FileCopy` per resource. The probe classes and the hand-built samples were scratch files of the stage and were copied into the container's `/tmp`; none is part of the product. Evidence only.

## Result against the stop rules

- Stop rule 1 (neither the `FileCopy` nor the fallback puts the resources on a worker's `sys.path` before the Memory step runs): does NOT hold. The primary form (a single-file `FileCopy` to `${mgrdir}python/<file>`) works on the Docker path and runs before the Configure invoke; the fallback is not needed. (M1)
- Stop rule 2 (`Clear` cannot stop a busy Python worker without harm): does NOT hold for the extraction workload. `Clear` ends a worker that is running pdfplumber, and no other caller's work is hurt. Two measured caveats go to Residual risks: `Clear` waits for a C call that does not return (a 30 s `time.sleep` held it 29 s), and the category's `MaxActiveWorkers` 1 did not serialise two concurrent reads. (M3)

Both stop rules are clear, so the story went on to product code.

## M1: deployment by the manifest `FileCopy`

- Form measured: `<FileCopy Name="ocutalon/python/ocutalon_extract.py" Target="${mgrdir}python/ocutalon_extract.py"/>` (and the same for `ocutalon_memory.py`) in `src/module.xml`; the root manifest has `src/` before `Name`. `${mgrdir}` (lower case) is understood by IPM 0.10.10.
- Docker path (after-start's `zpm load /opt/ocutalon/src`): both files landed in `/durable/iris/mgr/python/`, which is `<mgr>/python` of the durable mount (`ISC_DATA_DIRECTORY=/durable/iris`). Their md5 sums equal the image's `/opt/ocutalon/src/ocutalon/python/*`.
- A worker of each category imports them: `OcuTalon.Memory.Embedder` (job 3538) and `OcuTalon.Docs.Extractor` (job 3589) both answered `ocutalon_extract.MARK` and `ocutalon_memory.MARK`, with `__file__` in `/durable/iris/mgr/python/`. The worker's `sys.path` holds `/usr/irissys/mgr/python` (the image's pip packages: `pdfplumber` 0.11.10 and `docx` 1.1.2 imported from there) and `/durable/iris/mgr/python` (the resources).
- Order against the Configure phase: the verbose `load -verbose /opt/ocutalon/src` log reads `Activate START`, `Copying .../ocutalon_extract.py to .../mgr/python/ocutalon_extract.py`, `Copying .../ocutalon_memory.py ...`, `Configure START`, `Configure SUCCESS`, `Activate SUCCESS`. The copy is first, so the Memory step's `Download`, which runs in the Configure invoke, finds `ocutalon_memory`.
- A reinstall overwrites: with both files changed on disk (one appended to, one replaced), the same `load` restored both to the md5 sums of the image's sources.
- IPM path A of `release/ipm-install.sh` is run once at the end (Verification). Two of the four facts were measured there for the plain IRIS image (the order against the Configure phase, and the import by a worker of each category); the md5 sums and the overwrite on a reinstall were not (section "M1 on IPM path A" below).

## M2: libraries on the hand-built samples

Samples were written by a scratch generator (PDFs by hand with a stored content stream and a WinAnsi accent; .docx as a stored zip of four parts; OLE2 signature files with UTF-16LE stream names).

pdfplumber 0.11.10 (pdfminer.six 20260107):
- `pdf3.pdf` (3 pages, one accented word): `pages=3`, first page text `Page one caf<e-acute> rotation`, the accent kept.
- Drawing-only page: `pages=1`, text empty (`no_text`).
- `/Encrypt` with fixed hex `/O` and `/U` (V 1, R 2): `pdfplumber.utils.exceptions.PdfminerException`, empty message, `args[0]` is a `pdfminer.pdfdocument.PDFPasswordIncorrect`.
- `%PDF-1.4` plus junk, zero bytes, and a non-PDF file: `PdfminerException`, `args[0]` is a `pdfminer.pdfparser.PDFSyntaxError` ("No /Root object! - Is this really a PDF?").
- So the one wrapper class carries both: `isinstance(e.args[0], PDFPasswordIncorrect)` gives `encrypted`, anything else of `PdfminerException` (and `MalformedPDFException`) gives `damaged`.
- The class hierarchy: `PDFPasswordIncorrect` -> `PDFEncryptionError` -> `PDFException` -> `PSException` -> `Exception`.
- The 10,485,760-byte sample (one text page plus an unreferenced padding stream): `pages=1`, 16 characters, 0.00 s. Reading it costs nothing beyond the open. (A first, wrongly built sample whose cross-reference table was broken took 43.8 s through pdfminer's brute-force scan: a damaged-xref PDF is slow, bounded by `TIMEOUT`.)
- Dense text pages (50 lines each): 60 pages, 272,940 characters, 3.2 s; 200 pages 10.2 s; 800 pages 41.9 s; 2,000 pages 107 s. The slow sample that takes over 5 s is therefore 200 dense pages (about 970 KB, about 10 s).

python-docx 1.1.2:
- `Document.iter_inner_content()` exists and yields `Paragraph` and `Table` objects in document order.
- Style names for the samples' styles: `Title`, `Heading 1`, `Heading 2`, `Normal`.
- A 2x2 table reads as rows `[a1, b1]`, `[a2, b2]`.
- A .docx with no text: no items. A junk zip: `zipfile.BadZipFile`. A zip without `word/document.xml`: python-docx raises `KeyError` for `[Content_Types].xml`, so the `word/document.xml` name check must run before python-docx opens it. Total declared unpacked size is the sum of `ZipInfo.file_size`.

## M3: the time limit

The probe used a work item that runs `pdfplumber` page by page in a worker of category `OcuTalon.Docs.Extractor` (`MaxActiveWorkers` 1, `DefaultWorkers` 1, made by `Install.Step.Memory.EnsureCategory`).
- `WaitOne(1)` returns after 1.00 s with `ERROR #7881 Timeout from 'WaitOne'` (`$$$MultiTimeout`).
- After the timeout, `Clear(0)` took 1.3 s (2.3 s from the call); `Clear(1)` took 3.3 s and 4.3 s in two runs (4.3 to 5.3 s from the call). The busy worker's job no longer existed after either, and the next item ran in 0.00 to 0.11 s on a new worker job.
- Other callers: with caller A timing out and cleared while caller B (its own group) read a 3 s PDF, B finished all 60 pages on its own worker job; A's `Clear` did not touch it.
- Two concurrent reads did not share the one worker: they ran on two worker jobs at the same time (about 4 s each). `MaxActiveWorkers` 1 did not serialise them.
- A work item that sat in a C call (`time.sleep(30)`) was not stopped by `Clear(1)`: the call returned after 29 s, when the sleep ended. pdfplumber's text extraction is Python code and is stopped in 1 to 3 s.
- The category worker restarts cleanly: after every `Clear` the next `Submit` answered normally.

Decided from these figures (recorded in the spec): `Memory.Worker` calls `Clear(0)` on a timeout, because `Submit` has already waited the whole time limit and `Clear(1)` adds a second wait that the matrix's "within about 3 s" does not leave room for.

## Found while testing (after Task 0): a timed-out read leaves a work group lock

Measured on the warm throwaway of the implement stage, on the host under load (load average 8 to 13, so every duration below is 3 to 4 times the Task 0 figures).
- After a read that timed out and whose busy worker was stopped, the calling process held a lock `^IRIS.WorkQueue("Group",<id>)` for the rest of its life. It happens with `Clear(0)`, with `Clear(1)` and with no `Clear` at all (the work group released while its worker is busy), so it belongs to the stop of a busy worker, not to `Clear`. A normal read, a read whose work item failed, and a timed-out ObjectScript item (`Hang`) in a plain session left no lock in the measurements that were made.
- `%UnitTest.Manager` reports it as "A UnitTest left the following global locked after invocation" and fails the class. The calling process of a tool would keep one lock per timeout.
- `OcuTalon.Memory.Worker` therefore releases the work group locks that the process holds after a timeout and did not hold when `Submit` began (`ReleaseGroupLocks`). `Test.Docs.Extract:TestTimeLimit` asserts that the process holds no new lock; without the release the test and the class fail.
- Under that load the stop took 6 to 10 s from the call (2.3 s unloaded), so `TestTimeLimit` reads a 400-page sample (about 20 s unloaded) and asserts only that the read ended before it would have finished (under 20 s).

## M1 on IPM path A (`release/ipm-install.sh a`, plain IRIS image, IPM 0.10.10)

Measured 2026-11-06 on one lane-C throwaway after the review patches (aarch64; the whole script ended with "all checks passed").
- The second run (`second-ocutalon`, 93 s on a loaded host) printed `Activate START`, `Configure START`, one `STEP <name> OK` line per step and `Configure SUCCESS`. `STEP Memory OK 4.8s` carries no `WARN Memory` line: the Memory step's `Download` imports `ocutalon_memory` in a worker of the Embedder category during the Configure phase, and the model is in `<mgr>/fastembed/` afterwards (check 30). So the resource was on a worker's `sys.path` before the Memory step ran, as on the Docker path.
- Check 33 passes: `Docs.Extract.Read` answers the 3-page PDF and the headings .docx with `ok:1` and markers, in a worker of the `OcuTalon.Docs.Extractor` category. So `ocutalon_extract` is imported by a worker of that category from an IPM install, and the category exists (the Memory step made it).
- Check 32 passes: `gate.py check` on what IPM installed (all 36 distributions under an allowed licence) and `gate.py notices` names all 36 at their pinned versions. The 11 earlier distributions that the plain image already holds are reported as NOTE lines and are not gated (the deferred item on the six older copies).
- Not measured in this pass: the files' md5 sums against the sources, and that a reinstall overwrites them. They are check 31 of part b (`resources_fingerprint`), which this pass did not run.

## Measured figures

The figures that the README and `docs/install-ipm.md` quote (installed size, download size, model size, time), as measured on the lane-C throwaway of this story's implement stage with the commands the spec's PUBLIC TEXT item names (`du -sk`, `pip download --only-binary=:all: --no-deps -r requirements.txt`, the `TIME` lines of path A, and `docker build --no-cache`). The raw logs of those runs are not kept in the repository. Where the bytes came from: IPM path A installs OcuTalon from the local package folder in the throwaway (never from the public IPM registry); the pip step of that install and `pip download` fetched the 36 wheels from public PyPI (pypi.org, files.pythonhosted.org), and the Memory step downloaded the model from Hugging Face (huggingface.co) inside the same throwaway. All of it on the developer machine (aarch64); the x64 install time is read from the CI `ipm-install` job log once the story is pushed.
- Installed: `<mgr>/python` after path A holds 251,202,444 bytes (about 250 MB) that the install added.
- Download: the wheels of the 36 pinned distributions are 75,994,243 bytes in 36 files.
- Model: `<mgr>/fastembed` holds 91,103,785 bytes (about 90 MB).
- Time: the second command takes 58 to 63 s on a quiet host and 87 to 90 s on a loaded host (93 s on the loaded host of the run above); of that, pip and the download take about 21 s. The `docker build --no-cache` step that runs pip and fetches the model takes 26.0 s on the clean host. The README and docs round up to "about 1 minute" for an ordinary connection.
