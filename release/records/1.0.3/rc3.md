# OcuTalon 1.0.3 rc3

## IPM artifact
Result: pass
Candidate: 1.0.3 rc3, release/1.0.3-rc3 at de12ed2a893cd7914b56983e0488887c6aed0d0b
Artifact: ocutalon-1.0.3.tgz, kept in the release state folder (1.0.3-rc3/ipm/), outside the repository; release.sh status prints its full path
Size: 5797260 bytes
SHA-256: c7faa90e99b2ff04e50bdd64c3078992eaf73ce477efd89e19ff08b9340caefd
Content SHA-256: efcb7d68a32e1c39a539d61181c840bb597077a870b0e67f2f5c5e2624c5b682 (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence

## FR-57 job
Result: pass
Candidate: 1.0.3 rc3, release/1.0.3-rc3 at de12ed2a893cd7914b56983e0488887c6aed0d0b
Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-1.0.3.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command
Artifact: ocutalon-1.0.3.tgz, 5797260 bytes
Size: 5797260 bytes, over 5000000
Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged

## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.3 rc3, release/1.0.3-rc3 at de12ed2a893cd7914b56983e0488887c6aed0d0b
Cut from: feature/OCT_OcuTalon_MVP at 50103869cd8b4bf918d1e3799b079705b156a2f1
Hands-on time: 0 s for this candidate; 0 s for 1.0.3 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-07T20:57:14Z to 2026-11-07T21:23:28Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.3; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.3 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | pass | ocutalon-1.0.3.tgz, 5797260 bytes, SHA-256 c7faa90e99b2; carries the candidate's web bundle; not published |
| ipmcheck | pass | ocutalon-1.0.3.tgz (5797260 bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged |
| push | pass | release/1.0.3-rc3 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.3/rc3-notes.md (not committed) |
| record | committed, not pushed | the author's word was not given |
