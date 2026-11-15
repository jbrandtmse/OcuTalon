# OcuTalon 1.0.10 rc4

## IPM artifact
Result: pass
Candidate: 1.0.10 rc4, release/1.0.10-rc4 at acace3783c3364312e7857c9a6984f76ee7d3d60
Artifact: ocutalon-1.0.10.tgz, kept in the release state folder (1.0.10-rc4/ipm/), outside the repository; release.sh status prints its full path
Size: 7187998 bytes
SHA-256: ca683ba6f0ea1c292d48cb68ecc13131f51b73b4bed826a5c15683a930f2f1a1
Content SHA-256: c1c21832bc6b7a5f8beab2f4e1ae33075ee1423fc46494bbd571a4543a5ebe53 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 33 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.10 rc4, release/1.0.10-rc4 at acace3783c3364312e7857c9a6984f76ee7d3d60
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.10.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.10.tgz, 7187998 bytes
Size: 7187998 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.10 rc4, release/1.0.10-rc4 at acace3783c3364312e7857c9a6984f76ee7d3d60
Cut from: release/1.0.10-rc3 at 67cb11af93a731bd2929a871f3b61577e78867c4, then 9b964f83ba7833ad531456b890ee4c48b2aa9954 cherry-picked from rc-base/1.0.10
Hands-on time: 0 s for this candidate; 0 s for 1.0.10 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-15T00:38:54Z to 2026-11-15T01:20:38Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.10; web bundle built with Node.js and committed; fixes cherry-picked: 1 |
| image | pass | /opt/ocutalon/version reads 1.0.10 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.10.tgz, 7187998 bytes, SHA-256 ca683ba6f0ea; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.10.tgz (7187998 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.10-rc4 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.10/rc4-notes.md (not committed) |
| record | pushed | committed to rc-base/1.0.10 and pushed on the author's word |
