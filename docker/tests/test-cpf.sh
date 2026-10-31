#!/usr/bin/env bash
# The CPF resource of the IPM package (Story 15.1; AD-2, AD-3, AD-23; FR-57). Starts nothing: the rules read files only.
#   1. src/cpf/ocutalon.cpf has no line that names %Service_CallIn or %IPM: the package changes no service of the instance, and
#      IPM is mapped into OCUTALON by the package's second early step, not by the CPF file;
#   2. docker/merge.cpf without its lines that name %Service_CallIn or %IPM equals src/cpf/ocutalon.cpf byte for byte, so the
#      Docker install and the package create the same namespace;
#   3. the CPF file holds what AD-3 fixes and nothing else: the resources and databases OCUTALON_CODE, _DATA, _PRIVATE and _PUBLIC,
#      public Read on %DB_OCUTALON_PUBLIC only, the namespace OCUTALON with Interoperability, and the seven mappings;
#   4. src/module.xml has exactly one <CPF> element, the exact one of the package, and no <Resource>, <FileCopy> or <Invoke> line
#      comes before it: the CPF merge is the manifest's first resource;
#   5. src/module.xml declares the preload resource of the second early step and invokes its MapAndStop once, at Initialize, After,
#      and no other Invoke runs at Initialize, the phase where the first run stops (an Invoke of a later phase never runs there);
#   6. .github/workflows/lane-a.yml defines job ipm-install, and the job runs release/ipm-install.sh;
#   7. the job is wired the way the script needs: the base image in IRIS_IMAGE, a run tag that ends in -ipm, the web bundle built
#      before the script runs, and a live deadline that ends before the job's timeout.
#   8. src/module.xml declares the IPM entry point once: the exact Configure, After Invoke of OcuTalon.Install.Registry Ipm, on a line
#      of its own after the MapAndStop Invoke;
# Each rule first runs on synthetic files, one that keeps it and one that breaks it, so a rule that can no longer fail makes the
# test fail. Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cpf.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

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

merge_file=docker/merge.cpf
cpf_file=src/cpf/ocutalon.cpf
manifest=src/module.xml
CPF_ELEMENT='<CPF Name="ocutalon.cpf" Directory="cpf" Phase="Initialize" When="Before"/>'

# --- the rules ---

# 1. No line names %Service_CallIn or %IPM.
no_service_or_ipm() { ! grep -qE '%Service_CallIn|%IPM' "$1"; }

# 2. The merge file without those lines equals the package's file.
merge_without_docker_only() { grep -v -e '%Service_CallIn' -e '%IPM' "$1"; }
files_agree() { # files_agree <merge file> <cpf file>
  merge_without_docker_only "$1" > "$tmp/filtered"
  cmp -s "$tmp/filtered" "$2"
}

# 3. The content AD-3 fixes: every wanted line whole, and public Read on the public database only.
wanted_lines() {
  cat <<'EOW'
CreateResource:Name=%DB_OCUTALON_CODE,Description="OcuTalon code database"
CreateDatabase:Name=OCUTALON_CODE,Directory=ocutalon_code,Resource=%DB_OCUTALON_CODE
CreateResource:Name=%DB_OCUTALON_DATA,Description="OcuTalon data database"
CreateDatabase:Name=OCUTALON_DATA,Directory=ocutalon_data,Resource=%DB_OCUTALON_DATA
CreateResource:Name=%DB_OCUTALON_PRIVATE,Description="OcuTalon private database"
CreateDatabase:Name=OCUTALON_PRIVATE,Directory=ocutalon_private,Resource=%DB_OCUTALON_PRIVATE
CreateResource:Name=%DB_OCUTALON_PUBLIC,Description="OcuTalon public database",PublicPermission=R
CreateDatabase:Name=OCUTALON_PUBLIC,Directory=ocutalon_public,Resource=%DB_OCUTALON_PUBLIC
CreateNamespace:Name=OCUTALON,Globals=OCUTALON_DATA,Routines=OCUTALON_CODE,Interop=1
CreateMapGlobal:Namespace=OCUTALON,Name=OcuTalonP.*,Database=OCUTALON_PRIVATE
CreateMapGlobal:Namespace=OCUTALON,Name=OcuTalonBP.*,Database=OCUTALON_PRIVATE
CreateMapGlobal:Namespace=OCUTALON,Name=AI.Agent.Session*,Database=OCUTALON_PRIVATE
CreateMapGlobal:Namespace=OCUTALON,Name=IRIS.IF.*,Database=OCUTALON_PRIVATE
CreateMapGlobal:Namespace=OCUTALON,Name=OcuTalonPublic,Database=OCUTALON_PUBLIC
CreateMapPackage:Namespace=OCUTALON,Name=OcuTalon.Web.Public,Database=OCUTALON_PUBLIC
CreateMapPackage:Namespace=OCUTALON,Name=OcuTalon.Data.Public,Database=OCUTALON_PUBLIC
EOW
}
cpf_content() {
  local line
  while IFS= read -r line; do
    grep -qxF -- "$line" "$1" || return 1
  done < <(wanted_lines)
  [ "$(grep -c 'PublicPermission=' "$1")" = 1 ] && grep -qxF -- 'CreateResource:Name=%DB_OCUTALON_PUBLIC,Description="OcuTalon public database",PublicPermission=R' "$1" \
    && [ "$(grep -vc '^\[Actions\]$' "$1")" = "$(wanted_lines | wc -l | tr -d ' ')" ]
}

# 4. The manifest's first element is the CPF resource.
cpf_is_first() {
  awk -v want="$CPF_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line ~ /^<CPF[ \/>]/ { ncpf++; if (line != want) bad = 1; if (before) bad = 1; next }
    line ~ /^<(Resource|FileCopy|Invoke)[ \/>]/ { if (!ncpf) before = 1 }
    END { exit (ncpf == 1 && !bad && !before) ? 0 : 1 }' "$1"
}

# 5. The preload resource and the one Invoke of the second early step.
PRELOAD_ELEMENT='<Resource Name="OcuTalon.Install.Ipm.CLS" Directory="cls" Preload="true"/>'
INVOKE_ELEMENT='<Invoke Class="OcuTalon.Install.Ipm" Method="MapAndStop" Phase="Initialize" When="After"/>'
early_step_declared() {
  awk -v pre="$PRELOAD_ELEMENT" -v inv="$INVOKE_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == pre { npre++ }
    line ~ /^<Resource[ \/>].*OcuTalon\.Install\.Ipm/ && line != pre { bad = 1 }
    line == inv { ninv++ }
    line ~ /^<Invoke[ \/>]/ && line ~ /Phase="Initialize"/ && line != inv { bad = 1 }
    END { exit (npre == 1 && ninv == 1 && !bad) ? 0 : 1 }' "$1"
}

# 6. The FR-57 job of lane-a.yml runs the script: the job's block holds the run line.
ipm_job_runs_script() {
  awk '
    /^  [A-Za-z0-9_-]+:[ \t]*$/ { injob = ($1 == "ipm-install:") ; next }
    /^[^ ]/ { injob = 0 }
    injob && $0 ~ /^[ \t]+(- )?run: bash release\/ipm-install\.sh[ \t]*$/ { found = 1 }
    END { exit found ? 0 : 1 }' "$1"
}

# 7. The job's wiring: the base image, the -ipm tag suffix, the bundle build before the script, deadline inside the timeout.
ipm_job_wired() {
  awk '
    /^  [A-Za-z0-9_-]+:[ \t]*$/ { injob = ($1 == "ipm-install:") ; next }
    /^[^ ]/ { injob = 0 }
    !injob { next }
    { line = $0; sub(/^[ \t]+(- )?/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == "IRIS_IMAGE: ocutalon-iris-base:2026.3.0AI.154.0" { image = 1 }
    line ~ /^OCUTALON_RUN_TAG: .*-ipm$/ { tag = 1 }
    line ~ /^timeout-minutes: [0-9]+$/ { timeout = substr(line, 18) + 0 }
    line ~ /^OCUTALON_LIVE_DEADLINE: "?[0-9]+"?$/ { d = line; gsub(/[^0-9]/, "", d); deadline = d + 0 }
    line == "run: bash ci/iris.sh build" { built = 1 }
    line == "run: bash release/ipm-install.sh" { if (built) ordered = 1 }
    END { exit (image && tag && ordered && timeout > 0 && deadline > 0 && deadline < timeout * 60) ? 0 : 1 }' "$1"
}

# 8. The Configure Invoke of the IPM entry point: exactly one Invoke at Configure, the exact one, after the MapAndStop line.
IPM_ELEMENT='<Invoke Class="OcuTalon.Install.Registry" Method="Ipm" Phase="Configure" When="After"/>'
ipm_entry_declared() {
  awk -v inv="$INVOKE_ELEMENT" -v ipm="$IPM_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == inv { if (!seen) seen = NR }
    line == ipm { nipm++; if (!seen) before = 1 }
    line ~ /^<Invoke[ \/>]/ && line ~ /Configure/ && line != ipm { bad = 1 }
    line ~ /Registry/ && line ~ /Method="Ipm"/ && line != ipm { bad = 1 }
    END { exit (nipm == 1 && !before && !bad) ? 0 : 1 }' "$1"
}

# --- the rules on samples ---

wanted_lines > "$tmp/good.cpf"
cp "$tmp/good.cpf" "$tmp/other-good.cpf"
{ cat "$tmp/good.cpf"; echo 'ModifyService:Name=%Service_CallIn,Enabled=1,AutheEnabled=48'; } > "$tmp/with-service.cpf"
{ echo '[Actions]'; cat "$tmp/good.cpf"; echo 'ModifyService:Name=%Service_CallIn,Enabled=1,AutheEnabled=48'; } > "$tmp/cpf.with-service"
{ cat "$tmp/good.cpf"; echo 'CreateMapPackage:Namespace=OCUTALON,Name=%IPM,Database=IRISSYS'; } > "$tmp/with-ipm.cpf"
{ echo '[Actions]'; cat "$tmp/good.cpf"; echo 'ModifyService:Name=%Service_CallIn,Enabled=1,AutheEnabled=48'; echo 'CreateMapPackage:Namespace=OCUTALON,Name=%IPM,Database=IRISSYS'; } > "$tmp/merge.good"
{ echo '[Actions]'; cat "$tmp/good.cpf"; } > "$tmp/cpf.good"
{ echo '[Actions]'; cat "$tmp/good.cpf"; echo 'ModifyService:Name=%Service_Bindings,Enabled=1'; } > "$tmp/merge.extra"
sed 's/$/\r/' "$tmp/cpf.good" > "$tmp/cpf.crlf"
{ echo '[Actions]'; cat "$tmp/good.cpf"; echo 'CreateMapGlobal:Namespace=OCUTALON,Name=Extra*,Database=OCUTALON_PRIVATE'; } > "$tmp/cpf.extra"
sed 's/,PublicPermission=R//' "$tmp/good.cpf" > "$tmp/no-public-read.cpf"
sed 's/Description="OcuTalon code database"/Description="OcuTalon code database",PublicPermission=R/' "$tmp/good.cpf" > "$tmp/two-public-read.cpf"
grep -v 'Name=IRIS.IF.\*' "$tmp/good.cpf" > "$tmp/missing-mapping.cpf"
sed 's/Interop=1/Interop=0/' "$tmp/good.cpf" > "$tmp/no-interop.cpf"
{ cat "$tmp/good.cpf"; echo 'ModifyService:Name=%Service_Bindings,Enabled=1'; } > "$tmp/extra-line.cpf"

if no_service_or_ipm "$tmp/good.cpf" && ! no_service_or_ipm "$tmp/with-service.cpf" && ! no_service_or_ipm "$tmp/with-ipm.cpf"; then
  pass "rule 1 on samples: a file without those lines passes; a %Service_CallIn line or a %IPM line fails"
else
  fail "rule 1 on samples: the checker accepts a %Service_CallIn or %IPM line, or rejects a clean file"
fi
if files_agree "$tmp/merge.good" "$tmp/cpf.good" && ! files_agree "$tmp/merge.extra" "$tmp/cpf.good" \
  && ! files_agree "$tmp/merge.good" "$tmp/cpf.crlf" && ! files_agree "$tmp/merge.good" "$tmp/cpf.with-service" \
  && ! files_agree "$tmp/merge.good" "$tmp/cpf.extra"; then
  pass "rule 2 on samples: equal after the two Docker-only lines pass; another line, other endings or a service line fail"
else
  fail "rule 2 on samples: the checker accepts files that differ, or rejects files that agree"
fi
if cpf_content "$tmp/good.cpf" && ! cpf_content "$tmp/no-public-read.cpf" && ! cpf_content "$tmp/two-public-read.cpf" \
  && ! cpf_content "$tmp/missing-mapping.cpf" && ! cpf_content "$tmp/no-interop.cpf" && ! cpf_content "$tmp/extra-line.cpf"; then
  pass "rule 3 on samples: the full content passes; no public Read, a second public Read, a missing mapping, no Interoperability or an extra line fails"
else
  fail "rule 3 on samples: the checker accepts a CPF file with wrong content, or rejects the right one"
fi

cat > "$tmp/manifest.good" <<EOM
<Module>
  <SourcesRoot>.</SourcesRoot>
  $CPF_ELEMENT
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
  <FileCopy Name="a/" Target="b/"/>
</Module>
EOM
cat > "$tmp/manifest.late" <<EOM
<Module>
  <SourcesRoot>.</SourcesRoot>
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
  $CPF_ELEMENT
</Module>
EOM
cat > "$tmp/manifest.twice" <<EOM
<Module>
  $CPF_ELEMENT
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
  $CPF_ELEMENT
</Module>
EOM
cat > "$tmp/manifest.other" <<'EOM'
<Module>
  <CPF Name="ocutalon.cpf" Directory="cpf" Phase="Initialize" When="After"/>
  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>
</Module>
EOM
printf '<Module>\n  <Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>\n</Module>\n' > "$tmp/manifest.none"
if cpf_is_first "$tmp/manifest.good" && ! cpf_is_first "$tmp/manifest.late" && ! cpf_is_first "$tmp/manifest.twice" \
  && ! cpf_is_first "$tmp/manifest.other" && ! cpf_is_first "$tmp/manifest.none"; then
  pass "rule 4 on samples: the exact CPF element first passes; one after a resource, two, another phase or none fails"
else
  fail "rule 4 on samples: the checker accepts a manifest whose CPF element is not the first and only one, or rejects the right one"
fi

cat > "$tmp/manifest.steps" <<EOM
<Module>
  $CPF_ELEMENT
  $PRELOAD_ELEMENT
  $INVOKE_ELEMENT
</Module>
EOM
grep -v 'Invoke' "$tmp/manifest.steps" > "$tmp/manifest.no-invoke"
grep -v 'Preload' "$tmp/manifest.steps" > "$tmp/manifest.no-preload"
sed 's/When="After"/When="Before"/' "$tmp/manifest.steps" > "$tmp/manifest.invoke-before"
{ cat "$tmp/manifest.steps"; echo "  $INVOKE_ELEMENT"; } > "$tmp/manifest.two-invokes"
{ cat "$tmp/manifest.steps"; echo '  <Invoke Class="OcuTalon.Install.Registry" Method="Run" Phase="Activate" When="After"/>'; } > "$tmp/manifest.later-invoke"
{ cat "$tmp/manifest.steps"; echo '  <Invoke Class="OcuTalon.Install.Registry" Method="Run" Phase="Initialize" When="After"/>'; } > "$tmp/manifest.other-initialize"
if early_step_declared "$tmp/manifest.steps" && early_step_declared "$tmp/manifest.later-invoke" && ! early_step_declared "$tmp/manifest.no-invoke" \
  && ! early_step_declared "$tmp/manifest.no-preload" && ! early_step_declared "$tmp/manifest.invoke-before" && ! early_step_declared "$tmp/manifest.two-invokes" \
  && ! early_step_declared "$tmp/manifest.other-initialize"; then
  pass "rule 5 on samples: the preload resource and the one Invoke pass, also beside an Invoke of a later phase; a missing one, another phase, two Invokes or another Invoke at Initialize fail"
else
  fail "rule 5 on samples: the checker accepts a manifest without the exact preload resource and Invoke, or rejects the right one"
fi

cat > "$tmp/manifest.ipm" <<EOM
<Module>
  $CPF_ELEMENT
  $PRELOAD_ELEMENT
  $INVOKE_ELEMENT
  $IPM_ELEMENT
</Module>
EOM
grep -v 'Method="Ipm"' "$tmp/manifest.ipm" > "$tmp/manifest.ipm-none"
{ cat "$tmp/manifest.ipm"; echo "  $IPM_ELEMENT"; } > "$tmp/manifest.ipm-twice"
awk -v ipm="  $IPM_ELEMENT" -v inv="  $INVOKE_ELEMENT" '$0 == inv { held = $0; next } $0 == ipm { print; print held; next } { print }' "$tmp/manifest.ipm" > "$tmp/manifest.ipm-first"
sed 's/Phase="Configure"/Phase="Activate"/' "$tmp/manifest.ipm" > "$tmp/manifest.ipm-phase"
{ cat "$tmp/manifest.ipm"; echo '  <Invoke Class="OcuTalon.Install.Registry" Method="Run" Phase="Configure" When="After"/>'; } > "$tmp/manifest.ipm-other"
if ipm_entry_declared "$tmp/manifest.ipm" && ! ipm_entry_declared "$tmp/manifest.ipm-none" && ! ipm_entry_declared "$tmp/manifest.ipm-twice" \
  && ! ipm_entry_declared "$tmp/manifest.ipm-first" && ! ipm_entry_declared "$tmp/manifest.ipm-phase" && ! ipm_entry_declared "$tmp/manifest.ipm-other"; then
  pass "rule 8 on samples: the Configure Invoke of Ipm after MapAndStop passes; none, two, one before MapAndStop, another phase or another Invoke at Configure fails"
else
  fail "rule 8 on samples: the checker accepts a manifest without the exact Configure Invoke of Ipm after MapAndStop, or rejects the right one"
fi

cat > "$tmp/lane.good" <<'EOL'
jobs:
  standalone-bridge:
    steps:
      - run: bash release/standalone-bridge.sh
  ipm-install:
    steps:
      - run: bash ci/iris.sh build
      - run: bash release/ipm-install.sh
EOL
grep -v 'release/ipm-install.sh' "$tmp/lane.good" > "$tmp/lane.no-run"
sed 's/ipm-install:/ipm-installed:/' "$tmp/lane.good" > "$tmp/lane.renamed"
cat > "$tmp/lane.other-job" <<'EOL'
jobs:
  ipm-install:
    steps:
      - run: bash ci/iris.sh build
  standalone-bridge:
    steps:
      - run: bash release/ipm-install.sh
EOL
if ipm_job_runs_script "$tmp/lane.good" && ! ipm_job_runs_script "$tmp/lane.no-run" && ! ipm_job_runs_script "$tmp/lane.renamed" \
  && ! ipm_job_runs_script "$tmp/lane.other-job"; then
  pass "rule 6 on samples: a job ipm-install that runs the script passes; no run line, another job name or the line in another job fails"
else
  fail "rule 6 on samples: the checker accepts a workflow whose job ipm-install does not run release/ipm-install.sh, or rejects the right one"
fi

cat > "$tmp/wired.good" <<'EOL'
jobs:
  ipm-install:
    timeout-minutes: 30
    env:
      IRIS_IMAGE: ocutalon-iris-base:2026.3.0AI.154.0
      OCUTALON_RUN_TAG: ${{ github.run_id }}-${{ github.run_attempt }}-ipm
      OCUTALON_LIVE_DEADLINE: "1500"
    steps:
      - run: bash ci/iris.sh build
      - run: bash release/ipm-install.sh
EOL
sed 's/ocutalon-iris-base:2026.3.0AI.154.0/ocutalon-iris-base:latest/' "$tmp/wired.good" > "$tmp/wired.image"
sed 's/-ipm$/-bridge/' "$tmp/wired.good" > "$tmp/wired.tag"
grep -v 'ci/iris.sh build' "$tmp/wired.good" > "$tmp/wired.no-build"
awk '/ci\/iris.sh build/ { held = $0; next } /ipm-install.sh/ { print; print held; next } { print }' "$tmp/wired.good" > "$tmp/wired.build-late"
sed 's/"1500"/"1800"/' "$tmp/wired.good" > "$tmp/wired.deadline"
awk '/^  ipm-install:/ { print "  other:"; next } { print }' "$tmp/wired.good" > "$tmp/wired.renamed"
if ipm_job_wired "$tmp/wired.good" && ! ipm_job_wired "$tmp/wired.image" && ! ipm_job_wired "$tmp/wired.tag" \
  && ! ipm_job_wired "$tmp/wired.no-build" && ! ipm_job_wired "$tmp/wired.build-late" && ! ipm_job_wired "$tmp/wired.deadline" \
  && ! ipm_job_wired "$tmp/wired.renamed"; then
  pass "rule 7 on samples: a wired job passes; another image, a tag without -ipm, no build, a late build, a deadline past the timeout or no job fails"
else
  fail "rule 7 on samples: the checker accepts a mis-wired job ipm-install, or rejects the right one"
fi

# --- the real files ---

check "rule 1: $cpf_file has no line that names %Service_CallIn or %IPM" no_service_or_ipm "$cpf_file"
check "rule 2: $merge_file without its %Service_CallIn and %IPM lines equals $cpf_file" files_agree "$merge_file" "$cpf_file"
check "rule 3: $cpf_file creates the four databases, OCUTALON with Interoperability and the seven mappings" cpf_content "$cpf_file"
check "rule 4: $manifest has the one CPF element, first" cpf_is_first "$manifest"
check "rule 5: $manifest declares the preload resource and invokes MapAndStop once, at Initialize, After, and nothing else at Initialize" early_step_declared "$manifest"
check "rule 6: .github/workflows/lane-a.yml defines job ipm-install, which runs release/ipm-install.sh" ipm_job_runs_script .github/workflows/lane-a.yml
check "rule 7: job ipm-install has the base image, the -ipm tag, the bundle build before the script and a deadline inside the timeout" ipm_job_wired .github/workflows/lane-a.yml
check "rule 8: $manifest invokes OcuTalon.Install.Registry Ipm once, at Configure, After, after MapAndStop" ipm_entry_declared "$manifest"

if [ "$fails" -ne 0 ]; then
  echo "test-cpf: $fails check(s) failed"
  exit 1
fi
echo "test-cpf: all checks passed"
