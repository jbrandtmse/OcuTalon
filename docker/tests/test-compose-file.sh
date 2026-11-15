#!/usr/bin/env bash
# Static inspection of docker-compose.yml, docker-compose.dev.yml, ci/compose.ci.yml, the root Dockerfile, .dockerignore and
# .env.example. Starts no container. Prints one PASS or FAIL line per check; exits 0 only when every check passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

compose=docker-compose.yml
dockerfile=Dockerfile
fails=0

check() { # check <label> <command...>: passes when the command succeeds
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    fails=$((fails + 1))
  fi
}

# Non-comment, non-blank lines of a file.
code() { grep -v '^[[:space:]]*\(#\|$\)' "$1"; }

# --- docker-compose.yml ---

only_service_is_iris() {
  local names
  names=$(awk '
    /^services:/ { ins = 1; next }
    /^[^ #]/ { ins = 0 }
    ins && /^  [A-Za-z0-9_.-]+:/ { sub(/:.*/, ""); gsub(/ /, ""); print }
  ' "$compose")
  [ "$names" = iris ]
}

no_mock() { ! code "$compose" | grep -qi 'mock'; }

# The judges' file names no file of ci/ (CON-3).
no_ci_reference() { ! code "$compose" | grep -qi 'ci/\|compose\.ci'; }

no_forbidden_key() { # no non-comment line starts with the given key
  ! code "$compose" | grep -q "^[[:space:]]*$1:"
}

no_superserver_port() { ! code "$compose" | grep -q '1972'; }

# start_period as seconds (accepts <n>s, <n>m, <n>h); prints nothing for any other form.
start_period_seconds() {
  code "$compose" | awk '
    $1 == "start_period:" {
      v = $2
      if (match(v, /^[0-9]+s$/)) { print substr(v, 1, length(v) - 1) + 0 }
      else if (match(v, /^[0-9]+m$/)) { print (substr(v, 1, length(v) - 1) + 0) * 60 }
      else if (match(v, /^[0-9]+h$/)) { print (substr(v, 1, length(v) - 1) + 0) * 3600 }
    }'
}

start_period_at_least_600() {
  local s
  s=$(start_period_seconds)
  [ -n "$s" ] && [ "$s" -ge 600 ]
}

has_line() { code "$1" | grep -q "$2"; }

health_timing() {
  has_line "$compose" '^[[:space:]]*interval:[[:space:]]*10s[[:space:]]*$' \
    && has_line "$compose" '^[[:space:]]*timeout:[[:space:]]*5s[[:space:]]*$' \
    && has_line "$compose" '^[[:space:]]*retries:[[:space:]]*3[[:space:]]*$'
}

check "compose: the only service is iris" only_service_is_iris
check "compose: no non-comment line says mock" no_mock
check "compose: no non-comment line names a file of ci/" no_ci_reference
check "compose: no container_name" no_forbidden_key container_name
check "compose: no image tag" no_forbidden_key image
check "compose: no fixed volume or project name below the top level" \
  bash -c "! grep -v '^[[:space:]]*#' '$compose' | grep -q '^[[:space:]][[:space:]]*name:'"
check "compose: no superserver port" no_superserver_port
check "compose: top-level name ocutalon" has_line "$compose" '^name:[[:space:]]*ocutalon[[:space:]]*$'
check "compose: stop_grace_period 60s" has_line "$compose" '^[[:space:]]*stop_grace_period:[[:space:]]*60s[[:space:]]*$'
check "compose: start_period at least 600 s" start_period_at_least_600
check "compose: health check runs /opt/ocutalon/healthcheck.sh" \
  has_line "$compose" 'test:[[:space:]]*\["CMD",[[:space:]]*"/opt/ocutalon/healthcheck.sh"\]'
check "compose: health check interval 10s, timeout 5s, retries 3" health_timing
check "compose: IRIS_IMAGE build argument" has_line "$compose" 'IRIS_IMAGE:[[:space:]]*\${IRIS_IMAGE:-ocutalon-iris-base:2026\.3\.0AI\.154\.0}'
check "compose: pull_policy build" has_line "$compose" '^[[:space:]]*pull_policy:[[:space:]]*build[[:space:]]*$'
check "compose: restart unless-stopped" has_line "$compose" '^[[:space:]]*restart:[[:space:]]*unless-stopped[[:space:]]*$'
check "compose: optional .env file" \
  bash -c "grep -v '^[[:space:]]*#' '$compose' | grep -A1 '^[[:space:]]*-[[:space:]]*path:[[:space:]]*\.env[[:space:]]*\$' | grep -q '^[[:space:]]*required:[[:space:]]*false[[:space:]]*\$'"
check "compose: web port from OCUTALON_WEB_PORT" has_line "$compose" '"\${OCUTALON_WEB_PORT:-52773}:52773"'
check "compose: config parses (--quiet)" docker compose -f "$compose" config --quiet

# --- Dockerfile ---

last_user_is_51773() {
  [ "$(code "$dockerfile" | awk '$1 == "USER" { u = $2 } END { print u }')" = 51773 ]
}

check "dockerfile: IRIS_IMAGE defaults to the retagged build 154 image" \
  has_line "$dockerfile" '^ARG IRIS_IMAGE=ocutalon-iris-base:2026\.3\.0AI\.154\.0$'
check "dockerfile: FROM the IRIS_IMAGE argument" has_line "$dockerfile" '^FROM \${IRIS_IMAGE}$'
check "dockerfile: runs as UID 51773" last_user_is_51773
check "dockerfile: data and merge environment" \
  bash -c "grep -q 'ISC_DATA_DIRECTORY=/durable/iris' '$dockerfile' && grep -q 'ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf' '$dockerfile'"
check "dockerfile: an empty version fails the build" has_line "$dockerfile" 'test -n "\$version"'
check "dockerfile: CMD deletes the ready marker before IRIS starts, then runs the after-start script through iris-main" \
  has_line "$dockerfile" '^CMD \["--before", "rm -f /durable/ocutalon\.ready", "--after", "/opt/ocutalon/after-start\.sh"\]$'
check "dockerfile: the sources, the pinned IPM release and the scripts are copied" \
  bash -c "grep -q '^COPY src/ /opt/ocutalon/src/\$' '$dockerfile' && grep -q '^COPY docker/ipm/ /opt/ocutalon/ipm/\$' '$dockerfile' && grep -q '^COPY docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos /opt/ocutalon/\$' '$dockerfile'"
check "dockerfile: the version comes from the copied manifest" has_line "$dockerfile" '/opt/ocutalon/src/module\.xml'

# A source tree without the web bundle fails the build, in the same RUN as the version and before the modes are set.
bundle_guard_before_chmod() {
  local guard chmod_at
  guard=$(code "$dockerfile" | grep -n 'test -f /opt/ocutalon/src/ocutalon/csp/index\.html.*web bundle missing: run npm --prefix web run build.*exit 1' | head -n 1 | cut -d: -f1)
  chmod_at=$(code "$dockerfile" | grep -n 'find /opt/ocutalon -type f -exec chmod 444' | head -n 1 | cut -d: -f1)
  [ -n "$guard" ] && [ -n "$chmod_at" ] && [ "$guard" -lt "$chmod_at" ] \
    && [ "$(code "$dockerfile" | awk -v g="$guard" 'NR < g && /^USER / { n++ } END { print n + 0 }')" -eq 1 ]
}
check "dockerfile: a tree without src/ocutalon/csp/index.html fails the build, before the modes are set and the last USER" bundle_guard_before_chmod
# --- Dockerfile: step 3's Python packages, the baked model and the licence gate (Story 34.2; AD-21, AD-23) ---

# runs: each RUN instruction of the Dockerfile as one line (continuation lines joined), in order; copies: each COPY, in order.
runs() { code "$dockerfile" | awk '/^RUN / { cur = $0; while (cur ~ /\\$/) { sub(/[[:space:]]*\\$/, "", cur); getline nxt; sub(/^[[:space:]]+/, "", nxt); cur = cur " " nxt } print cur }'; }
# The line number of the first instruction that starts with the word, and of the first line that holds the text.
line_of() { code "$dockerfile" | grep -n -m 1 -e "$1" | cut -d: -f1; }
# The one RUN that installs the packages.
pip_run() { runs | grep -F 'pip install' ; }

pip_pins() {
  local n
  n=$(pip_run | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] || return 1
  pip_run | grep -qF -e 'python3 -m pip install --break-system-packages --no-cache-dir --target /usr/irissys/mgr/python --only-binary=:all: fastembed==0.9.0 pdfplumber==0.11.10 python-docx==1.1.2 -c "$constraints" &&' || return 1
  # Exactly the three pins follow the options: no other package, no other pin (the constraints file holds the rest).
  [ "$(pip_run | sed 's/.*--only-binary=:all: //; s/ -c .*//' | tr ' ' '\n' | grep -c .)" -eq 3 ]
}

# The constraints file is chosen by the build's architecture (uname -m): x86_64 is x64, aarch64 is arm64, and any other architecture
# fails the build with a message that names the missing file.
constraints_by_architecture() {
  local r
  r=$(pip_run)
  printf '%s\n' "$r" | grep -qF 'case "$(uname -m)" in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; *) echo "no Python constraints file for architecture $(uname -m)' || return 1
  printf '%s\n' "$r" | grep -qF 'exit 1 ;; esac && constraints="/opt/ocutalon/licences/constraints-$arch.txt" && python3 -m pip install' || return 1
  [ "$(line_of '^COPY docker/licences/allowed.txt docker/licences/gate.py docker/licences/constraints-arm64.txt docker/licences/constraints-x64.txt /opt/ocutalon/licences/$')" -lt "$(line_of 'pip install')" ]
}

# The architecture switch of the pip line is run with a stubbed uname: x86_64 picks constraints-x64.txt, aarch64 constraints-arm64.txt, and any
# other architecture exits 1 with a message that names the missing file.
constraints_switch_runs() {
  local snippet out
  snippet=$(pip_run | sed 's/^RUN //; s/ && constraints=.*//; s/ \\$//')
  [ -n "$snippet" ] || return 1
  out=$(sh -c "uname() { echo x86_64; }; $snippet; echo \"\$arch\"" 2>&1) && [ "$out" = x64 ] || return 1
  out=$(sh -c "uname() { echo aarch64; }; $snippet; echo \"\$arch\"" 2>&1) && [ "$out" = arm64 ] || return 1
  out=$(sh -c "uname() { echo riscv64; }; $snippet; echo \"\$arch\"" 2>&1) && return 1
  printf '%s\n' "$out" | grep -qF 'no Python constraints file for architecture riscv64: add docker/licences/constraints-<arch>.txt'
}

model_in_the_same_run() {
  local r
  r=$(pip_run)
  printf '%s\n' "$r" | grep -qF "snapshot_download('Qdrant/all-MiniLM-L6-v2-onnx', cache_dir='/opt/fastembed'" || return 1
  printf '%s\n' "$r" | grep -qF 'chown -R root:root /opt/fastembed' || return 1
  printf '%s\n' "$r" | grep -qF 'find /opt/fastembed -type d -exec chmod 555 {} +' || return 1
  printf '%s\n' "$r" | grep -qF 'find /opt/fastembed -type f -exec chmod 444 {} +'
}

# The packages and the model come before the sources are copied, so that a source change reuses their layer.
model_before_sources() {
  local pip copy
  pip=$(line_of 'pip install')
  copy=$(line_of '^COPY src/ /opt/ocutalon/src/$')
  [ -n "$pip" ] && [ -n "$copy" ] && [ "$pip" -lt "$copy" ]
}

# The gate runs after the install and before the notices, in the same RUN, and its allowed list is copied before it.
gate_after_pip() {
  local r
  r=$(pip_run)
  printf '%s\n' "$r" | grep -qF 'pip install' || return 1
  printf '%s\n' "$r" | grep -qF 'pip install ' || return 1
  printf '%s\n' "$r" | grep -q 'pip install .*&& python3 /opt/ocutalon/licences/gate.py check /usr/irissys/mgr/python "\$constraints" &&.*gate.py notices /usr/irissys/mgr/python /opt/ocutalon/THIRD-PARTY-NOTICES &&' || return 1
  [ "$(line_of '^COPY docker/licences/allowed.txt docker/licences/gate.py docker/licences/constraints-arm64.txt docker/licences/constraints-x64.txt /opt/ocutalon/licences/$')" -lt "$(line_of 'pip install')" ]
}

# The packages' licence files are kept: nothing is uninstalled and nothing is deleted under the packages' folder.
no_licence_deletion() {
  ! code "$dockerfile" | grep -q 'pip uninstall' || return 1
  ! code "$dockerfile" | grep -E '(^|[[:space:]&;|])(rm|unlink|shred)[[:space:]]' | grep -q '/usr/irissys/mgr/python' || return 1
  ! code "$dockerfile" | grep -q -e '-delete' -e 'find /usr/irissys/mgr/python.*-exec rm'
}

check "dockerfile: one pip line installs exactly fastembed==0.9.0 pdfplumber==0.11.10 python-docx==1.1.2, wheels only, into /usr/irissys/mgr/python" pip_pins
check "dockerfile: the pip line holds every dependency to the constraints file of the build's architecture (uname -m), and any other architecture fails the build" constraints_by_architecture
check "dockerfile: the architecture switch of the pip line picks constraints-x64.txt for x86_64 and constraints-arm64.txt for aarch64, and fails any other architecture with a message" constraints_switch_runs
check "dockerfile: FASTEMBED_CACHE_DIR is /opt/fastembed" \
  bash -c "grep -v '^[[:space:]]*#' '$dockerfile' | grep -q 'FASTEMBED_CACHE_DIR=/opt/fastembed'"
check "dockerfile: the model is downloaded into /opt/fastembed in the pip RUN, root-owned, folders 555 and files 444" model_in_the_same_run
check "dockerfile: the packages and the model come before the sources are copied" model_before_sources
check "dockerfile: the licence gate runs right after the install, then the notices, and its folder is copied first" gate_after_pip
check "dockerfile: no pip uninstall and no deletion under /usr/irissys/mgr/python (the licence files stay)" no_licence_deletion

# The licence gate (docker/licences/gate.py and allowed.txt): the allowed set is the ruled one, and planted distributions are judged as ruled.
gate=docker/licences/gate.py
allowed_set_is_ruled() {
  local want got
  want="0BSD AGG-2.3 Apache-2.0 Apache-2.0_WITH_LLVM-exception BSD-2-Clause BSD-3-Clause CC0-1.0 FTL HPND IJG ISC MIT MIT-0 MIT-CMU MPL-2.0 PSF-2.0 Unicode-3.0 Unlicense Zlib libpng-2.0"
  got=$(grep '^allow ' docker/licences/allowed.txt | sed 's/^allow //; s/ /_/g' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  [ "$got" = "$want" ] || return 1
  # CC-BY-4.0 is ruled for documentation only: a docs line, never an allow line.
  [ "$(grep '^docs ' docker/licences/allowed.txt)" = 'docs CC-BY-4.0' ]
}

# mkdist <folder> <name> <metadata lines> [licence text]: a .dist-info folder, with a LICENSE under licenses/ when a text is given.
mkdist() {
  local d="$1/$2-1.0.dist-info"
  mkdir -p "$d"
  printf 'Metadata-Version: 2.4\nName: %s\nVersion: 1.0\n%s\n' "$2" "$3" > "$d/METADATA"
  if [ -n "${4:-}" ]; then mkdir -p "$d/licenses"; printf '%s\n' "$4" > "$d/licenses/LICENSE"; fi
}

gate_rules() {
  command -v python3 >/dev/null 2>&1 || return 1
  local w ok=0 mit_text='Permission is hereby granted, free of charge, to any person obtaining a copy of this software' out
  w=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-gate.XXXXXX") || return 1
  # Allowed: an SPDX id, a dual licence with one allowed side, a package with no declaration whose file is MIT, a phrase that needs files.
  mkdir -p "$w/good"
  mkdist "$w/good" alpha 'License-Expression: MIT'
  mkdist "$w/good" beta 'License: GPL-2.0-or-later OR MIT'
  mkdist "$w/good" gamma 'Classifier: License :: OSI Approved :: Apache Software License'
  mkdist "$w/good" delta '' "$mit_text"
  mkdist "$w/good" epsilon 'License: BSD-3-Clause, dependency licenses' "$mit_text"
  mkdist "$w/good" zeta 'License-Expression: (GPL-3.0-only OR MIT) AND BSD-3-Clause'
  mkdist "$w/good" eta 'Classifier: License :: OSI Approved :: Apache License, Version 2.0'
  printf 'Apache notice line of eta\n' > "$w/good/eta-1.0.dist-info/NOTICE"
  mkdist "$w/good" theta $'License: MPL-2.0\nClassifier: License :: OSI Approved :: Mozilla Public License 2.0 (MPL 2.0)'
  mkdist "$w/good" iota '' 'Creative Commons Attribution 4.0 International Public License'
  # A licence file that the wheel installs in its package folder (listed in RECORD) goes to the notices too.
  mkdist "$w/good" kappa 'License-Expression: MIT'
  mkdir -p "$w/good/kappa"; printf 'Notices of the libraries bundled in kappa\n' > "$w/good/kappa/ThirdPartyNotices.txt"
  printf 'kappa/ThirdPartyNotices.txt,,\nkappa-1.0.dist-info/METADATA,,\n' > "$w/good/kappa-1.0.dist-info/RECORD"
  python3 "$gate" check "$w/good" >/dev/null 2>&1 || { echo "the good set was refused" >&2; ok=1; }
  # Refused, each alone in a folder with an allowed neighbour: the planted licence names the one that failed.
  local planted
  for planted in \
    'License-Expression: GPL-3.0-only' \
    'License: AGPL-3.0-or-later' \
    'License-Expression: MIT AND GPL-2.0-only' \
    'License-Expression: (MIT OR Apache-2.0) AND GPL-3.0-only' \
    'License-Expression: GPL-3.0-only AND (MIT OR Apache-2.0)' \
    'Classifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)' \
    $'License: MIT\nClassifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)' \
    'License-Expression: GPL-3.0-only OR dependency licenses' \
    'License-Expression: MIT,' \
    'License-Expression: MIT OR OR GPL-3.0-only' \
    'License-Expression: CC-BY-4.0' \
    'License: Proprietary'; do
    mkdir -p "$w/bad"; rm -rf "$w/bad"/*
    mkdist "$w/bad" neighbour 'License-Expression: MIT'
    mkdist "$w/bad" planted "$planted" "$mit_text"
    out=$(python3 "$gate" check "$w/bad" 2>&1) && { echo "'$planted' was allowed" >&2; ok=1; }
    printf '%s\n' "$out" | grep -q '^FAIL planted 1.0 ' || { echo "'$planted' was not named" >&2; ok=1; }
  done
  # Nothing declared and no licence file, or a file the gate cannot read as an allowed licence, or a phrase over such a file: refused.
  mkdir -p "$w/bad"; rm -rf "$w/bad"/*
  mkdist "$w/bad" planted ''
  python3 "$gate" check "$w/bad" >/dev/null 2>&1 && { echo "an undeclared package without a file was allowed" >&2; ok=1; }
  rm -rf "$w/bad"/*; mkdist "$w/bad" planted '' 'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007'
  python3 "$gate" check "$w/bad" >/dev/null 2>&1 && { echo "an undeclared package with an unreadable file was allowed" >&2; ok=1; }
  rm -rf "$w/bad"/*; mkdist "$w/bad" planted 'License: MIT, dependency licenses' 'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007'
  python3 "$gate" check "$w/bad" >/dev/null 2>&1 && { echo "a phrase over an unreadable file was allowed" >&2; ok=1; }
  # An empty folder is refused: nothing was installed.
  rm -rf "$w/bad"/*
  python3 "$gate" check "$w/bad" >/dev/null 2>&1 && { echo "an empty folder was allowed" >&2; ok=1; }
  # The notices come from the installed licence files and carry the two credit lines.
  python3 "$gate" notices "$w/good" "$w/NOTICES" >/dev/null 2>&1 || ok=1
  grep -qF 'Portions of this software are copyright (c) The FreeType Project (www.freetype.org). All rights reserved.' "$w/NOTICES" || ok=1
  grep -qF 'This software is based in part on the work of the Independent JPEG Group.' "$w/NOTICES" || ok=1
  grep -qF "$mit_text" "$w/NOTICES" || ok=1
  grep -qF 'Apache notice line of eta' "$w/NOTICES" || ok=1
  grep -qF 'Notices of the libraries bundled in kappa' "$w/NOTICES" || ok=1
  rm -rf "$w"
  return $ok
}

check "licences: the allowed set is the ruled one (U-285), in one file" allowed_set_is_ruled
check "licences: the gate allows the ruled kinds, fails a planted disallowed, unknown or missing licence, and writes the notices with the credit lines" gate_rules

# --- the constraints files (Story 34.3, DW-738): one pin for every distribution of an architecture's installed set ---

evidence_dir=_bmad-output/implementation-artifacts/evidence
arm64_evidence="$evidence_dir/34-2-task0-licences.md"
x64_evidence="$evidence_dir/34-3-x64-installed-set.md"
rule_sentence='Any version change here re-measures the licences (docker/licences/gate.py on the installed set) and updates the evidence in the same commit.'

# same_set <evidence file> <constraints file>: the evidence table's distributions and versions equal the constraints file's pins, exactly,
# and the file is sorted (by name, any case), holds nothing but comments and name==version lines, and carries the rule in a comment.
same_set() {
  python3 -I -c '
import re, sys
evidence, constraints, rule = sys.argv[1:4]
table = []
for line in open(evidence, encoding="ascii"):
    m = re.match(r"^\| ([A-Za-z0-9_.-]+) \| ([0-9][^ |]*) \|", line)
    if m:
        table.append("%s==%s" % m.groups())
pins, comments = [], []
for line in open(constraints, encoding="ascii").read().splitlines():
    if line.startswith("#"):
        comments.append(line)
    elif line.strip():
        if not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*==[A-Za-z0-9][A-Za-z0-9._+!-]*$", line):
            sys.exit("not a pin: " + line)
        pins.append(line)
if not table or len(set(table)) != len(table):
    sys.exit("the evidence table is empty or lists a distribution twice")
if sorted(pins, key=str.lower) != pins:
    sys.exit("the constraints file is not sorted")
if sorted(table) != sorted(pins):
    sys.exit("the evidence and the constraints differ: " + ", ".join(sorted(set(table) ^ set(pins))))
if "# " + rule not in comments:
    sys.exit("the rule comment is missing")
' "$1" "$2" "$rule_sentence" 2>&1
}

constraints_equal_evidence() {
  same_set "$arm64_evidence" docker/licences/constraints-arm64.txt || return 1
  same_set "$x64_evidence" docker/licences/constraints-x64.txt
}

# The check is shown red on a planted difference: one version changed in a copy of each constraints file, one pin dropped, one added.
constraints_check_can_fail() {
  local w ok=0
  w=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-constraints.XXXXXX") || return 1
  for arch in arm64 x64; do
    case "$arch" in arm64) ev=$arm64_evidence ;; x64) ev=$x64_evidence ;; esac
    sed 's/^anyio==.*/anyio==0.0.1/' "docker/licences/constraints-$arch.txt" > "$w/version.txt"
    same_set "$ev" "$w/version.txt" >/dev/null && { echo "$arch: a changed version was accepted" >&2; ok=1; }
    grep -v '^anyio==' "docker/licences/constraints-$arch.txt" > "$w/dropped.txt"
    same_set "$ev" "$w/dropped.txt" >/dev/null && { echo "$arch: a dropped pin was accepted" >&2; ok=1; }
    { cat "docker/licences/constraints-$arch.txt"; echo 'zzextra==1.0'; } > "$w/added.txt"
    same_set "$ev" "$w/added.txt" >/dev/null && { echo "$arch: an added pin was accepted" >&2; ok=1; }
    grep -v '^# Any version change' "docker/licences/constraints-$arch.txt" > "$w/norule.txt"
    same_set "$ev" "$w/norule.txt" >/dev/null && { echo "$arch: a file without the rule comment was accepted" >&2; ok=1; }
  done
  rm -rf "$w"
  return $ok
}

# The gate holds an installed set to a constraints file: a planted distribution that the file lacks, one at another version and a pin
# that is not installed are refused, and an installed set that equals the file is accepted.
gate_constraints() {
  command -v python3 >/dev/null 2>&1 || return 1
  local w out ok=0
  w=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-gate.XXXXXX") || return 1
  mkdir -p "$w/set"
  mkdist "$w/set" alpha 'License-Expression: MIT'
  mkdist "$w/set" beta 'License-Expression: Apache-2.0'
  printf '# comment\nalpha==1.0\nBeta==1.0\n' > "$w/equal.txt"
  python3 -I "$gate" check "$w/set" "$w/equal.txt" >/dev/null 2>&1 || { echo "an installed set equal to its constraints was refused" >&2; ok=1; }
  printf 'alpha==1.0\n' > "$w/missing.txt"
  out=$(python3 -I "$gate" check "$w/set" "$w/missing.txt" 2>&1) && { echo "a distribution absent from the constraints was accepted" >&2; ok=1; }
  printf '%s\n' "$out" | grep -q 'FAIL constraints: beta 1.0 is installed but not pinned' || { echo "the absent distribution was not named" >&2; ok=1; }
  printf 'alpha==1.0\nbeta==2.0\n' > "$w/differs.txt"
  out=$(python3 -I "$gate" check "$w/set" "$w/differs.txt" 2>&1) && { echo "a distribution at another version was accepted" >&2; ok=1; }
  printf '%s\n' "$out" | grep -q 'FAIL constraints: beta is installed at 1.0 but pinned at 2.0' || { echo "the differing version was not named" >&2; ok=1; }
  printf 'alpha==1.0\nbeta==1.0\ngamma==3.0\n' > "$w/stale.txt"
  out=$(python3 -I "$gate" check "$w/set" "$w/stale.txt" 2>&1) && { echo "a pin that is not installed was accepted" >&2; ok=1; }
  printf '%s\n' "$out" | grep -q 'FAIL constraints: gamma==3.0 is pinned but not installed' || { echo "the stale pin was not named" >&2; ok=1; }
  printf 'alpha==1.0\nbeta==1.0\ngamma>=1.0\n' > "$w/range.txt"
  python3 -I "$gate" check "$w/set" "$w/range.txt" >/dev/null 2>&1 && { echo "a range instead of a pin was accepted" >&2; ok=1; }
  # A disallowed licence still fails with a matching constraints file.
  mkdist "$w/set" gamma 'License-Expression: GPL-3.0-only'
  printf 'alpha==1.0\nbeta==1.0\ngamma==1.0\n' > "$w/all.txt"
  python3 -I "$gate" check "$w/set" "$w/all.txt" >/dev/null 2>&1 && { echo "a disallowed licence passed with a matching constraints file" >&2; ok=1; }
  # The real files parse the way the build reads them.
  for arch in arm64 x64; do
    python3 -I -c '
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
if len(gate.load_constraints(sys.argv[2])) < 30:
    sys.exit("too few pins")
' "$gate" "docker/licences/constraints-$arch.txt" >/dev/null 2>&1 || { echo "constraints-$arch.txt is not read by gate.py" >&2; ok=1; }
  done
  rm -rf "$w"
  return $ok
}

check "constraints: each architecture's file pins exactly the distributions and versions of its evidence table, sorted, with the rule in a comment" constraints_equal_evidence
check "constraints: the evidence check goes red on a changed version, a dropped pin, an added pin and a missing rule comment" constraints_check_can_fail
check "licences: the gate refuses an installed distribution that the constraints lack or pin at another version, a pin that is not installed, a range, and still refuses a disallowed licence" gate_constraints

check "module: the bundle is copied to the durable csp/ocutalon-web/ folder" \
  grep -q '<FileCopy Name="ocutalon/csp/" Target="${dataDir}csp/ocutalon-web/"/>' src/module.xml
# The Web step reads the build that IPM's FileCopy copied from the module root and the name of that copy (Story 36.7, BUILDFOLDERS).
build_folders_pinned() {
  local declared from_src from_root
  declared=$(sed -n 's/^Parameter BUILDFOLDERS = "\(.*\)";$/\1/p' src/ocutalon/cls/OcuTalon/Install/Step/Web.cls)
  from_src=$(sed -n 's|^ *<FileCopy Name="\([^"]*\)" Target="${dataDir}csp/ocutalon-web/"/>$|\1|p' src/module.xml)
  from_root=$(sed -n 's|^ *<FileCopy Name="\([^"]*\)" Target="${dataDir}csp/ocutalon-web/"/>$|\1|p' module.xml)
  [ -n "$from_src" ] && [ -n "$from_root" ] && [ "$declared" = "$from_src,$from_root" ]
}
check "module: the Web step's BUILDFOLDERS holds the bundle FileCopy names of src/module.xml and of module.xml, in that order" build_folders_pinned
check "healthcheck.sh: POSIX sh" test "$(head -n 1 docker/healthcheck.sh)" = '#!/bin/sh'
check "after-start.sh: bash" test "$(head -n 1 docker/after-start.sh)" = '#!/bin/bash'

# --- docker/merge.cpf and line endings ---

merge_directories_relative() {
  [ "$(grep -c 'Directory=' docker/merge.cpf)" -eq 4 ] && ! grep -q 'Directory="\{0,1\}/' docker/merge.cpf
}

# Files that the image copies, or that a script runs, keep LF in every checkout.
files_keep_lf() {
  local f
  for f in Dockerfile docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos \
    docker/ipm/zpm-0.10.10.xml docker/ipm/LICENSE docker/tests/test-compose-file.sh docker/tests/lib-live.sh \
    src/module.xml src/bridge/cls/OcuTalon/Bridge/Installer.cls src/ocutalon/cls/OcuTalon/Install/Registry.cls \
    .dockerignore .env.example; do
    [ "$(git check-attr eol -- "$f" | sed 's/.*: //')" = lf ] || return 1
  done
}

# A binary under src/ (the committed web bundle's images and fonts) is detected, not forced to text.
src_binaries_not_forced_text() {
  local f
  for f in src/ocutalon/csp/favicon.ico src/ocutalon/csp/media/font.woff2 src/ocutalon/cls/OcuTalon/Install/Registry.cls; do
    [ "$(git check-attr text -- "$f" | sed 's/.*: //')" = auto ] || return 1
  done
}

check "merge.cpf: four database directories, all relative" merge_directories_relative
check "gitattributes: the copied and executed files keep LF" files_keep_lf
check "gitattributes: files under src/ are text only when git detects text, so a binary is never rewritten" src_binaries_not_forced_text

# --- .dockerignore ---

dockerignore_is_allow_list() {
  # The first rule is '*', and the only exceptions are the files the Dockerfile copies.
  [ "$(code .dockerignore | head -n 1)" = '*' ] || return 1
  ! code .dockerignore | grep -v '^\*$' \
    | grep -v -x -e '!docker/merge.cpf' -e '!docker/healthcheck.sh' -e '!docker/after-start.sh' -e '!docker/after-start.cos' \
      -e '!docker/ipm/zpm-0.10.10.xml' -e '!docker/ipm/LICENSE' -e '!docker/licences/allowed.txt' -e '!docker/licences/gate.py' \
      -e '!docker/licences/constraints-arm64.txt' -e '!docker/licences/constraints-x64.txt' -e '!src' \
    | grep -q .
}

# Every exception the Dockerfile's COPY lines need is in the list, and none is missing.
dockerignore_names_every_exception() {
  local rule
  for rule in '!docker/merge.cpf' '!docker/healthcheck.sh' '!docker/after-start.sh' '!docker/after-start.cos' \
    '!docker/ipm/zpm-0.10.10.xml' '!docker/ipm/LICENSE' '!docker/licences/allowed.txt' '!docker/licences/gate.py' \
    '!docker/licences/constraints-arm64.txt' '!docker/licences/constraints-x64.txt' '!src'; do
    code .dockerignore | grep -qx -e "$rule" || return 1
  done
}

check "dockerignore: allow-list of the copied files only" dockerignore_is_allow_list
check "dockerignore: every copied file or directory is allowed" dockerignore_names_every_exception

# --- docker-compose.dev.yml ---

dev=docker-compose.dev.yml

# The override holds the project name and the one variable, and nothing else.
dev_file_is_exact() {
  [ "$(code "$dev")" = "name: ocutalon-dev
services:
  iris:
    environment:
      OCUTALON_DEV: \"1\"" ]
}

dev_no_mock() { ! code "$dev" | grep -qi 'mock'; }
dev_no_container_name() { ! code "$dev" | grep -q "^[[:space:]]*container_name:"; }

check "dev: the file holds only the project name and OCUTALON_DEV \"1\"" dev_file_is_exact
check "dev: top-level name ocutalon-dev" has_line "$dev" '^name:[[:space:]]*ocutalon-dev[[:space:]]*$'
check "dev: OCUTALON_DEV is \"1\" for the iris service" has_line "$dev" '^[[:space:]]*OCUTALON_DEV:[[:space:]]*"1"[[:space:]]*$'
check "dev: no non-comment line says mock" dev_no_mock
check "dev: no container_name" dev_no_container_name
check "dev: config parses together with the judges' file (--quiet)" docker compose -f "$compose" -f "$dev" config --quiet

# --- ci/compose.ci.yml ---

ci=ci/compose.ci.yml

# The override is exactly the mock's wiring (Stories 0.11 and 10.3): the project name; the iris service with OCUTALON_EVAL passed
# through from the environment (default 0), OCUTALON_MODEL_BASE_URL, the CI-only switch OCUTALON_MOCK_KEY_HEADER (owner
# decision 5), the Bot API base OCUTALON_TELEGRAM_API_BASE and the dummy bot token TELEGRAM_BOT_TOKEN, and the read-only log volume;
# the mock service from the public node image pinned by digest, with ci/mock mounted read-only; and the named volume mock-log.
# Nothing else.
ci_file_is_exact() {
  [ "$(code "$ci")" = 'name: ocutalon-ci
services:
  iris:
    environment:
      OCUTALON_EVAL: ${OCUTALON_EVAL:-0}
      OCUTALON_MODEL_BASE_URL: http://mock:8080/v1/
      OCUTALON_MOCK_KEY_HEADER: "1"
      OCUTALON_TEST_PLAIN_SMTP: "1"
      OCUTALON_TEST_OAUTH_MOCK: "1"
      OCUTALON_TELEGRAM_API_BASE: http://mock:8080
      TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token
    volumes:
      - mock-log:/opt/ocutalon/mock-log:ro
  mock:
    image: node:24.15.0-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d
    pull_policy: missing
    command: ["node", "/mock/server.mjs", "--log-dir", "/log"]
    volumes:
      - ./ci/mock:/mock:ro
      - mock-log:/log
    healthcheck:
      test: ["CMD", "node", "/mock/health.mjs"]
      interval: 2s
      timeout: 2s
      retries: 15
    stop_grace_period: 2s
volumes:
  mock-log:' ]
}

# The services are iris, and a service named mock (Story 0.11).
ci_services_are_known() {
  local names
  names=$(awk '
    /^services:/ { ins = 1; next }
    /^[^ #]/ { ins = 0 }
    ins && /^  [A-Za-z0-9_.-]+:/ { sub(/:.*/, ""); gsub(/ /, ""); print }
  ' "$ci" | grep -v -x -e iris -e mock)
  [ -z "$names" ]
}

# The non-comment lines of one service block of the CI file (the lines below `  <service>:` up to the next service).
ci_block() {
  code "$ci" | awk -v want="$1" '
    /^[^ ]/ { ins = 0 }
    /^services:/ { ins = 1; next }
    ins && /^  [A-Za-z0-9_.-]+:/ { cur = $1; sub(/:$/, "", cur); next }
    ins && cur == want { print }
  '
}

ci_adds_no_port_or_publishing_key() {
  ! code "$ci" | grep -qE '^[[:space:]]*(ports|env_file|container_name|build|privileged|network_mode|extra_hosts):'
}

# No model key and no variable that looks like a key, a token or a secret, except the one dummy bot token (Story 10.3), which the
# iris block sets once and which is checked below. A line that sets TELEGRAM_BOT_TOKEN is the only line that may name TELEGRAM.
ci_adds_no_key_variable() {
  ! code "$ci" | grep -v -x -e '      OCUTALON_TELEGRAM_API_BASE: http://mock:8080' -e '      TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token' \
    | grep -qE 'ANTHROPIC|TELEGRAM|API_KEY|_TOKEN|SECRET|PASSWORD'
}

# image: appears once, in the mock block, as node:<x.y.z>-slim@sha256:<64 hex>.
ci_image_is_the_pinned_node() {
  [ "$(code "$ci" | grep -cE '^[[:space:]]*image:')" -eq 1 ] \
    && [ "$(ci_block mock | grep -cE '^[[:space:]]*image:[[:space:]]*node:[0-9]+\.[0-9]+\.[0-9]+-slim@sha256:[0-9a-f]{64}[[:space:]]*$')" -eq 1 ]
}

# command: appears only in the mock block.
ci_command_only_in_mock() {
  [ "$(code "$ci" | grep -cE '^[[:space:]]*command:')" -eq 1 ] \
    && [ "$(ci_block mock | grep -cE '^[[:space:]]*command:')" -eq 1 ]
}

# The CI-only switch of owner decision 5: the iris block sets OCUTALON_MOCK_KEY_HEADER to "1", once, and nothing else in the
# file mentions it.
ci_sets_mock_key_header_for_iris() {
  [ "$(code "$ci" | grep -c 'OCUTALON_MOCK_KEY_HEADER')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      OCUTALON_MOCK_KEY_HEADER: "1"')" -eq 1 ]
}

# The CI-only plain-SMTP switch of Story 21.6 (ruling c): the iris block sets OCUTALON_TEST_PLAIN_SMTP to "1", once, and nothing else in
# the file mentions it.
ci_sets_plain_smtp_for_iris() {
  [ "$(code "$ci" | grep -c 'OCUTALON_TEST_PLAIN_SMTP')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      OCUTALON_TEST_PLAIN_SMTP: "1"')" -eq 1 ]
}

# The CI-only OAuth2 mock switch of Story 21.3 (ruling 4): the iris block sets OCUTALON_TEST_OAUTH_MOCK to "1", once, and nothing else in the file
# mentions it.
ci_sets_oauth_mock_for_iris() {
  [ "$(code "$ci" | grep -c 'OCUTALON_TEST_OAUTH_MOCK')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      OCUTALON_TEST_OAUTH_MOCK: "1"')" -eq 1 ]
}

# The Bot API wiring of Story 10.3: the iris block sets OCUTALON_TELEGRAM_API_BASE to the mock, once, and TELEGRAM_BOT_TOKEN to the dummy,
# once, and no other line of the file names either variable.
ci_sets_telegram_base_for_iris() {
  [ "$(code "$ci" | grep -c 'OCUTALON_TELEGRAM_API_BASE')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      OCUTALON_TELEGRAM_API_BASE: http://mock:8080')" -eq 1 ]
}
ci_sets_telegram_token_for_iris() {
  [ "$(code "$ci" | grep -c 'TELEGRAM_BOT_TOKEN')" -eq 1 ] \
    && [ "$(ci_block iris | grep -cx '      TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token')" -eq 1 ]
}

# The dummy bot token matches neither key pattern of test-boundaries.sh that could apply to it (an Anthropic key and a bot token of
# Telegram's shape), so it can sit in a committed file.
ci_dummy_token_is_no_key() {
  local dummy
  dummy=$(code "$ci" | sed -n 's/^      TELEGRAM_BOT_TOKEN:[[:space:]]*//p')
  [ -n "$dummy" ] && ! printf '%s\n' "$dummy" | grep -qE 'sk-ant-[A-Za-z0-9_-]{8,}|[0-9]{8,10}:[A-Za-z0-9_-]{35}'
}

# Only ci/compose.ci.yml sets the switch (owner decision 5): the file must exist and must not name it, so no surface that ships
# or that a developer starts without the CI override carries the mock-key header (the online demo never does).
mock_key_header_absent() { [ -f "$1" ] && ! grep -q 'OCUTALON_MOCK_KEY_HEADER' "$1"; }

# Only ci/compose.ci.yml sets the plain-SMTP switch (Story 21.6): no surface that ships or that a developer starts without the CI override names it.
plain_smtp_absent() { [ -f "$1" ] && ! grep -q 'OCUTALON_TEST_PLAIN_SMTP' "$1"; }

# Only ci/compose.ci.yml sets the OAuth2 mock switch (Story 21.3): no surface that ships or that a developer starts without the CI override names it.
oauth_mock_absent() { [ -f "$1" ] && ! grep -q 'OCUTALON_TEST_OAUTH_MOCK' "$1"; }

# Every compose file of the repository outside the CI override, and every Dockerfile, is free of the given CI-only switch (the shipped compose files and
# the image never set it). The list comes from git, so a compose file added later is covered.
switch_only_in_ci() {
  local f n=0
  while IFS= read -r f; do
    [ "$f" = "$ci" ] && continue
    n=$((n + 1))
    [ -f "$f" ] && ! grep -q "$1" "$f" || return 1
  done < <(git ls-files -- '*compose*.yml' '*compose*.yaml' 'Dockerfile' '*/Dockerfile' | grep -v '\.cls$')
  [ "$n" -ge 5 ]
}

# Story 21.3 (U-320 conditions 2 and 7): nothing that installs or starts the product touches IRIS's OAuth2 objects or the web application /csp/sys/oauth2. The web
# application is enabled only by Channel.Email.OAuth during an admin's register or sign-in action (the class test TestOnlyOneCallerOfTheClass pins the classes), so no
# Dockerfile, compose file, install script, package manifest, CPF merge, start or health script, preload or Python source names it, on the online demo or anywhere
# else. The list comes from git, so a file added later under these paths is covered. The built web bundle under src/ocutalon/csp/ is not scanned (Story 0.34): the
# release cut commits it, and its JavaScript only shows the admin the redirect path to register with the provider; a browser bundle cannot enable that web
# application or create OAuth2 objects.
# oauth_install_paths_clean <repository> <floor> passes when no listed file of that repository names them and at least <floor> files were scanned.
oauth_install_paths_clean() {
  local dir=$1 floor=$2 f n=0
  while IFS= read -r f; do
    [ -f "$dir/$f" ] || continue
    n=$((n + 1))
    if grep -qiE 'csp/sys/oauth2|OAuth2\.(Client|ServerDefinition|AccessToken)' "$dir/$f"; then
      echo "names IRIS's OAuth2 objects or /csp/sys/oauth2: $f"
      return 1
    fi
  done < <(git -C "$dir" ls-files -- Dockerfile 'docker-compose*.yml' install.sh module.xml .env.example 'docker/*' 'release/*' 'src/cpf/*' 'src/module.xml' 'src/preload/*' 'preload/*' 'src/ocutalon/python/*' '.github/*' ci/compose.ci.yml 'ci/*.sh' | grep -v '^docker/tests/')
  [ "$n" -ge "$floor" ]
}
oauth_app_untouched_by_install_paths() { oauth_install_paths_clean . 40; }

# Story 0.34: the same scan on a throwaway repository that holds a clean Dockerfile, with the redirect path the web bundle shows appended to <file>. Prints the
# scan's output and returns its status (0 clean, 1 named); a fixture that cannot be built, or whose <file> git does not track, returns 2. Git runs without the
# caller's GIT_DIR, GIT_WORK_TREE or GIT_INDEX_FILE and without global, system or XDG settings, so no ignore rule outside the fixture decides what is tracked.
oauth_scan_fixture() ( # oauth_scan_fixture <file>
  local w rc
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  w=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-oauth-scan.XXXXXX") || return 2
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$w/.git/xdg"
  if ! { git -C "$w" init -q && mkdir -p "$w/$(dirname "$1")" && printf 'FROM scratch\n' > "$w/Dockerfile" &&
    printf 'const REDIRECT_PATH = "%s";\n' '/csp/sys/oauth2/OAuth2.Response.cls' >> "$w/$1" && git -C "$w" add -A -f &&
    git -C "$w" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }; then
    rm -rf "$w"
    return 2
  fi
  oauth_install_paths_clean "$w" 1
  rc=$?
  rm -rf "$w"
  return "$rc"
)
oauth_scan_fixture_cannot_build() { # passes when a fixture with no temporary folder, or no file to plant the path in, returns 2
  local rc
  TMPDIR=/nonexistent/ocutalon oauth_scan_fixture src/ocutalon/csp/x.js
  rc=$?
  [ "$rc" -eq 2 ] || return 1
  oauth_scan_fixture ''
  rc=$?
  [ "$rc" -eq 2 ]
}
oauth_scan_fixture_names() { # passes when the scan fails on <file> and names exactly that file
  local out rc
  out=$(oauth_scan_fixture "$1")
  rc=$?
  [ "$rc" -eq 1 ] && [ "$out" = "names IRIS's OAuth2 objects or /csp/sys/oauth2: $1" ]
}

# QA of Story 21.8 (DW-1180, Never list): nothing that ships grants the privileges that registering the mail OAuth2 client was measured to need
# (%Admin_OAuth2_Client, %DB_IRISSYS; Test.Channel.EmailOAuthPrivileges MEASURED), to any OcuTalon role or install path. No tracked file of the product, its images, scripts,
# manifests, installer classes, tool metadata and guide names either resource; only the test class that measures them, the test scripts and the planning artifacts may. The list
# comes from git, so a file added later is covered.
measured_privileges_not_granted() {
  local f n=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if grep -qE 'Admin_OAuth2_Client|DB_IRISSYS' "$f"; then
      echo "names a measured OAuth2 privilege: $f"
      return 1
    fi
  done < <(git ls-files -- Dockerfile 'docker-compose*.yml' install.sh module.xml .env.example README.md GUIDE.md docs 'docker/*' 'release/*' 'src/*' 'preload/*' '.github/*' 'ci/*' \
    | grep -v -e '^docker/tests/' -e '/Test/' -e '^ci/mock/test/')
  [ "$n" -ge 100 ]
}

# Only ci/compose.ci.yml sets the Bot API base and gives a bot token a value (Story 10.3): the file must exist, must not name the base and
# must not hold the dummy token. A judge's file may still name TELEGRAM_BOT_TOKEN, as an empty key to fill in (.env.example) or as a
# variable to read.
telegram_wiring_absent() { [ -f "$1" ] && ! grep -q 'OCUTALON_TELEGRAM_API_BASE' "$1" && ! grep -q 'ocutalon-ci-dummy-bot-token' "$1"; }

check "ci: the file is exactly the mock's wiring (project name, iris variables and log volume, mock service, log volume)" ci_file_is_exact
check "ci: the iris service sets OCUTALON_MOCK_KEY_HEADER to \"1\", once, and no other line names it" ci_sets_mock_key_header_for_iris
check "ci: the iris service sets OCUTALON_TEST_PLAIN_SMTP to \"1\", once, and no other line names it" ci_sets_plain_smtp_for_iris
check "ci: the iris service sets OCUTALON_TEST_OAUTH_MOCK to \"1\", once, and no other line names it" ci_sets_oauth_mock_for_iris
check "ci: no compose file or Dockerfile outside ci/compose.ci.yml names OCUTALON_TEST_OAUTH_MOCK" switch_only_in_ci OCUTALON_TEST_OAUTH_MOCK
check "ci: no compose file or Dockerfile outside ci/compose.ci.yml names OCUTALON_TEST_PLAIN_SMTP (it also lets EmailIn send its token over plain POP3 to mock)" switch_only_in_ci OCUTALON_TEST_PLAIN_SMTP
check "install: no Dockerfile, compose file, script, manifest, CPF merge or preload names /csp/sys/oauth2 or IRIS's OAuth2 objects (the web application is enabled only by an admin's sign-in action)" oauth_app_untouched_by_install_paths
check "install: no shipped file (image, script, manifest, installer class, tool metadata, guide) names %Admin_OAuth2_Client or %DB_IRISSYS, so no OcuTalon role or install path grants the measured privileges (DW-1180)" measured_privileges_not_granted
check "install: the OAuth2 scan skips the built web bundle: the redirect path in src/ocutalon/csp/x.js passes (a throwaway repository)" oauth_scan_fixture src/ocutalon/csp/x.js
check "install: the OAuth2 scan still fails the redirect path in a Dockerfile, and names it (a throwaway repository)" oauth_scan_fixture_names Dockerfile
check "install: the OAuth2 scan still fails the redirect path in docker/merge.cpf, and names it (a throwaway repository)" oauth_scan_fixture_names docker/merge.cpf
check "install: an OAuth2 scan fixture that cannot be built returns 2, never a pass (no temporary folder, or no file to plant the path in)" oauth_scan_fixture_cannot_build
check "ci: the iris service sets OCUTALON_TELEGRAM_API_BASE to the mock, once, and no other line names it" ci_sets_telegram_base_for_iris
check "ci: the iris service sets TELEGRAM_BOT_TOKEN to the dummy, once, and no other line names it" ci_sets_telegram_token_for_iris
check "ci: the dummy bot token matches no key pattern" ci_dummy_token_is_no_key
for f in "$compose" "$dev" "$dockerfile" .env.example docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos \
  docker/tests/compose.throwaway.yml docker/tests/lib-live.sh; do
  check "judges: $f does not name OCUTALON_MOCK_KEY_HEADER (only ci/compose.ci.yml sets it)" mock_key_header_absent "$f"
  check "judges: $f does not name OCUTALON_TEST_PLAIN_SMTP (only ci/compose.ci.yml sets it)" plain_smtp_absent "$f"
  check "judges: $f does not name OCUTALON_TEST_OAUTH_MOCK (only ci/compose.ci.yml sets it)" oauth_mock_absent "$f"
  check "judges: $f names neither OCUTALON_TELEGRAM_API_BASE nor the dummy bot token (only ci/compose.ci.yml sets them)" telegram_wiring_absent "$f"
done
check "ci: top-level name ocutalon-ci" has_line "$ci" '^name:[[:space:]]*ocutalon-ci[[:space:]]*$'
check "ci: the services are iris, and mock if there is one" ci_services_are_known
check "ci: no ports, env_file, container_name, build, privileged, network_mode or extra_hosts" ci_adds_no_port_or_publishing_key
check "ci: no key variable anywhere, but the one dummy bot token" ci_adds_no_key_variable
check "ci: image appears once, in the mock block, as node:<x.y.z>-slim pinned by a sha256 digest" ci_image_is_the_pinned_node
check "ci: command appears only in the mock block" ci_command_only_in_mock
check "ci: config parses together with the judges' file (--quiet)" docker compose -f "$compose" -f "$ci" config --quiet
check "ci: config parses together with the judges' file and the throwaway override (--quiet)" \
  docker compose -f "$compose" -f docker/tests/compose.throwaway.yml -f "$ci" config --quiet
check "ci: config parses together with the judges' file and docker-compose.dev.yml (--quiet)" \
  docker compose -f "$compose" -f "$dev" -f "$ci" config --quiet

# --- .env.example ---

env_example_has_keys_without_values() {
  grep -qx 'ANTHROPIC_API_KEY=' .env.example \
    && grep -qx 'TELEGRAM_BOT_TOKEN=' .env.example \
    && ! code .env.example | grep -v -x -e 'ANTHROPIC_API_KEY=' -e 'TELEGRAM_BOT_TOKEN=' | grep -q .
}

# git check-ignore exits 0 when ignored, 1 when not ignored, 128 on error.
# The rule that ignores a path must be one of this repository's .gitignore, not a user's global ignore file;
# -v also prints a matching negation, so the ignore itself is checked with -q.
# A tracked path is never reported as ignored unless --no-index is given.
git_ignores() { git check-ignore -q "$1" && git check-ignore -v "$1" 2>/dev/null | grep -q '^\.gitignore:[0-9]*:[^!]'; }
# The same .gitignore rule, whether or not the path is tracked: a release candidate tracks the built bundle that the rule keeps out of every other branch.
git_ignore_rule() { git check-ignore -q --no-index "$1" && git check-ignore -v --no-index "$1" 2>/dev/null | grep -q '^\.gitignore:[0-9]*:[^!]'; }
git_does_not_ignore() { git check-ignore -q --no-index "$1"; [ $? -eq 1 ]; }

check "env.example: both keys, no values, nothing else" env_example_has_keys_without_values
check "git: .env is ignored" git_ignores .env
check "git: .env.example is not ignored" git_does_not_ignore .env.example

# --- the web bundle and the web sources ---

check "git: the built bundle src/ocutalon/csp/ is ignored" git_ignore_rule src/ocutalon/csp/index.html
check "git: the copied brand images are ignored" git_ignores web/public/assets/brand/icon-192.png
check "git: the Playwright results are ignored" git_ignores web/test-results/x
check "git: the Playwright report is ignored" git_ignores web/playwright-report/index.html
check "git: node_modules is ignored" git_ignores web/node_modules/x
check "git: the lock file is not ignored" git_does_not_ignore web/package-lock.json
check "git: the generated token stylesheet is not ignored" git_does_not_ignore web/src/styles/tokens.css
check "git: the generated sign-in assets are not ignored" git_does_not_ignore src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls
check "git: the vendored fonts are not ignored" git_does_not_ignore web/public/assets/fonts/Inter-Regular.woff2

# web/ keeps LF in every checkout, and a binary is detected, not forced to text.
web_attributes() {
  local f
  for f in web/package.json web/angular.json web/src/main.ts web/scripts/tokens.mjs web/src/styles/tokens.css web/public/assets/fonts/Inter-Regular.woff2; do
    [ "$(git check-attr eol -- "$f" | sed 's/.*: //')" = lf ] || return 1
    [ "$(git check-attr text -- "$f" | sed 's/.*: //')" = auto ] || return 1
  done
}
check "gitattributes: web/ is text only when git detects text, with LF" web_attributes

# --- the Dockerfile sits at the repository root (Story 0.15) ---

# The path that the Dockerfile left, assembled so that this file does not name it.
old_dockerfile=docker/"Dockerfile"

dockerfile_at_root() { [ -f Dockerfile ] && [ ! -e "$old_dockerfile" ]; }

compose_builds_root_dockerfile() {
  has_line "$compose" '^[[:space:]]*context:[[:space:]]*\.[[:space:]]*$' \
    && has_line "$compose" '^[[:space:]]*dockerfile:[[:space:]]*Dockerfile[[:space:]]*$'
}

release_builds_root_dockerfile() { code release/release.sh | grep -qF -- '-f "$ctx/Dockerfile"'; }

# No tracked or unignored file outside the pipeline's own folders names the old path, but the upgrade harness, which reads
# the previous release's tree (v1.0.4 and earlier kept the Dockerfile there), and its test.
no_old_dockerfile_reference() {
  local hits rc
  hits=$(git grep -l --untracked --exclude-standard -F "$old_dockerfile" -- . ':(exclude)_bmad' ':(exclude)_bmad-output' \
    ':(exclude)release/upgrade-harness.sh' ':(exclude)docker/tests/test-upgrade-harness.sh')
  rc=$?
  [ "$rc" -le 1 ] || return 1
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

check "dockerfile: Dockerfile is a file at the repository root and the old path is gone" dockerfile_at_root
check "compose: builds the root Dockerfile from the context ." compose_builds_root_dockerfile
check "release.sh: the image step builds from the root Dockerfile of the context" release_builds_root_dockerfile
check "dockerfile: no file names the old path, except the upgrade harness and its test" no_old_dockerfile_reference

if [ "$fails" -ne 0 ]; then
  echo "test-compose-file: $fails check(s) failed"
  exit 1
fi
echo "test-compose-file: all checks passed"
