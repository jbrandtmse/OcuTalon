#!/usr/bin/env bash
# The class rules of src/ that need no IRIS (Story 0.7; AD-2, AD-13, AD-19; DW-17). Starts nothing: the rules read files only.
#   - bridge-refs (AD-2): no class of OcuTalon.Bridge or OcuTalon.BridgeExample names another OcuTalon package, as a class
#     (OcuTalon.Pkg) or as a table (OcuTalon_Pkg);
#   - ai-allowlist (AD-2): %AI and EnsLib.AI (also as table names, %AI_... and EnsLib_AI_...) appear in code only in the whole packages OcuTalon.Bridge,
#     OcuTalon.BridgeExample, OcuTalon.Agent, OcuTalon.Tools, OcuTalon.Docs, OcuTalon.Memory, OcuTalon.Mcp, OcuTalon.Install and
#     OcuTalon.Test (a package matches by whole name, not by prefix);
#   - public-global (AD-19): OcuTalonPublic appears on a code line of src/ and docker/after-start.cos only in
#     OcuTalon/Data/Public/Settings.cls; a code line is a line of a .cls, .cos, .inc, .mac or .int file, so a configuration file
#     that maps the global (a CPF file) is not one;
#   - kb-ddl (AD-21, AD-33, Story 34.1): a code line of a .cls, .cos, .inc, .mac, .int or .py file of src/ outside the package OcuTalon.Test
#     that holds CREATE TABLE (in any case) also holds DEFAULTGLOBAL and the private prefix ^OcuTalonP. (^OcuTalonBP. under src/bridge/) on
#     that same line, so a knowledge-base table cannot be made with globals in the data database (the lines are read one at a time: a
#     CREATE TABLE line is flagged even when DEFAULTGLOBAL or the prefix follows on a later line, so write the three on one line, and a
#     statement that splits CREATE and TABLE over two lines is not read); and %AI.RAG.VectorStore.IRIS appears on a code line only in the
#     package OcuTalon.Docs and OcuTalon.Test, because only OcuTalon.Docs makes the tables (the class OcuTalon.Docs is in package OcuTalon,
#     outside the AD-2 allow-list);
#   - unchecked-prepare (AD-13, DW-17): outside the methods of ALLOW_UNCHECKED, no %Prepare whose second argument is not 1,
#     no %PrepareClassQuery whose third argument is not 1, and no %ExecDirectNoPriv or %ExecDirectNoPrivNoAudit, even when the
#     call spans lines or its SQL text holds commas and parentheses; and no entry of ALLOW_UNCHECKED that matches no such call.
#     A call that leaves the argument out takes the checked default. Embedded SQL is not scanned by this rule, because it is
#     not privilege-checked and this rule could not see it: the next rule keeps it out of src/;
#   - no-embedded-sql (AD-13 condition 4, inbox U-15): no &sql( or ##sql( on a code line of src/ outside its string literals, in
#     any case (a test's fixture text such as "&sql(DELETE ...)" is data, not embedded SQL), and no class
#     query of type %SQLQuery, whose SELECT compiles to embedded SQL. Embedded SQL is not privilege-checked and the
#     unchecked-prepare rule cannot see it, so the one unchecked path stays Ownership.Rows.
#   - trace-join (AD-26, Story 2.9): a call of OcuTalon.Core.Trace.Join, in any case, appears on a code line of src/ only in the
#     packages OcuTalon.Channel and OcuTalon.Test (a package matches by whole name, a sub-package belongs to its package): only a
#     channel service starts a session's trace thread; commands, approvals and notices inside a turn join through the bridge
#     context's ThreadSessionId;
#   - assert-concat (DW-505): in the first argument of $$$AssertTrue(, $$$AssertNotTrue(, $$$AssertEquals( and $$$AssertNotEquals(, no "_" at
#     the top level to the right of a top-level "[", "]" or "]]" (or their "'" forms). ObjectScript evaluates left to right, so
#     `text [ "a "_id` is `(text [ "a ") _ id`: it compares against the prefix alone and can never fail. Top level means outside string
#     literals, parentheses, braces and JSON-array brackets; a "[" is the operator when the character before it ends an operand, and a "]"
#     closes an array only when one is open. An assertion that spans lines is named at its first line; the Class:Method entries of
#     ALLOW_CONCAT are the exceptions, and an entry that matches no assertion fails as stale.
#   - web-global-reads (AD-13, DW-1287): in a class of the package OcuTalon.Web or a sub-package (a package matches by whole name), no code
#     line that names a product storage global (^OcuTalonP. or ^OcuTalonBP., also as an extended reference ^|"ns"| or ^["ns"] and inside a
#     string literal; a process-private ^|| name is not one) and no generated row-access call on a product class of src/short-names.tsv
#     (##class(<class>).<form>( or $ClassMethod("<class>", "<form>"), where the form is %OpenId, %ExistsId, %Open, %Exists or <Index>Open
#     or <Index>Exists of an index the class declares). A hit is named file:line Class:Method and what is read. The Class:Method entries
#     of ALLOW_WEB_READS are the sanctioned methods, and the Class:Method:Target entries of BASELINE_WEB_READS are the reads that are
#     reported and not yet moved; an entry that matches no read fails as stale. Known limits of a static check: methods that the web
#     process calls in other packages are not scanned; nor are a global or class name that is built at run time (concatenation,
#     indirection, a variable in $ClassMethod), a naked global reference ^(sub), the spelling $ZObjClassMethod, a short class name that
#     an Import resolves, a <Property>GetStored call, a row opened by following a reference property, a [ Language = python ] method, a
#     macro that expands to a read, a call split over several lines, embedded or dynamic SQL, an index that a product class inherits
#     (none does today), or a comment after code on the same line (it is scanned as code); and a baseline entry passes every repeat of
#     its own Class:Method:Target.
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
OcuTalon.Live.Event:Since
OcuTalon.Data.Ownership:Rows"
# The allow-list that the synthetic classes are judged by, so that the samples do not depend on the real list.
SAMPLE_ALLOW="OcuTalon.Data.Session:ForUser
OcuTalon.Live.Event:Since"

# The assertions of src/ that compare with a concatenation on the right of "[" (DW-505), Class:Method, one per line. None is left; an entry
# added here goes in the change that parenthesises the line, or the stale check fails.
ALLOW_CONCAT=""
SAMPLE_ALLOW_CONCAT="OcuTalon.Zz.Allowed:Run"

# The web-process methods that the Planner sanctions to read product storage directly (AD-13), Class:Method, one per line. None is sanctioned: the
# owning classes' methods and Ownership.Rows are outside OcuTalon.Web, so the rule never scans them.
ALLOW_WEB_READS=""
SAMPLE_ALLOW_WEB_READS="OcuTalon.Web.ZzAllowed:Run"

# The reads of product storage that web classes make today (DW-1287), Class:Method:Target, one per line: reported by Story 36.8 and not yet
# moved behind their owning class. An entry leaves this list in the change that moves its read, or the stale check fails.
BASELINE_WEB_READS="OcuTalon.Web.Api:CurrentSession:OcuTalon.Data.Session.RefIndexOpen
OcuTalon.Web.Live:Frame:OcuTalon.Data.Session.RefIndexOpen
OcuTalon.Web.Live:Heartbeat:OcuTalon.Data.Session.RefIndexOpen
OcuTalon.Web.Hook:Authenticated:OcuTalon.Data.Session.RefIndexExists"
SAMPLE_BASELINE_WEB_READS="OcuTalon.Web.ZzKnown:Run:OcuTalon.Data.Session.RefIndexOpen"

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
      if (low ~ /(^|[^a-z0-9_])%ai([^a-z0-9]|$)/ || low ~ /enslib[._]ai([^a-z0-9]|$)/) print FILENAME ":" FNR
    }
  ' "$@"
}

public_global() {
  awk '
    FNR == 1 { code = (FILENAME ~ /\.(cls|cos|inc|mac|int)$/); exempt = (FILENAME ~ /OcuTalon\/Data\/Public\/Settings\.cls$/) }
    exempt { next }
    !code || /^[ \t]*(\/\/|;|#;|##;)/ { next }
    /OcuTalonPublic/ { print FILENAME ":" FNR }
  ' "$@"
}

kb_ddl() {
  awk '
    FNR == 1 {
      code = (FILENAME ~ /\.(cls|cos|inc|mac|int|py)$/)
      py = (FILENAME ~ /\.py$/)
      test = (FILENAME ~ /\/OcuTalon\/Test\//)
      docs = (FILENAME ~ /\/OcuTalon\/Docs\//)
      prefix = (FILENAME ~ /(^|\/)src\/bridge\//) ? "^OcuTalonBP." : "^OcuTalonP."
    }
    test || !code || /^[ \t]*(\/\/|;|#;|##;)/ || (py && /^[ \t]*#/) { next }
    {
      low = tolower($0)
      if (low ~ /create[ \t]+table/ && (index(low, "defaultglobal") == 0 || index($0, prefix) == 0)) { print FILENAME ":" FNR; next }
      if (!docs && index(low, "%ai.rag.vectorstore.iris") > 0) print FILENAME ":" FNR
    }
  ' "$@"
}

# The awk machinery that unchecked_prepares and assert_concat share. The caller's program defines process(), which scans the joined text of
# one file (nlines lines in body[], their start offsets in lstart[] once join_text() has run) and calls hit() or allowed() for what it finds.
#   - comment lines of a class, routine or include file are blanked, so that a rule never sees them;
#   - memberAt[] and clsAt[] give the Class and the method of each line, and allow[] the Class:Method entries of -v allowlist (-v stale=1 also
#     prints an "allow-list:" line for each entry that allowed nothing).
SCAN_COMMON='
  function trim(s) { gsub(/^[ \t\r\n]+/, "", s); gsub(/[ \t\r\n]+$/, "", s); return s }
  function lineof(pos,   lo, hi, mid) {
    lo = 1; hi = nlines
    while (lo < hi) { mid = int((lo + hi + 1) / 2); if (lstart[mid] <= pos) lo = mid; else hi = mid - 1 }
    return lo
  }
  function join_text(   i, text) {
    text = ""
    for (i = 1; i <= nlines; i++) { lstart[i] = length(text) + 1; text = text body[i] "\n" }
    return text
  }
  function allowed(ln,   key) {
    key = tolower(clsAt[ln] ":" memberAt[ln])
    if (key in allow) { used[key] = 1; return 1 }
    return 0
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
'

# unchecked_prepares <file>...: file:line of each unchecked prepare outside ALLOW_UNCHECKED; with STALE=1, also a line for each
# entry that no unchecked call uses.
unchecked_prepares() {
  awk -v allowlist="$(printf '%s' "$ALLOW_UNCHECKED" | tr '\n' ' ')" -v stale="${STALE:-0}" "$SCAN_COMMON"'
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
    function hit(pos,   ln) {
      ln = lineof(pos)
      if (allowed(ln)) return
      print fname ":" ln
    }
    function process(   text, low, tok, t, pos, p, start, nt) {
      if (nlines == 0) return
      text = join_text()
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
  ' "$@"
}

# assert_concat <file>...: file:line of each assertion (the first line of it) whose first argument concatenates ("_") at the top level to the
# right of a top-level "[", "]" or "]]" (or their apostrophe forms), outside ALLOW_CONCAT; with STALE=1, also a line for each entry that no
# assertion uses.
assert_concat() {
  awk -v allowlist="$(printf '%s' "$ALLOW_CONCAT" | tr '\n' ' ')" -v stale="${STALE:-0}" "$SCAN_COMMON"'
    # 1 when the character ends an operand: a letter, a digit, ")", "}", a quote or an apostrophe.
    function ends_operand(c) {
      return (c ~ /^[A-Za-z0-9)}]$/) || c == "\"" || c == "\047"
    }
    # 1 when the argument that starts at position from has a "_" at the top level to the right of a top-level "[" or "]" operator.
    # The argument ends at a top-level "," or at the ")" that closes the assertion. stack holds the open "(", "{" and array "[".
    function concat_after_operator(text, from,   i, c, len, instr, prev, op, depth, stack) {
      len = length(text); instr = 0; prev = ""; op = 0; depth = 0; stack = ""
      for (i = from; i <= len; i++) {
        c = substr(text, i, 1)
        if (instr) { if (c == "\"") { instr = 0; prev = c }; continue }
        if (c == "\"") { instr = 1; continue }
        if (c ~ /^[ \t\r\n]$/) continue
        if (c == "(" || c == "{") { depth++; stack = stack c }
        else if (c == ")" || c == "}") {
          if (depth == 0) return 0
          depth--; stack = substr(stack, 1, depth)
        }
        else if (c == "[") {
          if (ends_operand(prev)) { if (depth == 0) op = 1 }
          else { depth++; stack = stack c }
        }
        else if (c == "]") {
          if (depth > 0 && substr(stack, depth, 1) == "[") { depth--; stack = substr(stack, 1, depth) }
          else if (depth == 0) op = 1
        }
        else if (c == "," && depth == 0) return 0
        else if (c == "_" && depth == 0 && op) return 1
        prev = c
      }
      return 0
    }
    function process(   text, low, tok, t, pos, p, start, nt, ln) {
      if (nlines == 0) return
      text = join_text()
      low = tolower(text)
      nt = split("$$$asserttrue( $$$assertnottrue( $$$assertequals( $$$assertnotequals(", tok, " ")
      for (t = 1; t <= nt; t++) {
        pos = 1
        while ((p = index(substr(low, pos), tok[t])) > 0) {
          start = pos + p - 1
          pos = start + length(tok[t])
          if (!concat_after_operator(text, pos)) continue
          ln = lineof(start)
          if (!allowed(ln)) print fname ":" ln
        }
      }
    }
  ' "$@"
}

# embedded_sql <file>...: file:line of each code line of a class, routine or include file that holds embedded SQL: &sql( or
# ##sql(, in any case, with blanks allowed before the parenthesis, or the declaration of a class query of type %SQLQuery.
embedded_sql() {
  awk '
    FNR == 1 { code = (FILENAME ~ /\.(cls|cos|inc|mac|int)$/) }
    !code || /^[ \t]*(\/\/|;|#;|##;)/ { next }
    { line = $0; gsub(/"([^"]|"")*"/, "\"\"", line) }
    tolower(line) ~ /(&|##)sql[ \t]*\(/ || tolower($0) ~ /^[ \t]*query[ \t].*[ \t]as[ \t]+%(library\.)?sqlquery([^a-z0-9_.]|$)/ { print FILENAME ":" FNR }
  ' "$@"
}

# trace_join <file>...: file:line of each code line of a class, routine or include file that calls OcuTalon.Core.Trace.Join, in
# any case, outside the packages OcuTalon.Channel and OcuTalon.Test (whole package names; a sub-package belongs to its package).
trace_join() {
  awk '
    FNR == 1 {
      cls = FILENAME
      sub(/^.*\/cls\//, "", cls)
      sub(/\.cls$/, "", cls)
      gsub(/\//, ".", cls)
      pkg = cls
      sub(/\.[^.]*$/, "", pkg)
      ok = (pkg == "OcuTalon.Channel" || index(pkg, "OcuTalon.Channel.") == 1 || pkg == "OcuTalon.Test" || index(pkg, "OcuTalon.Test.") == 1)
      code = (FILENAME ~ /\.(cls|cos|inc|mac|int)$/)
    }
    ok || !code || /^[ \t]*(\/\/|;|#;|##;)/ { next }
    tolower($0) ~ /ocutalon\.core\.trace\)[ \t]*\.join[ \t]*\(/ { print FILENAME ":" FNR }
  ' "$@"
}

# class_file <Class>: the .cls file of a class of src/ (the first of src/*/cls), or nothing.
class_file() {
  ls src/*/cls/"$(printf '%s' "$1" | tr . /)".cls 2>/dev/null | head -n 1
}

# product_classes: one "Class Index1 Index2 ..." per class of src/short-names.tsv (the product classes, AD-3), joined with ";" (no newline, so that
# it can be an awk -v value). The indexes are the "Index <Name>" declarations of the class's file; each makes <Name>Open and <Name>Exists.
product_classes() {
  awk -F'\t' 'NR > 1 && $3 != "" { print $3 }' src/short-names.tsv | while IFS= read -r c; do
    f=$(class_file "$c")
    printf '%s %s\n' "$c" "$([ -n "$f" ] && awk '/^Index[ \t]/ { printf "%s ", $2 }' "$f")"
  done | tr '\n' ';' | sed 's/;$//'
}

# web_reads <file>...: file:line Class:Method Target of each code line of a class of OcuTalon.Web (or a sub-package; whole package name) that
# names a product storage global (^OcuTalonP. or ^OcuTalonBP., with or without an extended reference, also inside a string literal), or calls a
# row-access form on a product class (WEB_PRODUCTS, from product_classes) as ##class(X).M( or $ClassMethod("X", "M". Target is the global (without
# the namespace part) or Class.Method. The reads of ALLOW_WEB_READS (Class:Method) and BASELINE_WEB_READS (Class:Method:Target) are not named; with
# STALE=1, also an "allow-list:" or "baseline:" line for each entry that no read uses.
web_reads() {
  awk -v allowlist="$(printf '%s' "$ALLOW_WEB_READS" | tr '\n' ' ')" -v baseline="$(printf '%s' "$BASELINE_WEB_READS" | tr '\n' ' ')" \
    -v products="$WEB_PRODUCTS" -v stale="${STALE:-0}" "$SCAN_COMMON"'
    BEGIN {
      np = split(products, prow, ";")
      for (bi = 1; bi <= np; bi++) {
        pk = split(prow[bi], pw, " "); pc = tolower(pw[1]); prod[pc] = pw[1]
        form[pc, "%openid"] = 1; form[pc, "%existsid"] = 1; form[pc, "%open"] = 1; form[pc, "%exists"] = 1
        for (bj = 2; bj <= pk; bj++) { form[pc, tolower(pw[bj]) "open"] = 1; form[pc, tolower(pw[bj]) "exists"] = 1 }
      }
      nb = split(baseline, bl, " ")
      for (bi = 1; bi <= nb; bi++) base[tolower(bl[bi])] = 1
    }
    function report(ln, target,   key) {
      if (allowed(ln)) return
      key = tolower(clsAt[ln] ":" memberAt[ln] ":" target)
      if (key in base) { bused[key] = 1; return }
      print fname ":" ln " " clsAt[ln] ":" memberAt[ln] " " target
    }
    function product_call(ln, c, m) {
      if ((tolower(c) in prod) && ((tolower(c), tolower(m)) in form)) report(ln, prod[tolower(c)] "." m)
    }
    function process(   i, s, ls, g, t, c, m, q) {
      if (nlines == 0) return
      if (index(tolower(cls), "ocutalon.web.") != 1) return
      for (i = 1; i <= nlines; i++) {
        if (body[i] == "") continue
        s = body[i]
        while (match(s, /\^(\|[^|]+\||\[[^]]*\])?OcuTalonB?P\.[A-Za-z0-9.]*/)) {
          g = substr(s, RSTART, RLENGTH)
          sub(/^\^(\|[^|]+\||\[[^]]*\])?/, "^", g)
          report(i, g)
          s = substr(s, RSTART + RLENGTH)
        }
        s = body[i]; ls = tolower(s)
        while (match(ls, /##class\([ \t]*[a-z0-9.%]+[ \t]*\)\.[a-z0-9%]+[ \t]*\(/)) {
          t = substr(s, RSTART, RLENGTH)
          s = substr(s, RSTART + RLENGTH); ls = substr(ls, RSTART + RLENGTH)
          c = t; sub(/^##class\([ \t]*/, "", c); sub(/[ \t]*\).*$/, "", c)
          m = t; sub(/^[^)]*\)\./, "", m); sub(/[ \t]*\($/, "", m)
          product_call(i, c, m)
        }
        s = body[i]; ls = tolower(s)
        while (match(ls, /\$classmethod\([ \t]*"[a-z0-9.%]+"[ \t]*,[ \t]*"[a-z0-9%]+"/)) {
          t = substr(s, RSTART, RLENGTH)
          s = substr(s, RSTART + RLENGTH); ls = substr(ls, RSTART + RLENGTH)
          split(t, q, "\"")
          product_call(i, q[2], q[4])
        }
      }
    }
    END {
      if (stale == 1) for (bi = 1; bi <= nb; bi++) if (!(tolower(bl[bi]) in bused)) print "baseline:" bl[bi]
    }
  ' "$@"
}

# --- the synthetic classes ---

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

bridge_ref_samples "$tmp/refs"
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
ai_bad5=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzEnsTable 'ClassMethod A()' '{' '	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT 1 FROM EnsLib_AI_Messages.Request")' '}')
ai_good5=$(write_class ai/src/ocutalon/cls OcuTalon/Bridge/ZzNested/Ok 'ClassMethod A()' '{' '	Quit ##class(%AI.Agent).%New()' '}')
ai_good1=$(write_class ai/src/ocutalon/cls OcuTalon/Agent/ZzOk 'ClassMethod A()' '{' '	Set a = ##class(%AI.Agent).%New()' '}')
ai_good2=$(write_class ai/src/ocutalon/cls OcuTalon/Test/Web/ZzOk 'ClassMethod A()' '{' '	Set a = ##class(EnsLib.AI.Thing).%New()' '}')
ai_good3=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzComment '/// Mentions %AI.Agent and EnsLib.AI in a comment only.' 'ClassMethod A()' '{' '	// ##class(%AI.Agent)' '	Quit 1' '}')
ai_good4=$(write_class ai/src/ocutalon/cls OcuTalon/Watch/ZzWords 'ClassMethod A()' '{' '	Set a = "%AIX and MyEnsLib.AIs and BrAIn"' '}')
# OcuTalon/Agents is not the package OcuTalon.Agent (a whole name, not a prefix); OcuTalon.Bridge.ZzNested belongs to OcuTalon.Bridge.
samples_ok=1
for f in "$ai_bad1" "$ai_bad2" "$ai_bad3" "$ai_bad4" "$ai_bad5"; do expect_flagged "ai-allowlist" ai_refs "$f"; done
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
printf '[Actions]\nCreateMapGlobal:Name=OcuTalonPublic,Namespace=OCUTALON,From=OCUTALON\n' > "$tmp/pg/ocutalon.cpf"
samples_ok=1
expect_flagged "public-global" public_global "$pg_dir/Web/Public/Status.cls" 1
expect_flagged "public-global" public_global "$tmp/pg/after-start.cos" 1
expect_clean "public-global" public_global "$pg_dir/Data/Public/Settings.cls"
expect_clean "public-global" public_global "$pg_dir/Watch/Other.cls"
expect_clean "public-global" public_global "$tmp/pg/ok.cos"
expect_clean "public-global" public_global "$tmp/pg/ocutalon.cpf"
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "public-global: ^OcuTalonPublic only in OcuTalon/Data/Public/Settings.cls" public_global \
    "$pg_dir/Web/Public/Status.cls" "$pg_dir/Data/Public/Settings.cls" "$(scan_files src docker/after-start.cos | grep -v '^src/ocutalon/csp/')"
fi

# --- kb-ddl ---

kb_dir="$tmp/kb/src/ocutalon/cls"
kb_bad1=$(write_class kb/src/ocutalon/cls OcuTalon/Watch/ZzBad 'ClassMethod A()' '{' '	Do ##class(%SQL.Statement).%ExecDirect(, "CREATE TABLE OcuTalonKB.S1 (id VARCHAR(64))")' '}')
kb_bad2=$(write_class kb/src/ocutalon/cls OcuTalon/Docs/ZzBad 'ClassMethod A()' '{' '	Do ##class(%SQL.Statement).%ExecDirect(, "create  table OcuTalonKB.S1 (id VARCHAR(64)) WITH %CLASSPARAMETER DEFAULTGLOBAL = '"'"'^OcuTalonKB.S1'"'"'")' '}')
kb_bad3=$(write_class kb/src/ocutalon/cls OcuTalon/Watch/ZzVector 'ClassMethod A()' '{' '	Quit ##class(%AI.RAG.VectorStore.IRIS).%New("T", 384)' '}')
kb_bad4=$(write_class kb/src/bridge/cls OcuTalon/Bridge/ZzBad 'ClassMethod A()' '{' '	Do ##class(%SQL.Statement).%ExecDirect(, "CREATE TABLE OcuTalonKB.S1 (id INT) WITH %CLASSPARAMETER DEFAULTGLOBAL = '"'"'^OcuTalonP.KBS1'"'"'")' '}')
mkdir -p "$kb_dir/OcuTalon/Docs" "$tmp/kb/src/ocutalon/python"
printf 'import iris\nrs = iris.sql.exec("create table OcuTalonKB.S1 (id INT)")\n' > "$tmp/kb/src/ocutalon/python/bad.py"
mkdir -p "$tmp/kb/src/ocutalon/mac"
printf 'ROUTINE ZzBad\n Do $SYSTEM.SQL.Execute("CREATE TABLE OcuTalonKB.S1 (id INT)")\n' > "$tmp/kb/src/ocutalon/mac/ZzBad.mac"
printf 'import iris\n# create table OcuTalonKB.S1 (id INT)\nx = 1\n' > "$tmp/kb/src/ocutalon/python/ok.py"
kb_good1=$(write_class kb/src/ocutalon/cls OcuTalon/Docs/ZzOk 'ClassMethod A()' '{' '	Do ##class(%SQL.Statement).%ExecDirect(, "CREATE TABLE OcuTalonKB.S1 (id VARCHAR(64)) WITH %CLASSPARAMETER DEFAULTGLOBAL = '"'"'^OcuTalonP.KBS1'"'"'")' '	Quit ##class(%AI.RAG.VectorStore.IRIS).%New("OcuTalonKB.S1", 384)' '}')
kb_good2=$(write_class kb/src/bridge/cls OcuTalon/Bridge/ZzOk 'ClassMethod A()' '{' '	Do ##class(%SQL.Statement).%ExecDirect(, "CREATE TABLE OcuTalonBridge.T (id INT) WITH %CLASSPARAMETER DEFAULTGLOBAL = '"'"'^OcuTalonBP.T'"'"'")' '}')
kb_good3=$(write_class kb/src/ocutalon/cls OcuTalon/Watch/ZzComment '/// A CREATE TABLE statement and %AI.RAG.VectorStore.IRIS in a comment only.' 'ClassMethod A()' '{' '	// CREATE TABLE OcuTalonKB.S1 (id INT) and %AI.RAG.VectorStore.IRIS' '	Quit 1' '}')
kb_bad5=$(write_class kb/src/ocutalon/cls OcuTalon.Docs 'ClassMethod A()' '{' '	Quit ##class(%AI.RAG.VectorStore.IRIS).%New("OcuTalonKB.S1", 384)' '}')
kb_bad6=$(write_class kb/src/ocutalon/cls OcuTalon/Docs/ZzNoDefault 'ClassMethod A()' '{' '	Set sql = "CREATE TABLE OcuTalonKB.S1 (id INT)", global = "^OcuTalonP.KBS1"' '}')
kb_good4=$(write_class kb/src/ocutalon/cls OcuTalon/Test/Docs/ZzFixture 'ClassMethod A()' '{' '	Do ##class(%SQL.Statement).%ExecDirect(, "CREATE TABLE OcuTalonKB.Zz (id INT)")' '	Quit ##class(%AI.RAG.VectorStore.IRIS).%New("OcuTalonKB.Zz", 384)' '}')
samples_ok=1
for f in "$kb_bad1" "$kb_bad2" "$kb_bad3" "$kb_bad4" "$kb_bad5" "$kb_bad6" "$tmp/kb/src/ocutalon/python/bad.py" "$tmp/kb/src/ocutalon/mac/ZzBad.mac"; do expect_flagged "kb-ddl" kb_ddl "$f" 1; done
for f in "$kb_good1" "$kb_good2" "$kb_good3" "$kb_good4" "$tmp/kb/src/ocutalon/python/ok.py"; do expect_clean "kb-ddl" kb_ddl "$f"; done
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "kb-ddl: a product CREATE TABLE line carries DEFAULTGLOBAL and the private prefix, and only OcuTalon.Docs names %AI.RAG.VectorStore.IRIS" kb_ddl \
    "$kb_bad1" "$kb_good1" "$(scan_files src | grep -E '\.(cls|cos|inc|mac|int|py)$')"
fi

# --- unchecked-prepare ---

# name_stale: the lines of unchecked_prepares and web_reads, a stale allow-list or baseline entry named at its line in this script.
name_stale() {
  local h entry
  while IFS= read -r h; do
    if [ "${h#allow-list:}" != "$h" ]; then
      entry=${h#allow-list:}
      echo "docker/tests/test-class-rules.sh:$(grep -n -F -- "$entry" "$0" | head -n 1 | cut -d: -f1) stale allow-list entry $entry"
    elif [ "${h#baseline:}" != "$h" ]; then
      entry=${h#baseline:}
      echo "docker/tests/test-class-rules.sh:$(grep -n -F -- "$entry" "$0" | head -n 1 | cut -d: -f1) stale baseline entry $entry"
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
  # The file list is split at newlines only, with no pattern expansion (as scan_rule does).
  hits=$(
    IFS='
'
    set -f
    STALE=1 unchecked_prepares $(scan_files src docker/after-start.cos | grep -E '\.(cls|cos|inc|mac|int)$') | name_stale
  )
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL unchecked-prepare: only Session.ForUser, Live.Event.Since and Ownership.Rows prepare without the privilege check, and each allow-list entry matches a call"
    fails=$((fails + 1))
  else
    echo "PASS unchecked-prepare: only Session.ForUser, Live.Event.Since and Ownership.Rows prepare without the privilege check, and each allow-list entry matches a call"
  fi
fi

# --- web-global-reads ---

# The product classes come from the registry, and the real list is guarded: every class of the registry is listed, has a file, and Session carries RefIndex.
WEB_PRODUCTS=$(product_classes)
wr_guard_ok=1
wr_reg=$(awk -F'\t' 'NR > 1 && $3 != "" { n++ } END { print n + 0 }' src/short-names.tsv)
wr_listed=$(printf '%s' "$WEB_PRODUCTS" | tr ';' '\n' | grep -c .)
if [ "$wr_reg" -eq 0 ] || [ "$wr_listed" -ne "$wr_reg" ]; then
  echo "FAIL web-global-reads: product_classes lists $wr_listed class(es), the registry has $wr_reg"
  fails=$((fails + 1)); wr_guard_ok=0
fi
for wr_c in $(awk -F'\t' 'NR > 1 && $3 != "" { print $3 }' src/short-names.tsv); do
  if [ -z "$(class_file "$wr_c")" ]; then
    echo "FAIL web-global-reads: the registry class $wr_c has no file in src/*/cls"
    fails=$((fails + 1)); wr_guard_ok=0
  fi
done
if ! printf '%s' "$WEB_PRODUCTS" | tr ';' '\n' | grep -Eq '^OcuTalon\.Data\.Session (.* )?RefIndex( |$)'; then
  echo "FAIL web-global-reads: product_classes does not list the index RefIndex of OcuTalon.Data.Session"
  fails=$((fails + 1)); wr_guard_ok=0
fi

wr_class() { # wr_class <sample> <Class> <method> <line>...: a class with one method that holds the lines
  local sample=$1 class=$2 method=$3
  shift 3
  write_class "wr/$sample" "$class" "ClassMethod $method()" '{' "$@" '}'
}
# wr_scan <file>...: the scan of the real tree, with the stale check and each stale entry named at its line in this script.
wr_scan() {
  STALE=1 web_reads "$@" | name_stale
}
mkdir -p "$tmp/wr"
real_allow_web=$ALLOW_WEB_READS
real_base_web=$BASELINE_WEB_READS
# The samples use a fixed list of product classes, so they do not depend on the registry; the real scan uses the guarded registry list.
real_products=$WEB_PRODUCTS
WEB_PRODUCTS="OcuTalon.Data.Session RefIndex;OcuTalon.Data.Webhook;OcuTalon.Data.Ownership"
ALLOW_WEB_READS=""
BASELINE_WEB_READS=""
wr_a=$(wr_class a OcuTalon.Web.ZzA Run '	Set id = $Order(^OcuTalonP.SessionD(""))')
wr_forms=$(wr_class forms OcuTalon.Web.ZzForms Run \
  '	Set a = $Get(^OcuTalonBP.DecisionD(1))' \
  '	Set b = $Data(^OcuTalonP.SessionI("a", 1))' \
  '	Merge x = ^OcuTalonP.SessionD' \
  '	Set g = "^OcuTalonP.SessionD"' \
  '	Set c = $Get(^|"OCUTALON"|OcuTalonP.SessionD(1))' \
  '	Set d = $Get(^["OCUTALON"]OcuTalonP.SessionD(1))')
wr_rows=$(wr_class rows OcuTalon.Web.Public.ZzB Run \
  '	Set a = ##class(OcuTalon.Data.Session).%OpenId(id)' \
  '	Set b = ##class(OcuTalon.Data.Session).%ExistsId(id)' \
  '	Set c = ##class(OcuTalon.Data.Session).%Open(oid)' \
  '	Set d = ##class(OcuTalon.Data.Session).%Exists(oid)' \
  '	Set e = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)' \
  '	Set f = ##class(OcuTalon.Data.Session).RefIndexExists(ref)' \
  '	Set g = ##class(ocutalon.data.SESSION).%openid(id)' \
  '	Set h = $ClassMethod("OcuTalon.Data.Session", "%OpenId", id)')
wr_clean=$(wr_class clean OcuTalon.Web.ZzClean Run \
  '	Set a = ##class(OcuTalon.Data.Webhook).ForSession(ref)' \
  '	Set b = ##class(OcuTalon.Data.Ownership).Rows(ref)' \
  '	Set c = ##class(OcuTalon.Data.Session).SignOuts(ref)' \
  '	Set d = $Get(^Ens.Runtime("x"))' \
  '	Set e = $Order(@store@(id))' \
  '	Set f = $Get(^||OcuTalonP.X)' \
  '	Set g = ##class(%Dictionary.CompiledXData).%OpenId(id)' \
  '	Set h = $Get(^OcuTalonPublic("x"))' \
  '	Set i = $Get(^OcuTalon.Runtime("x"))' \
  '	Set j = $Get(^ocutalonp.SessionD(1))' \
  '	Do ##class(OcuTalon.Data.Session).%DeleteId(id)' \
  '	Do session.%Save()' \
  '	Set k = ##class(OcuTalon.Data.Session).Other(id)' \
  '	Set l = $ClassMethod("OcuTalon.Data.Session", "SignOuts", id)' \
  '	Set o = ##class(OcuTalon.Zz.NotRegistered).%OpenId(id)' \
  '	Set p = ##class(OcuTalon.Zz.NotRegistered).RefIndexOpen(ref)' \
  '	Set q = $ClassMethod("OcuTalon.Zz.NotRegistered", "%OpenId", id)' \
  '	Set r = ##class(OcuTalon.Data.Session).NoSuchIndexOpen(ref)' \
  '	// Set m = ##class(OcuTalon.Data.Session).%OpenId(id) and $Get(^OcuTalonP.SessionD(1))' \
  '	; Set n = $Get(^OcuTalonBP.DecisionD(1))')
wr_doc=$(write_class wr/doc OcuTalon.Web.ZzDoc '/// Never read ^OcuTalonP.SessionD or call ##class(OcuTalon.Data.Session).%OpenId( here.' 'ClassMethod Run()' '{' '	Quit 1' '}')
wr_out1=$(wr_class out1 OcuTalon.Data.Session Run '	Set id = $Order(^OcuTalonP.SessionD(""))' '	Set a = ##class(OcuTalon.Data.Session).%OpenId(id)')
wr_out2=$(wr_class out2 OcuTalon.Webhook.ZzX Run '	Set id = $Order(^OcuTalonP.SessionD(""))' '	Set a = ##class(OcuTalon.Data.Session).%OpenId(id)')
wr_out3=$(wr_class out3 OcuTalon.Test.Web.ZzX Run '	Set id = $Order(^OcuTalonP.SessionD(""))' '	Set a = ##class(OcuTalon.Data.Session).%OpenId(id)')
wr_out4=$(wr_class out4 OcuTalon.Webs.ZzX Run '	Set id = $Order(^OcuTalonP.SessionD(""))')
wr_deep=$(wr_class deep OcuTalon.Web.Public.Deep.ZzC Run '	Set id = $Order(^OcuTalonP.SessionD(""))' '	Set a = ##class(OcuTalon.Data.Session).%OpenId(id)')
wr_mixed=$(wr_class mixed OcuTalon.Web.ZzMixed Run \
  '	If $Data(^OcuTalonP.SessionD(id)), ##class(OcuTalon.Data.Session).%ExistsId(id) Quit $Order(^OcuTalonBP.DecisionI(""))' \
  '	Set a = ##class(OcuTalon.Data.Webhook).ForSession(ref), b = $Get(^OcuTalonP.SessionD(1))')
samples_ok=$wr_guard_ok
expect_flagged "web-global-reads" web_reads "$wr_a" 1
expect_flagged "web-global-reads" web_reads "$wr_deep" 2
expect_flagged "web-global-reads" web_reads "$wr_mixed" 4
expect_flagged "web-global-reads" web_reads "$wr_forms" 6
expect_flagged "web-global-reads" web_reads "$wr_rows" 8
for f in "$wr_clean" "$wr_doc" "$wr_out1" "$wr_out2" "$wr_out3" "$wr_out4"; do expect_clean "web-global-reads" web_reads "$f"; done
# The hit names file:line, Class:Method and the target, with no namespace part and the registry spelling of the class.
call_line=$(grep -n 'OcuTalonP.SessionD' "$wr_a" | cut -d: -f1)
if [ "$(web_reads "$wr_a")" != "$wr_a:$call_line OcuTalon.Web.ZzA:Run ^OcuTalonP.SessionD" ]; then
  echo "FAIL web-global-reads: the planted read is not named as file:line Class:Method Target ($(web_reads "$wr_a" | sed "s#$tmp/##"))"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(web_reads "$wr_forms" | grep -c ' \^OcuTalonB\{0,1\}P\.[A-Za-z0-9.]*$')" != 6 ] || web_reads "$wr_forms" | grep -qi 'OCUTALON"'; then
  echo "FAIL web-global-reads: a global target keeps its namespace part, or is not named as a global"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(web_reads "$wr_rows" | grep -c ' OcuTalon\.Data\.Session\.[A-Za-z%]*$')" != 8 ]; then
  echo "FAIL web-global-reads: a row-access target is not named as Class.Method with the registry spelling of the class"
  fails=$((fails + 1)); samples_ok=0
fi
# The allow-list: an allowed method is not named and its entry is not stale; an entry whose method holds no read is stale; another method is named.
ALLOW_WEB_READS=$SAMPLE_ALLOW_WEB_READS
wr_allowed=$(wr_class allowed OcuTalon.Web.ZzAllowed Run '	Set id = $Order(^OcuTalonP.SessionD(""))')
wr_allowed_plus=$(write_class wr/allowed-plus OcuTalon.Web.ZzAllowed 'ClassMethod Run()' '{' '	Set id = $Order(^OcuTalonP.SessionD(""))' '}' 'ClassMethod Other()' '{' '	Set id = $Order(^OcuTalonP.SessionD(""))' '}')
if [ -n "$(STALE=1 web_reads "$wr_allowed")" ]; then
  echo "FAIL web-global-reads: an allowed read is flagged, or its entry is reported stale"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(STALE=1 web_reads "$wr_clean")" != "allow-list:OcuTalon.Web.ZzAllowed:Run" ]; then
  echo "FAIL web-global-reads: an allow-list entry that matches no read is not reported stale"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(web_reads "$wr_allowed_plus")" != "$wr_allowed_plus:$(grep -n 'OcuTalonP.SessionD' "$wr_allowed_plus" | tail -n 1 | cut -d: -f1) OcuTalon.Web.ZzAllowed:Other ^OcuTalonP.SessionD" ]; then
  echo "FAIL web-global-reads: a read in a method other than the allowed one is not named alone"
  fails=$((fails + 1)); samples_ok=0
fi
ALLOW_WEB_READS=""
# The baseline: a baselined read is not named and its entry is not stale; a new read in the same method is named; an entry whose read is gone is stale.
BASELINE_WEB_READS=$SAMPLE_BASELINE_WEB_READS
wr_known=$(wr_class known OcuTalon.Web.ZzKnown Run '	Set s = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)')
wr_known_plus=$(wr_class known-plus OcuTalon.Web.ZzKnown Run '	Set s = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)' '	Set t = ##class(OcuTalon.Data.Session).%OpenId(id)')
wr_known_gone=$(wr_class known-gone OcuTalon.Web.ZzKnown Run '	Quit 1')
if [ -n "$(STALE=1 web_reads "$wr_known")" ]; then
  echo "FAIL web-global-reads: a baselined read is flagged, or its entry is reported stale"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(STALE=1 web_reads "$wr_known_plus")" != "$wr_known_plus:$(grep -n '%OpenId' "$wr_known_plus" | cut -d: -f1) OcuTalon.Web.ZzKnown:Run OcuTalon.Data.Session.%OpenId" ]; then
  echo "FAIL web-global-reads: a new read in a baselined method is not named alone ($(STALE=1 web_reads "$wr_known_plus" | sed "s#$tmp/##" | tr '\n' ' '))"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(STALE=1 web_reads "$wr_known_gone")" != "baseline:OcuTalon.Web.ZzKnown:Run:OcuTalon.Data.Session.RefIndexOpen" ]; then
  echo "FAIL web-global-reads: a baseline entry whose read is gone is not reported stale"
  fails=$((fails + 1)); samples_ok=0
fi
if [ "$(wr_scan "$wr_known_gone")" != "docker/tests/test-class-rules.sh:$(grep -n -F 'SAMPLE_BASELINE_WEB_READS=' "$0" | head -n 1 | cut -d: -f1) stale baseline entry OcuTalon.Web.ZzKnown:Run:OcuTalon.Data.Session.RefIndexOpen" ]; then
  echo "FAIL web-global-reads: the real-tree scan does not name a stale baseline entry at its line in this script"
  fails=$((fails + 1)); samples_ok=0
fi
# A baselined read is keyed by class and method too: the same read in another method, or in another class, is named.
wr_known_method=$(write_class wr/known-method OcuTalon.Web.ZzKnown 'ClassMethod Run()' '{' '	Set s = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)' '}' 'ClassMethod Other()' '{' '	Set s = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)' '}')
wr_known_class=$(wr_class known-class OcuTalon.Web.ZzKnownB Run '	Set s = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)')
if [ "$(web_reads "$wr_known_method")" != "$wr_known_method:$(grep -n 'RefIndexOpen' "$wr_known_method" | tail -n 1 | cut -d: -f1) OcuTalon.Web.ZzKnown:Other OcuTalon.Data.Session.RefIndexOpen" ]; then
  echo "FAIL web-global-reads: the baselined read in another method of the class is not named alone ($(web_reads "$wr_known_method" | sed "s#$tmp/##" | tr '\n' ' '))"
  fails=$((fails + 1)); samples_ok=0
fi
expect_flagged "web-global-reads" web_reads "$wr_known_class" 1
ALLOW_WEB_READS=$real_allow_web
BASELINE_WEB_READS=$real_base_web
WEB_PRODUCTS=$real_products
if [ "$samples_ok" -eq 1 ]; then
  hits=$(
    IFS='
'
    set -f
    wr_scan $(scan_files src | grep '\.cls$')
  )
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL web-global-reads: no class of OcuTalon.Web reads a product storage global or a product class's rows directly, beyond the baseline, and each entry matches a read"
    fails=$((fails + 1))
  else
    echo "PASS web-global-reads: no class of OcuTalon.Web reads a product storage global or a product class's rows directly, beyond the baseline, and each entry matches a read"
  fi
fi

# --- assert-concat ---

ac_class() { # ac_class <sample> <Class> <method> <line>...: a class with one method that holds the lines
  local sample=$1 class=$2 method=$3
  shift 3
  write_class "ac/$sample" "$class" "ClassMethod $method()" '{' "$@" '}'
}
mkdir -p "$tmp/ac"
real_allow_concat=$ALLOW_CONCAT
ALLOW_CONCAT=$SAMPLE_ALLOW_CONCAT
ac_bad=$(ac_class bad OcuTalon.Zz.AcBad Run \
  '	Do $$$AssertTrue(text [ "agent steps "_stepId, "l: "_text)' \
  '	Do $$$AssertTrue(now ] $Translate(a, " ", "T")_"Z", "l")' \
  '	Do $$$AssertTrue(x '"'"'[ "a"_y, "l")' \
  '	Do $$$AssertEquals(x ]] "a"_y, 1)' \
  '	Do $$$AssertNotTrue(x '"'"'] "a" _ y, 0)' \
  '	Do $$$AssertNotEquals(x [ "a"_y, 0)')
ac_bad_two_lines=$(ac_class bad-two-lines OcuTalon.Zz.AcTwo Run \
  '	Set x = 1' \
  '	Do $$$AssertTrue(x [ "a"' \
  '		_ y, "l")')
ac_good=$(ac_class good OcuTalon.Zz.AcGood Run \
  '	Do $$$AssertTrue(text [ ("a"_y), "l: "_t)' \
  '	Do $$$AssertTrue((x [ "a")_y, "l")' \
  '	Do $$$AssertTrue(x_y [ z, "l")' \
  '	Do $$$AssertTrue(x [ y, "l "_z)' \
  '	Do $$$AssertTrue(x [ y && (a_b = c), "l")' \
  '	Do $$$AssertEquals([1,2].%ToJSON()_"", "[1,2]")' \
  '	Do $$$AssertTrue(..F([1, 2]) [ "a", "l")' \
  '	Do $$$AssertTrue(x = "a [ b_c", "l")' \
  '	If x [ "a"_y Quit' \
  '	// Do $$$AssertTrue(x [ "a"_y, "l")' \
  '	; Do $$$AssertTrue(x [ "a"_y, "l")')
mkdir -p "$tmp/ac/good-doc"
printf '/// Never write $$$AssertTrue(x [ "a"_y, "l") here.\nClass OcuTalon.Zz.AcDoc\n{\n}\n' > "$tmp/ac/good-doc/Doc.cls"
ac_allowed=$(ac_class allowed OcuTalon.Zz.Allowed Run '	Do $$$AssertTrue(text [ "a "_y, "l")')
samples_ok=1
expect_flagged "assert-concat" assert_concat "$ac_bad" 6
expect_flagged "assert-concat" assert_concat "$ac_bad_two_lines" 1
expect_clean "assert-concat" assert_concat "$ac_good"
expect_clean "assert-concat" assert_concat "$tmp/ac/good-doc/Doc.cls"
expect_clean "assert-concat" assert_concat "$ac_allowed"
# The line that is named is the first line of the assertion.
call_line=$(grep -n 'AssertTrue(x \[ "a"$' "$ac_bad_two_lines" | cut -d: -f1)
if [ "$(assert_concat "$ac_bad_two_lines")" != "$ac_bad_two_lines:$call_line" ]; then
  echo "FAIL assert-concat: the assertion that spans two lines is not named at its first line ($(assert_concat "$ac_bad_two_lines" | sed "s#$tmp/##"))"
  fails=$((fails + 1)); samples_ok=0
fi
# An entry that matches no assertion is reported; an entry that matches one reports nothing.
stale_out=$(STALE=1 assert_concat "$ac_good")
if [ "$stale_out" != "allow-list:OcuTalon.Zz.Allowed:Run" ]; then
  echo "FAIL assert-concat: the stale entry is not reported (got '$stale_out')"
  fails=$((fails + 1)); samples_ok=0
fi
if [ -n "$(STALE=1 assert_concat "$ac_allowed")" ]; then
  echo "FAIL assert-concat: an allowed assertion is flagged, or its entry is reported stale"
  fails=$((fails + 1)); samples_ok=0
fi
ALLOW_CONCAT=$real_allow_concat
if [ "$samples_ok" -eq 1 ]; then
  hits=$(
    IFS='
'
    set -f
    STALE=1 assert_concat $(scan_files src | grep '\.cls$') | name_stale
  )
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
    echo "FAIL assert-concat: no assertion compares with a concatenation to the right of [ or ], and each allow-list entry matches an assertion"
    fails=$((fails + 1))
  else
    echo "PASS assert-concat: no assertion compares with a concatenation to the right of [ or ], and each allow-list entry matches an assertion"
  fi
fi

# --- no-embedded-sql ---

es_bad=$(write_class es OcuTalon.Zz.EsBad 'ClassMethod A()' '{' '	&sql(SELECT 1 INTO :x FROM T)' '	&SQL (SELECT 2 INTO :y FROM T)' '	Set a = ##sql(SELECT 3 INTO :z FROM T)' '}' \
  'Query B(x As %String) As %SQLQuery(ROWSPEC = "y:%String") [ SqlProc ]' '{' 'SELECT y FROM T WHERE x = :x' '}' \
  'Query C() As %Library.SQLQuery' '{' 'SELECT 1 FROM T' '}')
es_good=$(write_class es OcuTalon.Zz.EsGood 'ClassMethod A()' '{' '	Set sc = statement.%Prepare("SELECT 1 FROM T")' '	Set text = "a &amp; sqlx and ##class(A.B).Sql()"' '	Quit 1' '}' \
  'Query B() As %Query(ROWSPEC = "y:%String")' '{' '}' 'Query C() As %SQLQueryCustom' '{' '}')
es_string=$(write_class es OcuTalon.Zz.EsString 'ClassMethod A(x)' '{' '	Set s = "&sql(SELECT 1 INTO :x FROM T)"' '	Do x.Matches($Char(9)_"&sql(DELETE FROM A.B)", "##sql(")' '	Set q = "a ""quoted"" &SQL ( text"' '	Quit 1' '}')
es_after=$(write_class es OcuTalon.Zz.EsAfter 'ClassMethod A()' '{' '	Set a = "&sql(" &sql(SELECT 1 INTO :x FROM T)' '}')
es_comment=$(write_class es OcuTalon.Zz.EsComment '/// Never write &sql( or ##sql( here.' 'ClassMethod A()' '{' '	// &sql(SELECT 1 INTO :x FROM T)' '	; &sql(SELECT 1 INTO :x FROM T)' '	Quit 1' '}')
samples_ok=1
expect_flagged "no-embedded-sql" embedded_sql "$es_bad" 5
expect_clean "no-embedded-sql" embedded_sql "$es_good"
expect_clean "no-embedded-sql" embedded_sql "$es_comment"
expect_clean "no-embedded-sql" embedded_sql "$es_string"
expect_flagged "no-embedded-sql" embedded_sql "$es_after" 1
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "no-embedded-sql: no &sql( and no %SQLQuery class query on a code line of src/" embedded_sql \
    "$es_bad" "$es_good" "$(scan_files src | grep -E '\.(cls|cos|inc|mac|int)$')"
fi

# --- trace-join ---

tj_bad1=$(write_class tj/src/ocutalon/cls OcuTalon/Core/ZzBad 'ClassMethod A()' '{' '	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc)' '}')
tj_bad2=$(write_class tj/src/ocutalon/cls OcuTalon/Web/ZzBadCase 'ClassMethod A()' '{' '	Set thread = ##class(ocutalon.core.TRACE).join(ref, .sc)' '}')
tj_bad3=$(write_class tj/src/ocutalon/cls OcuTalon/Channels/ZzBadPackage 'ClassMethod A()' '{' '	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc)' '}')
tj_good1=$(write_class tj/src/ocutalon/cls OcuTalon/Channel/WebChat/ZzOk 'ClassMethod A()' '{' '	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc, now)' '}')
tj_good2=$(write_class tj/src/ocutalon/cls OcuTalon/Test/Core/ZzOk 'ClassMethod A()' '{' '	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc)' '}')
tj_good3=$(write_class tj/src/ocutalon/cls OcuTalon/Core/ZzComment '/// Never call ##class(OcuTalon.Core.Trace).Join( from a Core class.' 'ClassMethod A()' '{' '	// ##class(OcuTalon.Core.Trace).Join(ref, .sc)' '	; ##class(OcuTalon.Core.Trace).Join(ref, .sc)' '	Quit 1' '}')
tj_good4=$(write_class tj/src/ocutalon/cls OcuTalon/Core/ZzOther 'ClassMethod A()' '{' '	Set sc = ##class(OcuTalon.Core.Trace).Started(ref, 5150)' '	Set sc = ##class(OcuTalon.Core.Trace).Position(id, .a, .b)' '	Quit ##class(OcuTalon.Core.TraceJoin).Join(ref)' '}')
samples_ok=1
for f in "$tj_bad1" "$tj_bad2" "$tj_bad3"; do expect_flagged "trace-join" trace_join "$f" 1; done
for f in "$tj_good1" "$tj_good2" "$tj_good3" "$tj_good4"; do expect_clean "trace-join" trace_join "$f"; done
if [ "$samples_ok" -eq 1 ]; then
  scan_rule "trace-join: OcuTalon.Core.Trace.Join is called only from OcuTalon.Channel and OcuTalon.Test" trace_join \
    "$tj_bad1" "$tj_good1" "$(scan_files src | grep -E '\.(cls|cos|inc|mac|int)$')"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-class-rules: $fails rule(s) failed"
  exit 1
fi
echo "test-class-rules: all rules passed"
