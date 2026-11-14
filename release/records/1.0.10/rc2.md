# OcuTalon 1.0.10 rc2

## IPM artifact
Result: pass
Candidate: 1.0.10 rc2, release/1.0.10-rc2 at c7feff8bd86bc7fe52c84c3ee967f4daea59c380
Artifact: ocutalon-1.0.10.tgz, kept in the release state folder (1.0.10-rc2/ipm/), outside the repository; release.sh status prints its full path
Size: 7188122 bytes
SHA-256: 83376bdcaa30b5fd22e17692198091b87ec66d43ad06cc55c6110ed50ee798b5
Content SHA-256: c1c21832bc6b7a5f8beab2f4e1ae33075ee1423fc46494bbd571a4543a5ebe53 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 33 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## Release sequence
Result: failed at ipmcheck: precondition: IPM 0.10.10 is loaded in %SYS and enabled for USER only: the IRIS session printed nothing
Mode: release
Candidate: 1.0.10 rc2, release/1.0.10-rc2 at c7feff8bd86bc7fe52c84c3ee967f4daea59c380
Cut from: release/1.0.10-rc1 at 2eb1f6bb6e44b3770031d6932cb30a986457112b, then af212d21b860e1396f5498a0957a02f8bdb450a7 293b98d3293460848b02c3c96654c0d5a5c9392e cherry-picked from rc-base/1.0.10
Hands-on time: 0 s for this candidate; 0 s for 1.0.10 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-14T22:59:23Z to 2026-11-14T23:43:04Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.10; web bundle built with Node.js and committed; fixes cherry-picked: 2 |
| image | pass | /opt/ocutalon/version reads 1.0.10 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.10.tgz, 7188122 bytes, SHA-256 83376bdcaa30; carries the candidate's web bundle; not published |
| ipmcheck | fail | precondition: IPM 0.10.10 is loaded in %SYS and enabled for USER only: the IRIS session printed nothing |
| record | committed, not pushed | rc-base/1.0.10 holds commits besides the record, so it was not offered for a push |

## FR-57 job
Result: fail
Candidate: 1.0.10 rc2, release/1.0.10-rc2 at c7feff8bd86bc7fe52c84c3ee967f4daea59c380
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.10.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.10.tgz, 7188122 bytes
Size: 7188122 bytes, over 5000000
First failure: precondition: IPM 0.10.10 is loaded in %SYS and enabled for USER only: the IRIS session printed nothing
