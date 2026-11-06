# Story 34.2 Task 0 (b): the image's Python packages, the baked model and the licence gate (measured)

- **Date:** 2026-11-05, about 09:04 to 09:11 UTC (one run of 49 s after a build of 38 s)
- **Target:** a throwaway stack of lane C, tag `e34s2f`, made by `docker/tests/lib-live.sh` (`live_start`) from this worktree's `docker/Dockerfile` with `docker/tests/compose.no-after-start.yml` (iris-main applies the merge and no after-start script runs, so the OCUTALON namespace exists and the package is not installed). The base is the build 154 image `ocutalon-iris-base:2026.3.0AI.154.0` (ARM64), never pulled. The sessions run as OS user `irisowner` (uid 51773). `ci/iris.sh build` ran first (the web bundle).
- **Repo:** the Epic 34 worktree; the run changed no tracked file. Teardown with tag `e34s2f`: 0 projects, 0 containers, 0 volumes, 0 networks and 0 images left, and the lane's lock folder was empty afterwards.
- **Scratch sources:** the stage scratch folder (outside the repository) holds the driver script.

## Verdict

**PASS.** With the network disconnected, AI Hub's FastEmbed embeds in a fresh IRIS job with only the image's `FASTEMBED_CACHE_DIR` (`/opt/fastembed`) and the folder is unchanged afterwards; `fastembed` 0.9.0, `pdfplumber` 0.11.10 and `python-docx` 1.1.2 import in IRIS's Python from `/usr/irissys/mgr/python`; the model folder is root-owned and read-only to the IRIS user; the licence gate listed 36 distributions and every one is under an allowed licence; the notices file is there.

## 1. Build and start

- `TIME build 38s` (`dc build`: the pip line, the licence gate, the notices, the model download, then the sources). `TIME ready 46s` (IRIS running, merge applied).
- The build log carries the gate's two lines: `licence gate: 36 distributions in /usr/irissys/mgr/python` and `licence gate: all 36 distributions are under an allowed licence`, then `notices: wrote /opt/ocutalon/THIRD-PARTY-NOTICES for 36 distributions`.
- `CHK|iris-user|uid=51773(irisowner) gid=51773(irisowner) groups=51773(irisowner)`.

## 2. The variable and the folder

- `CHK|env|/opt/fastembed` (`$SYSTEM.Util.GetEnviron("FASTEMBED_CACHE_DIR")` in the IRIS process) and `printenv` in the container prints `/opt/fastembed`.
- Owner and modes: `/opt/fastembed`, `models--Qdrant--all-MiniLM-L6-v2-onnx` and its `refs`, `blobs` and `snapshots` are `root:root` 555. No directory is other than 555, no file other than 444 and nothing is owned by anyone but root.
- The IRIS user cannot create a file there: `touch: cannot touch '/opt/fastembed/zz-write-test': Permission denied` and the same inside the model folder.
- `refs/main` holds `d13954661f83248295ba75c1ed411eef3b7b936e`. The snapshot holds `config.json`, `model.onnx`, `special_tokens_map.json`, `tokenizer_config.json` and `tokenizer.json`.
- Files (16, 89,052 KB in all): `blobs/48/489ad214c162daff8026f207bc7efa8ce66d6ac1e3edd507221316de21eaa830` (the `model.onnx` content, 90,387,630 bytes, with its `.lock` and `.refs` files beside it), `models--Qdrant--all-MiniLM-L6-v2-onnx/blobs/` 711,649 (`tokenizer.json`), 650, 1,412 and 695 bytes, `refs/main` 40 bytes, `trees/<sha>.json` 1,044 bytes, `CACHEDIR.TAG`, `.huggingface-shared-blobs` and five empty `.lock` files under `.locks/`. The Python `huggingface_hub` (1.33.0, which `fastembed` installs) writes this layout; the large file sits in the shared `blobs/` folder and the snapshot entry reaches it.
- `CHK|fstat-before|541339e24e64 16 89052` (hash of the sorted names, sizes, modes and owners; file count; KB).

## 3. The packages in IRIS's Python

- `CHK|python|3.12.3`.
- `CHK|version|fastembed|0.9.0`, `CHK|version|pdfplumber|0.11.10`, `CHK|version|python-docx|1.1.2` (`importlib.metadata.version`, called from ObjectScript through `%SYS.Python`).
- `fastembed`, `pdfplumber`, `docx`, `pypdfium2`, `onnxruntime` and `huggingface_hub` import, each from `/usr/irissys/mgr/python/<package>/__init__.py`.
- `/usr/irissys/mgr/python` holds 47 entries: the 36 `.dist-info` folders and the packages. The folder itself is `irisowner:irisowner` 555 (the base image's); everything pip wrote is root's.

## 4. Licences and notices

- `python3 /opt/ocutalon/licences/gate.py check /usr/irissys/mgr/python` exits 0 and prints one line for each of the 36 distributions: the same 36 as the lead's U-285 list (aarch64). 34 are read from their declared licence, `py_rust_stemmers` (declares nothing; its `LICENSE` is MIT) and `pypdfium2` (declares `BSD-3-Clause, Apache-2.0, dependency licenses`; its 18 licence files, the PDFium `BUILD_LICENSES` among them, are all read as allowed licences) from their files.
- Distributions and declared licences, as the METADATA says: anyio MIT; certifi MPL-2.0; cffi MIT-0; charset_normalizer MIT; click BSD-3-Clause; cryptography Apache-2.0 OR BSD-3-Clause; fastembed Apache-2.0; filelock MIT; flatbuffers Apache 2.0; fsspec BSD-3-Clause; h11 MIT; hf_xet Apache-2.0; httpcore BSD-3-Clause; httpx BSD-3-Clause; huggingface_hub Apache-2.0; idna BSD-3-Clause; loguru MIT (classifier); lxml BSD-3-Clause; mmh3 MIT License; numpy BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0; onnxruntime MIT License; packaging Apache-2.0 OR BSD-2-Clause; pdfminer.six MIT; pdfplumber MIT (classifier); pillow MIT-CMU; protobuf 3-Clause BSD License; py_rust_stemmers (nothing, MIT file); pycparser BSD-3-Clause; pypdfium2 as above; python-docx MIT; PyYAML MIT; requests Apache-2.0; tokenizers Apache Software License (classifier); tqdm MPL-2.0 AND MIT; typing_extensions PSF-2.0; urllib3 MIT.
- Licence files shipped: every distribution but flatbuffers, loguru, onnxruntime and tokenizers ships at least one; none was deleted (`CHK|dist|...|licence-files=<n>`).
- `/opt/ocutalon/THIRD-PARTY-NOTICES` is `root:root` 444, 428,158 bytes (36 distribution sections, each opened by a rule line of `=` characters; 63 lines start with `=====` in all, the rest inside licence texts), the two credit lines at its top (`Portions of this software are copyright (c) The FreeType Project (www.freetype.org). All rights reserved.` and `This software is based in part on the work of the Independent JPEG Group.`), FreeType's licence text and the 15 PDFium `BUILD_LICENSES` texts. `/opt/ocutalon/licences/` holds `allowed.txt` and `gate.py`, root-owned and read-only.

## 5. Network off, offline embed

- `docker network disconnect` of the one network: `CHK|disconnect|<project>_default|0`, `CHK|networks-after|[]`; `https://huggingface.co` from `python3` fails: `CHK|net-off|urllib.error.URLError: <urlopen error [Errno -3] Temporary failure in name resolution>`.
- A fresh `iris session` job in OCUTALON, with no `putenv` (the image's variable only): `CHK|offline-env|/opt/fastembed`; `%AI.RAG.Embedding.FastEmbed.Create()`, a vector store `Probe.FastEmbedImage` (384 dimensions), a knowledge base over it and one `AddDocument("The Results runbook: rotate the certificate, then resend.", {"source":"probe.md"})`; `CHK|offline|ok|rows=1|dot=1.0000003565312165498`.
- The folder is unchanged: `CHK|fstat-after|541339e24e64 16 89052`, `CHK|unchanged|yes` (the same hash, count and size).

## What is not measured (inference)

- The x64 image: the licence gate runs in every image build, so CI's x64 build is that check (the wheels differ by platform: PDFium's `BUILD_LICENSES` folder is `data/linux_x64/` there).
- `/usr/irissys/mgr/python` is `irisowner`-owned and 555 in the base image, so the IRIS user could change its mode; the packages inside are root's and read-only to it.
