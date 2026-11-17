# OcuTalon 1.0.13 rc2

## IPM artifact
Result: pass
Candidate: 1.0.13 rc2, release/1.0.13-rc2 at 52a5048045bbe13c102e4c5d1bdd937544f810af
Artifact: ocutalon-1.0.13.tgz, kept in the release state folder (1.0.13-rc2/ipm/), outside the repository; release.sh status prints its full path
Size: 7742468 bytes
SHA-256: da271dbcb45ed1c45644127dc41c5c279de40237e49fefd70d0292ee47f07ca7
Content SHA-256: bc20cd070a0ffbdaa7a020d28b19327bcc11370379dc8c43b1721b8d8631bb7d (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 43 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.13 rc2, release/1.0.13-rc2 at 52a5048045bbe13c102e4c5d1bdd937544f810af
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.13.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.13.tgz, 7742468 bytes
Size: 7742468 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.13 rc2, release/1.0.13-rc2 at 52a5048045bbe13c102e4c5d1bdd937544f810af
Cut from: rc-base/1.0.13 at 22fea0439fbbf3d964fc0001a56ddf5fb645c8cd
Hands-on time: 0 s for this candidate; 0 s for 1.0.13 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-17T19:03:11Z to 2026-11-17T19:28:41Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.13; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.13 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.13.tgz, 7742468 bytes, SHA-256 da271dbcb45e; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.13.tgz (7742468 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.13-rc2 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.13/rc2-notes.md (not committed) |
| record | pushed | committed to rc-base/1.0.13 and pushed on the author's word |
