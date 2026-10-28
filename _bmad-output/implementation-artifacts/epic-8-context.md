# Epic 8 Context: Heartbeat and reminders, on time and surviving restarts

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 builds OcuTalon's clock in `OcuTalon.Schedule`. It runs on runner C, in Lane B's files. It delivers a one-minute heartbeat with its stalled warning, and reminders asked for in plain words. A reminder fires within 10 s of its due time on every channel, can be listed and cancelled in the chat, and survives restarts and upgrades, marked late when it arrives late. Stories 8.1 to 8.6 are done.

What remains is the burn-down. The browser sign-in unit has grown to the edge of the 10-minute foreground cap every stage works under, and one of its specs passes only because of file order. Story 8.7 splits the unit into two parts that each fit the cap and removes that order dependence, so later stories can keep adding sign-in tests. The owner wants this fixed before Epic 8 merges.

## Stories

- Story 8.1: The heartbeat ticks every minute and catches up once after a restart (done)
- Story 8.2: The heartbeat-stalled warning comes from the real heartbeat (done)
- Story 8.3: A reminder fires on time on every channel (done)
- Story 8.4: Set, list and cancel reminders in plain words (done)
- Story 8.5: Reminders survive restarts and upgrades, and late ones say so (done)
- Story 8.6: Reminders through the chat on the demo path (done)
- Story 8.7: Epic 8 burn-down (DW-314 and DW-204)

## Requirements & Constraints

- **Two parts (DW-314).**
  - `live sign-in` (`docker/tests/test-sign-in.sh`) runs as part 1/2 and part 2/2 of the same script, split by spec file.
  - Each part takes about 4 to 5 minutes on the developer machine.
  - Together the two parts run every spec of the whole unit exactly once, and that must still hold when a spec file is added later.
  - With no part given, the script runs the whole unit as it does today.
- **CI unchanged.** CI's `browser` group still runs the whole unit. Its deadline is 1200 s, and the unit took 701 s on CI.
- **Recipe line.** Rule 21 in `_bmad/custom/skill-rules.md` gains a line that says how to run the two parts. The story decides the wording. The same rule's note "`live:sign-in` near its local deadline" is where the unit's timings are recorded.
- **Order independence (DW-204).**
  - `web/e2e/api/api.spec.ts` pins the instance stream at exactly one event, the script's seeded `noModelKey` status event. It checks this in `/state`'s stream counts and in its cursor polls.
  - `heartbeat.spec.ts` adds two status events to that stream, the onset and the clear. api.spec stays green only because `api/` sorts before `heartbeat/` and there is one worker.
  - api.spec must read the instance stream's events against a baseline it takes itself. It must pass whether or not heartbeat.spec ran first: in either part and in the whole unit.
- **Evidence (Rule 19).** Before the fix, see api.spec fail with heartbeat.spec run first, and record that mutation. Every test added or changed must pass on a fresh stack in either order.
- No committed file may hold a local absolute path, or CI's `test-boundaries.sh` fails.

## Technical Decisions

- **Ownership and rulings.**
  - `docker/tests/test-sign-in.sh`, `web/e2e/**` and the CI recipe are Lane B's files, which this epic works in.
  - The orchestrator ruled that `test-sign-in.sh` is not contended: no open branch changes it. The part argument goes in it.
  - Epic 6 is editing three things right now: the `browser` group line in `ci/units.sh`, `BROWSER_UNITS`, and the browser expectations in `docker/tests/test-demo-path-gate.sh`. Choose a part shape that leaves all three alone: no new unit name and no change to the group. The gate stubs `test-sign-in.sh`, runs `ci/iris.sh group browser`, and expects `UNIT live:sign-in passed`.
- **Plumbing today.**
  - `ci/iris.sh live <name>` runs `bash docker/tests/test-<name>.sh` with no arguments. Getting a part through the recipe needs one of two things: `cmd_live` forwards its arguments, or the script reads a variable.
  - Story 5.3 has already changed `ci/iris.sh` on the integration branch, so that file comes in on the next integrate-forward.
- **Precedent: `ci/iris.sh shard <name> --part k/n`.**
  - It comes from Story 5.3 and is on the integration branch, not yet on this epic's branch. Its helper is `shard_part` in `ci/iris.sh`.
  - It accepts `--part k/n` or `--part=k/n`.
  - It cuts the ordered list into n contiguous parts whose sizes differ by at most one. The first (count mod n) parts are the larger ones.
  - It titles the run "`<name>` part k/n".
  - It exits 2 for a malformed value, a k outside 1 to n, or an n above the item count.
- **The unit as built.**
  - One call starts one throwaway stack. It rebuilds the web bundle, builds the image and does the first start. It then runs the security checks, creates 14 fixture users with random passwords, and seeds three events: two reminder events on the README account's session and one status event on the instance stream.
  - Then it runs Playwright's `chromium` project: every spec under `web/e2e/` except `demo-path/`, `demo-switch/` and `floor/`, with one worker, in file-path order.
  - Each part pays that whole setup again.
  - The browser run's global timeout is whatever is left of `OCUTALON_LIVE_DEADLINE` minus 20 s. That deadline is 540 s by default locally and 1200 s in CI.
- **Timings.**
  - The unit has 222 tests in 18 spec files.
  - The whole call took 506 s at Story 8.3, 6.9 minutes of it in Playwright. At Story 8.6 it took 512 to 515 s, run with `OCUTALON_LIVE_DEADLINE=900`.
  - Spec files differ widely in run time. heartbeat.spec waits for two StatusMonitor runs, 15 s apart, and the trace specs post until a session holds more than 45 items. An even split by file count may therefore not split the time evenly.
  - Setting `OCUTALON_E2E_JSON` writes a JSON report with the time of each test.
- **State shared across files within a part.**
  - `reminder/chat.spec.ts` points the model keys at the mock and puts them back in its `afterAll` (`pointKeys` and `restoreKeys` in `support/devices.ts`). Later specs, `trace/links.spec.ts` among them, expect the no-key fallback.
  - session.spec S4 expects that nothing signed the sign-in user in before it.
  - Each part starts from the same fresh stack with no key, so all of this still holds if each part keeps file-path order.
- **Epic 8 as built, for orientation only.** 8.7 changes none of this.
  - `HeartbeatIn` sends a `Tick` to `Checks` every minute.
  - `ReminderOps` handles set, list and cancel, with plain-English refusals and repeats by `IdempotencyKey`.
  - Each reminder waits in its own frozen `ReminderTimer`.
  - The Schedule area's `Reconcile` re-arms reminders at every start.
  - The restart cases are the live unit `reminder-restart`, in the `production` group.

## Cross-Story Dependencies

- Stories 8.1 to 8.6 left specs in this unit: `heartbeat/heartbeat.spec.ts`, `reminder/reminder.spec.ts` and `reminder/chat.spec.ts`. They must pass in whichever part they land and in the whole unit.
- The `demo-path`, `demo-switch` and `floor` units use other Playwright projects and are not affected.
- Epic 6 is editing the browser group and the gate at the same time (see the rulings above). Expect a union, not a rewrite, if Story 8.7 touches anything near them.
- This epic owns DW-204 and DW-314 in the ledger. Both close in Story 8.7, and Epic 8 merges after it.
