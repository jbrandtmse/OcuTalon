# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds, a same-cause burst becomes one incident by the settle rule, and the Diagnosis agent explains it. The incident then moves through a fixed state table and can be dismissed from the chat. All of that is built. Two stories remain, and they make the watch visible and honest. In 5.6 the heartbeat runs each watched production's check every minute, records and publishes what it found, and quietly closes stale incidents. In 5.7, asked "is everything fine?", OcuTalon answers only from those code-computed results, so the model can never give a false all-clear. This epic is the "what broke" half of the demo path. Epic 7's approve-and-fix completes it.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details
- Story 5.9: Ask OcuTalon in the chat to dismiss an incident

## Requirements & Constraints

**Heartbeat checks (5.6)**
- On each `Tick`, run every check whose next-due time has passed. Run it once even if it missed several runs, and never replay the missed minutes.
- Each run records:
  - the time of the last run;
  - the result: `passed`, `failed` with the finding, or `not_checked` with the reason;
  - the latest run's trace header id.
- A reader error or timeout gives `not_checked` with its reason, never `passed`.
- A production watch's check covers the running state, new errors, the open incident and the latest run time.
- The page's background-check row shows:
  - the name ("Orders production");
  - the schedule ("Live, plus a check every minute");
  - the last run and the last result;
  - a trace link to the latest run.
- A new watch shows at once, and a stopped one leaves.
- Findings do not become Items yet. Story 30.4 adds that, along with "never report a finding twice" (for a stopped production or a disabled item). Until then, the check records each result on its row and sends no finding Item.
- Quiet close: each unclosed incident whose last failure is more than 15 min old gets `closeQuiet`, and only the transition table decides the result:
  - a resolved incident closes;
  - an open one closes only with demo mode off, and otherwise waits for Dismiss;
  - awaiting approval and fixing never close this way;
  - a newer failure changes nothing.

**No false all-clear (5.7)**
- Code computes from the check results whether an all-clear may be given. The model can't add one.
- Reply cases:
  - Every check passed: "Everything I checked passed."
  - Something failed or wasn't checked: name it first with "Not everything: {what failed, with its time}." Follow with "Everything else I checked passed." only when other checks passed. Example: "Not everything: the Orders production has 50 failed orders since 14:12 ET, and a fix is waiting for your approval."
  - Nothing watched: "I'm not watching any productions yet, so I can't say. Ask me to watch one."
  - In every case, code-computed check rows follow (what was checked, the result, when).
- The guard removes these from model text and keeps the rest:
  - the reserved sentences: "Everything I checked passed.", "Everything else I checked passed." and "Your IRIS system is healthy";
  - the closed list of banned phrases: "all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about".
- Required tests:
  - with Orders failing, "is everything OK?" gets no all-clear, and the failing check is named first;
  - in a mock scenario where the model claims everything is fine while a check fails, the reply still has no all-clear.

**Security**
- `check_status` is safe, read-only and trusted output.
  - Trusted output holds only text that code builds from OcuTalon's own records, and nothing from outside a user's untainted turn.
  - So a row's `finding` must be written by code, never raw error or event-log text (inference from the spine's trusted-output definition; no document states it, so the plan confirms or drops it).
- The same pattern holds for `dismiss_incident` (DW-288). It stays trusted output only while a `Test.Bridge.Gate` test pins its answer to code-built fields: Refs, states, variants, times, counts, the watch's display name, outcome codes and the code's own message texts. Any free-text field added later must fail that test.
- Database row ids never reach the model, and credential-like setting values never leave the reader.

## Technical Decisions

**Checks (5.6)**
- `OcuTalon.Checks.Process` (item `Checks`, Lane A) handles a `Tick` from Lane B's `HeartbeatIn` (Epic 8), which carries the tick time and the previous tick time in UTC. Tests send the `Tick` directly.
- `Checks` reads all watch state through `Watch.Reader`, the only class that switches namespace.
- `OcuTalon.Data.BackgroundCheck` is the one table for every background check. `WatchOps` writes the production-watch rows (`SessionRef`, namespace, production class, display name, asking IRIS user). Later steps add other check kinds to the same table.
- `Checks` is the single publisher of `check`.
  - The payload is the check's full current view, keyed by its `Ref`: name, schedule, last run, result, and the trace target as `TraceHeaderId` plus `TraceNamespace`.
  - It goes out through `Live.Publish` after commit (`Publish` refuses to run inside a transaction).
  - It is published when a row changes, and also when `WatchOps` starts or stops a watch.
- DW-66: add `Live.Payload.Check.FromRow`, and confirm or replace `traceNamespace` (the check's namespace). The web layer's copy in `Web.Api.CheckView` then switches to it. `Web` is Lane B's.
- `closeQuiet` is an `IncidentCommand`, and `IncidentManager` answers it synchronously:
  - `not_quiet` while `LastAt` is not more than 900 s old;
  - `not_allowed` when the transition table refuses the move;
  - `Ok` with outcome `closed` otherwise.
  - `closeQuiet` checks no session.
- Story 7.5 later adds a call to `Fix.Run.Sweep()` on each `Tick`, which sends its final `FixResult`s to `IncidentManager`.

**All-clear (5.7)**
- `OcuTalon.Checks.Render(results, *rows)` keeps Epic 0's pinned signature and is implemented here.
  - It returns a catalog key plus rows `{result, entry, finding, checkedAt}`, with `result` from the `CheckResult` enum.
  - Only `Render` chooses the reserved sentence. The sentences themselves are catalog entries, which the `*Out` operations and the page render.
- DW-90: the keys `checks.notEverything` and `notEverythingRestPassed` need a whatFailed slot, and the pinned signature has no way to return one. This story decides how the page gets whatFailed (from the failing row, or a slot path through `Render`) and makes both keys render.
- How the results travel:
  1. `check_status` (in `OcuTalon.Tools`) returns the session's latest results and fills the context's `HostData.checks`, a JSON array.
  2. The runner copies `HostData` onto the `Reply`.
  3. `Conversation` (Lane B, Story 2.6) passes the array to `Render` without reading it, and attaches the key and rows to the reply and to `chat.message` after the guard has run.
- `OcuTalon.Checks.ReplyGuard` extends `OcuTalon.Bridge.Ext.ReplyFilter` and replaces Epic 0's pass-through stub. `Decide`'s `ReplyFilterClass` setting already names it.
  - It runs exactly once, on every model-written text, before anything is recorded or leaves `Decide`.
  - The legitimate all-clear arrives afterwards, from `Render`'s key. So the guard can strip all all-clear wording without deleting a real one.
- Mock scenarios are files under `ci/mock/scenarios/A/` only.

**Conventions**
- Lane A files only: `OcuTalon.Checks`, `.Tools`, `.Watch`, and Lane A's region of the production XData.
  - Never edit Lane B files (`Core`, `Data.Session`, `Data.Ownership`, `Live`, `Msg`, `Web`, `Schedule`). Ask for properties instead.
  - `Tick` additions are Epic 8's, append-only.
- Components reach each other only through messages addressed by item name. Tools may use `Msg`, `Data`, `Watch.Reader` and `Commands.Submit`.
- Tool classes:
  - declare `CLASSIFICATION`, `READONLY`, `TRUSTEDOUTPUT`, `STEPLABEL` and `RESOURCES`, optionally `<NAME>`-suffixed;
  - return a dynamic object through `Tools.Result`;
  - take their names from `Tools.Names`.
- Times are UTC ISO 8601 to the second, rendered only through `Data.Time`.
- Refs come from `Bridge.Ids.NewRef()`, and settings are read through `Data.Setting.Get`.
- An SQL reserved word keeps its name and gets an `SqlFieldName` or `SqlTableName`.
- Tests are named `OcuTalon.Test.<Area>.<Subject>`.
- Timings (pickup within 15 s, the notice within 60 s) are measured in the rehearsal and never asserted in CI.

## UX & Interaction Patterns

- Plain English, in the first person, with short sentences and no exclamation marks. No class names, codes or stack traces outside Show details.
- A check row under a "fine?" reply shows a result icon and word (Passed, Failed, Not checked), the entry name, and the finding or reason with its time in muted text.

## Cross-Story Dependencies

- **Done:** 5.1 to 5.5, 5.8 and 5.9, in the run order 5.1, 5.2, 5.3, 5.4, 5.8, 5.5, 5.9, then 5.6, 5.7.
  - 5.6 builds on 5.1's `BackgroundCheck` rows and `WatchOps`, the reader, and 5.5's `closeQuiet` handling.
  - 5.7 reads the results that 5.6 records.
- **Upstream:**
  - Epic 0: `Tick`, the pinned `Checks.Render`, the `ReplyGuard` stub, `Decide`'s extension settings and the catalog keys.
  - Lane B's `HeartbeatIn` (Epic 8) sends the `Tick` every minute.
  - Epic 2 (Story 2.6): `Conversation` calls `Render`, and the page shows the check rows.
  - Epic 3: the gate's classifications.
- **Downstream:**
  - Story 7.5: `Fix.Run.Sweep` on each `Tick`.
  - Story 30.4: finding Items for a stopped production or a disabled item, with a two-Tick test.
  - Story 9.3: the all-clear evaluation cases. When the owner is `eval`, `check_status` reads the request's `HostData` in place of the session's results, and `EvalIn` calls `Render`. That path stays in Lane A, with no `Conversation`.
  - Epic 8: the page's check rows.
  - Epic 17: the digest's all-clear also comes from `Render`.
  - Epic 30: a purge task keeps `Checks` messages for 7 days.
