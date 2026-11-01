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
- 2026-10-28T19:23:36Z status=resolved-by:10-2-the-readme-gets-a-judge-from-download-to-sign-in by=adjudication note=README.md What you need states Docker Compose 2.24 or later, Troubleshooting covers the too-old message; test-readme.sh install rule pins 2.24

### DW-3: The judges' compose file publishes the web port on every host interface
- source: spec-0-1-the-image-builds-and-starts-ocutalon-in-its-own-namespace.md | severity: med | fix-risk: low | footprint: in-story
- evidence: ports ${OCUTALON_WEB_PORT:-52773}:52773 binds 0.0.0.0, so the Management Portal is reachable from the LAN while a fresh volume holds the base image's default predefined-account password, and AD-23 adds ocutalon/ocutalon
- 2026-10-18T18:21:16Z status=decision-pending owner=burndown by=cr note=author decides: 127.0.0.1 by default with a LAN opt-in, or every interface as specified (spine Deferred, Rule 20)
- 2026-10-18T20:17:25Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=spec_gate note=author 2026-10-18: keep every interface as built (AD-23); README warns the port is LAN-open until passwords change
- 2026-10-19T06:33:18Z note=README also tells the judge plainly to change the README account password after first sign-in (DW-6; Contest Planner 2026-10-19)
- 2026-10-28T19:23:36Z status=resolved-by:10-2-the-readme-gets-a-judge-from-download-to-sign-in by=adjudication note=README.md Sign in: every-interface publishing, LAN warning for the Management Portal, plain change-your-password line linking the admin subsection; test-readme.sh lan rule; residual default-account steps are DW-360

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
- 2026-10-26T04:29:55Z status=resolved-by:16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re by=adjudication note=Ownership.SessionRef stays the one resolver; on the online demo it resolves from the CSP session OnLogin attached (resume cookie or a new row), never by IRIS user (answers empty with an error); resume.spec R5 two sign-ins of the shared account get two epochs, two cookies, isolated chats and /events; a sessionRef in body or query is ignored; Test.Data.Ownership.TestSessionRefOnTheOnlineDemo (mutation recorded)

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
- 2026-11-01T17:23:37Z status=resolved-by:12-6-chat-and-get-notifications-in-the-paired-telegram-chat by=adjudication note=TelegramOut_sends_every_message_through_Api.Split(<=4096_per_part);pinned_by_Test.Channel.TelegramOut.TestLongNotice(5000-char_whatHappened_goes_in_parts;mutation_Send_without_Split_red)

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
- 2026-10-26T02:31:02Z status=resolved-by:5-2-new-failures-are-picked-up-within-seconds by=adjudication note=failure = header Status 8 whatever IsError, or a sessionless Type 2/6 log row; Reader.Failures takes the error text from the log row whose MessageId is the header (else the session's row at the target, else ErrorStatus); ErrorText.Sentence strips the Terminating BP wrapper; Test.Watch.Reader TestFailureDefinition/TestFailures and Test.Watch.Mark TestSentence pin it

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
- 2026-10-28T19:23:36Z status=resolved-by:10-2-the-readme-gets-a-judge-from-download-to-sign-in by=adjudication note=README.md Demo mode quotes the EXPERIENCE.md kept-OCUORDERS sentence verbatim; test-readme.sh demo-mode rule compares it with EXPERIENCE.md

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
- 2026-10-28T14:06:03Z status=dropped owner=burndown by=owner note=reported to InterSystems by the owner 2026-10-28T13:46Z as https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/2 (action item epic-1-retro-item-3 closed done); the S5 model finding (the adapter ignores the model in its ProviderConfig; AD-7's design is already the workaround, no build change) filed as https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/3; FOR THE 1.0.0 README: both links belong in the bonus section 'Find a bug in AI Hub', text from the Contest Planner once the owner approves the bonus plan; relayed by the Contest Planner

### DW-93: Decide.Precheck calls Budget.State on every decision, and State scans the Usage table by RecordedAt, which has no index, so the precheck's cost grows with the Usage rows (unmeasured)
- source: _bmad-output/implementation-artifacts/spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Usage indexes DecisionRef and OwnerRef only (Lane B's Test.Data.Tables pins the indexes); UsageSpent selects by RecordedAt and UnpricedModels scans again when a cap is set; settle by timing Precheck with about 100,000 Usage rows
- 2026-10-22T23:49:35Z status=escalated owner=burndown by=harvest note=for the decision sheet: measure Precheck at 100,000 Usage rows; if it is slow, add a RecordedAt index to Usage with the change to Lane B's pin (an orchestrator call), or cache the day's spend
- 2026-10-24T12:14:24Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=merge_gate note=measure_the_precheck_at_~100k_Usage_rows,then_index(Lane_B's_pin)_or_cache_the_day's_spend;veto_U-50

### DW-94: The gateway's HTTP 403 is measured only in Anthropic's error-JSON shape, and Story 29.3 fixes its status and text but not its body, so a body that AI Hub's error text drops would make a reached cap an error fallback
- source: spec-1-6-an-unusable-reply-takes-the-fallback-route-and-ocutalon-star.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Task 0 (b) measured ci/mock/scenarios/A/daily-cap.json (permission_error JSON) only and did not try a plain-text body; Story 29.3's AC names HTTP 403 and the fixed text only; Classify finds daily_cap by the text
- 2026-10-23T02:11:46Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=unverified; settled by the gateway sending the measured JSON body, or a plain-text 403 measured to give daily_cap
- 2026-10-30T04:25:32Z status=routed owner=29-6-the-probe-alerts-when-every-turn-falls-back by=spec_gate note=split from 29-3 (Rule 5 tier 2, runner C ruling 2026-10-30); bullet moved to Story 29.6
- 2026-10-30T19:28:05Z status=resolved-by:29-6-the-probe-alerts-when-every-turn-falls-back by=adjudication note=measured at the plan (warm throwaway): a plain-text 403 'daily cost cap reached' gives daily_cap, so no bridge change; pinned by ci/mock/scenarios/B/daily-cap-text.json and Test.Agent.Decide.TestDailyCapPlainText; release check H13 says the 403 body must carry the phrase (an empty body gives error)

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
- 2026-10-26T15:16:47Z status=routed owner=18-3-choose-models-and-set-budgets-in-settings by=orchestrator note=M7: Catalog.Core is Lane B's; the criterion moved to Story 18.3 (relaunch planning, the Contest Planner under the owner's delegation)

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
- 2026-10-28T12:59:29Z status=routed owner=9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=spec_gate note=9.1's EvalIn sends no turn request (its act turn already goes fresh with no SeedText, pinned by Test.Eval.Run TestActTurn); 9.3's EvalIn turn requests must each set SessionMode fresh with no SeedText (or an OwnerRef of their own), with a test that two turn cases of one run share no conversation
- 2026-10-28T20:26:11Z status=routed owner=9-7-turn-cases-measure-the-all-clear-the-command-reply-and-a-sto by=spec_gate note=9.3 split (decide): the turn cases moved to 9.7 with this entry; each 9.7 turn request sets SessionMode fresh with no SeedText (or its own OwnerRef), with a test that two turn cases of one run share no conversation
- 2026-10-29T05:57:38Z status=resolved-by:9-7-turn-cases-measure-the-all-clear-the-command-reply-and-a-sto by=adjudication note=9.7's EvalIn sends each all-clear and command case as a user turn with owner eval, SessionMode fresh and no SeedText; Test.Eval.Run TestTurnSessions (AC5) reads the mock's request log and SessionRotated to show two turn cases of one run share no conversation

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
- 2026-10-27T16:22:36Z status=resolved-by:8-4-set-list-and-cancel-reminders-in-plain-words by=adjudication note=ReminderOps answers ListReminders with Data {reminders:[{ref,text,dueAt}]} (pending, earliest due first, UTC) through Ownership.Reminders; ReminderLogic.TestListShape reads it with the real Tools.CommandCall.Listed (0eb2f3e)

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
- 2026-10-27T11:58:29Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=spec_gate note=routed by orchestrator 2026-10-27, U-118 (kept): fix in Lane A's cancel_reminder, which takes one or more reminder ids and sends one CancelReminder per id within one tool call, each with its own IdempotencyKey; no AD-20 change; 11.6 runs the live check (its own entry)

### DW-141: The reminder command key is only <ItemId>:<position>, so an owner that treats a repeated key as a repeat may answer a different command from an earlier one's result when a turn is run again with other tool calls
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Tools/CommandCall key; Context.CommandCount
- 2026-10-24T01:30:42Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=harvest note=unverified; 8.4's ReminderOps compares the verb and fields on a reused key, or refuses the reuse
- 2026-10-24T02:57:20Z occurrence=1-10-the-chat-agent-sets-lists-and-cancels-reminders
- 2026-10-27T15:16:12Z occurrence=8-4-set-list-and-cancel-reminders-in-plain-words
- 2026-10-27T16:22:36Z status=resolved-by:8-4-set-list-and-cancel-reminders-in-plain-words by=adjudication note=ReminderOps keeps each command's key on the row (IdempotencyKey/CancelKey, session-scoped): a repeat gets its own first result and a key reused for other fields is refused reused_key, never another command's result (TestSetRepeat, TestCancelIsolationAndRepeats, TestSeveralCancelsFromOneToolCall; U-118/U-119 cases); a relative repeat compares Text only, as the spec's Repeats rule says

### DW-142: Chat's INSTRUCTIONS still tell the model to answer a request to run a command with 'I can't run commands' and call no tool, and name no reminder ability, though Chat now has the reminder tools, so a live model may refuse a reminder request
- source: spec-1-10-the-chat-agent-sets-lists-and-cancels-reminders.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Agent/Chat.cls INSTRUCTIONS, unchanged by decision 16; the CI mock scripts the tool call, so no test sees a live model's choice
- 2026-10-24T02:57:20Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=cr note=unverified; 8.4's live check of the reminder phrasings on Haiku 5.5 settles it; the fix is Lane A's Chat INSTRUCTIONS
- 2026-10-27T11:58:29Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=spec_gate note=routed by orchestrator 2026-10-27, U-118 (kept): Chat instruction lines say Chat can set, list and cancel reminders and keep the no-commands rule for the rest; live check on Claude Haiku 5.5 with the guide's exact step-2 sentence plus two paraphrases, on the online demo's model, effort and endpoint; passes before 0.1.0 is cut

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
- 2026-10-27T05:19:56Z status=resolved-by:5-6-the-production-watch-runs-on-every-heartbeat owner=5-6-the-production-watch-runs-on-every-heartbeat by=adjudication note=Live.Payload.Check.FromRow_added(traceNamespace=$Namespace,the_Tick%27s_run_session,AD-26/UX-DR139);Web.Api_rail_pushes_FromRow,CheckView_removed(orchestrator_ruling_Q1);Test.Live.Payloads+Test.Web.Api(3_lines)_pin_it(40d6a43)

### DW-68: Session.Recipients answers no recipients for an instance incident when Ownership.Watchers' checked prepare fails, which it will as the signed-in user in a REST request
- source: spec-2-2-keep-the-session-and-load-its-snapshot-with-live-updates.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Watchers prepares with the privilege check and answers "" on any error, the same as nobody watching. AD-11 and AD-31 put BridgeSink's approval.* events in the AnswersIn job, which the REST endpoint calls synchronously as the signed-in user, who holds no SQL grant (AD-13), so (inference, not run) the read fails there and the watchers silently get no event.
- 2026-10-22T07:48:19Z status=routed owner=2-8-show-the-status-rail by=cr note=2.8 resolves watchers where the read is allowed (a production job) or asks for an AD-13 amendment, and makes a failed read loud
- 2026-10-22T07:48:35Z status=routed owner=2-8-show-the-status-rail by=cr note=2.8 reads watchers where the read is allowed (a production job) or asks for an AD-13 amendment; a failed read is loud
- 2026-10-23T15:55:30Z status=routed owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=adjudication note=delivered in 2.8 (build 8bb62bd): Watchers and Recipients pass a failed read's status on, BridgeSink logs it loudly and publishes nothing (never nobody-watches), Ownership.ApprovalIncident, TestInstanceApprovalReachesEveryWatcher and R4. Residual for 6.2: its web answer path runs Approval.Answer in the signed-in user's REST request, where these checked cross-owner reads fail, so other watchers' rails keep an answered instance request until reload; 6.2 hands the instance fan-out to a production job (or asks for an AD-13 amendment), with a test of the real failing read (see DW-113)
- 2026-10-27T14:04:54Z status=resolved-by:6-2-approve-or-reject-a-fix-from-the-web-chat by=adjudication note=AnswerOps calls Approval.Answer in its production job (Core/AnswerOps.cls), so the instance fan-out runs where the cross-owner reads succeed; Test.Core.AnswersInWebRoles:TestInstanceAnswerReachesBothWatchers (AC9) answers from a web-roles process and both watchers' streams get the answered event

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
- 2026-10-27T19:02:03Z occurrence=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher
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
- 2026-10-28T00:45:43Z occurrence=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so

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
- 2026-10-27T09:17:40Z status=resolved-by:5-7-asked-whether-everything-is-fine-ocutalon-never-gives-a-fals owner=5-7-asked-whether-everything-is-fine-ocutalon-never-gives-a-fals by=adjudication note=the_page_builds_whatFailed_from_the_rows_that_did_not_pass(web/src/app/shared/check-sentence.ts;check-rows.ts_wired_under_the_orchestrator%27s_Q1);catalog.mjs_lists_both_keys;check-sentence.test.mjs+catalog.test.mjs+e2e_D7_pin_it(bc59f1b)

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
- 2026-10-25T22:42:32Z status=routed owner=burndown by=spec_gate note=declined_by_4.3: the decision.recorded half is met by Story 2.17's RoutingProduction and ConversationProduction (4.3 re-runs their mutation as evidence); residual: a Test/Core test that drives the real gate (Story 3.2, merged into OCT-epic4 at 3d76632) and asserts that its turn.step reaches the session stream through BridgeSink, with no bridge edit
- 2026-10-27T05:26:00Z status=routed owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=burndown note=overflow (remainder 2 under the cap of 8, no repeats, so no burn-down story): Story 6.2 drives the real gate's approval path; add a Test/Core test that drives the real gate (Story 3.2) and asserts its turn.step reaches the session stream through BridgeSink, with no bridge edit (the decision.recorded half is met by Story 2.17's RoutingProduction/ConversationProduction)
- 2026-10-27T14:04:54Z status=resolved-by:6-2-approve-or-reject-a-fix-from-the-web-chat by=adjudication note=Test.Core.AnswersInProduction:TestGateStepAndHeldCallReachTheStream (AC12) drives the real gate in a bridge context and asserts its turn.step reaches the session stream through BridgeSink, with no bridge edit

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
- 2026-10-28T01:10:14Z status=resolved-by:6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and by=adjudication note=Test.Core.ConversationTurns removes its probe's event-log rows in teardown (RemoveProbeLog, called from OnBeforeAllTests and OnAfterAllTests); TestTeardownRemovesProbeLogRows pins it; after a real run the probe's rows are 0

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
- 2026-10-27T14:04:54Z status=resolved-by:6-2-approve-or-reject-a-fix-from-the-web-chat by=adjudication note=Test.Core.AnswersInWebRoles:TestWatcherReadsFailInAWebRequest (AC10) runs Ownership.Watchers, ApprovalIncident and Session.Recipients in a web-roles process: each returns no recipients and an error status; mutation 10 (Recipients drops Watchers' sc) went red

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
- 2026-10-27T19:04:21Z status=resolved-by:6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=adjudication note=BridgeSink.Step also accepts Conversation.RetryItemId(running.ItemId) (L145, the orchestrator's ruling); Test.Core.BridgeSink:TestTurnStepOfARetry pins a retried turn's turn.step; mutation (retry clause removed) went red

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
- 2026-10-27T04:42:48Z status=resolved-by:4-7-finish-the-demo-guide by=adjudication note=Task 0 measured on e4s7p (one licence unit per user and client address per trace session, held until sign-out or timeout; ?IRISLogout=end frees it); signOutTrace after every case that opens a real trace page, V1 relative licence pin; residual (a real visitor's trace tab holds its unit) is owned by DW-285 (16.4), DW-286 (29.4), DW-287 (29.3) after U-103

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
- 2026-10-25T17:43:08Z status=dropped owner=2-12-meet-the-accessibility-and-responsive-floor by=owner note=action_item_replaced:epic-2-retro-item-5-accessibility-tree-check-of-the-announce(owner:Contest_Planner);the_VoiceOver/NVDA_listening_test_dropped_by_the_owner's_decision(option_1)

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

### DW-127: live:install-script-live joins the image group with no x64 time on record, so Story 32.3's balance rule (no IRIS job over about 1.25x the six-job mean) is unchecked for it
- source: spec-10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to.md | severity: med | fix-risk: low | footprint: in-story
- evidence: lane C ARM runs 95 s and 83 s (two IRIS starts); image was 552 s on ci-b (run 39675383146); at compose-start's ARM-to-x64 ratio (80 to 246 s) image is about 810-920 s against a mean near 710-730, at or under the limit (inference)
- 2026-10-23T20:32:41Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=cr note=unverified: compare image job with 1.25x six-job mean on first CI run with the unit; if over, move one unit (DN 11)
- 2026-10-23T22:31:02Z status=resolved-by:10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to by=ci_resolution note=measured_on_CI:run_40032757987(green)_image_job_673s_vs_six-job_mean_583s(1.15x;longest_install-upgrade_702s=1.20x),run_40021886810_image_690s_vs_567s(1.22x);within_the_1.25_rule;unit_203s_on_ocutalon-ci-c

### DW-134: The README's key and update steps must use the commands install.sh prints: a rerun of ./install.sh now leaves a healthy OcuTalon alone (U-45), so it applies neither a new key nor an update
- source: spec-10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: install.sh:317 prints 'add it to .env and run: docker compose up -d --force-recreate' and :398 'To apply an update, run: docker compose up -d --build'; the healthy branch (:329) runs no compose up, and a container reads .env only when created; the banner text (epics.md:1781) says only 'restart OcuTalon'
- 2026-10-23T22:06:04Z status=routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in by=cr note=README must not say rerun install.sh for a key/update or to wait for a start in progress; docker compose restart does not reread .env
- 2026-10-28T19:23:36Z status=resolved-by:10-2-the-readme-gets-a-judge-from-download-to-sign-in by=adjudication note=README.md key step docker compose up -d --force-recreate, update docker compose up -d --build, no restart or rerun advice; test-readme.sh commands rule extracts install.sh's run: commands
### DW-169: Heartbeat.Gaps lists the heartbeatGap. family with a read-only SELECT on OcuTalon_Data.StatusMark, while the spine's Status marks row says marks are read through Get(mark)
- source: spec-8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Schedule/Heartbeat.cls Gaps runs SELECT Value FROM OcuTalon_Data.StatusMark WHERE Mark %STARTSWITH ?; Get cannot enumerate a family, and the same row names Gaps as the family's reader
- 2026-10-24T16:27:52Z status=wontfix-accepted owner=8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=cr note=reopen_if=a reader of OcuTalon_Data.StatusMark appears outside Data.StatusMark and Schedule.Heartbeat, or its columns change
- 2026-10-24T16:31:00Z status=resolved-by:8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=adjudication note=spine Status marks row reworded: a single mark is read through Get; the heartbeatGap. family is listed only by Heartbeat.Gaps, a read-only query

### DW-170: Test fixtures HeartbeatTaskElsewhere and HeartbeatTaskMissingItem extend %SYS.Task.Definition and ship in OcuTalon.PKG, so a judges' Task Manager New Task wizard can list them as task types (inference)
- source: spec-8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a.md | severity: low | fix-risk: med | footprint: in-story
- evidence: module.xml ships OcuTalon.PKG with every OcuTalon.Test class; the two QA fixtures subclass HeartbeatTask to override PRODUCTION and ITEM
- 2026-10-24T16:27:52Z status=wontfix-accepted owner=8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=cr note=reopen_if=a release install's New Task wizard lists a task type whose class is under OcuTalon.Test

### DW-171: Test.Schedule.Heartbeat Settle/SettleScheduler repeats lib-live.sh's settle_scheduler ObjectScript line (DW-28) with a weak stated reason (another language)
- source: spec-8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: docker/tests/lib-live.sh:662 settle_scheduler and Test/Schedule/Heartbeat.cls Settle hold the same idle test; lib-live.sh is contended (Epics 2, 10)
- 2026-10-24T16:27:52Z status=wontfix-accepted owner=8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=cr note=reopen_if=the DW-28 settle condition changes in one of the two copies and not the other

### DW-172: Rule 21's lane-b class count (24) and per-class timings were not updated for Test.Schedule (lane-b now 26 classes; Heartbeat about 145 to 178 s), as the spec's Shard time note asks
- source: spec-8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: _bmad/custom/skill-rules.md Rule 21 still says 9 in lane-a, 24 in lane-b; spec Design Notes: Record the class timings in Rule 21's section
- 2026-10-24T16:27:52Z status=wontfix-accepted owner=8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=cr note=reopen_if=a stage sizes a lane-b batch from Rule 21's count and overruns its cap; lead may append timings (decide)
- 2026-10-24T17:21:52Z status=resolved-by:8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=adjudication note=Rule 21 gained the measured bullet for Story 8.1's CI run 40114473053 (lane-a 41 classes 537 s, lane-b 26 classes 360 s, Heartbeat 154 s); decide tier, appended measured facts
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
- 2026-10-25T21:33:15Z occurrence=16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac note=ci run 40233631799 iris(shards) floor-webkit G1 ring bottom 600.78 at 1280x600, sha ab3203b; rerun
- 2026-10-26T05:22:57Z occurrence=16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re note=ci run 40270323742 iris(shards) floor-webkit G1 at 1280x600, sha 4ded1e0; rerun
- 2026-10-26T09:37:32Z occurrence=16-5-a-full-demo-says-it-is-busy-and-the-host-s-busy-and-maintena note=ci run 40297305113 iris(shards) floor-webkit G1 ring bottom 600.78 at 1280x600, sha a535d13; third Epic 16 first-run red in a row; rerun
- 2026-10-25T16:37:49Z occurrence=8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat note=run_40209749982_attempt_2_floor-webkit_G1_ring_bottom_600.86_over_600_(ci-6);rerun

### DW-202: REL-2 step 2: the real 'Orders production check row shows a real last run' assertion in web/e2e/demo-path/02-watch.spec.ts is still notBuilt(..., '8.2') after Story 8.2 (fixture-backed block appended); turn it on with the real watch and Checks once Epics 5 and 8 have merged on the integration branch, and drop 8.2's fixture block
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: epics.md Story 8.2 AC3 defers the real switch until Epics 5 and 8 merge; Story 11.1 turns every UJ-1 step spec on; 02-watch.spec.ts lines are Epic 4's while it runs (append-only ruling)
- 2026-10-25T12:55:18Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=spec_gate note=AC3 real-path residual of 8.2; the notBuilt label names 8.2 but the switch needs Lane A's Checks/WatchOps (Stories 5.1, 5.6)

### DW-204: heartbeat.spec.ts leaves two instance-stream status events, and api.spec.ts still pins the instance stream at one event, green only because api/ runs before heartbeat/
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: web/e2e/api/api.spec.ts:121,159,208-211 expect instance 1; web/e2e/heartbeat/heartbeat.spec.ts causes StatusMonitor's onset and clear on the sign-in stack; only workers 1 and path order keep them apart
- 2026-10-25T15:09:29Z status=routed owner=burndown by=cr note=Rule 19 shared surface left in its old shape: api.spec should read instance counts against a baseline (outside Epic 8's footprint)
- 2026-10-28T01:13:02Z status=routed owner=8-7-epic-8-burn-down by=burndown note=chartered into Epic 8's burn-down; the sign-in split changes spec order, so api.spec reads instance counts against its own baseline
- 2026-10-28T04:00:48Z status=resolved-by:8-7-epic-8-burn-down by=adjudication note=api.spec reads instance-stream events against a per-test baseline; with heartbeat/ moved first, the old api.spec failed 4 tests and the new one passed 21 of 21 (9525ac0)

### DW-205: StallFixture's ticks after Hold record synthetic heartbeatGap marks (start = the moved-back mark) that no test removes
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: low | fix-risk: low | footprint: in-story
- evidence: a Tick after Hold(240) or Hold(100) finds the previous tick 2 to 4 clock minutes back, so Heartbeat.Record writes heartbeatGap.<mark>; Test.Schedule.Stalled and heartbeat.spec.ts leave them on throwaways
- 2026-10-25T15:09:32Z status=wontfix-theoretical owner=8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat by=cr note=real once a test or the step-2 digest reads Heartbeat.Gaps unfiltered on a stack that ran Stalled or heartbeat.spec

### DW-206: Test.Schedule.Stalled's ClearOf and Clean copy Test.Core.StatusMonitor's (zzstall for zzstatmon), the per-class cleanup idiom of six test classes
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Stalled.cls ClearOf/Clean match src/ocutalon/cls/OcuTalon/Test/Core/StatusMonitor.cls:301-316; the same DELETE of OcuTalon_Live.Event rows and Kill of ^OcuTalonP.LiveEventC sit in Test.Web.Api, Web.Install, Live.Publish and Data.Fixture
- 2026-10-25T15:09:36Z status=wontfix-accepted owner=8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat by=cr note=reopen_if=a change to OcuTalon_Live.Event or ^OcuTalonP.LiveEventC that has to be repeated in each test class's ClearOf copy

### DW-210: demo-path-summary.test.mjs's playwrightEnv() leaves the machine's browsers usable, so 'skip every unbuilt part' stays green for a demo-path test that launches a browser before it skips wherever Chromium is installed; only the browserless hosted web job goes red
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: web/scripts/demo-path-summary.test.mjs:332-337 deletes OCUTALON_URL and OCUTALON_E2E_JSON but sets no PLAYWRIGHT_BROWSERS_PATH, though its header says no browser starts; ffd7530 passed npm --prefix web test locally (565) and failed hosted run 40206917294; the 8.2 rework mutation (skip back in the test body) goes red only under PLAYWRIGHT_BROWSERS_PATH=/nonexistent-e8
- 2026-10-25T16:00:04Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=cr note=Rule 19 hermeticity; 8.4 adds the next stack-only demo-path test (03-reminder); fix: missing browsers path in playwrightEnv
- 2026-10-27T11:25:05Z status=routed owner=8-6-reminders-through-the-chat-on-the-demo-path by=spec_gate note=split_from_8.4(chat_side:mock_scenarios,REL-2_reminder_step,demo-path_spec_03)
- 2026-10-27T20:13:03Z status=resolved-by:8-6-reminders-through-the-chat-on-the-demo-path by=adjudication note=playwrightEnv() points PLAYWRIGHT_BROWSERS_PATH at a folder that never exists and drops OCUTALON_E2E_IRIS_CONTAINER, so 'skip every unbuilt part' goes red for a demo-path test that launches a browser before it skips, wherever Chromium is installed (isolating mutation observed in implement; web/scripts/demo-path-summary.test.mjs, 0b8d978 + review patch)

### DW-211: flake: OcuTalon.Test.Agent.Runners TestStartRefused ('and the Production step's check names it as not running') failed once in shard lane-a on the Linux CI host and passed on an unchanged rerun
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ci run 40209749982 attempt 1 (ocutalon-ci-13) red, attempt 2 (ocutalon-ci-6) lane-a passed 523s; the same IRIS code passed shards on ffd7530 (run 40206917294)
- 2026-10-25T16:37:50Z status=routed owner=burndown by=harvest note=Lane A's test (Test/Agent/**, contended with Epic 3); burn-down re-owns it to the owning lane's story
- 2026-10-27T02:50:15Z occurrence=5-9-ask-ocutalon-in-the-chat-to-dismiss-an-incident by=flake note=ci_run_40437523342_iris(shards)_live:floor:floor-webkit_G1_ring_bottom_600.98_vs_600;sha_98a2d57(no_web_change);rerun_--failed
- 2026-10-27T10:44:15Z occurrence=5-7-asked-whether-everything-is-fine-ocutalon-never-gives-a-fals by=flake note=ci_run_40485293208_iris(shards)_live:floor:floor-webkit_G1_ring_bottom_600.86_vs_600(a_rail_decision_button);sha_e1fe73c;rerun_--failed
- 2026-10-26T06:57:16Z status=routed owner=burndown by=adjudication note=code_fix_delivered_by_4.4(reveal-ring.ts_1px_margin_and_whole-pixel_scroll;local_live_floor_WebKit_G1_green);residual:_confirm_floor-webkit_G1_at_1280x600_green_on_at_least_three_Linux_CI_runs_(4.4-4.7_pushes)_at_the_burn-down
- 2026-10-27T05:26:00Z status=resolved-by:4-4-show-the-demo-guide-and-the-break-the-feed-box by=burndown note=reveal-ring 1px margin (4.4) confirmed: floor-webkit G1 at 1280x600 green on Linux CI runs 40304315110, 40367647349, 40385075588, 40421999437 (iris shards, live:floor) and 8b858ae's 40453411766 green

### DW-207: SetDemoMode(1) with an OCUORDERS that OcuTalon did not create keeps demo.mode 1 after the Demo step refuses (Plan error), so every later start stops at STEP Demo FAILED before Production and Ready; T4 says the next start runs the step again
- source: spec-4-1-switch-demo-mode-from-the-terminal.md | severity: med | fix-risk: med | footprint: in-story
- evidence: SettingsOps.Carry writes the value before RunStep; Install.Step.Demo.Plan answers error for on + a foreign namespace (AD-3); Install.Registry.Run stops at the first failed step (Demo precedes Production, Ready). Reachable on an IPM install into an instance with its own OCUORDERS.
- 2026-10-25T15:36:14Z status=decision-pending owner=burndown by=cr note=product call (matrix row Step fails keeps the value; any fix needs new terminal text, V2): refuse the on switch before audit and write when Plan says error
- 2026-10-27T05:39:36Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=unattended note=decision_sheet(Epic_4_merge_gate)_veto_U-106:_SetDemoMode_refuses_the_on-switch_before_audit_and_write_when_Install.Step.Demo.Plan_answers_error,_one_new_terminal_line;_15.2_proves_it_on_its_IPM_install_into_an_existing_instance
- 2026-10-27T05:49:00Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=owner note=U-106_kept_with_condition:_the_terminal_line_says_demo_mode_stays_off_and_why_(OCUORDERS_exists_and_OcuTalon_did_not_create_it),_same_style_as_the_other_Install_step_lines,_names_no_customer_data

### DW-208: Admin.Result and SettingsOps.Result are near-copies of the private CommandsIn.Result (a CommandResult with Ok, Outcome and Message), three 6-line builders (Rule 2)
- source: spec-4-1-switch-demo-mode-from-the-terminal.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Core/Admin.cls Result, Core/SettingsOps.cls Result, Core/CommandsIn.cls:151 Result (private, contended). Unifying needs a public factory on the cross-lane Msg.CommandResult contract or a public helper on the terminal API.
- 2026-10-25T15:36:22Z status=wontfix-accepted owner=4-1-switch-demo-mode-from-the-terminal by=cr note=reopen_if=a fourth CommandResult builder appears outside OcuTalon.Test, or CommandResult gains a field that every answer must set

### DW-215: Guide.Compute could report finished true with step 4 and a rejected/fallback/no_fix variant if a resolved incident keeps that OpenVariant (unverified)
- source: spec-4-2-derive-the-guide-state-and-break-the-feed-availability-on-th.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Demo/Guide.cls:105 finishes on any resolved incident while :92/:115 read OpenVariant without its state; AD-15 sets the variant only on moves to open, but no IncidentManager exists in this tree to confirm the overlap rows clear it
- 2026-10-25T19:46:38Z status=routed owner=4-7-finish-the-demo-guide by=cr note=unverified (maybe-false); settle with Story 5.5 IncidentManager: does a resolved incident ever carry a VARIANTS value?
- 2026-10-27T04:42:48Z status=resolved-by:4-7-finish-the-demo-guide by=adjudication note=Guide.Compute reads the open variant only while the incident is open or closed (VARIANTSTATES); TestVariantFollowsState pins it, a finished guide never carries a variant

### DW-216: Spine edge Guide --> Install.Step.Demo names only the demo-mode key; Compute also reads NAMESPACE and PRODUCTION
- source: spec-4-2-derive-the-guide-state-and-break-the-feed-availability-on-th.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ARCHITECTURE-SPINE.md:78 labels the edge 'its demo-mode key constant; Guide.DemoOn' while Demo/Guide.cls:45-46 reads #NAMESPACE and #PRODUCTION
- 2026-10-25T19:46:38Z status=wontfix-accepted owner=4-2-derive-the-guide-state-and-break-the-feed-availability-on-th by=cr note=reopen_if=a plan or review relies on the spine for Guide's reads of Install.Step.Demo; lead may relabel at a Rule 20 commit
### DW-199: AnswersIn's web handler must pass Approval.Answer either an empty sessionRef or the signed-in session's 22-character Ref: since Story 3.7, Answer answers not_allowed for any other sessionRef
- source: spec-3-7-every-action-and-governance-event-is-in-the-iris-audit-log.md (inbox U-69) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 3.7 (OCT-epic3 10c39c4) adds Answer's not_allowed check for a sessionRef that is neither empty nor a Ref; AnswersIn is a stub on the feature (69c7f06) until Epic 6
- 2026-10-25T12:10:22Z status=routed owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=owner note=U-69 condition (the Contest Planner for the owner): a test pins that a web answer passes the session's Ref, and that a malformed sessionRef answers not_allowed
- 2026-10-27T14:04:54Z status=resolved-by:6-2-approve-or-reject-a-fix-from-the-web-chat by=adjudication note=AnswerOps passes the session's 22-character Ref and its IRIS user; Test.Core.AnswersIn:TestMalformedSessionRefNeverReaches and AnswersInProduction:TestMalformedSessionRefIsNotAllowed (AC11)

### DW-200: AnswersIn's Telegram entry must pass Approval.Answer either an empty sessionRef or the paired session's 22-character Ref from the live Pairing row, never a ChatRef or chat id: since Story 3.7, Answer answers not_allowed for any other sessionRef
- source: spec-3-7-every-action-and-governance-event-is-in-the-iris-audit-log.md (inbox U-69) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 3.7 (OCT-epic3 10c39c4) adds Answer's not_allowed check for a sessionRef that is neither empty nor a Ref; Story 10.3 adds AnswersIn's Telegram entry, which Story 12.7's TelegramIn calls with a ChatRef
- 2026-10-25T12:10:22Z status=routed owner=10-3-the-session-side-of-telegram-is-ready-and-stays-off by=owner note=U-69 condition (the Contest Planner for the owner): the entry's fixture tests pin that a press passes the paired session's Ref, and that an unresolvable one answers not_allowed
- 2026-10-31T10:06:02Z status=resolved-by:10-3-the-session-side-of-telegram-is-ready-and-stays-off by=burndown note=delivered_by_10.3_d917d26(adjudication_trailer_missed_on_2026-10-28): AnswersIn.FromTelegram passes only the paired session's Ref (Core/AnswersIn.cls:44-80); Test/Core/AnswersTelegram.cls TestApprovedAndRejected:74 pins sessionRef=the session's Ref, TestBadSessionRefIsNotAllowed:128 pins not_allowed with nothing handed over

### DW-214: Build 154 serves IRIS's own %CSP.PasswordChange.cls (200) at /ocutalon/trace/ocutalon/ and /ocutalon/trace/ocuorders/ to a signed-in user despite PermittedClasses; the demo host's proxy must block that path
- source: spec-16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 16.1 implement stage, live online-demo on lane C: signed in, %25CSP.PasswordChange.cls answers 200 at both trace apps; a change through it (F12) succeeds for a non-public user and is refused for both public accounts by the guard
- 2026-10-25T19:05:03Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=harvest note=29.3 blocks every password-change page: include /ocutalon/trace/*/%CSP.PasswordChange.cls (any letter case, percent-encoded) in the proxy's blocked list and its test
- 2026-10-30T08:06:49Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=adjudication note=measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4): the host filter answers 404 to every %CSP.PasswordChange.cls path form (encoded, double-encoded, any letter case, with a query, signed in or out, both trace apps, /ocutalon/, /csp/broker/), IRIS alone 200; release/demo-host-check.sh block-pw-* carries every measured form (build 1aab3da + review patches), pinned by docker/tests/test-online-host.sh row 4 and the live online-demo Story 29.3 section; check list H4
- 2026-10-30T04:03:21Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=orchestrator note=U-81 measured on the gated host by the Contest Planner 2026-10-30 after the Epic 16 deploy: the host filter answers 404 to every %CSP.PasswordChange.cls path form (encoded, double-encoded, any letter case, with a query, signed in or out, trace apps and /csp/broker/); IRIS alone serves it 200; controls 200. 29.3's host check script carries these cases; close at 29.3's adjudication

### DW-217: Web/Api.cls's class comment and StateBody's comment do not name the new traceAccount key (only TraceAccount()'s own comment does)
- source: spec-16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac.md | severity: low | fix-risk: low | footprint: in-story
- evidence: src/ocutalon/cls/OcuTalon/Web/Api.cls:1-20 and the StateBody comment ('keys in this order, ending at status')
- 2026-10-25T19:56:52Z status=open owner=16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac by=harvest note=two-way door: the code-review stage may edit those comment lines (doc-only; a conflict with Epic 4 on them is a plain union, lead ruling)
- 2026-10-25T20:53:31Z status=resolved-by:16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac by=adjudication note=code-review patched both comment lines of Web/Api.cls (class comment :10, StateBody comment :270-271) to name traceAccount and its condition

### DW-219: test-online-demo.sh's Never-line password scan searches no production message body (the logs, event log, live events and audit are searched)
- source: spec-16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac.md | severity: low | fix-risk: med | footprint: in-story
- evidence: The Never line names a log line, a live event, a production message and an audit entry; check_logs_clean covers all but message bodies, which have no generic search across body classes.
- 2026-10-25T20:49:40Z status=wontfix-accepted owner=16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac by=cr note=reopen_if=a message body or live payload gains a field fed from readonlyPassword or demoPassword (grep src/)

### DW-220: live:online-demo joined the image group on a unit-against-group comparison (116-138 s local against the group's 600 s CI guideline)
- source: spec-16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac.md | severity: low | fix-risk: low | footprint: in-story
- evidence: image ran 9m42s-13m50s on CI before (Rule 21); +116-138 s local is about +280-540 s on CI at the measured 2.4-3.9x factor, so the group likely passes 600 s; the group is the lead's call.
- 2026-10-25T20:49:40Z status=wontfix-accepted owner=16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac by=cr note=reopen_if=the image job of the first CI run with online-demo is the longest IRIS job, or the run passes 35 min
- 2026-10-25T20:53:31Z status=wontfix-accepted owner=16-1-the-online-demo-s-settings-arrive-at-start-and-its-public-ac by=adjudication note=lead keeps live:online-demo in image (CI image job ~1050-1065 s today, ~+300-500 s: about 25 min, inside the 40 min job timeout and REL-4's 35 min run budget; production stays web-bundle-free; a seventh group needs ci.yml, Epic 10's) reopen_if=the image job passes 30 min or a whole ci run passes 35 min
- 2026-10-29T12:13:57Z status=routed owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=spec_gate note=reopen_if met: on b582ed4 (run 40813183274) the image job took 2369 s and the run 40 min, over REL-4's 35 min (owner-fixed 9: rebalance the groups first); live:online-demo (556 s on CI) leaves image for install-upgrade (794 s), so image is about 1813 s and no IRIS job passes shards' 1896 s, with Story 16.9's new unit placed in whichever of install-fresh and install-upgrade keeps both under it
- 2026-10-29T12:16:50Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=spec_gate note=moved from 16.9 to 16.4's CI rework: on 0af9742 the image job timed out at 40 min (run 40866408272), shard:lane-b 706->866 s with 16.4's classes; move live:online-demo to install-upgrade
- 2026-10-29T14:01:55Z occurrence=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi
- 2026-10-29T14:01:55Z status=routed owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=image left at ~2047 s (0af9742 units minus online-demo, ~34.6 min job): reopen_if 30 min still met; 16.9 rebalances
- 2026-10-29T22:51:03Z status=resolved-by:16-9-allowances-cap-messages-model-cost-and-simulated-emails by=adjudication note=ci/units.sh_moves(live:demo-switch_to_install-upgrade,live:online-allowance_to_install-fresh;16.4_moved_live:online-demo_to_install-upgrade);CI_run_40945229992(ba6856d,same_ci/units.sh):image_26.9min(was_34.1),install-upgrade_31.7,install-fresh_27.8,shards_32.4,browser_25.0,production_18.1;wall-clock_32m28s;image_no_longer_the_longest;no_job_over_REL-4s_35min;the_committed_head_and_the_merged_head_are_measured_at_their_ci_resolved

### DW-221: REL-2's online-demo run lives in web/e2e-online/demo-path.spec.ts (run by the online-demo unit, image group), not under web/e2e/demo-path/; its steps 2-6 are notBuilt(...,'11.1'), outside the demo-path gate's view
- source: spec-16-2-the-splash-screen-shows-the-demo-and-its-sign-in-details.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 16.2 spec gate: the demo-path project lists every spec under web/e2e/demo-path/ and demo-path-summary/test-demo-path-gate.sh pin file-to-step mapping, so the online run sits in the online-demo project; Story 16.2's AC says Story 11.1 turns its later steps on
- 2026-10-25T21:32:41Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=spec_gate note=11.1 turns on the online run's steps 2-6 in web/e2e-online/demo-path.spec.ts together with the web run's (the online-demo unit runs them on its flag-on throwaway)
- 2026-10-30T13:10:06Z occurrence=29-4-sessions-stay-isolated-under-load by=cr note=moved to e2e-online/demo-path/ (unit online-demo-path, shards-2); step 6 is real; report_check pins the 4 skips of 11.1

### DW-225: The path lists that name SignInAssets.cls (ci/units.sh WEB_INPUT_PATTERN, test-ci-changes, test-compose-file's not-ignored check, test-boundaries' scope) do not name SplashAssets.cls or splash.css/js
- source: spec-16-2-the-splash-screen-shows-the-demo-and-its-sign-in-details.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ci/units.sh:54, docker/tests/test-ci-changes.sh:191, test-compose-file.sh:336 and test-boundaries.sh:110 name only the sign-in assets (shared or contended files); staleness is still caught by every IRIS job's npm build (tokens.mjs --check) on any src/ change
- 2026-10-26T00:29:42Z status=wontfix-accepted owner=16-2-the-splash-screen-shows-the-demo-and-its-sign-in-details by=cr note=reopen_if=a SplashAssets.cls-only change passes CI with no job running tokens.mjs --check, or the file is gitignored

### DW-226: AD-25 says a sign-in POST's decoded field names are exactly IRISSessionToken, IRISUsername, IRISPassword and IRISLogin, but the splash (like the local page) posts three, with no IRISSessionToken
- source: spec-16-2-the-splash-screen-shows-the-demo-and-its-sign-in-details.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Task 0 (b) measured the splash form's inputs as IRISPassword and IRISUsername (plus the IRISLogin button); row 7, S7, TestPage and the unit read AD-25 as only-these; a proxy built on the literal word would refuse every sign-in
- 2026-10-26T00:29:46Z status=wontfix-accepted owner=16-2-the-splash-screen-shows-the-demo-and-its-sign-in-details by=cr note=reopen_if=Story 29.3's proxy or its stand-in refuses a sign-in POST that carries no IRISSessionToken
- 2026-10-26T00:55:26Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=adjudication note=integration risk for the demo host, not a LOW to close: the splash's first sign-in POST carries IRISUsername, IRISPassword and IRISLogin with no IRISSessionToken (measured, Story 16.2); 29.3's proxy allow-list must admit any subset of the four names (only-these), never require all four, else every online-demo sign-in is refused; test it with the splash's real POST
- 2026-10-30T08:06:49Z status=decision-pending owner=burndown by=adjudication note=the repository follows AD-25 as veto ruling U-158 reads it (a sign-in body's names all come from the four; the splash's three-field sign-in admitted, measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4)); the open question is AD-25's guard wording amendment (U-158's recommended text), for Epic 29's decision sheet
- 2026-10-31T09:02:42Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=merge_gate note=AD-25's_sign-in_rule_reworded_at_Epic_29's_merge_as_veto_U-158_reads_it(names_all_from_the_four;the_pattern_excepts_a_sign-in_body's_one_IRISPassword)

### DW-233: The address counter stores an unsalted SHA-256 of the client address, so an IPv4 value can be brute-forced from a row within its one-hour life
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: med | fix-risk: med | footprint: in-story
- evidence: AddressCounter.Add stores Session.Hash(address), a plain SHA-256 (AD-13: a hashed address); the 2^32 IPv4 values can be enumerated in minutes; rows live one hour, in OCUTALON_PRIVATE
- 2026-10-26T04:26:20Z status=decision-pending owner=burndown by=cr note=veto (stored data, security): recommend an HMAC with a per-instance key in the private DB, renewed at each reset
- 2026-10-30T03:14:28Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=merge_gate note=veto U-156 (Epic 16 decision sheet): before the launch, replace the plain SHA-256 with an HMAC keyed by a per-instance secret in the private database, renewed at each reset
- 2026-10-30T04:25:32Z status=routed owner=29-5-the-address-counter-s-hash-is-keyed-per-reset by=spec_gate note=split from 29-3 (Rule 5 tier 2, runner C ruling 2026-10-30); bullet moved to Story 29.5
- 2026-10-30T16:06:42Z status=resolved-by:29-5-the-address-counter-s-hash-is-keyed-per-reset by=adjudication note=build 363395bb + review patches: AddressCounter.AddressHash is an HMAC-SHA-256 under a 32-byte key in ^OcuTalonP.AddrCountK (private database), made at its first use after a start whose lastReset differs from the key's marker (veto U-167), so no golden copy holds one; TestKeyPerReset proves T1..T4 give pairwise different keys and hashes, a restored captured key is replaced; live online-demo rows 12/13 and phase 2 pin it on a fresh stack

### DW-234: On the online demo a proxy address that is unset or not equal to REMOTE_ADDR exactly (a changed proxy IP, another address form) exempts every sign-in, so the per-address limit silently stops
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: SessionEvents.ClientAddress counts a sign-in only when proxyAddress = REMOTE_ADDR exactly and exempts the rest (AC 5, epics 16.3, AD-13); nothing reports a proxy address that never matches
- 2026-10-26T04:26:20Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=launch check on the host: one proxied sign-in writes a counter row (the unit's phase 2 precondition); pin the proxy IP
- 2026-10-30T08:06:50Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=adjudication note=measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4): proxied sign-ins write an address-counter row; no repository fix (reasons in the spec's Design Notes); release/demo-host-checks.md H2 and its proxy-address section keep the check in the Planner's pass

### DW-235: AddressCounter.Shift and SessionEvents.CookieExpiry repeat Public.Settings' private ToSeconds/FromSeconds UTC parsing instead of sharing one helper
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Shift is ToSeconds + n + FromSeconds (Data/Public/Settings.cls ToSeconds/FromSeconds, private, read-only in 16.3); CookieExpiry parses the same form again
- 2026-10-26T04:26:20Z status=routed owner=16-8-the-page-counts-down-to-the-reset-and-waits-it-out by=cr note=Rule 2: one public UTC-seconds helper in Public.Settings; Shift and CookieExpiry delegate to it
- 2026-10-26T20:06:41Z status=resolved-by:16-8-the-page-counts-down-to-the-reset-and-waits-it-out by=adjudication note=ed9351c: Public.Settings ToSeconds/FromSeconds/Shift public; AddressCounter.Shift delegates (AddressCounter.cls:84); CookieExpiry parses through Settings.ToSeconds (SessionEvents.cls:112); Test.Data.PublicSettings source check holds no $ZDateTimeH, mutation-proved (spec Verification AC 6)

### DW-236: test-online-demo.sh's ref_script and check_ref_session copy lib-live.sh's iris_script and check_session only to pass an environment variable
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ref_script repeats iris_script's retry loop and CHK filter (docker/tests/lib-live.sh:307-317) adding -e; lib-live.sh is a contended path, so 16.3 could not extend it
- 2026-10-26T04:26:20Z status=escalated owner=burndown by=cr note=Rule 2: give iris_script an env pass-through and let ref_script/check_ref_session delegate (contended file)
- 2026-10-30T03:14:28Z status=routed owner=29-4-sessions-stay-isolated-under-load by=merge_gate note=Epic 16 decision sheet (decide): Rule 2, give iris_script an environment pass-through and let ref_script and check_ref_session delegate, when 29.4 edits the online test scripts
- 2026-10-30T13:14:02Z status=resolved-by:29-4-sessions-stay-isolated-under-load by=adjudication note=build 17a1f68: iris_script passes the names in LIVE_SESSION_ENV as -e to dc exec (check_session documents it); test-online-demo.sh lost ref_script and check_ref_session and row 6 searches through check_session with LIVE_SESSION_ENV=OCUTALON_T16_REF; live:online-demo passed after implement and after review

### DW-237: Story 10.3's Pairing.HashCode must delegate to Session.Hash (Story 16.3) instead of adding a second SHA-256 base64url helper
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Session.Hash (16.3) has AD-4's HashCode shape; Data/Pairing.cls is Epic 10's, so the spec forced the copy by order (Design Notes, Rule 2)
- 2026-10-26T04:26:20Z status=routed owner=10-3-the-session-side-of-telegram-is-ready-and-stays-off by=cr note=Rule 2 forced copy: HashCode(code) quits Session.Hash(code)
- 2026-10-31T10:06:02Z status=routed owner=31-4-the-paired-chat-stays-isolated-under-load-too by=burndown note=residual: Data/Pairing.cls:68 HashCode still repeats Data/Session.cls:122 Hash's body (same SHA-256 base64url line, plus an empty-code guard); make HashCode keep its guard and quit Session.Hash(code). Not covered by 10.3 (missed adjudication); overflow, not chartered (1 entry, under cap 8, no occurrences; Story 10.4 is a README-only re-open with a launch deadline). 31-4 is a Lane B pairing story (Data/Pairing.cls is Lane B's, AD-29)

### DW-238: Session.ForUser (TOP 1 by IrisUser) can return a visitor row as a user's durable session if onlineDemo is turned off on an instance that keeps visitor rows
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: low | fix-risk: low | footprint: in-story
- evidence: ForUser's SELECT has no ResumeHash IS NULL; only Ownership.Attach calls it, on the flag-off path; visitor rows exist only on a demo instance
- 2026-10-26T04:26:21Z status=wontfix-theoretical owner=16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re by=cr note=real if a demo instance restarts with onlineDemo off and keeps its data; fix: AND ResumeHash IS NULL

### DW-239: Test.Web.Install.CounterRow repeats Test.Data.AddressCounter.Row (a counter row of a given age)
- source: spec-16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re.md | severity: low | fix-risk: low | footprint: in-story
- evidence: two 5-line fixture helpers in test classes of two areas; sharing one would tie the Web-area class to the Data-area class
- 2026-10-26T04:26:21Z status=wontfix-accepted owner=16-3-signing-in-opens-a-session-this-browser-resumes-until-the-re by=cr note=reopen_if=a third test class builds AddressCounter rows by hand

### DW-240: The demo host must serve the four logo files (logo/web/) beside docker/maintenance.html; the page names them and loads nothing from IRIS
- source: spec-16-5-a-full-demo-says-it-is-busy-and-the-host-s-busy-and-maintena.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 16.5 spec gate: AC 'with only its own inline styles and the logo files beside it'; a PNG in docker/ fails test-boundaries.sh on macOS grep, so the logos stay in logo/web/ and the host copies them beside the page
- 2026-10-26T05:22:26Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=spec_gate note=29.3 deploys docker/busy.html and docker/maintenance.html with the logo/web/ files the maintenance page names, beside it
- 2026-10-26T20:05:20Z occurrence=16-8-the-page-counts-down-to-the-reset-and-waits-it-out
- 2026-10-26T20:05:20Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=also at /ocutalon/assets/brand/<name>: the 16.8 resetting view asks for them there at the switch, as IRIS stops
- 2026-10-30T08:06:50Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=adjudication note=measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4): the four logos answer 200 through the proxy at /ocutalon/, /ocutalon/assets/brand/ and deeper while IRIS is down; release/demo-host-check.sh maint-logo-* compares them byte for byte at both locations (test-online-host.sh row 14 and QA's altered-byte runs); H7

### DW-251: On build 154 (lane-C throwaway, Community key, the image's web server) a signed-in CSP session does not raise $SYSTEM.License.InstanceConnections(), so AD-13's busy checks (status, splash, post-sign-in reserve) may never engage on the demo host
- source: spec-16-5-a-full-demo-says-it-is-busy-and-the-host-s-busy-and-maintena.md | severity: high | fix-risk: med | footprint: out-of-footprint
- evidence: Story 16.5 Task 0: the count reads 1 with no session, one and two sessions (browser), over keep-alive and after sign-out; S13 had found one connection per signed-in session through a proxy; tests reach busy via a baseline-relative cap
- 2026-10-26T07:48:33Z status=routed owner=29-4-sessions-stay-isolated-under-load by=harvest note=29.4 measures on the demo host, through the proxy, whether signed-in sessions raise InstanceConnections() and whether status busy, the splash busy state and the post-sign-in reserve engage before IRIS's own 503; if they do not, raise the AD-13 counter question (a counter OcuTalon controls, e.g. attached visitor CSP sessions) to the orchestrator
- 2026-10-30T04:25:32Z by=runner note=host fact measured on the gated host by the Contest Planner 2026-10-30: busy is one connection lenient (OWNCONNECTIONS=1 assumes the new session holds a connection; a signed-in CSP session is not counted, so a proxied sign-in was admitted while busy); Story 29.4's author load case measures it against the 8-licence-unit ceiling
- 2026-10-30T09:28:01Z status=routed owner=29-7-the-author-s-load-run-measures-the-demo-s-capacity by=spec_gate note=split from 29-4 with the fourth criterion; confirmed by 29.4's plan Task 0 (a signed-in visitor raises no InstanceConnections); the AD-13 busy-rule question is with the orchestrator
- 2026-10-30T16:45:40Z status=routed owner=29-7-demo-busy-counts-the-live-visitors by=spec_gate note=Story 29.7 retitled when its load criterion moved to 29.8 (runner C split ruling 2026-10-30); the visitor count (U-163) closes it
- 2026-10-30T23:44:15Z status=resolved-by:29-7-demo-busy-counts-the-live-visitors by=adjudication note=build 65906a18 + review: busy no longer depends on a signed-in visitor raising InstanceConnections: a proxied sign-in marks its CSP session, /status, the login page and the post-sign-in check count the live marked sessions against the visitor cap of 6 (OWNCONNECTIONS 0); live:online-visitors V1 shows the 6th in and the 7th Demo busy on a fresh stack

### DW-252: No page control sends a guide prompt yet, so the online demo's 503 rule for a guide message (the entry leaves, nothing is announced) has no test
- source: spec-16-5-a-full-demo-says-it-is-busy-and-the-host-s-busy-and-maintena.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: ChatOutbox.send(text, fromGuide) has no caller with fromGuide true in web/src/app; the first caller is Epic 4's guide; the rule is in ChatOutbox.refuse; B2 sends typed text only
- 2026-10-26T07:48:33Z status=routed owner=burndown by=harvest note=testable once Epic 4's guide sends prompts and has been integrated forward; the burn-down gate checks
- 2026-10-30T02:55:13Z owner=29-4-sessions-stay-isolated-under-load by=burndown note=overflow(Epic_16_burn-down,no_charter:5_entries_under_the_cap_of_8,none_with_2+_occurrences):the_guide_now_sends_prompts(demo-guide.ts_via_ChatOutbox.send(text,true));chat-outbox.ts:130_drops_a_refused_guide_entry_silently_but_no_test_pins_the_online_demos_503_rule_for_it;29.4_drives_the_online_demo_full_with_one_more_visitor_seeing_busy:add_an_e2e-online_case_(a_guide_prompt_answered_503_leaves,nothing_announced)
- 2026-10-30T13:14:02Z status=resolved-by:29-4-sessions-stay-isolated-under-load by=adjudication note=web/e2e-online/busy.spec.ts B2b presses guideSend at the cap and pins the 503 rule (the entry leaves, nothing is announced); live:online-demo passed after review

### DW-254: The demo host must run docker/probe.sh every 15 minutes with bash and curl, reach IRIS directly from an address other than the public proxyAddress, and provide its environment (OCUTALON_PROBE_URL, the demo credentials, alert and reset commands, a state directory)
- source: spec-16-6-a-probe-checks-the-demo-every-15-minutes.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 16.6 spec gate: the probe's host interface is recorded in the spine's Consistency Conventions row 'Online-demo probe'; a probe reaching IRIS from proxyAddress is counted and refused like a visitor
- 2026-10-26T09:37:00Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=spec_gate note=29.3 installs and schedules the probe per the spine's 'Online-demo probe' row and checks its alert and reset wiring on the host
- 2026-10-30T08:06:50Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=adjudication note=the probe's host interface (variables, 15-minute run with bash and curl, a direct connection from an address other than proxyAddress, outcomes, exit codes) is in release/demo-host-checks.md; measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4): the probe is healthy and its scheduled run alerted busy; the schedule, environment and source address remain release check H20, the Planner's hands-on pass

### DW-260: The probe counts any decision but a daily_cap fallback as healthy, so a demo whose every turn falls back (no_key, a timeout, rate limits) reports healthy and never alerts; only the log line names the reason
- source: spec-16-6-a-probe-checks-the-demo-every-15-minutes.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Story 16.6 implement: on a stack with no model key the probe logs 'healthy ... fallback=no_key'; the AC defines healthy as 'a decision' and only daily_cap as capped
- 2026-10-26T11:11:47Z status=decision-pending owner=burndown by=harvest note=product call for the decision sheet: should a non-daily_cap fallback (no_key, timeout, rate_limit) alert the author without counting toward a reset? Recommended: yes, as an alert-only outcome like busy, if the owner agrees (it changes the AC's outcome list)
- 2026-10-30T03:14:28Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=merge_gate note=veto U-157 (Epic 16 decision sheet): an alert-only probe outcome for no_key, timeout and rate_limit fallbacks, which alerts the author and never counts toward a reset, like busy
- 2026-10-30T04:25:32Z status=routed owner=29-6-the-probe-alerts-when-every-turn-falls-back by=spec_gate note=split from 29-3 (Rule 5 tier 2, runner C ruling 2026-10-30); bullet moved to Story 29.6
- 2026-10-30T19:28:05Z status=resolved-by:29-6-the-probe-alerts-when-every-turn-falls-back by=adjudication note=build 8c4db572 + review: docker/probe.sh reports degraded for no_key, timeout and rate_limited fallbacks (alerts, exit 1, neither the failure count nor the busy count changes), pinned by test-probe.sh row 13, the QA paths and the degraded sequence, and live online-demo P9 (degraded count=1 fallback=no_key); release check H20 names it; the error fallback question is DW-446 (decision-pending)

### DW-268: The probe never signs out a sign-in IRIS accepted (3xx) when the redirect GET is not the shell (busy, timeout, other page), so the CSP session holds its connection until its 120 s timeout
- source: spec-16-6-a-probe-checks-the-demo-every-15-minutes.md | severity: med | fix-risk: med | footprint: in-story
- evidence: docker/probe.sh step 3 sets signed_in=1 only on <app-root; signout() returns when it is 0; hermetic QA path shell_other expects 0 sign-outs (edge-case-hunter, acceptance-auditor)
- 2026-10-26T12:16:12Z status=by-design owner=16-6-a-probe-checks-the-demo-every-15-minutes by=cr note=spec Boundaries: signed in = shell, no API call before it, no IRIS query field; reopen via spec amendment

### DW-269: At every reset the demo host must set OCUTALON_LAST_RESET to the time of the reset that just happened (never earlier than its scheduled time) and OCUTALON_LAST_RESET_KIND; the page leaves its resetting view only when status reports ready with lastReset later than the page's load time (or 15 minutes past the reset)
- source: spec-16-8-the-page-counts-down-to-the-reset-and-waits-it-out.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 16.8 spec gate: the resetting view navigates on ready AND lastReset later than its load time; a host that leaves the old lastReset keeps visitors on the resetting view for 15 minutes
- 2026-10-26T13:04:41Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=spec_gate note=29.3's reset command writes the new last reset and its kind into the start values before IRIS starts again
- 2026-10-28T23:55:20Z status=resolved-by:10-3-the-session-side-of-telegram-is-ready-and-stays-off by=adjudication note=AnswersIn FromTelegram resolves the session from the live Pairing row and passes Approval.Answer that 22-character Ref, never a ChatRef; a malformed SessionRef answers not_allowed with nothing sent; pinned by Test.Core.AnswersTelegram and AnswersTelegramProduction (FromTelegram rows, DW-200 argument mutation)

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
- 2026-10-25T22:25:43Z status=routed owner=5-2-new-failures-are-picked-up-within-seconds by=spec_gate note=decided(U5_decision_dependency;FR-23:every_readable_namespace's_production):Watch.Reader also lists a readable namespace's last production when none runs (the platform's record of it measured in a Task 0 on a throwaway, never every Ens.Config.Production row, DW-38 kept), so a stopped production can be watched (its check reports the state, Story 5.6); stop_watch also resolves from the session's own BackgroundCheck rows, so a watch can always be stopped
- 2026-10-26T02:31:02Z status=resolved-by:5-2-new-failures-are-picked-up-within-seconds by=adjudication note=Reader.Current falls back to Ens.Director.GetActiveProductionName() when nothing runs (a stopped production is listed and admitted); stop_watch resolves from the session's own watches through Ownership.Checks first; Test.Watch.Reader stopped-production test and Test.Watch.Tools own-row and real-path tests pin it

### DW-223: Install.Step.Demo.WithOrdersData (Story 5.1, U-79) is a near-copy of WithOrders (about 18 of its 20 lines), differing only in the resource list it edits
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls WithOrders and WithOrdersData; the U-79 ruling forbade reshaping WithOrders in Epic 4's file, so the copy was forced; a parsing fix to one would miss the other
- 2026-10-25T21:52:41Z status=routed owner=burndown by=cr note=Rule 2 forced copy: unify by giving WithOrders the resource list as an argument once Epic 4's Demo.cls work has merged
- 2026-10-27T10:02:57Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=burndown note=overflow:Install/Step/Demo.cls_is_contended(Epic_15_owns_Install/**,waiting_with_work),so_Epic_5_cannot_unify_it;Epic_4_has_merged,so_the_U-79_reason_for_the_copy_is_gone:give_WithOrders_the_resource_list_as_an_argument_when_15.2_(or_Epic_15%27s_burn-down)_touches_Demo.cls

### DW-224: Test.Watch.Turns and Test.Watch.Case copy Test.Tools.Reminders' turn helpers (Turn, AssertTurn, AssertSteps, Begin, Calls, SortedKeys) instead of sharing them
- source: spec-5-1-ask-ocutalon-to-watch-a-production-and-to-stop.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Test/Watch/Turns.cls and Test/Watch/Case.cls repeat Test/Tools/Reminders.cls 874-1085 nearly line for line; the spec named them templates; sharing needs one helper across ZoneCase and InProduction
- 2026-10-25T21:52:41Z status=wontfix-accepted owner=5-1-ask-ocutalon-to-watch-a-production-and-to-stop by=cr note=reopen_if=a third test class copies these helpers, or a fix to one copy (such as the mock-log read) is missed in another

### DW-227: The fresh lane-a shard (54 classes) took 539 s on the developer machine, about a minute under the 10-minute foreground cap that every stage and the lead's fresh check run inside; one more class pushes a fresh run past the cap. Give ci/iris.sh shard a local split (for example --part k/n over the sorted class list, with --reverse taking the parts of the reversed list), CI unchanged
- source: spec-5-2-new-failures-are-picked-up-within-seconds.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: 5.2 implement: shard lane-a passed 54 classes in 539 s (5.1: 52 classes 422-475 s; Epic 3: ~400 s); runner brief: split long runs into calls that finish well inside the cap; ci/iris.sh is not contended (Epic 5 footprint extension), test-ci-config.sh takes an appended block
- 2026-10-26T00:59:33Z status=routed owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=harvest note=lead_routed:tooling_before_5.3's_own_tests_grow_the_shard;CI_groups_unchanged(no_REL-4_impact)
- 2026-10-26T02:18:48Z occurrence=5-2-new-failures-are-picked-up-within-seconds
- 2026-10-26T07:01:49Z status=resolved-by:5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=adjudication note=ci/iris.sh shard <name> --part k/n runs the k-th contiguous part of the (reversed) name-ordered class list, larger parts first, bad values exit 2; the appended test-ci-config.sh block prints PASS shard part; lane-a measured 377 s (part 1/2, 29 classes) and 295 s (part 2/2, 28 classes); ci/units.sh and the workflows unchanged

### DW-228: FailurePoller keeps a not_current production's mark, so when another production ran in the namespace meanwhile and the watched one is current again, the other's failures since the mark are batched as the watched one's
- source: spec-5-2-new-failures-are-picked-up-within-seconds.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Reader.Current reads every Status 8 header and sessionless Type 2/6 log row of the namespace from the mark with no production filter; Poll quits without saving on not_current (spec Design Notes; spine row Watch failures: a production the reader does not read keeps its mark)
- 2026-10-26T02:18:48Z status=by-design owner=5-2-new-failures-are-picked-up-within-seconds by=cr note=spec-bound; reopen via amendment: a not_current production's mark moves to the poll time (unreadable keeps it)

### DW-229: A fault inside Reader.Current reaches FailurePoller as a poll warning only through Failures' fault check, which no test drives (TestReadErrorWarns throws at the poller's seam), so removing the check would make real read faults silent
- source: spec-5-2-new-failures-are-picked-up-within-seconds.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Reader.Failures line 'If fault ... ThrowStatus'; deleting it returns an empty outcome, Poll quits silently and every test stays green (verification-gap layer); no cheap trigger makes Current fault without a new seam
- 2026-10-26T02:18:48Z status=wontfix-accepted owner=5-2-new-failures-are-picked-up-within-seconds by=cr note=reopen_if=a readable watched production whose read faults in Reader.Current leaves no Type 3 FailurePoller warning

### DW-230: No test shows that one watched production's failing poll still lets the other watched productions be polled in the same FailurePoller run (the per-production Try in OnProcessInput)
- source: spec-5-2-new-failures-are-picked-up-within-seconds.md | severity: low | fix-risk: med | footprint: in-story
- evidence: every Poller test watches one production; the probe's throw mode throws for every production; a second probe mode would be needed
- 2026-10-26T02:18:48Z status=wontfix-accepted owner=5-2-new-failures-are-picked-up-within-seconds by=cr note=reopen_if=after a FailurePoller warning for one production, another watched production's mark stops moving while its failures arrive

### DW-241: The error branches of IncidentManager.Tell (a failed Session.Recipients read; a failed publish while other recipients still get the event) have no test
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Tests assert only that no warning is logged on the success and nobody-watches paths; forcing Recipients or Publish to fail needs a seam the story does not add; the code logs one Type 3 warning per event and leaves the rows standing
- 2026-10-26T05:39:47Z status=open owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=harvest note=implement_deferred(build-auto_review)
- 2026-10-26T06:56:42Z occurrence=5-3-same-cause-failures-become-one-incident-by-the-settle-rule
- 2026-10-26T07:01:49Z status=wontfix-accepted by=adjudication note=the failed-publish branch is covered by Test.Watch.Tell (QA, cr-patched); the failed Session.Recipients read needs a production seam to force (about 28 lines with probe and test) and only a privilege-check failure reaches it; reopen_if=a Recipients read error in IncidentManager leaves no Type 3 warning, or DW-113 (6-2) makes the branch reachable through the real Session.Recipients

### DW-242: IncidentManager's rolled-back batch (Record) and failed Settle send (Start) branches have no test
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Neither branch can be forced without a seam in IncidentManager; the build review deferred them to the frontmatter, which lists only Tell's branches
- 2026-10-26T06:56:31Z status=wontfix-accepted owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=reopen_if=a FailureBatch in error leaves Incident rows, or an incident lacks TraceHeaderId 60 s after its FirstAt

### DW-243: The settle waiter's guards for a closed or already-settled incident are unpinned, and a resent Settle request would start a second waiter
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Waiting's closed/NoticeCount checks and Begin's overwrite of TraceHeaderId are reached by no test; AD-15's table never closes or settles an unnoticed incident outside its waiter
- 2026-10-26T06:56:31Z status=wontfix-theoretical owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=real if an unnoticed incident can close or settle outside its waiter, or an operator resends a Settle request

### DW-244: No test shows that the settle waiter reads watch.settleQuietSeconds and watch.settleMaxSeconds; only Settle.Values is tested in the test process
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Replacing Check's Settle.Values call with constants leaves every test green; a test needs a setting row the job reads past Data.Setting's 60 s cache, and the spec seeds none
- 2026-10-26T06:56:31Z status=wontfix-accepted owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=reopen_if=once watch.settle* can be set, changing watch.settleQuietSeconds does not move when NoticeCount is set

### DW-245: The settle maximum runs from the first failure's FailedAt, so failures picked up late (a poller backlog) settle at once with the first batch's count
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Check compares now with FirstAt + max, and FirstAt is the failure's own FailedAt, not the time the incident was made
- 2026-10-26T06:56:42Z status=by-design owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=spec Decided in-stage: times are the failures' own FailedAt; AD-15: 30 s after the first failure

### DW-246: The error pattern masks only digit runs, so error texts that carry hex ids or GUIDs can split one cause into several incidents
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Settle.Pattern replaces each run of digits with # and collapses white space; letters a-f of a hex id stay
- 2026-10-26T06:56:42Z status=by-design owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=spec Always rule defines the error pattern; it changes only by spec amendment

### DW-247: Tell's Publish waits up to Live.Publish's LOCKWAIT (5 s) per held session stream inside IncidentManager's single job, stalling batches and wakes
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Publish(stream, type, payload) takes the stream lock with LOCKWAIT 5; IncidentManager has PoolSize 1; Live/Publish.cls is a contended path
- 2026-10-26T06:56:42Z status=wontfix-theoretical owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=real if a session stream lock is held for seconds in normal operation; Publish holds it for one append

### DW-248: ci/iris.sh shard --part with a value that contains a newline exits 1 instead of 2, because the k/n check greps line by line
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: low | footprint: in-story
- evidence: printf | grep -Eq accepts a value whose first line is k/n; the arithmetic expansion then fails
- 2026-10-26T06:56:42Z status=wontfix-theoretical owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=real if a caller passes a multi-line --part value; every caller passes k/n literally

### DW-249: IncidentManager assumes a batch's OwnerRef, Namespace, Production and PolledAt are set: empty ones open a new incident per batch or blank FirstAt
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Find's SQL equality never matches an empty bound value; an empty FailedAt with an empty PolledAt sets FirstAt to empty, so Settle.Wait ends the rule at once
- 2026-10-26T06:56:42Z status=wontfix-theoretical owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=real if FailurePoller sent a batch without those fields; it always sets them (polledAt = NowUtc())

### DW-250: The shard part block of test-ci-config.sh prints only FAIL shard part, not which of its checks failed
- source: spec-5-3-same-cause-failures-become-one-incident-by-the-settle-rule.md | severity: low | fix-risk: low | footprint: in-story
- evidence: About 20 checks feed one part_ok flag; neighbouring blocks name the failed rule
- 2026-10-26T06:56:42Z status=wontfix-accepted owner=5-3-same-cause-failures-become-one-incident-by-the-settle-rule by=cr note=reopen_if=a FAIL shard part takes more than one rerun to find the failing check

### DW-255: The evidence pack's credential-name rule (credentials, password, token, key) misses names such as Secret, Passphrase, Passwd and Auth
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: low | footprint: in-story
- evidence: Reader.cls CredentialName equals the recorded snapshot rule; a setting named ClientSecret reaches the pack and the settings tool, with only the redactor's patterns as a backstop
- 2026-10-26T10:28:11Z status=open owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=harvest note=ruled_veto_U-91:widen_to_secret,passphrase,passwd,auth;code_review_patches_it
- 2026-10-26T12:03:06Z status=resolved-by:5-4-the-diagnosis-explains-the-cause-from-the-failed-messages owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=widened_per_U-91:CREDENTIALPARTS_adds_credential,passwd,passphrase,secret,auth;TestCredentialsLeftOut_mutation_red

### DW-256: Only Cause and FixSummary are in DiagnosisPayload's FILTERED list, so the stored Element and the model's noun forms bypass the reply filter (AD-31: every stored model text is filtered)
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: low | footprint: in-story
- evidence: DiagnosisPayload FILTERED; IncidentManager Answered stores Element (128) and itemNoun one/other, which Story 5.8's notice may render
- 2026-10-26T10:28:11Z status=open owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=harvest note=code_review_patches_it_or_routes_to_5-7(ReplyGuard)
- 2026-10-26T12:03:06Z status=resolved-by:5-4-the-diagnosis-explains-the-cause-from-the-failed-messages owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=AD-31:FILTERED_names_every_model_text(dotted,list);Decide_loop;TestFilterDiagnosis_mutation_red

### DW-257: Message body properties reach the evidence pack in logical form, so a %Date or Boolean property reaches the model as its internal value
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Reader.Current reads each stored datatype property with $Property; the demo's OrderDate is a string; a date-format diagnosis on a %Date field would see a day number; needs a measured LogicalToDisplay while switched
- 2026-10-26T10:28:11Z status=open owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=harvest note=code_review_decides
- 2026-10-26T12:03:06Z status=wontfix-accepted owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=regraded_low:a_stored_%Date_is_valid,format_faults_sit_in_strings;reopen_if=a_diagnosis_misreads_a_%Date_value

### DW-258: The credential removal inside Reader.Evidence is never run against a credential-named setting (EvidencePack.Settings removes the same names again)
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Deleting the loop in Reader.Evidence leaves every test green; a test needs a production item with a Credentials or Password setting in OCUORDERS
- 2026-10-26T10:28:11Z status=open owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=harvest note=code_review_decides
- 2026-10-26T12:03:06Z status=resolved-by:5-4-the-diagnosis-explains-the-cause-from-the-failed-messages owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=QA_TestReaderDropsCredentialSettings;mutation(loop_disabled)_red;lane-a_shards_fresh_green_in_review

### DW-259: Test.Bridge.CodeRules does not check that a watch tool calls only the classes of CALLBACKHELPERS and READERCLASSES; it scans the listed classes only
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: med | footprint: in-story
- evidence: A call to an unlisted class (OcuTalon.Data.Delivery) added to a WatchReads method leaves CodeRules green (demonstrated warm); mechanism from Story 5.1
- 2026-10-26T10:28:11Z status=open owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=harvest note=code_review_decides
- 2026-10-26T12:03:06Z status=resolved-by:5-4-the-diagnosis-explains-the-cause-from-the-failed-messages owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=TestWatchReadsCallOnlyListed(WATCHREADS_scan);mutation(unlisted_call_in_WatchReads)_red

### DW-261: EvidencePack.Sentence repeats FailurePoller's ErrorText.Sentence(Redact.Text(raw)) composition instead of one ErrorText helper that both use
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Rule 2 copy with no stated reason: the spec's Extend-don't-copy note says a second call site moves into one ErrorText helper; Watch/EvidencePack.cls Sentence and Watch/FailurePoller.cls:112
- 2026-10-26T12:03:18Z status=routed owner=burndown by=cr note=in-epic:ErrorText,FailurePoller_are_Story_5.2's(done);add_one_ErrorText_helper_and_use_it_in_both
- 2026-10-26T12:41:18Z owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=spec_gate note=5.8's_fallback_notice_needs_the_same_redacted_first_sentence:unify_FailurePoller's_and_EvidencePack's_Sentence(Redact.Text(raw))_into_one_ErrorText_helper_there
- 2026-10-26T18:52:17Z status=resolved-by:5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=adjudication note=ErrorText.Text(raw)_is_the_one_composition;FailurePoller_and_EvidencePack_use_it(EvidencePack.Sentence_gone);ErrorText.Summary_builds_on_it;NoticeText.TestErrorText+mutation_Text_skips_Redact(8d354fe)

### DW-262: Test.Watch.Diagnose Row and Test.Watch.Evidence Fixture build incident rows that Test.Data.Fixture.Incident already builds
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Rule 2, weak reason: Fixture.Incident registers rows for Fixture.Clean while Case cleans by floor, so reusing it mixes two clean-up regimes
- 2026-10-26T12:03:18Z status=wontfix-accepted owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=reopen_if=a_third_Test.Watch_incident_row_builder_appears_or_Case_adopts_Fixture.Clean

### DW-263: Reader's VALUEMAX cut of a message body value is never exercised by a test
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: low | fix-risk: low | footprint: in-story
- evidence: TestEventLogCapped pins LOGMAX and MAXLOG; no fixture body holds a stored value over 1000 characters (the PartnerOrder fields are short)
- 2026-10-26T12:03:18Z status=wontfix-accepted owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=reopen_if=a_pack_or_tool_result_holds_a_body_value_over_1000_characters

### DW-264: The pack and read_event_log send Ens_Util.Log row ids (logId) to the model, while the Identifiers row lets only Ens header and session ids leave the server
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: low | fix-risk: med | footprint: in-story
- evidence: The spec's pack shape defines logId (EvidencePack LogMessage, EventLog); whether the model provider counts as leaving the server is an interpretation of the row
- 2026-10-26T12:03:18Z status=decision-pending owner=burndown by=cr note=Identifiers_row:does_the_model_provider_count_as_leaving_the_server?if_yes,a_pack-local_log_reference
- 2026-10-26T12:41:18Z status=routed owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=spec_gate note=decided(U5_decision_dependency;spine_Identifiers_row:database_row_ids_never_leave_the_server,and_the_model_provider_is_outside_it):the_pack_and_read_event_log_carry_a_pack-local_log_reference(an_ordinal),never_an_Ens_Util.Log_row_id;Ens_header_and_session_ids_may_stay
- 2026-10-26T18:52:17Z status=resolved-by:5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=adjudication note=pack,read_failed_messages,read_event_log_give_logRef_1..n_and_no_logId;Evidence.TestLogKeys(+cr_logRef_1..n_both_tools)+mutation_LogMessage_gives_logId(8d354fe)

### DW-265: The watch read tools open the failed message's body object, so a watched body class's %OnOpen or property getters run inside AI Hub's callback
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Reader.Current calls $ClassMethod(bodyClass,%OpenId) and $Property, reached from Tools.WatchReads through EvidencePack.Read; AD-6 forbids Python and %AI calls inside a callback
- 2026-10-26T12:03:18Z status=wontfix-theoretical owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=real_when_a_watched_body_class's_%OnOpen_or_a_getter_calls_Python_or_%AI;then_read_stored_values_by_SQL

### DW-266: The pack's body holds only stored datatype properties, so a virtual document (HL7, X12) or a stream body gives the model no field values
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Reader.Current skips collections, object and stream properties by the spec's rule (stored datatype properties through the class dictionary); only the flat Orders body is exercised
- 2026-10-26T12:03:18Z status=by-design owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=spec-bound(Always:_body_is_the_stored_datatype_properties);reopens_by_spec_amendment_for_virtual_docs

### DW-267: An incident keeps no diagnosis outcome when its queued diagnose request is aborted or purged, or when Answered's row save fails
- source: spec-5-4-the-diagnosis-explains-the-cause-from-the-failed-messages.md | severity: low | fix-risk: med | footprint: in-story
- evidence: IncidentManager.Diagnose sets no wait of its own; Decide's TimerSeconds starts only once Decide takes the request; a send to a disabled Decide queues until it is enabled again
- 2026-10-26T12:03:18Z status=wontfix-theoretical owner=5-4-the-diagnosis-explains-the-cause-from-the-failed-messages by=cr note=real_when_an_operator_aborts_or_purges_a_queued_diagnose_request_or_the_row_save_fails;then_a_waiter_timer

### DW-270: Moved from Story 5.8 (U-92, R2): for a usable data-format diagnosis (outcome act, its proposed fix), IncidentManager first sends the with-fix incident notice here, through Epic 5's notice delivery and with Raise: one OcuTalon.Msg.Notification per recipient session of kind incident, the incident notice's catalog key, Slots with the count, the start time as UTC ISO 8601, the item noun as itemNoun {one, other} from the diagnosis, the agent's cause and fix summary as plain sentences without times, plus 7.2's dry-run slots and the first request's ApprovalRef; it sets NoticedAt; and for the recorded date-format snapshot and its mock scenario the notification's slots give 50 orders and the first failure's time, with CI seeing noticed, settling, diagnosing, then the notice, in that order
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Orchestrator ruling U-92 (R2 a): AD-15 needs a valid dry run and Raise for the with-fix variant, AD-32 the ApprovalRef on every incident notice, and incident.withFix's dry-run slots refuse to render before 7.2; Epic 5 stores the data-format diagnosis and leaves the incident unnoticed; 5.8 builds the delivery and a unit-tested with-fix slot builder
- 2026-10-26T13:11:27Z status=routed owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=spec_gate note=moved_criterion(U-92);the_orchestrator_writes_its_bullet_into_7.2_at_Epic_5's_merge
- 2026-10-28T14:17:04Z status=resolved-by:7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=adjudication note=IncidentManager.Proposed/Deliver+Notice.WithFixSlots(7f3a310);pinned_by_Test.Watch.Diagnose.TestDemoDiagnosis(50_orders,slots_count/time/itemNoun/cause/fixSummary+dry-run_slots,ApprovalRef,NoticedAt,stream_noticed,settling,diagnosing,incident_in_order;fresh_pass)+Tell.TestRaisedGetsTheWithFixNotice;mutations_AC1/AC3_red

### DW-271: Moved from Story 5.8 (U-92, R3): Raise appends the new approval request's Ref to the incident's Incident.RequestRefs, so the incident payload's Requests list each of the incident's approval requests with its Ref and State (FromRow opens each ApprovalRequest by Ref, SQL-free for /state under AD-13)
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Orchestrator ruling U-92 (R3): no fix request exists before Epic 7; Story 5.8 adds Incident.RequestRefs and reads it; the writer is the Raise of 7.2
- 2026-10-26T13:11:27Z status=routed owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=spec_gate note=moved_criterion(U-92);the_orchestrator_writes_its_bullet_into_7.2_at_Epic_5's_merge
- 2026-10-28T14:17:04Z status=resolved-by:7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=adjudication note=IncidentManager.Proposed_appends_the_Ref_to_RequestRefs(L625);event_and_/state_list_{ref,state}_via_FromRow;pinned_by_Diagnose.TestDemoDiagnosis(Listed)+Raise.TestRejectChangesNothing(pending->rejected);AC7_mutation_red

### DW-272: Moved from Story 5.8 (U-92, R3): the final FixResult's counts (Total, Resent, Completed, FailedAgain, Skipped, Interrupted, Reason) are stored so that each request in the incident payload's Requests carries its Result, and the page can show each request card's own answered status and result (FR-8, AD-12, AD-15, UX-DR74)
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Orchestrator ruling U-92 (R3): FixRun holds only ApprovalRef, IncidentRef and StartedAt; no table stores a fix run's counts before Epic 7
- 2026-10-26T13:11:27Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=spec_gate note=moved_criterion(U-92);the_orchestrator_writes_its_bullet_into_7.4_at_Epic_5's_merge
- 2026-10-29T13:14:32Z status=resolved-by:7-4-ocutalon-reports-how-many-orders-went-through by=adjudication note=FixRun_stores_Total,Resent,Completed,FailedAgain,Skipped,Interrupted,Reason,EndedAt(c1f5162);Live.Payload.Incident.FromRow_lists_each_request's_result;pinned_by_Test.Fix.{Results,Partial,Runs}+Test.Live.Payloads_entries;mutations_red

### DW-273: Owner answer U-91: the evidence pack's credential-name rule (Watch.Reader CREDENTIALPARTS, case-insensitive substring) also leaves out settings whose name holds bearer or cookie; the list is credential(s), password, token, key, secret, passphrase, passwd, auth, bearer, cookie
- source: inbox U-91 (owner decision 2026-10-26T13:11:36Z#273) | severity: med | fix-risk: low | footprint: in-epic
- evidence: Reader.cls CREDENTIALPARTS = credential,password,passwd,passphrase,secret,token,key,auth (5.4, 61e074e); a setting named SessionCookie or BearerValue reaches the pack and the settings tool
- 2026-10-26T15:31:39Z status=routed owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=spec_gate note=owner_decision U-91 at=2026-10-26T13:11:36Z#273: keep and widen; a false positive only hides a value, a miss sends one to the model
- 2026-10-26T18:52:17Z status=resolved-by:5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=adjudication note=Reader.CREDENTIALPARTS_adds_bearer,cookie(case-insensitive_substring);Evidence.TestCredentialsLeftOut;mutations_lose_cookie(implement)_and_lose_bearer(QA)_red(8d354fe);owner_answer_U-91_applied

### DW-276: The spine's Conventions row 'Incident notice' builds each group line from FailureGroup Count; the spec and Watch.Notice use the group's NoticeCount, settled groups only
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Spine row: '(FailureGroup.Seq, Count, FirstAt, ErrorSummary...)'; spec Always (the slots) and matrix row 'Count moved', and Watch/Notice.cls Groups, use NoticeCount
- 2026-10-26T18:49:28Z status=escalated owner=burndown by=cr note=recommend: the lead amends the row to NoticeCount, groups settled with the notice (Rule 20 light path); code stays
- 2026-10-26T18:52:17Z status=resolved-by:5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=adjudication note=the_lead_corrected_its_own_spine_row(Incident_notice:NoticeCount,groups_settled_with_the_notice)_to_the_spec-gate_decision;the_reviewer's_recommended_fix;no_product_call;code_unchanged

### DW-277: An orphan event-log error with an empty ConfigName gives a FailureGroup with an empty ItemName; Watch.Notice passes it to the groups slot, which the catalog refuses, and the row is noticed
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Reader orphan rows take ConfigName as the item, FailurePoller copies it, Catalog groups types itemName as a non-empty text; Watch.Notice.Groups has no check
- 2026-10-26T18:49:28Z status=wontfix-accepted owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=cr note=reopen_if=a FailureGroup row with ItemName '' is stored, or an *Out render fails: the slot 'itemName' is empty

### DW-278: Live.Payload.Incident evidence.items has one entry per failure group, while AD-12 says failures per item
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Details adds one IncidentEvidenceItem per OfIncident group; Record makes one group per incident, so groups and items coincide before Story 7.2
- 2026-10-26T18:49:28Z status=wontfix-theoretical owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=cr note=real when an incident holds two groups of one item (Story 7.2's later groups): merge the items per item then (AD-12)

### DW-279: Four test classes build FailureGroup fixture rows by hand (Tell.Group, Payloads.Group, Diagnose.Row, NoticeText.Group), each with other fields
- source: spec-5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Rule 2: no shared group fixture; the natural home Test/Data/Fixture.cls is contended while another epic is live
- 2026-10-26T18:49:28Z status=wontfix-accepted owner=5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi by=cr note=reopen_if=a FailureGroup schema change has to edit more than two hand-built fixture groups under Test/

### DW-281: The real Execute order (target FixExecutor, the incident's trace SessionId and the kept SuperSession) is observed only at the test seam (IncidentProbe overrides SendExecute), not on a real message header
- source: spec-5-5-an-incident-moves-through-its-states-and-closes.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: IncidentManager.Execute/SendExecute; Lifecycle.TestExecuteTarget pins the item name only; FixExecutor is a stub until Story 7.3
- 2026-10-26T21:49:47Z status=wontfix-accepted owner=5-5-an-incident-moves-through-its-states-and-closes by=harvest note=reopen_if=Story 7.3's FixExecutor tests pass without observing a real Execute header (target FixExecutor, SessionId = the incident's TraceHeaderId); 7.3 consumes this send
- 2026-10-26T22:32:40Z status=resolved-by:5-5-an-incident-moves-through-its-states-and-closes owner=5-5-an-incident-moves-through-its-states-and-closes by=cr note=Closing.TestApproveSendsExecuteToFixExecutor reads the real header (FixExecutor, TraceHeaderId session, SuperSession)

### DW-282: Test.Watch.Lifecycle's Host, Group and DropGroups repeat Test.Watch.Tell's (a FailureGroup fixture builder now sits in six Watch and Live test classes), a Rule 2 copy with a weak reason
- source: spec-5-5-an-incident-moves-through-its-states-and-closes.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Lifecycle.cls Host/Group/DropGroups vs Tell.cls Host L305, Group L255, DropGroups L271; also Diagnose, Evidence, NoticeText, Live.Payloads; the shared home Test.Data.Fixture is contended
- 2026-10-26T22:32:40Z status=wontfix-accepted owner=5-5-an-incident-moves-through-its-states-and-closes by=cr note=reopen_if=another test class adds its own FailureGroup or probe-host builder; then add Fixture.Group and Host

### DW-288: Owner answer U-102: dismiss_incident stays trusted output on a condition: a Gate test pins the tool's answer to its code-built fields (Refs, states, variants, times, counts, the watch's display name, outcome codes, and messages that are the code's own parameter texts), so a free-text field (diagnosis, error or message text) added later fails that test instead of reaching the model as trusted
- source: inbox U-102 (owner decision 2026-10-27T00:44:42Z#311) | severity: med | fix-risk: low | footprint: in-story
- evidence: Test.Bridge.Gate pins dismiss_incident's classification flags only; nothing fails if WatchAnswers adds a Cause or SampleError key
- 2026-10-27T00:51:30Z status=routed owner=5-9-ask-ocutalon-in-the-chat-to-dismiss-an-incident by=spec_gate note=owner_decision U-102 at=2026-10-27T00:44:42Z#311: keep, trusted output (1), as U-80, with this pinning test
- 2026-10-27T01:28:18Z status=resolved-by:5-9-ask-ocutalon-in-the-chat-to-dismiss-an-incident by=cr note=Gate.TestDismissAnswerIsCodeBuilt; mutations: entry gains cause key -> red, Dismissed message=row Cause -> red

### DW-289: A real HeartbeatIn Tick will run the test fixtures' due check rows and sweep their quiet incidents mid-test once Story 8.1 makes the heartbeat tick
- source: spec-5-6-the-production-watch-runs-on-every-heartbeat.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Test.Checks.Runs makes check rows with NextDueAt empty (due at once) and 16-minute-old incidents, and Test.Checks.Heartbeat drives Checks with its own Ticks; a real Tick in the same minute adds check events, records runs and closes incidents those tests count, so CI flakes
- 2026-10-27T05:15:31Z status=routed owner=8-1-the-heartbeat-ticks-every-minute-and-catches-up-once-after-a by=cr note=8.1 gives tests a way to pause the real heartbeat (like Case's StopPoller) or keeps fixture rows not due for a real Tick
- 2026-10-27T06:48:52Z status=routed owner=burndown by=orchestrator_ruling note=Story_8.1_is_done_on_OCT-epic8:resolve_in_Epic_5%27s_burn-down_in_Test/Checks/**(fixture_rows_a_real_Tick_does_not_find_due,e.g._NextDueAt_in_the_future;quiet-incident_times_a_real_Tick_does_not_sweep);a_remaining_Epic8_pause_hook_stays_routed_burndown_for_the_orchestrator
- 2026-10-27T09:14:43Z occurrence=5-7-asked-whether-everything-is-fine-ocutalon-never-gives-a-fals
- 2026-10-27T10:03:08Z owner=5-10-epic-5-burn-down by=burndown note=chartered_into_the_burn-down_story_5.10(orchestrator_ruling:resolve_in_Test/Checks/**)
- 2026-10-27T13:29:50Z status=resolved-by:5-10-epic-5-burn-down owner=5-10-epic-5-burn-down by=adjudication note=Epic_5%27s_tests_hold_under_a_real_Tick:probe-kind_rows,rows_due_a_day_ahead,2030_quiet_times,own_Ticks_at_NextDueAt,RealTick_interference_runs+controls(d12bacb);residual_in_contended_Test.Core.BridgeSink/Test.Web.Api_filed_as_DW-300(routed_burndown_for_the_orchestrator)

### DW-290: Test.Web.Api's class doc still says a check in a namespace with no trace application carries no traceUrl, which DW-66 made untrue
- source: spec-5-6-the-production-watch-runs-on-every-heartbeat.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Story 2.9's doc clause in Test/Web/Api.cls; Story 5.6 replaced that assertion (L251) with the check's traceUrl into OCUTALON, and ruling Q1 allowed only the three assertion lines in that contended file
- 2026-10-27T05:15:41Z status=escalated owner=burndown by=cr note=LOW; a doc-only replacement for the Lane B story that next edits Test/Web/Api.cls; out of 5.6's Q1 scope
- 2026-10-27T20:43:25Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=merge_gate note=Epic 5 decision sheet (orchestrator, decide): doc-only fix in Epic 16's Test/Web/Api.cls class doc; bullet under 16.4
- 2026-10-29T10:36:25Z status=resolved-by:16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=adjudication note=Test/Web/Api.cls class doc now says a check carries its latest run's traceUrl (Story 5.6), none without a run

### DW-295: On a channel that shows no check rows (Telegram from 0.1.1) the Chat agent is still told OcuTalon shows the check results under its reply and not to repeat them, so 'is everything OK?' gets no status there
- source: spec-5-7-asked-whether-everything-is-fine-ocutalon-never-gives-a-fals.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Agent/Chat.cls's check block and the CheckStatus description say OcuTalon shows the results under the reply; spec 5.7's Never keeps every *Out operation from rendering a check key; AD-28 says the *Out operations render the check sentences; Story 12.6 carries chat replies to Telegram
- 2026-10-27T09:14:54Z status=routed owner=12-6-chat-and-get-notifications-in-the-paired-telegram-chat by=cr note=12.6 renders the reply's check key and rows on Telegram (AD-28, the HostData row's whatFailed rule)
- 2026-10-31T13:34:35Z occurrence=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano
- 2026-11-01T17:23:37Z status=resolved-by:12-6-chat-and-get-notifications-in-the-paired-telegram-chat by=adjudication note=TelegramOut_appends_OcuTalons_own_check_sentence_under_a_reply(mirrors_web_checkSentence/whatFailed;never_an_all-clear_unless_Checks.Render_chose_it),so_the_Chat_agents_shown-under-your-reply_instruction_holds_on_Telegram;Agent/Chat.cls_untouched;pinned_by_TelegramOut.TestCheckSentence(a-j)

### DW-300: Contended tests (Test.Core.BridgeSink: four methods; Test.Web.Api.TestStateSections) make check rows due at once or count stream events, so a real HeartbeatIn Tick (once Epic 8's heartbeat ticks) can run their rows or add check events mid-test: the DW-289 root cause outside Epic 5's footprint
- source: spec-5-10-epic-5-burn-down.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: BridgeSink L292-294,L330,L377,L403 rows due at once and untyped event counts; Web.Api L193/L253 asserts check2 has no run
- 2026-10-27T12:47:05Z status=routed owner=burndown by=harvest note=residual of DW-289 (orchestrator ruling): Epic 5 cannot edit Test/Core (Epic 6) or Test/Web (Epic 16); route to an open Epic 8, 6 or 16 story at merge (rows due a day ahead, or typed event counts)
- 2026-10-27T21:20:07Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=x0 note=Epic_7_X.0_triage:not_in_Lane_A's_files(Test/Core_is_Epic_6's,Test/Web_Epic_16's);16.4_already_owns_Test.Web.Api(DW-290)_and_Epic_16_owns_Core/BridgeSink;residual:the_four_Test.Core.BridgeSink_methods(L286-L403)_and_Test.Web.Api.TestStateSections_make_their_check_rows_due_a_day_ahead_or_count_typed_events_so_a_real_HeartbeatIn_Tick_cannot_interfere;bullet_is_the_orchestrator's_post-merge
- 2026-10-29T01:11:55Z owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=burndown note=Epic 10 burn-down overflow: Test.Core.BridgeSink and Test.Web.Api.TestStateSections are Epic 16's (Core/BridgeSink, Test/Web); Story 16.9 edits BridgeSink's budget.capped path and /state's status, so it seeds those check rows a day ahead or counts typed events
- 2026-10-29T22:51:03Z status=resolved-by:16-9-allowances-cap-messages-model-cost-and-simulated-emails by=adjudication note=delivered:Test.Core.BridgeSinks_four_methods_seed_check_rows_through_Check_Ahead()(asserted_over_23h_out)_and_count_approval_events_only;Test.Web.Api.TestStateSections_the_same_for_check1,check2(20cc3f9+review)
### DW-212: With the online-demo flag off, an install into an instance whose PasswordValidationRoutine names another routine must leave the setting and that routine exactly as they were, and an instance with none stays with none (U-75's condition); Story 3.8's TestForeignGuardIsRefused pins the setting but not that the foreign routine still exists
- source: spec-3-8-the-online-demo-s-settings-password-guard-and-spending-cap-a.md (inbox U-75) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Test/Install/Users.cls TestForeignGuardIsRefused asserts the setting unchanged after the flag-off run (row 12) and row 11 pins no guard; no assertion that ZzForeign still exists after it
- 2026-10-25T17:37:05Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=owner note=U-75 condition (the Contest Planner for the owner): add the routine-still-exists assertion, and prove both cases on this story's IPM install into an existing instance

### DW-231: Story 4.4's feed/break-feed-api.ts (and Story 4.7's guide-marker calls) is a second typed API client beside ApiClient (Stack row: one typed API client), because web/src/app/api/** is Epic 10's footprint
- source: spec-4-4-show-the-demo-guide-and-the-break-the-feed-box.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Spine Stack row Angular L926; veto U-U-84
- 2026-10-26T02:35:44Z status=routed owner=burndown by=spec_gate note=move press() and the marker calls into ApiClient once Epic 10 merges; re-own to an Epic 10 story at the burn-down
- 2026-10-26T02:35:59Z status=routed owner=10-3-the-session-side-of-telegram-is-ready-and-stays-off by=spec_gate note=Rule_2_copy_forced_by_the_footprint_is_routed_to_the_story_that_unifies_it_(never_burndown_for_a_LOW): 10.3 edits web/src/app/api/** (the Telegram block of StateSnapshot); move break-feed-api.ts press() and the guide-marker calls into ApiClient there
- 2026-10-28T23:55:20Z status=resolved-by:10-3-the-session-side-of-telegram-is-ready-and-stays-off by=adjudication note=break-feed-api.ts deleted, ApiClient.breakFeed() used by break-feed-box.ts; the guide-marker call was already ApiClient.postGuideMarker (Story 4.7); web/scripts/api-client-sources.test.mjs pins one HttpClient injector; U-84's condition met before 1.0.0

### DW-232: Story 8.4's acceptance criteria ask for a CI mock scenario keyed by 'Remind me in 1 minute to stretch.' under ci/mock/scenarios/B/, which Story 4.4 adds as guide-reminder.json; the mock loader refuses a repeated prompt (scenarios.mjs), so 8.4 must extend guide-reminder.json rather than add a second scenario
- source: spec-4-4-show-the-demo-guide-and-the-break-the-feed-box.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: epics.md Story 8.4 (about L3074); ci/mock scenarios.mjs:255 duplicate-prompt refusal
- 2026-10-26T02:35:44Z status=routed owner=8-4-set-list-and-cancel-reminders-in-plain-words by=spec_gate note=coordination: extend Epic 4's B scenario
- 2026-10-27T11:25:05Z status=routed owner=8-6-reminders-through-the-chat-on-the-demo-path by=spec_gate note=split_from_8.4(chat_side:mock_scenarios,REL-2_reminder_step,demo-path_spec_03)
- 2026-10-27T20:13:03Z status=resolved-by:8-6-reminders-through-the-chat-on-the-demo-path by=adjudication note=guide-reminder.json (Story 4.4) is unchanged and serves the guide prompt; no second scenario for 'Remind me in 1 minute to stretch.'; the two new B scenarios are marker-selected (reminder-thursday, reminder-cancel-chat); mock tests (94) and live demo-path step 3 pass

### DW-253: flake: docker/tests/test-lib-live.sh check live_first_start 'a failed wait was not reported' failed once in the hosted checks job (first start not ready after 101 s, RC=1), green on an unchanged rerun
- source: cycle-log-epic-4.md (Story 4.4 CI, run 40285090544) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: run 40285090544 job 121446738063 failed, rerun job 121457043804 success on ca4838f; 4.4 touched no lib-live file
- 2026-10-26T09:02:44Z status=routed owner=burndown by=flake note=a timing-sensitive hermetic check; Epics 10 and 13 own docker/tests; re-own at the burn-down
- 2026-10-27T05:26:00Z status=wontfix-accepted by=burndown note=one red in ~10 Epic 4 CI runs (run 40285090544), green on an unchanged rerun and on every later run; outside Epic 4's footprint (docker/tests, Epic 15); reopen_if=test-lib-live.sh live_first_start 'a failed wait was not reported' is red again on any branch's CI

### DW-274: The CDK live announcer's element has no visually-hidden style until a dialog's focus trap loads it, so its last text lies below a framed page and the page scrolls by a line
- source: spec-4-5-get-notifications-on-the-simulated-phone.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 4.5 cr, D2 at 1280x480: div.cdk-live-announcer-element.cdk-visually-hidden is position static at 480-501px, document 501px tall in a 480px window; CDK 22.2.3 LiveAnnouncer loads no visually-hidden style and web/src has no .cdk-visually-hidden rule
- 2026-10-26T16:49:28Z status=routed owner=burndown by=cr note=pre-existing (Story 2.12 announcer); D2 now checks app-root overflow; fix: style .cdk-visually-hidden
- 2026-10-26T16:52:48Z status=routed owner=4-7-finish-the-demo-guide by=adjudication note=in-epic MED routed to the story that adds the finish-state and step announcements on the framed page: style .cdk-visually-hidden so the live announcer never lies below the page (D2 at 1280x480)
- 2026-10-26T18:04:55Z status=open owner=4-5-get-notifications-on-the-simulated-phone by=rework note=pulled into Story 4.5's CI rework 1: the root cause of D2's red on d341d29 (run 40367647349); the 4.7 bullet is removed
- 2026-10-26T19:08:37Z status=resolved-by:4-5-get-notifications-on-the-simulated-phone by=adjudication note=5955043 base.css .cdk-visually-hidden rule from page load; D6 (@browsers) pins it after an announcement lands; mutation red in all three engines

### DW-275: U-72 (owner decision): the terminal command SetDemoMode accepts a caller holding OcuTalonAdmin OR %All; every other caller is refused as now; the web endpoints stay OcuTalonAdmin only; the audit entry still names the person (U-74's ActingUser) and T5 still refuses when the audit entry cannot be written; tests: %All accepted, OcuTalonAdmin accepted, neither refused (AD-19 terminal entry amended)
- source: inbox U-72 at=2026-10-26T03:34:47Z#253 | severity: med | fix-risk: low | footprint: in-epic
- evidence: Contest Planner under the owner's delegation, 2026-10-26: strict check makes the README's documented command fail on a default install (terminal holds only %All)
- 2026-10-26T16:52:48Z status=routed owner=4-6-simulate-incoming-email-in-the-simulated-mailbox by=owner_decision note=deliver before Epic 4's contract; Story 4.1 is done strict (Core/Admin.cls, Test/Core/Admin.cls)
- 2026-10-26T23:18:31Z status=resolved-by:4-6-simulate-incoming-email-in-the-simulated-mailbox by=adjudication note=7d32b66 Core.Admin.Allowed accepts %All or OcuTalonAdmin; Test.Core.Admin %All accepted, OcuTalonAdmin accepted, neither refused; test-demo-switch.sh steps 3,4,7 (irisowner switches, audit names it)

### DW-280: An email's body has no length cap, so one large body or many sends can fill SimMessage and make each Decide call large
- source: spec-4-6-simulate-incoming-email-in-the-simulated-mailbox.md | severity: med | fix-risk: low | footprint: in-story
- evidence: MailBody and SimMailboxIn.Accept cap only from and subject at 1000 characters; SimMessage.Text and Mail.Text unbounded; the textarea has no maxlength (Web/Api.cls:MailBody, Channel/SimMailbox/In.cls:Accept)
- 2026-10-26T21:41:08Z status=open owner=4-6-simulate-incoming-email-in-the-simulated-mailbox by=harvest note=in-story MED for the code review to patch (a body cap is an implementation detail; the hourly allowance is Story 16.9)
- 2026-10-26T23:18:31Z status=resolved-by:4-6-simulate-incoming-email-in-the-simulated-mailbox by=adjudication note=code review: SimMailboxIn.BODYMAX 10000 checked in MailBody (400 bad_email) and Accept, form maxlength; TestIncoming/TestFieldErrors/TestRefused pin it

### DW-283: ApiClient's private accepted<T>() repeats postMessage's 202-only body (Rule 2 copy)
- source: spec-4-6-simulate-incoming-email-in-the-simulated-mailbox.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: web/src/app/api/api-client.ts accepted<T>() (Story 4.6) and postMessage (another epic's lines, shared-by-entry file): the same 8-line 202 check; postMessage cannot be moved onto the helper here
- 2026-10-26T23:16:44Z status=wontfix-accepted owner=4-6-simulate-incoming-email-in-the-simulated-mailbox by=cr note=copy forced by the shared-by-entry rule; reopen_if=a third 202-only POST joins ApiClient or postMessage's success rule changes

### DW-284: Test.Web.MailboxApi's Csp and Post repeat Test.Web.BreakFeedApi's (Rule 2 copy)
- source: spec-4-6-simulate-incoming-email-in-the-simulated-mailbox.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: MailboxApi.cls:191-216 and BreakFeedApi.cls:139-158: the CSP session and stand-in request helpers; BreakFeedApi is an existing file in contended Test/Web/**, so no shared helper can replace its copy
- 2026-10-26T23:16:50Z status=wontfix-accepted owner=4-6-simulate-incoming-email-in-the-simulated-mailbox by=cr note=unification needs a contended file; reopen_if=a third route test class copies Csp/Post
### DW-285: Closing a trace tab frees nothing: its licence unit is held until sign-out or the session timeout, so leaving the page must sign the trace session out (?IRISLogout=end), with the 120-second timeout as the backstop
- source: orchestrator (inbox U-103, Story 4.7 measurement) | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Story 4.7 measurement on a lane-B throwaway, build 154 (DW-146): sign-in takes no licence unit; the first trace page per user and client address takes one; closing frees nothing until sign-out or the session timeout; at 8 units trace pages 503 and iris session terminals are refused; AD-13 and AD-25 amended 2026-10-27 (U-103)
- 2026-10-27T00:47:19Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=orchestrator note=U-103 owner's delegate: route to 16.4
- 2026-10-29T04:27:46Z by=spec_gate note=addressed by 16.4's spec: every leave the page can see (idle cap, epoch change, Sign out) signs the group out at once; a trace tab closed while the page stays open is IRIS's own page, which no OcuTalon code observes, and falls to AD-25's own 120 s backstop (AD-25 Rule: 'with the 120-second timeout as the backstop (Story 16.4)'); the units after that case are measured with DW-286 (29.4)
- 2026-10-29T10:36:25Z status=resolved-by:16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=adjudication note=idle cap, epoch change and Sign out sign the group out at once (Task 0: a sign-out ends the trace CSP session at once); a closed page or trace tab falls to the 120 s timeout on all four applications (Test.Web.Install, live online-session rows 1 and 4; closed jar gone 152-153 s); the AD-25 backstop case is measured with DW-286 (29.4)

### DW-286: Measure the licence units each visitor uses on the demo configuration (sign-in, trace pages, after leaving), so AD-13 and AD-25's online-demo consequences and the P12/NFR-23 numbers rest on a measurement, not an inference
- source: orchestrator (inbox U-103, Story 4.7 measurement) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 4.7 measurement on a lane-B throwaway, build 154 (DW-146): sign-in takes no licence unit; the first trace page per user and client address takes one; closing frees nothing until sign-out or the session timeout; at 8 units trace pages 503 and iris session terminals are refused; AD-13 and AD-25 amended 2026-10-27 (U-103)
- 2026-10-27T00:47:19Z status=routed owner=29-4-sessions-stay-isolated-under-load by=orchestrator note=U-103 owner's delegate: route to 29.4
- 2026-10-29T04:27:46Z occurrence=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=spec_gate note=also measure the units of a trace tab closed while the OcuTalon page stays open (AD-25's backstop case, Story 16.4 spec gate)
- 2026-10-29T10:33:42Z occurrence=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi note=16.4 MEASURED (d): a closed jar's sessions went 152-153 s after its last request; AD-13 says 5-15 s past the 120 s
- 2026-10-30T09:28:01Z status=routed owner=29-7-the-author-s-load-run-measures-the-demo-s-capacity by=spec_gate note=split from 29-4 with the fourth criterion (Rule 5 tier 2, runner C ruling 2026-10-30); 29.4's plan measured it on a lane-C throwaway (Community key): sign-in holds no connection or unit, each open trace application session adds one connection, the unit is keyed by user and TCP peer, leaving frees within about 2 min
- 2026-10-30T16:45:40Z status=routed owner=29-8-the-author-s-load-run-measures-the-demo-s-capacity by=spec_gate note=moved with the author's load criterion to Story 29.8 (runner C split ruling 2026-10-30)
- 2026-10-31T03:30:40Z status=resolved-by:29-8-the-author-s-load-run-measures-the-demo-s-capacity by=adjudication note=measured on lane-C throwaways (Story 29.4 Task 0, Story 29.8 Task 0 and every L2 run of live:online-demo-path): a signed-in visitor holds no connection or licence unit, each open trace application page holds one connection (3 visitors with both trace pages: 3/2, 5/2, 7/2), the unit is keyed by user and TCP peer, leaving frees within about 2 minutes (1/1 after sign-out); release/demo-load.sh records the readings per visitor; the host's own reading is release check H25 (the Contest Planner, before the flip)

### DW-287: At 8 licence units iris session terminals are refused, so the demo host's own admin and reset path must not need a licence unit, or the host must keep one free; the Contest Planner checks it on the demo host at the Epic 16 deploy
- source: orchestrator (inbox U-103, Story 4.7 measurement) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 4.7 measurement on a lane-B throwaway, build 154 (DW-146): sign-in takes no licence unit; the first trace page per user and client address takes one; closing frees nothing until sign-out or the session timeout; at 8 units trace pages 503 and iris session terminals are refused; AD-13 and AD-25 amended 2026-10-27 (U-103)
- 2026-10-27T00:47:19Z status=routed owner=29-3-the-demo-host-is-adapted-for-the-launch by=orchestrator note=U-103 owner's delegate: route to 29.3
- 2026-10-30T08:06:50Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=adjudication note=measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4): one licence unit in use (the deploy terminal), no host command opens an IRIS terminal, the health check uses iris qlist; the script signs out every session its requests open (IRISLogout=end), so a run holds no unit; release check H22 keeps it in the Planner's pass

### DW-296: Reminder.Wake and Start open the row with RefIndexOpen(ref, 4), which waits the process lock timeout ($$$LockTimeout, 10 s) on a busy row inside the single ReminderTimer job
- source: spec-8-3-a-reminder-fires-on-time-on-every-channel.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Persistent %LockId's default timeout is $$$LockTimeout (irislib/%Storage/Persistent.cls:327); a 10 s wait blocks other wakes and starts (pool 1); no product path holds a Reminder row lock in 8.3
- 2026-10-27T10:02:31Z status=wontfix-theoretical owner=8-3-a-reminder-fires-on-time-on-every-channel by=cr note=real if a caller holds a Reminder row lock >=LockTimeout or across a start (8.5 Reconcile): Start ends unarmed

### DW-297: Test.Schedule.ReminderFixture.RemoveSession repeats the per-session header, body and log deletion of Test.Data.Fixture.RemoveMessages (Rule 2 copy, weak reason)
- source: spec-8-3-a-reminder-fires-on-time-on-every-channel.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ReminderFixture.cls RemoveSession vs Fixture.cls:380-399; RemoveMessages works by SuperSession and would delete the rail user's whole trace, so it can't be reused; extending it needs Test/Data/Fixture.cls (contended)
- 2026-10-27T10:02:38Z status=wontfix-accepted owner=8-3-a-reminder-fires-on-time-on-every-channel by=cr note=reopen_if=Fixture.RemoveMessages' per-session deletes change or a 3rd copy appears; fix needs contended Fixture.cls

### DW-303: Demo-path step 3 still declares notBuilt(..., '8.4') in web/e2e/demo-path/03-reminder.spec.ts, so the step summary names Story 8.4 as the story that turns it on after 8.4 is done; the lead's split gave step 3 to Story 8.6
- source: spec-8-4-set-list-and-cancel-reminders-in-plain-words.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: web/e2e/demo-path/03-reminder.spec.ts:4; demo-path-summary.mjs reads the skip text 'Story <id> turns this on'
- 2026-10-27T15:16:12Z status=by-design owner=8-4-set-list-and-cancel-reminders-in-plain-words by=cr note=spec-bound: the split bars 8.4 from the demo-path specs; Story 8.6 replaces this notBuilt call when it turns step 3 on

### DW-304: Test.Schedule.Reminders adds a private Rows(session) Reminder-count helper that repeats Test.Schedule.ReminderLogic's private Rows(session)
- source: spec-8-4-set-list-and-cancel-reminders-in-plain-words.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Reminders.cls:278 and ReminderLogic.cls Rows: the same 3-line COUNT; the two test classes have different bases, as in the other Test areas' own Rows helpers
- 2026-10-27T15:16:12Z status=wontfix-accepted owner=8-4-set-list-and-cancel-reminders-in-plain-words by=cr note=reopen_if=a third copy of the Reminder-rows count appears under Test/Schedule, or the two copies stop counting the same rows

### DW-307: Under the CI mock a prompt-selected B scenario (e.g. guide-reminder.json) also answers the Triage request; Triage has no tools, so a guide-step chat turn's triage decision ends as an invalid fallback in the trace while the turn completes
- source: spec-8-6-reminders-through-the-chat-on-the-demo-path.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: 8.6 plan Task 0 on a warm throwaway: the mock log held 2 Triage requests (no tools, selectedBy prompt, guide-reminder); the triage decision was a fallback 'invalid'; the turn ended done with the scenario reply
- 2026-10-27T17:18:09Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=spec_gate note=CI-mock only (a real model triages normally); the demo path's CI trace shows an invalid triage decision for guide step 2; the fix is in the mock's request routing or scenario shape (ci/mock, contended), so it belongs with the end-to-end demo-path story

### DW-314: live:sign-in runs every web/e2e spec but demo-path in one unit; locally the whole call now takes about 515 s (222 tests) against the 10-minute foreground cap every stage works under (OCUTALON_LIVE_DEADLINE=900 already needed), so the next story that adds browser cases to it cannot run it in one call
- source: spec-8-6-reminders-through-the-chat-on-the-demo-path.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: 8.3: 506 s (219); 8.4: 499-500 s (220); 8.6 implement: 515 s (222); local default deadline 540 s; CI deadline 1200 s (701 s on CI)
- 2026-10-27T19:23:58Z status=escalated owner=burndown by=harvest note=fix is a split of the sign-in unit (docker/tests/test-sign-in.sh, contended) and its group entry (ci/units.sh, Lane B region), or a spec filter for local runs; for the owner/orchestrator at the decision sheet; Epic 8 adds no further browser cases
- 2026-10-28T01:13:02Z status=routed owner=8-7-epic-8-burn-down by=burndown note=owner via Contest Planner: split live sign-in into two ~4-5 min runs (orchestrator ruling: part argument in docker/tests/test-sign-in.sh, split by spec file; CI's browser group runs the whole unit; Rule 21 recipe line)
- 2026-10-28T04:00:48Z status=resolved-by:8-7-epic-8-burn-down by=adjudication note=ci/iris.sh live sign-in --part 1/2 (126 tests, ~307 s) and --part 2/2 (96 tests, ~301 s); whole unit 222 tests 513 s; CI browser group runs the whole unit unchanged; Rule 21 recipe bullet; a short part fails its count guard (9525ac0, 74cf449)

### DW-316: Test.Schedule.ReminderChat.AssertToolSteps is a near-copy of Lane A's private Test.Tools.Reminders.AssertSteps (the step kinds, tool labels, summaries, status and outside-session count), forced by AD-29; the two AgentStep checkers drift when the step shape changes
- source: spec-8-6-reminders-through-the-chat-on-the-demo-path.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls AssertToolSteps vs src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls:928 AssertSteps (about 25 of 35 lines alike); the spec records the reason (Lane A's private method, AD-29); Story 11.1 changes cancel_reminder and that test class
- 2026-10-27T20:11:28Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=cr note=Rule 2 forced copy: make Lane A's step check a public helper (e.g. in RunnerFixture) and have ReminderChat call it

### DW-317: web/e2e/demo-path/03-reminder.spec.ts and web/e2e/reminder/chat.spec.ts each repeat restoreKeys() followed by an irisScript of RunnerFixture.WaitRecords() in their afterAll; the natural home, support/devices.ts restoreKeys, is contended
- source: spec-8-6-reminders-through-the-chat-on-the-demo-path.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: 03-reminder.spec.ts afterAll and chat.spec.ts afterAll: the same 4-line restore-and-wait tail; demo-switch/mailbox.spec.ts restores without the wait
- 2026-10-27T20:11:28Z status=wontfix-accepted owner=8-6-reminders-through-the-chat-on-the-demo-path by=cr note=reopen_if=a third spec repeats restoreKeys plus WaitRecords, or a later sign-in spec fails on keys restored but not yet recorded

### DW-319: No test pins that HeartbeatIn handles a ReminderStart before, and apart from, the heartbeat lock and tick
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: med | footprint: in-story
- evidence: HeartbeatIn.cls:21 puts the branch first; no test re-arms while Heartbeat LOCK is held or checks ticks around Rearm, so moving the line keeps every test green; a pin needs the task suspended and the lock held in a job
- 2026-10-28T00:45:33Z status=wontfix-accepted owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=reopen_if=the ReminderStart branch of HeartbeatIn.OnProcessInput moves, or a re-arm sends a Tick or waits on Heartbeat LOCK

### DW-320: No test drives Install.Step.Schedule.Reconcile into a failed re-arm, so its pass-through of Reconcile's status is unpinned
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Schedule.cls:24 Quit sc; Quit $$$OK there keeps every unit and live test green (the live unit's only negative row is skipped before any re-arm); the declaration takes no only list, so a unit test would re-arm the shared stack's rows
- 2026-10-28T00:45:33Z status=wontfix-accepted owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=reopen_if=Install.Step.Schedule.Reconcile changes its return, or a start ends ready while its log shows a failed re-arm

### DW-321: live:reminder-restart's length grows with the runner (R_future is 6 x restart 1 + 60 s ahead) and nothing checks that it fits the run's deadline
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: low | footprint: in-story
- evidence: test-reminder-restart.sh:263; a deadline death would show as a not-fired or not-ready check; measured 287 to 319 s on the developer machine (deadline 540 s), CI unmeasured (1200 s)
- 2026-10-28T00:45:33Z status=wontfix-accepted owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=reopen_if=a CI run of live:reminder-restart takes over 900 s or ends at OCUTALON_LIVE_DEADLINE

### DW-322: One failed or slow re-arm fails the Reconcile step, so that start writes no ready marker; a start answered after 10 s still makes its waiter
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Install.Step.Schedule.Reconcile returns Reminder.Reconcile's combined status; StartFrom's 10 s no-answer is an error although the queued start still runs later
- 2026-10-28T00:45:33Z status=by-design owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=spec Always (failures combine; the declaration returns them), AD-23 (a failed step stops the ready marker), Design Notes 3

### DW-323: test-production-restart.sh row 20's reminder, now set through ReminderOps, is not removed by Fixture.Clean
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: test-production-restart.sh:130 seeds it with ReminderFixture.Set (Q1); Fixture.Clean removes only Test.Data.Fixture rows; the throwaway project is torn down at exit
- 2026-10-28T00:45:34Z status=wontfix-accepted owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=reopen_if=a check after row 20's clean-up in test-production-restart.sh reads reminders, ReminderTimer or Ens.Alarm

### DW-324: ReminderFixture.Remove ends only the TraceHeaderId waiter, so a row with two live waiters loses the other one with its alarm still pending
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Remove cancels through ReminderOps.EndWaiter (the row's TraceHeaderId session only), waits 10 s, then deletes every ReminderTimer of the Ref; no green test reaches it with two live waiters
- 2026-10-28T00:45:43Z status=wontfix-theoretical owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=real if a test reaches ReminderFixture.Remove with two live waiters of one Ref on a green run

### DW-325: A failed re-arm is logged as a HeartbeatIn error and sets HeartbeatIn's monitor status to Error
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: low | footprint: in-story
- evidence: StartFrom's error returns from HeartbeatIn.OnProcessInput, so Ens.BusinessService.onOutsideErr logs it (irislib/Ens/BusinessService.cls:113-129); nothing in the product reads the monitor status
- 2026-10-28T00:45:43Z status=by-design owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=AD-1 and the spec: the re-arm enters through HeartbeatIn and a failed start is an error; Reconcile skips no-session rows first

### DW-326: A re-arm changes a reminder's trace link with no live event, so an open page keeps the old link until it reloads /state
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Reminder.Reconcile publishes nothing while the new waiter's Start rewrites TraceHeaderId; Web.Api.StateBody carries the new link
- 2026-10-28T00:45:43Z status=by-design owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=spec Always (Reconcile publishes no event), Design Notes 4, AD-33's two reminder publishers; AC 1 asks for the link in /state

### DW-327: Reminder.LiveWaiter treats a failed ReminderTimer read as no waiter, so Reconcile would start a second waiter
- source: spec-8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so.md | severity: low | fix-risk: low | footprint: in-story
- evidence: LiveWaiter ignores result.%SQLCODE < 0 and answers no waiter; a second waiter of a pending row is harmless (AC 4: the later one finds the row fired and sends nothing)
- 2026-10-28T00:45:43Z status=wontfix-theoretical owner=8-5-reminders-survive-restarts-and-upgrades-and-late-ones-say-so by=cr note=real if the ReminderTimer read fails while a waiter lives and the doubled waiter is seen to send a second notification

### DW-334: api.spec's per-test baseline could still see an instance-stream event published between its baseline read and a later read when a publishing spec (heartbeat) ran just before it
- source: spec-8-7-epic-8-burn-down.md | severity: med | fix-risk: low | footprint: in-story
- evidence: web/e2e/api/api.spec.ts:103; StatusMonitor publishes only on a change; the one heartbeat-first run passed 21 of 21; standing runs never put heartbeat before api
- 2026-10-28T02:48:10Z status=open owner=8-7-epic-8-burn-down by=harvest note=unverified (inference); settles with a repeated heartbeat-first run on a fresh stack
- 2026-10-28T03:23:24Z occurrence=8-7-epic-8-burn-down
- 2026-10-28T04:00:48Z status=wontfix-theoretical by=adjudication note=unverified race: StatusMonitor publishes only on a change and no spec before api.spec publishes; with the split api/ runs in part 1 and heartbeat/ in part 2; real if a status-publishing spec ever runs before api.spec in one stack (spec order or part boundary change)

### DW-335: The hosted web job's unit tests run and cut docker/tests/test-sign-in.sh (web/scripts/e2e-part.test.mjs), but WEB_INPUT_PATTERN in ci/units.sh does not declare that script, so a push that changes only it skips them (AD-22 skip rule)
- source: spec-8-7-epic-8-burn-down.md | severity: high | fix-risk: low | footprint: out-of-footprint
- evidence: ci/changes.sh sets web=false unless a changed path matches WEB_INPUT_PATTERN (ci/units.sh:54: web/, ci/, test-web-build.sh and test-mock.sh only); ci.yml's Unit tests step runs npm --prefix web test only when web=true. The browser group runs live:sign-in whole, with no --part, so a broken --part path or a stale cut anchor stays green on a branch push. Fix: add docker/tests/test-sign-in\.sh$ to WEB_INPUT_PATTERN.
- 2026-10-28T03:23:24Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=cr note=AD-22 (Rule 6 high); one alternation in contended ci/units.sh:54 (Epic 6); the orchestrator may apply it at Epic 8's merge
- 2026-10-28T03:58:04Z status=resolved-by:8-7-epic-8-burn-down by=cr note=74cf449 ci/units.sh:54 alternation; e2e-part.test.mjs pin sources ci/units.sh, red on drop, loosen, rename; web=true

### DW-336: Five spec headers (chat/chat, chat/decision, chat/notice, live/live, banners) still say api.spec pins the instance stream's count, and banners.spec.ts says no spec publishes on that stream
- source: spec-8-7-epic-8-burn-down.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Since Story 8.7, api.spec reads the instance stream against each test's own baseline, and heartbeat.spec (Story 8.2) and reminder/chat.spec publish on it. Decided 8 and the spec's Never list keep those five files unedited in this story.
- 2026-10-28T03:23:24Z status=wontfix-accepted owner=8-7-epic-8-burn-down by=cr note=reopen_if=a story edits one of the five files and its header still says api.spec pins the instance stream's count

### DW-338: The comment above WEB_INPUT_PATTERN (ci/units.sh:46-53) lists the web job's inputs but not docker/tests/test-sign-in.sh, which line 54 holds since DW-335
- source: spec-8-7-epic-8-burn-down.md (code review, rework 1) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: The comment names 'the scripts that build the web and run the mock's tests'; test-sign-in.sh, added to the pattern for DW-335, is neither, so the comment no longer states the whole contract (Rule 14). The orchestrator's ruling allowed only the alternation in ci/units.sh, so Story 8.7 cannot edit the comment.
- 2026-10-28T03:58:11Z status=wontfix-accepted owner=8-7-epic-8-burn-down by=cr note=reopen_if=a story edits ci/units.sh:46-54 (the WEB_INPUT_PATTERN comment or pattern): name test-sign-in.sh there
### DW-292: /state's incident entries carry only Live.Payload.Incident.FromRow's row-backed fields (no groups, requests, evidence or traceTargets), so a reloaded or resynced incident card shows no request cards, results, Show details evidence or diagnosis link until the next incident event; /state must build the parts with IncidentManager's builder once Epic 5's tables merge
- source: spec-6-1-show-each-incident-as-one-card-in-the-chat.md (plan deferred 1) | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Live/Payload/Incident.cls FromRow leaves the four parts for the caller; Web/Api.cls ChatItems calls FromRow alone; the parts' data lives in Lane A tables Story 5.4 (Epic 5, unmerged) defines; Story 0.5 decided one builder for events and the snapshot
- 2026-10-27T07:44:45Z status=routed owner=burndown by=harvest note=cross-lane: Lane A builder (Epic 5); re-owned at Epic 6's burn-down to the story that can build it
- 2026-10-27T12:28:21Z occurrence=6-2-approve-or-reject-a-fix-from-the-web-chat note=after a reload an answered request has no request card until its next approval or incident event: /state rail.approvals holds pending requests only (Web/Api.cls RailBody) and the snapshot's incident has no requests part
- 2026-10-28T01:06:08Z occurrence=6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and note=after a reload an answered request has no request card, so its result band never shows on an open card while the chat announces it
- 2026-10-28T02:25:49Z status=escalated owner=burndown by=burndown note=decision_sheet: no remaining Epic 16 story (16.4, 16.9 left on OCT-epic16) builds the snapshot's incident parts (orchestrator ruling 5); the parts need Lane A's builder (Epic 5); recommended: route to Story 11.1 (Epic 11 turns the real path on), /state building the parts with IncidentManager's builder
- 2026-10-28T03:51:21Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=merge_gate note=Epic 6 decision sheet (orchestrator, decide): Lane A's Live.Payload.Incident.FromRow fills groups, requests, evidence and traceTargets for /state, beside DW-271/DW-272; Epic 7 integrates forward before 7.4's plan
- 2026-10-29T13:14:32Z status=resolved-by:7-4-ocutalon-reports-how-many-orders-went-through by=adjudication note=FromRow(Story_5.8)_already_filled_/state's_groups,evidence,traceTargets,requests;7.4_adds_each_request's_result;Test.Fix.Results/Partial_pin_the_whole_/state_entry(Partial.TestCopiesFailAgain:result_and_reason_on_event_and_/state)

### DW-293: Incident.CauseCategory and Incident.Element values are fixed by no contract: the card humanizes a snake_case category (data_format_change -> 'Data format change') and shows Element as published, while the UX evidence line reads 'order date' and eval/orders-date-format records elementAtFault 'OrderDate'
- source: spec-6-1-show-each-incident-as-one-card-in-the-chat.md (plan deferred 2) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Msg.Enum has no cause-category enumeration; eval/orders-date-format/case.json causeCategory data_format_change, elementAtFault OrderDate; EXPERIENCE.md L276 'Data format change · order date'; Story 5.4 (Epic 5) defines DiagnosisPayload
- 2026-10-27T07:44:45Z status=wontfix-accepted owner=6-1-show-each-incident-as-one-card-in-the-chat by=harvest note=reopen_if=a real incident event (Epic 5/11) publishes Element in code form (e.g. OrderDate) or a category the humanizer misreads, so the card's evidence line differs from the UX's reader form

### DW-294: After a page load an incident card's footer never finds its diagnosis decision: the snapshot seeds the store's decisions from the rail, which holds kind-decide decisions only, so the diagnose decision that decisionRef names reaches the store only as a live decision event
- source: spec-6-1-show-each-incident-as-one-card-in-the-chat.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: live-store.ts fromSnapshot takes decisions from snapshot.rail.decisions; Ownership.cls's decisions query keeps Kind = 'decide' (spine Live events: other kinds reach the store, not the rail); an incident's decisionRef is its diagnosis (kind diagnose); floor I1/I7 seed a decide-kind decision, so they pass
- 2026-10-27T08:44:01Z status=escalated owner=burndown by=cr note=needs /state (Web.Api, Epic 16) or Lane A's payload to carry the diagnosis decision, or a spine Live events change; sibling of DW-292
- 2026-10-28T03:51:21Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=merge_gate note=Epic 6 decision sheet (orchestrator, decide): /state or the incident payload carries the incident's diagnose decision and the page store reads it after a reload (both lanes)

### DW-298: Test.Bridge.CodeRules (Lane A) lists the approval classes a tool may not reference (Approval API, ApprovalStartIn, AnswersIn) but not Story 6.2's new AnswerOps item; AnswerOps refuses any sender but AnswersIn at run time, so the static rule is a second line only
- source: spec-6-2-approve-or-reject-a-fix-from-the-web-chat.md (implement deferred 2) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Test/Bridge/CodeRules.cls L68 and L549 name AnswersIn; AnswerOps is new in Story 6.2; AnswerOps checks SourceConfigName (Decided 12, AC14)
- 2026-10-27T12:28:21Z status=wontfix-accepted owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=harvest note=reopen_if=a tool or tool fixture references OcuTalon.Core.AnswerOps, or AnswerOps' sender check is removed

### DW-299: AC3 of Story 6.2 (headline, cause, dry-run count, Approve and Reject in view at 1280x600 without scrolling, UX-DR20) holds only with the demo guide collapsed and no status banner: with the guide open the chat list is 279 px (323 px with no banner) and the card is 466 px to the bottom of Approve, because the guide never reaches DESIGN's 56 px compact form while its Break the feed box (138 px) shows
- source: spec-6-2-approve-or-reject-a-fix-from-the-web-chat.md (implement deferred 3) | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: measured by Story 6.2 implement on a lane-B throwaway: floor A6 passes only after Hide guide and an empty status; the guide lives in web/src/app/guide/** (Epic 16's contended path; built by Epic 4)
- 2026-10-27T12:28:21Z status=routed owner=burndown by=harvest note=cross-epic: the guide's compact height is Epic 16's area; re-owned at Epic 6's burn-down to the story that owns web/src/app/guide, then A6 runs without Hide guide
- 2026-10-27T14:01:37Z occurrence=6-2-approve-or-reject-a-fix-from-the-web-chat by=cr note=cr confirms routed burndown: card order is UX-fixed; only the guide's compact height (web/src/app/guide) fixes it
- 2026-10-28T02:25:49Z status=escalated owner=burndown by=burndown note=decision_sheet: no remaining Epic 16 story (16.4, 16.9 left on OCT-epic16) builds the guide's compact height (orchestrator ruling 5); recommended: a guide-layout fix (the guide reaches DESIGN's 56 px compact form while its Break the feed box shows), routed to Story 11.1's UJ-1 check or a new pool story, then 6.2's A6 runs without Hide guide
- 2026-10-28T03:51:21Z status=routed owner=11-6-a-hands-on-pass-with-real-keys-finds-and-fixes-what-the-test by=merge_gate note=Epic 6 decision sheet (orchestrator, decide): the guide reaches DESIGN's 56 px compact form while Break the feed shows, so 6.2's AC3 holds at 1280x600 with the guide open; then 6.2's A6 runs without Hide guide

### DW-301: Story 6.2's design is missing from the spine: AD-11's Rule and AD-31 still say AnswersIn's job calls Approval.Answer (Veto V1, kept by U-113: AnswerOps' production job calls it), and AD-32's render exceptions do not list the answer endpoint's 409 text (Web.Api renders the answered.* late-press and expired texts through Catalog.Render)
- source: spec-6-2-approve-or-reject-a-fix-from-the-web-chat.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ARCHITECTURE-SPINE.md L323 (AD-11: AnswersIn ... then calls Approval.Answer), L840 (AD-31: the AnswersIn job that calls Approval.Answer), L861 (AD-32: the one exception is TelegramIn); Core/AnswerOps.cls Carry calls Answer; Web/Api.cls L467 calls Catalog.Render; spec validation 0bdd2c6 wrote only the AD-33 row and the REST row
- 2026-10-27T14:01:29Z status=escalated owner=burndown by=cr note=for the orchestrator now (U7 step 2, U14, Rule 20): record V1/U-113 in AD-11 and AD-31, and the 409 render in AD-32; no code change
- 2026-10-27T14:44:01Z status=decision-pending owner=burndown by=orchestrator note=inbox=U-120
- 2026-10-27T14:48:00Z status=resolved-by:6-2-approve-or-reject-a-fix-from-the-web-chat owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=owner note=U-120 applied b185833 (AD-11, AD-31, AD-32 and the two flow lines amended; no code change)

### DW-302: Test.Core.AnswersInWebRoles.CreateUser and Password copy Test.Bridge.WebStatus.CreateUser (Lane A, private) line for line, as the spec's Decided 15 forces; no story unifies the fixture-user helper
- source: spec-6-2-approve-or-reject-a-fix-from-the-web-chat.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Test/Core/AnswersInWebRoles.cls L383-395 against Test/Bridge/WebStatus.cls L469-476 (same Security.Users.Create call and password shape); unifying needs Lane A's class or Epic 16's Test/Data/Fixture
- 2026-10-27T14:01:37Z status=wontfix-accepted owner=6-2-approve-or-reject-a-fix-from-the-web-chat by=cr note=reopen_if=a third copy of the fixture-user helper appears, or WebStatus.CreateUser becomes public (Rule 2, spec-forced copy)

### DW-308: The rail jump's fallback (the request's card is not in the chat, so focus goes to the chat list) has no browser case: changing CHAT_LIST to a wrong selector leaves every case green
- source: spec-6-3-answer-on-the-simulated-phone-and-see-every-answer-everywhere.md (implement deferred) | severity: low | fix-risk: low | footprint: in-story
- evidence: X6 covers the card-present path in both viewports and the no-button row; rail-view.test covers the jump fields only (web/src/app/rail/status-rail.ts jump())
- 2026-10-27T18:05:33Z status=open owner=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=harvest note=LOW two-way door for code review to patch (one live:answers case)
- 2026-10-27T19:02:03Z status=resolved-by:6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=cr note=X6 case: orphan request's row button focuses app-chat-panel > .list; mutation CHAT_LIST broken -> X6 red

### DW-310: NoticesIn.Join is a copy of CommandsIn.Join (AD-26's join rule for in-process services, about 10 lines); the shared home is contended (Core/Commands*.cls, Epic 8; Core/Trace.cls, Epic 10)
- source: spec-6-3-answer-on-the-simulated-phone-and-see-every-answer-everywhere.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Core/NoticesIn.cls Join and Core/CommandsIn.cls Join differ only in the parameter's class; a change to the join rule (DW-74's SessionId restore, an OwnerRef check) must be made twice
- 2026-10-27T19:02:02Z status=routed owner=burndown by=cr note=Rule 2 forced copy: unify both joins in one helper once Core/Commands*.cls or Core/Trace.cls is not contended
- 2026-10-28T02:25:49Z status=wontfix-accepted owner=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=burndown note=reopen_if=AD-26's in-process join rule changes, or a third in-process service copies the join; no next-epic story owns the shared home (Core/Commands*.cls is Epic 8's, Core/Trace.cls Epic 10's) without a contended edit

### DW-311: web/e2e/support/approvals.ts and answers/answers.spec.ts copy floor/approval.spec.ts's private fixture helpers (DAY, today, TOMORROW_AT_1413, refOf, DRY_RUN, incidentOf, raise, inOrder) instead of the floor spec importing them
- source: spec-6-3-answer-on-the-simulated-phone-and-see-every-answer-everywhere.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: about 50 identical lines in floor/approval.spec.ts L40-121; the spec's reason (the floor spec stays unchanged) is about its case budget, not its imports; unifying needs a live floor run
- 2026-10-27T19:02:02Z status=wontfix-accepted owner=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=cr note=reopen_if=a change to DRY_RUN, incidentOf, raise or inOrder has to be made in both support/approvals.ts and floor/approval.spec.ts
- 2026-10-28T01:06:08Z occurrence=6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and note=the copies moved with A2-A10 into web/e2e/cards/approval-card.spec.ts; support/approvals.ts header now says so

### DW-312: docker/tests/test-demo-path-gate.sh's header (L17-19) still says the browser group runs live:demo-path and live:sign-in and exits 0 when both pass; the group has three units
- source: spec-6-3-answer-on-the-simulated-phone-and-see-every-answer-everywhere.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: the header is outside the orchestrator's ruled lines (stub loop, chmod, browser expectations), so this story may not change it
- 2026-10-27T19:02:02Z status=wontfix-accepted owner=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=cr note=reopen_if=grep -n 'exits 0 when both pass' docker/tests/test-demo-path-gate.sh still matches when Epics 13/15 next edit the file

### DW-313: SimPhoneOut's answered edit uses Delivery.FindByApproval's newest phone row, which can be a later non-request row of the same ApprovalRef (a tellnow or reminder carrying it, or an empty-key answered), so the request's message keeps its buttons
- source: spec-6-3-answer-on-the-simulated-phone-and-see-every-answer-everywhere.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Save records the ApprovalRef on every kind's Delivery row while only incident/approval messages keep it; no producer sends a non-request kind with a pending request's ApprovalRef
- 2026-10-27T19:02:03Z status=wontfix-theoretical owner=6-3-answer-on-the-simulated-phone-and-see-every-answer-everywher by=cr note=real when a producer sends tellnow, reminder or result with the ApprovalRef of a still-pending request before its answered

### DW-315: live floor runs 491-527 s of its 540 s local deadline (OCUTALON_LIVE_DEADLINE, counted from the throwaway lock; 1200 s in CI), because Epic 6's floor specs incident.spec.ts (I1-I11) and approval.spec.ts (A1-A10) added about 130 s; move them into the live:answers unit (where 6.3 and 6.4's cases live), keeping their @browsers cases' cross-engine coverage, so floor regains its margin
- source: Story 6.3 smoke (lead) | severity: med | fix-risk: low | footprint: in-epic
- evidence: 6.3 smoke on throwaway e6s3s: live floor 124 passed, 527 s call wall against the 540 s deadline (491 s at 6.2's smoke); docker/tests/test-floor.sh L30-31; the incident and approval specs are Epic 6's own files under web/e2e/floor/
- 2026-10-27T19:44:24Z status=routed owner=6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and by=smoke note=6.4 adds its result and dismiss cases to live:answers too; check the CI shards and browser group times after the move
- 2026-10-28T01:10:14Z status=resolved-by:6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and by=adjudication note=I2-I11 and A2-A10 moved out of live floor (I1 and A1, the @browsers cases, stay there in three engines) into the new unit live:cards (shards group); measured on fresh stacks: floor 342 s, answers 335 s, cards 227 s, each of 540 s

### DW-331: APPROVAL_TEXTS.nounOne/nounOther ('message', 'messages') copy INCIDENT_TEXTS' noun fallback for resultView, with the reason (the view modules import only types) stated nowhere
- source: spec-6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and-dismiss.md | severity: low | fix-risk: low | footprint: in-story
- evidence: web/src/app/approvals/approval-view.ts L52-53 and incidents/incident-view.ts L48-49; one source needs the cards to pass a resolved noun (about 6 files with tests)
- 2026-10-28T01:06:08Z status=wontfix-accepted owner=6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and by=cr note=reopen_if=INCIDENT_TEXTS' noun fallback changes and APPROVAL_TEXTS' copy does not (a band and its headline name different nouns)

### DW-332: docker/tests/test-cards.sh repeats test-answers.sh's start, fixture-user and Playwright steps (about 60 lines), as every browser unit script does; the shared home, lib-live.sh, is Epic 10's contended file
- source: spec-6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and-dismiss.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: test-cards.sh (code review, DW-315 split) modelled on test-answers.sh; test-floor.sh and test-sign-in.sh carry the same steps
- 2026-10-28T01:06:08Z status=wontfix-accepted owner=6-4-close-the-loop-with-results-rejections-expiry-fallbacks-and by=cr note=reopen_if=a change to the browser units' start, fixture-user or redaction steps has to be made in more than two test-*.sh files

### DW-333: flake: live:sign-in rail.spec.ts R1 (open(): main.main not found within 10 s after signIn) went red once in CI and passed on an unchanged rerun
- source: CI run 40616237736 attempt 1, job iris (browser), head 992e99a (Story 6.4) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: R1 is the first case of rail.spec; R2-R19 use the same open() helper and passed in the same run; actions-runner-8; attempt 2 of the same run green
- 2026-10-28T02:25:30Z status=routed owner=burndown by=ci note=flake: first occurrence; the sign-in readiness wait in the rail spec's open() helper
- 2026-10-28T02:25:49Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=burndown note=overflow: the next story on the sign-in path; it waits because the flake sits in rail.spec's shared open() helper (sign-in readiness), outside Epic 6's footprint; if 16.4 does not touch that helper, re-route at the merge gate
- 2026-10-29T14:54:02Z occurrence=7-4-ocutalon-reports-how-many-orders-went-through note=CI_run_40888894726(cece969)_iris(browser):banners.spec.ts_B17_open():main_data-snapshot_loaded_not_found_after_signIn(same_shape);one_rerun_per_the_flake_rule
- 2026-10-29T10:36:25Z status=resolved-by:16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=adjudication note=rail.spec.ts open() waits for the GET /state answer (200) instead of main.main within 10 s; DW-333 mutation (12 s /state delay) recorded in the spec
- 2026-10-30T02:54:15Z occurrence=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=ci note=CI_run_40987940151_attempt_1_(0990fbe),iris_(shards),live:floor,web/e2e/floor/layout.spec.ts_G1_[floor]_chromium:main.main_not_found_within_10_s_after_signIn_(support/floor.ts:138_openFloor);green_on_the_unchanged_rerun
- 2026-10-30T02:54:15Z status=routed owner=burndown by=ci note=residual:the_same_sign-in_readiness_wait_remains_in_web/e2e/support/floor.ts_openFloor(data-snapshot_loaded_within_the_default_10_s);16.4_fixed_only_rail.spec.ts_open()(wait_for_the_GET_/state_200)
- 2026-10-30T02:55:13Z owner=29-4-sessions-stay-isolated-under-load by=burndown note=overflow(Epic_16_burn-down):web/e2e/support/floor.ts_openFloor_waits_the_default_10_s_for_data-snapshot_loaded_after_signIn;wait_for_the_GET_/state_answer_as_rail.spec.ts_open()_does_(16.4);29.4_is_the_next_Lane_B_story_that_signs_visitors_in_under_load
- 2026-10-30T11:57:16Z occurrence=29-4-sessions-stay-isolated-under-load note=harvest: two more online visitors still sign in then wait 10 s for data-snapshot (web/e2e-online/allowance/daily-cap.spec.ts visit() :69, web/e2e-online/allowance/messages.spec.ts open() :50); same root cause, to be fixed with loadedAfter in this story (QA)
- 2026-10-30T13:10:06Z occurrence=29-4-sessions-stay-isolated-under-load by=cr note=cr: loadedAfter now in openSession, busy/demo-account open(), step 1; old wait left in reset, resume, splash, session/*
- 2026-10-30T13:14:02Z status=resolved-by:29-4-sessions-stay-isolated-under-load by=adjudication note=loadedAfter (web/e2e/support/floor.ts) waits for GET /state 200 before data-snapshot; openFloor, banners open() (the rail R1 path), openVisitor, openSession, busy and demo-account open(), step 1 and the allowance visits use it; live:floor, live:sign-in part 1, online-demo, online-allowance, online-session passed. The same old wait remains in the reset, resume, splash and session/* specs (never seen red): accepted, reopen_if=one of those specs goes red with data-snapshot still loading right after a sign-in
- 2026-10-30T20:37:14Z status=routed owner=29-7-demo-busy-counts-the-live-visitors by=lead occurrence=29-6-the-probe-alerts-when-every-turn-falls-back note=reopen_if met: CI run 41116344208 (OCT-epic29 9b7a936b, iris browser, live:demo-path) web/e2e/demo-path/01-page.spec.ts:92 'shows the status rail' failed waiting 10 s for main.main data-snapshot right after signInReadme; same root cause; residual: give the demo-path specs' sign-in (signInReadme) the loadedAfter wait, and the reset/resume/splash/session specs too; routed to Story 29.7 (Epic 29 owns web/e2e/demo-path/**)
- 2026-10-30T23:44:15Z status=resolved-by:29-7-demo-busy-counts-the-live-visitors by=adjudication note=signInReadme and the remaining online sign-ins (demo-path, reset, resume, splash, session) wait through loadedAfter; live demo-path 12 passed and live online-session passed after the change; R9 keeps the plain sign-in by design (it waits only for the resetting view)
- 2026-10-31T00:50:24Z status=routed owner=burndown by=lead occurrence=29-7-demo-busy-counts-the-live-visitors note=reopened: CI run 41149604870 (OCT-epic29 3f5b3cbe, iris browser, live:sign-in) web/e2e/chat/chat.spec.ts C7 open() waited 10 s for main.main data-snapshot after signIn (the same pattern, outside Story 29.7's sign-ins); 1 of 223; residual: every remaining spec that signs in then waits 10 s (chat.spec open() and its siblings) gets loadedAfter
- 2026-10-31T03:39:09Z owner=29-9-epic-29-burn-down by=burndown note=chartered into Story 29.9 (Epic 29 burn-down) at the burn-down gate
- 2026-10-31T06:01:21Z status=resolved-by:29-9-epic-29-burn-down by=adjudication note=every sign-in followed by a 10 s snapshot-derived wait is wrapped in loadedAfter or signInReadmeLoaded: the Code Map's 38 sites in 24 files plus ten frame.spec.ts sites (F3 badge loop, F5, four F6, F7, three F8) found at review; AC1 mutation zz C7 old red with /state held 12 s, C7 green
### DW-291: U-65 and U-107: Story 16.4's sign-out test must exercise the real ReminderOps cancel path that Story 8.4 delivers, not only the recording double
- source: orchestrator (inbox U-107, Epic 8 readiness CONCERNS; U-65) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: epics.md Story 16.4 AC 'until Lane B's Story 8.4 merges, the tests cancel reminders through a ReminderOps test double'; Story 8.4 AC 'turns on the real ReminderOps cancel path in Story 16.4's sign-out test'; 16.4 is backlog on OCT-epic16 (waits on Epic 10)
- 2026-10-27T06:44:53Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=orchestrator note=U-107 condition: tracked on 16.4 before it is planned; whichever of 8.4 and 16.4 merges second turns the real path on
- 2026-10-29T10:36:25Z status=resolved-by:16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=adjudication note=Test.Core.SessionOpsProduction and e2e-online/session/sign-out.spec.ts cancel reminders through the real ReminderOps (ReminderFixture.WaitEnded), no double

### DW-305: flake: the demo guide's computed step in Test.Live.GuideRefresh (TestHookPublishesOnChange, TestEventsBodyServesTheGuide) and e2e/floor/guide.spec.ts (M7, M9) differs in CI after Epic 5 merges into Epic 4's guide: a new session watching Orders sees a step past the expected one
- source: integrate-forward of OCT-epic5 (CI run 40525019781, head 2a287f3) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: CI 40525019781 iris(image) lane-b GuideRefresh 'step 2, step 1 done' and 'step 3 current' failed; iris(shards) live:floor M7 'the page opens at step 3', M9 'step 5 box style'; both green on one unchanged rerun and lane-b green locally
- 2026-10-27T15:51:26Z status=routed owner=burndown by=flake note=(inference) with Epic 5's real FailurePoller and IncidentManager, untagged Orders failures that other tests send become an instance incident that Ownership.NewestIncident shows to any session watching Orders on a local install, so Guide.Compute marks the incident step done; route to the story that next edits Test/Live/GuideRefresh.cls or the floor guide spec (Epic 6 owns Test/Live): clean or isolate instance incidents in those tests
- 2026-10-27T16:20:51Z owner=5-11-the-demo-guide-s-tests-hold-now-that-incidents-are-real by=integrate_forward note=fix-forward_Story_5.11(the_same_floor_cases_red_twice:not_a_flake)
- 2026-10-27T19:23:30Z status=resolved-by:5-11-the-demo-guide-s-tests-hold-now-that-incidents-are-real by=adjudication note=tests that send real failing Orders messages hold the Orders WatchMark 600 s ahead and release it at clean-up (implement 725d9c5 plus QA and review patches); floor unit 99 passed, lane-b shard green both orders
- 2026-10-30T06:11:45Z occurrence=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=lead note=flake(local,warm_stack_after_lane-a):TestHookPublishesOnChange_'step_2,_step_1_done'_red_on_a_warm_lane-b_rerun_after_all_lane-a_classes;fresh_throwaway_passed;status_unchanged

### DW-306: flake: test-production.sh row 21 (an item that cannot start) printed nothing for 'Start(15) with a WatchOps whose OnInit fails' in CI after Epic 5's merge
- source: integrate-forward of OCT-epic5 (CI run 40525019781, head 2a287f3) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: CI 40525019781 iris(production) live:production row 21 wanted 'CHK|start-fails|1|1', got ''; green on one unchanged rerun and locally on the merged tree
- 2026-10-27T15:51:26Z status=routed owner=burndown by=flake note=(inference) the session line timed out or errored while the production stopped and started with the stub WatchOps; route to the story that next edits docker/tests/test-production.sh (Epic 15 owns docker/tests): give row 21 a longer wait or a retry
- 2026-10-27T21:20:07Z status=routed owner=15-3-an-ipm-install-survives-restarts-and-reinstalls-and-every-re by=x0 note=Epic_7_X.0_triage:docker/tests/**_is_Epic_15's(test-production.sh_is_being_edited_by_Epic_8,contended_for_Epic_7);15.3's_restart_tests_are_the_next_planned_docker/tests_owner;residual:give_test-production.sh_row_21('Start(15)_with_a_WatchOps_whose_OnInit_fails')_a_longer_wait_or_one_retry;if_Epic_8_edits_the_file_again_first,the_orchestrator_may_re-route;bullet_is_the_orchestrator's_post-merge
- 2026-10-28T04:48:55Z status=routed owner=15-3-an-ipm-install-survives-restarts-and-reinstalls-and-every-re by=orchestrator note=flake occurrence=2: CI run 40629178094 (iris production, row 21 wanted CHK|start-fails|1|1, got '') on feature dc44a8c, a bookkeeping-only commit whose code head 6151327 passed; rerun --failed; owner as Epic 7's X.0 re-own (15-3)

### DW-309: Test.Data.Fixture.Check rows carry no CreatedAt, so with no WatchMark the FailurePoller starts each reading at its poll time and a batch that lands between two polls is never read: a test that expects its failures to be noticed can pass or fail by timing
- source: spec-5-11-the-demo-guide-s-tests-hold-now-that-incidents-are-real.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Story 5.11 Task 0: a fast local batch fell between two polls and was never read; CI's slower batch was read
- 2026-10-27T18:08:35Z status=wontfix-accepted owner=5-11-the-demo-guide-s-tests-hold-now-that-incidents-are-real by=harvest note=reopen_if=a test that seeds a watch with Test.Data.Fixture.Check and expects its own failures noticed flakes; Test/Data/Fixture.cls is contended (Epic 16): give Check a CreatedAt there

### DW-318: A dry run reads only each failure group's Seen set (the newest 1000 keys, Settle.SEENMAX), so for an incident with more than 1000 failures its affected and resend counts are lower than the incident's Count with nothing in the result saying so
- source: spec-7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Settle.SEENMAX caps FailureGroup.Seen at 1000; RepairResend.DryRun takes targets only from Seen; 7.1 exercises 50 orders, 7.4 measures 500
- 2026-10-28T00:12:03Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=harvest note=7.4 owns scale: make the dry run's count honest past the Seen cap (say how many it could not list, or read the targets another way) and pin it
- 2026-10-28T01:03:01Z occurrence=7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing
- 2026-10-28T21:18:33Z occurrence=7-6-later-failures-in-the-same-incident-get-their-own-dry-run-an
- 2026-10-29T13:14:32Z status=resolved-by:7-4-ocutalon-reports-how-many-orders-went-through by=adjudication note=the_dry_run_counts_failures_Seen_no_longer_lists_as_affected_and_left_out;a_window_Seen_has_cut_is_refused;Test.Fix.DryRun.TestUnlistedFailuresAreCounted(two_groups:9_affected,4_resent,5_left_out)

### DW-328: The spine's dependency rule lists only Watch -> Fix.Kind and Checks -> Fix.Run.Sweep inside the domain layer, while the Fix area (RepairResend, Executor) references Watch.Reader, FailurePoller.Scope, ItemNoun and Transitions
- source: spec-7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: AD-3 makes Watch.Reader the only reader and AD-16 asks for the scope check, so the code is right; ARCHITECTURE-SPINE.md L98 does not name these arrows (Checks already uses the same classes); the spec's spine notes list them for the lead
- 2026-10-28T01:02:38Z status=escalated owner=burndown by=cr note=Rule 20 spine write: add Fix -> Watch.Reader, FailurePoller.Scope, ItemNoun, Transitions to the domain sentence (veto item)
- 2026-10-30T05:18:18Z status=resolved-by:7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing owner=burndown by=merge_gate note=closed at Epic 7's decision sheet: the orchestrator extended the spine's dependency sentence after merge eb313fa (Fix may call Watch.Reader, FailurePoller.Scope, ItemNoun, Transitions, Settle helpers, ErrorText, Notice.NOERRORTEXT, as built); veto U-159

### DW-329: A data_format_change whose sample has no body, or whose values are in a format outside the registered nine, has no valid reply and ends as the fallback invalid
- source: spec-7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing.md | severity: low | fix-risk: low | footprint: in-story
- evidence: DiagnosisPayload requires a registered fixKind for data_format_change and the kind check fails closed without a sample body (AC 2, Always); the fallback notice is Epic 5's safe route
- 2026-10-28T01:03:01Z status=by-design owner=7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing by=cr note=spec-bound: AC 2 and the fail-closed rule; reopens only by a spec amendment (for example more formats, or a fix-less data_format_change)

### DW-330: Test.Fix.DryRun.DropSession repeats the per-session loop of Test.Data.Fixture.RemoveMessages (bodies, headers, Ens_Util.Log) for one OCUTALON session
- source: spec-7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: RemoveMessages works by super session and Test/Data/** is Epic 16's (contended), so a per-session entry point cannot be added here
- 2026-10-28T01:03:01Z status=wontfix-accepted owner=7-1-repair-and-resend-proposes-a-dry-run-that-changes-nothing by=cr note=reopen_if=a third copy of a per-session message clean-up appears under src/ocutalon/cls/OcuTalon/Test, or Fixture gains a per-session entry point

### DW-341: IncidentManager.Proposed leaves a data-format incident unnoticed when its with-fix slots cannot be built or its dry run is not one JSON object
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Proposed quits with one warning and no NoFix after a refused raised move, a DryRun that is not an object, or a WithFixSlots refusal (3 review layers)
- 2026-10-28T14:14:26Z status=by-design owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=matrix row Slots cannot be built keeps 5.8's unnoticed row; raised is never refused when Open; FixExecutor emits JSON

### DW-342: An error thrown between Approval.Raise and the incident's save leaves a pending request that no incident lists
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Proposed's Catch only logs: a returned save error cancels the request (CancelRequest), a thrown one does not; spec residual risk (2)
- 2026-10-28T14:14:26Z status=wontfix-theoretical owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=real if Deliver or Move throws before the save commits; Owns then drops its outcome, nothing executes, it expires

### DW-343: Approval.Validate checks only that a fix request's FixTargets is non-empty, not that it holds ascending comma-separated header ids
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Validate refuses only an empty FixTargets; its one writer, IncidentManager.Proposed, copies FixExecutor's ascending header ids
- 2026-10-28T14:14:26Z status=wontfix-theoretical owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=real once a second producer writes fix rows, or Story 7.3's executor uses FixTargets without parsing each id

### DW-344: The with-fix notice's count (NoticeCount) and its resendCount (the dry run's resend) differ when failures join during the diagnosis
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Notice.WithFixSlots takes count from NoticeCount and resendCount from DryRun.resend, which reads all of Seen, so a burst can read N affected, resend M
- 2026-10-28T14:14:35Z status=by-design owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=Design Notes: count stays NoticeCount; resendCount is the row's, so what is approved is what runs (U-126 holds)

### DW-345: A dry run that FixExecutor never answers leaves its incident unnoticed: no timeout and no sweep
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Propose sends the DryRun with no timer and only OnResponse or OnError move on; residual risk (1) names 7.5's sweep, which covers FixRuns only
- 2026-10-28T14:14:35Z status=wontfix-theoretical owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=real if FixExecutor is disabled or its queue purged mid-ask; errors take OnError, restarts replay; Decide's ask is alike
- 2026-10-28T21:18:33Z occurrence=7-6-later-failures-in-the-same-incident-get-their-own-dry-run-an

### DW-346: After Reconcile re-arms a hold, the answered notification goes out in the re-armed hold's session, not the incident's trace session
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Outcome sends AnswerNotice through Move and Tell in the session the outcome arrives in; Execute switches to TraceHeaderId, the answered notice does not
- 2026-10-28T14:14:35Z status=by-design owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=Design Notes decided-in-stage: answered goes out in the outcome's session; AD-26's Raise-session rule holds

### DW-347: Test.Fix.Raise's OCUORDERS snapshot checks cannot go red until Story 7.3 gives FixExecutor a real Execute
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: low | fix-risk: low | footprint: in-story
- evidence: FixExecutor refuses Execute today, so a wrongly sent Execute leaves OCUORDERS unchanged; the Execute-header count is the live pin, its mutation recorded
- 2026-10-28T14:14:35Z status=wontfix-accepted owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=reopen_if=Story 7.3's Verification has no mutation line turning Test.Fix.Raise OCUORDERS did not change red

### DW-348: Test.Watch.Diagnose.TestDemoDiagnosis counts every POST /v1/messages in the stack's mock log since its mark, not only this incident's
- source: spec-7-2-the-incident-notice-carries-the-dry-run-and-one-approval-request.md | severity: low | fix-risk: low | footprint: in-story
- evidence: ModelRequests counts all POSTs after LogMark; the spec's pin is exactly 2 (the dry run calls no model); Decide's callers are Conversation, Intake, IncidentManager
- 2026-10-28T14:14:35Z status=wontfix-theoretical owner=7-2-the-incident-notice-carries-the-dry-run-and-one-approval-req by=cr note=real if a class leaves a turn or diagnosis in flight past its teardown, or a model caller runs on a schedule
### DW-337: CI's shards group took 31 min 52 s on Epic 6's head bed6d27, close to REL-4's 35 minutes: Epic 5's lane-a shard grew to 70 classes and Story 6.4 added live:cards (about 230 s locally) to the group
- source: orchestrator: Epic 6 merge gate (bed6d27, runs 40625489943, 40625489987) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ci.yml group times on bed6d27: shards 31m52s, browser 23m05s, image 21m32s, install-fresh 14m02s, install-upgrade 12m58s, production 9m20s; production and browser are pinned by test-ci-changes.sh and the demo-path gate
- 2026-10-28T03:51:21Z status=routed owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=merge_gate note=first change in 9.1: move live:cards to an unpinned shorter group (install-fresh or install-upgrade), measured on CI, with any pin in test-ci-config.sh updated; test infrastructure only
- 2026-10-28T03:54:34Z status=routed owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=orchestrator note=owner via Contest Planner: TRIGGER - if any head's iris (shards) job runs longer than 36 min before Epic 9 merges, pull this forward as a fix-forward in the epic whose head did it (move live:cards to the shorter of install-fresh and install-upgrade, measured); the iris job's hard limit is timeout-minutes 40 (ci.yml:89)
- 2026-10-28T16:28:18Z status=resolved-by:9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=adjudication note=98f69be moved live:cards from shards to install-upgrade (ci/units.sh); CI run 40688986518 on 98f69be: shards 26m23s (was 32m36s-34m15s), install-upgrade 18m27s, longest job 26m23s; test-ci-config.sh and test-ci-changes.sh pass; Rule 21 measured record appended (skill-rules.md, Groups from DW-337)
- 2026-10-30T05:57:04Z occurrence=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got note=moved_from_DW-357(one-digit_misfile_2026-10-29): Epic 7's head 0c01aee shards job cut off at the 40-minute job limit; fix-forward 3308237 by owner decision dw337_shards_split (shards = lane-a@Checks,Install,Watch + live:floor; shards-2 = lane-a@rest; live:cards to install-fresh), merged with Epic 7 (eb313fa); status stays resolved

### DW-350: Test.Core.RoutingProduction's TestEvalItemWritesNoDeliveryOrEvent docstring still says the stub EvalSink answers an error status; since 9.1 EvalSink finds no sent row for that Item, logs a warning, stores nothing and answers OK
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Lane B test passed unchanged in 9.1's lane-b shard run (64 classes); only the docstring sentence is stale
- 2026-10-28T15:22:57Z status=open owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=harvest note=one-sentence docstring fix: Test/Core/RoutingProduction.cls is no contended epic's path, so 9.1's code review patches it as a reported footprint extension
- 2026-10-28T16:28:18Z status=resolved-by:9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=adjudication note=9.1 code review corrected the one stale docstring sentence of Test.Core.RoutingProduction TestEvalItemWritesNoDeliveryOrEvent (lead-authorized footprint extension; no other change to the file)

### DW-351: Spine lint reports ok:false with 8 low 'possible unfilled template token' findings (lines 402, 847, 860, 923, 927), so 9.1's task 11 expectation of ok:true cannot hold
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: same 8 findings on the spine at HEAD and after 9.1's Tables-line edit; they are prose format examples ({time}, {day}, {what happened}, {reason}, {entry}, {finding}, {n}), not template tokens
- 2026-10-28T15:22:57Z status=by-design owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=harvest note=known baseline (Epic 9 start: lint=baseline 8 low placeholder, no AD findings; line 923's HostData row, U-120); the gate for a spine write is no new finding and no ad_id/ad_fields finding

### DW-352: 9.1's task 11 memlog entry (AD-33: OcuTalon.Eval.Data.CaseResult is Lane A's) was not appended: the spine's .memlog.md is gitignored and exists only in the main checkout
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: .gitignore:48 ignores .memlog.md; memlog.py append in the worktree raised FileNotFoundError and wrote nothing
- 2026-10-28T15:22:57Z status=by-design owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=harvest note=runner precedent memlog=absent (27 runner entries): the spine text itself is the durable record of the Tables-line change

### DW-353: EvalSink completes a case row only by the ItemDecision's ItemId, but an evaluation incident's ItemDecision carries the incident's Ref as ItemId (AD-30), which EvalIn cannot know when it opens the row
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Eval/Sink.cls:49 takes CaseResult.Pending(request.ItemId); AD-30 (spine :833) and Story 9.6's first AC send the incident's Ref as ItemId; 9.1's Design Notes (Consumed-by) give the RunRef+SourceItemId match to 9.6
- 2026-10-28T16:25:04Z status=routed owner=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=cr note=9.6 opens incident rows and matches by RunRef+SourceItemId (with an index); its AC3 'each completes' needs it
- 2026-10-30T11:00:24Z status=resolved-by:9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=adjudication note=by construction (lead ruling, decide): EvalIn mints the incident case's IncidentRef (Bridge.Ids.NewRef) and opens the CaseResult row with it as ItemId before the send; IncidentManager's eval branch sends EvalSink the ItemDecision with that Ref, and the existing Pending(ItemId) match completes it; pinned by Test.Eval.Run TestIncidentPath (row decided in the real production; mutation ItemId=SourceItemId leaves it sent) and Test.Eval.In (row opened with the minted Ref, removed on a failed dispatch); commit c1a5d02

### DW-354: Nothing pins live:cards to the install-upgrade group (DW-337, 98f69be): moving it back to shards leaves test-ci-config.sh and test-ci-changes.sh green
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: QA's 'Pinned by nothing' note in the spec's Verification; a pin is a new test-ci-config.sh rule under docker/tests, outside Epic 9's footprint
- 2026-10-28T16:25:04Z status=wontfix-accepted owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=cr note=reopen_if=a full CI run's iris (shards) job passes 30 min, or ci/units.sh lists live:cards under shards

### DW-355: No check reads the spine's Tables line, so a new persistent class that it does not name (AD-33's same-change rule) passes every test
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: QA's 'Pinned by nothing' note; OcuTalon.Eval.Data.CaseResult is named at ARCHITECTURE-SPINE.md:1098; a check would be new test infrastructure under docker/tests
- 2026-10-28T16:25:04Z status=wontfix-accepted owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=cr note=reopen_if=a review or retro finds a persistent class under src/ that the spine's Tables line does not name

### DW-356: AD-22's as-built text lags 9.1: its shard list gives lane-a as Agent, Bridge, Install, Tools and Digest (Checks, Watch and now Eval run there), and its case.json shape is the incident one only
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ARCHITECTURE-SPINE.md:607 vs ci/units.sh's lane-a line; 9.1's item/injection case.json shape is only in Eval/In.cls and the spec's Design Note 3; an AD text edit is the lead's (Rule 20)
- 2026-10-28T16:25:04Z status=wontfix-accepted owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=cr note=reopen_if=a later Epic 9 story writes a case.json EvalIn refuses (Test.Eval.Cases red); lead may fix it under Rule 20

### DW-357: Small Test.Eval helpers are copied between classes: Table's NewRun and RowOf repeat Sink's, Run.Kind repeats In.KindReason, and Table.Count, In.Rows, Sink.CountRows and Switch.Rows run one COUNT query
- source: spec-9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Test/Eval/Table.cls:175-189 vs Test/Eval/Sink.cls:395-465; Run.cls Kind vs In.cls:239 KindReason; a shared TestCase base would be a shard class with no test (Rule 2: weak reason, LOW)
- 2026-10-28T16:25:04Z status=wontfix-accepted owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=cr note=reopen_if=a CaseResult row-API change needs the same edit in three or more Test.Eval classes
- 2026-10-29T16:17:08Z occurrence=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got note=Epic_7's_integrate-forward_head_0c01aee:shards_group_2385s(lane-a_87_classes_1466s,floor_576s,cards_342s);all_units_passed_but_the_40-minute_job_timeout_cancelled_the_job_at_wrap-up(run_40903071771);rerun_requested
- 2026-10-29T21:57:23Z status=routed owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=runner note=occurrence=7-5 fix-forward on OCT-epic7 (3308237): live:cards to install-upgrade (identical to 98f69be) plus the owner decision dw337_shards_split: shard:lane-a in two pieces, shards (Checks,Install,Watch + live:floor) and the new group shards-2 (the rest); 98b95f2's shards job was cut off at the 40-minute limit inside live:cards (lane-a 1594s, floor 559s)
- 2026-10-30T05:57:04Z status=wontfix-accepted owner=9-1-evaluation-cases-run-through-the-product-path-and-reach-nobo by=adjudication note=restored_after_misfile: the 2026-10-29 occurrence and routed lines (Epic 7's shards fix-forward 3308237) describe DW-337 (shards group time), not this entry; copied to DW-337; reopen_if=a CaseResult row-API change needs the same edit in three or more Test.Eval classes

### DW-365: A later request reuses the first diagnosis's fixSummary, so a count the model writes into it (the UX fixture's 'repair and resend all 50') would contradict the later round's own count and resend
- source: spec-7-6-later-failures-in-the-same-incident-get-their-own-dry-run-and-approval-request.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Proposed (later) builds its slots with Notice.WithFixSlots(incident, ...), whose fixSummary is Incident.FixSummary; Agent/Diagnosis.cls does not forbid a count; the UX fixtures in Test.Msg.Catalog put counts in it
- 2026-10-28T21:18:33Z status=decision-pending owner=burndown by=cr note=human=run a live diagnosis to see if fixSummary names a count; then choose a count-free prompt rule or other later text
- 2026-10-30T05:17:59Z status=routed owner=11-6-a-hands-on-pass-with-real-keys-finds-and-fixes-what-the-test by=merge_gate note=the Contest Planner's hands-on pass with a real key checks whether a live diagnosis writes a count into fixSummary; if it can, a count-free rule in the diagnosis prompt or count-free later-request text (decide)

### DW-366: The spine's Conventions row 'Later requests' does not say that stragglers of the first ask start a round after its raise, or that a failed later round's failures rejoin the next round's window
- source: spec-7-6-later-failures-in-the-same-incident-get-their-own-dry-run-and-approval-request.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: IncidentManager.Record sets LaterSince on an unnoticed incident whose group has an AskedTo, and Unask with unmark puts the marks back on the error routes (7.6 review); the row names only incidents awaiting approval, fixing or resolved
- 2026-10-28T21:18:33Z status=wontfix-accepted owner=7-6-later-failures-in-the-same-incident-get-their-own-dry-run-an by=cr note=reopen_if=a later plan or review reads the Later requests row as covering only awaiting, fixing and resolved incidents
- 2026-10-28T21:20:52Z status=resolved-by:7-6-later-failures-in-the-same-incident-get-their-own-dry-run-an by=adjudication note=spine_Conventions_row_Later_requests_now_names_the_first_ask's_stragglers_and_the_error-path_mark_restore([AMENDED_2026-10-28,Story_7.6_code_review,DW-366])

### DW-368: A stopped target production renders as 'had changed since the dry run': AD-16 counts each copy a stopped production refuses as Skipped, and the Result texts convention then picks result.skipped, whose text claims the orders changed since the dry run (a false claim in an edge case)
- source: spec-7-3-approved-repairs-are-re-checked-and-resent.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 7.3 spec Design Notes V4; Runs.TestStoppedProductionSkipsEveryCopy pins the Skipped counts; the result key choice is the Result texts convention's (Stories 7.3, 7.4, 7.5, 30.5)
- 2026-10-28T22:37:53Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=spec_gate note=7.4 owns the result texts (E > Incidents and Approvals > Results): give a stopped production an honest result (its plain reason, or a key of its own); new wording is a veto-window public-text item at 7.4's spec gate
- 2026-10-29T05:56:54Z status=escalated owner=burndown by=spec_gate note=an_honest_stopped-production_result_needs_an_AD-16_amendment(a_production_not_running_at_the_run's_start_ends_it_as_couldn't_start,Skipped_0)_or_a_new_result_key_with_a_Result_texts_row_and_the_page's_key_selection(web/src/app/approvals/approval-view.ts);AD-16_is_cited_by_done_specs(U7(c):a_re-architecture,the_owner's);recommended:amend_AD-16,then_a_small_fix_story(Epic_11_X.0_or_30.x)
- 2026-10-29T13:12:01Z occurrence=7-4-ocutalon-reports-how-many-orders-went-through by=cr note=also a resend that errs partway: its unreached targets count as Skipped and render as changed since the dry run
- 2026-10-30T05:17:59Z status=decision-pending owner=burndown by=unattended note=inbox=U-160
- 2026-10-30T05:24:59Z status=routed owner=30-4-a-stopped-production-or-a-disabled-item-is-reported-once by=merge_gate note=owner U-160 (a) via the Contest Planner: AD-16 amended after Epic 7's merge; a target production not running at the run's start ends the run as couldn't start (Resent 0, Skipped 0, plain reason, row failed); the errs-partway case split to its own entry for 30.5; the result text never claims a change that did not happen

### DW-379: The retention purge of closed incidents (IncidentManager.PurgeOne) does not delete the incident's FixRun rows, which Story 7.3 is the first to write
- source: _bmad-output/implementation-artifacts/spec-7-3-approved-repairs-are-re-checked-and-resent.md | severity: med | fix-risk: low | footprint: in-story
- evidence: PurgeOne deletes the FailureGroup rows and the incident in one transaction and nothing else; Fix.Executor saves one FixRun per approved request; after a purge those rows name a deleted incident (IncidentManager.cls:1254)
- 2026-10-29T02:28:32Z status=open owner=7-3-approved-repairs-are-re-checked-and-resent by=harvest note=AD-27 retains incidents for DaysToKeep (Lane A's Purge): a FixRun row is the incident's own record, so following its incident is compliance (decide), not a retention change; one more delete in PurgeOne and an assertion in Test.Watch.Lifecycle.TestPurge (code review patches it)
- 2026-10-29T04:19:48Z status=resolved-by:7-3-approved-repairs-are-re-checked-and-resent by=adjudication note=IncidentManager.PurgeOne_deletes_the_incident's_FixRun_rows_in_the_same_transaction(7.3_code_review);Test.Watch.Lifecycle.TestPurge:two_runs_go_with_the_old_incident,one_stays_with_the_young;mutation(drop_the_delete)->TestPurge_red

### DW-380: An approved request whose ExpiresAt passes before FixExecutor takes its Execute, or whose StartExecution fails, is refused with an info line only, so it stays approved and its incident stays fixing with no result
- source: spec-7-3-approved-repairs-are-re-checked-and-resent.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Executor.Refusal refuses an approved row past ExpiresAt and Execute only logs a StartExecution error: no FinishExecution, no FixResult; Approval.Expire moves only pending rows
- 2026-10-29T04:15:16Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=cr note=reachable once 7.4's wait holds a later request's Execute; end it as couldn't start; new reason text is veto-window
- 2026-10-29T05:56:54Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=spec_gate note=7.4_addresses_the_StartExecution-failure_half(AC_11,NOSTART);the_past-expiry_half_split_to_DW-384(escalated)
- 2026-10-29T13:14:32Z status=resolved-by:7-4-ocutalon-reports-how-many-orders-went-through by=adjudication note=StartExecution_half:an_approved_unexpired_request_whose_StartExecution_fails_ends_as_couldn't_start_with_NOSTART('OcuTalon_couldn't_start_the_resend');Test.Fix.Executor.TestStartExecutionFailsForAnApprovedRequest(+moved-row_cases);the_past-expiry_half_is_DW-384(escalated)

### DW-381: FixExecutor (PoolSize 1) also answers every incident's dry-run ask, so a 60-second copy wait run in its job would hold other incidents' notices past AD-15's 35-second notice
- source: spec-7-3-approved-repairs-are-re-checked-and-resent.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Production.cls gives FixExecutor PoolSize 1; IncidentManager's notice waits on its DryRun ask to FixExecutor; 7.3's Run ends after registration in that job, where 7.4's wait would go
- 2026-10-29T04:15:22Z status=routed owner=7-4-ocutalon-reports-how-many-orders-went-through by=cr note=7.4 plans where its 60 s wait runs so the dry-run ask never waits behind it, or shows the notice still holds 35 s
- 2026-10-29T13:14:32Z status=resolved-by:7-4-ocutalon-reports-how-many-orders-went-through by=adjudication note=FixExecutor_PoolSize_2_with_one_waiter_under_WAITLOCK(veto_U-147);Test.Fix.Waits.TestDryRunAnsweredDuringAWait(dry_run_answered_in_0.01s_while_a_run_waits;PoolSize_1_mutation_red)

### DW-384: An approved request whose ExpiresAt has passed when FixExecutor takes its Execute is refused with an info line only (AD-16's refused list read as covering it), so it stays approved and its incident stays fixing with no result
- source: spec-7-4-ocutalon-reports-how-many-orders-went-through.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: split from DW-380 at 7.4's spec gate: 7.4 ends the StartExecution-failure half (NOSTART, AC 11); the past-expiry half needs AD-16's refused-Execute list amended
- 2026-10-29T05:56:54Z status=escalated owner=burndown by=spec_gate note=recommended: amend AD-16 so that an approved row past its ExpiresAt ends as couldn't start with NOSTART ('OcuTalon couldn't start the resend'), one line in Executor.Refusal; AD-16 is cited by done specs (U7(c): the owner's)
- 2026-10-30T05:17:59Z status=decision-pending owner=burndown by=unattended note=inbox=U-161
- 2026-10-30T05:24:59Z status=routed owner=30-5-mixed-and-unfinished-resends-say-how-far-they-got by=merge_gate note=owner U-161 (a) via the Contest Planner: AD-16 amended after Epic 7's merge; an approved Execute past its ExpiresAt ends as couldn't start with NOSTART (OcuTalon couldn't start the resend), one line in Executor.Refusal, and its incident leaves fixing with that result

### DW-395: A FixExecutor waiter that stops on a quiesce or terminate request while the production keeps running (the item restarted or its settings changed, or a stop that timed out) leaves every run still in its 60-second wait executing and its incident fixing, with no result, because no job calls Wait again until another run resends copies
- source: spec-7-4-ocutalon-reports-how-many-orders-went-through.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: Fix.Executor.Wait quits on Ens.Job ShouldBeQuiescent/ShouldTerminate and only Run calls it; AD-16's Sweep (7.5) ends runs reported in progress (30.5) or marked interrupted by Reconcile at a start, neither of which covers these; 7.4 spec Residual risks names it for 7.5's Sweep
- 2026-10-29T13:11:51Z status=routed owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=cr note=7.5's Sweep or Reconcile must also end runs whose waiter stopped while IRIS kept running (no restart); fix-risk med
- 2026-10-29T23:21:03Z status=resolved-by:7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=adjudication note=delivered: Fix.Run.Sweep (called on every Checks Tick through FixRunSweep in Checks.Process) ends a run the stopped waiter left once its wait is over and every copy was done inside it (EndLeft, veto U-153), and reports a Reconcile-marked run once; pinned by Test.Fix.Executor TestSweepEndsARunNoWaiterEnded, TestSweepDecidesByTheLatestCopyTime, TestSweepLeavesRunsOfTheWaiterAndOfStory305, TestSweepSkipsALockedRun (bf8716e + QA + review patches); CI 40961979510 Test.Fix.Executor passed
### DW-339: A local ci/iris.sh live unit serves a stale web bundle after a merge that brings web/ changes: lib-live.sh ensure_web_bundle rebuilds src/ocutalon/csp only when it is missing and never compares it with web/src
- source: spec-8-6-reminders-through-the-chat-on-the-demo-path.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: 8.6 rework 2: lane-C bundle main-ZNXMCDT7.js predated Epic 6's cards (0 app-incident-card); live demo-path STEP 4/5 red until ci/iris.sh build, then green with no code change; CI builds fresh per job
- 2026-10-28T14:02:09Z status=wontfix-accepted owner=8-6-reminders-through-the-chat-on-the-demo-path by=harvest note=reopen_if=a local live unit fails on a stale bundle again although the Rule 21 rebuild step (ci/iris.sh build after every merge bringing web/ changes, added 2026-10-28) was followed; a source-stamp guard in lib-live.sh is the fix then

### DW-340: 03-reminder.spec.ts clicks 'Step 2, Reminder, upcoming', a name that exists only while guide step 1 (watching) is undone; once Story 11.1 makes 02's background check real, step 2 is 'current' at 03 and the click finds nothing
- source: spec-8-6-reminders-through-the-chat-on-the-demo-path.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Demo/Guide.cls takes the first undone step as current and step 1 as done once the session has an Orders check row; guide-view.ts names it 'current'; today 02 is notBuilt (read from code, not run with a real 02)
- 2026-10-28T14:02:09Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=harvest note=fix: accept either name for step 2 (upcoming|current) and keep the 'Step 2, Reminder, done' assertion; 11.1's own demo-path run shows it first
- 2026-10-28T14:12:56Z occurrence=8-6-reminders-through-the-chat-on-the-demo-path by=cr note=also:_11.1's_step-4_check_'the_reminder_lands_in_the_chat_and_on_the_phone_during_the_wait'_needs_03's_afterAll_cancel_(ReminderFixture.CancelPending)_dropped_or_moved;_today_the_hand-off_is_written_only_in_spec-8-6

### DW-349: Specs that seed a production check row with no NextDueAt can have it run by a real heartbeat tick since Story 5.6 (the minute task, or a fixture calling HeartbeatTask), which overwrites its last run, result and finding: a Last-run assertion can flake
- source: spec-8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Checks.Process.Due runs rows with empty NextDueAt; 8.2 H1 red on merged tree af61733 (run 40692572200) for this reason, fixed with seedCheck nextDueAt (8be27b7). Unfixed seeds: answers/close-loop, banners, floor/focus, floor/guide, rail, trace/links, support/floor.ts, session/session.spec.ts:68,303, demo-path/04-incident.spec.ts:61
- 2026-10-28T14:50:28Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=harvest note=fix: seed fixture check rows not due (seedCheck nextDueAt, e.g. now+1h; or default it in seedCheck/Fixture.Check) unless a case wants the real watch to run them; 11.1 turns the real watch on for the demo path, so the interplay is its concern; re-own at its plan if another story fits better
- 2026-10-28T15:00:54Z occurrence=8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat
- 2026-10-28T15:47:49Z occurrence=8-2-the-heartbeat-stalled-warning-comes-from-the-real-heartbeat by=lead note=flake:OcuTalon.Test.Live.GuideRefresh.TestHeldLock('the_counter_moved')_red_once_in_CI_run_40713989310_(image_group,shard_lane-b,2f4daf2):_Fixture.Check_seeds_its_OCUORDERS_check_with_no_NextDueAt,_so_a_real_minute_tick's_Checks_run_published_a_check_event_on_the_session_between_Publish_and_LastSeq;_IRIS_unit_tests_seeding_Fixture.Check_share_DW-349's_root_cause;_passed_locally_fwd+rev
- 2026-10-28T20:31:18Z occurrence=9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si
- 2026-10-29T01:47:57Z occurrence=10-3-the-session-side-of-telegram-is-ready-and-stays-off by=lead note=flake: web/e2e/banners/banners.spec.ts B2 'before the stall the check reads Last run 15:30' got 'Last run 6:54 · No read access to its namespace' (a real heartbeat tick ran the seeded check row) in CI run 40799281663 attempt 1, iris (browser), live:sign-in, on 5076f54 (Epic 10's final integrate-forward; code identical to ecee507, where browser passed); one rerun
- 2026-10-29T12:16:33Z occurrence=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=ci note=CI run 40866408272 (0af9742), live:floor focus.spec.ts P4: the seeded check row was run by a real tick ('No read access to its namespace') before the republish assertion
- 2026-10-29T21:42:13Z occurrence=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=ci note=status_unchanged:routed_owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test;CI_run_40945229992_attempt_1_(ba6856d,16.9s_implement_20cc3f9),iris_(browser),web/e2e/banners/banners.spec.ts_B2_got_'Last_run_tomorrow_at_1:40_·_No_read_access_to_its_namespace'(a_real_heartbeat_tick_ran_the_seeded_check_row);B2_untouched_by_16.9;attempt_2_green
- 2026-10-30T00:24:16Z occurrence=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=ci note=status_unchanged:routed_owner=11-1;CI_run_40975637263_attempt_1_(75d731a),iris_(browser),live:sign-in,web/e2e/session/session.spec.ts_S1:the_seeded_Zz.Production_check_row_got_lastRunAt,finding_'No_read_access_to_its_namespace'_from_a_real_tick(session.spec.ts:68_is_on_DW-349s_list);rerun_requested
- 2026-10-30T02:20:58Z occurrence=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=ci note=status_unchanged:routed_owner=11-1;CI_run_40987940151_attempt_1_(0990fbe),iris_(browser),live:sign-in,web/e2e/rail/rail.spec.ts_R5:'Last_run_2:02_·_No_read_access_to_its_namespace'_(a_real_tick_ran_the_seeded_row;rail_is_on_DW-349s_list);rerun_requested
- 2026-10-30T09:34:20Z occurrence=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=ci note=flake: OcuTalon.Test.Live.GuideRefresh.TestHeldLock 'the counter moved' red in CI run 41028771985 attempt 1, iris (image), shard:lane-b, on 6ca6563 (Story 12.1 touches no Live, Demo or Checks code); the same class as run 40713989310; one rerun
- 2026-10-30T10:05:51Z occurrence=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=ci note=CI run 41028771985 attempt 1 and its rerun (attempt 2), iris (image), shard:lane-b, on 6ca6563: OcuTalon.Test.Live.GuideRefresh.TestHeldLock 'the counter moved' both times (the class ran across a minute boundary; Fixture.Check seeds its check with no NextDueAt); fix routed to Lane B (Epic 9): TestHeldLock sets NextDueAt one hour ahead through Fixture.Check's fields argument; general fix stays 11-1
- 2026-10-30T17:28:53Z occurrence=29-5-the-address-counter-s-hash-is-keyed-per-reset note=CI run 41088697760 attempt 2 (OCT-epic29 511f1b03, iris image, shard lane-b): Test.Live.GuideRefresh.TestHeldLock 'the counter moved' (Fixture.Check seeds a check row with no NextDueAt; a real minute tick published between Publish and LastSeq); flake class, one rerun
- 2026-10-31T00:50:24Z occurrence=29-7-demo-busy-counts-the-live-visitors note=CI run 41149604870 (OCT-epic29 3f5b3cbe, iris image, shard lane-b): Test.Live.GuideRefresh.TestHeldLock 'the counter moved' again; flake class, one rerun
- 2026-10-31T04:03:36Z occurrence=29-8-the-author-s-load-run-measures-the-demo-s-capacity note=CI run 41165190685 (OCT-epic29 61bb996d, iris browser, live:sign-in): web/e2e/session/session.spec.ts S1 rail check row gained lastRunAt/nextDueAt/finding after a real heartbeat tick; flake class, one rerun
- 2026-10-31T06:05:21Z occurrence=29-9-epic-29-burn-down note=CI run 41172492423 attempt 1 (OCT-epic29 c1758636, iris browser, live:sign-in): banners.spec.ts B2 and rail.spec.ts R5, each seeded check row read 'No read access to its namespace' (run by a real tick); flake class, one rerun
- 2026-10-30T06:11:45Z occurrence=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=lead note=flake(local,integrate-forward_98d4791):Test.Live.GuideRefresh.TestHeldLock('the_counter_moved')_red_twice_on_a_WARM_lane-b_stack_that_had_just_run_all_101_lane-a_classes(incidents,check_rows_left);rerun_also_hit_DW-305's_TestHookPublishesOnChange;passed_on_a_fresh_throwaway(6.7s);status_unchanged
- 2026-10-30T10:10:00Z occurrence=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=lead note=Test.Live.GuideRefresh.TestHeldLock('the_counter_moved')_red_twice_on_Epic_12's_6ca6563(run_41028771985,iris(image),shard:lane-b);fixed_in_lane_B_by_orchestrator_ruling:TestHeldLock_seeds_its_check_with_NextDueAt=Test.Watch.Case.Ahead()(now+24h)_through_Fixture.Check's_fields(9.6);general_fix(fixture_check_rows_not_due_by_default)_stays_with_11-1;status_unchanged
- 2026-10-30T10:50:46Z occurrence=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=cr note=sibling Test.Live.GuideRefresh.TestHeldLockCallerWait seeds Fixture.Check with no NextDueAt, asserts seq=1; status_unchanged
- 2026-10-31T07:36:27Z occurrence=29-9-epic-29-burn-down note=CI run 41178903176 attempt 1 (OCT-epic29 b8090784, bookkeeping over e7a5bb94's green code): iris image shard:lane-b Test.Web.GuideApi TestOnlyTheMarkerChanges (Fixture.Check's seeded row run by a real tick between the two fingerprints) and iris browser live:sign-in session.spec.ts S1 (the rail row gained a finding); superseded by the Epic 9 integrate-forward head, not rerun
- 2026-10-31T08:07:39Z occurrence=29-9-epic-29-burn-down note=CI run 41181446111 attempt 1 (OCT-epic29 13e56475, Epic 9 integrate-forward): iris browser live:sign-in banners.spec.ts B2 'Last run 13:19 · No read access to its namespace' (seeded check row run by a real tick); flake class, one rerun
- 2026-10-31T09:54:07Z occurrence=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=ci note=CI run 41188445340 attempt 1 (OCT-epic12 af47ff3c, Epic 12 integrate-forward onto 366a79ab), iris image, shard:lane-b: Test.Web.GuideApi TestOnlyTheMarkerChanges 'run_again changes none of the session data rows' (Fixture.Check seeded row run by a real tick between the two fingerprints; same as run 41178903176); flake class, one rerun; status_unchanged
- 2026-10-31T11:20:46Z occurrence=10-4-the-readme-opens-with-what-ocutalon-is-for-and-what-a-model by=ci note=CI run 41192152812 attempt 1 (OCT-epic10 192f60c3, Epic 10's final integrate-forward of feature 366a79ab; code = feature + README/test-readme only), iris (shards), live:floor web/e2e/floor/focus.spec.ts:209 P4: the seeded check row read 'No read access to its namespace' (run by a real heartbeat tick) before the republish assertion; floor/focus is on DW-349's list; flake class, one rerun (attempt 2 green); status_unchanged routed owner=11-1
- 2026-10-31T19:14:32Z occurrence=12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try by=ci note=CI run 41230579974 attempt 1 (OCT-epic12 a634857d, Story 12.8), iris browser, live:sign-in: web/e2e/rail/rail.spec.ts R5 'Last run 18:57 · No read access to its namespace' (a real tick ran the seeded check row; rail R5 is on DW-349's list); flake class, one rerun; status_unchanged

### DW-358: Live check of 'cancel all my reminders' with three or more reminders pending, on the online demo's model, effort and endpoint: the turn cancels every pending reminder within Chat's iteration ceiling (AD-20) through the multi-id cancel_reminder of DW-140, and the reply says so
- source: U-118 (owner via the Contest Planner, 2026-10-27); filed at Epic 8's merge | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: DW-140's ceiling is unverified on a live model; U-118's answer (at=2026-10-27T11:31:36Z#355, placement amended by the Planner 2026-10-27T11:3xZ) gives this live check to 11.6 and the tool change to 11.1
- 2026-10-28T16:26:29Z status=routed owner=11-6-a-hands-on-pass-with-real-keys-finds-and-fixes-what-the-test by=merge_gate note=routed by orchestrator at Epic 8's merge, U-118 (kept): 11.6's hands-on pass with real keys runs it; the fix itself is DW-140 in Story 11.1

### DW-362: Story 9.2's repository check docker/tests/test-eval-set.sh (a Lane A check of eval/) sits in Lane B's docker/tests and Lane B's ci/units.sh CHECK_SCRIPTS line, outside AD-29's lane map
- source: spec-9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si.md | severity: med | fix-risk: med | footprint: in-story
- evidence: AC3/Tasks 8-9 put it in the hosted checks job; lead logged both paths as footprint_extensions at spec_validated; ci/units.sh:5 is one line Lane B epics also append to
- 2026-10-28T19:52:15Z status=by-design owner=9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si by=cr note=spec-bound (AC3: the repository checks); lead's footprint grant; lead may add an AD-29 as-built exception (Rule 20)

### DW-363: eval/run.sh requires every test-only case to get one fixed answer (MOCK_WRONG_ANSWER=ignore), while test-eval-set.sh's markers rule accepts any scenario outcome other than the expected one
- source: spec-9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si.md | severity: low | fix-risk: med | footprint: in-story
- evidence: eval/run.sh:61,154 vs check-markers.mjs: a second test-only case whose scenario answers e.g. tellnow passes markers, scores wrong, yet the job FAILs 'did not get ignore'
- 2026-10-28T19:52:15Z status=wontfix-accepted owner=9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si by=cr note=reopen_if=a second case lands in eval/mock-wrong/ (e.g. 9.6's incident case) and eval/run.sh FAILs its answer check

### DW-364: No test checks that eval/run.sh appends both Markdown reports to $GITHUB_STEP_SUMMARY (AC4's step-summary clause)
- source: spec-9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si.md | severity: low | fix-risk: low | footprint: in-story
- evidence: eval/run.sh:173-174; GITHUB_STEP_SUMMARY appears in no test; run-guard stops at preflight, so only a CI run of the evaluation job shows it
- 2026-10-28T19:52:15Z status=wontfix-accepted owner=9-2-each-run-scores-decisions-and-causes-and-records-cost-and-si by=cr note=reopen_if=the first lane-a evaluation run's summary page lacks the set or the mock-wrong report

### DW-369: eval/run.sh checks only that the set run has no problem and prints only the items and incidents scores, so nothing at the evaluation job asserts the injection score, the Injection cases section or the number of sent cases
- source: spec-9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: eval/run.sh:77,130-137 read CHK lines for items/incidents and the case count with no comparison; the section and the injection case are pinned only by Test.Eval.Report.TestInjectionText and Test.Eval.Cases.TestRecordedCases
- 2026-10-28T22:49:28Z status=open owner=9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=harvest note=two-way door in this epic's eval/run.sh: 9.3's code review patches it (assert the injection score line, the section and sent=23 or at least the injection case's presence)
- 2026-10-28T23:56:08Z status=resolved-by:9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=adjudication note=9.3 code review patched eval/run.sh: the set run prints the injection score and fails without an injection-scored case, and set.md must hold the Injections line, the Injection cases section and the mail-suspicious-request bullet; red on two real-runtime mutations (EvalIn kinds reduced to item; section heading removed)

### DW-373: An injection case whose turn Decision is a fallback (a late reply: Decide emits no AgentStep) scores refused with no tool step, so it can be right while its turn's calls are unknown
- source: spec-9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Report.ScoreInjection sets refused=1 and loops only over the AgentStep rows of TurnDecisionRef; Decide.EmitSteps runs only for a reply in time, and Sink copies a turn Decision whatever its Fallback
- 2026-10-28T23:53:55Z status=wontfix-accepted owner=9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=cr note=reopen_if=a real-model run (9.5) shows an injection case right whose turn Decision has Fallback=1

### DW-374: Test.Eval.Cases.Keys (sorted member names, comma-separated) is a near-copy of Lane B's private Test.Core.BridgeSink.Keys
- source: spec-9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Cases.cls:331-345 repeats BridgeSink.cls:623-637 line for line; the sibling is private in a Lane B test class (AD-29), so extending it edits another lane's file
- 2026-10-28T23:53:55Z status=wontfix-accepted owner=9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=cr note=reopen_if=a third Lane A test class needs the helper, or the two copies' outputs differ

### DW-375: Report checks for a non-read-only tool step only in an injection case's turn, so a gate bypass in an item act turn of an eval run is not reported
- source: spec-9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Report.Problems pushes REASONTOOL only from injectionChecks; the spec's Boundaries scope the step check to an injection case's turn, and the run-wide action counts cover every case
- 2026-10-28T23:53:55Z status=by-design owner=9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=cr note=spec-bound (Boundaries: 'in an injection case's turn'); reopens only via a spec amendment, e.g. 9.7's turn-case scoring

### DW-377: TestOnlyRunTimeWriter's line-based SQL scan lets a DELETE of OcuTalon_Data.Setting pass when the verb is on another line and the table's line starts with a %keyword before FROM
- source: spec-9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Re-review (rework 1): after the patch a split DELETE is flagged when its FROM starts the line or a string; '&sql(DELETE' then '%NOLOCK FROM OcuTalon_Data.Setting' still passes (by reading the pattern; no product class has it).
- 2026-10-29T01:51:30Z status=wontfix-theoretical owner=9-3-decision-cases-cover-every-outcome-two-injections-the-all-cl by=cr note=real if a product class writes a split DELETE with a %keyword opening the table line; fix-risk med: needs a statement-level scan

### DW-382: The committed Story 9.4 spec held a local absolute path (the worktree root, line 402) and a real-looking home-folder sample (line 72), which docker/tests/test-boundaries.sh's paths rule refuses, so the hosted checks job would go red on the next push
- source: spec-9-7-turn-cases-measure-the-all-clear-the-command-reply-and-a-sto.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: bash ci/checks.sh FAIL paths on spec-9-4-ten-incidents-are-recorded-from-real-failures.md:72,402 (committed at 139e048 by the lead)
- 2026-10-29T04:54:37Z status=resolved-by:9-4-ten-incidents-are-recorded-from-real-failures owner=9-4-ten-incidents-are-recorded-from-real-failures by=harvest note=the lead rewrote line 72's samples as /Users/<name>/ placeholders (tests build samples by concatenation) and line 402 as the epic-9 worktree root without its path; test-boundaries.sh passes on the whole tree

### DW-383: Eval.In.Render is a line-for-line copy of Lane B's private Core.Conversation.Checked (the glue from a Reply's HostData checks to Checks.Render's key and rows), forced by AD-29; when Conversation's HostData handling changes, the evaluation's all-clear path drifts from the product's (AD-22)
- source: spec-9-7-turn-cases-measure-the-all-clear-the-command-reply-and-a-sto.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Eval/In.cls Render (12 lines) vs src/ocutalon/cls/OcuTalon/Core/Conversation.cls:449 Checked, identical but for the target fields; Design Notes 10 records the reason (a private method of a Lane B process); unlike the Busy numbers and the Input, no test pins the two equal; Story 20.2 extends Conversation's HostData handling
- 2026-10-29T05:55:13Z status=routed owner=20-2-see-citations-and-memories-in-answers by=cr note=Rule 2 forced copy: make the check-rows glue one public Lane A helper that Conversation and EvalIn both call

### DW-385: Test.Eval.Record FixtureSettings and DefinedSettings (QA, Story 9.4) are near-copies of Epic 7's private Test.Watch.Evidence helpers of the same names (same five fixture names, same open/remove/insert loop), forced by Epic 7's read-only Test/Watch/**; the two Orders-definition fixtures drift when the definition handling changes
- source: spec-9-4-ten-incidents-are-recorded-from-real-failures.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls FixtureSettings/DefinedSettings vs src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls:60 and :90 (Private, Epic 7's file); the reason is recorded in the 9.4 spec's Review Findings
- 2026-10-29T08:35:14Z status=routed owner=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=cr note=Rule 2 forced copy: after Epic 7's merge, make the Orders-definition fixture one public helper both classes call
- 2026-10-30T11:00:24Z status=resolved-by:9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=adjudication note=one shared helper OcuTalon.Test.Watch.OrdersDefinition (Put, Defined, the name parameters) called by Test.Watch.Evidence and Test.Eval.Record, whose private FixtureSettings/DefinedSettings are deleted; pinned by Test.Eval.SharedFixture TestNoPrivateCopy (a private copy under any name that builds an Ens.Config.Setting goes red) and the unchanged assertions of both classes; commit c1a5d02 plus QA

### DW-386: The product redactor OcuTalon.Bridge.Redact does not replace two key shapes that docker/tests/test-boundaries.sh key_like flags: DigitalOcean tokens (dop_v1_...) and PEM private-key headers (-----BEGIN ... PRIVATE KEY)
- source: spec-9-4-ten-incidents-are-recorded-from-real-failures.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: found by 9.4's code review comparing Redact.Text with key_like; Bridge.Redact is src/bridge (Lane A, Epic 7's contended path while Epic 7 is open); no release-1 recording source contains these shapes
- 2026-10-29T08:51:48Z status=escalated owner=burndown by=cr note=for the decision sheet: extend Bridge.Redact's key patterns to every key_like shape (security posture; a story of the bridge's owner once Epic 7 merges), or accept with reopen_if a recording or trace shows one
- 2026-10-31T07:17:56Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=merge_gate note=Epic_9_decision_sheet,veto_U-184:extend_Bridge.Redact_to_every_key_like_shape(dop_v1_,PEM_private-key_headers),one_test_per_shape,before_1.0.0
- 2026-10-31T07:25:04Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=owner note=U-184_kept(#557):also_the_Anthropic_key(sk-ant-...)_and_the_Telegram_bot_token(digits:35-char),each_with_a_test,if_key_like_lacks_them

### DW-392: Ownership.Watchers (Lane B) does not skip a watch row of owner eval, so while an evaluation run's watch of a production exists, an instance incident of that production caused by another session's watch would list eval as a recipient (a Notification with SessionRef eval reaches Notify, which refuses it with a warning)
- source: spec-9-8-a-stop-watching-injection-leaves-the-watch-unchanged.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: Data/Ownership.cls:373 selects every SessionRef of Kind production; Data/Session.cls:101 returns it for an instance incident; found by 9.8's plan and four review layers
- 2026-10-29T12:01:00Z status=wontfix-theoretical owner=9-8-a-stop-watching-injection-leaves-the-watch-unchanged by=harvest note=real only if a session watches the same production on a stack where EvalIn is enabled during a run; EvalIn runs only on throwaways and CI (owner condition U-131), where no session watches; fix would be a Lane B Watchers filter on owner eval (Data/Ownership.cls, contended by Epics 10 and 16)

### DW-393: FailurePoller.Watched's eval filter (SessionRef <> ?) compares in SessionRef's default SQLUPPER collation, so an owner EVAL or Eval would be skipped too, while RemoveEvalWatch and Report compare eval exactly
- source: spec-9-8-a-stop-watching-injection-leaves-the-watch-unchanged.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Watch/FailurePoller.cls:60 filters SessionRef <> ? on Data/BackgroundCheck.cls:13 (a %String, default SQLUPPER); Watch/Ops.cls RemoveEvalWatch compares row.SessionRef to eval exactly
- 2026-10-29T13:04:31Z status=wontfix-theoretical owner=9-8-a-stop-watching-injection-leaves-the-watch-unchanged by=cr note=real only if an owner equal to eval ignoring case is written; owners are lower-case or 22-char Refs; fix: %EXACT

### DW-394: Test.Eval.WatchOwners (QA, Story 9.8) repeats Test.Eval.Watch's BackgroundCheck fixture helpers (Row, RefOf, Sweep, the Listed loop; about 35 lines) in a second class instead of adding its five tests there
- source: spec-9-8-a-stop-watching-injection-leaves-the-watch-unchanged.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Test/Eval/WatchOwners.cls:202-293 Row/RefOf/Sweep match Test/Eval/Watch.cls:284-378 but for the production and display name; Decided 18 covers per-class clean-up only
- 2026-10-29T13:04:31Z status=wontfix-accepted owner=9-8-a-stop-watching-injection-leaves-the-watch-unchanged by=cr note=reopen_if a third Test.Eval class copies a BackgroundCheck row builder, or a BackgroundCheck change must be made in both Rows

### DW-397: Test.Eval.Feed.Fixture (Story 9.9) near-copies Install.Step.Demo.System's namespace create/remove and ServiceRole, and Keys/Count repeat Test.Demo.Production WaitCount/Count, forced by Lane B's OCUORDERS-fixed private helpers; the two teardown sequences drift when one changes
- source: spec-9-9-the-other-nine-incidents-come-from-real-failures-in-a-test-f.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: Fixture.cls RemoveSystem (about 65 of its 95 lines) vs Demo.cls System off branch, Revoke vs Demo.ServiceRole(0); Install/** and Test/Demo/* are read-only for 9.9 and both siblings are fixed to OCUORDERS
- 2026-10-29T17:55:09Z status=routed owner=burndown by=cr note=Rule 2 forced copy: a namespace-parameterised Demo.System helper unifies it when Epic 15 touches Demo.cls (cf. DW-223)
- 2026-10-30T15:23:33Z status=routed owner=15-2-the-second-install-run-gives-a-working-ocutalon-with-demo-mo by=burndown note=overflow: the fix (a namespace-parameterised Install.Step.Demo System helper that Test.Eval.Feed.Fixture calls) needs Install/Step/Demo.cls, Epic 15's contended path; Story 15.2 touches Demo.cls and already owns the sibling copy DW-223
- 2026-10-31T07:17:56Z status=routed owner=31-1-push-live-events-over-a-websocket-on-local-installs by=merge_gate note=follows_DW-223(U-177):the_fix_needs_Install/Step/Demo.cls(Lane_B,AD-33),not_Lane_A's_15.2;31.1_declines_it_onward_if_Demo.cls_is_not_free
### DW-359: The README's clone command and the page's README_URL resolve only once the repository is public (github.com/jbrandtmse/OcuTalon answered 404 on 2026-10-28); recheck every README link and GitHub's heading slugs on the public page before the release
- source: spec-10-2-the-readme-gets-a-judge-from-download-to-sign-in.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 10.2 implement: HTTP 404 on the private repository; test-readme.sh checks anchors against its own slug rule (Design Note 8, inference until the page is public)
- 2026-10-28T18:29:41Z status=routed owner=11-4-the-release-gets-draft-notes-and-a-checklist by=harvest note=release checklist item: open README_URL and every README anchor on the public repository page; Story 31.3 repeats it for 1.0.0
- 2026-10-28T19:29:24Z note=measured 2026-10-28 on OCT-epic10 dc4b73c via the repository README render (application/vnd.github.html): all 22 GitHub heading ids equal test-readme.sh's slugs and every in-README anchor resolves; the residual is only opening README_URL and the clone URL once the repository is public

### DW-360: The README's LAN warning names the default IRIS accounts' passwords but gives steps only for the README account
- source: spec-10-2-the-readme-gets-a-judge-from-download-to-sign-in.md | severity: med | fix-risk: low | footprint: in-story
- evidence: README.md ## Sign in: reachable from the LAN until the default IRIS accounts' and the README account's passwords are changed; only the README account has a how-to (DW-3 wording, author's decision 2026-10-18)
- 2026-10-28T18:29:41Z status=decision-pending owner=burndown by=harvest note=product and security-posture call: add how to change the default IRIS accounts' passwords, or say how to publish the port on 127.0.0.1 only, or keep the wording
- 2026-10-29T02:22:28Z status=routed owner=31-3-the-readme-leads-to-the-demo-and-the-launched-demo-is-measur by=merge_gate note=Epic 10 decision sheet (veto U-145): the 1.0.0 README adds how to change the default IRIS accounts' passwords in the Management Portal, next to the README account's how-to; the private 0.1.x README keeps its wording

### DW-361: The page's How to set a key and Install it yourself links open the README's top (#readme), not the Set a model key and Install it yourself sections
- source: spec-10-2-the-readme-gets-a-judge-from-download-to-sign-in.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: banner-view.ts:64-67 sends both actions to README_URL (#readme); epics.md Story 10.2 AC (line 3508) asks for an existing section; Design Note 1 kept #readme because web/src/app/banners/** is contended (Epic 16)
- 2026-10-28T19:20:22Z status=escalated owner=burndown by=cr note=recommend: the Epic 16 story that next edits banners/** targets #set-a-model-key and #install-it-yourself; or accept #readme
- 2026-10-29T02:22:28Z status=routed owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=merge_gate note=Epic 10 decision sheet (decide): the banners' How to set a key and Install it yourself actions target the README's #set-a-model-key and #install-it-yourself sections, not #readme
- 2026-10-29T22:51:03Z status=resolved-by:16-9-allowances-cap-messages-model-cost-and-simulated-emails by=adjudication note=banner-view.ts_actions_target_#set-a-model-key_and_#install-it-yourself;README_has_both_headings;pinned_by_banner-view.test.mjs,banners.spec.ts_B1/B4/B5,busy.spec.ts,allowance-sources.test.mjs,test-readme.sh

### DW-367: The CI override sets the dummy TELEGRAM_BOT_TOKEN for every CI and throwaway start, so once Included() can be 1 a start with no bot token (FR-21: no token, so Telegram off) has no way to be expressed in CI
- source: spec-10-3-the-session-side-of-telegram-is-ready-and-stays-off.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ci/compose.ci.yml sets TELEGRAM_BOT_TOKEN unconditionally and live_key_count counts an empty token as a key; unverified until Story 12.1 enables the Telegram items
- 2026-10-28T22:30:49Z status=routed owner=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=harvest note=Story 12.1 decides how a no-token start is made in CI (a start without the override, or an explicit empty value) when it turns the items on
- 2026-10-30T08:38:01Z status=resolved-by:12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=adjudication note=213ea71+review_patches: docker/tests/lib-live.sh live_key_count counts an empty TELEGRAM_BOT_TOKEN as no key and live_no_bot_token layers TELEGRAM_BOT_TOKEN='' last; test-production-restart.sh row 19 starts with the seam at 1 and an empty token (check_token_empty, check_no_key, check_items_run, check_telegram_off: rows 0, mark off, no Bot API call); test-lib-live.sh rows pin both

### DW-370: The CI mock's Bot API state is one global queue, call list and counter for one client: reset restarts update_id at 1, so a poller that keeps its offset drops new updates as confirmed, and Test.Contract.Mock.TestTelegramBotApi expects only its own three calls
- source: spec-10-3-the-session-side-of-telegram-is-ready-and-stays-off.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ci/mock/mock.mjs telegramControl reset sets tg.nextUpdateId = 1 and pendingUpdates drops update_id < offset (Decided 23); Test/Contract/Mock.cls:358-372 resets, then expects update_id 1 and 3 calls; reachable once Story 12.1 runs an enabled TelegramIn poller in CI
- 2026-10-28T23:35:43Z status=routed owner=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=cr note=12.1 decides how a live poller and the tests share the mock: keep update_id counting over reset, or reset the offset
- 2026-10-30T08:38:01Z status=resolved-by:12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=adjudication note=Lane A half (orchestrator ruling Q2, comply with AD-22/AD-33): Test.Channel.BotApi.Reset clears TelegramIn's kept offset ($$$EnsStaticAppData TelegramIn offset) in the same call as the mock reset and refuses under a live TelegramIn job (TelegramMock TestResetClearsKeptOffset, TestPollerCheck, mutations in the spec); the mock's one-client state and TestTelegramBotApi's own-calls assumption are DW-421 (escalated, Lane B mock ask); the poller's use of the node is DW-422 (12.2)

### DW-371: Data.Pairing.Purge repeats about 20 of the 22 lines of Lane A's Digest.Data.Item.Purge (the day-count check and the UTC cutoff), a copy forced by AD-29; the purges drift when the day rule changes
- source: spec-10-3-the-session-side-of-telegram-is-ready-and-stays-off.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Data/Pairing.cls:217 Purge vs src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls:64 Purge; Task A says the validation and cutoff follow Digest/Data/Item.cls:64-87; Digest is Lane A's (AD-29)
- 2026-10-28T23:35:43Z status=routed owner=30-2-old-messages-and-records-are-purged-on-schedule by=cr note=Rule 2 forced copy: one day-count check and cutoff helper (e.g. in Data.Time) for Bridge.Purge, Pairing.Purge, Digest

### DW-372: The Story 10.3 Pairing test classes each carry their own NewChat, Code, Submit, Hops and WaitHops helpers (SessionOps, SessionOpsProduction, AnswersTelegramProduction, PairingApi, beside RoutingProduction.WaitHops)
- source: spec-10-3-the-session-side-of-telegram-is-ready-and-stays-off.md | severity: low | fix-risk: med | footprint: in-story
- evidence: src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls:645-660, SessionOpsProduction.cls:219-290, AnswersTelegramProduction.cls:200-230, Test/Web/PairingApi.cls:312-412; each binds its class's Refs list; Test.Data.Fixture is contended
- 2026-10-28T23:35:43Z status=wontfix-accepted owner=10-3-the-session-side-of-telegram-is-ready-and-stays-off by=cr note=reopen_if=a change to RecordChat, StoreCode or Commands.Submit needs the same edit in more than two Pairing test classes

### DW-376: flake: OcuTalon.Test.Schedule.Heartbeat TestStoppedThenStarted, 'the task ran while the production was stopped': the Task Manager's RunNow run was not seen within RUNSECONDS
- source: spec-10-3-the-session-side-of-telegram-is-ready-and-stays-off.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Story 10.3 fresh check, lane C, fresh shard lane-b --part 3/3 (e10s3f, 2026-10-29): failed once at 159 s, then passed unchanged on a fresh class run (170 s); the story changes nothing under Schedule/
- 2026-10-29T00:23:31Z status=routed owner=burndown by=fresh_check note=flake class like DW-349: a fixed wait on the Task Manager's RunNow; a rerun clears it; route to the release-1 flake story at the burn-down gate
- 2026-10-29T01:11:55Z owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=burndown note=Epic 10 burn-down overflow: the release-1 flake class beside DW-349 (a fixed wait on a heartbeat-driven run); 11.1 gates REL-2 on a green CI, so it fixes the RunNow wait or ledgers the rerun rule
- 2026-10-30T16:58:58Z occurrence=29-5-the-address-counter-s-hash-is-keyed-per-reset note=CI run 41088697760 (OCT-epic29 511f1b03, iris image, shard lane-b): Test.Schedule.Heartbeat TestStoppedThenStarted 'the task ran while the production was stopped' (197 s); flake class, one rerun

### DW-378: Tagline: replace 'An OpenClaw-style assistant for InterSystems IRIS.' with 'An AI assistant for InterSystems IRIS.' in the About dialog and the tests that pin it; the not-affiliated note stays verbatim
- source: owner decision 2026-10-29 (relayed by the Contest Planner) | severity: high | fix-risk: low | footprint: out-of-footprint
- evidence: web/src/app/about/about-dialog.ts:26; web/e2e/frame/frame.spec.ts:250,260; web/scripts/ux-strings.test.mjs:272; planning text already amended (epics.md UX-DR16 and the About criterion, EXPERIENCE.md, prd.md, brief.md)
- 2026-10-29T02:23:36Z status=routed owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=owner note=owner: 'I don't want to infrenge on openClaw...' and 'Okay, let's go with A'; must be in before the 0.1.0 candidate is cut (the owner records the video on 0.1.1); docker/tests/test-readme.sh's 'OpenClaw outside the note' fixture stays (it proves the check)

### DW-399: Test.Fix.Stopped asserts that OrdersFromPartner starts again within WAITSECONDS - 10 (50) seconds of R1's ResentAt, which a slow CI runner could miss
- source: _bmad-output/implementation-artifacts/spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: med | fix-risk: low | footprint: in-story
- evidence: the class stops and starts FixExecutor (two 10 s lock waits) between R1's ResentAt and the copies' item restart, then asserts elapsed <= MARGIN; passed twice locally (85 s), no elapsed value printed (Stopped.cls:24)
- 2026-10-29T20:57:12Z status=open owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=harvest note=QA at the resume: measure the elapsed margin on a fresh run and on CI; if it can fail on a slow host, reorder the steps or widen the window
- 2026-10-29T23:21:03Z status=resolved-by:7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=adjudication note=measured: CI run 40961979510 (iris shards-2, a fresh CI stack) passed Test.Fix.Stopped in 83.41s, so OrdersFromPartner started again inside the 50s margin on a CI runner; locally the class measured 0s of 50 and the Tick 1s of 60 (QA); QA made Stopped print its measured seconds on a pass (a status-2 assert line), so every later CI run shows the value

### DW-407: The spine's AD-22 'CI as built' record still says six IRIS groups with lane-a run whole; 3308237 (DW-337) made seven groups (shards-2), runs lane-a in two pieces and moved live:cards to install-upgrade
- source: spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: ARCHITECTURE-SPINE.md:608 reads 'inside six IRIS groups (install-fresh, install-upgrade, production, browser, shards and image)' and lists lane-a as Agent, Bridge, Install, Tools and Digest; ci/units.sh now has seven IRIS_GROUPS and shard_unit_areas pieces
- 2026-10-29T23:01:40Z status=routed owner=burndown by=cr note=lead: Rule 20 light path, AD-22 as-built line (7 groups, lane-a pieces, live:cards, lane-a areas)
- 2026-10-30T03:44:43Z status=decision-pending owner=burndown by=burndown note=set aside for the decision sheet (orchestrator ruling, option b): the orchestrator writes the factual AD-22 as-built correction in the main checkout after the merge; no worktree AD edit (U14: AD-22 cited by Epics 9, 16, 15 and 13)
- 2026-10-30T05:18:18Z status=resolved-by:7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got owner=burndown by=merge_gate note=closed at Epic 7's decision sheet: the orchestrator corrected AD-22's as-built CI line after merge eb313fa (seven groups, lane-a in two pieces, live:cards in install-fresh, lane-a areas); owner_decision dw407_ad22_as_built via contest_planner

### DW-408: A final FixResult that Checks fails to send is lost: Fix.Run.Sweep has already ended the run, so no later Tick returns it and the incident stays fixing
- source: spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Checks/Process.cls Fixes logs LOGFIX and goes on after Sweep saved EndedAt; the spec's Always and Never bullets: a failed send logs LOGFIX, never a second FixResult, no stored property
- 2026-10-29T23:01:40Z status=by-design owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=cr note=spec-bound at-most-once, as FixExecutor's Report; an unsent marker needs a stored property (spec amendment)

### DW-409: When Fix.Run.EndLeft's close fails or throws after End saved the run, the request stays executing and the final result renders result.stillResending, which nothing follows up
- source: spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Fix/Run.cls:212-221 ends, then closes; TestSweepEndsARunNoWaiterEnded case C pins it; the spec's Always bullet orders End then FinishExecution done (residual risk 4)
- 2026-10-29T23:01:40Z status=by-design owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=cr note=spec-bound order (residual risk 4, as 7.4's Finish); needs a FinishExecution fault; reopen by amending: close first

### DW-410: A run that Reconcile marked counts as V2 rules: its row ends failed/interrupted with an interrupted Action entry even when nothing was cut off, recheck skips count as cut off, and an unreadable read counts every copy as cut off
- source: spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Fix/Run.cls:164-184 EndMarked (Skipped 0, Interrupted = Total - Completed - FailedAgain); spec V2 and the spine's Conventions row Fix runs; AD-11 and AD-16 still word it as the interrupted result
- 2026-10-29T23:01:40Z status=by-design owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=cr note=V2 ruled at the spec gate (veto U-154); conservative, never a false all-clear; AD-16's text kept as ruled

### DW-411: Reconcile's Fix.Run.Interrupt leaves a cut-short run unmarked when it cannot take the run's lock in 2 s or Mark's save fails, and nothing marks it before the next start
- source: spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Fix/Run.cls:88-89 and :99-100 push a problem and go on; Sweep never marks a run, and EndLeft holds the run's lock while it reads the copies
- 2026-10-29T23:01:48Z status=wontfix-theoretical owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=cr note=real if a Tick's Sweep holds that run's lock over 2 s inside the Reconcile step (thousands of copies) or a storage fault

### DW-412: Fix.Run repeats small parts of FixExecutor's end instead of calling them: Entry is Executor.Audit's try/catch around its own WriteAudit seam, and EndLeft rebuilds Executor.Look's done counts
- source: spec-7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Fix/Run.cls:208-211 and :241-252 against Fix/Executor.cls:688-691 and :487-498; the spec's Rule 2 note names the lifted methods but not these two
- 2026-10-29T23:01:48Z status=wontfix-accepted owner=7-5-a-resend-cut-short-by-a-restart-says-how-far-it-got by=cr note=reopen_if=a change to Executor.Look's counts or Audit's handling lands without the same change in Fix.Run.EndLeft or Entry

### DW-415: flake: live:sign-in web/e2e/sign-in/shell.spec.ts:93 row 9 failed with page.goto: net::ERR_NETWORK_CHANGED (Chromium saw the CI host's network interfaces change mid-run, likely another job's compose networks), then passed on an unchanged rerun
- source: orchestrator ruling: Epic 7 CI on 89685f6 (run 40993669822) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: run 40993669822 iris (browser) attempt 1: 1 failed (shell.spec.ts row 9, page.goto net::ERR_NETWORK_CHANGED at http://127.0.0.1:52808/ocutalon/); attempt 2 green
- 2026-10-30T03:44:09Z status=routed owner=burndown by=runner note=flake class per CI Is a Gate; no assertion failed; burn-down gate re-owns it
- 2026-10-30T03:44:43Z status=wontfix-accepted by=burndown note=a single CI-host network blip (no assertion failed; green on the unchanged rerun); reopen_if=net::ERR_NETWORK_CHANGED appears again in any iris job log
- 2026-10-29T10:36:25Z status=resolved-by:16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=adjudication note=about-dialog.ts:26 'An AI assistant for InterSystems IRIS.'; frame.spec.ts F6 and ux-strings.test.mjs pin it; the not-affiliated note verbatim (about-dialog.ts:42); no 'OpenClaw-style' left outside test-readme.sh's fixture (owner decision 2026-10-29)
- 2026-10-31T04:11:24Z occurrence=29-8-the-author-s-load-run-measures-the-demo-s-capacity note=CI run 41165190685 attempt 1 (OCT-epic29 61bb996d, iris shards, live:floor): keyboard.spec.ts K2 page.goto net::ERR_NETWORK_CHANGED at sign-in/helpers.ts:44; no assertion failed
- 2026-10-31T04:11:25Z status=routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=runner note=reopen_if fired (ERR_NETWORK_CHANGED again in an iris job log); the fix site is the shared sign-in helper, which Story 29.9's boundaries exclude; routed to the CI e2e flake owner beside DW-349 (a retry of page.goto on net::ERR_NETWORK_CHANGED only, or a Chromium launch option, is the candidate)

### DW-387: flake: Test.Core.SessionOpsProduction TestPageUnpairSendsTheNotice and TestRejectedPairsAreAudited fail 'one Pairing entry names the session' on a warm stack (AuditLog.Now() mark may share a stamp with the previous linked entry, so the wait returns two entries)
- source: spec-16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi.md | severity: med | fix-risk: low | footprint: in-footprint
- evidence: 16.4 QA: 2 of 9 warm runs with QA tests, 1 of 4 runs at HEAD 247dfad without them; Story 10.3 methods in the class 16.4 extends
- 2026-10-29T09:38:55Z status=open owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=harvest note=found by 16.4 QA; the class is in this story's footprint extension, so 16.4's code review makes the wait deterministic
- 2026-10-29T10:36:25Z status=resolved-by:16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=adjudication note=16.4 code review: every audit mark in Test.Core.SessionOpsProduction is taken past the newest audit entry (Mark); 4 of 4 warm runs green; mutation recorded

### DW-388: The idle cap counts only the OcuTalon page's key presses and clicks, so a visitor who reads Visual Trace for 10 minutes without going back to the page is signed out of the trace tab too
- source: spec-16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi.md | severity: low | fix-risk: high | footprint: in-story
- evidence: session-gate.ts:64-66 listens on the OcuTalon document only, and leave('idle') runs the group sign-out (:164), which Task 0 (a) measured ends the trace CSP session at once; the trace pages are IRIS's own, so the page cannot see activity there
- 2026-10-29T10:33:41Z status=by-design owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=cr note=spec-bound: AD-13 and the spec count only key presses, clicks and sends in the page; IRIS's trace pages can't be watched

### DW-389: After an unscheduled restart, a resume cookie set before it still makes the splash show the place-freed notice ('pick up where you left off'), though signing in starts a fresh session
- source: spec-16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi.md | severity: low | fix-risk: high | footprint: in-story
- evidence: Splash.InfoNotice shows PLACEFREED on the cookie alone when there is no since; the cookie expires at the next scheduled reset, which an unscheduled restart does not shift (AD-25), and the restored golden copy holds no session
- 2026-10-29T10:33:41Z status=decision-pending owner=burndown by=cr note=product call: accept; or no PLACEFREED while the period's last reset was unscheduled; or a reset id in the cookie (veto)
- 2026-10-30T03:14:28Z status=wontfix-accepted by=merge_gate note=Epic 16 decision sheet (decide): LOW, high fix-risk; reopen_if=a judge or the probe reports the place-freed notice after an unscheduled restart

### DW-390: SessionOps.End sends CancelReminder and StopWatch straight to ReminderOps and WatchOps, so CommandsIn's origin check for those two verbs is not applied to them
- source: spec-16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi.md | severity: low | fix-risk: med | footprint: in-story
- evidence: SessionOps.Carry sends them with SendRequestSync and the EndSession's origin (spec Design Notes, Direct messages); CommandsIn's Routes accept every EndSession origin for both verbs today, so nothing is bypassed now
- 2026-10-29T10:33:41Z status=wontfix-theoretical owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=cr note=theoretical: real only if CommandsIn's Routes drop an EndSession origin from CancelReminder or StopWatch

### DW-391: Test.Web.SessionEndApi repeats Test.Web.PairingApi's private Guard, Session, ErrorBody and clean-up helpers instead of sharing them (the spec's one stated copy, Rule 2)
- source: spec-16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi.md | severity: low | fix-risk: med | footprint: out-of-footprint
- evidence: SessionEndApi.cls Guard, Session, ErrorBody and OnBefore/AfterAllTests match PairingApi.cls's; sharing them means a route-test base class and an edit of Epic 10's merged PairingApi
- 2026-10-29T10:33:41Z status=wontfix-accepted owner=16-4-leaving-the-page-frees-its-place-and-sign-out-ends-the-sessi by=cr note=reopen_if=a third route test class copies PairingApi's Guard, Session and ErrorBody helpers

### DW-396: flake: checks ci-warm 'up beside a held warm-iris.lock' printed LOCK busy after 1 s without its LOCK waiting line (docker/tests/test-ci-warm.sh, Story 32.4)
- source: cycle-log-epic-16.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: CI run 40893085769 attempt 1 (8a89586): FAIL missing /^LOCK waiting: warm-iris is held by /; green on the unchanged rerun (attempt 2)
- 2026-10-29T15:14:20Z status=routed owner=burndown by=ci note=flake routed to the burn-down with priority; the test's 1 s wait leaves no room for the waiting line on a slow host
- 2026-10-30T02:55:13Z owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=burndown note=overflow(Epic_16_burn-down):docker/tests/test-ci-warm.sh_(Story_32.4)_waits_1_s_for_the_LOCK_waiting_line_beside_a_held_warm-iris.lock;give_it_room_on_a_slow_host;11.1_owns_the_CI_flakes_that_block_REL-2s_green_(DW-349,DW-376);the_file_is_on_Epic_7s_branch_(DW-337),so_after_Epic_7_merges

### DW-398: Core/NoticesIn.cls's class comment still calls Story 16.9's daily-cap message a sender to come; BridgeSink sends it now (comment only)
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: low | footprint: in-story
- evidence: 16.9 implement deferred: Task 0 (a) found NoticesIn's two branches already give each notice its own session's TraceRef; only the comment is stale
- 2026-10-29T18:56:14Z status=open owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=harvest note=a two-way-door LOW for 16.9's review to patch
- 2026-10-29T22:51:03Z status=resolved-by:16-9-allowances-cap-messages-model-cost-and-simulated-emails by=adjudication note=code_review_patched_the_Core/NoticesIn.cls_class_comment(names_BridgeSinks_daily-cap_message_as_a_sender;comment_only)

### DW-400: The allowance banner's clear at retryAt on the page's own clock (BannerStack.withAllowance) is pinned only by a source-text test
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: med | footprint: in-story
- evidence: A2 waits 45 s for the clear with retryAt about 30 s ahead; StatusMonitor's clear (15 s tick) also arrives in that time, so keeping the store's condition in withAllowance leaves A2 green; only allowance-sources.test.mjs (a regex) goes red.
- 2026-10-29T22:47:08Z status=wontfix-accepted owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=reopen_if=a page shows the allowance banner after retryAt while its composer is usable (A2 trace, smoke or bug report)

### DW-401: After a visitor's first allowance window ends, each later short window that opens at the limit starts with a first refusal and sends another allowance card
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Matrix row 5: a refusal once now >= AllowanceUntil is a first refusal; with a rolling hour the later windows last only until the next oldest entry ages out, so a visitor who keeps sending at the limit gets a card per short window.
- 2026-10-29T22:47:08Z status=by-design owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=spec-bound (matrix row 5, AC 3: one notice per window); reopens only by a spec amendment

### DW-402: AllowanceUntil is not reconciled when messageAllowance changes during an open window
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: med | footprint: in-story
- evidence: TryConsume keeps AllowanceUntil on an allowed message and returns the newly computed until on a later refusal: a raised limit accepts while the banner holds, a lowered one gives a 429 retryAt later than the status time.
- 2026-10-29T22:47:08Z status=wontfix-theoretical owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=real only if an admin changes messageAllowance on a running demo while a visitor's window is open

### DW-403: Allowance.Refund after a concurrent first refusal leaves AllowanceUntil set though the count is back under the limit
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Refund removes the newest entry under the row lock but never clears AllowanceUntil, so the banner and the disabled composer hold until retryAt although TryConsume would accept.
- 2026-10-29T22:47:08Z status=wontfix-theoretical owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=real only if an Item send fails on the 50th message while a concurrent post of that session is refused

### DW-404: Allowance.MailAllowed gives a retryAt too early when a session has more than 20 incoming emails in the hour
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: low | footprint: in-story
- evidence: retryAt is the oldest incoming email plus 3600 s; with 21 or more in the window the count is still 20 or more then, so the page re-enables the chips and the next press is refused again.
- 2026-10-29T22:47:08Z status=wontfix-theoretical owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=real only if the online-demo flag is switched on while a session has over 20 incoming emails in the past hour

### DW-405: Ownership.Resume's unlocked save at sign-in can write back a stale AllowanceUntil or DailyCapDay, not only AllowanceTimes
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Resume opens, sets CspSessionId and saves the whole Session row without its lock; a refusal or daily-cap send of the same session between its open and save is overwritten, so the next one sends a second card.
- 2026-10-29T22:47:08Z status=wontfix-theoretical owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=real only if a sign-in's Resume interleaves with a refusal or daily-cap send of that session; a second card would show it

### DW-406: The browser timer idiom (LONGEST_TIMER_MS, arm, disarm, re-arm) is copied into live/allowance-state.ts and mailbox/simulated-mailbox.ts beside reset-watch.ts and session/idle-cap.ts
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Rule 2, weak reason: the spec names reset-watch.ts as the sibling AllowanceState follows but not why the timer is not shared; the copies already differ (one clamps at 0, one clears at once).
- 2026-10-29T22:47:08Z status=wontfix-accepted owner=16-9-allowances-cap-messages-model-cost-and-simulated-emails by=cr note=reopen_if=a fifth copy of the LONGEST_TIMER_MS idiom lands in web/src/app, or a fix to one copy's clamp or re-arm misses another

### DW-413: Story 16.9's daily-cap browser cases D1, D2 and AP read the instance's day more than once, so an instance midnight inside a case turns it red
- source: spec-16-9-allowances-cap-messages-model-cost-and-simulated-emails.md | severity: med | fix-risk: med | footprint: in-story
- evidence: web/e2e-online/allowance/daily-cap.spec.ts seeds today's spend (seedUsage, :110 and :180) and later reads today's mark and day again (cappedMarked :127/:160, localToday :133/:165, support.ts:563-570); Bridge.Budget.State counts only the current local day. A midnight between them (a window of about 1-2 min per case) gives no daily_cap card, or a mark and DailyCapDay of the day before.
- 2026-10-30T01:29:01Z status=routed owner=burndown by=cr note=re-review 1 of 16.9 (verification-gap): take the day once (e.g. from the fallback's RecordedAt) and keep each case clear of instance midnight; not patched: the wait path is unexercisable here
- 2026-10-30T02:55:13Z owner=29-4-sessions-stay-isolated-under-load by=burndown note=overflow(Epic_16_burn-down):web/e2e-online/allowance/daily-cap.spec.ts_D1,D2,AP_read_the_instance_day_more_than_once;take_the_day_once_(e.g._the_fallbacks_RecordedAt)_and_keep_each_case_clear_of_instance_midnight;29.4_runs_the_online-demo_e2e_with_the_online-demo_start_values
- 2026-10-30T13:14:02Z status=resolved-by:29-4-sessions-stay-isolated-under-load by=adjudication note=web/e2e-online/support.ts instanceDay and clearOfMidnight read the instance day once per case; D1, D2 and AP pass that day to cappedMarked, unmarkCapped and the DailyCapDay comparison; the browserless D0 pins the midnight wait; review made test-online-allowance.sh's capped-mark checks day-independent

### DW-414: flake: OcuTalon.Test.Checks.Runs TestWindow 'the next reads from the previous run less 2 seconds' read from the real clock (2026-10-29 23:59:24) instead of the test's own Tick time, at an instance midnight
- source: cycle-log-epic-16.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: CI run 40975637263 attempt 1 (75d731a), iris (shards), shard:lane-a: FAIL TestWindow ... 2026-10-29 23:59:24.000; green on the unchanged rerun (attempt 2); Test/Checks is Epic 5's (Lane A), untouched by Epic 16
- 2026-10-30T01:32:49Z status=routed owner=burndown by=ci note=flake routed to the burn-down with priority; DW-289 (real-Tick interference in Test.Checks.Runs) was resolved by 5.10, so a new entry; the same run's two other reds also sat at 23:59Z (16.9's same-day time assertion, reworked)
- 2026-10-30T02:55:13Z owner=30-4-a-stopped-production-or-a-disabled-item-is-reported-once by=burndown note=overflow(Epic_16_burn-down):Test.Checks.Runs_TestWindow_read_the_real_clock_near_instance_midnight_(23:59:24Z);30.4_is_the_next_story_on_the_Checks_runs_and_their_tests_(Lane_A)

### DW-416: Behind a TLS-terminating proxy every online-demo API POST fails the origin check (403 wrong_origin): IRIS expects an http:// origin and the browser sends https://; the demo host maps that exact origin on /ocutalon/api/* as a workaround
- source: host facts measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4) | severity: med | fix-risk: med | footprint: in-epic
- evidence: the Planner's API POSTs through the gated proxy got 403 wrong_origin until the host mapped the origin; a foreign or missing Origin still gets 403 with the workaround
- 2026-10-30T04:25:44Z status=routed owner=burndown by=runner note=repository option the Planner prefers: trust X-Forwarded-Proto only from the trusted proxy address (the one trusted for X-Forwarded-For), or a configured public origin; a veto-window change to the origin check (security posture); not needed for the launch while the host workaround stands; runner C ruling 2026-10-30: no repository change in Story 29.3
- 2026-10-31T03:39:09Z owner=31-3-the-readme-leads-to-the-demo-and-the-launched-demo-is-measur by=burndown note=overflow: Lane B hardening on the launched demo; the host workaround (exact-origin mapping) stands until then; trusting X-Forwarded-Proto from the trusted proxy is a veto-window change for that story

### DW-417: Times the model writes itself on the online demo carry no ET (for example 'due at 23:39'), against UX-DR108 and UX-DR123; the catalog's message times do carry it
- source: host facts measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: the Planner saw a bare model-written time in a reply on the gated host; the agent's input preamble names the zone (Agent/Input.cls) but no instruction asks for the ET suffix on the online demo
- 2026-10-30T04:25:44Z status=routed owner=burndown by=runner note=raised from the Planner's LOW: every judge reads model-written times on the online demo; the likely fix is one online-demo instruction line (Agent/Chat.cls or Agent/Input.cls, Lane A files outside Epic 29's footprint); runner C ruling 2026-10-30: not Story 29.3's goal, decided at Epic 29's burn-down gate
- 2026-10-31T03:39:09Z owner=11-6-a-hands-on-pass-with-real-keys-finds-and-fixes-what-the-test by=burndown note=overflow: model-written times are real-model behaviour that Story 11.6's hands-on pass with real keys finds and fixes (an online-demo instruction line in Lane A's agent classes)

### DW-418: An online-demo start whose OCUTALON_CONNECTION_RESERVE is not below OCUTALON_CONNECTION_CAP leaves IRIS never ready without a clear start-up error
- source: host facts measured on the gated host by the Contest Planner 2026-10-30 (Epic 16 deploy c70a0f4) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Install/Step/Public.cls:109 already refuses the pair with a status naming OCUTALON_CONNECTION_RESERVE; the Planner saw only that IRIS never became ready (Install/** is Epic 15's contended path)
- 2026-10-30T04:25:44Z status=wontfix-accepted owner=29-3-the-demo-host-is-adapted-for-the-launch by=runner note=reopen_if=a start with reserve >= cap leaves no line naming OCUTALON_CONNECTION_RESERVE in the IRIS container's log; the host's own config, refused by design (AD-19)

### DW-423: AD-29's October 21 launch fix says Story 29.3 changes no file in this repository, but owner decision epic29_brief (2026-10-30) put the host check and its check list in release/ (Lane A's folder); the spine does not record it
- source: spec-29-3-the-demo-host-is-adapted-for-the-launch.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Spine AD-29 launch-fix bullet: 'Story 29.3 changes no file in this repository'; the story adds release/demo-host-check.sh and release/demo-host-checks.md, which epic29_brief directs; no AD-29 as-built line (Rule 20)
- 2026-10-30T08:03:08Z status=escalated owner=burndown by=cr note=for the decision sheet: an AD-29 as-built line naming 29.3's two release/ files (spine update is the lead's, Rule 20)
- 2026-10-30T19:11:36Z occurrence=29-6-the-probe-alerts-when-every-turn-falls-back
- 2026-10-31T09:02:42Z status=resolved-by:29-3-the-demo-host-is-adapted-for-the-launch by=merge_gate note=AD-29's_as-built_line_names_29.3's_release/demo-host-check.sh+demo-host-checks.md_and_29.8's_release/demo-load.sh

### DW-424: IRIS_INPUT's docker/tests/lib-[^/]+.sh pattern also claims lib-stub.sh, which only the hosted tests test-probe.sh and test-online-host.sh use, so a change to it runs every IRIS group in CI
- source: spec-29-3-the-demo-host-is-adapted-for-the-launch.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ci/units.sh:68 IRIS_INPUT holds docker/tests/lib-[^/]+\.sh$; lib-stub.sh (Story 29.3) is sourced by no live unit
- 2026-10-30T08:03:08Z status=wontfix-accepted owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=reopen_if=a push that changes only docker/tests/lib-stub.sh runs an IRIS group, and the epic's CI time is over REL-4's 35 min

### DW-425: The live Story 29.3 section measures each host_probes target with a unique probe= parameter added, while the script sends the targets exactly as listed (row 4's bare forms bare)
- source: spec-29-3-the-demo-host-is-adapted-for-the-launch.md | severity: low | fix-risk: med | footprint: in-story
- evidence: test-online-demo.sh host_send appends ${sep}probe=$probes (the unit's guard against the web gateway's per-URL answer cache); release/demo-host-check.sh sends probe_target as is
- 2026-10-30T08:03:08Z status=wontfix-theoretical owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=real if a build's routing or the gateway answers a CSP or REST path differently with a query string than without

### DW-426: The host check's sign-out (host_app) ends a session only on /ocutalon/* applications, so a session cookie set by an answer under /csp/* or /api/* (scoped to its own path) would not be ended
- source: spec-29-3-the-demo-host-is-adapted-for-the-launch.md | severity: low | fix-risk: low | footprint: in-story
- evidence: lib-online.sh host_app maps every target outside /ocutalon/trace/* and /ocutalon/api/* to /ocutalon/; on build 154 those answers are 404, 401 or 200 with no form and open no session
- 2026-10-30T08:03:08Z status=wontfix-theoretical owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=real when an answer under /csp/* or /api/* sets an IRIS session cookie (a build or host config that opens sessions there)

### DW-427: block-mark sees only the allowed reads (all 200), so a block mark that IRIS's own not-found answers also carry passes a let-through probe that IRIS answers 404 with no form
- source: spec-29-3-the-demo-host-is-adapted-for-the-launch.md | severity: low | fix-risk: med | footprint: in-story
- evidence: release/demo-host-check.sh note_allowed runs on allow-status, allow-splash, allow-broker and the two sign-ins; the 20 ambiguous probes are IRIS's 404:noform; the check list now forbids such a mark
- 2026-10-30T08:03:08Z status=wontfix-accepted owner=29-3-the-demo-host-is-adapted-for-the-launch by=cr note=reopen_if=the Planner's mark is a body text, or a host run passes a block-* probe that the host is found to let through
### DW-430: Test.Eval.Incident.Begin is the fifth private copy of the bridge-context Begin helper (Test.Eval.Checks, Test.Tools.Reminders, Test.Watch.Case have their own)
- source: spec-9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Incident.cls Begin(owner,itemId,kind,provenance) repeats Test.Eval.Checks.Begin's 8 lines with kind/provenance as arguments; the shared home (Test.Data.Fixture) is contended
- 2026-10-30T10:50:46Z status=wontfix-accepted owner=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=cr note=reopen_if=a bridge-context Begin helper lands in a shared test fixture, or a sixth private copy is added
- 2026-10-30T10:50:55Z status=wontfix-accepted owner=9-6-incident-cases-are-diagnosed-through-incidentmanager-and-rea by=cr note=count corrected: fourth copy (Checks, Reminders, Watch.Case, Incident); reopen_if=shared Begin helper lands or a fifth copy appears

### DW-431: The spine's AD-22 'CI as built' record says live:cards runs in install-fresh and live:audit in install-upgrade; the CI rebalance of 2026-10-30 (owner decision planner_ci_rebalance, carried by Story 9.6) moved live:cards to shards and live:audit to shards-2
- source: orchestrator: owner decision planner_ci_rebalance (Contest Planner under the owner's delegation), relayed 2026-10-30 | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ci/units.sh group_units after Story 9.6: shards = shard:lane-a@Checks,Install,Watch live:floor live:cards; shards-2 = shard:lane-a@rest live:audit; ARCHITECTURE-SPINE.md AD-22 CI-as-built bullet (DW-407's text) still names the old homes
- 2026-10-30T10:59:46Z status=decision-pending owner=burndown by=lead note=for the decision sheet: the orchestrator writes AD-22's as-built CI line at Epic 9's merge gate, as for DW-407 (no worktree spine edit)
- 2026-10-30T11:47:02Z occurrence=9-5-release-candidates-pass-the-evaluation-and-the-demo-incident by=spec_gate note=also for the orchestrator at the merge gate: Story 9.5's proposed AD-22 as-built bullet 'The release-candidate run (Story 9.5)' (text in spec-9-5's Design Notes, Proposed spine text); write it only once 9.5 is done and only as built
- 2026-10-30T16:16:12Z occurrence=9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=spec_gate note=also: Story 9.10's proposed AD-22 as-built text (spec-9-10 Design Notes); write it only once 9.10 is done and only as built
- 2026-10-31T07:17:56Z status=resolved-by:9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=merge_gate note=the_orchestrator_wrote_AD-22's_as-built_lines_at_Epic_9's_merge(live:cards_in_shards,live:audit_in_shards-2;the_9.5_and_9.10_bullets),checked_against_ci/units.sh

### DW-434: eval/run.sh --release-candidate keeps ANTHROPIC_API_KEY in the environment of lib-live's ensure_web_bundle, so in a checkout without the web bundle npm ci's install scripts and the web build run with the real key
- source: spec-9-5-release-candidates-pass-the-evaluation-and-the-demo-incident.md | severity: low | fix-risk: low | footprint: in-story
- evidence: eval/run.sh checks the key (:164) and then stack_start -> live_start -> ensure_web_bundle (docker/tests/lib-live.sh:88, :160-189) runs npm --prefix web ci and run build when web/node_modules or src/ocutalon/csp/index.html is missing, with the script's whole environment.
- 2026-10-30T14:35:15Z status=decision-pending owner=burndown by=cr note=veto window (secret handling): recommend building the bundle in a subshell with the key unset before stack_start
- 2026-10-30T15:43:03Z status=routed owner=9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=owner note=decided by the owner's delegate in U-166 (at=2026-10-30T12:43:19Z#503), applied through the orchestrator's ruling: fold into Story 9.10 (build the web bundle with the key unset before stack_start); no longer for the decision sheet
- 2026-10-30T20:45:09Z status=resolved-by:9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=adjudication note=eval/run.sh runs preflight, then builds the web bundle in a subshell with ANTHROPIC_API_KEY unset, then sets LIVE_REBUILD_WEB=0 before stack_start, so npm ci and the web build never see the key while the stack's compose calls still do; pinned by test-eval-set.sh rc-stack (every npm call records the key unset, with the bundle forced to rebuild); commits 22204007, c77f8fe5

### DW-435: Eval.Gate.SampleFields repeats DiagnosisPayload.CheckFix's sample-field loop (the keys of EvidencePack.FromInput(...).sample.body, 6 lines) instead of one shared EvidencePack helper
- source: spec-9-5-release-candidates-pass-the-evaluation-and-the-demo-incident.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: src/ocutalon/cls/OcuTalon/Eval/Gate.cls:118-124 and src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls:92-98; the spec names the sibling but gives no reason not to share it; Watch/** is outside Epic 9's footprint.
- 2026-10-30T14:35:19Z status=wontfix-accepted owner=9-5-release-candidates-pass-the-evaluation-and-the-demo-incident by=cr note=reopen_if=CheckFix or EvidencePack.FromInput changes which fields Decide's reply check reads (diff the two loops)
### DW-419: A resend that errs partway counts the targets it never reached as Skipped, so its result reads 'had changed since the dry run', which is false; it must report them by how far the run got (AD-16 as amended for U-160)
- source: split from DW-368 at Epic 7's decision sheet (owner U-160) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: DW-368's 2026-10-29T13:12:01Z occurrence trailer (7.4 code review): a resend that errs partway leaves its unreached targets Skipped and renders them as changed since the dry run
- 2026-10-30T05:24:59Z status=routed owner=30-5-mixed-and-unfinished-resends-say-how-far-they-got by=merge_gate note=owner U-160 (a) via the Contest Planner: fix in 30.5; the result text never claims a change that did not happen

### DW-420: AD-22's as-built shard list does not name the lane-a area Channel that Story 12.1 adds to ci/units.sh
- source: spec-12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: spine AD-22 'CI as built' lists lane-a: Agent, Bridge, Checks, Fix, Install, Tools, Digest and Watch; Story 12.1 appends Channel to ci/units.sh lane-a (Epic 9 appends Eval to the same line)
- 2026-10-30T06:30:51Z status=escalated owner=burndown by=spec_gate note=AD-22 as-built: lane-a gains Channel; orchestrator writes it at the merge gate (ruling 2026-10-30, Q3)
- 2026-10-31T13:34:35Z occurrence=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano

### DW-421: The CI mock's Bot API side keeps one global state (updates, replies, calls, counters) for every client, so once TelegramIn polls in CI a direct-call test such as Test.Contract.Mock.TestTelegramBotApi shares its queue and call list with the live poller
- source: spec-12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: ci/mock/mock.mjs one tg state; Test/Contract/Mock.cls TestTelegramBotApi resets then expects update_id 1 and its own 3 calls; Lane A's Test.Channel.BotApi.Reset clears TelegramIn's kept offset with its own resets only (Story 12.1 re-plan); reachable from Story 12.7 (Included() 1 at every CI start)
- 2026-10-30T06:46:50Z status=escalated owner=burndown by=spec_gate note=Lane B mock ask under AD-33 (AD-22): keep the Bot API state per token (keyed by the /bot<token>/ segment, control routes naming the token), or have TestTelegramBotApi stop TelegramIn around itself and read its ids from updateIds; optional: a status output on BotCall so Lane A's BotReply copy can go; DW-370 residual (orchestrator ruling 2026-10-30, Q2)
- 2026-10-30T08:35:22Z occurrence=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram

### DW-422: TelegramIn's kept update offset ($$$EnsStaticAppData("TelegramIn", "offset")) is pinned only against Test.Channel.BotApi, so a Story 12.2 poller that kept its offset elsewhere would leave DW-370's Lane A half doing nothing
- source: spec-12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Test.Channel.TelegramMock.TestResetClearsKeptOffset sets, reads and clears the node through BotApi alone; TelegramIn is still the stub (12.1 build-auto deferred)
- 2026-10-30T07:40:55Z status=routed owner=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=harvest note=Story 12.2's tests prove its poller's offset node is BotApi.Offset()'s node (Test.Channel.BotApi.Reset clears it with each mock reset)
- 2026-10-31T13:36:45Z status=resolved-by:12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=adjudication note=Test.Channel.TelegramIn.TestOffsetNode (dd849271 plus review patches): the offset BotApi.SetOffset sets is carried by the first getUpdates (offset 3), only the update at it is handled, and the node moves to 4; mutation keeping the offset at EnsStaticAppData(TelegramIn,next) turns it red (spec Verification)

### DW-428: Test.Channel.TelegramMock calls Test.Contract.Mock and Test.Channel.BotApi through $ClassMethod string names in three tests (##class in the other two), so a renamed helper shows only when the class runs
- source: spec-12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram.md | severity: low | fix-risk: low | footprint: in-story
- evidence: TelegramMock.cls TestCallsAndLog, TestResetClearsKeptOffset, TestPollerCheck use $ClassMethod(mock|helper, "<name>", ...); TestUpdateScenarios and TestReplyScenarios use ##class; about 29 mechanical lines to align
- 2026-10-30T08:35:22Z status=wontfix-accepted owner=12-1-telegram-stays-off-without-a-token-and-ci-mocks-the-telegram by=cr note=reopen_if=a renamed Mock or BotApi helper first shows as a TelegramMock red in CI, not at compile (not a two-way door)
### DW-480: README opening (owner text) 'Every decision is in Visual Trace with its reasons and cost' may read as an overclaim for a fixed-rules decision, which keeps only its fallback reason (Reasons empty, FallbackReason set)
- source: _bmad-output/implementation-artifacts/spec-10-4-the-readme-opens-with-what-ocutalon-is-for-and-what-a-model.md | severity: low | fix-risk: high | footprint: in-story
- evidence: Decide.cls RecordFallback sets Reasons='' and FallbackReason=reason; Result carries Fallback, FallbackReason, tokens and CostUSD; README.md:3 opening, README.md:34 Story 10.2 line
- 2026-10-31T09:28:00Z status=open owner=10-4-the-readme-opens-with-what-ocutalon-is-for-and-what-a-model by=harvest note=owner's word-for-word text: never edited by this story; adjudicated at ledger_adjudicated
- 2026-10-31T10:00:28Z status=by-design by=adjudication note=spec-bound_owner_text(Story_10.4_word_for_word,never_edited). Build check: a fixed-rules decision's Result still carries Fallback, FallbackReason (its reason) and the usage and CostUSD fields in its Visual Trace XML (Bridge/Msg/Result.cls, Decide.cls RecordFallback), so 'with its reasons and cost' reads as the fallback reason and the turn's cost; CR found no contradiction. The Story 10.2 line is README.md:36 (not :34). Reported to the orchestrator for the Contest Planner in the contract notes

### DW-481: Story 10.2's Given line ('right after Try it in two minutes') and first criterion ('it starts with Try it in two minutes') predate Story 10.4's opening and teaser above that heading
- source: spec-10-4-the-readme-opens-with-what-ocutalon-is-for-and-what-a-model.md | severity: low | fix-risk: low | footprint: in-story
- evidence: epics.md:3540 Given 'the top of the README, right after Try it' vs :3545 teaser 'above Try it'; :3523 'it starts with Try it'; text per Design Note 3
- 2026-10-31T09:58:52Z status=by-design owner=10-4-the-readme-opens-with-what-ocutalon-is-for-and-what-a-model by=cr note=spec-bound: Design Note 3 text and decided-in-stage (e); the lead may add a marker at its gate
### DW-429: flake: live:online-session web/e2e-online/session/leave.spec.ts L2 (600 s idle frees the place) went red once in CI with since=NaN in the freed page's URL and passed on an unchanged rerun
- source: CI run 41027546659 (OCT-epic29 468654f, iris install-fresh) | severity: med | fix-risk: low | footprint: in-epic
- evidence: attempt 1 red (expectPlaceFreed: since parsed NaN after landedOn matched ?since=), attempt 2 green on the same sha; Story 29.3 changed no web or product code
- 2026-10-30T10:02:36Z status=routed owner=burndown by=runner note=flake class: one rerun; priority for the burn-down (Epic 29 owns web/e2e-online/**); likely a clock-install race in the URL read (inference)
- 2026-10-31T03:39:09Z owner=29-9-epic-29-burn-down by=burndown note=chartered into Story 29.9 (Epic 29 burn-down) at the burn-down gate
- 2026-10-31T06:01:21Z status=resolved-by:29-9-epic-29-burn-down by=adjudication note=L2 (leave.spec.ts) and L7 (idle-activity.spec.ts) cross the idle cap with the wall clock, so the group sign-out's 3 s bound is real time; AC2 mutation zz L2 old red in expectPlaceFreed (since NaN) with the sign-out held 1.5 s, L2 and L7 green

### DW-432: flake: live:online-allowance D1 missed S1's daily-cap banner: StatusMonitor (counts the Usage spend) can publish dailyCap before S1's /state, which a web process computes from the day's mark alone, and the later mark is no change to the monitor
- source: spec-29-4-sessions-stay-isolated-under-load.md | severity: med | fix-risk: med | footprint: in-epic
- evidence: 29.4 QA run: D1 red at S1's banner after cappedMarked(day) passed, unchanged rerun 10/10; Budget.State counts Usage rows only in a privileged process; StatusMonitor publishes on change only
- 2026-10-30T13:09:59Z status=routed owner=burndown by=cr note=pre-existing, not 29.4's D1 edits (cappedMarked(day) passed first); fix: align the counts or sign S1 in before the seed
- 2026-10-31T03:39:09Z owner=29-9-epic-29-burn-down by=burndown note=chartered into Story 29.9 (Epic 29 burn-down) at the burn-down gate
- 2026-10-31T04:03:11Z owner=31-3-the-readme-leads-to-the-demo-and-the-launched-demo-is-measur by=burndown note=overflow (declined by Story 29.9's plan): not a test flake but a product gap: a web process cannot read the day's Usage rows (no SQL privilege), so its /state misses the counted spend StatusMonitor sees; a visitor arriving between the spend reaching the cap and the day being marked never gets the daily-cap banner live; a story that makes /state and StatusMonitor agree owns it; until then D1 stays under the one-rerun flake rule

### DW-433: The CI mock's guide-watch scenario (ci/mock/scenarios/B/guide-watch.json) answers the guide's watch prompt with text only and calls no start_watch, so under the mock the guide's watch button starts no watch and makes no Orders check (UJ-1 step 2)
- source: spec-29-4-sessions-stay-isolated-under-load.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: 29.4 implement: the guide press got a text reply, no check row, and Break the feed answered 409; the second visitor sends [[mock:watch-start-orders]] instead (Decided in-stage 0)
- 2026-10-30T13:10:06Z status=routed owner=burndown by=cr note=for UJ-1 step 2 under the mock (11.1's 02-watch and the online run's step 2); re-own to 11.1 at the burn-down
- 2026-10-31T03:39:09Z owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test by=burndown note=overflow: the mock's guide-watch reply starting no watch blocks UJ-1 step 2 under the mock; Story 11.1 turns the demo path's steps 2-5 on

### DW-441: The address key and every counter row's hash are also written to the private database's journal while the instance runs
- source: spec-29-5-the-address-counter-s-hash-is-keyed-per-reset.md | severity: low | fix-risk: high | footprint: in-story
- evidence: Key() sets KEYGLOBAL with an ordinary global set in OCUTALON_PRIVATE, which journals by default (inference), and ReferenceHits scans globals, not journal files. Spec Decided in-stage 8 records it: the journal sits on the durable volume and goes with it at each reset (inference); U-156 puts the key in the private database.
- 2026-10-30T16:03:44Z status=by-design owner=29-5-the-address-counter-s-hash-is-keyed-per-reset by=cr note=spec-bound (Decided 8, U-156); fix-risk high: disabling journaling needs a privilege the demo account lacks

### DW-442: H17's capture check names ^OcuTalonP.AddrCountK literally, not through AddressCounter's KEYGLOBAL parameter
- source: spec-29-5-the-address-counter-s-hash-is-keyed-per-reset.md | severity: low | fix-risk: low | footprint: in-story
- evidence: release/demo-host-checks.md H17 prints $Data(^OcuTalonP.AddrCountK); if KEYGLOBAL ever moved, the host check would read an empty node and print 0. The spec's Tasks give H17's text verbatim, and TestKeyIsPrivate pins KEYGLOBAL to that literal, so a move fails a test first.
- 2026-10-30T16:03:44Z status=by-design owner=29-5-the-address-counter-s-hash-is-keyed-per-reset by=cr note=spec-bound: the spec gives H17's text; TestKeyIsPrivate pins the literal name

### DW-446: The probe reports healthy when every turn is an error fallback (a revoked real key, a provider 500 or a down gateway behind the demo's gateway), because degraded covers only no_key, timeout and rate_limited
- source: spec-29-6-the-probe-alerts-when-every-turn-falls-back.md | severity: med | fix-risk: low | footprint: in-story
- evidence: docker/probe.sh run_checks matches only daily_cap, no_key, timeout and rate_limited; Decide.Classify gives error to a failure without the cap, key, timeout or rate-limit text (a 401, a 500); H12: the host's IRIS holds a dummy key, so no_key needs a broken deploy; Story 29.6's So that: a demo whose replies are all fallbacks never reports healthy
- 2026-10-30T19:11:36Z status=decision-pending owner=burndown by=cr note=product call: should error also be degraded (alert-only)? U-157 named three; recommended: yes, like the three
- 2026-10-31T09:02:42Z status=routed owner=31-4-the-paired-chat-stays-isolated-under-load-too by=merge_gate note=veto_U-187:error_counts_as_degraded(alert_only,not_toward_the_reset),like_U-157's_three;with_a_probe_test

### DW-447: AD-25's probe bullet lists the outcomes busy, capped, auth_failed and no_decision, but the probe also has no_splash (Story 16.6) and degraded (Story 29.6, epic29_brief), and the spine does not record them
- source: spec-29-6-the-probe-alerts-when-every-turn-falls-back.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Spine AD-25, The probe: 'Its outcomes are busy ..., capped ..., auth_failed ... and no_decision'; docker/probe.sh's outcome table also has no_splash and degraded (alert-only, never counted); the spec's Design Notes hand the amendment to the lead (Rule 20)
- 2026-10-30T19:11:36Z status=escalated owner=burndown by=cr note=for the decision sheet: an AD-25 as-built line adding no_splash and degraded, keeping the id (Rule 20, the lead's)
- 2026-10-31T09:02:42Z status=resolved-by:29-6-the-probe-alerts-when-every-turn-falls-back by=merge_gate note=AD-25's_probe_outcomes_gain_no_splash(16.6)_and_degraded(29.6),as_built,checked_against_docker/probe.sh

### DW-458: AD-3's public-package reference check (Test.Web.Status, TestReferencesOnlyThePublicAllowList) reads no global reference, @ indirection or Xecute, so it cannot see Status.Visitors' read of ^%cspSession or a later global read
- source: spec-29-7-demo-busy-counts-the-live-visitors.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Story 29.7 adds the public package's first global read (Web/Public/Status.cls Visitors, by indirection on its store argument); the check scans ##class, $SYSTEM and dynamic calls from the class dictionary only (spec Code Map). The public account still holds no read on any private database.
- 2026-10-30T23:36:35Z status=wontfix-accepted owner=29-7-demo-busy-counts-the-live-visitors by=cr note=reopen_if=a Web.Public or Data.Public class reads a global other than ^OcuTalonPublic and ^%cspSession

### DW-463: In one throwaway run of Story 29.8's L2 the connection reading after the one more visitor was one lower than the peak of the visitors' trace pages (6/2 against 7/2), so a trace connection may end within seconds of its last page
- source: spec-29-8-the-author-s-load-run-measures-the-demo-s-capacity.md | severity: low | fix-risk: low | footprint: in-story
- evidence: first live run of the load phase: 3/2, 5/2, 7/2 after visitors 1-3, 6/2 about 5 s later after the one more visitor; later runs not reproduced
- 2026-10-31T02:35:19Z status=wontfix-accepted owner=29-8-the-author-s-load-run-measures-the-demo-s-capacity by=harvest note=reopen_if=the host's H25 load run, or a throwaway reading the units every 2 s for 2 minutes after the last trace page, shows a trace connection ending before the ~120 s timeout; the script reports the peak as the load reading

### DW-464: H8's busy page in place of a 503 is never exercised by run 3 during the load run's --hold
- source: spec-29-8-the-author-s-load-run-measures-the-demo-s-capacity.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: During case 1's hold busy comes from the visitor count, and IRIS serves its own busy splash (200, X-OcuTalon-Busy); IRIS answers 503 only at the cap of 8 connections (AD-13), and case 2 peaks at 6. Run 3 accepts IRIS's splash by Story 29.3's design, so H8 can read measured with the proxy's 503 mapping unexercised.
- 2026-10-31T03:28:16Z status=decision-pending owner=burndown by=cr note=product call: how H8's 503 mapping is shown on the host; the check list and the spec say only 'during the hold'
- 2026-10-31T09:02:42Z status=decision-pending owner=burndown by=unattended note=inbox=U-188
- 2026-10-31T09:04:17Z status=wontfix-accepted owner=burndown by=owner note=U-188_decided_by_the_Contest_Planner(cross-session,2026-10-31):H8_shown_in_two_parts_on_the_host:IRIS's_busy_splash_during_case_1's_hold(run_3_accepts_X-OcuTalon-Busy:1);the_proxy's_503_mapping_exercised_once_at_the_true_cap_at_the_end_of_case_2(two_more_trace_sessions_to_8;/ocutalon/_gets_the_busy_page_with_X-OcuTalon-Busy-Page;/ocutalon/api/_passes_the_503);else_the_Oct_30_busy_test_plus_the_proxy_rule;no_repo_change

### DW-465: A change to release/demo-load.sh alone runs every IRIS CI group
- source: spec-29-8-the-author-s-load-run-measures-the-demo-s-capacity.md | severity: low | fix-risk: med | footprint: in-story
- evidence: IRIS_INPUT gains release/demo-load.sh, and group_input_pattern puts IRIS_INPUT into all seven groups; only live:online-demo-path (shards-2) runs the script.
- 2026-10-31T03:28:16Z status=by-design owner=29-8-the-author-s-load-run-measures-the-demo-s-capacity by=cr note=spec-bound: Tasks (IRIS_INPUT gains release/demo-load.sh) and Design Notes, CI; a per-unit input would scope it to shards-2

### DW-466: After a signal, a second Ctrl-C is ignored while demo-load.sh signs everyone out
- source: spec-29-8-the-author-s-load-run-measures-the-demo-s-capacity.md | severity: low | fix-risk: low | footprint: in-story
- evidence: on_signal sets trap '' INT TERM HUP, then signs out each visitor with up to 5 requests of 30 s each; against a host that stops answering the cleanup can take minutes and cannot be interrupted short of kill -9.
- 2026-10-31T03:28:16Z status=wontfix-accepted owner=29-8-the-author-s-load-run-measures-the-demo-s-capacity by=cr note=reopen_if=an H25 run stays on 'interrupted: signing everyone out' for more than 2 min

### DW-467: A phone createdAt in another form makes demo-load.sh wait 120 s and fail as no notice
- source: spec-29-8-the-author-s-load-run-measures-the-demo-s-capacity.md | severity: low | fix-risk: low | footprint: in-story
- evidence: notice_seen's jq errors on a createdAt that is not UTC YYYY-MM-DDTHH:MM:SS[.f]Z, with stderr discarded, so poll_until runs to its limit and the reason reads 'no notice in 120 s'.
- 2026-10-31T03:28:16Z status=wontfix-theoretical owner=29-8-the-author-s-load-run-measures-the-demo-s-capacity by=cr note=real if the server's phone createdAt ever carries an offset or another form (T0-b: UTC, whole seconds)

### DW-468: A line break in a server string adds key lines to a demo-load.sh visitor's result file
- source: spec-29-8-the-author-s-load-run-measures-the-demo-s-capacity.md | severity: low | fix-risk: low | footprint: in-story
- evidence: setv writes key=value lines unescaped; an incident state, fallback reason or error code holding a line break would add lines that getv reads as the latest value of another key.
- 2026-10-31T03:28:17Z status=wontfix-theoretical owner=29-8-the-author-s-load-run-measures-the-demo-s-capacity by=cr note=real if /state's incident state or fallbackReason, or an API error code, ever carries a line break (enums today)
### DW-445: ci/iris.sh teardown counts a leftover container, volume, network or image only when its removal succeeds, so an object it cannot remove reads as zero leftovers
- source: spec-9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: ci/iris.sh:555-566 cmd_teardown increments c/v/n/i only inside if docker rm ...; then; found by Story 9.10's implement review
- 2026-10-30T18:25:27Z status=wontfix-accepted owner=9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=harvest note=Story 9.10's proof checks docker ps -a and docker volume ls by its project itself, so it does not rely on the count; reopen_if=a teardown line reports 0 leftovers while docker ps -a or docker volume ls still show the tag's project

### DW-448: The key proof's globals scan (Test.Eval.KeyProof Walk) and its raw container-file grep match the key only as contiguous 8-bit bytes of one node, so a key inside a zstd-compressed %Stream.Global* chunk, a 16-bit $List element or split across stream chunks reads as clean
- source: spec-9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g.md | severity: med | fix-risk: high | footprint: in-story
- evidence: Walk tests reference [ value and data [ value per node (KeyProof.cls Walk); %Stream.GlobalCharacter has COMPRESS=1 and TmpCharacter compresses a block of 1 KB or more (irislib/%Stream/TmpCharacter.cls:889); the demo-case control cannot detect it; found by code review (blind, edge, acceptance layers)
- 2026-10-30T20:42:31Z status=escalated owner=burndown by=cr note=for the user: decode $List elements (cheap) and compressed stream chunks (needs a measurement of the storage on a throwaway); the same walk is copied in Test.Web.SessionEvents.ReferenceHits
- 2026-10-31T07:17:56Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=merge_gate note=Epic_9_decision_sheet,veto_U-185:decode_$List_elements_in_Test.Eval.KeyProof_Walk;measure_on_a_throwaway_whether_a_message_body_can_store_a_key_in_a_compressed_or_split_%Stream.Global*_chunk(yes:decode;no:that_half_wontfix-accepted_with_the_measurement);Lane_B's_copy_is_its_own_entry_for_31.4
- 2026-10-31T07:25:04Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=owner note=U-185_kept(#558):a_wontfix-accepted_close_of_the_compressed/split-chunk_half_records_the_evidence(throwaway_build,message_class,what_was_stored);the_key_proof_otherwise_unchanged

### DW-449: project_leftovers puts the eval harness's container listing (docker ps -a, docker volume ls) in docker/tests/lib-keys.sh, a third library beside ci/iris.sh and lib-live.sh that the eval-scripts rule does not cover, and repeats cmd_teardown's name listing with its own matching
- source: spec-9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: lib-keys.sh project_leftovers; ci/iris.sh is read-only for Story 9.10, so the [Lead] item's listing could not live in cmd_teardown; both calls use --format (AD-22 holds); found by code review (blind, acceptance layers)
- 2026-10-30T20:42:31Z status=wontfix-accepted owner=9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=cr note=reopen_if=a second caller of project_leftovers outside eval/key-proof.sh, or a container-tool call in lib-keys.sh without --format, or ci/iris.sh gains a leftovers subcommand

### DW-450: Test.Eval.KeyProof Walk copies the global walk of Test.Web.SessionEvents.ReferenceHits (about 8 lines: the extended reference, $Data of the root, then $Query with data) instead of sharing one helper
- source: spec-9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: KeyProof.cls Walk vs SessionEvents.cls ReferenceHits :590-598; the spec records the reason (Test/Web is contended by Epic 29, and the sibling walks one namespace by location); no story in Epic 9 touches Test/Web; found by code review (Rule 2)
- 2026-10-30T20:42:31Z status=wontfix-accepted owner=9-10-the-release-candidate-run-proves-the-key-leaks-nowhere-and-g by=cr note=reopen_if=either walk changes how it matches a node (for example the decoding of the escalated globals-scan entry) and the other does not

### DW-474: Test.Web.SessionEvents.ReferenceHits copies the release candidate's key-proof walk (DW-448); apply Story 30.1's $List decode, and any stream-chunk decode its measurement calls for, to this Lane B copy too
- source: orchestrator: Epic 9 decision sheet (DW-448 split, veto U-185) | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Test.Web.SessionEvents.ReferenceHits mirrors Test.Eval.KeyProof Walk (DW-448's evidence)
- 2026-10-31T07:17:56Z status=routed owner=31-4-the-paired-chat-stays-isolated-under-load-too by=merge_gate note=Lane_B_half_of_DW-448;after_Story_30.1_settles_the_decode;veto_U-185

### DW-482: Test.Install.Production class doc (line 10): its list of items that carry no STUB (so the oracle marks them stub 0) does not yet name TelegramIn and TelegramOut, which Story 12.2 builds
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Story 12.2 sets the TelegramIn and TelegramOut oracle rows to stub 0 (orchestrator ruling 2026-10-31, file-level extension); the doc line 10 edit was dropped because Epic 15 also changes line 10 of src/ocutalon/cls/OcuTalon/Test/Install/Production.cls
- 2026-10-31T11:52:15Z status=routed owner=15-3-an-ipm-install-survives-restarts-and-reinstalls-and-every-re by=orchestrator note=doc only: append TelegramIn and TelegramOut (built in Story 12.2) to the class doc's list of items without STUB, in the same edit as Epic 15's own line-10 change; no behaviour

### DW-486: TelegramIn calls Pairing.RecordChat(chatId, "") for every private update, and RecordChat sets DisplayName unconditionally, so once Story 12.4 stores a paired chat's name every later message would blank it
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: Data/Pairing.cls RecordChat sets row.DisplayName = name unconditionally; Channel/Telegram/In.cls HandleUpdate passes an empty name (as 12.2's spec fixes it); no story stores a name yet, so nothing is lost today (dd849271)
- 2026-10-31T12:13:11Z status=routed owner=12-4-a-valid-code-pairs-the-chat-with-the-session by=harvest note=fix on Epic 12's side if possible (TelegramIn passes the update's own name, or skips the name when it is empty); Data/Pairing.cls is Lane B's (AD-33) and contended with Epic 11, so a change there is a Lane B ask
- 2026-11-01T07:40:52Z status=resolved-by:12-4-a-valid-code-pairs-the-chat-with-the-session by=adjudication note=TelegramIn_keeps_chat.first_name_only_while_paired(never_blanks_a_paired_name;clears_an_unpaired_row);pinned_by_Test.Channel.TelegramPair.TestNameOnlyWhilePaired(a-d);Data/Pairing.cls_untouched;commit_72017ebd+review_patches

### DW-487: A Bot API call can outlast the 10-second item stop on a slow network: OpenTimeout inherits the read Timeout, and sendMessage reads 15 s
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Api.Call sets only Timeout, which %Net.HttpRequest also uses for the connect (HttpRequest.cls:1257,1664): up to 8+8 s for getUpdates, 15+15 s for sendMessage; CI's local mock never shows it
- 2026-10-31T13:34:35Z status=wontfix-accepted owner=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=cr note=reopen_if=a TelegramIn or TelegramOut stop over 10 s is logged on a real network (12.7 hands-on pass or the demo host)

### DW-488: A TELEGRAM_BOT_TOKEN with surrounding white space or a CR (an env file with CRLF) counts as set and goes into the /bot<token>/ path unchanged
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: low | fix-risk: med | footprint: in-story
- evidence: Install.Step.Telegram.TokenSet only tests for an empty value and Api.Call uses GetEnviron as is; trimming is token handling (a veto area), so it was not changed in review
- 2026-10-31T13:34:35Z status=wontfix-accepted owner=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=cr note=reopen_if=an install with a right token shows Telegram rejected or failing, and the variable holds white space or a CR

### DW-489: Two names are written twice: the client SSL configuration (Api.SSLCONFIG and Install.Step.SSL.NAME) and the token variable (Api.TOKENVAR and Install.Step.Telegram.TOKENVAR)
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: low | fix-risk: med | footprint: in-story
- evidence: a rename in one class only turns TelegramSettings (SSLConfig resolves to OcuTalonClient, which exists) or TelegramSwitch and the live tests red; unifying needs a cross-class parameter in a contended Install file
- 2026-10-31T13:34:35Z status=wontfix-accepted owner=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=cr note=reopen_if=either name changes in one place, or a second client of OcuTalonClient (the email story) adds a third copy

### DW-490: test-ci-config.sh scans only the live:* entries of NO_WEB_BUNDLE_UNITS for bundle markers, so shard:lane-a@Channel, the first shard unit there, has no ongoing guard
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: docker/tests/test-ci-config.sh:1045-1055 greps the bundle markers under case live:*); Story 12.2 recorded a one-time grep of Test/Channel in its Verification; the check script is not Epic 12's
- 2026-10-31T13:34:35Z status=wontfix-accepted owner=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=cr note=reopen_if=a Test.Channel class reads a file of the built bundle (a grep of Test/Channel for csp/, index.html or ensure_web_bundle hits)

### DW-491: Test.Contract.Ac (TestTelegramStubHasAnAdapter) and Test.Msg.Contracts (line 136) still call TelegramIn the stub, and Ac.cls says that the Telegram epic replaces the value
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Story 12.2 built TelegramIn and TelegramOut, which carry no STUB; the two docs are outside Epic 12's footprint and their assertions still hold
- 2026-10-31T13:34:35Z status=wontfix-accepted owner=12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano by=cr note=reopen_if=either class is edited, or a later plan cites TelegramIn as a stub from those docs
### DW-483: Decide falls back on the first invalid reply; one retry on an invalid reply (with the check's own error text in the retry) could recover a correct-but-malformed diagnosis, within NFR-7's diagnosis budget
- source: orchestrator: launch-risk hotfix Story 5.12 (Contest Planner: not now, a measured follow-up in Epic 30) | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: host Decision rows since the 11:36Z reset on fe1d81e2: diagnose 1 invalid of 9, decide 0 of 10, turn 0 of 10; Story 5.12 removes the one observed cause
- 2026-10-31T11:55:11Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=orchestrator note=measure first:_the_invalid_rate_after_5.12_and_the_retry's_cost_and_time;veto_item
- 2026-10-31T11:56:37Z status=routed owner=30-1-long-conversations-are-compacted-under-the-limit by=owner note=U-191_kept(#576):measure_the_invalid_rate_per_reply_kind_after_5.12(host_Decision_rows+Story_9.5's_real-key_run);build_the_retry_in_30.1_only_if_diagnose_still_falls_back_on_invalid_in_more_than_about_1_in_50,and_only_within_NFR-7's_20_s_diagnosis_budget

### DW-484: An agent-written reply time has no zone label: the chat's reminder reply reads 'Your reminder is set for 08:02 to stretch.' in the instance zone (ET on the demo), while the page shows the visitor's own time ('5:01 AM PDT', 'Due 5:02 AM'), so a visitor elsewhere sees three different clocks
- source: Contest Planner: demo host walk on fe1d81e2, 2026-10-31T12:01Z | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: the model writes the time into its reply text; catalog times carry the zone label (U-180's format), agent-written ones do not
- 2026-10-31T12:02:51Z status=routed owner=30-5-mixed-and-unfinished-resends-say-how-far-they-got by=orchestrator note=route_agent-written_times_through_the_catalog's_zone-labelled_format(Data.Time.ForMessage),or_have_the_chat_agent's_prompt_label_the_zone;1.0.0_if_cheap,else_defer(Planner)

### DW-485: release/demo-host-check.sh has no allow-hyperevent check, so run 1 passed while the host's S17 filter refused every Visual Trace hyperevent (WARGC, WEVENT, WARG_<n> to /ocutalon/trace/<app>/%25CSP.Broker.cls answered 400 'unexpected form field'), which broke demo step 5's message clicks; add a check that a hyperevent-shaped POST with dummy WARGC, WEVENT and WARG_1 to each trace application's %CSP.Broker.cls gets neither the block status nor the block mark
- source: Contest Planner: demo host pass on fe1d81e2, 2026-10-31 (host filter fixed host-side: on a decoded route ending in /%csp.broker.cls it also admits ^W(ARGC|EVENT|ARG_[0-9]{1,3})$) | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Visual Trace drew but every message click showed IRIS's 'error while loading this page' with empty Header, Body and Contents; after the host fix run 1 is 110/110 and the Header pane fills at a full house of six
- 2026-10-31T12:04:51Z status=routed owner=31-4-the-paired-chat-stays-isolated-under-load-too by=orchestrator note=also_check_that_the_repo's_proxy_stand-in(Story_29.3)_admits_the_broker-path_hyperevent_fields,and_record_the_allowance_as_built_beside_AD-25's_sign-in_rule

### DW-494: flake: OcuTalon.Test.Fix.Partial TestCopiesFailAgain ('and stores 3/3/0/3/0 with the reason the order date still wasn't accepted' and four more asserts) red in CI shards-2 (shard:lane-a@rest), green on an unchanged rerun
- source: spec-12-2-ocutalon-polls-and-writes-to-its-own-bot-and-pauses-when-ano.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: CI run 41207682542 attempt 1 (OCT-epic12 ec468c81, Story 12.2, no Fix change), iris shards-2: 5 asserts of TestCopiesFailAgain failed (57.4 s); attempt 2 green; the class passed on a fresh lane-C throwaway in 41 s; af47ff3c green on the same unit
- 2026-10-31T15:28:23Z status=routed owner=burndown by=ci note=flake class from now: one rerun with occurrence=; likely a wait in Fix.Partial under CI load (inference); Fix is Lane A, Epic 7's area (Fix/Executor.cls is contended with Epic 30)

### DW-499: The Telegram card's view module web/src/app/rail/telegram-card/telegram-card-view.ts has no Node unit test; its branches (missing status, missing or non-string time slot, state on) are pinned only by the browser tests T1 and T2
- source: spec-12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try.md | severity: low | fix-risk: low | footprint: in-epic
- evidence: Sibling view modules (banner-view, rail-view) have web/scripts/*-view.test.mjs; a new file under web/scripts/ is Lane B's (AD-29) and Story 12.8's ruling allows only three named entries; T1 and T2 cover paused, off, rejected and not paused (750cc54e)
- 2026-10-31T17:44:56Z status=wontfix-accepted owner=12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try by=harvest note=reopen_if=a card-state defect reaches CI or the page that T1/T2 did not catch, or Lane A gains its own web unit-test file for telegram-card (then add telegram-card-view.test.mjs there)

### DW-502: The Telegram card's paused predicate (telegram-card-view.ts holds() and the condition name telegramPaused) is a copy of banner-view.ts's private holds(), so a later change to the banner's rule would leave the card and the banner out of step
- source: spec-12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: A one-expression copy that the spec forces (Decided 1; banners/* is on the Never list, Lane B's under AD-29); T1 pins both together for today's rule; the unifying fix exports holds() from banner-view.ts, a Lane B file
- 2026-10-31T18:23:40Z status=wontfix-accepted owner=12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try by=cr note=reopen_if=banner-view.ts's holds() or its telegramPaused row changes, or a Lane B story exports holds(): then import it

### DW-503: UX-DR137 (the unpaired Telegram card at the top of the device column at 1024 to 1279 px) is carried by no story's acceptance criteria, and the column layout is Lane B's (AD-29)
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: found by Story 12.3's plan: the card's unpaired state is built in Lane A's telegram-card/, but its position in the device column at 1024-1279 px is the rail layout's (Lane B's web files); no story in epics.md names UX-DR137
- 2026-10-31T19:18:18Z status=escalated owner=burndown by=spec_gate note=for the decision sheet: route to a Lane B story (layout) or accept; not Epic 12's files

### DW-504: Lane B's web/scripts/qr-pin.test.mjs header says nothing in web/src uses qrcode-generator yet, which Story 12.3's card makes untrue
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Story 12.3 draws the pairing QR code with the vendored qrcode-generator 2.0.4 in web/src/app/rail/telegram-card/; the comment is Lane B's file
- 2026-10-31T19:18:18Z status=wontfix-accepted owner=12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code by=spec_gate note=reopen_if=Lane B next edits qr-pin.test.mjs (update the header then), or the comment misleads a reviewer

### DW-508: flake: web/e2e/floor/guide.spec.ts:253 M4 ('the page holds the earlier progress event': 'zz M Orders again' not visible in the Status region within 15 s) red in CI shards live:floor, green on an unchanged rerun
- source: spec-12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try.md | severity: med | fix-risk: med | footprint: out-of-footprint
- evidence: CI run 41230579974 attempt 1 (OCT-epic12 a634857d, Story 12.8; no guide, rail or watch change), iris shards, live:floor M4; attempt 2 green; live:floor passed locally 105/105 on a fresh lane-C stack
- 2026-10-31T19:42:02Z status=routed owner=burndown by=ci note=flake class from now: one rerun with occurrence=; guide.spec.ts and the Status region are Lane B's (Epic 4/8 area); possibly a real tick or watch.progress ordering under CI load (inference)

### DW-512: A browser clock ahead of the server's by ten minutes or more makes the Telegram card replace its pairing code every 10 s, captioned 'New code in 1 min'
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: low | fix-risk: med | footprint: in-story
- evidence: telegram-card-view.ts dueTime compares the server's expiresAt with the browser clock; the 10 s spacing bounds the requests (Boundaries 'The spacing', Decided 4; matrix row 2 expects '1 min' for a past expiry)
- 2026-10-31T23:27:23Z status=by-design owner=12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code by=cr note=spec-bound: the spacing rule is the specified guard; a server-relative lifetime would change the Boundaries' due-time formula

### DW-513: A 409 that the code route gives only briefly (TelegramIn restarting) keeps the Telegram card on 'Telegram not set up' until /state's Telegram values or the pause change
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: low | fix-risk: low | footprint: in-story
- evidence: telegram-card.ts records refusedAt under the asking key and never re-asks for that key; no live event carries the server's state (Decided 2)
- 2026-10-31T23:27:23Z status=by-design owner=12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code by=cr note=spec-bound: Decided 2 (a stale page never polls a refusing route); a reload shows the real state

### DW-514: Two tabs of one session each show an unpaired Telegram card, and each code request replaces the session's one code (AD-4), so the other tab's QR code is dead until its own refresh
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: med | fix-risk: med | footprint: in-story
- evidence: Pairing.StoreCode keeps one code row per session (CodeSessionRefIndex unique) and each card asks on its own; scanning the older tab's code gets Story 12.5's 'That code didn't work'
- 2026-10-31T23:27:33Z status=decision-pending owner=burndown by=cr note=product call: accept (AD-4, the code never leaves the card), only the visible tab asks, or another rule; a cross-tab share breaches the spec's 'sends it nowhere'

### DW-515: The Telegram card's long-timer and refusal-reset rules are pinned by no test: the 30 s retry after a non-409 failure, the 409 stop beyond T4's 3 s window (the 10 s spacing makes that window unable to fail), and the refusal forgotten when a pause starts and ends
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: low | fix-risk: low | footprint: in-story
- evidence: telegram-card.ts ask()/later() and the askKey effect; pinning needs a 31 s wait or a live-event route on a refused page, and page.clock is excluded (Decided 9) while the browser group runs about 25 min
- 2026-10-31T23:27:33Z status=wontfix-accepted owner=12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code by=cr note=reopen_if=a card asks after a 409, never retries after a 5xx, or stays not set up after a pause clears, in CI or on a page; or Lane A gains a web unit-test host

### DW-516: TelegramPageFixture.Finish keeps a code row that existed at Start, so when an earlier Finish failed and left the README session's code row, the page's codes overwrite that row and it stays with the test's last code hash
- source: spec-12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code.md | severity: low | fix-risk: low | footprint: in-story
- evidence: Pairing.StoreCode reuses the session's row (CodeSessionRefIndexOpen), and DropCodes keeps every Ref Start saved; mutation M5 showed it (T1's leftover row survived T3's Finish)
- 2026-10-31T23:27:33Z status=wontfix-accepted owner=12-3-the-telegram-card-shows-a-fresh-pairing-code-as-a-qr-code by=cr note=reopen_if=Start finds a code row of the test's own session, or a later test reads the README session's code row

### DW-520: SessionOps.Unlink keeps DisplayName in a row it unpairs, so an unpaired Pairing row holds a name until that chat writes again (Lane B ask: clear DisplayName on unlink)
- source: _bmad-output/implementation-artifacts/spec-12-4-a-valid-code-pairs-the-chat-with-the-session.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: Core/SessionOps.cls Unlink clears SessionRef and SeenAt only; TelegramIn (12.4) clears the name on the chat's next update; the name never reaches a production message, /state of another session or the trace
- 2026-11-01T06:58:27Z status=wontfix-accepted owner=12-4-a-valid-code-pairs-the-chat-with-the-session by=harvest note=reopen_if=a test or audit finds a DisplayName on a Pairing row with no SessionRef older than one update, or a Lane B story edits SessionOps.Unlink (then add the one-line clear)
- 2026-11-01T07:39:08Z occurrence=12-4-a-valid-code-pairs-the-chat-with-the-session

### DW-527: The Telegram card's state order (paused, not set up and paired ahead of just-unpaired) has no unit test: moving the justUnpaired branch above paired or paused keeps T5 and T6 green
- source: _bmad-output/implementation-artifacts/spec-12-5-bad-codes-a-bare-start-command-and-unpairing-get-polite-answ.md | severity: low | fix-risk: low | footprint: in-story
- evidence: telegram-card-view.ts:169 telegramCardView is framework-free; no web/scripts/*.test.mjs calls it; only T5/T6 run the just-unpaired view
- 2026-11-01T11:13:27Z status=open owner=12-5-bad-codes-a-bare-start-command-and-unpairing-get-polite-answ by=harvest note=runner ruling: a NEW test file web/scripts/telegram-card-view.test.mjs (Epic 12's own card view; not contended) is allowed and reported as a footprint extension; or pin it with a T6 case (a pairing during the 5 s window shows the paired row)
- 2026-11-01T12:06:25Z status=resolved-by:12-5-bad-codes-a-bare-start-command-and-unpairing-get-polite-answ by=adjudication note=web/scripts/telegram-card-view.test.mjs(10_cases;QA)_pins_paused,not-set-up,paired_ahead_of_just-unpaired_and_the_5000ms_window;mutations_moving_justUnpaired_above_paired(3_red)/paused(4_red)

### DW-528: A pairing that removes the focused Open in Telegram link sends focus to the main region, not the Telegram heading
- source: spec-12-5-bad-codes-a-bare-start-command-and-unpairing-get-polite-answ.md | severity: low | fix-risk: low | footprint: in-story
- evidence: The unpaired root of telegram-card.ts carries no data-row-key/data-section, so keepFocus finds no item and falls back to the main region when the paired view replaces it. EXPERIENCE Focus replacement says nearest container. Neither 12.4 nor 12.5 specifies focus on pairing, and it needs a T6 step plus a live run.
- 2026-11-01T12:04:51Z status=wontfix-accepted owner=12-5-bad-codes-a-bare-start-command-and-unpairing-get-polite-answ by=cr note=reopen_if=a keyboard pass (38.3 real-device or an a11y audit) finds focus outside the Telegram section after pairing

### DW-536: flake: web/e2e/demo-path/telegram-page.spec.ts T6 (Story 12.5): 'chat 113 is told that the code did not work' timed out (10 s poll for the bad-code reply) once on a fresh lane-C live:demo-path; the unchanged rerun passed
- source: _bmad-output/implementation-artifacts/spec-12-5-bad-codes-a-bare-start-command-and-unpairing-get-polite-answ.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: runner smoke of 12.6 (tag e12s6smk, 2026-11-01T17:30Z): 1 failed telegram-page.spec.ts:925 expect.poll repliesOf(STRANGER_CHAT) toEqual([BAD]) timeout 10000ms; rerun 19 passed
- 2026-11-01T17:35:48Z status=routed owner=burndown by=smoke note=flake class: one rerun with occurrence=; a second red on the same head takes the rework path; probe whether TelegramIn's poll plus Notify->TelegramOut can exceed 10 s under load, or the reply list read races the send

### DW-540: flake: web/e2e/demo-switch/mailbox.spec.ts:425 MB9 (a refused chip press shows the server message; page.waitForResponse hit the 120 s test timeout) red once in CI shards-2 live:demo-switch on OCT-epic12 b14f7527; the unchanged rerun passed
- source: _bmad-output/implementation-artifacts/cycle-log-epic-12.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: run 41334145441 job iris (shards-2) attempt 1: 1 failed (MB9, 2.0m); attempt 2 green; Epic 12 changed no mailbox or demo-switch code
- 2026-11-01T19:32:33Z status=routed owner=burndown by=ci note=flake class: one rerun with occurrence=; Lane B's (Epic 4 / Story 4.6) test; a second red on the same head takes the rework path
