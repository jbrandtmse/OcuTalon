---
title: 'Story 11.23: install.sh accepts build 109'
type: 'bugfix'
created: '2026-11-05'
status: 'done'
baseline_revision: '0242c7b2f922c97a46015b44d7a4b484c399075b'
baseline_commit: '0242c7b2f922c97a46015b44d7a4b484c399075b'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The Early Access portal now offers only build 109, and `install.sh` accepts only build 154 image refs, so a judge's local install stops at its first check; the README sends a build 109 reader down a separate hand path (U-241) instead (DW-636).

**Approach:** `install.sh` accepts the IRIS for Health build 109 image by its exact ref beside today's exact build 154 refs, retags it to the same base name and prefers build 154 when both are loaded; its messages name both builds. The README's separate "Start it with build 109" path gives way to the one path that now covers both builds, in the Contest Planner's approved wording, and `test-readme.sh`'s build 109 pins follow it.

## Boundaries & Constraints

**Always:**
- Accepted refs are exactly: `irishealth-community:2026.3.0AI.154.0` and `iris-community:2026.3.0AI.154.0` (today's two, unchanged) and `irishealth-community:2027.1.0AI.109.0`. A ref matches when its repository's last path segment and its tag equal one of these exactly, with or without a registry prefix, as today's 154 refs already match (Design Notes D1). No pattern or prefix on the tag.
- Preference among loaded images for this CPU: Health 154, then Health 109, then non-Health 154. A base name that exists is never moved (unchanged).
- A Health 109 image is handled like a Health 154 image: tagged once as `ocutalon-iris-base:2026.3.0AI.154.0` (the base name every compose file expects), and `docker compose up -d` gets `IRIS_IMAGE` set to that name.
- README.md and install.sh's printed messages use exactly the wording in Design Notes, "README text for approval", as APPROVED by the Contest Planner (P2 as amended there). No other user-facing text changes. `docker/tests/test-readme.sh` gains pins for P2's new wording; no pin is deleted.
- Every pin changed in `docker/tests/test-readme.sh` is updated in place, never deleted (Design Notes, "Pins changed"); every other pin stays as it is.
- Exit codes and every other message, check, wait and change of install.sh stay as they are; bash 3.2 rules of its header hold; ASCII only.

**Never:**
- No change under `src/`, to `docker/Dockerfile`, `docker-compose.yml`, `docs/`, `release/`, `ci/` or `docker/tests/test-install-script-live.sh`.
- No edit of README.md's "Credits and licences" section or of `test-readme.sh` lines 34-45 (header), the `DOCKERFILE` variable area (about 132-167) or `chk_licence`/`rule_licence` (Epic 34's contended regions).
- Never load, pull, remove or retag a shared image; only names this story's own run creates (`$P-...`) are added and removed, never with `-f`.
- No commit of README.md before the Planner's approval reaches the lead (the lead's gate, not the implement stage's).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Build 109 only | `registry.example/irishealth-community:2027.1.0AI.109.0`, this CPU, no base name | `Image: IRIS for Health, build 109 (<ref>).`; tagged once to the base name; `IRIS_IMAGE` is the base name; exit 0 | none |
| Build 109 bare and prefixed | `irishealth-community:2027.1.0AI.109.0`, `one/...`, `a/b/c/...`, `localhost:5000/team/...` | each is a Health candidate (tagged once) | none |
| Both Health builds | Health 154 and Health 109 for this CPU, in any sort order (e.g. bare 154 with `a/...:2027.1.0AI.109.0`) | build 154 is the tag source and named | none |
| Health 109 beside non-Health 154 | both for this CPU | Health 109 used | none |
| Health 109 other CPU | Health 109 for x64, non-Health 154 for arm64, arm64 daemon | non-Health used; line `The IRIS for Health image <109 ref> is for x64, not for this machine's arm64, so the non-Health image is used.` | none |
| Refused refs | `iris-community:2027.1.0AI.109.0`, `irishealth-community:2027.1.0AI.110.0`, `:2027.1.0AI.109.1`, `:2027.1.0AI.109`, `:2027.1`, `irishealth-community-x:2027.1.0AI.109.0` | no-image row: the new no-image message, exit 1, nothing changed | as today |
| Existing base is the 109 image | base name exists with the 109 image's ID | `Image: IRIS for Health, build 109 (<ref>). The existing <base> is that image, so it is not tagged again.` | none |
| Existing base matches nothing | base name exists, no accepted image has its ID | `Image: the existing <base>. No IRIS build 154 or build 109 image loaded here has its ID, so it is used as it is.` | none |
| Wrong CPU | only Health 109 for x64, arm64 daemon | the new wrong-CPU message, the image's CPU line, exit 1 | nothing changed |

</intent-contract>

## Code Map

- `install.sh` (400 lines) -- `TAG=2026.3.0AI.154.0` (29; stays the base tag: `test-install-script.sh:842-843` reads `^TAG=` and pins it to the compose default); `base` (31). `scan_images` (165-192): the accept filter (179 tag, 180-184 repository `h`/`n`), records `<kind> <ref> <id> <arch>` in `LC_ALL=C` order; extend it with the 109 entry and a build field. `pick` (194-210, first of a kind for this CPU) and its callers 236 and 268-271: the preference. Readers of records: `other_cpu_lines` (213-221), the base-ID match (249-258), the mixed-CPU loop (275-283): each `while read -r kind ref id arch` follows a new field. Messages to change: header comments 2 and 7, scan comment 166-168, 239-240, 260, 265, 270, 285-286, 290, 292. 274 (non-Health line) and every other message unchanged.
- `docker/tests/test-install-script.sh` (863 lines) -- hermetic; helpers `new_case`, `add_image <ref> <id> <arch>`, `run_install`, `tagged_once`, `up_env_is`, `out_has`, `no_change`, `exit_is` (around 200-255); `TAG`/`BASE` (65-66); header rows 9-13. Pins on changed messages: 322, 351, 352, 430, 438, 459 (459 matches `irishealth-community:$TAG> $BASE`). Unchanged pins that must stay green: 281, 293, 413, 421, 446, 453 and the wrong-CPU case (`archive for arm64 and load it`, 365-369). Cases to extend: the prefix loop (305-311), look-alikes (313-323), tie (325-335). Source pin 842-843.
- `README.md` -- passages P1 to P9 (Design Notes): step 2 at 16; "Get the image" 94; "Start it with the install script" 106 and 114; "Start it by hand" 128; "Start it with build 109" 138-151; "The IRIS (non-Health) image" 154; Troubleshooting 244 and 246. Unchanged: step 1 (15), "Get the image" 92, the code blocks of 108-112 and 130-134, 156-161. Epic 34 adds one bullet at 343 (Credits and licences): a different hunk.
- `docker/tests/test-readme.sh` (1832 lines) -- `try-it`: header 10-12, `TRY_FACTS`/`TRY_B109` (430-444), `chk_try_it` (445-465), `rule_try_it` (1216-1230). `install`: header 30-33, `INSTALL_FACTS`/`INSTALL_B109`/`T_B109`/`H_B109` (616-651), `chk_install` (652-672), `rule_install` self-tests 1381-1389. Helpers: `section` (259), `chk_facts` (268), `st`, `st_move`, `st_facts`, `st_append`, `finish` (327-393). Also reads install.sh: `chk_install_pointer` (675) and `chk_commands` (688) need "The Troubleshooting section of README.md" and `run: docker compose ...` kept (unchanged texts). `docs` rule (41-45, 1073-1084, 1779-1791) pins the build 109 sentences of `docs/bridge-guide.md` and `docs/install-ipm.md`: unchanged (D7).
- `docker/tests/test-install-script-live.sh` -- read only. Real install.sh in a lane throwaway with `IRIS_IMAGE=$P-base:<tag>` and a source name `$P-src/irishealth-community:<154 tag>` on the shared base's ID; asserts `Image: IRIS for Health` and `The existing $test_base is that image`. On this machine the 109 image is loaded beside several 154 refs, so the unit also shows 154 is preferred. Run as `ci/iris.sh live install-script-live` (group `install-fresh`, `ci/units.sh:68`).
- `ci/units.sh` -- read only: `install-script` and `readme` are in `CHECK_SCRIPTS` (6), run by `bash ci/checks.sh`; install.sh is unclassified on purpose (169-170), so a change to it runs every CI group. `.github/workflows/ci.yml` 41 (ShellCheck on install.sh and its test, CI only: no shellcheck on this machine, measured) and 45-54 (`install-macos`: `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh`; this machine's `/bin/bash` is 3.2.57).
- `docker/Dockerfile` (read only): `IRIS_IMAGE` is used only by `FROM ${IRIS_IMAGE}` (4-5), so a 109 image under the base name builds as the spike's `IRIS_IMAGE=<109 ref>` did.
- Measured on this machine (read only): `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0` is loaded (ID 78bfd01c5b6a, arm64, daemon arm64), beside the 154 refs `irishealth-community`, `iris-community`, their `docker.iscinternal.com/...` names and `ocutalon-iris-base:2026.3.0AI.154.0` (ID 4e3907db2004).

## Tasks & Acceptance

**Execution:**
- [x] `install.sh` -- add `TAG_109=2027.1.0AI.109.0` beside `TAG`; in `scan_images` accept a Health ref at `TAG_109` (no non-Health 109) and record each candidate's build; make every records reader follow; pick by the preference Health 154, Health 109, non-Health 154 (both at 268-271 and in the existing-base wrong-CPU fix at 236); print the build of the chosen or matched image; replace the changed messages with the approved texts (Design Notes, block B); update the header and scan comments to the accepted refs (contract only). -- DW-636, AC1-AC3
- [x] `docker/tests/test-install-script.sh` -- add `TAG_109`; new cases: build 109 only (prefixed): exit 0, `tagged_once`, `up_env_is "$BASE"`, the build 109 image line; the prefix loop over the four forms at `TAG_109`; both Health builds in both sort orders (bare 154 with `a/...:$TAG_109`, and `z/...:$TAG` with bare 109): 154 is the source; Health 109 beside non-Health 154: Health 109 used; Health 109 for x64 with non-Health 154 for arm64: the mixed-CPU line names the 109 ref; refused third refs (the Matrix row) each in its own case: exit 1, the new no-image message, `no_change`; existing base with the 109 image's ID: the build 109 existing line; wrong CPU with only Health 109: the new wrong-CPU line; a source pin that `^TAG_109=` is `2027.1.0AI.109.0`. Update pins 322, 351, 352, 430, 438, 459 to the approved texts, and header rows 9-13 to name build 109 and the refused refs. -- AC1-AC3 pins
- [x] `README.md` -- apply passages P1 to P9 of block A exactly; remove the whole "Start it with build 109" section (P6). -- AC4
- [x] `docker/tests/test-readme.sh` -- apply "Pins changed" R1 to R12 in place: new texts word for word, the negative pins that the separate path is gone, the self-tests rewritten so each still breaks its rule; touch no other line. -- AC5
- [ ] Manual build 109 run (once) -- see Verification; record the result in this spec. -- AC6
- [x] This spec -- record Verification results and the `mutation:` lines.

**Acceptance Criteria:**
- AC1 (DW-636, accepted refs). Given a Docker host with `irishealth-community:2027.1.0AI.109.0` (bare or with a registry prefix) or today's exact build 154 refs for its CPU, when install.sh checks the image, then it accepts each by its exact ref, and every other ref (the Matrix's refused rows included) takes today's no-image path, exit 1, nothing changed; `test-install-script.sh` pins both accepted builds and the refused refs, and the mutations below turn it red.
- AC2 (preference). Given Health 154 and Health 109 for this CPU, in either sort order, when install.sh picks, then build 154 is tagged and named; Health 109 is used before non-Health 154.
- AC3 (messages). Given each path of the Matrix, when install.sh prints, then its lines are exactly block B's texts, and no other message or exit code changed (the unchanged pins stay green).
- AC4 (one path). Given the README, when a judge with build 109 follows "Try it in two minutes" or "Install it yourself", then one path covers both builds in block A's wording word for word, there is no "Start it with build 109" section and no link to `#start-it-with-build-109`, and `test-readme.sh` passes (readme-links and product-links included).
- AC5 (pins updated). Given `test-readme.sh`, when its `try-it` and `install` rules run, then they pin block A's passages and the absence of the separate path, every self-test still breaks its rule, each pin in "Pins changed" is changed in place, and no line in Epic 34's regions changed.
- AC6 (real runtime). Given this machine with the real build 109 image loaded beside build 154, when `live install-script-live` runs and the manual build 109 run runs, then the first passes unchanged (build 154 preferred) and the second shows the build 109 line, reaches healthy and signs in with the printed account.
- AC7 (footprint). Given the diff since `story_base` without `_bmad-output`, when listed, then it holds only `install.sh`, `README.md`, `docker/tests/test-install-script.sh` and `docker/tests/test-readme.sh`.
- DW-636 (ledger): closed by AC1 to AC5 (install.sh finds the build 109 image; the README's separate path is dropped).

## Spec Change Log

## Review Triage Log

### 2026-11-05 -- Review pass
- verdicts: 19 findings -- high 0, medium 3, low 16, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: a stale existing base name wins silently over a newly loaded build 109 image -- the spec's Always rule keeps "a base name that exists is never moved (unchanged)"; a fix is new behaviour and new public text.
  - `[low]` `[reject]` Blind: an `IRIS_IMAGE=` line in `.env` left by the removed README section is not mentioned -- spec-bound: P3/P6 are the approved text and no other user-facing wording may be added; install.sh reads the env, not `.env`, as before.
  - `[low]` `[reject]` Blind: `docker/Dockerfile` line 1 comment still says build 154 -- Design Notes D7 leaves it on purpose (Epic 34 edits that file; Boundaries forbid touching it).
  - `[low]` `[reject]` Blind: AC6's manual build 109 run is unrecorded and the Auto Run Result looked stale -- the manual run is the lead's committed evidence by the stage prompt; the Auto Run Result is rewritten at finalize.
  - `[medium]` `[patch]` Blind: no case for Health 154 of another CPU beside Health 109 of this CPU -- real gap in `pick_health`'s fall-through; patched: case `health-154-other-cpu-with-109` added, mutation recorded (grouped with the two rows below).
  - `[low]` `[reject]` Blind: the mixed-CPU line names only the first Health ref -- Design Notes D5 decided it.
  - `[low]` `[reject]` Blind: `T_B109_CPU` pins only the heading prefix of the CPU Troubleshooting entry -- P9 changes only the quoted message and the spec says the rest of the line stays; the quote is pinned word for word.
  - `[low]` `[reject]` Blind: `#get-the-image` in `TRY_FACTS` duplicates a link in step 1 -- R2 mandates it (spec-bound).
  - `[low]` `[reject]` Blind: no README way to force build 109 when both are loaded -- spec-bound (preference rule and approved text; any new sentence is unapproved public text).
  - `[low]` `[patch]` Edge: the existing-base wrong-CPU fix with Health 109 and non-Health 154 of this CPU is unpinned -- patched: case `base-wrong-cpu-109-before-non-health`, mutation recorded.
  - `[medium]` `[patch]` Edge: Health 154 of another CPU beside Health 109 of this CPU is untested -- same root cause as the Blind row above; patched with that case.
  - `[low]` `[patch]` Edge: `mixed-cpus-109` checks neither the exit code nor `IRIS_IMAGE` -- patched: both checks added, mirroring `mixed-cpus`.
  - `[low]` `[reject]` Edge: the existing-base ID match takes the first record, not the preferred one -- refs that share an ID are the same image, and builds 154 and 109 cannot share an ID; the line stays true; unchanged behaviour.
  - `[low]` `[reject]` Edge: README P4 says "when both are, it uses build 154" while Health 109 beats non-Health 154 -- approved text (P4); the spec's preference rule is Health 154, Health 109, non-Health 154.
  - `[low]` `[reject]` Edge: a stale base with only build 109 loaded -- same as the first Blind row; unchanged behaviour.
  - `[medium]` `[patch]` VG: same Health 154 other-CPU beside Health 109 gap -- patched with the same case.
  - `[low]` `[reject]` VG: no mutation lines for B2, B3, B4 and the call site -- Rule 19 asks one demonstrated mutation per AC; AC3 has one; a mutation for the call site is added with the patch above.
  - `[low]` `[reject]` VG: AC6 has no automated proof and was not run -- the lead's committed evidence (Planner condition 1).
  - `[low]` `[patch]` VG (other findings): no self-test rewrites P9's quote alone -- patched: self-test 'the Troubleshooting CPU quote back to build 154 only' added in `rule_install`; it must flag, and `test-readme.sh` passes with it.
  - Intent alignment: descriptive only, no finding; it reports the 109 runtime on real Docker (AC6) as the lead's pending smoke.


## Design Notes

**Governing ADs.** AD-23 (one image recipe; the install script retags whichever accepted archive was loaded to `ocutalon-iris-base:2026.3.0AI.154.0` and prefers the Health image; its Prevents line "two install paths drifting apart" is what retiring the separate build 109 path serves), AD-22 (test tiers: install.sh's hermetic test in the hosted `checks` and `install-macos` jobs, live units on throwaways; the AI Hub image never enters a cache or artifact, so CI has no build 109 image and the 109 runtime proof is the local manual run), AD-29 (Lane B files: `docker/tests/`). No AC contradicts an AD's Prevents line.

**For the lead (Rule 20, AD-23's Rule text).** AD-23's Rule names the accepted archives as two refs. The charter (the Planner's ruling, story AC) adds the Health build 109 ref, so the Rule's wording should follow. Recommended: "The install script retags whichever archive was loaded (`irishealth-community:2026.3.0AI.154.0`, `irishealth-community:2027.1.0AI.109.0` or `iris-community:2026.3.0AI.154.0`) to `ocutalon-iris-base:2026.3.0AI.154.0`, the name every compose file expects, prefers the Health image when both are present (build 154 before build 109), and passes the build argument otherwise." The planner stage changes no spine text; an AD wording change is the lead's (veto-window category).

**Decided in-stage.**
- D1. "Exact ref" means the repository's last path segment and the tag are exactly an accepted pair, with or without a registry prefix: the rule today's 154 refs already follow (`install.sh:180-182`). The portal's archive loads as `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0` (measured here, and quoted by today's README), so a bare-only match would refuse the very image the story is for.
- D2. Plain IRIS build 109 (`iris-community:2027.1.0AI.109.0`) is refused: the charter names only the Health 109 ref, and the README says it is untested.
- D3. Preference Health 154, Health 109, non-Health 154: Health first as AD-23 says; 154 before 109 because 154 is CI's tested build, and sort order alone would pick 109 for some prefix pairs (e.g. bare 154 against `a/...:2027.1.0AI.109.0`).
- D4. A 109 image gets the same base name and `IRIS_IMAGE` as a Health 154 image (AD-23's single name; the Dockerfile reads `IRIS_IMAGE` only in `FROM`). The README's hand path says so in one sentence (P5), so the `154` inside the name is not read as a claim about the image.
- D5. When a Health 109 image is used while a Health 154 image for another CPU is loaded, no extra line is printed (smaller); the mixed-CPU line for the non-Health choice names the first Health ref of the records, whichever build.
- D6. README step 1 (15) and "Get the image"'s first paragraph (92) stay: both already name both builds. The first sentence of 94 stays word for word: it is the measured 1.0.0 claim.
- D7. Unchanged on purpose: `docs/bridge-guide.md` and `docs/install-ipm.md` build 109 sentences (about the bridge guide and the IPM install, not install.sh; their pins sit in Epic 34's contended header region), `release/records/1.0.0/rc4.md` (a record), `docker/Dockerfile` comment line 1 (the default base; Epic 34 edits that file), `test-install-script-live.sh` (stays the 154 regression; CI has no 109 image).
- D8. The Troubleshooting quotes follow install.sh's new first lines word for word; no new cross-file check is added (both sides are pinned word for word by their own tests).
- D9. The changed install.sh messages are public text, so they are in the approval block (block B) with the README.

**Rule 1/2.** No service, module or shared component is introduced; no Integration AC applies. Extend, don't copy: the 109 entry and the build field extend `scan_images`, `pick` and the existing records readers (no second scanner); new hermetic cases use `new_case`/`add_image`/`run_install` and the existing assertion helpers; the README pins extend `chk_try_it`/`chk_install` and the `st`/`st_facts` self-test helpers.

**Ledger (Rule 17).** DW-636 is the only entry owned by this story: addressed by AC1 to AC5.

**Contended regions.** Epic 34 (open) changes README.md at 343 and `test-readme.sh` at 40, 135, 167 and from 1058 (`chk_licence`, `rule_licence`); Epics 17 and 40 change only `docs/` files this story does not touch. This story's hunks (README 16-246; test-readme 10-12, 30-33, 430-465, 616-672, 1216-1230, 1381-1389) are different hunks, so the second merge is a plain union. Keep the header edit inside lines 30-33 (34-45 untouched).

### README text for approval

**[Lead, 2026-11-05] APPROVED by the Contest Planner under the owner's delegation (relayed by the orchestrator): Block A with one change (P2's new text, below, replaces the drafted one; P1 and P3 to P9 and the anchor removals exactly as listed); Block B as written. Use this text verbatim; no other user-facing wording. Conditions: (1) the lead's manual install.sh smoke on the build 109 throwaway is committed as evidence (`_bmad-output/implementation-artifacts/evidence/11-23-build-109-install.md`: the image line printed, the start, the sign-in page answering 200, demo guide step 1); (2) test-readme is updated in place, no pin deleted, and pins are ADDED for P2's new wording.**

Two blocks of public text for the Contest Planner, word for word. Block A is README.md (old, new, per passage, with its section); block B is install.sh's printed lines (`<cpu>`, `<ref>` and `<base>` are filled in by the script at run time). Every line not listed stays as it is.

**Block A: README.md**

P1. "Try it in two minutes", step 2 (line 16). Step 1 stays as it is.
- Old: ``2. Clone this repository and run `./install.sh` in its folder ([what it does](#start-it-with-the-install-script)). With build 109, follow [Start it with build 109](#start-it-with-build-109) instead.``
- New: ``2. Clone this repository and run `./install.sh` in its folder ([what it does](#start-it-with-the-install-script)).``

P2. "Get the image", second paragraph (line 94). The first paragraph stays as it is.
- Old: ``OcuTalon 1.0.0 also runs unchanged on build 109: its install, production and test checks and the demo guide pass on it. In this release, `./install.sh` looks only for build 154, so with build 109, start OcuTalon as [Start it with build 109](#start-it-with-build-109) shows.``
- New (APPROVED with the Planner's change): ``OcuTalon also runs on build 109: at release 1.0.0 its install, production and test checks and the demo guide passed on it, and `./install.sh` accepts either build.``

P3. "Start it with the install script", first line (line 106).
- Old: ``The install script needs build 154. With build 109, see [Start it with build 109](#start-it-with-build-109).``
- New: (removed, with the empty line after it; the section starts with its code block)

P4. "Start it with the install script", paragraph after the code block (line 114); only its first sentence changes.
- Old: ``The script checks that Docker and Docker Compose work and that a build 154 image for your CPU is loaded.``
- New: ``The script checks that Docker and Docker Compose work and that a build 154 or build 109 image for your CPU is loaded; when both are, it uses build 154.``

P5. "Start it by hand", first paragraph (line 128). The code block and the paragraph after it stay as they are.
- Old: ``Without the script, give the loaded image the name OcuTalon builds from, then start it. `docker load` printed the loaded image's name; for the IRIS for Health archive it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`.``
- New: ``Without the script, give the loaded image the name OcuTalon builds from, then start it. `docker load` printed the loaded image's name; for the IRIS for Health archive of build 154 it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`, and for build 109 it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0`. The name is `ocutalon-iris-base:2026.3.0AI.154.0` for both builds.``

P6. "Start it with build 109" (lines 138-151): the whole section is removed: its heading `### Start it with build 109`, its paragraph, its code block (`git clone`, `cd OcuTalon`, `cp .env.example .env`, `echo 'IRIS_IMAGE=<the name docker load printed>' >> .env`, `docker compose up -d`) and its closing paragraph (``Skip the `cp` step when `.env` already exists. Keep the `IRIS_IMAGE` line in `.env`, because every `docker compose up -d` reads it, an update included. Then [check that it is ready](#check-that-it-is-ready) and [sign in](#sign-in).``).
- New: (none; "Start it by hand" is followed by "The IRIS (non-Health) image")

P7. "The IRIS (non-Health) image", first paragraph (line 154); only its last sentence changes.
- Old: ``Build 109's plain IRIS image has not been tested.``
- New: ``Build 109's plain IRIS image has not been tested, and `./install.sh` does not use it.``

P8. "Troubleshooting", first entry (line 244).
- Old: ``**"No IRIS build 154 image is loaded in Docker"**: download the archive for your CPU ([Get the image](#get-the-image)), load it with `docker load -i <the archive file>`, then run `./install.sh`. With build 109, follow [Start it with build 109](#start-it-with-build-109) instead of running `./install.sh`.``
- New: ``**"No IRIS build 154 or build 109 image is loaded in Docker"**: download the archive for your CPU ([Get the image](#get-the-image)), load it with `docker load -i <the archive file>`, then run `./install.sh`.``

P9. "Troubleshooting", second entry (line 246); only its quoted message changes, the rest of the line stays.
- Old: ``**"The IRIS build 154 image that is loaded is for another CPU than this machine's"**:``
- New: ``**"The IRIS build 154 or build 109 image that is loaded is for another CPU than this machine's"**:``

Anchors: `#start-it-with-build-109` is removed, and every link to it goes with it (README lines 16, 94, 106 and 244: P1, P2, P3, P8; no page or server text links it, measured with `git grep`). Kept, with every link to them: `#get-the-image`, `#start-it-with-the-install-script`, `#start-it-by-hand`, `#the-iris-non-health-image`, `#check-that-it-is-ready`, `#sign-in`, `#troubleshooting`.

**Block B: install.sh's printed lines**

B1. No accepted image loaded (285-286). Old:
- `No IRIS build 154 image is loaded in Docker (no irishealth-community:2026.3.0AI.154.0, and no iris-community:2026.3.0AI.154.0).`
- `Download the IRIS for Health AI Hub build 154 archive for this machine's CPU (<cpu>; the archives are for arm64 or x64) and load it:`

New:
- `No IRIS build 154 or build 109 image is loaded in Docker (no irishealth-community:2026.3.0AI.154.0, no irishealth-community:2027.1.0AI.109.0, and no iris-community:2026.3.0AI.154.0).`
- `Download the IRIS for Health AI Hub build 154 or build 109 archive for this machine's CPU (<cpu>; the archives are for arm64 or x64) and load it:`

B2. Loaded images are all for another CPU (290, 292). Old:
- `The IRIS build 154 image that is loaded is for another CPU than this machine's. This machine's Docker runs <cpu>.`
- `Download the IRIS for Health AI Hub build 154 archive for <cpu> and load it:`

New:
- `The IRIS build 154 or build 109 image that is loaded is for another CPU than this machine's. This machine's Docker runs <cpu>.`
- `Download the IRIS for Health AI Hub build 154 or build 109 archive for <cpu> and load it:`

B3. The base name exists for another CPU and no accepted image for this CPU is loaded (239-240). Old:
- `Download the IRIS for Health AI Hub build 154 archive for <cpu> and load it:  docker load -i <the archive file>`
- `Then point the name at the loaded image:  docker tag <the loaded image, ending in irishealth-community:2026.3.0AI.154.0> <base>`

New:
- `Download the IRIS for Health AI Hub build 154 or build 109 archive for <cpu> and load it:  docker load -i <the archive file>`
- `Then point the name at the loaded image:  docker tag <the loaded image, ending in irishealth-community:2026.3.0AI.154.0 or irishealth-community:2027.1.0AI.109.0> <base>`

B4. The image line (260, 265, 270). Unchanged: `Image: IRIS for Health, build 154 (<ref>).`, its existing-base form, and both non-Health lines. New lines for a Health 109 image:
- `Image: IRIS for Health, build 109 (<ref>).`
- `Image: IRIS for Health, build 109 (<ref>). The existing <base> is that image, so it is not tagged again.`

Changed (265). Old: `Image: the existing <base>. No IRIS for Health or IRIS (non-Health) build 154 image loaded here has its ID, so it is used as it is.` New: `Image: the existing <base>. No IRIS build 154 or build 109 image loaded here has its ID, so it is used as it is.`

### Pins changed (`docker/tests/test-readme.sh`, condition 3)

Each is changed in place, never deleted; the variable names stay.
- R1. Header 10-12 (`try-it`): "...and leads to the build 109 section; steps 1 and 2 are the ruled build 109 steps, word for word (U-241 item 1)" becomes: the local path is four numbered steps; steps 1 and 2 are pinned word for word (U-241 item 1, Story 11.23), and the section never links `#start-it-with-build-109`.
- R2. `TRY_FACTS` line `#start-it-with-build-109` becomes `#get-the-image`.
- R3. `TRY_B109` line 2 becomes P1's new text (line 1, step 1, unchanged).
- R4. `chk_try_it` gains one negative check: the section holds no `#start-it-with-build-109` (message `try-it: step 2 still sends build 109 to a separate path`); `rule_try_it` gains the self-test 'the separate build 109 step back' (P1's old sentence appended to step 2), which it must flag.
- R5. Header 30-33 (`install`): the build 109 facts become: its image names, one install path for both builds (no "Start it with build 109" section, no link to it, no `IRIS_IMAGE=` line), its plain IRIS image untested and not used by install.sh, and block A's passages of "Get the image", "Start it with the install script", "Start it by hand" and Troubleshooting, word for word (U-241, Story 11.23). Stay within lines 30-33.
- R6. `INSTALL_FACTS` `IRIS_IMAGE=` becomes `build 154 or build 109`; `#start-it-with-build-109` becomes ``The name is `ocutalon-iris-base:2026.3.0AI.154.0` for both builds.``; `irishealth-community:2027.1.0AI.109.0` stays.
- R7. "Build 109's plain IRIS image has not been tested." becomes P7's new sentence.
- R8. "The install script needs build 154. With build 109, see [...]" becomes P4's new sentence.
- R9. `INSTALL_B109` (five lines) becomes four: "Get the image"'s first paragraph (unchanged), P2 new, P5 new, and the whole first paragraph of "The IRIS (non-Health) image" with P7 new.
- R10. `T_B109` becomes P8's new line; a second Troubleshooting pin holds P9's new quoted message (as `T_B109_CPU`); the message reads `install: the Troubleshooting entries do not quote install.sh's build 154 or build 109 messages word for word`.
- R11. `H_B109` and its position checks become negative pins: the install section holds no line `### Start it with build 109` and no `IRIS_IMAGE=`, and the README holds no `(#start-it-with-build-109)`; messages `install: the separate '### Start it with build 109' path is back` and `install: IRIS_IMAGE= is back in the install sections`.
- R12. Self-tests 1383-1388 become, one for one: the build 109 heading inserted before `### The IRIS (non-Health) image`; P2's old second sentence appended to P2; `echo 'IRIS_IMAGE=<the name docker load printed>' >> .env` inserted after `cp .env.example .env` in "Start it by hand"; P4 back to "a build 154 image"; P8's old sentence appended to P8; P8's quote back to "No IRIS build 154 image". Each must be flagged. The `finish install` description (1389) names "one install path for build 154 and build 109".

## Verification

Run from the epic worktree root, each command in the foreground with `timeout: 600000`, one live unit per call, never two in one message. `LANE` stands for:

`env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=11 stage=implement' OCUTALON_RUN_TAG=e11s23i`

After each live run, also after a failure, run `LANE bash ci/iris.sh teardown`. No class changes, so no slot or warm stack is needed. ShellCheck runs only in CI's `checks` job (not installed here).

**Shared surfaces:** install.sh's printed lines and exit codes (`test-install-script.sh`; `test-install-script-live.sh` reads `Image: IRIS for Health` and `The existing <base> is that image`; `test-readme.sh` `chk_install_pointer` and `chk_commands` read install.sh's README pointer and `run: docker compose` lines, all unchanged); the README sections and anchors that `test-readme.sh` pins (`try-it`, `install`, `readme-links`, `product-links`, `commands`, `install-pointer`), with `#start-it-with-build-109` removed and every link to it removed. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- `(loop)` `bash docker/tests/test-install-script.sh` -- expected: every check passes, the new cases included.
- `(loop)` `bash docker/tests/test-readme.sh` -- expected: every rule PASS (no self-test note).
- `(once)` `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh` -- expected: pass under bash 3.2.
- `(once)` `bash docker/tests/test-readme.sh` then `bash docker/tests/test-install-script.sh`, then the reverse order -- expected: all pass both ways.
- `(once)` `bash ci/checks.sh` -- expected: every static and hermetic script passes (boundaries ASCII and public-text scans included).
- `(once)` `LANE bash ci/iris.sh live install-script-live` -- expected: pass unchanged on this machine with the build 109 image loaded (154 preferred); then `LANE bash ci/iris.sh teardown`.
- `(once)` Manual build 109 run, from a scratch script in the stage's scratchpad subfolder (never in the tree): source `docker/tests/lib-live.sh` with `LANE`, `live_start t23` and `live_web_port` as `test-install-script-live.sh` does; `docker tag <the loaded build 109 Health ref> "$P-base:2026.3.0AI.154.0"`; run the real `bash install.sh` with `COMPOSE_PROJECT_NAME="$P"`, `COMPOSE_FILE` from `LIVE_FILES`, `IRIS_IMAGE="$P-base:2026.3.0AI.154.0"` and `OCUTALON_INSTALL_WAIT=600`. Expected: exit 0; the line `Image: IRIS for Health, build 109 (<the 109 ref>). The existing $P-base:2026.3.0AI.154.0 is that image, so it is not tagged again.`; the ready block; the printed account signs in (curl, as the live test). Then `docker image rm "$P-base:2026.3.0AI.154.0"` without `-f` and `LANE bash ci/iris.sh teardown`. Record exit code, first-start time and the image line. If the build 109 image is no longer loaded, record that and skip (never load or pull it). A failed start on 109 is a finding for the lead (block A claims install.sh accepts build 109), not something to work around.
- `git status --short` and `git diff --stat` -- expected: only the four files of AC7 (and this spec), no leftover mutation.

**Mutations (Rule 19; apply, observe red, revert, confirm the tree byte-identical):**
- AC1: let `scan_images` accept any tag for `irishealth-community` -> the refused-refs cases red. Drop the 109 entry -> the build 109 cases red. Accept `iris-community` at `TAG_109` -> the `iris-community:2027.1.0AI.109.0` refused case red.
- AC2: pick the first Health ref in sort order, whatever its build -> the both-builds case with `a/...:$TAG_109` red.
- AC3: put back B1's old first line -> the no-image case red.
- AC4/AC5: put back P1's old sentence in README.md -> `test-readme.sh` `try-it` red; put back the `### Start it with build 109` section -> `install` red; put back P8's old quote -> `install` red.
- AC6 and AC7 carry no mutation (a measured run and a diff listing).

### Implement-stage results

- `bash docker/tests/test-install-script.sh`: all checks passed (297 PASS before the final pin; run again after the mutations, green). Under `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash` (3.2.57): passed.
- `bash docker/tests/test-readme.sh`: all rules passed, no self-test note. Both orders (readme then install, install then readme) passed.
- `bash ci/checks.sh`: `checks: all scripts passed`.
- `ci/iris.sh live install-script-live` (lane B, run tag e11s23impl): `test-install-script-live: all checks passed`; the line printed was `Image: IRIS for Health, build 154 (docker.iscinternal.com/...irishealth-community:2026.3.0AI.154.0). The existing <throwaway base> is that image, so it is not tagged again.` (build 154 preferred with the 109 image loaded). `ci/iris.sh teardown` afterwards: 0 projects, containers, volumes, networks and images left.
- Manual build 109 run: not run by the implement stage (the lead's, committed as evidence).
- ShellCheck: not installed here (CI's `checks` job runs it).
- mutation: AC1 `scan_images` accepts any tag for `irishealth-community` -> `test-install-script.sh` red (15 FAIL: look-alikes and the refused-refs cases); reverted byte-identically.
- mutation: AC1 the 109 entry dropped from `scan_images` -> red (18 FAIL: build 109 only, the four prefix forms, 109 beside non-Health, existing base, wrong CPU and mixed CPU cases); reverted byte-identically.
- mutation: AC1 `iris-community` accepted at `TAG_109` -> red (6 FAIL: the `iris-community:2027.1.0AI.109.0` and `x/iris-community:...109.0` refused cases); reverted byte-identically.
- mutation: AC2 `pick` takes the first Health ref in sort order whatever its build -> red (6 FAIL: the both-builds cases with `a/...:$TAG_109` and bare 109 beside `z/...:$TAG`); reverted byte-identically.
- mutation: AC3 B1's old first line put back (`No IRIS build 154 image is loaded in Docker (no`) -> red (9 FAIL: the no-image pin, look-alikes and the refused-refs cases); reverted byte-identically.
- mutation: AC4 P1's old sentence put back in README.md -> `test-readme.sh` `try-it` red (`install` and `readme-links` red too); reverted byte-identically.
- mutation: AC5 the `### Start it with build 109` section put back in README.md -> `install` red; reverted byte-identically.
- mutation: AC5 P8's old quote (`No IRIS build 154 image is loaded in Docker`) put back in README.md -> `install` red; reverted byte-identically.
- mutation: AC2 (review patch) `pick_health` falls through to Health 109 only when no Health 154 record exists, whatever its CPU -> `health-154-other-cpu-with-109` red (3 FAIL); reverted byte-identically.
- mutation: AC2/AC3 (review patch) the existing-base wrong-CPU fix calls `pick h 154 || pick n 154` instead of `pick_health || pick n 154` -> `base-wrong-cpu-109` and `base-wrong-cpu-109-before-non-health` red (2 FAIL); reverted byte-identically.
- After the review patches (four test additions: `health-154-other-cpu-with-109`, `base-wrong-cpu-109-before-non-health`, exit and `IRIS_IMAGE` checks in `mixed-cpus-109`, and the self-test 'the Troubleshooting CPU quote back to build 154 only'): `test-install-script.sh` passed (also under `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash`, 3.2.57), `test-readme.sh` passed, both orders passed, `bash ci/checks.sh` printed `checks: all scripts passed`, and `ci/iris.sh live install-script-live` (lane B, tag e11s23i2) printed `test-install-script-live: all checks passed` with `Image: IRIS for Health, build 154 (...)` (build 154 preferred beside the loaded build 109 image); `ci/iris.sh teardown` left nothing.
- After the mutations: `git status --short` lists only README.md, install.sh, `docker/tests/test-install-script.sh`, `docker/tests/test-readme.sh` and this spec; each mutated file was `cmp`-identical to the pre-mutation backup.
- mutation: AC3 (QA) B3's first line in the existing-base wrong-CPU fix (`build 154 or build 109 archive`, install.sh line 271) changed to `build 10X` -> `test-install-script.sh` stayed GREEN (0 FAIL, a gap), so QA added the pin `existing base, wrong CPU, no image loaded: the download line names build 154 or build 109 and this CPU`; with the pin the same mutation is red (1 FAIL); reverted byte-identically.
- mutation: AC3 (QA) each other changed message of install.sh (the B3 tag line `$TAG_109`, the unknown-existing-base line, the no-image first and download lines, the other-CPU first and download lines) changed one at a time -> red each (1, 2, 12, 1, 1, 1 FAIL); reverted byte-identically.
- mutation: AC3 (QA) the build named in the image line forced to 154 (`build $pick_build`, `build $base_build`, and `base_build=$build`) -> red (3, 1, 1 FAIL); reverted byte-identically.
- mutation: AC1 (QA) `scan_images` compares the 109 tag as a prefix (`2027.1.0AI.109` and more) instead of exactly -> red (6 FAIL: the refused `.109.1` cases); reverted byte-identically.
- mutation: AC4/AC5 (QA) `109` changed to `10X` on each of the README lines that carry the build 109 wording (15, 92, 94, 112, 126, 138, 228, 230), one at a time -> `try-it` red for line 15, `install` red for every other; reverted byte-identically.
- mutation: AC4 (QA) a link to `#start-it-with-build-109` appended at the end of README.md, outside the try-it and install sections -> `install` and `readme-links` red; reverted byte-identically.
- QA gap audit: every AC1-AC5 and Matrix row has a pinning test; the one gap (B3 download line) is closed. After the QA edits `test-install-script.sh` passed (also under `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash`, 3.2.57) and `test-readme.sh` passed; install.sh and README.md are `cmp`-identical to their pre-mutation copies; the diff since `0242c7b2` still touches no line of Epic 34's regions of `test-readme.sh`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `install.sh` accepts exactly the three refs (`irishealth-community:2026.3.0AI.154.0`, `iris-community:2026.3.0AI.154.0`, `irishealth-community:2027.1.0AI.109.0`, with or without a registry prefix) and refuses every other ref. It prefers Health 154, Health 109, then non-Health 154, tags a Health 109 image to the same base name, and prints Block B's lines. README.md has one install path for both builds (P1 to P9, the Planner's P2), and `test-readme.sh` follows (R1 to R12 in place, no pin deleted, P2's new wording pinned as a whole line).

**Files changed.**
- `install.sh`: `TAG_109`, a build field in the scan records, `pick <kind> <build>`, `pick_health`, the Block B messages and the matching comments.
- `README.md`: passages P1 to P9; the "Start it with build 109" section and its links are gone; Credits and licences untouched.
- `docker/tests/test-install-script.sh`: build 109 cases (only, four prefix forms, refused refs, both Health builds in four sort orders, beside non-Health, mixed CPUs, other-CPU 154 beside this-CPU 109, existing base, wrong CPU, existing-base wrong CPU, source pin of `TAG_109`) and the changed message pins.
- `docker/tests/test-readme.sh`: R1 to R12 and one extra self-test; Epic 34's regions untouched.
- This spec: Verification results, mutation lines, triage log.

**Review findings.** 19 findings: patches applied 4 entries (one medium, three low; all test additions), deferred 0, rejected 15 with their reasons in the triage log (spec-bound text, unchanged behaviour, the lead's AC6 run, Design Notes D5 and D7).

**Follow-up review recommended:** false (one medium entry patched, no high).

**Verification.** See "Implement-stage results" under `## Verification`: both hermetic scripts, bash 3.2, both orders, `bash ci/checks.sh` and `ci/iris.sh live install-script-live` all pass; ten mutations went red and were reverted byte-identically.

**Residual risks / for the lead.** (1) The manual install.sh run on the loaded build 109 image (AC6, Planner condition 1, evidence file) is the lead's smoke; until it is committed, the README claim that `./install.sh` accepts build 109 rests on the stubbed tests and the live unit's 154 preference. (2) AD-23's Rule wording (see "For the lead (Rule 20)") is the lead's to apply. (3) ShellCheck runs only in CI. (4) `test-readme.sh` prints three pre-existing "Broken pipe" lines from the `in_tree` helper (line 139), which this story did not touch.
