---
title: 'Story 0.1: The image builds and starts OcuTalon in its own namespace'
type: 'feature'
created: '2026-10-18'
status: 'done'
baseline_revision: '5e0324ed680dfc1d7bdd9024eccd10b6b5042afb'
baseline_commit: '5e0324ed680dfc1d7bdd9024eccd10b6b5042afb'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      iris-main skips an unchanged merge file, so a merge that failed partway on a first start, or a mapping removed by hand, is not repaired by a plain restart.
    evidence: |-
      Build 154 logs "unchanged; skipping" and adds no Merging line when the merge file equals /durable/iris/^opt^ocutalon^merge.cpf.last_merge. Whether iris-main writes that copy after a failed merge was not tested.
      A throwaway run whose merge file holds a failing action on the first start, followed by a plain restart, would settle it. Story 0.2's after-start script could re-run `iris merge` explicitly.
    location: >-
      docker/Dockerfile (ISC_CPF_MERGE_FILE)
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Nothing in the repository builds or starts IRIS, so `docker compose up` gives no OCUTALON namespace, and nothing reports when OcuTalon is ready.

**Approach:** Add the following, each tested by bash scripts (hermetic, static and one live throwaway run):
- one Dockerfile `FROM` the retagged build 154 image;
- a CPF merge that creates OCUTALON at every start;
- the judges' compose file, with durable `%SYS` on a named volume and a health check that opens no IRIS session (IRIS running, and the ready marker equal to the image's version);
- `.env.example`.

## Boundaries & Constraints

**Always:**
- The merge is idempotent, and its database directories are relative (`Directory=ocutalon_code`, so they resolve to `<ISC_DATA_DIRECTORY>/mgr/<dir>/`).
- The health check is POSIX `sh` and calls only `iris qlist`.
- Tests create and remove their own state. Live runs use a unique throwaway project only (AD-22, Rule 21).
- Scripts use only bash 3.2 / POSIX `sh`, docker, git, sed, grep and awk, in ASCII (Rule 14).

**Never:**
- Scope that belongs elsewhere:
  - the after-start script, IPM, package resources, a marker writer or `--after` (Story 0.2);
  - OCUORDERS in the merge (AD-3: the `Demo` step);
  - web applications (0.3);
  - the CI override or mock (0.7);
  - `install.sh` (Epic 10).
- In `docker-compose.yml`: no `container_name`, fixed volume `name:`, `image:` tag, mock service or superserver port.
- No `docker push` or registry sign-in. No `docker compose config` without `--quiet`, and no `docker inspect` without `--format`. Never read or print `.env`.
- No local machine path or key-like string in a tracked file, and no new dependency. Nothing from `irislib/` or `irissys/`.
- The implement stage, QA and code review never stop, wipe, restart or recreate `ocutalon-slot-a` or `-b`, and never edit `../ocutalon-slot-a` or `../ocutalon-slot-b`. No other container or MCP profile is a target.

## I/O & Edge-Case Matrix

Rows 1–6 run `docker/healthcheck.sh` hermetically, with a fake `iris` on `PATH` that logs its arguments and prints a recorded qlist line (see the Code Map), and temporary version and marker files. Rows 7–8 run live.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 IRIS down | down line; marker = version | exit non-zero | none |
| 2 No marker | running line; no marker | exit non-zero | none |
| 3 Other version | running; marker `0.0.9` | exit non-zero | none |
| 4 Ready | running; marker = version plus newline | exit 0 | none |
| 5 Empty version | running; version file and marker empty | exit non-zero | none |
| 6 No session | rows 1–4 | fake `iris` saw only `qlist` | test fails otherwise |
| 7 Integration: Docker's health monitor consumes the script | live: IRIS running, no marker, then a wrong marker, then `cp /opt/ocutalon/version /durable/ocutalon.ready` | `docker inspect --format '{{.State.Health.Status}}'` stays `starting` and the in-container script exits 1 for the first two; after the copy it exits 0, and the status is `healthy` within 60 s | test fails, printing the status |
| 8 Stale build | image built from the tree | `/opt/ocutalon/version` = first `<Version>` of `src/module.xml` | build fails on an empty version |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- read by range: AD-3 L121–149, AD-5 L174–184, AD-22 L571–591, AD-23 L593–637, environments and source tree L1090–1144.
- `.gitignore` -- already ignores `.env` and keeps `.env.example`. No change.
- `../spikes/install/{Dockerfile,scripts/healthcheck.sh}` -- S1 prior art (outside the repo, read-only): `USER root`, `chown 51773:51773 /durable`, `USER 51773`, `ISC_DATA_DIRECTORY`, `ISC_CPF_MERGE_FILE`.
- `../spikes/batch2/s16/scripts/s16-merge.cpf` -- `PublicPermission=R`, `CreateMapPackage`, `CreateMapGlobal`.
- `../spikes/batch2/trackG/s19/ocutalon7.cpf` -- relative `Directory=`, observed resolving to `/durable/iris/mgr/<dir>/`.
- `../ocutalon-slot-a/docker-compose.yml` (B is the same) -- read-only: `./iris-data:/durable`, `ISC_DATA_DIRECTORY=/durable/iris`, `ISC_CPF_MERGE_FILE=/config/merge.cpf`, a qlist-only health check.
- `irislib/%SYS/Namespace.cls` -- `GetGlobalDest` L93, `GetPackageDest` L141. `irislib/%Library/EnsembleMgr.cls` -- `IsEnsembleNamespace` L79. `Security.Resources.Get` returns `PublicPermission` as a mask (Read = 1, Write = 2).
- Recorded build 154 qlist lines:
  - down: `IRIS^/usr/irissys^2026.3.0AI.154.0com^down, last used Thu Sep 24 18:31:12 2026^iris.cpf^1972^52773^0^^IRISHealth^^^/usr/irissys^1972`
  - running: `IRIS^/usr/irissys/^2026.3.0AI.154.0com^running, since Sun Oct 18 14:37:45 2026^iris.cpf^1972^52773^0^ok^IRISHealth^^^/durable/iris/^1972`
  - Field 10 is `IRIS` on the non-Health image, which is loaded locally.
- Base image: user 51773, entry point `/tini -- /iris-main`, no `HEALTHCHECK`, and `/bin/sh` is dash.

## Tasks & Acceptance

**Execution:**
- `src/module.xml` -- the IPM manifest with its identity only: name `ocutalon`, `<Version>0.1.0</Version>` as the file's first `<Version>`, and `Packaging` `module`, with no resources -- AD-23: the image's version is the module's. Story 0.2 adds the resources.
- `docker/merge.cpf` -- the actions:
  - the resources and databases `OCUTALON_CODE`, `_DATA`, `_PRIVATE` and `_PUBLIC` (`%DB_OCUTALON_PUBLIC` with `PublicPermission=R`);
  - the namespace OCUTALON (globals in data, routines in code, `Interop=1`);
  - global maps `OcuTalonP.*`, `OcuTalonBP.*`, `AI.Agent.Session*` and `IRIS.IF.*` to private, and `OcuTalonPublic` to public;
  - package maps `OcuTalon.Web.Public` and `OcuTalon.Data.Public` to public;
  - `ModifyService:Name=%Service_CallIn,Enabled=1,AutheEnabled=48`.
  - AD-3, AD-23.
- `docker/healthcheck.sh` -- exit 0 only if `iris qlist | grep -q '\^running'` succeeds and a non-empty `${OCUTALON_VERSION_FILE:-/opt/ocutalon/version}` equals `${OCUTALON_READY_MARKER:-/durable/ocutalon.ready}`.
- `docker/Dockerfile` -- `ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0`, then `FROM ${IRIS_IMAGE}`. Create `/durable` owned by 51773. Copy the merge file and `module.xml` read-only and the health check executable under `/opt/ocutalon/`. Derive `/opt/ocutalon/version`, failing the build when it is empty. Then `USER 51773` and `ENV ISC_DATA_DIRECTORY=/durable/iris ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf`.
- `.dockerignore` -- `*`, then allow only the copied files, so `.env`, `irislib/`, `irissys/` and `.git` stay out of the build context.
- `docker-compose.yml` -- `name: ocutalon`, and one service, `iris`, with:
  - `build` (`docker/Dockerfile`, context `.`, arg `IRIS_IMAGE: ${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}`), `pull_policy: build`, `restart: unless-stopped`, `stop_grace_period: 60s`;
  - `env_file` `.env` (`required: false`) and `ports` `${OCUTALON_WEB_PORT:-52773}:52773`;
  - volume `durable:/durable`;
  - `healthcheck`: `["CMD", "/opt/ocutalon/healthcheck.sh"]`, 10 s interval, 5 s timeout, 3 retries, `start_period: 600s`.
- `.env.example` -- `ANTHROPIC_API_KEY=` and `TELEGRAM_BOT_TOKEN=` with no values, plus a comment (NFR-11, AD-19).
- `docker/tests/compose.throwaway.yml` -- a test-only override on `iris`: `ports: !reset []` and `env_file: !reset []`.
- `docker/tests/test-healthcheck.sh` -- matrix rows 1–6: one PASS or FAIL line per row, with the temporary directory removed in an EXIT trap.
- `docker/tests/test-compose-file.sh` -- grep/awk inspection of the compose file, the Dockerfile, `.dockerignore` and `.env.example`:
  - the only service is `iris`, no non-comment line says `mock`, `start_period` is at least 600 s, and there is no `container_name`;
  - `docker compose -f docker-compose.yml config --quiet` passes;
  - `git check-ignore -q .env` succeeds and `git check-ignore -q .env.example` fails.
- `docker/tests/test-compose-start.sh` -- the live test.
  - Setup: `P=ocutalon-t01-<epoch>-$$`. Every call is `docker compose -p "$P" -f docker-compose.yml -f docker/tests/compose.throwaway.yml`, and an EXIT trap runs `down -v --rmi local` for `$P`.
  - Start: `up -d --build`, then wait at most 240 s for `^running`.
  - `CHECK`: one `exec -T iris iris session IRIS -U %SYS` script prints values for the test to compare:
    - OCUTALON exists and `IsEnsembleNamespace` = 1;
    - the databases are in `/durable/iris/mgr/ocutalon_{code,data,private,public}/`;
    - the public mask has Read and not Write;
    - `GetGlobalDest` puts `OcuTalonP.S01`, `OcuTalonBP.S01`, `AI.Agent.SessionD` and `IRIS.IF.S01` in private, `OcuTalonPublic` in public and `OcuTalonS01` in data;
    - both packages resolve to public;
    - CallIn is enabled with 48;
    - qlist's data directory is `/durable/iris/`, and `/durable` is a `volume` mount.
  - Then matrix rows 7 and 8.
  - Restart: set `^OcuTalonS01Probe` and `^OcuTalonP.S01Probe`. Run `stop` then `start`, then `down` then `up -d`, waiting at most 90 s each time. After each one, the probes and `CHECK` hold, `messages.log` has one more `Merging /opt/ocutalon/merge.cpf` line, and no line from that merge's pid has severity 2 or 3.

**Acceptance Criteria:**
- Given the retagged base image, when `docker compose up` runs, then the image builds from `docker/Dockerfile` and the container starts with durable `%SYS` on a named volume. OCUTALON has Interoperability, the four databases (public Read on the public one), AD-3's mappings and `%Service_CallIn` (`test-compose-start.sh`, `CHECK`).
- Given OCUTALON holding the two probes, when the container is stopped and started, and also when it is recreated on the same volume, then the merge reapplies without errors and both probes survive in their databases (`test-compose-start.sh`).
- Given `docker-compose.yml`, when it is inspected, then it has `name:`, `stop_grace_period: 60s`, the health check with `start_period` of at least 10 minutes, the `IRIS_IMAGE` argument and no mock service. `.env.example` lists both keys with no values, and `.env` is git-ignored (`test-compose-file.sh`).
- `(lead, after code review)` Given the final `docker/merge.cpf`, when the lead runs each slot's procedure, then that slot's MCP profile shows OCUTALON with Interoperability and every `CHECK` database, directory and mapping.
  - Order: `ocutalon-slot-a`, then `-b`.
  - The MCP calls use `server` `ocutalon-slot-<a|b>` and `namespace: OCUTALON`, with identity checked first through `iris_server_info` (build 154, port 52790 or 52791).
  - Procedure, from the slot folder:
    1. Copy `docker/merge.cpf` to `config/merge.cpf`.
    2. `docker compose down`.
    3. `find iris-data -mindepth 1 -delete`.
    4. `docker compose up -d --wait`.
    5. `python3 set-system-password.py`.
  - The slot compose file needs no change: with `ISC_DATA_DIRECTORY=/durable/iris`, the relative directories land in `./iris-data/iris/mgr/`. If one lands elsewhere, the lead fixes the slot's mount or `ISC_DATA_DIRECTORY`, never the merge file.

### Review Findings

Code review, 2026-10-18 (`bmad-code-review`, full mode, four layers). The layers reported 38 rows. Ten were rejected (seven lines under Rejected below), and the other 28 grouped into 16 entries. With the implement stage's residual note that makes 17 entries: 0 high, 5 medium, 12 low. All 15 patch entries were applied. The other two were ledgered (DW-2, DW-3), and DW-1 got an evidence trailer.

- [x] [Review][Patch] [med] Readiness raced the merge: build 154's iris-main runs `iris merge` after it logs `...started InterSystems IRIS instance`, so in the changed-merge-file round `iris_ready` (qlist running and any `*.last_merge`) could pass before this start's merge. `iris_ready` now requires the record to equal `/opt/ocutalon/merge.cpf` (`cmp -s`). [docker/tests/test-compose-start.sh:iris_ready] fix-risk low.
- [x] [Review][Patch] [med] AC 2's "without errors" could not see a real merge failure: build 154 logs a failed action at severity 1 (`ERROR #503`/`#507`), and the filter read only severity 2 and 3. `merge_errors` now also flags `ERROR #` lines, its control holds the recorded `ERROR #507` line, and the first start's merge is checked too. A live run showed that a failed merge leaves no record, so readiness never comes (DW-1 trailer). [docker/tests/test-compose-start.sh:merge_errors] fix-risk low.
- [x] [Review][Patch] [med] "Receives no keys" depended on a `.env` the test did not create (Rule 19). The test now writes its own decoy key file into an extra override, which `compose.throwaway.yml`'s reset must drop. [docker/tests/test-compose-start.sh:dc] fix-risk low.
- [x] [Review][Patch] [low] The plain restart rounds never confirmed a restart. The exit codes of stop, start and down are now checked; the start time must change, and a recreate must give a new container. [docker/tests/test-compose-start.sh:restart_round]
- [x] [Review][Patch] [low] `git: .env is ignored` passed when a later rule negates it (`-v` prints `!.env`). It now needs `-q` and a non-negated `.gitignore` source. [docker/tests/test-compose-file.sh:git_ignores]
- [x] [Review][Patch] [low] `git: .env.example is not ignored` could not fail on a tracked file. It now uses `--no-index`. [docker/tests/test-compose-file.sh:git_does_not_ignore]
- [x] [Review][Patch] [low] The project name was not pinned; it must now be exactly `name: ocutalon`. [docker/tests/test-compose-file.sh:79]
- [x] [Review][Patch] [low] The boundary scanner missed `docker compose ... push`, `dc push`, `docker image push`, `--push`, `convert`, `docker-compose` and `--format` templates that print `.Config.Env` or `{{json .}}`. It is widened, with five new controls. [docker/tests/test-boundaries.sh:risky_docker_calls]
- [x] [Review][Patch] [low] The LF rule left out `.dockerignore` and `.env.example`, whose exact-match checks fail on CRLF. Both are added and pinned by `files_keep_lf`. [.gitattributes]
- [x] [Review][Patch] [low] `docker/** text` would force any future binary under `docker/` to be treated as text; it is now `text=auto`. [.gitattributes]
- [x] [Review][Patch] [low] There was no overall time budget: the capped waits add up to about 815 s, against the "under 9" minutes stated under Verification. A 540 s deadline now bounds every wait. [docker/tests/test-compose-start.sh]
- [x] [Review][Patch] [low] Nothing pinned the read-only copies under `/opt/ocutalon`. The live test now checks their owner and mode (root; 444, or 555 for the health check). [docker/tests/test-compose-start.sh]
- [x] [Review][Patch] [low] The throwaway override kept `restart: unless-stopped`; it now has `restart: "no"`. [docker/tests/compose.throwaway.yml]
- [x] [Review][Patch] [low] Only `run_check` retried an IRIS session that printed nothing; `check_probes`, the first session after each restart, did not. The retry now lives in `iris_script`. [docker/tests/test-compose-start.sh:iris_script]
- [x] [Review][Patch] [low] `.env.example` did not mention `OCUTALON_WEB_PORT`; it now has one comment line. [.env.example]
- [x] [Review][Defer] [med] Docker Compose 2.24 or later is needed (`env_file` with `required: false`), and nothing checks or states that. DW-2 is routed to `10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to` (the install script refuses an older Compose, and Story 10.2's README states the minimum). This is the implement stage's residual note.
- [x] [Review][Defer] [med] The web port is published on every host interface while a fresh volume holds default credentials. DW-3 is decision-pending for the author (spec-bound `ports` line; a product and security call).

Rejected:
- Blind Hunter: the spec is marked done while AC 2 says the merge reapplies at every start. This is DW-1, already ledgered as decision-pending. It is not a new occurrence; this review appended evidence to it.
- Blind Hunter, Edge Case, Verification Gap, Acceptance Auditor: the closing records are stale after QA (26 checks against 29, file lists, the `git status` line, 32 PASS lines). Fixing them means editing the spec, so that is left to the lead or Finalize.
- Edge Case: a precondition failure in `forget_last_merge`/`change_last_merge` is silent. Low: the round still goes red on the Merging count, only one record can exist, and the fix adds guards.
- Edge Case: the `/home/irisowner` exclusion in the path scanner drops the whole line. Theoretical: it needs a line that holds both paths.
- Edge Case: `$files` is unquoted in `scan_rule`. Theoretical: no file in scope has whitespace in its name, and the fix adds array handling.
- Acceptance Auditor: `test-build-inputs.sh` needs the build 154 image, but the Design Notes hand-off names only the live test for the IRIS runner. Fixing the note means editing the spec; the script's header states the requirement, and Story 0.7 must place the script on the IRIS runner.
- Acceptance Auditor: the health check's path variables can be reached through `.env`. Theoretical: it needs a deliberate `.env` line naming an undocumented variable. Reopen if `.env.example` or the README ever names them.

## Spec Change Log

### 2026-10-18 -- Implement-stage observation (no loopback)
- Trigger: on build 154, `iris-main` applies `ISC_CPF_MERGE_FILE` only when the file differs from its saved copy, `/durable/iris/^opt^ocutalon^merge.cpf.last_merge` (it logs `Files differ; merging` or `unchanged; skipping`). The merge therefore does not run at every start: it runs at the first start and whenever the merge file changes, as a new image's would. AD-23 ("A CPF merge at every start") and AC 2 ("the merge reapplies") are worded for every start.
- Amended: nothing inside the intent contract. `test-compose-start.sh` covers four restarts: a plain stop and start and a plain recreate (merge skipped, probes and `CHECK` hold); a stop and start after the saved copy is edited, which is what an image with a changed merge file looks like (iris-main replaces the read-only copy, the merge reapplies cleanly); and a recreate after the saved copy is removed (the merge reapplies cleanly).
- Known-bad state avoided: asserting a `Merging` line after a plain restart, which build 154 never writes.
- KEEP: the relative `Directory=` values (they resolved to `/durable/iris/mgr/<dir>/`, so no switch to absolute paths); the `restart_round` helper; the filter control for the merge log.
- For the lead (Rule 20, light path): word AD-23's merge sentence and Rule 21's "the merge reapplies at every start" as "at the first start and whenever `merge.cpf` changes". Story 0.2's after-start script may run `iris merge` explicitly where it needs a guaranteed reapply (see `deferred:`).

### 2026-10-18 -- Author decisions on DW-1 and DW-3 (lead, after the story was committed)
- DW-1: the author kept AD-23's merge at every start. AD-23 now says that build 154's `iris-main` merges only at the first start and on change, and that the after-start script re-runs `iris merge` at every start (Story 0.2, `DW-1:` bullet). Rule 21's slot note now says to wait for `*.last_merge` to match.
- DW-3: the author kept the web port on every host interface. AD-23 records it, and Story 10.2's README warns about it (`DW-3:` bullet).

## Review Triage Log

### 2026-10-18 -- Review pass
- verdicts: 40 findings -- high 0, medium 6, low 25, false 8, maybe-false 1
- findings:
  - `[low]` `[reject]` Blind Hunter: `## Auto Run Result` still reads `ready-for-dev` -- the fix is to edit this spec; Finalize rewrites the block.
  - `[medium]` `[patch]` Blind Hunter: no LF rule, so a Windows checkout with autocrlf gives `healthcheck.sh` a CRLF shebang and the container never reports healthy -- added `docker/**` and `src/module.xml` `eol=lf` to `.gitattributes`, pinned by `files_keep_lf` in `test-compose-file.sh`.
  - `[false]` `[reject]` Blind Hunter: the marker persists, so a restart can report healthy before the merge finishes -- the merge runs before IRIS starts (probe log: `Merging` precedes `running`), and the marker writer and its removal at start are Story 0.2's (Never list, AD-23 step 1).
  - `[medium]` `[patch]` Blind Hunter: only a forced re-merge is tested, never a plain restart or a changed merge file -- `test-compose-start.sh` now runs `restart_round` four times (plain stop/start, plain recreate, changed saved copy, removed saved copy). Grouped with Edge Case 3 and 9 members and Intent 1.
  - `[low]` `[patch]` Blind Hunter: row 8 oracle repeats the Dockerfile's `sed` -- the control build now has a later decoy `<Version>9.9.9</Version>` and the image must still hold the first. Grouped with Edge Case 8, Verification Gap 4 and Intent 6.
  - `[low]` `[patch]` Blind Hunter: mutation coverage partial -- rows 1 to 3 now have recorded mutations; the other sub-assertions are not pinning tests (Rule 19 scopes to one mutation per AC).
  - `[low]` `[reject]` Blind Hunter: Compose version undocumented -- the `env_file` long form is the spec's; prerequisites belong to Epic 10's install script and README. Residual risk recorded.
  - `[low]` `[patch]` Edge Case: the merge-log filter ignores severity 1 while the failure text said "warnings or errors" -- the spec bars severity 2 and 3; the failure text now says "severity 2 or 3 lines".
  - `[low]` `[reject]` Edge Case: fixed 240 s first-start wait -- the spec fixes it, and a first start measured about 2 minutes (Rule 21); Story 0.7 sizes CI waits.
  - `[medium]` `[patch]` Edge Case: a changed merge file against an existing, read-only saved copy is never exercised -- the concern that iris-main cannot overwrite the 0444 copy is false (a probe stack logged `Files differ; merging` and replaced it); the path is now a test round. Grouped with Blind Hunter 4.
  - `[false]` `[reject]` Edge Case: `docker compose exec` failure read as "script exited 1" -- `stays_starting` also needs Docker's status `starting`, two monitor runs and a last monitor exit of 1, which a stopped container fails.
  - `[low]` `[reject]` Edge Case: `IRIS_IMAGE` set only in `.env` gives the control builds another base -- they exercise only the Dockerfile's version logic, which does not depend on the base.
  - `[medium]` `[patch]` Edge Case: CRLF on Windows checkouts -- same root cause as Blind Hunter 2, patched there.
  - `[low]` `[reject]` Edge Case: the only-service awk misses quoted or oddly indented names -- `config --services` would break AD-22's `--quiet` rule, and the `mock` check catches the case that matters.
  - `[low]` `[patch]` Edge Case: the `sed` takes the last `<Version>` of a line, comments included -- the decoy build pins first-wins; the sed is line-based by design. Grouped with Blind Hunter 5.
  - `[maybe-false]` `[defer]` Edge Case: a merge that failed partway, or a hand-removed mapping, is not repaired by a plain restart because an unchanged file is skipped -- unverified medium; a run with a failing first merge would settle it. In `deferred:`.
  - `[low]` `[patch]` Verification Gap: `pull_policy`, `restart`, `env_file` and `ports` are unpinned -- four checks added to `test-compose-file.sh`.
  - `[medium]` `[patch]` Verification Gap: a missing resource and a resource with no public permission print the same `pub-read`/`pub-write` -- `CHECK` now prints `res-exists` for the four resources.
  - `[low]` `[patch]` Verification Gap: the merge-log check has no positive control -- `merge_errors` is a function run first on a synthetic excerpt.
  - `[low]` `[patch]` Verification Gap: row 8 first-version not independently pinned -- same fix as Blind Hunter 5 (reviewer proposed defer).
  - `[low]` `[patch]` Verification Gap: row 7 "no marker" assumed state it did not create -- the marker is removed first.
  - `[low]` `[patch]` Verification Gap: rows 1 to 3 have no `mutation:` line -- three mutations demonstrated and recorded in `## Verification`.
  - `[low]` `[patch]` Verification Gap: AC 2 "without errors" clause cannot be shown to fail -- same fix as Verification Gap 3, with a recorded mutation.
  - `[false]` `[reject]` Verification Gap: the lead's slot AC has no pinning test -- it is the lead's manual procedure by design.
  - `[low]` `[patch]` Verification Gap: the throwaway override's invariant is asserted nowhere -- the live test checks zero published ports and zero key variables (counts only, no values printed).
  - `[false]` `[reject]` Verification Gap: the scripts are not in a CI path -- Story 0.7 adds it (Design Notes).
  - `[low]` `[reject]` Verification Gap: stale `Auto Run Result` -- same as Blind Hunter 1.
  - `[false]` `[reject]` Verification Gap: the matrix says row 6 covers rows 1 to 4 while the test covers 1 to 5 -- the test is stricter, no defect.
  - `[low]` `[patch]` Verification Gap: `config --quiet` cannot see a regression of `required: false` where `.env` exists -- the `env_file` check added for the first finding pins it.
  - `[low]` `[reject]` Verification Gap: Compose 2.24.4 needed for `!reset` -- same as Blind Hunter 7; the override is test-only and fails loudly.
  - `[low]` `[reject]` Verification Gap: hermetic test falls back to `sh` without `dash` -- row 7 runs the script under the image's own `/bin/sh` through Docker.
  - `[medium]` `[patch]` Intent Alignment: the test never runs the unforced restart path "at every start" implies -- plain rounds added; the wording divergence is in the Spec Change Log. Grouped with Blind Hunter 4.
  - `[low]` `[patch]` Intent Alignment: relative `Directory=` is checked nowhere in text -- `test-compose-file.sh` now requires four `Directory=` values, none absolute.
  - `[low]` `[reject]` Intent Alignment: "no IRIS session" is observed through a fake `iris` on `PATH` -- a bypass would need an absolute path in a 12-line script; theoretical.
  - `[false]` `[reject]` Intent Alignment: row 7 sits inside `start_period` -- Docker's own health log records each exit code and the `healthy` transition, and the later `unhealthy` state is by design until Story 0.2.
  - `[low]` `[patch]` Intent Alignment: the judges' file differs from the file the live test runs (`ports`, `env_file`) -- static checks now pin them. Grouped with Verification Gap 1.
  - `[low]` `[patch]` Intent Alignment: row 8 oracle shares the Dockerfile's extraction -- same fix as Blind Hunter 5.
  - `[false]` `[reject]` Intent Alignment: durability is split between the Dockerfile `ENV` and the compose mount -- both are observed, statically and live; no divergence.
  - `[low]` `[reject]` Intent Alignment: `CHECK` samples mappings rather than listing them -- it resolves six globals and both packages, one per merge line; AD-3's set is the merge file's.
  - `[false]` `[reject]` Intent Alignment: scripts use `tr`, `cut`, `wc` and similar -- the spec's list names the toolchain, not each coreutil.

## Design Notes

**ADs:** AD-3, AD-5 (state on the durable volume), AD-19 (keys only from the environment), AD-22 (no mock in the judges' file, `--quiet` and `--format`, throwaway stacks), AD-23 (recipe, merge, health check, UID 51773, version checked inside the built image) and AD-29 (after Epic 0, `merge.cpf` is Lane A's and the rest of `docker/` Lane B's). Spikes: S1, S12, S16, S19.

**Contracts fixed here:** `/opt/ocutalon/version` is the image's version. `/durable/ocutalon.ready` is the marker: one line with the version, which Story 0.2's after-start script writes atomically (a temporary file in `/durable`, then `mv`). The two path variables exist only for the hermetic test. Until Story 0.2, a container stays `starting` and then turns `unhealthy`, by design.

**Relative directories** keep S19's rule reachable (`src/cpf/ocutalon.cpf` = this file minus the CallIn and IPM lines). If the live check shows another location, switch to absolute `/durable/iris/mgr/...` paths and log it in the Spec Change Log. If the merge refuses `IRIS.IF.*`, that is an `intent gap` HALT naming AD-3, never a dropped line.

**Integration ACs:** Docker's health monitor (row 7) and the slots (the lead AC) consume this story's work.
- Consumed-by:
  - Story 0.2: the marker writer, `--after`, `module.xml` resources and the `.dockerignore` allow-list.
  - Story 0.3: the web port and the public package maps.
  - Story 0.7: the CI override extends the compose file, and CI runs `docker/tests/test-*.sh`, the live one on the IRIS runner.
  - Epic 10: `install.sh` uses `IRIS_IMAGE`.
  - Epic 15: `src/cpf/ocutalon.cpf`.
- Consumes: none.

**Tests:** there is no framework yet, so the tests are plain bash scripts, `docker/tests/test-*.sh`, each runnable alone and exiting 0 on success. The marker written by hand in row 7 is a test fixture, not Story 0.2's writer.

**Reuse (Rule 2):** the repository has no sibling to extend. The Dockerfile and health check adapt the disposable S1 spike files from outside the repository.

**Ledger inbox:** none.

## Verification

**Commands:**
- `(loop)` `bash docker/tests/test-healthcheck.sh` -- expected: exit 0, PASS for rows 1–6.
- `(loop)` `bash docker/tests/test-compose-file.sh` -- expected: exit 0.
- `(loop)` `bash docker/tests/test-compose-start.sh` (`timeout: 600000`) -- expected: exit 0 in about 3 to 5 minutes, under 9 even with every wait capped. Afterwards `docker compose ls -a` and `docker volume ls` show nothing named `ocutalon-t01-*`.
- `(loop)` `bash docker/tests/test-build-inputs.sh` (QA) -- expected: exit 0 in under 10 s: the build context carries only the Dockerfile's COPY sources, and `IRIS_IMAGE` reaches `FROM`.
- `(loop)` `bash docker/tests/test-boundaries.sh` (QA) -- expected: exit 0: ASCII only, no local path or key-like string, no push or sign-in, `config` only with `--quiet`, `inspect` only with `--format`.
- `(once)` `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 docker compose -p ocutalon-t01-plain -f docker-compose.yml -f docker/tests/compose.throwaway.yml build && test "$(docker run --rm --entrypoint iris ocutalon-t01-plain-iris qlist | cut -d^ -f10)" = IRIS; rc=$?; docker image rm -f ocutalon-t01-plain-iris >/dev/null; [ $rc -eq 0 ]` -- expected: exit 0. This builds the non-Health image without starting IRIS.
- `(once)` `git status --short` -- expected: only the files listed in Tasks.

**Collision avoidance:** each run uses a unique `-p ocutalon-t01-*` project. The override drops `ports` and `env_file`, so the run publishes no host port and receives no keys: 1972–1979, 1990/1991, 52773–52779, 52790/52791 and 8089–8091 are all untouched (52773 is taken here). The product file fixes no container, volume or image name, so everything is project-scoped. The trap tears down only `$P`. There is one IRIS stack at a time.

**Shared surfaces:** none that other tests assert on. The slots' `config/merge.cpf` changes only in the lead step. Every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19):**
- Matrix row 4: the pattern `';running'` turns `test-healthcheck.sh` red.
- Row 5: dropping the `-n` guard turns it red.
- AC 1: deleting the `IRIS.IF.*` line turns `test-compose-start.sh` red.
- AC 2: removing the `durable:/durable` mount turns it red after the recreate.
- Row 7: a qlist-only compose `test` turns it red.
- AC 3: `stop_grace_period: 30s`, or a value in `.env.example`, turns `test-compose-file.sh` red.

**Mutation results (Rule 19):** each applied with the smallest change, run, then reverted; `git status --short` and the file's `shasum` were identical afterwards.
- mutation: `docker/healthcheck.sh` pattern `'\^running'` changed to `';running'` -> `test-healthcheck.sh` row 4 (ready) went red.
- mutation: `docker/healthcheck.sh` `[ -n "$want" ] && [ "$have" = "$want" ]` changed to `[ "$have" = "$want" ]` (no `-n` guard) -> `test-healthcheck.sh` row 5 (empty version) went red.
- mutation: `docker/healthcheck.sh` given an extra `iris session IRIS -U %SYS` call -> `test-healthcheck.sh` row 6 (no session) went red.
- mutation: the `CreateMapGlobal ... Name=IRIS.IF.*` line deleted from `docker/merge.cpf` -> `test-compose-start.sh` went red in `CHECK` (`gdest|IRIS.IF.S01` resolved to `ocutalon_data`), on the first start and again after each restart.
- mutation: the service's `volumes: - durable:/durable` removed from `docker-compose.yml` -> `test-compose-start.sh` went red at the first `CHECK` (`/durable` not the named volume) and again after the recreate (both probes gone).
- mutation: the health check `test` replaced by the qlist-only `["CMD-SHELL", "iris qlist | grep -q '\\^running'"]` -> `test-compose-start.sh` row 7 went red for "no marker" and "wrong marker" (status `healthy`, wanted `starting`).
- mutation: `stop_grace_period: 60s` changed to `30s` in `docker-compose.yml` -> `test-compose-file.sh` went red (`compose: stop_grace_period 60s`).
- mutation: `ANTHROPIC_API_KEY=` changed to `ANTHROPIC_API_KEY=x` in `.env.example` -> `test-compose-file.sh` went red (`env.example: both keys, no values, nothing else`).
- mutation: `&& test -n "$version"` removed from `docker/Dockerfile` -> `test-compose-file.sh` went red (`dockerfile: an empty version fails the build`) and `test-compose-start.sh` row 8 went red (`a manifest without a version built an image`).
- mutation: `docker/healthcheck.sh` pattern `'\^running'` changed to `'\^'` -> `test-healthcheck.sh` row 1 (IRIS down) went red.
- mutation: `docker/healthcheck.sh` marker read changed to `have=$(cat "$marker_file" 2>/dev/null || cat "$version_file")` (a missing marker reads as the version) -> `test-healthcheck.sh` row 2 (no marker) went red.
- mutation: `docker/healthcheck.sh` final test changed to `[ -n "$want" ]` (the marker is not compared) -> `test-healthcheck.sh` row 3 (other version) went red.
- mutation: `pull_policy: build` deleted from `docker-compose.yml` -> `test-compose-file.sh` went red (`compose: pull_policy build`).
- mutation: `Directory=ocutalon_code` changed to `Directory=/durable/iris/mgr/ocutalon_code` in `docker/merge.cpf` -> `test-compose-file.sh` went red (`merge.cpf: four database directories, all relative`).
- mutation: the `docker/**` rule deleted from `.gitattributes` -> `test-compose-file.sh` went red (`gitattributes: the copied and executed files keep LF`).
- mutation: `head -n 1` changed to `tail -n 1` in the version extraction of `docker/Dockerfile` -> `test-compose-start.sh` went red (`row 8 with a later <Version> the image holds '9.9.9', wanted '0.1.0'`).
- mutation: the `|| / ERROR #[0-9]/` clause dropped from the `merge_errors` filter of `test-compose-start.sh` -> its control went red (`merge log filter does not isolate the error lines of one process`): the recorded build 154 `ERROR #507` line was no longer flagged. (Code review; this replaces the `$3 == 9` mutation of the filter before it.)

**QA pass (QA).** Files added: `docker/tests/test-build-inputs.sh`, `docker/tests/test-boundaries.sh`. Files changed: `docker/tests/test-compose-start.sh` (`CHECK` resolves 12 globals and 4 packages, 42 values), `docker/tests/test-compose-file.sh` (4 checks added, the `.env` check reads the ignoring rule's source). Gaps closed: the wildcard maps were sampled once each and an exact-name map stayed green; `.env` could be ignored by a user's global file instead of `.gitignore`; the health check's command, interval, timeout and retries and the `sh` shebang were unpinned; `.dockerignore` and `IRIS_IMAGE` were pinned by text only; the intent's Boundaries (ASCII, no local path or key, no push, `--quiet`, `--format`) had no test. QA re-ran the recorded mutations for AC 2, AC 3 and rows 1 to 8 (each went red, each reverted byte-identical) and added:
- mutation: `Name=AI.Agent.Session*` changed to `Name=AI.Agent.SessionD` in `docker/merge.cpf` (AC 1) -> `test-compose-start.sh` went red in `CHECK` (`gdest|AI.Agent.SessionI` resolved to `ocutalon_data`), on the first start and after each of the four restarts; the earlier sample (`SessionD` only) stayed green.
- mutation: the `.env` rule deleted from `.gitignore` while a global ignore file holds `.env` -> `test-compose-file.sh` went red (`git: .env is ignored`); the former `git check-ignore -q .env` stayed green.
- mutation: `retries: 3` changed to `retries: 1` -> `test-compose-file.sh` went red (`compose: health check interval 10s, timeout 5s, retries 3`).
- mutation: the health check path `healthcheck.sh` changed to `healthcheck` in `docker-compose.yml` -> `test-compose-file.sh` went red (`compose: health check runs /opt/ocutalon/healthcheck.sh`).
- mutation: `#!/bin/sh` changed to `#!/bin/bash` in `docker/healthcheck.sh` -> `test-compose-file.sh` went red (`healthcheck.sh: POSIX sh`).
- mutation: the leading `*` removed from `.dockerignore` -> `test-build-inputs.sh` went red (`the build context differs from the files the Dockerfile copies`, listing the decoy `.env`, `irislib` and `.git` files).
- mutation: `FROM ${IRIS_IMAGE}` changed to `FROM ocutalon-iris-base:2026.3.0AI.154.0` in `docker/Dockerfile`, and separately the compose build argument given a literal value -> `test-build-inputs.sh` went red both times (`IRIS_IMAGE: the built image carries label ''`).
- mutation: a non-ASCII dash added to a comment of `docker/Dockerfile`; `/Users/...` added to `.env.example`; an `sk-ant-` string added to `docker/merge.cpf`; `--format` dropped from a `docker inspect` in `test-compose-start.sh`; `--quiet` dropped from `config` in `test-compose-file.sh` -> `test-boundaries.sh` went red for the matching rule each time, naming `file:line` only.
- mutation: `push` removed from the sign-in scanner's pattern, and the `/Users/` pattern misspelled, in `test-boundaries.sh` itself -> its own controls went red (`the scanner does not flag sample 1`, `the scanner does not flag a line that breaks the rule`).
- Every mutation was reverted: `git status --short` and the file's `shasum` matched before and after. `docker compose ls -a`, `docker volume ls`, `docker ps -a` and `docker image ls` show nothing named `ocutalon-t01-*`.

**Code review pass (CR).** The static mutations were applied in the tree and reverted byte-identical (`git status --short` and `shasum` unchanged). The live ones ran in scratch copies of the build files, which hold no `.env`, so the repository never changed. Final tree: `test-healthcheck.sh` 6 PASS, `test-compose-file.sh` 29 PASS, `test-boundaries.sh` 5 PASS, `test-build-inputs.sh` 2 PASS, `test-compose-start.sh` 34 PASS in 74 s; nothing named `ocutalon-t01-*` was left.
- mutation: `!.env` appended to `.gitignore` (AC 3) -> `test-compose-file.sh` went red (`git: .env is ignored`).
- mutation: `!.env.example` deleted from `.gitignore` -> `test-compose-file.sh` went red (`git: .env.example is not ignored`).
- mutation: `name: ocutalon` changed to `name: ocutalon-app` (AC 3) -> `test-compose-file.sh` went red (`compose: top-level name ocutalon`).
- mutation: `.dockerignore text eol=lf` deleted from `.gitattributes` -> `test-compose-file.sh` went red (`gitattributes: the copied and executed files keep LF`).
- mutation: the scanner's former push rule restored in `test-boundaries.sh` -> its controls went red (`the scanner does not flag sample 7`, `8` and `9`).
- mutation: `env_file: !reset []` deleted from `compose.throwaway.yml`, run without a `.env` -> `test-compose-start.sh` went red (`throwaway container has '0' published port(s) and '2' key variable(s)`).
- mutation: `chmod 444` changed to `chmod 644` in `docker/Dockerfile` -> `test-compose-start.sh` went red (`/opt/ocutalon owners and modes are ... 0 644 ...`).
- mutation: `dc stop iris` and `dc down` in `restart_round` made no-ops with `--dry-run` (AC 2) -> `test-compose-start.sh` went red in all four rounds (`the container's start time did not change`, `no new container`).
- mutation: the failing action `CreateMapGlobal:Namespace=OCUTALON,Name=OcuTalonZZ,Database=OCUTALON_NOSUCH` appended to `docker/merge.cpf` (AC 2, "without errors") -> `test-compose-start.sh` went red at the first start (`IRIS did not reach running with the merge applied within 240 s`). Build 154 logged the failure at severity 1 (`ERROR #503`, `#507`, `#520`) and kept IRIS running. It wrote no `*.last_merge`, so no readiness came, and the next start retried the merge (`Files differ; merging`).

**Observed behavior that shaped the live test:** `iris-main` applies `ISC_CPF_MERGE_FILE` at a start only when the file differs from its saved copy (`/durable/iris/^opt^ocutalon^merge.cpf.last_merge`, mode 0444) and otherwise logs `unchanged; skipping`, so a plain restart adds no `Merging` line. `test-compose-start.sh` therefore runs four restarts: plain stop and start, plain recreate, a stop and start after the saved copy is edited (a changed merge file), and a recreate after the saved copy is removed. The last two assert one more `Merging` line and no severity 2 or 3 line from its process. `Security.Resources.Get` returns `PublicPermission` as letters (`R`), not a mask; the test accepts either.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `docker compose up` now builds one image from `docker/Dockerfile` (`FROM ${IRIS_IMAGE}`, default `ocutalon-iris-base:2026.3.0AI.154.0`) and starts it with durable `%SYS` on a named volume. `docker/merge.cpf` creates the four OCUTALON databases (public Read on the public one), the namespace with Interoperability, AD-3's global and package maps and `%Service_CallIn`, with relative directories that resolve to `/durable/iris/mgr/<dir>/`. `docker/healthcheck.sh` calls only `iris qlist` and compares the ready marker with `/opt/ocutalon/version`, which the build derives from the first `<Version>` of `src/module.xml`.

**Files changed.**
- `src/module.xml` -- manifest identity only (name, version 0.1.0).
- `docker/merge.cpf` -- the CPF merge actions.
- `docker/healthcheck.sh` -- POSIX `sh` health check.
- `docker/Dockerfile` -- recipe, read-only copies under `/opt/ocutalon/`, version derivation that fails on an empty version.
- `.dockerignore` -- allow-list of the three copied files.
- `docker-compose.yml` -- the judges' file: `name:`, one `iris` service, volume, health check, `stop_grace_period: 60s`.
- `.env.example` -- the two keys, no values.
- `.gitattributes` -- `docker/**` and `src/module.xml` keep LF (added at review; not in the Tasks list).
- `docker/tests/compose.throwaway.yml`, `test-healthcheck.sh`, `test-compose-file.sh`, `test-compose-start.sh` -- the override and the three tests (rows 1 to 6 hermetic, static inspection, live throwaway run).

**Review.** 40 findings: high 0, medium 6, low 25, false 8, maybe-false 1. Patches applied (7 entries after grouping, three of them medium): LF rules for the copied files; plain, changed-file and removed-record restart rounds; `res-exists` in `CHECK`; first-wins `<Version>` decoy build; static checks for `pull_policy`, `restart`, `env_file`, `ports` and relative `Directory=`; a control for the merge-log filter; the marker removed before row 7; a published-port and key-variable check on the throwaway container; mutation lines for rows 1 to 3. Deferred: 1 (an unchanged merge file is skipped, so a partly failed first merge is not retried; unverified medium). Rejected findings carry their reasons in the triage log (spec-bound, belong to Story 0.2 or 0.7, theoretical, or false).

**Follow-up review recommended: true.** Three medium entries were patched. Unverified: the `.gitattributes` rules have not been exercised on a real Windows autocrlf checkout, and the changed-merge-file round emulates an upgrade by editing iris-main's saved copy instead of starting a new image.

**Verification performed (final tree).**
- `bash docker/tests/test-healthcheck.sh`: exit 0, rows 1 to 6 PASS.
- `bash docker/tests/test-compose-file.sh`: exit 0, 26 checks PASS.
- `bash docker/tests/test-compose-start.sh`: exit 0, 32 PASS lines in about 70 s, in a throwaway `ocutalon-t01-*` project.
- `(once)` non-Health image build: exit 0, `qlist` field 10 is `IRIS`.
- `(once)` `git status --short`: the Tasks files plus `.gitattributes` and this spec.
- The eight mutations added at review went red and were reverted byte-identical (the nine recorded by the implement pass were demonstrated by it). `docker compose ls -a`, `docker volume ls` and `docker image ls` show nothing named `ocutalon-t01-*`.
- Matrix Test Audit: rows 1 to 6 ran in `test-healthcheck.sh`, rows 7 and 8 in `test-compose-start.sh`, all passing.

**Residual risks.**
- AD-23 and Rule 21 say the merge reapplies at every start. On build 154 it runs at the first start and whenever the merge file changes (see the Spec Change Log); the lead words the spine accordingly.
- The compose file needs Docker Compose 2.24 or later (`env_file` with `required: false`); Epic 10's install script and README state it.
- The slot recreation AC is the lead's, after code review, and has not been run.
