# OcuTalon 1.0.12 rc2

## IPM artifact
Result: pass
Candidate: 1.0.12 rc2, release/1.0.12-rc2 at 9c26772acef1655b3b2a6abfaecc88726e14ecdb
Artifact: ocutalon-1.0.12.tgz, kept in the release state folder (1.0.12-rc2/ipm/), outside the repository; release.sh status prints its full path
Size: 7503905 bytes
SHA-256: b9292c0c35f714ae4786121a86e299e241f41a83b9d54baac81381b39daf7a1d
Content SHA-256: f600555dadeeae5290968decb044a469b1fd203afe61ea624e3f8465915bfc82 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 39 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.12 rc2, release/1.0.12-rc2 at 9c26772acef1655b3b2a6abfaecc88726e14ecdb
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.12.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.12.tgz, 7503905 bytes
Size: 7503905 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.12 rc2, release/1.0.12-rc2 at 9c26772acef1655b3b2a6abfaecc88726e14ecdb
Cut from: rc-base/1.0.12 at b7b7deed233ae2149c9a92ff6e303c3553a04757
Hands-on time: 0 s for this candidate; 0 s for 1.0.12 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-16T14:22:59Z to 2026-11-16T14:54:19Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.12; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.12 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.12.tgz, 7503905 bytes, SHA-256 b9292c0c35f7; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.12.tgz (7503905 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.12-rc2 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.12/rc2-notes.md (not committed) |
| record | pushed | committed to rc-base/1.0.12 and pushed on the author's word |
