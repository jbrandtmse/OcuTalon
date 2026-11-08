# Story 19.2 Task 0: the Python fastembed package reads the model folder through cache_dir (measured)

- **Date:** 2026-11-06, about 05:30 to 05:40 UTC (one run of 222 s after the stack was ready; an earlier run of the same driver found three bugs in the scratch probe, none in the product, and is not recorded).
- **Target:** one fresh lane-C throwaway, run tag `e19s2i0`, built from the Epic 19 worktree with the Docker path (`docker-compose.yml` + the CI override), after-start install ready. `$ZV`: `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:05:18 EDT`. Sessions and workers run as `irisowner`. `$SYSTEM.Util.ManagerDirectory()` is `/durable/iris/mgr/`, so the IPM-install folder `<mgr>/fastembed/` is `/durable/iris/mgr/fastembed/` there. The image's `FASTEMBED_CACHE_DIR` is `/opt/fastembed` (root-owned, folders 555, files 444); `HF_HUB_OFFLINE` is unset.
- **Repo:** the run changed nothing in the repository (`git status --short` showed only the spec's own earlier edit). Teardown with tag `e19s2i0`: 0 projects, 0 containers, 0 volumes, 0 networks and 0 images left; the lane's lock folder was empty afterwards.
- **Scratch sources:** the stage scratch folder (outside the repository) holds the driver script and the probe class `ZE19.Probe`; the class was loaded only into the throwaway's OCUTALON namespace. The probe is `OcuTalon.Memory.Embedder`-shaped: the Python package is driven from ObjectScript through `%SYS.Python` inside a `%SYSTEM.WorkMgr` worker of category `OcuTalon.Memory.Embedder` (made in the throwaway with `Config.WorkQueues.Create`, `MaxActiveWorkers` 2, `DefaultWorkers` 1; `Get` and `Modify` also worked).

## Verdict

**PASS. The stop rule does not fire.** Offline (the only network of the iris container disconnected; a name lookup fails), in a worker, Python `fastembed` 0.9.0 loads the model from `cache_dir=/opt/fastembed` (read-only) and from `cache_dir=<mgr>/fastembed/` (the folder the Dockerfile's `snapshot_download` call made), returns 384 values, and the vectors equal AI Hub's FastEmbed vectors within 1.3e-7 (limit 1e-6). Nothing was written into any folder, and `HF_HUB_OFFLINE=1` is not needed.

## Method details

- The worker sets `os.environ["FASTEMBED_CACHE_DIR"]` (through `%SYS.Python`, so the Python `os.environ` mapping and the C environment both change; `os.putenv` alone does not change `os.environ`, which `fastembed` reads) and then builds `fastembed.TextEmbedding("sentence-transformers/all-MiniLM-L6-v2", cache_dir=<folder>, local_files_only=True)`. `%SYS.Python` from ObjectScript passes no keyword arguments (a `kw(...)...` argument is ignored on this build; measured on the slot), so the call is made through a one-line `eval` of a `lambda` with an explicit globals dict (`eval` without one fails with "frame does not exist").
- The model is cached per worker process in an attribute of the `sys` module (key: folder), so the model loads once per worker process: the second and third calls had `loaded-now` 0.
- The model name `sentence-transformers/all-MiniLM-L6-v2` resolves, in `fastembed` 0.9.0 (`text/pooled_normalized_embedding.py`), to the Hugging Face source `Qdrant/all-MiniLM-L6-v2-onnx`, whose folder is `models--Qdrant--all-MiniLM-L6-v2-onnx`: the folder the image bakes. The package first looks in the cache with `local_files_only=True` and returns without any network call when it finds the snapshot.
- The copy under `<mgr>` was made with `cp -r /opt/fastembed <mgr>/fe-copy`; the download with the Dockerfile's call (`snapshot_download('Qdrant/all-MiniLM-L6-v2-onnx', cache_dir=..., allow_patterns=['config.json', 'tokenizer.json', 'tokenizer_config.json', 'special_tokens_map.json', '*.onnx'])`) in the worker, with the network up.
- Folder state is a checksum of the sorted list of path and size (relative to the folder, so two folders compare by file count and size), the count of files and the size in KB.

## Download (network up)

- `CHK|run.Download.sc|ok`, `download-s` 3.8 s (the worker's `$JOB` 3985, the caller's 3979); the snapshot path ends `models--Qdrant--all-MiniLM-L6-v2-onnx/snapshots/d13954661f83248295ba75c1ed411eef3b7b936e`.
- `<mgr>/fastembed/` holds `blobs`, `CACHEDIR.TAG` and `models--Qdrant--all-MiniLM-L6-v2-onnx`; 16 files and 89,052 KB, the same file count and size as `/opt/fastembed` (16 files, 89,052 KB) and as the copy.

## Block

- `docker network disconnect` of the container's one network (`..._default`) returned 0, `docker inspect` then listed no network, and a name lookup of `huggingface.co` from Python failed with `urllib.error.URLError: <urlopen error [Errno -3] Temporary failure in name resolution>`.

## M1: Python fastembed, `cache_dir=/opt/fastembed`, offline, no `HF_HUB_OFFLINE`

- Three texts through a worker (`$JOB` 3985 each time; the callers' jobs differ: 4059, and others): `sc` ok, `len` 384, `vlen` 384.
- The first call loaded the model: `load-s` 0.671, `first-vector-s` 0.700 (an earlier cold run of the same stack took 2.2 s with a cold file cache). The next calls took 0.006 s and 0.112 s with no load.
- `FASTEMBED_CACHE_DIR` inside the worker was `/opt/fastembed`; `HF_HUB_OFFLINE` was empty, so it is not needed.
- Worker memory (`/proc/self/status`): `VmRSS` 68,656 KB before the load, 266,636 KB after the first vector (+198 MB, the spine's "about 220 MB").
- `/opt/fastembed` unchanged afterwards (checksum equal before and after M1, M2 and M3); `fastembed` created no other cache (`find / -xdev -name .fastembed_cache -o -name fastembed_cache` found nothing).
- Control, an empty folder (`cache_dir=<mgr>/fe-empty`), offline: the worker's error is `<PYTHON EXCEPTION> 246 <class 'ValueError'>: Could not load model sentence-transformers/all-MiniLM-L6-v2 from any source.` returned in 0.00 s, and the folder stayed empty. Without `local_files_only=True` the same control took 39 s (three download tries with waits) before the same error, so the worker passes `local_files_only=True`: a missing model fails at once, with no network try.

## M2: the difference against AI Hub's FastEmbed (the three matrix texts)

AI Hub's FastEmbed (in a session job, the image's `FASTEMBED_CACHE_DIR` as it is) embedded each text with `KnowledgeBase.AddDocument` into one `%AI.RAG.VectorStore.IRIS` table (3 rows, one chunk per text). A worker then embedded each stored chunk text with Python `fastembed` and compared every component with the stored `vector` column:

| Text | chars | word pieces | max component difference |
|------|-------|-------------|--------------------------|
| ASCII (`the Results partner's contact is Lee`) | 36 | 10 | 1.139e-7 |
| accented Latin letter and two CJK characters, authored with `$Char` | 46 | 14 | 1.290e-7 |
| 5,795 characters of ordinary sentences (over 256 word pieces) | 5,795 | 256 (the tokenizer's limit) | 1.167e-7 |

- Maximum 1.290e-7, below 1e-6. AI Hub did not split the long text (one chunk); both sides cut it at 256 word pieces.

## M3: the folder as the download made it, and the copy

- Python `fastembed` with `cache_dir=<mgr>/fastembed/` (the download): `sc` ok, `len` 384, `load-s` 0.227, the same first three components as M1 (`-.0936...`, `.0854...`, `-.0272...`). With `cache_dir=<mgr>/fe-copy`: ok, `load-s` 0.890, the same components.
- AI Hub's FastEmbed in a worker of category `Default` (so not the Python worker's process), the variable set by `os.putenv` through `%SYS.Python` before `FastEmbed.Create()` as Story 34.1 did: with `<mgr>/fastembed/` it embedded a document (1 row) and its vector differs from Python's by at most 1.139e-7; with the copy it embedded a document (1 row).
- The download folder and the copy were unchanged afterwards; the network was still disconnected (`docker inspect` listed no network).

## Consequences recorded for the story

- The worker needs no `HF_HUB_OFFLINE`, no `specific_model_path` and no network; it passes `cache_dir`, sets `FASTEMBED_CACHE_DIR` in itself and passes `local_files_only=True`.
- A failure inside the worker returns as the work item's `%Status` and the error node, so the caller never sees a crash.

## What is not measured (inference)

- The run is on ARM64 (the developer machine). The x64 result is measured by `live:memory-offline` on CI's `iris (shards-4)`.
- The step's own download in an IPM install without `fastembed` or `huggingface_hub` (today's FR-57 image) is covered by `Test.Memory.Install` and `release/ipm-install.sh`, not here.
