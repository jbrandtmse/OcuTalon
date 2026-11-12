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

## Upgrade harness

Result: fail
Mode: release
Required: yes
Candidate: 1.0.8 at e7b1ccf4137a94a9b7cee0d991186f2b1492ca6c
Previous: explicit v1.0.7 at 45a89574281d7c41dcd9c0f6cc1460cdbb527980, version 1.0.7, built as 1.0.7
Run: 2026-11-12T18:47:50Z to 2026-11-12T19:01:43Z, tag upg-1794509270
Merge retries: 0

| Record | Result | Detail |
| --- | --- | --- |
| previous build | pass | 12 checks passed |
| upgrade | fail | settings project upgrade: the log differs from the expected phases and steps (and 1 more failed) |
| conversation | pass | 3 checks passed |
| reminder | pass | 2 checks passed; R1 fired on-time (due 187 s after the candidate was ready) |
| approval | pass | 3 checks passed |
| watch | pass | 2 checks passed |
| settings | pass | 9 checks passed |
| restart | pass | 10 checks passed |
| storage | pass | 2 checks passed |
| private globals | pass | 2 checks passed |
| pairing | pass | 5 checks passed |
| memory | pass | 2 checks passed |
| document | pass | 4 checks passed |

## Release checklist

Result: not confirmed
Candidate: 1.0.8 rc1 at e7b1ccf4137a94a9b7cee0d991186f2b1492ca6c
Notes: release/records/1.0.8/rc1-notes.md
Run: 2026-11-12T19:20:24Z
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

## Overrides and rulings (Contest Planner, under the owner's delegation, 2026-11-12)

- Upgrade harness: OVERRIDDEN. The one failed check, in the settings and the records project, is the first start's log line after the 1.0.7 -> 1.0.8 upgrade: "STEP public-classes OcuTalon.Web.Public.HookBase is not compiled" where "ok" was expected (release-evidence/1.0.8-gates/upgrade-harness.log lines 16-18 and 58-60). docker/after-start.cos line 6 checks the public classes before line 8 loads the package, and line 7 reloads the package because the installed version (1.0.7) differs from the image's (1.0.8). So on a real upgrade a public class that is new in the release reads "not compiled" at that point. The harness's expected log was too strict. Proof that the class is in place after the upgrade, as the Planner required: release-evidence/1.0.8-gates/upgrade-hookbase-proof.md. (1) compiled, with its routine in the OCUTALON_PUBLIC database: pass; (2) after a restart, "STEP public-classes ok", "STEP package skipped 1.0.8", "RESULT OK 1.0.8": pass; (3) a webhook created on the upgraded instance answers 202 to its POST (401 with a wrong secret, 404 to OPTIONS with no Allow header): pass. Every record of the harness passed. The fix of the expectation is a burndown DW (release-evidence/1.0.8-gates/dw-drafts.md).
- Release-candidate evaluation: verdict blocked only by SM-1 (21, 20 and 20 of 24 against 22), overridden under the owner's standing 1.0.2 decision. Safety held in all 3 attempts (S6: 0 approval requests, commands, setting changes and fix runs), demo gate 30 of 30, SM-2 11, 11 and 10 of 11. The overridden pair is in release-evidence/1.0.8-gates/rc-eval/release-candidate-overridden.json and .md.
- IPM artifact 6,736,247 bytes, over 5,000,000: accepted, as 1.0.7's 6,488,387 bytes was.
- Release checklist: the 13 automated rows pass. The author rows and registry-install are as in 1.0.7; public-links and demo-protections are checked after the merge and the demo update.
