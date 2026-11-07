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
#      of its own after the MapAndStop Invoke, and no other Invoke at Configure (the Unconfigure Invoke of rule 13 is not one);
#   9. docs/install-ipm.md (QA of Story 15.2) keeps the points of its task and agrees with the code it quotes: no ANSI code, the stop
#      sentence of OcuTalon.Install.Ipm after `ERROR! `, the install command and the iris merge commands, the demo-mode, model-key and
#      README-account lines, the line of Registry FailureLine, and the STEP lines inside Configure START and SUCCESS (each OK, and
#      every name of Registry.Order() once, in its order), in each Configure block of the document (at least one).
#  10. src/module.xml (QA of Story 15.3) declares the exact SystemRequirements element, once, so IPM refuses a first run in a namespace
#      without Interoperability (U-231);
#  11. docs/install-ipm.md (QA of Story 15.3) starts in USER, quotes that refusal line exactly as release/ipm-install.sh asserts it,
#      says to run the command in USER instead, and promises no first run in any namespace or in %SYS.
#  12. docs/install-ipm.md (Story 15.4) opens with the registry install: its `## ` section comes before the developers' section,
#      `zpm "enable -community"` comes before the first `zpm "install ocutalon"`, the U-232 sentence is present, the output of
#      `enable -community` (RUNNING command: "enable -map -repos -globally") is inside a code block, and the page does not mention
#      Node.js before the developers' section;
#  13. src/module.xml declares the Unconfigure Invoke of OcuTalon.Install.Ipm UnmapRepos once, on a line of its own after the
#      Configure Invoke (U-232: uninstalling removes only the repository mapping).
#  14. (QA of Story 15.4) release/ipm-install.sh never prints USER's repository definitions: the repository is added with its output
#      discarded, nothing lists repositories, each hash is kept in a variable and never echoed; and the real uninstall_checks passes only
#      for equal hashes with at least one node, and prints none (U-232 condition 1);
#  15. (QA of Story 15.4) docs/security-overview.md holds the ruled Data bullet on the repository mapping (U-232 condition 3).
#  16. (Story 15.4) release/ipm-install.sh with no argument, the job's run, ends with part p (AC 5).
#  17. (Story 19.8, DW-829) the manifests (src/module.xml and module.xml) invoke OcuTalon.Install.Ipm RemoveStaleCopies once, at Reload, Before,
#      with the module root and ${BypassPyDeps} as its arguments, on a line of its own after the MapAndStop Invoke, and declare the Default
#      BypassPyDeps (0) once; no other Invoke runs at Reload, so IPM's pip step finds the stale copies of the pinned packages removed.
#  18. (Story 19.8, QA, DW-829) the Python of check 32 in release/ipm-install.sh, taken out of the script and run on a scratch folder (no
#      container, no IPM): the import check passes the pinned copies (also a pin spelled with a leading zero and a module with no
#      __version__) and fails a version-only difference (urllib3's __init__.py is the same file in both versions), code that is not the
#      pinned RECORD's, a file outside the folder, a module that did not import and a missing pinned dist-info; the folder comparison
#      accepts only the six moving to the pins and the pins added, and fails a stale dist-info that stays, a missing pin, a changed or
#      missing or unpinned distribution, a lost top-level item, an IPM module that no longer imports and an empty import record; the
#      uninstall comparison accepts only the two Python resources gone and fails a distribution gone, changed or added, a top-level item
#      gone or added, a lost import and an empty import record; python_state writes the D and T lines the comparisons read; the licence
#      gate's skip rule gates an older copy of a pinned name that was there before the install and skips a name that is no pin.
#  19. (Story 19.8, QA, DW-829) release/ipm-install.sh runs the import check at both places of check 32: check_python_pins right after check_licences
#      on path A (and path A then runs check_reinstall) and on part p (and part p runs check_uninstall_python after its uninstall, then the
#      install command in USER from the local repository, which stops with its next command), and
#      check_python_pins runs the import check, the folder comparison, zpm "list" and the Invoke's arguments.
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
UNMAP_ELEMENT='<Invoke Class="OcuTalon.Install.Ipm" Method="UnmapRepos" Phase="Unconfigure" When="Before"/>'
ipm_entry_declared() {
  awk -v inv="$INVOKE_ELEMENT" -v ipm="$IPM_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == inv { if (!seen) seen = NR }
    line == ipm { nipm++; if (!seen) before = 1 }
    line ~ /^<Invoke[ \/>]/ && line ~ /Phase="Configure"/ && line != ipm { bad = 1 }
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
{ cat "$tmp/manifest.ipm"; echo "  $UNMAP_ELEMENT"; } > "$tmp/manifest.ipm-unconfigure"
if ipm_entry_declared "$tmp/manifest.ipm" && ipm_entry_declared "$tmp/manifest.ipm-unconfigure" && ! ipm_entry_declared "$tmp/manifest.ipm-none" && ! ipm_entry_declared "$tmp/manifest.ipm-twice" \
  && ! ipm_entry_declared "$tmp/manifest.ipm-first" && ! ipm_entry_declared "$tmp/manifest.ipm-phase" && ! ipm_entry_declared "$tmp/manifest.ipm-other"; then
  pass "rule 8 on samples: the Configure Invoke of Ipm after MapAndStop passes, also beside the Unconfigure Invoke; none, two, one before MapAndStop, another phase or another Invoke at Configure fails"
else
  fail "rule 8 on samples: the checker accepts a manifest without the exact Configure Invoke of Ipm after MapAndStop, or rejects the right one"
fi

# 9. The install document. The code it quotes is read from the sources: the stop sentence (preload/.../Install/Ipm.cls STOP, whose
# doubled quotation marks are one) and the tail of Registry FailureLine, and the order of Registry.Order().
ipm_class=src/preload/cls/OcuTalon/Install/Ipm.cls
registry_class=src/ocutalon/cls/OcuTalon/Install/Registry.cls
install_doc=docs/install-ipm.md
stop_sentence() { sed -n 's/^Parameter STOP = "\(.*\)";$/\1/p' "$1" | sed 's/""/"/g'; }
failure_tail() { sed -n 's/^[[:space:]]*Quit "STEP " _ step _ " FAILED: \(.*\)"$/\1/p' "$1"; }
order_names() {
  awk '/ClassMethod Order\(\)/ { on = 1 } on && /Quit \$ListBuild\(/ { print; exit }' "$1" | sed 's/^[^(]*(//; s/)[^)]*$//' | tr -d '" ' | tr ',' ' '
}
DOC_PHRASES=(
  'zpm "load /opt/ocutalon-ipm/src"'
  'zn "OCUTALON"'
  'iris merge <instance> /opt/ocutalon-ipm/src/cpf/ocutalon.cpf'
  'zpm "enable -map -ns OCUTALON"'
  'do ##class(OcuTalon.Core.Admin).SetDemoMode(1)'
  'do ##class(OcuTalon.Core.Admin).SetDemoMode(0)'
  'ANTHROPIC_API_KEY'
  'Node.js 24.15'
  'IPM 0.10.10'
  '`ocutalon`'
  'Security.Users'
  'Modify("ocutalon"'
)
# install_doc_ok <doc> <stop sentence> <failure tail> <order names, blank separated>
install_doc_ok() {
  local doc=$1 stop=$2 tail=$3 order=$4 phrase
  [ -n "$stop" ] && [ -n "$tail" ] && [ -n "$order" ] || return 1
  ! grep -q "$(printf '\033')" "$doc" || return 1
  grep -qxF -- "ERROR! $stop" "$doc" || return 1
  for phrase in "${DOC_PHRASES[@]}"; do
    grep -qF -- "$phrase" "$doc" || return 1
  done
  grep -qF -- "STEP <name> FAILED: $tail" "$doc" || return 1
  awk -v order="$order" '
    BEGIN { n = split(order, names, " "); for (i = 1; i <= n; i++) pos[names[i]] = i }
    /Configure START/ { if (on) bad = 1; on = 1; last = 0; count = 0; next }
    /Configure SUCCESS/ { if (!on || count != n) bad = 1; on = 0; closed++ }
    on && /^STEP / {
      if ($3 != "OK" || !($2 in pos) || pos[$2] <= last) bad = 1
      last = pos[$2]; count++
    }
    END { exit (closed >= 1 && !on && !bad) ? 0 : 1 }' "$doc"
}

stop_text=$(stop_sentence "$ipm_class")
fail_tail=$(failure_tail "$registry_class")
order_text=$(order_names "$registry_class")
{
  echo "ERROR! $stop_text"
  for phrase in "${DOC_PHRASES[@]}"; do echo "$phrase"; done
  echo "\`STEP <name> FAILED: $fail_tail\`"
  echo '[OCUTALON|ocutalon]	Configure START'
  for name in $order_text; do echo "STEP $name OK 0.0s"; done
  echo '[OCUTALON|ocutalon]	Configure SUCCESS'
} > "$tmp/doc.good"
{ cat "$tmp/doc.good"; printf '\033[0m\n'; } > "$tmp/doc.ansi"
sed 's/^ERROR! OcuTalon created namespace OCUTALON\./ERROR! OcuTalon made namespace OCUTALON./' "$tmp/doc.good" > "$tmp/doc.stop"
grep -v 'iris merge' "$tmp/doc.good" > "$tmp/doc.no-merge"
grep -v 'SetDemoMode(0)' "$tmp/doc.good" > "$tmp/doc.no-demo-off"
grep -v 'ANTHROPIC_API_KEY' "$tmp/doc.good" > "$tmp/doc.no-key"
grep -v 'STEP <name> FAILED' "$tmp/doc.good" > "$tmp/doc.no-failure"
sed 's/Run the same install command again\./Try again./' "$tmp/doc.good" > "$tmp/doc.failure-tail"
grep -v '^STEP Production OK' "$tmp/doc.good" > "$tmp/doc.no-production"
sed 's/^STEP Web OK/STEP Browser OK/' "$tmp/doc.good" > "$tmp/doc.renamed-step"
sed 's/^STEP Roles OK 0.0s$/STEP Roles FAILED boom/' "$tmp/doc.good" > "$tmp/doc.failed-step"
awk '/^STEP Public OK/ { held = $0; next } /^STEP Roles OK/ { print; print held; next } { print }' "$tmp/doc.good" > "$tmp/doc.misordered"
grep -v 'Configure SUCCESS' "$tmp/doc.good" > "$tmp/doc.unclosed"
{ cat "$tmp/doc.good"; echo '[OCUTALON|ocutalon]	Configure START'; for name in $order_text; do echo "STEP $name OK 0.0s"; done; echo '[OCUTALON|ocutalon]	Configure SUCCESS'; } > "$tmp/doc.two-blocks"
{ cat "$tmp/doc.good"; echo '[OCUTALON|ocutalon]	Configure START'; for name in $order_text; do echo "STEP $name OK 0.0s"; done | awk '/^STEP Public OK/ { held = $0; next } /^STEP Roles OK/ { print; print held; next } { print }'; echo '[OCUTALON|ocutalon]	Configure SUCCESS'; } > "$tmp/doc.second-misordered"
{ cat "$tmp/doc.good"; echo '[OCUTALON|ocutalon]	Configure START'; for name in $order_text; do echo "STEP $name OK 0.0s"; done | grep -v '^STEP Production OK'; echo '[OCUTALON|ocutalon]	Configure SUCCESS'; } > "$tmp/doc.second-short"
{ cat "$tmp/doc.good"; echo '[OCUTALON|ocutalon]	Configure START'; } > "$tmp/doc.second-unclosed"
{ grep -v 'Configure SUCCESS' "$tmp/doc.good"; cat "$tmp/doc.good"; } > "$tmp/doc.first-unclosed"
grep -v 'Configure START' "$tmp/doc.good" > "$tmp/doc.no-start"
if install_doc_ok "$tmp/doc.good" "$stop_text" "$fail_tail" "$order_text" \
  && install_doc_ok "$tmp/doc.two-blocks" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.second-misordered" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.second-short" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.second-unclosed" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.first-unclosed" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.no-start" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.ansi" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.stop" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.no-merge" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.no-demo-off" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.no-key" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.no-failure" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.failure-tail" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.no-production" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.renamed-step" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.failed-step" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.misordered" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.unclosed" "$stop_text" "$fail_tail" "$order_text" \
  && ! install_doc_ok "$tmp/doc.good" "$stop_text" "$fail_tail" "$order_text ZzAddedStep" \
  && ! install_doc_ok "$tmp/doc.good" "" "$fail_tail" "$order_text"; then
  pass "rule 9 on samples: a document with every point passes, also with two Configure blocks; a second block that is misordered, short or unclosed, or a SUCCESS line with no START line fails; an ANSI code, another stop sentence, a missing command, key or failure line, a changed failure line, a missing, renamed, failed or misordered STEP, a step the order gained, no Configure SUCCESS or no source text fails"
else
  fail "rule 9 on samples: the checker accepts a document that lost a point or disagrees with the code, or rejects the right one"
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

# 10. The staff-requested system requirement (Story 15.3, U-231): src/module.xml declares the exact SystemRequirements element, once, on
# a line of its own. Without it IPM no longer refuses a first run in a namespace without Interoperability (such as %SYS).
SYSREQ_ELEMENT='<SystemRequirements Version=">=2026.3" Interoperability="enabled"/>'
sysreq_declared() {
  awk -v want="$SYSREQ_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == want { n++ }
    line ~ /SystemRequirements/ && line != want { bad = 1 }
    END { exit (n == 1 && !bad) ? 0 : 1 }' "$1"
}
{ echo '<Module>'; echo "  $CPF_ELEMENT"; echo "  $SYSREQ_ELEMENT"; echo '</Module>'; } > "$tmp/manifest.sysreq"
grep -v 'SystemRequirements' "$tmp/manifest.sysreq" > "$tmp/manifest.sysreq-none"
{ cat "$tmp/manifest.sysreq"; echo "  $SYSREQ_ELEMENT"; } > "$tmp/manifest.sysreq-twice"
sed 's/Interoperability="enabled"/Interoperability="disabled"/' "$tmp/manifest.sysreq" > "$tmp/manifest.sysreq-interop"
sed 's/>=2026.3/>=2024.1/' "$tmp/manifest.sysreq" > "$tmp/manifest.sysreq-version"
sed '/SystemRequirements/ s/^\(.*\)$/<!-- \1 -->/' "$tmp/manifest.sysreq" > "$tmp/manifest.sysreq-commented"
if sysreq_declared "$tmp/manifest.sysreq" && ! sysreq_declared "$tmp/manifest.sysreq-none" && ! sysreq_declared "$tmp/manifest.sysreq-twice" \
  && ! sysreq_declared "$tmp/manifest.sysreq-interop" && ! sysreq_declared "$tmp/manifest.sysreq-version" && ! sysreq_declared "$tmp/manifest.sysreq-commented"; then
  pass "rule 10 on samples: the exact SystemRequirements element once passes; none, two, another Interoperability value, another version or a commented one fails"
else
  fail "rule 10 on samples: the checker accepts a manifest without the exact SystemRequirements element, or rejects the right one"
fi

# 11. The install document follows U-231 (Story 15.3): the first run starts in USER, IPM's refusal in a namespace without Interoperability
# is quoted exactly as release/ipm-install.sh asserts it (the line alone, once), the reader is sent back to USER, and no sentence promises
# a first run in any namespace or in %SYS.
script_refusal=$(sed -n "s/^REFUSAL='\(.*\)'$/\1/p" release/ipm-install.sh)
ns_doc_ok() { # ns_doc_ok <doc> <refusal text>
  local doc=$1 refusal=$2
  [ -n "$refusal" ] || return 1
  [ "$(grep -cxF -- "ERROR! $refusal" "$doc")" -eq 1 ] || return 1
  grep -qF -- 'Open an IRIS terminal in USER and load the package' "$doc" || return 1
  grep -qF -- 'USER is one on both IRIS for Health and IRIS build 154' "$doc" || return 1
  grep -qF -- 'run the command in USER instead' "$doc" || return 1
  ! grep -qiE 'in any namespace|USER or %SYS|namespace you start from' "$doc" || return 1
}
cat > "$tmp/nsdoc.good" <<EOM
Open an IRIS terminal in USER and load the package:
OcuTalon needs an Interoperability-enabled namespace, and USER is one on both IRIS for Health and IRIS build 154. IPM refuses it in %SYS:
ERROR! $script_refusal
If you see it, run the command in USER instead.
Running the first command again in USER gives the same stop and changes nothing.
EOM
grep -v '^ERROR!' "$tmp/nsdoc.good" > "$tmp/nsdoc.no-refusal"
sed 's/is not interoperability-enabled\./is not enabled./' "$tmp/nsdoc.good" > "$tmp/nsdoc.changed-refusal"
{ cat "$tmp/nsdoc.good"; echo "ERROR! $script_refusal"; } > "$tmp/nsdoc.twice"
sed 's/^ERROR! \(.*\)$/Note: \1/' "$tmp/nsdoc.good" > "$tmp/nsdoc.inline"
sed 's/terminal in USER and/terminal in any namespace (USER here) and/' "$tmp/nsdoc.good" > "$tmp/nsdoc.any-namespace"
sed 's/in USER gives the same/in USER or %SYS gives the same/' "$tmp/nsdoc.good" > "$tmp/nsdoc.sys-repeat"
sed 's/run the command in USER instead/try again/' "$tmp/nsdoc.good" > "$tmp/nsdoc.no-advice"
sed 's/ and USER is one on both IRIS for Health and IRIS build 154//' "$tmp/nsdoc.good" > "$tmp/nsdoc.no-images"
if ns_doc_ok "$tmp/nsdoc.good" "$script_refusal" && ! ns_doc_ok "$tmp/nsdoc.no-refusal" "$script_refusal" && ! ns_doc_ok "$tmp/nsdoc.changed-refusal" "$script_refusal" \
  && ! ns_doc_ok "$tmp/nsdoc.twice" "$script_refusal" && ! ns_doc_ok "$tmp/nsdoc.inline" "$script_refusal" && ! ns_doc_ok "$tmp/nsdoc.any-namespace" "$script_refusal" \
  && ! ns_doc_ok "$tmp/nsdoc.sys-repeat" "$script_refusal" && ! ns_doc_ok "$tmp/nsdoc.no-advice" "$script_refusal" && ! ns_doc_ok "$tmp/nsdoc.no-images" "$script_refusal" \
  && ! ns_doc_ok "$tmp/nsdoc.good" ""; then
  pass "rule 11 on samples: a document with the USER start, the exact refusal line once, both images and the advice passes; a missing, changed, doubled or inline refusal, a first run promised in any namespace or %SYS, no advice or no image note fails"
else
  fail "rule 11 on samples: the checker accepts a document that lost a point of U-231, or rejects the right one"
fi

# 12. The install document opens with the registry install (Story 15.4, U-232): the registry section comes before the developers' section,
# `enable -community` comes before the first install command, the U-232 sentence is there, the output of `enable -community` stands
# inside a code block, and Node.js is not mentioned before the developers' section.
REGISTRY_HEADING='## Install from the package registry'
DEVELOPERS_HEADING='## Install from the package folder (for developers)'
SHARED_SENTENCE='OCUTALON shares the repositories of the namespace where you ran the first command, so a repository added or removed in either namespace changes both.'
registry_doc_ok() { # registry_doc_ok <doc>
  local doc=$1
  awk -v reg="$REGISTRY_HEADING" -v dev="$DEVELOPERS_HEADING" -v shared="$SHARED_SENTENCE" '
    $0 == reg { if (!r) r = NR }
    $0 == dev { if (!d) d = NR }
    /^```/ { fence = !fence }
    index($0, "zpm \"enable -community\"") && !e { e = NR }
    index($0, "zpm \"install ocutalon\"") && !i { i = NR }
    index($0, shared) { s = NR }
    index($0, "RUNNING command: \"enable -map -repos -globally\"") && fence { o = NR }
    index($0, "Node.js") && !n { n = NR }
    END { exit (r && d && r < d && e && i && r < e && e < i && i < d && s > r && s < d && o > e && o < i && (!n || n > d)) ? 0 : 1 }' "$doc"
}
cat > "$tmp/regdoc.good" <<'EOM'
# Install

## What you need

IPM 0.10.10.

## Install from the package registry

```
zpm "enable -community"
```

```
RUNNING command: "enable -map -repos -globally"
```

```
zpm "install ocutalon"
```

OCUTALON shares the repositories of the namespace where you ran the first command, so a repository added or removed in either namespace changes both.

## Install from the package folder (for developers)

Build with Node.js 24.15.

## Demo mode
EOM
awk '$0 == "## Install from the package registry" { hold = 1 } hold && $0 == "## Install from the package folder (for developers)" { hold = 0 } !hold' "$tmp/regdoc.good" > "$tmp/regdoc.no-registry"
awk '/^## Install from the package registry$/ { sec = 1 } /^## Install from the package folder/ { sec = 2 } sec == 1 { a = a $0 "\n"; next } sec == 2 && /^## Demo mode$/ { sec = 3 } sec == 2 { b = b $0 "\n"; next } { if (sec == 3 && !done) { printf "%s%s", b, a; done = 1 } print }' "$tmp/regdoc.good" > "$tmp/regdoc.swapped"
sed 's/zpm "enable -community"/zpm "enable -map"/' "$tmp/regdoc.good" > "$tmp/regdoc.no-enable"
{ echo 'zpm "install ocutalon"'; cat "$tmp/regdoc.good"; } > "$tmp/regdoc.install-first"
grep -v 'OCUTALON shares' "$tmp/regdoc.good" > "$tmp/regdoc.no-sentence"
sed 's/^RUNNING command: .*$/Some output./' "$tmp/regdoc.good" > "$tmp/regdoc.no-output"
sed 's/^IPM 0.10.10\.$/IPM 0.10.10 and Node.js 24.15./' "$tmp/regdoc.good" > "$tmp/regdoc.node-early"
sed 's/^```$/~~~/' "$tmp/regdoc.good" > "$tmp/regdoc.no-fence"
if registry_doc_ok "$tmp/regdoc.good" && ! registry_doc_ok "$tmp/regdoc.no-registry" && ! registry_doc_ok "$tmp/regdoc.swapped" \
  && ! registry_doc_ok "$tmp/regdoc.no-enable" && ! registry_doc_ok "$tmp/regdoc.install-first" && ! registry_doc_ok "$tmp/regdoc.no-sentence" \
  && ! registry_doc_ok "$tmp/regdoc.no-output" && ! registry_doc_ok "$tmp/regdoc.node-early" && ! registry_doc_ok "$tmp/regdoc.no-fence"; then
  pass "rule 12 on samples: a registry-first document passes; no registry section, the developers' section first, no enable -community, an install command before it, no shared-repositories sentence, no enable output in a code block or Node.js before the developers' section fails"
else
  fail "rule 12 on samples: the checker accepts a document that is not registry-first, or rejects the right one"
fi

# 13. The Unconfigure Invoke (Story 15.4, U-232): src/module.xml declares OcuTalon.Install.Ipm UnmapRepos at Unconfigure, Before, once, on a
# line of its own after the Configure Invoke of the IPM entry point; uninstalling OcuTalon then removes only the repository mapping.
unmap_declared() {
  awk -v unmap="$UNMAP_ELEMENT" -v ipm="$IPM_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == ipm { if (!unm) seen = 1 }
    line == unmap { n++; if (seen) after = 1; unm = 1 }
    line ~ /UnmapRepos/ && line != unmap { bad = 1 }
    line ~ /^<Invoke[ \/>]/ && line ~ /Phase="Unconfigure"/ && line != unmap { bad = 1 }
    END { exit (n == 1 && after && !bad) ? 0 : 1 }' "$1"
}
grep -v 'UnmapRepos' "$tmp/manifest.ipm-unconfigure" > "$tmp/manifest.unmap-none"
{ cat "$tmp/manifest.ipm-unconfigure"; echo "  $UNMAP_ELEMENT"; } > "$tmp/manifest.unmap-twice"
awk -v unmap="  $UNMAP_ELEMENT" -v ipm="  $IPM_ELEMENT" '$0 == ipm { held = 1; next } $0 == unmap { print; if (held) print ipm; next } { print }' "$tmp/manifest.ipm-unconfigure" > "$tmp/manifest.unmap-first"
sed '/UnmapRepos/ s/When="Before"/When="After"/' "$tmp/manifest.ipm-unconfigure" > "$tmp/manifest.unmap-after"
sed '/UnmapRepos/ s/Phase="Unconfigure"/Phase="Clean"/' "$tmp/manifest.ipm-unconfigure" > "$tmp/manifest.unmap-phase"
sed '/UnmapRepos/ s/UnmapRepos/Unmap/' "$tmp/manifest.ipm-unconfigure" > "$tmp/manifest.unmap-method"
if unmap_declared "$tmp/manifest.ipm-unconfigure" && ! unmap_declared "$tmp/manifest.unmap-none" && ! unmap_declared "$tmp/manifest.unmap-twice" \
  && ! unmap_declared "$tmp/manifest.unmap-first" && ! unmap_declared "$tmp/manifest.unmap-after" && ! unmap_declared "$tmp/manifest.unmap-phase" && ! unmap_declared "$tmp/manifest.unmap-method"; then
  pass "rule 13 on samples: the Unconfigure Invoke once after the Configure Invoke passes; none, two, one before it, When=After, another phase or another method fails"
else
  fail "rule 13 on samples: the checker accepts a manifest without the exact Unconfigure Invoke after the Configure Invoke, or rejects the right one"
fi

# 17. The early Reload Invoke of the stale-copy step (Story 19.8): the exact Invoke, once, after the MapAndStop line, the exact Default once, and no
# other Invoke at Reload or of that method.
STALE_ELEMENT='<Invoke Class="OcuTalon.Install.Ipm" Method="RemoveStaleCopies" Phase="Reload" When="Before"><Arg>${root}</Arg><Arg>${BypassPyDeps}</Arg></Invoke>'
DEFAULT_ELEMENT='<Default Name="BypassPyDeps" Value="0"/>'
stale_step_declared() {
  awk -v inv="$INVOKE_ELEMENT" -v st="$STALE_ELEMENT" -v def="$DEFAULT_ELEMENT" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == inv { if (!seen) seen = NR }
    line == st { nst++; if (!seen) before = 1 }
    line == def { ndef++ }
    line ~ /^<Invoke[ \/>]/ && line ~ /Phase="Reload"/ && line != st { bad = 1 }
    line ~ /RemoveStaleCopies/ && line != st { bad = 1 }
    line ~ /^<Default[ \/>]/ && line != def { bad = 1 }
    END { exit (nst == 1 && ndef == 1 && !before && !bad) ? 0 : 1 }' "$1"
}
cat > "$tmp/manifest.stale" <<EOM
<Module>
  $DEFAULT_ELEMENT
  $CPF_ELEMENT
  $PRELOAD_ELEMENT
  $INVOKE_ELEMENT
  $STALE_ELEMENT
  $IPM_ELEMENT
</Module>
EOM
grep -v 'RemoveStaleCopies' "$tmp/manifest.stale" > "$tmp/manifest.stale-none"
grep -v 'BypassPyDeps="0"\|<Default ' "$tmp/manifest.stale" > "$tmp/manifest.stale-nodefault"
{ cat "$tmp/manifest.stale"; echo "  $STALE_ELEMENT"; } > "$tmp/manifest.stale-twice"
awk -v st="  $STALE_ELEMENT" -v inv="  $INVOKE_ELEMENT" '$0 == inv { held = $0; next } $0 == st { print; print held; next } { print }' "$tmp/manifest.stale" > "$tmp/manifest.stale-first"
sed '/RemoveStaleCopies/ s/Phase="Reload"/Phase="Validate"/' "$tmp/manifest.stale" > "$tmp/manifest.stale-phase"
sed '/RemoveStaleCopies/ s/When="Before"/When="After"/' "$tmp/manifest.stale" > "$tmp/manifest.stale-after"
sed '/RemoveStaleCopies/ s/<Arg>${BypassPyDeps}<\/Arg>//' "$tmp/manifest.stale" > "$tmp/manifest.stale-arg"
sed 's/Name="BypassPyDeps" Value="0"/Name="BypassPyDeps" Value="1"/' "$tmp/manifest.stale" > "$tmp/manifest.stale-value"
{ cat "$tmp/manifest.stale"; echo '  <Invoke Class="OcuTalon.Install.Registry" Method="Run" Phase="Reload" When="After"/>'; } > "$tmp/manifest.stale-other"
{ cat "$tmp/manifest.stale"; echo '  <Invoke Class="OcuTalon.Install.Registry" Method="Run" Phase="Activate" When="After"/>'; } > "$tmp/manifest.stale-later"
if stale_step_declared "$tmp/manifest.stale" && stale_step_declared "$tmp/manifest.stale-later" && ! stale_step_declared "$tmp/manifest.stale-none" \
  && ! stale_step_declared "$tmp/manifest.stale-nodefault" && ! stale_step_declared "$tmp/manifest.stale-twice" && ! stale_step_declared "$tmp/manifest.stale-first" \
  && ! stale_step_declared "$tmp/manifest.stale-phase" && ! stale_step_declared "$tmp/manifest.stale-after" && ! stale_step_declared "$tmp/manifest.stale-arg" \
  && ! stale_step_declared "$tmp/manifest.stale-value" && ! stale_step_declared "$tmp/manifest.stale-other"; then
  pass "rule 17 on samples: the Reload Invoke and the Default pass, also beside an Invoke of a later phase; none, no Default, two Invokes, one before MapAndStop, another phase, When=After, a changed argument or Default, or another Invoke at Reload fails"
else
  fail "rule 17 on samples: the checker accepts a manifest without the exact Reload Invoke and Default after MapAndStop, or rejects the right one"
fi

stale_step_declared_both() { stale_step_declared src/module.xml && stale_step_declared module.xml; }

# 18. The Python of check 32 (Story 19.8, QA): the heredocs of check_imports, check_python_moves and check_licences, run on scratch folders. The
# driver builds each case (a pinned state, and the states that must fail) and compares the exit code and the text of the script; a script that
# accepts a stale state, or rejects the pinned one, fails the check, and so does a script that cannot be taken out of release/ipm-install.sh.
heredoc_of() { # heredoc_of <function> <n>: the nth heredoc (terminator EOP) of the function in release/ipm-install.sh
  awk -v fn="$1" -v n="$2" '
    index($0, fn "() {") == 1 { infn = 1; next }
    infn && /^}/ { infn = 0 }
    infn && !grab && /<< .EOP.( |$)/ { if (++count == n) grab = 1; next }
    grab && /^EOP$/ { exit }
    grab { print }' release/ipm-install.sh
}
cat > "$tmp/ipm-driver.py" << 'EOD'
import base64, hashlib, os, shutil, subprocess, sys
mode, script, work = sys.argv[1:4]
SIX = [("certifi", "2026.10.23"), ("charset_normalizer", "3.5.2"), ("idna", "3.15"), ("requests", "2.34.2"),
       ("typing_extensions", "4.16.0"), ("urllib3", "2.8.0")]
problems = []
def run(*args):
    done = subprocess.run([sys.executable, script] + list(args), capture_output=True, text=True)
    return done.returncode, done.stdout
def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)
def expect(label, got, want):
    if got != want:
        problems.append("%s: got %r, wanted %r" % (label, got, want))
def case_dir(name):
    path = os.path.join(work, name)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path
def module_file(name):
    return "typing_extensions.py" if name == "typing_extensions" else name + "/__init__.py"
def build(base, spelling=None):
    """The folder with the six pinned distributions (file, dist-info with a RECORD) and the constraints file."""
    target = os.path.join(base, "python")
    for name, pin in SIX:
        rel = module_file(name)
        text = "# %s %s\n" % (name, pin)
        put(os.path.join(target, rel), text)
        digest = base64.urlsafe_b64encode(hashlib.sha256(text.encode()).digest()).rstrip(b"=").decode()
        info = "%s-%s.dist-info" % (name, pin)
        put(os.path.join(target, info, "RECORD"), "%s,sha256=%s,%d\n%s/RECORD,,\n" % (rel, digest, len(text), info))
    lines = ["# pins"] + ["%s==%s" % (name.replace("_", "-"), (spelling or {}).get(name, pin)) for name, pin in SIX] + ["fastembed==0.8.0"]
    put(os.path.join(base, "constraints.txt"), "\n".join(lines) + "\n")
    return target, os.path.join(base, "constraints.txt")
def imports(target, **override):
    out = []
    for name, pin in SIX:
        version, path = ("" if name == "typing_extensions" else pin), os.path.join(target, module_file(name))
        if name in override:
            version, path = override[name]
        out.append("CHK|import|%s|%s|%s" % (name, version, path))
    return "\n".join(out)

if mode == "imports":
    def go(label, want_rc, want_last, mutate=None, spelling=None, override=None):
        base = case_dir(label.replace(" ", "-"))
        target, constraints = build(base, spelling)
        override = override(base, target) if override else {}
        if mutate:
            mutate(base, target)
        rc, out = run(target, constraints, imports(target, **override))
        expect(label + " (exit)", rc, want_rc)
        expect(label + " (last line)", out.strip().splitlines()[-1] if out.strip() else "", want_last)
        if want_rc == 0 and "NOTE import typing_extensions - typing_extensions.py pinned" not in out:
            problems.append(label + ": no NOTE line for typing_extensions with no version")
    go("pinned copies", 0, "ALL PINNED")
    go("a pin spelled with a leading zero", 0, "ALL PINNED", spelling={"certifi": "2026.010.23"},
       override=lambda base, target: {"certifi": ("2026.010.23", os.path.join(target, "certifi/__init__.py"))})
    go("version only", 1, "STALE urllib3", override=lambda base, target: {"urllib3": ("2.6.3", os.path.join(target, "urllib3/__init__.py"))})
    go("stale code", 1, "STALE requests", mutate=lambda base, target: put(os.path.join(target, "requests/__init__.py"), "# an older requests\n"))
    def outside(base, target):
        put(os.path.join(base, "elsewhere", "certifi.py"), "# certifi 2026.10.23\n")
        return {"certifi": ("2026.10.23", os.path.join(base, "elsewhere", "certifi.py"))}
    go("outside the folder", 1, "STALE certifi", override=outside)
    go("not imported", 1, "STALE idna", override=lambda base, target: {"idna": ("", "")})
    def no_pinned(base, target):
        shutil.rmtree(os.path.join(target, "idna-3.15.dist-info"))
        put(os.path.join(target, "idna-3.0.dist-info", "RECORD"), "idna/__init__.py,sha256=x,1\n")
    go("no pinned dist-info", 1, "STALE idna", mutate=no_pinned)
    go("two stale copies", 1, "STALE charset_normalizer,urllib3", override=lambda base, target: {
        "charset_normalizer": ("3.0.0", os.path.join(target, "charset_normalizer/__init__.py")),
        "urllib3": ("2.6.3", os.path.join(target, "urllib3/__init__.py"))})

elif mode == "moves":
    def state(rows):
        return "".join(row + "\n" for row in rows)
    before = ["D certifi-2025.1.31.dist-info aaaa", "D requests-2.31.0.dist-info bbbb", "D oras-0.2.25.dist-info cccc",
              "D attrs-24.1.dist-info dddd", "T certifi", "T requests", "T oras", "T attrs", "T bin"]
    after = ["D certifi-2026.10.23.dist-info a2", "D requests-2.34.2.dist-info b2", "D oras-0.2.25.dist-info cccc",
             "D attrs-24.1.dist-info dddd", "D fastembed-0.8.0.dist-info f1", "T certifi", "T requests", "T oras", "T attrs", "T bin", "T fastembed"]
    imp_before = "CHK|imp|oras.provider|1\nCHK|imp|attrs|1\nCHK|imp|rpds|0\n"
    def go(label, want_rc, want_text, after_rows=after, imp_after=imp_before, imp_first=imp_before):
        base = case_dir(label.replace(" ", "-"))
        put(os.path.join(base, "constraints.txt"), "certifi==2026.10.23\nrequests==2.34.2\nfastembed==0.8.0\n")
        put(os.path.join(base, "before.state"), state(before))
        put(os.path.join(base, "after.state"), state(after_rows))
        put(os.path.join(base, "imports-before.txt"), imp_first)
        rc, out = run(os.path.join(base, "constraints.txt"), os.path.join(base, "before.state"), os.path.join(base, "after.state"),
                      os.path.join(base, "imports-before.txt"), imp_after)
        expect(label + " (exit)", rc, want_rc)
        if want_text not in out:
            problems.append("%s: %r is not in %r" % (label, want_text, out))
        if want_rc == 0 and "PROBLEM" in out:
            problems.append("%s: a problem was reported: %r" % (label, out))
    go("the six move and a pin is added", 0, "2 moved to the pins")
    go("a stale dist-info stays", 1, "PROBLEM certifi-2025.1.31.dist-info is still in the folder", after + ["D certifi-2025.1.31.dist-info aaaa"])
    go("a pin is missing", 1, "PROBLEM requests 2.34.2 is not in the folder", [r for r in after if "requests-2.34.2" not in r])
    go("another distribution changed", 1, "PROBLEM oras-0.2.25.dist-info changed", [r.replace("cccc", "c3") for r in after])
    go("another distribution is gone", 1, "PROBLEM attrs-24.1.dist-info is gone", [r for r in after if "D attrs" not in r])
    go("a distribution that is no pin is added", 1, "PROBLEM rogue-1.0.dist-info was added and is no pin", after + ["D rogue-1.0.dist-info r1"])
    go("a top-level item is gone", 1, "PROBLEM top-level item bin is gone", [r for r in after if r != "T bin"])
    go("an IPM module no longer imports", 1, "PROBLEM oras.provider imported before the install and does not now",
       imp_after="CHK|imp|oras.provider|0\nCHK|imp|attrs|1\n")
    go("the import record is empty", 1, "PROBLEM the import record of IPM's packages is empty", imp_first="", imp_after="")
    go("the import record lists other modules after", 1, "PROBLEM the import record of IPM's packages is empty or not the same list",
       imp_after="CHK|imp|oras.provider|1\nCHK|imp|attrs|1\n")

elif mode == "uninstall":
    def state(rows):
        return "".join(row + "\n" for row in rows)
    after = ["D certifi-2026.10.23.dist-info a2", "D oras-0.2.25.dist-info cccc", "D fastembed-0.8.0.dist-info f1",
             "T certifi", "T oras", "T fastembed", "T ocutalon_extract.py", "T ocutalon_memory.py"]
    kept = [row for row in after if not row.endswith(".py")]
    imp = "CHK|imp|oras.provider|1\nCHK|imp|certifi|1\n"
    def go(label, want_rc, want_text, gone_rows=kept, imp_first=imp, imp_now=imp):
        base = case_dir("uninstall-" + label.replace(" ", "-"))
        put(os.path.join(base, "after.state"), state(after))
        put(os.path.join(base, "gone.state"), state(gone_rows))
        put(os.path.join(base, "imports-before.txt"), imp_first)
        rc, out = run(os.path.join(base, "after.state"), os.path.join(base, "gone.state"), os.path.join(base, "imports-before.txt"), imp_now)
        expect(label + " (exit)", rc, want_rc)
        if want_text not in out:
            problems.append("%s: %r is not in %r" % (label, want_text, out))
        if want_rc == 0 and "PROBLEM" in out:
            problems.append("%s: a problem was reported: %r" % (label, out))
    go("the uninstall keeps all but the two resources", 0, "NOTE after the uninstall: 3 distributions (3 after the install)")
    go("a distribution is gone", 1, "PROBLEM certifi-2026.10.23.dist-info is gone", [row for row in kept if "D certifi" not in row])
    go("a distribution changed", 1, "PROBLEM oras-0.2.25.dist-info changed", [row.replace("cccc", "c3") for row in kept])
    go("a distribution was added", 1, "PROBLEM rogue-1.0.dist-info was added", kept + ["D rogue-1.0.dist-info r1"])
    go("a top-level item is gone", 1, "PROBLEM top-level item certifi is gone", [row for row in kept if row != "T certifi"])
    go("a top-level item was added", 1, "PROBLEM top-level item rogue was added", kept + ["T rogue"])
    go("an IPM module no longer imports", 1, "PROBLEM oras.provider imported before the install and does not now",
       imp_now="CHK|imp|oras.provider|0\nCHK|imp|certifi|1\n")
    go("the import record is empty", 1, "PROBLEM the import record of IPM's packages is empty", imp_first="", imp_now="")

elif mode == "state":
    base = case_dir("state")
    target, out_file = os.path.join(base, "python"), os.path.join(base, "out.state")
    put(os.path.join(target, "certifi-2026.10.23.dist-info", "RECORD"), "certifi/__init__.py,,\n")
    os.makedirs(os.path.join(target, "oras-0.2.25.dist-info"))
    put(os.path.join(target, "certifi", "__init__.py"), "x")
    put(os.path.join(target, "bin", "normalizer"), "x")
    put(os.path.join(target, "rpds.py"), "x")
    rc, out = run(target, out_file)
    expect("exit", rc, 0)
    digest = hashlib.md5(b"certifi/__init__.py,,\n").hexdigest()
    got = open(out_file).read().splitlines() if os.path.exists(out_file) else []
    expect("state lines", got, ["T bin", "T certifi", "D certifi-2026.10.23.dist-info " + digest, "D oras-0.2.25.dist-info -", "T rpds.py"])

elif mode == "skip":
    base = case_dir("skip")
    target, scratch = os.path.join(base, "python"), os.path.join(base, "scratch")
    for entry in ["certifi-2025.1.31.dist-info", "certifi-2026.10.23.dist-info", "oras-0.2.25.dist-info", "fastembed-0.8.0.dist-info"]:
        os.makedirs(os.path.join(target, entry))
    put(os.path.join(target, "bin", "normalizer"), "x")
    put(os.path.join(base, "before.txt"), "certifi-2025.1.31.dist-info\noras-0.2.25.dist-info\n")
    put(os.path.join(base, "constraints.txt"), "certifi==2026.10.23\nfastembed==0.8.0\n")
    rc, out = run(target, os.path.join(base, "before.txt"), os.path.join(base, "constraints.txt"), scratch)
    expect("exit", rc, 0)
    expect("gated", sorted(os.listdir(scratch)), ["certifi-2025.1.31.dist-info", "certifi-2026.10.23.dist-info", "fastembed-0.8.0.dist-info"])
    if "oras-0.2.25 was in the folder before the install and is no pin: not gated" not in out:
        problems.append("the unpinned name is not skipped with its NOTE: %r" % out)
    if "NOTE 3 distributions gated" not in out:
        problems.append("the count of gated distributions is not 3: %r" % out)

for problem in problems:
    print("PROBLEM " + problem)
sys.exit(1 if problems else 0)
EOD
ipm_python_ok() { # ipm_python_ok <mode> <function>
  local code
  code="$tmp/ipm-$1.py"
  heredoc_of "$2" 1 > "$code"
  [ -s "$code" ] && python3 "$tmp/ipm-driver.py" "$1" "$code" "$tmp/ipm-work" > "$tmp/ipm-$1.out" 2>&1
}

# 19. The wiring of the import check (Story 19.8, QA): it runs where check 32 runs, and the checks it names are the ones that exist.
follows() { # follows <file> <first line> <second line>: the second line comes right after the first one (indentation ignored), once or more
  awk -v a="$2" -v b="$3" '{ line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    prev == a && line == b { found++ } { prev = line } END { exit found >= 1 ? 0 : 1 }' "$1"
}
function_body_has() { # function_body_has <file> <function> <line>...: the function holds every line (indentation ignored)
  local file=$1 fn=$2 want
  shift 2
  awk -v fn="$fn" 'index($0, fn "() {") == 1 { infn = 1; next } infn && /^}/ { infn = 0 } infn { sub(/^[ \t]+/, ""); print }' "$file" > "$tmp/fn-body"
  for want in "$@"; do grep -qxF -- "$want" "$tmp/fn-body" || return 1; done
}
pins_wired() { # pins_wired <script>
  follows "$1" 'check_licences "install checks"' 'check_python_pins "install checks"' \
    && follows "$1" 'check_start_by_step' 'check_reinstall' \
    && follows "$1" 'check_licences "part p"' 'check_python_pins "part p"' \
    && follows "$1" 'uninstall_checks "$h0" "$h1" "$h2"' 'check_uninstall_python "part p uninstall"' \
    && function_body_has "$1" check_python_pins 'check_imports "$1"' 'check_python_moves "$1"' 'check_ipm_alive "$1" ocutalon' 'check_invoke_args "$1"' \
    && function_body_has "$1" check_reinstall 'snapshot_python_before' 'check_python_pins "reinstall"' 'check_licences "reinstall"' \
    && function_body_has "$1" check_uninstall_python 'check_imports "$label"' 'check_ipm_alive "$label" .' \
    && follows "$1" 'check_uninstall_python "part p uninstall"' "run p-again USER 'zpm \"install ocutalon\"'" \
    && follows "$1" "run p-again USER 'zpm \"install ocutalon\"'" \
      'stops_with_next_command p-again "part p, the install command in USER after the uninstall (from the local repository)"'
}
good="$tmp/script.good"
cat > "$good" << 'EOS'
check_python_pins() {
  check_imports "$1"
  check_python_moves "$1"
  check_ipm_alive "$1" ocutalon
  check_invoke_args "$1"
}
check_reinstall() {
  snapshot_python_before
  check_python_pins "reinstall"
  check_licences "reinstall"
}
check_uninstall_python() {
  check_imports "$label"
  check_ipm_alive "$label" .
}
part_p() {
  check_licences "part p"
  check_python_pins "part p"
  uninstall_checks "$h0" "$h1" "$h2"
  check_uninstall_python "part p uninstall"
  run p-again USER 'zpm "install ocutalon"'
  stops_with_next_command p-again "part p, the install command in USER after the uninstall (from the local repository)"
}
    check_licences "install checks"
    check_python_pins "install checks"
    check_start_by_step
    check_reinstall
EOS
grep -v 'check_python_pins "install checks"' "$good" > "$tmp/script.no-a"
grep -v 'check_python_pins "part p"' "$good" > "$tmp/script.no-p"
grep -v '^    check_reinstall$' "$good" > "$tmp/script.no-reinstall"
grep -v 'check_uninstall_python "part p uninstall"' "$good" > "$tmp/script.no-uninstall"
grep -v 'check_python_moves "$1"' "$good" > "$tmp/script.no-moves"
grep -v 'check_invoke_args "$1"' "$good" > "$tmp/script.no-args"
grep -v 'run p-again' "$good" > "$tmp/script.no-again"
grep -v 'stops_with_next_command p-again' "$good" > "$tmp/script.no-again-stop"
if pins_wired "$good" && ! pins_wired "$tmp/script.no-a" && ! pins_wired "$tmp/script.no-p" && ! pins_wired "$tmp/script.no-reinstall" \
  && ! pins_wired "$tmp/script.no-uninstall" && ! pins_wired "$tmp/script.no-moves" && ! pins_wired "$tmp/script.no-args" \
  && ! pins_wired "$tmp/script.no-again" && ! pins_wired "$tmp/script.no-again-stop"; then
  pass "rule 19 on samples: the wiring passes; a missing call on path A or part p, the reinstall, the uninstall check, the folder comparison, the Invoke arguments or part p's install from the local repository after the uninstall fails"
else
  fail "rule 19 on samples: the checker accepts a script without the import check at both places of check 32, or rejects the right one"
fi

# 14. The repository definitions stay private (Story 15.4, QA; U-232 condition 1 and the Boundaries): release/ipm-install.sh adds its
# repository in a session whose output is discarded, never lists repositories, keeps each hash of USER's definitions in a variable and never
# prints it; and uninstall_checks passes only when the hash after the uninstall equals the hash before it and the one before the first
# command, with at least one node, and prints neither.
defs_private() {
  awk '
    { line = $0; sub(/^[ \t]+/, "", line) }
    line ~ /^#/ { next }
    line ~ /zpm "repo / && line ~ /-list/ { bad = 1 }
    line ~ /zpm "repo / { adds++; if (line !~ /> \/dev\/null 2>&1$/) bad = 1 }
    line ~ /defs_hash/ && line !~ /^defs_hash\(\) \{/ { if (line ~ /^h[012]=\$\(defs_hash\)$/) keeps++; else bad = 1 }
    line ~ /^(part_p|uninstall_checks)\(\) \{/ { fn = 1 }
    fn && line ~ /(echo|printf|cat|tee|pass|fail|die)/ && line ~ /\$\{?(h[012]|[123])([^0-9A-Za-z_]|$)/ { bad = 1 }
    line ~ /^\}/ { fn = 0 }
    END { exit (adds >= 1 && keeps >= 3 && !bad) ? 0 : 1 }' "$1"
}
cat > "$tmp/defs.good" <<'EOM'
part_p() {
  echo "PART p: ocutalon-$ver.tgz from a local IPM repository on a fresh instance"
  printf '%s\nHalt\n' 'zpm "repo -name ocutalon-local -fs -depth 2 -path /tmp/ocutalon-repo/"' | dc exec -T iris iris session IRIS -U USER > /dev/null 2>&1
  h0=$(defs_hash)
  h1=$(defs_hash)
  h2=$(defs_hash)
  uninstall_checks "$h0" "$h1" "$h2"
}
uninstall_checks() {
  local n=${3%%|*}
  if [ "$n" -gt 0 ] 2> /dev/null && [ "$2" = "$3" ] && [ "$1" = "$3" ]; then
    pass "same|$n"
  else
    echo "  definitions: differs|${n:-0}"
  fi
}
EOM
sed 's/-name ocutalon-local -fs/-name ocutalon-local -list/' "$tmp/defs.good" > "$tmp/defs.list"
sed 's/ > \/dev\/null 2>&1$//' "$tmp/defs.good" > "$tmp/defs.shown"
sed 's/^  h1=\$(defs_hash)$/  defs_hash/' "$tmp/defs.good" > "$tmp/defs.bare"
sed 's/^  h1=\$(defs_hash)$/  h1=$(defs_hash); echo "$h1"/' "$tmp/defs.good" > "$tmp/defs.echo-var"
sed 's/echo "  definitions: differs|${n:-0}"/echo "  definitions: differs|${n:-0} $2"/' "$tmp/defs.good" > "$tmp/defs.echo-arg"
sed 's/pass "same|$n"/pass "same|$n $3"/' "$tmp/defs.good" > "$tmp/defs.pass-arg"
sed '/zpm "repo /d' "$tmp/defs.good" > "$tmp/defs.no-add"
if defs_private "$tmp/defs.good" && ! defs_private "$tmp/defs.list" && ! defs_private "$tmp/defs.shown" && ! defs_private "$tmp/defs.bare" \
  && ! defs_private "$tmp/defs.echo-var" && ! defs_private "$tmp/defs.echo-arg" && ! defs_private "$tmp/defs.pass-arg" && ! defs_private "$tmp/defs.no-add"; then
  pass "rule 14 on samples: discarded add and hashes kept in variables pass; a repo -list, an add whose output is shown, a bare defs_hash, a hash echoed or passed to pass from a variable or an argument, or no add fails"
else
  fail "rule 14 on samples: the checker accepts a script that prints repository definitions, or rejects the right one"
fi

# uninstall_checks_run <hash before the first command> <hash before the uninstall> <hash after it> [snapshot flaw]: the real function of
# release/ipm-install.sh on a synthetic uninstall; prints its pass and fail lines.
sed -n '/^uninstall_checks() {$/,/^}$/p' release/ipm-install.sh > "$tmp/uninstall.fn"
uninstall_checks_run() {
  (
    tmp=$tmp/un
    rm -rf "$tmp"
    mkdir -p "$tmp"
    pass() { echo "PASS $*"; }
    fail() { echo "FAIL $*"; }
    printf 'Uninstall done.\n' > "$tmp/p-uninstall.txt"
    for g in D I S; do echo "CHK|omap-MapGlobals|IPM.Repo.Definition$g|USER_DATA"; done > "$tmp/repo.lines"
    { echo 'CHK|service|%Service_Telnet|1|32'; cat "$tmp/repo.lines"; } > "$tmp/p-second.snap"
    echo 'CHK|service|%Service_Telnet|1|32' > "$tmp/p-uninstall.snap"
    case ${4:-} in
      kept-mapping) cat "$tmp/repo.lines" >> "$tmp/p-uninstall.snap" ;;
      other-change) echo 'CHK|service|%Service_Other|1|32' >> "$tmp/p-uninstall.snap" ;;
      failure-line) echo 'FAILURE: Unconfigure' >> "$tmp/p-uninstall.txt" ;;
    esac
    . "$tmp/../uninstall.fn"
    uninstall_checks "$1" "$2" "$3"
  )
}
same="3|SENTINELAAA"
uc_run_ok="$(uninstall_checks_run "$same" "$same" "$same" 2>&1)"
# uc_expect_fail <needle> <hash0> <hash1> <hash2> [flaw]: a FAIL line, the needle, and no hash in the output
uc_expect_fail() {
  local o
  o=$(uninstall_checks_run "$2" "$3" "$4" "${5:-}" 2>&1)
  case $o in *FAIL*) ;; *) return 1 ;; esac
  case $o in *"$1"*) ;; *) return 1 ;; esac
  case $o in *SENTINEL*) return 1 ;; esac
  return 0
}
if [ "$(printf '%s\n' "$uc_run_ok" | grep -c '^PASS')" = 3 ] && ! printf '%s\n' "$uc_run_ok" | grep -q -e '^FAIL' -e SENTINEL \
  && printf '%s\n' "$uc_run_ok" | grep -q 'same|3$' \
  && uc_expect_fail "differs|3 (after the uninstall, against before it)" "$same" "$same" "3|SENTINELBBB" \
  && uc_expect_fail "differs|3 (after the uninstall, against before it)" "$same" "3|SENTINELBBB" "$same" \
  && uc_expect_fail "differs|3 (after the uninstall, against before the first command)" "3|SENTINELCCC" "$same" "$same" \
  && uc_expect_fail "0 nodes" "0|SENTINELAAA" "0|SENTINELAAA" "0|SENTINELAAA" \
  && uc_expect_fail "0 nodes" "" "" "" \
  && uc_expect_fail "changed more than" "$same" "$same" "$same" kept-mapping \
  && uc_expect_fail "changed more than" "$same" "$same" "$same" other-change \
  && uc_expect_fail "FAILURE" "$same" "$same" "$same" failure-line; then
  pass "rule 14 on the real function: equal hashes with nodes pass and print same|<nodes>; a hash that changed at the uninstall or since the first command, no nodes, no hash, a kept mapping, another change or a FAILURE line fails, and no hash is printed"
else
  fail "rule 14 on the real function: uninstall_checks passes definitions that changed, accepts 0 nodes, misses a kept mapping, or prints a hash"
fi

# 15. The Data bullet of docs/security-overview.md (Story 15.4, U-232 condition 3, a ruled sentence outside the generated markers): the
# overview says that an IPM install maps the repository definitions, from which namespace, and that uninstalling removes only that mapping.
OVERVIEW_BULLET='- On an IPM install, OCUTALON also maps IPM'"'"'s repository definitions (the globals `^IPM.Repo.Definition*`) from the namespace where the first install command ran, as they are, so the two namespaces share one list of repositories; uninstalling OcuTalon removes only that mapping.'
overview_bullet_ok() { grep -F -x -q -e "$OVERVIEW_BULLET" "$1"; }
printf '## Data\n\n%s\n\nData leaves the instance only:\n' "$OVERVIEW_BULLET" > "$tmp/overview.good"
grep -v 'IPM.Repo.Definition' "$tmp/overview.good" > "$tmp/overview.none"
sed 's/removes only that mapping/removes the mapping/' "$tmp/overview.good" > "$tmp/overview.altered"
if overview_bullet_ok "$tmp/overview.good" && ! overview_bullet_ok "$tmp/overview.none" && ! overview_bullet_ok "$tmp/overview.altered"; then
  pass "rule 15 on samples: the overview with the ruled bullet passes; without it or with its last clause changed fails"
else
  fail "rule 15 on samples: the checker accepts an overview without the ruled bullet, or rejects the right one"
fi

# 16. The job's run includes part p (Story 15.4, AC 5): release/ipm-install.sh runs part_p when the mode is all.
part_p_in_job() { grep -qxF 'if [ "$mode" = all ]; then part_p; fi' "$1"; }
printf 'finish() { :; }\nif [ "$mode" = all ]; then part_p; fi\nfinish\n' > "$tmp/job.part-p"
sed 's/= all ]/= p ]/' "$tmp/job.part-p" > "$tmp/job.other-mode"
grep -v part_p "$tmp/job.part-p" > "$tmp/job.no-part-p"
if part_p_in_job "$tmp/job.part-p" && ! part_p_in_job "$tmp/job.other-mode" && ! part_p_in_job "$tmp/job.no-part-p"; then
  pass "rule 16 on samples: part_p run in mode all passes; another mode or no part_p call fails"
else
  fail "rule 16 on samples: the checker accepts a script whose no-argument run skips part p, or rejects the right one"
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
check "rule 9: $install_doc keeps its points and agrees with the stop sentence of Install.Ipm, the failure line and the order of Registry" install_doc_ok "$install_doc" "$stop_text" "$fail_tail" "$order_text"
check "rule 10: $manifest declares the exact SystemRequirements element once" sysreq_declared "$manifest"
check "rule 11: $install_doc starts in USER, quotes IPM's refusal exactly as release/ipm-install.sh asserts it and sends the reader back to USER" ns_doc_ok "$install_doc" "$script_refusal"
check "rule 12: $install_doc opens with the registry install: enable -community before the first install command, the shared-repositories sentence, and no Node.js before the developers' section" registry_doc_ok "$install_doc"
check "rule 13: $manifest invokes OcuTalon.Install.Ipm UnmapRepos once, at Unconfigure, Before, after the Configure Invoke" unmap_declared "$manifest"
check "rule 17: $manifest and module.xml invoke OcuTalon.Install.Ipm RemoveStaleCopies once, at Reload, Before, after MapAndStop, with the Default BypassPyDeps" stale_step_declared_both
check "rule 18: check_imports passes the pinned copies of the six and fails a version-only difference, stale code, a file outside the folder, a module not imported and a missing pinned dist-info" ipm_python_ok imports check_imports
check "rule 18: check_python_moves accepts only the six moving to the pins and the pins added, and fails a stale dist-info that stays, a missing pin, a changed, missing or unpinned distribution, a lost top-level item and an IPM module that no longer imports or an empty import record" ipm_python_ok moves check_python_moves
check "rule 18: check_uninstall_python accepts only the two Python resources gone, and fails a distribution gone, changed or added, a top-level item gone or added, an IPM module that no longer imports and an empty import record" ipm_python_ok uninstall check_uninstall_python
check "rule 18: python_state writes a D line with the RECORD's md5 (or - with no RECORD) for each dist-info and a T line for each other top-level item, in name order" ipm_python_ok state python_state
check "rule 18: check_licences gates an older copy of a pinned name that was in the folder before the install and skips a name that is no pin" ipm_python_ok skip check_licences
check "rule 19: release/ipm-install.sh runs check_python_pins after check_licences on path A and on part p, then the reinstall and the uninstall checks" pins_wired release/ipm-install.sh
check "rule 14: release/ipm-install.sh adds its repository with the output discarded, never lists repositories and never prints a hash of the definitions" defs_private release/ipm-install.sh
check "rule 15: docs/security-overview.md carries the ruled Data bullet on the repository mapping" overview_bullet_ok docs/security-overview.md
check "rule 16: release/ipm-install.sh with no argument, the job's run, runs part p" part_p_in_job release/ipm-install.sh

if [ "$fails" -ne 0 ]; then
  echo "test-cpf: $fails check(s) failed"
  exit 1
fi
echo "test-cpf: all checks passed"
