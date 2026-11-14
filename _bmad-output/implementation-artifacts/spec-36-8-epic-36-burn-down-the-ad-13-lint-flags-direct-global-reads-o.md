---
title: 'Story 36.8: Epic 36 burn-down: the AD-13 lint flags direct global reads of product storage in web-process classes'
type: 'chore'
created: '2026-11-14'
status: 'ready-for-dev'
baseline_revision: '0faed5df3a39fb05a541809388d9a926448957e1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
warnings: ['oversized']
deferred:
  - summary: 'Four web-class methods open or test Data.Session rows directly (generated RefIndexOpen/RefIndexExists over the Session extent); reported by Story 36.8, not fixed, held in BASELINE_WEB_READS'
    evidence: 'Web/Api.cls:1556 CurrentSession, Web/Live.cls:163 Frame, Web/Live.cls:195 Heartbeat open the caller''s own Session row keyed by Ownership.SessionRef; Web/Hook.cls:110 Authenticated tests that a webhook''s owning session exists. None reads beyond the caller''s own row, but each is the %OpenId form AD-13 (DW-1278 amendment) names. Moving them behind Ownership or Data.Session is not a one-line move the 17:10Z ruling covers.'
    location: 'src/ocutalon/cls/OcuTalon/Web/{Api,Live,Hook}.cls'
    severity: 'low'
  - summary: 'The lint cannot see reads made by methods the web process calls in other packages; measured at 36.8: five depth-1 and two depth-2 callee reads'
    evidence: 'Core.SettingsOps.Heartbeat:499 Data.Setting.KeyIndexExists; Live.Publish.LastSeq:48-51 ^OcuTalonP.LiveEventC (lock and $Get); Live.Publish.WakeName:59 $Name(^OcuTalonP.LiveWake) (a resource name, never read); Live.Publish.RefreshGuide:145 Data.Session.RefIndexOpen; Watch.Summary.Text:133 Data.Incident.RefIndexOpen; SettingsOps.Values and .Persona reach SettingsOps.Stored:266 Data.Setting.KeyIndexOpen. DW-1278''s own case (SettingsOps.OnCallUsers walking the Session and Pairing globals) was this shape, so the web-scoped rule would not have caught it.'
    location: 'src/ocutalon/cls/OcuTalon/{Core/SettingsOps,Live/Publish,Watch/Summary}.cls'
    severity: 'low'
---

<intent-contract>

## Intent

**Problem:** AD-13, as the DW-1278 ruling amended it, counts a web-process read of product storage that bypasses the owning class (walking a `^OcuTalonP.*` global, or `%OpenId` over another class's extent) as an unchecked path. The class-rules lint checks only unchecked SQL prepares, so nothing in CI catches such a read (DW-1287).

**Approach:** Add a rule `web-global-reads` to `docker/tests/test-class-rules.sh`. It flags, in every class of the package `OcuTalon.Web` and its sub-packages, each code-line reference to a product storage global and each generated row-access call on a product class, naming file:line, Class:Method and what is read. An empty allow-list `ALLOW_WEB_READS` (Class:Method) and a baseline `BASELINE_WEB_READS` (Class:Method:Target) both carry stale checks. The baseline names the four reads in the current tree, so the tree passes while any new read fails. Synthetic samples include a planted violation, and recorded mutations prove the rule works. No product code changes.

## Boundaries & Constraints

**Always:**
- Product storage globals are the names that start `^OcuTalonP.` or `^OcuTalonBP.`, including an extended reference (`^|"ns"|OcuTalonP.x`, `^["ns"]OcuTalonP.x`) and a name written inside a string literal (an indirection target). The match is case-sensitive, as global names are. A process-private `^||OcuTalonP.x` is not one.
- The product classes are the `class` column of `src/short-names.tsv`. Their row-access forms are `%OpenId`, `%ExistsId`, `%Open`, `%Exists` and `<Index>Open` / `<Index>Exists` for each `Index` declared in that class's file. A call is flagged when it is written `##class(<product class>).<form>(` or `$ClassMethod("<product class>", "<form>"`. Class and method are matched in any case.
- Web-process classes are those whose `Class` line names `OcuTalon.Web` or `OcuTalon.Web.<anything>`, matched by whole package name. `OcuTalon.Webhook.X` and `OcuTalon.Test.Web.X` are out of scope.
- Comment lines are not code (SCAN_COMMON's blanking). A failing hit prints `file:line Class:Method Target` and never the line's text.
- Every allow-list or baseline entry that matches no hit fails as stale, named at its line in the script (`name_stale`).
- Reuse `SCAN_COMMON`, `write_class`, `expect_flagged`, `expect_clean` and `name_stale`. The existing rules' output and samples stay byte-identical.

**Never:**
- Change any file outside `docker/tests/test-class-rules.sh`. That means no fix to the four baseline reads and no edit to the spine or `epics.md`.
- Scan methods in other packages that the web process calls (see Design Notes, known limit).
- Flag writes in object form (`%DeleteId`, `%Save`), `^OcuTalonPublic` (the `public-global` rule already owns it), `^OcuTalon.<x>` runtime globals, or Ens message extents.
- Use a newline in an awk `-v` value, which BSD awk rejects. Join with `;` or a space, as the existing allow-lists do.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Global read in a web class | `OcuTalon.Web.ZzA:Run` holds `$Order(^OcuTalonP.SessionD(id))` | `<file>:<line> OcuTalon.Web.ZzA:Run ^OcuTalonP.SessionD` | rule FAILs |
| Other global forms | `$Get(^OcuTalonBP.DecisionD(1))`, `$Data(...I(...))`, `Merge x = ^OcuTalonP...`, `"^OcuTalonP.SessionD"`, `^\|"OCUTALON"\|...`, `^["OCUTALON"]...` | one hit per line, target without the namespace part | FAIL |
| Row-access forms | in `OcuTalon.Web.Public.ZzB`: `%OpenId`, `%ExistsId`, `%Open`, `%Exists`, `RefIndexOpen`, `RefIndexExists`, a lower-case class name, `$ClassMethod("OcuTalon.Data.Session", "%OpenId", id)` | 8 hits | FAIL |
| Sanctioned calls | `Data.Webhook.ForSession`, `Data.Ownership.Rows`, `Data.Session.SignOuts`, `^Ens.Runtime`, `@store@(id)`, `^\|\|OcuTalonP.X`, `%Dictionary.CompiledXData.%OpenId` | no hit | none |
| Out of scope | the same reads in `OcuTalon.Data.Session`, `OcuTalon.Webhook.ZzX`, `OcuTalon.Test.Web.ZzX`, or on comment lines | no hit | none |
| Allow-list | sample entry `OcuTalon.Web.ZzAllowed:Run`, method holds a read | no hit; with the method absent, `allow-list:` stale line | stale FAILs |
| Baseline | sample entry `OcuTalon.Web.ZzKnown:Run:OcuTalon.Data.Session.RefIndexOpen` | that read passes; a `%OpenId` added in the same method is flagged; with the read gone, `baseline:` stale line | FAIL on new or stale |
| Real tree, today | `src/**/*.cls` at baseline_revision | `PASS web-global-reads: ...` | none |

</intent-contract>

## Code Map

- `docker/tests/test-class-rules.sh:3-40` -- the header list of rules. Add a `web-global-reads (AD-13, DW-1287)` bullet in the same style.
- `:51-62` -- `ALLOW_UNCHECKED` / `SAMPLE_ALLOW` and `ALLOW_CONCAT=""` / `SAMPLE_ALLOW_CONCAT`, the pattern for `ALLOW_WEB_READS=""`, `SAMPLE_ALLOW_WEB_READS`, `BASELINE_WEB_READS` and `SAMPLE_BASELINE_WEB_READS`.
- `:124-177` `SCAN_COMMON` -- tracks `clsAt[]`/`memberAt[]` per line, blanks comment lines, and holds `allowed()` with the `-v stale=1` "allow-list:" report. The new scanner extends it with a baseline array keyed `tolower(cls:member:target)` and its own `baseline:` stale lines. SCAN_COMMON itself stays unchanged.
- `:181-223` `unchecked_prepares`, `:228-279` `assert_concat` -- the shape for a SCAN_COMMON-based scanner: `-v allowlist="$(... | tr '\n' ' ')"` plus a caller-defined `process()`.
- `:426-436` `name_stale` -- maps `allow-list:<entry>` to `docker/tests/test-class-rules.sh:<n> stale allow-list entry <entry>`. Extend it so `baseline:<entry>` maps to `... stale baseline entry <entry>`, keeping the existing output unchanged.
- `:423-521` the unchecked-prepare block -- the template for the new block: swap the real lists for the sample lists, run the samples, check stale entries, restore, then scan the real tree with `STALE=1 ... | name_stale` and print PASS/FAIL.
- `docker/tests/lib-scan.sh:13` `scan_files` -- lists the tracked and unignored files, so an untracked planted class under `src/` is scanned too (used by the planted check in Verification).
- `src/short-names.tsv` -- the registry (`short global class lane`, 40 rows). `test-storage.sh` keeps its `class` column equal to the set of classes with `DEFAULTGLOBAL`, and keeps every storage location under `^OcuTalonP.`/`^OcuTalonBP.` (rules registry-row, registry-class, prefix, locations). Measured: this set equals the 40 classes whose `DataLocation` is under those prefixes.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls` -- `Index RefIndex` produces `RefIndexOpen` / `RefIndexExists`, the generated forms in the baseline.
- `src/ocutalon/cls/OcuTalon/Web/**` (22 classes, read-only) -- the scanned set. No web class extends a non-web OcuTalon class, so inheritance hides no product code from the scan.
- `ci/checks.sh` + `ci/units.sh:6` (read-only) -- `CHECK_SCRIPTS` holds `class-rules`, so the hosted `checks` job runs the script from the repository root. No change there.

## Tasks & Acceptance

**Execution:**
- `docker/tests/test-class-rules.sh` -- add the rule after the unchecked-prepare block:
  - a helper `product_classes` that prints `Class Idx1 Idx2...` per registry row, joined with `;` for awk;
  - the scanner `web_reads <file>...`, using SCAN_COMMON, a `-v products`, `-v allowlist`, `-v baseline` and `-v stale`, and printing `file:line Class:Method Target` (Target is `^OcuTalonP.X` / `^OcuTalonBP.X`, or `<Registry spelling of the class>.<method as written>`);
  - the lists, with `BASELINE_WEB_READS` holding exactly the four entries listed in Design Notes;
  - the samples and checks from the I/O matrix, including an exact-output check that the planted `ZzA` read is named as `file:line OcuTalon.Web.ZzA:Run ^OcuTalonP.SessionD`, and a real-tree guard that `product_classes` lists all 40 registry classes, with `OcuTalon.Data.Session` carrying `RefIndex`;
  - the real-tree scan and PASS/FAIL line, plus the `name_stale` extension and the header bullet. Then run the script and record the mutations.

**Acceptance Criteria:**
- Given a web-process class holding a direct read of a product storage global or a row-access form on a product class (the I/O matrix rows), when `bash docker/tests/test-class-rules.sh` runs its samples, then each is flagged with file:line, Class:Method and the target, and a mutation that disables the new check turns the samples red.
- Given the tree at baseline_revision, when the script runs from the repository root as `ci/checks.sh` runs it, then it prints `PASS web-global-reads: ...` and `test-class-rules: all rules passed` and exits 0. Every other rule's PASS line is unchanged.
- Given one baseline entry removed, when the script runs, then it exits 1 naming that read's file:line, Class:Method and target. Given an added entry that matches nothing, it exits 1 naming the stale entry at its script line.
- Given an untracked planted class `src/ocutalon/cls/OcuTalon/Web/ZzPlanted.cls` with `Set id = $Order(^OcuTalonP.SessionD(""))` in `ClassMethod Run()`, when the script runs, then it exits 1 naming `src/ocutalon/cls/OcuTalon/Web/ZzPlanted.cls:<line> OcuTalon.Web.ZzPlanted:Run ^OcuTalonP.SessionD`. Once the file is deleted, the script exits 0 again.
- Every test added or changed passes on a fresh environment, in either order. All samples live under the script's `mktemp` folder, which is removed on exit.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs.**
- AD-13: "no other unchecked path" includes direct global reads, by the DW-1278 amendment (spine line 481).
- AD-3: private prefixes, the short-name registry and the `test-storage.sh` prefix rules.
- AD-19: `^OcuTalonPublic` belongs to `Data.Public.Settings`, under the existing `public-global` rule.
- AD-29: `docker/` is Lane B's, and this story touches no other lane's file.

Rule 3 does not apply: this is non-user-facing CI tooling. Rule 1: the story adds no service. Consumes: `ci/checks.sh` (existing, unchanged). Extends (Rule 2): `SCAN_COMMON`, `name_stale`, and the `ALLOW_UNCHECKED`/`ALLOW_CONCAT` list pattern. There is no copy.

**Inbox.** DW-1287 (owned) is addressed for web classes. The callee residual is reported in `deferred:`.

**Scope, and what a static lint cannot see (known limit, for the Planner).** The rule scans only web-process classes. "A method the web process calls" (AD-13) is not checked. A depth-1 scan of literal `##class(X).M(` calls is possible, but it would miss:
- `..M()` chains inside the callee (SettingsOps.Values reaches `Stored`, which opens Setting rows);
- instance calls such as `obj.M()`;
- `$ClassMethod` and indirection with non-literal names, and `Xecute`.

It would also bind other lanes' classes (Core, Live, Watch) and Ownership's other accessors (Ownership opens rows in methods other than `Rows`, such as line 306). The second `deferred:` item lists what a depth-1/2 scan measured today. The web-scoped rule also cannot see indirection through a computed, non-literal name, or a class name held in a variable.

**Why an empty allow-list.** The owning classes' methods and `Ownership.Rows` live outside `OcuTalon.Web`, so the rule never scans them. A call from a web class to a hand-written method such as `Data.Webhook.ForSession` or `Ownership.Rows` is never flagged, because only generated row-access forms are. Listing them would fail the stale check by construction. `ALLOW_WEB_READS` is therefore for web-class methods the Planner sanctions, and it is empty today, like `ALLOW_CONCAT`.

**Why a separate baseline.** The baseline holds reported reads that have not been accepted. Its key is `Class:Method:Target`, so a new, different read in a baselined method still fails. A repeat of the same target in the same method passes (accepted limit). An entry leaves the baseline in the change that moves its read.

**Existing violations (reported, not fixed).** Measured with a scratch prototype of the rule over `src/**/*.cls` at baseline_revision. There are no direct global references in any web class: the only globals web classes name are `^Ens.Runtime` (Documents.cls:234) and `^%cspSession` through indirection (Public/Status.cls:129-139).
- `OcuTalon.Web.Api:CurrentSession:OcuTalon.Data.Session.RefIndexOpen` (Api.cls:1556): opens the caller's Session row, keyed by `Ownership.SessionRef`.
- `OcuTalon.Web.Live:Frame:OcuTalon.Data.Session.RefIndexOpen` (Live.cls:163): the same, for the WebSocket frame.
- `OcuTalon.Web.Live:Heartbeat:OcuTalon.Data.Session.RefIndexOpen` (Live.cls:195): the same, for the keep-alive frame's epoch.
- `OcuTalon.Web.Hook:Authenticated:OcuTalon.Data.Session.RefIndexExists` (Hook.cls:110): tests that the webhook's owning session exists.

None of these is a one-line move the 17:10Z ruling covers (that ruling covered only 36.4's `OnCallUsers`), so none is fixed here. The open branches OCT-epic11, 22 and 26 add no web-class change against the feature branch, so the rule fails no other lane's open work.

**Decisions for the Planner (veto items, not decided here).**
- (V1) Extend the rule to the web process's callees: depth-1 literal calls plus same-class `..M()` chains, with its own baseline. Recommendation: yes, as a follow-on story after this merges, because DW-1278's own case was a callee read. It needs a ruling on whether all of Ownership's accessors (not only `Ownership.Rows`) are sanctioned, and that is AD-13 wording.
- (V2) After merge, the spine's sentence "The CI check above still covers only SQL prepares; extending it to direct global reads in web classes is DW-1287" is stale. Recommendation: the lead amends it to name `web-global-reads` and its web-class scope (Rule 20). That is an AD wording change.
- (V3) The four baseline reads. Recommendation: route them to one follow-on that moves the three own-Session opens behind an Ownership accessor (Ownership.SessionRef already resolves the row's key) and the Hook existence check behind its owning class, deleting each baseline entry. The alternative is to sanction them in `ALLOW_WEB_READS` as own-row reads.

## Verification

Shared surfaces: the script's set of PASS/FAIL lines (one new line; `ci/checks.sh` prints them and asserts no count); `SCAN_COMMON` and `name_stale` (shared with unchecked-prepare and assert-concat, whose output must not change).

**Commands:**
- `bash docker/tests/test-class-rules.sh` -- expected: exit 0. Nine PASS lines: the eight existing ones, byte-identical to baseline_revision's, plus `PASS web-global-reads: ...`.
- `bash -n docker/tests/test-class-rules.sh && LC_ALL=C grep -n '[^ -~	]' docker/tests/test-class-rules.sh` -- expected: syntax OK, no non-ASCII byte (Rule 14).
- Planted check (AC 4): write the planted class, run the script (expect exit 1 and the named line), delete it, run again (expect exit 0), then confirm `git status --short` is as before.

**Mutations (Rule 19; apply, observe red, revert, confirm `git status --short` and `git diff --stat` are unchanged):**
- mutation: make `web_reads`' `process()` return at once (the new check disabled) → `FAIL web-global-reads: the scanner does not flag the sample` on every bad sample (AC 1).
- mutation: change the global pattern's `OcuTalonB?P\.` to `OcuTalonXP\.` → the `ZzA` samples and the exact-name check go red (AC 1).
- mutation: drop the `##class(...)` form match → the `ZzB` sample's count of 8 goes red (AC 1).
- mutation: delete the `OcuTalon.Web.Hook:Authenticated:...` baseline entry → the real-tree scan FAILs naming `src/ocutalon/cls/OcuTalon/Web/Hook.cls:110 OcuTalon.Web.Hook:Authenticated OcuTalon.Data.Session.RefIndexExists` (AC 2, 3).
- mutation: add `OcuTalon.Web.Api:Gone:OcuTalon.Data.Session.RefIndexOpen` to the baseline → FAIL `stale baseline entry` at its script line (AC 3).
- mutation: key the baseline by `Class:Method` only → the `ZzKnown` known-plus-`%OpenId` sample goes red.
- mutation: match the web package by prefix (`OcuTalon.Web` without the dot) → the `OcuTalon.Webhook.ZzX` clean sample goes red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none (halted after planning, as the invocation directed)
