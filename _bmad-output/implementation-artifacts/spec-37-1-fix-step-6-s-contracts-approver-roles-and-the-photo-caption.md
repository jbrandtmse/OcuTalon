---
title: "Story 37.1: Fix step 6's contracts: approver roles and the photo caption"
type: 'feature'
created: '2026-11-12'
status: 'done'
baseline_revision: '6ca4386e502ce25848e2251823e2444f90817061'
baseline_commit: '6ca4386e502ce25848e2251823e2444f90817061'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-37-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 6's feature epics (25: Lane B's Roles section, the role check in `AnswersIn`, the file replies; 26: Lane A's file reading, photo captions and approver roles) need fixed names before either lane can build. Today the spine leaves the approver kinds to step 6 (Deferred), nothing maps an approval row (`fix`, `tool_call`, `setting`) to an `OcuTalonApprover_<kind>` role, the photo-caption request and the read result that Story 25.6 renders (DW-1231) are named nowhere, and no `MayAnswer` or role-assignment method exists in code.

**Approach:** Write Lane A's step 6 contracts into `ARCHITECTURE-SPINE.md` as additive bullets and rows (the full list and text are `### Spine edits` and `### Spine content`), and land the cross-lane APIs as compiling signatures pinned in `Test.Contract.Ac`: `Approval.MayAnswer` (an interim body that answers today's rule, so no answer changes before Story 26.4), and the stubs `Install.Step.Roles.Assign`, `Install.Step.Roles.Holders` and `Agent.Input.ReadFile`.

## Boundaries & Constraints

**Always:**
- Spine additions are unions: new bullets, rows and clauses, each marked `[ADDED <date of the change>, Story 37.1]` (or `[AMENDED ...]` for the one Deferred row removed); existing sentences stay word for word; `lint_spine.py` adds no finding to the pre-existing low `placeholder` ones; refresh the frontmatter `updated:`.
- `MayAnswer` answers exactly the rule `Answer` applies today (the row's `RequiredRole` in the user's recursed role set, through `HoldsRole`), writes nothing and fires nothing; `kind` is "" until Story 26.4.
- `Assign` and `Holders` answer "not implemented" (`$$$ERROR($$$NotImplemented)`, code 5003) and change and read nothing; `changed` is 0 and `users` is `[]`. `ReadFile` answers 5003 with `result` `{}` and opens no file.
- No bridge class names another OcuTalon package or a role literal beyond what it has today; ASCII only in every file written; no local machine path.
- Every new signature is pinned in `OcuTalon.Test.Contract.Ac`.

**Never:**
- Edit a Lane B file: `Core/**` (`AnswersIn`, `AnswerOps`, `SettingsOps`, `Conversation`, `Files`, `SecretHandoff`), `Web/**`, `web/**`, `Msg/Enum.cls`, `Msg/Catalog.cls`, `Msg/Catalog/Core.cls`, `Msg/Command/**`, `Data/**` (Lane B's), `Live/**`, `Test/Core/**`, `Test/Web/**`, `Test/Data/**`, `Test/Msg/**`.
- Build any step 6 behaviour: no role, resource or grant created; no `ApproverKind` column; no `Install.Step.Users` role change (the demo and README accounts keep today's roles); no change to `Approval.Answer`, `Raise`, `HoldsRole`, `Decide`'s `ApprovalRole` default, `Bridge.Audit`, `Agent.Input.Render`, `READSFILES`, any fix kind, `Bridge.Msg.Enum` or `Bridge.Ext.*`.
- Add user-visible text, a production item, a table, an enumeration value, a REST route or an `AD-n` id; touch `Test/Bridge/CodeRules.cls`, `Fix/**` or `ci/units.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| MayAnswer, holder | A pending row with `RequiredRole` `OcuTalonUser`; `MayAnswer(ref, "ocutalon", .kind)` (the README account) | 1, `kind` "" | none |
| MayAnswer, no role | Same row; user `OcuTalonWorkflow` (no roles) | 0, `kind` "" | none |
| MayAnswer, role nobody holds | A row with `RequiredRole` `ZzNobody<n>`; user `ocutalon` | 0 | none |
| MayAnswer, no row | A well-formed unknown Ref; a malformed Ref `"x"`; an empty user | 0, `kind` "" | no error, no throw |
| MayAnswer writes nothing | Any call above | The row's `State`, `Answered*` fields and the table's row count are unchanged; no event, no audit entry | none |
| Assign stub | `Assign("ocutalon", "OcuTalonApprover", 1, .changed)`, and `Assign("ocutalon", "%All", 0, .changed)` | Error 5003; `changed` 0; the user's recursed role set is unchanged | Caller (Story 25.4's `SettingsOps`) shows its not-built path |
| Holders stub | `Holders(.users)` | Error 5003; `users` is `[]` | as above |
| ReadFile stub | A fixture `Msg.Item` with `FileRef` (a well-formed Ref), `SessionRef`, `FileMediaType` `application/pdf` | Error 5003; `result.%ToJSON()` is `{}` | Never reached in the product before Story 26.2 (`Core.Files.Readable()` is 0) |
| Consumer call (Integration) | Code outside the class calls each method by the spine's name and argument order | Compiles; answers as the rows above; `Test.Contract.Ac` pins all four | A renamed argument fails `Test.Contract.Ac` |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- the contract (519 KB; read only the anchors). Anchors (this tree): AD-11 390-418 (approval-role bullet 409; Story 22.4's MCP rows bullet 417, which Epic 22 amends); AD-17 574-584 (the "their role (from step 6)" bullet 580); AD-21 731-834 (extraction bullet 747, memory names 749, learned saves 764); AD-24 916-946 (role list 921, the online demo account bullet 941, already saying "from step 6 `OcuTalonApprover`"; FORBIDDEN bullet 943); AD-29 1044-1099 (contract epics 1054); AD-31 1123-1145 (extension list; the `ClassFor` bullet 1138); Conventions: "Citations and memories" 1223, "... on the page" 1224, "Approval requests" 1248; Ownership cross-area table rows of Story 25.3 at 1493-1494; Deferred row "Approver kinds and per-kind checks" 1724. No `.memlog.md` exists in the spine folder (Story 25.3's Task 0): do not create one.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- `IsRef` :288 (public), `Answer` doc :305-321 and `AnswerLocked` :352/:358 (the role check), `HoldsRole` :393-407 (private; `GetUserRecursedRoleSet`), row open by `ApprovalRequest.RefIndexOpen(ref)` (:577). `MayAnswer` goes right after `HoldsRole`.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- `RequiredRole` MAXLEN 128 (:37), `Kind`, `FixKind`; read only (Story 26.4 appends `ApproverKind`; Epic 22 appends `ToolFingerprint` at storage slot 26 first).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:139, :264-267` -- `ApprovalRole` setting, `InitialExpression = "OcuTalonUser"` (the only seed); read only.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls` -- `Compose`/`Add`/`Apply`, `FORBIDDEN` (pinned by `Test/Install/Registry.cls:628`); add `Assign` and `Holders` as stubs, nothing else changes.
- `src/ocutalon/cls/OcuTalon/Install/Step/Mcp.cls:55-70` -- `Grant`/`Revoke`: the sibling for a public run-time privilege method in an installer area (`%SYS` switch, error names the input); read only.
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls` -- `ROLES` :37 (README account `ocutalon`), `DEMOROLES` :46, `READONLYROLES` :49, `EnsurePublic` :350-357 rewrites the public accounts' roles at every start; read only (Story 26.4).
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls` -- `Render` :44 (Lane A); add `ReadFile` stub after `Render`'s helpers; `READSFILES` stays absent (Story 26.2).
- `src/ocutalon/cls/OcuTalon/Docs/Extract.cls` -- `Read` :72 (`{ok, reason}` codes), `Failure(code, size)` :159; read only (the read result's `reason` and `text`).
- `src/ocutalon/cls/OcuTalon/Core/AnswersIn.cls` (Lane B; `TelegramCode` :113-116 puts `row.Kind` in the `not_allowed` slot `kind`), `Core/AnswerOps.cls:58`, `Core/SettingsOps.cls` (`Save`, `AuditData` :222, `SecretHandoff.Take` :1470), `Core/SecretHandoff.cls` (`Put` :25, `Take` :51, `Discard` :76), `Core/Conversation.cls` (`Begin` :389 no-reader branch, `Sourced` :611 HostData carry), `Web/Public/Shell.cls:27,145` (post-sign-in check by role name) -- read only: the consumers' seams the spine text names.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls` -- `XData Signatures` :299-392, 89 entries; floor `count >= 85` at :165; stale class-doc count at :21 ("85 signatures"). Entry form `{"class","method","args","returns"}`, output args `*name`, trailing defaults left out.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls` -- the sibling test of Lane A's cross-lane stubs (Story 0.6); extend it (doc :1-3 says no Approval stub is left).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ApprovalRows.cls` -- `NewRow(kind, ...)` :13 and `Save(row, state, expiresIn, answerer, .ref)` :47 (sets `RequiredRole` `OcuTalonUser`), `ANSWERER = "ocutalon"`; the test's row fixture. No delete helper: the test deletes its rows by Ref.
- `docker/tests/test-class-rules.sh` (bridge-refs, `lib-scan.sh:83-96`), `docker/tests/test-boundaries.sh` (ASCII) -- static checks.
- `ci/units.sh:18-23` -- `Test.Bridge.*` and `Test.Install.*` run in shard lane-a, `Test.Contract.*` in lane-b; no edit (no new class).

## Tasks & Acceptance

**Execution:**
- [ ] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- apply S1 to S9 of `### Spine edits` with the text of `### Spine content`, each at its anchor with its marker; remove the Deferred row of S8; set `updated:`; run `lint_spine.py` until it reports no new finding -- the AC's spine update (Rules 6, 20).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- add after `HoldsRole`: `ClassMethod MayAnswer(ref As %String, irisUser As %String, Output kind As %String) As %Boolean` with body: `Set kind = ""`, quit 0 unless `..IsRef($Get(ref))`, open the row by `RefIndexOpen`, quit 0 when there is none, else `Quit ..HoldsRole($Get(irisUser), row.RequiredRole)`. Doc comment states the S1 contract and "Until Story 26.4 it answers today's rule (the row's RequiredRole), kind empty". Add one line to the class doc's list. -- AC 2; demo path unchanged.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls` -- add `ClassMethod Assign(userName As %String, role As %String, grant As %Boolean, Output changed As %Boolean) As %Status` (`Set changed = 0`, `Quit $$$ERROR($$$NotImplemented)`) and `ClassMethod Holders(Output users As %DynamicArray) As %Status` (`Set users = []`, 5003); doc comments state S2's contract and "A stub until Story 26.4"; one class-doc line naming them. -- AC 2.
- [ ] `src/ocutalon/cls/OcuTalon/Agent/Input.cls` -- add `ClassMethod ReadFile(item As OcuTalon.Msg.Item, Output result As %DynamicObject) As %Status` (`Set result = {}`, 5003); doc comment states S4's read-result contract and "A stub until Stories 26.2 (documents) and 26.3 (photos)"; one class-doc line. -- DW-1231.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls` -- append four entries: `{"class": "OcuTalon.Bridge.Approval", "method": "MayAnswer", "args": "ref,irisUser,*kind", "returns": "%Boolean"}`, `{"class": "OcuTalon.Install.Step.Roles", "method": "Assign", "args": "userName,role,grant,*changed", "returns": "%Status"}`, `{"class": "OcuTalon.Install.Step.Roles", "method": "Holders", "args": "*users", "returns": "%Status"}`, `{"class": "OcuTalon.Agent.Input", "method": "ReadFile", "args": "item,*result", "returns": "%Status"}`; raise the floor to 93 and correct the class-doc count to the real total. -- AC 2 pin.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls` -- add `TestMayAnswer` (every MayAnswer row of the I/O matrix, rows made with `ApprovalRows.NewRow("tool_call")` and `Save(row, "pending", , , .ref)`, plus one row whose `RequiredRole` is set to `ZzNobody<n>` after `Save` (open it by `ApprovalRequest.RefIndexOpen(ref)`, set the property, `%Save()`); "writes nothing" by comparing `State`, `AnsweredBy`, `AnsweredAt` and `SELECT COUNT(*)` before and after; rows deleted by Ref in a cleanup that also runs after a failure), `TestRoleStubs` (Assign twice and Holders, with the README account's `$SYSTEM.Security.GetUserRecursedRoleSet` equal before and after) and `TestReadFileStub`; update the class doc (MayAnswer is interim until Story 26.4; Assign, Holders and ReadFile are stubs). -- matrix, Rule 19.

**Acceptance Criteria:**
- Given the spine after the edits, when the reviewer reads it against `### Spine edits` and `### Spine content`, then S1 to S9 are present at their anchors with their markers, no pre-existing sentence of a Rule, Binds, Prevents or convention row changed, the Deferred row of S8 is gone, and `lint_spine.py` reports no finding beyond the pre-existing low `placeholder` ones.
- Given the spine's AD-11, AD-24, AD-17, AD-21 and AD-31 additions, when a Lane B author reads them, then they name, with final spelling: the approver kinds and the row-to-role mapping, `OcuTalonApprover`, the seven `OcuTalonApprover_<kind>` roles, `OcuTalonViewer` and the same-named resources; that `setting` rows (persona proposals) keep today's rule; how they take over from `ApprovalRole`; the online demo account's and the README account's `OcuTalonApprover`; `MayAnswer`, `Assign`, `Holders` and their personal-data handoff; the photo-caption request; and the read result (`fileRef`, `kind`, `read`, `reason`, `text`, `chars`, `cut`, `addable`) and the HostData member `caption` (`memoryRef`, `text`) that Story 25.6 renders (DW-1231).
- Given the compiled package, when Lane B code calls `Approval.MayAnswer`, `Install.Step.Roles.Assign`, `Install.Step.Roles.Holders` or `Agent.Input.ReadFile` by the spine's names, then each compiles and answers as the matrix says, `Test.Contract.Ac` pins all four signatures, `Test.Bridge.Api` passes, and `test-class-rules.sh` (bridge-refs) passes.
- Given the online demo or a local install running this change, when any user answers an approval request or sends a file, then nothing behaves differently: no role, resource, grant, account, setting or row changes, and `Test.Bridge.Approval` and `Test.Install.Registry` pass unchanged.

### Review Findings

Code review 2026-11-13 (story's first review; four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; tier full-opus, no model override). Rule 3: exempt (no user-facing surface: stubs, an interim pre-check and spine text). The spine patches below change only this story's own `[ADDED 2026-11-13, Story 37.1]` bullets, no pre-existing sentence; where they differ from `### Spine content`, the Planner rulings V3, V4 and V6 govern and the spine is the contract.

- [x] [Review][Patch] HIGH (ruling V3) `Holders` was not stated admin-only or refused on the online demo; V3 rules "Assign/Holders: admin-only ... refused on the demo" [ARCHITECTURE-SPINE.md AD-24 S2, the `Assign` and `Holders` bullets] -- fix-risk low (additive clause in this story's text). Patched: "It is admin-only, as `Holders` is" and "It is admin-only [Planner ruling V3, 2026-11-13], and on the online demo it refuses as `Assign` does."
- [x] [Review][Patch] HIGH (ruling V3) `Assign`'s refusal list of installer-managed accounts left out the SQL-watch user `OcuTalonSqlReader` (AD-18), which the same bullet says never holds an approver role [ARCHITECTURE-SPINE.md AD-24 S2] -- fix-risk low. Patched: the list adds "the SQL-watch user `OcuTalonSqlReader` of AD-18, and any other account the installer manages".
- [x] [Review][Patch] HIGH (ruling V6) S1's "the approval-role setting still names the role that answers every kind, and `Raise` records it as `RequiredRole`" contradicted the V6 bullet once 26.4 moves the default to `OcuTalonApprover` (a `setting` row would get `OcuTalonApprover`, and a user with `OcuTalonUser` could not accept their own persona) [ARCHITECTURE-SPINE.md AD-11 S1 "Who may answer"] -- fix-risk low. Patched: "except on a `setting` row, whose `RequiredRole` stays `OcuTalonUser` as the bullet above says; Story 26.4 builds how `Raise` keeps it there without a new role literal in the bridge (AD-2)". The obligation is already DW-1271 (owner 26.4).
- [x] [Review][Patch] MED S2's "The user name and the role reach only the IRIS `Settings` audit entry" contradicted V3's audit entry per assignment and V4's "the IRIS audit entry of a role change, and of a settings change" [ARCHITECTURE-SPINE.md AD-24 S2 Personal data] -- fix-risk low. Patched: "reach only IRIS audit entries, the role change's and the `Settings` entry (AD-17's V4 bullet)".
- [x] [Review][Patch] MED (Rule 19) the "no event" half of the matrix row "MayAnswer writes nothing" had no pin: a `MayAnswer` that calls `..Fire("", ...)` (the `HostSinkClass` fallback) stayed green [src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls TestMayAnswer] -- fix-risk low. Patched: the first row is owned by a fixture session (`Test.Data.Fixture.Session`, cleaned by `Fixture.Clean` in `OnAfterOneTest`), and the test asserts `Live.Event.Since(session, 0)` is empty after the calls; mutation recorded in `## Verification`.
- [x] [Review][Patch] MED (Rule 19) `RowFacts` read the test's own in-memory OREFs through `RefIndexOpen`, so a write by SQL or another job was invisible and the "writes nothing" assertion could not fail for it [Api.cls RowFacts] -- fix-risk low. Patched: `%Reload()` before reading; mutation recorded.
- [x] [Review][Patch] LOW "ignores state and expiry" (S1, method doc) was untested [Api.cls TestMayAnswer] -- fix-risk low. Patched: an `approved` row 60 s past its expiry answers 1 for the holder; mutation recorded.
- [x] [Review][Patch] LOW `RowCount` answers -1 on a failed query, which made the count comparison vacuous [Api.cls] -- fix-risk low. Patched: "the approval rows are counted" (`>= 3`) before the calls.
- [x] [Review][Patch] LOW the `OcuTalonWorkflow` case passed for a missing user too [Api.cls TestMayAnswer] -- fix-risk low. Patched: the user's role set is read with an OK status first.
- [x] [Review][Patch] LOW the AD-6 bullet said "the request's `ContentClass` answers content" (it is `Decide`'s setting; `Part` answers) and, with S5, left out the turn's text part that `ChatWithContent(session, content)` needs beside the image [ARCHITECTURE-SPINE.md AD-6 bullet, AD-31 S5] -- fix-risk low. Patched both sentences.
- [x] [Review][Patch] LOW (Rule 19) AC 3's "`test-class-rules.sh` (bridge-refs) passes" had no `mutation:` line -- closed in this pass (`## Verification`).

**Rejected:**
- BH: `Assign` has no acting-user argument, so 26.4 must break the pinned signature -- false: `Test.Contract.Ac` compares the leading arguments only, so a trailing argument can be added; V3's admin check sits on the admin-only Roles routes and `SettingsOps`.
- BH: `MayAnswer`'s callers may lack `%Admin_Secure` -- false: it calls the same `HoldsRole` that `Answer` runs today in the same callers, and reading one's own role set needs no privilege (`%SYSTEM.Security.GetUserRecursedRoleSet` doc).
- BH: `kind` for an existing row with no `ApproverKind` -- low, spec-bound: it is empty; what `AnswersIn` shows is Story 25.5's (DW-1268).
- BH/EH: `ImageData` is a builder and nobody says who base64-encodes; `Part`/`Accepted` error handling; merging `hostData` over existing members; a caption over 2,000 characters -- low: Story 26.3 builds each against the AI Hub API; no reachable failure before then.
- BH: AD-31's "the three settings" sentence is stale -- low, spec-bound: a pre-existing sentence the spec forbids rewording; it was already stale (five settings) before this story.
- BH: the V4 bullet is phrased as an amendment, and the original Prevents line stays -- spec-bound: the ruling's own form ("added as its own bullet").
- BH: `Holders` leaves direct-vs-recursed roles, which roles and the sort key open -- low: Story 26.4 builds `Holders` and its tests; Story 25.4 renders `{user, roles}` whatever the order.
- BH/EH/AA: spec `status: done` while sprint-status says `review` -- false: `bmad-build-auto` writes `done` at finalize; the sprint key is the stage state, and this stage must not change the frontmatter.
- BH: the floor moved 85 -> 93 though the spec says 89 -> 93 -- false: 89 entries became 93; the floor and the class-doc count were stale at 85 and now equal the real total.
- EH: `MayAnswer` may read a stale OREF of the row -- theoretical (wontfix-theoretical): `RequiredRole` is never changed after `Raise` in the product; real only if a caller edits a row's role in the same process before calling.
- EH: a `fix` row without a caller kind falls back to its `FixKind`, whose role does not exist; a per-kind resource may be missing -- false: S1 and Design Notes 1 make that fail safe (only the all-kinds role answers), and OcuTalon's callers always pass `APPROVERKIND`.
- EH: an invalid caller `ApproverKind` has no stated outcome -- low: Story 26.4 builds it inside `Raise`'s existing refusal pattern (`Validate`, an error naming the field).
- EH: a file that is neither a document nor a photo has no `kind` -- low: Story 25.3's sending path admits only PDF, .docx, JPEG and PNG.
- EH: `ReadFile`'s 5003 with `{}` would end a turn with empty text -- false: `Conversation` calls it only once `Core.Files.Readable()` is 1 (matrix row "ReadFile stub").
- AA: S4 writes `<reason>` where the spec has `{reason}` -- false: it follows the spine's own wording at AD-21's PDF and Word bullet, and `{...}` is a `lint_spine` placeholder finding.
- AA: two S2 sentences differ from `### Spine content` -- allowed by Design Notes open point 3 (Epic 36 re-check); informational.
- VG: the tests rely on the README account -- false for hermeticity: the installer creates it on every environment (fresh included), as `Test.Bridge.Approval` relies on it; a missing account fails red, never green.
- VG: the table-wide `COUNT(*)` can flake under a concurrent `Raise` -- low, theoretical: classes run one at a time and nothing raises approvals unprompted on the test stack.
- VG: AC 1 and AC 2's mutation is structural only -- by-design: document ACs, pinned by this review's read of the spine against `### Spine content` and the rulings (findings above).
- VG: AC 4's named classes have no mutation line -- low: AC 4's pinning test is `TestMayAnswer` (writes nothing), with three mutations recorded.
- Rule 2 (reviewer): `Api.RowCount` repeats `Test.Bridge.Approval`'s 4-line `RowCount` -- low, with a reason: that one is `[ Private ]` and AC 4 keeps `Test.Bridge.Approval` unchanged (Epic 22 contends for it).

## Spec Change Log

- 2026-11-13, lead, Contest Planner rulings (`rulings-371-dw1255-20261113.md`, "37.1 plan", binding; owner's delegation): spine amendments AD-11, AD-24, AD-17, AD-21, AD-31, AD-6, AD-29, the Conventions row, four ownership rows and the Deferred-row removal APPROVED as additive (orchestrator U7/U14). V1, V2 (both `OcuTalonApprover` grants; Story 26.4 pins them), V5, V7 approved. V3: `Assign`/`Holders` admin-only, an allowlist of exactly `OcuTalonApprover` and `OcuTalonViewer`, every `%` role and the installer-managed accounts refused, an IRIS audit entry per assignment and removal, 409 on the demo before the body, a test per refusal (S2 updated). V4: approved, with AD-17 narrowed by the Planner's exact sentence (S3 updated). V6: the ALTERNATIVE, `setting` rows keep today's rule (S1 updated; seven approver kinds, no `OcuTalonApprover_setting`; AC 2 updated). V8: each new obligation on 25.4, 25.5, 25.6, 26.2 (and 26.4's V2/V3 conditions) is filed as a ledger entry routed to that story's key; the orchestrator adds the epics.md bullets post-merge. Escalation: Story 25.6's "no file content in a production message body" means no bytes and no image; extracted text may reach the turn like chat text, and 26.2 does not move into the runner. Story code is unchanged by the rulings (stubs only); the implement stage applies them in the spine text.

## Review Triage Log

### 2026-11-13 -- Review pass
- verdicts: 28 findings -- high 0, medium 0, low 22, false 6, maybe-false 0 (the intent-alignment layer is descriptive and filed no finding)
- findings:
  - `[low]` `[reject]` BH1: AD-17 "Prevents: identities in audit data" is not edited beside the V4 bullet -- the Planner's ruling V4 says the narrowing is "added as its own bullet", and S3 gives that text exactly; spec-bound, not a patch.
  - `[low]` `[reject]` BH2: AD-31's "the three settings" sentence follows the ContentClass block -- S5 fixes the anchor (before that sentence) and the spec forbids rewording existing sentences; the count is Story 26.3's to correct when it adds the setting.
  - `[low]` `[reject]` BH3: `lint_spine` is a weak pin for AC 1/2 -- the spec records this honestly in the mutation line; AC 1/2 are document ACs pinned by the reviewer's read (Manual checks).
  - `[low]` `[reject]` BH4: no mutation for `Holders` -- Rule 19 asks one mutation per AC; AC 3 has three demonstrated, and `TestRoleStubs` asserts `Holders`' 5003 and `[]` after a preset "zz".
  - `[low]` `[reject]` BH5: tests assume the README account exists -- the matrix row names that account, and `Test.Bridge.Approval` (`ANSWERER`) relies on it the same way; it ran green on a fresh and a warm stack.
  - `[low]` `[reject]` BH6: fixture hygiene (unchecked `Save`, no `$IsObject(nobody)`, counter global) -- a failed save fails loudly in the test, the counter global is allowed by `test-boundaries.sh`; guards would add branches to a test for no reachable harm.
  - `[low]` `[reject]` BH7: `TestRoleStubs` uses `%All` on the README account -- the matrix prescribes exactly those two calls; the stub changes nothing.
  - `[false]` `[reject]` BH8: an explicit `ApprovalRole` of `OcuTalonUser` defeats per-kind roles -- AD-11 says the setting names the role that answers every kind and that a set value stays; it is the stated design, not a gap.
  - `[low]` `[patch]` BH9: the `ReadFile` line splits the `Agent.Input` class doc -- moved to the end of the doc block (`Input.cls`).
  - `[low]` `[reject]` EH1: `HoldsRole` answers 0 on a read denial without a log -- pre-existing behaviour of `HoldsRole`, shared with `Answer`; `MayAnswer` must answer `Answer`'s rule.
  - `[false]` `[reject]` EH2: `RefIndexOpen` is outside a Try -- `IsRef` rejects malformed Refs first and `RefIndexOpen` on a well-formed Ref answers "" and does not throw; the matrix rows pass.
  - `[false]` `[reject]` EH3: state and expiry are ignored -- documented in S1 and in the method doc ("Answer decides those").
  - `[low]` `[reject]` EH4: no `$IsObject(nobody)` guard in the test -- same as BH6.
  - `[low]` `[reject]` EH5: the table-wide `COUNT(*)` can flake under concurrent writers -- the spec prescribes this comparison, and the test stack runs no concurrent approval writer; the scoped `RowFacts` assertion also holds.
  - `[low]` `[reject]` EH6: README account assumed -- same as BH5.
  - `[low]` `[reject]` EH7: `%DeleteId` status is not checked in cleanup -- a stray row would not change any later assertion (every test reads its own Ref).
  - `[low]` `[reject]` EH8: `Assign` with empty or non-boolean input is unpinned -- stub; Story 26.4 owns the refusal tests (S2).
  - `[low]` `[reject]` EH9: `ReadFile` with an empty Item is unpinned -- stub; the bare path returns the same 5003 and `{}` without reading the item.
  - `[low]` `[reject]` EH10: the `>= 93` floor tolerates dropped signatures -- the spec says "raise the floor to 93"; the per-signature checks fail for a dropped entry's method.
  - `[low]` `[reject]` EH11: the spine says the kinds "today" include `rollback` and `email` before their fix kinds exist -- spec-bound text (S2); AD-16 itself marks `rollback_setting` "not declared yet", and S1 says callers set the kind from each fix kind's parameter.
  - `[false]` `[reject]` EH12: `MayAnswer` 1 does not guarantee `Answer` will not answer `not_allowed` -- the doc says `Answer` decides state and expiry, and `Answer` applies the same role rule under the lock.
  - `[low]` `[reject]` VG1: "fires nothing, no audit entry" has no observing assertion -- the spec prescribes the `State`/`AnsweredBy`/`AnsweredAt`/`COUNT(*)` comparison; `MayAnswer` takes no sink, so it cannot fire an event, and a state-neutral audit write is not demonstrable without building a valid Approval entry in a mutation. Not a reachable failure.
  - `[low]` `[reject]` VG2: the AC 1/2 mutation line pins a different property than the ACs -- the line states what it proves; the spec's own planned mutation did not hold, and the document ACs are read-pinned.
  - `[low]` `[reject]` VG3: README account hermeticity -- same as BH5.
  - `[low]` `[reject]` VG4: table-wide count -- same as EH5.
  - `[false]` `[reject]` VG5: the stub test would leave a grant if the stub were replaced -- theoretical until Story 26.4, which rewrites these tests with its refusal tests.
  - `[low]` `[patch]` VG6: the `Test.Bridge.Api` class doc says nothing else is written -- added the `^OcuTalonTest("BridgeApi", "n")` counter to the sentence (`Api.cls`).
  - `[false]` `[reject]` VG7: the Auto Run Result section still says ready-for-dev -- it is written at finalize; the verification outcomes are recorded there.

## Design Notes

**Governing ADs (Rule 6):** AD-2 (one package, the bridge names no other OcuTalon package), AD-3 (only installer areas switch to `%SYS`), AD-4 (session ownership; no personal data in production messages), AD-5 (append-only storage; `ApproverKind` is an appended column, Story 26.4), AD-6 (runners are the only model callers; untrusted turns use throwaway, never-linked sessions), AD-7 (model-use rules), AD-10 (untrusted turns run read-only tools at most), AD-11 (approvals, the row is the truth, one answer handler), AD-13 (post-sign-in check), AD-14 (provenance), AD-17 (one audit writer; the role from step 6), AD-19 (`SettingsOps` the only run-time writer; secrets through `SecretHandoff`), AD-21 (memory and documents; files never carry bytes), AD-24 (roles and their limits), AD-29 (lanes, stubs, contract epics), AD-31 (extension classes), AD-33 (one owner per item, table and contract). No AC contradicts an AD Rule. No new AD is needed: every rule fits as an extension of AD-11, AD-17, AD-21, AD-24, AD-29 and AD-31, plus ownership rows.

**Rule 2 (extend, don't copy):** `MayAnswer` extends `Approval` and reuses `HoldsRole` and `IsRef` (no second role check). `Assign`/`Holders` extend the role area `Install.Step.Roles`, following `Install.Step.Mcp.Grant`/`Revoke` (public run-time privilege methods of an installer area). `ReadFile` extends `Agent.Input`, which already owns the read-path flag `READSFILES`. The stub bodies follow Story 33.1's step-2 stubs (`spec-33-1-...md`, `Bridge.Settings`: `%Status` 5003, outputs empty). The tests extend `Test.Bridge.Api`, Lane A's test of its cross-lane stubs, instead of adding a class.

**Integration ACs (Rule 1):** no production consumer in this story; the first consumers are Stories 25.4, 25.5 and 25.6. The integration row of the matrix calls each API from outside its class by the spine's names (`Test.Bridge.Api`), and `Test.Contract.Ac` is the cross-lane signature oracle the consumers compile against.

**Consumed-by:**
- Story 25.4 (Lane B): `SettingsOps` calls `Roles.Assign` and `Roles.Holders` for Settings > Roles, through the `SecretHandoff` path of S2; its tests create the fixture roles named in S2.
- Story 25.5 (Lane B): `AnswersIn` calls `Approval.MayAnswer` before `Answer`; the `not_allowed` slot `kind` and the per-kind sentences use S1's approver kinds.
- Story 25.6 (Lane B): `Conversation` calls `Agent.Input.ReadFile` and renders the read result and the HostData member `caption` (DW-1231); Add to documents uses `fileRef`.
- Story 26.2 (Lane A): builds `ReadFile` for PDF and Word and sets `READSFILES`.
- Story 26.3 (Lane A): builds the photo-caption request, `ContentClass`, `OcuTalon.Agent.Content`, `ReadFile`'s photo branch and the `caption` member.
- Story 26.4 (Lane A): builds `MayAnswer`'s step 6 rule, `Answer`'s check, `ApproverKind`, the roles, resources and grants, `Assign`, `Holders`, the `ApprovalRole` default, the audit `role`, and the demo and README grants.

**Consumes:** `Core.Files` (`Open`, the `SentFile` `Ref`; Story 25.3), `Docs.Extract.Read`/`Failure` codes (Story 19.6), `Core.SecretHandoff` (Story 35.3/21.2), `Test.Bridge.ApprovalRows` (fixture).

**Ledger inbox (Rule 17):** DW-1231 is addressed by S4 and S6 (the read result and `caption`), the `ReadFile` stub and its pin (Tasks 4 and 5, matrix row "ReadFile stub"), and the second AC.

**Decided in-stage:**
1. **Open point 1, row to role** (superseded for `setting` rows by Planner ruling V6: they get no `ApproverKind` and keep today's rule; see S1). An approval row gets an approver kind (`ApproverKind`, Story 26.4): the caller's value, else `tool` for `tool_call`, `setting` for `setting` and the row's `FixKind` for a `fix`. OcuTalon's fix kinds declare `APPROVERKIND` (default `NAME`): `repair_resend` -> `resend`, `reroute` -> `reroute`, `suspend_item` and `resume_item` -> `suspend` (the PRD's "suspend and resume"), `rollback_setting` -> `rollback` (Epic 36's AD-16 name), `partner_warning` -> `partner`, `email` -> `email` (Story 22.7). The kind role is `<RequiredRole>_<ApproverKind>`, so the bridge derives every name from its one setting and hard-codes none (AD-2, AD-31), and a standalone bridge keeps working with its developer's role. A missing or unknown kind fails safe: only the all-kinds role answers.
2. **The resources (26.4's `CheckUserPermission`).** Each approver role holds Use on a resource of its own name (IRIS itself names roles and resources alike, e.g. `%DB_USER`). The resource rule applies only to a row with an `ApproverKind` whose `RequiredRole` names an existing resource; every other row keeps today's role-set rule. So pending rows raised before the upgrade and standalone bridges are unaffected, and no second setting is needed.
3. **The take-over.** Story 26.4 changes `Decide`'s `ApprovalRole` default (`InitialExpression`, the only seed) from `OcuTalonUser` to `OcuTalonApprover` in the change that creates the roles; an explicitly set value stays. Rows raised before keep `OcuTalonUser` until they expire (at most 24 h).
4. **`MayAnswer`'s interim body.** Story 33.1's convention (empty value) would make the stub answer 0 and refuse every answer once Story 25.5 wires it in before Story 26.4 merges, breaking the demo path. It answers today's `HoldsRole` rule instead, which changes nothing because `Answer` already enforces it under the lock. Its output `kind` is a third, output argument, so the AC's two-argument call `MayAnswer(Ref, IrisUser)` stays valid.
5. **`Roles.Holders`** is added beside `Assign`. Settings > Roles must list users, Lane B may not switch to `%SYS` (AD-3), and the REST process lacks `%Admin_Secure`, so the list comes from Lane A's role area in `SettingsOps`' job.
6. **Open point 2, the "extracted-text summary ref".** It is the read result's `fileRef` (the `SentFile` `Ref`) plus code-built counts (`chars`, `cut`). No model summary and no stored extracted text exist. The text lives only in the model request (Story 26.2's `Render`), and Add to documents extracts again from the stored file through `DocumentOps`. This fits AD-21 (no bytes in messages) and Story 25.3's `SentFile` and Item fields.
7. **The read result reaches Lane B by a call, the caption by HostData.** `Conversation` already renders file turns in its own job (`Agent.Input.Render` through `Intake.RequestFor`), so the read outcome is a synchronous `ReadFile` answer there, and a failed read ends the turn with no model request, like Story 25.3's no-reader branch. The photo caption is the photo turn's own reply. Its memory is saved by `Decide` after it accepts a usable reply, through `ContentClass.Accepted` (AD-31), and it rides on the Reply as the HostData member `caption`, the `citations`/`memories`/`learned` precedent. No Lane B call site is needed for the caption, so Story 26.3 gains no new dependency.
8. **The photo-caption request is a `turn`**, not a new request kind. Provenance `untrusted` already gives a throwaway AI session that is never linked (AD-6) and read-only tools at most (AD-10), and adding a kind would need a Lane B `Msg.Enum` edit (the enum-equality pin, `Test.Msg.Contracts`). The image reaches the runner only through `ContentClass.Part` in the runner's job.
9. **Caption memory fields without a schema change.** The text is the reply text (at most 2,000 characters), the `ItemId` is the photo Item's (its source), the origin is `system` (a recall then taints, AD-21 line 754) and the `Source` is `learned`. `Data.Memory` stays unchanged.
10. **The audit role.** `Bridge.Audit`'s common fields gain `role` (Story 26.4). An approval answer's role is the approver role that allowed it. Any other entry's role is whatever its caller passes, which keeps AD-17's "their role (from step 6)" as written.

**Open point 3 (Epic 36 not merged): the Epic 36 deliverables this spec relies on.** After the integrate-forward of Epic 36, the implement stage re-checks each of these against the merged spine and adjusts only the S-text that names them:
- 36.1's AD-16 bullet naming the fix kind `rollback_setting` (parameter `change`, `%Ens_ProductionConfig:W`, `ONLINEGRANT` 0), which is the approver kind `rollback`;
- 36.1's AD-24 V5 bullet (Story 23.3 grants `%Ens_ProductionConfig:W`): S2 must not contradict it;
- 36.2's AD-16 dry-run fields for step 5's kinds, and "A page raises no approval": pages need no approver kind;
- 36.4's S1(b) rule: in 36.4's spec only, not yet in the spine. Its planned AD-19 bullet (36.4 spec S2) and its `Web.OnCallSettings` handoff pattern are what S2's personal-data clause follows. If 36.4's AD-19 bullet has merged, S2 cites it; otherwise S2 carries the rule itself, as written.
- Not Epic 36, but in the same position: Story 22.7's fix kind `email` (Epic 22, `Fix/Kind/Email.cls`) is the approver kind `email`.

**Contended overlaps:**
- Lane B, Epic 36: the spine. 36.1 and 36.2 add AD-1, AD-12, AD-14 to AD-16, AD-18, AD-19, AD-24 (line 977 in their tree), AD-29 (line 1106, "Epic 36's names"), AD-32, ownership rows (1486, 1509, 1533) and Deferred rows 1763-1765. Their `Msg/Enum.cls` appends `page`. 36.4 adds the on-call section in `Core/SettingsOps.cls` and the new `Web.OnCallSettings`. 37.1 edits none of these files except the spine, and puts its spine text at different anchors: an AD-24 bullet after the online-demo bullet, not near 977; its own AD-29 bullet after Epic 36's; ownership rows after Story 25.3's rows.
- Lane C, Epic 21: 21.8 edits `SettingsOps` (OAuth) and adds AD-24 line 953 ("What registering the mail OAuth2 client needs"); 21.7, 21.12 and 21.13 touch AD-14, AD-19 and AD-22. 21.10's spec reads `Approval.AnswerLocked` and `Cancel` and changes neither. No file is shared except the spine (AD-24, an adjacent bullet).
- Lane D, Epic 22: `Bridge/Approval.cls` (the `Validate` fingerprint rules, `IsMcpSource` near line 253, `CancelPending` near line 445, `FinishExecution` `changed`), `Bridge/Data/ApprovalRequest.cls` (`ToolFingerprint`, storage slot 26), `Fix/Kind.cls` plus the new `Fix/Kind/Email.cls`, `Policy/Gate.cls` (the MCP proxy and `HoldByHook`), many `Test/Bridge/*` classes (not `Api.cls`), and the spine's AD-11 line 417 (the MCP rows bullet) and AD-10. 37.1 adds `MayAnswer` after `HoldsRole` (line 393), away from 22's methods, and puts its AD-11 bullet after line 409, not after 417. Story 26.4 must append `ApproverKind` after `ToolFingerprint`.
- Epic 25 consumes this story (25.4, 25.5, 25.6). No spec exists yet, its worktree has no changes, and none of its files are touched here.

**Spine amendments (for the lead to route under U7/U14; each additive, no existing sentence changed):**
- Spine amendment: AD-11 -- S1, approver kinds, the step 6 answer rule, the take-over from `ApprovalRole`, `MayAnswer`, the `not_allowed` kind, the audit role.
- Spine amendment: AD-24 -- S2, the step 6 role names and same-named resources, the viewer's grants, the README account's `OcuTalonApprover` at the step 6 upgrade (the online demo's is already in the Rule), `Assign`/`Holders` and their personal-data handoff.
- Spine amendment: AD-17 -- S3, the common field `role`.
- Spine amendment: AD-21 -- S4, the read result (DW-1231), the photo-caption request and the caption memory.
- Spine amendment: AD-31 -- S5, the new extension `ContentClass` (`Part`, `Accepted`).
- Spine amendment: AD-6 -- S5's clause that a runner may call `ChatWithContent` with one `ImageData` part, under the same runner rules as `Chat`.
- Spine amendment: AD-29 -- S9, a one-line "Epic 37's names" bullet.
- Plus a Conventions row (S6), four ownership rows (S7) and the removal of a Deferred row (S8).

**Veto items (for the lead to route):**
1. Privileges and grants (AD-24): the seven `OcuTalonApprover_<kind>` roles (V6: no `setting` kind), `OcuTalonApprover`, `OcuTalonViewer` and one same-named resource per approver role, named here and created by Story 26.4. Online demo: they exist there too; only the demo account holds `OcuTalonApprover`; no visitor can assign a role.
2. A grant to the demo account (AD-24 already states it; the AC asks it as an amendment): the online demo account holds `OcuTalonApprover`. Online demo: visitors keep answering their own session's requests (the owning-session rule still applies, both checks run); the account is never an admin; no Roles section is shown. The README account also gains `OcuTalonApprover` at the step 6 upgrade (local installs only).
3. A run-time privilege-change path: `Roles.Assign` grants or removes approver and viewer roles of other IRIS users, and only those; it refuses every other role, `%` roles and the installer-managed accounts. `Roles.Holders` reads every user's roles with `%Admin_Secure` in `SettingsOps`' job. Online demo: unreachable, because the Roles routes are admin-only and the demo account is not an admin.
4. Security posture and personal data: the target user names travel only through `Core.SecretHandoff`, both ways (the listing goes back through a handoff too, a reverse use the spine has not stated before). They reach only the IRIS `Settings` audit entry, which names the target IRIS user and the role. Read against AD-17's "Prevents: identities in audit data" together with 36.4's S1 rule ("values reach only the audit entry"). Online demo: unreachable (admin only).
5. Stored data (AD-5): Story 26.4 appends the column `ApproverKind` to `ApprovalRequest`, and `Bridge.Audit` entries gain the field `role`. Online demo: rows raised there get an approver kind; nothing else changes.
6. [RULED V6, 2026-11-13: the alternative; `setting` rows keep today's rule] A product call: from Story 26.4, approving one's own persona proposal (a `setting` row) needs an approver role (`OcuTalonApprover` or `OcuTalonApprover_setting`), so a user holding only `OcuTalonUser` can no longer approve one. The alternative is to keep `setting` rows on today's rule; that needs the lead's ruling. Online demo: unchanged (the demo account holds `OcuTalonApprover`).
7. Security posture (AD-31): the runner reads a user's photo bytes through `ContentClass.Part` (owner-scoped by `Core.Files.Open`), and `Decide` saves a memory through `ContentClass.Accepted`. Online demo: unreachable, because sending files is off there (Story 25.3, ruling 1).
8. Additions to other epics' not-yet-planned stories (parallel: route to the orchestrator):
   - Story 25.6: call `ReadFile` before a file turn's requests and end the turn with `result.text` when `read` is 0; carry the read result and `caption` and name the carriers; Add to documents by `fileRef`.
   - Story 25.4: the handoff both ways, plus a leak-scan test of the change's message bodies for the target user name.
   - Story 25.5: one "Only an approver for ..." sentence per approver kind, of which only "resends" is in `EXPERIENCE.md` (PUBLIC TEXT for 25.5 to propose).
   - Story 26.2: read once for `ReadFile` and `Render` in the same job, or re-read.
   - Online demo: this story changes nothing there; each receiving story states its own demo behaviour.

**PUBLIC TEXT:** none. The stubs add no user-visible text. The texts the contracts name are already verbatim in `EXPERIENCE.md`: "I couldn't read that file: {reason}." (:1090, through `Docs.Extract.Failure`), **Add to documents** (:1091), "Saved to memory" (:1092) and the fixture "Only an approver for resends can answer this request." (:721). The per-kind sentences for the other seven kinds are not in the UX docs; they are Story 25.5's to propose (veto item 8).

**For the lead (escalated, not blocking):**
- Story 25.6's "no file content appears in a production message body" is read here as "no file bytes and no image". Story 26.2's own AC and the spine row at 1494 have `Agent.Input.Render` quote a document's extracted text into the turn request's `Input`, which is a production message body, as a user's chat text is. If the Planner reads "file content" as the extracted text too, Story 26.2's rendering must move into the runner's job (through `ContentClass.Part`, S5). That ruling belongs to the 26.2 and 25.6 plans; this contract supports either.
- `ReadFile`, and Story 26.2's `Render`, run `Docs.Extract` (up to 45 s) in `Conversation`'s job, which never waits on a message. That is a pool-size consideration for Story 26.2, not a contract change.

### Spine edits

| Id | Anchor | Edit |
| --- | --- | --- |
| S1 | AD-11, a new bullet right after "The bridge's approval-role setting names the role ..." (line 409) | Approver kinds and roles (step 6) |
| S2 | AD-24, a new bullet right after "The online demo account holds `OcuTalonUser` ..." (line 941) | Approver and viewer roles (step 6) |
| S3 | AD-17, a new bullet right after "Production jobs run as the Interoperability system user ..." (line 580) | The audit role |
| S4 | AD-21, a new top-level Rule bullet at the end of AD-21's Rule list (the last line before `### AD-22`, line 835) | Files and photos sent from the chat or Telegram (step 6) |
| S5 | AD-31, a new sub-bullet after the `McpServersClass` additions (before "The bridge reads the three settings ...", line 1138) | `ContentClass` |
| S6 | Conventions, a new row right after "Citations and memories on the page" (line 1224) | File read results (step 6) |
| S7 | Ownership cross-area table, four new rows right after Story 25.3's rows (after line 1494) | the four contracts |
| S8 | Deferred, remove the row "Approver kinds and per-kind checks (FR-11, step 6)" (line 1724) | decided by S1 and S2 |
| S9 | AD-29, a new bullet after Epic 36's names bullet when it is present after the integrate-forward, else after line 1054 | Epic 37's names |

### Spine content

**S1 (AD-11).** `- **Approver kinds and roles (step 6)** [ADDED <date>, Story 37.1]:`
- `ApprovalRequest` gains `ApproverKind` (Story 26.4, appended under AD-5). From Story 26.4, `Raise` takes it from the caller when given: a lower-case token of letters and `_`, at most 32 characters, which the bridge never checks against a host list. Otherwise it sets `tool` for a `tool_call` and the row's `FixKind` for a `fix`; a `setting` row gets none (below). OcuTalon's callers set it from the fix kind's `APPROVERKIND` parameter (default its `NAME`): `repair_resend` is `resend`, `reroute` is `reroute`, `suspend_item` and `resume_item` are `suspend`, `rollback_setting` is `rollback`, `partner_warning` is `partner` and `email` is `email`. A page raises no request.
- `setting` rows keep today's rule [Planner ruling V6, 2026-11-13]. A persona proposal (`Kind` `setting`) gets no `ApproverKind`, and its `RequiredRole` stays `OcuTalonUser` across the take-over below, so the requesting user answers their own proposal with the role they already hold (the owning-session rule still applies). A user never needs an approver role to accept their own assistant's persona, and no `OcuTalonApprover_setting` role exists.
- Who may answer. The approval-role setting still names the role that answers every kind, and `Raise` records it as `RequiredRole`. The kind's role is `<RequiredRole>_<ApproverKind>`. Each approver role holds Use on a resource of its own name (AD-24).
  - A row that has an `ApproverKind`, and whose `RequiredRole` names an existing resource, is answerable by a user for whom `$SYSTEM.Security.CheckUserPermission(user, RequiredRole, "U")` or `$SYSTEM.Security.CheckUserPermission(user, RequiredRole _ "_" _ ApproverKind, "U")` is 1.
  - Every other row keeps the rule above: the role must be in the user's recursed role set. These are rows raised before step 6's upgrade, and a standalone bridge's rows where the developer made no such resource.
  - `Answer` applies the rule under the row's lock and answers `not_allowed` (Story 26.4).
- The take-over. Story 26.4 changes the default of `Decide`'s `ApprovalRole` from `OcuTalonUser` to `OcuTalonApprover` in the same change that creates the roles, so an install whose `Decide` item does not set the value moves at its upgrade; a value set on the item stays. Rows raised before the upgrade keep `OcuTalonUser` until they expire.
- `OcuTalon.Bridge.Approval.MayAnswer(ref, irisUser, Output kind) As %Boolean` is the role check Lane B makes before `Answer` (`AnswersIn` and the page's approval state, Story 25.5).
  - It answers 1 when the user may answer the row by the rule above. Otherwise it answers 0, with `kind` set to the row's `ApproverKind`, or empty when no row has the Ref.
  - It reads the row without its lock, ignores state and expiry (`Answer` decides those), and writes and fires nothing.
  - Until Story 26.4 it answers the role-set rule, with `kind` empty (Story 37.1).
- From step 6, `AnswersIn`'s `not_allowed` slot `kind` carries the `ApproverKind`, and the catalog has one "Only an approver for ..." sentence per approver kind (Lane B, Story 25.5).
- An allowed answer's Approval audit entry names, as `role`, the approver role that allowed it: the `RequiredRole` when the user passes that check, otherwise the kind's role (AD-17, Story 26.4).

**S2 (AD-24).** `- **Approver and viewer roles (step 6)** [ADDED <date>, Story 37.1]:`
- The roles are `OcuTalonApprover` (every kind), one `OcuTalonApprover_<kind>` for each approver kind of AD-11, and `OcuTalonViewer`.
  - The approver kinds today are `resend`, `reroute`, `suspend`, `rollback`, `partner`, `email` and `tool`, plus one for each fix kind's `APPROVERKIND` added later.
  - Story 26.4's installer creates the roles, and one resource with the same name for each approver role, which only that role holds (Use). It composes their grants from the areas' `Grants()`, as for every role, inside the limits of this AD.
- `OcuTalonViewer` holds the read (R) grants the areas declare for `OcuTalonUser` and no W or U grant (Story 26.4 measures what the web applications need). The post-sign-in check admits it by name (Lane B, Story 25.4; AD-13).
- The online demo account's `OcuTalonApprover` is the bullet above (Story 26.4 adds it to `Install.Step.Users` `DEMOROLES`). The README account gains `OcuTalonApprover` at the step 6 upgrade, so a local install still approves. The read-only account and the service, Workflow and SQL-watch users never hold an approver or viewer role. Story 26.4 pins both grants (the demo account's and the README account's `OcuTalonApprover`) in tests [Planner ruling V2, 2026-11-13].
- `OcuTalon.Install.Step.Roles.Assign(userName, role, grant, Output changed) As %Status` grants (`grant` 1) or removes (0) one role of an existing IRIS user.
  - It is admin-only and works from an ALLOWLIST of exactly two roles, `OcuTalonApprover` and `OcuTalonViewer` (never a denylist) [Planner ruling V3, 2026-11-13]. The per-kind roles `OcuTalonApprover_<kind>` are not assignable through it; an administrator grants those in IRIS.
  - It refuses every other role (`OcuTalonAdmin`, `OcuTalonUser`, `OcuTalonTraceViewer`, the per-kind roles and any `%` role, `%All` included) and the installer-managed accounts (the online demo and read-only accounts, `OcuTalonService`, `OcuTalonWorkflow`). Each refusal is an error that names what it refused, and nothing changes. Story 26.4 has a test for each refusal.
  - Every assignment and every removal writes an IRIS audit entry (Story 26.4).
  - On the online demo the Roles routes answer 409 `not_available` before the body is read (Lane B, Story 25.4), and `Assign` refuses there too.
  - `changed` is 0 when the user already was in that state.
- `Roles.Holders(Output users As %DynamicArray) As %Status` lists the users who hold an OcuTalon role, as `{user, roles}`, with the OcuTalon roles each holds, sorted.
- Both methods run in `%SYS` (AD-3) in the caller's job, which needs `%Admin_Secure:USE`: in OcuTalon, `SettingsOps`' production job. Until Story 26.4 both are stubs (Story 37.1): `Assign` answers "not implemented" (5003) and changes nothing, and `Holders` answers 5003 and `[]`.
- Personal data. An IRIS user name other than the acting user's is never in a traced message.
  - The Roles section (Lane B, Story 25.4) hands the target user name and the role to `SettingsOps` through `OcuTalon.Core.SecretHandoff`, so `SaveSettings.Changes` holds only `{"handoff": uri}`.
  - `Holders`' list goes back the same way: the `CommandResult` carries only a handoff uri.
  - The user name and the role reach only the IRIS `Settings` audit entry, and Story 25.4's route test scans the change's message bodies for the user name, as Story 36.4 does for the on-call values.

**S3 (AD-17).** `- **The role** [ADDED <date>, Story 37.1]:` `Bridge.Audit`'s common fields gain `role` (Story 26.4). An Approval answer's role is AD-11's approver role. Any other entry names the role its caller passes, or none.
- `[AMENDED <date>, Story 37.1, Contest Planner ruling V4]` AD-17's "Prevents: identities in audit data" is narrowed by exactly this sentence, added as its own bullet: "The IRIS audit entry of a role change, and of a settings change, may hold the IRIS user names involved, plus the on-call contact values (36.2 V3); OcuTalon's own Action audit holds no identities."

**S4 (AD-21).** `- **Files and photos sent from the chat or Telegram (step 6)** [ADDED <date>, Story 37.1]:`
- **The read result (DW-1231).** `OcuTalon.Agent.Input.ReadFile(item, Output result As %DynamicObject) As %Status` (Lane A) reads the file of an Item with a `FileRef` through `Core.Files.Open(item.FileRef, item.SessionRef)`. Story 26.2 builds it for PDF and Word and Story 26.3 for photos; until then it is a stub that answers 5003 and `{}` (Story 37.1).
  - The result is built by code, never from model text, and holds no file bytes and no extracted text. Its fields:
    - `fileRef`: the `SentFile` `Ref`, which every later step uses;
    - `kind`: `document` (PDF, .docx) or `photo` (JPEG, PNG);
    - `read`: 1 or 0;
    - with `read` 0: `reason`, one of `Docs.Extract`'s codes (a photo the model cannot be sent is `failed`), and `text`, which is `Docs.Extract.Failure(reason)`, "I couldn't read that file: {reason}.";
    - with `read` 1, for a document: the extracted-text summary `chars` (the characters of the extracted text) and `cut` (1 when `MAXTEXT` cut it), and `addable` 1, the Add to documents offer;
    - with `read` 1, for a photo: `addable` 0.
  - `Conversation` (Lane B, Story 25.6) calls `ReadFile` for a turn with a `SentFile`, once `Core.Files.Readable()` is 1 and before the turn's requests are sent.
    - A result with `read` 0 ends the turn with `text` and makes no model request, as the no-reader reply does.
    - Otherwise the turn runs as an untrusted turn (AD-6, AD-10), and the result rides on its reply.
  - Story 25.6 names the Lane B carriers in its own rows. Add to documents goes through the documents route with the `fileRef`, which opens the stored file for the session through `Core.Files.Open` and extracts it again through `DocumentOps`; the extracted text is never stored.
- **The photo-caption request (Story 26.3).** A photo's turn is its caption request: a `turn` request of provenance `untrusted` through `Decide` to `ChatAgent`, with no new request kind.
  - It runs in a throwaway AI session that is never linked to the conversation (AD-6), with read-only tools at most (AD-10), and `Decide` records its decision, usage and cost as for any turn (AD-20).
  - The image reaches the model only inside the runner's job, through `ContentClass.Part` (AD-31), as one `%AI.LLM.ContentPart.ImageData` sent with `ChatWithContent`, under AD-6's runner rules and AD-7's model-use rules. No production message body, agent step or log holds it.
- **The caption memory.** After `Decide` accepts a usable reply, `ContentClass.Accepted` saves the reply's text (at most 2,000 characters) as a memory through `SaveMemory` to `MemoryOps`, with the photo Item's `ItemId`, origin `system` (so recalling it taints a turn) and `Source` `learned`.
  - The Reply then carries the HostData member `caption`, `{memoryRef, text}`, built by code and absent when nothing was saved.
  - `Conversation` carries it as it carries `learned` (Story 25.6), and the page shows "Saved to memory".
  - An unusable reply takes the fallback route and saves nothing (AD-8).

**S5 (AD-31).** `- **ContentClass (step 6, Story 26.3)** [ADDED <date>, Story 37.1]:`
- The base is `OcuTalon.Bridge.Ext.Content`. The setting `ContentClass` is on `Decide` (category Extensions) and is read through `Ext.Accessor.ClassFor`, whose `BASES` gains the pair.
- `Part(request As OcuTalon.Bridge.Msg.Request, Output mediaType As %String, Output data As %Stream.Object) As %Status` is called in the runner's job before the model call, never inside a callback. It defaults to no content.
  - When it answers content, the runner calls `ChatWithContent` with one `ImageData` part instead of `Chat`, under every runner rule of AD-6.
- `Accepted(request As OcuTalon.Bridge.Msg.Request, text As %String, Output hostData As %DynamicObject) As %Status` is called by `Decide` in its own job after it accepts a usable `turn` reply. It defaults to nothing, and `Decide` merges the members of `hostData` into the reply's `HostData`.
- OcuTalon's class is `OcuTalon.Agent.Content` (Lane A).
  - `Part` answers the image of a photo turn: from the request's `ItemId` and `OwnerRef` to the turn's `SentFile`, then through `Core.Files.Open`.
  - `Accepted` saves the caption memory (AD-21) and answers `{"caption": {memoryRef, text}}`.
- The bridge alone sends no content (FR-5).

**S6 (Conventions row).** `| File read results (step 6) | The read result of AD-21 and the HostData member caption follow the citations, memories and learned precedent: built by code, never model text, absent when empty, no file bytes and no extracted text. Story 25.6 names the Lane B carriers (Turn, Outbound, chat.message, /v1/state) [ADDED <date>, Story 37.1] |` (with the names in backticks, as the neighbouring rows write them).

**S7 (Ownership rows).**
- `| OcuTalon.Bridge.Approval.MayAnswer(ref, irisUser, *kind) (AD-11), called by AnswersIn and the page's approval state | A | Story 37.1 (interim rule), Story 26.4 [ADDED <date>, Story 37.1] |`
- `| OcuTalon.Install.Step.Roles.Assign(userName, role, grant, *changed) and .Holders(*users) (AD-24), called by SettingsOps for Settings > Roles | A | Story 37.1 (stubs), Story 26.4 [ADDED <date>, Story 37.1] |`
- `| OcuTalon.Agent.Input.ReadFile(item, *result), the read result and the HostData member caption (AD-21), read by Conversation | A | Story 37.1 (stub), Stories 26.2 and 26.3 [ADDED <date>, Story 37.1] |`
- `| OcuTalon.Bridge.Ext.Content, the ContentClass setting and OcuTalon.Agent.Content (AD-31) | A | Story 26.3 [ADDED <date>, Story 37.1] |`

(Names in backticks, as the table writes them.)

**S8 (Deferred).** Remove the row; record in the S1 marker `[AMENDED <date>, Story 37.1: the Deferred row "Approver kinds and per-kind checks (FR-11, step 6)" is decided here and removed]`.

**S9 (AD-29).** `- **Epic 37's names** [ADDED <date>, Story 37.1]: AD-11's approver kinds and MayAnswer, AD-24's step 6 roles, resources, Assign and Holders, AD-21's read result, photo-caption request and caption, AD-31's ContentClass; Lane B's halves (the Roles section, AnswersIn's check, the file replies) get their rows from Stories 25.4, 25.5 and 25.6.` (Names in backticks.)

## Verification

Every IRIS line runs with the lane prefix `P` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=37 stage=implement'`. Each line is one call, in the foreground, with `timeout: 600000`, and one test run per message.

- Start the warm stack once: `P OCUTALON_RUN_TAG=e37s1iw ci/warm.sh up`.
- End, also after a failure: `P OCUTALON_RUN_TAG=e37s1iw ci/warm.sh down`, then `P OCUTALON_RUN_TAG=e37s1i ci/iris.sh teardown`.
- Every call must finish inside about 150 s. When a part nears that, run it as its two halves (`--part 2k-1/2n`, then `--part 2k/2n`), never as a re-submit.
- Implement re-checks the Epic 36 items of Design Notes after the integrate-forward, before the first run.

**Commands:**
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: no finding beyond the baseline low `placeholder` ones (record the baseline before the edits).
- (loop) `bash docker/tests/test-class-rules.sh` -- expected: PASS, bridge-refs included.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: PASS (ASCII, no local path).
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh class OcuTalon.Test.Bridge.Api` -- expected: passed.
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh class OcuTalon.Test.Contract.Ac` -- expected: passed, 93 signatures.
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh class OcuTalon.Test.Bridge.Approval` -- expected: passed (`Answer` unchanged).
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh class OcuTalon.Test.Install.Registry` -- expected: passed (the Roles step unchanged).
- (loop) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh class OcuTalon.Test.Agent.Render` -- expected: passed (`Agent.Input` unchanged in behaviour).
- (once) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh shard lane-a --part 1/16`, then `--part 2/16` through `--part 16/16`, one call each -- expected: every class passed.
- (once) `P OCUTALON_WARM=1 OCUTALON_RUN_TAG=e37s1iw ci/iris.sh shard lane-b@Contract,Core,Data,Demo,Live,Msg,Web --part 1/12`, then `--part 2/12` through `--part 12/12`, one call each -- expected: every class passed.
  - `Schedule` is left out: this story does not touch it, and `Test.Schedule.Heartbeat` alone runs longer than one call (140-206 s, Rule 21). CI runs it.

**Planned mutations (Rule 19), one per AC's pinning test:**
- AC 1 and AC 2 are document ACs, pinned by the reviewer's read of the spine diff against `### Spine content`. Their structural pin is `lint_spine`: remove the `**Rule:**` line of AD-24, and `lint_spine` goes red.
- AC 3:
  - Rename `MayAnswer`'s `kind` to `role`, and `Test.Contract.Ac` goes red.
  - Make `MayAnswer` `Quit 1`, and `Test.Bridge.Api` `TestMayAnswer` goes red (the `OcuTalonWorkflow` case).
  - Make `Assign` `Quit $$$OK`, and `TestRoleStubs` goes red.
  - Make `ReadFile` set `result = {"read":1}`, and `TestReadFileStub` goes red.
- AC 4: make `MayAnswer` call `Answer` (a write), and `TestMayAnswer`'s "writes nothing" case goes red.
- Record each as `mutation: <change> -> <test went red>`, reverted, with `git status --short` and `git diff --stat` unchanged.
- Demonstrated (2026-11-13, implement; each reverted, `git status --short` and `git diff` byte-identical afterwards):
  - mutation: AC 1 and AC 2, `lint_spine` structural pin: the word "rule" (any case) replaced by "Rxle" in the whole AD-24 block -> `lint_spine` reports `ad_fields` "AD-24 missing required field(s): rule" (high). Removing only the `**Rule:**` line stays green, because the check is a case-insensitive substring match on the whole block and the block's prose says "rule" elsewhere.
  - mutation: AC 3, `MayAnswer`'s output argument renamed `kind` to `role` -> `Test.Contract.Ac` `TestCrossLaneSignatures` red ("MayAnswer takes (ref,irisUser,*kind) in that order").
  - mutation: AC 3, `MayAnswer` ends with `Quit 1` -> `Test.Bridge.Api` `TestMayAnswer` red (OcuTalonWorkflow, nobody-role and empty-user cases).
  - mutation: AC 3, `Assign` ends with `Quit $$$OK` -> `Test.Bridge.Api` `TestRoleStubs` red (both Assign cases).
  - mutation: AC 3, `ReadFile` sets `result = {"read":1}` -> `Test.Bridge.Api` `TestReadFileStub` red ("and the result is empty").
  - mutation: AC 4, `MayAnswer` calls `..Answer(ref, "approve", "web", irisUser, row.OwnerRef)` before its `Quit` -> `Test.Bridge.Api` `TestMayAnswer` red ("no state, answer field or row count changed").
  - [QA 2026-11-13] mutation: AC 4 / matrix row "MayAnswer writes nothing" ("no event, no audit entry"), `MayAnswer` calls `Audit.Write("Approval", {"ref":(ref)}, ...)` before its `Quit` and changes no row -> `Test.Bridge.Api` `TestMayAnswer` red ("and no audit entry names either row"; the implement-stage assertions stayed green, so this audit assertion is the only pin). Reverted; `git diff` byte-identical.
  - [code review 2026-11-13] mutation: AC 4 / matrix row "MayAnswer writes nothing" ("no event"), `MayAnswer` calls `..Fire("", ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALANSWERED, row.OwnerRef, ref)` before its `Quit` -> `Test.Bridge.Api` `TestMayAnswer` red ("and no event reached the stream of the row's owner").
  - [code review 2026-11-13] mutation: AC 4, `MayAnswer` runs `UPDATE OcuTalon_Bridge_Data.ApprovalRequest SET AnsweredBy = 'zz' WHERE Ref = ?` before its `Quit` -> `TestMayAnswer` red ("no state, answer field or row count changed"; `RowFacts` now reloads the row).
  - [code review 2026-11-13] mutation: AC 3 (S1 "ignores state and expiry"), `MayAnswer` adds `If row.State '= "pending" Quit 0` -> `TestMayAnswer` red ("an answered row past its expiry still answers 1 for the holder").
  - [code review 2026-11-13] mutation: AC 3 (bridge-refs), `MayAnswer` adds `If '##class(OcuTalon.Core.Files).Readable() Quit 0` -> `docker/tests/test-class-rules.sh` red ("FAIL bridge-refs", `Approval.cls:427`).
  - Each reverted; `git diff` and `git status --short` byte-identical afterwards. `Test.Bridge.Api` passed after the patches (warm stack e37s1cw); `test-class-rules.sh`, `test-boundaries.sh` pass; `lint_spine` 10 low `placeholder` findings, as before.

**Shared surfaces:** `Test.Contract.Ac`'s signature list and floor (89 to 93); the spine's ownership tables, the Conventions table and the Deferred list; the `ApprovalRequest` rows the test makes and deletes. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Manual checks:**
- The spine diff holds only S1 to S9, each with its marker, and the removed Deferred row; `git diff` of the spine shows only added lines, apart from that one row.
- No file outside the Code Map's write list changed (`git status --short`).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Step 6's Lane A contracts are written into the spine as additive bullets and rows (S1 to S9, each marked `[ADDED 2026-11-13, Story 37.1]`; the AD-17 and Deferred-row changes marked `[AMENDED]`), and four cross-lane APIs compile and are pinned in `Test.Contract.Ac`: `Approval.MayAnswer` (today's `HoldsRole` rule, `kind` empty, writes nothing), and the stubs `Install.Step.Roles.Assign` and `Holders` and `Agent.Input.ReadFile` (5003, `changed` 0, `users` `[]`, `result` `{}`). The Epic 36 deliverables of Design Notes' open point 3 were re-checked against the merged spine; S9 sits after "Epic 36's names", and S2 states that the `%Ens_ProductionConfig:W` exception stays Story 23.3's and the online demo leaves it out. Planner rulings V1 to V8 are applied as the spec states them.

**Files changed.**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: S1 (AD-11), S2 (AD-24), S3 and the V4 bullet (AD-17), S4 (AD-21), S5 (AD-31) and its AD-6 clause, S6 (Conventions row), S7 (four ownership rows), S9 (AD-29); the Deferred row removed (S8).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: `MayAnswer` after `HoldsRole`; class-doc line.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls`: `Assign` and `Holders` stubs; class-doc line.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls`: `ReadFile` stub; class-doc line.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`: four signatures, floor 93, class-doc count 93.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`: `TestMayAnswer`, `TestRoleStubs`, `TestReadFileStub`, cleanup in `OnAfterOneTest`.

**Review.** 28 findings from three layers (the intent-alignment layer was descriptive): 2 patches applied (both doc comments), 0 deferred, 26 rejected with the reason in the triage log. No HIGH or MEDIUM. Follow-up review recommended: false (no patched high, fewer than two patched mediums).

**Verification.**
- `lint_spine`: 10 findings, all low `placeholder`, before (HEAD) and after.
- `test-class-rules.sh` (bridge-refs) and `test-boundaries.sh`: pass, after the last patch too.
- Warm stack, `(loop)` classes: `Test.Bridge.Api`, `Test.Contract.Ac` (93 signatures), `Test.Bridge.Approval`, `Test.Install.Registry`, `Test.Agent.Render` passed; `Test.Bridge.Api` and `Test.Agent.Render` passed again after the two doc patches.
- `(once)` `shard lane-a --part 1/16` to `16/16`: every class passed except `Test.Channel.EmailLive` (part 4, `TestDigestReachesTheStub`, three digest-text assertions) and `Test.Fix.Restart` (part 11, "and warns of nothing"). Neither touches a file of this story. `EmailLive` failed again alone on the warm stack and passed alone on a fresh stack (115 s); `Fix.Restart` passed alone on a fresh stack (40 s). They are warm-stack leftovers (state kept from the earlier classes of the sweep), not defects of this change; the lane-a CI run of the merged feature head passed.
- `(once)` `shard lane-b@Contract,Core,Data,Demo,Live,Msg,Web --part 1/12` to `12/12`: every class passed.
- Matrix Test Audit: every row is covered by `TestMayAnswer`, `TestRoleStubs`, `TestReadFileStub` or `Test.Contract.Ac`, and each ran and passed.
- Mutations demonstrated and reverted: see `## Verification`.

**Residual risks.** The mutation pin for AC 1 and AC 2 is `lint_spine`'s structural check only; the substance of S1 to S9 is read-pinned. Story 26.4 must rewrite `TestRoleStubs` with the refusal tests when `Assign` is built. The tests use the README account `ocutalon`, as `Test.Bridge.Approval` does.
