---
title: 'Epic 19 burn-down: the IPM install imports the pinned packages, and the docs name the hosts it contacts'
type: 'bugfix'
created: '2026-11-07'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-19-6-extract-text-from-pdf-and-word-files-with-embedded-python.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/19-6-task0-extraction.md'
warnings: ['oversized']
deferred: []
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

**Acceptance Criteria:**
- Given the local-artifact IPM install (path A and part p), when check 32 runs, then each of the six modules imports the pinned copy (`__file__` under `<mgr>/python` with the pinned RECORD's hash, `__version__` equal to the pin where defined), and check 32 fails otherwise (DW-829).
- Given the unfixed tree, when Task 0 runs the import check, then the evidence file records `__version__` and `__file__` for all six and the decision taken. The import check's red on a stale copy is observed (on the unfixed tree, or under a mutation that skips the fix).
- Given a stale copy was measured, when the install's Reload phase starts, then `RemoveStaleCopies` removes exactly the stale pinned distributions' unshared items. IPM's ORAS packages still import, `bin/` and every other distribution are unchanged, and checks 30 to 33 and path b's checks pass.
- Given README A5, when the story is done, then A5 is unchanged, unless the stop rule HALTed.
- Given M6's measurements, when a reader opens README A4 and `docs/install-ipm.md` A6, then they name exactly the hosts seen (unchanged if the same three), and any change ships only as the ruled PUBLIC TEXT (DW-830).
- Given the image (read only), when M5 runs, then the evidence says whether the image imports pinned or older copies of the six.

## Spec Change Log

- 2026-11-07 (lead, before implement): Task 0 measured ahead of implement (evidence committed); the Planner's rulings recorded under Design Notes "Rulings (2026-11-07 ...)": DW-829 fix with four conditions, the disclosure bullet, DW-830 Option 2 hosts.

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). DW-829 and DW-830 are addressed by Task 0 (measure first), the import check in check 32's area, the conditional stale-copy fix and the separate last docs task. DW-830's blocked-download half is declined with its reason under Design Notes. The PUBLIC TEXT items depend on Task 0 M6's measured hosts.
