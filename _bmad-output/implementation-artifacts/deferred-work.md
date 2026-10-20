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
- 2026-10-20T00:45:56Z status=resolved-by:0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model owner=0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model by=adjudication note=test-storage-roundtrip.sh in IRIS group image with an in-run control; green in run 39338702672

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

### DW-21: REL-4's 30 minutes holds only by dispatch order: the five IRIS groups (largest 14.6 min, about 50 runner-minutes) can schedule to about 32 min on two runners
- source: spec-0-7-ci-runs-on-hosted-runners-and-the-iris-runner-with-the-model.md | severity: med | fix-risk: high | footprint: in-story
- evidence: Run 39338702672 took 27 min 37 s; install started fourth after a 13 min queue. List scheduling of its measured jobs gives 27.1 min at best and about 32 min at worst; a push with an open PR also starts a second matrix.
- 2026-10-20T00:40:42Z status=escalated owner=burndown by=cr note=install split makes 6 groups (AD-22 says five), worst case 31.5 min; real fixes: one stack for both shards, or a third runner (spend)
- 2026-10-20T01:30:58Z occurrence=0-8-the-demo-path-test-signs-in-and-loads-the-page note=demo-path unit adds about 3 runner-minutes to browser; worst-case bound grows about 1.5 min

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

### DW-29: Banner keys with a {time} slot render as message times in the instance zone, while the UX says banner times are page times in the browser's zone
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: in-epic
- evidence: 0.9 Rule 22 ruling: Render renders times only through Data.Time.ForMessage; EXPERIENCE banner table; Story 2.10 renders the banners
- 2026-10-20T05:25:07Z status=routed owner=2-10-show-status-banners-for-a-missing-key-or-a-stalled-heartbeat by=harvest note=2.10 decides: pass a web-formatted time, or render the banner's time in the browser

### DW-30: Nothing limits a rendered text's length, while Telegram caps a message at 4,096 characters, so a long model-written slot could make sendMessage fail
- source: spec-0-9-the-message-catalog-and-its-one-renderer.md | severity: med | fix-risk: low | footprint: out-of-epic
- evidence: 0.9 implement report; Msg.Catalog.Render has no length cap; Bot API sendMessage limit
- 2026-10-20T05:25:07Z status=routed owner=12-6-chat-and-get-notifications-in-the-paired-telegram-chat by=harvest note=TelegramOut truncates or splits per the UX before sendMessage
