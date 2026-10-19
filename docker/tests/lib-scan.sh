# Helpers shared by the static scanners (test-boundaries.sh, test-class-rules.sh, test-install-start.sh row 5).
# Sourced, not run: it defines functions and nothing else. The caller keeps the counter `fails`.
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
  hits=$("$scanner" $list)
  if [ -n "$hits" ]; then
    echo "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL $label"
    fails=$((fails + 1))
  else
    echo "PASS $label"
  fi
}

# bridge_refs <file>...: file:line of each code line that names an OcuTalon package other than OcuTalon.Bridge and
# OcuTalon.BridgeExample, as a class name (OcuTalon.Pkg) or as a table name (OcuTalon_Pkg). A comment line is not code.
# The compiler accepts a call to a class it cannot find, so loading the bridge alone cannot see such a reference; this does.
bridge_refs() {
  awk '!/^[[:space:]]*\/\// {
    s = $0
    while (match(s, /OcuTalon[._][A-Za-z]+/)) {
      w = substr(s, RSTART, RLENGTH)
      if (w != "OcuTalon.Bridge" && w != "OcuTalon.BridgeExample" && w != "OcuTalon_Bridge" && w != "OcuTalon_BridgeExample") print FILENAME ":" FNR
      s = substr(s, RSTART + RLENGTH)
    }
  }' "$@"
}
