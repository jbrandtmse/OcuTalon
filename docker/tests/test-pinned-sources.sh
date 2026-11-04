#!/usr/bin/env bash
# Static pins of what the image ships and no other test pins (Story 0.2). Starts nothing.
#   - docker/ipm/: the IPM 0.10.10 release file and its licence are the byte-identical files of the Stack row
#     (size and sha256), the file says it is 0.10.10, the licence keeps its copyright notice, and the
#     after-start session names that file and version;
#   - src/module.xml: the manifest's sources root, and the three resources in the order AD-2 fixes, the bridge
#     package, the bridge example, then the product, each in a directory that exists below the sources root;
#   - module.xml, the manifest that the package registry reads from the repository root: it is src/module.xml except that its sources
#     root is src and its FileCopy names the bundle from the root, so a change to one manifest alone fails; and preload/, the folder IPM
#     imports from beside module.xml, is the same tree as src/preload/, byte for byte.
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

# AD-2: the bridge package is the first resource, the bridge example the second, the product package the third.
bridge_first() {
  [ "$(resources "$1" | head -n 3)" = "OcuTalon.Bridge.PKG bridge/cls
OcuTalon.BridgeExample.PKG bridge/cls
OcuTalon.PKG ocutalon/cls" ]
}

sources_root_is_dot() { grep -q '<SourcesRoot>\.</SourcesRoot>' "$1"; }

# The drift rule: <root manifest> and <src manifest> agree when the root one has the sources root src and the root-relative FileCopy, and
# is otherwise, line for line, the src one.
manifests_agree() {
  grep -q '^ *<SourcesRoot>src</SourcesRoot>$' "$1" && grep -q '<FileCopy Name="src/ocutalon/csp/"' "$1" \
    && sed -e 's:<SourcesRoot>src</SourcesRoot>:<SourcesRoot>.</SourcesRoot>:' -e 's:<FileCopy Name="src/ocutalon/csp/":<FileCopy Name="ocutalon/csp/":' "$1" | cmp -s - "$2"
}

# The two preload folders hold the same files with the same bytes.
same_tree() { [ -d "$1" ] && [ -d "$2" ] && diff -r "$1" "$2"; }

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
  <Resource Name="OcuTalon.BridgeExample.PKG" Directory="bridge/cls"/>
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
cat > "$tmp/manifest.nobridgeexample" <<'EOM'
<Module>
  <SourcesRoot>.</SourcesRoot>
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
  <Resource Name="OcuTalon.PKG" Directory="ocutalon/cls"/>
  <Resource Name="OcuTalon.Later.PKG" Directory="later/cls"/>
</Module>
EOM
printf '<Parameter name="VERSION">\n<Description>\nVersion</Description>\n<Default>0.10.9</Default>\n</Parameter>\n' > "$tmp/release.old"

if bridge_first "$tmp/manifest.good" && ! bridge_first "$tmp/manifest.reversed" && ! bridge_first "$tmp/manifest.single" \
  && ! bridge_first "$tmp/manifest.nobridgeexample" \
  && sources_root_is_dot "$tmp/manifest.good" && ! sources_root_is_dot "$tmp/manifest.reversed" \
  && [ "$(release_version "$tmp/release.old")" = 0.10.9 ]; then
  pass "checkers: they accept the right manifest and reject a reversed one, a single resource, the old two-resource one and another root"
else
  fail "checkers: a manifest checker accepts what it should reject, or rejects what it should accept"
fi

cat > "$tmp/root.good" <<'EOM'
<Module>
  <Version>1.2.3</Version>
  <Description>The product.</Description>
  <SourcesRoot>src</SourcesRoot>
  <CPF Name="ocutalon.cpf" Directory="cpf"/>
  <FileCopy Name="src/ocutalon/csp/" Target="${dataDir}csp/ocutalon-web/"/>
</Module>
EOM
sed -e 's:<SourcesRoot>src<:<SourcesRoot>.<:' -e 's:Name="src/ocutalon/csp/":Name="ocutalon/csp/":' "$tmp/root.good" > "$tmp/src.good"
sed 's:1\.2\.3:1.2.4:' "$tmp/root.good" > "$tmp/root.version"
sed 's:The product\.:Another product.:' "$tmp/root.good" > "$tmp/root.description"
sed 's:Directory="cpf":Directory="src/cpf":' "$tmp/root.good" > "$tmp/root.directory"
grep -v '<CPF' "$tmp/root.good" > "$tmp/root.lost"
sed 's:<SourcesRoot>src<:<SourcesRoot>.<:' "$tmp/root.good" > "$tmp/root.dot"
sed 's:Name="src/ocutalon/csp/":Name="ocutalon/csp/":' "$tmp/root.good" > "$tmp/root.relative"
sed 's:1\.2\.3:1.2.4:' "$tmp/src.good" > "$tmp/src.version"
if manifests_agree "$tmp/root.good" "$tmp/src.good" \
  && ! manifests_agree "$tmp/root.version" "$tmp/src.good" && ! manifests_agree "$tmp/root.description" "$tmp/src.good" \
  && ! manifests_agree "$tmp/root.directory" "$tmp/src.good" && ! manifests_agree "$tmp/root.lost" "$tmp/src.good" \
  && ! manifests_agree "$tmp/root.dot" "$tmp/src.good" && ! manifests_agree "$tmp/root.relative" "$tmp/src.good" \
  && ! manifests_agree "$tmp/root.good" "$tmp/src.version" && ! manifests_agree "$tmp/root.good" "$tmp/no-such-file"; then
  pass "drift on samples: a root manifest that differs only in the sources root and the FileCopy passes; any other change to one side fails, and so do a root with the src paths and a missing file"
else
  fail "drift on samples: the checker accepts a manifest that drifted, or rejects the right pair"
fi

mkdir -p "$tmp/a/cls" "$tmp/b/cls" "$tmp/c/cls" "$tmp/d/cls"
printf 'x\n' | tee "$tmp/a/cls/I.cls" "$tmp/b/cls/I.cls" "$tmp/c/cls/I.cls" "$tmp/d/cls/I.cls" > /dev/null
printf 'y\n' > "$tmp/c/cls/I.cls"
printf 'x\n' > "$tmp/d/cls/J.cls"
if same_tree "$tmp/a" "$tmp/b" > /dev/null && ! same_tree "$tmp/a" "$tmp/c" > /dev/null && ! same_tree "$tmp/a" "$tmp/d" > /dev/null \
  && ! same_tree "$tmp/a" "$tmp/no-such-folder" > /dev/null; then
  pass "preload on samples: two equal trees pass; a changed byte, an extra file and a missing folder fail"
else
  fail "preload on samples: the checker accepts two trees that differ, or rejects equal ones"
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
check "manifest: the first three resources are the bridge package, the bridge example, then the product package" bridge_first src/module.xml

# A resource "A.B.PKG" in directory D holds the classes of package A.B at src/D/A/B/. A class resource "A.B.C.CLS" with
# Preload="true" is IPM's preload step: its file is src/preload/D/A/B/C.cls.
each_resource_has_its_package() {
  local name dir path
  resources src/module.xml | while read -r name dir; do
    case $name in
      *.CLS)
        grep -F "Name=\"$name\"" src/module.xml | grep -q 'Preload="true"' || exit 1
        [ -f "src/preload/$dir/$(echo "${name%.CLS}" | tr . /).cls" ] || exit 1
        ;;
      *)
        path="src/$dir/$(echo "${name%.PKG}" | tr . /)"
        [ -n "$(find "$path" -type f -name '*.cls' 2>/dev/null | head -n 1)" ] || exit 1
        ;;
    esac
  done
}
check "manifest: each resource's package is in its directory below src/" each_resource_has_its_package

# --- module.xml and preload/ ---

check "drift: module.xml is src/module.xml with the sources root src and the root-relative FileCopy, and nothing else differs" manifests_agree module.xml src/module.xml
check "drift: preload/ is the same tree as src/preload/, byte for byte" same_tree preload src/preload

if [ "$fails" -ne 0 ]; then
  echo "test-pinned-sources: $fails check(s) failed"
  exit 1
fi
echo "test-pinned-sources: all checks passed"
