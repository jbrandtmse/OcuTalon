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

### DW-10: Nothing reports that instance-wide auditing is off, so on such an instance (an IPM install into an existing instance) the six events register and no entry is ever written
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Bridge.Installer, Step.Audit and Bridge.Audit.Write never read Security.System AuditEnabled; build 154 has it on by default (measured), an existing instance may not
- 2026-10-19T08:48:58Z status=routed owner=3-7-every-action-and-governance-event-is-in-the-iris-audit-log by=harvest note=Audit step warns plainly (log warning + a status the security overview and README point to); never changes the setting (AD-17; Contest Planner 2026-10-19)

### DW-11: AC5 (each Storage block equals the compiler's output) is checked once by a load-compile-export round trip, not by a recurring CI check
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: test-storage.sh checks only that a Storage Default block exists and its DataLocation; a hand-edited block fails no test
- 2026-10-19T08:48:58Z status=routed owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=harvest note=the IRIS checks job runs the round trip and fails on any storage-block difference

### DW-12: Data.Time.ToLocal and Zone() read the process TZ; no test runs them in a production job started with the container's TZ (inference that jobs inherit it)
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: row 8 sets the test process TZ only; a wrong job TZ would show catalog and reminder times in the wrong zone
- 2026-10-19T08:48:58Z status=routed owner=0-9-the-message-catalog-and-its-one-renderer by=harvest note=Task 0 in 0.9: throwaway with a compose-level TZ, call ToLocal from a production job (0.6's stubs exist by then)
- 2026-10-19T09:48:41Z occurrence=0-4-the-cross-lane-message-and-data-contracts by=cr note=also: with TZ unset on a non-UTC host (IPM install outside the image) Zone() says UTC while ToLocal uses the OS zone
- 2026-10-19T09:51:16Z occurrence=0-4-the-cross-lane-message-and-data-contracts by=cr note=with TZ unset on a non-UTC host (IPM install outside the image) Zone() says UTC while ToLocal uses the OS zone

### DW-13: test-storage.sh treats only %Persistent, Ens.Request and Ens.Response as storage roots, so a business process or Ens.MessageBody subclass escapes the storage-block and DEFAULTGLOBAL checks
- source: spec-0-4-the-cross-lane-message-and-data-contracts.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: check.awk roots (test-storage.sh:54) omit Ens.BusinessProcess (persistent, irislib/Ens/BusinessProcess.cls:7), Ens.MessageBody and Ens.StreamContainer; no such class exists in src/ yet
- 2026-10-19T09:48:41Z status=routed owner=0-6-every-release-1-production-item-runs-as-a-stub-beside-the-or by=cr note=0.6 adds the BP stubs: extend roots, exempt Ens.MessageBody/Ens.BusinessProcess extents from DEFAULTGLOBAL, add bad samples
- 2026-10-19T09:51:16Z note=the occurrence line above belongs to DW-12 (filed here by mistake at cr; restated there by the lead)

### DW-14: ApiClient has no browser-envelope support: a non-GET call needs Content-Type: application/json and X-OcuTalon-Request: 1, which Angular does not send by default
- source: spec-0-5-live-events-and-the-rest-skeleton.md | severity: low | fix-risk: low | footprint: out-of-footprint
- evidence: the API refuses a state-changing call without both (403 not_json / no_request_header); ApiClient has no POST or DELETE yet
- 2026-10-19T12:43:59Z status=routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=harvest note=Rule 22 ruling: routed, not wontfix, because 2.2 adds the first POST (session/end) and the gap then becomes certain

### DW-15: Web.Api State and Events resolve the caller's session with Session.ForUser($Username), outside Data.Ownership (AD-4), so 16.3 has two lookups to replace
- source: spec-0-5-live-events-and-the-rest-skeleton.md | severity: med | fix-risk: low | footprint: out-of-footprint
- evidence: Api.cls State() and Events() call Data.Session.ForUser($Username) and read Live.Event.Since directly. AD-4 says REST reads go through Ownership; Stories 2.2 (AC 17) and 16.3 (one session per visitor) expect Ownership to resolve the caller's SessionRef from the CSP session, never the IRIS user name. Isolation holds today (one durable session per user).
- 2026-10-19T13:50:49Z status=routed owner=2-2-keep-the-session-and-load-its-snapshot-with-live-updates by=cr note=2.2: resolve State/Events' session via Ownership; lead reconciles AD-4's last bullet with AD-13's Oct 19 amendment
