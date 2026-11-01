# Helpers shared by the static scanners (test-boundaries.sh, test-class-rules.sh, test-install-start.sh row 5), by the two
# Storage block checks (test-storage.sh, test-storage-roundtrip.sh) and by the release checklist (release/checklist.sh, Story 11.4,
# which scans the draft notes with local_path).
# Sourced, not run: it defines functions and one variable, STORAGE_BLOCKS_AWK, and nothing else. The caller keeps the counter `fails`.
#
# A scanner prints file:line for each offending line of the files it is given, and never the text of the line.
# scan_rule first runs a scanner on a sample that breaks the rule and on one that keeps it, so that a scanner that can no
# longer flag anything fails, and only then on the real files.

# scan_files <pathspec>...: the files that git tracks, or has not ignored, below the pathspecs (the whole repository when
# none is given), one per line. A file named .env or .env.<x> other than .env.example is never listed, whatever git says.
scan_files() {
  git -c core.quotePath=false ls-files -co --exclude-standard -- "$@" | sort -u | while IFS= read -r f; do
    [ -f "$f" ] || continue
    case ${f##*/} in
      .env.example) ;;
      .env | .env.*) continue ;;
    esac
    printf '%s\n' "$f"
  done
}

# scan_rule <label> <scanner> <bad sample file> <good sample file> <files, one per line>: prints PASS or FAIL for the label.
scan_rule() {
  local label=$1 scanner=$2 bad=$3 good=$4 list=$5 hits
  if [ -z "$("$scanner" "$bad")" ]; then
    echo "FAIL $label: the scanner does not flag a line that breaks the rule"
    fails=$((fails + 1))
    return
  fi
  if [ -n "$("$scanner" "$good")" ]; then
    echo "FAIL $label: the scanner flags a line that keeps the rule"
    fails=$((fails + 1))
    return
  fi
  if [ -z "$list" ]; then
    echo "FAIL $label: no file to scan"
    fails=$((fails + 1))
    return
  fi
  # The list is split at newlines only, with no pattern expansion, so a file name with a space or a glob character is one file.
  hits=$(
    IFS='
'
    set -f
    "$scanner" $list
  )
  if [ -n "$hits" ]; then
    echo "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL $label"
    fails=$((fails + 1))
  else
    echo "PASS $label"
  fi
}

# local_path <file>...: file:line of each line that holds a local machine path (CON-5): a home or volume folder with a name below it,
# a /private/tmp, /private/var or /private/etc path, a macOS per-user temporary folder (/var/folders/<x>), a Windows user folder with
# a name below it, or a Linux home folder other than the image's /home/irisowner. The patterns are written so that they cannot match
# this file.
local_path() {
  { grep -nHIE '/Use[r]s/[A-Za-z0-9]|/Volume[s]/[A-Za-z0-9]|/privat[e]/(tmp|var|etc)/|(^|[^A-Za-z0-9_.])/va[r]/folders/[A-Za-z0-9_]|[A-Za-z]:\\Use[r]s\\[A-Za-z0-9]' "$@"
    grep -nHIE '/hom[e]/[A-Za-z]' "$@" | grep -v '/home/irisowner'
  } | cut -d: -f1,2
}

# bridge_refs <file>...: file:line of each code line that names an OcuTalon package other than OcuTalon.Bridge and
# OcuTalon.BridgeExample, as a class name (OcuTalon.Pkg) or as a table name (OcuTalon_Pkg). A comment line (//, ///, ; and #;)
# is not code. The compiler accepts a call to a class it cannot find, so loading the bridge alone cannot see such a reference;
# this does.
bridge_refs() {
  awk '!/^[[:space:]]*(\/\/|;|#;|##;)/ {
    s = $0
    while (match(s, /OcuTalon[._][A-Za-z]+/)) {
      w = substr(s, RSTART, RLENGTH)
      if (w != "OcuTalon.Bridge" && w != "OcuTalon.BridgeExample" && w != "OcuTalon_Bridge" && w != "OcuTalon_BridgeExample") print FILENAME ":" FNR
      s = substr(s, RSTART + RLENGTH)
    }
  }' "$@"
}

# bridge_ref_samples <dir>: writes the samples of bridge_refs into the folder: Bad.cls names another package twice, once as a class
# and once as a table; Ok.cls names only the bridge's own packages, and another package only in comments.
bridge_ref_samples() {
  mkdir -p "$1"
  cat > "$1/Bad.cls" <<'EOS'
Class OcuTalon.Bridge.ZzBad
{
ClassMethod A()
{
	Do ##class(OcuTalon.Core.BridgeSink).OnEvent()
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT 1 FROM OcuTalon_Data.Session")
}
}
EOS
  cat > "$1/Ok.cls" <<'EOS'
/// Names OcuTalon.Core.BridgeSink in a comment only.
Class OcuTalon.Bridge.ZzOk
{
Parameter P = "OcuTalon_Bridge_Data.Decision";
Parameter Q = "OcuTalon.BridgeExample.Host";
ClassMethod A()
{
	; OcuTalon.Core.BridgeSink in a comment
	#; OcuTalon_Data.Session in a comment
	Quit 1
}
}
EOS
}

# The awk program of a class file's Storage blocks: from a line that starts a block to its closing brace, in order. test-storage.sh
# runs it on the host and test-storage-roundtrip.sh in the container, so both read the same lines as the block.
STORAGE_BLOCKS_AWK='/^Storage / { p = 1 }
p { print }
p && /^\}/ { p = 0 }'
