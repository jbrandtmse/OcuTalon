---
title: 'Epic 19 burn-down: the IPM install imports the pinned packages, and the docs name the hosts it contacts'
type: 'bugfix'
created: '2026-11-07'
status: 'done'
baseline_revision: '43df7710cb0f204d2935a7d5f45b02505c2f6943'
baseline_commit: '2a8d0caba2ea817722b3efba8846f00c49fb18cb'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-6-extract-text-from-pdf-and-word-files-with-embedded-python.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/19-6-task0-extraction.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The two sample-output blocks of docs/install-ipm.md show an install without the six `STEP Python replaced <name> <old> with <pin>` lines that a plain instance's second command now prints between `Reload START` and `requirements.txt START`.
    evidence: |-
      evidence/19-8-task0-install-accuracy.md (M3): path A's second run and part p's second command print the six lines on a plain build 154 instance. The blocks are real runs of an earlier build (DW-784); this story may edit only the host list and the disclosure bullet of the page (Epic 17 edits the rest), and test-cpf rule 9 reads only the STEP lines inside Configure, so nothing fails.
    location: >-
      docs/install-ipm.md:151
    severity: low
  - summary: >-
      A process that imported the old requests, urllib3 or certifi before the step ran may lazily import from files the step removed, until it restarts.
    evidence: |-
      Edge Case Hunter (unverified). Path A and part p finish with Activate SUCCESS and IPM answers afterwards, but a registry install (forbidden here) downloads the module through ORAS in the same process before the Reload phase.
      What would settle it: a registry install of the package on a plain instance, run by the owner or the Planner.
    location: >-
      src/preload/cls/OcuTalon/Install/Ipm.cls (RemoveStaleCopies)
    severity: medium (unverified)
  - summary: >-
      The ipmcheck section of the release record says "the CI job ipm-install runs the same command" as release/ipm-install.sh with no argument, but since the CI split that job runs modes a and r and ipm-install-p runs b and p.
    evidence: |-
      Edge Case Hunter and Verification Gap, rework iteration 2. release/release.sh prints the sentence and docker/tests/test-release-sequence.sh pins it (the "ipmcheck pass: the command line" case). The release-tool freeze keeps release/release.sh and the test of it unchanged in this item.
      What would settle it: a Planner ruling on the wording (RELEASE TOOL), then one sentence in release.sh and its pin.
    location: >-
      release/release.sh:940, docker/tests/test-release-sequence.sh:1901
    severity: low
---

<intent-contract>

## Intent

**Problem:** On an IPM install, IPM 0.10.10 runs `pip install -t <mgr>/python` without `--upgrade`, and `<mgr>/python` already holds older copies of six pinned distributions (certifi, charset_normalizer, idna, requests, typing_extensions, urllib3; IPM's own ORAS dependencies). pip skips a top-level folder or file that already exists, so the older code may be what Python imports, beside the pinned dist-info. README sentence A5 ("the same Python packages, at the same versions") and AD-23's "the IPM path installs exactly the licence-measured set" depend on it (DW-829). The README and `docs/install-ipm.md` name three hosts (pypi.org, files.pythonhosted.org, huggingface.co), but nobody has measured which hosts the downloads are redirected to (DW-830).

**Approach:** Measure first (Task 0): an import check in check 32's area of `release/ipm-install.sh` records each of the six modules' `__version__` and `__file__` on the local-artifact IPM install. HEAD-only `curl -sI` probes record the hosts in the `Location` headers of the Hugging Face resolve URLs and of pip's wheel URLs. If the pinned copies are imported, the import check becomes part of the gate and A5 stays. If they are not, fix the install, never the sentence. The fix is an early install step, run just before IPM's pip step, that removes stale copies of pinned distributions (any version other than the pin) whose files no other distribution claims. The same import check then gates the result. The docs name exactly the hosts that were seen, and any change to them is PUBLIC TEXT.

## Boundaries & Constraints

**Always:**
- Every IPM run is a local-artifact install: `release/ipm-install.sh` (folder path `a`, and part `p` with its own packaged artifact or `OCUTALON_IPM_ARTIFACT`). Never use the public IPM registry: no `zpm "install ocutalon"` after `enable -community`.
- Probes are HEAD requests only (`curl -sI`, also with `-L` to follow redirects). No model or wheel body is downloaded outside the install itself.
- `requirements.txt` stays the measured set: the same 36 pins as both constraints files.
- The stale-copy step (built only when Task 0 measures a stale copy) removes only a distribution whose normalized name is a pin of the module root's `requirements.txt` and whose version differs from the pin. It removes only that distribution's top-level items (files and folders) that no other distribution's RECORD in the folder claims, together with its own dist-info folder. It never touches `bin/`, a path outside the target folder, a distribution at the pinned version, or any other distribution. With no `requirements.txt` at the root (the Docker image path), or with `-bypass-py-deps`, it removes nothing. It prints nothing, never throws, and returns OK, so a failed removal leaves the install exactly as it is today.
- The step is ObjectScript only: no Python, no `$ZF`, no network (AD-6).
- README.md and `docs/install-ipm.md` change only in the scope of Story 19.6's rulings B1 and B2 (the IPM paragraph A4 and the "What you need" bullet A6). Any change to their wording is PUBLIC TEXT, built as proposed, in a separate last task.
- Every test added or changed creates and removes its own state (its own scratch folder and files) and passes on a fresh environment, in either order.

**Never:**
- Never reword A5 to fit a stale install. That is allowed only as the HALT proposal below.
- No `docker/Dockerfile` or `docker/licences/**` edit (Lane B; read only). If the image shows the same issue, it is reported, not fixed.
- Nothing from Stories 19.4, 19.5 or 19.7, and nothing that depends on them (this is part 1's last story).
- No `--upgrade` in either manifest, no change to the install command, and no new user-facing text without the PUBLIC TEXT route.
- No new `AD-n`. Spine edits are plain unions marked `[AMENDED 2026-11-07, Story 19.8, ...]`.

## I/O & Edge-Case Matrix

`RemoveStaleCopies(root, bypass, target)` on a scratch target folder, with `root/requirements.txt` pinning `requests==2.34.2`, `typing_extensions==4.16.0`, `charset-normalizer==3.5.2` and `protobuf==7.36.2`:

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stale folder package | `requests-2.31.0.dist-info` (RECORD lists `requests/...`), `requests/` with an extra unrecorded `__pycache__/x.pyc` | `requests/` (whole) and `requests-2.31.0.dist-info` are gone | none |
| Pinned already | `requests-2.34.2.dist-info` and `requests/` | nothing removed | none |
| Both versions | stale and pinned dist-info of one name, one `requests/` | the stale dist-info and `requests/` are gone; the pinned dist-info is kept | none |
| Single-file module | stale `typing_extensions-4.12.2.dist-info`, `typing_extensions.py`, `__pycache__/typing_extensions.cpython-312.pyc` beside another module's `.pyc` | the `.py`, its `.pyc` and the dist-info are gone; the other `.pyc` and `__pycache__/` are kept | none |
| Top-level native file | stale charset_normalizer RECORD lists `charset_normalizer/` and a top-level `<hash>__mypyc.cpython-312-*.so` | both are gone | none |
| Shared folder | stale `protobuf-5.0.0.dist-info` lists `google/protobuf/...`; `googleapis_common_protos-1.0.dist-info` lists `google/api/...` | `google/` is kept and the stale dist-info is gone | none |
| Not pinned | `oras-0.2.25.dist-info`, `jsonschema-4.0.dist-info` | untouched | none |
| `bin/` and outside paths | stale RECORD lists `bin/normalizer` and `../../x` | `bin/normalizer` is kept and nothing outside the target is touched | none |
| No RECORD | stale dist-info without RECORD | nothing of it is removed | none |
| No requirements | root without `requirements.txt` | nothing removed | none |
| Bypass | `bypass` = 1 | nothing removed | none |
| Bad input | target missing, root `""` | returns OK and removes nothing | never throws |
| Integration: consumer IPM's pip step (Rule 1) | path A's second run and part p's install in OCUTALON, from the unfixed plain image's `<mgr>/python` | the six import the pinned copies: each `__file__` is under `<mgr>/python` and matches the pinned dist-info's RECORD hash, and `__version__` (where defined) equals the pin. Check 32 PASS | check 32 FAIL names the module |

</intent-contract>

## Code Map

- `release/ipm-install.sh:96-103` -- the header's check 32/33 text (extend 32). `:486-518` `manager_directory`, `stage_licence_gate`, `snapshot_python_before` (the folder's dist-info list in `/tmp/ocutalon-python-before.txt`). `:520-579` `check_licences` (check 32): a container `python3` heredoc symlinks the gated dist-infos into a scratch folder. Its skip rule is `if entry in before and pins.get(norm(name)) != version` (NOTE, not gated). `:582-613` `check_extract` and `check_memory` show the session-probe form (`check_session`, `chk`, `##class(%SYS.Python).Import(...)`). The call sites are `:1730-1737` (path A: `snapshot_python_before`, then the second run, then `check_licences "install checks"`) and `:1539-1555` (part p). Path b runs no check 32.
- `src/module.xml`, `module.xml` (root) -- identical except `SourcesRoot` and `Name="src/"`. They hold `<Resource Name="OcuTalon.Install.Ipm.CLS" Directory="cls" Preload="true"/>` and the Invokes `MapAndStop` (Initialize After), `Registry.Ipm` (Configure After) and `UnmapRepos` (Unconfigure Before). `src/module.xml` is `shared_by_region` (an appended line is a plain union).
- `src/preload/cls/OcuTalon/Install/Ipm.cls` (65 lines; Epic 15's preload class, compiled before Initialize) -- `MapAndStop`, `MapRepos`, `UnmapRepos`. The new method goes here: it is the only OcuTalon code that IPM has compiled before the Reload phase.
- IPM 0.10.10 (decoded from `docker/ipm/zpm-0.10.10.xml`, read only):
  - `%IPM.Lifecycle.Base:%Reload` calls `InstallOrDownloadPythonRequirements(tRoot, .pParams)`, which runs `PipInstall` with `install -r requirements.txt --python-version <v> --only-binary=:all:` plus `pParams("ExtraPipFlags")`. It returns early when `pParams("BypassPyDeps")` is set.
  - `%IPM.Utils.Module:PipInstall` inserts `-t <mgr>/python`.
  - `%IPM.Storage.Module` phase loop: Invokes with `When="Before"` run before the lifecycle's `%<Phase>`, so a `Phase="Reload" When="Before"` Invoke runs just before pip. A first run in USER stops at Initialize (`MapAndStop`), so it never reaches Reload.
  - `%IPM.Storage.InvokeReference:GetArgsArray`: `<Arg>${root}</Arg>` is `Module.Root`, which `ExecutePhases` sets from `pParams("RootDirectory")`. A module `<Default Name="X" Value="..."/>` is overridden by `pParams("X")`, so `${BypassPyDeps}` can carry the flag (inference until Task 0 M4).
  - `ExecutePhases` also merges a manifest `<Parameter>` default into `pParams`. So a module could set `ExtraPipFlags` itself (inference, unmeasured; Story 19.6's "a module cannot add --upgrade" was read from the call site only; see Design Notes for why F1 is not used).
  - `IPM.Installer:InstallORASIfMissing` puts IPM's ORAS packages into `<mgr>/python` at IPM load. That is the source of the six older copies and the five unpinned ones.
- `requirements.txt` -- the 36 pins (header comment, then `name==version`). Its pin lines equal `docker/licences/constraints-arm64.txt`'s.
- `docker/Dockerfile:20-30` (Lane B, read only) -- pip `--target /usr/irissys/mgr/python` at build, gate on that folder. At runtime the after-start loads IPM into the durable `<mgr>` (`/durable/iris/mgr/python`). A worker's `sys.path` holds both (19.6 evidence M1). Which copy of the six the image imports depends on their order (measured in Task 0 M5).
- `src/ocutalon/cls/OcuTalon/Memory/Embedder.cls:28-35` -- `SOURCE` `Qdrant/all-MiniLM-L6-v2-onnx`, `PATTERNS`, `SNAPSHOTFILES` (model.onnx, tokenizer.json, config.json, tokenizer_config.json, special_tokens_map.json). No revision is pinned, so the install resolves `main`. The commit measured in 19.2 was `d13954661f83248295ba75c1ed411eef3b7b936e`.
- `src/ocutalon/python/ocutalon_memory.py` -- `download()` = `huggingface_hub.snapshot_download(source, cache_dir, allow_patterns)`. hf-xet 1.8.0 is pinned, so Xet-backed files may go through Xet hosts.
- `README.md:182` (A4) and `:330` (A5), `docs/install-ipm.md:9` (A6) -- the ruled lines. `docker/tests/test-release-sequence.sh:2918-2920` pins all three whole-line (`grep -cxF`). The figures-match test follows them (`:2906` area).
- `docker/tests/test-cpf.sh:9-25,114-170,567` -- manifest rules 4, 5, 8 and 13 (exact Invoke lines per phase; "no other Invoke at Initialize/Configure"). A Reload Invoke breaks none of them. The new rule goes here (Rule 2 sibling). `:250-272` holds the synthetic-manifest samples.
- `docker/tests/test-pinned-sources.sh` -- the root vs `src` manifest drift rule (an identical Invoke line passes). `docker/tests/test-release-sequence.sh:2482` builds synthetic manifests for `ipmlib`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:751` (AD-21 "The FastEmbed model" bullet) and `:800` (AD-23 Rule, the Story 19.6 union ending "...runs the licence gate on what IPM installed.]") -- where the unions go.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first; product default 5). Use one lane-C throwaway `OCUTALON_RUN_TAG=e19s8i0` (Verification's lane variables). Write the results to `_bmad-output/implementation-artifacts/evidence/19-8-task0-install-accuracy.md` (ASCII, no local path).
  - M1 (DW-829). First build the import check (task below) in report form, then run `release/ipm-install.sh a` on the unfixed tree. For each of the six, record `__version__` (or `-`), `__file__`, the dist-infos of that name in `<mgr>/python`, and pinned yes or no.
  - M2 (safety, from M1's run). Use a temporary NOTE block in `snapshot_python_before`, applied from your own backup and reverted byte-identical after the run. Record:
    - each dist-info in `<mgr>/python` before the install, with its version;
    - the top-level items that the 36 pins share with that folder (what `--upgrade` would replace, `bin/` and any namespace folder such as `google/` included);
    - each `Requires-Dist` of a pre-existing distribution on one of the six, and whether the pin satisfies it (`packaging.specifiers`);
    - whether `oras.provider` imports before and after.
  - M3 (fix wiring, only if M1 shows a stale copy). With the fix built, run `a` again. The six now import pinned copies, and the stale dist-infos are gone.
  - M4 (Invoke arguments). In OCUTALON after M3, evaluate the new Invoke's arguments with `GetArgsArray`, with `pParams("BypassPyDeps")` unset and set to 1. Record `${root}` and the flag.
  - M5 (image, read only). On the warm throwaway `e19s8iw` (its project from `ci/warm.sh status`), open an OCUTALON session and record the six's `__version__`/`__file__`, `sys.path`'s order of the two `mgr/python` folders, and the dist-infos of the six in each folder.
  - M6 (DW-830, from the host). Record status, every hop's `Location` host and any `X-Repo-Commit`, `X-Xet-*` and `Link` header hosts for:
    - `curl -sIL --max-redirs 5` on `https://huggingface.co/Qdrant/all-MiniLM-L6-v2-onnx/resolve/main/<f>` for the five `SNAPSHOTFILES`, and on `resolve/<X-Repo-Commit>/<f>`;
    - `curl -sI` on `https://huggingface.co/api/models/Qdrant/all-MiniLM-L6-v2-onnx/revision/main`;
    - pip's wheel URLs for all 36 pins, from the host's pip: `pip install --dry-run --report <scratch>/r.json --no-deps --only-binary=:all: --python-version 3.12 --platform manylinux_2_28_aarch64` (and `..._x86_64`) `--target <scratch>/t -r requirements.txt` (index and metadata reads only, no wheel body). Then `curl -sI` each `download_info.url` and record its host and any `Location`. Also record the index host.
    - Label any host the client may use that a HEAD cannot show (for example Xet chunk transfer) as inference.

  **Decision rule (DW-829, the Planner's ruling of 2026-11-07):**
  - All six import pinned copies: skip the fix task. The import check joins check 32 and A5 stays.
  - Any stale copy: do the fix task. The same import check gates it.
  - **Stop rule:** if the fix does not make all six pinned on path A and part p by 2026-11-07T14:00Z, HALT `blocked` / `intent gap`. Give the evidence and this proposed answer, PUBLIC TEXT for the README A5 bullet: "- An IPM install puts the same Python packages, at the same versions, into the instance's `mgr/python` folder, each with its licence files; if that folder already held an older copy of one of them (IPM's own packages hold six), Python may load the older copy." The lead sends it.
- `release/ipm-install.sh` -- the import check (DW-829), in check 32's area. It is a function called right after `check_licences` at both call sites (path A, part p), labelled as check 32, and the header text of check 32 says so. For each of certifi, charset_normalizer, idna, requests, typing_extensions and urllib3, an OCUTALON session's Embedded Python imports the module (`%SYS.Python.Import`) and prints `__version__` (empty when undefined; typing_extensions defines none, inference) and `__file__`. The container's `python3` then checks against the pinned dist-info `<name>-<pin>.dist-info/RECORD`:
  - `__file__` is under `<mgr>/python`;
  - RECORD lists it with the same sha256 (urlsafe base64, unpadded);
  - `__version__`, when present, equals the pin.

  One NOTE line per module (`NOTE import <name> <version or -> <file relative to mgr/python> pinned|stale`), and one PASS, or a FAIL naming each stale module. `snapshot_python_before` also records whether `oras.provider` imports (%SYS session). The check then FAILs when it imported before and not after.
- (Only if M1 shows a stale copy) `src/preload/cls/OcuTalon/Install/Ipm.cls` -- new `ClassMethod RemoveStaleCopies(root As %String, bypass As %String = 0, target As %String = "") As %Status`. `target` defaults to `$SYSTEM.Util.ManagerDirectory()_"python/"`. It follows the Boundaries rule and the matrix:
  - pins come from `root_"requirements.txt"` (`name==version`, comments and blanks skipped, names normalized PEP 503 style: lower case, runs of `-_.` to `-`);
  - a dist-info folder's name and version come from `<name>-<version>.dist-info`;
  - a stale distribution's top-level items are the first segments of its RECORD paths (CSV, first field; quoted fields allowed), skipping absolute and `..` paths, `bin`, `__pycache__` and its own dist-info;
  - a folder goes whole and a file goes alone (with its `__pycache__/<module>.*.pyc`), only when no other dist-info's RECORD lists a path inside it (the pinned dist-info of the same name excepted);
  - then the stale dist-info goes.

  Doc comment: contract only.
- (Same condition) `src/module.xml` and `module.xml` -- one identical line after the `MapAndStop` Invoke: `<Invoke Class="OcuTalon.Install.Ipm" Method="RemoveStaleCopies" Phase="Reload" When="Before"><Arg>${root}</Arg><Arg>${BypassPyDeps}</Arg></Invoke>`, and `<Default Name="BypassPyDeps" Value="0"/>` as a child of `<Module>`, the form IPM 0.10.10 reads into `Module.Defaults` (M4 confirms it reaches the arguments). test-cpf rule 17 pins the Default line too while it is kept.
  - If M4 shows `${BypassPyDeps}` does not reach the arguments, drop the Default and that Arg, and record the residual risk (Design Notes).
  - If M4 or M3 shows `${root}` is not the folder that holds `requirements.txt`, HALT `blocked` / `intent gap` with the measurement (AD-23).
- (Same condition) `release/ipm-install.sh` `check_licences` -- the skip rule becomes "in the folder before and its name is no pin". A stale dist-info of a pinned name is then gated, so it fails the gate.
- (Same condition) `docker/tests/test-cpf.sh` -- new rule 17 (header line and samples, like rules 5, 8 and 13): `src/module.xml` holds that exact Invoke once, after the MapAndStop line, and no other Reload Invoke. A good sample and a breaking sample.
- (Same condition) `src/ocutalon/cls/OcuTalon/Test/Install/StaleCopies.cls` (new; area `Install`, already in `shard:lane-a@Checks,Install,Watch`) -- one test per matrix row. Each test builds its own folder under `##class(%SYS.System).TempDirectory()` with `zz-stale-*` names (a `requirements.txt` root and a target), passes both to `RemoveStaleCopies`, and removes the folder.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- plain unions. Then lint the spine; it must show no new finding.
  - AD-23, after the 19.6 union: `[AMENDED 2026-11-07, Story 19.8, DW-829]` with the M1 result. If fixed: the Reload-before step `Install.Ipm.RemoveStaleCopies` and why (pip `-t` keeps existing items). In either case: check 32's import check.
  - AD-21's FastEmbed bullet: `[AMENDED 2026-11-07, Story 19.8, DW-830]` with the measured download hosts.
  - If M5 shows that the image imports older copies, record that in the evidence and the frontmatter `deferred:` (a Lane B finding for the lead), and do not edit AD-23's "IPM's own Python packages don't clash (S11)".
- LAST, separate task (DW-830 docs; only if M6's hosts differ from pypi.org, files.pythonhosted.org and huggingface.co). Change the host clause of README A4 and `docs/install-ipm.md` A6 to exactly the hosts seen, using the PUBLIC TEXT items below with the measured host list. Update `test-release-sequence.sh:2918,2920` to the new whole lines. If the hosts are the same three, change nothing and record that.

- [x] [Owner] DW-856 (the Contest Planner's ruling of about 08:45Z; fixed in part 1, before the merge): `RemoveStaleCopies` removes a copy ONLY when IPM's pip step runs in the same lifecycle -- it removes nothing unless the pinned version of that distribution will be installed or is already importable. Approved release-tool hunk under the freeze: the Reload-invoke `cmd` argument (both manifests: `<Default Name="cmd" Value=""/>` and a third `<Arg>${cmd}</Arg>` on the Reload Invoke; `release/ipm-install.sh` `check_invoke_args` expects the third argument; measure that `${cmd}` reaches the method on a live IPM). Tests: (a) a reload with pip skipped and (b) a `-bypass-py-deps` load: in each nothing is removed, and afterwards IPM's own imports and `zpm "list"` still work; each shown red with the guard removed (mutation lines). Then re-run IPM paths `a`, `b` and `p` (local paths only).
- [x] [Owner] DW-857 (PUBLIC TEXT approved): in `docs/install-ipm.md` the disclosure bullet becomes EXACTLY: "- The second command puts these packages in the instance's shared Python folder, mgr/python in the IRIS install directory. Where that folder already holds other versions of certifi, charset_normalizer, idna, requests, typing_extensions or urllib3, which IPM installs for itself, the second command replaces them with the versions OcuTalon pins. IPM's own packages work with these versions." Update its fixed-strings pin and show a mutation red. The last sentence still rests on condition 2, checked against IPM 0.10.10.

- [x] [Owner] CI split 1 (the Contest Planner's ruling of about 13:35Z; discharges DW-826): a new iris group `shards-5` runs `shard:lane-a@Bridge,Agent`, so `shard:lane-a@rest` in `shards-2` no longer runs the Bridge and Agent areas. Add `shards-5` to `IRIS_GROUPS` and its `group` case in `ci/units.sh`, and to the iris matrix in `.github/workflows/ci.yml` (NOTHING else in ci.yml changes). Update whatever pins the group list (`docker/tests/test-ci-config.sh`: the matrix equals `ci/iris.sh groups`; `ci/changes.sh` if it maps groups). Raising any timeout stays excluded. Every area of the lane-a shard stays in exactly one piece.
- [x] [Owner] CI split 2 (approved release-tool hunk under the freeze; DW-864): `.github/workflows/lane-a.yml` gets a new job `ipm-install-p` beside `ipm-install`. `ipm-install` runs path A and `ipm-install-p` runs part p, its local-repository reinstall and the uninstall checks, each by passing an explicit mode to `release/ipm-install.sh` (it already takes `a|r|b|p`). CONDITIONS: `release/ipm-install.sh` with NO mode argument does EXACTLY what it does today, on every path; only CI's two jobs pass explicit modes; `release/release.sh`, `release/lib-release.sh` and every other caller stay unchanged; the two jobs' modes together cover exactly the no-argument run's checks (if the no-argument run also covers path B or another path, it goes in one of the two jobs). A test pins (a) the no-argument run covers the union of both modes' checks and (b) each mode alone runs only its own set. If the existing modes already give that, the release-tool hunk is none; if anything beyond a mode selection would be needed in `release/ipm-install.sh`, HALT `blocked` with an intent gap that gives the exact hunk (the lead sends it to the Planner as RELEASE TOOL).

**Acceptance Criteria:**
- Given the local-artifact IPM install (path A and part p), when check 32 runs, then each of the six modules imports the pinned copy (`__file__` under `<mgr>/python` with the pinned RECORD's hash, `__version__` equal to the pin where defined), and check 32 fails otherwise (DW-829).
- Given the unfixed tree, when Task 0 runs the import check, then the evidence file records `__version__` and `__file__` for all six and the decision taken. The import check's red on a stale copy is observed (on the unfixed tree, or under a mutation that skips the fix).
- Given a stale copy was measured, when the install's Reload phase starts, then `RemoveStaleCopies` removes exactly the stale pinned distributions' unshared items. IPM's ORAS packages still import, `bin/` and every other distribution are unchanged, and checks 30 to 33 and path b's checks pass.
- Given README A5, when the story is done, then A5 is unchanged, unless the stop rule HALTed.
- Given M6's measurements, when a reader opens README A4 and `docs/install-ipm.md` A6, then they name exactly the hosts seen (unchanged if the same three), and any change ships only as the ruled PUBLIC TEXT (DW-830).
- Given the image (read only), when M5 runs, then the evidence says whether the image imports pinned or older copies of the six.

### Review Findings

Code review 2026-11-07 (tier full-opus; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 0 decision-needed, 8 patch, 3 defer, 21 rejected.

- [x] [Review][Patch] The link guard accepted any folder inside the target, and the stale dist-info and `__pycache__` removals had no guard, so a link could lead the removal to another distribution or out of `<mgr>/python` (condition 1) [src/preload/cls/OcuTalon/Install/Ipm.cls:138] -- fixed: `IsOwnFolder` (a folder is removed or searched only when it resolves to itself in the resolved target), the dist-info goes through `RemoveItem`; tests `TestSymlinkInside`, `TestDistInfoSymlinkOutside`, `TestPycacheSymlinkOutside`; byte copy in `preload/`.
- [x] [Review][Patch] The IPM-import comparison of condition 2 passed on an empty or partial import record (a producer that prints nothing made both snapshots empty) [release/ipm-install.sh:769] -- fixed in `check_python_moves` and `check_uninstall_python`: an empty record, or one that lists other modules after than before, fails; test-cpf rule 18 cases.
- [x] [Review][Patch] The uninstall comparison of condition 3 had no hermetic test [release/ipm-install.sh:1881] -- test-cpf rule 18 mode `uninstall` (the two resources may go; a distribution gone, changed or added, a top-level item gone or added, a lost import and an empty record fail).
- [x] [Review][Patch] The folder-state producer `python_state` was unpinned, so a broken digest or lost `T` lines would silently disable the comparisons [release/ipm-install.sh:533] -- test-cpf rule 18 mode `state`.
- [x] [Review][Patch] Part p's install from the local repository after the uninstall (condition 2) was not pinned by rule 19 [docker/tests/test-cpf.sh:844] -- rule 19 now requires `run p-again` after `check_uninstall_python` and its stop check after it.
- [x] [Review][Patch] `TestBadInput` called the step with no target, so its default reached the shared instance's real `<mgr>/python` path (Rule 19 hermeticity) [src/ocutalon/cls/OcuTalon/Test/Install/StaleCopies.cls:235] -- the call passes the fixture target; the "nothing is removed" assert follows it.
- [x] [Review][Patch] The AD-23 union of Story 19.8 had no closing bracket, so it ran into the existing judges' compose sentence [ARCHITECTURE-SPINE.md:800] -- bracketed like the 19.6 union (own text only).
- [x] [Review][Patch] DW-853: the two sample-output blocks of `docs/install-ipm.md` lacked the six `STEP Python replaced` lines [docs/install-ipm.md:152] -- added between `Reload START` and `requirements.txt START`, copied from this review's path b log (the same lines as the evidence's M3 block); Epic 17's `STEP Digest OK` hunks are about 45 lines away, a plain union.
- [x] [Review][Defer] A lifecycle command that reaches Reload but is not install, load or update runs the step while IPM skips pip [src/preload/cls/OcuTalon/Install/Ipm.cls:76] -- deferred: DW-856 escalated (fix needs a `cmd` argument, a live IPM measurement and a release hunk the freeze bars).
- [x] [Review][Defer] The step replaces any pinned name at any other version (newer, another application's), while the ruled disclosure names only older copies of the six [src/preload/cls/OcuTalon/Install/Ipm.cls:110] -- deferred: DW-857 decision-pending (spec Boundaries against ruled text).
- [x] [Review][Defer] No IPM check asserts the STEP Python lines in the real install log [release/ipm-install.sh:826] -- deferred: DW-858 wontfix-accepted (the check needs a release hunk the freeze bars).

Rejected:
- `false`: B6/VG5: `-bypass-py-deps` might not reach the step, or the Default might override it. IPM's modifier sets `pParams("BypassPyDeps")=1` (dataAlias), `GetCustomParameters` prefers `pParams` over a `<Default>`, a `<Default>` is never merged into `pParams` (only `<Parameter>` is), and M4 measured `GetArgsArray`.
- `false`: B5: the public `target` argument lets a caller delete any tree. A caller who can run class methods can delete those files with `%File` already, and the manifest passes no target.
- `false`: E14: the folder comparison fails when a stale distribution's top-level item is absent from the pin (a mypyc `.so`). The stale charset_normalizer 2.1.1 is pure Python (evidence M2); a future case fails loudly.
- `false`: VG: the reinstall's negated grep passes on a missing file. The `Activate SUCCESS` grep on the same file fails first.
- `false`: VG: QA's additions are uncommitted. That is the stage protocol; the lead commits.
- by-design: B1/E6/AA5: with a shared folder the stale dist-info goes and the STEP line is written while `google/` stays. This is the matrix row "Shared folder" and the Residual risks; there is no overlap in the 36 pins (M2).
- by-design: B8/VG6/AA1: no ORAS operation is exercised, `p-again` stops at Initialize, and path A has no repository install. Condition 2 is gated as ruled (top-level imports, `zpm "list"`, a local-repository install); the local repository is a folder and needs no Python; an ORAS call needs a local OCI endpoint.
- by-design: E3: a failed pip step leaves the six absent. This is in the spec's Residual risks. The same command restores them for local and default-registry installs, which import no oras before Reload.
- by-design: VG: AC4 rests on Story 19.6's mutation and AC6 is a measurement. The spec's Verification says so.
- `low`: B7: `check_imports` drops a Python traceback. It still FAILs; the fix adds a branch.
- `low`: small: test-cpf's rule 18 data uses idna 3.15 as the pin. The data is self-consistent; this is cosmetic.
- `low`: E11: PEP 440 spellings (1.0 against 1.0.0). This is the same as the implement review's row: none of the 36 pins needs it.
- `low`: E12: `python_state` raises when `<mgr>/python` is missing. It fails loudly, and IPM always creates the folder.
- `low`: VG7: the always-OK status asserts. They can fail against a mutation of the wrapper's `Quit`; this was triaged in implement.
- `low`: VG: `check_ipm_alive "."` after the uninstall. The error-token half carries the check (implement triage).
- theoretical: B4: only `bin` and `__pycache__` are protected. It would be real if a pinned distribution's RECORD named a shared data folder (`share/`, `include/`) that unrecorded files of others use.
- theoretical: E8: a nested link inside a stale package folder is followed by `RemoveDirectoryTree`. It would be real if an operator linked a folder inside a pinned package; wheels hold no links.
- theoretical: E10: a dangling top-level link. It would be real only for a hand-made link.
- theoretical: E4: other processes importing during the seconds between the step and pip. It would be real if another application's process imports requests from `mgr/python` during a first install.
- theoretical: E5/DW-854: a process that imported the old modules lazily imports removed files. By code read of IPM 0.10.10, only `IPM.Installer` (at IPM load, another process) and the ORAS repository classes import oras or requests; a local-artifact or default-registry (`%IPM.Repo.Remote`, HTTP) install imports none of the six before the step. It would be real for an install from an ORAS-type repository.
- reported: AA3: release hunks beyond the literal freeze list (`check_invoke_args`, `check_reinstall`). They are listed for the orchestrator in the review's Decisions; no change.

Code review 2026-11-07, rework re-review (iteration 1; diff `2a8d0cab..HEAD`; tier full-opus; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 0 decision-needed, 4 patch, 1 defer, 11 rejected. No high.

- [x] [Review][Patch] Rule 19 pinned the calls of `check_pip_skipped` but not the reload run line, the import record taken before the runs, the decoy's RECORD (the pinned idna's package) or the checks of `check_nothing_removed` (STEP line, folder, version-and-hash imports, `zpm "list"`), so DW-856's live tests (a) and (b) could stop testing anything with every static check green [docker/tests/test-cpf.sh:856] -- fixed: `pins_wired` pins those lines of `check_pip_skipped`, `plant_stale_copy` and `check_nothing_removed`; eight new breaking samples.
- [x] [Review][Patch] Rule 17's "no Default" sample removed both Defaults, no sample had two `cmd` Defaults, and its comment still said "the exact Default once" [docker/tests/test-cpf.sh:603] -- fixed: the sample removes only the BypassPyDeps Default, a `cmd`-twice sample, the comment.
- [x] [Review][Patch] The evidence said every command but install, load and update returns at once from IPM's pip method; the wheel export (`download` set) runs `pip download` into the module root's `wheels/` for any command [_bmad-output/implementation-artifacts/evidence/19-8-task0-install-accuracy.md:190] -- fixed: one sentence (read from IPM 0.10.10's `InstallOrDownloadPythonRequirements`; it never writes `<mgr>/python`).
- [x] [Review][Patch] The evidence's "Unmutated" path A run is the one from before the rework's review patch, unlabelled [_bmad-output/implementation-artifacts/evidence/19-8-task0-install-accuracy.md:215] -- fixed: labelled, and the run after the patch added.
- [x] [Review][Defer] Path A's `check_pip_skipped` adds about 64-68 s locally, likely about twice that on x64 CI, where the `ipm-install` job ran 1889-1950 s of its 35-minute timeout; the job's no-argument sequence (`check_pip_skipped`, then `reinstall_failures`) has not run at this head [release/ipm-install.sh:2165] -- deferred: DW-864 escalated (REL-4's 35 minutes is owner-fixed value 9; the first CI run at this head settles it).

Rejected (rework re-review):
- `low`: the triage row's "`baseline_commit` is the story's" reason against the frontmatter, `review_loop_iteration` 0 against the cycle log's 1, the rework review's counts (17 of "19"; 2 medium patched, not 3). Lead bookkeeping in the spec; the lead set `baseline_commit` to the rework's baseline for this re-review.
- `low`: the rework's "Verification performed" names suites its Verification lines do not record. This review ran them at this head: `test-release-sequence.sh` (all rules, 341 s), `test-ci-config`, `test-compose-file`, `test-readme`, `test-boundaries`, `test-pinned-sources`, `test-class-rules`, `test-cpf`; all pass.
- `low`: the evidence's probe paragraph is hard to read. Cosmetic; the probe was in a scratch copy, nothing of it is tracked.
- `low`: `check_nothing_removed` reads the manager directory again and leaves two state files under the throwaway container's `/tmp`. One session per row; the container is torn down.
- `low`: a Reload that fails before IPM's pip step (module.xml load, mapping) after the step removed copies. The Before-Invoke design of the first review, outside this rework's range and not high; the same class as the Residual risk "a failed pip step", and the same command restores them.
- by-design: the check 32 header text and the `check_pip_skipped "pip skipped"` call in path A's block are release hunks outside the literal function area; the Design Notes list them, and the checks cannot run without the call.
- by-design: `${root}` (Module.Root) against IPM's `pParams("RootDirectory")`. Carried from the first review; measured equal in every row.
- by-design: the plain import record, `zpm "list"` and Reload SUCCESS cannot go red for DW-856's defect on this image. The evidence says so; tests (a) and (b) each went red through the STEP line, the folder and the version-and-hash import check, as ruled.
- `false`: the spec's I/O matrix gives the old signature. The matrix is the frozen intent block; Design Notes and Verification carry the four-argument form.
- by-design: `update` is not run live. IPM 0.10.10's `Main.Update` sets `cmd` to `update` and `LoadQualifiedReference` sets it again (read by the Acceptance Auditor and this review); the unit test passes the value directly; `update` from the registry is outside this pass.
- `false`: the guard differs from IPM's pip condition. `InstallOrDownloadPythonRequirements` quits unless `cmd` is install, load or update (and on `BypassPyDeps`), the same list and case as `Replace`.

## Spec Change Log

- 2026-11-07 (lead): rework iteration 2 opened on the Contest Planner's rulings of about 13:35Z (CI splits: iris group shards-5; ipm-install-p); scope = the two CI-split [Owner] items only.

- 2026-11-07 (lead): rework iteration 1 opened on the Contest Planner's rulings of about 08:45Z (DW-856 guard, DW-857 text); scope = the two [Owner] items only.

- 2026-11-07 (implement, rework iteration 1): DW-856 and DW-857 done; see Verification "Rework iteration 1" and Design Notes "Decided in-stage (rework iteration 1)". No other item reopened.

- 2026-11-07 (lead, before implement): Task 0 measured ahead of implement (evidence committed); the Planner's rulings recorded under Design Notes "Rulings (2026-11-07 ...)": DW-829 fix with four conditions, the disclosure bullet, DW-830 Option 2 hosts.

## Review Triage Log

### 2026-11-07 -- Review pass
- verdicts: 43 findings -- high 0, medium 6, low 35, false 1, maybe-false 1
- findings:
  - Blind Hunter
    - `[medium]` `[patch]` Dist-info removed although an item failed to go (Replace ignores RemoveItem's result) -- fixed: `Replace` keeps the dist-info and writes no STEP line when an owned item still exists after the attempt, so the next call retries; the doc comment no longer claims a failed removal leaves the install as it was (`TestSymlinkOutside`).
    - `[low]` `[reject]` Empty `Catch {}` writes nothing -- spec-bound: the Boundaries and the Decided-in-stage note make the step quiet and always OK so a failure leaves today's state and check 32 shows it.
    - `[low]` `[patch]` `RecordTops` `$Translate(x, "", "/")` is a no-op -- the dead call is removed (RECORD paths use `/`).
    - `[low]` `[reject]` NormalizeVersion does not treat PEP 440 spellings (1.0 and 1.0.0) as equal -- hypothetical for the 36 current pins (path A's reinstall replaces nothing); the fix adds a parser, more than a direct correction.
    - `[low]` `[reject]` No test for the symlink guard, dist-info with several hyphens, a different spelling, a partial failure -- the symlink and partial-failure parts are patched (`TestSymlinkOutside`); the others have no reachable failure on the pinned set.
    - `[low]` `[reject]` "IPM's own packages work with these versions" is not backed for a registry install -- the sentence is the Planner's ruled text with condition 2 as its gate (imports, `zpm "list"`, local-repository install); the registry is forbidden here.
    - `[low]` `[reject]` Disclosure bullet omits that the replacement is permanent, `-bypass-py-deps` and what to do if another package needs the old versions -- ruled EXACT text.
    - `[low]` `[reject]` The two hf.co download hosts are not seen on real traffic (HEAD evidence only) -- ruled EXACT text (Option 2, "in our test installs"); the spine union labels the chunk hosts inference.
    - `[low]` `[patch]` Test label says "five hosts" while the expected string has six names -- label reworded.
    - `[false]` `[reject]` Artifacts dated 2026-11-07 while "today" is 2026-11-06 -- the project's rulings, the spec and its AMENDED markers are dated 2026-11-07 by instruction; no wrong date.
    - `[low]` `[reject]` Rule 17 placed before rule 14 and hard-codes the two manifest paths -- cosmetic; the script `cd`s to the root and checks both files.
    - `[low]` `[reject]` `check_python_moves` returns before writing the after-state when the manager directory is unreadable, so part p's later check crashes with a traceback -- that path is already a FAIL; only the message differs.
  - Edge Case Hunter
    - `[medium]` `[patch]` RemoveItem failure ignored, dist-info removed, STEP claims a replacement -- same root cause as Blind Hunter's first row; fixed there.
    - `[medium]` `[patch]` Partial removal leaves a half-removed package with no retry marker -- same root cause; fixed there.
    - `[low]` `[reject]` Pip step fails after the removal, IPM's requests/urllib3/certifi stay deleted -- documented residual risk in Design Notes (the same command repeated restores them).
    - `[low]` `[reject]` PEP 440 spelling -- same as Blind Hunter's row.
    - `[maybe-false]` `[defer]` Running processes that imported the old modules before the files go -- see deferred.
    - `[low]` `[patch]` `$Translate` no-op -- same root cause as Blind Hunter's row; fixed there.
    - `[low]` `[reject]` Another package without a readable RECORD may own a shared folder -- every pip-installed wheel has a RECORD; no reachable case.
    - `[low]` `[reject]` `requirements.txt` with a BOM or a `===` pin -- the file is the measured set; none of the 36 pins uses either.
    - `[low]` `[reject]` `check_ipm_alive` with pattern "." after the uninstall is vacuous -- the error-token check carries the assertion; an empty list has no text to match.
    - `[low]` `[reject]` `check_ipm_alive` ignores the session's exit status -- an unreadable session prints no list and no error token only if IRIS is down, which earlier checks already fail on.
    - `[low]` `[reject]` `check_python_moves` would fail on a future pin that drops a top-level item -- hypothetical for a later bump, which would update the check.
    - `[low]` `[reject]` State files split on whitespace -- no top-level entry of the folder has whitespace.
    - `[low]` `[reject]` `stale_step_declared` awk misses a multi-line Invoke -- the manifests keep one element per line (rule 8 and 13 share the form).
    - `[low]` `[reject]` Host regexp matches `.co` inside `.com` and reads every `pypi.org` line -- fails loudly on a mismatch, not silently; label patched separately.
    - `[low]` `[reject]` Host claims "in our test installs" are partly HEAD evidence -- ruled EXACT text.
    - `[medium]` `[patch]` "A failed removal leaves the install exactly as it is today" is false for a partial removal -- same root cause; fixed there (comment and behaviour).
    - `[low]` `[reject]` Boundaries say the step prints nothing, the code prints a STEP line -- the Rulings' condition 1 requires the STEP line and binds over the Boundaries line; recorded in Decided in-stage.
    - `[low]` `[reject]` Pinned dist's files are removed when stale and pinned dist-infos coexist -- that is the intended case (matrix "Both versions"); pip restores them.
    - `[low]` `[reject]` Idempotence holds only up to leading-zero spelling -- same as the PEP 440 rows.
    - `[low]` `[reject]` "IPM's own packages work" claim -- same as Blind Hunter's row.
  - Verification Gap
    - `[medium]` `[patch]` The resolve-to-inside-target guard has no isolated test -- `TestSymlinkOutside` added; mutations recorded below.
    - `[medium]` `[patch]` `TestIdempotent` cannot fail if the step does nothing -- the first call's STEP line and removal are asserted now.
    - `[low]` `[reject]` `AssertStatusOK` and the bad-input guards cannot fail -- the guards (`root = ""`, missing target) are redundant: with no pins or no folder nothing is removable; the status asserts pin "returns, never throws".
    - `[low]` `[reject]` Live check branches have no `mutation:` line -- Rule 19 asks one demonstrated mutation per AC, recorded below; each branch needs a full IPM stack per mutation.
    - `[low]` `[patch]` Label "five hosts" -- same root cause as Blind Hunter's row; fixed there.
    - `[low]` `[reject]` Hermeticity of the shell checks (state files under /tmp) -- fails closed and order-dependent by design of the script.
    - `[low]` `[patch]` `RecordTops` `$Translate` is a no-op -- same root cause as Blind Hunter's row; fixed there.
  - Intent Alignment (descriptive; four divergences logged as rows)
    - `[low]` `[reject]` "It prints nothing" versus the STEP line -- the Rulings (condition 1) bind.
    - `[low]` `[reject]` A third docs bullet beyond A4 and A6 -- the ruled DISCLOSURE bullet.
    - `[low]` `[reject]` `cas-server.xethub.hf.co` is from a `Link` header, not a redirect -- ruled Option 2 text.
    - `[low]` `[reject]` The licence gate's skip rule changed -- required by the spec ("the skip rule becomes ...").
- patches applied by the lead (the handoff subagent cannot be re-engaged): `src/preload/cls/OcuTalon/Install/Ipm.cls` and its byte copy `preload/cls/OcuTalon/Install/Ipm.cls` (keep the dist-info when an item stays; dead `$Translate` removed), `src/ocutalon/cls/OcuTalon/Test/Install/StaleCopies.cls` (`TestSymlinkOutside`, `TestIdempotent`), `docker/tests/test-release-sequence.sh` (a label).

### 2026-11-07 -- Review pass (rework iteration 1: DW-856, DW-857)
- verdicts: 19 findings (Blind Hunter 9, Edge Case Hunter 7, Verification Gap 3; the Intent Alignment report is descriptive and adds none) -- high 0, medium 3, low 12, false 2, maybe-false 0; the rows below group a finding with its repeats from other layers
- findings:
  - `[medium]` `[patch]` Blind Hunter, Edge Case (plant call), Verification Gap: rule 19 does not pin `plant_stale_copy` or the `-bypass-py-deps` run line, so either can vanish and both rows still pass -- test-cpf rule 19 now pins both lines (two new samples); mutation below.
  - `[low]` `[patch]` Blind Hunter, Edge Case (3 rows): a failed plant or removal leaves the decoy dist-info; `skip_imports` is an undeclared global -- the plant-failure branch removes the decoy, the final removal fails loudly, `skip_imports` is local to `check_pip_skipped`.
  - `[low]` `[patch]` Edge Case, Blind Hunter: the spine says `install` was measured "from a repository"; only the local repository was -- reads "from the local repository".
  - `[medium]` `[patch]` Blind Hunter, Edge Case, Verification Gap, Intent Alignment: `update` has no live `${cmd}` row -- the evidence now labels it an inference from the IPM source read (no live run: `update` and a registry install are outside this pass); the unit test passes the value directly.
  - `[low]` `[patch]` Verification Gap: the plain import record, `zpm "list"` and Reload SUCCESS never went red under the guard mutations -- the evidence says so (the STEP line, the folder and the version-and-hash import check carry the red; the other assertions guard other defects).
  - `[medium]` `[reject]` Edge Case: removal before a pip step that then fails leaves the names absent -- carried from the first review: the spec's Residual risks name it; the same command restores them.
  - `[low]` `[reject]` Blind Hunter, Edge Case: case-sensitive `cmd` match, padded values untested -- IPM 0.10.10 passes lowercase (measured); a mismatch removes nothing, the safe side.
  - `[low]` `[reject]` Blind Hunter: `target` moved from third to fourth -- every caller (two manifests, the tests) was updated; the old call form would remove nothing.
  - `[false]` `[reject]` Blind Hunter: the DW-829 spine amendment contradicts DW-856's -- the second union extends the first with the third argument; neither sentence claims the argument list is closed.
  - `[false]` `[reject]` Blind Hunter: `baseline_commit`/`review_loop_iteration` not updated -- `baseline_commit` is the story's, `baseline_revision` is this pass's; the loop count is 0.
  - `[low]` `[reject]` Blind Hunter, Edge Case: Docker path and registry install not run -- with no `requirements.txt` the step removes nothing, `cmd` is empty there; a registry install is forbidden here.
  - `[low]` `[reject]` Edge Case: `check_nothing_removed` returns early when the manager directory is unreadable -- it records a FAIL first; no false pass.
  - `[low]` `[reject]` Verification Gap: no hermetic scratch test of `check_nothing_removed` and `check_invoke_args`'s expected string -- both run live on path A and part p (and the guard mutations fail them); a docker-less harness for them is larger than the defect.
  - `[low]` `[reject]` Intent Alignment (descriptive): "or is already importable" has no code -- the Design Notes decision records why (the pip step in the same lifecycle installs the pin); the guard is the stricter reading.

### 2026-11-07 -- Review pass (rework iteration 2: the CI splits)
- verdicts: 17 findings (Blind Hunter 6, Edge Case Hunter 7, Verification Gap 4; the Intent Alignment report is descriptive and adds none) -- high 0, medium 3, low 12, false 2, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind Hunter, Edge Case Hunter, Verification Gap (one root cause): rule 20 says mode p adds only its packaging stack and each mode runs only its own set, but `ipm_modes_alone` read eight marker lines, a set-subset for a, r, b and nothing for p, so an extra gate or an extra p line passed -- patched: the gate pin `ipm_gates_pinned` (the seven tests of `$mode` in the main flow, with its own samples and a real-file check), the p-only whitelist (pkg-first, pkg-second, packaging stack, the continuation lines of its check_session) and the per-line count check for a, r, b (so a mode that repeats a line fails); residual: a check moved between blocks that share the same gates is read by review, not by the test
  - `[low]` `[patch]` Edge Case Hunter: a test of `$mode` that is not an `if` line (`[ "$mode" = a ] && cmd`, `case`) was read as ungated although the header says another form is an error -- patched: such a line sets `unknown` (exit 3); sample `modes.test-not-if`
  - `[low]` `[patch]` Edge Case Hunter: a one-line gate with `; else` printed the else part as a statement -- patched: `unknown` when the body has `; else `; sample `modes.else-oneline`
  - `[low]` `[patch]` Edge Case Hunter: `sort -u` hides a mode that repeats a line of the no-argument run -- patched with the count check above; sample `modes.dup-in-a`
  - `[low]` `[patch]` Blind Hunter: the PASS text of the recipe check in `test-ci-config.sh` still said eight groups, its FAIL text ten -- patched to ten
  - `[low]` `[patch]` Blind Hunter, Intent Alignment (timing): the `ci/units.sh` comment of `shards-5` gave no measured seconds -- patched: the comment names run 42373301364's class seconds for the move and the expected group seconds (inference until a run)
  - `[low]` `[reject]` Blind Hunter: the header comment of `.github/workflows/ci.yml` (line 2) still says nine groups -- the item allows no other change in ci.yml; the pins that count groups say ten
  - `[low]` `[reject]` Blind Hunter: rule 6 hardcodes `ipm-install=a,r ipm-install-p=b,p` while rule 20 computes coverage generically -- the split is the ruled design (Design Notes), rule 6 is meant to fail on a changed split and rule 20 to fail on lost coverage; a deliberate rebalance edits both
  - `[false]` `[reject]` Blind Hunter: no check ties the `ci.yml` matrix to `IRIS_GROUPS` -- `test-ci-config.sh` "matrix" pins the group list of ci.yml to `ci/iris.sh groups`; its mutation (shards-5 dropped from the matrix -> the matrix rule red) is recorded in `## Verification`
  - `[low]` `[reject]` Edge Case Hunter: `ipm_jobs_wired` compares the timeout and deadline lines of the two jobs in file order, so a reordering fails it -- it fails loudly, never passes a wrong pair, and the jobs are copies of each other
  - `[low]` `[reject]` Edge Case Hunter: each script run has its own 1,980 s deadline inside the job's 2,100 s, so a slow second run is cancelled by the job timeout without the script's summary -- the item keeps the timeout and the deadline as `ipm-install`'s; wontfix-accepted, reopen_if=a `lane-a` run cancels `ipm-install` or `ipm-install-p` at its job timeout (the local seconds put each job at 674 and 785 s, about 1,480 and 1,300 to 1,730 s on the runner)
  - `[low]` `[defer]` Edge Case Hunter, Verification Gap (Other findings): `release/release.sh:940` says the CI job ipm-install runs the same command as the no-argument run -- real after the split, but the fix is in `release/release.sh` and `test-release-sequence.sh:1901`, which the freeze keeps unchanged; deferred (low) for a RELEASE TOOL ruling
  - `[low]` `[defer]` Verification Gap (Other findings): same root cause as the row above -- recorded in the same deferred item
  - `[false]` `[reject]` Verification Gap: modes r and b were never executed before CI -- both ran on lane C in this pass (`r` 74 PASS, `b` 59 PASS, no hidden dependency on the skipped second-run state); the first CI run still measures their seconds on the runner
  - `[low]` `[reject]` Verification Gap (Other findings): the samples `bad-gate` and `and-gate` fail by the same exit-3 path -- two cheap samples of one rejection reason; no harm
  - Intent Alignment (descriptive): readings 2a (modes free between the jobs) and 2d (union covers, p adds its packaging stack) are the ones implemented; the "every area in exactly one piece" property of shards-5 is pinned by the existing shard-pieces rule of `test-ci-config.sh` (it ran green on the real `ci/units.sh`)

## Design Notes

**Architecture decisions:**
- AD-23: the IPM path installs exactly the licence-measured set; one install recipe.
- AD-21: the FastEmbed model download.
- AD-22: throwaways and tests.
- AD-6: no Python outside workers (the step is ObjectScript).
- AD-29: Lane A; the Dockerfile and licences are read only.
- No AC contradicts an AD. Stack: no new dependency or licence (Rule 5: no NFR tripwire).

**Integration ACs:** The step is an installer hook, not a service. Its consumer is IPM's own pip step, and the matrix's last row is the integration AC, observed by check 32 on a real IPM install.

**Consumed-by:** none (no later story reads it).

**Consumes:**
- 19.6: check 32 and `stage_licence_gate`;
- `requirements.txt`;
- the evidence on `<mgr>/python`;
- Epic 15: `Install.Ipm` and the manifests.

**Extend, don't copy:**
- The import check extends check 32's area: the same call sites, the `norm()` and pin parsing of `check_licences`' heredoc, and `check_session`/`chk`.
- `RemoveStaleCopies` sits beside `MapAndStop` in the one preload class; no new preload resource.
- test-cpf rule 17 follows rules 5, 8 and 13.
- `Test.Install.StaleCopies` follows `Test.Docs.Extract`'s own-temp-folder pattern.

**Decided in-stage:**
- Fix F2 (remove stale copies before pip), not F1 (`--upgrade`). F1 would need a manifest `<Parameter>` `ExtraPipFlags` (possible by the IPM code read, inference) or a changed install command (PUBLIC TEXT). What `pip -t --upgrade` also changes:
  - it deletes and replaces every top-level item of the 36 that already exists. That includes the whole `bin/` (other packages' scripts) and a shared namespace folder such as `google/` (protobuf is pinned), which would delete an instance's other `google-*` packages;
  - it does this on every reinstall;
  - it leaves the old dist-info folders, so `importlib.metadata` and the gate still see two versions;
  - an admin's own `-extra-pip-flags` replaces the module's.

  F2 is safe for an instance's own packages because it touches only distributions OcuTalon pins, only when their version differs, and only items no other distribution claims. M2 shows that IPM's ORAS dependencies accept the pinned versions, and the gate checks that `oras.provider` still imports.
- Reload/Before, not Initialize/After: it runs right before pip, never in a first run that stops at Initialize, and keeps test-cpf rule 5 ("no other Invoke at Initialize") true.
- The step is quiet and always returns OK, so a failure leaves today's state (the gate shows it). This avoids new user-facing error text.
- The import check takes the hash from RECORD, because `typing_extensions` defines no `__version__` and both dist-infos may exist. `importlib.metadata` alone could report the pinned version for old code.
- The import check covers the six that the ruling names. The stale-copy rule is generic over all 36 pins, so a future overlap is fixed the same way.
- No `ipm_artifact_check` change (B4's static check): part p's import check proves the artifact path end to end.
- Path b gets no check 32, but it must stay green (reinstall with the step in place).
- Implement stage (2026-11-07), in-stage decisions, each small and reversible inside this story:
  - The step's text is `STEP Python replaced <name> <old> with <pin>`, one line for each replaced distribution, written after the removal at Reload (before `requirements.txt START`). It is outside the Configure block, so `step_names` and test-cpf rule 9 do not read it, and a reinstall writes nothing. The Rulings give the STEP line without wording; this wording is install-log text for the operator, built as the Rulings' condition 1 asks.
  - Versions are compared after the leading zeros of their numeric parts are removed (`2025.01.31` is `2025.1.31`): pip writes the dist-info folder with the normalized version, and a pin may be typed either way. Without it a pinned copy would be called stale and replaced on every install. The ObjectScript step and both Python checks of the script do it.
  - Every dist-info of the same normalized name counts as the stale distribution's own, for the ownership rule (the Boundaries name the pinned one; two stale versions of one name behave the same).
  - `%File:FileSet` with includedirs returns every folder, not only the ones that match the wildcard, so the step keeps a folder only when its name ends in `.dist-info`. A folder is removed only when `ResolvePath` puts it inside the resolved target (a symlink out of the target is never followed); a `..` path is skipped before that as well.
  - Part p's pins and path A's pins for the import check come from the staged constraints file (`stage_licence_gate`), which the existing test pins to the same 36 lines as `requirements.txt`; part p's container has no staged `requirements.txt`.
  - `snapshot_python_before` also records the folder's entries (dist-info name and RECORD checksum, other top-level items) and whether IPM's packages import, and prints the dist-infos it found (part p's starting state). `check_python_pins` (imports of the six, folder comparison, `zpm "list"`, the Invoke's arguments) runs right after `check_licences` on path A and part p; path A then runs the install command again (`check_reinstall`: no `STEP Python` line, the checks again). Part p runs `check_uninstall_python` after its uninstall and then `zpm "install ocutalon"` in USER once more (the install from the local repository still answers with its stop sentence). The reinstall adds one full install command to path A (about 75 s on a quiet host).
  - The uninstall (condition 3) removes only the two Python resources, so nothing was changed in it (evidence file).
  - `Test.Install.StaleCopies` runs the step through a redirected device to read its STEP lines, with every file below its own `zz-stale-<job>-<n>` folder.
  - The byte copy `preload/cls/OcuTalon/Install/Ipm.cls` (the root manifest's preload tree, pinned equal to `src/preload` by `test-pinned-sources.sh`) carries the same class.
  - The host-list match is a new pair of checks in `test-release-sequence.sh static`: the hosts in the README paragraph and the install page bullet are the same set, and that set is the five measured hosts plus `hf.co`.
  - IPM check time added (Verification, TIME lines): path A about 75 s, part p about 6 s.

- Rework iteration 1 (2026-11-07), in-stage decisions, each small and reversible inside this story:
  - `cmd` is the THIRD parameter of `RemoveStaleCopies(root, bypass, cmd, target)`, as the third `<Arg>` of the Invoke; `target` moves to the fourth place (only the tests pass it). The step removes a copy only when `bypass` is not set and `cmd` is install, load or update, the commands for which IPM 0.10.10 runs its pip step; an empty or missing `cmd` removes nothing. The Ruling's second clause ("or is already importable") needs no code: with the pip step in the same lifecycle the pinned version is installed in the stale copy's place.
  - Both manifests carry `<Default Name="cmd" Value=""/>` after the BypassPyDeps Default (the Ruling's form); test-cpf rule 17 pins both Default lines once each, the Invoke with its three arguments, and has samples for a missing argument, a missing Default and a Default with a value.
  - The IPM-path checks are one function, `check_pip_skipped`, called after `check_reinstall` on path A only (part p and path b run no check 32 extras). It plants a decoy stale `idna-0.0.1.dist-info` (its RECORD names the pinned idna's package), runs `zpm "reload ocutalon"` and `zpm "load -bypass-py-deps <module folder>"`, and removes the decoy. Each run is checked by `check_nothing_removed`: Reload SUCCESS, no `STEP Python` line, the folder's entries equal to the planted state, IPM's packages import as before, check 32's version-and-hash import check holds (the base image also keeps older copies of the six in the user's `~/.local`, so a plain import of idna passes with the pinned copy gone) and `zpm "list"` answers. Added IPM-check time on path A: about 70 s, almost all of the `-bypass-py-deps` load, which is a full install without pip. test-cpf rule 19 pins the wiring.
  - The disclosure bullet of the install page reads "other versions" (DW-857, exactly the ruled text); its fixed-strings pin in `test-release-sequence.sh static` is the new line.
  - The spine's AD-23 Story 19.8 union gained a second bracketed union marked `[AMENDED 2026-11-07, Story 19.8, DW-856]`. It is written without braces (a `${...}` form made the spine lint report two new template-token findings; the lint shows the same 10 findings as before).
  - Release hunks under the freeze, all in `release/ipm-install.sh`: `check_invoke_args` (third argument), the new `plant_stale_copy`, `check_nothing_removed` and `check_pip_skipped` in check 32's area (between `check_reinstall` and `check_extract`), the call after `check_reinstall` in path A's block, and the check 32 header text. Nothing else in `release/*.sh`.

**Declined:** DW-830's second half ("the docs do not say what a blocked download looks like"). The Planner's ruling of 2026-11-07 scopes DW-830 to the host list. A blocked-download sentence would be new PUBLIC TEXT that nobody has ruled. DW-829 and DW-830's host list are addressed by Task 0, the import check, the conditional fix and the last task.

**Footprint (for the lead's contract):**
- `src/preload/cls/OcuTalon/Install/Ipm.cls` and `docker/tests/test-cpf.sh`: Epic 15's files, outside `paths_hint`, no contended epic (`footprint_extensions`).
- `src/module.xml` (`shared_by_region`, one appended line) and root `module.xml`.
- `release/ipm-install.sh`: the ruling names check 32's area.
- README.md (Epic 11) and `docs/install-ipm.md` (Epic 17 contended): only the A4/A6 host clause, by rulings B1/B2, as PUBLIC TEXT.
- No `docker/Dockerfile` or `docker/licences/**` edit.

**PUBLIC TEXT needed (the last task; built as proposed, sent by the lead before commit; `<hosts>` is exactly M6's extra hosts, joined as "A" / "A and B" / "A, B and C"):**
- PUBLIC TEXT needed: README.md (A4) -- proposed: "The second run also downloads OcuTalon's Python packages from PyPI (fastembed, pdfplumber and python-docx with their dependencies, about 250 MB once installed) and the embedding model from Hugging Face (about 90 MB), so the instance needs network access to pypi.org, files.pythonhosted.org, huggingface.co and its download host <hosts>. In our test installs on an Apple silicon Mac, the downloads took about 20 seconds and the whole second run about 1 to 1.5 minutes." (for example `<hosts>` = cas-bridge.xethub.hf.co; "download hosts" if more than one)
- PUBLIC TEXT needed: docs/install-ipm.md (A6) -- proposed: "- Network access from the instance to PyPI (pypi.org and files.pythonhosted.org) and to Hugging Face (huggingface.co and its download host <hosts>): the second command downloads OcuTalon's Python packages, about 250 MB once installed, and the embedding model, about 90 MB. In our test installs on an Apple silicon Mac, the downloads took about 20 seconds and the whole second command about 1 to 1.5 minutes."
- If M6 shows an extra PyPI host, it joins the PyPI parentheses the same way. If the hosts are the three named today, there is no PUBLIC TEXT.

**Residual risks:**
- Between the step and pip, the removed names are absent. A failed pip step (no network) leaves them absent until the same command runs again.
- A pinned distribution whose top-level folder another distribution owns (a namespace folder) is still skipped by pip `-t`. M2 lists any overlap.
- `-bypass-py-deps` (if M4 refutes the Default): the step still removes stale copies.
- The pip `-t` skip behaviour is inference (pip's target-directory handling) until M1.

**Rulings (2026-11-07, the Contest Planner under the owner's delegation, about 03:05Z; relayed by the orchestrator). They settle Task 0's decision and the PUBLIC TEXT task; Task 0's measurements are DONE (evidence `_bmad-output/implementation-artifacts/evidence/19-8-task0-install-accuracy.md`, committed): reuse them, do not re-measure, except part p's starting state, which is still to measure.**
- DW-829 (owner decision): APPROVED. `OcuTalon.Install.Ipm.RemoveStaleCopies` runs before IPM's pip step, and README A5 stays, under these CONDITIONS:
  1. Its pinned list is READ FROM `requirements.txt` (nothing hard-coded). It never touches a file outside `<mgr>/python`. It is idempotent: a second install removes nothing. It writes a `STEP` line to the install log for each distribution it replaces.
  2. Snapshot every distribution in `<mgr>/python` before and after the install. Both times, import each top-level module of IPM's own packages (`oras.provider` and the rest: attrs, jsonschema, jsonschema_specifications, oras, referencing and the six). The only differences allowed are the six moving to the pinned versions, plus OcuTalon's own additions. `zpm "list"` and an install from the local repository must still work afterwards. Gate this in the IPM check (path A and part p).
  3. Uninstall: measure what OcuTalon's uninstall does to the six. IPM must still work after it (the same imports, and `zpm "list"`). If the uninstall removes the six, change it so it leaves them in place. Record the measurement in the evidence file.
  4. The version+hash import check (both `__version__` and the RECORD hash; urllib3's `__init__.py` is byte-identical across the two versions) gates path A and part p, in check 32's area.
- DISCLOSURE (new PUBLIC TEXT, ruled), in `docs/install-ipm.md` ONLY, directly after the "Network access ..." bullet in "What you need", EXACTLY:
  "- The second command puts these packages in the instance's shared Python folder, mgr/python in the IRIS install directory. Where that folder already holds older versions of certifi, charset_normalizer, idna, requests, typing_extensions or urllib3, which IPM installs for itself, the second command replaces them with the versions OcuTalon pins. IPM's own packages work with these versions."
  The last sentence stands ONLY if condition 2 passes; if it fails, HALT `blocked` with an intent gap naming it (the lead brings the bullet back to the Planner). README gets no matching sentence: exempt this bullet from the A4/A6 pairing test, and pin it with a fixed-strings test.
- DW-830 hosts: Option 2, EXACTLY, in both files (each is the same sentence/bullet as today with only the host list changed; the final sentences stay as ruled for Story 19.6):
  - README: "...so the instance needs network access to pypi.org, files.pythonhosted.org, huggingface.co and its download hosts under hf.co (in our test installs us.aws.cdn.hf.co and cas-server.xethub.hf.co)."
  - `docs/install-ipm.md`: "- Network access from the instance to PyPI (pypi.org and files.pythonhosted.org) and to Hugging Face (huggingface.co and its download hosts under hf.co, in our test installs us.aws.cdn.hf.co and cas-server.xethub.hf.co): ..."
  The HEAD evidence is in the Task 0 evidence file. The pairing test keeps the two host lists matched; update its fixed-strings pins.

### Rework iteration 2 (CI splits; decided in-stage)

Work ONLY the two unchecked `[Owner]` "CI split" items; do not re-derive or re-verify the rest. Lane C variables as in `## Verification`, with `OCUTALON_LOCK_OWNER='epic=19 stage=implement'`, fresh tag `e19s8x`, warm tag `e19s8xw` (the older tags `e19s8i`/`e19s8r` are history); never write an absolute local path into a tracked file. `release/ipm-install.sh` mode map (read from the script): `all` (no argument) = path A (first and second run, checks 1-6, 8-14, 19 and Story 19.8's checks, no reinstall_failures) + `reinstall_failures` (checks 16-20) + path B (7, 15, 19, 21-25) + part p (26-29, reusing the artifact path A packaged); `a` = path A without `reinstall_failures`; `r` = A's first and second run + `reinstall_failures`; `b` = A's first run + path B; `p` = part p alone (it builds its own packaging stack first when OCUTALON_IPM_ARTIFACT is unset). The existing modes give the split with no release-tool hunk: `ipm-install` runs `a` then `r` (path A and its reinstalls), `ipm-install-p` runs `b` then `p` (path B and part p), each a `run:` step with an explicit mode, `ipm-install-p` with its own `OCUTALON_RUN_TAG` ending `-ipm-p` (teardown matches by tag). Why not three modes `a`, `r`, `b` in one job: part 1's job log (run 42373301375) puts path A at about 1,170 s, path B at about 630 s and part p after it, so `a`+`r`+`b` would repeat the first and second run twice and pass 2,100 s; `a`+`r` is about 1,480 s and `b`+`p` about 1,500 s by the same log (inference until a CI run). The union test goes in `docker/tests/test-cpf.sh` (it already pins `lane-a.yml`'s job and `ipm-install.sh`'s no-argument run, rules 6, 7, 16, 19), whose rules that name the `ipm-install` job's single `run: bash release/ipm-install.sh` line are updated to the explicit modes. Mutation lines for every pinning test touched go in `## Verification` under `Rework iteration 2`.

## Verification

Lane variables go on every `ci/iris.sh`, `ci/warm.sh` and `release/ipm-install.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=19 stage=implement'`.

Every command runs in its own foreground call with `timeout: 600000`. If the harness moves a call to the background after about 180 s, poll its output in foreground loops under 170 s, and never start a second copy. One `iris_execute_tests` per message; `server` `ocutalon-slot-c` and `namespace` `OCUTALON` on every IRIS MCP call. The slot is used only for `iris_doc_load` compile checks (`baseDir` `.../src/preload/cls` for `Install.Ipm`).

Targets (lane C): `e19s8i0` (Task 0), warm `e19s8iw` (`ci/warm.sh up` once, `down` at the end, also after a failure), fresh `e19s8i`. Tear down only these. A manifest change refuses a warm run: `down`, then `up`.

**Commands:**
- (once) Task 0: `OCUTALON_RUN_TAG=e19s8i0 bash release/ipm-install.sh a`, then the M6 `curl -sI`/`pip --dry-run` probes from the host and M5's session on `e19s8iw`. Expected: the evidence file is filled and the decision rule applied. Then `ci/iris.sh teardown` for `e19s8i0`.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e19s8iw ci/iris.sh class OcuTalon.Test.Install.StaleCopies` -- expected: CLASS passed.
- (once) `OCUTALON_RUN_TAG=e19s8i bash release/ipm-install.sh a`, then `p`, then `b`, one call each. Expected: `a` and `p` check 32 PASS (gate, notices, import check, ORAS), and checks 30, 31 and 33 PASS; `b` every check PASS (check 24's known loaded-host flake: rerun once). Record each `TIME` line; a full run over 1,800 s is reported.
- (once) `OCUTALON_RUN_TAG=e19s8i ci/iris.sh live install-start` -- expected: PASS. The Docker path loads the manifest with the new Invoke and no `requirements.txt`, so nothing is removed.
- (once each) `bash docker/tests/test-cpf.sh`, `test-pinned-sources.sh`, `test-release-sequence.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh`, `test-compose-file.sh`, and `test-readme.sh` if the last task ran (all under `docker/tests/`) -- expected: PASS.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: no new finding.
- CI after the push (the lead): `lane-a` `ipm-install` job green on x64, under 35 minutes.

**Mutations (one per AC; apply from a backup, observe red, revert, confirm byte-identical with `git status --short` and `git diff --stat`):**
- AC1 and AC2: the unfixed tree (Task 0's run), or the Reload Invoke removed from `src/module.xml` once the fix exists -> the import check FAILs on `a` (each stale name listed). Removing the Invoke also turns `test-cpf.sh` rule 17 red. If no fix was needed, point the check at a wrong pin version for one module (for example certifi) -> FAIL names it.
- AC3: the version compare made always-equal -> `Test.Install.StaleCopies` "stale folder package" red. The ownership guard dropped -> "shared folder" red. The `bin`/`..` skip dropped -> "bin and outside paths" red.
- AC4: pinned by the existing `(DW-784, A5)` whole-line check of `test-release-sequence.sh static` (its mutation is recorded in Story 19.6); re-run it, no new mutation.
- AC5 (if the last task ran): one host in README A4 changed -> `test-release-sequence.sh static` red. Without the last task, the existing A4/A6 pins stand.
- AC6: a measurement (the evidence file's M5 section); no test.

**Shared surfaces:**
- the manifests' Invoke list (`test-cpf.sh` rules 5, 8, 13 and 17; `test-pinned-sources.sh`; `test-release-sequence.sh` `ipmlib` samples);
- `<mgr>/python` on an IPM install (checks 30 to 33);
- check 32's gated set and its NOTE lines;
- README A4/A6 (`test-release-sequence.sh` static A4/A6 and figures-match, `test-readme.sh`);
- the spine's AD-21/AD-23 bullets.

Every test added or changed passes on a fresh environment, in either order.

**Results (implement stage, 2026-11-07; the evidence file `evidence/19-8-task0-install-accuracy.md` holds the measurements):**
- `(once)` lines run after the last patch of `release/ipm-install.sh` (the TIME lines): `release/ipm-install.sh a` (all checks passed, 63 PASS: checks 30 to 33 included; `TIME second-ocutalon 76s`, `python-pins 1s`, `reinstall-same 71s`, `reinstall-checks 74s`) and `p` (all checks passed; `TIME p-fresh 184s`, `python-pins 2s`, `uninstall-python 1s`, `p-again 3s`).
- `(once)` lines run before that last patch (a patch of three `echo "TIME ..."` lines and two local variables) and not repeated: `release/ipm-install.sh b` (all checks passed, `OCUTALON_LIVE_DEADLINE=1980`; the six `STEP Python replaced` lines appear in its second merge's install output; `b` does not call the new functions); `bash docker/tests/test-release-sequence.sh` (all rules, 368 s), `test-pinned-sources.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh`, `test-compose-file.sh`, `test-readme.sh` (all PASS). `test-cpf.sh` and `test-release-sequence.sh static` were re-run after every later edit and pass. The spine lint shows 10 findings before and after (no new one).
- `OCUTALON_WARM=1 ... ci/iris.sh class OcuTalon.Test.Install.StaleCopies` passes (17 tests); `OcuTalon.Test.Bridge.CodeRules` passes. The warm stack `e19s8iw` was used for them and for the mutations, then taken down; no throwaway is left.
- `OCUTALON_RUN_TAG=e19s8i ci/iris.sh live install-start` did NOT pass on this host: it fails at row 4's last restart ("did not end ready within 200 s", load average 8 to 12), twice with the change and once with the Invoke and Default lines removed from `src/module.xml`. Its first rows pass, so the manifest with the new Invoke loads on the Docker path (see the evidence file). Left for CI.
- Two environment flakes seen and rerun: the stack's first session printing nothing right after `up` (aborted before any check, both times) and path A's check 13 ("start outside the step", `ReconcileIn` rows 0 to 0 then 1) on a loaded host; the final `a` run on a quiet host passes it.
- A part p run on the loaded host needs `OCUTALON_LIVE_DEADLINE=1980` (the packaging stack's first command took 342 s there).

**Mutations of this story (each applied from a backup, observed red, reverted; `git status --short` and `git diff --stat` equal before and after, and `src/preload/.../Ipm.cls` equal to its root copy):**
- mutation (AC1, AC2): the unfixed tree (the new checks, no Reload Invoke) on part p -> check 32 FAIL three ways: the gate (`certifi is installed at 2025.1.31 but pinned at 2026.10.23` and five more), the import check (`stale` for all six, urllib3 by its version only) and the folder comparison (`... is still in the folder` for the six). Also the Reload Invoke line removed from `src/module.xml` -> `test-cpf.sh` rule 17 red.
- mutation (AC3): the version compare made always-equal (`(1 = 1) Continue`) -> `TestStaleFolderPackage`, `TestBothVersions`, `TestSingleFileModule`, `TestTopLevelNativeFile`, `TestBinAndOutside`, `TestQuotedRecordField` and more red. The ownership guard dropped (`owned` never set) -> `TestSharedFolder` red ("the shared folder google/ stays ..."). The `bin` skip dropped -> `TestBinAndOutside` red ("bin/normalizer stays"). The `..` skip and the resolve guard dropped -> `TestBinAndOutside` red ("the target folder stays (the ../ path is not followed)").
- mutation (AC3, the Rulings' conditions): the STEP `Write` dropped -> `TestStaleFolderPackage`, `TestStepLines`, `TestPinsAreRead` red; the bypass test dropped from `Replace` -> `TestBypass` red ("with the flag 1 nothing is removed"); the leading-zero version rule dropped -> `TestVersionSpelling` red.
- mutation (AC4): `test-release-sequence.sh static` re-run with the A5 bullet unchanged: PASS (the existing `(DW-784, A5)` whole-line check; its mutation is recorded in Story 19.6). README.md has no other edit than the host list.
- mutation (AC5): `us.aws.cdn.hf.co` changed to `us.aws.cdn.hf.com` in README A4 -> `static` red ("(DW-784, A4)"); `cas-server.xethub.hf.co` dropped from the install page's A6 bullet -> `static` red; the disclosure bullet's last sentence changed -> `static` red ("(DW-829) the install page's bullet ... is the ruled text"); the words `shared Python folder` added to the README -> `static` red ("(DW-829) the README has no such bullet").
- AC6: a measurement (the evidence file's M5 section and its follow-up on the Docker path); no test.

**Review patches (lead, 2026-11-07):**
- mutation (AC3, partial removal): the dist-info removed although an item stays (`If 'kept,` dropped) -> `TestSymlinkOutside` red; the resolve guard of `RemoveItem` dropped on its own -> `TestSymlinkOutside` red; `Replace` made a no-op -> `TestIdempotent` red (its first call now asserts the STEP line and the removal). Each applied from a backup, reverted byte-identical (`git status --short` equal, the two `Ipm.cls` copies equal), and the class green again on the same warm stack.
- (once) lines run after the last patch: `release/ipm-install.sh a` (63 PASS; `TIME second-ocutalon 58s`, `python-pins 2s`, `reinstall-checks 54s`) and `p` (all PASS; `TIME p-fresh 146s`, `python-pins 1s`, `uninstall-python 0s`), `test-release-sequence.sh static`, `test-pinned-sources.sh`, `test-class-rules.sh`, `test-boundaries.sh`; `OcuTalon.Test.Install.StaleCopies` and `OcuTalon.Test.Bridge.CodeRules` on warm `e19s8iw`. Not repeated after the patch: `release/ipm-install.sh b`, `ci/iris.sh live install-start` (both passed before it: `b` 59 PASS in 439 s and `install-start` PASS in 451 s on the lead's re-run), `test-cpf.sh`, `test-ci-config.sh`, `test-compose-file.sh`, `test-readme.sh`, the spine lint (no file they read changed).
- The lead's first `p` run failed in its first command ("Error merging CPF file. $zf(-100) exited with 7", Initialize, before any Story 19.8 code ran); the rerun on the same tree passed. Recorded as a host flake.

**QA stage (2026-11-07; files marked (QA)):**
- (QA) `docker/tests/test-cpf.sh` -- rule 18 (the Python of `check_imports`, `check_python_moves` and `check_licences`' skip rule taken out of `release/ipm-install.sh` and run on scratch folders with no container: the pinned state passes, each stale state fails) and rule 19 (check_python_pins runs after check_licences on path A and part p, then the reinstall and the uninstall checks). Before this, check 32's import check, the folder comparison and the new skip rule were observed only on a live IPM install.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Install/StaleCopies.cls` -- `TestDotDotDoesNotBlock`, `TestNameSpelling`, `TestSymlinkToTarget` (21 tests now).
- Run: `OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Install.StaleCopies` and `OcuTalon.Test.Bridge.CodeRules` pass on warm `e19s8qw` (taken down); `test-cpf.sh`, `test-boundaries.sh`, `test-class-rules.sh`, `test-pinned-sources.sh` pass.
- mutation (QA, AC1 and AC2): the RECORD hash compare of `check_imports` dropped (`elif not listed:`) -> `test-cpf.sh` rule 18 (imports) red; the `__version__` compare dropped (`if False:`) -> rule 18 (imports) red.
- mutation (QA, the Rulings' condition 2): the RECORD checksum compare of `check_python_moves` dropped -> rule 18 (moves) red.
- mutation (QA, the gate's skip rule): reverted to `pins.get(norm(name)) != version` -> rule 18 (skip) red.
- mutation (QA, AC1 wiring): `check_python_pins "install checks"` deleted from path A -> rule 19 red.
- mutation (QA, AC3): the `..` skip of `RecordTops` dropped on its own -> `TestDotDotDoesNotBlock` red ("and so is the stale dist-info ..."; `TestBinAndOutside` stayed green, which is the gap this test closes); `RemoveItem`'s `<=` made `<` (a link to the target itself) -> `TestSymlinkToTarget` red; the lower-casing in `Normalize` dropped -> `TestNameSpelling` red. Each applied from a backup in the QA scratch folder and reverted byte-identical (`cmp` against the backup, `git status --short` equal, the two `Ipm.cls` copies equal); `release/ipm-install.sh` was edited only for the first five mutations and restored byte-identical each time (no QA edit remains).
- mutations_demonstrated=8.

**Rework iteration 1 (2026-11-07; DW-856 and DW-857; lane C, tags `e19s8r` fresh and `e19s8rw` warm, both torn down; `git status --short` and `git diff --stat` equal before and after each mutation, the two `Ipm.cls` copies equal):**
- `${cmd}` reaches the method (measured on a live IPM, the evidence file's "Rework iteration 1"): `load` for a load and for the reinstall, `reload` for `zpm "reload ocutalon"`, `load` with the flag 1 for a load with `-bypass-py-deps`, `install` for the install from the local repository (part p).
- Run: `OCUTALON_WARM=1 ci/iris.sh class OcuTalon.Test.Install.StaleCopies` (27 tests with `TestReloadPipSkipped`, `TestBypassLoad`, `TestLifecycleCommands`) and `OcuTalon.Test.Bridge.CodeRules` pass on warm `e19s8rw`. `release/ipm-install.sh a` 75 PASS (`TIME second-ocutalon 86s`, `reinstall-checks 107s`, `skip-reload 2s`, `skip-bypass 62s`, `pip-skipped 68s`), `b` 59 PASS, `p` 32 PASS (`TIME p-fresh 204s`), each in its own call, local paths only. `test-cpf`, `test-pinned-sources`, `test-class-rules`, `test-boundaries` and `test-release-sequence.sh static` pass; the spine lint shows the same 10 findings (no new one).
- mutation (DW-856, unit): the `cmd` guard dropped from `Replace` -> `TestReloadPipSkipped` red (reload, none, compile, uninstall and Install each removed the stale copy); the `bypass` guard dropped -> `TestBypass` and `TestBypassLoad` red; the list narrowed to install only -> `TestLifecycleCommands` red (load and update).
- mutation (DW-856, IPM path A): both guards dropped -> `release/ipm-install.sh a` FAIL for `reload (pip skipped)` (STEP line, folder) and for `load -bypass-py-deps` (folder); the `cmd` guard alone dropped -> the reload row FAIL (STEP line, folder, import check for idna); the `bypass` guard alone dropped -> only the `-bypass-py-deps` row FAIL (STEP line, folder, import check), the reload row passes.
- mutation (DW-856, test-cpf): the `<Arg>${cmd}</Arg>` removed from `src/module.xml` -> rule 17 red; the `cmd` Default given the value `load` -> rule 17 red; the `check_pip_skipped "pip skipped"` call deleted from path A -> rule 19 red. Each restored from the backup (`cmp` equal, `git status --short` and `git diff --stat` equal).
- Review patches (rework iteration 1): `mutation: test-cpf rule 19`: the `plant_stale_copy` call replaced in `check_pip_skipped` -> rule 19 red; the `run skip-bypass` line deleted -> rule 19 red. Each restored from a backup in the scratch folder (`cmp` equal, `git diff --stat` equal). After the patch: `release/ipm-install.sh a` 75 PASS (`TIME skip-reload 3s`, `skip-bypass 56s`, `pip-skipped 64s`, `reinstall-checks 85s`), `test-cpf`, `test-boundaries`, `test-pinned-sources`, `test-release-sequence.sh static` pass, the spine lint shows the same 10 findings. `b` and `p` were not repeated (the patch touches `check_pip_skipped`, which runs on path A only).
- mutation (DW-857): "other versions" changed back to "older versions" in `docs/install-ipm.md` -> `test-release-sequence.sh static` red ("(DW-829, DW-857) the install page's bullet on the shared Python folder is the ruled text: got '0', wanted '1'"); restored from the backup (`cmp` equal).

**Code review stage (2026-11-07; lane C, tags `e19s8c` fresh and `e19s8cw` warm, both torn down):**
- Run after the review patches, one call each: `release/ipm-install.sh b` (59 PASS, all checks passed; `TIME second-merge 58s`; the six `STEP Python replaced` lines in its second merge), `ci/iris.sh live install-start` (95 PASS, 0 FAIL, no `STEP Python` line on the Docker path), `release/ipm-install.sh p` (all checks passed; `TIME p-fresh 130s`; import record 14 modules before and after) and `a` (63 PASS; `TIME second-ocutalon 61s`, `reinstall-checks 59s`), each with `OCUTALON_LIVE_DEADLINE` raised for a loaded host (load average about 7). Static: `test-cpf`, `test-pinned-sources`, `test-class-rules`, `test-boundaries`, `test-release-checklist`, `test-ci-config`, `test-readme`, `test-release-sequence` (all rules, 252 s) pass; the spine lint shows the same 10 findings (no new one). `OcuTalon.Test.Install.StaleCopies` (24 tests) and `OcuTalon.Test.Bridge.CodeRules` pass on warm `e19s8cw`.
- mutation (review, condition 1): `RemoveItem`'s `IsOwnFolder` line dropped -> `TestSymlinkInside`, `TestDistInfoSymlinkOutside`, `TestSymlinkOutside`, `TestSymlinkToTarget` red; the stale dist-info removed with `RemoveDirectoryTree` again -> `TestDistInfoSymlinkOutside` red; the `__pycache__` guard dropped -> `TestPycacheSymlinkOutside` red. Each restored from the review's backup (`cmp` equal, the two `Ipm.cls` copies equal) and the class green again on the same warm stack.
- mutation (review, condition 2): the import-record check dropped from `check_python_moves` -> test-cpf rule 18 (moves) red.
- mutation (review, condition 3): the import-record check dropped from `check_uninstall_python` -> rule 18 (uninstall) red; its `changed` compare made `elif False:` -> rule 18 (uninstall) red.
- mutation (review, the producer): `python_state` reading `RECORDS` -> rule 18 (state) red.
- mutation (review, condition 2 wiring): `run p-again USER ...` deleted from part p -> rule 19 red. Each `release/ipm-install.sh` mutation restored byte-identical from the review's backup (`cmp`), `git status --short` and `git diff --stat` equal before and after.
- Found already covered (no new test): every matrix row, the Rulings' condition 1 (pins read from the file, STEP line, idempotence, nothing outside `<mgr>/python`), the symlink-out guard, partial removal, the test-cpf rule 17 samples, the host-list and disclosure pins of `test-release-sequence.sh static`. Not covered by a hermetic test and left to the live runs: the Rulings' conditions 2 and 3 as a whole (imports of IPM's packages, `zpm "list"`, the uninstall), which need a real IPM.

**Code review stage, rework re-review (2026-11-07; lane C; no throwaway started: the patches touch `docker/tests/test-cpf.sh` and the evidence only, so path A, path b and part p were not re-run):**
- Path A was last run after the last change to anything it executes (the rework's review patch, 75 PASS); `b` and `p` ran before that patch, which changed `check_pip_skipped` only, a function neither calls. The `${cmd}` measurement is in the evidence (`load`, `reload`, `load` with the flag 1, `install`).
- Run at this head after the patches, one call each: `test-cpf`, `test-release-sequence.sh` (all rules, 341 s), `test-boundaries`, `test-pinned-sources`, `test-ci-config`, `test-compose-file`, `test-readme`, `test-class-rules` (all pass); the spine lint shows the same 10 findings.
- mutation (DW-856, test-cpf rule 19): `run skip-reload ...` deleted from `check_pip_skipped` in `release/ipm-install.sh` -> rule 19 red; `check_imports "$label"` dropped from `check_nothing_removed` -> rule 19 red; the decoy RECORD naming `zz/__init__.py` instead of the pinned idna's package -> rule 19 red; `check_nothing_removed`'s STEP Python test made `if true; then` -> rule 19 red.
- mutation (DW-856, test-cpf rule 17): the `cmd` Default written twice in `src/module.xml` -> rule 17 red; the BypassPyDeps Default removed on its own -> rule 17 red.
- Each applied from this review's backup and restored (`cmp` equal; `git status --short` and `git diff --stat` equal before and after).

**Rework iteration 2 (2026-11-07; the CI splits; lane C, tag `e19s8x`, torn down; `git status --short` and `git diff --stat` equal before and after each mutation, each file restored from the backup in the scratch folder with `cmp` equal):**
- Split 1: `ci/units.sh` gains the group `shards-5` (`shard:lane-a@Bridge,Agent`), `IRIS_GROUPS` ends with it, the iris matrix of `ci.yml` ends with it (that line only). `bash ci/iris.sh groups` prints ten names ending in `shards-5`; `ci/iris.sh classes lane-a@Bridge,Agent` lists 51 classes (Agent 15, Bridge 36), `classes lane-a@rest` lists 78 (none of Agent or Bridge; its areas are Fix, Tools, Digest, Eval, Memory, Docs), `lane-a@Checks,Install,Watch` 45 and `lane-a@Channel` 14, together the 188 classes of `classes lane-a` (rest is computed from the pieces the groups name, so every area is in exactly one piece). `shards-5` is no unit of NO_WEB_BUNDLE_UNITS, as `shard:lane-a@rest` was not, so its input pattern is `shards-2`'s: it runs and skips on the inputs its areas had. `ci/changes.sh` maps groups through `group_input_pattern` and needs no edit; `test-ci-changes.sh` `web_groups` gained `shards-5`; `test-ci-config.sh` pins the ten names (groups rule, the `ci/iris.sh groups` list, the unknown-group message, the sample trees, a new `g-nine` sample).
- Split 2: `.github/workflows/lane-a.yml` job `ipm-install` runs `release/ipm-install.sh a` then `r`; the new job `ipm-install-p` (a copy of it: same image, deadline 1980, timeout 35, steps; tag ending `-ipm-p`) runs `b` then `p`. `release/ipm-install.sh` and `release/*.sh` are unchanged: the existing modes give the split (the Design Notes' map holds against the script: `a` = path A without `reinstall_failures`, `r` = A's first and second run plus `reinstall_failures`, `b` = A's first run plus path B, `p` = part p alone; no argument = `all`, `mode=${1:-all}`). No intent gap.
- `docker/tests/test-cpf.sh`: rule 6 (the jobs and their modes: `ipm-install=a,r ipm-install-p=b,p`, no other job), rule 7 (each job wired, its own tag suffix, the bundle build before the job's first run, the same timeout and deadline), rule 16 (the default mode is `all` and `all` runs part p) and the new rule 20: (a) `ipm_mode_lines` reads the main flow of the script (after `# --- the stack ---`) with each mode's gates, and the modes the workflow passes together run every line of the no-argument run; (b) each of `all`, `a`, `r`, `b` and `p` alone has its own set of eight marker lines (first run, second run, install checks, reinstall check, failed reinstalls, path B, part p, packaging stack), and a, r and b run no line outside the no-argument run. A gate of another form or an unbalanced `if` is an error. Rule 19 is unchanged (it reads the script's calls, which the modes do not move).
- Measured (local paths only, one per call, `OCUTALON_LIVE_DEADLINE=1980`, load average 3 to 4): `release/ipm-install.sh a`: 75 PASS, 0 FAIL, wall-clock 298 s, `TIME second-ocutalon 62s`, `reinstall-same 51s`, `reinstall-checks 52s`, `skip-bypass 46s`, `pip-skipped 51s`. `release/ipm-install.sh p`: all checks passed, wall-clock 255 s, `TIME pkg-second 59s`, `p-second 63s`, `p-fresh 122s`, `python-pins 1s`, `uninstall-python 0s`, `p-again 3s`. `r` and `b` were not run in this pass. The x64 CI times are read from the first CI run at this head (inference: about twice the Mac's).
- Static, one per call: `test-ci-config`, `test-ci-changes`, `test-cpf`, `test-boundaries`, `test-pinned-sources`, `test-compose-file` pass; `test-release-sequence.sh static` passes (that script pins neither `lane-a.yml` nor the mode usage; the full run was not repeated, no input of it changed).
- mutation (rule 6, test-cpf): the `r` step removed from `ipm-install` -> rule 6 and rule 20 (union) red; the `b` step removed from `ipm-install-p` -> rule 6 and rule 20 (union) red; the `r` step with no mode (the no-argument run) -> rule 6 red.
- mutation (rule 7, test-cpf): the tag of `ipm-install-p` ending `-ipm` again -> rule 7 red; the timeout of `ipm-install-p` 25 against 35 -> rule 7 red.
- mutation (rule 16, test-cpf): `mode=${1:-all}` changed to `mode=${1:-a}` in `release/ipm-install.sh` -> rule 16 red.
- mutation (rule 20, test-cpf): `reinstall_failures` gated `!= x` (every mode, mode a included, runs it) and gated `= r` (the no-argument run skips it) -> rule 20 (each mode alone) red both times; the gate `[ "$mode" = a ] || [ "$mode" = r ]` before path B narrowed to `= a` (r falls into path B) -> rule 20 (each mode alone) red; a line only mode a runs added -> rule 20 (each mode alone) red; a line only the no-argument run runs added -> rule 20 (union) red. Each applied to `release/ipm-install.sh` or `lane-a.yml` from a backup and restored (`cmp` equal); no edit of `release/ipm-install.sh` remains.
- mutation (groups, test-ci-config): `shards-5` dropped from the matrix of `ci.yml` -> the matrix rule red; dropped from `IRIS_GROUPS` -> the matrix rule, the groups rule and the recipe rule red; its `group_units` case removed -> the groups rule and the inputs rule red.
- mutation (groups, test-ci-changes): `shards-5` dropped from `web_groups` -> the web classifier cases red (shards-5 runs on a web change); `shard:lane-a@Bridge,Agent` added to NO_WEB_BUNDLE_UNITS -> the same cases red (shards-5 would skip where `shards-2` ran).

- Review patches (rework iteration 2; lead): `r` and `b`, which the reviewers found never executed, ran on lane C (tags `e19s8xr`, `e19s8xb`, `OCUTALON_LIVE_DEADLINE=1980`, one per call, torn down, no container or volume left): `release/ipm-install.sh r` 74 PASS, 0 FAIL, wall-clock 376 s (`TIME second-ocutalon 63s`, `reinstall-fail 53s`, `reinstall-recover 55s`, `reinstall-compile 66s`); `release/ipm-install.sh b` 59 PASS, 0 FAIL, wall-clock 530 s (`TIME merge 35s`, `second-merge 70s`, `after-restarts 89s`, `reinstall-next 66s`, `check-reinstall-next 83s`). Local seconds per job: `ipm-install` (a, r) 674, `ipm-install-p` (b, p) 785; part 1's CI log scales path A about 2.2 times, so about 1,480 and 1,300 to 1,730 s against the 2,100 s timeout (inference until a CI run).
- mutation (rule 20, review patch, test-cpf; each applied from the patched file's backup in the scratch folder, observed red, restored with `cmp` equal, `git status --short` and `git diff --stat` equal): the `; else` test of the one-line gate dropped from `ipm_mode_lines` -> rule 20 on samples red (`modes.else-oneline` accepted); the `unknown` rule for a `$mode` test outside an `if` line dropped -> rule 20 on samples red (`modes.test-not-if`); the p-only whitelist line of `ipm_modes_alone` dropped -> rule 20 on samples red (`modes.p-extra`); the per-line count loop of `ipm_modes_alone` replaced by `:` -> rule 20 on samples red (`modes.dup-in-a`); one extra gate line added to `IPM_GATES` -> rule 20 on samples red and the real gate pin red.
- mutation (rule 20, review patch, the real script): `if [ "$mode" = r ]; then check_web; fi` added after the `reinstall_failures` gate of `release/ipm-install.sh` (from a backup in the scratch folder, restored `cmp` equal, `git diff --quiet -- release` clean) -> only the gate pin of rule 20 red (the markers, the subset and the count checks stay green, which is the gap the pin closes).
- `bash docker/tests/test-cpf.sh`, `test-ci-config.sh` and `test-boundaries.sh` pass after the patches.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The IPM install now imports the pinned copies of certifi, charset_normalizer, idna, requests, typing_extensions and urllib3 (DW-829). `OcuTalon.Install.Ipm.RemoveStaleCopies` runs at Reload, Before (just ahead of IPM's pip step), reads its pins from `requirements.txt`, removes only stale pinned distributions' unshared items inside `<mgr>/python` and then their dist-info, writes one `STEP Python replaced <name> <old> with <pin>` line each, and is idempotent. Check 32 gained the version-plus-RECORD-hash import check, the before/after folder and imports comparison, `zpm "list"`, the Invoke-argument check, a reinstall on path A and the uninstall measurement on part p. README A5 is unchanged. The Option 2 host lists (DW-830) are in README A4 and `docs/install-ipm.md` A6, and the ruled disclosure bullet follows A6 in the install page only. Condition 2 held, so the bullet's last sentence stands.

**Files changed.**
- `src/preload/cls/OcuTalon/Install/Ipm.cls`, `preload/cls/OcuTalon/Install/Ipm.cls` (byte copy): `RemoveStaleCopies` and helpers.
- `src/module.xml`, `module.xml`: the Reload Invoke and `<Default Name="BypassPyDeps" Value="0"/>`.
- `release/ipm-install.sh`: check 32's import check, folder and imports comparison, `zpm "list"`, Invoke arguments, reinstall, uninstall measurement; the gate's skip rule.
- `src/ocutalon/cls/OcuTalon/Test/Install/StaleCopies.cls` (new): one test per matrix row plus extras and the symlink case.
- `docker/tests/test-cpf.sh` (rule 17), `docker/tests/test-release-sequence.sh` (A4/A6 pins, host-list match, disclosure pin).
- `README.md` (A4 host list), `docs/install-ipm.md` (A6 host list, disclosure bullet).
- `ARCHITECTURE-SPINE.md` (AD-23 and AD-21 unions), the Task 0 evidence file and this spec.

**Review.** 43 findings from four layers. Patched (by the lead): a stale dist-info is kept, and no STEP line written, when an owned item could not be removed; the dead `$Translate` in `RecordTops`; `TestSymlinkOutside` (new) and a real first call in `TestIdempotent`; a test label. Deferred: one (running processes that already imported the old modules; unverified, settled by a registry install, which is outward). Rejected: the rest, each with its reason in the Review Triage Log (ruled text, spec-bound, hypothetical or cosmetic).

**Follow-up review recommended: true.** Patched entries: medium 3 (the partial-removal fix, `TestSymlinkOutside`, `TestIdempotent`), low 3. Named unverified risk: after the patch to `Replace`, `release/ipm-install.sh b` and `live install-start` were not run again (both passed before it; `a` and `p` passed after it and exercise the changed method).

**Verification performed.** `a` (63 PASS) and `p` pass after the last patch; `b` (59 PASS), `live install-start` (PASS, 451 s), `test-cpf`, `test-pinned-sources`, `test-release-sequence` (all rules), `test-class-rules`, `test-boundaries`, `test-ci-config`, `test-compose-file`, `test-readme` pass; `StaleCopies` and `Test.Bridge.CodeRules` pass on warm; the spine lint shows no new finding. Added IPM-check time: path A about 55 to 75 s (almost all of it the reinstall), part p about 6 s.

**Residual risks.** A failed pip step after the removal leaves the removed names absent until the same command runs again. The sample-output blocks of `docs/install-ipm.md` omit the six STEP lines (deferred, low). A registry install is not exercised (forbidden here).

### Rework iteration 1 (2026-11-07; DW-856, DW-857)

Status: done
Blocking condition: none

**Summary.** `RemoveStaleCopies(root, bypass, cmd, target)` removes a copy only when `bypass` is not set and the lifecycle command `cmd` is install, load or update (the commands for which IPM 0.10.10 runs its pip step); a reload, any other command or no command removes nothing. `${cmd}` was measured on a live IPM (`load`, `reload`, `load` with the flag 1, `install` from the local repository). Both manifests carry `<Default Name="cmd" Value=""/>` and a third `<Arg>${cmd}</Arg>`; `check_invoke_args` expects it; path A checks a reload and a `-bypass-py-deps` load against a planted stale copy (nothing removed, IPM's packages import, `zpm "list"` answers). The install page's disclosure bullet reads "other versions" and its pin follows.

**Files changed.** `src/preload/cls/OcuTalon/Install/Ipm.cls` and `preload/cls/OcuTalon/Install/Ipm.cls`; `src/module.xml`, `module.xml`; `release/ipm-install.sh` (check 32 area only); `src/ocutalon/cls/OcuTalon/Test/Install/StaleCopies.cls`; `docker/tests/test-cpf.sh` (rules 17 and 19); `docker/tests/test-release-sequence.sh` and `docs/install-ipm.md` (the bullet); the spine (AD-23 union); the evidence file; this spec.

**Review.** Patched: 3 medium, 2 low (rule 19 pins for the planted copy and the bypass run, decoy cleanup and a local variable, the spine's "local repository", the `update` inference label, the evidence note on which assertions carry the red). Deferred: none. Rejected: each with its reason in the Review Triage Log.

**Follow-up review recommended: false.** No high was patched in this follow-up pass.

**Verification performed.** `a` 75 PASS (after the review patch), `b` 59 PASS and `p` 32 PASS (before it), `StaleCopies` (27 tests) and `Test.Bridge.CodeRules` on warm, `test-cpf`, `test-boundaries`, `test-pinned-sources`, `test-class-rules`, `test-release-sequence` (all rules), `test-ci-config`, `test-compose-file`, `test-readme`; spine lint: the same 10 findings.

**Residual risks.** `update` and a registry install were not run live (inference from the IPM source, and the registry is forbidden here). `ci/iris.sh live install-start` was not re-run (the Docker path has no `requirements.txt`, so the step removes nothing there).

### Rework iteration 2 (2026-11-07; the two CI splits, DW-826 and DW-864)

Status: done
Blocking condition: none

**Summary.** CI split 1: the iris group `shards-5` runs `shard:lane-a@Bridge,Agent` (`ci/units.sh`: `IRIS_GROUPS`, the `group_units` case and a comment with the measured seconds; the `ci.yml` iris matrix, that line only), so `shard:lane-a@rest` in `shards-2` drops the two areas by itself (the rest is computed from the pieces the groups name); `ci/changes.sh` needed no edit (it derives each group's inputs from `group_input_pattern`, and `shards-5` is not in `NO_WEB_BUNDLE_UNITS`, as `@rest` is not). CI split 2: no release-tool hunk, the existing modes give the split. `lane-a.yml` job `ipm-install` runs `release/ipm-install.sh a` then `r` (path A and its failed reinstalls); the new job `ipm-install-p` (a copy: image, deadline 1980, timeout 35) runs `b` then `p` (path B and part p), with a tag ending `-ipm-p`. `release/ipm-install.sh` with no argument is untouched and so are `release.sh` and `lib-release.sh`.

**Files changed.** `ci/units.sh`, `.github/workflows/ci.yml` (matrix line), `.github/workflows/lane-a.yml` (job `ipm-install` steps, new job `ipm-install-p`), `docker/tests/test-ci-config.sh` and `docker/tests/test-ci-changes.sh` (the group pins), `docker/tests/test-cpf.sh` (rules 6, 7, 16 reworked; rule 20 new: the jobs' modes cover the no-argument run, each mode alone runs only its own set, the seven gates of the main flow are pinned), this spec.

**Review.** 17 findings, no high. Patched: 3 medium (one root cause: rule 20 bounded a mode by eight marker lines only; now also the gate pin, the p-only whitelist and the per-line count), 5 low (a `$mode` test outside an `if`, a one-line `else`, the count of repeated lines, the stale "eight groups" text, the timing comment of `shards-5`). Deferred: 1 low (the release record's sentence "the CI job ipm-install runs the same command", in `release/release.sh` which the freeze keeps). Rejected: 5 low and 2 false, each with its reason in the Review Triage Log (the `ci.yml` header comment, rule 6's pinned split, the order-sensitive wiring check, the per-run deadline against the job timeout, a duplicate sample, the matrix pin that exists, `r` and `b` never run).

**Follow-up review recommended: false.** No high was patched in this follow-up pass. Patched counts by verdict: medium 1 (the grouped entry), low 5.

**Verification performed.** Local, lane C, tags `e19s8x`, `e19s8xr`, `e19s8xb`, all torn down: `release/ipm-install.sh a` 75 PASS in 298 s, `r` 74 PASS in 376 s, `b` 59 PASS in 530 s, `p` all PASS in 255 s (local seconds per job: `ipm-install` 674, `ipm-install-p` 785). Static, one per call: `test-ci-config`, `test-ci-changes`, `test-cpf`, `test-boundaries`, `test-pinned-sources`, `test-compose-file` and `test-release-sequence.sh static` pass; `bash ci/iris.sh groups` prints ten names, `classes lane-a@Bridge,Agent` lists 51 classes and `classes lane-a@rest` 78, none of Agent or Bridge. `mutation:` lines for every pinning test touched are under `Rework iteration 2` in `## Verification`.

**Residual risks.** The seconds of the two lane-a jobs on the runner are an inference (about 1,480 s for `ipm-install` and 1,300 to 1,730 s for `ipm-install-p` against 2,100 s) until a CI run measures them; `shards-2` and `shards-5` likewise (about 1,470 s and 1,300 s). Rule 20 reads the script's gates, not its blocks, so a check moved between blocks that share gates is for review. The release record's sentence about the CI job is stale (deferred).
