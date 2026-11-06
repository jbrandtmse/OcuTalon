# OcuTalon 1.0.2 rc1

## IPM artifact
Result: pass
Candidate: 1.0.2 rc1, release/1.0.2-rc1 at fe61a8e20c17f5f0d565abdee9422abc0c66ac47
Artifact: ocutalon-1.0.2.tgz, kept in the release state folder (1.0.2-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 5441993 bytes
SHA-256: be3aac63999ffcdfb7d34cd7c86be5b09826619d4aafbc2c45d3851eadb6ca69
Content SHA-256: bfb114afff9aea021e087a64e185bc200503be8c598310aa4b6b8e0ed60e30f2 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.2 rc1, release/1.0.2-rc1 at fe61a8e20c17f5f0d565abdee9422abc0c66ac47
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.2.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.2.tgz, 5441993 bytes
Size: 5441993 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.2 rc1, release/1.0.2-rc1 at fe61a8e20c17f5f0d565abdee9422abc0c66ac47
Cut from: feature/OCT_OcuTalon_MVP at b5dcbbfa535306a3fc297e97753f0095131c1be0
Hands-on time: 0 s for this candidate; 0 s for 1.0.2 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-06T19:07:10Z to 2026-11-06T19:33:07Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.2; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.2 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.2.tgz, 5441993 bytes, SHA-256 be3aac63999f; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.2.tgz (5441993 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.2-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.2/rc1-notes.md (not committed) |
| record | committed, not pushed | the author's word was not given |
