# Story 11.23 evidence: the real install.sh starts OcuTalon on build 109

Lead-side smoke for AC6 (the manual build 109 run), run on 2026-11-05 (UTC) by a helper of the epic runner.

## What ran

- Worktree: the epic-11 worktree, branch `OCT-epic11`, commit `047fec6e`. install.sh ran as committed there. Uncommitted at the time
  (QA/review patches and bookkeeping): `docker/tests/test-install-script.sh`, `docker/tests/test-readme.sh`,
  `spec-11-23-install-sh-accepts-build-109.md`, `sprint-status.yaml`, `deferred-work.md`, `cycle-log-epic-11.md`. None of them is
  read by install.sh or the image build.
- Docker: arm64 daemon, Docker Compose 5.5.0.
- Image refs loaded (unchanged before and after the run):
  - `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0` (ID 78bfd01c5b6a, arm64)
  - `irishealth-community:2026.3.0AI.154.0`, `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`
    and `ocutalon-iris-base:2026.3.0AI.154.0` (ID 4e3907db2004)
  - `iris-community:2026.3.0AI.154.0`, `docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.154.0` (ID 8fa0ae85777d)

## Why a docker wrapper

install.sh prefers Health build 154 when a 154 ref is loaded, and the 154 refs are loaded on this machine and may not be removed,
untagged or retagged. So the install.sh run had a wrapper on PATH, first, named `docker`. It passes every call to the real docker
unchanged, except the image listing (install.sh's `docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}'` in `scan_images`),
from whose output it drops every line with the tag `2026.3.0AI.154.0`. No image is touched. Its exact content:

```bash
#!/bin/bash
# Passes every docker call to the real docker unchanged, except the image listing (docker image ls / image list / images):
# its output drops every line with the tag 2026.3.0AI.154.0, so install.sh sees no build 154 ref. Nothing is untagged.
self_dir=$(cd "$(dirname "$0")" && pwd)
real=""
IFS=:
for d in $PATH; do
  if [ "$d" = "$self_dir" ]; then continue; fi
  if [ -x "$d/docker" ]; then real="$d/docker"; break; fi
done
unset IFS
if [ -z "$real" ]; then echo "docker wrapper: no real docker on PATH" >&2; exit 127; fi
if { [ "${1:-}" = image ] && { [ "${2:-}" = ls ] || [ "${2:-}" = list ]; }; } || [ "${1:-}" = images ]; then
  out=$("$real" "$@")
  rc=$?
  printf '%s\n' "$out" | grep -v ':2026\.3\.0AI\.154\.0' || true
  exit $rc
fi
exec "$real" "$@"
```

Through the wrapper the listing shows one candidate: the build 109 ref above.

## The command

A lane B throwaway, as `docker/tests/test-install-script-live.sh` runs install.sh: a scratch script sourced `docker/tests/lib-live.sh`
and ran `live_start i23` and `live_web_port` with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b`,
`OCUTALON_TEST_WEB_PORT=52802`, `OCUTALON_LOCK_OWNER='epic=11 stage=smoke'`, `OCUTALON_RUN_TAG=e11s23b109`,
`OCUTALON_LIVE_DEADLINE=570`. Then:

```
env PATH="<wrapper folder>:$PATH" COMPOSE_PROJECT_NAME="$P" COMPOSE_FILE="<lib-live files>" \
  IRIS_IMAGE="$P-base:2026.3.0AI.154.0" OCUTALON_INSTALL_WAIT=420 bash install.sh
```

- `$P` = `ocutalon-i23-e11s23b109-<epoch>-<pid>` (run 1: `...-1793904405-12415`, run 2: `...-1793904643-14177`).
- `<lib-live files>`: `docker-compose.yml`, lib-live's decoy key file, `docker/tests/compose.throwaway.yml`, `ci/compose.ci.yml` (model
  and Bot API mock, dummy bot token), lib-live's port file (web port 52802, published on the loopback address only). Run 2 adds, last, lib-live's `live_no_bot_token`
  file (`TELEGRAM_BOT_TOKEN` set and empty, which is what a `.env` copied from `.env.example` holds).
- `.env` did not exist in the worktree; install.sh created it and the run's cleanup removed it (the throwaway override resets
  `env_file`, so the container never read it). `git status --short` is the same before and after, apart from this file.

## Results (run 2, the recorded run)

Install output, build log and compose progress lines left out, password replaced:

```
OcuTalon install
Docker is running on arm64, and Docker Compose is 5.5.0.
Image: IRIS for Health, build 109 (docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0).
Tagged it as ocutalon-i23-e11s23b109-1793904643-14177-base:2026.3.0AI.154.0, the name that OcuTalon's own image is built from.
Created .env from .env.example. The model key (ANTHROPIC_API_KEY) in it is empty:
OcuTalon starts without one, and its page shows a notice about it. To set a key, add it to .env and run: docker compose up -d --force-recreate
Starting OcuTalon with docker compose up -d. The first start takes a few minutes; up to 15 minutes are allowed.
Waiting, 32 s so far: container running, health check starting
...
Waiting, 2 min 33 s so far: container running, health check starting

OcuTalon is ready after 2 min 44 s.

  Open:      http://localhost:52802/ocutalon/
  User:      ocutalon
  Password:  <printed password>
```

| # | Check | Result |
|---|-------|--------|
| 1 | Image line names build 109 | PASS: `Image: IRIS for Health, build 109 (docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0).` The base name holds the 109 image's ID (sha256:78bfd01c5b6a...); the image build's `FROM` resolved to that digest; `iris qlist` in the container reports version `2027.1.0AI.109.0com`. |
| 2 | Start | PASS: install.sh exit 0 after 164 s (wall clock of the call); ready block printed with `http://localhost:52802/ocutalon/`. |
| 3 | Sign-in page | PASS: `curl` of the printed URL answered HTTP 200, and the page holds the sign-in form (`IRISPassword` field). |
| 4 | Demo guide step 1 after sign-in | PASS: `OCUTALON_URL=http://localhost:52802 npx playwright test --project=demo-path e2e/demo-path/01-page.spec.ts` (from `web/`): 6 passed, exit 0. |

Check 4 in detail: the spec signs in with `README_ACCOUNT` (user `ocutalon` and the README password); the run first checked that the
user and password install.sh printed are exactly that account. The six tests: the page snapshot loads after sign-in; the empty chat
panel and its last line "Start with step 1 of the demo guide above."; the status rail ("Nothing yet. Step 1 of the guide sets up a
watch."); the simulated phone and mailbox; the region "Demo guide" with its five steps, where step 1 is "Watch" with the prompt
"Watch the Orders production and only tell me if something needs me." and its one Send button (nothing sent); and Break the feed with
the hint "Ask OcuTalon to watch the Orders production first (step 1).".

## Run 1 (same command without the empty bot token layer)

Checks 1 to 3 passed the same way (exit 0, ready after 3 min 10 s, 192 s for the call; HTTP 200). The spec gave 5 passed, 1 failed:
the guide test (step 1) passed; "shows the status rail" failed at its Telegram card assertion, because `ci/compose.ci.yml` sets a
dummy bot token, so the card showed the pairing QR instead of "Telegram not set up". The repo's demo-path unit avoids this by parking
Telegram (`live_park_telegram` in `wait_started_ready`); this smoke does not use that path, so run 2 added lib-live's
`live_no_bot_token` layer, which matches a judge's install, and all six passed. No product file was changed between the runs.

## Teardown

Each run's EXIT trap removed `$P-base:2026.3.0AI.154.0` (by name, without `-f`), removed the `.env` the run created, then ran
lib-live's `live_cleanup` (`docker compose down -v --rmi local`, lock released: "LOCK released throwaway-iris" both times).
`ci/iris.sh teardown` with `OCUTALON_RUN_TAG=e11s23b109` then reported 0 projects, containers, volumes, networks and images left.
`docker ps -a`, `docker volume ls`, `docker network ls` and `docker image ls` show nothing named `e11s23`. The six shared image refs
listed above keep their IDs.
