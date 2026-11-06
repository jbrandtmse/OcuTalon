# Story 34.2 Task 0 (licences): the installed set of the three pinned packages

Measured 2026-11-05 by the Epic 34 runner (lane C), evidence only, for inbox item U-285 (answer #861: (a), conditional on this list).

**Method.** A throwaway container of the AI Hub base image `ocutalon-iris-base:2026.3.0AI.154.0` (Python 3.12.3, aarch64; removed after each run) ran `python3 -m pip install --no-cache-dir --target <scratch dir> fastembed==0.9.0 pdfplumber==0.11.10 python-docx==1.1.2`. Each installed distribution's licence was read from its `METADATA` (`License-Expression`, `License`, the `License ::` classifiers) and, where those are empty or say "dependency licenses", from the licence files in its `.dist-info`. "In base image" is the version the base image already ships in the IRIS owner's user site-packages (33 distributions there, from AI Hub); the system Python ships only Ubuntu's own packages. The x64 CI runner gets the same distributions as x64 wheels (inference: not measured on x64).

**Result: 36 distributions installed. 34 are inside the families U-285 allows; 2 are not (pypdfium2 and numpy, below), so the measurement STOPS per the answer.**

| Distribution | Version | Licence (as declared) | Family check | In base image |
|---|---|---|---|---|
| anyio | 4.16.0 | MIT | yes | 4.15.1 |
| certifi | 2026.10.23 | MPL-2.0 | yes | 2026.7.22 |
| cffi | 2.1.1 | MIT-0 | yes | - |
| charset-normalizer | 3.5.2 | MIT | yes | 3.5.1 |
| click | 8.5.0 | BSD-3-Clause | yes | - |
| cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause | yes | - |
| fastembed | 0.9.0 | Apache-2.0 | yes | - |
| filelock | 4.2.9 | MIT | yes | - |
| flatbuffers | 25.12.19 | Apache 2.0 | yes | - |
| fsspec | 2026.9.0 | BSD-3-Clause | yes | - |
| h11 | 0.16.0 | MIT | yes | 0.16.0 |
| hf-xet | 1.8.0 | Apache-2.0 | yes | - |
| httpcore | 1.0.9 | BSD-3-Clause | yes | 1.0.9 |
| httpx | 0.28.1 | BSD-3-Clause | yes | 0.28.1 |
| huggingface_hub | 1.33.0 | Apache-2.0 | yes | - |
| idna | 3.20 | BSD-3-Clause | yes | 3.20 |
| loguru | 0.7.3 | MIT License | yes | - |
| lxml | 6.1.3 | BSD-3-Clause | yes | - |
| mmh3 | 5.3.1 | MIT License | yes | - |
| numpy | 2.5.4 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 | NO: the expression includes Zlib (libdivide) | - |
| onnxruntime | 1.31.1 | MIT License | yes | - |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | yes | 26.3 |
| pdfminer.six | 20260107 | MIT | yes | - |
| pdfplumber | 0.11.10 | MIT License | yes | - |
| pillow | 12.3.0 | MIT-CMU | yes | - |
| protobuf | 7.36.2 | 3-Clause BSD License | yes | - |
| py_rust_stemmers | 0.1.8 | MIT (LICENSE file; METADATA empty) | yes | - |
| pycparser | 3.12 | BSD-3-Clause | yes | - |
| pypdfium2 | 5.14.0 | BSD-3-Clause, Apache-2.0, dependency licenses | NO: bundled PDFium components outside the families (see below) | - |
| python-docx | 1.1.2 | MIT | yes | - |
| PyYAML | 6.0.3 | MIT | yes | 6.0.3 |
| requests | 2.34.2 | Apache-2.0 | yes | 2.34.2 |
| tokenizers | 0.23.3 | Apache Software License | yes | - |
| tqdm | 4.70.1 | MPL-2.0 AND MIT | yes | - |
| typing_extensions | 4.16.0 | PSF-2.0 | yes | 4.16.0 |
| urllib3 | 2.8.0 | MIT | yes | 2.8.0 |

**Outside the allowed families:**
- **pypdfium2 5.14.0** (required by pdfplumber 0.11.10). `METADATA` `License: BSD-3-Clause, Apache-2.0, dependency licenses`; the wheel bundles a PDFium build whose `BUILD_LICENSES` include: FreeType ("The FreeType Project LICENSE", the FTL; FreeType is FTL or GPL-2.0, and this build ships the FTL text), zlib ("zlib.h -- interface of the 'zlib' general purpose compression library", the Zlib licence), libpng ("PNG Reference Library License version 2"), libjpeg-turbo ("covered by two compatible BSD-style open source licenses: The IJG (Independent JPEG Group) License" and BSD-3-Clause), ICU ("UNICODE LICENSE V3"), Anti-Grain Geometry 2.3 (AGG's own permissive licence), LLVM libc ("Apache License v2.0 with LLVM Exceptions"); its own README text is CC-BY-4.0. Inside the families: abseil, fast_float, lcms, libopenjpeg, simdutf, pdfium, pdfium-binaries.
- **numpy 2.5.4** (required by fastembed 0.9.0, through onnxruntime and others). `License-Expression: BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0`; the Zlib part is libdivide ("zlib License ... Copyright (C) 2010 - 2019 ridiculous_fish").

**Notes.**
- py_rust_stemmers 0.1.8 declares no licence in `METADATA`, but ships `LICENSE` ("MIT License, Copyright (c) 2024 qdrant"): MIT.
- cffi's `MIT-0` (MIT No Attribution) is read as the MIT family.
- certifi and tqdm (MPL-2.0) and typing_extensions (PSF-2.0) are allowed by U-285's answer; certifi and typing_extensions are already in the base image.
- Nothing was committed to the image or vendored; the repository's own licence is unchanged.
