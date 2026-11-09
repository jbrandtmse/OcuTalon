# OcuTalon 1.0.5 rc1

## IPM artifact
Result: pass
Candidate: 1.0.5 rc1, release/1.0.5-rc1 at 7353750b250b0e84696efed6cc39ea7466839239
Artifact: ocutalon-1.0.5.tgz, kept in the release state folder (1.0.5-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 6178083 bytes
SHA-256: 4c1c60ddbdac5a8e30c069e55f9bc08f1495d68c88b4100ff291d9dcb828a82b
Content SHA-256: 0208a146669828ce69d9dd2c1f3353dbe9bc7b6548f2045285c08c39f4591136 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.5 rc1, release/1.0.5-rc1 at 7353750b250b0e84696efed6cc39ea7466839239
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.5.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.5.tgz, 6178083 bytes
Size: 6178083 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.5 rc1, release/1.0.5-rc1 at 7353750b250b0e84696efed6cc39ea7466839239
Cut from: feature/OCT_OcuTalon_MVP at 2a45f8bca14fb3a8f9f7ad6b19f50d5d120c6e4b
Hands-on time: 0 s for this candidate; 0 s for 1.0.5 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-09T09:06:12Z to 2026-11-09T09:36:04Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.5; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.5 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.5.tgz, 6178083 bytes, SHA-256 4c1c60ddbdac; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.5.tgz (6178083 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.5-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.5/rc1-notes.md (not committed) |
| record | committed, not pushed | the author's word was not given |
