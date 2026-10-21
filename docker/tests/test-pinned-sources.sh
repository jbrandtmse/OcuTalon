#!/usr/bin/env bash
# Static pins of what the image ships and no other test pins (Story 0.2). Starts nothing.
#   - docker/ipm/: the IPM 0.10.10 release file and its licence are the byte-identical files of the Stack row
#     (size and sha256), the file says it is 0.10.10, the licence keeps its copyright notice, and the
#     after-start session names that file and version;
#   - src/module.xml: the manifest's sources root, and the two resources in the order AD-2 fixes, the bridge
#     package first, each in a directory that exists below the sources root.
# The digest and the manifest checkers first run on synthetic inputs (a known digest; manifests that keep and
# break their rules), so a checker that can no longer fail makes the test fail; the other checks compare a file
# with a fixed value. Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ps.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# The Stack row's files (spec of Story 0.2, Code Map): the release file and the licence of IPM v0.10.10.
ipm_file=docker/ipm/zpm-0.10.10.xml
ipm_size=1593780
ipm_sha=daa2adabd66b488f57187d29712e54b0c25bbe000794fbf2a35a882c458b788a
licence_file=docker/ipm/LICENSE
licence_sha=ad94a204521dfec7db27a44bd068e33d7f889cd2e4352f68bbb790b2291c888f

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
check() { # check <label> <command...>: passes when the command succeeds
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

# --- checkers ---

# The sha256 of a file: sha256sum (Linux), else shasum (macOS).
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

file_size() { wc -c < "$1" | tr -d ' '; }

# The release file's own VERSION parameter: the <Default> two lines below it.
release_version() { grep -A3 '<Parameter name="VERSION">' "$1" | sed -n 's:.*<Default>\(.*\)</Default>.*:\1:p' | head -n 1; }

# The Name and Directory of each <Resource>, one per line, in the manifest's order.
resources() {
  awk '/<Resource[ ]/ {
    n = $0; sub(/.*Name="/, "", n); sub(/".*/, "", n)
    d = $0; sub(/.*Directory="/, "", d); sub(/".*/, "", d)
    print n " " d }' "$1"
}

# AD-2: the bridge package is the first resource, the product package the second.
bridge_first() {
  [ "$(resources "$1" | head -n 2)" = "OcuTalon.Bridge.PKG bridge/cls
OcuTalon.PKG ocutalon/cls" ]
}

sources_root_is_dot() { grep -q '<SourcesRoot>\.</SourcesRoot>' "$1"; }

# --- the checkers on samples ---

printf 'abc' > "$tmp/abc"
if [ "$(sha256 "$tmp/abc")" = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad ]; then
  pass "sha256: the checker reads the known digest of 'abc'"
else
  fail "sha256: no sha256sum or shasum, or a wrong digest for 'abc'"
fi

cat > "$tmp/manifest.good" <<'EOM'
<Module>
  <SourcesRoot>.</SourcesRoot>
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
  <Resource Name="OcuTalon.PKG" Directory="ocutalon/cls"/>
  <Resource Name="OcuTalon.Later.PKG" Directory="later/cls"/>
</Module>
EOM
cat > "$tmp/manifest.reversed" <<'EOM'
<Module>
  <SourcesRoot>src</SourcesRoot>
  <Resource Name="OcuTalon.PKG" Directory="ocutalon/cls"/>
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
</Module>
EOM
printf '<Module>\n  <Resource Name="OcuTalon.PKG" Directory="ocutalon/cls"/>\n</Module>\n' > "$tmp/manifest.single"
printf '<Parameter name="VERSION">\n<Description>\nVersion</Description>\n<Default>0.10.9</Default>\n</Parameter>\n' > "$tmp/release.old"

if bridge_first "$tmp/manifest.good" && ! bridge_first "$tmp/manifest.reversed" && ! bridge_first "$tmp/manifest.single" \
  && sources_root_is_dot "$tmp/manifest.good" && ! sources_root_is_dot "$tmp/manifest.reversed" \
  && [ "$(release_version "$tmp/release.old")" = 0.10.9 ]; then
  pass "checkers: they accept the right manifest and reject a reversed one, a single resource and another root"
else
  fail "checkers: a manifest checker accepts what it should reject, or rejects what it should accept"
fi

# --- docker/ipm/ ---

check "ipm: the release file is $ipm_size bytes" test "$(file_size "$ipm_file")" = "$ipm_size"
check "ipm: the release file is the Stack row's file (sha256)" test "$(sha256 "$ipm_file")" = "$ipm_sha"
check "ipm: the release file says it is 0.10.10" test "$(release_version "$ipm_file")" = 0.10.10
check "ipm: the licence is the file of IPM v0.10.10 (sha256)" test "$(sha256 "$licence_file")" = "$licence_sha"
check "ipm: the licence keeps its copyright notice" \
  grep -qx 'Copyright (c) 2019 InterSystems Developer Community' "$licence_file"
check "ipm: the licence is the MIT licence" grep -qx 'MIT License' "$licence_file"

# The session installs the file in docker/ipm/ and wants the version that the file's name carries.
session_ipm_file() { sed -n 's:.*ipmfile="/opt/ocutalon/ipm/\([^"]*\)".*:\1:p' docker/after-start.cos | head -n 1; }
session_ipm_version() { sed -n 's:.*ipmwant="\([^"]*\)".*:\1:p' docker/after-start.cos | head -n 1; }
check "ipm: the after-start session names a release file that is in docker/ipm/" test -f "docker/ipm/$(session_ipm_file)"
check "ipm: the session's file and wanted version agree" test "$(session_ipm_file)" = "zpm-$(session_ipm_version).xml"
check "ipm: the wanted version is the pinned 0.10.10" test "$(session_ipm_version)" = 0.10.10

# --- src/module.xml ---

check "manifest: the sources root is the manifest's own directory" sources_root_is_dot src/module.xml
check "manifest: the first two resources are the bridge package, then the product package" bridge_first src/module.xml

# A resource "A.B.PKG" in directory D holds the classes of package A.B at src/D/A/B/.
each_resource_has_its_package() {
  local name dir path
  resources src/module.xml | while read -r name dir; do
    path="src/$dir/$(echo "${name%.PKG}" | tr . /)"
    [ -n "$(find "$path" -type f -name '*.cls' 2>/dev/null | head -n 1)" ] || exit 1
  done
}
check "manifest: each resource's package is in its directory below src/" each_resource_has_its_package

if [ "$fails" -ne 0 ]; then
  echo "test-pinned-sources: $fails check(s) failed"
  exit 1
fi
echo "test-pinned-sources: all checks passed"
