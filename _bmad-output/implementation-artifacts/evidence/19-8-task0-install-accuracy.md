# Story 19.8 Task 0: what the IPM install imports, and which hosts the downloads use

Measured 2026-11-06 (the session date; the spec is dated 2026-11-07) by the Epic 19 runner (lane C), stage "task0", on the developer machine (Apple silicon, Docker, aarch64 containers). Measurement only: no product file, test or script was edited. Evidence only.

## Result and decision

- DW-829: after the local-artifact IPM install (path A, second run), ALL SIX of certifi, charset_normalizer, idna, requests, typing_extensions and urllib3 import the OLDER copy that IPM's own dependencies put in `<mgr>/python` before the install. The pinned dist-info folders sit beside the old ones, but Python loads the old code. No pinned copy is imported.
- Decision (the spec's rule): "Any stale copy: do the fix task". README sentence A5 stays; the fix is the early `RemoveStaleCopies` step; the same import check gates it. The "pinned copies imported -> skip the fix" branch does not apply.
- Image (read only, M5): the Docker image imports the PINNED copies of all six (they come first on `sys.path`). No Lane B finding for `deferred:`; AD-23's "IPM's own Python packages don't clash (S11)" stays.
- DW-830: the hosts seen are NOT the three named today. Extra Hugging Face hosts: `us.aws.cdn.hf.co` (a `Location` host for the 90 MB `model.onnx`) and `cas-server.xethub.hf.co` (a `Link` header host: Xet). PyPI side: only `pypi.org` and `files.pythonhosted.org`, no redirect. The hosts the Xet client then contacts for chunk transfer are not visible to a HEAD (inference, see M6). The last (PUBLIC TEXT) task therefore applies; the spec's example host `cas-bridge.xethub.hf.co` was NOT seen.

## How it was run (lane variables written symbolically)

Lane variables on every call: `OCUTALON_LOCK_DIR=<lane-c lock folder> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=task0'`.

1. Warm stack for M5 (image, read only): `OCUTALON_RUN_TAG=e19s8iw bash ci/warm.sh up` (READY 151 s); the probes below ran as `docker exec` sessions on its iris container (read only: an `iris session IRIS -U OCUTALON` import session, and `python3 -` reading the folders with the script on stdin, so nothing was written into the container). Then `OCUTALON_RUN_TAG=e19s8iw bash ci/warm.sh down`.
2. Fresh throwaway for M1/M2: `OCUTALON_RUN_TAG=e19s8i0 bash <scratch copy of release/ipm-install.sh> a`. The scratch copy is `release/ipm-install.sh` with three changes made in the scratch folder only (the file under `release/` is unchanged, `git status` clean): `root` fixed to the worktree; a function `m2_before` called after `snapshot_python_before`; a function `m_probe`, then `check_memory`, `check_licences "install checks"` and `finish`, called right after `check_second_run`. The run is the script's own path A: stack up (47 s), first run in %SYS and USER, repeat, Shell() run, second run in OCUTALON from the folder (`zpm "load /opt/ocutalon-ipm/src"`, with `requirements.txt` staged beside `src/module.xml` as the script does), `TIME second-ocutalon 91s`. The IPM source is the local folder only: the public IPM registry was never used (the script's path a). The stack's trap removed it at the end (`LOCK released`).
3. `m_probe` (container, after the second run):
   - an OCUTALON terminal session (`iris session IRIS -U OCUTALON`) imports each module with `##class(%SYS.Python).Import(name)` (the call OcuTalon's workers use) and prints `getattr(m, "__version__", "")` and `m.__file__`, and `sys.path`;
   - the container's `python3` (3.12.3) compares each `__file__` with every `<name>-<version>.dist-info/RECORD` in the folder: sha256 of the file, urlsafe base64, unpadded, against the RECORD row of the file's path relative to the folder;
   - the pin comes from `requirements.txt`; a copy counts as pinned only when the RECORD hash of the PINNED dist-info matches the imported file AND `__version__` (where defined) equals the pin.
4. M6: host-side `curl -sIL --max-redirs 5` (HEAD only; `-L` repeats HEAD at each hop) and `python3 -m pip install --dry-run --report ... --no-deps --only-binary=:all: --python-version 3.12 --implementation cp --abi cp312 --abi abi3 --abi none --platform manylinux_2_39_<arch> ... --platform manylinux_2_17_<arch> --platform manylinux2014_<arch> --platform any --target <scratch>/t-<arch> -r requirements.txt`, once for `aarch64` and once for `x86_64`.

Teardown: `ci/warm.sh down` (tag e19s8iw: 1 project removed, 0 leftovers) and `ci/iris.sh teardown` (tag e19s8i0: 0 projects, 0 leftovers: the fresh run had already removed its own stack). The lane-c lock folder was empty afterwards (both locks released), and `docker ps -a` showed no container of either tag.

## M1 (DW-829): the six imports on path A, unfixed tree, plain IRIS image

Embedded Python in an OCUTALON session; `<mgr>` is the instance's manager directory. `sys.path` of that session starts with `<mgr>/python` (then the system Python folders, and `<mgr>/python` once more later).

| module | pin (requirements.txt) | imported `__version__` | imported `__file__` (relative to `<mgr>`) | dist-infos of that name in `<mgr>/python` | RECORD hash of the imported file matches | pinned copy imported |
|--------|-----------------------|-----------------------|-------------------------------------------|-------------------------------------------|------------------------------------------|----------------------|
| certifi | 2026.10.23 | 2025.01.31 | python/certifi/__init__.py | certifi-2025.1.31, certifi-2026.10.23 | 2025.1.31: yes; 2026.10.23: DIFFERS | no |
| charset_normalizer | 3.5.2 | 2.1.1 | python/charset_normalizer/__init__.py | charset_normalizer-2.1.1, charset_normalizer-3.5.2 | 2.1.1: yes; 3.5.2: DIFFERS | no |
| idna | 3.20 | 3.15 | python/idna/__init__.py | idna-3.15, idna-3.20 | 3.15: yes; 3.20: DIFFERS | no |
| requests | 2.34.2 | 2.32.3 | python/requests/__init__.py | requests-2.32.3, requests-2.34.2 | 2.32.3: yes; 2.34.2: DIFFERS | no |
| typing_extensions | 4.16.0 | - (the module defines none) | python/typing_extensions.py | typing_extensions-4.12.2, typing_extensions-4.16.0 | 4.12.2: yes; 4.16.0: DIFFERS | no |
| urllib3 | 2.8.0 | 2.6.3 | python/urllib3/__init__.py | urllib3-2.6.3, urllib3-2.8.0 | 2.6.3: yes; 2.8.0: yes (see below) | no (the version is 2.6.3) |

Finding for the import check's design (important): urllib3's `__init__.py` is byte-identical in 2.6.3 and 2.8.0 (the version lives in `_version.py`), so the hash of `__init__.py` alone matches BOTH RECORDs and would wrongly pass. The version compare (`__version__` equal to the pin) is what shows urllib3 is stale. The import check must therefore apply both tests, as the spec says (hash AND version where defined), and a hash-only check is not enough for a module whose `__init__.py` does not change between versions. (An extra safeguard, not measured here: also hash the file that carries the version, `<pkg>/_version.py`, or compare a second file.)

State after the install: `<mgr>/python` holds BOTH dist-infos of each of the six (old from IPM's dependencies, pinned from `pip install -t`), and the old top-level folders/files (`certifi/`, `charset_normalizer/`, `idna/`, `requests/`, `typing_extensions.py`, `urllib3/`) were kept by pip as they were: the imported code is the old code. The pip `-t` skip behaviour is thereby confirmed for these six names (it was inference in the spec).

Check 32 (the licence gate) on this unfixed run: PASS ("all 36 distributions are under an allowed licence", notices name all 36). It cannot see the problem: its NOTE lines list the 11 pre-existing dist-infos as "was in the folder before the install and is no pin: not gated" - including the six OLD copies of pinned names, because its skip rule `entry in before and pins.get(norm(name)) != version` skips a stale dist-info of a pinned name, and "36 distributions gated" counts the pinned ones. Check 30 (fastembed 0.9.0, pdfplumber 0.11.10, python-docx 1.1.2, model once) PASS. Whole `a` prefix up to there: "all checks passed". The import check's red on a stale copy is therefore observed on the unfixed tree by M1's comparison: 6 of 6 stale.

## M2 (safety), from the same run

Before the second run (the folder as IPM left it when it loaded, in the plain image; the image's python3 is `/usr/bin/python3` 3.12.3):

- Dist-infos in `<mgr>/python` before the install (11): attrs 25.1.0, certifi 2025.1.31, charset_normalizer 2.1.1, idna 3.15, jsonschema 4.23.0, jsonschema_specifications 2024.10.1, oras 0.1.30, referencing 0.36.2, requests 2.32.3, typing_extensions 4.12.2, urllib3 2.6.3. Exactly six of them are names that requirements.txt pins (the six); the other five (attrs, jsonschema, jsonschema_specifications, oras, referencing) are no pin.
- Top-level items before: `__pycache__`, `attr`, `attrs`, `bin` (holding only `normalizer`), `certifi`, `charset_normalizer`, `idna`, `jsonschema`, `jsonschema_specifications`, `oras`, `referencing`, `requests`, `rpds.py`, `typing_extensions.py`, `urllib3`, and the 11 dist-info folders.
- Top-level items that the 36 pins share with that folder (what `pip --upgrade` would replace): exactly six - `certifi`, `charset_normalizer`, `idna`, `requests`, `typing_extensions.py`, `urllib3` - each claimed by the PINNED dist-info's RECORD of the same name. No pinned RECORD claims `attr`, `attrs`, `jsonschema*`, `oras`, `referencing`, `rpds.py` or `__pycache__`. No pinned RECORD lists a `bin/<file>` that `bin/` held before (the pre-existing `bin/normalizer` is not claimed by a pinned RECORD; not re-listed after the install, so whether pip wrote its own `bin/` entries is not measured). Items claimed by two or more distributions after the install: only the six stale/pinned pairs above (no namespace folder such as `google/` was shared: `google/` is created by the install by protobuf alone).
- `Requires-Dist` of a pre-existing distribution on one of the six, and whether the pin satisfies it (`packaging.specifiers`, pin versions, prereleases allowed; markers not evaluated, extras noted):

| distribution (version) | requires | marker | pin | satisfied |
|------------------------|----------|--------|-----|-----------|
| jsonschema 4.23.0 | idna (no range) | extra == 'format' | 3.20 | yes |
| jsonschema 4.23.0 | idna (no range) | extra == 'format-nongpl' | 3.20 | yes |
| oras 0.1.30 | requests (no range) | - | 2.34.2 | yes |
| oras 0.1.30 | requests (no range) | extra == 'all' | 2.34.2 | yes |
| referencing 0.36.2 | typing-extensions >=4.4.0 | python_version < '3.13' | 4.16.0 | yes |
| requests 2.32.3 | charset-normalizer >=2,<4 | - | 3.5.2 | yes |
| requests 2.32.3 | idna >=2.5,<4 | - | 3.20 | yes |
| requests 2.32.3 | urllib3 >=1.21.1,<3 | - | 2.8.0 | yes |
| requests 2.32.3 | certifi >=2017.4.17 | - | 2026.10.23 | yes |

  Every requirement is satisfied by the pin (requests 2.32.3 itself is the stale copy that would go).
- `oras.provider` imports before the install (CHK oras-before 1) and after it (CHK oras 1, in the OCUTALON session), on the unfixed tree. (The fix is not built; the "imports after the fix" half belongs to the implement stage.)

## M3, M4 (not measured: they need the fix)

M3 (fix wiring) and M4 (`GetArgsArray` on the new Invoke) need the `RemoveStaleCopies` step and its Invoke, which this stage must not build. They stay in the implement stage's Task 0 follow-up. Nothing in M1/M2 argues against the fix: the six stale names are exactly the ones whose pinned dist-info exists beside them.

## M5 (image, read only), warm stack e19s8iw (aarch64, Python 3.12.3)

The image has TWO `mgr/python` folders: `/usr/irissys/mgr/python` (the image build's `pip --target`, the pins) and `/durable/iris/mgr/python` (the durable manager directory, where the after-start's `zpm load` put IPM's ORAS dependencies and OcuTalon's two Python resources). In an OCUTALON session `sys.path` is `/usr/irissys/mgr/python` (FIRST), the system Python folders, `/durable/iris/mgr/python`, `/usr/irissys/lib/python`, ...; `oras.provider` imports (CHK oras 1).

| module | pin | imported `__version__` | imported `__file__` | dist-infos in `/usr/irissys/mgr/python` (image) | dist-infos in `/durable/iris/mgr/python` | RECORD hash of the imported file | pinned copy imported |
|--------|-----|-----------------------|---------------------|-------------------------------------------------|------------------------------------------|----------------------------------|----------------------|
| certifi | 2026.10.23 | 2026.10.23 | /usr/irissys/mgr/python/certifi/__init__.py | 2026.10.23 | 2025.1.31 | equal (pinned) | yes |
| charset_normalizer | 3.5.2 | 3.5.2 | /usr/irissys/mgr/python/charset_normalizer/__init__.py | 3.5.2 | 2.1.1 | equal (pinned) | yes |
| idna | 3.20 | 3.20 | /usr/irissys/mgr/python/idna/__init__.py | 3.20 | 3.15 | equal (pinned) | yes |
| requests | 2.34.2 | 2.34.2 | /usr/irissys/mgr/python/requests/__init__.py | 2.34.2 | 2.32.3 | equal (pinned) | yes |
| typing_extensions | 4.16.0 | - (none) | /usr/irissys/mgr/python/typing_extensions.py | 4.16.0 | 4.12.2 | equal (pinned) | yes |
| urllib3 | 2.8.0 | 2.8.0 | /usr/irissys/mgr/python/urllib3/__init__.py | 2.8.0 | 2.6.3 | equal (pinned) | yes |

The image holds the same six older copies as the plain image, in the durable folder, but they come second on `sys.path`, so the session imports the pinned copies. (A worker's `sys.path` is the same pair per the 19.6 evidence; this probe used a terminal session, so a worker was not re-probed.) No change was made to the warm stack.

## M6 (DW-830): hosts, HEAD requests only

All requests are HEAD (`curl -sIL --max-redirs 5`); no model or wheel body was fetched. The signed query strings of redirect targets are not recorded, only hosts. Hugging Face revision measured: `X-Repo-Commit` `d13954661f83248295ba75c1ed411eef3b7b936e` (the 19.2 commit; `main` still resolves to it).

### Hugging Face: `https://huggingface.co/Qdrant/all-MiniLM-L6-v2-onnx`

| URL (`<f>` as shown) | hops (status; Location host; other host-bearing headers) |
|----------------------|-----------------------------------------------------------|
| `/resolve/main/model.onnx` | 302 -> Location host `us.aws.cdn.hf.co`; `X-Repo-Commit` d1395466...; `X-Xet-Hash` present; `Link` hosts `cas-server.xethub.hf.co` and `huggingface.co` (rels `xet-auth`, `xet-reconstruction-info`); then 200 at the CDN |
| `/resolve/<commit>/model.onnx` | the same as `main` |
| `/resolve/main/tokenizer.json` | 307 -> relative Location (stays on `huggingface.co`, path `/api/resolve-cache/models/...`); 200 on `huggingface.co`; `X-Repo-Commit` d1395466...; no Xet header |
| `/resolve/main/config.json` | the same as tokenizer.json |
| `/resolve/main/tokenizer_config.json` | the same |
| `/resolve/main/special_tokens_map.json` | the same |
| `/resolve/<commit>/<f>` for the four small files | the same as by `main` |
| `/api/models/Qdrant/all-MiniLM-L6-v2-onnx/revision/main` | 200 on `huggingface.co`, no redirect |

So by HEAD: the four small files are served by `huggingface.co` itself; the only file with an off-site hop is `model.onnx` (`us.aws.cdn.hf.co`, and Xet metadata pointing at `cas-server.xethub.hf.co`). `us.aws.cdn.hf.co` is the CDN edge this machine was sent to; the edge a different network gets may differ (inference).

Label as INFERENCE (a HEAD cannot show it): the pinned `hf-xet` 1.8.0 may download `model.onnx` through the Xet protocol instead of the redirect: it reads reconstruction information from `cas-server.xethub.hf.co` (named by the `Link` header; a GET with a token from `huggingface.co`) and then fetches chunk ranges from hosts that the reconstruction response names, not visible here. Which hosts the install actually opened was not captured (no packet or DNS capture was taken; a capture on a throwaway install is the way to measure it if the Planner needs more than the HEAD-visible hosts).

### PyPI (36 pins, `requirements.txt`)

- Index: `https://pypi.org/simple/<name>/` for all 36 normalized names: 36 of 36 `HTTP/2 200`, no `Location`. Index host: `pypi.org`. (A PEP 658 `.metadata` file next to a wheel URL, sampled on certifi: 200, same host as the wheel.)
- Wheel URLs from the dry-run reports (36 wheels each for `aarch64` and `x86_64`, both from `https://files.pythonhosted.org/packages/...`): 72 of 72 HEAD requests `HTTP/2 200`, no `Location`, no Xet header. Distinct host of all 72: `files.pythonhosted.org`.
- pip platform note: `--platform manylinux_2_28_<arch>` alone finds no wheel for cffi 2.1.1 (pip 26.2.1 does not expand it to the older manylinux tags the wheel carries), so the reports were made with the full list manylinux_2_39 down to 2_17, manylinux2014 and `any`, which is what a pip on the image (glibc 2.39) accepts. pip wrote one index page (about 570 KB, gzip) to the host's pip HTTP cache; no wheel body (the dry-run reports resolve from the index and PEP 658 metadata).
- The 14 platform-specific wheels (arm64 / x64): PyYAML 6.0.3, cffi 2.1.1, charset-normalizer 3.5.2, cryptography 50.0.2, hf-xet 1.8.0, lxml 6.1.3, mmh3 5.3.1, numpy 2.5.4, onnxruntime 1.31.1, pillow 12.3.0, protobuf 7.36.2, py_rust_stemmers 0.1.8, pypdfium2 5.14.0 and tokenizers 0.23.3 each have an aarch64 and an x86_64 file (for example `hf_xet-1.8.0-cp38-abi3-manylinux_2_28_aarch64.whl` and `hf_xet-1.8.0-cp38-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl`); the other 22 wheels are the same pure-Python file on both. (The per-arch filenames are in the stage's scratch reports; all are on `files.pythonhosted.org`.)

### Distinct hosts of the whole install

| host | seen by | URLs |
|------|---------|------|
| `pypi.org` | HEAD (index) | `/simple/<name>/` of the 36 pins |
| `files.pythonhosted.org` | HEAD (wheel and `.metadata` URLs) | 36 aarch64 + 36 x86_64 wheels |
| `huggingface.co` | HEAD (resolve, API) | all five SNAPSHOTFILES by `main` and by commit; the revision API |
| `us.aws.cdn.hf.co` | `Location` header | `model.onnx` by `main` and by commit (location dependent) |
| `cas-server.xethub.hf.co` | `Link` header (xet-reconstruction-info) | `model.onnx` by `main` and by commit |
| further Xet transfer hosts (inference) | not visible to a HEAD | `model.onnx` through hf-xet 1.8.0 |

Compared with the three hosts the README and `docs/install-ipm.md` name today (pypi.org, files.pythonhosted.org, huggingface.co): two extra HEAD-visible Hugging Face hosts, `us.aws.cdn.hf.co` and `cas-server.xethub.hf.co`. PyPI adds none. The spec's PUBLIC TEXT items name a placeholder `<hosts>` (example `cas-bridge.xethub.hf.co`); the measured set for it is `us.aws.cdn.hf.co` and `cas-server.xethub.hf.co`, with the Xet transfer hosts unmeasured.

## Decided in-stage

- Did not edit `release/ipm-install.sh` (the stage may edit only this file): the M1/M2 probes ran from a scratch copy of the script, which is the spec's "temporary NOTE block" done without touching the repository file.
- Ran only path A (`a`) for M1/M2, not part p: part p installs the same module through the same IPM pip step into a fresh instance of the same image, so it has the same starting `<mgr>/python` (inference; the implement stage's `p` run measures it).
- For the pip dry-run, used a platform list rather than the single `--platform` in the spec text (the single tag finds no cffi wheel); same index, same wheels.
- Recorded only hosts, not signed URLs, for redirect targets.
