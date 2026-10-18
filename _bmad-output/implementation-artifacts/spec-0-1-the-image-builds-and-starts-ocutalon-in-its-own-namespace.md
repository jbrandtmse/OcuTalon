---
title: 'Story 0.1: The image builds and starts OcuTalon in its own namespace'
type: 'feature'
created: '2026-10-18'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
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

## Spec Change Log

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
