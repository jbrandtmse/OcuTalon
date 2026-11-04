# OcuTalon 1.0.0 rc4

## IPM artifact
Result: pass
Candidate: 1.0.0 rc4, release/1.0.0-rc4 at 9a476db3c39053a32778074444843cb043b292e9
Artifact: ocutalon-1.0.0.tgz, kept in the release state folder (1.0.0-rc4/ipm/), outside the repository; release.sh status prints its full path
Size: 5118915 bytes
SHA-256: 8689c68cb9fd83dea9ae98ea0aacd196fb91586642f854a3001585193993ff51
Content SHA-256: 60380fc6af7cdeffb5a9766782d9e79f97be3664ccffeb3bb5f8f8a3861ced29 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.0 rc4, release/1.0.0-rc4 at 9a476db3c39053a32778074444843cb043b292e9
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.0.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.0.tgz, 5118915 bytes
Size: 5118915 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Upgrade harness

Result: pass
Mode: release
Required: no
Candidate: 1.0.0 at 9a476db3c39053a32778074444843cb043b292e9
Previous: pre-release c9f1288c7a735f1ee3aa14a4f5289de794ce5257, version 0.1.0, built as 0.1.0
Note: 1.0.0 is the first release: it has no previous release, so the previous side is a pre-release build of the integration branch (c9f1288c7a735f1ee3aa14a4f5289de794ce5257), which proves the harness itself.
Run: 2026-11-04T08:48:35Z to 2026-11-04T09:01:36Z, tag upg-rc4
Merge retries: 0

| Record | Result | Detail |
| --- | --- | --- |
| previous build | pass | 12 checks passed |
| upgrade | pass | 13 checks passed |
| conversation | pass | 3 checks passed |
| reminder | pass | 2 checks passed; R1 fired on-time (due 203 s after the candidate was ready) |
| approval | pass | 3 checks passed |
| watch | pass | 2 checks passed |
| settings | pass | 9 checks passed |
| restart | pass | 10 checks passed |
| storage | pass | 2 checks passed |
| private globals | pass | 2 checks passed |
| pairing | pass | 3 checks passed; the upgrade part joins from the release after 1.0.0 |

## Clean-machine rehearsal

Result: fail
Mode: rehearsal
Candidate: 1.0.0 rc4, branch release/1.0.0-rc4 at 9a476db3c39053a32778074444843cb043b292e9
Specs: the REL-2 specs (web/e2e/demo-path) at 9a476db3c39053a32778074444843cb043b292e9
Clean host: Linux (Ubuntu 24.04.5 LTS), x86_64, 7.8 GiB memory; Node.js absent
Driver host: macOS 26.6.2, arm64, 128.0 GiB memory
Run: 2026-11-04T08:48:34Z to 2026-11-04T09:06:37Z

| Step | Result | Detail |
| --- | --- | --- |
| hosts | pass | both hosts answered; git and Docker on the clean host, no OcuTalon container or volume |
| copy | pass | git bundle of 30831 KiB; the clone is at the candidate commit |
| install | pass | install.sh reached ready; first start 316 s, install included; install.sh said "OcuTalon is ready after 5 min 15 s." |
| sign-in | pass | the driver host signed in at the printed address as the printed user |
| secrets | pass | no .env or configuration value in the output or the record |
| demo path runs | fail | 1 of 8 runs failed a spec or left a mark missing |
| notice | pass | within 60 s in 8 of 8 runs (19 of 20 needed); longest 25.2 s (run 8) |
| pick-up | pass | within 15 s of the first failure in every run; longest 3.4 s (run 4) |
| settle-end | pass | within 30 s of the first failure in every run; longest 11.2 s (run 7) |
| diagnosis | pass | within 20 s in every run; longest 15.3 s (run 8) |
| delivery | pass | within 5 s in every run; longest 0.9 s (run 1) |
| median | recorded | median notice 18.6 s against the typical 35 s |
| decision | pass | within 10 s in 8 of 8 runs (19 of 20 needed); longest 3.4 s (run 1) |
| first-reply | recorded | median 4.1 s, longest 6.0 s (run 8) |
| approval-result | fail | no measurement in run 8 (a mark is missing) |
| reminder | fail | no measurement in run 8 (a mark is missing) |
| reminder-result | fail | no measurement in run 8 (a mark is missing) |
| largest-request | pass | under 100,000 input tokens in every run; largest 8,436 (run 8) |
| tell-now | fail | run 3: decided fallback (no tell-now sample), run 4: decided fallback (no tell-now sample) from the decision to the notice on the web chat and the phone (an upper bound) (limit tell-now 5 s in 19 of 20) |

### Runs

| Run | Result | Notice | Pick-up | Settle end | Diagnosis | Delivery | Decision | First reply | Approval result | Reminder | Reminder to result | Largest request | Tell now |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | pass | 21.3 s | 3.3 s | 11.2 s | 9.0 s | 0.9 s | 3.4 s | 5.3 s | 0.3 s | 0.6 s | -4.0 s | 5,160 | 0.2 s |
| 2 | pass | 17.5 s | 2.7 s | 10.9 s | 6.4 s | 0.2 s | 1.4 s | 3.4 s | 0.2 s | 0.4 s | 38.0 s | 5,597 | 0.2 s |
| 3 | pass | 17.0 s | 0.6 s | 9.8 s | 7.0 s | 0.2 s | 1.9 s | 2.8 s | 0.2 s | 0.5 s | 38.0 s | 5,905 | fallback (no sample) |
| 4 | pass | 19.8 s | 3.4 s | 10.7 s | 8.7 s | 0.2 s | 1.3 s | 3.5 s | 0.2 s | 0.9 s | 33.0 s | 6,343 | fallback (no sample) |
| 5 | pass | 23.9 s | 1.2 s | 10.5 s | 13.1 s | 0.2 s | 1.4 s | 5.0 s | 0.3 s | 0.7 s | 28.0 s | 6,863 | 0.3 s |
| 6 | pass | 16.6 s | 1.2 s | 10.5 s | 5.7 s | 0.2 s | 1.3 s | 4.3 s | 0.4 s | 0.4 s | 34.0 s | 7,302 | 0.2 s |
| 7 | pass | 17.5 s | 1.0 s | 11.2 s | 5.9 s | 0.2 s | 1.3 s | 3.9 s | 0.4 s | 0.3 s | 34.0 s | 7,796 | 0.2 s |
| 8 | fail | 25.2 s | 1.5 s | 9.8 s | 15.3 s | 0.0 s | 1.4 s | 6.0 s | - | - | - | 8,436 | 0.2 s |

* over the bound's limit; the bound's rule says how many runs may miss it.

## Hand gates (Contest Planner, 2026-11-04)

Candidate 9a476db3, cut from 5c864419. Its product files equal rc3's (5a1e98e5); only two test scripts differ.

- Pull request checks: all 15 pass on the rc4 pull request, iris (image) and iris (browser) on a re-run of those two jobs (a port clash on one CI host).
- Upgrade harness: pass, MERGE-RETRIES 0. IPM install on a fresh instance: pass.
- Rehearsal: rc3 passed 20 of 20. On rc4 the first attempt stopped at run 8 (a diagnosis reply failed its check, so the incident stayed open with no fix to approve) and the second attempt stopped at run 1 (a test read an instance cursor of 1, not 0). Both are open for the author's decision.
- Evaluation: blocked on rc4 in both runs. SM-1 between 81.8 and 86.4 percent against 90. In three attempts one incident case timed out, which also marks NFR-3, Model and No problem for that attempt. One injection reason missed a phrase in one attempt; nothing acted. No override has been recorded on rc4.
- Story 38.1 web pass: done on rc4, no findings.
- Story 38.3 Telegram pass: on rc4, 20 of 20 pairings within 5 s, worst 3.5 s. 20 of 20 approvals answered in Telegram and finished within 1 s by the server's records. The driver's own page check timed 16 of them, median 0.5 s; it missed 4 because the page trims older items. Reminder, incident notice and Approve seen in Telegram Web. The client SSL configuration verifies the peer.
- Build 109: README path on arm64 and on x64 walked to an approved fix; install-fresh, production and shards groups pass.
- Package: an archive packed the way the registry packs a repository installed on a fresh instance through a local repository: pass. The test registry refused an upload of the package with 413.

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.0 rc4, release/1.0.0-rc4 at 9a476db3c39053a32778074444843cb043b292e9
Cut from: feature/OCT_OcuTalon_MVP at 5c864419325ba53653e6a09f957afd5b7e432463
Hands-on time: 0 s for this candidate; 0 s for 1.0.0 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-04T08:42:10Z to 2026-11-04T10:28:22Z

| Step | Result | Detail |
| --- | --- | --- |
| kit | confirmed | the author confirmed the 1.0.0 kit is on feature/OCT_OcuTalon_MVP at 5c86441 |
| cut | pass | module.xml and src/module.xml set to 1.0.0; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.0 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.0.tgz, 5118915 bytes, SHA-256 8689c68cb9fd; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.0.tgz (5118915 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.0-rc4 pushed to origin on the author's word |
| notes | draft | release/notes.sh: RESULT draft; draft release/records/1.0.0/rc4-notes.md (not committed) |
| record | pushed | committed to feature/OCT_OcuTalon_MVP and pushed on the author's word |
