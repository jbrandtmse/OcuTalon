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

## Release checklist

Result: not confirmed
Candidate: 1.0.8 rc2 at 886cee317abbca7a8ea5a5a5ca1c5da042db6fe4
Notes: release/records/1.0.8/rc2-notes.md
Run: 2026-11-12T21:26:06Z
Author's actions: Posts, articles, the video and bonus claims are the author's actions, done by hand. No script or workflow posts anything or claims a bonus.

| Item | Result | Detail |
| --- | --- | --- |
| checkout | pass | the checkout is the candidate commit, with no uncommitted change outside release/records/ |
| note-readme | pass | README.md holds the not-affiliated note word for word |
| note-about | pass | the About dialog's source and the built page hold the note word for word |
| product-name | pass | no product name holds the name from the note |
| name-only-in-note | pass | outside the planning files, the name appears only in the note |
| licences | pass | every font, icon and package licence notice is present |
| web-bundle | pass | the built web bundle is in the checkout |
| readme | pass | docker/tests/test-readme.sh passed: README links, anchors and headings checked offline |
| readme-video | pass | docker/tests/check-readme-video.sh passed: every address of the README's Video row answered, and each YouTube id's oEmbed did |
| bridge-guide | pass | docker/tests/test-bridge-guide.sh passed: the bridge guide matches the code of this release |
| public-text | pass | docker/tests/test-boundaries.sh passed, and the draft notes hold no local path or key-like text |
| iris-source | pass | irislib/ and irissys/ are ignored, and none of their files is tracked |
| no-outward | pass | no script or workflow publishes a release, changes the repository's settings or posts to a public site |
| no-copied-code | not confirmed | No code, prompts or workflows are copied from the project named in the not-affiliated note, or from a project like it. |
| no-artwork | not confirmed | None of that project's logo or artwork is used. |
| no-ai-hub-copy | not confirmed | Nothing is copied from InterSystems' published AI Hub examples. |
| public-review | not confirmed | Before the repository went public, the author reviewed every planning file under _bmad-output/ and the agent instructions (CLAUDE.md and the .claude/ and _bmad/ folders) for keys, local machine paths, private infrastructure details and names of other contest entrants. |
| public-links | not confirmed | On the public repository page, every README link and section link opens, and the README's clone command works. |
| overview-review | not confirmed | The hand-written sections of docs/security-overview.md were reviewed against this release, and each statement is true of it; the public-text row passed on the overview. |
| demo-protections | not confirmed | Each online-demo protection that docs/security-overview.md states was checked against the running online demo for this release. |
| registry-install | later | After this version was published to the package registry, the guide's two commands ran once against the registry on a clean build 154 instance and gave the same working OcuTalon; the result is in the release notes, and docs/install-ipm.md shows that run's output. |

## Carried over from rc1 by identity, and the Planner's overrides (owner's delegation, 2026-11-12)

- rc2 = rc1 (e7b1ccf4) + the test-only hotfix Story 0.34 (four cherry-picked commits) + the cut commit. Outside _bmad-output, rc2's tree differs from rc1 ONLY in docker/tests/test-compose-file.sh. The built web bundle is byte-identical, and src/, web/, eval/, install.sh, release/, .github/ and the start scripts are unchanged (release-evidence/1.0.8-gates/rc2-carryover.md, which holds `git diff --stat release/1.0.8-rc1 release/1.0.8-rc2`).
- So these carry over from rc1: the real-model RC evaluation and its override under the owner's standing 1.0.2 decision (SM-1 21, 20 and 20 of 24; S6 all 0; demo gate 30 of 30); the upgrade harness, overridden for the one first-start log line of the new public class, with release-evidence/1.0.8-gates/upgrade-hookbase-proof.md (all three proofs pass); and the greps (no "measured at release 1.0.8", no "least privilege", no claim that the digest is re-sent).
- Re-run on rc2: the release steps (all pass; IPM artifact 6,736,209 bytes, accepted as over 5,000,000, as for 1.0.7), docker/tests/test-compose-file.sh (all checks passed, the U-320 row with the bundle committed), and this checklist (the 13 automated rows pass).
- rc1's PR #12 was closed for the U-320 row (the check scanned the committed bundle). rc2's PR is #13.
