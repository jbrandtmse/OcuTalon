# Every list of the CI recipe, defined once (Story 0.7). Sourced by ci/iris.sh, ci/checks.sh, ci/changes.sh and
# docker/tests/test-ci-config.sh, which compares it with .github/workflows/ci.yml. Bash 3.2: no associative arrays.
# Defines variables and functions only.

# The hermetic and static scripts of the hosted `checks` job: docker/tests/test-<name>.sh.
CHECK_SCRIPTS="boundaries storage class-rules ci-config ci-changes compose-file pinned-sources after-start healthcheck lib-live bootstrap demo-path-gate ci-warm probe install-script readme eval-set online-host online-load"

# The scripts of the hosted `web` job.
WEB_SCRIPTS="web-build mock"

# The %UnitTest shards, each a union of whole areas (OcuTalon.Test.<Area>), aligned with the lanes of AD-29.
SHARDS="lane-a lane-b"

# shard_areas <shard>: the areas of a shard.
shard_areas() {
  case $1 in
    lane-a) echo "Agent Bridge Checks Fix Install Tools Digest Watch Eval" ;;
    lane-b) echo "Contract Core Data Demo Live Msg Schedule Web" ;;
    *) return 1 ;;
  esac
}

# The IRIS groups, in the order of the matrix of .github/workflows/ci.yml.
IRIS_GROUPS="install-fresh install-upgrade production browser shards shards-2 image"

# group_units <group>: the units of a group in the order they run. live:<name> is docker/tests/test-<name>.sh and
# shard:<name> is a %UnitTest shard. Every docker/tests/test-*.sh is in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or a group.
# A shard too long for one job runs in pieces, shard:<name>@<piece> (shard_unit_areas): every area of the shard is in exactly
# one piece, so every test class runs once. lane-a runs in two pieces (DW-337): Checks, Install and Watch beside live:floor in
# shards, and the rest of its areas in shards-2, which also takes any area added to lane-a later. The CI rebalance of 2026-10-30
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
# classes check the built bundle.
# Story 11.7 swapped live:online-demo-path and live:install-script-live: the online unit grows by its steps 2 to 5 (the guide's watch
# and reminder, Break the feed and the approval, one visitor's journey), so it moved from install-fresh to image, and the shorter
# live:install-script-live moved the other way. From the unit seconds of CI run 41206732188 (Story 11.1's head): install-fresh is
# 2,007 - 358 + 270 = 1,919 s (install-start 739, bundle-folder 264, online-demo 646, install-script-live 270) and image is
# 1,692 - 270 + 358 + 5 = 1,785 s plus the growth of the online unit (storage-roundtrip 312, build-inputs 9, compose-start 201, lane-b
# 900 and about 5 for Story 11.7's two new tests (inference), online-demo-path 358 + the growth).
group_units() {
  case $1 in
    install-fresh) echo "live:install-start live:bundle-folder live:online-demo live:install-script-live" ;;
    install-upgrade) echo "live:install-upgrade live:cards live:online-allowance live:online-visitors" ;;
    production) echo "live:production live:production-restart live:reminder-restart live:audit" ;;
    browser) echo "live:demo-path live:sign-in live:answers" ;;
    shards) echo "shard:lane-a@Checks,Install,Watch live:floor live:online-session" ;;
    shards-2) echo "shard:lane-a@rest live:demo-switch" ;;
    image) echo "live:storage-roundtrip live:build-inputs live:compose-start shard:lane-b live:online-demo-path" ;;
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

# The live units that drive Playwright and need its Chromium: ci/iris.sh live installs the browser before each of them.
BROWSER_UNITS="demo-path sign-in floor online-demo demo-switch answers cards online-session online-allowance online-demo-path online-visitors"

# The browser units that also run in Firefox and WebKit: ci/iris.sh live installs both after Chromium before each of them. Every name is in BROWSER_UNITS.
FIREFOX_WEBKIT_UNITS="floor"

# The paths whose change makes the web job run (ci/changes.sh): the web sources, the Live payload classes, the catalog
# classes that the page's generated catalog module and its tests read (Msg/Catalog.cls, Msg/Catalog/Core.cls,
# Msg/Catalog/Watch.cls, whose check sentences the page renders, and Msg/Enum.cls, whose fallback reasons the tests compare
# with the module) and the generated sign-in assets that the web build reads or writes, the UX design documents, the logo,
# the CI recipe (which holds the model mock and its scenarios) and the scripts that build the web and run the mock's tests,
# the files that the mock's tests read (the agent classes' MOCKKEY, the tool names, the compaction prefix and the example
# agent of the bridge), the workflow itself, and the root .gitignore and .gitattributes, which decide whether the build
# leaves the checkout clean and how git checks out the files it reads.
WEB_INPUT_PATTERN='^(web/|src/ocutalon/cls/OcuTalon/Live/|src/ocutalon/cls/OcuTalon/Msg/Catalog\.cls$|src/ocutalon/cls/OcuTalon/Msg/Catalog/Core\.cls$|src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch\.cls$|src/ocutalon/cls/OcuTalon/Msg/Enum\.cls$|src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets\.cls$|_bmad-output/planning-artifacts/ux-designs/|logo/|ci/|docker/tests/test-web-build\.sh$|docker/tests/test-mock\.sh$|docker/tests/test-sign-in\.sh$|src/ocutalon/cls/OcuTalon/Agent/[^/]+\.cls$|src/bridge/cls/OcuTalon/BridgeExample/.+\.cls$|src/ocutalon/cls/OcuTalon/Tools/Names\.cls$|src/bridge/cls/OcuTalon/Bridge/Compaction\.cls$|\.github/workflows/ci\.yml$|\.gitignore$|\.gitattributes$)'

# Bookkeeping: the pipeline's own folders. The UX design documents are not bookkeeping, because the web build reads them.
BOOKKEEPING_PATTERN='^(_bmad/|_bmad-output/)'
NOT_BOOKKEEPING_PATTERN='^_bmad-output/planning-artifacts/ux-designs/'

# The inputs of the IRIS groups (ci/changes.sh --group): a group runs only when a changed path matches its pattern. Every unit builds
# its stack from the whole product, so IRIS_INPUT holds what every unit builds from or runs: the sources, the image and compose
# files (.dockerignore and docker/ipm/ among them), the throwaway helpers and compose overrides, release/demo-load.sh (which the load phase
# of live:online-demo-path runs), the eval folder, the CI recipe,
# .github/workflows/ci.yml, and the root .gitattributes and .gitignore. These are unanchored ERE alternatives, joined by
# group_input_pattern.
IRIS_INPUT='src/|docker/[^/]+$|docker/ipm/|docker/tests/lib-[^/]+\.sh$|release/demo-load\.sh$|docker/tests/compose\.[^/]+\.yml$|docker-compose[^/]*\.yml$|\.dockerignore$|eval/|ci/|\.github/workflows/ci\.yml$|\.gitattributes$|\.gitignore$'

# The inputs of the built web bundle, which every stack installs; a unit that reads, compares or serves the bundle's files depends on them.
WEB_BUNDLE_INPUT='web/|logo/|_bmad-output/planning-artifacts/ux-designs/'

# The units whose checks never read, compare or serve the built web bundle. A group whose units are all listed here does not run on a
# web-only change; a unit that is not listed counts as checking the bundle. A unit or test class that starts to check the bundle
# leaves this list (docker/tests/test-ci-config.sh, rule inputs, flags a live script that names the bundle).
NO_WEB_BUNDLE_UNITS="live:audit live:production live:production-restart live:storage-roundtrip live:reminder-restart"

# The paths that no IRIS unit reads: documentation and release files, the agent settings, Lane A's workflow, the example environment,
# the manual recording tool, and the check and web scripts. A changed path that no group pattern claims, that is not here and that is
# not bookkeeping makes ci/changes.sh run every group, so a story that adds a unit, or gives one a new input, declares that input
# in IRIS_INPUT or in the unit's list, and a story whose unit starts to read one of these paths removes it from here.
# The one input that stays unclassified on purpose is install.sh, which live:install-script-live runs: docker/tests/test-ci-changes.sh
# pins it so, and a change to it runs every group.
NOT_IRIS_INPUT_PATTERN='^(\.claude/|[^/]+\.md$|LICENSE[^/]*$|NOTICE[^/]*$|docs/|release/|\.github/workflows/lane-a\.yml$|\.env\.example$|docker/tests/record-eval\.sh$|docker/tests/test-[^/]+\.sh$)'

# group_input_pattern <group>: the anchored ERE of the paths whose change makes the group run: IRIS_INPUT, WEB_BUNDLE_INPUT unless
# every unit of the group is in NO_WEB_BUNDLE_UNITS, and the script of each live unit of group_units. Returns 1 for an unknown group.
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
      live:*) pattern="$pattern|docker/tests/test-${u#live:}"'\.sh$' ;;
    esac
  done
  printf '^(%s)\n' "$pattern"
}
