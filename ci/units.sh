# Every list of the CI recipe, defined once (Story 0.7). Sourced by ci/iris.sh, ci/checks.sh, ci/changes.sh and
# docker/tests/test-ci-config.sh, which compares it with .github/workflows/ci.yml. Bash 3.2: no associative arrays.
# Defines variables and functions only.

# The hermetic and static scripts of the hosted `checks` job: docker/tests/test-<name>.sh.
CHECK_SCRIPTS="boundaries storage class-rules ci-config ci-changes compose-file pinned-sources after-start healthcheck lib-live bootstrap demo-path-gate ci-warm probe install-script readme eval-set online-host online-load upgrade-harness rehearsal release-checklist release-notes release-sequence redact-shapes cpf bridge-example bridge-guide triage-heartbeat"

# The scripts of the hosted `web` job.
WEB_SCRIPTS="web-build mock"

# Hosted `checks` scripts appended to CHECK_SCRIPTS above.
CHECK_SCRIPTS="$CHECK_SCRIPTS eval-personas heartbeat-overview mcp-notices"

# The %UnitTest shards, each a union of whole areas (OcuTalon.Test.<Area>), aligned with the lanes of AD-29.
SHARDS="lane-a lane-b"

# shard_areas <shard>: the areas of a shard.
shard_areas() {
  case $1 in
    lane-a) echo "Agent Bridge Checks Fix Install Tools Digest Watch Eval Channel Memory Docs Mcp" ;;
    lane-b) echo "Contract Core Data Demo Live Msg Schedule Web" ;;
    *) return 1 ;;
  esac
}

# The IRIS groups, in the order of the matrix of .github/workflows/ci.yml (eight since Epic 30's CI step, nine since Epic 12's close, ten since Story 19.8's CI split, sixteen since Story 0.20's rebalance).
IRIS_GROUPS="install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11"

# group_units <group>: the units of a group in the order they run. live:<name> is docker/tests/test-<name>.sh and
# shard:<name> is a %UnitTest shard. Every docker/tests/test-*.sh is in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or a group.
# A shard too long for one job runs in pieces, shard:<name>@<piece> (shard_unit_areas): every area of the shard is in exactly
# one piece, so every test class runs once. lane-a runs in eight pieces and lane-b in two (Story 0.20); shard:lane-a@rest in shards-2
# takes any area added to lane-a later, and shard:lane-b@rest in shards-6 any area added to lane-b. The CI rebalance of 2026-10-30
# (an owner decision, taken by the Contest Planner under the owner's delegation, carried by Story 9.6) moved live:cards out of
# install-fresh and live:audit out of install-upgrade, the two longest groups. Each unit runs in its own project and needs no state
# of its group's install, so a unit can sit in any group whose job builds what it reads. At Epic 29's integrate-forward of Epic 9
# (2026-10-31; the Contest Planner's rule: rebalance the combined layout to about 32-33 min a group, production only for units in
# NO_WEB_BUNDLE_UNITS, an eighth group only if seven cannot fit) the groups were packed again from the unit seconds measured on CI
# runs 41175908969 (OCT-epic29) and 41177721874 (OCT-epic9), the larger of the two for each unit: install-fresh about 1,850 s
# (install-start 676, bundle-folder 245, online-demo 593, online-demo-path 334 with Story 29.8's load phase), install-upgrade about
# 1,820 s (install-upgrade 653, cards 392, online-allowance 391, online-visitors 383), production about 1,300 s (its three units,
# 1,037, and live:audit, 267, which reads no web bundle), browser about 1,580 s, shards about 1,710 s (lane-a's Checks, Install
# and Watch 654, floor 621, online-session 439), shards-2 about 1,810 s (lane-a's other areas, Eval included, 1,334, and
# demo-switch 473) and image about 1,660 s. shard:lane-b cannot go to production, whose units read no web bundle, because its Web
# classes check the built bundle. Story 12.2 (2026-10-31, a runner ruling) made lane-a's Channel area a third piece of lane-a,
# shard:lane-a@Channel, in production: before the move, on af47ff3c (ci run 41188445340), shards-2 took 31 minutes and production
# 25. Its classes read no file of the bundle, so the unit is in NO_WEB_BUNDLE_UNITS.
# Story 11.7 swapped live:online-demo-path and live:install-script-live: the online unit grows by its steps 2 to 5 (the guide's watch
# and reminder, Break the feed and the approval, one visitor's journey), so it moved from install-fresh to image, and the shorter
# live:install-script-live moved the other way. From the unit seconds of CI run 41206732188 (Story 11.1's head): install-fresh is
# 2,007 - 358 + 270 = 1,919 s (install-start 739, bundle-folder 264, online-demo 646, install-script-live 270) and image is
# 1,692 - 270 + 358 + 5 = 1,785 s plus the growth of the online unit (storage-roundtrip 312, build-inputs 9, compose-start 201, lane-b
# 900 and about 5 for Story 11.7's two new tests (inference), online-demo-path 358 + the growth).
# Epic 30's CI step (2026-11-02; the Contest Planner's rule: every group at or under 33 minutes, an eighth group only if no packing of
# seven gets there) added the eighth group shards-3. From the largest unit seconds of CI runs 41350877752 (attempt 1), 41395335549,
# 41442099518, 41495443713 and 41526116324 (Epic 30 after Epic 11 part 1 merged; about 14,160 s in all), no packing of seven groups
# gets each group's units under about 1,940 s (33 minutes less the job's own setup): on 41495443713 shards-2 took 38.9 minutes and
# install-fresh, shards and install-upgrade 34 to 35. The groups now hold, in seconds: install-fresh about 1,830 (install-start 849,
# online-demo 664, install-script-live 314), install-upgrade about 1,880 (install-upgrade 827, online-visitors 431, online-allowance
# 415, compose-start 202), production about 1,330 (its three units; live:audit moved to shards-3, so production keeps room for
# shard:lane-a@Channel, Story 12.2, about 8 minutes, plus a minute), browser about 1,830, shards about 1,830 (lane-a's Checks, Install
# and Watch 902, online-session 530, cards 402), shards-2 about 1,820 (lane-a's other areas alone; any area added to lane-a later
# lands here), image about 1,740 (lane-b 1,013, online-demo-path 389, storage-roundtrip 325, build-inputs 13), and shards-3 about
# 1,890 (floor 734, demo-switch 524, bundle-folder 320, audit 310).
# Epic 12's close (2026-11-03, an orchestrator ruling, carried to the Contest Planner for main's required checks) added the ninth
# group shards-4 for shard:lane-a@Channel alone: that unit took 704 s in CI (ci run 41618490851), and on feature run 41612880963 the
# eight groups' steps took 24 to 31 minutes, so it fitted under 33 minutes in none of them; beside production-restart and
# reminder-restart it had also met the 40-minute job timeout (DW-591).
# Split by Contest Planner ruling 2026-11-05: live:sign-in 1047 s over the 1,000 s line. On ci run 42086496017 (OCT-epic34, attempt 2)
# browser took 2,043 s (demo-path 550, sign-in 1047, answers 446) and its job 34.5 minutes, and on 42087551083 (OCT-epic40, attempt 2)
# sign-in took 1,118 s and browser 2,206 s (37.3 minutes), against the 1,200 s deadline and the 35-minute budget (REL-4). About 260 s
# of each run was the unit's own build, start and setup and the rest the browser run (786 s and 834 s). The unit's spec files are now
# two Playwright projects, each on its own stack with the whole setup of docker/tests/test-sign-in.sh: live:sign-in keeps the project
# chromium in browser, and live:sign-in-2 (test-sign-in-2.sh) runs the project sign-in-2, the folders live/, phone/, rail/, reminder/,
# session/ and settings/ (web/playwright.config.ts SIGN_IN_2_DIRS; 129 of today's 323 tests, the stack-free wait specs of live/
# among them, about 160 s of wall-clock waits), in shards-4, the group with the most room: shard:lane-a@Channel alone took 729 s and
# 725 s on those runs (jobs of 12.7 minutes). Each half was aimed at about 400 s of browser run and so about 680 s a unit (under the
# 800 s that the ruling sets for each); browser becomes about 1,680 s and shards-4 about 1,410 s. Each unit prints one SPEC line per
# spec file with its seconds, so that a later move between the two projects can be made by spec file from CI's own numbers.
# Split again by the Contest Planner's ruling of 2026-11-07: after Story 4.11 added 96 more-to-try tests to the chromium project,
# live:sign-in took 1,034 s on feature 5b47f052 (ci run 42393186349) and 1,170 s on OCT-epic11 623b9cb0 (ci run 42392984136), over the
# 1,000 s line and close to its 1,200 s deadline, and browser took 2,104 s, over REL-4's 35-minute budget. The project sign-in-3
# (test-sign-in-3.sh) takes the folders guide/ and heartbeat/ and the root file heartbeat-card.spec.ts (web/playwright.config.ts
# SIGN_IN_3_DIRS and SIGN_IN_3_FILES; 137 of chromium's 339 tests): by the SPEC lines of 623b9cb0 about 429 s of browser run (guide/ 198,
# of which more-to-try 127, heartbeat/ 33, heartbeat-card 198) against about 421 s for what chromium keeps, and with about 260 s of build,
# start and setup a unit each, so each unit is about 690 s (inference). browser becomes about 1,750 s (inference). The new unit goes
# into shards-5, the only group with room for about 700 s: shard:lane-a@Bridge,Agent took 1,246 s on 5b47f052, so shards-5 becomes about
# 1,950 s, 32.5 minutes, plus 30 to 40 s for the job (inference until a run measures it); every other group plus 700 s passes 2,100 s.
# CI split of Story 19.8 (2026-11-07; the Contest Planner's ruling of about 13:35Z, discharging DW-826) added the tenth group shards-5 for
# shard:lane-a@Bridge,Agent, so that shard:lane-a@rest in shards-2 no longer runs the Bridge and Agent areas (rest is computed from the
# pieces the groups name, so every area of lane-a stays in exactly one piece). The new unit is not in NO_WEB_BUNDLE_UNITS, as shard:lane-a@rest
# is not, so shards-5 runs and skips on the inputs that its areas had in shards-2. Measured on part 1's head (ci run 42373301364): the
# shards-2 job was cancelled at its 40-minute timeout after 2,421 s, in the Memory area and before Tools (Fix 755, Bridge 665, Agent 282,
# Eval 178, Memory 76 so far, Docs 67 and Digest 37 s of classes, READY 267 s); Tools took 27 s on ci run 42375447084. Bridge and Agent
# are 947 s of that, so shards-2 is about 1,500 s and shards-5 about 1,250 s (inference until a run measures them).
# Story 19.4 (2026-11-07) added live:documents: the real /v1/documents routes over HTTP, four chat turns, a container restart and the 10 MB size check.
# Measured in ci run 42425571857 (a loaded queue): live:documents 315 s in shards-5. Story 32.5 puts live:sign-in-3 into shards-5, so live:documents runs in
# shards-3, whose units no Epic 19 story changes (that run: shards-3 1,807 s, shards-2 1,803 s, image 1,840 s; clean shards-3 about 1,710 s on ci run 42384900368).
# The Test.Docs classes run in shard:lane-a@rest.
# Story 19.5 (2026-11-08; the orchestrator's ruling of 2026-11-08, item 6, carried out before the push) added live:session-data (the online demo's per-session
# tables and sign-out, curl only, about 300 s in CI, inference from live:documents' 315 s with a restart; 155 s and 339 s on a lane-C throwaway) and the classes Test.Docs.{TurnTools,Sessions,
# SessionTurns,SessionLive}, Test.Memory.Drop and Test.Bridge.TurnTools (7, 35, 18, 0, 18 and 10 s on a lane-C warm stack), with Test.Docs.{Store,Ops,Turns}
# growing by about 25 s: about 100 s for the Docs and Memory areas and 10 s for Bridge. Measured inputs (green runs, group seconds): this branch at 881ac467 (ci run
# 42445320545) shards-2 1,766 (READY 280; areas Fix 738, Docs 225, Memory 197, Eval 170, Tools 93, Digest 40), shards 1,763, shards-3 1,976, shards-4 about 1,940,
# image about 1,790, shards-5 about 1,270 (Bridge and Agent only); the feature at 550bf9b8 (ci run 42425689094) shards-5 1,901 (Bridge and Agent 1,222 and Story
# 32.5's live:sign-in-3 678), shards 1,868, image 1,895, shards-3 1,831, shards-4 1,917, browser 1,765. Projection with the larger figure of each group and the
# feature's shards-5, which the integrate-forward brings: shards-2 would be 1,766 + 100 + 300 = 2,166 s, over the 2,100 s line, so the Eval area (170 s) moved out of
# shard:lane-a@rest into the piece of shards (rest is computed from the pieces the groups name, so every area of lane-a stays in exactly one piece): shards-2 about
# 1,996 s (Fix, Tools, Digest, Memory and Docs, and live:session-data) and shards about 2,038 s (1,868 + 170). shards-5 keeps about 1,911 s (1,901 + 10). No other
# group changes, and none is added, renamed or given a longer deadline. The first measured CI run replaces these figures (inference until then).
# Epic 41 (2026-11-08; the Contest Planner's ruling under the owner's delegation, for REL-4's 35 minutes) moved lane-a's Agent area out of
# shard:lane-a@Bridge,Agent into production as the piece shard:lane-a@Agent (no Agent test reads the web bundle, so it joins NO_WEB_BUNDLE_UNITS,
# as shard:lane-a@Channel did). Measured before the move (ci run 42485902344, 6aa10fd5): shards-5 job 35 min (shard:lane-a@Bridge,Agent 1,294 s,
# class time Bridge 673 s and Agent 309 s; live:sign-in-3 776 s) and production job 26 min (its four units 1,546 s). Projection: production about
# 1,546 + 309 + a stack start (about 250) = 2,105 s, shards-5 about 2,070 - 309 = 1,761 s plus Epic 41's specs in live:sign-in-3 (inference until a run
# measures them). No group is added, renamed or given a longer deadline.
# Story 0.20 (2026-11-09; the Contest Planner's rulings on DW-1025, relayed by the orchestrator: 16 groups, each planned to about 29 minutes; every
# shard: unit of two or more areas at 900 s or less, a single-area unit whole; no longer timeout) added shards-6 to shards-11 and cut lane-a into
# eight pieces and lane-b into two. On ci runs 42634825529, 42633085173, 42603815732 and 42583599821 every iris job took 31 to 41 minutes, and
# install-upgrade, shards-2, image, shards-3 and shards-4 met the 40-minute timeout with no failing test. Planned from the largest unit seconds of
# those runs; a new piece is its areas' largest class seconds plus 423 s, the largest stack start and teardown measured; a job adds 53 s. Pieces:
# Agent 633, Bridge 1,167, Channel 841, Docs 1,056, Fix 1,192 and Watch 937 s, one area each; Install, Digest and Eval 890 s; lane-a's rest (Checks,
# Tools and Memory) 866 s, 896 s with Epic 35's Mcp area; lane-b's Contract, Core, Data and Live 899 s and its rest (Demo, Msg, Schedule and Web)
# 898 s. Groups, in seconds of units: install-fresh 1,659, install-upgrade 1,657, production 1,620, browser 1,632, shards 1,464, shards-2 1,636, image
# 1,615, shards-3 1,559, shards-4 1,644, shards-5 1,641, shards-6 1,660, shards-7 1,643, shards-8 1,570, shards-9 1,665, shards-10 1,544 and shards-11
# 1,673, so at most 1,726 s (28.8 minutes) a job (inference until a run measures them). live:memory-offline stays in shards-4: with live:documents
# beside it in shards-6, no packing keeps every group at or under 1,687 s of units (the best is 1,749 s, 30.0 minutes).
# Story 8.8 (2026-11-10; DW-1018) added live:heartbeat-restart (docker/tests/test-heartbeat-restart.sh: one first start, two plain restarts and a wait of at
# most 120 s for the first tick after a restart with the heartbeat task suspended) to shards, the group with the most headroom on the two newest full green
# runs (shards 1,233 s of units in run 42730214385 and 1,346 s in run 42718893543; shards-7 1,341 and 1,288; image 1,287 and 1,353; shards-3 1,266 and 1,386;
# shards-10 1,451 holds the contended live:reminder-restart). The unit is estimated at 350 to 450 s (inference: live:compose-start is 173 to 191 s for a start,
# and a plain restart took 23 s in live:reminder-restart), so shards becomes about 1,580 to 1,800 s of units, about 27 to 30 minutes a job: inside REL-4's 35
# minutes and the 40-minute timeout, and possibly above Story 0.20's 1,687 s a group (inference until a run measures it). Locally, on a loaded ARM developer machine, the unit did 521 s of work (a first start of 276 s, restart 1 26 s to
# ready, the first tick 62 s after ready, restart 2 44 s), so the CI figure is the one to confirm. The unit reads no web bundle, but it is not added to NO_WEB_BUNDLE_UNITS: shards holds units that read
# it, so listing it would change no skip (list it if it ever moves to a group whose other units read no bundle). No group is added, renamed or given a longer deadline.
group_units() {
  case $1 in
    install-fresh) echo "live:install-start live:online-demo-path" ;;
    install-upgrade) echo "live:install-upgrade live:online-visitors" ;;
    production) echo "live:production live:production-restart shard:lane-a@Channel" ;;
    browser) echo "live:demo-path live:online-demo" ;;
    shards) echo "shard:lane-a@Install,Digest,Eval live:online-allowance live:heartbeat-restart" ;;
    shards-2) echo "shard:lane-a@rest live:session-data live:install-script-live" ;;
    image) echo "live:storage-roundtrip live:build-inputs shard:lane-b@Contract,Core,Data,Live live:compose-start" ;;
    shards-3) echo "live:floor live:demo-switch" ;;
    shards-4) echo "live:sign-in-2 live:memory-offline" ;;
    shards-5) echo "live:sign-in-3 live:security-overview live:audit" ;;
    shards-6) echo "live:documents shard:lane-b@rest live:bundle-folder" ;;
    shards-7) echo "shard:lane-a@Docs live:answers" ;;
    shards-8) echo "shard:lane-a@Watch shard:lane-a@Agent" ;;
    shards-9) echo "shard:lane-a@Bridge live:online-session" ;;
    shards-10) echo "live:sign-in live:reminder-restart" ;;
    shards-11) echo "shard:lane-a@Fix live:cards" ;;
    *) return 1 ;;
  esac
}

# shard_unit_areas <shard>[@<piece>]: the areas that the shard unit shard:<shard>[@<piece>] runs, on one line. With no piece they are
# every area of the shard. A piece is a comma-separated list of areas of the shard, or rest: the areas of the shard that no other
# piece of it in group_units names. Returns 1 for an unknown shard, an area that is not the shard's, an area named twice, or a piece
# with no area.
shard_unit_areas() {
  local shard=${1%%@*} piece areas a g u named="" out=""
  areas=$(shard_areas "$shard") || return 1
  case $1 in
    *@*) piece=${1#*@} ;;
    *)
      printf '%s\n' "$areas"
      return 0
      ;;
  esac
  if [ "$piece" = rest ]; then
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        case $u in
          "shard:$shard@rest") ;;
          "shard:$shard@"*) named="$named $(printf '%s' "${u#"shard:$shard@"}" | tr ',' ' ')" ;;
        esac
      done
    done
    for a in $areas; do
      case " $named " in
        *" $a "*) ;;
        *) out="$out $a" ;;
      esac
    done
  else
    for a in $(printf '%s' "$piece" | tr ',' ' '); do
      case " $areas " in
        *" $a "*) ;;
        *) return 1 ;;
      esac
      case " $out " in
        *" $a "*) return 1 ;;
      esac
      out="$out $a"
    done
  fi
  out=${out# }
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# unit_live_deadline <unit>: the floor, in seconds, of OCUTALON_LIVE_DEADLINE for a live unit (its name without live:); returns 1 for
# any other name. ci/iris.sh live runs a listed unit with at least this deadline, so the CI env's 1200 s does not cap it, and never
# lowers a higher given value. A floor is the larger of 1.4 times the unit's green median in seconds and, for the three sign-in units,
# the deadline that leaves their browser run 950 s or 1.4 times its median (Story 0.32, DW-1082, DW-1195; the audit is
# _bmad-output/implementation-artifacts/evidence/0-32-task0-ci-time-budgets.md), rounded up to 60 s and at most 2340 s, under the 40
# minutes of the iris job.
unit_live_deadline() {
  case $1 in
    install-start | install-upgrade) echo 1440 ;;
    sign-in | sign-in-2 | sign-in-3) echo 1500 ;;
    *) return 1 ;;
  esac
}

# The live units that drive Playwright and need its Chromium: ci/iris.sh live installs the browser before each of them.
BROWSER_UNITS="demo-path sign-in sign-in-2 sign-in-3 floor online-demo demo-switch answers cards online-session online-allowance online-demo-path online-visitors"

# The browser units that also run in Firefox and WebKit: ci/iris.sh live installs both after Chromium before each of them. Every name is in BROWSER_UNITS.
FIREFOX_WEBKIT_UNITS="floor"

# The paths whose change makes the web job run (ci/changes.sh): the web sources, the Live payload classes, the catalog
# classes that the page's generated catalog module and its tests read (Msg/Catalog.cls, Msg/Catalog/Core.cls,
# Msg/Catalog/Watch.cls, whose check sentences the page renders, and Msg/Enum.cls, whose fallback reasons the tests compare
# with the module) and the generated sign-in assets that the web build reads or writes, the UX design documents, the logo,
# the CI recipe (which holds the model mock and its scenarios) and the scripts that build the web and run the mock's tests,
# the three sign-in unit scripts (test-sign-in.sh, test-sign-in-2.sh and test-sign-in-3.sh, which the e2e-part tests of web/scripts/ read and run),
# the files that the mock's tests read (the agent classes' MOCKKEY, the tool names, the compaction prefix and the example
# agent of the bridge), the workflow itself, and the root .gitignore and .gitattributes, which decide whether the build
# leaves the checkout clean and how git checks out the files it reads.
WEB_INPUT_PATTERN='^(web/|src/ocutalon/cls/OcuTalon/Live/|src/ocutalon/cls/OcuTalon/Msg/Catalog\.cls$|src/ocutalon/cls/OcuTalon/Msg/Catalog/Core\.cls$|src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch\.cls$|src/ocutalon/cls/OcuTalon/Msg/Enum\.cls$|src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets\.cls$|_bmad-output/planning-artifacts/ux-designs/|logo/|ci/|docker/tests/test-web-build\.sh$|docker/tests/test-mock\.sh$|docker/tests/test-sign-in\.sh$|docker/tests/test-sign-in-2\.sh$|docker/tests/test-sign-in-3\.sh$|src/ocutalon/cls/OcuTalon/Agent/[^/]+\.cls$|src/bridge/cls/OcuTalon/BridgeExample/.+\.cls$|src/ocutalon/cls/OcuTalon/Tools/Names\.cls$|src/bridge/cls/OcuTalon/Bridge/Compaction\.cls$|\.github/workflows/ci\.yml$|\.gitignore$|\.gitattributes$)'

# Bookkeeping: the pipeline's own folders. The UX design documents are not bookkeeping, because the web build reads them.
BOOKKEEPING_PATTERN='^(_bmad/|_bmad-output/)'
NOT_BOOKKEEPING_PATTERN='^_bmad-output/planning-artifacts/ux-designs/'

# The inputs of the IRIS groups (ci/changes.sh --group): a group runs only when a changed path matches its pattern. Every unit builds
# its stack from the whole product, so IRIS_INPUT holds what every unit builds from or runs: the sources, the image (the Dockerfile
# at the repository root) and compose files (.dockerignore and docker/ipm/ among them), the throwaway helpers and compose
# overrides, release/demo-load.sh (which the load phase of live:online-demo-path runs), the eval folder, the CI recipe,
# .github/workflows/ci.yml, and the root .gitattributes and .gitignore. These are unanchored ERE alternatives, joined by
# group_input_pattern.
IRIS_INPUT='src/|Dockerfile$|docker/[^/]+$|docker/ipm/|docker/tests/lib-[^/]+\.sh$|release/demo-load\.sh$|docker/tests/compose\.[^/]+\.yml$|docker-compose[^/]*\.yml$|\.dockerignore$|eval/|ci/|\.github/workflows/ci\.yml$|\.gitattributes$|\.gitignore$'
# The generated overview is read by live:security-overview, which compares it with a fresh generation (Story 14.1); this claim outranks docs/ in NOT_IRIS_INPUT_PATTERN.
IRIS_INPUT="$IRIS_INPUT|docs/security-overview\.md\$"
# live:documents reads the line of docs/bridge-guide.md that states the Filter(text, hostData) contract (Story 19.4), so a change of that guide runs the IRIS groups too.
IRIS_INPUT="$IRIS_INPUT|docs/bridge-guide\.md\$"

# The inputs of the built web bundle, which every stack installs; a unit that reads, compares or serves the bundle's files depends on them.
WEB_BUNDLE_INPUT='web/|logo/|_bmad-output/planning-artifacts/ux-designs/'

# The units whose checks never read, compare or serve the built web bundle. A group whose units are all listed here does not run on a
# web-only change; a unit that is not listed counts as checking the bundle. A unit or test class that starts to check the bundle
# leaves this list (docker/tests/test-ci-config.sh, rule inputs, flags a live script that names the bundle).
NO_WEB_BUNDLE_UNITS="live:audit live:production live:production-restart live:storage-roundtrip live:reminder-restart live:security-overview shard:lane-a@Channel shard:lane-a@Agent"

# The paths that no IRIS unit reads: documentation and release files, the agent settings, Lane A's workflow, the example environment,
# the manual recording tool, and the check and web scripts. A changed path that no group pattern claims, that is not here and that is
# not bookkeeping makes ci/changes.sh run every group, so a story that adds a unit, or gives one a new input, declares that input
# in IRIS_INPUT or in the unit's list, and a story whose unit starts to read one of these paths removes it from here.
# The one input that stays unclassified on purpose is install.sh, which live:install-script-live runs: docker/tests/test-ci-changes.sh
# pins it so, and a change to it runs every group.
NOT_IRIS_INPUT_PATTERN='^(\.claude/|[^/]+\.md$|LICENSE[^/]*$|NOTICE[^/]*$|docs/|release/|\.github/workflows/lane-a\.yml$|\.env\.example$|docker/tests/record-eval\.sh$|docker/tests/test-[^/]+\.sh$)'

# group_input_pattern <group>: the anchored ERE of the paths whose change makes the group run: IRIS_INPUT, WEB_BUNDLE_INPUT unless
# every unit of the group is in NO_WEB_BUNDLE_UNITS, and the script of each live unit of group_units, with docker/tests/test-sign-in.sh for
# live:sign-in-2 and live:sign-in-3, whose scripts run it. Returns 1 for an unknown group.
group_input_pattern() {
  local units u pattern all_without_bundle=1
  units=$(group_units "$1") || return 1
  pattern=$IRIS_INPUT
  for u in $units; do
    case " $NO_WEB_BUNDLE_UNITS " in
      *" $u "*) ;;
      *) all_without_bundle=0 ;;
    esac
  done
  if [ "$all_without_bundle" -eq 0 ]; then pattern="$pattern|$WEB_BUNDLE_INPUT"; fi
  for u in $units; do
    case $u in
      live:sign-in-2 | live:sign-in-3) pattern="$pattern|docker/tests/test-${u#live:}"'\.sh$'"|docker/tests/test-sign-in"'\.sh$' ;;
      live:*) pattern="$pattern|docker/tests/test-${u#live:}"'\.sh$' ;;
    esac
  done
  printf '^(%s)\n' "$pattern"
}
