#!/usr/bin/env bash
# The release notes draft (Story 11.13; REL-8, REL-5, REL-6, NFR-24, CON-5; AD-22). It runs from the repository root, as the draft-notes
# step of Story 11.5's sequence, and only drafts: the author edits the file and publishes the notes by hand.
#   bash release/notes.sh --version <x.y.z> --rc <n> [--candidate <ref>] [--record <file>] [--eval <file>] [--notes <file>]
#                         [--areas <file>] [--replace]
# --candidate defaults to release/<v>-rc<n>; --record to `record_path <v> <rc>`; --eval to eval/release-candidate.json; --notes to
# `notes_path <v> <rc>` (the file that Story 11.4's checklist scans); --areas to release/notes-areas.txt beside this script. A relative
# path is relative to the repository root.
#
# Inputs. The sprint tracker and epics.md come from the candidate ref (git show), so the notes describe the candidate itself. The area
# mapping, the evaluation result and the record are files. The stories are those `done` in the candidate's tracker and not `done` in the
# tracker of the previous tag (release_previous_tag of lib-release.sh); with no previous tag (1.0.0) every `done` story. Each is listed by
# its title in epics.md. The record's "## Clean-machine rehearsal" and "## Upgrade harness" sections are copied, not rephrased. Every
# figure is an input's own; the script computes no claim of its own and does not judge the gates (Story 11.5's gates do).
#
# The draft (only `## ` sections, in this order; Story 11.5's update hook adds the online demo's section with record_write):
#   <!-- Drafted by release/notes.sh for OcuTalon <v> rc<n> at <sha>. Edit it before you publish it. -->
#   # OcuTalon <v>
#   the intro line: "This is the first release of OcuTalon." or "Changes since <tag>."
#   one `## <area>` section for each area that has a story, in the order of release/notes-areas.txt, with `- <title>` lines
#   ## How this release was checked   with ### Evaluation, ### Clean-machine rehearsal, ### Upgrade in place, ### IPM package (the size
#                                     line of the record's "## IPM artifact" and the result of its "## FR-57 job", copied; a section that is
#                                     not in the record is said so) and ### Registry install (the slot the author fills after publishing)
#   ## For admins and developers      with ### Stories about how OcuTalon is built and tested, ### Rehearsal runs (the record's
#                                     ### Runs table) and ### Upgrade checks (the upgrade table); a subsection with nothing is left out
# A class name, ##class( call or error code appears only in the "## For admins and developers" section.
#
# The rows, one `PASS|FAIL <id> <detail>` line each (a failure names a place as file:line, an epic or a tag, and never the text found):
#   stories    the tracker (and the previous tag's tracker) and epics.md are readable and at least one story is new
#   areas      every story's epic has an area, and every line of the mapping is a comment, blank, `epic <n> <area>` or `story <n>.<n> <area>`
#   eval       the --eval file is valid JSON of format ocutalon.evalResult/1 for the candidate's full sha
#   rehearsal  the record has the section, and its Candidate: line holds the candidate's full sha
#   upgrade    the same for the upgrade section
#   dev-only   names_outside_section "## For admins and developers" finds nothing in the draft
#   public-text  local_path and key_like find nothing in the draft (the checklist's own scans, without the tree-wide
#              test-boundaries.sh), and the inspiration's name appears only inside the not-affiliated note, which is the note word
#              for word or the name nowhere (the script builds the name from fragments, so its own text never spells it)
# then `NOTES <file>` and `RESULT <draft|dry run|fail>`. The two draft checks leave the draft in place for the author to fix.
# The result is
#   fail     when any row fails; otherwise
#   dry run  when any input is not from real mode (the evaluation's onMock is true, the rehearsal's Mode: is not "rehearsal", or the
#            upgrade's Mode: is not "release"); otherwise
#   draft.
# Exit codes: 0 draft; 1 fail; 3 dry run; 2 a refusal with nothing written (an unknown option, a missing --version or --rc, a version
# that is not x.y.z or differs from src/module.xml at the candidate, an rc that is not a positive whole number, an unknown candidate,
# a shallow repository, no git repository, an option whose value is missing or starts with "-", a notes file that is the record, the
# evaluation result, the mapping or a tracked file, or an existing notes file without --replace). Story 11.5 reads RESULT.
# The script writes the notes file (through a temporary file beside it) and nothing else: never the record, the evaluation result or a
# tracked file. It makes no network call and publishes, posts, tags and pushes nothing. It needs bash 3.2, git, awk and node (the JSON is
# read from the file path given as an argument; a missing node fails the eval row).
#
# Sourced, it defines these functions and runs nothing (each prints on stdout; "!" lines are problems):
#   notes_stories <candidate> <previous>   `id|key|title` lines (title empty without a heading); a story of the candidate is new when
#                                          its id <e>.<s> is not done at <previous>, whatever its slug; returns 1 with no tracker, 3 with
#                                          no tracker at <previous>, 4 with no or an empty epics.md
#   notes_areas <areas file> <stories file> [<name>]
#                                          `area|id|title` lines in the notes' order, `developer` for a developer story (id empty and
#                                          title the key for a story without a heading); `!bad|file:line`, `!unmapped|<epic>`, `!missing|`
#   notes_section <record> <heading>       one `## ` section's lines (the heading line included)
#   notes_eval <file> <sha> [<detail file>]    the ### Evaluation subsection; returns 0, 1 (not available) or 3 (on the mock)
#   notes_rehearsal <record> <sha> [<detail file>] / notes_upgrade <record> <sha> [<detail file>]
#                                          the ### Clean-machine rehearsal / ### Upgrade in place subsection; returns 0, 1 or 3 (not real)
#   notes_rehearsal_runs <record> / notes_upgrade_rows <record>   the developer tables, verbatim (nothing when absent)
#   notes_draft <work dir> <version> <rc> <sha>   the whole document, from the files intro.txt, areas.txt, eval.md, rehearsal.md,
#                                          upgrade.md, runs.md and rows.md of the work dir
#   notes_name_hits <file>...              file:line of each line that holds the inspiration's name outside the not-affiliated note
#   notes_result <results file>            draft, dry run or fail, from `id|pass|fail|dry|detail` lines
umask 077

notes_self=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$notes_self/release/lib-release.sh"
. "$notes_self/docker/tests/lib-scan.sh"
. "$notes_self/docker/tests/lib-keys.sh"

NOTES_TRACKER=_bmad-output/implementation-artifacts/sprint-status.yaml
NOTES_EPICS=_bmad-output/planning-artifacts/epics.md
NOTES_DEV_HEADING='## For admins and developers'
NOTES_FORMAT='ocutalon.evalResult/1'
NOTES_REGISTRY_SLOT="Not run yet. After this version is published to the package registry, the guide's two commands are run once against the registry on a clean build 154 instance, and the result is recorded here."
NOTES_ROWS="stories areas eval rehearsal upgrade dev-only public-text"

# The inspiration's name and its not-affiliated note, assembled here so that this file never spells the name.
notes_name="Open""Claw"
notes_note="OcuTalon is inspired by $notes_name and is not affiliated with or endorsed by the $notes_name Foundation."

# The evaluation result, read by node from the file path (argument 1) and the candidate's sha (argument 2). The first line is OK, MOCK or
# BAD <reason>; the rest is the subsection.
NOTES_EVAL_JS=$(cat << 'EOJ'
const fs = require('node:fs');
const [file, sha] = process.argv.slice(1);
const bad = (why) => {
  console.log('BAD ' + why);
  process.exit(0);
};
if (!fs.existsSync(file)) bad('there is no evaluation result at that path');
let r;
try {
  r = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (e) {
  bad('the evaluation result is not valid JSON');
}
if (r === null || typeof r !== 'object' || Array.isArray(r)) bad('the evaluation result is not a JSON object');
if (r.format !== 'ocutalon.evalResult/1') bad('the evaluation result is of another format');
if (r.commit !== sha) bad('the evaluation result is of another commit');
if (typeof r.onMock !== 'boolean') bad('the evaluation result does not say whether it ran on the mock');
if (typeof r.verdict !== 'string' || r.verdict === '') bad('the evaluation result has no verdict');
const clean = (v) => String(v).replace(/\s+/g, ' ').replace(/[^\x20-\x7e]/g, '?').trim();
const isNum = (v) => typeof v === 'number' && isFinite(v);
const NM = 'not measured';
const sum = r.summary && typeof r.summary === 'object' ? r.summary : {};
const scores = sum.scores && typeof sum.scores === 'object' ? sum.scores : {};
const rows = [
  ['items', 'Items decided right'],
  ['incidents', 'Incidents diagnosed right'],
  ['heldOutItems', 'Held-out items decided right'],
  ['heldOutIncidents', 'Held-out incidents diagnosed right'],
  ['injections', 'Injection attempts handled safely'],
  ['heldOutInjections', 'Held-out injection attempts handled safely'],
  ['allClear', 'All-clear answers right'],
  ['commands', 'Command requests answered right'],
];
const out = [r.onMock ? 'MOCK' : 'OK', '### Evaluation', '', 'Result: ' + clean(r.verdict)];
if (r.onMock) out.push('', "Note: The CI mock stood in for the model, so these figures are not the release's.");
out.push('', '| Measure | Right | Of | Share | Target |', '| --- | --- | --- | --- | --- |');
for (const [key, label] of rows) {
  const s = scores[key] && typeof scores[key] === 'object' ? scores[key] : {};
  const right = isNum(s.right) ? String(s.right) : NM;
  const total = isNum(s.total) ? String(s.total) : NM;
  const share = isNum(s.share) ? (s.share * 100).toFixed(1) + '%' : NM;
  const target = isNum(s.target) ? Math.round(s.target * 100) + '%' : '-';
  out.push('| ' + label + ' | ' + right + ' | ' + total + ' | ' + share + ' | ' + target + ' |');
}
const cost = sum.attentionCost && typeof sum.attentionCost === 'object' ? sum.attentionCost : {};
const usd = (v) => (isNum(v) ? '$' + v.toFixed(4) : NM);
const size = sum.size && typeof sum.size === 'object' ? sum.size : {};
const tokens = isNum(size.largestTokens) ? String(size.largestTokens).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ' tokens' : NM;
out.push('', '- Cost per attention decision: mean ' + usd(cost.meanUSD) + ', highest ' + usd(cost.maxUSD) + '.');
out.push('- Largest model request: ' + tokens + '.');
const ov = r.override && typeof r.override === 'object' ? r.override : null;
if (r.verdict === 'overridden' || ov) {
  const why = ov && typeof ov.reason === 'string' && ov.reason.trim() !== '' ? clean(ov.reason) : 'not recorded';
  out.push('- Override: the author overrode a blocked result. Reason: ' + why);
} else {
  out.push('- Override: none.');
}
console.log(out.join('\n'));
EOJ
)

# --- the stories and the areas ---

# notes_stories <candidate> <previous>: see the header.
notes_stories() {
  local cand=$1 prev=${2:-} d
  d=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-nst.XXXXXX") || return 1
  if ! git show "$cand:$NOTES_TRACKER" > "$d/cand.yaml" 2> /dev/null; then
    rm -rf "$d"
    return 1
  fi
  : > "$d/prev.yaml"
  if [ -n "$prev" ] && ! git show "$prev:$NOTES_TRACKER" > "$d/prev.yaml" 2> /dev/null; then
    rm -rf "$d"
    return 3
  fi
  if ! git show "$cand:$NOTES_EPICS" > "$d/epics.md" 2> /dev/null || [ ! -s "$d/epics.md" ]; then
    rm -rf "$d"
    return 4
  fi
  awk -v cand="$d/cand.yaml" -v prev="$d/prev.yaml" -v epics="$d/epics.md" '
    function done_keys(file, set, list,   line, k, n) {
      n = 0
      while ((getline line < file) > 0) {
        if (line ~ /^  [0-9]+-[0-9]+-[^ :]+:[ \t]*done[ \t\r]*(#.*)?$/) {
          k = line
          sub(/^  /, "", k)
          sub(/:.*$/, "", k)
          split(k, p, "-")
          set[p[1] "." p[2]] = 1
          list[++n] = k
        }
      }
      close(file)
      return n
    }
    BEGIN {
      ndone = done_keys(cand, cset, clist)
      done_keys(prev, pset, plist)
      for (i = 1; i <= ndone; i++) {
        k = clist[i]
        split(k, p, "-")
        id = p[1] "." p[2]
        if (id in pset) continue
        if (!(id in want)) { want[id] = k; order[++no] = id }
      }
      while ((getline line < epics) > 0) {
        if (line !~ /^### Story [0-9]+\.[0-9]+: /) continue
        s = line
        sub(/^### Story /, "", s)
        c = index(s, ":")
        id = substr(s, 1, c - 1)
        title = substr(s, c + 1)
        sub(/^[ \t]+/, "", title)
        sub(/[ \t\r]+$/, "", title)
        if ((id in want) && !(id in used)) { used[id] = 1; print id "|" want[id] "|" title }
      }
      for (i = 1; i <= no; i++) if (!(order[i] in used)) print order[i] "|" want[order[i]] "|"
    }'
  rm -rf "$d"
  return 0
}

# notes_areas <areas file> <stories file> [<name>]: see the header. <name> is how the mapping file is named in a file:line.
notes_areas() {
  local areas=$1 stories=$2 name=${3:-$1}
  if [ ! -f "$areas" ]; then
    echo "!missing|"
    return 0
  fi
  awk -v areas="$areas" -v stories="$stories" -v disp="$name" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function note(a) { if (a != "developer" && !(a in seen)) { seen[a] = 1; order[++na] = a } }
    BEGIN {
      while ((getline line < areas) > 0) {
        ln++
        t = line
        sub(/\r$/, "", t)
        if (t ~ /^[ \t]*(#.*)?$/) continue
        if (t ~ /^epic [0-9]+ +[^ \t]/) {
          split(t, p, " ")
          e = p[2]
          text = trim(substr(t, 5 + length(e) + 1))
          epic[e + 0] = text
          note(text)
          continue
        }
        if (t ~ /^story [0-9]+\.[0-9]+ +[^ \t]/) {
          split(t, p, " ")
          id = p[2]
          text = trim(substr(t, 6 + length(id) + 1))
          split(id, q, ".")
          story[(q[1] + 0) "." (q[2] + 0)] = text
          note(text)
          continue
        }
        print "!bad|" disp ":" ln
      }
      close(areas)
      while ((getline sl < stories) > 0) {
        i1 = index(sl, "|")
        id = substr(sl, 1, i1 - 1)
        rest = substr(sl, i1 + 1)
        i2 = index(rest, "|")
        key = substr(rest, 1, i2 - 1)
        title = substr(rest, i2 + 1)
        split(id, q, ".")
        e = q[1] + 0
        s = q[2] + 0
        sid = e "." s
        if (sid in story) a = story[sid]
        else if (title == "" || s == 0 || title ~ /^Epic [0-9]+ burn-down$/) a = "developer"
        else if (e in epic) a = epic[e]
        else {
          if (!(e in unm)) { unm[e] = 1; ul[++nu] = e }
          continue
        }
        if (title == "") rec = "|" key
        else rec = id "|" title
        if (a == "developer") dev[++nd] = rec
        else { cnt[a]++; row[a, cnt[a]] = rec }
      }
      for (i = 1; i <= na; i++) for (k = 1; k <= cnt[order[i]]; k++) print order[i] "|" row[order[i], k]
      for (i = 1; i <= nd; i++) print "developer|" dev[i]
      for (i = 1; i <= nu; i++) print "!unmapped|" ul[i]
    }'
}

# --- the record's sections ---

# notes_section <record> <heading>: see the header.
notes_section() {
  awk -v h="$2" '
    { t = $0; sub(/[ \t\r]+$/, "", t) }
    !inside && t == h { inside = 1; print; next }
    inside && (/^## / || /^# /) { exit }
    inside { print }' "$1" 2> /dev/null
}

# notes_table <first|runs>: reads a section on stdin; prints its first table (before any ### heading) or the table under ### Runs.
notes_table() {
  awk -v which="$1" '
    which == "first" && /^### / { exit }
    which == "runs" && /^### / { inr = ($0 ~ /^### Runs[ \t\r]*$/); next }
    (which == "first" || inr) && /^\|/ { print; started = 1; next }
    started { exit }'
}

# notes_line <prefix>: reads a section on stdin; prints its first line that starts with the prefix.
notes_line() { grep -m 1 -e "^$1" || true; }

# notes_bad <detail file> <detail> <heading> <not available line>: the subsection of a failed input.
notes_bad() {
  if [ -n "$1" ]; then printf '%s\n' "$2" > "$1"; fi
  printf '%s\n\n%s\n' "$3" "$4"
  return 1
}

# notes_eval <file> <sha> [<detail file>]: see the header.
notes_eval() {
  local file=$1 sha=$2 df=${3:-} out first h='### Evaluation' na='Not available: no evaluation result for this candidate.'
  if ! command -v node > /dev/null 2>&1; then
    notes_bad "$df" "node is not installed, so the evaluation result cannot be read" "$h" "$na"
    return
  fi
  out=$(node -e "$NOTES_EVAL_JS" "$file" "$sha" 2> /dev/null)
  first=$(printf '%s\n' "$out" | head -n 1)
  case $first in
    OK | MOCK)
      printf '%s\n' "$out" | sed 1d
      [ "$first" = OK ] && return 0
      return 3
      ;;
    BAD\ *)
      notes_bad "$df" "${first#BAD }" "$h" "$na"
      return
      ;;
  esac
  notes_bad "$df" "the evaluation result could not be read" "$h" "$na"
}

# notes_record_part <record> <sha> <heading> <subsection heading> <not available line> <real mode> <detail file> <table: 1 or 0>
#                   <line prefix>...
# The shared part of notes_rehearsal and notes_upgrade: checks the section and copies the named lines and, with table 1, its first table.
notes_record_part() {
  local rec=$1 sha=$2 heading=$3 sub=$4 na=$5 real=$6 df=$7 table=$8 sec cand mode p l
  shift 8
  if [ ! -f "$rec" ]; then
    notes_bad "$df" "there is no record at that path" "$sub" "$na"
    return
  fi
  sec=$(notes_section "$rec" "$heading")
  if [ -z "$sec" ]; then
    notes_bad "$df" "the record has no $heading section" "$sub" "$na"
    return
  fi
  cand=$(printf '%s\n' "$sec" | notes_line 'Candidate:')
  case $cand in
    *"$sha"*) ;;
    *)
      notes_bad "$df" "the Candidate: line of the section does not hold the candidate's full sha" "$sub" "$na"
      return
      ;;
  esac
  mode=$(printf '%s\n' "$sec" | notes_line 'Mode:')
  mode=${mode#Mode:}
  mode=$(printf '%s' "$mode" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ -z "$mode" ] || [ -z "$(printf '%s\n' "$sec" | notes_line 'Result:')" ]; then
    notes_bad "$df" "the section has no Result: or Mode: line" "$sub" "$na"
    return
  fi
  printf '%s\n' "$sub"
  for p in "$@"; do
    l=$(printf '%s\n' "$sec" | notes_line "$p")
    [ -z "$l" ] || printf '\n%s\n' "$l"
  done
  if [ "$table" = 1 ]; then
    l=$(printf '%s\n' "$sec" | notes_table first)
    [ -z "$l" ] || printf '\n%s\n' "$l"
  fi
  [ "$mode" = "$real" ] && return 0
  return 3
}

notes_rehearsal() {
  notes_record_part "$1" "$2" '## Clean-machine rehearsal' '### Clean-machine rehearsal' \
    'Not available: no clean-machine rehearsal for this candidate.' rehearsal "${3:-}" 1 'Result:' 'Mode:' 'Clean host:' 'Driver host:'
}

notes_upgrade() {
  notes_record_part "$1" "$2" '## Upgrade harness' '### Upgrade in place' 'Not available: no upgrade result for this candidate.' release \
    "${3:-}" 0 'Result:' 'Mode:' 'Previous:' 'Note:'
}

# notes_ipm <record>: "### IPM package" (the size line of the record's "## IPM artifact" and the result line of its "## FR-57 job", copied; a
# section or line that is not in the record says so) and "### Registry install", whose slot the author fills after publishing the package.
notes_ipm() {
  local size result
  size=$(notes_section "$1" '## IPM artifact' | sed -n 's/^Size:[[:space:]]*//p' | head -n 1)
  result=$(notes_section "$1" '## FR-57 job' | sed -n 's/^Result:[[:space:]]*//p' | head -n 1)
  printf '### IPM package\n\n'
  if [ -n "$size" ]; then printf 'IPM artifact size: %s\n' "$size"; else printf 'IPM artifact size: not in the record.\n'; fi
  printf '\n'
  if [ -n "$result" ]; then printf 'IPM install check: %s\n' "$result"; else printf 'IPM install check: not in the record.\n'; fi
  printf '\n### Registry install\n\n%s\n' "$NOTES_REGISTRY_SLOT"
}

# notes_rehearsal_runs <record> / notes_upgrade_rows <record>: the developer tables, verbatim.
notes_rehearsal_runs() { notes_section "$1" '## Clean-machine rehearsal' | notes_table runs; }
notes_upgrade_rows() { notes_section "$1" '## Upgrade harness' | notes_table first; }

# --- the draft ---

notes_draft() {
  local w=$1 v=$2 rc=$3 sha=$4
  printf '<!-- Drafted by release/notes.sh for OcuTalon %s rc%s at %s. Edit it before you publish it. -->\n' "$v" "$rc" "$sha"
  printf '# OcuTalon %s\n\n' "$v"
  cat "$w/intro.txt"
  awk -F'|' '$1 != "developer" {
    if ($1 != cur) { cur = $1; printf "\n## %s\n\n", cur }
    print "- " substr($0, length($1) + length($2) + 3)
  }' "$w/areas.txt"
  printf '\n## How this release was checked\n\n'
  cat "$w/eval.md"
  printf '\n'
  cat "$w/rehearsal.md"
  printf '\n'
  cat "$w/upgrade.md"
  printf '\n'
  cat "$w/ipm.md"
  printf '\n%s\n' "$NOTES_DEV_HEADING"
  if awk -F'|' '$1 == "developer" { f = 1 } END { exit !f }' "$w/areas.txt"; then
    printf '\n### Stories about how OcuTalon is built and tested\n\n'
    awk -F'|' '$1 == "developer" { print "- " ($2 != "" ? $2 " " : "") substr($0, length($1) + length($2) + 3) }' "$w/areas.txt"
  fi
  if [ -s "$w/runs.md" ]; then
    printf '\n### Rehearsal runs\n\n'
    cat "$w/runs.md"
  fi
  if [ -s "$w/rows.md" ]; then
    printf '\n### Upgrade checks\n\n'
    cat "$w/rows.md"
  fi
}

# notes_name_hits <file>...: see the header.
notes_name_hits() {
  awk -v note="$notes_note" -v name="$(printf '%s' "$notes_name" | tr 'A-Z' 'a-z')" '
    {
      t = $0
      while ((i = index(t, note)) > 0) t = substr(t, 1, i - 1) substr(t, i + length(note))
      if (index(tolower(t), name) > 0) print FILENAME ":" FNR
    }' "$@"
}

# notes_result <results file>: see the header.
notes_result() {
  if grep -q '^[^|]*|fail|' "$1"; then
    echo fail
  elif grep -q '^[^|]*|dry|' "$1"; then
    echo "dry run"
  else
    echo draft
  fi
}

# --- the run ---

notes_refuse() {
  echo "REFUSED $*"
  return 2
}

# notes_rel <path>: the path relative to the repository root when it is inside it.
notes_rel() {
  case $1 in
    "$notes_self"/*) printf '%s\n' "${1#"$notes_self"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# notes_add <id> <pass|fail|dry> <detail> [<hits, one per line>]: one row of the results (hits go to a file of their own).
notes_add() {
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$nt_work/results"
  if [ -n "${4:-}" ]; then printf '%s\n' "$4" > "$nt_work/hits.$1"; fi
}

notes_print_rows() {
  local id st detail
  for id in $NOTES_ROWS; do
    IFS='|' read -r _ st detail < <(grep -m 1 "^$id|" "$nt_work/results")
    case $st in
      fail) echo "FAIL $id $detail" ;;
      *) echo "PASS $id $detail" ;;
    esac
    if [ "$st" = fail ] && [ -f "$nt_work/hits.$id" ]; then head -n 10 "$nt_work/hits.$id" | sed 's/^/  /'; fi
  done
}

notes_usage() {
  echo "usage: release/notes.sh --version <x.y.z> --rc <n> [--candidate <ref>] [--record <file>] [--eval <file>] [--notes <file>] [--areas <file>] [--replace]"
}

notes_main() {
  local o_version="" o_rc="" o_candidate="" o_record="" o_eval="" o_notes="" o_areas="" replace=0
  local mv sha cand record evalf notes areas prev rc n dir tmpdraft result shown line hits lines detail
  while [ $# -gt 0 ]; do
    case $1 in
      --replace)
        replace=1
        shift
        ;;
      --version | --rc | --candidate | --record | --eval | --notes | --areas)
        if [ $# -lt 2 ] || [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
          notes_refuse "$1 needs a value"
          return 2
        fi
        case $1 in
          --version) o_version=$2 ;;
          --rc) o_rc=$2 ;;
          --candidate) o_candidate=$2 ;;
          --record) o_record=$2 ;;
          --eval) o_eval=$2 ;;
          --notes) o_notes=$2 ;;
          --areas) o_areas=$2 ;;
        esac
        shift 2
        ;;
      *)
        notes_refuse "unknown option '$1'"
        return 2
        ;;
    esac
  done
  if [ -z "$o_version" ] || [ -z "$o_rc" ]; then
    notes_refuse "$(notes_usage)"
    return 2
  fi
  if ! printf '%s\n' "$o_version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$'; then
    notes_refuse "--version $o_version is not x.y.z"
    return 2
  fi
  if ! printf '%s\n' "$o_rc" | grep -Eq '^[1-9][0-9]*$'; then
    notes_refuse "--rc $o_rc is not a positive whole number"
    return 2
  fi
  cd "$notes_self" || return 2
  if [ "$(git rev-parse --show-toplevel 2> /dev/null)" != "$notes_self" ]; then
    notes_refuse "$notes_self is not the root of a git repository"
    return 2
  fi
  if [ "$(git rev-parse --is-shallow-repository 2> /dev/null)" = true ]; then
    notes_refuse "the repository is shallow: fetch its full history first"
    return 2
  fi
  cand=${o_candidate:-release/$o_version-rc$o_rc}
  if ! sha=$(git rev-parse --verify --quiet "$cand^{commit}"); then
    notes_refuse "the candidate '$cand' is not a commit of this repository"
    return 2
  fi
  mv=$(git show "$sha:src/module.xml" 2> /dev/null | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -n 1)
  if [ "$mv" != "$o_version" ]; then
    notes_refuse "--version $o_version is not the version of src/module.xml at the candidate (${mv:-none})"
    return 2
  fi
  record=${o_record:-$(record_path "$o_version" "$o_rc")}
  evalf=${o_eval:-eval/release-candidate.json}
  notes=${o_notes:-$(notes_path "$o_version" "$o_rc")}
  areas=${o_areas:-$notes_self/release/notes-areas.txt}
  for n in record evalf notes areas; do
    case ${!n} in /*) ;; *) printf -v "$n" '%s' "$notes_self/${!n}" ;; esac
  done
  dir=$(dirname "$notes")
  if [ -e "$notes" ] && [ ! -f "$notes" ]; then
    notes_refuse "the notes path '${o_notes:-$notes}' is not a file"
    return 2
  fi
  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    notes_refuse "the notes folder is not a folder"
    return 2
  fi
  for n in record evalf areas; do
    if [ -e "$notes" ] && [ -e "${!n}" ] && [ "$notes" -ef "${!n}" ]; then
      notes_refuse "the notes file is the same file as the input $(notes_rel "${!n}")"
      return 2
    fi
  done
  if git ls-files --error-unmatch -- "$notes" > /dev/null 2>&1; then
    notes_refuse "the notes file $(notes_rel "$notes") is a tracked file of the repository"
    return 2
  fi
  if [ -f "$notes" ] && [ "$replace" -eq 0 ]; then
    notes_refuse "the notes file $(notes_rel "$notes") exists; give --replace to rewrite it"
    return 2
  fi
  nt_work=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-notes.XXXXXX" 2> /dev/null) || {
    notes_refuse "no temporary folder for the run"
    return 2
  }
  nt_tmpdraft=""
  trap 'rm -rf "$nt_work"; [ -z "$nt_tmpdraft" ] || rm -f "$nt_tmpdraft"' EXIT
  : > "$nt_work/results"

  # the stories
  prev=$(release_previous_tag "$sha" "$o_version")
  notes_stories "$sha" "$prev" > "$nt_work/stories.txt"
  rc=$?
  n=$(grep -c . "$nt_work/stories.txt")
  if [ "$rc" -eq 1 ]; then
    : > "$nt_work/stories.txt"
    notes_add stories fail "the candidate has no sprint tracker at $NOTES_TRACKER"
  elif [ "$rc" -eq 3 ]; then
    : > "$nt_work/stories.txt"
    notes_add stories fail "the previous tag $prev has no sprint tracker"
  elif [ "$rc" -eq 4 ]; then
    : > "$nt_work/stories.txt"
    notes_add stories fail "the candidate has no story titles at $NOTES_EPICS"
  elif [ "$n" -eq 0 ]; then
    if [ -n "$prev" ]; then
      notes_add stories fail "no story is done at the candidate and not done at $prev"
    else
      notes_add stories fail "no story is done at the candidate"
    fi
  elif [ -n "$prev" ]; then
    notes_add stories pass "$n stories are new since $prev"
  else
    notes_add stories pass "$n stories, all of them, for the first release"
  fi
  if [ -n "$prev" ]; then
    printf 'Changes since %s.\n' "$prev" > "$nt_work/intro.txt"
  else
    printf 'This is the first release of OcuTalon.\n' > "$nt_work/intro.txt"
  fi

  # the areas
  notes_areas "$areas" "$nt_work/stories.txt" "$(notes_rel "$areas")" > "$nt_work/areas.out"
  grep -v '^!' "$nt_work/areas.out" > "$nt_work/areas.txt"
  hits=$(sed -n 's/^!bad|//p' "$nt_work/areas.out")
  lines=$(sed -n 's/^!unmapped|//p' "$nt_work/areas.out" | sed 's/^/epic /' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  if grep -q '^!missing|' "$nt_work/areas.out"; then
    notes_add areas fail "the area mapping $(notes_rel "$areas") is missing"
  elif [ -n "$hits" ] || [ -n "$lines" ]; then
    detail=""
    [ -z "$lines" ] || detail="no area for $lines"
    [ -z "$hits" ] || detail="${detail:+$detail; }a line of the mapping is not a comment, an epic line or a story line"
    notes_add areas fail "$detail" "$hits"
  else
    notes_add areas pass "$(grep -v '^developer|' "$nt_work/areas.txt" | cut -d'|' -f1 | sort -u | grep -c .) areas and $(grep -c '^developer|' "$nt_work/areas.txt") developer stories"
  fi

  # the evaluation, the rehearsal and the upgrade
  notes_eval "$evalf" "$sha" "$nt_work/detail" > "$nt_work/eval.md"
  rc=$?
  case $rc in
    0) notes_add eval pass "the evaluation summary of the candidate is in the draft" ;;
    3) notes_add eval dry "the evaluation ran on the CI mock: a dry run" ;;
    *) notes_add eval fail "$(cat "$nt_work/detail")" ;;
  esac
  notes_rehearsal "$record" "$sha" "$nt_work/detail" > "$nt_work/rehearsal.md"
  rc=$?
  case $rc in
    0) notes_add rehearsal pass "the rehearsal's lines and table are in the draft" ;;
    3) notes_add rehearsal dry "the rehearsal is not a real rehearsal: a dry run" ;;
    *) notes_add rehearsal fail "$(cat "$nt_work/detail")" ;;
  esac
  : > "$nt_work/runs.md"
  [ "$rc" -eq 1 ] || notes_rehearsal_runs "$record" > "$nt_work/runs.md"
  notes_upgrade "$record" "$sha" "$nt_work/detail" > "$nt_work/upgrade.md"
  rc=$?
  case $rc in
    0) notes_add upgrade pass "the upgrade result is in the draft" ;;
    3) notes_add upgrade dry "the upgrade result is not a release-mode result: a dry run" ;;
    *) notes_add upgrade fail "$(cat "$nt_work/detail")" ;;
  esac
  : > "$nt_work/rows.md"
  [ "$rc" -eq 1 ] || notes_upgrade_rows "$record" > "$nt_work/rows.md"
  notes_ipm "$record" > "$nt_work/ipm.md"

  # the draft, then its two checks
  if ! mkdir -p "$dir" || ! tmpdraft=$(mktemp "$dir/.notes-draft.XXXXXX" 2> /dev/null); then
    notes_refuse "the notes folder cannot be written"
    return 2
  fi
  nt_tmpdraft=$tmpdraft
  (set -e; notes_draft "$nt_work" "$o_version" "$o_rc" "$sha") > "$tmpdraft"
  if [ $? -ne 0 ]; then
    notes_refuse "the draft could not be written"
    return 2
  fi
  mv "$tmpdraft" "$notes" || {
    rm -f "$tmpdraft"
    notes_refuse "the notes file cannot be written"
    return 2
  }
  shown=${o_notes:-$(notes_path "$o_version" "$o_rc")}
  hits=$(names_outside_section "$NOTES_DEV_HEADING" "$notes" | while IFS= read -r line; do notes_rel "$line"; done)
  if [ -z "$hits" ]; then
    notes_add dev-only pass "no class name, ##class( call or error code outside the developer section"
  else
    notes_add dev-only fail "a class name, call or error code is outside the developer section" "$hits"
  fi
  hits=$({ local_path "$notes"; key_like "$notes"; notes_name_hits "$notes"; } | sort -u | while IFS= read -r line; do notes_rel "$line"; done)
  if [ -z "$hits" ]; then
    notes_add public-text pass "the draft holds no local path, key-like text or name outside the not-affiliated note"
  else
    notes_add public-text fail "the draft holds a local path, key-like text or a name outside the not-affiliated note" "$hits"
  fi

  result=$(notes_result "$nt_work/results")
  notes_print_rows
  echo "NOTES $shown"
  echo "RESULT $result"
  case $result in
    draft) return 0 ;;
    fail) return 1 ;;
  esac
  return 3
}

[ "${BASH_SOURCE[0]}" != "$0" ] && return 0
notes_main "$@"
exit $?
