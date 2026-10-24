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
    lane-a) echo "Agent Bridge Install Tools Digest" ;;
    lane-b) echo "Contract Core Data Demo Live Msg Web" ;;
    *) return 1 ;;
  esac
}

# The IRIS groups, in the order of the matrix of .github/workflows/ci.yml.
IRIS_GROUPS="install production browser shards image"

# group_units <group>: the units of a group in the order they run. live:<name> is docker/tests/test-<name>.sh and
# shard:<name> is a %UnitTest shard. Every docker/tests/test-*.sh is in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or a group.
group_units() {
  case $1 in
    install) echo "live:install-start live:install-upgrade" ;;
    production) echo "live:production live:production-restart live:audit" ;;
    browser) echo "live:demo-path live:sign-in live:bundle-folder" ;;
    shards) echo "shard:lane-a shard:lane-b" ;;
    image) echo "live:storage-roundtrip live:build-inputs live:compose-start" ;;
    *) return 1 ;;
  esac
}

# The live units that drive Playwright and need its Chromium: ci/iris.sh live installs the browser before each of them.
BROWSER_UNITS="demo-path sign-in"

# The paths whose change makes the web job run (ci/changes.sh): the web sources, the Live payload classes and the generated
# sign-in assets that the web build reads or writes, the UX design documents, the logo, the CI recipe (which holds the model
# mock and its scenarios) and the scripts that build the web and run the mock's tests, the files that the mock's tests read
# (the agent classes' MOCKKEY, the tool names, the compaction prefix and the example agent of the bridge), the workflow itself,
# and the root .gitignore and .gitattributes, which decide whether the build leaves the checkout clean and how git checks
# out the files it reads.
WEB_INPUT_PATTERN='^(web/|src/ocutalon/cls/OcuTalon/Live/|src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets\.cls$|_bmad-output/planning-artifacts/ux-designs/|logo/|ci/|docker/tests/test-web-build\.sh$|docker/tests/test-mock\.sh$|src/ocutalon/cls/OcuTalon/Agent/[^/]+\.cls$|src/bridge/cls/OcuTalon/BridgeExample/.+\.cls$|src/ocutalon/cls/OcuTalon/Tools/Names\.cls$|src/bridge/cls/OcuTalon/Bridge/Compaction\.cls$|\.github/workflows/ci\.yml$|\.gitignore$|\.gitattributes$)'

# Bookkeeping: the pipeline's own folders. The UX design documents are not bookkeeping, because the web build reads them.
BOOKKEEPING_PATTERN='^(_bmad/|_bmad-output/)'
NOT_BOOKKEEPING_PATTERN='^_bmad-output/planning-artifacts/ux-designs/'
