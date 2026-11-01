#!/usr/bin/env bash
# Hermetic self-test of the release checklist (Story 11.4; release/checklist.sh, notes_path of release/lib-release.sh, local_path of
# docker/tests/lib-scan.sh), with no container, no network call and no model. It builds one synthetic git repository in a temporary
# folder (copies of the checklist and its three libraries, fixture files, a fixture bundle, and stubs for test-readme.sh and
# test-boundaries.sh that fail only when a marker file exists), copies it for each case and pins:
#   - base: a record with a rehearsal section and all five confirmations gives RESULT pass and exit 0; both other sections stay byte for
#     byte; the checklist section appears once and is replaced by a second run;
#   - rows: each automated row, mutated in a fresh copy, fails with file:line (or a count) and without the planted text, and with no other
#     row failing but the ones that must (a name outside the note fails name-only-in-note as well);
#   - author: the author rows are read from the record only: no section, a malformed line, an impossible date, another word, a leap day,
#     a date with text, the precedence of fail over not confirmed, and the section never changed;
#   - refusals: each refusal exits 2 with one line, and the record is neither created nor changed;
#   - no-network: stubs for curl, wget, gh, ssh and nc leave no marker after any case;
#   - sourcing: sourcing the checklist runs nothing, and lib-scan.sh defines local_path;
#   - static: mode 100755, umask 077, ASCII, the main guard, no network command, and no line that holds the inspiration's name without
#     the note (first run on a synthetic file that breaks each rule).
# The samples that break a rule are built by concatenation, so that this file keeps the rules it tests. Prints one PASS or FAIL line per
# rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root" || exit 1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ckl.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN

NOTE='OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.'
NAME="Open""Claw"
PLANT_PATH="/Use""rs/someone/work"
PLANT_KEY="sk-""ant-""aaaaaaaaaaaaaaaa"
W=$tmp/w
marks=$tmp/marks
netm=$tmp/netmarks
mkdir -p "$marks" "$netm" "$tmp/bin"
bad=0
fails_total=0

eq() { # eq <label> <got> <want>
  if [ "$2" != "$3" ]; then
    echo "  $1: got '$2', wanted '$3'"
    bad=1
  fi
}
has() { # has <label> <text> <part>
  case $2 in
    *"$3"*) ;;
    *)
      echo "  $1: the text lacks '$3'"
      bad=1
      ;;
  esac
}
lacks() { # lacks <label> <text> <part>
  case $2 in
    *"$3"*)
      echo "  $1: the text holds '$3'"
      bad=1
      ;;
  esac
}
rule() { # rule <name> <function>
  bad=0
  "$2"
  if [ "$bad" -eq 0 ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    fails_total=$((fails_total + 1))
  fi
}

# --- the stubs and the synthetic repository ---

for n in curl wget gh ssh nc; do
  printf '#!/bin/sh\n: > "$NETMARK/%s"\nexit 1\n' "$n" > "$tmp/bin/$n"
  chmod 755 "$tmp/bin/$n"
done

stub() { # stub <file> <marker>
  printf '#!/usr/bin/env bash\nif [ -e "$CK_MARK/%s" ]; then\n  echo "FAIL fixture marker"\n  exit 1\nfi\nexit 0\n' "$2" > "$1"
  chmod 755 "$1"
}

mkbase() {
  local b=$tmp/base
  mkdir -p "$b/release" "$b/docker/tests" "$b/docker/ipm" "$b/web/src/app/about" "$b/web/public/assets/licenses" "$b/src" \
    "$b/src/ocutalon/csp/assets/licenses" "$b/docs"
  cp -p "$root/release/checklist.sh" "$root/release/lib-release.sh" "$b/release/"
  cp -p "$root/docker/tests/lib-scan.sh" "$root/docker/tests/lib-keys.sh" "$b/docker/tests/"
  stub "$b/docker/tests/test-readme.sh" readme
  stub "$b/docker/tests/test-boundaries.sh" boundaries
  printf '# OcuTalon\n\n%s\n' "$NOTE" > "$b/README.md"
  printf '<div>\n  <p>%s</p>\n</div>\n' "$NOTE" > "$b/web/src/app/about/about-dialog.ts"
  printf '<Export>\n  <Document name="ocutalon.ZPM">\n    <Module>\n      <Name>ocutalon</Name>\n      <Version>1.0.0</Version>\n    </Module>\n  </Document>\n</Export>\n' > "$b/src/module.xml"
  printf '{\n  "name": "ocutalon-web",\n  "dependencies": {\n    "@angular/core": "1",\n    "qrcode-generator": "2",\n    "rxjs": "7"\n  },\n  "devDependencies": {\n    "typescript": "5"\n  }\n}\n' > "$b/web/package.json"
  printf '<html><head>\n  <title>OcuTalon</title>\n</head></html>\n' > "$b/web/src/index.html"
  printf "import { Component } from '@angular/core';\nimport { map } from 'rxjs/operators';\n" > "$b/web/src/main.ts"
  printf "import qr from 'qrcode-generator';\n" > "$b/web/src/main.spec.ts"
  printf 'name: ocutalon\n' > "$b/docker-compose.yml"
  printf 'licence a\n' > "$b/web/public/assets/licenses/a-OFL.txt"
  printf 'licence b\n' > "$b/web/public/assets/licenses/b-LICENSE.txt"
  cp "$b/web/public/assets/licenses/"* "$b/src/ocutalon/csp/assets/licenses/"
  printf 'MIT License\n\nCopyright (c) 2019 InterSystems Developer Community\n' > "$b/docker/ipm/LICENSE"
  printf '<html></html>\n' > "$b/src/ocutalon/csp/index.html"
  printf 'var a = "%s";\n' "$NOTE" > "$b/src/ocutalon/csp/main-x.js"
  printf 'Package: @angular/core\nMIT\n\nPackage: rxjs\nApache-2.0\n' > "$b/src/ocutalon/csp/3rdpartylicenses.txt"
  printf 'irislib/\nirissys/\n/irislib\n/irissys\n' > "$b/.gitignore"
  git init -q "$b" || exit 1
  git -C "$b" checkout -q -b release/1.0.0-rc1
  git -C "$b" add -A
  git -C "$b" commit -q -m base
  printf 'a plain page\n' > "$b/docs/page.txt"
  git -C "$b" add -A
  git -C "$b" commit -q -m second
}

fresh() {
  rm -rf "$W"
  cp -R "$tmp/base" "$W"
}
commit_all() {
  git -C "$W" add -A
  git -C "$W" commit -q -m mutation
}

CONF_IDS="no-copied-code no-artwork no-ai-hub-copy public-review public-links"
mkrec() { # mkrec <file> [<ids to confirm>]: the default confirms all five
  local f=$1 ids id
  shift
  ids=${*:-$CONF_IDS}
  {
    printf '# OcuTalon 1.0.0 rc1\n\n## Clean-machine rehearsal\n\nResult: pass\n\n| Item | Result |\n| --- | --- |\n| a | pass |\n\n'
    printf '## Author confirmations\n\n'
    for id in $ids; do printf -- '- %s: confirmed 2026-11-02 by the author\n' "$id"; done
    printf '\n'
  } > "$f"
}
mkrec_plain() { # a record with a rehearsal section only
  printf '# OcuTalon 1.0.0 rc1\n\n## Clean-machine rehearsal\n\nResult: pass\n\n' > "$1"
}
sect() { # sect <file> <title>: the section, up to the next heading
  awk -v t="$2" '$0 == t { on = 1; print; next } on && /^##? / { exit } on { print }' "$1"
}

rec=$tmp/rc1.md
notes=$tmp/notes.md
newcase() { # a fresh copy, a full record and a clean notes file
  fresh
  mkrec "$rec"
  printf '# OcuTalon draft\n\nA plain sentence.\n' > "$notes"
  rm -f "$marks"/*
}
out=""
rc=0
run_ck() { # run_ck <args...>: out and rc
  out=$(cd "$tmp" && PATH="$tmp/bin:$PATH" CK_MARK="$marks" NETMARK="$netm" bash "$W/release/checklist.sh" "$@" 2>&1)
  rc=$?
}
std() { run_ck --version 1.0.0 --rc 1 --record "$rec" --notes "$notes" "$@"; }
failed_ids() { printf '%s\n' "$out" | grep '^FAIL ' | awk '{ printf "%s ", $2 }'; }
expect_fail() { # expect_fail <label> <ids that fail, space separated, each followed by a space>
  std
  eq "$1: exit" "$rc" 1
  eq "$1: failed rows" "$(failed_ids)" "$2"
  has "$1: result" "$out" "RESULT fail"
}

# --- base ---

t_base() {
  local before_r before_a first size prefix
  newcase
  before_r=$(sect "$rec" "## Clean-machine rehearsal")
  before_a=$(sect "$rec" "## Author confirmations")
  size=$(wc -c < "$rec" | tr -d ' ')
  prefix=$(cksum < "$rec")
  std
  eq "exit" "$rc" 0
  eq "the record's earlier bytes are kept" "$(head -c "$size" "$rec" | cksum)" "$prefix"
  has "result" "$out" "RESULT pass"
  has "record line" "$out" "RECORD $rec"
  eq "PASS lines" "$(printf '%s\n' "$out" | grep -c '^PASS ')" 16
  eq "no FAIL or CONFIRM line" "$(printf '%s\n' "$out" | grep -c -e '^FAIL ' -e '^CONFIRM ')" 0
  eq "rehearsal section kept" "$(sect "$rec" "## Clean-machine rehearsal")" "$before_r"
  eq "confirmations kept" "$(sect "$rec" "## Author confirmations")" "$before_a"
  eq "one checklist section" "$(grep -c '^## Release checklist$' "$rec")" 1
  has "section result" "$(sect "$rec" "## Release checklist")" "Result: pass"
  has "candidate line" "$(sect "$rec" "## Release checklist")" "Candidate: 1.0.0 rc1 at $(git -C "$W" rev-parse HEAD)"
  has "notes line" "$(sect "$rec" "## Release checklist")" "Notes: $notes"
  has "author actions" "$(sect "$rec" "## Release checklist")" "Posts, articles, the video and bonus claims are the author's actions"
  has "confirmed detail" "$(sect "$rec" "## Release checklist")" "| public-review | confirmed | the record says the author confirmed this on 2026-11-02 |"
  first=$(sect "$rec" "## Release checklist")
  std
  eq "second run: exit" "$rc" 0
  eq "second run: one checklist section" "$(grep -c '^## Release checklist$' "$rec")" 1
  eq "second run: the record's earlier bytes are kept" "$(head -c "$size" "$rec" | cksum)" "$prefix"
  eq "second run: rehearsal section kept" "$(sect "$rec" "## Clean-machine rehearsal")" "$before_r"
  eq "second run: confirmations kept" "$(sect "$rec" "## Author confirmations")" "$before_a"
  eq "second run: same table" "$(sect "$rec" "## Release checklist" | grep '^| ')" "$(printf '%s\n' "$first" | grep '^| ')"
  # A missing record is created with the heading, and the defaults name the record and the notes under release/records/.
  rm -f "$rec"
  std
  eq "new record: first line" "$(head -n 1 "$rec")" "# OcuTalon 1.0.0 rc1"
  has "new record: not confirmed" "$out" "RESULT not confirmed"
  run_ck --version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --notes "$notes" --record "$tmp/new/dir/rc1.md"
  eq "candidate by branch name: exit" "$rc" 1
  eq "record folder created" "$([ -f "$tmp/new/dir/rc1.md" ] && echo yes)" yes
}

# --- the rows ---

t_note_rows() {
  local altered=${NOTE/inspired/inspires}
  newcase
  sed "s/$NOTE/$altered/" "$W/README.md" > "$W/r.new" && mv "$W/r.new" "$W/README.md"
  commit_all
  expect_fail "readme note altered" "note-readme name-only-in-note "
  has "readme note: place" "$out" "README.md"
  has "readme note: name-only place" "$out" "README.md:3"
  lacks "readme note: no text" "$out" "inspires"
  newcase
  sed "s/$NOTE/${NOTE/inspired/Inspired}/" "$W/README.md" > "$W/r.new" && mv "$W/r.new" "$W/README.md"
  commit_all
  expect_fail "readme note in another case" "note-readme name-only-in-note "
  newcase
  sed "s/$NOTE/$altered/" "$W/web/src/app/about/about-dialog.ts" > "$W/r.new" && mv "$W/r.new" "$W/web/src/app/about/about-dialog.ts"
  commit_all
  expect_fail "about note altered" "note-about name-only-in-note "
  has "about note: place" "$out" "web/src/app/about/about-dialog.ts"
  lacks "about note: no text" "$out" "inspires"
  newcase
  printf 'var a = "%s";\n' "$altered" > "$W/src/ocutalon/csp/main-x.js"
  commit_all
  expect_fail "bundle note altered" "note-about name-only-in-note "
  has "bundle note: place" "$out" "main-*.js"
  lacks "bundle note: no text" "$out" "inspires"
  # The note in a bundle file that is not main-*.js does not count.
  newcase
  git -C "$W" mv src/ocutalon/csp/main-x.js src/ocutalon/csp/other-x.js
  printf 'var a = 1;\n' > "$W/src/ocutalon/csp/main-y.js"
  commit_all
  expect_fail "note only in another file" "note-about "
}

t_name_rows() {
  newcase
  sed "s/<Name>ocutalon</<Name>${NAME}</" "$W/src/module.xml" > "$W/r.new" && mv "$W/r.new" "$W/src/module.xml"
  commit_all
  expect_fail "name in module.xml" "product-name name-only-in-note "
  has "name in module.xml: place" "$out" "src/module.xml:4"
  lacks "name in module.xml: no text" "$out" "$NAME"
  newcase
  printf 'An AI assistant, inspired by %s.\n' "$NAME" > "$W/web/src/x.ts"
  commit_all
  expect_fail "tagline-like line in web/src" "name-only-in-note "
  has "tagline: place" "$out" "web/src/x.ts:1"
  newcase
  mkdir -p "$W/_bmad-output" "$W/_bmad"
  printf 'An AI assistant, inspired by %s.\n' "$NAME" > "$W/_bmad-output/x.md"
  printf 'A rule that names %s.\n' "$NAME" > "$W/_bmad/rule.md"
  commit_all
  std
  eq "the same line under the planning folders: exit" "$rc" 0
  # The note's own line is fine; the note with more text after the name on the same line is not.
  newcase
  printf '%s It is also %s.\n' "$NOTE" "$NAME" > "$W/docs/page.txt"
  commit_all
  expect_fail "the name beside the note" "name-only-in-note "
  has "the name beside the note: place" "$out" "docs/page.txt:1"
  newcase
  sed "s/\"ocutalon-web\"/\"${NAME}-web\"/" "$W/web/package.json" > "$W/r.new" && mv "$W/r.new" "$W/web/package.json"
  commit_all
  expect_fail "name in package.json" "product-name name-only-in-note "
  has "package.json: place" "$out" "web/package.json:2"
  newcase
  sed "s|<title>ocutalon</title>|<title>${NAME}</title>|I" "$W/web/src/index.html" > "$W/r.new" && mv "$W/r.new" "$W/web/src/index.html"
  commit_all
  expect_fail "name in the page title" "product-name name-only-in-note "
  has "title: place" "$out" "web/src/index.html:2"
  newcase
  printf 'name: %s\n' "$NAME" > "$W/docker-compose.yml"
  commit_all
  expect_fail "name in the compose project name" "product-name name-only-in-note "
  has "compose: place" "$out" "docker-compose.yml:1"
  # Epic 10's README test names the inspiration by design and is excepted by name.
  newcase
  printf '# the README test checks the note about %s\n' "$NAME" >> "$W/docker/tests/test-readme.sh"
  commit_all
  std
  eq "the name in docker/tests/test-readme.sh: exit" "$rc" 0
  newcase
  printf '# %s\n' "$NAME" > "$W/README.md"
  printf '%s\n' "$NOTE" >> "$W/README.md"
  commit_all
  expect_fail "name in the first line of the README" "product-name name-only-in-note "
  has "first line: place" "$out" "README.md:1"
}

t_licence_rows() {
  newcase
  : > "$W/web/public/assets/licenses/a-OFL.txt"
  commit_all
  expect_fail "empty licence file" "licences "
  has "empty licence: place" "$out" "web/public/assets/licenses/a-OFL.txt"
  newcase
  printf "import z from 'rxjs';\nimport q from 'qrcode-generator/lib';\n" > "$W/web/src/b.ts"
  commit_all
  expect_fail "imported package without an entry" "licences "
  has "package: place" "$out" "3rdpartylicenses.txt: no entry for qrcode-generator"
  newcase
  git -C "$W" rm -q src/ocutalon/csp/assets/licenses/b-LICENSE.txt
  commit_all
  expect_fail "bundle without a licence file" "licences "
  has "bundle licence: place" "$out" "src/ocutalon/csp/assets/licenses/b-LICENSE.txt"
  newcase
  : > "$W/src/ocutalon/csp/3rdpartylicenses.txt"
  commit_all
  expect_fail "empty 3rdpartylicenses.txt" "licences "
  newcase
  printf 'MIT License\n' > "$W/docker/ipm/LICENSE"
  commit_all
  expect_fail "IPM licence without the copyright line" "licences "
  has "IPM licence: place" "$out" "docker/ipm/LICENSE"
  newcase
  printf 'Copyright (c) 2019 InterSystems Developer Community\n' > "$W/docker/ipm/LICENSE"
  commit_all
  expect_fail "IPM licence without the MIT line" "licences "
  has "MIT line: place" "$out" "docker/ipm/LICENSE"
  newcase
  git -C "$W" rm -q src/ocutalon/csp/main-x.js
  commit_all
  expect_fail "a built page with no main-*.js" "note-about "
  has "no main-*.js: place" "$out" "src/ocutalon/csp/main-*.js"
  newcase
  git -C "$W" rm -q -r src/ocutalon/csp
  commit_all
  expect_fail "no bundle" "web-bundle "
  has "no bundle: the note row says so" "$(sect "$rec" "## Release checklist")" "| note-about | pass | the About dialog's source holds the note word for word; there is no built page to check |"
  has "no bundle: the web-bundle detail" "$out" "Story 11.5 commits it on the candidate branch"
}

t_script_rows() {
  newcase
  : > "$marks/readme"
  expect_fail "test-readme.sh fails" "readme "
  newcase
  : > "$marks/boundaries"
  expect_fail "test-boundaries.sh fails" "public-text "
  newcase
  printf 'see %s\n' "$PLANT_PATH" > "$notes"
  expect_fail "local path in the notes" "public-text "
  has "local path: place" "$out" "notes.md:1"
  lacks "local path: no text" "$out" "someone"
  newcase
  printf 'k=%s\n' "$PLANT_KEY" > "$notes"
  expect_fail "key-like text in the notes" "public-text "
  has "key: place" "$out" "notes.md:1"
  lacks "key: no text" "$out" "aaaaaaaa"
  lacks "key: no text in the record" "$(cat "$rec")" "aaaaaaaa"
  newcase
  rm -f "$notes"
  expect_fail "no notes file" "public-text "
  has "no notes: the line" "$out" "no draft notes at $notes"
  # With the default paths, nothing the run writes into the record names a local folder.
  newcase
  run_ck --version 1.0.0 --rc 1
  eq "default paths: exit" "$rc" 1
  has "default notes: the line" "$out" "no draft notes at release/records/1.0.0/rc1-notes.md"
  has "default record: the CONFIRM line" "$out" "in release/records/1.0.0/rc1.md"
  has "default record: the Notes line" "$(cat "$W/release/records/1.0.0/rc1.md")" "Notes: release/records/1.0.0/rc1-notes.md"
  lacks "default record: no local folder" "$(cat "$W/release/records/1.0.0/rc1.md")" "$tmp"
  lacks "default output: no local folder" "$out" "$tmp"
}

t_source_rows() {
  newcase
  mkdir -p "$W/irislib"
  printf 'x\n' > "$W/irislib/x.txt"
  git -C "$W" add -f irislib/x.txt
  git -C "$W" commit -q -m forced
  expect_fail "a tracked file of irislib/" "iris-source "
  has "irislib: the count" "$out" "irislib/ or irissys/ component is tracked: 1 path(s)"
  newcase
  mkdir -p "$W/docs/%Library"
  printf 'x\n' > "$W/docs/%Library/X.cls"
  commit_all
  expect_fail "a tracked path with a percent component" "iris-source "
  has "percent: the count" "$out" "starts with a percent sign is tracked: 1 path(s)"
  newcase
  : > "$W/.gitignore"
  commit_all
  expect_fail "irislib and irissys not ignored" "iris-source "
  has "not ignored: the folder" "$out" "irissys/ is not ignored"
}

outward_plant() { # outward_plant <path> <line>: a script of two lines in the case's copy
  mkdir -p "$W/$(dirname "$1")"
  printf '#!/bin/sh\n%s\n' "$2" > "$W/$1"
}

t_outward_rows() {
  local gh_ver="g""h" f
  newcase
  mkdir -p "$W/release"
  printf '#!/bin/sh\n%s release create v1 --notes-file n.md\n' "$gh_ver" > "$W/release/x.sh"
  commit_all
  expect_fail "a release create line" "no-outward "
  has "release create: place" "$out" "release/x.sh:2"
  lacks "release create: no text" "$out" "notes-file"
  newcase
  printf '#!/bin/sh\necho "--visi""bility public"\n' | sed 's/""//' > "$W/release/x.sh"
  commit_all
  expect_fail "a visibility line" "no-outward "
  has "visibility: place" "$out" "release/x.sh:2"
  newcase
  printf '#!/bin/sh\ncurl_url="https://tw""itter.com/a"\n' | sed 's/""//' > "$W/release/x.sh"
  commit_all
  expect_fail "a social host" "no-outward "
  has "social host: place" "$out" "release/x.sh:2"
  newcase
  mkdir -p "$W/.github/workflows"
  printf 'steps:\n  - uses: softprops/action-g""h-release@v1\n' | sed 's/""//' > "$W/.github/workflows/y.yml"
  commit_all
  expect_fail "a release action in a workflow" "no-outward "
  has "workflow: place" "$out" ".github/workflows/y.yml:2"
  newcase
  printf '#!/bin/sh\necho "https://pm.community.intersystems.com/x https://box.com/a"\n' > "$W/release/x.sh"
  commit_all
  std
  eq "the package manager's host and a longer host name are not posts: exit" "$rc" 0
  # Each remaining pattern, and each scanned root and file kind, with one planted line in its own file (at most ten hits are listed).
  newcase
  mkdir -p "$W/ci" "$W/eval" "$W/docker"
  outward_plant ci/a.sh "$gh_ver release edit v1"
  outward_plant eval/b.mjs "$gh_ver release upload v1 f"
  outward_plant docker/c.js "$gh_ver release delete v1"
  outward_plant install.sh "$gh_ver repo edit --description d"
  outward_plant release/d.sh "uses: create-""release"
  outward_plant release/e.sh "open https://comm""unity.intersystems.com/post"
  outward_plant release/f.sh "open https://openex""change.intersystems.com/x"
  outward_plant release/g.sh "open https://x"".com/post"
  outward_plant release/h.sh "open https://linked""in.com/post"
  outward_plant release/i.sh "open https://you""tube.com/upload"
  commit_all
  expect_fail "each pattern and root, first group" "no-outward "
  for f in ci/a.sh eval/b.mjs docker/c.js install.sh release/d.sh release/e.sh release/f.sh release/g.sh release/h.sh release/i.sh; do
    has "first group: $f" "$out" "$f:2"
  done
  newcase
  outward_plant release/j.sh "open https://med""ium.com/post"
  outward_plant release/k.sh "open https://dev"".to/post"
  outward_plant release/l.sh "open https://red""dit.com/post"
  commit_all
  expect_fail "each pattern, second group" "no-outward "
  for f in release/j.sh release/k.sh release/l.sh; do
    has "second group: $f" "$out" "$f:2"
  done
}

t_checkout_rows() {
  newcase
  printf 'x\n' > "$W/docs/new.txt"
  expect_fail "an untracked file" "checkout "
  has "untracked: the count" "$out" "outside release/records/: 1 path(s)"
  newcase
  printf 'changed\n' >> "$W/docs/page.txt"
  expect_fail "a changed file" "checkout "
  newcase
  mkdir -p "$W/release/records/1.0.0"
  printf 'x\n' > "$W/release/records/1.0.0/other.md"
  commit_all
  printf 'changed\n' >> "$W/release/records/1.0.0/other.md"
  printf 'new\n' > "$W/release/records/1.0.0/new.md"
  std
  eq "a change inside release/records/: exit" "$rc" 0
}

# --- the author's rows ---

t_author() {
  local before id
  newcase
  mkrec_plain "$rec"
  std
  eq "no section: exit" "$rc" 1
  has "no section: result" "$out" "RESULT not confirmed"
  eq "no section: five CONFIRM lines" "$(printf '%s\n' "$out" | grep -c '^CONFIRM ')" 5
  for id in $CONF_IDS; do
    has "CONFIRM $id" "$out" "CONFIRM $id: add the line \"- $id: confirmed <YYYY-MM-DD>\" under \"## Author confirmations\" in $rec"
  done
  eq "no section: none written" "$(grep -c 'Author confirmations' "$rec")" 0
  has "no section: the table" "$(sect "$rec" "## Release checklist")" "| no-artwork | not confirmed | None of that project's logo or artwork is used. |"
  # A malformed line, an impossible date, another word: each row stays not confirmed, and the rest are confirmed.
  newcase
  {
    printf '# OcuTalon 1.0.0 rc1\n\n## Author confirmations\n\n'
    printf -- '- no-copied-code: confirmed yesterday\n'
    printf -- '- no-artwork: confirmed 2026-13-40\n'
    printf -- '- no-ai-hub-copy: confirmed 2027-02-29\n'
    printf -- '- public-review: done\n'
    printf -- '- public-links: confirmed\n'
    printf -- 'no-copied-code: confirmed 2026-11-02\n'
  } > "$rec"
  before=$(cat "$rec")
  std
  eq "malformed: exit" "$rc" 1
  eq "malformed: five CONFIRM lines" "$(printf '%s\n' "$out" | grep -c '^CONFIRM ')" 5
  eq "malformed: the record's own section is unchanged" "$(sect "$rec" "## Author confirmations")" "$(printf '%s\n' "$before" | sed -n '/^## Author confirmations/,$p')"
  # A leap day and a date with no text are confirmed; the heading must be exact; a section further down is not read.
  newcase
  {
    printf '# OcuTalon 1.0.0 rc1\n\n## Author confirmations\n\n'
    printf -- '- no-copied-code: confirmed 2028-02-29\n'
    printf -- '- no-artwork: confirmed 2026-11-02\n'
    printf -- '- no-ai-hub-copy: confirmed 2026-11-02 text with: colons - and dashes\n'
    printf -- '- public-review: confirmed 2026-11-03 reviewed\n'
    printf '\n## Other\n\n- public-links: confirmed 2026-11-02\n'
  } > "$rec"
  std
  eq "leap day: one CONFIRM line" "$(printf '%s\n' "$out" | grep -c '^CONFIRM ')" 1
  has "the section below is not read" "$out" "CONFIRM public-links:"
  has "leap day confirmed" "$out" "PASS no-copied-code the record says the author confirmed this on 2028-02-29"
  lacks "no text of the line in the detail" "$(sect "$rec" "## Release checklist")" "colons"
  # A heading that only starts like the section's is not the section.
  newcase
  {
    printf '# OcuTalon 1.0.0 rc1\n\n## Author confirmations (draft)\n\n- no-copied-code: confirmed 2026-11-02\n'
    printf '\n## author confirmations\n\n- no-artwork: confirmed 2026-11-02\n'
  } > "$rec"
  std
  eq "look-alike headings: five CONFIRM lines" "$(printf '%s\n' "$out" | grep -c '^CONFIRM ')" 5
  # Not confirmed rows never turn a failing result into not confirmed.
  newcase
  mkrec_plain "$rec"
  : > "$marks/readme"
  std
  eq "fail with unconfirmed rows: exit" "$rc" 1
  has "fail wins" "$out" "RESULT fail"
  has "fail wins: the record" "$(sect "$rec" "## Release checklist")" "Result: fail"
}

# --- refusals ---

refused() { # refused <label> <args...>: exit 2, one REFUSED line, no record
  local label=$1
  shift
  rm -f "$rec"
  run_ck "$@"
  eq "$label: exit" "$rc" 2
  eq "$label: one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
  has "$label: REFUSED" "$out" "REFUSED "
  eq "$label: nothing written" "$([ -e "$rec" ] && echo written)" ""
}

t_refusals() {
  local sum
  newcase
  git -C "$W" branch old HEAD~1
  refused "unknown option" --version 1.0.0 --rc 1 --record "$rec" --bogus
  refused "no version" --rc 1 --record "$rec"
  refused "no rc" --version 1.0.0 --record "$rec"
  refused "a missing value" --version 1.0.0 --rc
  refused "version 1.0" --version 1.0 --rc 1 --record "$rec"
  refused "version with a letter" --version 1.0.x --rc 1 --record "$rec"
  refused "rc 0" --version 1.0.0 --rc 0 --record "$rec"
  refused "rc x" --version 1.0.0 --rc x --record "$rec"
  refused "rc 1.5" --version 1.0.0 --rc 1.5 --record "$rec"
  refused "a version other than module.xml's" --version 2.0.0 --rc 1 --record "$rec"
  refused "an unknown candidate" --version 1.0.0 --rc 1 --candidate no-such-ref --record "$rec"
  refused "a candidate that is not HEAD" --version 1.0.0 --rc 1 --candidate old --record "$rec"
  # An existing record is unchanged by a refusal.
  mkrec "$rec"
  sum=$(cksum < "$rec")
  run_ck --version 2.0.0 --rc 1 --record "$rec"
  eq "an existing record: exit" "$rc" 2
  eq "an existing record: unchanged" "$(cksum < "$rec")" "$sum"
  # A record that is a folder.
  mkdir -p "$tmp/recdir"
  run_ck --version 1.0.0 --rc 1 --record "$tmp/recdir" --notes "$notes"
  eq "a record that is a folder: exit" "$rc" 2
  # Not a git repository: the scripts alone in a folder.
  rm -f "$rec"
  rm -rf "$tmp/nogit"
  mkdir -p "$tmp/nogit/release" "$tmp/nogit/docker/tests"
  cp -p "$root/release/checklist.sh" "$root/release/lib-release.sh" "$tmp/nogit/release/"
  cp -p "$root/docker/tests/lib-scan.sh" "$root/docker/tests/lib-keys.sh" "$tmp/nogit/docker/tests/"
  out=$(cd "$tmp" && bash "$tmp/nogit/release/checklist.sh" --version 1.0.0 --rc 1 --record "$rec" 2>&1)
  rc=$?
  eq "no git repository: exit" "$rc" 2
  has "no git repository: REFUSED" "$out" "REFUSED "
  eq "no git repository: nothing written" "$([ -e "$rec" ] && echo written)" ""
}

t_nonetwork() {
  eq "no stub was called" "$(ls "$netm" | tr '\n' ' ')" ""
}

t_sourcing() {
  local o
  newcase
  o=$(cd "$W" && bash -c '. release/checklist.sh; row_public_text "$1"' _ "$notes" 2>&1)
  eq "row_public_text on a draft, sourced" "$o" "PASS public-text docker/tests/test-boundaries.sh passed, and the draft notes hold no local path or key-like text"
  printf 'see %s\n' "$PLANT_PATH" > "$notes"
  o=$(cd "$W" && bash -c '. release/checklist.sh; row_public_text "$1"' _ "$notes" 2>&1)
  has "row_public_text on a bad draft, sourced" "$o" "FAIL public-text"
  has "row_public_text on a bad draft: place" "$o" "notes.md:1"
  o=$(cd "$W" && bash -c '. release/checklist.sh; type row_public_text > /dev/null && type checklist_result > /dev/null && type local_path > /dev/null && echo defined' 2>&1)
  eq "sourcing runs nothing and defines the rows" "$o" "defined"
  o=$(cd "$root" && bash -c '. docker/tests/lib-scan.sh; printf "x %s\n" "$1" > "$2"; local_path "$2"' _ "$PLANT_PATH" "$tmp/lp.txt" 2>&1)
  eq "lib-scan.sh defines local_path, which flags a planted path" "$o" "$tmp/lp.txt:1"
  o=$(cd "$root" && bash -c '. release/lib-release.sh; notes_path 1.0.0 3')
  eq "notes_path" "$o" "release/records/1.0.0/rc3-notes.md"
}

# --- static ---

static_hits() { # static_hits <file>: one line per violation
  local f=$1
  [ -x "$f" ] || echo "$f: not executable"
  if [ -n "$(git ls-files --stage -- "$f" 2> /dev/null)" ] && ! git ls-files --stage -- "$f" | grep -q '^100755 '; then echo "$f: not mode 100755 in git"; fi
  grep -q '^umask 077$' "$f" || echo "$f: no umask 077"
  LC_ALL=C grep -n '[^[:print:][:space:]]' "$f" | sed "s|^|$f: not ASCII: |"
  grep -qF '[ "${BASH_SOURCE[0]}" != "$0" ] && return 0' "$f" || echo "$f: no main guard"
  grep -vE '^[[:space:]]*#' "$f" | grep -nE '(^|[^A-Za-z0-9_./-])(curl|wget|gh|ssh|nc)[[:space:]]|git[[:space:]]+(fetch|pull|push|ls-remote|clone)' | sed "s|^|$f: network command: |"
  grep -n -i -e '[o]pen[c]law' "$f" | grep -vF "$NOTE" | sed "s|^|$f: the name outside the note: |"
}

t_static() {
  local o
  printf '#!/usr/bin/env bash\necho "caf\303\251"\ncurl http://x\nssh h\ngit fetch\nrun gh x\necho %s\n' "$NAME" > "$tmp/bad-static.sh"
  o=$(static_hits "$tmp/bad-static.sh")
  has "break: mode" "$o" "not executable"
  has "break: umask" "$o" "no umask 077"
  has "break: ASCII" "$o" "not ASCII"
  has "break: main guard" "$o" "no main guard"
  has "break: curl" "$o" "network command"
  eq "break: network lines" "$(printf '%s\n' "$o" | grep -c 'network command')" 4
  has "break: the name" "$o" "the name outside the note"
  o=$(static_hits release/checklist.sh)
  eq "release/checklist.sh keeps the static rules" "$o" ""
  o=$(static_hits docker/tests/test-release-checklist.sh | grep -e 'not executable' -e 'not mode' -e 'not ASCII' -e 'the name outside')
  eq "this file is executable, ASCII and keeps the name inside the note" "$o" ""
}

mkbase
rule base t_base
rule note-rows t_note_rows
rule name-rows t_name_rows
rule licence-rows t_licence_rows
rule script-rows t_script_rows
rule source-rows t_source_rows
rule outward-rows t_outward_rows
rule checkout-rows t_checkout_rows
rule author t_author
rule refusals t_refusals
rule no-network t_nonetwork
rule sourcing t_sourcing
rule static t_static

if [ "$fails_total" -ne 0 ]; then
  echo "test-release-checklist: $fails_total rule(s) failed"
  exit 1
fi
echo "test-release-checklist: all rules passed"
