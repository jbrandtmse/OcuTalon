# Story 34.1 Task 0: the FastEmbed model path on an IPM install (measured)

- **Date:** 2026-11-05, about 05:20 to 05:27 UTC (one run of 224 s)
- **Target:** a throwaway stack of lane C, tag `e34s1f`, made as `release/ipm-install.sh` makes it (`release/ipm/Dockerfile`, `release/ipm/compose.ipm.yml`, the CI override): a clean build 154 instance, IPM 0.10.10 loaded in %SYS and enabled for USER. `$ZV`: `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:05:18 EDT`. The sessions run as OS user `irisowner`.
- **Repo:** the Epic 34 worktree. The run changed nothing in it (`git status --short` was empty before and after). Teardown with tag `e34s1f`: 0 projects, 0 containers, 0 volumes, 0 networks and 0 images left; the lane's lock folder was empty afterwards.
- **Scratch sources:** the stage scratch folder (outside the repository) holds the driver script and the probe routine `ZFEProbe.mac`; the routine was loaded into the throwaway's OCUTALON namespace only.
- **Manager directory:** `$SYSTEM.Util.ManagerDirectory()` is `/usr/irissys/mgr/`, so `F` = `/usr/irissys/mgr/fastembed/`.

## Verdict

**PASS.** On an IPM-installed instance with outbound network blocked, AI Hub's FastEmbed finds the model in `<mgr>/fastembed/` and embeds offline when `FASTEMBED_CACHE_DIR` is set to that folder before first use, in a fresh IRIS job (step 8) and in a `%SYSTEM.WorkMgr` worker (step 9). Without the variable it does not find the model (step 7). Setting the variable after the AI Hub library is loaded, but before `FastEmbed.Create()`, also works (step 10). Nothing was downloaded after the block (step 11).

- 8 and 9 are ok, 7 errors, 6's block is verified and 11 holds: the verdict rule of the spec is met.
- The download is 11 files and 89,012 KB in `models--Qdrant--all-MiniLM-L6-v2-onnx`, one 90,387,630-byte `model.onnx` blob among them.

## 1. Stack

- `TIME 1-stack 67s`; the project name is `ocutalon-ipm-e34s1f-<epoch>-<pid>`.

## 2. Precondition

- `CHK|pre-printenv-exit|1` (`printenv FASTEMBED_CACHE_DIR` exits 1 in the container).
- `CHK|pre-getenv|[]` (`$SYSTEM.Util.GetEnviron("FASTEMBED_CACHE_DIR")` is empty).

## 3. IPM install

- `CHK|ipm-load|1`, `CHK|ipm-enable|1`.
- First run in USER: `TIME 3a-install-user 79s`; ends with `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`
- Second run in OCUTALON: `TIME 3b-install-ocutalon 56s`; `CHK|steps-ok|15`, `CHK|steps-failed|0`; `STEP Bridge.Installer` to `STEP Ready` all OK (`STEP PrivateData OK 0.1s`); `Configure SUCCESS`, `Activate SUCCESS`.
- `CHK|F|/usr/irissys/mgr/fastembed/`.

## 4. Network on

- `CHK|net-on|200` (`https://huggingface.co` from `irispython`); `TIME 4-net 0s`.

## 5. Download as the install step would

- One OCUTALON job as `irisowner`: `CreateDirectoryChain(F)` (`CHK|mkdir|1|1`), `os.putenv` through `%SYS.Python`, `CHK|download-env|/usr/irissys/mgr/fastembed/`, `FastEmbed.Create()`, VectorStore `Probe.FastEmbedDownload` (384), KB `probe`, one `AddDocument`.
- `CHK|download|ok|rows=1|dot=1.0000003565312165498`; `TIME 5-download 6s`.
- `CHK|fstat-5|size_kb=89012 files=11 list=45ef0f8aa0c5` (the last field is the first 12 characters of the md5 of the sorted list of path and size).
- Layout: `F/models--Qdrant--all-MiniLM-L6-v2-onnx/{blobs,refs,snapshots}`; blobs of 90,387,630 (`model.onnx`), 711,649, 1,412, 695 and 650 bytes, `refs/main` of 40 bytes, and two empty `.lock` files. `F` is `drwxrwxr-x irisowner irisowner`.
- No other cache: `/durable/iris/mgr/.fastembed_cache`, `/tmp/fastembed_cache`, `/durable/iris/mgr/fastembed_cache` and `/tmp/.fastembed_cache` do not exist.

## 6. Block

- `CHK|disconnect|ocutalon-ipm-e34s1f-<epoch>-<pid>_default|0`; `CHK|networks-after|[ ]` (`docker inspect` lists no network).
- `CHK|net-off|urllib.error.URLError: <urlopen error [Errno -3] Temporary failure in name resolution>` (error class: name resolution).

## 7. Control (new job, offline, no variable)

- `CHK|control-env|[]`.
- `CHK|control|error|ERROR <%AICore>EmbeddingUnavailable: Embedding provider is unavailable > ERROR <%AICore>ComponentUnavailable: Component unavailable: Failed to retrieve model.onnx`; `TIME 7-control 1s`.
- It created no folder: `CHK|fstat-7` equals `fstat-5`, and `find / -xdev -name .fastembed_cache -o -name fastembed_cache` found nothing (`CHK|other-caches-7|` empty).

## 8. Test (new job, offline, variable set before any %AI call)

- `CHK|test-env|/usr/irissys/mgr/fastembed/`
- `CHK|test|ok|rows=1|dot=1.0000003565312165498` (VectorStore `Probe.FastEmbedPath`, `AddDocument` of the runbook sentence with source `probe.md`, then `SELECT COUNT(*), MAX(VECTOR_DOT_PRODUCT(vector, vector))`); `TIME 8-test 2s`.

## 9. Worker (offline)

- `$SYSTEM.WorkMgr.Initialize("")` and `Queue("$$Run^ZFEProbe", F, "Probe.FastEmbedWorker")`, then `WaitForComplete()`: `CHK|wm-init|1`, `CHK|worker-sc|1|caller-job|1792`.
- `CHK|worker|808|/usr/irissys/mgr/fastembed/|ok|rows=1|dot=1.0000003565312165498`: the worker's `$JOB` (808) differs from the caller's (1792), it set the variable itself, and it embedded offline; `TIME 9-worker 2s`.

## 10. Order (recorded, not the stop rule)

- New job, offline: VectorStore `Probe.FastEmbedLate` built first (this loads the AI Hub library), then `os.putenv`, then `Create()` and a document.
- `CHK|order-env|/usr/irissys/mgr/fastembed/`, `CHK|order|ok|rows=1|dot=1.0000003565312165498`: the variable need not be set before the job's first `%AI` call, only before `FastEmbed.Create()`; `TIME 10-order 1s`.

## 11. No new download

- `CHK|fstat-11|size_kb=89012 files=11 list=45ef0f8aa0c5`, equal to step 5's; `CHK|unchanged|yes`; `CHK|net-final|[ ]` (still no network).

## What is not measured (inference)

- That the Python package `fastembed` (Story 19.2) reads the same folder through its `cache_dir` is inference; Story 19.2 measures it.
- The model folder is created by the install step in the run above by hand; the installer step itself is Story 19.2's.
- The run is on ARM64 (the developer machine); the x64 runner is not measured.
