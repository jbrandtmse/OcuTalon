---
title: 'Story 11.18: The update hook updates the online demo, and a rehearsal candidate proves the sequence'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-16-the-sequence-asks-before-each-outward-step-after-the-gates.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-15-the-hands-on-gate-stops-the-sequence-and-its-resume-command.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-14-the-release-sequence-runs-every-gate-on-the-pushed-candidate.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 11.16's `demo` step calls `release/demo-update.sh` through a fixed contract, but the hook does not exist, so the sequence can only say "the online demo was not updated". Nothing copies a release to the demo host, reads `ocutalon-demo status`, or writes the online-demo line into the draft notes. No stand-in for the host exists to test against. And nothing has run the whole sequence end to end on a candidate: `release.sh` has no rehearsal mode, and a rehearsal cut named `release/1.0.0-rc1` would trip the step epics' merge gate (U-203).

**Approach:**
- Build the hook to 11.16's call contract and AD-25's interface. It copies a `git bundle` over `host_run demo` (SSH, strict host keys, `DEMO_` keys of the author's `release.conf`), runs `ocutalon-demo update <v>`, then `ocutalon-demo status`, and checks both. It writes its own record section and the draft notes' online-demo section.
- Build a stand-in demo host in `release/demo-standin/`: a throwaway compose project whose `ocutalon-demo` answers `status` and `update` exactly as AD-25 says. It builds the real image from the copied bundle and keeps a golden-copy volume.
- Add `release.sh start --rehearsal`. The candidate is `rehearsal/<v>-rc<n>`, the record says `Mode: rehearsal`, the remote can only be a local bare repository, and the outward steps after the gates never act.
- Prove the rehearsal end to end: on a throwaway hermetically (CI), and once against the live stand-in.

This story takes epics.md Story 11.18's two criteria, verbatim there, with the U-203 amendment (AC7).

## Boundaries & Constraints

**Always:**
- **The conventions of 11.5 and 11.14 to 11.17 still hold:**
  - Bash 3.2 and ASCII (Rule 14); mode 100755; `umask 077`; the main guard;
  - output lines `PASS|FAIL|SKIP <id> <detail>`, then `RECORD`, `NOTES` and `RESULT`;
  - answers only on stdin; no value printed (no `env`, `printenv`, `set -x`, `declare -p`);
  - never `docker push|login|save|export|pull`.
- **The hook keeps 11.16's call contract exactly.** It runs in `<state>/candidate` as `release/demo-update.sh --version <v> --rc <n> --ref <ref> --record <abs> --notes <abs>`.
  - Its output is any lines, then `RESULT updated|scheduled|not updated|fail` last. `scheduled` adds a `SCHEDULED <nextReset>` line, and `fail` adds one `FAIL demo-update <reason>` line.
  - Exit codes: 0 updated or scheduled; 3 not updated (no demo host configured); 1 failed; 2 refused (nothing sent to any host).
- **The ref.**
  - The hook reads `Mode:` and `Candidate:` from the record's `## Release sequence` (11.14's `record_field`).
  - `Mode: release` needs `--ref v<v>`, an annotated tag in the clone on the candidate's SHA.
  - `Mode: rehearsal` needs `--ref <the candidate's 40-hex SHA>`.
  - Anything else is refused.
- **The bundle** holds exactly one ref:
  - `refs/tags/v<v>` for a release;
  - `refs/heads/rehearsal/<v>-rc<n>` at the cut SHA for a rehearsal ("because there is no tag").
  - The hook makes it in a temporary bare repository with `git fetch`, never `git push` and never by changing the clone's refs. `git bundle verify` must pass.
  - It goes through `host_run demo` on stdin into `ocutalon-demo/bundles/ocutalon-<v>.bundle` (relative to the login folder), written to `.part` and then renamed.
- **The host's answers.**
  - `update` exits 0 with exactly `{"result":"updated","version":"<v>"}` or `{"result":"scheduled","at":"<UTC ISO 8601>"}` (whitespace free). Anything else fails.
  - A non-zero exit is shown and recorded as its one line (`detail_clean`).
  - `status` must have exactly AD-25's seven keys and types (the rules of Epic 29's `check_demo_status`).
  - After `updated`: `runningVersion` = `goldenVersion` = `<v>`, `pendingVersion` null, `access` `restricted`.
  - After `scheduled`: `pendingVersion` = `<v>`, `access` `public`.
  - ssh exit 255 fails as `could not reach the demo host`.
- **Configuration (AD-19, AD-25, CON-5).** `release_config_read <file> DEMO` reads only `DEMO_` keys from the same `release.conf`:
  - `DEMO_SSH` (user@host) and `DEMO_KEY`;
  - optionally `DEMO_PORT`, `DEMO_KNOWN_HOSTS` and `DEMO_STANDIN` (`yes`, or unset).
  - No file, or no `DEMO_SSH`, means no demo host is configured. The hook says so, exits 3, writes the not-updated notes line, and calls no host.
  - A set `DEMO_SSH` with a missing or unreadable key, a config file inside the repository, an unknown `DEMO_` key or a bad `DEMO_STANDIN` is refused (exit 2).
  - No value of the file is ever printed or recorded. The record names the host only as "the configured demo host" or "a stand-in demo host".
- **A rehearsal never reaches the real online demo.**
  - In `Mode: rehearsal`, with a demo host configured, the hook refuses unless `DEMO_STANDIN=yes`.
  - With `DEMO_STANDIN=yes` in any mode, the hook prints `HOST stand-in`, and its record and notes say a stand-in was updated, not the online demo.
  - `release.sh`'s `demo` step in `Mode: release` turns a stand-in update into the row `not updated`.
- **The stand-in (`release/demo-standin/`)** is a compose project named `ocutalon-demostandin-<OCUTALON_RUN_TAG>`.
  - It builds `docker/Dockerfile` from a clone of the copied bundle, on the local base image with `--pull=false`, after checking the base image is present (never a pull).
  - It keeps a `durable` volume and a `golden` volume.
  - Its container starts the built image with the entrypoint replaced: it copies the image's `/opt/ocutalon/version` into `/durable/ocutalon.version`, which stands for IRIS's in-place upgrade, and then writes `/durable/ocutalon.ready`.
  - `update` follows AD-25's order: build before the boundary; if `access` is public, record `pendingVersion` and answer `scheduled`. Otherwise:
    - check that the golden copy holds the running (previous) version: the update's exemption, which replaces the reset's version refusal;
    - restore golden into durable, start on the new image, wait for ready, check that the upgraded copy reports `<v>`;
    - stop, capture golden without the ready marker, start from it;
    - answer `updated`.
  - Any failure exits non-zero with one reason line, and golden is left unchanged.
  - Stand-in-only commands: `init <bundle>` (the first golden copy, from a fresh start), `reset` (applies a pending update, or restores golden and refuses one whose version differs from the image's), `access restricted|public` and `down`.
  - It holds no lane lock, because it starts no IRIS. It removes only its own project's containers, volumes, images and folders.
- **Rehearsal mode (`release.sh start --version <v> --rehearsal`; U-203).** Every name that 11.5 and 11.14 to 11.17 derive from `<v>` and `<n>` carries the rehearsal kind, and is set once at `start` into the state:
  - the branch `rehearsal/<v>-rc<n>`;
  - the record `release/records/<v>/rehearsal-rc<n>.md`;
  - the notes `release/records/<v>/rehearsal-rc<n>-notes.md`;
  - the state folder `<v>-rehearsal-rc<n>/`;
  - the run tags `reh<digits>rc<n>upg|reh`.
  - The record says `Mode: rehearsal`, and `Candidate: <v> rc<n>, rehearsal/<v>-rc<n> at <sha>`.
  - `next_rc` counts only rehearsal branches.
  - `next|resume|status` take `--rehearsal` to pick a rehearsal state.
  - Real hands-on-time sums never count rehearsal records.
- **The rehearsal's guards** (each `REFUSED`, exit 2, with nothing written or pushed):
  - any remote of the checkout whose URL is not a local bare repository, named by the remote's name only;
  - `--from` with a `release/*` name (the U-203 line), and any other `--from`, because a rehearsal is cut from the integration branch;
  - a push whose branch is not `rehearsal/<v>-rc<n>` (checked again at `push`).
- **In rehearsal, nothing goes out.** `pr`, `merge`, `tag` and `mergeback` still ASK. A decline is skipped, as in 11.16. A `yes` gives `FAIL <step> a rehearsal never ...`, exit 1, sends nothing and calls no `gh` write, and the ASK comes back on the next `next`. `demo` passes `--ref <cut sha>`.
- **Extend, don't copy (Rule 2):**
  - 11.3's `release_config_read`, `host_run` and `record_write`;
  - 11.4's `notes_path`; 11.5's `candidate_branch` and `next_rc` (each takes an optional kind argument, with its default unchanged);
  - 11.14's `record_field`, `candidate_clone` and gate steps; 11.15's hands-on gate; 11.16's ASK, rows and `demo` step;
  - test fixtures: 11.14's fixture driver, 11.15's fresh-pass fixture, and 11.16's `gh` shim and pre-receive log.
- **Tests:** only throwaway repositories, local bare remotes, an `ssh` shim through `OCUTALON_REHEARSAL_SSH` (11.3's seam) that checks the strict-host-key argv and runs the command in the stand-in's login folder, and either the stand-in or a canned fake host.

**Never:**
- Update the real online demo host, SSH to any real host, push to `origin` of the real repository, tag outside a throwaway, open a pull request, publish anything, change settings, use a real model key, or pull or push an image.
- Run `release/release.sh` or the hook in this worktree or any real checkout.
- Edit Epic 29's `release/demo-host-check.sh`, `release/demo-load.sh`, `docker/tests/test-online-host.sh` or `docker/tests/lib-online.sh` (read only, contended), or `ci/units.sh`, `.github/workflows/*`, `src/module.xml`, `README.md`, `docker/tests/lib-live.sh` or `.gitignore`.
- Add `rehearsal/*` to any workflow trigger. Change the rc1 merge gate (`git ls-remote --heads origin release/1.0.0-rc1`) or any dependency statement.
- Commit or push the draft notes. Write the literal words of 11.4's `no-outward` patterns in a scanned file.
- Let any option, variable or configuration key answer an ASK, skip a gate, or let a rehearsal record carry a pass over.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Update before launch | `Mode: release`, `--ref v1.0.0` (annotated, on the candidate SHA). The host's `access` is restricted | Bundle `refs/tags/v1.0.0` copied; `ocutalon-demo update 1.0.0`, then `status`; `PASS` lines; record `## Online demo update` `Result: updated`; notes `## Online demo update` updated line; `RESULT updated`, exit 0 | -- |
| Update after launch | `access` public | `SCHEDULED <at>`; status `pendingVersion` 1.0.0; the notes line names `<at>`; `RESULT scheduled`, exit 0 | -- |
| Host refuses | `update` exits non-zero with one line | `FAIL demo-update the demo host did not update: <line>`; the record keeps the line; the notes say not updated; `RESULT fail`, exit 1 | Nothing retried |
| Bad answers | Extra JSON key, wrong version, `status` without `access`, running not `<v>` after `updated`, `pendingVersion` not `<v>` after `scheduled`, ssh exit 255 | `FAIL demo-update` naming the field, or `could not reach the demo host`; exit 1 | The notes say not updated |
| No host configured | No `release.conf`, or no `DEMO_SSH` | `SKIP demo-update no demo host is configured; the online demo was not updated`; no ssh call; notes and record say so; `RESULT not updated`, exit 3 | -- |
| Refusals | `DEMO_KEY` missing or unreadable; config inside the repository; unknown `DEMO_` key; release `--ref <sha>`; rehearsal `--ref v<v>`; a tag on another SHA; a missing record section or notes file; no `jq`; rehearsal without `DEMO_STANDIN=yes` | One `FAIL demo-update <reason>` line naming a key or rule, never a value; `RESULT fail`, exit 2 | No host contacted; nothing written |
| Stand-in update (live) | Golden 0.1.0 from `init`; restricted; `update 1.0.0` from a bundle | Image built from the bundle; golden and running 1.0.0; `{"result":"updated","version":"1.0.0"}` | Fault (the upgraded copy reports another version): exit 1, one line; golden unchanged |
| Stand-in schedule and reset (live) | Public; `update 1.0.1`; then `reset` | `scheduled` at `nextReset`; `pendingVersion` 1.0.1; after `reset`, golden and running 1.0.1 | `reset` with a golden version that differs from the image refuses; the update's own restore does not |
| Rehearsal start | `start --version 1.0.0 --rehearsal`, every remote a local bare repository | State `1.0.0-rehearsal-rc1`; `Mode: rehearsal`; the branch, record and notes rehearsal names | A network-URL remote, `--from release/1.0.0-rc1` or any `--from`: `REFUSED` (Design Notes) |
| Rehearsal flow | 11.14's fixture gates; the push `yes` | push, every gate, `hands-on` stop; `resume` refused until the fixture pass; then `pr merge tag mergeback` declined (`SKIP`); `demo` yes with `--ref <cut sha>`; end `Result:` rehearsal text | `yes` at `pr`/`merge`/`tag`/`mergeback`: `FAIL <step>` rehearsal line, nothing out |
| Push guard | The state's branch planted as `release/1.0.0-rc1` in a rehearsal | `REFUSED` with the U-203 line at `push` | The bare remote is unchanged |
| No carry-over | A real candidate whose `## Hands-on pass` is a carry-over naming the rehearsal candidate; `start --from rehearsal/1.0.0-rc1` in release mode | 11.15's `REFUSED hands-on a rehearsal record never carries a pass over`; `REFUSED a release candidate is never cut from a rehearsal candidate` | Nothing written |

</intent-contract>

## Code Map

**Prerequisites.** Stories 11.3, 11.4, 11.11, 11.13, 11.5, 11.14, 11.15, 11.16 and 11.17 must be merged into this branch. Today `release/` holds only `lib-release.sh`, `rehearse.sh`, `upgrade-harness.sh`, `standalone-bridge.sh` and Epic 29's files, and 11.5 and 11.13 to 11.17 are `ready-for-dev`. If `release.sh` with 11.14's gates, 11.15's hands-on gate or 11.16's `demo` step is missing, implement HALTs `blocked` with `missing prerequisite story`, naming them.

**Files:**
- `release/demo-update.sh` -- new; the hook. Its header carries the call contract, the bundle rule, the host's two commands and the exit codes (Rule 14: contract only). It sources `lib-release.sh`.
- `release/demo-standin/ocutalon-demo` -- new; the stand-in (POSIX sh, 100755). It reads its settings (project, compose file, base image) from `ocutalon-demo/standin.conf` in its login folder, which the test writes. It prints AD-25's status JSON with `printf`, keys in the order of `write_status_fixture`.
- `release/demo-standin/compose.yml` -- new:
  - one service `iris`, `image: ${STANDIN_IMAGE}`, user 51773, the entrypoint replaced as in Boundaries, and the `durable` volume at `/durable`;
  - a `golden` volume, which no service mounts. The stand-in copies between the two with `docker run --rm` on the built image.
- `release/lib-release.sh` (`:36-37`, `:73-153`, `:157-200`, `:207-216`) -- extend:
  - `release_config_read <file> [REHEARSAL|DEMO]`: per-prefix key lists, path keys and required keys. `REHEARSAL` (the default) is byte-for-byte today's behaviour, which `test-rehearsal.sh` pins. `DEMO` returns 3 for no file or no `DEMO_SSH`.
  - `host_run demo <cmd>`: always ssh (never the dry branch), with `DEMO_SSH`, `DEMO_KEY`, `DEMO_PORT` and `DEMO_KNOWN_HOSTS`, and the same option list as `clean`.
  - `record_write`'s default heading also covers `rehearsal-rc[0-9]*` (`# OcuTalon <v> rehearsal-rc<n>`).
  - `record_path`, `notes_path`, `candidate_branch` and `next_rc` each take an optional last argument `rehearsal`.
  - `demo_status_judge <status json> <updated|scheduled> <v>`: one FAIL detail per broken rule, empty when good. It copies `check_demo_status`'s key and type expressions (`release/demo-host-check.sh:398-437`). The reason for the copy: Epic 29's file is read only and contended, and it runs as a script.
- `release/release.sh` (11.5; extended by 11.14 to 11.17) -- extend:
  - `start --rehearsal`, the guards and the kind-derived names;
  - `--rehearsal` on `next|resume|status`;
  - the four outward steps' rehearsal `FAIL` before any remote or `gh` call;
  - the `demo` step:
    - `--ref <cut sha>` in rehearsal;
    - in release mode, fetch `refs/tags/v<v>` into `<state>/candidate` when it is absent;
    - the rehearsal ASK text and the stand-in rows;
    - `not updated` takes its reason from the `SKIP demo-update` line;
  - the rehearsal end `Result:` text;
  - the header and usage gain rehearsal mode and the U-203 sentences (Design Notes).
  - Every use of a candidate name reads the state, never a literal `release/`.
- `docker/tests/test-release-sequence.sh` (11.5; extended by 11.14 to 11.17) -- extend; no new `CHECK_SCRIPTS` entry:
  - `--cases demo`: the hook with a canned fake host (a script that answers from flag files), the ssh shim, and a temporary `release.conf`;
  - `--cases rehearsal`: the whole rehearsal flow, the guards and the no-carry-over cases;
  - `--live-demo prepare|hook|rehearsal|clean`, one part per call, never in CI. It needs `OCUTALON_RUN_TAG` and the base image, and prints `SKIP` without the image.
- `release/demo-host-check.sh:398-437` (read only) -- the status rules copied above. `docker/tests/test-online-host.sh:308-315` (read only) -- `write_status_fixture`, the fixture shape. A pin compares the key list in `lib-release.sh` with `demo-host-check.sh`'s.
- `docker/Dockerfile` (read only) -- `IRIS_IMAGE` default `ocutalon-iris-base:2026.3.0AI.154.0`. It writes `/opt/ocutalon/version` from the first `<Version>`, and fails without `src/ocutalon/csp/index.html`. `/durable` is owned by 51773. `.dockerignore` is an allow-list, so building from a bundle clone's root works.
- `docker/tests/test-rehearsal.sh:383-470` -- the stub-ssh precedent: `OCUTALON_REHEARSAL_SSH`, the argv checks, the stdin size log.
- `ci/units.sh:150` `NOT_IRIS_INPUT_PATTERN` -- it covers `release/` and `docker/tests/test-*.sh`, so no IRIS group runs for these files. A new folder under `docker/tests/` would run every group, which is why the stand-in lives in `release/demo-standin/`.
- The 11.13 draft uses `## <area>` headings (one is "The online demo"), so the hook's notes section is titled `## Online demo update` and never replaces an area.

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure, figures into `## Verification`):
  - On a scratch throwaway (never this worktree), time `docker build --pull=false -f docker/Dockerfile` of a bundle clone of HEAD with a placeholder `src/ocutalon/csp/index.html`, and confirm that no pull happened.
  - In the built image with a fresh named volume, run `docker run --rm --entrypoint sh <image> -c 'id -u; cat /opt/ocutalon/version; touch /durable/x; command -v sleep'`.
  - Check `git bundle create` from a temporary bare repository filled by `git fetch` of a tag, and of a SHA under `refs/heads/rehearsal/...`, then `list-heads` and `clone`.
  - Time the self-test parts. If a part with this story's cases nears 6 minutes, split it with `--cases`.
- `release/lib-release.sh` -- the helpers above. Keep every consumer's self-test green.
- `release/demo-update.sh`, `release/demo-standin/ocutalon-demo`, `release/demo-standin/compose.yml` -- as in Boundaries, the Matrix and Design Notes.
- `release/release.sh` -- rehearsal mode, the guards, the demo step changes, the texts and the header.
- `docker/tests/test-release-sequence.sh` -- every Matrix row, AC1 to AC12 and IA1 to IA5, the `--cases` parts and `--live-demo`. Update the pins of 11.5 and 11.14 to 11.17 that a kind argument or the `demo` row touches.

**Acceptance Criteria:**
- **AC1 (update before launch; REL-10, AD-25, CON-1):** **Given** a fake host answering `updated`, **when** the hook runs with `--ref v1.0.0`, **then**:
  - the ssh shim saw, in order, the bundle copy (stdin size equal to the bundle's), `ocutalon-demo update 1.0.0` and `ocutalon-demo status`;
  - each call had `-o StrictHostKeyChecking=yes`, `-o BatchMode=yes`, `-i <DEMO_KEY>` and the `DEMO_SSH` destination;
  - the copied bundle verifies and lists exactly `refs/tags/v1.0.0` at the candidate SHA;
  - `RESULT updated`, exit 0;
  - the record holds `## Online demo update` (Design Notes golden), with `## Release sequence` byte-identical;
  - the draft notes hold the updated line.
- **AC2 (scheduled):** **Given** a fake host answering `scheduled` and a status with `pendingVersion` 1.0.0, **when** the hook runs, **then** it prints `SCHEDULED <at>`, writes `<at>` into the notes line, gives `RESULT scheduled` and exits 0. A `pendingVersion` of null fails.
- **AC3 (failures shown and recorded):** **Given** each failing row of the Matrix, **when** the hook runs, **then** it prints one `FAIL demo-update <reason>` that names the field or carries the host's own line, and gives `RESULT fail`, exit 1. The record keeps the reason, and the notes say the online demo was not updated.
- **AC4 (no demo host; REL-10, CON-5):** **Given** no `release.conf`, or one without `DEMO_SSH`, **when** the hook runs, **then** it prints the `SKIP` line, makes no ssh call, writes the not-updated notes line and the record section, and gives `RESULT not updated`, exit 3.
- **AC5 (configuration and refusals; AD-19):** **Given** each refusal row, **when** the hook runs, **then** it exits 2 with no ssh call and no write.
  - With planted `DEMO_SSH` and `DEMO_KEY` values in a full run, no value appears in any output line, record, notes or shim log, except the key path and destination in ssh's own argv.
  - `release_config_read` with no prefix still passes `test-rehearsal.sh`.
- **AC6 (the stand-in host; REL-10, AD-25; `(once)` live):** **Given** `--live-demo prepare` (golden 0.1.0 from `init`), **when** `--live-demo hook` runs, **then**:
  - restricted: `update 1.0.0` built from the copied tag bundle answers `updated`, and `status` shows running and golden 1.0.0;
  - public: `update 1.0.1` answers `scheduled` at `nextReset` with `pendingVersion` 1.0.1, and `reset` then gives running and golden 1.0.1;
  - the fault gives a non-zero exit with one line, and golden is unchanged;
  - `reset` refuses a golden whose version differs from the image, while the update's restore over the previous version passes;
  - `docker images` shows no image pulled for the run;
  - `--live-demo clean` leaves no container, volume, image or folder of `ocutalon-demostandin-<tag>`.
- **AC7 (U-203: rehearsal names and remotes) [AMENDED 2026-11-01, U-203 (veto, kept)]:** **Given** `start --version 1.0.0 --rehearsal`, **when** the candidate is cut and pushed, **then**:
  - the branch is `rehearsal/1.0.0-rc1`, the record is `rehearsal-rc1.md` with `Mode: rehearsal`, and the pre-receive log never shows a `release/*` ref;
  - **given** a remote with a network URL (configured only, never contacted), `--from release/1.0.0-rc1`, or a planted `release/1.0.0-rc1` branch in the state at `push`, **then** each is `REFUSED` with the U-203 lines, and nothing is written or pushed;
  - `release.sh`'s header holds the two U-203 sentences of Design Notes (a test pins them);
  - no workflow file changed, and the rc1 merge gate is untouched.
- **AC8 (the rehearsal proves the sequence; REL-1, REL-3, REL-7):** **Given** a rehearsal candidate, 11.14's fixture gates, 11.15's fresh-pass fixture and a host, **when** the author runs the sequence, **then**:
  - it asks before the push and pushes `rehearsal/1.0.0-rc1` on `yes`;
  - every gate step runs and writes its row;
  - `hands-on` stops (exit 4), `resume` is refused (exit 2) until the fixture pass is in the record, and then passes;
  - `pr`, `merge`, `tag` and `mergeback` are declined (`SKIP`, and the sequence goes on);
  - `demo` copies a bundle of `refs/heads/rehearsal/1.0.0-rc1` at the cut SHA, and the host builds from it;
  - the record holds the cut SHA, each gate's result, the `demo` row and `Hands-on time:` equal to the sum of the ASK windows;
  - `Result:` is the rehearsal text, never a release.
  - Hermetic with the fake host; `(once)` live with the stand-in (`--live-demo rehearsal`), where the stand-in's running version afterwards is 1.0.0.
- **AC9 (no carry-over; REL-7):** **Given** the rehearsal's passed record, **when** a real candidate's carry-over names it, or `start --from rehearsal/1.0.0-rc1` runs in release mode, **then** both are refused as in the Matrix.
- **AC10 (nothing goes out in a rehearsal; REL-11):** **Given** `yes` at `pr`, `merge`, `tag` or `mergeback` in a rehearsal, **when** the step runs, **then** it prints its rehearsal `FAIL`, exits 1, the `gh` shim logs no call for it, the bare remote is unchanged, and the next `next` asks again. After a full rehearsal, the pre-receive log holds only `rehearsal/1.0.0-rc1` and the integration branch's record commits.
- **AC11 (separate hands-on sums):** **Given** a rehearsal record of 1.0.0 beside a real `rc1.md`, **when** the real candidate's record is written, **then** its version sum excludes the rehearsal's windows, and the rehearsal's own sum covers only rehearsal records.
- **AC12 (static):** **Given** `release/demo-update.sh`, the stand-in and `lib-release.sh`, **when** the self-test scans them, **then**:
  - they are ASCII, mode 100755 (the scripts), and the hook sets `umask 077`;
  - there is no `docker push|login|save|export|pull`, `printenv`, `set -x` or `declare -p`;
  - the hook has no direct `ssh`, `scp` or `git push`, and the stand-in builds only with `--pull=false`;
  - a planted line in a copy fails each scan with `file:line`.
- **IA1 (consumes 11.16's real `demo` step):** **Given** the real `release.sh` at `demo` with the real hook and the fake host, **when** `yes` is answered, **then**, for each of `updated`, `scheduled`, `not updated` and `fail`:
  - the row is the matching 11.16 row (the stand-in rows in rehearsal), and `scheduled` carries `<at>`;
  - a release-mode stand-in update gives `not updated`;
  - the end `Result:` names the outcome.
- **IA2 (consumes 11.15's real gate):** **Given** a `Mode: rehearsal` record at `hands-on`, **when** AC8's stop, `resume` refusal and resume run, **then** they come from 11.15's real `step_hands_on` (its stop and refusal lines), and **when** AC9's carry-over is judged, **then** 11.15's real carry-over check gives its rehearsal line.
- **IA3 (consumes 11.14's real gate steps):** **Given** 11.14's fixture driver on a rehearsal candidate, **when** the gate steps run, **then** each row comes from 11.14's real step, and the `ci` gate's logged `gh` calls name `--branch rehearsal/1.0.0-rc1` and never `release/`.
- **IA4 (consumes 11.4's real `no-outward` row):** **Given** the tree with this story's files, **when** the real row runs, **then** it passes.
- **IA5 (drift pin with Epic 29):** **Given** `release/demo-host-check.sh`, **when** the self-test extracts its seven-key list, **then** it equals `demo_status_judge`'s.
- **Standing:** **Given** a fresh environment, **when** the tests added or changed run in either order, **then** every one passes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- **AD-25:** the hook's interface (a bundle over SSH, `update`, then `status`; the two results; one line on a non-zero exit; the notes line; no host means say so), and the update's golden-copy order and version exemption, which the stand-in follows.
- **AD-19:** configuration outside the repository, and no value printed.
- **AD-22:** throwaways only, and no registry (the stand-in builds from the local base image).
- **AD-23:** the image's version comes from `src/module.xml` in the bundle.
- **AD-29:** `release/` is Lane A's. The step epics' gate keys on `release/1.0.0-rc1`, which a rehearsal never creates.
- No criterion contradicts an AD.

**U-203 amendment for epics.md (the lead mirrors it into Story 11.18's block):**
> [AMENDED 2026-11-01, U-203 (veto, kept)] Rehearsal candidates are always named `rehearsal/<v>-rc<n>`, never `release/*`. A rehearsal branch never goes to origin, because the repository is public: the rehearsal works on a local bare remote only, the sequence's rehearsal mode refuses a `release/*` name (a test pins the refusal), and the script's header and usage say that a rehearsal branch accidentally pushed to origin is deleted when the rehearsal ends. The rc1 merge gate (`git ls-remote --heads origin release/1.0.0-rc1`) is unchanged, and no dependency statement changes.

**The host side of the contract (written into the hook's header).** The bundle is at `ocutalon-demo/bundles/ocutalon-<v>.bundle` in the login folder. It holds exactly one ref, and the host builds that ref's commit after checking that its `src/module.xml` reads `<v>`. AD-25 leaves the location open, so this is decided here, and the Contest Planner applies it to the real host's command (Epic 29's checklist row H19).

**The stand-in's model.** The image, the volumes and the golden-copy moves are real Docker objects. Only IRIS's in-place upgrade is modelled, by the version marker copy. The upgrade itself is 11.2's harness's proof on IRIS, and the real host's update is H19, the Planner's check on the host.

**Decided in-stage (unattended block: small, reversible, in intent):**
1. **Not split.** 11.5's line has used 5 of its 6 split children. The stand-in and the rehearsal could be split (the second criterion to an 11.19), but the rehearsal is the stand-in's only end-to-end consumer, and U-203 must sit in this story's criteria. So a split is avoidable, and it is not made.
2. **The rehearsal's gates are 11.14's fixture gates.** A real gate cannot pass on a throwaway (a dry run never passes). The gate steps, the hands-on gate, the declines, the hook and the stand-in are real. Epic 38 runs the real gates.
3. **On a local bare remote the `ci` gate reads runs through 11.14's `OCUTALON_RELEASE_GH_REPO` seam.** In this build that is always the `gh` shim. A rehearsal without the seam fails `ci` (no false pass).
4. **`yes` to an outward step in a rehearsal fails and sends nothing,** which is stricter than the criterion's decline, and never looser.
5. **`DEMO_STANDIN=yes` marks a stand-in.** A rehearsal needs it, and a release-mode `demo` row never calls a stand-in update "updated". So a rehearsal can never touch the real online demo.
6. **No polling (no exit 5).** The update blocks until ready, as AD-25 says. The author's terminal has no 10-minute cap, and the stand-in's update takes seconds (Task 0).
7. **The status checks add `access`** (`restricted` with `updated`, `public` with `scheduled`), so a host that contradicts its own answer fails.
8. **Rehearsal records live beside real ones under other names** (`rehearsal-rc<n>.md`), so no real path, sum or rc number sees them.

**Fixed texts (new public-facing text for the lead to rule, veto window; product default 3).** None names a host, rival entry or entrant, says "IRIS Couch", or names OpenClaw.

Hook lines:
- `PASS demo-update bundle ocutalon-<v>.bundle <bytes> bytes, <ref> at <short sha>`
- `PASS demo-update update <the host's JSON>`
- `PASS demo-update status running <r>, golden <g>, pending <p>, access <a>`
- `HOST stand-in`
- `SKIP demo-update no demo host is configured; the online demo was not updated`
- `SCHEDULED <at>`

FAIL reasons:
- `could not reach the demo host (ssh exit 255)`
- `the demo host did not update: <its line>`
- `the demo host's answer is not one of the two results`
- `the demo host's status <field> is <value>, not <expected>`
- `the demo host's status does not have AD-25's keys`
- `<rule> (configuration)`, from `release_config_read`
- `--ref <ref> does not match Mode: <mode>`
- `v<v> is on <short>, not the candidate <short>`
- `a rehearsal updates only a stand-in demo host (DEMO_STANDIN=yes)`
- `the draft notes do not exist`
- `the record has no Release sequence section`

Record section (golden):
```
## Online demo update
Result: updated
Mode: release
Candidate: 1.0.0 rc1 at <40-hex>
Host: the configured demo host
Bundle: refs/tags/v1.0.0 at <40-hex>, <bytes> bytes
Update: {"result":"updated","version":"1.0.0"}
Status: running 1.0.0, golden 1.0.0, pending null, access restricted, next reset <ISO>
Run: <ISO> to <ISO>
```
- `Host:` is one of `the configured demo host`, `a stand-in demo host (not the online demo)` or `none configured`.
- A failure adds `Reason: <reason>`.

Notes section, titled `## Online demo update`, one line:
- `The online demo now runs OcuTalon <v>.`
- `The online demo updates to OcuTalon <v> at its next scheduled reset, <at>.`
- `The online demo was not updated with this release.` (no host, and every failure)
- `The online demo was not updated: a stand-in demo host was updated instead (rehearsal).` (any stand-in update)

`release.sh` texts:
- `REFUSED a rehearsal never uses a release/* branch: <name>; rehearsal candidates are rehearsal/<v>-rc<n> (U-203)`
- `REFUSED a rehearsal runs only against local bare repositories; remote <name> is not one`
- `REFUSED a rehearsal candidate is cut from the integration branch; --from is not taken`
- `REFUSED a release candidate is never cut from a rehearsal candidate`
- `FAIL <step> a rehearsal never opens the release pull request, merges, tags or merges back; nothing went out`
- `ASK demo Update the stand-in demo host to <v> (rehearsal)? [yes/no]`
- Rows:
  - `demo | updated | the stand-in demo host runs <v> (rehearsal); the online demo was not updated`
  - `demo | scheduled | the stand-in demo host updates to <v> at <at> (rehearsal)`
  - `demo | not updated | a stand-in demo host was updated, not the online demo` (release mode)
- End: `Result: rehearsal ended: every step ran on rehearsal/<v>-rc<n> at <short> (not a release); pr <o>, merge <o>, tag <o>, mergeback <o>, demo <o>`
- Header and usage, U-203:
  - "A rehearsal (`--rehearsal`) cuts `rehearsal/<v>-rc<n>`, never a `release/*` branch, and works only against local bare repositories; it never goes to origin."
  - "If a rehearsal branch is ever pushed to origin by accident, it is deleted from origin when the rehearsal ends."

Stand-in lines (test infrastructure in the public tree): `the bundle for <v> is missing`, `the bundle holds <n> refs, not one`, `the bundle's src/module.xml reads <x>, not <v>`, `the base image is not on this host`, `the image for <v> did not build`, `the golden copy holds <g>, not the running version <p>`, `the upgraded copy reports <x>, not <v>`, `the instance was not ready within <s> s`, `reset refused: the golden copy holds <g>, but the image is <i>`.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Consumes:**
  - 11.16's `demo` step and call contract (IA1, real);
  - 11.15's hands-on gate and carry-over check (IA2, real);
  - 11.14's gate steps, `record_field`, `candidate_clone` and the `OCUTALON_RELEASE_GH_REPO` seam (IA3, real; the gates' scripts are fixtures);
  - 11.5's cut, push, ASK, stop routine and state;
  - 11.4's `no-outward` row (IA4, real);
  - 11.3's `release_config_read`, `host_run` and `record_write`;
  - 11.13's draft notes;
  - Epic 29's status rules (IA5, pinned).
- **Consumed-by:**
  - **11.16's `demo` step**, through the contract;
  - **Epic 38 (38.1 to 38.3):** the real 1.0.0 update of the online demo, through the proved sequence;
  - **Epic 29's H19:** the Planner checks the real host's `ocutalon-demo` against this contract and stand-in.

**Ledger inbox (Rule 17):** none (`LEDGER slice` is empty).

**Previous story continuity:** 11.11 (done). Its stub-ssh tests (`OCUTALON_REHEARSAL_SSH`, real-mode argv) are the precedent for this story's ssh shim. Nothing else is shared.

**Contended paths (U14):** none. The new files are in `release/`, and the changed files (`release/release.sh`, `release/lib-release.sh`, `docker/tests/test-release-sequence.sh`) are Epic 11's. Epic 29's files are only read. `ci/units.sh` is unchanged. No footprint extension.

**CI budget (inference):** the hosted `checks` job's `test-release-sequence.sh` grows by about 30 to 60 s. No IRIS group runs, because `release/` and `docker/tests/test-*.sh` are not IRIS inputs. The live parts never run in CI.

## Clarification Needed (non-blocking: this plan does not depend on the answers)

1. **The host-side contract** (the bundle path and the one-ref rule) adds detail to AD-25's "The release hook's interface". The recommendation is that the lead adds one sentence to AD-25 (veto window, an AD amendment), and the Contest Planner applies it to the real host's `ocutalon-demo` before Epic 38.
2. **`DEMO_STANDIN`**, a new configuration key, is a safety marker and holds no secret. It is listed under configuration handling for the veto window.
3. **The public texts above** are listed for the lead's veto ruling, and U-203's amendment is for the lead to mirror into epics.md.

## Verification

Run each command in its own foreground call, with `timeout: 600000`, from the worktree root. `release/release.sh` and the hook run only inside the self-test's throwaway.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh --cases demo`, then `--cases rehearsal`, then the other parts that 11.14 to 11.17 defined, one per call -- expected: exit 0; the throwaway is removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` `test-rehearsal.sh`, `test-upgrade-harness.sh`, `test-release-checklist.sh` and `test-release-notes.sh`, one per call -- expected: exit 0, with `lib-release.sh`'s defaults unchanged.
- `(once)` With the lane-A variables and their lock folder written as `"$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"`, `OCUTALON_LOCK_OWNER='epic=11 stage=<stage>'` and `OCUTALON_RUN_TAG=e11s18d`, run `bash docker/tests/test-release-sequence.sh --live-demo prepare`, then `hook`, then `rehearsal`, then `clean`, one per call (`clean` also after a failure). Expected:
  - AC6 and AC8's live lines pass;
  - afterwards `docker ps -a`, `docker volume ls` and `docker images` show nothing named `ocutalon-demostandin-e11s18d`.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash ci/changes.sh ci.yml` -- expected: exit 0, and no IRIS group for these paths.
- `(once)` `bash ci/checks.sh` in its parts, one per call -- expected: no `FAILED`.

**Mutations (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: bundle the integration head instead of the tag.
- AC2: skip the `pendingVersion` check.
- AC3: print `RESULT updated` on a non-zero `update`.
- AC4: call the host with no `DEMO_SSH`.
- AC5: echo `DEMO_SSH` in the PASS line.
- AC6: capture golden before the version check.
- AC7: let `candidate_branch` ignore the kind.
- AC8: skip the `resume` refusal for rehearsals.
- AC9: accept `Mode: rehearsal` as a carry-over source.
- AC10: let `yes` at `tag` push in a rehearsal.
- AC11: sum `rehearsal-rc*.md` into the real version total.
- AC12: drop `--pull=false`.
- IA1: map exit 3 to `updated`.
- IA5: drop `access` from the key list.

**Shared surfaces:**
- `lib-release.sh`'s function signatures (`release_config_read`, `host_run`, `record_path`, `notes_path`, `candidate_branch`, `next_rc`, `record_write`'s heading), sourced by the harness, the rehearsal, the checklist, the notes and their self-tests;
- `release.sh`'s state folder names, rows and `Result:` texts, which 11.5's and 11.14 to 11.17's pins read;
- the record's and the draft notes' `## ` sections;
- AD-25's status keys, shared with Epic 29's check.
- Every test added or changed passes on a fresh environment, in either order. Each part builds and removes its own repositories, bare remotes, shims, configuration, stand-in project, volumes and images.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
