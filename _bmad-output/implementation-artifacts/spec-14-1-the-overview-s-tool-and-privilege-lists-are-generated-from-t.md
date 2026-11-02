---
title: 'Story 14.1: The overview''s tool and privilege lists are generated from the product'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: 'abf2022f08c25332d2df081cd13eb762fad84e5e'
baseline_commit: 'abf2022f08c25332d2df081cd13eb762fad84e5e'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: 'The privilege test reads Security.Roles, Security.Users and Security.SQLPrivileges with its own small readers, a copy of the private readers of OcuTalon.Test.Install.Registry (ReadRole, UserResources, SqlPrivileges), because that class is contended (Epic 15) and its readers are private.'
    evidence: 'src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:1047,1103 (private); contended list at the epic start'
    location: 'src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls'
    severity: low
---

<intent-contract>

## Intent

**Problem:** A security reviewer has no document listing what OcuTalon's built-in tools, fix kinds, roles and service user can do, and nothing stops such a list from drifting from what ships and what the installer grants.

**Approach:** Create `docs/security-overview.md` with three generated sections between markers (tools, fix kinds, privileges), written by a new generator class from `%AI.Catalog`, the tool and fix-kind parameters and the installer's composed `Grants()`. Tests fail when the committed sections differ from a fresh generation, when the tool list differs from what every running runner holds, or when IRIS security records differ from the listed privileges; the release sequence runs the same checks and stops on a failure.

## Boundaries & Constraints

**Always:**
- Read tools through `%AI.Catalog` with pattern `OcuTalon.%`, then keep only the product's own classes: agents under `OcuTalon.Agent.`, toolsets under `OcuTalon.Tools.` (the same scope as `Install.Step.Tools.Toolsets()`, which grants the service role). Expand each toolset with `%Discover()` (the catalog cannot expand toolsets; measured on slot D).
- Read every tool value through the existing readers: `StepBuffer.ToolParameter` (CLASSIFICATION, READONLY, TRUSTEDOUTPUT, RESOURCES), `StepBuffer.LabelFor`, `Gate.HookFor`, `Gate.Resources`. Compose the role grants with `Install.Step.Roles.Compose`. Take the demo-mode-only grants from `Install.Step.Demo.WithOrdersData` and `WithOrders`.
- Output is deterministic (sorted) and ASCII only. The generator changes only the text between its markers. Every byte outside them stays the same.
- The generated tools section carries this fixed statement, word for word: "No built-in tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL, and AI Hub's shell, filesystem, SQL and web-search tools are never registered. The automated tool-inventory test `OcuTalon.Test.Agent.Runners` (`TestToolInventory`) checks this on every running runner."
- Every IRIS test runs on lane-D throwaways (`ci/iris.sh`), never on a slot. `ci/units.sh` gets new entries only.

**Never:**
- Edit a contended file: `Tools/Names.cls`, `Install/Step.cls`, `Install/Registry.cls`, `Production.cls`, `src/module.xml`, existing `Test/Install/*` classes, `docker/tests/lib-live.sh`, `docs/install-ipm.md`. Never edit `Install/Step/Demo.cls` or `Install/Step/Web.cls` (Lane B). Reading them is fine.
- Add, rename or remove a CI group or job. Move or edit an existing unit. Run, cut, tag or push a release.
- Write hand-written overview text beyond the title, one intro sentence and the placeholders (Story 14.2 writes those sections). No host, address or local path in the overview.
- Change any security record, grant or role. This story only lists and checks them.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tool rows | Compiled package. Catalog also returns `OcuTalon.Test.*` fixtures and `OcuTalon.BridgeExample.Agent` | 12 rows, one per name in `Tools.Names` `RELEASE1`, sorted by name. Columns: Tool, Source class, Toolset, Agents, Step label, Classification, Read-only, Trusted output, Resources (`none` when empty). No fixture appears | No error expected |
| DW-521 | `recent_activity` | Its row reads Source `OcuTalon.Tools.RecentActivity`, Toolset `OcuTalon.Tools.Watching`, Agents `OcuTalon.Agent.Chat`, label "Reading recent activity", `safe`, Read-only `yes`, Trusted output `yes`. A test pins it | No error expected |
| Classify hook | A tool with `Classify`/`Classify<NAME>` (`Gate.HookFor` is not empty) | The Classification cell reads "per call: " plus the text of `CLASSIFYRULE<NAME>` / `CLASSIFYRULE`, read with `ToolParameter` | Generation fails with a status naming the tool when the rule text is missing |
| Fix kinds | `Fix.Kind.Classes()` | One row per kind: class, `NAME`, `RESOURCES` (`repair_resend`: `%Ens_MessageResend` U) | No error expected |
| Privileges (DW-213) | Composed `Grants()` | Per role (`OcuTalonServiceRole`, `OcuTalonUser`, `OcuTalonAdmin`, `OcuTalonTraceViewer`): each resource and permission, and the areas that declare it. A separate "With demo mode on" list: service role `%DB_OCUORDERS_DATA` R; trace role `%DB_OCUORDERS_CODE` R and `%DB_OCUORDERS_DATA` R. SQL: the trace role has SELECT on `Ens.MessageHeader` in OCUTALON, and in OCUORDERS with demo mode on. `OcuTalonService` holds exactly `OcuTalonServiceRole`, with login disabled. `/ocutalon` and `/ocutalon/api` add `Web.APPLICATIONROLES` to every signed-in user | No error expected |
| Splice | Overview with hand-written text and three marker pairs | Each region is replaced. The rest of the file is byte-identical (line endings and the final newline included) | A missing, repeated or out-of-order marker returns an error status naming the marker. Nothing is written |
| Drift: committed | A tool added, removed, renamed or reclassified, overview not regenerated | `live:security-overview` prints `DRIFT tool <name>` for each changed row and the diff of the region, then exits 1 | Fails the CI group |
| Drift: runtime | A runner's ToolManager holds a tool that is not in its agent's rows, or the reverse | `TestToolsMatchRunners` fails naming the runner and the tool | A production that is not running fails the test (never a skip) |
| Privilege | IRIS records differ from the model, in the current demo mode | `TestPrivilegesMatchSecurityRecords` fails naming the role, resource and permission, extra or missing | No error expected |
| Release | `release.sh next` at step `overview` | The callable unit passes: `PASS overview`, `NEXT ipm`. Drift or privilege failure: `FAIL overview <detail>`, and the release stops with the record written. The lane lock is busy (exit 75): `WAIT overview`, exit 5 | As `step_ipm` |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Agent/{Chat,Diagnosis,Triage}.cls` -- `Parameter TOOLSETS`: Chat `Reminders,Watching`, Diagnosis `Watch`, Triage none.
- `src/ocutalon/cls/OcuTalon/Tools/{Reminders,Watching,Watch}.cls` -- the toolsets (XData `Definition`). Providers: `ReminderTools`, `WatchTools`, `RecentActivity`, `WatchReads`. All 12 tools are `safe` by parameter. No tool has a Classify hook or `RESOURCES`. The `WatchReads` tools are the only ones without trusted output.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls:6-31` -- the 12 names and `RELEASE1`. Read only (contended).
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls:155,167` -- `LabelFor`, `ToolParameter(toolClass, name, base)`, which applies the `<BASE><NAME>` rule.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls:197,221,344` -- `ClassificationOf` (needs the Decide configuration; use it only in tests on a running stack), `Resources(value, where)`, `HookFor(source, name)`.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls:29-38` and `Fix/Kind/RepairResend.cls:26` -- `Classes()`, `NAME`, `RESOURCES`.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls:97` -- `Declared("Grants", .entries)`, with `entries(n,"area")`. Read only.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls:23` -- `Compose(Output roles)` is `[Private]`. It is a pure read: `roles(role,resource)=perm`, plus a check that each resource exists, in `%SYS`.
- `src/ocutalon/cls/OcuTalon/Install/Step/{Tools,Fix,Users,Web}.cls` -- the four `Grants()` declarers. `Users`: `SERVICEUSER`, `SERVICEROLE`, `EnsureService()` (`Enabled=0`, roles exactly the service role). `Web`: `TRACEROLE`, `APPLICATIONROLES` (`:40`), `GrantTraceSql` (`:336`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls:134,149,176` -- `Mode()` (it seeds the setting, so call it only in tests), `WithOrders`, `WithOrdersData` (pure helpers).
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls:312` and `RunnerFixture.cls:265` -- the pattern for the ToolInventory request: `RunnerFixture.Send(item, ##class(OcuTalon.Bridge.Msg.ToolInventory).%New(), .response)`, then `tools[].name` from the JSON.
- `docker/tests/lib-live.sh` -- `live_start`, `iris_script <ns>` (keeps `CHK|` lines only), `dc`. Read only (contended).
- `release/release.sh:54,437,720,760-775` -- `STEPS`, `step_fail`, and the 75-to-WAIT mapping in `step_ipm`. `docker/tests/test-release-sequence.sh:488-497,834,873,1043,1969` -- `to_step`, the `NEXT ipm` literals, the order pin, and `mkseed` (`:403`), which archives `release/`.
- `ci/units.sh:53,134,142` -- the `production` group, `IRIS_INPUT`, `NO_WEB_BUNDLE_UNITS`. `docs/` is a non-input (`:150`).

## Tasks & Acceptance

**Execution:**
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls` -- Drop `[Private]` from `Compose`, and say in its doc comment that the overview also reads it. -- Reuse, not a copy. No behaviour change.
- [x] `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- New. Add these methods:
  - `Model() As %DynamicObject`: tools, fix kinds, roles, the demo-only grants, SQL privileges, the service user and the application roles, per the matrix.
  - `Sections(Output sections)`: the Markdown for the keys `tools`, `fix-kinds` and `privileges`.
  - `Splice(text, Output out) As %Status`.
  - `Regenerate(inFile, outFile) As %Status`.
  
  Markers are `<!-- BEGIN GENERATED <key>: written by OcuTalon.Install.SecurityOverview, do not edit -->` and `<!-- END GENERATED <key> -->`. Generate in OCUTALON. -- AC 1, 2, 5.
- [x] `docs/security-overview.md` -- New. It holds:
  - the title `# OcuTalon security overview`;
  - one intro sentence saying that the generated sections are written from the product and checked by tests;
  - the three marker pairs, filled by `--write`;
  - headings with `<!-- HAND-WRITTEN (Story 14.2) -->` placeholders for: limits of the privilege check, approval and audit, data, MCP tools, online demo.
  -- Runner ruling 1.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls` -- New `%UnitTest`, area Install. Add these tests:
  - `TestToolRows`: 12 rows equal `RELEASE1`, no fixture, and each row's classification equals `Gate.ClassificationOf(...).classification`.
  - `TestRecentActivityRow`: DW-521.
  - `TestToolsetScope`: the catalog toolsets in scope equal `Install.Step.Tools.Toolsets()`.
  - `TestFixKindRows`: `Classes()` equals every non-abstract class in package `OcuTalon.Fix.Kind`.
  - `TestDemoOnlyGrantsListed`: DW-213.
  - `TestSplice`: keeps the outside bytes, and errors on a missing, repeated or out-of-order marker.
  - `TestInventoryStatement`: the verbatim statement, and `OcuTalon.Test.Agent.Runners||TestToolInventory` exists.
  - `TestAscii`.
  - `TestToolsMatchRunners`: every enabled production item of class `OcuTalon.Bridge.Operation.AgentRunner`, by its `AgentClass`.
  - `TestPrivilegesMatchSecurityRecords`: each listed role's resources and the service user's roles and `Enabled`. Also SQL `SELECT` on `Ens.MessageHeader` per namespace, and the MatchRoles of `/ocutalon` and `/ocutalon/api`. The expected set is the base grants plus the demo grants when `Demo.Mode()` is on.
  
  Use small private readers of the security records (deferred item). Each test creates and removes its own state. -- AC 1-5, Rule 19.
- [x] `docker/tests/test-security-overview.sh` -- New live unit. It runs these steps:
  1. `live_start security-overview`, and wait until the stack is healthy.
  2. Copy the committed overview into the container and run `Regenerate` through `iris_script OCUTALON` (`CHK|` result).
  3. Read the output back and compare it with `cmp`.
  4. On a difference, print the diff of each changed region and one `DRIFT tool <name>` line per added, removed or changed tool row (or `DRIFT fix-kinds` / `DRIFT privileges`), then exit 1.
  
  With `--write`, it writes the result to `docs/security-overview.md` instead. It names no web bundle path. -- AC 3, the committed half.
- [x] `ci/units.sh` -- Add three entries:
  - append `live:security-overview` to the `production` line;
  - append `live:security-overview` to `NO_WEB_BUNDLE_UNITS`;
  - add a new line after `IRIS_INPUT`, with a one-line comment: `IRIS_INPUT="$IRIS_INPUT|docs/security-overview\.md\$"`.
  -- Runner ruling 4. The inputs rule of test-ci-config and the skips of `ci/changes.sh` both need the claim.
- [x] `release/security-overview.sh` -- New. This is the callable unit: `bash release/security-overview.sh [--write]`, run from the root of a checkout. It runs these, one at a time, with its own run tag:
  1. `ci/iris.sh live security-overview [--write]`;
  2. `ci/iris.sh class OcuTalon.Test.Install.SecurityOverview`;
  3. `ci/iris.sh teardown`, always.
  
  Output and exits: `PASS|FAIL overview <detail>`. Exit 0 on a pass, 75 when the lane lock is busy, 1 otherwise. -- AC 6. Story 11.14 can call it.
- [x] `release/release.sh` -- Set `STEPS="cut image overview ipm push notes"`, and update the header's step list. Add `step_overview`: it runs the unit in the candidate clone. 0 means PASS. 75 means `WAIT overview` (return 5), as in `step_ipm`. Anything else means `step_fail overview <first FAIL/DRIFT line>`. -- AC 6.
- [x] `docker/tests/test-release-sequence.sh` -- Update the order pin, `to_step` and the `NEXT ipm` literals that now read `NEXT overview`. Add cases for the pass, the fail (stopped, record written, no `NEXT ipm`) and the busy-lock WAIT. Each case uses a stub `release/security-overview.sh` written into the seed repository before `start`, so the step needs no docker shim and no test variable. -- Pins AC 6.

**Acceptance Criteria:**
- Given a fresh lane-D throwaway, when `ci/iris.sh class OcuTalon.Test.Install.SecurityOverview` runs, then every test passes, and a run in reverse order passes too.
- Given the committed overview regenerated with `--write`, when `ci/iris.sh live security-overview` runs, then it prints PASS. Given `CLASSIFICATIONRECENTACTIVITY` changed to `risky` without regenerating, then it exits 1 with `DRIFT tool recent_activity`.
- Given hand-written text outside the markers, when `--write` runs, then `git diff` shows changes only between markers.
- Given the release sequence at step `overview`, when the callable unit fails, then the release stops with `FAIL overview` and its record, and never reaches `ipm`.

## Spec Change Log

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 25 rows (reviewer findings grouped by shared claim; one row each) - high 0, medium 4, low 21, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: step_overview drops the drift diff from the record - the first DRIFT line names the tool and the unit reruns with the diff; a log-keeping branch is more than a direct correction.
  - `[medium]` `[patch]` Blind + VG: release/security-overview.sh is only run through a stub - Patch P2: a hermetic run of the real script with a stubbed ci/iris.sh.
  - `[medium]` `[patch]` Blind + VG: the lane lock folder reaching the unit is not asserted - Patch P1: the stub prints OCUTALON_LOCK_DIR and t_overview compares it.
  - `[low]` `[reject]` Blind: other step_overview failure paths (no script, CLASS failed fallback text) untested - low, covered by P2 for the CLASS branch; the rest are unlikely.
  - `[low]` `[reject]` Blind: reverse checks (every OcuTalon role or application is in the model) - by design: Decided in-stage (c) limits the check to the listed roles because other tests create fixture roles.
  - `[low]` `[reject]` Blind + Edge: docs/security-overview.md in the shared IRIS_INPUT, and release/security-overview.sh in no group input - by design: Decided in-stage (e) and the spec's approved ci/units.sh entries; P2 puts the script under test-release-sequence.sh.
  - `[low]` `[reject]` Blind + Edge: Regenerate Catch closes outFile when not opened, partial output on a failed write, single Read - no user-reachable failure; the splice error path writes nothing (pinned by P3).
  - `[low]` `[reject]` Blind + Edge: Cell/Code do not escape backtick, angle brackets, backslash - no shipped value contains them; ASCII and the fixed statement are pinned.
  - `[low]` `[patch]` Blind + Edge: TestToolRows skips the read-only and trusted-output checks for per-call tools, TestSplice leaves an unused status - Patch P5.
  - `[low]` `[reject]` Blind: dc cp relies on the repo root as working directory - lib-live.sh sets it; no failure.
  - `[low]` `[reject]` Blind: empty HAND-WRITTEN placeholders could ship - Story 14.2 owns them; the spec fixes the placeholders.
  - `[low]` `[patch]` Blind: the helpers divider line merges into the RowOf doc comment - Patch P5.
  - `[low]` `[patch]` Edge: git archive failure hidden by the pipe status - Patch P6 (pipefail in the subshell).
  - `[low]` `[reject]` Edge: a DRIFT/FAIL line with a pipe or path in the record - the lines are generated tool names and CLASS lines; no path is printed by them.
  - `[low]` `[reject]` Edge: unit runs without the lane lock when the author's repository has no lock folder - ci/iris.sh takes the lane lock itself; unreachable on a real author checkout.
  - `[low]` `[reject]` Edge: INT/TERM trap ordering, discarded teardown output - teardown is idempotent and runs again; theoretical.
  - `[low]` `[reject]` Edge (x3): invalid CLASSIFICATION value or settings-entry fallback would differ from Gate.ClassificationOf - spec-bound: the Always rule reads tool values through ToolParameter; TestToolRows compares with the gate for every shipped tool.
  - `[low]` `[reject]` Edge: %Discover returning no tools, Splice section without a final line feed, missing input file message - internal callers pass generated values; the result is an error or an empty region caught by the drift unit.
  - `[medium]` `[patch]` VG: Regenerate has no unit test and its nothing-is-written rule is unpinned - Patch P3.
  - `[medium]` `[patch]` VG: the DRIFT detail lines and --write path of the live unit run only by hand - Patch P7: region/tool_rows/drift move to docker/tests/lib-security-overview.sh and test-release-sequence.sh runs them on two files.
  - `[low]` `[patch]` VG (Rule 19): TestToolsetScope, TestClassifyHookShowsItsRule, TestFixKindRows, TestAscii and the SQL, Enabled and MatchRoles assertions have no mutation: line - Patch P4: demonstrate each mutation and write the lines.
  - `[low]` `[reject]` VG: assertions that cannot fail (sorted fix-kind rows, toolset-row membership, the statement self-compare) - the neighbouring assertions carry the weight and the statement is pinned by its mutation.
  - `[low]` `[reject]` VG: the demo-off branch of the privilege test is not exercised in CI - the test must not change the demo mode (a security change); the demo-on mutation and the AC mutation pin the expectation.
  - `[low]` `[reject]` VG: mutation labels AC1-AC6 do not map to the four listed criteria - labels belong to the spec's Verification table, not to the code.
  - `[low]` `[reject]` Intent audit (descriptive, 5 readings): the class test does not read the committed file - the committed-versus-fresh comparison is the live unit by the spec's Tasks; no divergence needs a decision.

**Patch tasks (this pass):**
- P1 `docker/tests/test-release-sequence.sh`: the pass stub of release/security-overview.sh prints the OCUTALON_LOCK_DIR it receives; t_overview asserts it equals the case's lock folder. Done: the stub records the folder it receives, and the pass case runs without OCUTALON_LOCK_DIR so the step derives it from the author's repository (otherwise the check could not fail).
- P2 `docker/tests/test-release-sequence.sh`: a hermetic rule that runs the REAL release/security-overview.sh copied into a temp tree with stub ci/iris.sh and stub docker/tests/test-security-overview.sh: exit 0 gives PASS and exit 0; a live exit 75 gives WAIT and exit 75 and the class step does not run; a live failure printing a DRIFT line gives FAIL with that line and exit 1 and the class step does not run; a class failure gives FAIL; teardown runs in every case; the run tag is the caller's tag plus -ovw-<pid>; --write reaches the live step. Done: rule `overviewunit`.
- P3 `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls`: add TestRegenerate: a good temp file (created and removed by the test) gives OK and bytes equal to Splice of the same text; a file with a missing marker gives an error status and no output file. Done.
- P4 Rule 19: for TestToolsetScope, TestClassifyHookShowsItsRule, TestFixKindRows, TestAscii, TestRegenerate and the SQL, Enabled and MatchRoles assertions of TestPrivilegesMatchSecurityRecords: apply a mutation, observe red, revert byte-identical, and write a mutation: line for each in Verification. Also a mutation for criterion 3 that pins the --write path (for example Regenerate writes without the splice). Done: eleven mutation lines in Verification.
- P5 `Test/Install/SecurityOverview.cls`: TestToolRows compares read-only and trusted output for per-call tools too (skip only the classification comparison); drop the unused status in TestSplice; separate the helpers divider line from the RowOf doc comment. Done: per-call tools read their flags with ToolParameter.
- P6 `release/release.sh` step_overview: the export fails the step when git archive fails (pipefail in a subshell). Done.
- P7 move `region`, `tool_rows`, `drift` from docker/tests/test-security-overview.sh into the new docker/tests/lib-security-overview.sh (they take `$tmp` as now), sourced by the live script; add cases to docker/tests/test-release-sequence.sh (its own rule) that source the lib and assert: one changed tool row gives `DRIFT tool recent_activity`; a change outside the rows gives `DRIFT tools`; a fix-kinds change gives `DRIFT fix-kinds`; a privileges change gives `DRIFT privileges`; equal files print nothing. Done: rule `overviewdrift`.

## Design Notes

**Governing ADs:** AD-10 (the inventory statement, and the runner ToolManager check), AD-16 (fix kinds and their `RESOURCES`), AD-22 (the as-built 12 tools, CI groups, no release run by CI), AD-23 (grants come from `Grants()`, composed by Lane A's step), AD-24 (the roles, the service user, the trace role, the demo-mode-only OCUORDERS grants, and an overview that never overstates least privilege), AD-29 and AD-33 (Lane A files; Lane B's Demo and Web steps are read, never edited).

**Integration ACs:** The consumers below run against a real installed stack:
- `live:security-overview` reads `Regenerate` and fails naming the tool.
- `TestPrivilegesMatchSecurityRecords` reads `Model()` against the IRIS records.
- `step_overview` reads the callable unit and stops the release.
- Story 14.2 writes inside the placeholders, outside the markers, and `--write` keeps its text.

**Consumed-by:** Story 14.2 (the file and its markers; it supplies the path for Story 31.3's About link), Story 17.5 (the generated privilege list), Story 11.14 (calls `release/security-overview.sh` on the pushed candidate). **Consumes:** `Install.Step.Roles.Compose`, `Install.Registry.Declared`, `StepBuffer.ToolParameter`/`LabelFor`, `Gate.HookFor`/`Resources`/`ClassificationOf`, `Demo.WithOrders`/`WithOrdersData`, `RunnerFixture.Send`, `Fix.Kind.Classes`.

**Extend, don't copy:** The generator reuses every reader named above. `Roles.Compose` is made public rather than copied. The only copy is in the privilege test: small readers of the security records (frontmatter `deferred:`). `Test.Install.Registry`'s readers are private, and that class is contended. `lib-live.sh check_security` is shell and also contended.

**Runner rulings recorded:**
1. The file is `docs/security-overview.md`, with the markers and Story 14.2's placeholders as in the Tasks.
2. AD-22's count of 12 includes `recent_activity`. `TestRecentActivityRow` pins it, and the drift unit checks the committed row (DW-521).
3. The release hook is decided:
   - The callable unit is `release/security-overview.sh`, and Story 11.14 can call it on the pushed candidate.
   - It is also wired into the merged sequence as step `overview`, between `image` and `ipm`, because that is a small, self-contained addition: one step function plus pins in the hermetic test, which stubs the unit in the seed repository.
   - "Regenerates" means a fresh generation from the candidate's code is compared with the candidate's committed sections. On drift the release stops, and the author runs `--write` on the integration branch, commits, and cuts the next rc. A candidate branch is never re-committed (Story 11.5).
4. CI placement:
   - The test class sits in area Install, so it runs in `shard:lane-a@Checks,Install,Watch` of group `shards`, the shard group with the most room (about 1,710 s), with no `ci/units.sh` change.
   - The live unit goes in `production` (about 1,300 s, the most room). It reads no web bundle, so it also joins `NO_WEB_BUNDLE_UNITS`. Estimated about 250-450 s on CI (inference, from the other live units there).
5. The slot was used for Task 0 only:
   - `%AI.Catalog` with `OcuTalon.%` lists 10 agents, 10 toolsets and 13 tool classes. That includes the test fixtures and `OcuTalon.BridgeExample.Agent`, which has no toolsets.
   - `Fix.Kind.Classes()` is `RepairResend` alone (`%Ens_MessageResend:U`).
   - `Declared("Grants")` gives the service role `%Ens_MessageResend` U only. Users and Admin have no resources. The trace role has the six grants.
6. The only file edited outside the listed footprint is `Install/Step/Roles.cls` (not contended; report it under `footprint_extensions`), along with `docker/tests/test-release-sequence.sh` and the new `docker/tests/test-security-overview.sh`.
7. The public text is the AC's fixed statement, naming `OcuTalon.Test.Agent.Runners` `TestToolInventory`.

**Decided in-stage:**
- (a) A Read-only column is added, which DW-521 asks for.
- (b) The privilege section also lists `Web.APPLICATIONROLES` and the trace role's SQL `SELECT`, so that it never overstates least privilege (AD-24). The test checks both.
- (c) The privilege test checks only the listed roles exactly, not "no other `OcuTalon*` role", because other tests create fixture roles.
- (d) A Classify-hook tool needs `CLASSIFYRULE[<NAME>]` text, or generation fails.
- (e) `docs/security-overview.md` becomes an IRIS input of every group, a new line in `ci/units.sh`. So an edit to the overview, Story 14.2's included, runs the groups.
- (f) The generated text claims about `OcuTalonService` only what the test checks: its role, and that login is disabled.
- (g) Each generated region starts with its own `##` heading (`Built-in tools`, `Fix kinds`, `Privileges`), so the headings cannot drift from the content, and Story 14.2 adds its text only in the placeholder sections. Sub-headings of the privilege region are `###`.
- (h) A tool with no `CLASSIFICATION` value and no Classify method shows `unclassified`. Roles are listed in name order; the "Declared by" cell names the installer areas by their short class names (`Users`, `Fix`, `Web`); a role with no resource shows `none` and `-`.
- (i) A table cell escapes `|` as `\|` and turns line breaks into spaces, so a CLASSIFYRULE text with a bar cannot break the table. The generator fails (a status naming the section) when a section holds a non-ASCII character.
- (j) `Splice` takes an optional third argument, the sections to write (made by `Sections` when absent), so `TestSplice` pins the byte rules with fixed text. A region is written with the line ending of its begin marker line, so a CRLF file keeps CRLF. A marker is a whole line (a trailing CR allowed).
- (k) `docker/tests/test-security-overview.sh` copies the committed file into the container and the result out with `docker compose cp`, since `iris_script` keeps only `CHK|` lines. Its diff headers carry the region names, not temporary paths.
- (l) `release/security-overview.sh` appends `-ovw-<pid>` to the caller's run tag (so its teardown removes only its own stacks), and treats a failed CLASS line like a FAIL line when it names the detail. `step_overview` runs the unit in an export (`git archive`) of the candidate's cut commit, since the temporary clone is gone after the image step, and creates an empty `web/node_modules` there so `ensure_web_bundle` installs nothing. It hands the lane lock folder of the author's repository to the unit.
- (m) `test-release-sequence.sh` keeps a passing stub of the unit in the seed; the fail and busy cases replace it in the case's checkout and push it to the integration branch before `start`. The pass stub checks that it runs in the cut candidate (module version 1.0.0, `web/node_modules` present).
- (n) `TestPrivilegesMatchSecurityRecords` compares the trace role's SQL privileges as a whole set (the listed SELECT rows, those of OCUORDERS only with demo mode on), as `Test.Install.Registry.TestTraceRoleSql` does. `TestClassifyHookShowsItsRule` uses a new fixture, `Test.Install.ZzOverviewRule`, and the existing `Test.Bridge.ZzGateWide` (a class-wide hook with no rule text) for the failing case.

**Ledger inbox:** DW-213 is addressed in the Privileges row and in `TestDemoOnlyGrantsListed`. DW-521 is addressed in the DW-521 row and in `TestRecentActivityRow`.

## Verification

Every IRIS command runs from the worktree root with the lane prefix. Use `timeout: 600000` and one command per call. The prefix is:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=14 stage=implement'
```

**Commands:**
- (loop) `<prefix> OCUTALON_RUN_TAG=e14s1implw bash ci/warm.sh up`, once. Then `<prefix> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e14s1implw bash ci/iris.sh class OcuTalon.Test.Install.SecurityOverview` -- expected: the CLASS line passes. At the stage's end, also after a failure: `<prefix> OCUTALON_RUN_TAG=e14s1implw bash ci/warm.sh down`.
- (loop) `<prefix> OCUTALON_RUN_TAG=e14s1impl bash ci/iris.sh live security-overview` -- expected: PASS, then `... teardown`.
- (loop) `bash docker/tests/test-release-sequence.sh` -- expected: no FAIL.
- (loop) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, one per call -- expected: exit 0.
- (once) `<prefix> OCUTALON_RUN_TAG=e14s1impl bash ci/iris.sh class <C>`, one call each for `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Install.Tools`, `OcuTalon.Test.Watch.Grant` and `OcuTalon.Test.Agent.Runners` -- expected: each passes. These are the units that the change to `Roles.Compose` and the reused readers touch.
- (once) `<prefix> OCUTALON_RUN_TAG=e14s1rel bash release/security-overview.sh` -- expected: `PASS overview`, exit 0, and the throwaways torn down.
- (once) `<prefix> OCUTALON_RUN_TAG=e14s1impl bash ci/iris.sh shard lane-a@Checks,Install,Watch --part 1/2`, then `--part 2/2`, then both again with `--reverse` -- expected: every CLASS line passes. Finish with `ci/iris.sh teardown` for each tag used.

**Mutations (Rule 19), one per AC:**

| AC | Change | Expected red |
|----|--------|--------------|
| 1 | `TRUSTEDOUTPUTRECENTACTIVITY=0` | `TestRecentActivityRow` |
| 1 | `Splice` drops the final newline | `TestSplice` |
| 2 | `Model()` omits the `WithOrdersData` grant | `TestDemoOnlyGrantsListed` |
| 3 | `CLASSIFICATIONRECENTACTIVITY="risky"`, overview not regenerated | `live:security-overview` with `DRIFT tool recent_activity` |
| 3 | The generator skips `OcuTalon.Tools.Watch` | `TestToolsMatchRunners` |
| 4 | `Model()` omits `%Ens_MessageResend` | `TestPrivilegesMatchSecurityRecords` |
| 5 | The statement names another test method | `TestInventoryStatement` |
| 6 | `step_overview` ignores the exit code | the fail case of `test-release-sequence.sh` |

mutation: (run in the Implement stage; each applied, run, observed red, and reverted to a byte-identical tree)
- mutation: AC1 `TRUSTEDOUTPUTRECENTACTIVITY=0` -> `TestRecentActivityRow` red (trusted output, and the table row of recent_activity).
- mutation: AC1 `Splice` drops the final newline -> `TestSplice` red (LF and CRLF with a final newline: the replaced text, the end of the text, the second splice).
- mutation: AC2 `Model()` omits the `WithOrdersData` grant -> `TestDemoOnlyGrantsListed` red (the demo-only list and the section row); `TestPrivilegesMatchSecurityRecords` red as well.
- mutation: AC3 `CLASSIFICATIONRECENTACTIVITY="risky"`, overview not regenerated -> `ci/iris.sh live security-overview` exits 1 with `DRIFT tool recent_activity` and the diff of the region.
- mutation: AC3 the generator skips `OcuTalon.Tools.Watch` -> `TestToolsMatchRunners` red (DiagnosisAgent), and `TestToolRows` red.
- mutation: AC4 `Model()` omits `%Ens_MessageResend` -> `TestPrivilegesMatchSecurityRecords` red (OcuTalonServiceRole).
- mutation: AC5 the statement names `TestToolInventoryX` -> `TestInventoryStatement` red (the fixed statement, and the line in the section).
- mutation: AC6 `step_overview` ignores the exit code -> the fail and busy cases of `test-release-sequence.sh overview` red (exit, line, NEXT ipm, record, WAIT).
- mutation: AC3 `ToolRows` reads the toolsets of the package `OcuTalon.Test.Install.ZzGrant` instead of `OcuTalon.Tools.` -> `TestToolsetScope` red ("every row is a tool of one of those toolsets"), `TestToolRows` and `TestToolsMatchRunners` red as well.
- mutation: AC5 `Classification` drops the rule text (`Quit "per call"`) -> `TestClassifyHookShowsItsRule` red (own hook, class-wide hook).
- mutation: AC4 `FixKindRows` gives an empty `resources` -> `TestFixKindRows` red (the RESOURCES of `RepairResend`, and the table row).
- mutation: AC5 `NonAscii` returns "" -> `TestAscii` red (control: a character outside ASCII is found).
- mutation: AC3 `Regenerate` writes the text it read, not the spliced text (the `--write` path) -> `TestRegenerate` red (its bytes are those of Splice of the same text; the hand-written lines kept; the status names the marker).
- mutation: AC4 `SqlRows` names `Ens.MessageBody` in OCUTALON -> `TestPrivilegesMatchSecurityRecords` red (the trace role's SQL privileges are the listed SELECT rows), and `TestDemoOnlyGrantsListed` red.
- mutation: AC4 `Applications` drops the last application role -> `TestPrivilegesMatchSecurityRecords` red (`/ocutalon` and `/ocutalon/api` add the listed roles), and `TestDemoOnlyGrantsListed` red.
- mutation: AC4 `ReadUser` (the test's reader) reports the inverse of `Enabled`, standing for a service user whose login is on, since this story changes no security record -> `TestPrivilegesMatchSecurityRecords` red (`OcuTalonService has login disabled`).
- mutation: AC6 `step_overview` does not hand the lane lock folder to the unit -> the pass case of `test-release-sequence.sh overview` red (the stub's recorded folder).
- mutation: AC3 `drift` prints `DRIFT <key>x` -> `test-release-sequence.sh overviewdrift` red (fix-kinds and privileges cases).
Each mutation above was applied, run on the warm stack (or in the shell suite), observed red, and reverted from a private copy; `git status` and `git diff` were identical before and after, and the class passed again.

**Shared surfaces:**
- `ci/units.sh`: the `production` group membership, `NO_WEB_BUNDLE_UNITS` and `IRIS_INPUT`, checked by `test-ci-config.sh` and `test-ci-changes.sh`;
- `release/release.sh` `STEPS`, pinned by `test-release-sequence.sh`;
- `Install.Step.Roles.Compose` visibility.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Install.SecurityOverview` (`Model`, `Sections`, `Splice`, `Regenerate`) generates the tools, fix-kinds and privileges sections of `docs/security-overview.md` from `%AI.Catalog`, the tool and fix-kind parameters and the composed `Grants()`. The committed file was written by the real generator (`--write` through the live unit). `live:security-overview` compares the committed sections with a fresh generation (`DRIFT tool <name>`), `OcuTalon.Test.Install.SecurityOverview` checks the rows, splice, runner inventory and security records, and the release sequence has a new step `overview` that runs `release/security-overview.sh`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- new generator.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls` -- `Compose` made public (footprint extension).
- `src/ocutalon/cls/OcuTalon/Test/Install/SecurityOverview.cls`, `Test/Install/ZzOverviewRule.cls` -- tests and a Classify-rule fixture.
- `docs/security-overview.md` -- generated sections plus Story 14.2 placeholders.
- `docker/tests/test-security-overview.sh`, `docker/tests/lib-security-overview.sh` -- the live unit and its drift helpers.
- `release/security-overview.sh`, `release/release.sh` -- the callable unit and step `overview`.
- `docker/tests/test-release-sequence.sh` -- order pin, `NEXT overview`, rules `overview`, `overviewunit`, `overviewdrift` (footprint extension).
- `ci/units.sh` -- three new entries only.

**Review.** Four layers. Patches applied: 4 medium rows (real unit run hermetically, lock folder hand-off pinned, `Regenerate` test, drift lines tested hermetically) and 4 low rows (mutation lines, per-call tool checks, helper divider, `git archive` pipe status). Deferred: none new (the privilege-reader copy was already listed). Rejected: 17 low rows with their reasons in the Review Triage Log.

**Follow-up review recommended: true** (four medium patches in a first pass). Unverified risk: the new hermetic rules `overviewunit` and `overviewdrift` and the extraction of `region`/`tool_rows`/`drift` into `lib-security-overview.sh` were verified only by their own green runs and mutations, not re-reviewed.

**Verification.** Warm class run of `OcuTalon.Test.Install.SecurityOverview`, `ci/iris.sh live security-overview` (PASS), `test-release-sequence.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-boundaries.sh`, `test-class-rules.sh` all green after the last patch. Once-lines: `Install.Registry`, `Install.Tools`, `Watch.Grant`, `Agent.Runners` and `release/security-overview.sh` (`PASS overview`) passed before the review patches (none touches the patched files); the `lane-a@Checks,Install,Watch` shard parts 1/2 and 2/2, forward and `--reverse`, passed (18 classes each) after the last patch. All throwaways and the warm stack were torn down.

**Residual risks.** `step_overview` against a real candidate was exercised only through the stubbed hermetic test. Neither new unit has run in actual CI. The stale comment in `ci/iris.sh` about which live units read arguments was left alone (outside the footprint). The `Enabled` mutation of the privilege test only inverts the test's own reader.
