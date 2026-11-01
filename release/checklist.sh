#!/usr/bin/env bash
# The release checklist (Story 11.4; CON-2, CON-5, UX-DR16, UX-DR28, DW-359, REL-11). It runs on the checkout of a release candidate,
# from the repository root, and is the checklist gate of Story 11.5's sequence:
#   bash release/checklist.sh --version <x.y.z> --rc <n> [--candidate <ref>] [--record <file>] [--notes <file>]
# --record defaults to `record_path <v> <rc>` (release/records/<v>/rc<n>.md) and --notes to `notes_path <v> <rc>`
# (release/records/<v>/rc<n>-notes.md, the draft notes that Story 11.13 writes). A relative path is relative to the repository root.
# --candidate <ref> must name the commit that is checked out (HEAD).
#
# The automated rows, each one PASS or FAIL line (a failure names file:line, a count or a rule, and never the text found):
#   checkout           no change outside release/records/ in `git status`, untracked files that are not ignored included
#   note-readme        a line of README.md equals the not-affiliated note word for word
#   note-about         the About dialog's source (web/src/app/about/about-dialog.ts, as a <p> line) and one main-*.js of the built page
#                      hold the note; with no built page only the source is checked, and the detail says so
#   product-name       no product name holds the inspiration's name: the first line of README.md, <Name> of src/module.xml, "name" of
#                      web/package.json, <title> of web/src/index.html and name: of docker-compose.yml
#   name-only-in-note  in every file of scan_files (except under _bmad-output/ and _bmad/, and docker/tests/test-readme.sh) a line that
#                      holds the name holds it only inside the note
#   licences           every file of web/public/assets/licenses/ is non-empty; docker/ipm/LICENSE holds the lines "MIT License" and
#                      "Copyright (c) 2019 InterSystems Developer Community"; with the built page, 3rdpartylicenses.txt holds
#                      "Package: <name>" for each dependency of web/package.json that a non-spec web/src/**/*.ts file imports, and
#                      assets/licenses/ holds the same non-empty files as the source folder
#   web-bundle         src/ocutalon/csp/index.html exists (Story 11.5 commits the built page on the candidate branch)
#   readme             docker/tests/test-readme.sh exits 0 (its note, links, anchors and heading slugs are checked offline)
#   public-text        docker/tests/test-boundaries.sh exits 0 (Epic 0's public-text check of the tree), and local_path and key_like find
#                      nothing in the draft notes; a missing notes file fails
#   iris-source        irislib/ and irissys/ are ignored, and no tracked path has an irislib/ or irissys/ component or a component that
#                      starts with a percent sign
#   no-outward         no script of release/, ci/, eval/ or docker/, install.sh or workflow publishes a release, changes the repository's
#                      visibility or settings, or names a public site that posts are made to
# The author's rows, which only the author's own line confirms. They are read from the record's "## Author confirmations" section, one
# line each, in this form and no other (the date is a real calendar date; the text after it is optional):
#   - <id>: confirmed <YYYY-MM-DD>[ <text>]
# with <id> one of no-copied-code, no-artwork, no-ai-hub-copy, public-review and public-links. A row that the record does not confirm
# reads "not confirmed", and a CONFIRM line prints the line to add. This script never writes that section and never confirms a row.
#
# It writes the section "## Release checklist" into the record through record_write (replacing its own section, or appending it) and
# prints RECORD <file> and RESULT <result>. The section holds Result:, Candidate: (the version, the rc and the full sha of HEAD),
# Notes:, Run:, Author's actions:, and a table of Item, Result and Detail. The result is
#   fail           when any automated row fails; otherwise
#   not confirmed  while any author row is not confirmed; otherwise
#   pass.
# Story 11.5 accepts exit 0 with "Result: pass" only.
# Exit codes: 0 pass; 1 fail or not confirmed; 2 a refusal (usage, version, rc, candidate or record), with nothing written.
# The script makes no network call. Sourced, it defines the row functions and runs nothing; Story 11.13 runs, from the repository root,
# row_public_text <its draft notes file> on its draft.
umask 077

ck_self=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$ck_self/release/lib-release.sh"
. "$ck_self/docker/tests/lib-scan.sh"
. "$ck_self/docker/tests/lib-keys.sh"

CK_NOTE='OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.'
CK_NAME_ERE='[o]pen[c]law'
CK_CSP=src/ocutalon/csp
CK_LICENSES=web/public/assets/licenses
CK_AUTHOR_IDS="no-copied-code no-artwork no-ai-hub-copy public-review public-links"
CK_AUTHOR_ACTIONS="Posts, articles, the video and bonus claims are the author's actions, done by hand. No script or workflow posts anything or claims a bonus."

# --- the results ---

# ck_add <id> <result> <detail>: one line of the results file (id|result|detail).
ck_add() {
  [ -n "${ck_results:-}" ] || return 0
  printf '%s|%s|%s\n' "$1" "$2" "$(printf '%s' "$3" | detail_clean)" >> "$ck_results"
}

ck_pass_text() {
  case $1 in
    checkout) echo "the checkout is the candidate commit, with no uncommitted change outside release/records/" ;;
    note-readme) echo "README.md holds the not-affiliated note word for word" ;;
    note-about) echo "the About dialog's source and the built page hold the note word for word" ;;
    product-name) echo "no product name holds the name from the note" ;;
    name-only-in-note) echo "outside the planning files, the name appears only in the note" ;;
    licences) echo "every font, icon and package licence notice is present" ;;
    web-bundle) echo "the built web bundle is in the checkout" ;;
    readme) echo "docker/tests/test-readme.sh passed: README links, anchors and headings checked offline" ;;
    public-text) echo "docker/tests/test-boundaries.sh passed, and the draft notes hold no local path or key-like text" ;;
    iris-source) echo "irislib/ and irissys/ are ignored, and none of their files is tracked" ;;
    no-outward) echo "no script or workflow publishes a release, changes the repository's settings or posts to a public site" ;;
  esac
}

ck_author_text() {
  case $1 in
    no-copied-code) echo "No code, prompts or workflows are copied from the project named in the not-affiliated note, or from a project like it." ;;
    no-artwork) echo "None of that project's logo or artwork is used." ;;
    no-ai-hub-copy) echo "Nothing is copied from InterSystems' published AI Hub examples." ;;
    public-review) echo "Before the repository went public, the author reviewed every planning file under _bmad-output/ and the agent instructions (CLAUDE.md and the .claude/ and _bmad/ folders) for keys, local machine paths, private infrastructure details and names of other contest entrants." ;;
    public-links) echo "On the public repository page, every README link and section link opens, and the README's clone command works." ;;
  esac
}

# ck_pass <id> [<detail>]
ck_pass() {
  local d=${2:-$(ck_pass_text "$1")}
  echo "PASS $1 $d"
  ck_add "$1" pass "$d"
}

# ck_fail <id> <summary> [<hits, one per line>]: a FAIL line, then at most 10 hits indented.
ck_fail() {
  local id=$1 summary=$2 hits=${3:-} flat
  echo "FAIL $id $summary"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
    flat=$(printf '%s\n' "$hits" | head -n 5 | tr '\n' ' ')
    ck_add "$id" fail "$summary: $flat"
  else
    ck_add "$id" fail "$summary"
  fi
}

# ck_has_line <file> <text>: 0 when a line of the file, trimmed of spaces, equals the text.
ck_has_line() {
  [ -f "$1" ] || return 1
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$1" | LC_ALL=C grep -Fxq -- "$2"
}

# ck_rel <path>: the path relative to the repository root when it is inside it (so that no record holds a local path), else as given.
ck_rel() {
  case $1 in
    "$ck_self"/*) printf '%s\n' "${1#"$ck_self"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# --- the automated rows ---

row_checkout() {
  local n
  # A rename counts when either of its two paths is outside release/records/.
  n=$(git status --porcelain --untracked-files=all 2> /dev/null | awk '{ p = substr($0, 4); q = p; if ((i = index(p, " -> ")) > 0) { q = substr(p, i + 4); p = substr(p, 1, i - 1) } }
    p !~ /^release\/records\// || q !~ /^release\/records\// { n++ } END { print n + 0 }')
  if [ "$n" -eq 0 ]; then
    ck_pass checkout
  else
    ck_fail checkout "the checkout has uncommitted changes outside release/records/: $n path(s)"
  fi
}

row_note_readme() {
  if [ -f README.md ] && LC_ALL=C grep -Fxq -- "$CK_NOTE" README.md; then
    ck_pass note-readme
  else
    ck_fail note-readme "README.md: the note is missing or not word for word"
  fi
}

row_note_about() {
  local src=web/src/app/about/about-dialog.ts bad="" js mains=0 noted=0 built=0
  ck_has_line "$src" "<p>$CK_NOTE</p>" || bad="$src: the note is missing or not word for word"
  for js in "$CK_CSP"/main-*.js; do
    [ -f "$js" ] || continue
    mains=$((mains + 1))
    if LC_ALL=C grep -Fq -- "$CK_NOTE" "$js"; then noted=1; fi
  done
  # The built page is there when its index.html or a main-*.js is: a page without a main-*.js holding the note lacks it.
  if [ -f "$CK_CSP/index.html" ] || [ "$mains" -gt 0 ]; then
    built=1
    [ "$noted" -eq 1 ] || bad="${bad:+$bad; }$CK_CSP/main-*.js: no file holds the note"
  fi
  if [ -n "$bad" ]; then
    ck_fail note-about "$bad"
  elif [ "$built" -eq 0 ]; then
    ck_pass note-about "the About dialog's source holds the note word for word; there is no built page to check"
  else
    ck_pass note-about
  fi
}

# ck_name_in <file> <line ere>: file:line of each line that matches the line pattern and holds the name.
ck_name_in() {
  if [ ! -f "$1" ]; then
    echo "$1: missing"
    return
  fi
  awk -v re="$CK_NAME_ERE" -v lre="$2" -v f="$1" 'tolower($0) ~ re && $0 ~ lre { print f ":" FNR }' "$1"
}

row_product_name() {
  local hits=""
  if [ -f README.md ]; then
    if head -n 1 README.md | tr '[:upper:]' '[:lower:]' | grep -q -e "$CK_NAME_ERE"; then hits="README.md:1"; fi
  else
    hits="README.md: missing"
  fi
  hits="$hits
$(ck_name_in src/module.xml '<Name>')
$(ck_name_in web/package.json '"name"[[:space:]]*:')
$(ck_name_in web/src/index.html '<title>')
$(ck_name_in docker-compose.yml '^name:')"
  hits=$(printf '%s\n' "$hits" | sed '/^$/d')
  if [ -z "$hits" ]; then
    ck_pass product-name
  else
    ck_fail product-name "a product name holds the name from the note" "$hits"
  fi
}

row_name_only_in_note() {
  local files hits=""
  files=$(scan_files | grep -v -e '^_bmad-output/' -e '^_bmad/' -e '^docker/tests/test-readme\.sh$')
  if [ -n "$files" ]; then
    hits=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -nHIi -e "$CK_NAME_ERE" 2> /dev/null \
      | awk -v note="$CK_NOTE" -v re="$CK_NAME_ERE" '
        match($0, /^[^:]*:[0-9]+:/) {
          loc = substr($0, 1, RLENGTH - 1)
          t = substr($0, RLENGTH + 1)
          while ((i = index(t, note)) > 0) t = substr(t, 1, i - 1) substr(t, i + length(note))
          if (tolower(t) ~ re) print loc
        }')
  fi
  if [ -z "$hits" ]; then
    ck_pass name-only-in-note
  else
    ck_fail name-only-in-note "the name from the note appears outside the note" "$hits"
  fi
}

row_licences() {
  local bad="" f n dep imports have_bundle=0
  n=0
  for f in "$CK_LICENSES"/*; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    [ -s "$f" ] || bad="$bad$f: empty
"
  done
  [ "$n" -gt 0 ] || bad="$bad$CK_LICENSES: no licence file
"
  if ! grep -Fxq 'MIT License' docker/ipm/LICENSE 2> /dev/null; then
    bad="${bad}docker/ipm/LICENSE: no line 'MIT License'
"
  fi
  if ! grep -Fxq 'Copyright (c) 2019 InterSystems Developer Community' docker/ipm/LICENSE 2> /dev/null; then
    bad="${bad}docker/ipm/LICENSE: no copyright line of the Developer Community
"
  fi
  if [ -f "$CK_CSP/index.html" ]; then
    have_bundle=1
    if [ ! -s "$CK_CSP/3rdpartylicenses.txt" ]; then
      bad="$bad$CK_CSP/3rdpartylicenses.txt: missing or empty
"
    else
      imports=$(find web/src -name '*.ts' ! -name '*.spec.ts' -exec grep -hoE "from ['\"][^'\"]+['\"]" {} + 2> /dev/null | tr '"' "'")
      for dep in $(awk '/"dependencies"[[:space:]]*:/ { on = 1; next } on && /}/ { on = 0 }
          on && match($0, /"[^"]+"[[:space:]]*:/) { s = substr($0, RSTART + 1, RLENGTH - 1); sub(/".*/, "", s); print s }' web/package.json 2> /dev/null); do
        if printf '%s\n' "$imports" | grep -Fq -e "from '$dep'" -e "from '$dep/"; then
          grep -Fxq "Package: $dep" "$CK_CSP/3rdpartylicenses.txt" || bad="$bad$CK_CSP/3rdpartylicenses.txt: no entry for $dep
"
        fi
      done
    fi
    for f in "$CK_LICENSES"/*; do
      [ -f "$f" ] || continue
      [ -s "$CK_CSP/assets/licenses/${f##*/}" ] || bad="$bad$CK_CSP/assets/licenses/${f##*/}: missing or empty
"
    done
  fi
  bad=$(printf '%s' "$bad" | sed '/^$/d')
  if [ -n "$bad" ]; then
    ck_fail licences "a licence notice is missing or empty" "$bad"
  elif [ "$have_bundle" -eq 0 ]; then
    ck_pass licences "the font, icon and IPM licence files are present; there is no built page to check"
  else
    ck_pass licences
  fi
}

row_web_bundle() {
  if [ -f "$CK_CSP/index.html" ]; then
    ck_pass web-bundle
  else
    ck_fail web-bundle "the built web bundle is not in the checkout (Story 11.5 commits it on the candidate branch)"
  fi
}

row_readme() {
  local out rc
  out=$(mktemp "${ck_tmp:-${TMPDIR:-/tmp}}/readme.XXXXXX") || {
    ck_fail readme "no temporary file to run docker/tests/test-readme.sh in"
    return 0
  }
  bash docker/tests/test-readme.sh > "$out" 2>&1 < /dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then
    ck_pass readme
  else
    ck_fail readme "docker/tests/test-readme.sh failed (exit $rc)" "$(grep '^FAIL' "$out" | head -n 10)"
  fi
  rm -f "$out"
}

# row_public_text [<notes file>]: from the repository root; the notes file defaults to the one of the run (ck_notes).
row_public_text() {
  local out rc hits="" lines notes=${1:-${ck_notes:-}}
  out=$(mktemp "${ck_tmp:-${TMPDIR:-/tmp}}/boundaries.XXXXXX") || {
    ck_fail public-text "no temporary file to run docker/tests/test-boundaries.sh in"
    return 0
  }
  bash docker/tests/test-boundaries.sh > "$out" 2>&1 < /dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    lines=$(grep -E '^(FAIL|  )' "$out" | head -n 10)
    hits="docker/tests/test-boundaries.sh failed (exit $rc)${lines:+
$lines}"
  fi
  rm -f "$out"
  if [ ! -f "$notes" ]; then
    hits="${hits:+$hits
}no draft notes at $(ck_rel "$notes")"
  else
    lines=$({ local_path "$notes"; key_like "$notes"; } | sort -u | while IFS= read -r h; do ck_rel "$h"; done)
    [ -z "$lines" ] || hits="${hits:+$hits
}$lines"
  fi
  if [ -z "$hits" ]; then
    ck_pass public-text
  else
    ck_fail public-text "the public-text check failed" "$hits"
  fi
}

row_iris_source() {
  local bad="" d rc n
  for d in irislib irissys; do
    git check-ignore -q "$d/x" 2> /dev/null
    rc=$?
    # A folder that is a symbolic link cannot be asked about a path below it; the link itself is then asked.
    if [ "$rc" -eq 128 ]; then
      git check-ignore -q "$d" 2> /dev/null
      rc=$?
    fi
    [ "$rc" -eq 0 ] || bad="${bad}$d/ is not ignored by .gitignore
"
  done
  n=$(git -c core.quotePath=false ls-files 2> /dev/null | awk -F/ '
    { for (i = 1; i <= NF; i++) {
        if ($i == "irislib" || $i == "irissys") { a++; next }
        if (substr($i, 1, 1) == "%") { p++; next }
      } }
    END { print a + 0 " " p + 0 }')
  [ "${n% *}" -eq 0 ] || bad="${bad}a path with an irislib/ or irissys/ component is tracked: ${n% *} path(s)
"
  [ "${n#* }" -eq 0 ] || bad="${bad}a path with a component that starts with a percent sign is tracked: ${n#* } path(s)
"
  bad=$(printf '%s' "$bad" | sed '/^$/d')
  if [ -z "$bad" ]; then
    ck_pass iris-source
  else
    ck_fail iris-source "the IRIS reference source rule is broken" "$bad"
  fi
}

# outward_hits <file>...: file:line of each line that publishes a release, changes the repository's settings or names a public site.
outward_hits() {
  grep -nHIE -e 'gh[ ]+release[ ]+(create|edit|upload|delete)' -e 'gh[ ]+repo[ ]+edit' -e '--visibilit[y]' -e 'action-gh-releas[e]' \
    -e 'create-releas[e]' -e '(^|[^.A-Za-z0-9-])community[.]intersystems[.]com' -e 'openexchange[.]intersystems[.]com' \
    -e 'twitter[.]com' -e '(^|[^A-Za-z0-9._-])x[.]com/' -e 'linkedin[.]com' -e 'youtube[.]com' -e 'medium[.]com' \
    -e '(^|[^A-Za-z0-9._-])dev[.]to/' -e 'reddit[.]com' "$@" 2> /dev/null | cut -d: -f1,2
}

row_no_outward() {
  local files hits=""
  files=$({ scan_files release ci eval docker | grep -E '\.(sh|mjs|js)$'; scan_files install.sh '.github/workflows'; } | sort -u)
  if [ -n "$files" ]; then
    # The list is split at newlines only, with no pattern expansion, as scan_rule does.
    hits=$(
      IFS='
'
      set -f
      outward_hits $files
    )
  fi
  if [ -z "$hits" ]; then
    ck_pass no-outward
  else
    ck_fail no-outward "a script or workflow publishes, changes the repository's settings or names a public site" "$hits"
  fi
}

# --- the author's rows ---

# ck_valid_date <YYYY-MM-DD>: 0 for a real calendar date.
ck_valid_date() {
  case $1 in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  awk -v d="$1" 'BEGIN {
    split(d, a, "-"); y = a[1] + 0; m = a[2] + 0; dd = a[3] + 0
    if (y < 1 || m < 1 || m > 12 || dd < 1) exit 1
    split("31 28 31 30 31 30 31 31 30 31 30 31", md, " ")
    mx = md[m]
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) mx = 29
    exit (dd > mx) ? 1 : 0
  }'
}

# ck_confirmed_date <section lines file> <id>: prints the date of the first valid confirmation line of the id; returns 1 when none.
ck_confirmed_date() {
  local l rest d
  while IFS= read -r l || [ -n "$l" ]; do
    case $l in
      "- $2: confirmed "*) ;;
      *) continue ;;
    esac
    rest=${l#"- $2: confirmed "}
    d=${rest%% *}
    if ck_valid_date "$d"; then
      printf '%s\n' "$d"
      return 0
    fi
  done < "$1"
  return 1
}

# author_rows <record>: one PASS or CONFIRM line for each author row, read from the record's "## Author confirmations" section.
author_rows() {
  local record=$1 lines id d
  lines=$(mktemp "${ck_tmp:-${TMPDIR:-/tmp}}/author.XXXXXX") || {
    for id in $CK_AUTHOR_IDS; do
      echo "CONFIRM $id: the record could not be read (no temporary file)"
      ck_add "$id" "not confirmed" "$(ck_author_text "$id")"
    done
    return 0
  }
  if [ -f "$record" ]; then
    awk '{ t = $0; sub(/[ \t\r]+$/, "", t) }
      t == "## Author confirmations" { on = 1; next }
      on && /^##? / { on = 0 }
      on { print }' "$record" > "$lines"
  fi
  for id in $CK_AUTHOR_IDS; do
    if d=$(ck_confirmed_date "$lines" "$id"); then
      echo "PASS $id the record says the author confirmed this on $d"
      ck_add "$id" confirmed "the record says the author confirmed this on $d"
    else
      echo "CONFIRM $id: add the line \"- $id: confirmed <YYYY-MM-DD>\" under \"## Author confirmations\" in $(ck_rel "$record")"
      ck_add "$id" "not confirmed" "$(ck_author_text "$id")"
    fi
  done
  rm -f "$lines"
}

# --- the result and the section ---

# checklist_result <results>: fail, not confirmed or pass.
checklist_result() {
  if grep -q '^[^|]*|fail|' "$1"; then
    echo fail
  elif grep -q '^[^|]*|not confirmed|' "$1"; then
    echo "not confirmed"
  else
    echo pass
  fi
}

# checklist_section <results> <options>: the section "## Release checklist" on standard output. The options file holds the lines
# version=, rc=, sha=, notes= and run=.
checklist_section() {
  local results=$1 opts=$2
  printf '## Release checklist\n\n'
  printf 'Result: %s\n' "$(checklist_result "$results")"
  printf 'Candidate: %s rc%s at %s\n' "$(env_get "$opts" version)" "$(env_get "$opts" rc)" "$(env_get "$opts" sha)"
  printf 'Notes: %s\n' "$(env_get "$opts" notes)"
  printf 'Run: %s\n' "$(env_get "$opts" run)"
  printf "Author's actions: %s\n\n" "$CK_AUTHOR_ACTIONS"
  printf '| Item | Result | Detail |\n| --- | --- | --- |\n'
  awk -F'|' '{ d = $3; for (i = 4; i <= NF; i++) d = d "|" $i; print "| " $1 " | " $2 " | " d " |" }' "$results"
}

# --- main ---

ck_refuse() {
  echo "REFUSED $*"
  return 2
}

checklist_main() {
  local o_version="" o_rc="" o_candidate="" o_record="" o_notes="" mv sha cand record notes result opts sec rc
  while [ $# -gt 0 ]; do
    case $1 in
      --version | --rc | --candidate | --record | --notes)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          ck_refuse "$1 needs a value"
          return 2
        fi
        case $1 in
          --version) o_version=$2 ;;
          --rc) o_rc=$2 ;;
          --candidate) o_candidate=$2 ;;
          --record) o_record=$2 ;;
          --notes) o_notes=$2 ;;
        esac
        shift 2
        ;;
      *)
        ck_refuse "unknown option '$1'"
        return 2
        ;;
    esac
  done
  if [ -z "$o_version" ] || [ -z "$o_rc" ]; then
    ck_refuse "usage: release/checklist.sh --version <x.y.z> --rc <n> [--candidate <ref>] [--record <file>] [--notes <file>]"
    return 2
  fi
  if ! printf '%s\n' "$o_version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$'; then
    ck_refuse "--version $o_version is not x.y.z"
    return 2
  fi
  if ! printf '%s\n' "$o_rc" | grep -Eq '^[1-9][0-9]*$'; then
    ck_refuse "--rc $o_rc is not a positive whole number"
    return 2
  fi
  cd "$ck_self" || return 2
  if [ "$(git rev-parse --show-toplevel 2> /dev/null)" != "$ck_self" ]; then
    ck_refuse "$ck_self is not the root of a git repository"
    return 2
  fi
  mv=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/module.xml 2> /dev/null | head -n 1)
  if [ "$mv" != "$o_version" ]; then
    ck_refuse "--version $o_version is not the version of src/module.xml (${mv:-none})"
    return 2
  fi
  sha=$(git rev-parse --verify --quiet 'HEAD^{commit}') || {
    ck_refuse "the repository has no commit"
    return 2
  }
  if [ -n "$o_candidate" ]; then
    if ! cand=$(git rev-parse --verify --quiet "$o_candidate^{commit}"); then
      ck_refuse "the candidate '$o_candidate' is not a commit of this repository"
      return 2
    fi
    if [ "$cand" != "$sha" ]; then
      ck_refuse "the candidate '$o_candidate' is not the checked out commit (HEAD)"
      return 2
    fi
  fi
  record=${o_record:-$(record_path "$o_version" "$o_rc")}
  notes=${o_notes:-$(notes_path "$o_version" "$o_rc")}
  case $record in /*) ;; *) record=$ck_self/$record ;; esac
  case $notes in /*) ;; *) notes=$ck_self/$notes ;; esac
  if [ -e "$record" ] && [ ! -f "$record" ]; then
    ck_refuse "the record '${o_record:-$record}' is not a file"
    return 2
  fi
  if [ ! -f "$record" ] && [ -e "$(dirname "$record")" ] && [ ! -d "$(dirname "$record")" ]; then
    ck_refuse "the record's folder is not a folder"
    return 2
  fi

  ck_tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ck.XXXXXX" 2> /dev/null) || {
    ck_refuse "no temporary folder for the run"
    return 2
  }
  ck_results=$ck_tmp/results
  ck_notes=$notes
  : > "$ck_results"
  row_checkout
  row_note_readme
  row_note_about
  row_product_name
  row_name_only_in_note
  row_licences
  row_web_bundle
  row_readme
  row_public_text
  row_iris_source
  row_no_outward
  author_rows "$record"
  result=$(checklist_result "$ck_results")
  opts=$ck_tmp/options
  : > "$opts"
  env_set "$opts" version "$o_version"
  env_set "$opts" rc "$o_rc"
  env_set "$opts" sha "$sha"
  env_set "$opts" notes "$(ck_rel "$notes")"
  env_set "$opts" run "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sec=$ck_tmp/section.md
  checklist_section "$ck_results" "$opts" > "$sec"
  if ! record_write "$record" "$sec" "# OcuTalon $o_version rc$o_rc"; then
    echo "FAIL the record could not be written"
    rm -rf "$ck_tmp"
    return 1
  fi
  echo "RECORD ${o_record:-$(record_path "$o_version" "$o_rc")}"
  echo "RESULT $result"
  rm -rf "$ck_tmp"
  rc=1
  [ "$result" = pass ] && rc=0
  return "$rc"
}

[ "${BASH_SOURCE[0]}" != "$0" ] && return 0
checklist_main "$@"
exit $?
