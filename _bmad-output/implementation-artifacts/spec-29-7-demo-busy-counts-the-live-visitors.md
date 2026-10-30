---
title: 'Story 29.7: Demo busy counts the live visitors'
type: 'feature'
created: '2026-10-30'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [multiple-goals, oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 29.4's plan measured that a signed-in online-demo visitor holds no licence connection on build 154. So AD-13's busy checks (`/ocutalon/public/status`, the splash and the post-sign-in reserve) never engage on visitors who stay out of Visual Trace, and a 7th visitor gets in (DW-251). Owner decision U-163 amended AD-13: busy also counts OcuTalon's own live visitor sessions against a visitor cap of about 6. Separately, nothing in the repository yet lets the author run and record the real-proxy load run that measures the demo's capacity (DW-286).

**Approach (as proposed in the split, Design Notes "HALT"):** This story becomes the AD-13 visitor count. A proxied sign-in that attaches a visitor marks its own CSP session. The sessionless status and the login page count the marked CSP sessions that have not timed out, read from IRIS's own CSP session store without taking a session. Busy is reached at 6 counted visitors, the post-sign-in check refuses the 7th, and `OWNCONNECTIONS` is 0. The author's load script and its procedure in `release/` become a sibling, Story 29.8.

## Boundaries & Constraints

**Always:**
- Owner decisions U-163 and `epic29_brief` bind. Both are quoted under Design Notes.
- No new global, table, property or storage definition. No grant to the demo, trace or public accounts.
- The count's reader takes no connection and no session, and reads only what any process may read.

**Never:**
- Connect to, configure or probe the demo host. Run `ocutalon-demo`, SSH or DNS commands.
- Edit `Install/**`, `src/cpf/**`, `docker/merge.cpf` or any other contended path. Write the spine.

</intent-contract>

## Code Map

The investigation of this pass. The re-plan reuses it. Line numbers are at `160ce107`.

**The busy rule today**
- `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls`:
  - `Body` (:57-66) sets `busy` from `Busy()`.
  - `Busy(own)` (:71-74) is `IsBusy(InstanceConnections() - own, connectionCap, connectionReserve)`.
  - `IsBusy` (:78-83) answers `connections >= cap - reserve`, and 0 without a valid cap.
  - `BUSYHEADER` (:21).
  - The class doc (:1-10) names what the class may reference (AD-3).
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`:
  - `OWNCONNECTIONS = 1` (:35);
  - `AttachVisitor` (:66-104): it refuses busy first with `If proxied, Status.Busy(..#OWNCONNECTIONS)` at :67, then resumes from the cookie (:71-75), or, when proxied, takes the counter lock, checks the limit, starts the visitor and counts it (:79-95).
  - The class doc (:24-25) says it has no `OnLogout`, `OnEndSession` or `OnTimeout`.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`:
  - `REFUSALKEY = "OcuTalon.Refused"` (:25) is a key of `%session.Data`. The hook writes it at sign-in, and `OnPreDispatch` (:65-81) reads it in the same request (Story 16.5's rows 5 and 6). That does not show the key persisting across requests: that the key is saved with the session is read from `%SaveData` (below) and is not measured.
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls:124`: the splash shows busy when `Status.Busy()` is 1, so it follows `Busy`'s rule.
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls`:
  - `KEYS` (:9) is AD-19's fixed list;
  - `ready` is the one runtime key (`ClearReady` and `SetReady`);
  - it is the only reader and writer of `^OcuTalonPublic`, which `docker/tests/test-class-rules.sh` (rule public-global, :8 and :75-78) enforces.
- `web/src/app/live/demo-busy-state.ts`: `openTrace` (:42-51) asks `/ocutalon/public/status` and opens no window when `busy` is true. While busy, a quiet re-check runs every 10 s. `web/src/app/api/api-client.ts:26` and `:117` hold `publicStatus()`.

**Tests that pin today's rule**
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls`:
  - `TestBusyOwn` (:137-149) pins `Busy(1)`;
  - `TestReferencesOnlyThePublicAllowList` (:204-243) scans the two public packages for class, `$SYSTEM` and dynamic references. It does not scan global references.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls`: `ForceBusy` (:361) and the busy cases at :265, :293, :325 and :338.
- `docker/tests/test-online-demo.sh`:
  - its header (:54) and rows 5 and 6 (:1118-1186) pin `OWNCONNECTIONS` at 1;
  - helpers: `set_cap` :940, `script_connections` :942, `status_read` :945, `http_view` :960, `busy_page` :990, `set_proxy` :813, `host_address` :816;
  - `session_csp` :1289 and `csp_alive` :1290 (`%CSP.Session.%ExistsId`, in `%SYS`).
- `docker/tests/test-online-session.sh:121` reads `<InstanceConnections>/<LUConsumed>`.

**IRIS's CSP session store (read-only source, the same build)**
- `irislib/%CSP/Session.cls`:
  - `%SaveData` (:906-921) writes `^%cspSession(id)` as a `$ListBuild` and the session's `Data` under `^%cspSession(id,0)`;
  - `UpdateTimeout` (:798-833) moves the timeout at each request;
  - `SessionInfo` (:1089-1126) reads `$$$sesOldTimeout` (3) and `$$$sesApplication` (13) (`irislib/%cspBuild.inc:154-166`).
- `irislib/%CSP/Daemon.cls:56-110`: sessions are ended as their timeout passes.
- `irissys/NSPMAP.int:505` and `irissys/Config/Journal.cls:97`: the store is mapped away from the namespace's databases.

**The load script's siblings (for Story 29.8)**
- `release/demo-host-check.sh` (538 lines), Story 29.3's sibling:
  - the gate credentials reach curl only through a temporary owner-only configuration file (:28-31);
  - no host literal;
  - exit codes 0, 1, 2 and 3.
- `docker/tests/test-online-host.sh` (918 lines, a `CHECK_SCRIPTS` entry, hermetic): a `lib-stub.sh` Node stand-in, and row 15's self-scan for host detail and ASCII.
- `release/demo-host-checks.md` (92 lines): the release check list, H1 to H24.
- `docker/tests/lib-online.sh`: `online_signin` :88, `logout_all` :77, `keys_point` :111.
- `web/e2e-online/support.ts`: `openVisitor` and `sessionRow` (Story 29.4).
- `ci/units.sh:31-41`: the groups.

**Measured in this pass (slot C, build 154U, id `19113194-CDDB-11F1-9984-5AEDC9673D1B`, namespace OCUTALON; read-only, no session's data or security context printed)**
- `^%cspSession` from OCUTALON resolves to `IRISLOCALDATA` (`%SYS.Namespace.GetGlobalDest`). It is not IRISTEMP, as `Config.Journal`'s comment suggests.
- The resources' public permissions:
  - `%DB_IRISLOCALDATA` R and `%DB_IRISTEMP` RW;
  - `%DB_OCUTALON_PUBLIC` R (also `docker/merge.cpf:8`);
  - `%DB_OCUTALON_DATA` and `%DB_OCUTALON_PRIVATE` none.
- The application roles are `%DB_OCUTALON_CODE`, `%DB_OCUTALON_DATA` and `%DB_OCUTALON_PRIVATE` (`Install/Step/Web.cls:40`). So no signed-in visitor can write `^OcuTalonPublic`.
- Two live sessions (`/api/atelier/`) gave:
  - `$ListGet(^%cspSession(id),1)` is the application timeout (3600);
  - `$ListGet(^%cspSession(id),3)` is the absolute time it ends, in `$ZTIMESTAMP` seconds (3599.5 s and 3393.5 s ahead of now);
  - `$ListGet(^%cspSession(id),13)` is the application path;
  - the store has a timeout index at `^%cspSession(0)`.
- Not measured (inference, for the re-plan's Task 0 on an online-demo throwaway):
  - a marker set in `OnLogin` appears at `^%cspSession(id,0,<key>)`;
  - a sign-out deletes the node;
  - a restart empties the store;
  - a request with no session can read the store.
- Story 16.4 measured that a closed page's CSP session is deleted 152-153 s after its last request (DW-286's trailer). A count that reads the timeout drops at 120 s.

## Tasks & Acceptance

None in this pass: the plan HALTs (Design Notes, "HALT"). The re-plan writes the tasks for the scope the lead rules.

## Spec Change Log

- 2026-10-30, lead: the plan HALTed (split recommended; AD-13's trace-window bullet). Rulings 1 and 2 applied (story retitled and split, 29.8 added; the count's home accepted); ruling 3 is with the orchestrator. The spec stays `blocked` until that ruling.

## Review Triage Log

## Design Notes

**Owner decision U-163** (`apply U-163 at=2026-10-30T09:33:18Z#496`, the Contest Planner under the owner's delegation). It binds, quoted:
> option (a): amend AD-13 so busy also counts OcuTalon's own live demo visitor sessions against a cap of about 6 (the owner's figure, P12/NFR-23, unchanged), kept where the sessionless `/status` and the login page can read it. OWNCONNECTIONS becomes 0, and the InstanceConnections check stays as the trace-licence guard. Conditions: (1) a session leaves the count on sign-out and on its timeout (about 120 s, as measured), so a crashed tab can't hold a place; (2) the probe and the admin path never count; (3) the count starts at 0 at every reset; (4) the tests prove a 7th visitor sees Demo busy while a 6th gets in.

**Owner decision `epic29_brief`, the load-run bullet** (as the orchestrator relays it):
> The real-proxy load case is the author's (the Contest Planner's pass) on the adapted host. The repository delivers what the author runs: a load script in `release/` and its procedure, taking the base URL and the driver addresses from the author, holding no host detail, never spending the $20 daily cost cap, staying within the 8-licence-unit ceiling (DW-287), writing results in a form for the 1.0.0 release notes, never asserted in sharded CI as the real-proxy result. It is proven in CI against a local stack or stand-in with a small bounded run, and never run against the demo host.

**Architecture decisions that govern this story (Rule 6):**
- AD-13 (as amended under U-163): the visitor count, busy, the post-sign-in check, the trace-window check and `/status`.
- AD-3: the public package's references.
- AD-19: the public settings' fixed keys and their only accessor.
- AD-25: the probe's direct connection, resets, the golden copy and capacity.
- AD-4: visitor sessions.
- AD-22: tests, throwaways and CI groups.
- AD-29: the Epic 29 exception for `release/`.

**Lead rulings (2026-10-30; runner C, unattended policy 6df0676):**
1. **The split is accepted (decide; Rule 5 tier 2 within `split_children`).** This story is retitled "Demo busy counts the live visitors" (key `29-7-demo-busy-counts-the-live-visitors`; this spec file renamed to match) and keeps U-163's conditions 1 to 4 and DW-251; Story 29.8, "The author's load run measures the demo's capacity" (key `29-8-the-author-s-load-run-measures-the-demo-s-capacity`), takes the real-proxy load criterion verbatim and DW-286 (re-owned). The load-script part of this plan is 29.8's input; remove it from this spec at the re-plan.
2. **The count's home is accepted (decide; within the orchestrator's rule):** derived on read from IRIS's own CSP session store, each proxied visitor's CSP session carrying one marker in its session data (the `REFUSALKEY` mechanism); no new global, key, table or mapping. The re-plan's Task 0 measures the four unmeasured points (the marker survives to the next request; sign-out deletes the session; a restart empties the store; a sessionless request can read it) on a lane-C throwaway before any code; a failed measurement is a new intent gap.
3. **AD-13's trace-window bullet ("Before opening a trace window, the page checks `/status`") is with the orchestrator** (an AD amendment, doctrine U14): the recommendation is `/status?for=trace` answering busy from the connection check alone. Re-plan only after the ruling.

### HALT: intent gap (two questions for the lead and the orchestrator)

**Question 1: split the story (Rule 5 tier 2; size).** The story holds two independently shippable changes.
- **The AD-13 visitor count.** Two product classes and the public shell. The web trace check (question 2). Updated pins in `Test.Web.Status`, `Test.Web.SessionEvents` and `test-online-demo.sh` rows 5 and 6. A new live unit with a 120 s timeout wait.
- **The author's load script and its CI proof.** A `release/` script the size of Story 29.3's `demo-host-check.sh` (538 lines), with a stand-in or live proof (29.3's took 918 lines), a procedure section and a CI unit.

Together they exceed one reviewable change. The count is the owner's pre-launch need ("before the public flip"), and the script is the author's release tool, which uses the count only for its "one more visitor sees busy" step. The recommended split keeps U-163's conditions where U-163 put them:
- **Story 29.7, retitled "Demo busy counts the live visitors"** (new key `29-7-demo-busy-counts-the-live-visitors`):
  - scope: the epics block's first criterion and its "And" (U-163's conditions 1 to 4), and DW-251;
  - the plan:
    - `Shell.VISITORKEY` (a `%session.Data` key, beside `REFUSALKEY`);
    - `SessionEvents.OWNCONNECTIONS = 0`, and `AttachVisitor` marks the CSP session after a proxied attach (resume or create) succeeds;
    - `Status.VISITORCAP = 6`, and `Status.Visitors()` counts the CSP sessions of `/ocutalon/` that carry the marker and whose timeout is still ahead (question 3);
    - `Busy(own)` is 1 when the connection rule holds or `Visitors() >= VISITORCAP`, so a 6th visitor gets in and the 7th is refused;
    - the trace form of question 2.
  - Tests:
    - `Test.Web.Status` and `Test.Web.SessionEvents` (the rule, the marker only on a proxied attach, `OWNCONNECTIONS` 0);
    - `test-online-demo.sh` rows 5 and 6, pinned at 0;
    - a new live unit `live:online-busy` in `shards`. Six proxied visitors from six forwarded addresses get in; then `/status` and the splash report busy with the marker header. The 7th is refused with the busy splash, and gets no row, cookie or counter row. A direct sign-in (the probe's path) at the cap gets in and is not counted. One sign-out frees a place. A visitor that stops polling leaves the count at its 120 s timeout. A restart starts at 0.
  - Expected: about 6 to 8 min on CI (inference: about 230 s of start and checks, as `live:online-allowance`, plus about 130 s of timeout wait), so `shards` rises from 21 to about 28 min.
- **Story 29.8, "The author's load run measures the demo's capacity"** (new key `29-8-the-author-s-load-run-measures-the-demo-s-capacity`):
  - scope: the epics block's second criterion (the real-proxy load run) and DW-286;
  - the plan: `release/demo-load.sh <base-url> --visitors N [--trace] [--max-turns M] --interface ADDR...` extends `release/demo-host-check.sh`: its gate-credential file, no host literal, exit codes and self-scan. It needs one driver address per visitor, and nothing in it sets `X-Forwarded-For`.
  - Per visitor:
    1. sign in from the splash with the three fields;
    2. wait for `/state` 200;
    3. send one guide watch turn;
    4. press Break the feed;
    5. time the notice from `/events` against NFR-7's 60 s;
    6. approve on the phone channel;
    7. optionally open the trace link;
    8. sign out of the whole group.
  - Then one more visitor reads `/status` and the splash. The output is a line per visitor and a Markdown table for the 1.0.0 notes. It refuses a run whose turn bound exceeds `--max-turns`.
  - The procedure goes in a section of `release/demo-host-checks.md`. It has two cases, 6 visitors without Visual Trace and 3 with. The author also reads connections and units per visitor from the host's admin path while a unit is free (H22) for DW-286.
  - The CI proof is a small bounded run (2 visitors) against an online-demo throwaway with the keys at the mock, or a `lib-stub.sh` stand-in; 29.8's plan decides.
- Bookkeeping for the lead: retitle 29.7 (Rule 5: `SPRINT_PLAN generate --set`), move the second criterion verbatim to the new 29.8 block, and re-own DW-251 (to 29.7's new key) and DW-286 (to 29.8).
- The alternative that keeps 29.7's key: a new 29.8 holds the count and is planned and built before 29.7. It moves U-163's conditions out of the story U-163 put them in, so it is not recommended.
- Either way the AD-13 count ships in Epic 29.

**Question 2: the trace-window check and the visitor count (AD-13; an amendment, veto window (9)).**
- The conflict:
  - AD-13 keeps "Before opening a trace window, the page checks `/status` and shows the busy text instead". `demo-busy-state.ts` `openTrace` opens no window while `busy` is true, and re-checks every 10 s.
  - As amended, `/status`'s `busy` also covers the visitor count.
  - So at a full house (6 counted visitors), no admitted visitor can open Visual Trace, although the connection guard would allow up to 6 trace sessions (cap 8 less reserve 2).
- Two readings, with observably different outcomes: the literal one (the trace check follows `busy`, visitor count included), and the owner's stated outcome ("the InstanceConnections check stays as the trace-licence guard").
- Recommendation: `/status` takes one optional query pair, `for=trace`. In that form `busy` is the connection check alone. The five keys stay the same, so the probe, the splash and `release/demo-host-check.sh` are unchanged. `openTrace` and its re-check use the trace form.
- AD-13's trace bullet would read: "Before opening a trace window, the page checks `/status` in its trace form (`?for=trace`, the connection check alone) and shows the busy text instead".
- This keeps UJ-1's trace step real for every admitted visitor (product default 1).
- The literal reading needs no amendment, but blocks step 6 for all six visitors at a full house.

**Question 3, decided (no escalation): where the count lives.**
- It needs no new storage. It is derived on read from IRIS's own CSP session store, which any process may read (`%DB_IRISLOCALDATA`, public R, measured). Each counted session carries one key in its own `%session.Data`, the same structure that `REFUSALKEY` already uses. That the key is saved with the session and visible to another process is read from IRIS's source, not measured (Code Map).
- The reader lives in `Web.Public.Status`, beside its `$SYSTEM.License` read. It is IRIS's state, not an OcuTalon value, so "it and the login page read only the public settings" (AD-13) and AD-19's fixed keys hold as written. The CSP store is `%CSP`'s, which AD-3 allows.
- The conditions follow from the session's own life:
  - (1) a sign-out deletes the session, and a session whose stored timeout has passed is not counted, so the count drops at 120 s, not at the daemon's 152 s;
  - (2) only `AttachVisitor`'s proxied branch sets the marker. The probe connects directly, and the admin path is not a proxied `/ocutalon` session;
  - (3) a reset restarts IRIS. Every session from before it is past its timeout or gone (inference until the re-plan's Task 0), and a golden copy holds no visitor sessions (AD-25).
  - The trace applications' sessions carry no marker. The read-only account holds no OcuTalon user role, so its `/ocutalon` session ends at once.
- Rejected:
  - a new key in `^OcuTalonPublic`. It amends AD-19's fixed keys. No visitor session can write it (public R, and the application roles lack `%DB_OCUTALON_PUBLIC`). It is durable, so a crash leaves stale entries and a golden copy captures them.
  - a new IRISTEMP global. It is a new stored global (the orchestrator's veto rule), and it is not needed.
- The risk: the store's layout (`$ListGet` positions 3 and 13, `Data` under subscript 0) is IRIS's internal one. The re-plan pins it with a Task 0 measurement and the live unit, so a change in a later build turns CI red.

**Ledger inbox (Rule 17):**
- DW-251: addressed. The visitor count engages busy without a connection. Recommended owner: 29.7 under its new title.
- DW-286: addressed by the proposed 29.8. The author's measurement on the host closes it. 29.4's throwaway readings are already in its trailer.

**Integration ACs (Rule 1):** none yet. The count's consumers (the status, the splash, the post-sign-in check and the trace check) and the load script's consumer (the author's run) are named in the split's plans. The re-plan writes the Integration ACs and the `Consumed-by:` and `Consumes:` lists.

**footprint_extensions:** none in this pass. The proposed 29.7 touches:
- `web/src/app/live/**` and `web/src/app/api/**`, which are `web/src/app/**`, in the footprint;
- `docker/tests/test-online-demo.sh`, in the footprint;
- `ci/units.sh`, only its own unit entry.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: (1) split recommended (Rule 5 tier 2, size): Story 29.7 holds two independently shippable changes, the AD-13 visitor count and the author's load script with its CI proof; recommend 29.7 retitled "Demo busy counts the live visitors" (U-163's conditions 1 to 4, DW-251) and a new Story 29.8 "The author's load run measures the demo's capacity" (the real-proxy load criterion, DW-286); (2) AD-13: the page's trace-window check reads /status's busy, which now includes the visitor count, so at a full house no admitted visitor can open Visual Trace; recommend /status?for=trace answering busy from the connection check alone (the owner's "the InstanceConnections check stays as the trace-licence guard"), an AD-13 amendment (veto window). The count's home needs no escalation: derived on read from IRIS's CSP session store, no new storage (Design Notes, HALT).

**Plan stage (2026-10-30, runner C, unattended).** Planned only. Nothing was implemented, and no runtime but slot C was used (read-only: identity, resource permissions, the CSP store's mapping and layout). No throwaway was started, so there is nothing to tear down. The investigation is in the Code Map for the re-plan.
