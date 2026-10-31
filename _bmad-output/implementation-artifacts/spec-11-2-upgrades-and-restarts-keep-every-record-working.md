---
title: 'Story 11.2: Upgrades and restarts keep every record working'
type: 'feature'
created: '2026-10-31'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing proves that a new OcuTalon release installs over a running one, or survives a container restart, with every record still working (FR-6, FR-60, NFR-16, NFR-17, REL-6). `docker/tests/test-install-upgrade.sh` only bumps the version of the same tree. No script builds an older commit, seeds real records through the product, upgrades it in place and checks the records afterwards, and no release record holds such a result.

**Approach:** Add the upgrade harness, `release/upgrade-harness.sh`, a release gate that runs by hand and in Story 11.5's sequence. It is not a CI unit. It works only in throwaway compose projects with the CI override:
1. It builds the previous build's image from that commit's own tree on this machine.
2. Through the product's HTTP API and the CI mock, it seeds a conversation, an Orders watch, a pending approval from Break the feed and two reminders.
3. In a second project of the previous build, it switches demo mode off with `SetDemoMode(0)`.
4. It upgrades both projects in place to the candidate, then restarts the records project, checking every record after each.
5. It diffs storage against the previous build and writes pass or fail per record to `release/records/<version>/rc<n>.md`.

It runs in resumable phases, so that every call fits 10 minutes. A hermetic self-test of its logic joins `CHECK_SCRIPTS`. 1.0.0 has no previous release, so the previous side defaults to a pinned pre-release commit of the integration branch. The pairing family is built as an off hook for Story 12.7.

## Boundaries & Constraints

**Always:**
- **Throwaways only.**
  - Every stack is a `docker/tests/lib-live.sh` throwaway (`live_start`, the decoy key file, `compose.throwaway.yml`, `ci/compose.ci.yml` with the mock), named `ocutalon-upgset-<tag>-...` (the settings project) or `ocutalon-upgrade-<tag>-...` (the records project).
  - It never touches a slot, `ocutalon-aihub-test`, any `ocupilot*` container or `iris-community-edition`, and it makes no MCP call.
  - The two projects run one after the other, never at once: `settings` starts and removes its own project before `seed` starts the second.
- **The lane lock.**
  - The records project holds the lane's `throwaway-iris.lock` from `seed` until `down`, across calls.
  - A later phase checks that the lock file still holds the content it saved, and never claims it again.
  - `down` removes the tag's projects (`cmd_teardown` of `ci/iris.sh`), releases the lock only when its content is the harness's, and deletes the state folder.
- **The previous build** is a commit's tree, exported with `git archive <sha>` into the state folder (no worktree, Rule 10).
  - When the tree has no `src/ocutalon/csp/index.html`, its web bundle is built from its own `web/` with `npm --prefix <tree>/web ci` and `run build`.
  - Its image is built from that tree's own Dockerfile through a `build.context` override, on top of the candidate's compose files.
  - When its manifest version equals the candidate's, its copy of `src/module.xml` is stamped `<version>-pre.1` (Task 0, Design Notes).
- **The candidate** is this checkout: its `HEAD` sha, its manifest version and its working tree, which the image builds from.
  - `--version`, when given, must equal `manifest_version src/module.xml`.
  - The candidate's web bundle is ensured (`ensure_web_bundle`) and never rebuilt. Story 11.5 commits it on the rc branch.
- **The previous ref:**
  1. `--previous <ref>`;
  2. else the highest `v*` tag merged into `HEAD`, not on `HEAD` and not `v<candidate version>`, sorted with `versionsort.suffix=-`;
  3. else the pinned pre-release commit `c9f1288c7a735f1ee3aa14a4f5289de794ce5257` (the integration branch at Epic 11's start).

  The resolved commit must be an ancestor of `HEAD` and must not be `HEAD` itself, or the harness exits 2. Case 3 adds the record note that 1.0.0 has no previous release.
- **Records go through the product's own surfaces.**
  - Sign-in is the README account's form (`online_signin` of `lib-online.sh`).
  - Turns, Break the feed and the approval answer use `POST /ocutalon/api/v1/messages`, `/v1/demo/break-feed` and `/v1/approvals/:ref/answer`, with `Content-Type: application/json`, `X-OcuTalon-Request: 1` and `Origin`.
  - Reads use `GET /v1/state` with a unique `probe` query. The settings change is the admin's terminal command `##class(OcuTalon.Core.Admin).SetDemoMode(0)`.
  - IRIS sessions are used only to:
    - point the runners' keys at the mock after every start (`keys_point`);
    - write the probes;
    - cross-check that waiters live (`Bridge.Approval.LiveHold`, `Test.Schedule.ReminderFixture.WaitingCount`);
    - read the installed version, readiness, the demo.mode row and what OCUORDERS owned (`check_installed`, `check_demo_off`);
    - read the storage dictionary and run `PrivateData.Run()`.
- **The mock decides every reply** (AD-22).
  - Markers carry a per-run key (`[[mock:<name>:<key>]]`).
  - Lane A adds only the two reminder scenarios under `ci/mock/scenarios/A/`.
  - `ANTHROPIC_API_KEY` is never read or needed.
- **Every check prints one `PASS` or `FAIL` line and appends `RECORD <name> pass|fail|off <detail>` to the run's results.**
  - The record holds a row per record name. A row is `pass` only when every line for it passed, `fail` when any failed, and `not run` when none was written.
  - `Result: pass` needs every enabled row to pass. Otherwise the result is `fail` and the run exits 1.
- **Nothing prints an environment value or a password.**
  - `docker compose config` runs only with `--quiet`, and `docker inspect` only with `--format`.
  - There is no `docker push`, `save`, `export` or `login`, and nothing is written to the main checkout.
- **Text.** Code is ASCII, and its comments state the contract (Rule 14). The record and its details are plain ASCII text.

**Never:**
- **Contended or another story's files.** Change `docker/tests/lib-live.sh`, `docker/tests/lib-online.sh`, `ci/iris.sh` or `ci/warm.sh`.
  - Change no file that Epics 15, 30, 12 or 13 change: `release/ipm-install.sh`, `release/ipm/*`, `src/module.xml`, `src/cpf/ocutalon.cpf`, the Install classes of Epic 15, `release/standalone-bridge.sh`, `docker/tests/test-production-restart.sh`, and every file in `contended-epic-11.txt`.
  - Change no group line, `NO_WEB_BUNDLE_UNITS` or layout comment of `ci/units.sh` (Story 11.7's and Epic 12's). Its `CHECK_SCRIPTS` line is the one line this story touches.
  - Change no other file or line that Stories 11.7 or 11.9 plan to change. Story 11.7 changes the `install-fresh` and `image` lines of `ci/units.sh` and its layout comment, and reads `release/demo-load.sh`.
- **No new CI unit and no product class.** The harness is no `live:` unit, and no class under `src/` changes. A mutation is applied only for a run and then reverted.
- **No committed record from a stage run.** Implement, QA and review runs pass `--record "${TMPDIR:-/tmp}/<tag>-record.md"`.
- **No real model and no outward action.** Turn on no pairing check (Story 12.7). Change no AD.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Previous: explicit | `--previous HEAD~1` | Kind `explicit`, that sha; the record names the ref and sha | Unknown ref, not an ancestor of HEAD, or HEAD itself: exit 2 with one line, nothing started |
| Previous: a release tag | `v1.0.0` merged into HEAD, candidate 1.0.1 | Kind `tag`, `v1.0.0`; `Required: yes` | A tag on HEAD, `v<candidate>`, or a higher tag on an unmerged branch is not taken |
| Previous: no tag (1.0.0) | No `v*` tag merged | Kind `pre-release`, the pinned commit; `Required: no`; the note "1.0.0 is the first release: it has no previous release, so the previous side is a pre-release build of the integration branch (<sha>), which proves the harness itself." | Pinned commit not in the repository or not an ancestor: exit 2 |
| Version stamp | Previous and candidate both 0.1.0 | The previous image is built as `0.1.0-pre.1`; the upgrade log reads `STEP package loaded (version 0.1.0-pre.1 to 0.1.0)` | Versions differ: no stamp |
| Mode | Clean tree; `--rehearsal`; tracked changes; `plan` | `release`; `rehearsal`; `rehearsal (uncommitted changes)`; `dry run` | No error expected |
| Dry run | `plan --rc 1 --record <f>` | Prints the plan (refs, shas, versions, stamp, phases, record path), starts no container, writes the section with every row `not run`, `Result: not run`, `Mode: dry run`; exit 0 | No error expected |
| Phase order | `upgrade` before `seed` is done; a phase with no state or no tag | One refusal line; exit 2 | No error expected |
| Settings (project 2) | Previous build; `SetDemoMode(0)` answers `off`; then the upgrade | demo.mode `Value` 0 with the same `UpdatedAt` as after the switch; `check_demo_off` passes; `/state` `demoMode` false; break-feed 404; the `demo-switch` Playwright project passes with `OCUTALON_E2E_DEMO_MODE=0` | Any check fails: its FAIL line and the `settings` row fails |
| Seed (project 1) | Previous build, ready, keys pointed | Turns in this order: the watch (`watch-start-orders`); Break the feed, giving an incident awaiting approval with one pending request (ref and `expiresAt` kept); `upgrade-reminder-later` (R2, a day ahead); `upgrade-reminder` (R1, 300 s); `recall-tell` with the fact "my build server is called ORION-7 (zz<key>)", answered "Noted.". Also the probes and the storage snapshot | A seed step fails: FAIL in its record's row, and that record's later checks are skipped |
| Upgrade | The candidate on the same volume | `check_log` against `expected_run` with `loaded (version <prev> to <cand>)`; `check_installed <cand>`; `STEP Reconcile OK` with no `WARN Reconcile` naming a seeded ref; `LiveHold(ref)` set; R2 `WaitingCount` 1; R1 waiting or already fired | Not ready within 400 s: FAIL with the last log lines; every later row `not run` |
| Conversation | After the upgrade, `recall-ask` | Every seeded turn is in `/state` with its reply. The new turn is done with "Your build server is called ORION-7.", and the turn's first ChatAgent request in the mock log (after the mark) carries `zz<key>` | The request lacks the fact, or the reply differs: FAIL |
| Reminder R1 | Due 300 s after it was set | It leaves `rail.reminders`; a chat notification of kind `reminder` appears. Due more than 20 s before the candidate's ready: "Reminder (late; ..." required. More than 20 s after: "Reminder: check the upgrade." required. Within 20 s: either, and the record says which | Not fired by its due time + 90 s: FAIL; it fired before the upgrade began: FAIL "the phases ran too far apart" |
| Approval | The pending request | Still in `rail.approvals` with the original `expiresAt`. Approve on `channel: phone`, answered 200, then: the result `{total 50, completed 50, failedAgain 0}`, the incident `resolved`, a phone item "All 50 orders went through." | Any differs, or nothing within 120 s: FAIL |
| Watch | After the approval | `rail.checks` lists the Orders production. A new press answers 200, and within 180 s a new incident (another ref) awaits approval with a new pending request (ref2) | 409 `not_watching`, or no new incident: FAIL |
| Restart | `dc restart iris`, ready with the candidate's marker, keys pointed | `recall-ask` after a mark: done with the scenario's answer, and its first ChatAgent request carries `zz<key>`. Every earlier turn is in `/state`. Orders is still listed. R2 is pending with the same `dueAt` and `WaitingCount` 1. ref2 is pending with the same `expiresAt` and `LiveHold` set | Any fails: FAIL in the `restart` row |
| Storage | The prev and candidate snapshots; the previous sha | Every line of the previous snapshot (class, data node, slot, property, type, collection) is in the candidate's, and `OCUTALON_STORAGE_BASE=<sha> bash docker/tests/test-storage.sh` prints `PASS release-diff` | A renamed, retyped or removed property, or a moved slot: FAIL naming it |
| Private globals | After the upgrade | `check_probes` (written under the previous build) and `PrivateData.Run()` OK | FAIL naming the offender |
| Record file | An existing file with other `## ` sections | Only the `## Upgrade harness` section is replaced, or appended when missing. A missing file is created with `# OcuTalon <version> rc<n>` | No error expected |
| Pairing | Any run | The row reads pairing, off, "joins from the release after 1.0.0 (Story 12.7)"; it is not counted against `Result` | No error expected |

</intent-contract>

## Code Map

Paths are from the epic-11 worktree root. `C/` is `src/ocutalon/cls/OcuTalon/` and `B/` is `src/bridge/cls/OcuTalon/Bridge/`.

**Siblings to source or extend (Rule 2)**
- `ci/iris.sh`, sourced, defines functions only (`:571-572`):
  - `setup_tag` :54, `preflight` :96, `stack_start` :250, `stack_ready` :258, `warm_state_dir` :513;
  - `cmd_teardown` :534, which removes only the tag's projects and never `throwaway-iris.lock`;
  - it sources `ci/units.sh` and `lib-live.sh` :45-46.
  - The release-side precedent of sourcing it is `release/standalone-bridge.sh:30-41`.
- `ci/warm.sh:140-170` (`warm_up`) is the pattern for a stack that outlives its call: copy the decoy env and every compose override into a state folder, rewrite `LIVE_FILES` to those copies, save `P`, the files and the time, then `trap - EXIT INT TERM HUP` and remove `$tmp`. `warm_attach` :198-221 is the pattern for the later calls.
- `docker/tests/lib-live.sh` (read only):
  - `live_start` :58-89 sets `P`, `tmp`, `deadline`, `LIVE_FILES` and the lock, and installs the trap;
  - `live_lock_claim` and `live_lock_release` :111-149 (`LIVE_LOCK_FILE`, `LIVE_LOCK_CONTENT`);
  - `live_add_file` :152, `ensure_web_bundle` :160, `live_web_port` :202 (uses `OCUTALON_TEST_WEB_PORT`), `dc` :244, `live_track_image` :252;
  - `pass`, `fail`, `die` :274-283; `wait_until` :287; `iris_script` :311; `marker` :346; `start_log` :350; `wait_started_ready` :377;
  - `check_session` :485, `session_value` :493;
  - `set_probes` and `check_probes` :548-579 (the probe values carry `$P`, so `P` must be the same across phases);
  - `manifest_version` :587, `log_steps` :590, `expected_run` :595, `check_log` :604, `live_pop_file` :616;
  - `check_demo_off` :878.
- `docker/tests/lib-online.sh` (read only, sourceable):
  - `next_probe` :80 (needs `probe_file`), `logout_all` :86;
  - `online_signin <jar> "" "" ocutalon ocutalon` :97-115 (needs `base` and `probe_file`);
  - `keys_point` :120-124 (`Test.Agent.RunnerFixture.PointKeys`, then `WaitRecords`; the Provider step resets the keys at every start).
- `docker/tests/test-install-upgrade.sh`:
  - `make_image_context` :33-52, whose :35-36 is the awk that stamps the first `<Version>`;
  - `use_image_context` :55-64 (the `build.context` override);
  - `recreate_with` :67-76 (`dc up -d --build`, then `live_track_image`, `cid`);
  - `check_installed` :79-96 (marker, `/opt/ocutalon/version`, the `%IPM` VersionString, readiness 1);
  - the upgrade's expected lines :194.
- `docker/tests/test-demo-switch.sh`:
  - `api_get` and `api_post` :63-69 (the envelope);
  - `e2e` :158-170 (the demo-switch Playwright project, with `OCUTALON_URL`, `OCUTALON_E2E_DEMO_MODE`, `OCUTALON_E2E_TIMEOUT_MS`);
  - `run_admin` :142-155 (`SetDemoMode` through `iris session ... -U OCUTALON`; `CHK|outcome|`).
- `release/demo-load.sh:420-538` (`poll_until`, `turn_done`, `drive_visitor`) is the HTTP precedent for watch, press, phone notice and approve. Epic 29's file, read only.
- `docker/tests/test-storage.sh`:
  - `release_diff` :316-346 picks the tag at :323-329;
  - its synthetic samples are :391-485;
  - the verdict on the real tree is :488-503.
- `eval/run.sh:250-258, 712-737`: the output style of a release gate (`REPORT`, `RESULT` lines).

**The product surfaces the harness drives (read only)**
- `C/Web/Api.cls`:
  - routes :126-138;
  - POST envelope checks :963-971;
  - `Messages` :245-298 (`{clientId, text}`, 202);
  - `BreakFeed` :340-365 (200 `{state:"sent"}`, 409 `not_watching` or `incident_in_progress`, 404 with demo mode off);
  - `AnswerApproval` :478-550 (`{action, channel}`);
  - `StateBody` :737-791 holds `demoMode` (:759), `chat[]` (`ChatItems` :829-878: `chat.message` payload `{clientId, state, text, replyText}`; `incident` payload `{ref, state, requests[{ref, state, result}]}`; `notification` payload `{kind, text, dueAt}`), `rail{approvals, checks, reminders, decisions}` (`RailBody` :882-898) and `phone[]`.
- `C/Core/Admin.cls:26-49` `SetDemoMode`. `C/Core/SettingsOps.cls` writes the row and runs the Demo step.
  - `C/Install/Step/Demo.cls:134-138` `Mode()` seeds the row only when it is missing (`C/Data/Setting.cls:57-64`).
- Reminders:
  - `C/Data/Reminder.cls` (`DueAt` :18, `State` :21, `Late` :24);
  - `C/Schedule/Reminder.cls` (`LATESECONDS` :28, `Reconcile` :217-249);
  - texts in `C/Msg/Catalog/Core.cls:252-265` ("Reminder: {text}." and "Reminder (late; it was due at {time}): {text}.");
  - `C/Install/Step/Schedule.cls:17-25`.
- Approvals:
  - `B/Data/ApprovalRequest.cls` (`ExpiresAt` :48, a 24 h expiry);
  - `B/Approval.cls` `LiveHold(ref)` :629 and `Reconcile` :653-694;
  - `C/Install/Step/Approvals.cls:8-11`.
- The result text: `C/Watch/IncidentManager.cls:1218-1228` and `C/Msg/Catalog/Watch.cls:151-157` `result.allThrough`, on `phone[]` only.
- `C/Demo/BreakFeedIn.cls:6-13` closes the session's resolved incident before a replay.
- `C/Core/Conversation.cls`:
  - :11-14: a turn sends Decide two requests, Kind decide (Triage) first and then Kind turn. Neither request message carries another turn's text, so the model request's history comes from the AI session (`continue`) or from the recap (`fresh`);
  - `Ask` :400-416: `continue`, or `fresh` with the `Recap` when the last replied turn was Tainted (`RECAPTURNS` 20);
  - so the fact turn is seeded last.
- `C/Install/Step/PrivateData.cls:18` `Run()`. `C/Install/Step/Reconcile.cls` prints only `STEP Reconcile OK`, plus Lane B's `WARN Reconcile the reminder <ref> has no session ...`.
- `docker/after-start.cos`: the version gate (`inst'=img`) loads whenever the versions differ.
- Fixtures, present at the pinned commit and at HEAD:
  - `C/Test/Agent/RunnerFixture.cls` `PointKeys` :456;
  - `C/Test/Schedule/ReminderFixture.cls` `WaitingCount` :197.
- `web/e2e/demo-switch/badge.spec.ts:12-49`, run by `npm --prefix web run e2e:demo-switch`, needs Chromium (`npx --prefix web playwright install chromium`).

**The mock**
- `ci/mock/mock.mjs`:
  - the selection rule :24-37;
  - the log line :649-666: `marker`, `selectedBy`, `step`, and `request`, which keeps `messages` whole and reduces `tools` to names;
  - redaction :236-241.
- The iris container reads the log at `/opt/ocutalon/mock-log/requests.jsonl`.
- Scenarios used as they are:
  - `A/watch-start-orders.json`;
  - `A/recall-tell.json` ("Noted.");
  - `A/recall-ask.json` ("Your build server is called ORION-7.");
  - `A/diagnosis.json`, through the mock key.
- `A/reminder-set-relative.json` is the shape of the two new files.
- `ci/mock/test/scenarios.test.mjs` counts the committed scenarios dynamically, so no pin changes.

**Record and checks wiring**
- `ci/units.sh:6`: `CHECK_SCRIPTS`. Epics 13 and 15 append to the same line, which is a plain union at integrate-forward.
- `ci/checks.sh` runs each name as `docker/tests/test-<name>.sh`.
- `docker/tests/test-ci-config.sh:27, 633-648` requires every `docker/tests/test-*.sh` to be in exactly one list.
- `ci/units.sh:144` `NOT_IRIS_INPUT_PATTERN` already holds `release/` and `docker/tests/test-*.sh`. The new `docker/tests/lib-upgrade.sh` matches `IRIS_INPUT` (`docker/tests/lib-[^/]+\.sh$`).
- `release/records/` does not exist yet. Epic 38's footprint names `release/records/1.0.0/**`.

## Tasks & Acceptance

**Execution:**
- `docker/tests/lib-upgrade.sh` -- new.
  - It holds `check_installed <label> <version>`, moved word for word from `test-install-upgrade.sh:79-96`.
  - It holds `stamp_version <manifest> <version>`, which prints the manifest with its first `<Version>` replaced (the awk of :35-36).
  - Its header says it is shared by the in-place upgrade test and the release upgrade harness, and needs `lib-live.sh` sourced first.
  - Rule 2: one home for both callers.
- `docker/tests/test-install-upgrade.sh` -- source `lib-upgrade.sh` after `lib-live.sh`, delete its local `check_installed`, and use `stamp_version` in `make_image_context`. No behaviour change.
- `docker/tests/test-storage.sh` -- in `release_diff`, `OCUTALON_STORAGE_BASE=<commit>`, when set, replaces the tag choice.
  - It must resolve to a commit (`rev-parse --verify <x>^{commit}`), else the result is a `VIOLATION` naming it. The verdict line reads `PASS release-diff: the storage blocks only grew since <base>`.
  - Add two synthetic samples: a changed slot since the base is flagged with no tag present, and an appended slot is clean. Update the header.
  - Unset, every result is as today.
- `ci/mock/scenarios/A/upgrade-reminder.json` -- new, with marker `upgrade-reminder`:
  - reply 0 is `toolUse` `set_reminder` `{"text":"check the upgrade","delaySeconds":300}`;
  - reply 1 is the text "The CI mock set the reminder for after the upgrade.".
- `ci/mock/scenarios/A/upgrade-reminder-later.json` -- new, with marker `upgrade-reminder-later`:
  - reply 0 is `{"text":"review the upgrade notes","delaySeconds":86400}`;
  - reply 1 is the text "The CI mock set the reminder for tomorrow.".
- `release/upgrade-harness.sh` -- new. It sources `ci/iris.sh`, then `docker/tests/lib-online.sh` and `docker/tests/lib-upgrade.sh`, and runs its main only when executed (`[ "${BASH_SOURCE[0]}" != "$0" ] && return 0`). The usage is the header:
  - **Commands** take the form `release/upgrade-harness.sh <command> [--version <v>] [--rc <n>] [--previous <ref>] [--rehearsal] [--record <file>]`:
    - `plan` (the dry run);
    - `run` (every phase in order, then `report`, then always `down`);
    - one phase per call: `build`, `settings`, `seed`, `upgrade`, `restart`, `storage`, `report`, `down`.

    Options are taken by `plan`, `run` and `build` only, and stored in the state. `--rc` is a positive whole number, required unless `--record` is given. Phase commands need `OCUTALON_RUN_TAG`; `run` defaults it to `upg-<epoch>`. `run` runs each phase as its own process (`bash release/upgrade-harness.sh <phase>`), as `ci/iris.sh group` runs its units, so that each `live_start` has its own trap.
  - **State.** The folder is `${TMPDIR:-/tmp}/ocutalon-upgrade-<tag>/`. It holds:
    - `options` (`key=value`: version, rc, mode, record, previous kind, ref, sha and version, stamp, candidate sha, dirty);
    - `previous/`, the exported tree;
    - `p1/` (project, compose file copies, lock file and content);
    - `results`, the RECORD lines;
    - `phase.<name>`, holding `done <s>` or `failed <s>`;
    - `seed.env` (key, fact token, client ids, approval and incident refs and `expiresAt`, R1 and R2 refs and `dueAt`);
    - `upgrade.env` (ready epoch, ref2, `expiresAt2`);
    - `storage.prev` and `storage.cand`.
  - **Order.**
    - `settings`, `seed` and `report` need `build` done. `upgrade` needs `seed` done, and `restart` and `storage` need `upgrade` done. `down` may always run.
    - Any other order exits 2 (`phase_ready`).
    - Each phase sets `deadline` from `OCUTALON_LIVE_DEADLINE` (default 540) and prints `PHASE <name> done <s>s (<n> failed)`.
    - Every phase that starts a stack calls `preflight` first.
  - **Rows**, in record order:
    - `previous build`: the export, the stamp, the bundle, and both previous starts reaching ready with the previous version;
    - `upgrade`: AC2's checks, in both projects;
    - `conversation`, `reminder`, `approval`, `watch`, `settings`: each record's seed and its checks after the upgrade;
    - `restart`, `storage`, `private globals`;
    - `pairing`: `off`, never counted.

    A seed step that fails writes `fail` to its record's row.
  - **`build`:**
    - resolve the options (`resolve_previous`, `stamp_for`, `mode_for`). The tree is dirty when `git status --porcelain --untracked-files=no` prints anything;
    - `git archive <sha> | tar -x` into `previous/`;
    - stamp its manifest when `stamp_for` says so;
    - build its bundle when it is missing.
  - **`settings`:**
    - `live_start upgset` and `live_web_port`; add a `build.context` override for `previous/`; `dc up -d --build`; `wait_started_ready 400`; `check_installed <prev>`;
    - run `SetDemoMode(0)` through `iris_script OCUTALON` and require the outcome `off`; save the demo.mode `Value|UpdatedAt`;
    - `live_pop_file` the context and `dc up -d --build` the candidate; `wait_started_ready 400`; `check_installed <cand>`;
    - then the checks of the Settings matrix row: the row is unchanged, `check_demo_off`, `/state` `demoMode` false, break-feed 404, and the Playwright project in mode 0 after `npx --prefix web playwright install chromium`.
    - The project ends with the phase.
  - **`seed`:**
    - `live_start upgrade`, `live_web_port`, then the `previous/` context override, which is the last compose file, so that `upgrade` drops it with `live_pop_file`;
    - the previous build up and ready; `check_installed <prev>`; `keys_point` = 1; `set_probes`;
    - sign in, then the five steps of the Seed matrix row in its order (watch, press, R2, R1, fact). Each turn is waited to `done` within 120 s, and the press to its pending request within 180 s;
    - the storage snapshot to `storage.prev`;
    - save the state as `warm_up` does and drop the trap.
    - A `die` before the save tears the project down through `live_cleanup`.
  - **`upgrade`, `restart`:**
    - attach:
      - load `p1/`;
      - when a lock was taken, require that the lock file still holds the saved content (with no lock folder, as in CI, there is none);
      - `trap 'rm -rf "$tmp"' EXIT` only;
    - run the matrix rows;
    - `upgrade` records its start time first: an R1 `dueAt` before it is the "phases ran too far apart" FAIL. It then `live_pop_file`s the context, runs `dc up -d --build`, and writes `storage.cand`;
    - `restart` is `dc restart iris`, then `wait_started_ready 300`, the marker equal to the candidate's version, and `keys_point`.
  - **`storage`:** `storage_compare storage.prev storage.cand`, then `OCUTALON_STORAGE_BASE=<previous sha> bash docker/tests/test-storage.sh`, reading its `release-diff` line.
  - **`report`:**
    - `record_section` and `record_write` to `--record`, or to `release/records/<version>/rc<n>.md`;
    - the section has the shape in Design Notes;
    - `Required: yes` when the previous is a `v*` tag (resolved or given), else `no`;
    - prints `RECORD <file>` and `RESULT pass|fail|not run`;
    - exit 1 unless the result is pass (0 for a dry run).
  - **`down`:**
    - `cmd_teardown` for the tag;
    - set `LIVE_LOCK_FILE` and `LIVE_LOCK_CONTENT` from `p1/`, then `live_lock_release`;
    - `rm -rf` the state folder;
    - prints `TEARDOWN`.
  - **Pure functions**, each taking its inputs as arguments:
    - `resolve_previous <repo> <candidate version> [<ref>]` prints `kind<TAB>ref<TAB>sha`. The pinned sha is the variable `UPGRADE_PRE_RELEASE_COMMIT`;
    - `stamp_for`, `mode_for`, `phase_ready <state> <phase>`;
    - `reminder_expect <due epoch> <ready epoch>` prints `late`, `on-time` or `either` (±20 s);
    - `state_turn <state.json> <clientId>` prints `state|replyText`;
    - `state_pending_approval`, `state_reminder_card`, `state_checks_orders`, `state_new_incident`;
    - `chat_request_carries <log> <mark> <marker> <text>` uses the first line after the mark with that `marker` and a non-empty `request.tools`; its message texts (string or text blocks) must contain the text;
    - `storage_compare <before> <after>`;
    - `record_rows <results>`, `record_section <results> <options>`, `record_write <file> <section>`.

    Each JSON reader uses `jq`.
  - **The storage snapshot** is an `iris_script OCUTALON` over `%Dictionary.CompiledStorageDataValue`. For each class named `OcuTalon.*` it prints `CHK|slot|<class>|<data node>|<slot>|<property>|<Type>|<Collection>`, with the type from `%Dictionary.CompiledProperty` (empty when no such property), sorted.
  - **The pairing hook.**
    - `HARNESS_ON` is `"conversation reminder approval watch settings"` and `HARNESS_OFF` is `"pairing"`.
    - `seed_pairing`, `check_pairing_upgrade` and `check_pairing_restart` exist and only write `RECORD pairing off ...`.
    - Each phase calls a family's hooks only when the family is in `HARNESS_ON`.
- `docker/tests/test-upgrade-harness.sh` -- new. It is hermetic, and starts no container and no network call. It sources the harness and, on synthetic git repositories and files in its own temporary folder, pins:
  - `resolve_previous` (explicit, tag by version with a pre-release before its release, tag on HEAD skipped, unmerged tag skipped, `v<candidate>` skipped, no tag gives the pinned commit, a non-ancestor and HEAD refused);
  - `stamp_for` and `mode_for`;
  - `phase_ready` (each forbidden order);
  - `reminder_expect` at the two edges and inside the band;
  - the `state_*` readers on canned `/state` JSON;
  - `chat_request_carries` (carries; a Triage-only line; the fact only before the mark; text-block content);
  - `storage_compare` (appended is clean; renamed, retyped, removed and moved slots are flagged);
  - `record_section` and `record_write` (pass only with every enabled row passing; fail; not run; pairing off is not counted; each mode line; the pre-release note and `Required:`; another section kept; a section replaced, not duplicated).

  It also pins, on the real tree:
  - `plan --previous HEAD~1 --rc 1 --record <tmp>` exits 0 with a dry-run record;
  - `plan --version 9.9.9` exits 2;
  - a phase with no tag exits 2;
  - a static rule: the harness holds no `docker push|login|save|export`, no `compose config` without `--quiet` and no `inspect` without `--format`.

  Each rule first fails on a synthetic break (the `rule` pattern of `test-storage.sh`). One `PASS` or `FAIL` line per rule; exit 0 only when all pass.
- `ci/units.sh` -- append `upgrade-harness` to `CHECK_SCRIPTS`, and change nothing else.
- `(Task 0, measure on the first full run, once the harness above exists; recorded under Verification)`:
  - (a) the `build` phase's seconds for the pinned commit (export, `npm ci`, bundle build);
  - (b) that the previous image stamped `0.1.0-pre.1` reaches ready with that marker. If IPM refuses a pre-release version, `stamp_for` instead gives the candidate's version with its patch lowered by one, or, when the patch is 0, `<major>.<minor-1>.999`, or `<major-1>.999.999` when the minor is 0 too;
  - (c) the seconds from R1 being set to the candidate's ready. If they exceed 240 s, raise `delaySeconds` in `A/upgrade-reminder.json` to that plus 120 s, rounded up to the minute;
  - (d) in the mock log of the post-upgrade `recall-ask` turn, the requests in order (Triage without tools, then the ChatAgent's), whether the Triage request carries `zz<key>`, and whether the chat request continues the session (prior messages present). If the earlier conversation is carried only in a fresh recap outside `messages`, stop with a `## Clarification Needed`;
  - (e) whether `LiveHold(ref)` after the upgrade is the id from before (kept) or a new one (re-armed);
  - (f) every phase's seconds. If `settings` passes 480 s, split it into `settings` (start and switch) and `settings-upgrade` the way `seed` and `upgrade` are split.

**Acceptance Criteria:**
- **AC1 (setup; FR-60, CON-1, AD-22, AD-23).** Given the candidate checkout and the previous ref the harness resolves, when `build`, `settings` and `seed` run with a lane-A tag, then:
  - the previous image is built on this machine from `git archive` of that commit, stamped when the versions are equal, and never pulled or pushed;
  - both projects are throwaways with the CI override, and run one after the other;
  - the settings project switches demo mode off with `SetDemoMode(0)` before its own upgrade;
  - the records project reaches ready under the previous version and seeds the records of the Seed matrix row through the HTTP API and the mock, each with a PASS line;
  - the pairing family writes only its `off` row.
- **AC2 (upgrade; FR-60, NFR-17, AD-5, AD-23).** Given the seeded records project, when `upgrade` starts the candidate on the same volume, then:
  - its after-start log equals `expected_run "cleared" "present <ipm>" "already mapped" "ok" "loaded (version <prev> to <cand>)" "<cand>"`, so the order runs Bridge.Installer, Public, the other steps, Production, Reconcile, PrivateData and Ready;
  - `check_installed <cand>` passes;
  - no `WARN Reconcile` names a seeded ref;
  - every pending approval and reminder has a live waiter (`LiveHold`, `WaitingCount`).
- **AC3 (the records after the upgrade; FR-16, FR-60, NFR-16, NFR-17, AD-19).** Given the upgraded projects, when the harness checks each record, then the Conversation, Reminder R1, Approval, Watch and Settings rows of the matrix hold.
- **AC4 (restart; FR-6, NFR-16, AD-5).** Given the candidate running with the fact turn, R2 and ref2 pending, when `restart` restarts its container, then the Restart matrix row holds.
- **AC5 (storage and private globals; NFR-17, AD-5, AD-23).** Given the two storage snapshots and the previous sha, when `storage` runs (and after the upgrade, for the globals), then no previous slot line is missing or changed, the release-diff rule passes against `OCUTALON_STORAGE_BASE`, and `check_probes` and `PrivateData.Run()` pass.
- **AC6 (the record; FR-60, REL-6).** Given a run that ended (or failed in any phase), when `report` runs, then the record section holds:
  - `Result:`, `Mode:`, `Required:`, `Candidate:` (version and full sha), `Previous:` (kind, ref, full sha, version, stamp) and the pre-release note when it applies;
  - one row per record, with rows that were never reached as `not run` and pairing `off`.

  Any failure gives `Result: fail` and exit 1.
- **AC7 (the harness's own logic; Rule 19).** Given the self-test, when `bash docker/tests/test-upgrade-harness.sh` runs (also through `ci/checks.sh`), then every rule passes on the real harness and each fails on its synthetic break. No container starts.
- **AC8 (the storage rule's base).** Given `OCUTALON_STORAGE_BASE` set to a commit, when `test-storage.sh` runs, then `release-diff` judges against that commit and names it. Unset, every existing sample and the real-tree verdict are unchanged.
- **AC9 (no regression).** Given the moved `check_installed` and `stamp_version`, when `ci/iris.sh live install-upgrade` runs on a fresh stack, then it passes as before.
- **AC10 (ten-minute calls).** Given the developer machine, when the phases run one per call, then each ends within 540 s. Every phase's seconds and the full run's total are recorded under Verification.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**

| AD | What it governs here |
| --- | --- |
| AD-5 | State on the durable volume; append-only storage and the diff against the previous release; `ApprovalHold` and `ReminderTimer` re-armed from their rows |
| AD-23 | The after-start order, the version gate, the version checked inside the built image, and one image recipe for both builds |
| AD-22 | Throwaways with the CI override; markers and the mock log; Lane A adds only `A/` scenarios; no push; `compose config` only with `--quiet` and `inspect` only with `--format` |
| AD-19 | No key anywhere (the mock-key header is CI-only); the demo.mode row and `SetDemoMode` as the one run-time settings writer |
| AD-25 | The demo host's update is the same in-place upgrade. The harness touches no host and writes no host value |
| AD-11, AD-18 | The approval and reminder rows are the truth (expiry and due time read from them); the late mark |
| AD-12 | `/state` is the read surface |
| AD-3 | The private database |
| AD-29 | Epic 11 may change either lane's files; `release/` and `ci/mock/scenarios/A/` are Lane A's |

No AC contradicts an AD. The base variable extends AD-5's diff to a pre-release commit while CI is unchanged.

**Integration ACs and links (Rule 1/2).** No consumers in this story; the first consumer will be Story 11.5. Its sequence runs the harness as gate 3 and reads the record section. The section's lines are pinned by AC6 and AC7.

| Link | Who |
| --- | --- |
| Consumed-by | Story 11.5: gate 3, `release/upgrade-harness.sh run --version <v> --rc <n>`. It reads `Result:`, `Mode:` and `Required:`, and decides whether a `Required: no` failure blocks 1.0.0 |
| Consumed-by | Story 11.4: the notes generator reads the section's `Result:` and rows for "the upgrade result" |
| Consumed-by | Story 12.7: turns the pairing family on (moves `pairing` to `HARNESS_ON` and fills its three hooks) |
| Consumed-by | Epic 38: the 1.0.0 check runs Story 11.5's sequence |
| Consumes | `lib-live.sh`, `lib-online.sh`, `ci/iris.sh` (sourced), the new `lib-upgrade.sh`, and `test-storage.sh` with `OCUTALON_STORAGE_BASE` |
| Consumes | The product: the HTTP API, `Core.Admin.SetDemoMode`, the after-start script and `PrivateData.Run()`, the demo-switch Playwright project |
| Consumes | The CI mock and its log; the fixtures `RunnerFixture.PointKeys`, `ReminderFixture.WaitingCount` and `Bridge.Approval.LiveHold`, against real throwaways |

**The record section (the contract Stories 11.4 and 11.5 read).** Shown here for a pre-release run, indented by two spaces so that this spec's own section scan never reads it; in the record each line starts at column 1. The order is fixed.
```
  ## Upgrade harness

  Result: pass
  Mode: rehearsal (uncommitted changes)
  Required: no
  Candidate: 0.1.0 at <full sha>
  Previous: pre-release c9f1288c7a735f1ee3aa14a4f5289de794ce5257, version 0.1.0, built as 0.1.0-pre.1
  Note: 1.0.0 is the first release: it has no previous release, so the previous side is a pre-release build of the integration branch (c9f1288c7a735f1ee3aa14a4f5289de794ce5257), which proves the harness itself.
  Run: <UTC start> to <UTC end>, tag <tag>

  | Record | Result | Detail |
  | --- | --- | --- |
  | previous build | pass | ... |
  (one row per record, in the order of the Rows task; pairing last, as off)
```

**Extend, don't copy (Rule 2).**
- `check_installed` and the version stamp move into `docker/tests/lib-upgrade.sh`, used by both callers.
- The stack lifecycle reuses `lib-live.sh` and `ci/iris.sh`. The cross-call state follows `ci/warm.sh`'s pattern; its functions are warm-specific, so they cannot be called.
- Sign-in, probes and keys come from `lib-online.sh`. The only copies are `api_get` and `api_post` (about 4 lines in all, from `test-demo-switch.sh:63-69`, a script that runs at top level and cannot be sourced), with `next_probe` added to GETs.
- The storage diff reuses `test-storage.sh`'s rule through one variable. The one-line `v*` tag query in `resolve_previous` mirrors `test-storage.sh:325`, which is inside a script that runs at top level.

**Decided in-stage.**
1. **The previous ref.** The default is a `v*` tag when one exists. Otherwise it is the pinned `c9f1288c7a735f1ee3aa14a4f5289de794ce5257`:
   - It was the integration branch's head when Epic 11 started, with every release-1 record kind built (Epics 0 to 10, 16, 29 and 32 merged).
   - It lies on the feature branch's history, so every later candidate holds it.
   - It is the same for every run.
   - Its delta to today's head (27 class files at plan time, including a changed persistent class) gives the upgrade real code changes.

   A merge-base computed at run time would equal the candidate at Story 11.5's cut.
2. **The stamp.** The version gate loads whenever the versions differ. `-pre.1` sorts before the release under semver, and it lives only in a throwaway image. Task 0 (b) confirms it, and its fallback is fixed above.
3. **Compose files.** Both builds use the candidate's compose files and mock. The judges' file has not changed since Story 10.3, and the previous image is still built from the previous tree's own Dockerfile and sources.
4. **Phases.**
   - They run in this order: settings, seed, upgrade, restart. One lane, one throwaway at a time: the settings project is removed before the records project starts, and the records project keeps the lane's lock across calls.
   - The settings project finishes in one call, about 6 minutes (inference).
   - `run` chains every phase for Story 11.5 and for people. Each phase gets its own 540 s deadline.
5. **"The next turn's first model request".** This is read as the turn's first ChatAgent request. The Triage request comes first and decides on the new message (inference from `Conversation.cls:11-14`), and Task 0 (d) measures whether it also carries the fact. The harness asserts on the chat request either way.
6. **"A scenario ... passes".** The mock's reply is fixed, so the scenario passes when the turn completes with `recall-ask`'s answer and its chat request carried the fact told before the upgrade and the restart.
7. **The fact turn is seeded last.** The next turn then continues the AI session: "Noted." is not Tainted. R1 is set just before it, so R1's 300 s cover the upgrade (Task 0 (c)).
8. **The late band.** It is ±20 s around the candidate's ready, because `LATESECONDS` is 10 and the waiters are re-armed a few seconds before `Ready` (inference: `Reconcile` runs two steps before `Ready`).
9. **The restart** is `dc restart iris`, the clean container restart of FR-6.
10. **Storage.** The compiled dictionary comparison catches a renamed, retyped or removed property and a moved slot, inherited properties included. The block rule of AD-5 runs against the same commit. The block rule alone cannot see a type.
11. **The section contract.** The record's `## Upgrade harness` section carries `Result:`, `Mode:` and `Required:`. The harness rewrites only that section.
12. **`ci/units.sh`.** The 11.1 lead ruling is that it is shared by region, and Story 11.7's spec treats it the same way; this story touches only the `CHECK_SCRIPTS` line. A hermetic self-test needs that list (`test-ci-config.sh`). The full run is no `live:` unit, so it stays outside every group and outside REL-4's budget (the lead's ruling 3).
13. **Two new `A/` scenarios.** The mock never takes a delay from the request (`mock.mjs:37`), and `B/reminder-thursday` is a guide-prompt scenario that Story 11.7 may change.
14. **The page check** reuses the demo-switch Playwright project, the outermost surface of "no demo feature on the page".
15. **A dry run** (`plan`) starts nothing and writes its record marked `dry run`. `--rehearsal` and a dirty tree mark the record `rehearsal`.

**Size.** About six files: one large script and its self-test, and four small changes. The phases share one state and one records project, so the restart part cannot stand alone without a seed of its own. No split is proposed.

**Ledger (Rule 17).** This story owns no entries (`LEDGER slice` is empty), and its block holds no `DW-` bullet.

**Contended paths (U14).** Every file this story changes is listed under Tasks.
- None is in `contended-epic-11.txt` or in the diffs of `OCT-epic15`, `OCT-epic30`, `OCT-epic12` or `OCT-epic13`, checked at plan time. `ci/units.sh` is touched only on its `CHECK_SCRIPTS` line, which Epics 13 and 15 also extend (a plain union).
- `release/demo-load.sh` and `lib-online.sh` (Epic 29, merged) are read only.

## Verification

`<A>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`. QA and review use their own stage names and tags (`e11s2q...`, `e11s2c...`).

**Run discipline:**
- Run everything from the epic-11 worktree root.
- Each command runs in the foreground of its own call, with `timeout: 600000`. Never background a run, never use `Monitor`, and never re-submit after a client-side timeout. `ANTHROPIC_API_KEY` stays unset.
- One test or harness call per message.
- No slot and no MCP call: this story changes no class.
- While the records project is up (from `seed` until `down`), it holds lane A's throwaway lock. Run no other fresh lane-A throwaway in between; a warm stack is allowed.
- Always end with `down`, also after a failure.

**Shared surfaces:**
- `CHECK_SCRIPTS` gains `upgrade-harness` (`ci/checks.sh`, `test-ci-config.sh`).
- `ci/mock/scenarios/A/` gains two marker scenarios (the mock tests count them dynamically).
- `test-storage.sh`'s `release_diff` reads `OCUTALON_STORAGE_BASE`; unset, nothing changes.
- `test-install-upgrade.sh` sources `lib-upgrade.sh`.
- Lane A's lock and web port 52801 are held across the harness's calls.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.
- The self-test, `test-storage.sh` and `test-mock.sh` are hermetic.
- `live:install-upgrade` runs on its own fresh stack.
- The harness is one ordered journey on its own fresh projects (its order is the contract, and the self-test pins the refusals). Its evidence is a green full run on fresh projects after the last change.

**Commands:**
- (once, first) `git rev-parse --show-toplevel` -- expected: the epic-11 worktree.
- (once) `<A> OCUTALON_RUN_TAG=e11s2i ci/iris.sh build` -- expected: the bundle is built from this checkout.
- (loop) `bash -n release/upgrade-harness.sh && bash docker/tests/test-upgrade-harness.sh` -- expected: every rule PASS.
- (loop) `bash docker/tests/test-storage.sh` -- expected: all rules passed, `release-diff: no release tag yet` unchanged.
- (once) `bash docker/tests/test-mock.sh` -- expected: passes, and the two scenarios load.
- (once) `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`, then `bash ci/changes.sh ci.yml`, each in its own call -- expected: pass.
- (once) `<A> OCUTALON_RUN_TAG=e11s2u ci/iris.sh live install-upgrade` -- expected: `test-install-upgrade: all checks passed` (AC9).
- (loop) The harness, one phase per call, in this order:
  1. `<A> OCUTALON_RUN_TAG=e11s2h release/upgrade-harness.sh build --rc 1 --record "${TMPDIR:-/tmp}/e11s2h-record.md"`
  2. `<A> OCUTALON_RUN_TAG=e11s2h release/upgrade-harness.sh settings`
  3. `... seed`
  4. `... upgrade`
  5. `... restart`
  6. `... storage`
  7. `... report`
  8. `... down`

  Expected: each phase's PASS lines, and `PHASE <name> done <s>s (0 failed)` within 540 s. `report` prints `RESULT pass` with `Mode: rehearsal (uncommitted changes)` and `Previous: pre-release c9f1288c...`. Record the record's section and every phase's seconds here (Task 0, AC10).
- (once) `<A> OCUTALON_RUN_TAG=e11s2d release/upgrade-harness.sh plan --rc 1 --record "${TMPDIR:-/tmp}/e11s2d-record.md"` -- expected: exit 0, no container, `Mode: dry run`.
- (once) `bash ci/checks.sh` exceeds 10 minutes in one call, so run its parts. Each part is one call: `for s in <names>; do bash docker/tests/test-$s.sh || echo "FAILED $s"; done`.
  1. `boundaries storage class-rules ci-config ci-changes compose-file pinned-sources`
  2. `after-start healthcheck lib-live bootstrap demo-path-gate ci-warm`
  3. `probe install-script readme eval-set online-host online-load upgrade-harness`

  A part that nears 8 minutes is split further. Expected: no `FAILED` line.
- (once, last; also after a failure) `<A> OCUTALON_RUN_TAG=<tag> release/upgrade-harness.sh down` for each harness tag, then `<A> OCUTALON_RUN_TAG=<tag> ci/iris.sh teardown` for `e11s2i`, `e11s2u`, `e11s2h`, `e11s2m` and `e11s2v` -- expected: no lock of this stage left in the lane-a folder, and no project of these tags.

**Planned mutations (Rule 19).** For each one: apply it, observe red, revert, check that `git status --short` and `git diff --stat` are unchanged, then see green again. Record each as a `mutation:` line here.

Run M (tag `e11s2m`) is one full harness run with mutations 2 to 7 applied together, because their reds land in different rows. Run V (tag `e11s2v`) is `build`, `seed`, `upgrade` and `down` with mutation 1 alone, because it stops the upgrade.

| AC | Mutation | Expected red |
|---|---|---|
| AC2 (run V) | `docker/after-start.cos`: `inst'=img` in the `why` `$Select` becomes `0` | `upgrade` FAIL: not ready, or `check_installed`; every later row `not run`; `RESULT fail` |
| AC3, AC4 (run M) | `C/Core/Conversation.cls` `Ask`: always `fresh` with an empty `SeedText` | `conversation` and `restart` rows FAIL on the missing fact |
| AC3 (run M) | `C/Install/Step/Schedule.cls` `Reconcile` returns OK without calling `Schedule.Reminder.Reconcile` | `upgrade` FAIL on R2's waiter; `reminder` FAIL (R1 never fires) |
| AC3 (run M) | `C/Msg/Catalog/Watch.cls` `result.allThrough` text "went through" becomes "went thru" | `approval` FAIL on the phone text |
| AC3 (run M) | `C/Install/Step/Demo.cls` `Mode()`: `Setting.Set` instead of `Seed` | `settings` FAIL: demo mode on after the upgrade |
| AC3 (run M) | `C/Install/Step/Web.cls`'s `Reconcile` also runs `Do ##class(OcuTalon.Data.BackgroundCheck).%KillExtent()` | `watch` FAIL: Orders not listed and the press answers 409 `not_watching` |
| AC5 (run M) | In one stored class that exists at the pinned commit, rename a property that no other class names, in the class and in its storage slot (for example one of `C/Data/AddressCounter.cls`, if one qualifies) | `storage` FAIL from both the compare and `release-diff` |
| AC1, AC6, AC7 | Self-test: `resolve_previous` returns HEAD's sha; `record_section` ignores fail rows; `chat_request_carries` skips the `tools` filter; `storage_compare` drops the type column | The matching self-test rule FAILs |
| AC8 | `release_diff` ignores `OCUTALON_STORAGE_BASE` | The new base sample FAILs |
| AC9 | `lib-upgrade.sh` `check_installed` compares the marker with `$1` instead of `$2` | `live install-upgrade` FAIL on the marker; run V's red already covers the harness side |
| AC10 | (a measurement, not a test) | -- |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Summary (plan stage, 2026-10-31; nothing implemented, nothing committed).**
- What was planned: the upgrade harness `release/upgrade-harness.sh`, a hermetic self-test `docker/tests/test-upgrade-harness.sh` added to `CHECK_SCRIPTS`, two `A/` reminder scenarios, `docker/tests/lib-upgrade.sh` (moved out of `test-install-upgrade.sh`), and `OCUTALON_STORAGE_BASE` in `test-storage.sh`.
- Phases: the harness runs one phase per call (`build`, `settings`, `seed`, `upgrade`, `restart`, `storage`, `report`, `down`) or chains them with `run`, and keeps lane A's lock across calls while its records project is up.
- Previous ref: a `v*` tag when one exists, else the pinned pre-release commit `c9f1288c7a735f1ee3aa14a4f5289de794ce5257` (the integration branch at Epic 11's start), with the record note that 1.0.0 has no previous release.
- Pairing: the family is built as a hook and left off for Story 12.7.
- Not a CI unit: the full run stays out of every group and out of REL-4's budget.
- Ledger: owned entries: none. Amendments: none. Clarifications: none. Split: none proposed (Design Notes, Size).
- Footprint: Epic 11's footprint is "either lane's files", so there is no extension. The only shared-by-region edit is the `CHECK_SCRIPTS` line of `ci/units.sh`. No contended file is changed.
