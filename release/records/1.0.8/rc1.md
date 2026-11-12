# OcuTalon 1.0.8 rc1

## IPM artifact
Result: pass
Candidate: 1.0.8 rc1, release/1.0.8-rc1 at e7b1ccf4137a94a9b7cee0d991186f2b1492ca6c
Artifact: ocutalon-1.0.8.tgz, kept in the release state folder (1.0.8-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 6736247 bytes
SHA-256: c929ed24bf018a617b9ffa1632382a43da4a0667a06426cf978a3482e8870f11
Content SHA-256: 1e586a530797b32af010f570ad4d7a0d83b9edde14f79f7874c932355a7c3bee (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.8 rc1, release/1.0.8-rc1 at e7b1ccf4137a94a9b7cee0d991186f2b1492ca6c
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.8.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.8.tgz, 6736247 bytes
Size: 6736247 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.8 rc1, release/1.0.8-rc1 at e7b1ccf4137a94a9b7cee0d991186f2b1492ca6c
Cut from: feature/OCT_OcuTalon_MVP at 36092ff1226d25a0fc0fee976a0892c47d79e407
Hands-on time: 0 s for this candidate; 0 s for 1.0.8 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-12T18:46:53Z to 2026-11-12T19:18:30Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.8; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.8 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.8.tgz, 6736247 bytes, SHA-256 c929ed24bf01; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.8.tgz (6736247 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.8-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.8/rc1-notes.md (not committed) |
| record | committed, not pushed | the author's word was not given |
