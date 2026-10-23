# Deferred Work Ledger

See _bmad/custom/skill-rules.md Rule 15 (entry grammar) and Rule 17 (the drain).

### DW-1: Build 154 iris-main skips an unchanged ISC_CPF_MERGE_FILE, so the merge is not reapplied at every start (AD-23, Rule 21); a partly failed first merge or a hand-removed mapping is not repaired by a restart
- source: _bmad-output/implementation-artifacts/spec-0-1-the-image-builds-and-starts-ocutalon-in-its-own-namespace.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: iris-main logs 'unchanged; skipping' against /durable/iris/^opt^ocutalon^merge.cpf.last_merge (observed in the 0.1 live test); retry after a failed first merge untested
- 2026-10-18T17:23:45Z status=decision-pending owner=burndown by=harvest note=decide before 0.2 plan: 0.2 after-start re-runs iris merge every start (AD-23 kept) or reword AD-23 and Rule 21; spine Deferred
- 2026-10-18T18:21:16Z status=decision-pending owner=burndown by=cr note=evidence: a failed merge leaves no .last_merge and IRIS running; next start retries it; merge runs after IRIS starts
- 2026-10-18T20:17:25Z status=routed owner=0-2-the-package-installs-and-upgrades-itself-at-every-start by=spec_gate note=author 2026-10-18: after-start script re-runs iris merge with the image merge file at every start; AD-23 amended
- 2026-10-19T01:13:57Z status=resolved-by:0-2-the-package-installs-and-upgrades-itself-at-every-start by=adjudication note=after-start.sh re-merges a fresh copy of merge.cpf every start; test-install-start row 2 restores a hand-removed IRIS.IF.* map; row 8 pins merge failure

### DW-2: The judges' compose file needs Docker Compose 2.24 or later (env_file with required: false), and nothing checks or states it
- source: spec-0-1-the-image-builds-and-starts-ocutalon-in-its-own-namespace.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: docker-compose.yml uses the env_file long form (path, required: false), which Compose before 2.24.0 rejects; Story 10.1 checks only that Compose v2 is present
- 2026-10-18T18:21:16Z status=routed owner=10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to by=cr note=install.sh refuses Compose below 2.24 with the exact fix; Story 10.2's README states the minimum
- 2026-10-23T20:37:08Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=adjudication note=install.sh_half_resolved_by_10-1(refuses_Compose_below_2.24_with_the_exact_fix;matrix_rows_compose-too-old/new-enough_pinned_in_test-install-script.sh);residual:the_README_states_Compose_2.24_as_the_minimum(Story_10.2)

### DW-3: The judges' compose file publishes the web port on every host interface
- source: spec-0-1-the-image-builds-and-starts-ocutalon-in-its-own-namespace.md | severity: med | fix-risk: low | footprint: in-story
- evidence: ports ${OCUTALON_WEB_PORT:-52773}:52773 binds 0.0.0.0, so the Management Portal is reachable from the LAN while a fresh volume holds the base image's default predefined-account password, and AD-23 adds ocutalon/ocutalon
- 2026-10-18T18:21:16Z status=decision-pending owner=burndown by=cr note=author decides: 127.0.0.1 by default with a LAN opt-in, or every interface as specified (spine Deferred, Rule 20)
- 2026-10-18T20:17:25Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=spec_gate note=author 2026-10-18: keep every interface as built (AD-23); README warns the port is LAN-open until passwords change
- 2026-10-19T06:33:18Z note=README also tells the judge plainly to change the README account password after first sign-in (DW-6; Contest Planner 2026-10-19)

### DW-4: A hash-route deep link such as /ocutalon/#/x is lost at sign-in (the fragment never reaches the server, so the 303 lands on /ocutalon/)
- source: spec-0-3-sign-in-to-an-empty-ocutalon-page.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: Error:FullURL and the 303 Location carry no fragment; harmless until the first hash route ships (Epic 2 frame)
- 2026-10-19T05:10:58Z status=routed owner=2-1-lay-out-the-main-page-frame by=harvest note=Rule 22 ruling: routed, not wontfix, because Story 2.1 adds the first routes and the defect then becomes certain; fix in Shell/signin.js

### DW-5: On the non-Health image the namespace's default application /csp/ocutalon serves the bundle folder without sign-in and without the shell's policy
- source: spec-0-3-sign-in-to-an-empty-ocutalon-page.md | severity: med | fix-risk: high | footprint: out-of-footprint
- evidence: Probe (iris-community 154): /csp/ocutalon (merge CreateNamespace, Path /durable/iris/csp/ocutalon, ServeFiles 2) answers 200 for index.html and main-*.js with no session and no CSP header; Health image 404
- 2026-10-19T06:11:45Z status=escalated owner=burndown by=cr note=AD-23 folder = non-Health default app's; own folder (AD-23, row 14) or ServeFiles 3 on /csp/<ns>; Rule 22.3
- 2026-10-19T06:15:51Z status=routed owner=0-5-live-events-and-the-rest-skeleton by=merge_gate note=Rule 22 ruling: bundle to its own durable folder csp/ocutalon-web/ (AD-23 amended); IRIS's /csp/ocutalon app left alone (portal uses it); VETO WINDOW
- 2026-10-19T06:33:18Z note=Story 0.5 live test on the non-Health image checks the 404 at /csp/ocutalon and the bundle at the new folder (Contest Planner 2026-10-19)
- 2026-10-19T14:02:35Z status=resolved-by:0-5-live-events-and-the-rest-skeleton by=adjudication note=bundle in csp/ocutalon-web/; RemoveOldBundle; test-bundle-folder.sh shows /csp/ocutalon 404 and the new folder served on both images

### DW-6: A cross-site page can post a sign-in, with IRIS's password-change fields, to a local /ocutalon/: no CSRF token, and IRIS takes a password change in any sign-in request
- source: spec-0-3-sign-in-to-an-empty-ocutalon-page.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: form-action 'self' binds only our own form; SessionScope 2 keeps the victim's cookie off but not a new session or a password change, which IRIS handles before the shell (AD-13, S7/S17; inference)
- 2026-10-19T06:11:45Z status=decision-pending owner=burndown by=cr note=Rule 22.3: keep as residual risk with a README line (10.2), or run AD-13's password-validation routine locally
- 2026-10-19T06:15:51Z status=wontfix-accepted owner=0-3-sign-in-to-an-empty-ocutalon-page by=merge_gate note=Rule 22: needs the published password; DW-3 README warns; reopen_if=a sign-in request changes a non-default password; VETO WINDOW

### DW-7: Test classes switch to %SYS, and AD-3's list of the classes that switch namespace does not name them
- source: spec-0-3-sign-in-to-an-empty-ocutalon-page.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Test.Install.Users and .Registry, Test.Web.Install and .Shell set $Namespace to %SYS to read security objects; AD-3 lists runtime and installer classes only; no check enforces the list yet
- 2026-10-19T06:11:53Z status=wontfix-accepted owner=0-3-sign-in-to-an-empty-ocutalon-page by=cr note=reopen_if=a check enforces AD-3's namespace list over src/ (then add OcuTalon.Test.* to AD-3 under Rule 20)

### DW-8: The %SYS fixture helpers (delete by prefix, CreateRoles) are repeated in each new test class (Rule 2)
- source: spec-0-3-sign-in-to-an-empty-ocutalon-page.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Clean() in Test.Web.Install, Test.Web.Shell and Test.Install.Users, and CreateRoles in Test.Web.Install and Test.Install.Users, repeat one pattern with their own prefixes, 6 to 12 lines each
- 2026-10-19T06:11:53Z status=wontfix-accepted owner=0-3-sign-in-to-an-empty-ocutalon-page by=cr note=reopen_if=a fourth test class repeats the delete-by-prefix or CreateRoles helper (then extract one OcuTalon.Test fixture class)

### DW-9: flake: OcuTalon.Test.Install.Users:TestEnsureCreates read an empty password hash once (1 of 7 runs on slot A), then passed on 3 unchanged reruns
- source: fresh_check 0.3 | severity: med | fix-risk: low | footprint: in-epic
- evidence: Account() reads object.Password_object.Salt via Security.Users.Exists(user,.object); fixture name is always ZzUsers1 because Clean() kills the counter (inference: stale object or read-after-create timing)
- 2026-10-19T06:31:36Z status=routed owner=burndown by=harvest note=fresh-check flake, priority: make the hash read deterministic (unique fixture name per run, re-open the object); product path proven by Playwright README sign-in
- 2026-10-20T19:34:14Z status=routed owner=0-12-epic-0-burn-down by=burndown note=chartered into Story 0.12 (Epic 0 burn-down)
- 2026-10-21T03:00:27Z status=resolved-by:0-12-epic-0-burn-down owner=0-12-epic-0-burn-down by=adjudication note=cause found by QA: the binary hash can hold the | the test split on; Account returns the hash length; unique ZzUsers<n>; 11 consecutive slot A runs green

### DW-10: Nothing reports that instance-wide auditing is off, so on such an instance (an IPM install into an existing instance) the six events register and no entry is ever written
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Bridge.Installer, Step.Audit and Bridge.Audit.Write never read Security.System AuditEnabled; build 154 has it on by default (measured), an existing instance may not
- 2026-10-19T08:48:58Z status=routed owner=3-7-every-action-and-governance-event-is-in-the-iris-audit-log by=harvest note=Audit step warns plainly (log warning + a status the security overview and README point to); never changes the setting (AD-17; Contest Planner 2026-10-19)

### DW-11: AC5 (each Storage block equals the compiler's output) is checked once by a load-compile-export round trip, not by a recurring CI check
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: test-storage.sh checks only that a Storage Default block exists and its DataLocation; a hand-edited block fails no test
- 2026-10-19T08:48:58Z status=routed owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=harvest note=the IRIS checks job runs the round trip and fails on any storage-block difference
- 2026-10-20T00:45:56Z status=resolved-by:0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=adjudication note=test-storage-roundtrip.sh in IRIS group image with an in-run control; green in run 39338702672

### DW-12: Data.Time.ToLocal and Zone() read the process TZ; no test runs them in a production job started with the container's TZ (inference that jobs inherit it)
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: row 8 sets the test process TZ only; a wrong job TZ would show catalog and reminder times in the wrong zone
- 2026-10-19T08:48:58Z status=routed owner=0-9-the-message-catalog-and-its-one-renderer by=harvest note=Task 0 in 0.9: throwaway with a compose-level TZ, call ToLocal from a production job (0.6's stubs exist by then)
- 2026-10-19T09:48:41Z occurrence=0-4-the-cross-lane-message-and-data-contracts by=cr note=also: with TZ unset on a non-UTC host (IPM install outside the image) Zone() says UTC while ToLocal uses the OS zone
- 2026-10-19T09:51:16Z occurrence=0-4-the-cross-lane-message-and-data-contracts by=cr note=with TZ unset on a non-UTC host (IPM install outside the image) Zone() says UTC while ToLocal uses the OS zone
- 2026-10-20T06:55:28Z status=resolved-by:0-9-the-message-catalog-and-its-one-renderer owner=0-9-the-message-catalog-and-its-one-renderer by=adjudication note=Task 0 measured jobs inherit TZ; test-production.sh checks it; residual routed to 15.2 as DW-34

### DW-13: test-storage.sh treats only %Persistent, Ens.Request and Ens.Response as storage roots, so a business process or Ens.MessageBody subclass escapes the storage-block and DEFAULTGLOBAL checks
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: check.awk roots (test-storage.sh:54) omit Ens.BusinessProcess (persistent, irislib/Ens/BusinessProcess.cls:7), Ens.MessageBody and Ens.StreamContainer; no such class exists in src/ yet
- 2026-10-19T09:48:41Z status=routed owner=0-6-every-release-1-production-item-runs-as-a-stub-beside-the-or by=cr note=0.6 adds the BP stubs: extend roots, exempt Ens.MessageBody/Ens.BusinessProcess extents from DEFAULTGLOBAL, add bad samples
- 2026-10-19T09:51:16Z note=the occurrence line above belongs to DW-12 (filed here by mistake at cr; restated there by the lead)
- 2026-10-19T18:50:04Z occurrence=0-6-every-release-1-production-item-runs-as-a-stub-beside-the-or by=cr note=med: AD-3 L138 exempts only messages; the business-process exemption needs its Rule 20 amendment
- 2026-10-19T19:12:22Z status=resolved-by:0-6-every-release-1-production-item-runs-as-a-stub-beside-the-or by=adjudication note=test-storage.sh roots now include Ens.BusinessProcess, Ens.MessageBody, Ens.StreamContainer with bad samples; AD-3 carve-out for business processes written into the spine

### DW-14: ApiClient has no browser-envelope support: a non-GET call needs Content-Type: application/json and X-OcuTalon-Request: 1, which Angular does not send by default
- source: spec-0-5-live-events-and-the-rest-skeleton.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: the API refuses a state-changing call without both (403 not_json / no_request_header); ApiClient has no POST or DELETE yet
- 2026-10-19T12:43:59Z status=routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=harvest note=Rule 22 ruling: routed, not wontfix, because 2.2 adds the first POST (session/end) and the gap then becomes certain

### DW-15: Web.Api State and Events resolve the caller's session with Session.ForUser($Username), outside Data.Ownership (AD-4), so 16.3 has two lookups to replace
- source: spec-0-5-live-events-and-the-rest-skeleton.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Api.cls State() and Events() call Data.Session.ForUser($Username) and read Live.Event.Since directly. AD-4 says REST reads go through Ownership; Stories 2.2 (AC 17) and 16.3 (one session per visitor) expect Ownership to resolve the caller's SessionRef from the CSP session, never the IRIS user name. Isolation holds today (one durable session per user).
- 2026-10-19T13:50:49Z status=routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=2.2: resolve State/Events' session via Ownership; lead reconciles AD-4's last bullet with AD-13's Oct 19 amendment

### DW-16: On the online demo every visitor shares one IRIS account, so session resolution by user name would merge visitors; the one Ownership lookup (DW-15) needs a per-sign-in / resume-cookie branch
- source: Contest Planner note 2026-10-19 (0.5 review) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Session.ForUser($Username) is right locally (AD-13 interim); FR-15 and AD-4 need one session per visitor on the shared account
- 2026-10-19T17:28:35Z status=routed owner=16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re by=cr note=16.3 extends Ownership's resolution (one method, 2.2) with the per-sign-in branch; test: two sign-ins of the shared demo account get different sessions
- 2026-10-21T03:37:13Z status=routed owner=29-2-signing-in-opens-a-session-this-browser-resumes-until-the-re by=lead note=owner decision Oct 20: moved from 16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re
- 2026-10-21T13:18:50Z owner=16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re by=load note=renumbered_at_the_unattended_launch:Story_29.2_is_Story_16.3_again(owner_decision,worked_out_with_the_Contest_Planner)

### DW-17: Unchecked SQL prepares (%Prepare(sql,0)) are allowed by AD-13 only for the API's two ownership-filtered queries; nothing stops the exception spreading
- source: Contest Planner note 2026-10-19 (0.5 review) | severity: med | fix-risk: low | footprint: in-epic
- evidence: Session.ForUser and Live.Event use %Prepare(sql,0), parameterized and ownership-filtered; no check fails on a new unchecked prepare
- 2026-10-19T17:28:35Z status=routed owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=cr note=0.7's checks job fails on any unchecked prepare outside an allow-list naming those two
- 2026-10-20T00:45:56Z status=resolved-by:0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=adjudication note=test-class-rules.sh unchecked-prepare keyed by class:method, stale entry fails; checks job green

### DW-18: .gitattributes forces LF for docker/**, src/** and web/** but not ci/**, so a Windows checkout with core.autocrlf=true gives ci/*.sh CRLF endings and breaks them
- source: _bmad-output/implementation-artifacts/spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: low | fix-risk: low | footprint: in-story
- evidence: ci/*.sh run only on Linux runners and bash dev machines today; docker/** has the rule because the image copies its scripts
- 2026-10-19T23:00:06Z status=open owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=harvest note=one-line .gitattributes rule; adjudicate at 0.7's gate
- 2026-10-20T00:45:56Z status=resolved-by:0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=adjudication note=.gitattributes gains ci/** text=auto eol=lf (code-review patch)

### DW-19: release-diff reads files at HEAD (git show), not the working tree, so a hand edit of a committed Storage block shows red only after it is committed
- source: _bmad-output/implementation-artifacts/spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: low | fix-risk: med | footprint: in-story
- evidence: the roundtrip rule (image built from the working tree) and the storage rule catch the same edit earlier
- 2026-10-19T23:00:06Z status=open owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=harvest note=adjudicate at 0.7's gate
- 2026-10-20T00:45:56Z status=wontfix-accepted owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=adjudication note=reopen_if=a hand edit of a committed Storage block is committed while roundtrip and storage rules stay green

### DW-20: The public-package check (Test.Web.Status) misses embedded SQL, query bodies, globals, macros, XECUTE and @ indirection, $PROPERTY, projections and includes
- source: spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: med | fix-risk: high | footprint: in-story
- evidence: AD-3: CI fails if either public package references anything outside its allow-list; the scan reads ##class, $SYSTEM, four dispatch functions, superclasses and member types only. No public class uses the missed forms today (grep, 2026-10-19).
- 2026-10-20T00:40:42Z status=escalated owner=burndown by=cr note=pre-existing scope; needs an ObjectScript reference scanner; lead: amend AD-3 to the covered forms or charter a story
- 2026-10-21T03:43:29Z status=wontfix-accepted owner=burndown by=merge_gate note=Rule 22 decision sheet: AD-3 names what the check reads; the public packages hold six small reviewed classes and use none of the missed forms; reopen_if=a public-package class uses embedded SQL, a global, a macro, XECUTE, @ indirection, $PROPERTY, a projection or an include

### DW-21: REL-4's 30 minutes holds only by dispatch order: the five IRIS groups (largest 14.6 min, about 50 runner-minutes) can schedule to about 32 min on two runners
- source: spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: med | fix-risk: high | footprint: in-story
- evidence: Run 39338702672 took 27 min 37 s; install started fourth after a 13 min queue. List scheduling of its measured jobs gives 27.1 min at best and about 32 min at worst; a push with an open PR also starts a second matrix.
- 2026-10-20T00:40:42Z status=escalated owner=burndown by=cr note=install split makes 6 groups (AD-22 says five), worst case 31.5 min; real fixes: one stack for both shards, or a third runner (spend)
- 2026-10-20T01:30:58Z occurrence=0-8-the-demo-path-test-signs-in-and-loads-the-page note=demo-path unit adds about 3 runner-minutes to browser; worst-case bound grows about 1.5 min
- 2026-10-20T13:15:52Z occurrence=0-10-the-orders-demo-production-runs-in-ocuorders note=install 13:49 at 916ff92; QA+cr fixtures add ~0.6-1.4 min x64 (inference); chain ~26-27 of 30 min
- 2026-10-20T18:15:26Z status=wontfix-accepted owner=burndown by=owner note=owner decision 7: REL-4 is 35 minutes; rebalance first; reopen_if=a ci run on an epic head exceeds 35 minutes after rebalancing (then a third runner service via the Contest Planner)

### DW-22: The spine lags two Story 0.7 implement rulings: AD-3 does not allow system datatype classes as types, and AD-5 lacks the slot-keeps-its-number-and-property rule
- source: spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Test.Web.Status TypeOutside allows %-prefixed datatype classes (Spec Change Log ruling); test-storage.sh release-diff checks slot triples (review ruling). AD-3 (spine L135) and AD-5 (L181) say neither.
- 2026-10-20T00:40:42Z status=routed owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=cr note=lead: Rule 20 spine write for AD-3 and AD-5 at ledger_adjudicated, then resolved-by
- 2026-10-20T00:45:56Z status=resolved-by:0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=adjudication note=spine AD-3 (datatype types, what the scan reads) and AD-5 (slot keeps number and property) amended

### DW-23: A push to a branch with an open same-repository pull request starts two full IRIS matrices (the push run and the PR run), about 100 runner-minutes
- source: spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Both workflows trigger on push to main, feature/OCT_OcuTalon_MVP and OCT-epic* and on every pull_request; the concurrency groups differ (run id against PR number), and a pull request never skips.
- 2026-10-20T00:40:42Z status=by-design owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=cr note=spec-bound triggers (AC6, test-ci-config triggers rule); reopens via a spec amendment or Story 11.5's pull-request flow

### DW-24: unchecked-prepare flags a %PrepareClassQuery whose third argument is 3 (privilege bit set), or a %Prepare with $$$YES, though both are checked calls
- source: spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: low | fix-risk: low | footprint: in-story
- evidence: The rule flags any argument other than the literal 1 (spec AC3 table); in irislib %SQL.Statement bit 1 of pFlags is the privilege check. No such call exists in src/.
- 2026-10-20T00:40:42Z status=by-design owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=cr note=spec-bound, fails closed (a red, never a false green); a caller writes 1

### DW-25: api.spec.ts reads eight sign-in unit variables at import, so npm --prefix web run e2e -- --list exits 1 with no test listed unless they are set
- source: _bmad-output/implementation-artifacts/spec-0-8-the-demo-path-test-signs-in-and-loads-the-page.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: measured in 0.8 Task 0: OCUTALON_E2E_VERSION must be set, Total: 0 tests; the unit and the summary test set them
- 2026-10-20T02:29:16Z status=open owner=0-8-the-demo-path-test-signs-in-and-loads-the-page by=harvest note=deferring the reads into the tests touches 0.5's spec file; adjudicate at 0.8's gate
- 2026-10-20T03:35:26Z status=resolved-by:0-8-the-demo-path-test-signs-in-and-loads-the-page owner=0-8-the-demo-path-test-signs-in-and-loads-the-page by=adjudication note=QA made api.spec.ts read its variables lazily; bare e2e --list exits 0; CR ran live sign-in green (29 passed)

### DW-26: On a developer machine the 540 s run deadline ends the first-start wait before the 720 s WARN threshold, so only CI (1200 s) can print the WARN line
- source: _bmad-output/implementation-artifacts/spec-0-8-the-demo-path-test-signs-in-and-loads-the-page.md | severity: low | fix-risk: low | footprint: in-story
- evidence: local first start measured 47-53 s; the gap shows only on a host about ten times slower
- 2026-10-20T02:29:16Z status=open owner=0-8-the-demo-path-test-signs-in-and-loads-the-page by=harvest note=adjudicate at 0.8's gate
- 2026-10-20T03:35:26Z status=by-design owner=0-8-the-demo-path-test-signs-in-and-loads-the-page by=adjudication note=spec fixes the 900 s wait bounded by the run deadline; WARN path pinned by test-demo-path-gate.sh and test-lib-live.sh

### DW-27: REL-2 runs the demo path on every pull request, but 0.7's fork guard keeps every self-hosted job, the demo path included, off fork pull requests; once the repository is public a fork PR could merge with no demo-path run
- source: spec-0-8-the-demo-path-test-signs-in-and-loads-the-page.md | severity: med | fix-risk: med | footprint: out-of-epic
- evidence: ci.yml iris job if: push or same-repository PR (CON-1, REL-4); code review of 0.8, October 20
- 2026-10-20T03:35:26Z status=routed owner=11-5-one-scripted-sequence-cuts-a-release by=adjudication note=branch protection or a maintainer-run path must require the demo path for fork PRs before the repo goes public (owner-only settings)

### DW-28: flake: test-production.sh's two 'another production' checks failed once on the first run with the compose-level TZ file, then passed on three unchanged reruns
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 0.9 implement report: one red run of the DW-12-extended script on throwaway v09a, three greens after; inference that it is timing
- 2026-10-20T05:25:07Z status=routed owner=burndown by=harvest note=flake, priority; occurrence=1
- 2026-10-20T05:55:57Z occurrence=0-9-the-message-catalog-and-its-one-renderer note=ci run 39374739457 iris (production): ZzOther StopProduction(30) timed out at 30.5 s; second occurrence, both since 0.9 extended test-production.sh
- 2026-10-20T06:51:54Z status=routed owner=0-9-the-message-catalog-and-its-one-renderer by=cr note=cause: stop right after start races Ens.ScheduleHandler on ^Ens.Runtime (5/15 vs 0/15 settled); patched in review
- 2026-10-20T06:55:28Z status=resolved-by:0-9-the-message-catalog-and-its-one-renderer owner=0-9-the-message-catalog-and-its-one-renderer by=adjudication note=race patched in review (0/15 settled vs 5/15); the next push's iris (production) confirms, else reopen

### DW-29: Banner keys with a {time} slot render as message times in the instance zone, while the UX says banner times are page times in the browser's zone
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 0.9 Rule 22 ruling: Render renders times only through Data.Time.ForMessage; EXPERIENCE banner table; Story 2.10 renders the banners
- 2026-10-20T05:25:07Z status=routed owner=2-10-show-status-banners-for-a-missing-key-or-a-stalled-heartbeat by=harvest note=2.10 decides: pass a web-formatted time, or render the banner's time in the browser
- 2026-10-20T06:51:54Z occurrence=0-9-the-message-catalog-and-its-one-renderer by=cr note=also the web cards' answered statuses (Formats: page time beside message text, 20:15 CEST): 6.3/6.4 follow 2.10

### DW-30: Nothing limits a rendered text's length, while Telegram caps a message at 4,096 characters, so a long model-written slot could make sendMessage fail
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: out-of-epic
- evidence: 0.9 implement report; Msg.Catalog.Render has no length cap; Bot API sendMessage limit
- 2026-10-20T05:25:07Z status=routed owner=12-6-chat-and-get-notifications-in-the-paired-telegram-chat by=harvest note=TelegramOut truncates or splits per the UX before sendMessage
- 2026-10-20T06:51:54Z occurrence=0-9-the-message-catalog-and-its-one-renderer by=cr note=code review sighting (edge-case hunter): incident.fallback/noFix groups and slots have no length cap

### DW-31: AD-32's older sentence can read as putting the Results keys in Catalog.Core, while its Story 0.9 bullet and the code put result.* in Catalog.Watch
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: AD-32 Rule bullet 4 ('including the answered statuses and Results and Telegram's pairing replies and press alerts (in Catalog.Core)') vs the AMENDED 2026-10-20 bullet; Watch.cls holds result.*
- 2026-10-20T06:52:09Z status=wontfix-accepted owner=0-9-the-message-catalog-and-its-one-renderer by=cr note=reopen_if=a story places a result.* key in Catalog.Core citing AD-32; the lead may tidy the sentence (Rule 20)
- 2026-10-20T06:55:29Z status=resolved-by:0-9-the-message-catalog-and-its-one-renderer owner=0-9-the-message-catalog-and-its-one-renderer by=adjudication note=AD-32 sentence tidied: Results in Catalog.Watch

### DW-32: Test.Msg.Catalog repeats Test.Data.Time's process-zone save and restore (SavedZone, RestoreZone and the hooks), a Rule 2 copy with a weak reason
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Test/Msg/Catalog.cls SavedZone, OnBeforeAllTests, OnAfterOneTest, RestoreZone vs Test/Data/Time.cls L6-25 and RestoreZone; the spec names Test.Data.Time as the pattern
- 2026-10-20T06:52:09Z status=wontfix-accepted owner=0-9-the-message-catalog-and-its-one-renderer by=cr note=reopen_if=a third test class copies SavedZone/RestoreZone: extract one zone fixture base that ci/units.sh does not run

### DW-33: Msg.Catalog.ReadEntries repeats Test.Contract.Read's three-line JSON XData read, a copy the spec states (product code may not depend on OcuTalon.Test)
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Msg/Catalog.cls ReadEntries (CompiledXData %OpenId + %FromJSON) vs Test/Contract.cls Read; spec Tasks and Design Notes > Reuse name the copy; no story is planned to unify it
- 2026-10-20T06:52:09Z status=wontfix-accepted owner=0-9-the-message-catalog-and-its-one-renderer by=cr note=reopen_if=another product class reads a JSON XData block: extract one product reader that Test.Contract.Read also calls

### DW-34: With TZ unset on a non-UTC host (an IPM install outside the image), Data.Time.Zone() reports UTC while ToLocal converts in the operating system's zone, so message times and the model preamble's zone can disagree
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: out-of-epic
- evidence: 0.9 Task 0: the image has TZ unset and /etc/localtime at UTC, so Docker installs agree; DW-12's declined residual
- 2026-10-20T06:55:28Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=adjudication note=an IPM install derives the instance zone from the OS, or the install sets it, and a test checks Zone() against ToLocal

### DW-35: A failed Orders header has Status 8 (Error), IsError 0 and an empty ErrorStatus; its error text is only the event-log row inside the Terminating BP wrapper, so a reader that keys on IsError or GetErrorText finds no failure
- source: spec-0-10-the-orders-demo-production-runs-in-ocuorders.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: measured in 0.10 Task 0.3b on build 154: IsError and ErrorStatus are set only on error response headers; the partner sends asynchronously
- 2026-10-20T10:54:10Z status=routed owner=5-2-new-failures-are-picked-up-within-seconds by=harvest note=Lane A's poller and evidence (5.2, 5.4, 6.1's fallback line) key on Status 8 and the event log and parse the sentence out of the wrapper

### DW-36: The Demo step's non-Health image path (ENSTEMP and SECONDARY databases, the SECONDARY resource and role the off path removes) has no run in the repository or in CI
- source: spec-0-10-the-orders-demo-production-runs-in-ocuorders.md | severity: med | fix-risk: high | footprint: in-epic
- evidence: CI and ci/iris.sh hold only the Health base; 0.10 Task 0 step 4's hand run is the only evidence; deleting that removal keeps every check green
- 2026-10-20T10:54:10Z status=escalated owner=burndown by=harvest note=needs the non-Health base on the runner (a runner change) or a local-only recipe run; lead decides at the decision sheet
- 2026-10-20T18:15:26Z status=wontfix-accepted owner=burndown by=owner note=owner decision 3: no plain-image CI run; IRIS for Health is the tested image; README says plain IRIS supported, verified on ARM64; reopen_if=the owner asks for a plain-image CI run

### DW-37: Demo.Orders() and Demo.System() branches reached only from a foreign or partial state (a foreign OCUORDERS production, RecoverProduction, the start timeout, another database directory, a mapping Modify, a directory with no CPF entry) have no test
- source: spec-0-10-the-orders-demo-production-runs-in-ocuorders.md | severity: med | fix-risk: med | footprint: in-story
- evidence: rows 1-8 start from all-absent or all-present; deleting the foreign-production guard keeps them green
- 2026-10-20T10:54:10Z status=open owner=0-10-the-orders-demo-production-runs-in-ocuorders by=harvest note=QA adds foreign-state fixtures inside existing install-script rows, in the style of ZzOther.Production
- 2026-10-20T12:14:11Z status=resolved-by:0-10-the-orders-demo-production-runs-in-ocuorders by=qa note=foreign-state fixtures in test-install-start.sh rows 3 and 4; foreign-production guard mutation red; see spec Verification QA pass
- 2026-10-20T13:21:23Z status=resolved-by:0-10-the-orders-demo-production-runs-in-ocuorders owner=0-10-the-orders-demo-production-runs-in-ocuorders by=adjudication note=QA fixtures cover all six branches (verified in code review); CR added the stopped-foreign and off-while-running fixtures

### DW-38: Compiling OcuTalon.Demo.Orders.Production in OCUTALON registers an Ens.Config.Production row there (description Orders) at every install, demo mode on or off, so a cross-namespace match of Orders by display name finds a second, never-running Orders production in OCUTALON
- source: spec-0-10-the-orders-demo-production-runs-in-ocuorders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: 0.10 Spec Change Log ruling 3 measured it; on slot A (no OCUORDERS) Ens.Config.Production.%ExistsId(OcuTalon.Demo.Orders.Production) in OCUTALON is 1; 5.1 matches by display name across every readable namespace (FR-23)
- 2026-10-20T13:15:44Z status=routed owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=cr note=5.1's Watch.Reader match keys on each namespace's own production (GetProductionStatus), or OCUORDERS only for Orders

### DW-39: The CI mock picks an agent's default script by its MOCKKEY, which reaches the mock only as the x-ocutalon-mockkey request header that the Provider step must add whenever OCUTALON_MODEL_BASE_URL is set
- source: spec-0-11-the-ci-model-mock-answers-every-scenario-the-stories-need.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 0.11 Rule 22 ruling; Install.Step.Provider is Lane A's only provider writer (AD-19) and is built in 1.1
- 2026-10-20T14:30:01Z status=routed owner=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=planning note=1.1's Provider step writes http_config.custom_headers x-ocutalon-mockkey=<the agent class's MOCKKEY> only with OCUTALON_MODEL_BASE_URL set
- 2026-10-20T18:15:26Z status=routed owner=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=owner note=owner decision 5: header only when OCUTALON_MOCK_KEY_HEADER=1 (CI-only), never from OCUTALON_MODEL_BASE_URL alone; online demo never carries it

### DW-40: Test.Contract.Mock's guard failure path (OCUTALON_MODEL_BASE_URL not the mock's) has no automated run: CI always runs under the mock's value
- source: _bmad-output/implementation-artifacts/spec-0-11-the-ci-model-mock-answers-every-scenario-the-stories-need.md | severity: low | fix-risk: low | footprint: in-story
- evidence: TestBaseUrlGuard pins CheckBaseUrl on seven values; the consequence was shown by hand in throwaway v11a
- 2026-10-20T17:00:03Z status=open owner=0-11-the-ci-model-mock-answers-every-scenario-the-stories-need by=harvest note=adjudicate at 0.11's gate
- 2026-10-20T19:26:26Z status=wontfix-accepted owner=0-11-the-ci-model-mock-answers-every-scenario-the-stories-need by=adjudication note=QA narrowed it to the two environment reads; the guard's logic is pinned in-process; reopen_if=a throwaway run with another OCUTALON_MODEL_BASE_URL builds a provider or passes a provider test

### DW-41: Owner decision 1 (October 20): add the count-of-one, late-press and sign-in-label texts now fixed in EXPERIENCE.md to Catalog.Core and Catalog.Watch and remove the matching gap fields
- source: owner decision 1, 2026-10-20 (EXPERIENCE.md, Results) | severity: med | fix-risk: low | footprint: in-epic
- evidence: nine gap keys plus answered.alreadyApproved's gap (Test.Msg.Catalog Gaps list); the sign-in labels sit outside the catalog and Test.Web.PublicTexts
- 2026-10-20T18:15:26Z status=routed owner=burndown by=owner note=burn-down: catalog entries with count-of-one forms picked by count; Gaps list emptied for these keys; PublicTexts compares the three labels
- 2026-10-20T19:34:14Z status=routed owner=0-12-epic-0-burn-down by=burndown note=chartered into Story 0.12 (Epic 0 burn-down)
- 2026-10-21T03:00:27Z status=resolved-by:0-12-epic-0-burn-down owner=0-12-epic-0-burn-down by=adjudication note=owner texts in Catalog.Core/Watch with one forms picked by their own count slot; Gaps list empty; sign-in labels compared (11/0/19)

### DW-42: Owner decision 2 (October 20): with demo mode off, an OCUORDERS that OcuTalon didn't create or that holds any production other than the Orders demo is left in place with a logged warning and a status note on removing it by hand, and the start finishes with the ready marker
- source: owner decision 2, 2026-10-20 (Story 0.10 review item) | severity: med | fix-risk: low | footprint: in-epic
- evidence: 0.10's code review made the off path fail the start (STEP Demo FAILED, no ready marker) in that case
- 2026-10-20T18:15:26Z status=routed owner=burndown by=owner note=burn-down: Install.Step.Demo off path keeps and warns instead of failing; test-install-start.sh's stopped-foreign fixture expects the warning, the note and the ready marker
- 2026-10-20T19:34:14Z status=routed owner=0-12-epic-0-burn-down by=burndown note=chartered into Story 0.12 (Epic 0 burn-down)
- 2026-10-21T03:00:27Z status=resolved-by:0-12-epic-0-burn-down owner=0-12-epic-0-burn-down by=adjudication note=keep path keeps a foreign or other-production OCUORDERS, WARN line, demoKept mark with the owner's how sentence, ready marker; install-start 94 PASS

### DW-43: The spine's AD-22 'mock as built' names neither the countdown endpoint (/_mock/countdown) nor the reply rule that 0.11's Design Notes listed as spine updates
- source: spec-0-11-the-ci-model-mock-answers-every-scenario-the-stories-need.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Spec Design Notes 'Spine updates for the lead' list 'the countdown's endpoint and rule' and 'the reply rule'; AD-22 (spine L576-601) has neither; mock.mjs's header and Test.Contract.Mock's Arm/Remaining document both
- 2026-10-20T19:23:41Z status=wontfix-accepted owner=0-11-the-ci-model-mock-answers-every-scenario-the-stories-need by=cr note=reopen_if=a Lane A plan or test needs /_mock/countdown or the reply rule and AD-22 lacks both; lead may add them
- 2026-10-20T19:26:26Z status=resolved-by:0-11-the-ci-model-mock-answers-every-scenario-the-stories-need owner=0-11-the-ci-model-mock-answers-every-scenario-the-stories-need by=adjudication note=AD-22 now names /_mock/countdown and the reply rule (Rule 20)

### DW-44: The demoKept note does not say how to remove a kept OCUORDERS by hand (owner decision 2, AD-3), and the parked sentence is tracked nowhere
- source: spec-0-12-epic-0-burn-down.md (code review, acceptance-auditor) | severity: high | fix-risk: low | footprint: in-story
- evidence: Owner (cycle log L280): 'show a status note saying how to remove it by hand'; AD-3 L142 says the same. Demo.cls L356 writes {text,namespace,globals,routines}, text = 0.10's kept sentence; the spec parked the how-to sentence for the Contest Planner, but no outbox item or ledger row carries it
- 2026-10-21T02:03:59Z status=decision-pending owner=0-12-epic-0-burn-down by=cr note=lead rules under 22.3: draft the how-to sentence (VETO FYI), rework adds a how field (Demo.cls L356) + kept_note check
- 2026-10-21T02:07:36Z status=open owner=0-12-epic-0-burn-down by=owner note=owner approved the how-to sentence via the Contest Planner (Oct 21); rework adds the how field and pins it
- 2026-10-21T03:00:27Z status=resolved-by:0-12-epic-0-burn-down owner=0-12-epic-0-burn-down by=adjudication note=rework 5cba5e0 adds the how field with the owner's sentence; kept_note pins it; re-review found no HIGH or MED

### DW-45: The README must carry the owner's how-to-remove sentence for a kept OCUORDERS (EXPERIENCE.md owner forms table), and Story 10.2 has no AC for it
- source: spec-0-12-epic-0-burn-down.md | severity: low | fix-risk: low | footprint: out-of-epic
- evidence: 0.12 rework deferred item; the sentence exists only in Demo.cls and its tests
- 2026-10-21T02:41:40Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=harvest note=10.2 quotes the sentence where the README explains demo mode off

### DW-46: The security overview must carry the owner's how-to-remove sentence for a kept OCUORDERS (EXPERIENCE.md owner forms table), and Story 14.2 has no AC for it
- source: spec-0-12-epic-0-burn-down.md | severity: low | fix-risk: low | footprint: out-of-epic
- evidence: 0.12 rework deferred item
- 2026-10-21T02:41:40Z status=routed owner=14-2-the-security-overview-says-what-ocutalon-can-do-and-what-sto by=harvest note=14.2 quotes the sentence where it describes what demo mode off leaves in place

### DW-47: flake: web/e2e/sign-in/sign-in.spec.ts row 13 (sign-in at a deep link) ended at /ocutalon/#/ instead of /ocutalon/index.html?x=1 once on the runner, then passed on an unchanged rerun
- source: ci run 39534434817 attempt 1 (head 811102f) | severity: med | fix-risk: low | footprint: in-epic
- evidence: the 302 location was right (line 188 passed); toHaveURL saw the shell root; Story 0.12 changed nothing under web/; attempt 2 green
- 2026-10-21T03:42:30Z status=routed owner=2-1-lay-out-the-main-page-frame by=harvest note=flake, priority; occurrence=1; same area as DW-4 (deep link lost at sign-in)
- 2026-10-21T04:11:07Z status=open owner=0-12-epic-0-burn-down by=lead note=second red on fae0f9e (run 39540054243): a test race, not a flake; reopened 0.12 with a [CI] task (the first red commit is 811102f)
- 2026-10-21T04:37:20Z status=resolved-by:0-12-epic-0-burn-down owner=0-12-epic-0-burn-down by=adjudication note=row 13 now checks the 303 location, the 200 shell document and the title, not the post-boot URL (fe20df6); 3 local runs green; the x64 run confirms, else reopen

### DW-48: test-ci-config.sh's units and demo-path rules read only their violation functions' stdout, so a tree that cannot be read can print PASS (the new groups rule carries the guard)
- source: spec-32-1-the-install-group-runs-as-two-jobs.md | severity: low | fix-risk: low | footprint: in-story
- evidence: hits=$(units_violations ...) and hits=$(demo_path_violations ...) ignore the exit status; a set -u abort in the sourced ci/units.sh leaves stdout empty; other rules keep the suite red in realistic cases
- 2026-10-21T15:28:03Z status=open owner=32-1-the-install-group-runs-as-two-jobs by=harvest note=LOW two-way door in a file this story edits: for the code review to patch or close
- 2026-10-21T16:06:55Z status=resolved-by:32-1-the-install-group-runs-as-two-jobs by=adjudication note=cr patched test-ci-config.sh: real_hits helper guards the units, demo-path and groups real-tree reads; u-unread sample pins it; mutation recorded in spec Verification

### DW-49: ci/iris.sh gives the browser units a fixed web port (52810 + n) only for runners 1 to 9, so on ocutalon-ci-10 to -14 they probe for the first free port of 52800-52819, which two concurrent browser jobs on ocutalon-ci-c can both pick
- source: spec-32-1-the-install-group-runs-as-two-jobs.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: setup_tag (ci/iris.sh) sets OCUTALON_TEST_WEB_PORT only when the runner number is 9 or less; live_web_port (lib-live.sh) then probes and binds later, a check-then-use race; 5 of the 12 services (ci-c's 10-14) take it, and a red CI job re-opens a story
- 2026-10-21T16:04:07Z status=routed owner=burndown by=cr note=fix: map runners 10-19 to 52800-52809 in setup_tag (no fixed or forbidden port there) plus a recipe pin; Rule 21's 'is 52810 plus the runner's number' needs this
- 2026-10-21T16:21:02Z status=routed owner=32-3-every-iris-job-finishes-in-about-ten-minutes by=adjudication note=in-epic MED (ci/iris.sh is Epic 32's): Story 32.3 measures the real runners, and a port collision between two browser jobs on ocutalon-ci-c would turn its run red; fix in setup_tag (runners 10-19 to 52800-52809) plus a recipe pin
- 2026-10-21T20:50:08Z status=resolved-by:32-3-every-iris-job-finishes-in-about-ten-minutes by=adjudication note=setup_tag exports 52819-n on runners 10-19 (52809..52800, distinct from 52811..52819); test-ci-config recipe pins the mapping, distinctness and the child-process export; real-runner PORT lines are the lead CI check

### DW-50: test-ci-config.sh names the six IRIS groups as literals in both the groups rule and the recipe rule, so a change to the group set edits both
- source: spec-32-1-the-install-group-runs-as-two-jobs.md | severity: low | fix-risk: low | footprint: in-story
- evidence: groups_violations compares IRIS_GROUPS with the six names, and the recipe rule compares ci/iris.sh groups and the 'unknown group install' line with the same literal list
- 2026-10-21T16:04:12Z status=by-design owner=32-1-the-install-group-runs-as-two-jobs by=cr note=QA's recipe line is a deliberate, independent pin of the CLI output (spec QA files); a missed edit fails closed, never green

### DW-51: AC 1's clause 'install-upgrade holds live:audit after live:install-upgrade' has no pinning test: the groups rule pins only the two anchors, and its good sample g-moved puts live:audit back in production
- source: spec-32-1-the-install-group-runs-as-two-jobs.md | severity: low | fix-risk: low | footprint: in-story
- evidence: moving live:audit back to production, or into install-fresh, leaves matrix, groups, units and recipe green (g-moved is that tree)
- 2026-10-21T16:04:19Z status=by-design owner=32-1-the-install-group-runs-as-two-jobs by=cr note=Design Notes item 3: a whole-unit rebalance needs no test edit; the lead's per-unit CI times and AC 5's Rule 21 record name audit's group

### DW-55: IRIS jobs on ocutalon-ci-c run 1.4 to 3 times as long as on ocutalon-ci-b and miss the 400 s first-start limit, and the job holding install-start runs over 10 minutes on either host
- source: spec-32-3-every-iris-job-finishes-in-about-ten-minutes.md (lead CI check) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: run 39633794167: install-upgrade 19:18 on ci-c, raw 1.33x the mean, grouping 1.21x; run 39657913372: six stacks on ci-c, 9 units of two runs failed a start limit; run 39675383146 (no other run): every IRIS job on ci-c failed or crawled (first start ready 449-557 s against 150-250 s on ci-b), twice; install-start 550-681 s even on ci-b
- 2026-10-21T21:49:22Z status=decision-pending owner=burndown by=lead note=human=CI capacity: fix, resize or cap ocutalon-ci-c; a ~10 min job needs faster hosts
- 2026-10-21T22:10:11Z status=dropped by=unattended note=action_item:epic-32-retro-item-1-ci-capacity-dw-55-ocutalon-ci-c-starts-i(human=CI_capacity;decision_sheet_epic_32)

### DW-111: parallel.yaml lists no warm-iris lock, so the stale-lock rule (throwaway-iris, 20 minutes) does not describe a warm stack's lock, which is held for a whole stage
- source: spec-32-4-the-developer-loop-reuses-one-warm-throwaway-per-lane.md (plan, For the lead) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Story 32.4 adds warm-iris.lock in each lane folder (held from ci/warm.sh up to down); _bmad/custom/parallel.yaml runtime_locks names only runtime and throwaway-iris (stale_minutes 20); _bmad/ is owner-only
- 2026-10-23T13:41:30Z status=decision-pending owner=burndown by=spec_gate note=human=decide whether parallel.yaml gains a warm-iris entry (stale_minutes about a stage, e.g. 240) or the sweep rule names warm-iris.lock; the orchestrator's sweep already confirms the owner is dead before it deletes
- 2026-10-23T16:47:25Z status=dropped by=merge_gate note=action_item:epic-32-retro-item-2-add-a-warm-iris-entry-to-_bmad-custom-pa(owner;decided_unattended_U9:human-only_entry_to_action_items)

### DW-123: Two warm calls at once on one warm stack (or a killed call's IRIS session still running in it) race on its stored manifest and its test results; ci/warm.sh takes no run lock
- source: spec-32-4-the-developer-loop-reuses-one-warm-throwaway-per-lane.md | severity: med | fix-risk: med | footprint: in-story
- evidence: warm_reload reads and rewrites the stored manifest with no exclusion, so an interleaving can record a file as loaded that the stack holds in an older version (exit 0 on stale code)
- 2026-10-23T16:14:17Z status=wontfix-theoretical owner=32-4-the-developer-loop-reuses-one-warm-throwaway-per-lane by=cr note=theoretical under Rule 18 (one call at a time, a warm tag per stage); real if a stage runs warm calls in parallel

### DW-124: A warm reload trusts the IRIS session to print one CHK row per delete and import; an item with no row is neither counted nor failed, so a Load or Delete that threw mid-line could end in exit 0
- source: spec-32-4-the-developer-loop-reuses-one-warm-throwaway-per-lane.md | severity: med | fix-risk: low | footprint: in-story
- evidence: maybe-false (unverified medium): the source of %apiOBJ is not exported, so whether SYSTEM.OBJ Load or Delete can throw instead of returning a status was not settled
- 2026-10-23T16:14:20Z status=wontfix-theoretical owner=32-4-the-developer-loop-reuses-one-warm-throwaway-per-lane by=cr note=real if a warm session's output lacks a CHK row for a listed import or delete

### DW-127: live:install-script-live joins the image group with no x64 time on record, so Story 32.3's balance rule (no IRIS job over about 1.25x the six-job mean) is unchecked for it
- source: spec-10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to.md | severity: med | fix-risk: low | footprint: in-story
- evidence: lane C ARM runs 95 s and 83 s (two IRIS starts); image was 552 s on ci-b (run 39675383146); at compose-start's ARM-to-x64 ratio (80 to 246 s) image is about 810-920 s against a mean near 710-730, at or under the limit (inference)
- 2026-10-23T20:32:41Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=cr note=unverified: compare image job with 1.25x six-job mean on first CI run with the unit; if over, move one unit (DN 11)
- 2026-10-23T22:31:02Z status=resolved-by:10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to by=ci_resolution note=measured_on_CI:run_40032757987(green)_image_job_673s_vs_six-job_mean_583s(1.15x;longest_install-upgrade_702s=1.20x),run_40021886810_image_690s_vs_567s(1.22x);within_the_1.25_rule;unit_203s_on_ocutalon-ci-c

### DW-134: The README's key and update steps must use the commands install.sh prints: a rerun of ./install.sh now leaves a healthy OcuTalon alone (U-45), so it applies neither a new key nor an update
- source: spec-10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: install.sh:317 prints 'add it to .env and run: docker compose up -d --force-recreate' and :398 'To apply an update, run: docker compose up -d --build'; the healthy branch (:329) runs no compose up, and a container reads .env only when created; the banner text (epics.md:1781) says only 'restart OcuTalon'
- 2026-10-23T22:06:04Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=cr note=README must not say rerun install.sh for a key/update or to wait for a start in progress; docker compose restart does not reread .env
