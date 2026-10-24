# Every list of the CI recipe, defined once (Story 0.7). Sourced by ci/iris.sh, ci/checks.sh, ci/changes.sh and
# docker/tests/test-ci-config.sh, which compares it with .github/workflows/ci.yml. Bash 3.2: no associative arrays.
# Defines variables and functions only.

# The hermetic and static scripts of the hosted `checks` job: docker/tests/test-<name>.sh.
CHECK_SCRIPTS="boundaries storage class-rules ci-config ci-changes compose-file pinned-sources after-start healthcheck lib-live bootstrap demo-path-gate"

# The scripts of the hosted `web` job.
WEB_SCRIPTS="web-build mock"

# The %UnitTest shards, each a union of whole areas (OcuTalon.Test.<Area>), aligned with the lanes of AD-29.
SHARDS="lane-a lane-b"

# shard_areas <shard>: the areas of a shard.
shard_areas() {
  case $1 in
    lane-a) echo "Agent Bridge Install" ;;
    lane-b) echo "Contract Core Data Demo Live Msg Web" ;;
    *) return 1 ;;
  esac
}

# The IRIS groups, in the order of the matrix of .github/workflows/ci.yml.
IRIS_GROUPS="install-fresh install-upgrade production browser shards image"

# group_units <group>: the units of a group in the order they run. live:<name> is docker/tests/test-<name>.sh and
# shard:<name> is a %UnitTest shard. Every docker/tests/test-*.sh is in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or a group.
group_units() {
  case $1 in
    install-fresh) echo "live:install-start" ;;
    install-upgrade) echo "live:install-upgrade live:audit" ;;
    production) echo "live:production live:production-restart" ;;
    browser) echo "live:demo-path live:sign-in live:bundle-folder" ;;
    shards) echo "shard:lane-a shard:lane-b live:floor" ;;
    image) echo "live:storage-roundtrip live:build-inputs live:compose-start" ;;
    *) return 1 ;;
  esac
}

# The live units that drive Playwright and need its Chromium: ci/iris.sh live installs the browser before each of them.
BROWSER_UNITS="demo-path sign-in floor"

# The paths whose change makes the web job run (ci/changes.sh): the web sources, the Live payload classes, the catalog
# classes that the page's generated catalog module and its tests read (Msg/Catalog.cls, Msg/Catalog/Core.cls,
# Msg/Catalog/Watch.cls, whose check sentences the page renders, and Msg/Enum.cls, whose fallback reasons the tests compare
# with the module) and the generated sign-in assets that the web build reads or writes, the UX design documents, the logo,
# the CI recipe (which holds the model mock and its scenarios) and the scripts that build the web and run the mock's tests,
# the files that the mock's tests read (the agent classes' MOCKKEY, the tool names, the compaction prefix and the example
# agent of the bridge), the workflow itself, and the root .gitignore and .gitattributes, which decide whether the build
# leaves the checkout clean and how git checks out the files it reads.
WEB_INPUT_PATTERN='^(web/|src/ocutalon/cls/OcuTalon/Live/|src/ocutalon/cls/OcuTalon/Msg/Catalog\.cls$|src/ocutalon/cls/OcuTalon/Msg/Catalog/Core\.cls$|src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch\.cls$|src/ocutalon/cls/OcuTalon/Msg/Enum\.cls$|src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets\.cls$|_bmad-output/planning-artifacts/ux-designs/|logo/|ci/|docker/tests/test-web-build\.sh$|docker/tests/test-mock\.sh$|src/ocutalon/cls/OcuTalon/Agent/[^/]+\.cls$|src/bridge/cls/OcuTalon/BridgeExample/.+\.cls$|src/ocutalon/cls/OcuTalon/Tools/Names\.cls$|src/bridge/cls/OcuTalon/Bridge/Compaction\.cls$|\.github/workflows/ci\.yml$|\.gitignore$|\.gitattributes$)'

# Bookkeeping: the pipeline's own folders. The UX design documents are not bookkeeping, because the web build reads them.
BOOKKEEPING_PATTERN='^(_bmad/|_bmad-output/)'
NOT_BOOKKEEPING_PATTERN='^_bmad-output/planning-artifacts/ux-designs/'

# The inputs of the IRIS groups (ci/changes.sh --group): a group runs only when a changed path matches its pattern. Every unit builds
# its stack from the whole product, so IRIS_INPUT holds what every unit builds from or runs: the sources, the image and compose
# files (.dockerignore and docker/ipm/ among them), the throwaway helpers and compose overrides, the eval folder, the CI recipe,
# .github/workflows/ci.yml, and the root .gitattributes and .gitignore. These are unanchored ERE alternatives, joined by
# group_input_pattern.
IRIS_INPUT='src/|docker/[^/]+$|docker/ipm/|docker/tests/lib-[^/]+\.sh$|docker/tests/compose\.[^/]+\.yml$|docker-compose[^/]*\.yml$|\.dockerignore$|eval/|ci/|\.github/workflows/ci\.yml$|\.gitattributes$|\.gitignore$'

# The inputs of the built web bundle, which every stack installs; a unit that reads, compares or serves the bundle's files depends on them.
WEB_BUNDLE_INPUT='web/|logo/|_bmad-output/planning-artifacts/ux-designs/'

# The units whose checks never read, compare or serve the built web bundle. A group whose units are all listed here does not run on a
# web-only change; a unit that is not listed counts as checking the bundle. A unit or test class that starts to check the bundle
# leaves this list (docker/tests/test-ci-config.sh, rule inputs, flags a live script that names the bundle).
NO_WEB_BUNDLE_UNITS="live:audit live:production live:production-restart live:storage-roundtrip"

# The paths that no IRIS unit reads: documentation and release files, the agent settings, Lane A's workflow, the example environment,
# the manual recording tool, and the check and web scripts. A changed path that no group pattern claims, that is not here and that is
# not bookkeeping makes ci/changes.sh run every group, so a story that adds a unit, or gives one a new input, declares that input
# in IRIS_INPUT or in the unit's list, and a story whose unit starts to read one of these paths removes it from here.
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
