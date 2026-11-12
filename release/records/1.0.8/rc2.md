# OcuTalon 1.0.8 rc2

## IPM artifact
Result: pass
Candidate: 1.0.8 rc2, release/1.0.8-rc2 at 886cee317abbca7a8ea5a5a5ca1c5da042db6fe4
Artifact: ocutalon-1.0.8.tgz, kept in the release state folder (1.0.8-rc2/ipm/), outside the repository; release.sh status prints its full path
Size: 6736209 bytes
SHA-256: 74e0a558c9957198ad71c2f9521661a12bd02c9950fe2dc3786a7f1642a08dff
Content SHA-256: 1e586a530797b32af010f570ad4d7a0d83b9edde14f79f7874c932355a7c3bee (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.8 rc2, release/1.0.8-rc2 at 886cee317abbca7a8ea5a5a5ca1c5da042db6fe4
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.8.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.8.tgz, 6736209 bytes
Size: 6736209 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.8 rc2, release/1.0.8-rc2 at 886cee317abbca7a8ea5a5a5ca1c5da042db6fe4
Cut from: release/1.0.8-rc1 at e7b1ccf4137a94a9b7cee0d991186f2b1492ca6c, then 916fcfbf056848b4d4f0d44d0b9d0ea1f372ac63 6bb2b957e625f3c5e018062531d6166ed4fb570a 6ab163f1c49e0e64e38f3351d44ec21f9087163b 1327fa1b5fdc2de3071a0de2e328c9a9e04dad8c cherry-picked from feature/OCT_OcuTalon_MVP
Hands-on time: 0 s for this candidate; 0 s for 1.0.8 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-12T20:59:15Z to 2026-11-12T21:24:40Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.8; web bundle built with Node.js and committed; fixes cherry-picked: 4 |
| image | pass | /opt/ocutalon/version reads 1.0.8 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.8.tgz, 6736209 bytes, SHA-256 74e0a558c995; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.8.tgz (6736209 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.8-rc2 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.8/rc2-notes.md (not committed) |
| record | committed, not pushed | the author's word was not given |
