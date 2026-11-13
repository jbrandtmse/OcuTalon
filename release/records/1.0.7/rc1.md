# OcuTalon 1.0.7 rc1

## IPM artifact
Result: pass
Candidate: 1.0.7 rc1, release/1.0.7-rc1 at 1e2963ea6ad2a56c88cf98e19a0b068920c0a56a
Artifact: ocutalon-1.0.7.tgz, kept in the release state folder (1.0.7-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 6488387 bytes
SHA-256: 100a495112c77113c354cb744b1a059e96ccf6ee4f5fd1e1a563f901ac670f00
Content SHA-256: fecf682e17e28136b928856aa75b0b9714111b95e5f6af6135cb5b166b5c0d31 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.7 rc1, release/1.0.7-rc1 at 1e2963ea6ad2a56c88cf98e19a0b068920c0a56a
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.7.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.7.tgz, 6488387 bytes
Size: 6488387 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.7 rc1, release/1.0.7-rc1 at 1e2963ea6ad2a56c88cf98e19a0b068920c0a56a
Cut from: feature/OCT_OcuTalon_MVP at 5ed39411c1168b45c29babac838b63f4b7916261
Hands-on time: 0 s for this candidate; 0 s for 1.0.7 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-11T10:44:31Z to 2026-11-11T11:09:25Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.7; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.7 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.7.tgz, 6488387 bytes, SHA-256 100a495112c7; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.7.tgz (6488387 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.7-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.7/rc1-notes.md (not committed) |
| record | pushed | committed to feature/OCT_OcuTalon_MVP and pushed on the author's word |
