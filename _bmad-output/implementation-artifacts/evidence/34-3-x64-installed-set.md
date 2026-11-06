# Story 34.3 DW-738: the x64 installed set of the three pinned packages

Resolved 2026-11-05 by the Epic 34 runner (lane C), evidence for DW-738 and the Contest Planner's ruling on pinning the image's transitive Python packages per architecture.

**Method (resolved, then confirmed by the CI x64 build below).** No x64 Python image runs on the arm64 development machine, and nothing new was pulled. The set was resolved with the host's pip 26.2 (no image): `python3 -m pip install --no-cache-dir --target <dir> --platform manylinux_2_28_x86_64 --platform manylinux_2_27_x86_64 --platform manylinux_2_17_x86_64 --platform manylinux2014_x86_64 --platform manylinux_2_34_x86_64 --platform manylinux_2_35_x86_64 --platform manylinux_2_39_x86_64 --python-version 3.12 --implementation cp --abi cp312 --abi abi3 --abi none --only-binary=:all: fastembed==0.9.0 pdfplumber==0.11.10 python-docx==1.1.2` (the extra manylinux tags cover the glibc of the base image, which pip does not infer for another platform), and each distribution's licence was then read by `docker/licences/gate.py check` on that folder (the gate reads METADATA and licence files, which do not depend on the platform). The resolved set is 36 distributions at the same versions as the arm64 set of `34-2-task0-licences.md`.

**The CI x64 image build is the x64 confirmation.** The Dockerfile installs with `-c /opt/ocutalon/licences/constraints-x64.txt` and then runs `gate.py check` with that file, so the x64 `image` build fails on any installed distribution that is missing from the file or at another version, and on any pin that is not installed, and prints the installed set. Two limits of the resolution above: pip evaluated the dependencies' environment markers against the host interpreter (macOS arm64), not x86_64 Linux, so a dependency that only Linux or x86_64 needs may be missing here; and because the image installs with `-c`, a pinned version that has no x86_64 wheel, or that conflicts with x64's requirements, makes pip itself fail the build first, naming the distribution, before the gate prints any set. The lead records the run id, the job and the printed set (or pip's failure) here after the push, replacing the table below, which `docker/tests/test-compose-file.sh` reads as the pin list (inference until then: the x64 wheels were resolved, not installed and imported).

| Distribution | Version | Licence (as declared) | Gate verdict |
|---|---|---|---|
| anyio | 4.16.0 | MIT | allowed (declaration) |
| certifi | 2026.10.23 | (MPL-2.0) AND (Mozilla Public License 2.0 (MPL 2.0)) | allowed (declaration) |
| cffi | 2.1.1 | MIT-0 | allowed (declaration) |
| charset-normalizer | 3.5.2 | MIT | allowed (declaration) |
| click | 8.5.0 | BSD-3-Clause | allowed (declaration) |
| cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause | allowed (declaration) |
| fastembed | 0.9.0 | (Apache-2.0) AND (Apache Software License) | allowed (declaration) |
| filelock | 4.2.9 | MIT | allowed (declaration) |
| flatbuffers | 25.12.19 | (Apache 2.0) AND (Apache Software License) | allowed (declaration) |
| fsspec | 2026.9.0 | BSD-3-Clause | allowed (declaration) |
| h11 | 0.16.0 | (MIT) AND (MIT License) | allowed (declaration) |
| hf-xet | 1.8.0 | (Apache-2.0) AND (Apache Software License) | allowed (declaration) |
| httpcore | 1.0.9 | (BSD-3-Clause) AND (BSD License) | allowed (declaration) |
| httpx | 0.28.1 | (BSD-3-Clause) AND (BSD License) | allowed (declaration) |
| huggingface_hub | 1.33.0 | (Apache-2.0) AND (Apache Software License) | allowed (declaration) |
| idna | 3.20 | BSD-3-Clause | allowed (declaration) |
| loguru | 0.7.3 | MIT License | allowed (declaration) |
| lxml | 6.1.3 | BSD-3-Clause | allowed (declaration) |
| mmh3 | 5.3.1 | MIT License | allowed (declaration) |
| numpy | 2.5.4 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 | allowed (declaration) |
| onnxruntime | 1.31.1 | MIT License | allowed (declaration) |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | allowed (declaration) |
| pdfminer.six | 20260107 | MIT | allowed (declaration) |
| pdfplumber | 0.11.10 | MIT License | allowed (declaration) |
| pillow | 12.3.0 | MIT-CMU | allowed (declaration) |
| protobuf | 7.36.2 | 3-Clause BSD License | allowed (declaration) |
| py_rust_stemmers | 0.1.8 | (nothing) | allowed (files) |
| pycparser | 3.12 | BSD-3-Clause | allowed (declaration) |
| pypdfium2 | 5.14.0 | BSD-3-Clause, Apache-2.0, dependency licenses | allowed (files) |
| python-docx | 1.1.2 | (MIT) AND (MIT License) | allowed (declaration) |
| PyYAML | 6.0.3 | (MIT) AND (MIT License) | allowed (declaration) |
| requests | 2.34.2 | (Apache-2.0) AND (Apache Software License) | allowed (declaration) |
| tokenizers | 0.23.3 | Apache Software License | allowed (declaration) |
| tqdm | 4.70.1 | MPL-2.0 AND MIT | allowed (declaration) |
| typing_extensions | 4.16.0 | PSF-2.0 | allowed (declaration) |
| urllib3 | 2.8.0 | MIT | allowed (declaration) |

**Result (CI x64 build, 2026-11-05).** CI run 42128738213 (workflow ci.yml) on OCT-epic34 at 148652a1 built the image from this Dockerfile on the project's self-hosted x64 runners in every iris group (install-fresh, install-upgrade, production, browser, shards, shards-2, image, shards-3, shards-4), and every group concluded success. Each build ran `pip install ... -c /opt/ocutalon/licences/constraints-x64.txt` and then `gate.py check`, which fails the build when the installed set differs from the constraints file in any distribution or version, or when a licence is outside the allowed set. So the installed x64 set equals `constraints-x64.txt` (the 36 distributions above), measured, not assumed. Limitation: the image build's own output (the gate's per-distribution lines) does not reach the CI job log, so the listing itself is not quoted here; the pass of the equality gate is the measurement.

**Notes.**
- The licence column is the declaration the gate evaluates (every declaration of a package joined with AND); a package with none, or a phrase such as "dependency licenses", passes only through its licence files (py_rust_stemmers, pypdfium2).
- The family rulings (FreeType FTL, zlib, libpng, IJG, Unicode, AGG for pypdfium2 and Zlib for numpy) are those recorded in `docker/licences/allowed.txt`; the arm64 measurement is in `34-2-task0-licences.md`.
- The same list, as `name==version` pins, is `docker/licences/constraints-x64.txt`; `docker/tests/test-compose-file.sh` checks that the two are equal.
