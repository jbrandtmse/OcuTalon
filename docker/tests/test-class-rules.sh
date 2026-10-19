#!/usr/bin/env bash
# The class rules of src/ that need no IRIS (Story 0.7; AD-2, AD-13, AD-19; DW-17). Starts nothing: the rules read files only.
#   - bridge-refs (AD-2): no class of OcuTalon.Bridge or OcuTalon.BridgeExample names another OcuTalon package, as a class
#     (OcuTalon.Pkg) or as a table (OcuTalon_Pkg);
#   - ai-allowlist (AD-2): %AI (also as a table name, %AI_...), EnsLib.AI and EnsLib_AI appear in code only in the whole packages OcuTalon.Bridge,
#     OcuTalon.BridgeExample, OcuTalon.Agent, OcuTalon.Tools, OcuTalon.Docs, OcuTalon.Memory, OcuTalon.Mcp, OcuTalon.Install and
#     OcuTalon.Test (a package matches by whole name, not by prefix);
#   - public-global (AD-19): OcuTalonPublic appears on a code line of src/ and docker/after-start.cos only in
#     OcuTalon/Data/Public/Settings.cls;
#   - unchecked-prepare (AD-13, DW-17): outside the methods of ALLOW_UNCHECKED, no %Prepare whose second argument is not 1,
#     no %PrepareClassQuery whose third argument is not 1, and no %ExecDirectNoPriv or %ExecDirectNoPrivNoAudit, even when the
#     call spans lines or its SQL text holds commas and parentheses; and no entry of ALLOW_UNCHECKED that matches no such call.
#     A call that leaves the argument out takes the checked default. Embedded SQL is not scanned.
# A comment line (// ///, ; and #;) is not code. Each rule first runs on synthetic classes: ones that break it, ones that keep it,
# and one with only a comment that mentions it, so a rule that can no longer flag anything fails. A failing rule prints file:line
# and never the text of the line. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/docker/tests/lib-scan.sh"

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cr.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# The only unchecked prepares of src/ (DW-17): Class:Method, one per line.
ALLOW_UNCHECKED="OcuTalon.Data.Session:ForUser
OcuTalon.Live.Event:Since"
# The allow-list that the synthetic classes are judged by, so that the samples do not depend on the real list.
SAMPLE_ALLOW="OcuTalon.Data.Session:ForUser
OcuTalon.Live.Event:Since"

# The packages that may use %AI (AD-2), by whole name; a sub-package belongs to its package.
AI_PACKAGES="OcuTalon.Bridge OcuTalon.BridgeExample OcuTalon.Agent OcuTalon.Tools OcuTalon.Docs OcuTalon.Memory OcuTalon.Mcp OcuTalon.Install OcuTalon.Test"

# --- the scanners: file:line of each offending line ---

ai_refs() {
  awk -v packages="$AI_PACKAGES" '
    BEGIN { n = split(packages, pk, " ") }
    FNR == 1 {
      cls = FILENAME
      sub(/^.*\/cls\//, "", cls)
      sub(/\.cls$/, "", cls)
      gsub(/\//, ".", cls)
      pkg = cls
      sub(/\.[^.]*$/, "", pkg)
      if (pkg == cls) pkg = ""
      ok = 0
      for (i = 1; i <= n; i++) if (pkg == pk[i] || index(pkg, pk[i] ".") == 1) ok = 1
    }
    ok { next }
    /^[ \t]*(\/\/|;|#;|##;)/ { next }
    {
      low = tolower($0)
      if (low ~ /(^|[^a-z0-9_])%ai([^a-z0-9]|$)/ || low ~ /enslib[._]ai([^a-z0-9_]|$)/) print FILENAME ":" FNR
    }
  ' "$@"
}

public_global() {
  awk '
    FNR == 1 { code = (FILENAME ~ /\.(cls|cos|inc|mac|int)$/); exempt = (FILENAME ~ /OcuTalon\/Data\/Public\/Settings\.cls$/) }
    exempt { next }
    code && /^[ \t]*(\/\/|;|#;|##;)/ { next }
    /OcuTalonPublic/ { print FILENAME ":" FNR }
  ' "$@"
}

# unchecked_prepares <file>...: file:line of each unchecked prepare outside ALLOW_UNCHECKED; with STALE=1, also a line for each
# entry that no unchecked call uses.
unchecked_prepares() {
  awk -v allowlist="$(printf '%s' "$ALLOW_UNCHECKED" | tr '\n' ' ')" -v stale="${STALE:-0}" '
    function trim(s) { gsub(/^[ \t\r\n]+/, "", s); gsub(/[ \t\r\n]+$/, "", s); return s }
    function lineof(pos,   lo, hi, mid) {
      lo = 1; hi = nlines
      while (lo < hi) { mid = int((lo + hi + 1) / 2); if (lstart[mid] <= pos) lo = mid; else hi = mid - 1 }
      return lo
    }
    # The arguments of the call whose "(" precedes position from: parg[1..pn], each trimmed.
    function parse_args(text, from,   i, c, depth, instr, cur, len) {
      pn = 0; cur = ""; depth = 0; instr = 0; len = length(text)
      for (i = from; i <= len; i++) {
        c = substr(text, i, 1)
        if (instr) { cur = cur c; if (c == "\"") instr = 0; continue }
        if (c == "\"") { instr = 1; cur = cur c; continue }
        if (c == "(" || c == "{" || c == "[") { depth++; cur = cur c; continue }
        if (c == ")" || c == "}" || c == "]") {
          if (depth == 0) { if (trim(cur) != "" || pn > 0) parg[++pn] = trim(cur); return }
          depth--; cur = cur c; continue
        }
        if (c == "," && depth == 0) { parg[++pn] = trim(cur); cur = ""; continue }
        cur = cur c
      }
      if (trim(cur) != "" || pn > 0) parg[++pn] = trim(cur)
    }
    function hit(pos,   ln, key) {
      ln = lineof(pos)
      key = tolower(clsAt[ln] ":" memberAt[ln])
      if (key in allow) { used[key] = 1; return }
      print fname ":" ln
    }
    function process(   i, text, low, tok, t, pos, p, start, nt) {
      if (nlines == 0) return
      text = ""
      for (i = 1; i <= nlines; i++) { lstart[i] = length(text) + 1; text = text body[i] "\n" }
      low = tolower(text)
      nt = split("%prepare( %prepareclassquery( %execdirectnopriv", tok, " ")
      for (t = 1; t <= nt; t++) {
        pos = 1
        while ((p = index(substr(low, pos), tok[t])) > 0) {
          start = pos + p - 1
          pos = start + length(tok[t])
          if (t == 3) { hit(start); continue }
          parse_args(text, pos)
          if (t == 1 && pn >= 2 && parg[2] != "1") hit(start)
          if (t == 2 && pn >= 3 && parg[3] != "1") hit(start)
        }
      }
    }
    function reset(   k) {
      for (k in body) delete body[k]
      for (k in lstart) delete lstart[k]
      for (k in memberAt) delete memberAt[k]
      for (k in clsAt) delete clsAt[k]
      nlines = 0; cls = ""; member = ""
    }
    BEGIN {
      n = split(allowlist, a, " ")
      for (i = 1; i <= n; i++) { allow[tolower(a[i])] = a[i] }
    }
    FNR == 1 {
      process(); reset()
      fname = FILENAME
      objscript = (FILENAME ~ /\.(cls|cos|inc|mac|int)$/)
    }
    {
      line = $0
      sub(/\r$/, "", line)
      nlines++
      if (line ~ /^Class /) { split(line, w, /[ \t]+/); cls = w[2] }
      else if (line ~ /^(ClassMethod|Method)[ \t]/) {
        s = line
        sub(/^(ClassMethod|Method)[ \t]+/, "", s)
        match(s, /^[A-Za-z0-9_%]+/)
        member = substr(s, 1, RLENGTH)
      }
      else if (line ~ /^(Property|Parameter|Index|Query|ClassQuery|XData|Storage|Relationship|Trigger|ForeignKey|Projection)[ \t]/) member = ""
      memberAt[nlines] = member
      clsAt[nlines] = cls
      body[nlines] = (objscript && line ~ /^[ \t]*(\/\/|;|#;|##;)/) ? "" : line
    }
    END {
      process()
      if (stale == 1) for (k in allow) if (!(k in used)) print "allow-list:" allow[k]
    }
  ' "$@"
}

# --- the synthetic classes ---

cls_dir() { mkdir -p "$tmp/$1"; }

# A class file: write_class <dir> <Class> <body lines...>; the body goes between the braces.
write_class() {
  local dir=$1 name=$2 file
  shift 2
  file="$tmp/$dir/$(printf '%s' "$name" | tr . /).cls"
  mkdir -p "$(dirname "$file")"
  { printf 'Class %s Extends %%RegisteredObject\n{\n\n' "$name"; printf '%s\n' "$@"; printf '\n}\n'; } > "$file"
  printf '%s\n' "$file"
}

samples_ok=1
expect_flagged() { # expect_flagged <rule> <scanner> <file> [<lines expected>]
  local out
  out=$("$2" "$3")
  if [ -z "$out" ]; then
    echo "FAIL $1: the scanner does not flag the sample ${3#$tmp/}"
    fails=$((fails + 1)); samples_ok=0
  elif [ -n "${4:-}" ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" != "$4" ]; then
    echo "FAIL $1: the scanner flags the sample ${3#$tmp/} on $(printf '%s\n' "$out" | wc -l | tr -d ' ') line(s), wanted $4"
    fails=$((fails + 1)); samples_ok=0
  fi
}
expect_clean() { # expect_clean <rule> <scanner> <file>
  if [ -n "$("$2" "$3")" ]; then
    echo "FAIL $1: the scanner flags the sample ${3#$tmp/}, which keeps the rule"
    fails=$((fails + 1)); samples_ok=0
  fi
}

# --- bridge-refs ---

cls_dir refs
cat > "$tmp/refs/Bad.cls" <<'EOS'
Class OcuTalon.Bridge.ZzBad
{
ClassMethod A()
{
	Do ##class(OcuTalon.Core.BridgeSink).OnEvent()
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT 1 FROM OcuTalon_Data.Session")
}
}
EOS
cat > "$tmp/refs/Ok.cls" <<'EOS'
/// Names OcuTalon.Core.BridgeSink in a comment only.
Class OcuTalon.Bridge.ZzOk
{
Parameter P = "OcuTalon_Bridge_Data.Decision";
Parameter Q = "OcuTalon.BridgeExample.Host";
}
EOS
samples_ok=1
expect_flagged "bridge-refs" bridge_refs "$tmp/refs/Bad.cls" 2
expect_clean "bridge-refs" bridge_refs "$tmp/refs/Ok.cls"
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "bridge-refs: no class of OcuTalon.Bridge or OcuTalon.BridgeExample names another OcuTalon package" bridge_refs \
    "$tmp/refs/Bad.cls" "$tmp/refs/Ok.cls" "$(scan_files src/bridge/cls | grep '\.cls$')"
fi

# --- ai-allowlist ---

ai_bad1=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzBad 'ClassMethod A()' '{' '	Set a = ##class(%AI.Agent).%New()' '}')
ai_bad2=$(write_class ai/src/ocutalon/cls OcuTalon/Agents/ZzBad 'ClassMethod A()' '{' '	Set a = "EnsLib.AI.Thing"' '}')
ai_bad3=$(write_class ai/src/ocutalon/cls OcuTalon/ZzBad 'Property T As %String(VALUELIST = ",EnsLib_AI");' 'ClassMethod B()' '{' '	Set a = ##class(%ai.agent).%New()' '}')
ai_bad4=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzTable 'ClassMethod A()' '{' '	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT 1 FROM %AI_Agent.Session")' '}')
ai_good5=$(write_class ai/src/ocutalon/cls OcuTalon/Bridge/ZzNested/Ok 'ClassMethod A()' '{' '	Quit ##class(%AI.Agent).%New()' '}')
ai_good1=$(write_class ai/src/ocutalon/cls OcuTalon/Agent/ZzOk 'ClassMethod A()' '{' '	Set a = ##class(%AI.Agent).%New()' '}')
ai_good2=$(write_class ai/src/ocutalon/cls OcuTalon/Test/Web/ZzOk 'ClassMethod A()' '{' '	Set a = ##class(EnsLib.AI.Thing).%New()' '}')
ai_good3=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzComment '/// Mentions %AI.Agent and EnsLib.AI in a comment only.' 'ClassMethod A()' '{' '	// ##class(%AI.Agent)' '	Quit 1' '}')
ai_good4=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzWords 'ClassMethod A()' '{' '	Set a = "%AIX and MyEnsLib.AIs and BrAIn"' '}')
# OcuTalon/Agents is not the package OcuTalon.Agent (a whole name, not a prefix); OcuTalon.Bridge.ZzNested belongs to OcuTalon.Bridge.
samples_ok=1
for f in "$ai_bad1" "$ai_bad2" "$ai_bad3" "$ai_bad4"; do expect_flagged "ai-allowlist" ai_refs "$f"; done
expect_flagged "ai-allowlist" ai_refs "$ai_bad3" 2
for f in "$ai_good1" "$ai_good2" "$ai_good3" "$ai_good4" "$ai_good5"; do expect_clean "ai-allowlist" ai_refs "$f"; done
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "ai-allowlist: %AI and EnsLib.AI only in the whole packages Bridge, BridgeExample, Agent, Tools, Docs, Memory, Mcp, Install and Test" ai_refs \
    "$ai_bad1" "$ai_good1" "$(scan_files src | grep '\.cls$')"
fi

# --- public-global ---

pg_dir="$tmp/pg/src/ocutalon/cls/OcuTalon"
mkdir -p "$pg_dir/Web/Public" "$pg_dir/Data/Public" "$pg_dir/Watch"
printf 'Class OcuTalon.Web.Public.Status\n{\nClassMethod A()\n{\n\tQuit $Get(^OcuTalonPublic("ready"))\n}\n}\n' > "$pg_dir/Web/Public/Status.cls"
printf 'Class OcuTalon.Data.Public.Settings\n{\nClassMethod A()\n{\n\tQuit $Get(^OcuTalonPublic("ready"))\n}\n}\n' > "$pg_dir/Data/Public/Settings.cls"
printf 'Class OcuTalon.Watch.Other\n{\n/// Reads ^OcuTalonPublic through Settings.\nClassMethod A()\n{\n\t// ^OcuTalonPublic\n\tQuit 1\n}\n}\n' > "$pg_dir/Watch/Other.cls"
printf 'Set g = "^OcuTalonPublic"\n' > "$tmp/pg/after-start.cos"
printf 'Set g = 1\n; ^OcuTalonPublic in a comment\n' > "$tmp/pg/ok.cos"
samples_ok=1
expect_flagged "public-global" public_global "$pg_dir/Web/Public/Status.cls" 1
expect_flagged "public-global" public_global "$tmp/pg/after-start.cos" 1
expect_clean "public-global" public_global "$pg_dir/Data/Public/Settings.cls"
expect_clean "public-global" public_global "$pg_dir/Watch/Other.cls"
expect_clean "public-global" public_global "$tmp/pg/ok.cos"
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "public-global: ^OcuTalonPublic only in OcuTalon/Data/Public/Settings.cls" public_global \
    "$pg_dir/Web/Public/Status.cls" "$pg_dir/Data/Public/Settings.cls" "$(scan_files src docker/after-start.cos | grep -v '^src/ocutalon/csp/')"
fi

# --- unchecked-prepare ---

# name_stale: the lines of unchecked_prepares, a stale allow-list entry named at its line in this script.
name_stale() {
  local h entry
  while IFS= read -r h; do
    if [ "${h#allow-list:}" != "$h" ]; then
      entry=${h#allow-list:}
      echo "docker/tests/test-class-rules.sh:$(grep -n -F -- "$entry" "$0" | head -n 1 | cut -d: -f1) stale allow-list entry $entry"
    else
      echo "$h"
    fi
  done
}

up_class() { # up_class <sample> <Class> <method> <call line>...: a class with one method that holds the call lines
  local sample=$1 class=$2 method=$3
  shift 3
  write_class "up/$sample" "$class" "ClassMethod $method()" '{' "$@" '}'
}
mkdir -p "$tmp/up"
real_allow=$ALLOW_UNCHECKED
ALLOW_UNCHECKED=$SAMPLE_ALLOW
up_bad_zero=$(up_class bad-zero OcuTalon.Zz.A Run '	Set sc = statement.%Prepare("SELECT 1", 0)')
up_bad_two_lines=$(up_class bad-two-lines OcuTalon.Zz.B Run '	Set sc = statement.%Prepare("SELECT 1 FROM T",' '		0)')
up_bad_sql=$(up_class bad-sql OcuTalon.Zz.C Run '	Set sc = statement.%Prepare("SELECT a, f(b, c) FROM T WHERE x IN (1, 2) AND y = '"'"'z, 1)'"'"'", 0)')
up_bad_var=$(up_class bad-variable OcuTalon.Zz.D Run '	Set sc = statement.%Prepare(sql, checkPriv)')
up_bad_other=$(up_class bad-other-method OcuTalon.Data.Session Other '	Set sc = statement.%Prepare("SELECT 1", 0)')
up_bad_other_class=$(up_class bad-other-class OcuTalon.Live.Event ForUser '	Set sc = statement.%Prepare("SELECT 1", 0)')
up_bad_class_query=$(up_class bad-class-query OcuTalon.Zz.E Run '	Set sc = statement.%PrepareClassQuery("A.B", "C", 0)' '	Set sc = statement.%PrepareClassQuery("A.B", "C", 3)')
up_bad_nopriv=$(up_class bad-nopriv OcuTalon.Zz.F Run '	Set r = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT 1")' '	Set r = ##class(%SQL.Statement).%ExecDirectNoPrivNoAudit(, "SELECT 1")')
up_bad_case=$(up_class bad-case OcuTalon.Zz.G Run '	Set sc = statement.%prepare("SELECT 1", 0)')
up_bad_empty=$(up_class bad-empty OcuTalon.Zz.H Run '	Set sc = statement.%Prepare("SELECT 1", )')
up_good_allowed1=$(up_class good-for-user OcuTalon.Data.Session ForUser '	Set sc = statement.%Prepare("SELECT 1", 0)')
up_good_allowed2=$(up_class good-since OcuTalon.Live.Event Since '	Set sc = statement.%Prepare("SELECT 1", 0)')
up_good_checked=$(up_class good-checked OcuTalon.Zz.I Run \
  '	Set sc = statement.%Prepare("SELECT a, f(b, c) FROM T WHERE x IN (1, 2)", 1)' \
  '	Set sc = statement.%Prepare("SELECT a, f(b, c) FROM T")' \
  '	Set sc = statement.%Prepare("SELECT 1",' \
  '		1)' \
  '	Do $$$AssertStatusOK(statement.%Prepare("SELECT ID FROM T WHERE ID %STARTSWITH ?"), "prepared")' \
  '	Set sc = statement.%PrepareClassQuery("A.B", "C", 1)' \
  '	Set sc = statement.%PrepareClassQuery("A.B", "C")' \
  '	Set r = ##class(%SQL.Statement).%ExecDirect(, "SELECT 1")')
up_good_comment=$(up_class good-comment OcuTalon.Zz.J Run \
  '	// statement.%Prepare("SELECT 1", 0) and %ExecDirectNoPriv' \
  '	; %PrepareClassQuery("A", "B", 0)' \
  '	Quit 1')
mkdir -p "$tmp/up/good-doc"
printf '/// Never use %%Prepare("x", 0) or %%ExecDirectNoPriv here.\nClass OcuTalon.Zz.K\n{\n}\n' > "$tmp/up/good-doc/K.cls"
samples_ok=1
for f in "$up_bad_zero" "$up_bad_two_lines" "$up_bad_sql" "$up_bad_var" "$up_bad_other" "$up_bad_other_class" "$up_bad_case" "$up_bad_empty"; do
  expect_flagged "unchecked-prepare" unchecked_prepares "$f" 1
done
expect_flagged "unchecked-prepare" unchecked_prepares "$up_bad_class_query" 2
expect_flagged "unchecked-prepare" unchecked_prepares "$up_bad_nopriv" 2
for f in "$up_good_allowed1" "$up_good_allowed2" "$up_good_checked" "$up_good_comment" "$tmp/up/good-doc/K.cls"; do
  expect_clean "unchecked-prepare" unchecked_prepares "$f"
done
# The line that is named is the line of the call (the first line of a call that spans lines).
call_line=$(grep -n 'Prepare("SELECT 1 FROM T",' "$up_bad_two_lines" | cut -d: -f1)
if [ "$(unchecked_prepares "$up_bad_two_lines")" != "$up_bad_two_lines:$call_line" ]; then
  echo "FAIL unchecked-prepare: the call that spans two lines is not named at its first line ($(unchecked_prepares "$up_bad_two_lines" | sed "s#$tmp/##"))"
  fails=$((fails + 1)); samples_ok=0
fi
# A stale entry: with the allowed method of one entry present and the other absent, only the absent entry is reported.
stale_out=$(STALE=1 unchecked_prepares "$up_good_allowed1")
if [ "$stale_out" != "allow-list:OcuTalon.Live.Event:Since" ]; then
  echo "FAIL unchecked-prepare: the stale entry is not reported (got '$stale_out')"
  fails=$((fails + 1)); samples_ok=0
fi
ALLOW_UNCHECKED="OcuTalon.Data.Session:Gone"
stale_out=$(STALE=1 unchecked_prepares "$up_good_allowed1")
ALLOW_UNCHECKED=$SAMPLE_ALLOW
if ! printf '%s\n' "$stale_out" | grep -q '^allow-list:OcuTalon.Data.Session:Gone$' || ! printf '%s\n' "$stale_out" | grep -q 'good-for-user/'; then
  echo "FAIL unchecked-prepare: an entry that matches no call is not reported, or the call it should have allowed is not flagged"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(STALE=1 unchecked_prepares "$up_good_allowed1" "$up_good_allowed2" "$up_good_checked")" != "" ]; then
  echo "FAIL unchecked-prepare: the allowed methods are flagged, or an entry is reported stale"
  fails=$((fails + 1)); samples_ok=0
fi
ALLOW_UNCHECKED=$real_allow
if [ "$samples_ok" -eq 1 ]; then
  hits=$(STALE=1 unchecked_prepares $(scan_files src docker/after-start.cos | grep -E '\.(cls|cos|inc|mac|int)$') | name_stale)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL unchecked-prepare: only Session.ForUser and Live.Event.Since prepare without the privilege check, and each allow-list entry matches a call"
    fails=$((fails + 1))
  else
    echo "PASS unchecked-prepare: only Session.ForUser and Live.Event.Since prepare without the privilege check, and each allow-list entry matches a call"
  fi
fi

if [ "$fails" -ne 0 ]; then
  echo "test-class-rules: $fails rule(s) failed"
  exit 1
fi
echo "test-class-rules: all rules passed"
