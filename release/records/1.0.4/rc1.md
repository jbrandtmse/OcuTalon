# OcuTalon 1.0.4 rc1

## IPM artifact
Result: pass
Candidate: 1.0.4 rc1, release/1.0.4-rc1 at c7d8fa75db2e95f828e81fb95ceccda10ff4158f
Artifact: ocutalon-1.0.4.tgz, kept in the release state folder (1.0.4-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 5964752 bytes
SHA-256: 211f77ff45f3d3c81744a8acc76faf33c0876a80020f6c9f37e9a629375cda8d
Content SHA-256: e3cfe1208f60d284957246ab04089dadce4a443d0127c0c922fd4a2234cb1af8 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.4 rc1, release/1.0.4-rc1 at c7d8fa75db2e95f828e81fb95ceccda10ff4158f
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.4.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.4.tgz, 5964752 bytes
Size: 5964752 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.4 rc1, release/1.0.4-rc1 at c7d8fa75db2e95f828e81fb95ceccda10ff4158f
Cut from: feature/OCT_OcuTalon_MVP at a77f9a878e2bbe53f3484f572e352136a8138d5f
Hands-on time: 0 s for this candidate; 0 s for 1.0.4 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-08T19:15:54Z to 2026-11-08T19:45:26Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.4; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.4 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.4.tgz, 5964752 bytes, SHA-256 211f77ff45f3; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.4.tgz (5964752 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.4-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.4/rc1-notes.md (not committed) |
| record | committed, not pushed | the author's word was not given |
