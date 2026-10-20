# Messages for the Contest Planner (undelivered)

Rule 22.6: the Contest Planner relays owner-only and VETO WINDOW items. When its session is unreachable, the lead writes the message here and resends it when the session is back. Each entry is marked `sent` once delivered.

## 2026-10-19 19:15 UTC: correction to the Story 0.6 VETO WINDOW item 2 (production recover)

Status: sent (the Contest Planner read it at origin 80abb60 on October 19; no veto)

I said queued messages "stay Suspended, never discarded". That is inaccurate. Code review measured IRIS's recover on build 154:

- in-progress messages go back on their queues;
- asynchronous queues are kept for the next start;
- queued synchronous messages are marked Suspended;
- private-queue messages (in-flight synchronous replies) are discarded.

The step still never runs clean and never kills application data.

- **Ruling:** unchanged. Recover rather than refuse to start.
- **Rejected:** refusing to start, which leaves the judge's install unhealthy after any crash.
- **Reversal:** drop the recover branch.
- **Spine:** AD-23's wording is corrected in Story 0.6's commit.

Also from the 0.6 review:

- AD-3 now says business processes set no `DEFAULTGLOBAL`, because they store in `Ens.BusinessProcess`'s extent, and that they keep no private text in their properties.
- Code review fixed two HIGHs in-pass: lane-shared test counts, and `TelegramIn` missing `STUB`.

## 2026-10-19 20:26 UTC: Story 0.7 (CI): one owner-only item and five VETO WINDOW items

Status: sent (the Contest Planner read it at origin 80abb60 on October 19; no veto on items 1-5; the CI-gate wording is with the owner)

**Owner-only (Rule 22.4, `.claude/` is the owner's).** The CI gate in `/epic-cycle` reads one run per commit: `.claude/commands/epic-cycle.md`, "CI Is a Gate", uses `gh run list --branch … --commit <sha> … -L 1`. Story 0.7 adds two workflows, `ci` and `lane-a`, so every push has two runs and the gate sees only one of them.
- Recommended wording: "list every run for the sha (`-L 20`) and require each workflow's run to conclude `success`".
- Until then, the lead lists both runs by hand at every resolution point.

**Repository settings (owner-only, no change needed now).** Keep "run workflows from fork pull requests" off on this private repository; branch protection comes at Story 11.5. The job-level fork guard holds either way.

**VETO WINDOW (Rule 22.3).** Each item is ruled and in the spec. Say so to reverse one.
1. **Dependencies.** Three new ones, all MIT and pinned: `actions/checkout` v7.0.1 and `actions/setup-node` v7.0.0 (by commit SHA), and `@types/node` 24.19.1 (exact). The last is for the web lint, a strict type check of the Playwright specs.
2. **Scan scope.**
   - The checks job's path and key scans cover every tracked file, `_bmad-output/`, `.claude/` and `CLAUDE.md` included. A spec or log that cites a machine path turns CI red.
   - The path pattern needs a user-name segment. Measured on the tree today, there are no hits.
   - A hit under `.claude/` or in `CLAUDE.md` would be the owner's to fix.
3. **Token.** The IRIS and web jobs get `actions: read`, so they can find the newest green run; everything else gets `contents: read`. No secret is referenced.
4. **Skip rule.** A job skips its own steps, never the workflow, only when nothing it checks changed since the newest commit whose push run succeeded. Pull requests, a missing base and API errors run everything, so a skip never turns a red into a green. Bookkeeping-only pushes skip the IRIS steps, but they still take a runner for a few seconds.
5. **Kept whole.** Story 0.7 stays one story. Its spec is 61 KB, about the size of 0.6's at planning (58 KB), which passed in one implement pass. The planner's split line (the new class rules into a 0.12) is the fallback if implement does not converge.

The time budget is at risk: about 28 minutes against REL-4's 30 (inference). If the first real run exceeds 30 minutes, the lead rebalances the groups. Changing the 30-minute figure, or moving checks off epic pushes, would be the owner's call.

## 2026-10-20: owner decisions of October 20 applied (shas for verification)

Status: pending. No session named "Contest Planner" was listed, so this is written here, as the owner directed; it was also sent to the `contests-b0` session.

The owner gave seven decisions directly in the Epic 0 lead's session. Each is logged as `owner_decision` with the owner's words in `cycle-log-epic-0.md`. Both commits are on `origin/OCT-epic0`:

- **The CI-gate fix (decision 6): `80e8f46`.**
  - `.claude/commands/epic-cycle.md` only: the three gate reads (at `committed`, the runner's `ci:` claim, the merge precondition), the resolution points and `ci_green_verified`.
  - Each now lists every run for the sha (`-L 20`), groups the runs by workflow, and requires each expected workflow's latest run to succeed.
  - Nothing else under `.claude/` changed.
- **Decisions 1, 2, 3, 5 and 7 recorded: `85503df`.**
  1. The count-of-one, late-press and sign-in-label texts are in `EXPERIENCE.md`, and AD-32 notes them. DW-41 is routed to the burn-down, which adds them to the catalog and removes the gap fields.
  2. Demo mode off keeps a foreign or other-production OCUORDERS: a warning, a status note on removing it by hand, and the start finishes with the ready marker. This is in AD-3, and DW-42 is routed to the burn-down.
  3. No plain-image CI run: DW-36 is closed as accepted. NFR-21 reinstates the P15 wording ("supported, verified on ARM64"), the ARCHITECTURE-NOTES P15 row says so, and an AC bullet under Story 10.2 carries it.
  5. `x-ocutalon-mockkey` is sent only with the CI-only `OCUTALON_MOCK_KEY_HEADER=1`, which only `ci/compose.ci.yml` sets, and never from `OCUTALON_MODEL_BASE_URL` alone. This is in AD-19, AD-22 and the DW-39 bullet under 1.1. Story 0.11's QA and review add the setting and pin it.
  7. REL-4 is 35 minutes, in the PRD, `epics.md` (REL-4 and the Epic 9 line) and Rule 21's budget line. DW-21 is closed as accepted; a run still over 35 after a rebalance goes to you, and the fix is a third runner service.
  - Decision 4 (the `node:24.15.0-slim` image is accepted) needed no file change.

CI: the hold head `71cd7cc` is green on both workflows (ci 29m39s, under the new 35). `85503df`'s runs are in flight.
