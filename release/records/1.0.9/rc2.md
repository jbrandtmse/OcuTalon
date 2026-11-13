# OcuTalon 1.0.9 rc2

## IPM artifact
Result: pass
Candidate: 1.0.9 rc2, release/1.0.9-rc2 at 12bd6fb5f66b35f6a425098161ad9e3fee37fe72
Artifact: ocutalon-1.0.9.tgz, kept in the release state folder (1.0.9-rc2/ipm/), outside the repository; release.sh status prints its full path
Size: 6935299 bytes
SHA-256: 11ce47fdff33d8f0d133d393285c099469b47ad676f7603bd5424f728b4181ab
Content SHA-256: 7a0ea84c29cbc690689ce1858332c2fb90ee5d4842aafd19af4548a5a21bd1b7 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.9 rc2, release/1.0.9-rc2 at 12bd6fb5f66b35f6a425098161ad9e3fee37fe72
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.9.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.9.tgz, 6935299 bytes
Size: 6935299 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.9 rc2, release/1.0.9-rc2 at 12bd6fb5f66b35f6a425098161ad9e3fee37fe72
Cut from: release/1.0.9-rc1 at 5dbb2156957753eb87db87e153ad1912a6355546, then d3ab42cd5fb3876f635aeb8ac7d0caf9d3471681 5c8ae1160cbbf366ff1078af3ba48fc6e47ddaa9 cherry-picked from rc-base/1.0.9
Hands-on time: 0 s for this candidate; 0 s for 1.0.9 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-13T21:57:51Z to 2026-11-13T22:24:27Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.9; web bundle built with Node.js and committed; fixes cherry-picked: 2 |
| image | pass | /opt/ocutalon/version reads 1.0.9 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.9.tgz, 6935299 bytes, SHA-256 11ce47fdff33; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.9.tgz (6935299 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.9-rc2 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.9/rc2-notes.md (not committed) |
| record | pushed | committed to rc-base/1.0.9 and pushed on the author's word |
