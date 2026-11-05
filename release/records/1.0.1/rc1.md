# OcuTalon 1.0.1 rc1

## IPM artifact
Result: pass
Candidate: 1.0.1 rc1, release/1.0.1-rc1 at 639f3e43c897a4b9975899b3aff0d774739ac058
Artifact: ocutalon-1.0.1.tgz, kept in the release state folder (1.0.1-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 5183617 bytes
SHA-256: 79b8d4218bcd53afa0827a4654fd51388fb744e8081221bb5708b50625620233
Content SHA-256: a2ebc9d753cb8263765e35705766347a9a49d1106d21f0a38ef9dca8f52ed01a (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.1 rc1, release/1.0.1-rc1 at 639f3e43c897a4b9975899b3aff0d774739ac058
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.1.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.1.tgz, 5183617 bytes
Size: 5183617 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.1 rc1, release/1.0.1-rc1 at 639f3e43c897a4b9975899b3aff0d774739ac058
Cut from: feature/OCT_OcuTalon_MVP at a745aa6aa4400f6223a652df1c5056c806a811fa
Hands-on time: 0 s for this candidate; 0 s for 1.0.1 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-05T10:40:36Z to 2026-11-05T10:59:58Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.1; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.1 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.1.tgz, 5183617 bytes, SHA-256 79b8d4218bcd; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.1.tgz (5183617 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.1-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.1/rc1-notes.md (not committed) |
| record | pushed | committed to feature/OCT_OcuTalon_MVP and pushed on the author's word |
