#!/usr/bin/env bash
# Checks the short-name registry and the storage blocks of src/ (AD-3, AD-5; Story 0.4, matrix row 5):
#   - registry-duplicate: no two rows of src/short-names.tsv share a short name, a global or a class;
#   - registry-class: the class of every row sets Parameter DEFAULTGLOBAL to the row's global;
#   - registry-row: every class that sets Parameter DEFAULTGLOBAL has a row;
#   - registry-param: every storage-bearing class that is not a message sets Parameter DEFAULTGLOBAL;
#   - scan: the scan of the real tree reads src/short-names.tsv and at least one class, and ends without an error;
#   - prefix: a global starts with ^OcuTalonP., or with ^OcuTalonBP. under src/bridge/ and nowhere else;
#   - storage: a storage-bearing class has a Storage Default block. A class is storage-bearing when it is not abstract
#     and its Extends chain, followed through src/, reaches %Persistent, %Library.Persistent, Ens.Request or
#     Ens.Response. An abstract class carries whatever block the compiler gave it;
#   - datalocation: the DataLocation of a class with a default global is that global plus D;
#   - locations: its IdLocation, IndexLocation and StreamLocation are that global plus D, I and S, so that every global of
#     the class stays under the private prefix (AD-3).
# Starts nothing: the checks read the files only. Each rule first runs on synthetic trees in a temporary folder, one that
# keeps every rule and one that breaks only this rule, so a rule that can no longer flag anything fails.
# A failing check prints file:line and the rule; the tree's own text is not printed.
# Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-st.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- the checker: prints rule<TAB>file[:line]<TAB>detail for each violation in <dir>/src ---

cat > "$tmp/check.awk" <<'EOA'
function bears(c, depth,    n, i, parts, p) {
  if (depth > 20 || !(c in ext)) return 0
  n = split(ext[c], parts, ",")
  for (i = 1; i <= n; i++) {
    p = parts[i]
    if (p in roots) return 1
    if (bears(p, depth + 1)) return 1
  }
  return 0
}
function message(c, depth,    n, i, parts, p) {
  if (depth > 20 || !(c in ext)) return 0
  n = split(ext[c], parts, ",")
  for (i = 1; i <= n; i++) {
    p = parts[i]
    if (p == "Ens.Request" || p == "Ens.Response") return 1
    if (message(p, depth + 1)) return 1
  }
  return 0
}
function report(rule, where, detail) { printf "%s\t%s\t%s\n", rule, where, detail }
BEGIN {
  FS = "\t"
  roots["%Persistent"] = 1; roots["%Library.Persistent"] = 1; roots["Ens.Request"] = 1; roots["Ens.Response"] = 1
}
FILENAME ~ /short-names\.tsv$/ {
  if (FNR == 1 || $0 == "") next
  rows++
  rshort[rows] = $1; rglobal[rows] = $2; rclass[rows] = $3; rline[rows] = FILENAME ":" FNR
  if ($1 in seenShort) report("registry-duplicate", rline[rows], "short name " $1 " is already in line " seenShort[$1])
  if ($2 in seenGlobal) report("registry-duplicate", rline[rows], "global " $2 " is already in line " seenGlobal[$2])
  if ($3 in seenClass) report("registry-duplicate", rline[rows], "class " $3 " is already in line " seenClass[$3])
  seenShort[$1] = FNR; seenGlobal[$2] = FNR; seenClass[$3] = FNR
  rowOfClass[$3] = 1
  next
}
FNR == 1 { inheader = 0; instorage = 0; cname = ""; header = "" }
inheader {
  if ($0 ~ /^\{/) {
    inheader = 0
    split(header, words, " ")
    cname = words[2]
    file[cname] = FILENAME
    ext[cname] = ""
    if (match(header, /Extends[ \t]+(\([^)]*\)|[A-Za-z0-9_.%]+)/)) {
      s = substr(header, RSTART, RLENGTH)
      sub(/^Extends[ \t]+/, "", s)
      gsub(/[() \t]/, "", s)
      ext[cname] = s
    }
    abs[cname] = (header ~ /\[[^]]*Abstract/) ? 1 : 0
  } else {
    header = header " " $0
  }
  next
}
/^Class / { inheader = 1; header = $0; next }
cname != "" && /^Parameter DEFAULTGLOBAL[ \t]*=/ {
  s = $0
  hasdg[cname] = 1
  if (match(s, /"[^"]*"/)) dg[cname] = substr(s, RSTART + 1, RLENGTH - 2)
  dgline[cname] = FILENAME ":" FNR
  next
}
cname != "" && /^Storage Default/ { st[cname] = 1; instorage = 1; next }
instorage && /<DataLocation>/ {
  s = $0
  sub(/.*<DataLocation>/, "", s)
  sub(/<\/DataLocation>.*/, "", s)
  dl[cname] = s
  next
}
instorage && /<IdLocation>/ {
  s = $0
  sub(/.*<IdLocation>/, "", s)
  sub(/<\/IdLocation>.*/, "", s)
  idl[cname] = s
  next
}
instorage && /<IndexLocation>/ {
  s = $0
  sub(/.*<IndexLocation>/, "", s)
  sub(/<\/IndexLocation>.*/, "", s)
  il[cname] = s
  next
}
instorage && /<StreamLocation>/ {
  s = $0
  sub(/.*<StreamLocation>/, "", s)
  sub(/<\/StreamLocation>.*/, "", s)
  sl[cname] = s
  next
}
instorage && /^\}/ { instorage = 0 }
END {
  for (i = 1; i <= rows; i++) {
    c = rclass[i]
    if (!(c in file)) report("registry-class", rline[i], "class " c " of row " rshort[i] " has no file in src/")
    else if (!(c in hasdg) || dg[c] != rglobal[i]) report("registry-class", file[c], "class " c " does not set Parameter DEFAULTGLOBAL = \"" rglobal[i] "\"")
  }
  for (c in hasdg) {
    if (!(c in rowOfClass)) report("registry-row", dgline[c], "class " c " sets Parameter DEFAULTGLOBAL but has no row in src/short-names.tsv")
    want = (file[c] ~ /^src\/bridge\//) ? "^OcuTalonBP." : "^OcuTalonP."
    if (substr(dg[c], 1, length(want)) != want) report("prefix", dgline[c], "DEFAULTGLOBAL " dg[c] " of " c " must start with " want)
    if (c in st && dl[c] != dg[c] "D") report("datalocation", file[c], "DataLocation of " c " is not " dg[c] "D")
    if (c in st && idl[c] != dg[c] "D") report("locations", file[c], "IdLocation of " c " is not " dg[c] "D")
    if (c in st && il[c] != dg[c] "I") report("locations", file[c], "IndexLocation of " c " is not " dg[c] "I")
    if (c in st && sl[c] != dg[c] "S") report("locations", file[c], "StreamLocation of " c " is not " dg[c] "S")
    if (!(c in st)) report("datalocation", file[c], "class " c " has a default global and no Storage Default block")
  }
  for (c in file) {
    if (!abs[c] && bears(c, 0) && !(c in st)) report("storage", file[c], "storage-bearing class " c " has no Storage Default block")
    if (!abs[c] && bears(c, 0) && !message(c, 0) && !(c in hasdg)) report("registry-param", file[c], "storage-bearing class " c " does not set Parameter DEFAULTGLOBAL")
  }
  if (rows == 0) report("scan", "src/short-names.tsv", "the registry has no rows")
}
EOA

check_tree() { # check_tree <directory>: the violations of <directory>/src
  local list out
  list=$(cd "$1" && find src -name '*.cls' | sort)
  if [ -z "$list" ] || ! out=$(cd "$1" && printf '%s\n' "$list" | xargs awk -f "$tmp/check.awk" src/short-names.tsv 2>/dev/null); then
    printf 'scan\tsrc/short-names.tsv\tno class was read, or the scan of the tree failed\n'
    return
  fi
  printf '%s\n' "$out" | sort
}

# --- the synthetic trees ---

# make_tree <directory>: a tree that keeps every rule.
make_tree() {
  local d=$1 b=$1/src/bridge/cls/OcuTalon/Bridge/Data o=$1/src/ocutalon/cls/OcuTalon
  mkdir -p "$b" "$o/Data" "$o/Msg"
  printf 'short\tglobal\tclass\tlane\nAlpha\t^OcuTalonBP.Alpha\tOcuTalon.Bridge.Data.Alpha\tA\nBeta\t^OcuTalonP.Beta\tOcuTalon.Data.Beta\tB\n' > "$d/src/short-names.tsv"
  persistent_class OcuTalon.Bridge.Data.Alpha '^OcuTalonBP.Alpha' > "$b/Alpha.cls"
  persistent_class OcuTalon.Data.Beta '^OcuTalonP.Beta' > "$o/Data/Beta.cls"
  printf 'Class OcuTalon.Msg.Base Extends Ens.Request [ Abstract ]\n{\n\nProperty Text As %%String;\n\n}\n' > "$o/Msg/Base.cls"
  printf 'Class OcuTalon.Msg.Gamma Extends OcuTalon.Msg.Base\n{\n\nStorage Default\n{\n<Type>%%Storage.Persistent</Type>\n}\n\n}\n' > "$o/Msg/Gamma.cls"
  printf 'Class OcuTalon.Plain Extends (%%RegisteredObject, %%JSON.Adaptor)\n{\n\nProperty Text As %%String;\n\n}\n' > "$o/Plain.cls"
}

# persistent_class <class> <global>: the source of a persistent class with its default global and storage block.
persistent_class() {
  printf 'Class %s Extends %%Persistent\n{\n\nParameter DEFAULTGLOBAL = "%s";\n\nProperty Text As %%String;\n\nStorage Default\n{\n<Data name="XDefaultData">\n</Data>\n<DataLocation>%sD</DataLocation>\n<DefaultData>XDefaultData</DefaultData>\n<IdLocation>%sD</IdLocation>\n<IndexLocation>%sI</IndexLocation>\n<StreamLocation>%sS</StreamLocation>\n<Type>%%Storage.Persistent</Type>\n}\n\n}\n' "$1" "$2" "$2" "$2" "$2" "$2"
}

# bad_tree <name> <expected file> <edit command...>: a copy of the good tree that the command breaks; the command runs in
# the copy's directory. The expected file is the one that the rule must name.
bad_tree() {
  local name=$1 expect=$2
  shift 2
  cp -R "$tmp/good" "$tmp/$name"
  (cd "$tmp/$name" && "$@")
  printf '%s\n' "$expect" > "$tmp/$name/expect"
}

edit() { # edit <file> <awk program>: rewrites a file through awk
  local file=$1 prog=$2
  awk "$prog" "$file" > "$file.new" && mv "$file.new" "$file"
}

BETA=src/ocutalon/cls/OcuTalon/Data/Beta.cls
ALPHA=src/bridge/cls/OcuTalon/Bridge/Data/Alpha.cls
GAMMA=src/ocutalon/cls/OcuTalon/Msg/Gamma.cls
TSV=src/short-names.tsv

make_tree "$tmp/good"

bad_tree dup-short "$TSV" sh -c "printf 'Alpha\t^OcuTalonP.Other\tOcuTalon.Data.Other\tB\n' >> $TSV"
bad_tree dup-global "$TSV" sh -c "printf 'Other\t^OcuTalonP.Beta\tOcuTalon.Data.Other\tB\n' >> $TSV"
bad_tree dup-class "$TSV" sh -c "printf 'Other\t^OcuTalonP.Other\tOcuTalon.Data.Beta\tB\n' >> $TSV"
bad_tree no-parameter "$BETA" edit "$BETA" '!/^Parameter DEFAULTGLOBAL/'
bad_tree wrong-parameter "$BETA" sh -c "sed 's/^Parameter DEFAULTGLOBAL = \"^OcuTalonP.Beta\"/Parameter DEFAULTGLOBAL = \"^OcuTalonP.Other\"/' $BETA > $BETA.new && mv $BETA.new $BETA"
bad_tree no-row "$BETA" edit "$TSV" '!/^Beta\t/'
bad_tree prefix-bridge "$ALPHA" sh -c "sed 's/OcuTalonBP\./OcuTalonP./g' $ALPHA > $ALPHA.new && mv $ALPHA.new $ALPHA"
bad_tree prefix-outside "$BETA" sh -c "sed 's/OcuTalonP\./OcuTalonBP./g' $BETA > $BETA.new && mv $BETA.new $BETA"
bad_tree prefix-unknown "$BETA" sh -c "sed 's/OcuTalonP\./OcuTalonZz./g' $BETA > $BETA.new && mv $BETA.new $BETA"
bad_tree no-storage-persistent "$BETA" edit "$BETA" '/^Storage Default/ { skip = 1 } !skip { print } skip && /^\}/ { skip = 0 }'
bad_tree no-storage-message "$GAMMA" edit "$GAMMA" '/^Storage Default/ { skip = 1 } !skip { print } skip && /^\}/ { skip = 0 }'
bad_tree wrong-location "$BETA" sh -c "sed 's#<DataLocation>^OcuTalonP.BetaD#<DataLocation>^OcuTalonP.BetaX#' $BETA > $BETA.new && mv $BETA.new $BETA"
bad_tree wrong-id-location "$BETA" sh -c "sed 's#<IdLocation>^OcuTalonP.BetaD#<IdLocation>^OcuTalonP.BetaX#' $BETA > $BETA.new && mv $BETA.new $BETA"
bad_tree wrong-index-location "$BETA" sh -c "sed 's#<IndexLocation>^OcuTalonP.BetaI#<IndexLocation>^OcuTalonZz.BetaI#' $BETA > $BETA.new && mv $BETA.new $BETA"
bad_tree wrong-stream-location "$BETA" sh -c "sed 's#<StreamLocation>^OcuTalonP.BetaS#<StreamLocation>^OcuTalonP.BetaX#' $BETA > $BETA.new && mv $BETA.new $BETA"
DELTA=src/ocutalon/cls/OcuTalon/Data/Delta.cls
bad_tree no-param-new "$DELTA" sh -c "printf 'Class OcuTalon.Data.Delta Extends %%Persistent\n{\n\nProperty Text As %%String;\n\nStorage Default\n{\n<DataLocation>^OcuTalon.DeltaD</DataLocation>\n<Type>%%Storage.Persistent</Type>\n}\n\n}\n' > $DELTA"
bad_tree no-registry "$TSV" rm -f "$TSV"
bad_tree no-classes "$TSV" sh -c "find src -name '*.cls' -delete"

# --- the controls and the rules ---

if [ -n "$(check_tree "$tmp/good")" ]; then
  check_tree "$tmp/good" | head -n 10 | sed 's/^/  /'
  echo "FAIL controls: the checker flags the tree that keeps every rule"
  exit 1
fi

# rule <name> <sample>...: PASS when the checker flags each sample under this rule and names its file, and the
# real tree has no violation of the rule.
rule() {
  local name=$1 sample out hits ok=1
  shift
  for sample in "$@"; do
    out=$(check_tree "$tmp/$sample" | awk -F'\t' -v r="$name" '$1 == r')
    if [ -z "$out" ]; then
      echo "FAIL $name: the checker does not flag the sample $sample"
      ok=0
    elif ! printf '%s\n' "$out" | cut -f2 | grep -q "^$(cat "$tmp/$sample/expect")"; then
      echo "FAIL $name: the checker does not name $(cat "$tmp/$sample/expect") for the sample $sample"
      ok=0
    fi
  done
  hits=$(check_tree "$root" | awk -F'\t' -v r="$name" '$1 == r { print $2 ": " $3 }')
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    fails=$((fails + 1))
  fi
}

rule registry-duplicate dup-short dup-global dup-class
rule registry-class no-parameter wrong-parameter
rule registry-row no-row
rule registry-param no-param-new
rule scan no-registry no-classes
rule prefix prefix-bridge prefix-outside prefix-unknown
rule storage no-storage-persistent no-storage-message
rule datalocation wrong-location no-storage-persistent
rule locations wrong-id-location wrong-index-location wrong-stream-location

if [ "$fails" -ne 0 ]; then
  echo "test-storage: $fails rule(s) failed"
  exit 1
fi
echo "test-storage: all rules passed"
