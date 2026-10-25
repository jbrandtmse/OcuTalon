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
- 2026-10-22T02:09:17Z status=resolved-by:2-1-lay-out-the-main-page-frame by=adjudication note=signin.js_appends_location.hash_to_the_form_action_once(de7dc48;Shell.cls_unchanged:a_fragment-less_303_Location_inherits_the_fragment);sign-in.spec.ts_DW-4_rows(#/x_and_index.html?q=1#/x_land_on_/ocutalon/#/x_after_boot;wrong_password_first;double_submit;no-fragment_lands_on_#/)_red_under_the_dropped_append_and_the_dropped_guard_mutations;56_of_56_chromium_on_throwaway_e2s21r

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
- 2026-10-24T15:47:10Z occurrence=3-1-roles-and-the-service-user-grant-only-what-the-architecture
- 2026-10-24T15:47:10Z status=wontfix-accepted owner=3-1-roles-and-the-service-user-grant-only-what-the-architecture by=cr note=4th copy: Test.Install.Registry Clean deletes ZzRegistry users by prefix; extraction spans Lane B Test.Web. reopen_if=a 5th test class repeats it

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
- 2026-10-25T12:50:32Z status=resolved-by:3-7-every-action-and-governance-event-is-in-the-iris-audit-log by=adjudication note=Audit_step_warns_when_instance_auditing_is_off_and_records_on/off/unknown_in_the_status_mark_instanceAuditing;never_changes_the_setting;Test.Install.Audit(4_tests,mutations)+live_audit_AD-17_row

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
- 2026-10-22T07:51:44Z status=resolved-by:2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=adjudication note=envelope.interceptor.ts_sets_Content-Type_and_X-OcuTalon-Request_on_POST/PUT/PATCH/DELETE_under_/ocutalon/api;session.spec_S1_(204_with_both_headers)_and_S2_(403_not_json/no_request_header);red_under_the_omitted-header_mutation

### DW-15: Web.Api State and Events resolve the caller's session with Session.ForUser($Username), outside Data.Ownership (AD-4), so 16.3 has two lookups to replace
- source: spec-0-5-live-events-and-the-rest-skeleton.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Api.cls State() and Events() call Data.Session.ForUser($Username) and read Live.Event.Since directly. AD-4 says REST reads go through Ownership; Stories 2.2 (AC 17) and 16.3 (one session per visitor) expect Ownership to resolve the caller's SessionRef from the CSP session, never the IRIS user name. Isolation holds today (one durable session per user).
- 2026-10-19T13:50:49Z status=routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=2.2: resolve State/Events' session via Ownership; lead reconciles AD-4's last bullet with AD-13's Oct 19 amendment
- 2026-10-22T07:51:44Z status=resolved-by:2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=adjudication note=Web.Api_State_and_Events_resolve_through_Ownership.SessionRef_(no_ForUser($Username)_left_in_Web.Api);TestPollsResolveTheCspSession_red_under_the_ForUser_mutation;Story_16.3_extends_the_one_resolution_method_(DW-16)

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
- 2026-10-25T04:09:47Z status=routed owner=11-5-one-scripted-sequence-cuts-a-release by=orchestrator note=owner decision via the Contest Planner 2026-10-25 (the owner: 'We won't make the repo public until we release on Open Exchange.'): GitHub Free gives a private repository no branch protection (HTTP 403), so branch protection, with the demo path required for fork pull requests, is set up at the public flip together with the Open Exchange release; while private, Story 11.5 checks every ci.yml and lane-a.yml job on the PR head itself (b258031)

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
- 2026-10-24T07:07:21Z status=resolved-by:2-10-show-status-banners-for-a-missing-key-or-a-stalled-heartbeat by=adjudication note=build ae0d062: the page formats each banner's UTC time slot as a page time in the browser's zone with no instance-zone suffix; banner-view.test.mjs, B4 (Asia/Kolkata) and B8 (New York, 12-hour)

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
- 2026-10-22T12:43:51Z occurrence=1-4-every-turn-and-decision-carries-its-tokens-and-cost
- 2026-10-22T12:46:48Z status=routed owner=1-10-the-chat-agent-sets-lists-and-cancels-reminders by=adjudication note=reopen_if fired at Story 1.4: Lane A now holds four copies of the process-zone save and restore (Test.Agent.Render, Test.Bridge.Time, Test.Bridge.Usage, Test.Bridge.Budget); Story 1.10 (reminders, zone-heavy tests) folds Lane A's copies into one Lane A test helper before adding its own; Lane B's two (Test.Data.Time, Test.Msg.Catalog) stay Lane B's
- 2026-10-24T03:01:40Z status=resolved-by:1-10-the-chat-agent-sets-lists-and-cancels-reminders by=adjudication note=Lane_A's_four_copies(Test.Agent.Render,Test.Bridge.Time,Usage,Budget)+Test.Bridge.Decide_now_extend_the_abstract_Test.Bridge.ZoneCase;Test.Bridge.Time.TestZoneCase_scans_for_any_other_zone_save/restore_and_TestZoneHooksCallSuper_pins_the_hooks;Lane_B's_two_copies(Test.Msg.Catalog,Test.Data.Time)_stay_the_original_low_wontfix-accepted_scope(Lane_B's_files)

### DW-33: Msg.Catalog.ReadEntries repeats Test.Contract.Read's three-line JSON XData read, a copy the spec states (product code may not depend on OcuTalon.Test)
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Msg/Catalog.cls ReadEntries (CompiledXData %OpenId + %FromJSON) vs Test/Contract.cls Read; spec Tasks and Design Notes > Reuse name the copy; no story is planned to unify it
- 2026-10-20T06:52:09Z status=wontfix-accepted owner=0-9-the-message-catalog-and-its-one-renderer by=cr note=reopen_if=another product class reads a JSON XData block: extract one product reader that Test.Contract.Read also calls

### DW-34: With TZ unset on a non-UTC host (an IPM install outside the image), Data.Time.Zone() reports UTC while ToLocal converts in the operating system's zone, so message times and the model preamble's zone can disagree
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: out-of-epic
- evidence: 0.9 Task 0: the image has TZ unset and /etc/localtime at UTC, so Docker installs agree; DW-12's declined residual
- 2026-10-20T06:55:28Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=adjudication note=an IPM install derives the instance zone from the OS, or the install sets it, and a test checks Zone() against ToLocal
- 2026-10-24T02:57:20Z occurrence=1-10-the-chat-agent-sets-lists-and-cancels-reminders

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
- 2026-10-25T21:56:16Z status=resolved-by:5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=adjudication note=Watch.Reader matches each readable namespace's own current production only (GetProductionStatus), never every Ens.Config.Production row; Test.Watch.Reader TestReadableNamespaceOffersItsOwnProduction pins it (mutation: list every row -> double match)

### DW-39: The CI mock picks an agent's default script by its MOCKKEY, which reaches the mock only as the x-ocutalon-mockkey request header that the Provider step must add whenever OCUTALON_MODEL_BASE_URL is set
- source: spec-0-11-the-ci-model-mock-answers-every-scenario-the-stories-need.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 0.11 Rule 22 ruling; Install.Step.Provider is Lane A's only provider writer (AD-19) and is built in 1.1
- 2026-10-20T14:30:01Z status=routed owner=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=planning note=1.1's Provider step writes http_config.custom_headers x-ocutalon-mockkey=<the agent class's MOCKKEY> only with OCUTALON_MODEL_BASE_URL set
- 2026-10-20T18:15:26Z status=routed owner=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=owner note=owner decision 5: header only when OCUTALON_MOCK_KEY_HEADER=1 (CI-only), never from OCUTALON_MODEL_BASE_URL alone; online demo never carries it
- 2026-10-21T18:39:25Z status=resolved-by:1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=adjudication note=Provider.Details adds x-ocutalon-mockkey only for OCUTALON_MOCK_KEY_HEADER=1; pinned by TestDetails, ProviderEnv TestBaseUrlAlone/TestFlagAlone/TestCiEnvironment

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

### DW-52: Bridge.ConfigStore.Merge validates only api_key's placeholder form and nested @{: any @{env:NAME}, base_url, header or secret:// passes, so a user-facing caller could pair the key placeholder with an arbitrary base_url
- source: _bmad-output/implementation-artifacts/spec-1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Merge refuses only a non-placeholder api_key and any other @{ (AD-19, decision 10, U-2); {"api_key":"@{env:X}","base_url":"http://other.invalid/v1/"} passes and @{config:} resolves both; Story 17.3 is the first caller taking user input
- 2026-10-21T17:28:39Z status=open owner=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=harvest note=deferred by 1.1 implement; adjudicate at 1.1's gate (likely route to 17-3 with the residual)
- 2026-10-21T18:26:41Z occurrence=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor
- 2026-10-21T18:39:25Z status=routed owner=17-3-run-each-agent-on-a-supported-provider by=adjudication note=residual: 17.3's model-change API must validate env var name, base_url, headers, model, secret:// before Merge (1.1 checks api_key, @{ only)

### DW-53: cycle-log-epic-1.md line 1 held a local absolute path (state=), which test-boundaries.sh flags in every tracked file, so the hosted checks job would go red on the next push
- source: _bmad-output/implementation-artifacts/spec-1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor.md | severity: med | fix-risk: low | footprint: in-story
- evidence: runner bookkeeping commit 9808cd9 (line from 13:54Z); found by 1.1 implement's ci/checks.sh run
- 2026-10-21T17:28:39Z status=open owner=1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=harvest note=lead bookkeeping defect, fixed by the lead before any push
- 2026-10-21T18:39:25Z status=resolved-by:1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor by=adjudication note=lead corrected cycle-log line 1 to a relative state= path in cb4a11c; test-boundaries.sh PASS paths (QA and CR runs)

### DW-54: Test.Agent.KeyScan's FindRequest and Has copy Test.Contract.Mock's private Find and Has, though Story 1.1's spec says to call Mock and not copy it
- source: spec-1-1-every-agent-runs-on-claude-haiku-5-5-through-the-config-stor.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: KeyScan.cls FindRequest and Has repeat Mock.cls Find and Has (about 436-461) line for line; Mock's are Private and Lane B's (Test.Contract), so Lane A cannot call them or edit them (Rule 2)
- 2026-10-21T18:26:38Z status=escalated owner=burndown by=cr note=decision sheet: Lane B makes Mock.Find and Mock.Has public, then KeyScan calls them and drops its copies
- 2026-10-21T23:45:21Z occurrence=1-2-agent-runners-send-every-request-under-the-model-rules
- 2026-10-24T12:14:23Z status=wontfix-accepted by=merge_gate note=decided_unattended(U9):test-only_copy_of_Mock's_Find/Has;reopen_if=Test.Contract.Mock's_Find,Has_or_its_log_format_change(KeyScan's_copy_would_drift)

### DW-56: Nothing sets Reply.ToolsRun: the runner's Answer fills Text, FinishReason, HostData and Tainted only, so a turn that ran tools reports ToolsRun 0
- source: _bmad-output/implementation-artifacts/spec-1-2-agent-runners-send-every-request-under-the-model-rules.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: AD-6 gives Reply ToolsRun; Story 1.7 re-sends after a rate limit only when no tool ran (ToolsRun false); Adapter/Agent.cls Answer builds the Reply; %AI.LLM.Response carries the tool-call count
- 2026-10-21T22:30:46Z status=routed owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=harvest note=1.7 sets ToolsRun in Adapter.Agent Answer (or where the step audit sees a tool run) and pins it; its rate-limit AC depends on it
- 2026-10-23T11:56:20Z status=resolved-by:1-7-timeouts-and-rate-limits-end-every-decision-on-time by=adjudication note=Adapter.Agent.Answer_sets_Reply.ToolsRun_from_AI_Hub's_tool-call_counter_or_the_step_records(unreadable=1);Decide_re-sends_only_with_ToolsRun_0;tests_Test.Bridge.Runner.TestToolsRun,Test.Agent.Steps.TestToolRanNoResend,TestTwoTools(766bf3b)

### DW-63: No hermetic check pins the content of lane-a.yml's standalone-bridge job: its step that runs release/standalone-bridge.sh could be removed or turned back into an echo with every check green
- source: _bmad-output/implementation-artifacts/spec-1-3-decide-records-exactly-one-attention-decision-per-item.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: docker/tests/test-ci-config.sh asserts only that lane-a.yml has a job named standalone-bridge and the workflow-wide rules, which the old echo job also met; the job is the script's only automatic host (no ci/units.sh list runs it); the check is Lane B's file
- 2026-10-22T05:37:11Z status=wontfix-accepted owner=1-3-decide-records-exactly-one-attention-decision-per-item by=harvest note=reopen_if=grep -q 'bash release/standalone-bridge.sh' .github/workflows/lane-a.yml fails, or a standalone-bridge job log on a Lane A push lacks the script's PASS lines; a Lane B story that edits test-ci-config.sh may add the pin

### DW-64: docker/tests/test-boundaries.sh does not list release/ among its ASCII-scanned roots, so a non-ASCII byte in a release/ script would pass the boundaries check
- source: _bmad-output/implementation-artifacts/spec-1-3-decide-records-exactly-one-attention-decision-per-item.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: found by the Story 1.3 implement stage when it added release/standalone-bridge.sh (the folder's first file); the script was checked ASCII by hand; test-boundaries.sh is Lane B's file
- 2026-10-22T05:37:12Z status=wontfix-accepted owner=1-3-decide-records-exactly-one-attention-decision-per-item by=harvest note=reopen_if=LC_ALL=C grep -rnP '[^\x00-\x7F]' release/ finds a byte, or a Lane B story edits test-boundaries.sh's scanned roots (it may add release/ then)

### DW-67: release/standalone-bridge.sh repeats row 5's namespace-create and LoadDir recipe from Lane B's test-install-start.sh
- source: spec-1-3-decide-records-exactly-one-attention-decision-per-item.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: About 10 lines (the CPF heredoc, the docker exec copy and iris merge, LoadDir, Installer.Run and the other-classes query) appear in both scripts; the spec forces the copy (Rule 2), since test-install-start.sh runs as a whole and lib-live.sh has no helper for it.
- 2026-10-22T07:03:27Z status=wontfix-accepted owner=1-3-decide-records-exactly-one-attention-decision-per-item by=cr note=reopen_if=a third script copies the namespace-create and LoadDir recipe, or lib-live.sh gains a helper for it

### DW-76: The daily cost cap fails open and silently: a Usage row whose cost is unknown (a model with no Price row) counts nothing toward Budget.State's spend, and an unreadable DailyCostCapUSD, GatewaySpendUSD or GatewaySpendDate leaves the cap off with no log line
- source: _bmad-output/implementation-artifacts/spec-1-4-every-turn-and-decision-carries-its-tokens-and-cost.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Story 1.4 implement residual risks: CostFor returns empty for an unpriced model (never 0, by U-18), and State cannot count such a row; the budget settings are read through the accessor with no fault path; Story 1.6 builds the daily_cap precheck that reads State
- 2026-10-22T11:02:45Z status=routed owner=1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star by=harvest note=1.6's daily_cap precheck treats an unknown-cost row and an unreadable budget setting as a configuration fault it logs, and does not let it pass silently; how a set cap behaves then (fail open or closed) is 1.6's plan decision, recorded in its spec
- 2026-10-22T12:43:51Z occurrence=1-4-every-turn-and-decision-carries-its-tokens-and-cost
- 2026-10-23T03:24:34Z status=resolved-by:1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star by=adjudication note=Budget.State(now,.faults)_names_each_fault(unreadable_DailyCostCapUSD/GatewaySpendUSD/GatewaySpendDate,unpriced_Usage_row);Decide.Precheck_logs_each_as_a_warning;cap_fails_open_per_veto_U-26;tests_Test.Bridge.Budget.TestFaults,Test.Agent.Decide.TestPrechecks(03a8bf5+1.6_review)

### DW-77: AD-20 says the Usage row holds the largest estimated request size; Story 1.4 stores the last request's measured input from Response.Usage (empty when Chat threw), and the spec's call for a lead ruling on its Decision 5 was never recorded
- source: spec-1-4-every-turn-and-decision-carries-its-tokens-and-cost.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Usage.FromStats sets LargestRequestTokens from last.prompt_tokens+cache_read_tokens+cache_creation_tokens; spec line 410 says Decisions 2 and 5 depart from AD wording for the lead to rule; U-16..U-18 rule only 1, 2, 3 and stored data
- 2026-10-22T12:43:46Z status=routed owner=1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual by=cr note=1.5's plan rules Decision 5: comply (max of step estimates) or amend AD-20's wording by Rule 20's light path
- 2026-10-22T19:41:40Z status=resolved-by:1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual by=adjudication note=Usage.Largest(last, estimates) puts the larger of the measured last request and the step estimates on LargestRequestTokens, also after a throw; AD-20 complied with as written; pinned by Test.Bridge.Usage.TestLargest and TestFromStats (mutation lines in spec-1-5 Verification)

### DW-78: A capped-day mark is never cleared: after an owner raises or turns off DailyCostCapUSD on a marked day, Budget.State still reports capped (cap 0, capped true) until local midnight
- source: spec-1-4-every-turn-and-decision-carries-its-tokens-and-cost.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Budget.State: capped = $Data(^OcuTalonBP.UsageCapped(day)) || (cap>0 && spent>=cap); no code clears the node; Boundaries and AD-20 define capped as marked-or-reached
- 2026-10-22T12:43:46Z status=by-design owner=1-4-every-turn-and-decision-carries-its-tokens-and-cost by=cr note=spec-bound (Boundaries State.capped, AD-20); purge is Story 30.2's; reopens via the step-2 settings-page story if a raised cap must clear the mark

### DW-79: Test.Bridge.Budget copies Test.Bridge.Ext's private WaitFor and CleanRuns (the spec's only reason: its child job follows Ext's), so the two child-job helpers now live in two Lane A test classes
- source: spec-1-4-every-turn-and-decision-carries-its-tokens-and-cost.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Test/Bridge/Budget.cls CleanRuns and WaitFor vs Test/Bridge/Ext.cls:230-247, same bodies with their own ^OcuTalonTest area; unifying them is about 40 lines over three files
- 2026-10-22T12:43:46Z status=wontfix-accepted owner=1-4-every-turn-and-decision-carries-its-tokens-and-cost by=cr note=reopen_if=a third Lane A test class copies WaitFor or CleanRuns: move both into Test.Agent.RunnerFixture beside EventMark
- 2026-10-24T10:59:25Z occurrence=1-13-epic-1-burn-down

### DW-83: A Chat that throws returns only an error status, so the steps its runner buffered (the model requests and tool calls before the failure) never reach Visual Trace
- source: _bmad-output/implementation-artifacts/spec-1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Story 1.5 decision 6: Answer's error path carries no Reply, so Reply.Steps cannot travel; Story 1.6 turns every failure into a fallback decision with a reply, where the buffered steps can ride
- 2026-10-22T13:43:43Z status=routed owner=1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star by=spec_gate note=1.6's fallback carries the failed call's buffered steps (redacted) to Decide, which sends them to AgentSteps like a completed turn's; FR-3 every model request and tool call recorded
- 2026-10-22T19:38:04Z occurrence=1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual by=cr note=a reply whose ReplyClassOf lookup fails ends Decide in error before EmitSteps, so its steps are not sent either
- 2026-10-23T03:24:34Z status=resolved-by:1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star by=adjudication note=Adapter.Agent.Answer_returns_a_failure_Reply_carrying_the_buffered_steps_when_Chat_throws;Decide.EmitSteps_sends_them_to_AgentSteps(before_ReplyClassOf);test_Test.Agent.Steps.TestFailedTurnSteps(03a8bf5+1.6_review)

### DW-85: Shipped tool classes declare no STEPLABEL, and nothing fails a tool class that has none, so every real tool step reads 'Running a tool' in Visual Trace
- source: _bmad-output/implementation-artifacts/spec-1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: AD-9 and the spine's Agent step labels convention: each tool declares its readable step label; Tools.WatchFixture carries none (Story 5.4 replaces it); Test.Bridge.CodeRules.TestCallbackRule is where a scan belongs once the first real tool class exists
- 2026-10-22T17:04:48Z status=routed owner=1-10-the-chat-agent-sets-lists-and-cancels-reminders by=harvest note=1.10's reminder tools declare their STEPLABEL<NAME> labels, and 1.10 adds the CodeRules scan that fails a shipped OcuTalon tool class with no label (fixtures and Tools.WatchFixture exempted until Story 5.4)
- 2026-10-24T03:01:40Z status=resolved-by:1-10-the-chat-agent-sets-lists-and-cancels-reminders by=adjudication note=ReminderTools_declare_STEPLABEL<NAME>_for_set/list/cancel,WatchFixture_for_its_three_tools;Test.Bridge.CodeRules.TestToolsHaveStepLabels_fails_a_shipped_tool_class_with_no_label_(no_exemptions)_and_no_two_tools_share_a_label

### DW-86: A model's call of a tool the agent does not have reaches neither %LogExecution nor %LogDenial, so it has no step and its model step says 0 tool calls while AgentStepCount counts it
- source: spec-1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Task 0 (c) measured it: usage-turn on ChatAgent calls list_productions, which Chat lacks; only OnBegin and two OnMessage fire, total_tool_calls counts the call (blind-hunter, edge-case-hunter).
- 2026-10-22T19:37:59Z status=by-design owner=1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual by=cr note=spec decision 5 keeps the stats delta and lists the gap as a residual risk; reopen only by a spec amendment

### DW-87: The redactor's unquoted value takes a closing brace or bracket after it, so a JSON fragment in a text loses it (chatId:777001} becomes chatId:[redacted])
- source: spec-1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual.md | severity: low | fix-risk: med | footprint: in-story
- evidence: QA probe on the slot and the acceptance-auditor: the unquoted branch admits } and ]; nothing leaks, and a bracket-aware rule breaks idempotence ([redacted] ends in ]) or leaks a value that holds }.
- 2026-10-22T19:38:02Z status=wontfix-accepted owner=1-5-every-model-request-and-tool-call-is-an-agent-step-in-visual by=cr note=reopen_if=a step summary's broken JSON fragment hides non-secret text that a reviewer needed

### DW-92: AI Hub (build 154) runs a tool call that the provider cut at max_tokens and goes on, and reports only the last response's stop reason, so the bridge cannot see an intermediate cut-off; whether such a call's arguments can be truncated on the real Anthropic API is unmeasured
- source: _bmad-output/implementation-artifacts/spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: med | fix-risk: high | footprint: out-of-footprint
- evidence: Story 1.6 Task 0 (e): cut-off-tool through StepsAgent gives steps model, tool, model and FinishReason end_turn; StepRenderer.OnMessage gets the content only; TestCutOffToolCall pins it
- 2026-10-22T23:49:35Z status=decision-pending owner=burndown by=harvest note=human=report it to InterSystems (an AI Hub stop reason per response, or no tool run after a max_tokens stop); until then Epic 3's gate governs any risky tool call, and the read-only tools of release 1 are harmless with cut arguments
- 2026-10-24T12:14:24Z status=dropped by=merge_gate note=action_item:epic-1-retro-item-3-report-to-intersystems-ai-hub-build-154(owner:report_to_InterSystems;outward)

### DW-93: Decide.Precheck calls Budget.State on every decision, and State scans the Usage table by RecordedAt, which has no index, so the precheck's cost grows with the Usage rows (unmeasured)
- source: _bmad-output/implementation-artifacts/spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Usage indexes DecisionRef and OwnerRef only (Lane B's Test.Data.Tables pins the indexes); UsageSpent selects by RecordedAt and UnpricedModels scans again when a cap is set; settle by timing Precheck with about 100,000 Usage rows
- 2026-10-22T23:49:35Z status=escalated owner=burndown by=harvest note=for the decision sheet: measure Precheck at 100,000 Usage rows; if it is slow, add a RecordedAt index to Usage with the change to Lane B's pin (an orchestrator call), or cache the day's spend
- 2026-10-24T12:14:24Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=merge_gate note=measure_the_precheck_at_~100k_Usage_rows,then_index(Lane_B's_pin)_or_cache_the_day's_spend;veto_U-50

### DW-94: The gateway's HTTP 403 is measured only in Anthropic's error-JSON shape, and Story 29.3 fixes its status and text but not its body, so a body that AI Hub's error text drops would make a reached cap an error fallback
- source: spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Task 0 (b) measured ci/mock/scenarios/A/daily-cap.json (permission_error JSON) only and did not try a plain-text body; Story 29.3's AC names HTTP 403 and the fixed text only; Classify finds daily_cap by the text
- 2026-10-23T02:11:46Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=unverified; settled by the gateway sending the measured JSON body, or a plain-text 403 measured to give daily_cap

### DW-95: RecordFallback marks the day of the call (MarkCapped with no day), so a cap reached within one call's latency before local midnight marks the next day as capped
- source: spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Decide.RecordFallback calls Budget.MarkCapped("", sinkClass), which takes the day when the mark is written, after the precheck or the gateway's 403 has seen the cap
- 2026-10-23T02:11:52Z status=by-design owner=1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star by=cr note=spec-bound: the Boundaries prescribe MarkCapped("", sinkClass); the window is one call's latency, once a day

### DW-96: Classify knows only Anthropic's refusal and max_tokens stop reasons, so another provider's cut-off (length) or Anthropic's model_context_window_exceeded with text reads as usable
- source: spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Decide.Classify rule 3 matches refusal and max_tokens only; AD-8 maps those two and treats other providers as reporting none until checked; release 1 runs Anthropic only
- 2026-10-23T02:11:52Z status=wontfix-theoretical owner=1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star by=cr note=real once a provider other than Anthropic runs (Story 17.3) or a request can come near the model's context window

### DW-100: The catalog's fallbackReason.timeout says 'the model didn't answer within 60 seconds', which is inexact once the bridge timer can be changed (Timeouts.Apply, Story 1.7; SettingsOps, Story 17.4); fallbackReason.rateLimited ('retries ran out') also shows when a tool ran and Decide, by AD-8, did not re-send
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:181-208 (EXPERIENCE Message Catalog / Conversation / Fallback reasons); Story 1.7 decisions 3 and 7 make the timer changeable and give rate_limited when a tool ran
- 2026-10-23T05:40:25Z status=routed owner=17-4-apply-model-price-budget-and-zone-changes-through-the-bridge by=spec_gate note=the timeout text needs the timer as a slot (or no number) when SettingsOps lets an admin change it; the rateLimited wording is the UX's (AI Hub's own retry ran), so 17.4 rewords only if the UX does

### DW-101: Timeouts.Apply is not atomic: a failed entry merge after Decide's TimerSeconds row is written leaves the timer changed for some runners, and two concurrent Apply calls are not serialized (no lock)
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: low | fix-risk: med | footprint: in-story
- evidence: 1.7 implement review rows BH4, EC6 (rejected low): Apply writes the row, then merges each entry, then restarts; no lock
- 2026-10-23T10:08:08Z status=wontfix-accepted owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=harvest note=reopen_if=Story 17.4's SettingsOps gives Apply concurrent callers, or a failed merge is seen in the field
- 2026-10-23T11:54:57Z occurrence=1-7-timeouts-and-rate-limits-end-every-decision-on-time

### DW-102: Agent step Positions skip a number after a non-object record in Reply.Steps (EmitSteps skips the record but StepsSent counts it)
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: low | fix-risk: low | footprint: in-story
- evidence: 1.7 implement review rows BH8, EC7 (rejected low)
- 2026-10-23T10:08:08Z status=wontfix-accepted owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=harvest note=reopen_if=a non-object record is seen in a Reply.Steps
- 2026-10-23T11:54:57Z status=resolved-by:1-7-timeouts-and-rate-limits-end-every-decision-on-time owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=cr note=StepsSent is now the last Position built (the defect was a repeat, not a skip); TestStepPositionsAcrossResends pins it

### DW-103: Timeouts.Apply refuses a production whose disabled runner has no @{config:} entry, so such a production cannot change its timer through Apply
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: low | fix-risk: low | footprint: in-story
- evidence: 1.7 implement review row BH6 (rejected low)
- 2026-10-23T10:08:08Z status=wontfix-accepted owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=harvest note=reopen_if=such a production needs Apply

### DW-104: Decide writes no event-log line when its timer fires; the timeout is visible only in the Decision row and the trace
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: low | fix-risk: low | footprint: in-story
- evidence: 1.7 implement review row EC16 (rejected low)
- 2026-10-23T10:08:08Z status=wontfix-accepted owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=harvest note=reopen_if=operators ask for a log line when the timer fires

### DW-108: Timeouts.Restart's clean-up (TempStopConfigItem(item, 0) after a stop or start that failed once the stop flag was set) has no test that fails without it
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: low | fix-risk: med | footprint: in-story
- evidence: 1.7 code review VG2: TestRestartError's Ens.Alarm fails in findItemByName before any stop flag (Ens/Director.cls:2492-2499), so removing Timeouts.cls:167 stays green; a red needs UpdateProduction to fail after the flag (a lock held over 60 s)
- 2026-10-23T11:54:57Z status=wontfix-accepted owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=cr note=reopen_if=Restart runs under SettingsOps (Story 17.4) and a runner item is seen left temporarily stopped

### DW-109: Timeouts.Apply puts its TimerSeconds row back with Ens.Config.DefaultSettings.%DeleteId, outside Ext.Accessor.WriteDefault, the one writer of System Default Settings rows
- source: spec-1-7-timeouts-and-rate-limits-end-every-decision-on-time.md | severity: low | fix-risk: low | footprint: in-story
- evidence: 1.7 code review AA2: Timeouts.cls:100 deletes the row it wrote when the definition or a more specific row shadows it; the fix is a new public bridge method (a delete through the accessor), not a two-way door
- 2026-10-23T11:54:58Z status=wontfix-accepted owner=1-7-timeouts-and-rate-limits-end-every-decision-on-time by=cr note=reopen_if=Ext.Accessor.WriteDefault gains auditing or a hook (SettingsOps, Story 17.4) that a %DeleteId bypasses

### DW-110: Evaluation turn cases (EvalIn, Stories 9.1 to 9.3) would share one linked conversation per (OwnerRef eval, ChatAgent) from Story 1.8 on, so one case's history leaks into the next, unless each case is sent with SessionMode fresh (or its own OwnerRef)
- source: spec-1-8-conversations-survive-restarts.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 1.8 links every user turn by (OwnerRef, agent) (AD-6); an eval turn case is a user turn with owner eval (AD-30)
- 2026-10-23T12:47:58Z status=routed owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=spec_gate note=each eval turn case starts fresh (SessionMode fresh with no SeedText) or gets an OwnerRef of its own

### DW-114: Decide probes the conversation lock inside its one job (PoolSize 1), so each user turn that finds its conversation held stalls every other Decide request for the probe's 2 seconds
- source: spec-1-8-conversations-survive-restarts.md | severity: med | fix-risk: high | footprint: in-epic
- evidence: Production.cls:18 Decide PoolSize 1; Decide.Held waits LOCKSECONDS (2) in OnRequest (AD-6 fixes the 2-s wait); Busy arises only while a late Chat of the same conversation holds the lock
- 2026-10-23T15:50:33Z status=escalated owner=burndown by=harvest note=a spine call: a larger Decide pool (AD-30 ordering) or a probe of Conversation's own (Lane B); for the decision sheet
- 2026-10-24T12:14:24Z status=wontfix-accepted by=merge_gate note=release_1:only_while_a_late_Chat_holds_the_lock;reopen_if=a_measured_stall_over_2s_on_the_demo_path_or_under_29.4's_load;veto_U-51

### DW-115: A saved conversation holds the tool results the model saw, verbatim, in OCUTALON_PRIVATE; the redaction convention covers steps, audit, logs and errors, not the stored history
- source: spec-1-8-conversations-survive-restarts.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Adapter/Agent.cls SaveLinked; the four redaction tests drop their turn's session before the key scan (measured: without the drop the scan names the saved session)
- 2026-10-23T15:50:33Z status=by-design owner=1-8-conversations-survive-restarts by=harvest note=spine-bound: AD-3 puts AI sessions in the private database; AD-20's compaction keeps every tool result verbatim in facts_learned; AD-4/AD-14 keep keys out of tool results structurally; veto item U-39 for the owner

### DW-116: A ConversationLink Point failure after a successful session %Save leaves the saved session unlinked; the only reachable cause is an OwnerRef over the link column's 22 characters
- source: spec-1-8-conversations-survive-restarts.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Adapter/Agent.cls SaveLinked; Test.Bridge.Conversation.TestSaveProblem pins the warning and SessionRotated 0
- 2026-10-23T15:50:33Z status=wontfix-accepted owner=1-8-conversations-survive-restarts by=harvest note=reopen_if=a caller sends an OwnerRef over 22 characters (then Admit should refuse it)

### DW-117: A fresh turn that outlives Decide's timer is answered with a timeout fallback whose SessionRotated is 0, yet its late untainted Chat still moves the link to the new seeded session
- source: spec-1-8-conversations-survive-restarts.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Decide.RecordFallback sets no runner flag for a timer fallback; AnswerLinked saves the late Chat and Points the link
- 2026-10-23T15:50:33Z status=wontfix-accepted owner=1-8-conversations-survive-restarts by=harvest note=reopen_if=Epic 2's Conversation retries or continues after a timed-out fresh turn and expects the old session

### DW-118: A continue turn whose link names an AI session that no longer exists fails with an error status on every turn, with no signal to send fresh
- source: spec-1-8-conversations-survive-restarts.md | severity: low | fix-risk: low | footprint: in-story
- evidence: spec decision 14: unreachable today (retention purges only unlinked sessions, AD-20); Test.Bridge.Conversation.TestLockReleased pins the error and the lock release
- 2026-10-23T15:50:33Z status=wontfix-accepted owner=1-8-conversations-survive-restarts by=harvest note=reopen_if=Story 30.2's purge or a restore of the private database leaves a link whose session is gone

### DW-119: Test.Agent.Conversation asserts elapsed-time windows (Busy 2-5 s, the timed-out turn 11-17 s, turn 2 within 6 s) that a loaded CI runner could miss
- source: spec-1-8-conversations-survive-restarts.md | severity: low | fix-risk: low | footprint: in-story
- evidence: the windows are the spec's matrix numbers (timer 12 s, late reply 18 s)
- 2026-10-23T15:50:33Z status=wontfix-accepted owner=1-8-conversations-survive-restarts by=harvest note=reopen_if=a CI run goes red on an elapsed-window assertion of TestBusyWhileHeld, TestBusyAfterTimedOutTurn or TestRunnerBusy

### DW-125: Until Story 30.1's compaction, a linked conversation whose stored history alone passes the request-size limit answers too_large on every turn that continues it (about 400,000 characters of history); Epic 2's Conversation starts a fresh session only after Tainted or SessionBroken, so the conversation stays stuck
- source: spec-1-9-no-model-request-goes-over-100-000-tokens.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Story 1.9 Decide.Precheck too_large on the estimate (history + prompt + schemas + input); Story 1.8 resumes the linked history
- 2026-10-23T18:29:11Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=spec_gate note=30.1 compacts (or rotates to a fresh seeded session) a flagged turn whose history alone passes the limit, and adds its summarizer time only to flagged turns it can compact

### DW-130: Until Story 30.1 compacts, a turn that passes the request-size check can still send a later model request above 100,000 tokens inside AI Hub's tool loop (a 99,000-token first request could reach about 153,000 on its fourth); AD-20's arithmetic bound holds only once turns above 40,000 are compacted
- source: spec-1-9-no-model-request-goes-over-100-000-tokens.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Story 1.9 checks the first request only; the AC's amendment sends a flagged turn as it is until 30.1 merges; AD-20 bounds the loop by compaction at 40,000
- 2026-10-23T21:02:46Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=harvest note=30.1's compaction of every flagged turn closes it; its tests should show a four-iteration turn staying under 100,000
- 2026-10-23T22:00:43Z occurrence=1-9-no-model-request-goes-over-100-000-tokens by=cr note=cr: Chat has no tools until 1.10, so the loop opens there (and with 22.x MCP), not before; 30.1 still closes it

### DW-131: The tool-result cap counts a result's characters before AI Hub encodes a string result again as a JSON string, so a cut result reaches the model slightly larger than the room (10,006 tokens against 10,000 measured)
- source: spec-1-9-no-model-request-goes-over-100-000-tokens.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Tools/Result.cls Return
- 2026-10-23T21:02:46Z status=wontfix-accepted owner=1-9-no-model-request-goes-over-100-000-tokens by=harvest note=reopen_if=the mock logs a tool_result of one step whose encoded content is more than 10 percent over the 40,000-character room (e.g. Story 5.4's real readers)
- 2026-10-23T22:00:43Z occurrence=1-9-no-model-request-goes-over-100-000-tokens by=cr note=cr: 10,006 is characters, not tokens; a cut object grows about a fifth when encoded, so reopen_if may fire with 5.4

### DW-132: The request-size estimate of a continuing turn counts the system prompt twice: the stored history (ContextData) holds it and a version envelope, and the agent part counts it too (about 24% high on a short history)
- source: spec-1-9-no-model-request-goes-over-100-000-tokens.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Bridge/RequestSize.cls HistoryChars; Test.Bridge.Conversation BANDPERCENT 29
- 2026-10-23T21:02:46Z status=wontfix-accepted owner=1-9-no-model-request-goes-over-100-000-tokens by=harvest note=reopen_if=Story 30.1 reads the stored history and can subtract the stored prompt, or BANDPERCENT has to grow above 29

### DW-133: RequestSize.HistoryChars returns 0 with no status or log line when the SQL read of the stored history or the stream open fails, so the estimate fails open silently
- source: spec-1-9-no-model-request-goes-over-100-000-tokens.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Bridge/RequestSize.cls HistoryChars; Test.Agent.RequestSize.TestTooLarge checks the history adds more than 1,500 tokens
- 2026-10-23T21:02:46Z status=wontfix-accepted owner=1-9-no-model-request-goes-over-100-000-tokens by=harvest note=reopen_if=the base image changes the %AI_Agent.Session table or the ContextData stream class
- 2026-10-23T22:00:43Z occurrence=1-9-no-model-request-goes-over-100-000-tokens by=cr note=cr: an SQL error leaves %SQLCODE<0 and throws nothing, so the Catch never runs; same silent 0

### DW-135: Cross-lane contract for ReminderOps (Story 8.4): ListReminders answers with CommandResult.Data = {"reminders":[{"ref","text","dueAt"}]}, the command's session's pending reminders, earliest due first, dueAt in UTC; Story 1.10's list tool and its CommandsIn test double read and answer exactly this shape
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 1.10 Tools/CommandCall + Test.Tools.CommandsDouble; Story 0.4 fixes the command fields, not the result's Data
- 2026-10-23T23:00:53Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=spec_gate note=add as an AC bullet to Story 8.4 (veto category 8, a parallel run's orchestrator routes it); 8.4's ReminderOps must answer this shape or the list tool reports a failure

### DW-136: Set and cancel reminder tools declare TRUSTEDOUTPUT 0 (the AC: only list is trusted output), so once Epic 3's taint rule lands every turn that sets or cancels a reminder is tainted, never saved, and the next turn starts fresh with a recap; their output is built by code from ReminderOps' CommandResult, which fits AD-10's definition of trusted output
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 1.10 Tools/ReminderTools TRUSTEDOUTPUT<NAME>; AD-10 3a quarantine; spine row Saved conversations
- 2026-10-23T23:00:53Z status=routed owner=3-3-content-that-didn-t-come-from-the-user-can-only-look-notify by=spec_gate note=3.3 decides whether set_reminder and cancel_reminder declare TRUSTEDOUTPUT 1 (a class parameter each)
- 2026-10-24T23:49:42Z status=resolved-by:3-3-content-that-didn-t-come-from-the-user-can-only-look-notify by=adjudication note=set_reminder+cancel_reminder_declare_TRUSTEDOUTPUT_1(ReminderTools,commit_41bf263);pinned_by_Test.Bridge.Gate_TestTaintFollowsTrustedOutput+TestWatchToolsAreClassified+Test.Tools.Reminders_want(mutation_TRUSTEDOUTPUTSETREMINDER=0->reminder-set-two_second_call_denied);veto_U-60

### DW-137: A JSON true given as set_reminder's delaySeconds reaches SetReminder as 1 (AI Hub decodes arguments before the method runs), so it sets a reminder one second ahead instead of being refused
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Task 0 (c): true becomes 1; the schema says integer
- 2026-10-24T01:30:42Z status=wontfix-accepted owner=1-10-the-chat-agent-sets-lists-and-cancels-reminders by=harvest note=reopen_if=a live run shows a model sending a boolean or a non-integer delaySeconds

### DW-138: The reminder tools pass the model's strings on without a bound, so a value longer than the command's field (LocalDueAt MAXLEN 19, Text 1000, ReminderRef 22; delaySeconds unbounded) may fail when the real CommandsIn saves the message, and the model is told the service did not answer
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Tools/CommandCall; the double never saves the message
- 2026-10-24T01:30:42Z status=wontfix-accepted owner=1-10-the-chat-agent-sets-lists-and-cancels-reminders by=harvest note=reopen_if=with Story 2.3's real CommandsIn, a 20-character localDueAt or a 20-digit delaySeconds gives NOTSENT instead of the owner's plain-English refusal

### DW-139: list_reminders declares TRUSTEDOUTPUT 1 (the AC), but each reminder's Text is model-authored (set_reminder's argument), so a later turn that lists it gets stored model text back as trusted output
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Tools/ReminderTools TRUSTEDOUTPUTLISTREMINDERS; AD-10's trusted output is 'built by code from OcuTalon's own records'
- 2026-10-24T01:30:42Z status=routed owner=3-3-content-that-didn-t-come-from-the-user-can-only-look-notify by=harvest note=unverified; 3.1/3.3 decide whether a result carrying stored model-authored text is exempt from taint (with DW-136)
- 2026-10-24T23:49:42Z status=resolved-by:3-3-content-that-didn-t-come-from-the-user-can-only-look-notify by=adjudication note=list_reminders_stays_trusted_output;set_reminder_is_not_read-only_so_it_is_denied_in_every_untrusted_or_tainted_turn(rows2-3),so_no_text_from_outside_a_user's_untainted_turn_reaches_a_Reminder_row_through_a_tool;stated_in_ReminderTools_class_comment+spine_Tool_classification_row;mutation_TRUSTEDOUTPUTLISTREMINDERS=0->reminder-cancel_denied

### DW-140: Chat's ceiling of 4 iterations (AD-20) may be too low for a turn that lists and then cancels several reminders one call at a time, ending as an unusable turn after the cancels ran
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: AD-20 max_iterations arithmetic; one cancel_reminder call per Ref
- 2026-10-24T01:30:42Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=harvest note=unverified; 8.4's live check of a 'cancel all my reminders' turn with three or more pending reminders settles it; raising the ceiling amends AD-20 (owner's veto window)

### DW-141: The reminder command key is only <ItemId>:<position>, so an owner that treats a repeated key as a repeat may answer a different command from an earlier one's result when a turn is run again with other tool calls
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Tools/CommandCall key; Context.CommandCount
- 2026-10-24T01:30:42Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=harvest note=unverified; 8.4's ReminderOps compares the verb and fields on a reused key, or refuses the reuse
- 2026-10-24T02:57:20Z occurrence=1-10-the-chat-agent-sets-lists-and-cancels-reminders

### DW-142: Chat's INSTRUCTIONS still tell the model to answer a request to run a command with 'I can't run commands' and call no tool, and name no reminder ability, though Chat now has the reminder tools, so a live model may refuse a reminder request
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Agent/Chat.cls INSTRUCTIONS, unchanged by decision 16; the CI mock scripts the tool call, so no test sees a live model's choice
- 2026-10-24T02:57:20Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=cr note=unverified; 8.4's live check of the reminder phrasings on Haiku 5.5 settles it; the fix is Lane A's Chat INSTRUCTIONS

### DW-143: The watch fixture's three tools declare no CLASSIFICATION, READONLY or TRUSTEDOUTPUT parameters, so by the Tool classification convention they are unclassified (risky) once Epic 3's gate reads the parameters, and Diagnosis's read-only tools would be held
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Tools/WatchFixture.cls gained only STEPLABEL<NAME> in Story 1.10; spine convention 'Tool classification': an undeclared tool is unclassified
- 2026-10-24T02:57:20Z status=routed owner=3-2-one-gate-decides-every-tool-call by=cr note=3.2 declares the watch tools' classification (event-log and message text never trusted output, AD-10) or scans for it
- 2026-10-24T20:57:42Z status=resolved-by:3-2-one-gate-decides-every-tool-call by=adjudication note=WatchFixture_declares_CLASSIFICATION/READONLY/TRUSTEDOUTPUT_per_tool(safe,1,0);pinned_by_Test.Bridge.Gate:TestWatchToolsAreClassified+TestEveryBuiltInToolIsClassified+Test.Agent.Runners(mutation_recorded);commit_c88bd3b

### DW-144: Test.Tools.Reminders.Prepare is the fifth copy of the live-test readiness helper (Test.Agent.RequestSize, Agent.Decide, Agent.Conversation, Bridge.Budget), with the CommandsIn swap added, instead of one shared helper in RunnerFixture
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: low | fix-risk: med | footprint: in-epic
- evidence: Rule 2 check at review: the spec names RequestSize as the pattern it follows (a weak reason); each copy keeps per-class flags and asserts
- 2026-10-24T02:57:20Z status=wontfix-accepted owner=1-10-the-chat-agent-sets-lists-and-cancels-reminders by=cr note=reopen_if=two copies of Prepare diverge (one gains a readiness step another lacks) or a sixth live test class copies it

### DW-149: In a request without %Admin_ConfigStore (Epic 2's /ocutalon/api /state, APPLICATIONROLES only), Keys.Status reads a MISSING model key as present: Status sets present=1 in its Catch, and Keys.Present falls back to %ConfigStore.Configuration.Exists when ConfigStore.Details fails; so a keyless start shows no 'no model key' banner (a false all-clear) and each /state audits three refusals; Budget.State's Usage SELECT has no SQL grant there either and logs a warning per call
- source: spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: high | fix-risk: med | footprint: in-footprint
- evidence: src/bridge/cls/OcuTalon/Bridge/Keys.cls Status/Present; Bridge/Budget.cls State; Epic 2's /state computes noModelKey from Keys.Status(agent); Install/Step/Web.cls APPLICATIONROLES; verified by the orchestrator on origin/OCT-epic1 7f1c2bb
- 2026-10-24T05:11:53Z status=routed owner=burndown by=cr note=cross-epic, found by Epic 2 at 2.10 (Epic 2's DW-148); must close in Epic 1; orchestrator ruling 2026-10-24: chartered first in Epic 1's burn-down story, never overflowed; a refused or failed read never reads as present, a missing key reads missing, unknown never passes as OK; Budget.State works there or degrades without a per-call warning; the key's value never reaches the web request; pinning test: the read in a request context without %Admin_ConfigStore and no key configured reads as missing
- 2026-10-24T06:59:12Z owner=1-13-epic-1-burn-down by=burndown note=chartered_into_Story_1.13(orchestrator_ruling:first,never_overflowed)
- 2026-10-24T11:01:45Z status=resolved-by:1-13-epic-1-burn-down by=adjudication note=Keys.Status_reads_only_the_runner's_recorded_state(^OcuTalonBP.KeyState,present_alone_reads_1);Keys.Present/Absent_answer_unknown_without_%Admin_ConfigStore:USE(no_Config_Store_call,no_AccessDenied_row);Decide's_precheck_on_Keys.Absent(live_rule_unchanged);Budget.State_degrades_quietly(one_fault_line,no_warning);pinned_by_Test.Bridge.WebStatus(a_job_logged_in_as_a_fixture_user_with_exactly_APPLICATIONROLES:no_key->0_for_every_runner,key->1,stopped->0,no_AccessDenied_from_the_read,Budget_no_warning)+Test.Bridge.Keys(7740a9c+review)

### DW-150: Digest.Data.Item.Since returns every item of the session since the time, with no cap
- source: spec-1-12-items-saved-for-the-digest-are-kept-for-it.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Digest/Data/Item.cls Since; the first consumer is Story 17.6
- 2026-10-24T05:11:53Z status=wontfix-accepted owner=1-12-items-saved-for-the-digest-are-kept-for-it by=harvest note=reopen_if=Story 17.6's digest wants only a count and the newest N summaries, and a session's saved items between two digests can reach thousands

### DW-151: TestKeepsInstance's no-live-event check counts only instance-stream events whose payload holds the ItemId or DecisionRef, so a store publishing an event without either Ref would pass it
- source: spec-1-12-items-saved-for-the-digest-are-kept-for-it.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Test/Digest/Store.cls TestKeepsInstance; TestKeeps counts the owner's whole stream
- 2026-10-24T05:11:53Z status=wontfix-accepted owner=1-12-items-saved-for-the-digest-are-kept-for-it by=harvest note=reopen_if=any file under src/ocutalon/cls/OcuTalon/Digest/ names OcuTalon.Live.Publish
- 2026-10-24T06:25:15Z status=wontfix-accepted owner=1-12-items-saved-for-the-digest-are-kept-for-it by=cr note=reopen_if=a file under src/ocutalon/cls/OcuTalon/Digest/ names OcuTalon.Live or OcuTalon_Live (cr widened the probe)

### DW-152: DigestStore.Keep's concurrent-repeat path (the save fails on the unique index after the pre-check found no row) has no test
- source: spec-1-12-items-saved-for-the-digest-are-kept-for-it.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Digest/Store.cls Keep; DigestStore pool 1; TestOnce pins the sequential repeat
- 2026-10-24T05:11:53Z status=wontfix-accepted owner=1-12-items-saved-for-the-digest-are-kept-for-it by=harvest note=reopen_if=the DigestStore item in OcuTalon.Production has a PoolSize above 1

### DW-154: Keys.Status keeps reading a recorded present key for a runner whose job ended without OnTearDown (a refused start, measured; a killed job or a crash); the record stays true about the key and misleads only if the key is removed while that runner stays refused or disabled across an IRIS restart
- source: spec-1-13-epic-1-burn-down.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Adapter/Agent.cls:74 records before CheckSettings; Test.Agent.Runners.TestStartRefused pins it
- 2026-10-24T09:40:20Z status=wontfix-accepted owner=1-13-epic-1-burn-down by=harvest note=reopen_if=a release lets a runner stay disabled or refused across an IRIS restart, or the owner wants a refused start to read as stopped (Status 0)
- 2026-10-24T10:59:25Z occurrence=1-13-epic-1-burn-down

### DW-157: Budget.UsageSpent's warning arm for an SQL failure other than a missing privilege (SQLCODE -99) has no test, so a change that silenced every failure of the Usage SELECT would stay green
- source: spec-1-13-epic-1-burn-down.md | severity: low | fix-risk: med | footprint: in-story
- evidence: UsageSpent splits -99 (quiet, unreadable) from other failures (warning); Test.Bridge.Budget.TestFaults holds the privilege and WebStatus gets only -99; no test reads 'cannot be summed'
- 2026-10-24T10:59:31Z status=wontfix-accepted owner=1-13-epic-1-burn-down by=cr note=reopen_if=UsageSpent's error handling changes again, or a test can make the Usage SELECT fail with an SQLCODE but -99
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

### DW-57: Story 2.1's server button, inline notice and announcer ship with no executed test host; the matrix Busy rows are pinned only through BusyState
- source: spec-2-1-lay-out-the-main-page-frame.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: No spec or page renders app-server-button, app-inline-notice or Announcer; busy-state.test.mjs covers only the framework-free state machine; the Busy AC places their first browser test in Story 2.2
- 2026-10-22T02:05:46Z status=routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=Retry is the first consumer: browser-test aria-busy and aria-disabled, the spinner, the notice text, announced once
- 2026-10-22T07:51:44Z status=resolved-by:2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=adjudication note=Retry_is_the_first_browser_test_of_the_server_button_notice_and_announcer:live.spec_L6_(busy_label_spinner_aria-busy/aria-disabled_never_disabled;10s_notice_announced_once)_and_L11_(answered_Retry);red_under_the_disabled-while-busy_and_unannounced-notice_mutations

### DW-58: Story 2.1's popover service ships with no executed test host
- source: spec-2-1-lay-out-the-main-page-frame.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: No code calls Popovers.show; the spec's Integration ACs place its first browser test in Story 2.9 (the Visual Trace menu)
- 2026-10-22T02:05:46Z status=routed owner=2-9-open-anything-in-visual-trace by=cr note=The menu is the first consumer: test the dialog role and name, focus on open, Esc, an outside press and focus leaving
- 2026-10-23T16:42:48Z owner=2-13-open-visual-trace-from-the-page by=spec_gate note=moved with Story 2.9's page half (split, U5 decide): its first consumer, the Visual Trace menu, is Story 2.13's
- 2026-10-24T03:09:18Z status=resolved-by:2-13-open-visual-trace-from-the-page by=adjudication note=build 91ffd1a plus QA and review: the popover service's first browser tests through the Visual Trace menu and the sign-in help (V4, V7, V12, V13; a dialog named by its heading, no aria-modal, focus to its first control, Esc, outside press and focus leaving close it and return focus) in Chromium; the WebKit and Firefox remainder is DW-145 (Story 2.12)

### DW-59: No test can tell the snapshot's three models keys apart, because every agent resolves to the same model
- source: spec-2-1-lay-out-the-main-page-frame.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Swapping TriageAgent and DiagnosisAgent in Web.Api.StateBody leaves Test.Web.Api, api.spec row 13 and frame F9 green; all three resolve to claude-haiku-5-5 (Task 0)
- 2026-10-22T02:05:46Z status=wontfix-accepted owner=2-1-lay-out-the-main-page-frame by=cr note=reopen_if=an OcuTalon.Production agent item gets its own Model (Production.cls, an installer step or a default setting)

### DW-60: F2's Demo guide and Simulated devices absence checks cannot fail until those regions exist
- source: spec-2-1-lay-out-the-main-page-frame.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Neither text appears anywhere in web/src, so toHaveCount(0) holds in every mode; F2's pinning assertion is main's geometry (flex: none)
- 2026-10-22T02:05:46Z status=wontfix-accepted owner=2-1-lay-out-the-main-page-frame by=cr note=reopen_if=web/src renders a Demo guide or Simulated devices region and frame.spec F2 has no demo-mode-on twin

### DW-61: Story 2.2's snapshot carries each turn without my message text or its reply text, because Data.Turn has no text columns
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Data.Turn holds SessionRef, State, Channel, FromGuide, CreatedAt only; Story 2.2's snapshot AC asks for turns with their replies; Story 2.4's Tainted-reply recap already builds on Turn rows holding the messages and replies as sent
- 2026-10-22T02:54:40Z status=routed owner=2-4-answer-every-chat-message-through-the-turn-pipeline by=spec_gate note=Turn keeps the message text, the reply text as sent, the clientId and the trace target, and ChatMessage.FromRow (Story 2.2) maps them, so /state's chat shows each turn with its reply after a reload; veto ruling at 2.2 spec validation
- 2026-10-22T16:16:48Z status=resolved-by:2-4-answer-every-chat-message-through-the-turn-pipeline by=adjudication note=Turn_keeps_Text,ReplyText,ClientId,TraceHeaderId(slots_10-18);ChatMessage.FromRow_maps_them;api.spec_CHAT_reload_and_Test.Live.Payloads_TestFromRowBuilders;red_under_FromRow_omitting_Text

### DW-62: Story 2.2's snapshot carries no notice cards, because no table keeps a delivered web notice card's text (Delivery keeps references only)
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Delivery.Record keeps ownerRef, channel, channelMessageId and approvalRef; Story 2.2's snapshot AC asks for the conversation with its notice cards; Story 2.7 publishes the notification event and records Delivery
- 2026-10-22T02:54:40Z status=routed owner=2-7-route-untrusted-items-and-notifications-by-outcome by=spec_gate note=keep each web notice card where the snapshot can read it, and add notification entries to StateBody's chat merge (Story 2.2), so a reload shows the cards in order; veto ruling at 2.2 spec validation
- 2026-10-23T11:08:44Z status=resolved-by:2-7-route-untrusted-items-and-notifications-by-outcome by=adjudication note=Delivery keeps each web card (Kind, Text, DecisionRef, DueAt, FallbackReason; build 4fdc430); Ownership.RecentNotices and Web.Api ChatItems merge cards by time; TestStateChatNotices, TestStateChatNoticeCardFields, notice.spec N7 and N14 pin it

### DW-65: Web.Api.StateBody loads and serializes every turn and every noticed incident of the session on each /state call and snapshot reload, with no cap or paging
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: ChatItems reads Ownership.Turns and Ownership.Incidents without a limit, opens each row and exports it; a durable local session only grows (Web/Api.cls ChatItems)
- 2026-10-22T06:27:39Z status=routed owner=2-5-chat-with-ocutalon-in-the-page by=harvest note=the chat's renderer decides a cap or paging for /state's chat (AD-12's snapshot shape) and a test pins it on a long session
- 2026-10-22T07:48:43Z occurrence=2-2-keep-the-session-and-load-its-snapshot-with-live-updates
- 2026-10-22T22:46:30Z status=resolved-by:2-5-chat-with-ocutalon-in-the-page by=adjudication note=Web.Api_CHATMAX_100_newest_entries_via_Ownership_recentTurns/recentIncidents;TestStateChatCapped(103_turns)_and_TestStateChatCappedTies;Task_0:1000_turns_1.38MB->138KB;veto_U-24

### DW-66: Web.Api.CheckView copies what a Live.Payload.Check.FromRow would do, because the check payload is Lane A's; its traceNamespace is the check's namespace
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Rule 2 copy forced by the lanes (spec Design Notes, Extend don't copy); Web/Api.cls CheckView builds Live.Payload.Check for StateBody's rail.checks
- 2026-10-22T06:27:39Z status=routed owner=5-6-the-production-watch-runs-on-every-heartbeat by=harvest note=the check event's publisher (Checks) adds Check.FromRow, confirms or replaces traceNamespace, and StateBody switches to it; orchestrator writes the acceptance bullet after Epic 2 merges

### DW-68: Session.Recipients answers no recipients for an instance incident when Ownership.Watchers' checked prepare fails, which it will as the signed-in user in a REST request
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Watchers prepares with the privilege check and answers "" on any error, the same as nobody watching. AD-11 and AD-31 put BridgeSink's approval.* events in the AnswersIn job, which the REST endpoint calls synchronously as the signed-in user, who holds no SQL grant (AD-13), so (inference, not run) the read fails there and the watchers silently get no event.
- 2026-10-22T07:48:19Z status=routed owner=2-8-show-the-status-rail by=cr note=2.8 resolves watchers where the read is allowed (a production job) or asks for an AD-13 amendment, and makes a failed read loud
- 2026-10-22T07:48:35Z status=routed owner=2-8-show-the-status-rail by=cr note=2.8 reads watchers where the read is allowed (a production job) or asks for an AD-13 amendment; a failed read is loud
- 2026-10-23T15:55:30Z status=routed owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=adjudication note=delivered in 2.8 (build 8bb62bd): Watchers and Recipients pass a failed read's status on, BridgeSink logs it loudly and publishes nothing (never nobody-watches), Ownership.ApprovalIncident, TestInstanceApprovalReachesEveryWatcher and R4. Residual for 6.2: its web answer path runs Approval.Answer in the signed-in user's REST request, where these checked cross-owner reads fail, so other watchers' rails keep an answered instance request until reload; 6.2 hands the instance fan-out to a production job (or asks for an AD-13 amendment), with a test of the real failing read (see DW-113)

### DW-69: LiveState prepends every decision event to store.decisions with no cap, while the snapshot carries the 20 newest decide decisions
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: low | fix-risk: low | footprint: in-story
- evidence: live-store.ts applyEvent's decisions case puts a new decision first and never trims, so after live events the list holds more than a reload would; no view renders it until Story 2.8, which shows the 20 newest.
- 2026-10-22T07:48:19Z status=wontfix-accepted owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=reopen_if=Story 2.8's Recent decisions shows more than 20 rows, or other rows than a reload shows, after live decision events
- 2026-10-22T07:48:35Z status=wontfix-accepted owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=reopen_if=Story 2.8's Recent decisions shows over 20 rows, or other rows than a reload, after live decision events

### DW-70: The Envelope criterion's Content-Type half is satisfied by Angular for an object body, so no test can see the interceptor drop it
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: low | fix-risk: low | footprint: in-story
- evidence: S1 checks content-type application/json on POST /session/end, but HttpClient sets that header itself for an object body ({}), so deleting it from envelope.interceptor.ts keeps every spec green; no current call has a body-less or non-object changing request.
- 2026-10-22T07:48:19Z status=wontfix-accepted owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=reopen_if=ApiClient gains a state-changing call with no body or a non-object body (e.g. DELETE /v1/pairing) and no spec checks its content-type
- 2026-10-22T07:48:35Z status=wontfix-accepted owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=reopen_if=ApiClient gains a body-less or non-object state-changing call and no spec checks its content-type

### DW-71: TestStateFailsLoudly sees only the first failing section read of StateBody, so a later read's lost Check would pass
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: low | fix-risk: med | footprint: in-story
- evidence: The test calls StateBody with a session that has no Ref, so the turns read throws first and the seven later Check(sc) calls never run; Ownership offers no seam to fail one read without a test-only hook, which the spec forbids.
- 2026-10-22T07:48:19Z status=wontfix-accepted owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=reopen_if=a /state 200 is seen with an empty chat or rail section while the session holds rows of that kind

### DW-72: The live-event retention is declared by Install.Step.Web.Purge, while AD-27 names the area OcuTalon.Live; its move to Install.Step.Live is recorded only in the spec
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Install.Step.Web.Purge delegates to Live.Event.Purge (the logic is in OcuTalon.Live), because the registry finds only Install.Step.<Area> classes and Install/** other than Web.cls is Lane A's; spec Design Note 10 plans the move, and nothing else tracks it.
- 2026-10-22T07:48:43Z status=wontfix-accepted owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=reopen_if=Install/Step/ is open to Lane B, or an OcuTalon.Install.Step.Live class exists, and Web still declares it

### DW-73: CommandsIn checks a tool's Dismiss against the command's SessionRef and never compares it with the active bridge context's OwnerRef, so a tool that filled SessionRef from model-supplied arguments could dismiss another session's incident
- source: spec-2-3-route-every-command-by-verb-with-origin-checks.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Core/CommandsIn.cls tool Dismiss branch uses command.SessionRef; Bridge.Context.Current().OwnerRef is never compared; no tool submits yet (unverified)
- 2026-10-22T10:04:50Z status=open owner=2-3-route-every-command-by-verb-with-origin-checks by=harvest note=code review patches the cross-check (context active: SessionRef must equal Context.Current().OwnerRef, else not_found) with a test, or dispositions it with reason
- 2026-10-22T10:57:48Z status=resolved-by:2-3-route-every-command-by-verb-with-origin-checks by=cr note=context Dismiss with SessionRef not OwnerRef is not_found; TestContextDismissSeesOwnIncidentOnly red without it

### DW-74: Commands.Submit's ProcessInput kills the calling job's job-local SessionId on exit, so event-log rows a tool's job writes after a Submit may carry no SessionId and drop out of the turn's Visual Trace thread
- source: spec-2-3-route-every-command-by-verb-with-origin-checks.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Ens.BusinessService.ProcessInput kills JobSessionId in preProcessInput and at Exit (irislib/Ens/BusinessService.cls:79,100); CommandsIn runs in the caller's process; behaviour since Story 0.6 (unverified)
- 2026-10-22T10:04:50Z status=routed owner=2-9-open-anything-in-visual-trace by=harvest note=a throwaway check inside an operation job with JobSessionId set: Submit, then log an event and read its SessionId; if lost, Trace.Join or the runner restores the id
- 2026-10-22T10:56:07Z occurrence=2-3-route-every-command-by-verb-with-origin-checks
- 2026-10-23T16:42:48Z status=routed owner=burndown by=spec_gate note=declined by Story 2.9's plan: the fix belongs in Core/Commands.cls (Commands.Submit's ProcessInput kills the job-local SessionId on exit, irislib Ens/BusinessService.cls:79, read from source), which is contended in this run; the burn-down gate re-checks the contention or overflows it to the epic that owns Commands
- 2026-10-25T06:36:24Z status=routed owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=burndown note=Story 5.1's start-watch tool is the first tool job that calls Commands.Submit (origin tool) inside a traced turn: check on a throwaway that event-log rows its job writes after Submit keep the turn's SessionId; if ProcessInput's kill of JobSessionId drops them (irislib Ens/BusinessService.cls:79,100), restore the id after Submit (Core/Commands.cls) with a test
- 2026-10-25T21:56:16Z status=resolved-by:5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=adjudication note=no Core/Commands.cls change: Tools.CommandCall.Run saves and restores $$$JobSessionId around Submit; Test.Watch.Tools and Test.Watch.Turns prove the id unchanged and a later warning in the session for start/stop, a failed submit included (mutation: drop the restore -> red)

### DW-75: AD-1's Submit sub-bullet says role checks stay with the admin-checked endpoints and CommandsIn, but CommandsIn makes none (Story 2.3 Design Notes 6 reads the clause as its origin rules)
- source: spec-2-3-route-every-command-by-verb-with-origin-checks.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Spine AD-1 :105 (amended 2026-10-19 from Story 0.6's ruling: the admin-checked endpoints and 2.3's CommandsIn own those checks); CommandsIn.cls: Role checks are not made here; AD-19 puts the admin role check in Admin.SetDemoMode
- 2026-10-22T10:56:07Z status=decision-pending owner=burndown by=cr note=veto U7: amend the AD-1 sub-bullet to origin checks, or add a role check to CommandsIn; lead routes to orchestrator
- 2026-10-25T11:58:31Z status=decision-pending owner=burndown by=unattended note=inbox=U-70(AD-1_re-architecture_under_U7c;recommended_a:amend_the_Submit_sub-bullet_to_as_built)
- 2026-10-25T12:10:22Z status=resolved-by:2-3-route-every-command-by-verb-with-origin-checks owner=2-3-route-every-command-by-verb-with-origin-checks by=owner note=U-70(a):AD-1's_Submit_sub-bullet_amended_to_as_built(CommandsIn_makes_the_origin_checks;the_role_check_is_in_the_admin-checked_endpoints,AD-19);Story_4.1_already_refuses_a_non-admin_caller_before_submitting;no_code_change

### DW-80: Nothing runs the Reconcile declarations when the production starts on its own (an IPM install's autostart, or a stop and start without an installer run), so a turn left running waits for the next installer run
- source: spec-2-4-answer-every-chat-message-through-the-turn-pipeline.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: AD-23: on an IPM install Reconcile runs on every production start; only Install.Step.Reconcile calls CallAreas(Reconcile), inside the installer order; no OnStart hook in src (Registry.cls, Production.cls are Lane A)
- 2026-10-22T13:35:56Z status=routed owner=burndown by=harvest note=a production-start hook calls the Reconcile declarations (AD-23), with a test that restarts the production alone
- 2026-10-25T06:36:24Z status=routed owner=15-3-an-ipm-install-survives-restarts-and-reinstalls-and-every-re by=burndown note=Story 15.3's criterion that every area's Reconcile() runs once the autostarted production's items run is this entry: a production started on its own (IPM autostart, or a stop and start with no installer run) must run the Reconcile declarations (AD-23), so a turn left running is picked up; test a restart of the production alone

### DW-81: Conversation's Busy wait and resend run end to end only against a probe replacing SetTimer, never through the real Ens.Alarm and the reopened instance
- source: spec-2-4-answer-every-chat-message-through-the-turn-pipeline.md | severity: med | fix-risk: low | footprint: in-story
- evidence: TestBusyRequeues drives Wait through ConversationProbe; Task 0 measured the timer path once with a reverted temporary change; production tests reach only the Epic 0 Decide stub
- 2026-10-22T13:35:56Z status=open owner=2-4-answer-every-chat-message-through-the-turn-pipeline by=harvest note=code review closes it: a throwaway test production with DecideDouble answering Busy, or a reasoned disposition
- 2026-10-22T16:01:16Z status=routed owner=2-7-route-untrusted-items-and-notifications-by-outcome by=cr note=probe now replaces only SetTimer (Wait runs); real Ens.Alarm resend e2e once 2.7 puts DecideDouble in a production
- 2026-10-23T05:47:06Z status=routed owner=burndown by=spec_gate note=declined by Story 2.7's plan: an end-to-end Busy wait and resend needs a production of its own with DecideDouble as Decide, which stops and restarts the lane-b shard's production; nothing else in 2.7 needs one; a test-infrastructure item for Epic 2's burn-down
- 2026-10-25T06:36:24Z status=wontfix-accepted by=burndown note=no later story builds a production with DecideDouble as Decide; Wait runs for real with only SetTimer probed, and Task 0 measured the Ens.Alarm path once. reopen_if=after Epic 1's real Decide merges, a Busy answer (Story 1.7's rate-limit path) in a production run does not wait and resend once, or any Busy-resend defect is reported

### DW-82: No test observes that WebChatIn's Allowed reaches Allowance.TryConsume, because TryConsume cannot refuse yet
- source: spec-2-4-answer-every-chat-message-through-the-turn-pipeline.md | severity: low | fix-risk: low | footprint: in-story
- evidence: WebChatIn.Allowed delegates to TryConsume, a constant 1 until Story 16.9; replacing Allowed with Quit 1 changes no test
- 2026-10-22T13:35:56Z status=wontfix-accepted owner=2-4-answer-every-chat-message-through-the-turn-pipeline by=harvest note=reopen_if=Story 16.9's online-demo refusal test passes with WebChatIn.Allowed replaced by Quit 1

### DW-84: The no-production branches (Reconcile with no production, the REST 500 when WebChatIn can't be made) run only on the slot, never in CI
- source: spec-2-4-answer-every-chat-message-through-the-turn-pipeline.md | severity: low | fix-risk: med | footprint: in-story
- evidence: TestReconcileWithoutProduction and TestMessagesNoProductionIs500 skip where a production runs, and CI's lane-b shard runs Core and Web with the production up
- 2026-10-22T16:01:16Z status=wontfix-accepted owner=2-4-answer-every-chat-message-through-the-turn-pipeline by=cr note=reopen_if=either branch changes or CI gains a unit with no production; both mutations were seen red on slot B

### DW-88: The chat panel's at-the-bottom flag can turn false when an entry lands between the panel's own scroll to the bottom and that scroll's event, so the list stops following new content
- source: spec-2-5-chat-with-ocutalon-in-the-page.md | severity: med | fix-risk: low | footprint: in-story
- evidence: chat-panel.ts onScroll/scrollToBottom: scrollTop set, a DOM growth over 24 px, then the scroll event measures the geometry; not reproduced in C6/C10 (unverified)
- 2026-10-22T20:12:26Z status=open owner=2-5-chat-with-ocutalon-in-the-page by=harvest note=code review patches it (e.g. ignore the scroll event the panel caused itself) with a test, or dispositions it with a reason
- 2026-10-22T22:45:19Z status=resolved-by:2-5-chat-with-ocutalon-in-the-page by=cr note=reproduced by C13 (red on the old rule); onScroll leaves the bottom only on a scroll up; patched with C13

### DW-89: The chat list and the rail scroll on their own with no tab stop, so a keyboard user in Safari cannot scroll them unless a link or button sits inside
- source: spec-2-5-chat-with-ocutalon-in-the-page.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: chat-panel.ts .list and main-page.ts section.rail: overflow-y auto, no tabindex or name; entries are tabindex=-1; Chromium and Firefox focus a scroller, WebKit does not
- 2026-10-22T22:18:28Z status=routed owner=2-12-meet-the-accessibility-and-responsive-floor by=cr note=2.12 owns WebKit runs and the a11y scan: e.g. tabindex=0 plus aria-labelledby the Chat heading; the rail too
- 2026-10-24T11:52:16Z owner=2-16-prove-the-floor-in-chromium-firefox-and-webkit by=spec_gate note=moved with Story 2.12's split: the WebKit run that checks it is Story 2.16's
- 2026-10-25T06:00:48Z status=resolved-by:2-16-prove-the-floor-in-chromium-firefox-and-webkit by=adjudication note=the chat list (tabindex 0, named by its Chat heading) and the rail (tabindex 0 while it scrolls on its own) are tab stops with the ring inside; E2 (@browsers, Chromium, Firefox, WebKit) tabs to both and scrolls them by keyboard; K4 and G1 walks; mutations recorded in the spec

### DW-90: checks.notEverything and notEverythingRestPassed take a whatFailed slot that the pinned Checks.Render(results, *rows) has no way to return, so the page (Story 2.6) shows no sentence for those keys
- source: spec-2-6-show-every-decision-with-its-reasons-and-cost.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Msg/Catalog/Watch.cls:49-75 (whatFailed: text); Checks/Render.cls returns only a key and rows (pinned results,*rows); 2.6 renders only the three slotless checks.* keys and shows the rows
- 2026-10-22T23:33:46Z status=routed owner=5-7-asked-whether-everything-is-fine-ocutalon-never-gives-a-fals by=spec_gate note=5.7 says how the page gets whatFailed (from the failing row, or a slot path through Render) and the page renders both keys; orchestrator writes the bullet after Epic 2 merges

### DW-91: Test.Bridge.Ext's comment says BridgeSink adds nothing, which Story 2.6 makes stale (BridgeSink now publishes decision and turn.step events for session owners)
- source: spec-2-6-show-every-decision-with-its-reasons-and-cost.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls:95-122 (Lane A) stays green: it calls OnEvent with owner zz, which is no session Ref
- 2026-10-22T23:33:46Z status=wontfix-accepted owner=2-6-show-every-decision-with-its-reasons-and-cost by=spec_gate note=reopen_if=Test.Bridge.Ext is next edited by a Lane A story, or it asserts BridgeSink publishes nothing for a session owner

### DW-97: TurnCost can leave out the usage of an earlier attempt's decision when a broken session is retried, because Conversation.Replied overwrites Turn.TurnDecisionRef on every non-busy answer
- source: spec-2-6-show-every-decision-with-its-reasons-and-cost.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Conversation.Replied overwrites TurnDecisionRef (SessionBroken answer included); Ownership.TurnCost sums only TriageDecisionRef and TurnDecisionRef (unverified: Decide is a stub)
- 2026-10-23T02:34:42Z status=open owner=2-6-show-every-decision-with-its-reasons-and-cost by=harvest note=code review settles it: keep every attempt's DecisionRef (or sum usage by turn) with a test, or a reasoned disposition
- 2026-10-23T04:43:23Z status=wontfix-theoretical owner=2-6-show-every-decision-with-its-reasons-and-cost by=cr note=real only if Story 1.8 gives a retried SessionBroken turn a second DecisionRef; AD-20 unique (ItemId,Kind) forbids it

### DW-98: No test drives the bridge's own emission of decision.recorded and turn.step into BridgeSink; every test calls OnEvent directly
- source: spec-2-6-show-every-decision-with-its-reasons-and-cost.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: BridgeSink tests and the D6/D10 sinkEvent helper call OnEvent directly; Decide is Epic 0's stub and no Lane A emitter is merged
- 2026-10-23T02:34:42Z status=routed owner=burndown by=harvest note=when Lane A's emitter lands: a real Decide records a decision for a session and a decision event reaches that session's stream
- 2026-10-25T06:36:24Z status=routed owner=4-3-break-the-feed-with-a-real-batch-of-50-orders by=burndown note=Lane A's emitter has merged (Epic 1); Story 4.3's real batch makes the real Decide record decisions for a session: assert that a decision.recorded (and a turn.step) the bridge emits reaches that session's stream through BridgeSink, not only OnEvent called directly

### DW-99: Story 2.8's real approval.result path for a replayed tool call has no story that turns it on (epics.md:1706); Story 30.3 must turn it on
- source: epics.md:1706 | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: epics.md:1706 (Story 2.8) says the replayed tool call's approval.result real path turns on when Story 30.3 does; Story 30.3's criteria do not turn it on, and Story 11.1's catch-all leaves Epic 30/31 clauses to that story
- 2026-10-23T03:24:57Z status=routed owner=30-3-an-approved-tool-call-runs-exactly-once-with-no-model by=load note=Contest Planner's routing at the graph review (2026-10-23); the orchestrator adds the DW bullet to Story 30.3 after Epic 2 merges (Rule 17 (1b)); Story 31.2 waits for Epic 30 in the approved graph

### DW-105: Test.Core.ConversationTurns leaves its ConversationProbe event-log rows (Begin, Ask, Tell, OnResponse) in the Ens log on every run
- source: spec-2-7-route-untrusted-items-and-notifications-by-outcome.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Slot B, 2026-10-23: Ens_Util.Log holds 112 rows of SourceClass OcuTalon.Test.Core.ConversationProbe (first 2026-10-22 12:02, last 09:50), no ConfigName; ConversationTurns (Stories 2.4, 2.6) never removes them; Rule 19 hermeticity
- 2026-10-23T11:06:38Z status=routed owner=burndown by=cr note=in-epic MED, owning stories done; fix: remove the probe's log rows in ConversationTurns' teardown (Observe.RemoveWarnings shape)
- 2026-10-23T20:36:31Z occurrence=2-9-open-anything-in-visual-trace
- 2026-10-25T06:36:24Z status=routed owner=6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and by=burndown note=Story 6.4's fallbacks extend Conversation's turn tests (inference): remove ConversationProbe's Ens log rows (Begin, Ask, Tell, OnResponse) in Test.Core.ConversationTurns' teardown, the Observe.RemoveWarnings shape (Rule 19)

### DW-106: Lane B's production tests assert the Epic 0 stub Decide's fallback unusable, so they need new expectations when Story 1.3's real Decide merges
- source: spec-2-7-route-untrusted-items-and-notifications-by-outcome.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: RoutingProduction.TestUntrustedItemReachesTheWebChat (item text without a mock marker, exact unusable texts) and ConversationProduction (Story 2.4's unusable rows, Story 2.7's reply DecisionRef "") assert the stub's answer; with the CI mock an unmarked item is triaged digest (ci/mock/scenarios/A/triage.json)
- 2026-10-23T11:06:38Z status=by-design owner=2-7-route-untrusted-items-and-notifications-by-outcome by=cr note=AD-29: callers test against the stub until the API lands; the AC Until Story 1.3 says so; the merge that brings 1.3 updates them
- 2026-10-25T07:37:05Z occurrence=2-17-epic-2-s-tests-follow-the-real-decide

### DW-107: Two 'is this owner a session' predicates over Session.Recipients: WebChat.Out.IsSession and Core.Rule.Functions.IsSession
- source: spec-2-7-route-untrusted-items-and-notifications-by-outcome.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Channel/WebChat/Out.cls IsSession and Core/Rule/Functions.cls IsSession both test Recipients(ref) without an incident; the spine bars a channel from calling OcuTalon.Core.Rule, so neither can call the other (Rule 2, weak stated reason)
- 2026-10-23T11:06:38Z status=wontfix-accepted owner=2-7-route-untrusted-items-and-notifications-by-outcome by=cr note=reopen_if=a third such predicate appears, or Recipients without an incident can answer one Ref other than the owner

### DW-112: Conversation.Rebuild retries a SessionBroken turn under the same ItemId, which AD-20's one Decision row per (ItemId, Kind) makes Decide refuse; the retry must be a new Decide call under a new ItemId
- source: src/ocutalon/cls/OcuTalon/Core/Conversation.cls:469 (Story 2.4) | severity: high | fix-risk: low | footprint: in-footprint
- evidence: Rebuild calls Ask(turn), whose Request(turn) is built from ItemOf(turn), so the retry carries the turn's ItemId; Decide.ResponseFromRow (src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls ~825) refuses a second turn decision for an ItemId (AD-20); latent until Epic 1's Story 1.8 (linked sessions, error fallback row for the broken attempt)
- 2026-10-23T14:14:25Z status=routed owner=2-9-open-anything-in-visual-trace by=cr note=orchestrator cross-epic ruling 2026-10-23 (U14, decide): comply with AD-20, AD-20 and AD-30 unchanged; fix Rebuild so the retry is a new Decide call under a new ItemId (e.g. derived from the turn's), the broken attempt keeps its error fallback row, the Turn keeps its own ItemId and links to the retry's decision; pinning test: a SessionBroken retry reaches Decide under a new ItemId and gets an answer; add the Conventions row with the fix; must be resolved before the integrate-forward, never overflowed
- 2026-10-23T20:50:47Z status=resolved-by:2-9-open-anything-in-visual-trace by=adjudication note=build 94806a0 plus review patch: Conversation.Rebuild retries under Conversation.RetryItemId(turn.ItemId), a new Decide call; the broken attempt keeps its row; the Turn keeps its own ItemId and TurnDecisionRef is the retry's; pinned by TestBrokenRetryIsANewItem, TestBrokenRetryAfterATaintedTurn and ThreadProduction.TestBrokenRetryThroughTheProduction (red on the old code); Conventions row 'SessionBroken retry'; leftovers DW-126 (escalated) and DW-128 (burndown)

### DW-113: The failing branches of Ownership.Watchers and Ownership.ApprovalIncident, and Session.Recipients passing Watchers' status on, are run by no test, so dropping the pass-through (DW-68's bug) leaves every test green
- source: spec-2-8-show-the-status-rail.md | severity: med | fix-risk: med | footprint: in-story
- evidence: TestFailedWatcherReadIsLoud fails the read through the BridgeSink.Recipients seam above the code that can fail; measured on slot B: no role change, login or bound value makes the checked prepare fail in %UnitTest; only a privilege-limited login (Story 6.2's REST answer path) or a private statement seam in Ownership/Session can
- 2026-10-23T14:14:35Z status=open owner=2-8-show-the-status-rail by=harvest note=implement-stage defer; code review settles it: a statement seam with a pinning test, or a reasoned disposition (Story 6.2 is where the read really fails)
- 2026-10-23T15:53:16Z status=escalated owner=burndown by=cr note=fix-risk high: every full pin crosses a boundary (product test hook, Session subclass, login fixture); recommend 6-2
- 2026-10-25T11:58:31Z status=routed owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=merge_gate note=Story_6.2's_privilege-limited_REST_answer_path_is_where_the_checked_reads_really_fail:pin_the_failing_branches_of_Ownership.Watchers/ApprovalIncident_and_Session.Recipients'_pass-through_there;veto_U-71

### DW-120: page-time.ts and rail-view.ts each define the same {name} template filler, because neither Node-run module can import a value from the other
- source: spec-2-8-show-the-status-rail.md | severity: low | fix-risk: low | footprint: in-story
- evidence: web/src/app/chat/page-time.ts fill and web/src/app/rail/rail-view.ts fill are the same one-pass regex; both modules import only types so Node runs them as they are
- 2026-10-23T15:53:19Z status=wontfix-accepted owner=2-8-show-the-status-rail by=cr note=reopen_if=a third copy of the {name} filler appears under web/src/app, or the two copies' placeholder grammar diverges

### DW-121: The initial web bundle is 503.22 kB, over the 500 kB warning budget of web/angular.json, so every web build now prints a budget warning
- source: spec-2-8-show-the-status-rail.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Story 2.8's rail took the initial bundle from 485.9 kB to 503.22 kB; the error limit is 1 MB and no PRD, epic or spine target sets the budget (Angular's default)
- 2026-10-23T15:53:22Z status=wontfix-accepted owner=2-8-show-the-status-rail by=cr note=reopen_if=the initial bundle passes 550 kB, or a build or CI step fails on the budget warning; then split or lazy-load

### DW-122: A session that stops watching a production keeps that production's pending instance approval rows in its live rail until a reload, because later approval events no longer reach it
- source: spec-2-8-show-the-status-rail.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: BridgeSink.Approved publishes each approval.* event only to Session.Recipients' current watchers, and the live store drops an approval only on its own event, while a reload's Rows(approvals) leaves it out
- 2026-10-23T15:53:24Z status=wontfix-accepted owner=2-8-show-the-status-rail by=cr note=reopen_if=after Stop watching ships (Epic 5) a live rail keeps an instance request whose later event it never got

### DW-126: A turn re-run after a restart that followed a broken first answer sends its first request under the turn's own ItemId again; whether the real Decide answers from the existing (ItemId, turn) row or refuses is not settled
- source: spec-2-9-open-anything-in-visual-trace.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Conversation.Begin resets BrokenRetried to 0 (Conversation.cls:320) and Ask uses RetryItemId only while BrokenRetried is 1, so a restarted sweep goes out under the turn's own ItemId, which already has the broken attempt's fallback row; DecideDouble refuses a second turn request per ItemId; the real Decide is Lane A's stub until Stories 1.3 and 1.5
- 2026-10-23T19:23:09Z status=open owner=2-9-open-anything-in-visual-trace by=harvest note=implement-stage defer (medium, unverified); code review settles it: a persisted retry marker or the Attempt number choosing the derived ItemId (a stored-data change, veto), or a reasoned disposition
- 2026-10-23T20:36:31Z status=escalated owner=burndown by=cr note=settled: real Decide refuses (OCT-epic1 ResponseFromRow), turn ends unusable; fix-risk high: persisted marker = veto 3
- 2026-10-25T11:58:31Z status=wontfix-accepted owner=2-9-open-anything-in-visual-trace by=merge_gate note=honest_fallback:the_real_Decide_refuses_a_second_request_per_ItemId,so_the_restarted_turn_ends_unusable;reopen_if=a_restarted_turn_ending_unusable_is_seen_on_the_demo_path_or_a_persisted_retry_marker_is_planned(stored-data_change);veto_U-71

### DW-128: BridgeSink.Step drops every turn.step of a SessionBroken retry: the bridge context carries RetryItemId(turn.ItemId), and Step publishes only when the context's ItemId is the running turn's own
- source: spec-2-9-open-anything-in-visual-trace.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Conversation.Ask sends the retry under RetryItemId (Conversation.cls:406); Bridge.Context.Begin copies request.ItemId (src/bridge Context.cls:52); BridgeSink.Step quits when Context.Current().ItemId '= running.ItemId (BridgeSink.cls:145); no test covers a retried turn's steps; reachable once Stories 1.3/1.5 emit steps
- 2026-10-23T20:36:21Z status=routed owner=burndown by=cr note=in-epic MED (Core/BridgeSink.cls, Stories 2.6/2.8 done); fix: Step also accepts RetryItemId(running.ItemId), plus a test
- 2026-10-25T06:36:24Z status=routed owner=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=burndown note=Story 6.3 makes BridgeSink join the turn's thread through the bridge context; with Epic 1's step emitter merged a SessionBroken retry's turn.step is now reachable: Step also accepts RetryItemId(running.ItemId) (Core/BridgeSink.cls:145), with a test of a retried turn's steps

### DW-129: A decision's traceUrl opens page 1 of the day's thread with the first Item selected, not the decision: traceHeaderId is the decision's TraceSessionId (now the thread) and no index is known
- source: spec-2-9-open-anything-in-visual-trace.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Live.Payload.Decision.FromRow sets traceHeaderId = row.TraceSessionId (Decision.cls:88); DecideDouble and Lane A's Decide write the thread there (AD-26: a decision's target is the session holding its message); TraceLink.Url adds PAGE only with an index; Decided 5's details pane on the target held only while each turn was its own session
- 2026-10-23T20:36:24Z status=routed owner=2-13-open-visual-trace-from-the-page by=cr note=2.13 owns where decision-strip links open; likely needs the decision message's header id and position (AD-26 decision-target wording)
- 2026-10-24T03:09:18Z status=resolved-by:2-13-open-visual-trace-from-the-page by=adjudication note=Decision.FromRow reads the checked Ownership.TurnOfItem so a chat turn's decision carries its turn's target and index and its link opens the day's thread at the turn; TestDecisionOfATurnOpensAtTheTurn, Test.Web.Api and Test.Core.BridgeSink (seen red) and V2 on the real viewer

### DW-145: The Visual Trace menu's button cannot close its open popover in Safari or macOS Firefox: a press there does not focus the button, so Popovers' focus-leave rule closes the popover on mousedown and the click opens it again
- source: spec-2-13-open-visual-trace-from-the-page.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: popover.ts closeOnFocusLeave closes when focus is outside the trigger and the pane; WebKit and macOS Firefox do not focus a pressed button, so header.ts toggleTrace finds it closed and reopens it (FR-12 lists Safari)
- 2026-10-24T03:06:53Z status=routed owner=2-12-meet-the-accessibility-and-responsive-floor by=cr note=fix in popover.ts (a press on the trigger keeps it inside); verify in 2.12's WebKit and Firefox runs; chromium V7 passes
- 2026-10-24T11:52:16Z owner=2-16-prove-the-floor-in-chromium-firefox-and-webkit by=spec_gate note=moved with Story 2.12's split: the WebKit and Firefox runs that check it are Story 2.16's
- 2026-10-25T06:00:48Z status=resolved-by:2-16-prove-the-floor-in-chromium-firefox-and-webkit by=adjudication note=popover.ts: a primary-button press that starts on the trigger or inside the panel counts as inside until it ends (completed at review, which found the same cause inside the panel in WebKit); E1 presses the button and inside the menu with a press that takes no focus, in all three engines; removing the listener turns E1 red in all three

### DW-146: Specs that open real Visual Trace pages starve later cases of the same live sign-in stack; the cause (each signed-in trace tab holds a licence connection until its session times out) is an inference, and no spec signs its trace tabs out
- source: spec-2-13-open-visual-trace-from-the-page.md | severity: med | fix-risk: high | footprint: in-story
- evidence: Story 2.13 Decided 14: a run with every links.spec tab real left V8 drawing nothing and trace.spec T1 without a session; V3-V6 and V9-V16 stub their trace tabs to stay green
- 2026-10-24T03:06:56Z status=escalated owner=burndown by=cr note=settle by measuring licence and gateway connections on a throwaway while trace tabs are open; 4.7 and 6.1 add real trace pages
- 2026-10-25T11:58:31Z status=routed owner=4-7-finish-the-demo-guide by=merge_gate note=Story_4.7_adds_real_trace_pages:measure_licence_and_gateway_connections_on_a_throwaway_with_trace_tabs_open;if_tabs_hold_connections,sign_trace_tabs_out_in_the_specs;veto_U-71

### DW-147: AD-26's decision bullet still says a decision's trace target is the session holding its decision message, while the Live events convention gives a chat turn's decision its turn's header and item index (DW-129)
- source: spec-2-13-open-visual-trace-from-the-page.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ARCHITECTURE-SPINE.md AD-26: 'The decision event's trace target is that session'; the Conventions Live events row (Story 2.13 amendment) and Decision.FromRow use Ownership.TurnOfItem
- 2026-10-24T03:06:59Z status=wontfix-accepted owner=2-13-open-visual-trace-from-the-page by=cr note=reopen_if=a later spec or review cites AD-26 against Decision.FromRow's turn target (lead ruled: AD-26 extended)

### DW-148: After Epic 1 merges, /state may compute noModelKey as off on a start with no key: Lane A's Keys.Status cannot read the Config Store entry in an /ocutalon/api request and then counts the key as present (a false all-clear); Budget.State's Usage SELECT also lacks its SQL grant there
- source: spec-2-10-show-status-banners-for-a-missing-key-or-a-stalled-heartbeat.md | severity: high | fix-risk: med | footprint: out-of-footprint
- evidence: OCT-epic1 Bridge/Keys.cls: when ConfigStore.Details fails, present = Configuration.Exists(fqn), which answers 1; Configuration.Get needs %Admin_ConfigStore:USE, which the API application lacks (Install/Step/Web.cls :35), and audits each refusal; Budget.cls :129 Usage SELECT has no SQL grant in the request (inference from source; stubs here)
- 2026-10-24T03:56:49Z status=escalated owner=burndown by=harvest note=found by Story 2.10's plan; cross-epic (Lane A's Keys.Status and Budget.State, Stories 1.6 and 1.4, done on OCT-epic1); raised to the orchestrator for routing to Epic 1 before its merge; Story 2.10's B6, B1 and api.spec row 13 turn red at the merge if it is not fixed
- 2026-10-24T03:59:27Z status=routed owner=1-12-items-saved-for-the-digest-are-kept-for-it by=adjudication note=cross-epic:fixed_in_Epic_1's_burn-down_story_before_its_merge(orchestrator_ruling);canonical_entry_in_Epic_1's_ledger
- 2026-10-24T06:49:46Z occurrence=2-10-show-status-banners-for-a-missing-key-or-a-stalled-heartbeat by=cr note=also Ens_Config.Item embedded-SQL reads per /state (Keys.Status, Budget settings: Ens.Director.GetItemSettingValue)
- 2026-10-25T11:58:32Z status=resolved-by:1-13-epic-1-burn-down owner=1-13-epic-1-burn-down by=merge_gate note=canonical_entry_DW-149_resolved_by_Story_1.13(Epic_1_merged_2f0d6bc):Keys.Status_reads_the_runner's_recorded_state;closed_at_Epic_2's_merge

### DW-153: Banners that appear in one update are announced 150 ms apart, and each later announce() clears the earlier text about 50 ms after it landed, which a screen reader may drop (unverified)
- source: spec-2-10-show-status-banners-for-a-missing-key-or-a-stalled-heartbeat.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: banner-stack.ts ANNOUNCE_GAP_MS 150; CDK LiveAnnouncer.announce clears at once and sets the text 100 ms later; the B specs count DOM insertions, not speech; no screen reader runs here
- 2026-10-24T06:49:46Z status=routed owner=2-12-meet-the-accessibility-and-responsive-floor by=cr note=maybe-false; settle with VoiceOver+NVDA on two banners in one update, or announce one update's new banners as one message
- 2026-10-24T15:27:58Z status=resolved-by:2-12-meet-the-accessibility-and-responsive-floor by=cr note=one update's banners are one text, pinned by A4 and announce-queue.test.mjs; the screen-reader check stays DW-159

### DW-155: After a sleep, or in a tab hidden long enough for Chrome's intensive timer throttling, the page's poll and its 10 s and 30 s thresholds fire in one batch, so Unreachable renders and is announced and then clears when that poll answers
- source: spec-2-11-say-plainly-when-the-page-loses-contact.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Chrome aligns a hidden tab's chained timers to one minute after 5 min hidden; the poll timer, then both ContactWatch timers fire in that batch before the poll answers (live-state.ts schedulePoll, contact-watch.ts answered)
- 2026-10-24T10:31:40Z status=wontfix-accepted owner=2-11-say-plainly-when-the-page-loses-contact by=cr note=reopen_if=a page hidden over 5 min or woken from sleep renders Unreachable while its in-flight /events answers 200 in 1 s

### DW-156: A 503 of /events, or of a loaded page's /state, counts as a live-path answer on its status alone, so a run of 503s (one not from IRIS's busy path, or a busy reload after a skipped Seq) shows no lost-contact banner
- source: spec-2-11-say-plainly-when-the-page-loses-contact.md | severity: low | fix-risk: med | footprint: in-story
- evidence: live-state.ts isBusy reads only HttpErrorResponse.status === 503 (poll error handler and fetchSnapshot); IRIS's own licence-cap 503 carries no OcuTalon envelope (S13), so a body check would miss the real busy state
- 2026-10-24T10:31:46Z status=by-design owner=2-11-say-plainly-when-the-page-loses-contact by=cr note=spec Decided 2 and 11, AD-13, AD-25; Story 16.5 shows the busy text for any API 503, so the page is not silent then

### DW-158: B15 and B16 copy L3's five-line skipped-Seq injection (fetch, parse, push an event two past the cursor, fulfill) inline instead of sharing one helper in web/e2e/support/api.ts
- source: spec-2-11-say-plainly-when-the-page-loses-contact.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: banners.spec.ts B15 and B16 skip branches repeat live.spec.ts L3 lines 157-166; the spec's reason is 'B15's skip reuses L3's injection pattern' (Rule 2: a weak reason)
- 2026-10-24T11:03:10Z status=wontfix-accepted owner=2-11-say-plainly-when-the-page-loses-contact by=cr note=reopen_if=a fourth spec injects a skipped Seq, or an event envelope change is applied to one of the three copies only

### DW-159: Screen-reader check of the announcer (DW-153): VoiceOver and NVDA on two banners in one update, a reply and a burst of four announcements
- source: spec-2-12-meet-the-accessibility-and-responsive-floor.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: an agent cannot run a screen reader; Story 2.12 builds the joined announcement and its automated test (A4)
- 2026-10-24T11:52:16Z status=decision-pending owner=burndown by=spec_gate note=human=screen-reader check of the announcer (VoiceOver on macOS, NVDA on Windows)
- 2026-10-25T11:58:32Z status=dropped owner=2-12-meet-the-accessibility-and-responsive-floor by=merge_gate note=action_item:epic-2-retro-item-4-screen-reader-check-of-the-announcer-voi(owner:user)

### DW-161: A2 to A5 hold the page's poll while seeding, so on a host 2.5 times slower the hold may near the 10 s after which Reconnecting shows
- source: spec-2-12-meet-the-accessibility-and-responsive-floor.md | severity: low | fix-risk: low | footprint: in-story
- evidence: holdPoll (web/e2e/support/api.ts) reports a hold of 8 s or more only as a test annotation
- 2026-10-24T13:41:33Z status=open owner=2-12-meet-the-accessibility-and-responsive-floor by=harvest note=implement-stage defer; code review settles it
- 2026-10-24T15:27:58Z status=resolved-by:2-12-meet-the-accessibility-and-responsive-floor by=cr note=QA's holdPoll stops the page clock during a hold, and a 12 s hold passes, so Reconnecting cannot show

### DW-162: A rail row is not focusable, so focus-rule.ts cannot return focus to a row that stays when an update removes only the control inside it that held focus
- source: spec-2-12-meet-the-accessibility-and-responsive-floor.md | severity: low | fix-risk: low | footprint: in-story
- evidence: status-rail.ts renders li.row with no tabindex; HTMLElement.focus() on a non-focusable li does nothing
- 2026-10-24T13:41:33Z status=open owner=2-12-meet-the-accessibility-and-responsive-floor by=harvest note=implement-stage defer; code review settles it
- 2026-10-24T15:27:58Z status=resolved-by:2-12-meet-the-accessibility-and-responsive-floor by=cr note=keepFocus passes a focus its target cannot take to main.main; focus-rule.test.mjs pins it (cr patch)

### DW-163: No browser case runs the chat reload row (a skipped seq reloads the snapshot and only entries new since the last view are announced)
- source: spec-2-12-meet-the-accessibility-and-responsive-floor.md | severity: low | fix-risk: low | footprint: in-story
- evidence: chat-announcements.test.mjs pins the diff on hand-built entries; no A or P case causes a skipped seq
- 2026-10-24T13:41:33Z status=open owner=2-12-meet-the-accessibility-and-responsive-floor by=harvest note=implement-stage defer; code review settles it
- 2026-10-24T15:27:58Z status=wontfix-accepted by=cr note=reopen_if=a reply that lands across a skipped seq is not announced, or a reload announces the chat again

### DW-178: The skip links' href="#/" points at no element on the page, so a rule-based accessibility scan may flag them
- source: spec-2-14-work-the-whole-page-by-keyboard-with-labels-and-words.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: skip links in web/src/app/header/skip-links.ts carry href="#/" and move focus by script; Story 2.16's scan is where it would show (unverified)
- 2026-10-24T18:24:29Z status=routed owner=2-16-prove-the-floor-in-chromium-firefox-and-webkit by=harvest note=implement-stage defer (medium, unverified): Story 2.16's own scan settles it
- 2026-10-25T06:00:48Z status=resolved-by:2-16-prove-the-floor-in-chromium-firefox-and-webkit by=adjudication note=href=#/ kept as a hash route; the in-house scan's links rule (support/scan.ts) accepts hash routes and flags fragments with no target; U1 and U2 find no link to nothing in three engines, U3 and U4 plant the link-to-nothing cases and see them

### DW-179: The turns that seedTurns writes are never removed: it does not adopt them, so cleanFixtureRows cannot delete them
- source: spec-2-14-work-the-whole-page-by-keyboard-with-labels-and-words.md | severity: low | fix-risk: low | footprint: in-story
- evidence: web/e2e/support/iris.ts seedTurns keeps no refs for cleanFixtureRows; rows accumulate on the throwaway's session (pre-existing)
- 2026-10-24T18:24:29Z status=open owner=2-14-work-the-whole-page-by-keyboard-with-labels-and-words by=harvest note=implement-stage defer; code review settles it (throwaways are torn down, so it is test hygiene only)
- 2026-10-24T20:43:50Z status=routed owner=2-16-prove-the-floor-in-chromium-firefox-and-webkit by=adjudication note=root cause fixed in 2.14 (seedTurns now adopts its turn and Decision rows; turnRows; H1 in e2e/floor/fixtures.spec.ts and the floor-fixtures ratchet; 2.14's K and W cases clean their turns). Residual: Story 2.12's A1, A5, A7 and P4 still pass no turnRows to cleanFixtureRows, so their turns stay; Story 2.16 runs the floor unit in more browser projects on one stack, where leftovers multiply and K4's tab walk is bounded at 150 stops - opt those four cases in there
- 2026-10-25T06:00:48Z status=resolved-by:2-16-prove-the-floor-in-chromium-firefox-and-webkit by=adjudication note=A1, A5, A7 and P4 pass turnRows to cleanFixtureRows; the floor-fixtures ratchet checks each case cleans the turns it seeds (5 cases), with a mutation per case recorded; the floor unit runs three engines on one stack (70 cases green)

### DW-184: layout.spec.ts's Tab walk (walk) repeats K4's inline Tab loop in keyboard.spec.ts, with its own end test
- source: spec-2-15-lay-the-page-out-at-every-supported-width.md | severity: low | fix-risk: low | footprint: in-story
- evidence: web/e2e/floor/layout.spec.ts walk() and keyboard.spec.ts K4's loop share the press, read and ring steps; G1 ends at a name holding Send, K4 at the composer button; the spec names K4's walk the pattern (a weak reason)
- 2026-10-25T01:26:03Z status=wontfix-accepted owner=2-15-lay-the-page-out-at-every-supported-width by=cr note=reopen_if=a third spec copies the Tab loop, or G1 and K4 end on different stops of one page; the identical helpers moved

### DW-185: The initial web bundle is over its 500 kB warning budget, before and after Story 2.15 (a warning; the error budget is 1 MB)
- source: spec-2-15-lay-the-page-out-at-every-supported-width.md | severity: low | fix-risk: med | footprint: in-epic
- evidence: ng build of clean copies: 050ca9a 530.80 kB raw (128.04 kB transfer), a35f7bc 538.57 kB (129.75 kB); the story adds 7.77 kB raw and 1.71 kB transfer (1.5%), not material
- 2026-10-25T01:26:11Z status=wontfix-accepted owner=2-15-lay-the-page-out-at-every-supported-width by=cr note=reopen_if=the initial bundle passes 600 kB raw or 150 kB transfer, or a page-load measurement misses its target

### DW-190: In WebKit (Safari) a mouse press on the Status button or on the narrow-window note's Close leaves focus on the page body: Safari focuses no pressed button, so Story 2.15's focus hand-back after a click does not run
- source: spec-2-16-prove-the-floor-in-chromium-firefox-and-webkit.md | severity: low | fix-risk: med | footprint: in-epic
- evidence: Story 2.16 plan Task 0 (macOS, Playwright 1.64.1, WebKit 27.2): G2's and G6's click steps leave document.activeElement on body in WebKit; keyboard paths unaffected
- 2026-10-25T02:31:37Z status=wontfix-accepted owner=2-16-prove-the-floor-in-chromium-firefox-and-webkit by=spec_gate note=reopen_if=a Safari keyboard path loses focus after the drawer or the note closes, or a Safari mouse user reports losing their place; Story 2.15's Decided 3 held this by inference only

### DW-193: A focused banner's ring abuts its 4px accent on the left edge (ring, accent, halo) at 1.07 to 1.25:1, and the scan's ring rule (halo plus backdrop) cannot measure it, so Story 2.14's reopen trigger never fires
- source: spec-2-16-prove-the-floor-in-chromium-firefox-and-webkit.md | severity: low | fix-risk: med | footprint: in-story
- evidence: outline-offset -2px covers 2px of banner-stack.ts's border-left 4px accent; --focus vs the six accent tokens computes 1.07-1.25:1 (light and dark); vs the page and the halo 5.5:1+. Spec Decided 9 says the ring rule now measures it.
- 2026-10-25T05:57:24Z status=decision-pending owner=burndown by=cr note=design call (Story 2.14: a fix needs a design choice): keep, as the outer side contrasts, or restyle the banner's focus edge
- 2026-10-25T11:58:32Z status=by-design owner=2-16-prove-the-floor-in-chromium-firefox-and-webkit by=merge_gate note=the_ring's_outer_side_contrasts_5.5:1_with_the_page_and_the_halo;only_its_own_4px_accent_stripe_is_low;restyling_is_a_design_call;veto_U-71
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

### DW-160: On a fresh flag-on volume's first start the Users step cannot pin the public accounts' Visual Trace page size in OCUORDERS (AD-23 runs the Demo step, which creates OCUORDERS, after Users), so UX-DR148's pin in both namespaces holds only from the second start; the Public step's last phase (after Production and Reconcile, before SetReady) should call Users.PinTrace for both public accounts
- source: spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: spec 3.1 Design Notes, Decided in-stage: The OCUORDERS pin
- 2026-10-24T13:17:50Z status=routed owner=3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a by=spec_gate note=routed at Story 3.1's spec gate; 3.8 owns the Public step's last phase
- 2026-10-25T15:40:13Z status=resolved-by:3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a by=adjudication note=Public.Ready()_pins_both_public_accounts'_Visual_Trace_page_size(Users.PinTrace)_after_Production_and_Reconcile,before_SetReady;Test.Install.Public(mutation_recorded)

### DW-164: ci/warm.sh up printed READY warm 543s while the warm stack's after-start log said RESULT FAILED and not ready (a class package failed to compile), so a stage can believe a failed warm stack is ready; only the first class run showed the failure
- source: spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: 3.1 implement Auto Run Result, residual risks: tooling observation (warm up on tag e3s1iw)
- 2026-10-24T14:47:52Z status=routed owner=burndown by=harvest note=ci/warm.sh is outside Epic 3's footprint and not contended (Epic 32's, merged); the burn-down story may fix it as a footprint extension
- 2026-10-25T16:29:37Z owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=burndown note=overflow(no_charter:3_story-closable_entries_under_cap_8,none_with_2+_occurrences);ci/warm.sh_tooling_fix_(READY_only_after_the_after-start_RESULT_OK)_before_Lane_A's_next_epic_relies_on_warm_mode;Epic_5's_X.0_fix-or-close_pass
- 2026-10-25T21:56:16Z status=resolved-by:5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=adjudication note=ci/warm.sh up prints READY only when the after-start log's last RESULT line is RESULT OK, else FAIL, exit 1 and teardown; an unreadable log fails too (cr patch); docker/tests/test-ci-warm.sh appended block d1-d5 pins it

### DW-165: Security.Users Create and Modify accept a role that does not exist, so EnsureService's 'the role must exist' is a precondition that nothing checks
- source: spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Measured at review on the warm throwaway e3s1rw: Modify(user, Roles=ZzCrNoSuchRole) returned 1. AD-23's order runs Roles (which creates OcuTalonServiceRole from the Tools area's role-alone entry) before Users, and a missing role grants nothing.
- 2026-10-24T15:47:10Z status=wontfix-theoretical owner=3-1-roles-and-the-service-user-grant-only-what-the-architecture by=cr note=real if the Users step runs without the Roles step before it (a reordered registry, or a Roles failure that does not stop the start)

### DW-166: AD-24's 'no services' for the service user is not enforced against a later RESOURCES declaration of a %Service_ resource
- source: spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md | severity: low | fix-risk: low | footprint: in-story
- evidence: The service user's login is disabled (Enabled 0, matrix rows 1 and 2), which closes every service; no tool declares RESOURCES yet, so OcuTalonServiceRole holds nothing; its resource set shows only the instance's public permissions.
- 2026-10-24T15:47:10Z status=wontfix-theoretical owner=3-1-roles-and-the-service-user-grant-only-what-the-architecture by=cr note=real once a tool or fix kind declares a %Service_ resource for OcuTalonServiceRole (Story 3.2's gate, Stories 7.x)

### DW-167: The Users step never removes a Workflow user or Workflow role membership that is added by hand for a public account
- source: spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md | severity: low | fix-risk: low | footprint: in-story
- evidence: AD-24 says public accounts are never Workflow users; the step never makes one and TestEveryRole checks it on test stacks, but a start does not take one away; the online demo is a fresh volume (AD-25).
- 2026-10-24T15:47:10Z status=wontfix-theoretical owner=3-1-roles-and-the-service-user-grant-only-what-the-architecture by=cr note=real if an operator makes a public account a Workflow user on a kept flag-on volume; Story 3.4 owns OcuTalonApprovals' exact membership

### DW-168: The Roles step leaves an OcuTalon-prefixed role that no area declares as it is, so FORBIDDEN and the GrantedRoles reset never reach it
- source: spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Roles.Compose and Apply touch only declared roles; no OcuTalon release has shipped, so no installed volume holds a role that a later version stopped declaring.
- 2026-10-24T15:47:10Z status=wontfix-theoretical owner=3-1-roles-and-the-service-user-grant-only-what-the-architecture by=cr note=real once a release drops a role from every Grants() while kept volumes still hold it

### DW-173: A zero from CheckUserPermission for the ServiceUser reads as a missing privilege with no log, so a runner job without %Admin_Secure:USE would deny every tool that declares RESOURCES; the production runner job's user was not measured
- source: spec-3-2-one-gate-decides-every-tool-call.md | severity: med | fix-risk: low | footprint: in-story
- evidence: CheckUserPermission returns 0 on error and needs %Admin_Secure:USE for another user (irislib/%SYSTEM/Security.cls); tests ran as irisowner
- 2026-10-24T18:06:19Z status=open owner=3-2-one-gate-decides-every-tool-call by=harvest note=lead: settle in 3.2's QA or smoke with one gate call from a production runner job on a throwaway
- 2026-10-24T20:57:42Z status=resolved-by:3-2-one-gate-decides-every-tool-call by=adjudication note=measured_at_QA_on_a_fresh_throwaway:production_AgentRunner_job_runs_as__Ensemble;zz_gate_public(%DB_IRISLIB:R)_allowed_and_ran,zz_gate_admin(%Admin_Secure:U)_denied_NOPRIVILEGE;pinned_by_Test.Bridge.Gate:TestPrivilegeInProductionRunnerJob(2_mutations);residual:a_production_with_another_acting_user_unmeasured

### DW-174: Whether AI Hub gives an MCP tool a toolref that starts mcp: is unmeasured; another form (the JSON configuration form of %AI.Tool.Resolver) would take metadata.origin_class as the source, so a shadowing MCP tool could take a built-in's classification
- source: spec-3-2-one-gate-decides-every-tool-call.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Task 0 measured toolset tools only; rows 8 and 9 build the toolref by hand
- 2026-10-24T18:06:19Z status=routed owner=22-2-classify-mcp-tools-by-server-and-name by=harvest note=measure a real MCP tool's toolref and metadata in %CanExecute (stdio, remote, JSON configuration) when step 4 registers MCP servers
- 2026-10-24T20:53:20Z occurrence=3-2-one-gate-decides-every-tool-call

### DW-175: Two tools of one class whose names differ only in underscores, hyphens or case share their CLASSIFICATION, RESOURCES and STEPLABEL parameters (StepBuffer.ToolParameter's naming rule)
- source: spec-3-2-one-gate-decides-every-tool-call.md | severity: low | fix-risk: med | footprint: in-epic
- evidence: send_mail and sendmail in one class read the same CLASSIFICATIONSENDMAIL
- 2026-10-24T18:06:19Z status=wontfix-accepted owner=3-2-one-gate-decides-every-tool-call by=harvest note=reopen_if=a tool class declares two tools whose names differ only in _, - or case

### DW-176: A tool that AI Hub's metadata marks as requiring authorization but whose class declares safe is not held, because the gate never reads metadata's requirements; a governance-test check that no built-in tool is both safe and REQUIRESAUTH is the smallest guard
- source: spec-3-2-one-gate-decides-every-tool-call.md | severity: low | fix-risk: low | footprint: in-story
- evidence: spec Boundaries: the gate never reads metadata's requirements; implement deferred it for the lead (security posture)
- 2026-10-24T18:06:19Z status=open owner=3-2-one-gate-decides-every-tool-call by=harvest note=lead ruling: add the governance-test check in 3.2's code review (tightens only)
- 2026-10-24T20:57:42Z status=resolved-by:3-2-one-gate-decides-every-tool-call by=adjudication note=governance_test_fails_if_any_built-in_tool_is_REQUIRESAUTH_and_safe_or_argument-classified(Gate.AuthMarks,TestEveryRiskyBuiltInIsDenied);mutation_REQUIRESAUTH=1_on_ReminderTools->red

### DW-177: The classes that OcuTalon.Core.BridgeSink calls once it publishes (Lane B) are not in CodeRules.CALLBACKHELPERS, so the callback rule does not scan them, although the gate fires turn.step to the HostSinkClass from inside AI Hub's authorization callback; a session call or Python there would deadlock or crash the job (AD-6)
- source: spec-3-2-one-gate-decides-every-tool-call.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: CALLBACKHELPERS lists OcuTalon.Core.BridgeSink only; BridgeSink's publishing callees are Lane B's (Epic 2)
- 2026-10-24T18:06:19Z status=routed owner=burndown by=harvest note=lead: severity raised to med (a deadlock in the gate's callback once BridgeSink publishes); extend CALLBACKHELPERS in Test/Bridge once Epic 2's BridgeSink is on the feature branch
- 2026-10-25T09:16:27Z occurrence=3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing
- 2026-10-25T16:29:37Z owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=burndown note=overflow;needs_Lane_B's_publishing_BridgeSink_on_the_feature_branch_(Epic_2)_before_CodeRules.CALLBACKHELPERS_can_list_its_callees;occurrence_3.6_(approval.raised_from_the_callback);Epic_5's_X.0_fix-or-close_pass
- 2026-10-25T21:56:16Z status=resolved-by:5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=adjudication note=CodeRules.CALLBACKHELPERS lists BridgeSink's callees (SINKCLASSES) and the watch tools' callback classes (READERCLASSES); TestCallbackRule compiles, scans and asserts each clean

### DW-182: A tool's own code can lower the context's Tainted or rewrite its Provenance through Context.Put, which the gate's step 4 reads
- source: spec-3-3-content-that-didn-t-come-from-the-user-can-only-look-notify.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Context.Put sets any FIELDS name to any value (Context.cls Put); no tool writes Tainted 0 or Provenance today, and arriving content cannot make one do so
- 2026-10-24T23:46:11Z status=wontfix-theoretical owner=3-3-content-that-didn-t-come-from-the-user-can-only-look-notify by=cr note=real when a tool's code writes Tainted 0 or Provenance, or passes a context field name from its arguments to Put

### DW-183: ToolCodeClean is a static scan: %Save on an opened Ens.Config object, a class name built at run time and a message-resend API pass it
- source: spec-3-3-content-that-didn-t-come-from-the-user-can-only-look-notify.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Design Notes limit the scan to the listed writes and AC 4 names no resend; AD-1's CommandsIn origin check (a refusing stub until Story 2.3) is the guard
- 2026-10-24T23:46:11Z status=by-design owner=3-3-content-that-didn-t-come-from-the-user-can-only-look-notify by=cr note=spec Design Notes: the scan backs AD-1 rather than replacing it; reopens only via a spec amendment

### DW-186: ApprovalHold's expiry timer is set in whole seconds rounded down, so it can fire up to 1 s before the row's ExpiresAt; an expiry handler that requires the clock to be past ExpiresAt would leave the request pending
- source: spec-3-4-each-risky-action-becomes-one-approval-request-held-in-iris.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Approval.Hold SetTimer gets the whole seconds until ExpiresAt, at least 1 (implement report residual risk; spec Decided in-stage)
- 2026-10-25T02:07:44Z status=routed owner=3-5-the-first-answer-wins-and-unanswered-requests-expire by=harvest note=3.5's expiry path must accept a timer that fires up to 1 s early (treat the timer as the expiry, or re-arm for the remainder)
- 2026-10-25T06:22:33Z status=resolved-by:3-5-the-first-answer-wins-and-unanswered-requests-expire by=adjudication note=Expire_never_compares_the_clock;its_callers_(the_hold's_timer,Answer's_past-expiry_step)_decide;matrix_row8_TestExpireDoesNotWaitForTheClock(mutation_recorded);spine_Approval_requests_row

### DW-187: Approval.Raise inside an open transaction fails closed with the hold's 'no approval request' error, because the hold's job cannot see the uncommitted row; if AI Hub's %CanExecute callback runs at a TLevel above 0, Story 3.6's gate could never hold a call
- source: spec-3-4-each-risky-action-becomes-one-approval-request-held-in-iris.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Review triage Blind 2 / Edge 5 (rejected for 3.4: no release-1 caller raises inside a transaction); the gate is 3.6's first caller
- 2026-10-25T02:07:44Z status=routed owner=3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing by=harvest note=3.6 Task 0: measure TLevel inside %CanExecute on build 154 and either commit-safe the call or refuse clearly
- 2026-10-25T03:03:19Z occurrence=3-4-each-risky-action-becomes-one-approval-request-held-in-iris by=cr note=effect corrected: ProcessInput TCommits every open level, so Raise silently commits the caller's transaction
- 2026-10-25T09:18:58Z status=resolved-by:3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing by=adjudication note=measured_TLevel_0_inside_%CanExecute_on_build_154;Raise_refuses_at_TLevel>0_leaving_the_caller's_transaction_open;TestRaiseRefusesInATransaction(levels_1,2)+Gate_row4b(mutation_recorded)

### DW-188: Approval.LiveHold finds a hold by scanning ApprovalHold instances by Ref with no index
- source: spec-3-4-each-risky-action-becomes-one-approval-request-held-in-iris.md | severity: low | fix-risk: med | footprint: in-story
- evidence: an index would change stored data (veto window); scan cost grows with the number of hold instances
- 2026-10-25T02:07:44Z status=wontfix-accepted owner=3-4-each-risky-action-becomes-one-approval-request-held-in-iris by=harvest note=reopen_if=Reconcile or Raise takes more than 1 s with more than a few thousand ApprovalHold instances

### DW-189: A Raise running at the same moment as Reconcile at start is not serialized with it, so Reconcile could see a pending row before its hold has registered
- source: spec-3-4-each-risky-action-becomes-one-approval-request-held-in-iris.md | severity: low | fix-risk: med | footprint: in-story
- evidence: the window is milliseconds and opens only during the after-start Reconcile step
- 2026-10-25T02:07:44Z status=wontfix-theoretical owner=3-4-each-risky-action-becomes-one-approval-request-held-in-iris by=harvest note=real when a caller raises during the after-start (no release-1 caller does; the gate's first raise needs a running production)

### DW-191: Approval.StartHold runs ApprovalStartIn's ProcessInput in the caller's job, which kills $$$JobSessionId and replaces $$$JobCurrentHeaderId; from a host job (Story 3.6's gate in the runner, Epic 5's IncidentManager) the host's later event-log rows lose their session and message
- source: spec-3-4-each-risky-action-becomes-one-approval-request-held-in-iris.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: irislib Ens/BusinessService.cls ProcessInput ends with Kill $$$JobSessionId, SendRequestSync sets $$$JobCurrentHeaderId, and Ens/Util/Log.cls:87-88 reads both for every event-log row; Core.Commands.Submit (Lane B) starts its service the same way
- 2026-10-25T03:03:19Z status=routed owner=3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing by=cr note=3.6 measures the runner's session and header after Raise (spec Consumed-by) and restores them; Commands.Submit shares it
- 2026-10-25T09:18:58Z status=resolved-by:3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing by=adjudication note=StartHold_puts_the_job's_session_and_current_header_ids_back_after_the_ApprovalStartIn_round_trip(also_after_an_error);TestRaiseKeepsTheCallersJobIds(mutation_recorded);exception_branch_untested(residual,DW-196_wontfix-accepted)

### DW-192: A pending approval row can lose its hold (a task completed outside Answer, the timer's Expire failing on the lock or a save, a past-expiry Answer on a row whose hold is gone); then no timer fires and no ApprovalOutcome is sent until the next Reconcile
- source: spec-3-5-the-first-answer-wins-and-unanswered-requests-expire.md | severity: med | fix-risk: med | footprint: in-story
- evidence: HoldResponse sends nothing for a task whose action does not match the row (row 14); a late Answer still expires the row, so only the expired outcome to ResultTarget is missing
- 2026-10-25T05:16:11Z status=open owner=3-5-the-first-answer-wins-and-unanswered-requests-expire by=harvest note=for the 3.5 code review: patch (re-arm or expire-and-deliver when the hold ends with a pending row) or route with a reason
- 2026-10-25T06:21:01Z status=escalated owner=burndown by=cr note=fix-risk high: Reconcile/Hold must deliver answered or expired rows with no hold (3.5 Never list, row 14); operator-only
- 2026-10-25T17:27:23Z status=routed owner=30-3-an-approved-tool-call-runs-exactly-once-with-no-model by=merge_gate note=Story_30.3_reworks_the_hold's_delivery:Reconcile_or_the_hold_delivers_an_answered_or_expired_row_that_has_no_live_hold(the_expired_outcome_to_ResultTarget);veto_U-78

### DW-194: A tool_call ApprovalRequest stores neither the tool's source class nor the runner item that made the call, which AD-10's replay needs (the live grant matches the source; the replay goes to the runner of the agent that made the call)
- source: spec-3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: 3.6 spec Cross-epic; Epic 0's row contract (AD-33) has no Source or Runner column, and Test/Data/** is contended
- 2026-10-25T07:09:50Z status=routed owner=30-3-an-approved-tool-call-runs-exactly-once-with-no-model by=spec_gate note=30.3 adds the two fields (a stored-data change in its own veto window) or derives them (for example from the decision's trace)

### DW-195: A hold whose start times out after STARTSECONDS can still create its Workflow task and timer after Raise has deleted the row (the hold passed its row check before the delete)
- source: spec-3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Approval.SaveAndStart deletes the row when StartHold errors (incl. the 10 s timeout); nothing cancels a hold that answers later; Reconcile cancels the orphan task only at the next start (unverified)
- 2026-10-25T08:18:18Z status=routed owner=burndown by=harvest note=3.4's path (cr_complete): measure with ApprovalStartIn held past STARTSECONDS; fix by the hold re-checking the row before it sends the task, or by cancelling the late hold
- 2026-10-25T16:29:37Z owner=30-3-an-approved-tool-call-runs-exactly-once-with-no-model by=burndown note=overflow;the_replay_story_reworks_the_hold's_start_and_delivery_(with_DW-194);measure_ApprovalStartIn_held_past_STARTSECONDS_and_re-check_the_row_before_the_task_is_sent

### DW-196: TestRaiseKeepsTheCallersJobIds' 'both ids still undefined' checks cannot fail in the unit-test process, so StartHold's re-kill of an undefined id is unpinned
- source: spec-3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Outside a production job, closing ApprovalStartIn (OnTearDown) kills the whole %Ensemble array before the restore, so deleting both Else-Kill arms keeps every test green; row 5b has both ids defined.
- 2026-10-25T09:16:27Z status=wontfix-accepted owner=3-6-a-risky-tool-call-waits-for-approval-and-runs-nothing by=cr note=reopen_if=a production job with no session or header id (a service before its first send) calls Raise or StartHold

### DW-201: The spine's Approval requests and Audit entries rows omit Answer's sessionRef refusal and Cancel's person arguments (Story 3.7)
- source: spec-3-7-every-action-and-governance-event-is-in-the-iris-audit-log.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Row 913 lists Answer's not_allowed causes without the malformed sessionRef; row 914 omits Cancel(ref,sinkClass,channel,irisUser,sessionRef); Stories 6.2, 12.7, 16.4 and 22.x plan from the spine
- 2026-10-25T12:46:35Z status=routed owner=burndown by=cr note=lead Rule 20 write; else 16.4/22.x Cancel entries name the system user (AD-17 Prevents)
- 2026-10-25T12:50:32Z status=resolved-by:3-7-every-action-and-governance-event-is-in-the-iris-audit-log by=adjudication note=spine_Conventions_row_Audit_entries_now_names_Answer's_sessionRef_refusal_and_Cancel's_channel,irisUser,sessionRef(Rule20_light_path);Ac_pins_Cancel's_five_arguments

### DW-203: The password guard matches the lower-cased name exactly; with multiple domains enabled IRIS passes the name with its domain, so a public account's password change would pass the guard
- source: spec-3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Security.System documents the routine's name carries the domain when multiple domains are enabled (implement deferred, unverified)
- 2026-10-25T14:30:39Z status=open owner=3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a by=harvest note=for the 3.8 code review: match the part before the domain too (fails closed), or route with a reason
- 2026-10-25T15:37:09Z status=open owner=3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a by=cr note=patched by cr: Check also matches the name before its last @; TestGuardDecidesByNameAndPassword pins it (mutation)
- 2026-10-25T15:40:13Z status=resolved-by:3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a by=adjudication note=the_generated_guard_also_matches_the_name_before_its_last_@(fails_closed);TestGuardDecidesByNameAndPassword(domain_assertions,mutation_recorded)

### DW-209: A flag-on start with renamed published accounts leaves the old online-demo account enabled with its published password, outside the password guard
- source: spec-3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Users.Accounts disables MARKER accounts only with the flag off (DisablePublic); Guard and EnsurePublic cover only the current demoUser and readonlyUser
- 2026-10-25T15:37:09Z status=wontfix-accepted owner=3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a by=cr note=reopen_if=the deployment renames OCUTALON_DEMO_USER or OCUTALON_READONLY_USER between flag-on starts (Story 29.3)
### DW-197: No check counts the Decision rows left after the production tests, so a lost adopt (RoutingProduction's two, Fixture.AdoptTurns) or D14's finally clean-up would leak rows with every test green
- source: spec-2-17-epic-2-s-tests-follow-the-real-decide.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Dropping RoutingProduction's eval adopt leaves 1 eval Decision row and the class green (QA, counted by SQL); a leftover count needs a shard-level check and this story adds no unit
- 2026-10-25T10:53:35Z status=wontfix-accepted owner=2-17-epic-2-s-tests-follow-the-real-decide by=cr note=reopen_if=a warm-stack SQL count finds OcuTalon_Bridge_Data.Decision rows owned by eval or a zz fixture session after the shards

### DW-198: flake: floor-webkit G1 (web/e2e/floor/layout.spec.ts:136) at 1280x600 on the Linux CI host: a rail Trace link's focus ring ends 0.78 px past the viewport's bottom (600.78 vs 600), beyond the ring check's half-pixel tolerance
- source: spec-2-16-prove-the-floor-in-chromium-firefox-and-webkit.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: CI run 40187895230 attempt 1, job 121152465590 (shards, Linux WebKit 27.2): G1 red at a Trace link stop; unchanged rerun (attempt 2) green; e805585 green with the same case; macOS WebKit never showed it
- 2026-10-25T11:46:51Z status=routed owner=4-4-show-the-demo-guide-and-the-break-the-feed-box by=flake note=Story 4.4 adds the demo guide to the page layout and its floor cases: make revealRing keep a 1 px margin past the ring (or reveal the rail's last stops with the ring's full outset) in WebKit, then confirm G1 at 1280x600 green over several Linux runs; a second red is an occurrence

### DW-199: AnswersIn's web handler must pass Approval.Answer either an empty sessionRef or the signed-in session's 22-character Ref: since Story 3.7, Answer answers not_allowed for any other sessionRef
- source: spec-3-7-every-action-and-governance-event-is-in-the-iris-audit-log.md (inbox U-69) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 3.7 (OCT-epic3 10c39c4) adds Answer's not_allowed check for a sessionRef that is neither empty nor a Ref; AnswersIn is a stub on the feature (69c7f06) until Epic 6
- 2026-10-25T12:10:22Z status=routed owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=owner note=U-69 condition (the Contest Planner for the owner): a test pins that a web answer passes the session's Ref, and that a malformed sessionRef answers not_allowed

### DW-200: AnswersIn's Telegram entry must pass Approval.Answer either an empty sessionRef or the paired session's 22-character Ref from the live Pairing row, never a ChatRef or chat id: since Story 3.7, Answer answers not_allowed for any other sessionRef
- source: spec-3-7-every-action-and-governance-event-is-in-the-iris-audit-log.md (inbox U-69) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 3.7 (OCT-epic3 10c39c4) adds Answer's not_allowed check for a sessionRef that is neither empty nor a Ref; Story 10.3 adds AnswersIn's Telegram entry, which Story 12.7's TelegramIn calls with a ChatRef
- 2026-10-25T12:10:22Z status=routed owner=10-3-the-session-side-of-telegram-is-ready-and-stays-off by=owner note=U-69 condition (the Contest Planner for the owner): the entry's fixture tests pin that a press passes the paired session's Ref, and that an unresolvable one answers not_allowed

### DW-213: The security overview must list the service role's demo-mode-only Read on %DB_OCUORDERS_DATA (granted by the Demo step with demo mode on, removed with it off or kept), so it never overstates least privilege
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Orchestrator ruling 2026-10-25 on Story 5.1 (veto U-79): Install/Step/Demo.cls grants OcuTalonServiceRole %DB_OCUORDERS_DATA:R only with demo mode on (AD-3 readable-namespace rule; AD-24 Prevents: a role that grants more than the security overview says)
- 2026-10-25T18:12:36Z status=routed owner=14-1-the-overview-s-tool-and-privilege-lists-are-generated-from-t by=spec_gate note=orchestrator_ruling:the_generated_overview_marks_this_grant_demo-mode-only;its_DW_bullet_is_the_orchestrator's_after_Epic_5's_merge

### DW-218: WatchOps' failure answers (session lock timeout, a failed save or delete) and the per-session lock's serialisation of one session's commands have no test
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Watch/Ops.cls OnStart/OnStop answer failed (Ok 0) when Lock +^OcuTalon.Watch(session):5 times out or %Save/%DeleteId fails; Test.Watch.Ops covers the other outcomes only; deleting the lock line leaves every test green (needs a second job holding the lock >5 s)
- 2026-10-25T20:35:03Z status=open owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=harvest note=implement_deferred(build-auto_review);code_review_may_patch_it
- 2026-10-25T21:56:16Z status=resolved-by:5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=adjudication note=QA's Test.Watch.Ops TestLockTimeout (second job holds the session lock: start and stop answer failed, rows unchanged), TestLockIsReleased and TestFailedSave (cr: dynamic SQL); the failed-%DeleteId branch shares the failed answer code with the tested save branch and cannot be failed fast and reliably

### DW-222: Watch.Reader lists only a namespace's running, suspended or troubled production (GetProductionStatus gives an empty name after a clean stop), so a stopped production cannot be watched and a watch on it cannot be stopped from chat
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: med | fix-risk: med | footprint: in-story
- evidence: irislib/Ens/Director.cls GetProductionStatus empties the name when no job, runtime or suspended node exists (a clean stop), not only when nothing ever ran (spec Task 0); start_watch and stop_watch both resolve through Reader.Find, so both answer unknown_production
- 2026-10-25T21:52:35Z status=decision-pending owner=burndown by=cr note=product call: list a stopped namespace's last production and/or resolve stop_watch from the session's own rows

### DW-223: Install.Step.Demo.WithOrdersData (Story 5.1, U-79) is a near-copy of WithOrders (about 18 of its 20 lines), differing only in the resource list it edits
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls WithOrders and WithOrdersData; the U-79 ruling forbade reshaping WithOrders in Epic 4's file, so the copy was forced; a parsing fix to one would miss the other
- 2026-10-25T21:52:41Z status=routed owner=burndown by=cr note=Rule 2 forced copy: unify by giving WithOrders the resource list as an argument once Epic 4's Demo.cls work has merged

### DW-224: Test.Watch.Turns and Test.Watch.Case copy Test.Tools.Reminders' turn helpers (Turn, AssertTurn, AssertSteps, Begin, Calls, SortedKeys) instead of sharing them
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Test/Watch/Turns.cls and Test/Watch/Case.cls repeat Test/Tools/Reminders.cls 874-1085 nearly line for line; the spec named them templates; sharing needs one helper across ZoneCase and InProduction
- 2026-10-25T21:52:41Z status=wontfix-accepted owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=cr note=reopen_if=a third test class copies these helpers, or a fix to one copy (such as the mock-log read) is missed in another
