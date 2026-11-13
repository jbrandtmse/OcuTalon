#!/usr/bin/env bash
# Hermetic self-test of the release notes draft (Story 11.13; release/notes.sh, release_previous_tag of release/lib-release.sh,
# names_outside_section of docker/tests/lib-scan.sh), with no container, no network call and no model. It needs bash, git, awk and node.
# It builds one synthetic git repository in a temporary folder (copies of the notes script, the checklist and the libraries, a stub
# test-boundaries.sh, fixture module.xml, epics.md, sprint-status.yaml and area mapping, all committed on release/1.0.0-rc1), copies it for
# each case, writes the case's record and evaluation result with the candidate's sha, and pins:
#   - base: real-mode inputs give RESULT draft and exit 0; the intro, the areas in the mapping's order with titles in epics.md order,
#     developer stories only in the developer section, the eight scores, the cost and size lines, the rehearsal and upgrade lines and
#     tables, the runs and upgrade tables in the developer section; the record and the result stay byte for byte; nothing else is written;
#   - ipm: ### IPM package and ### Registry install follow ### Upgrade in place in the public part: the record's IPM artifact size line and
#     the result of its FR-57 job are copied (as "IPM install check"), a section the record lacks is said to be not in it, and the registry slot is the not-run-yet text;
#   - later: with a v1.0.0 tag, only the new stories and "Changes since v1.0.0."; with no new story, FAIL stories;
#   - areas: the areas follow the mapping's order; a story line moves a story into another named area;
#   - epics: no or an empty epics.md at the candidate fails stories, naming the file;
#   - inputs: each failing input fails its own row alone (no record fails the rehearsal and the upgrade), with its Not available: line,
#     RESULT fail and exit 1;
#   - eval-forms: an overridden result carries its reason; a null share and a null cost read "not measured";
#   - dry: the mock, a dry-run rehearsal and a non-release upgrade give RESULT dry run and exit 3; a failure still wins;
#   - checks: dev-only and public-text fail with file:line and without the planted text (a local path, key-like text, the inspiration's
#     name outside the not-affiliated note), and pass for the note word for word;
#   - defaults: with no path options the record, the evaluation and the notes are at their own default paths; the tracker is read from the
#     candidate commit (not the working tree) and --candidate may name another commit than the checked-out one;
#   - integration: the checklist's row_public_text, sourced, reads the draft at the default notes path;
#   - refusals: each exits 2 with one line and writes nothing (an option value starting with "-", a notes file that is an input or a
#     tracked file, a draft that cannot be completed); --replace rewrites an existing file;
#   - no-network: the stubs for curl, wget, gh, ssh and nc are live (a call leaves a marker), and a run leaves none;
#   - library: release_previous_tag and names_outside_section;
#   - static: the rules on release/notes.sh and on this file; the not-affiliated note of release/notes.sh, release/checklist.sh and
#     README.md is one text; names_outside_section finds nothing in README.md or GUIDE.md, as test-readme.sh's dev-only rule does
#     (outside "For admins and developers" and "Gmail and Microsoft 365"; a class name in any other section is still reported),
#     except the line that equals the IPM_LOAD value of test-readme.sh word for word (a changed load line is still reported; no
#     IPM_LOAD value fails);
#   - real-tree: the real mapping parses and names real story and epic headings; a run on a fresh repository holding the real scripts,
#     mapping, module.xml, tracker and epics.md of HEAD (no tag) passes stories, dev-only and public-text, and its areas row passes or
#     fails only for epics outside release 1 (RELEASE1_EPICS); notes.sh itself still fails areas for such an epic.
# Every run of notes.sh is checked for a network stub call and a temporary folder left behind (after_run). The samples that break a rule
# are built by concatenation, so that this file keeps the rules it tests. Prints one PASS or FAIL line per rule; exits 0 only when all
# pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root" || exit 1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-nts.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$tmp/xdg"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN

NAME="Open""Claw"
NOTE="OcuTalon is inspired by $NAME and is not affiliated with or endorsed by the $NAME Foundation."
PLANT_PATH="/Use""rs/someone/work"
PLANT_KEY="sk-""ant-""aaaaaaaaaaaaaaaa"
PLANT_CLASS="Alpha.""Core"
COUCH="IRIS"" Couch"
PERSTEP="per"" step"
W=$tmp/w
C=$tmp/c
netm=$tmp/netmarks
ntmp=$tmp/ntmp
mkdir -p "$netm" "$ntmp" "$tmp/bin"
# The epics of release 1 (epics.md, Epic List): all but the step epics (17 to 28, 33 to 37) and the personality epics (39 to 41), which
# merge only after release/1.0.0-rc1 exists. The real-tree run tolerates an unmapped epic outside this list and fails on one inside it.
RELEASE1_EPICS=" 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 29 30 31 32 38 "
bad=0
fails_total=0
out=""
rc=0

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

for n in curl wget gh ssh nc; do
  printf '#!/bin/sh\n: > "$NETMARK/%s"\nexit 1\n' "$n" > "$tmp/bin/$n"
  chmod 755 "$tmp/bin/$n"
done

# --- the synthetic repository ---

write_tracker() { # write_tracker <file> <extra lines>
  {
    printf 'generated: x\ndevelopment_status:\n'
    printf '  epic-1: in-progress\n'
    printf '  1-1-install-the-thing: done\n'
    printf '  1-2-the-core-contract: done  # a comment\n'
    printf '  1-3-chat-in-the-page: done\n'
    printf '  epic-1-retrospective: optional\n'
    printf '  2-0-cleanup: done\n'
    printf '  2-1-watch-a-production: done\n'
    printf '  2-2-burn-down: done\n'
    printf '  3-1-approve-a-fix: backlog\n'
    printf '  3-9-ghost-story: done\n'
    [ -z "${2:-}" ] || printf '%s\n' "$2"
  } > "$1"
}

mkbase() {
  local b=$tmp/base
  mkdir -p "$b/release" "$b/docker/tests" "$b/src" "$b/_bmad-output/implementation-artifacts" "$b/_bmad-output/planning-artifacts"
  cp -p "$root/release/notes.sh" "$root/release/lib-release.sh" "$root/release/checklist.sh" "$b/release/"
  cp -p "$root/docker/tests/lib-scan.sh" "$root/docker/tests/lib-keys.sh" "$b/docker/tests/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$b/docker/tests/test-boundaries.sh"
  chmod 755 "$b/docker/tests/test-boundaries.sh"
  printf '<Export>\n  <Document name="ocutalon.ZPM">\n    <Module>\n      <Name>ocutalon</Name>\n      <Version>1.0.0</Version>\n    </Module>\n  </Document>\n</Export>\n' > "$b/src/module.xml"
  {
    printf '# Epics\n\n## Epic 1: Alpha\n\n'
    printf '### Story 1.3: Chat in the page\n\nbody\n\n'
    printf '### Story 1.1: Install the thing\n\nbody\n\n'
    printf '### Story 1.2: The %s contract\n\nbody\n\n' "$PLANT_CLASS"
    printf '## Epic 2: Beta\n\n'
    printf '### Story 2.0: Epic 1 deferred cleanup\n\nbody\n\n'
    printf '### Story 2.1: Watch a production\n\nbody\n\n'
    printf '### Story 2.2: Epic 2 burn-down\n\nbody\n\n'
    printf '## Epic 3: Gamma\n\n'
    printf '### Story 3.1: Approve a fix\n\nbody\n\n'
    printf '### Story 1.4: Extra chat\n\nbody\n'
  } > "$b/_bmad-output/planning-artifacts/epics.md"
  write_tracker "$b/_bmad-output/implementation-artifacts/sprint-status.yaml"
  printf '# the mapping\n\nepic 1 Install and start\nepic 2 Watching\nepic 3 Approvals\nstory 1.2 developer\n' > "$b/release/notes-areas.txt"
  git init -q "$b" || exit 1
  git -C "$b" checkout -q -b release/1.0.0-rc1
  git -C "$b" add -A
  git -C "$b" commit -q -m base
}

# --- one case ---

mkrec() { # mkrec: the record from the r_* and u_* variables
  {
    printf '# OcuTalon 1.0.0 rc1\n\n'
    if [ "$r_on" = 1 ]; then
      printf '## Clean-machine rehearsal\n\nResult: pass\nMode: %s\nCandidate: 1.0.0 rc1, branch release/1.0.0-rc1 at %s\n' "$r_mode" "$r_sha"
      printf 'Specs: the REL-2 specs at %s\nClean host: Ubuntu 24.04, 4 CPU, 8 GiB memory; Node.js absent\n' "$r_sha"
      printf 'Driver host: macOS 15, 8 CPU, 16 GiB memory\nRun: 2026-11-01T10:00:00Z to 2026-11-01T10:30:00Z\n\n'
      printf '| Step | Result | Detail |\n| --- | --- | --- |\n| Install | pass | first start 41 s, install included |\n| Decision | pass | 4 s |\n\n'
      printf '### Runs\n\n| Run | Decision | Tell now |\n| --- | --- | --- |\n| 1 | 4 s | 2 s |\n| 2 | 5 s | 3 s |\n\n'
    fi
    if [ "$u_on" = 1 ]; then
      printf '## Upgrade harness\n\nResult: pass\nMode: %s\nRequired: yes\nCandidate: 1.0.0 at %s\n' "$u_mode" "$u_sha"
      printf 'Previous: pre-release c9f1288 at c9f1288, version 0.1.0, built as 0.1.0\nNote: 1.0.0 is the first release, so its previous side is a pre-release build.\n'
      printf 'Run: 2026-11-01T11:00:00Z to 2026-11-01T11:20:00Z, tag upg-1\n\n'
      printf '| Record | Result | Detail |\n| --- | --- | --- |\n| Conversation | pass | kept |\n| Reminder | pass | kept |\n'
    fi
  } > "$rec"
}

mkeval() { # mkeval: the evaluation result from the e_* variables
  cat > "$ev" << EOF
{"format":"ocutalon.evalResult/1","commit":"$e_commit","onMock":$e_mock,"verdict":"$e_verdict","summary":{"scores":{
"items":{"right":19,"total":20,"share":$e_share,"target":0.9,"met":true},
"incidents":{"right":9,"total":10,"share":0.9,"target":0.8,"met":true},
"heldOutItems":{"right":5,"total":5,"share":1,"met":null},
"heldOutIncidents":{"right":2,"total":2,"share":1},
"injections":{"right":2,"total":2,"share":1},
"heldOutInjections":{"right":1,"total":1,"share":1},
"allClear":{"right":3,"total":3,"share":1},
"commands":{"right":1,"total":1,"share":1}},
"attentionCost":{"meanUSD":$e_mean,"maxUSD":0.0009},"size":{"largestTokens":1520}},"override":$e_override}
EOF
}

ready() { # ready: the case's inputs, with the sha of the checked-out commit
  sha=$(git -C "$W" rev-parse HEAD)
  r_mode=rehearsal u_mode=release r_sha=$sha u_sha=$sha r_on=1 u_on=1
  e_commit=$sha e_mock=false e_verdict=pass e_override=null e_share=0.95 e_mean=0.0006
  mkrec
  mkeval
}

newcase() {
  rm -rf "$W" "$C"
  cp -R "$tmp/base" "$W"
  mkdir -p "$C"
  rec=$C/rec.md
  ev=$C/eval.json
  notes=$C/out/notes.md
  ready
}

commit_all() {
  git -C "$W" add -A
  git -C "$W" commit -q -m mutation
  ready
}

after_run() { # after_run: a run of notes.sh called no network stub and left no temporary folder
  if [ -n "$(ls -A "$netm")" ]; then
    echo "  a network stub was called: $(ls "$netm" | tr '\n' ' ')"
    rm -f "$netm"/*
    bad=1
  fi
  if [ -n "$(ls -A "$ntmp")" ]; then
    echo "  a run left a temporary folder behind"
    rm -rf "${ntmp:?}"/*
    bad=1
  fi
}
run_notes() { # run_notes <args>: sets out and rc
  out=$(cd "$W" && NETMARK=$netm TMPDIR=$ntmp PATH="$tmp/bin:$PATH" bash release/notes.sh "$@" 2>&1)
  rc=$?
  after_run
}
run_std() { run_notes --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes "$notes" "$@"; }

failed_rows() { printf '%s\n' "$out" | grep '^FAIL ' | cut -d' ' -f2 | tr '\n' ' '; }
passed_rows() { printf '%s\n' "$out" | grep '^PASS ' | cut -d' ' -f2 | tr '\n' ' '; }
draft() { cat "$notes" 2> /dev/null; }
lineno() { grep -nF -m 1 -- "$2" "$1" | cut -d: -f1; }
dev_part() { awk '/^## For admins and developers$/ { f = 1 } f' "$notes"; }
pub_part() { awk '/^## For admins and developers$/ { exit } { print }' "$notes"; }
sums() { cat "$rec" "$ev" 2> /dev/null | cksum; }

expect_only() { # expect_only <label> <exit> <result> <failed rows, space separated>
  eq "$1: exit" "$rc" "$2"
  has "$1: result" "$out" "RESULT $3"
  eq "$1: failed rows" "$(failed_rows)" "$4"
}

# --- the rules ---

t_base() {
  local before refs d pub dev
  newcase
  before=$(sums)
  refs=$(git -C "$W" for-each-ref)
  run_std
  eq "base: no tracked file changed" "$(git -C "$W" status --porcelain)" ""
  eq "base: no tag or branch made" "$(git -C "$W" for-each-ref)" "$refs"
  eq "base: exit" "$rc" 0
  has "base: result" "$out" "RESULT draft"
  eq "base: all seven rows pass, in order" "$(passed_rows)" "stories areas eval rehearsal upgrade dev-only public-text "
  eq "base: the notes line" "$(printf '%s\n' "$out" | grep '^NOTES ')" "NOTES $notes"
  has "base: the stories row" "$out" "PASS stories 7 stories, all of them, for the first release"
  has "base: the areas row" "$out" "PASS areas 2 areas and 4 developer stories"
  eq "base: the record and the result are unchanged" "$(sums)" "$before"
  eq "base: only the notes file was written" "$(ls -A "$C/out")" "notes.md"
  eq "base: no record folder in the repository" "$([ -e "$W/release/records" ] && echo yes)" ""
  d=$(draft)
  pub=$(pub_part)
  dev=$(dev_part)
  has "base: provenance" "$d" "<!-- Drafted by release/notes.sh for OcuTalon 1.0.0 rc1 at $sha. Edit it before you publish it. -->"
  has "base: title" "$d" "# OcuTalon 1.0.0"
  has "base: intro" "$d" "This is the first release of OcuTalon."
  eq "base: the first line is the provenance comment" "$(head -n 1 "$notes" | cut -c1-30)" "<!-- Drafted by release/notes."
  has "base: area 1" "$pub" "## Install and start"
  has "base: area 2" "$pub" "## Watching"
  lacks "base: an area with no story is left out" "$d" "## Approvals"
  [ "$(lineno "$notes" '## Install and start')" -lt "$(lineno "$notes" '## Watching')" ] || { echo "  base: the areas are not in the mapping's order"; bad=1; }
  [ "$(lineno "$notes" '- Chat in the page')" -lt "$(lineno "$notes" '- Install the thing')" ] || { echo "  base: the titles are not in epics.md order"; bad=1; }
  has "base: a mapped story" "$pub" "- Watch a production"
  lacks "base: the developer story is not under an area" "$pub" "contract"
  lacks "base: the story numbered 0 is not under an area" "$pub" "deferred cleanup"
  lacks "base: the burn-down is not under an area" "$pub" "burn-down"
  lacks "base: the story with no heading is not under an area" "$pub" "ghost"
  has "base: developer story (mapped)" "$dev" "- 1.2 The $PLANT_CLASS contract"
  has "base: developer story (number 0)" "$dev" "- 2.0 Epic 1 deferred cleanup"
  has "base: developer story (burn-down)" "$dev" "- 2.2 Epic 2 burn-down"
  has "base: developer story (no heading, by its key)" "$dev" "- 3-9-ghost-story"
  has "base: scores head" "$d" "| Measure | Right | Of | Share | Target |"
  has "base: score 1" "$d" "| Items decided right | 19 | 20 | 95.0% | 90% |"
  has "base: score 2" "$d" "| Incidents diagnosed right | 9 | 10 | 90.0% | 80% |"
  has "base: score 3" "$d" "| Held-out items decided right | 5 | 5 | 100.0% | - |"
  has "base: score 4" "$d" "| Held-out incidents diagnosed right | 2 | 2 | 100.0% | - |"
  has "base: score 5" "$d" "| Injection attempts handled safely | 2 | 2 | 100.0% | - |"
  has "base: score 6" "$d" "| Held-out injection attempts handled safely | 1 | 1 | 100.0% | - |"
  has "base: score 7" "$d" "| All-clear answers right | 3 | 3 | 100.0% | - |"
  has "base: score 8" "$d" "| Command requests answered right | 1 | 1 | 100.0% | - |"
  has "base: result line" "$d" "Result: pass"
  has "base: cost" "$d" "- Cost per attention decision: mean \$0.0006, highest \$0.0009."
  has "base: size" "$d" "- Largest model request: 1,520 tokens."
  has "base: override" "$d" "- Override: none."
  lacks "base: no mock note" "$d" "The CI mock"
  has "base: rehearsal heading" "$pub" "### Clean-machine rehearsal"
  has "base: rehearsal result" "$pub" "Result: pass"
  has "base: rehearsal mode" "$pub" "Mode: rehearsal"
  has "base: clean host" "$pub" "Clean host: Ubuntu 24.04, 4 CPU, 8 GiB memory; Node.js absent"
  has "base: driver host" "$pub" "Driver host: macOS 15, 8 CPU, 16 GiB memory"
  has "base: rehearsal table" "$pub" "| Install | pass | first start 41 s, install included |"
  lacks "base: the runs table is not public" "$pub" "| 1 | 4 s | 2 s |"
  has "base: IPM package heading" "$pub" "### IPM package"
  has "base: registry install heading" "$pub" "### Registry install"
  has "base: upgrade heading" "$pub" "### Upgrade in place"
  has "base: upgrade mode" "$pub" "Mode: release"
  has "base: upgrade previous" "$pub" "Previous: pre-release c9f1288 at c9f1288, version 0.1.0, built as 0.1.0"
  has "base: upgrade note" "$pub" "Note: 1.0.0 is the first release, so its previous side is a pre-release build."
  lacks "base: the upgrade table is not public" "$pub" "| Conversation | pass | kept |"
  has "base: runs heading" "$dev" "### Rehearsal runs"
  has "base: runs table head" "$dev" "| Run | Decision | Tell now |"
  has "base: runs table row" "$dev" "| 2 | 5 s | 3 s |"
  has "base: upgrade checks heading" "$dev" "### Upgrade checks"
  has "base: upgrade table row" "$dev" "| Reminder | pass | kept |"
  lacks "base: the sha of the rehearsal's Candidate line is not copied" "$d" "branch release"
  lacks "base: the rehearsal's Specs: line is not copied" "$d" "Specs: the REL-2"
  lacks "base: no Run: line is copied" "$d" "Run: 2026-11-01"
  lacks "base: the upgrade's Required: line is not copied" "$d" "Required: yes"
  lacks "base: the upgrade's Candidate: line is not copied" "$d" "Candidate: 1.0.0 at"
}

# The IPM package and the registry install (Story 15.4): copied lines, the slot, and a record without the sections.
t_ipm() {
  local pub slot="Not run yet. After this version is published to the package registry, the guide's two commands are run once against the registry on a clean build 154 instance, and the result is recorded here."
  newcase
  {
    cat "$rec"
    printf '\n## IPM artifact\nResult: pass\nCandidate: 1.0.0 rc1, branch release/1.0.0-rc1 at %s\nSize: 4940070 bytes\nSHA-256: abc\n' "$sha"
    printf '\n## FR-57 job\nResult: pass\nCandidate: 1.0.0 rc1\nArtifact: ocutalon-1.0.0.tgz, 4940070 bytes\n'
  } > "$rec.new"
  mv "$rec.new" "$rec"
  run_std
  expect_only "with the sections" 0 draft ""
  pub=$(pub_part)
  has "with the sections: the size" "$pub" "IPM artifact size: 4940070 bytes"
  has "with the sections: the job result" "$pub" "IPM install check: pass"
  lacks "with the sections: no other line of the artifact section" "$pub" "SHA-256"
  has "with the sections: the slot" "$pub" "$slot"
  [ "$(lineno "$notes" '### Upgrade in place')" -lt "$(lineno "$notes" '### IPM package')" ] || { echo "  the IPM package follows the upgrade"; bad=1; }
  [ "$(lineno "$notes" '### IPM package')" -lt "$(lineno "$notes" '### Registry install')" ] || { echo "  the registry install follows the IPM package"; bad=1; }
  [ "$(lineno "$notes" '### Registry install')" -lt "$(lineno "$notes" '## For admins and developers')" ] || { echo "  the registry install is in the public part"; bad=1; }
  eq "with the sections: the slot appears once" "$(grep -cF "$slot" "$notes")" 1
  # a failed job and a failed artifact section are copied as they stand
  newcase
  { cat "$rec"; printf '\n## FR-57 job\nResult: fail\n'; } > "$rec.new"
  mv "$rec.new" "$rec"
  run_std
  has "a failed job: the result" "$(draft)" "IPM install check: fail"
  # a record without the sections says so, and still has the slot
  newcase
  run_std
  expect_only "without the sections" 0 draft ""
  pub=$(pub_part)
  has "without the sections: the size" "$pub" "IPM artifact size: not in the record."
  has "without the sections: the job result" "$pub" "IPM install check: not in the record."
  has "without the sections: the slot" "$pub" "$slot"
  # no record at all: the same, and the other inputs fail as they did
  newcase
  rm -f "$rec"
  run_std
  has "no record: the size" "$(draft)" "IPM artifact size: not in the record."
  has "no record: the slot" "$(draft)" "$slot"
}

t_later() {
  local d
  newcase
  git -C "$W" tag v1.0.0
  git -C "$W" checkout -q -b release/1.1.0-rc1
  sed -i.bak 's:<Version>1.0.0</Version>:<Version>1.1.0</Version>:' "$W/src/module.xml"
  rm -f "$W/src/module.xml.bak"
  write_tracker "$W/_bmad-output/implementation-artifacts/sprint-status.yaml" "  1-4-extra-chat: done"
  sed -i.bak 's|  3-1-approve-a-fix: backlog|  3-1-approve-a-fix: done|' "$W/_bmad-output/implementation-artifacts/sprint-status.yaml"
  rm -f "$W/_bmad-output/implementation-artifacts/sprint-status.yaml.bak"
  commit_all
  run_notes --version 1.1.0 --rc 1 --record "$rec" --eval "$ev" --notes "$notes"
  d=$(draft)
  has "later: stories row" "$out" "PASS stories 2 stories are new since v1.0.0"
  has "later: intro" "$d" "Changes since v1.0.0."
  lacks "later: not the first release" "$d" "This is the first release"
  has "later: a new story" "$d" "- Extra chat"
  has "later: a new story in a new area" "$d" "- Approve a fix"
  has "later: the new area" "$d" "## Approvals"
  lacks "later: an old story is left out" "$d" "Install the thing"
  lacks "later: an old story is left out (2)" "$d" "Watch a production"
  lacks "later: an old developer story is left out" "$d" "burn-down"
  # With no new story the stories row fails, naming the tag.
  newcase
  git -C "$W" tag v1.0.0
  git -C "$W" checkout -q -b release/1.1.0-rc1
  sed -i.bak 's:<Version>1.0.0</Version>:<Version>1.1.0</Version>:' "$W/src/module.xml"
  rm -f "$W/src/module.xml.bak"
  commit_all
  run_notes --version 1.1.0 --rc 1 --record "$rec" --eval "$ev" --notes "$notes"
  has "later, no new story: FAIL stories" "$out" "FAIL stories no story is done at the candidate and not done at v1.0.0"
  eq "later, no new story: failed rows" "$(failed_rows)" "stories "
  has "later, no new story: RESULT" "$out" "RESULT fail"
  eq "later, no new story: exit" "$rc" 1
  # A tag whose tree has no tracker.
  newcase
  git -C "$W" rm -q -r _bmad-output/implementation-artifacts
  git -C "$W" commit -q -m "no tracker"
  git -C "$W" tag v1.0.0
  git -C "$W" checkout -q -b release/1.1.0-rc1
  sed -i.bak 's:<Version>1.0.0</Version>:<Version>1.1.0</Version>:' "$W/src/module.xml"
  rm -f "$W/src/module.xml.bak"
  mkdir -p "$W/_bmad-output/implementation-artifacts"
  write_tracker "$W/_bmad-output/implementation-artifacts/sprint-status.yaml"
  commit_all
  run_notes --version 1.1.0 --rc 1 --record "$rec" --eval "$ev" --notes "$notes"
  has "later, a tag with no tracker: FAIL stories" "$out" "FAIL stories the previous tag v1.0.0 has no sprint tracker"
  eq "later, a tag with no tracker: failed rows" "$(failed_rows)" "stories "
  # A story whose slug was renamed since the tag is not new; the story id is what is compared.
  newcase
  git -C "$W" tag v1.0.0
  git -C "$W" checkout -q -b release/1.1.0-rc1
  sed -i.bak 's:<Version>1.0.0</Version>:<Version>1.1.0</Version>:' "$W/src/module.xml"
  rm -f "$W/src/module.xml.bak"
  write_tracker "$W/_bmad-output/implementation-artifacts/sprint-status.yaml" "  1-4-extra-chat: done"
  sed -i.bak 's|  1-1-install-the-thing: done|  1-1-install-it-renamed: done|' "$W/_bmad-output/implementation-artifacts/sprint-status.yaml"
  rm -f "$W/_bmad-output/implementation-artifacts/sprint-status.yaml.bak"
  commit_all
  run_notes --version 1.1.0 --rc 1 --record "$rec" --eval "$ev" --notes "$notes"
  has "later, a renamed slug: stories row" "$out" "PASS stories 1 stories are new since v1.0.0"
  has "later, a renamed slug: the new story" "$(draft)" "- Extra chat"
  lacks "later, a renamed slug: the renamed story is not new" "$(draft)" "Install the thing"
}

t_epics() {
  newcase
  git -C "$W" rm -q _bmad-output/planning-artifacts/epics.md
  commit_all
  run_std
  expect_only "no epics.md at the candidate" 1 fail "stories "
  has "no epics.md at the candidate: names the file" "$out" "FAIL stories the candidate has no story titles at _bmad-output/planning-artifacts/epics.md"
  newcase
  : > "$W/_bmad-output/planning-artifacts/epics.md"
  commit_all
  run_std
  expect_only "an empty epics.md at the candidate" 1 fail "stories "
  has "an empty epics.md at the candidate: names the file" "$out" "epics.md"
}

t_areas() {
  local pub
  # The areas follow the mapping's order, not epics.md's.
  newcase
  printf '# the mapping\n\nepic 2 Watching\nepic 1 Install and start\nepic 3 Approvals\nstory 1.2 developer\n' > "$W/release/notes-areas.txt"
  run_std
  eq "a mapping in another order: exit" "$rc" 0
  [ "$(lineno "$notes" '## Watching')" -lt "$(lineno "$notes" '## Install and start')" ] || { echo "  the areas do not follow the mapping's order"; bad=1; }
  # A story line moves one story into another named area.
  newcase
  printf 'story 1.1 Watching\n' >> "$W/release/notes-areas.txt"
  run_std
  eq "a story line to a named area: exit" "$rc" 0
  pub=$(pub_part)
  has "a story line to a named area: the story" "$pub" "- Install the thing"
  [ "$(lineno "$notes" '- Chat in the page')" -lt "$(lineno "$notes" '## Watching')" ] || { echo "  the story stayed in a later area"; bad=1; }
  [ "$(lineno "$notes" '## Watching')" -lt "$(lineno "$notes" '- Install the thing')" ] || { echo "  the story did not land in the named area"; bad=1; }
  [ "$(lineno "$notes" '- Install the thing')" -lt "$(lineno "$notes" '- Watch a production')" ] || { echo "  the moved story is not listed with its area"; bad=1; }
}

t_inputs() {
  local d
  newcase
  rm -f "$ev"
  run_std
  expect_only "no evaluation file" 1 fail "eval "
  d=$(draft)
  has "no evaluation file: Not available" "$d" "Not available: no evaluation result for this candidate."
  newcase
  printf '{not json\n' > "$ev"
  run_std
  expect_only "invalid JSON" 1 fail "eval "
  has "invalid JSON: Not available" "$(draft)" "Not available: no evaluation result for this candidate."
  lacks "invalid JSON: no score table" "$(draft)" "| Measure |"
  newcase
  sed -i.bak 's:ocutalon.evalResult/1:ocutalon.evalResult/2:' "$ev"
  run_std
  expect_only "another format" 1 fail "eval "
  newcase
  e_commit=0000000000000000000000000000000000000000
  mkeval
  run_std
  expect_only "another commit" 1 fail "eval "
  has "another commit: Not available" "$(draft)" "Not available: no evaluation result for this candidate."
  newcase
  rm -f "$rec"
  run_std
  expect_only "no record" 1 fail "rehearsal upgrade "
  has "no record: rehearsal line" "$(draft)" "Not available: no clean-machine rehearsal for this candidate."
  has "no record: upgrade line" "$(draft)" "Not available: no upgrade result for this candidate."
  newcase
  r_on=0
  mkrec
  run_std
  expect_only "no rehearsal section" 1 fail "rehearsal "
  has "no rehearsal section: Not available" "$(draft)" "Not available: no clean-machine rehearsal for this candidate."
  lacks "no rehearsal section: the runs table is left out" "$(draft)" "### Rehearsal runs"
  has "no rehearsal section: the upgrade is still in" "$(draft)" "### Upgrade checks"
  newcase
  r_sha=1111111111111111111111111111111111111111
  mkrec
  run_std
  expect_only "a rehearsal of another sha" 1 fail "rehearsal "
  newcase
  u_on=0
  mkrec
  run_std
  expect_only "no upgrade section" 1 fail "upgrade "
  has "no upgrade section: Not available" "$(draft)" "Not available: no upgrade result for this candidate."
  lacks "no upgrade section: the upgrade table is left out" "$(draft)" "### Upgrade checks"
  newcase
  u_sha=2222222222222222222222222222222222222222
  mkrec
  run_std
  expect_only "an upgrade of another sha" 1 fail "upgrade "
  newcase
  sed -i.bak '/^epic 2 /d' "$W/release/notes-areas.txt"
  run_std
  expect_only "an unmapped epic" 1 fail "areas "
  has "an unmapped epic: named" "$out" "FAIL areas no area for epic 2"
  newcase
  printf 'epic nine Nine\n' >> "$W/release/notes-areas.txt"
  run_std
  expect_only "a malformed mapping line" 1 fail "areas "
  has "a malformed mapping line: file:line" "$out" "  release/notes-areas.txt:7"
  lacks "a malformed mapping line: not the text" "$out" "nine"
  newcase
  rm -f "$W/release/notes-areas.txt"
  run_std
  expect_only "no mapping file" 1 fail "areas "
  # The evaluation fails closed.
  newcase
  sed -i.bak 's/"onMock":false,//' "$ev"
  run_std
  expect_only "an evaluation without onMock" 1 fail "eval "
  newcase
  sed -i.bak 's/"verdict":"pass"/"verdict":""/' "$ev"
  run_std
  expect_only "an evaluation with an empty verdict" 1 fail "eval "
  newcase
  printf 'null\n' > "$ev"
  run_std
  expect_only "an evaluation that is JSON null" 1 fail "eval "
  # A section without its Result: or Mode: line fails its own row alone.
  newcase
  sed -i.bak '/^## Clean-machine rehearsal/,/^## Upgrade harness/{/^Mode: /d;}' "$rec"
  run_std
  expect_only "a rehearsal without Mode:" 1 fail "rehearsal "
  newcase
  sed -i.bak '/^## Clean-machine rehearsal/,/^## Upgrade harness/{/^Result: /d;}' "$rec"
  run_std
  expect_only "a rehearsal without Result:" 1 fail "rehearsal "
  newcase
  sed -i.bak '/^## Upgrade harness/,${/^Mode: /d;}' "$rec"
  run_std
  expect_only "an upgrade without Mode:" 1 fail "upgrade "
  newcase
  sed -i.bak '/^## Upgrade harness/,${/^Result: /d;}' "$rec"
  run_std
  expect_only "an upgrade without Result:" 1 fail "upgrade "
}

t_eval_forms() {
  local d
  newcase
  e_verdict=overridden e_override='{"reason":"Attempt 3 missed by one item","at":"2026-11-01T09:00:00Z"}'
  mkeval
  run_std
  d=$(draft)
  eq "overridden: exit" "$rc" 0
  has "overridden: result line" "$d" "Result: overridden"
  has "overridden: the reason" "$d" "- Override: the author overrode a blocked result. Reason: Attempt 3 missed by one item"
  lacks "overridden: not none" "$d" "Override: none."
  newcase
  e_share=null e_mean=null
  mkeval
  run_std
  d=$(draft)
  eq "null share and cost: exit" "$rc" 0
  has "null share" "$d" "| Items decided right | 19 | 20 | not measured | 90% |"
  has "null cost" "$d" "- Cost per attention decision: mean not measured, highest \$0.0009."
}

t_dry() {
  local d
  newcase
  e_mock=true
  mkeval
  run_std
  d=$(draft)
  eq "mock: exit" "$rc" 3
  has "mock: result" "$out" "RESULT dry run"
  eq "mock: no row fails" "$(failed_rows)" ""
  has "mock: note" "$d" "Note: The CI mock stood in for the model, so these figures are not the release's."
  newcase
  r_mode="dry run"
  mkrec
  run_std
  eq "dry-run rehearsal: exit" "$rc" 3
  has "dry-run rehearsal: result" "$out" "RESULT dry run"
  has "dry-run rehearsal: the mode is copied" "$(draft)" "Mode: dry run"
  newcase
  u_mode=rehearsal
  mkrec
  run_std
  eq "non-release upgrade: exit" "$rc" 3
  has "non-release upgrade: result" "$out" "RESULT dry run"
  newcase
  e_mock=true
  mkeval
  rm -f "$rec"
  run_std
  eq "mock with a failed row: exit" "$rc" 1
  has "mock with a failed row: result" "$out" "RESULT fail"
}

t_checks() {
  local d
  newcase
  sed -i.bak "s:Chat in the page:Chat in the $PLANT_CLASS page:" "$W/_bmad-output/planning-artifacts/epics.md"
  rm -f "$W/_bmad-output/planning-artifacts/epics.md.bak"
  commit_all
  run_std
  expect_only "a class name in a mapped title" 1 fail "dev-only "
  has "a class name in a mapped title: file:line" "$out" "notes.md:"
  lacks "a class name in a mapped title: not the text" "$out" "$PLANT_CLASS"
  eq "a class name in a mapped title: the draft is kept" "$([ -f "$notes" ] && echo yes)" yes
  # The same title as a developer story passes (the base case holds story 1.2).
  newcase
  run_std
  has "the same name in a developer story passes" "$out" "PASS dev-only"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"saved under $PLANT_PATH today\",\"at\":\"x\"}"
  mkeval
  run_std
  expect_only "a local path" 1 fail "public-text "
  has "a local path: file:line" "$out" "notes.md:"
  lacks "a local path: not the text" "$out" "someone"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"the key was $PLANT_KEY\",\"at\":\"x\"}"
  mkeval
  run_std
  expect_only "key-like text" 1 fail "public-text "
  lacks "key-like text: not the text" "$out" "aaaaaaaa"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"copied from $NAME and renamed\",\"at\":\"x\"}"
  mkeval
  run_std
  expect_only "the name outside the note" 1 fail "public-text "
  has "the name outside the note: file:line" "$out" "notes.md:"
  lacks "the name outside the note: not the text" "$out" "renamed"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"copied from $(printf '%s' "$NAME" | tr a-z A-Z) and renamed\",\"at\":\"x\"}"
  mkeval
  run_std
  expect_only "the name in another case outside the note" 1 fail "public-text "
  lacks "the name in another case: not the text" "$out" "renamed"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"$NOTE\",\"at\":\"x\"}"
  mkeval
  run_std
  eq "the note word for word passes" "$rc" 0
  has "the note word for word: public-text" "$out" "PASS public-text"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"$NOTE and also $NAME\",\"at\":\"x\"}"
  mkeval
  run_std
  expect_only "the note and the name again" 1 fail "public-text "
}

t_defaults() {
  local d
  # With no --record, --eval, --notes, --candidate or --areas, the defaults are the record's, the evaluation's and the notes' own paths.
  newcase
  mkdir -p "$W/release/records/1.0.0" "$W/eval"
  cp "$rec" "$W/release/records/1.0.0/rc1.md"
  cp "$ev" "$W/eval/release-candidate.json"
  run_notes --version 1.0.0 --rc 1
  eq "defaults: exit" "$rc" 0
  has "defaults: result" "$out" "RESULT draft"
  has "defaults: the notes line" "$out" "NOTES release/records/1.0.0/rc1-notes.md"
  eq "defaults: the notes file" "$([ -f "$W/release/records/1.0.0/rc1-notes.md" ] && echo yes)" yes
  eq "defaults: nothing else written beside the record" "$(ls -A "$W/release/records/1.0.0" | tr '\n' ' ')" "rc1-notes.md rc1.md "
  eq "defaults: the record is unchanged" "$(cksum < "$W/release/records/1.0.0/rc1.md")" "$(cksum < "$rec")"
  # The tracker comes from the candidate commit, not from the working tree.
  write_tracker "$W/_bmad-output/implementation-artifacts/sprint-status.yaml" "  1-4-extra-chat: done"
  run_notes --version 1.0.0 --rc 1 --replace
  has "working tree: the stories row" "$out" "PASS stories 7 stories"
  lacks "working tree: an uncommitted story is not listed" "$(cat "$W/release/records/1.0.0/rc1-notes.md")" "Extra chat"
  # --candidate names another commit than the checked-out one.
  newcase
  git -C "$W" checkout -q -b other
  write_tracker "$W/_bmad-output/implementation-artifacts/sprint-status.yaml" "  1-4-extra-chat: done"
  commit_all
  git -C "$W" checkout -q release/1.0.0-rc1
  run_std --candidate other
  d=$(draft)
  eq "another candidate: exit" "$rc" 0
  has "another candidate: the stories row" "$out" "PASS stories 8 stories"
  has "another candidate: its story" "$d" "- Extra chat"
  has "another candidate: its sha" "$d" "at $(git -C "$W" rev-parse other). Edit it"
}

t_integration() {
  local o
  newcase
  run_notes --version 1.0.0 --rc 1 --record "$rec" --eval "$ev"
  eq "integration: the draft at the default notes path: exit" "$rc" 0
  eq "integration: the default notes path" "$([ -f "$W/release/records/1.0.0/rc1-notes.md" ] && echo yes)" yes
  o=$(cd "$W" && bash -c '. release/checklist.sh; ck_notes=$PWD/$(notes_path 1.0.0 1); row_public_text' 2>&1)
  eq "integration: row_public_text on the default path" "$o" "PASS public-text docker/tests/test-boundaries.sh passed, and the draft notes hold no local path or key-like text"
  newcase
  e_verdict=overridden e_override="{\"reason\":\"saved under $PLANT_PATH today\",\"at\":\"x\"}"
  mkeval
  run_notes --version 1.0.0 --rc 1 --record "$rec" --eval "$ev"
  has "integration: notes.sh fails public-text" "$out" "FAIL public-text"
  o=$(cd "$W" && bash -c '. release/checklist.sh; ck_notes=$PWD/$(notes_path 1.0.0 1); row_public_text' 2>&1)
  has "integration: row_public_text fails on the planted path" "$o" "FAIL public-text"
}

refused() { # refused <label> <args>: exit 2, one REFUSED line, nothing written
  local label=$1
  shift
  run_notes "$@"
  eq "$label: exit" "$rc" 2
  eq "$label: one REFUSED line" "$(printf '%s\n' "$out" | grep -c '^REFUSED ')/$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1/1"
  eq "$label: nothing written" "$([ -e "$C/out" ] && echo yes)" ""
}

t_refusals() {
  local std sum
  newcase
  std="--record $rec --eval $ev --notes $notes"
  # shellcheck disable=SC2086
  {
    refused "an unknown option" --version 1.0.0 --rc 1 $std --nope
    refused "no --version" --rc 1 $std
    refused "no --rc" --version 1.0.0 $std
    refused "a version that is not x.y.z" --version 1.0 --rc 1 $std
    refused "an rc of 0" --version 1.0.0 --rc 0 $std
    refused "an rc that is not a number" --version 1.0.0 --rc x $std
    refused "an option without a value" --version 1.0.0 --rc 1 --record
    refused "an option value that is the next option" --version 1.0.0 --rc 1 --record --eval "$ev" --notes "$notes"
    has "an option value that is the next option: says so" "$out" "REFUSED --record needs a value"
    refused "a candidate that starts with a dash" --version 1.0.0 --rc 1 --candidate -x $std
    has "a candidate that starts with a dash: says so" "$out" "REFUSED --candidate needs a value"
    refused "a notes value that starts with a dash" --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes -x
    refused "an unknown candidate" --version 1.0.0 --rc 2 $std
    refused "a version that differs from module.xml" --version 1.0.1 --rc 1 --candidate HEAD $std
  }
  # The notes file may not be the record, the evaluation result or the mapping, even with --replace.
  sum=$(cat "$rec" "$ev" "$W/release/notes-areas.txt" | cksum)
  ln -s "$rec" "$C/rec-link.md"
  # shellcheck disable=SC2086
  {
    refused "notes is the record" --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes "$rec" --replace
    refused "notes is the evaluation result" --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes "$ev" --replace
    refused "notes is the mapping" --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --areas "$W/release/notes-areas.txt" --notes "$W/release/notes-areas.txt" --replace
    refused "notes is a link to the record" --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes "$C/rec-link.md" --replace
  }
  eq "the inputs are unchanged by those refusals" "$(cat "$rec" "$ev" "$W/release/notes-areas.txt" | cksum)" "$sum"
  # Nor a tracked file of the repository, even with --replace.
  refused "notes is a tracked file" --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes src/module.xml --replace
  has "notes is a tracked file: says so" "$out" "REFUSED the notes file src/module.xml is a tracked file of the repository"
  eq "notes is a tracked file: the tree is unchanged" "$(git -C "$W" status --porcelain)" ""
  # A draft that cannot be completed is never moved into place, and no temporary file stays.
  mkdir -p "$tmp/failbin"
  printf '#!/bin/sh\ncase "$*" in *intro.txt*) exit 1 ;; esac\nexec /bin/cat "$@"\n' > "$tmp/failbin/cat"
  chmod 755 "$tmp/failbin/cat"
  out=$(cd "$W" && NETMARK=$netm TMPDIR=$ntmp PATH="$tmp/failbin:$tmp/bin:$PATH" bash release/notes.sh --version 1.0.0 --rc 1 --record "$rec" --eval "$ev" --notes "$notes" 2>&1)
  rc=$?
  after_run
  eq "a draft that fails: exit" "$rc" 2
  has "a draft that fails: REFUSED" "$out" "REFUSED the draft could not be written"
  eq "a draft that fails: one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
  eq "a draft that fails: no notes file and no temporary file" "$(ls -A "$C/out" 2> /dev/null)" ""
  rm -rf "$C/out"
  # A shallow repository.
  rm -rf "$tmp/shallow"
  git clone -q --depth 1 "file://$tmp/base" "$tmp/shallow" 2> /dev/null
  out=$(cd "$tmp/shallow" && git checkout -q release/1.0.0-rc1 2> /dev/null; NETMARK=$netm TMPDIR=$ntmp PATH="$tmp/bin:$PATH" bash release/notes.sh --version 1.0.0 --rc 1 --candidate HEAD --record "$rec" --eval "$ev" --notes "$notes" 2>&1)
  rc=$?
  after_run
  eq "a shallow repository: exit" "$rc" 2
  has "a shallow repository: says so" "$out" "REFUSED the repository is shallow"
  eq "a shallow repository: nothing written" "$([ -e "$C/out" ] && echo yes)" ""
  # Not a git repository.
  rm -rf "$tmp/nogit"
  mkdir -p "$tmp/nogit"
  cp -R "$tmp/base/release" "$tmp/base/docker" "$tmp/nogit/"
  out=$(cd "$tmp/nogit" && NETMARK=$netm TMPDIR=$ntmp PATH="$tmp/bin:$PATH" bash release/notes.sh --version 1.0.0 --rc 1 $std 2>&1)
  rc=$?
  after_run
  eq "not a git repository: exit" "$rc" 2
  has "not a git repository: says so" "$out" "is not the root of a git repository"
  has "not a git repository: REFUSED" "$out" "REFUSED "
  eq "not a git repository: nothing written" "$([ -e "$C/out" ] && echo yes)" ""
  # An existing notes file is refused, left unchanged, and rewritten only with --replace.
  run_std
  eq "the first run: exit" "$rc" 0
  printf 'the author edit\n' >> "$notes"
  sum=$(cksum < "$notes")
  run_std
  eq "an existing notes file: exit" "$rc" 2
  eq "an existing notes file: one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
  has "an existing notes file: REFUSED" "$out" "REFUSED "
  eq "an existing notes file: unchanged" "$(cksum < "$notes")" "$sum"
  run_std --replace
  eq "--replace: exit" "$rc" 0
  eq "--replace: rewritten" "$(grep -c 'the author edit' "$notes")" 0
  has "--replace: the draft is back" "$(draft)" "# OcuTalon 1.0.0"
  eq "--replace: only the notes file" "$(ls -A "$C/out")" "notes.md"
}

t_nonetwork() {
  local n
  # The stubs are live: each, called through the PATH that every run uses, leaves its marker.
  for n in curl wget gh ssh nc; do
    (NETMARK=$netm PATH="$tmp/bin:$PATH" "$n" x > /dev/null 2>&1)
  done
  eq "no-network: every stub leaves its marker" "$(ls "$netm" | tr '\n' ' ')" "curl gh nc ssh wget "
  rm -f "$netm"/*
  # A full real-mode run calls none of them (after_run checks the markers).
  newcase
  run_std
  eq "no-network: a real-mode run" "$rc" 0
}

t_library() {
  local o r
  r=$tmp/lib
  rm -rf "$r"
  mkdir -p "$r"
  git init -q "$r"
  git -C "$r" commit -q --allow-empty -m one
  o=$(. "$root/release/lib-release.sh"; release_previous_tag HEAD 1.0.0 "$r")
  eq "release_previous_tag: no tag" "$o" ""
  git -C "$r" tag v1.0.0
  git -C "$r" commit -q --allow-empty -m two
  o=$(. "$root/release/lib-release.sh"; release_previous_tag HEAD 1.1.0 "$r")
  eq "release_previous_tag: the tag below" "$o" "v1.0.0"
  git -C "$r" tag v1.1.0-rc1
  git -C "$r" commit -q --allow-empty -m three
  o=$(. "$root/release/lib-release.sh"; release_previous_tag HEAD 1.1.0 "$r")
  eq "release_previous_tag: a pre-release before its release" "$o" "v1.1.0-rc1"
  git -C "$r" tag v1.1.0
  git -C "$r" commit -q --allow-empty -m four
  o=$(. "$root/release/lib-release.sh"; release_previous_tag HEAD 1.1.0 "$r")
  eq "release_previous_tag: skips v<version>" "$o" "v1.1.0-rc1"
  o=$(. "$root/release/lib-release.sh"; release_previous_tag HEAD 1.2.0 "$r")
  eq "release_previous_tag: the highest release" "$o" "v1.1.0"
  git -C "$r" tag v1.2.0-rc1
  o=$(. "$root/release/lib-release.sh"; release_previous_tag HEAD 1.2.0 "$r")
  eq "release_previous_tag: skips a tag on the ref" "$o" "v1.1.0"
  o=$(cd "$r" && . "$root/release/lib-release.sh"; release_previous_tag HEAD 1.2.0)
  eq "release_previous_tag: the current folder by default" "$o" "v1.1.0"
  printf 'plain\nSee ##class(A.B).C() here\n## For admins and developers\nIn ##class(A.B).C() it is fine\n## Other\nERROR #5001 outside\nFine text, Node.js too\n' > "$tmp/sec.md"
  o=$(. "$root/docker/tests/lib-scan.sh"; names_outside_section '## For admins and developers' "$tmp/sec.md" | tr '\n' ' ')
  eq "names_outside_section: lines outside the section" "$o" "$tmp/sec.md:2 $tmp/sec.md:6 "
  printf 'An <UNDEFINED> error\n%s here\nPlain words, v1.0.0 and 3.5 are fine\n## For admins and developers\n<UNDEFINED> in the section\n' "$PLANT_CLASS" > "$tmp/sec2.md"
  o=$(. "$root/docker/tests/lib-scan.sh"; names_outside_section '## For admins and developers' "$tmp/sec2.md" "$tmp/sec.md" | tr '\n' ' ')
  eq "names_outside_section: an error name, a dotted class name, two files" "$o" "$tmp/sec2.md:1 $tmp/sec2.md:2 $tmp/sec.md:2 $tmp/sec.md:6 "
  o=$(. "$root/docker/tests/lib-scan.sh"; names_outside_section '## Other' "$tmp/sec.md" | tr '\n' ' ')
  eq "names_outside_section: the heading is a parameter" "$o" "$tmp/sec.md:2 $tmp/sec.md:4 "
  o=$(. "$root/docker/tests/lib-scan.sh"; names_outside_section "$(printf '%s\n%s' '## For admins and developers' '## Other')" "$tmp/sec.md" | tr '\n' ' ')
  eq "names_outside_section: several headings, one per line, are all exempt" "$o" "$tmp/sec.md:2 "
}

# static_names <ipm load line> <file>: file:line of each line names_outside_section reports outside "For admins and developers" and
# "Gmail and Microsoft 365" (the sections test-readme.sh's dev_names exempts), except the line that equals the IPM load line.
static_names() {
  local ipm_load=$1 f=$2 n
  (. docker/tests/lib-scan.sh; names_outside_section "$(printf '%s\n%s' '## For admins and developers' '## Gmail and Microsoft 365')" "$f") |
    while IFS=: read -r f n; do [ -n "$ipm_load" ] && [ "$(sed -n "${n}p" "$f")" = "$ipm_load" ] || printf '%s:%s\n' "$f" "$n"; done
}

static_hits() { # static_hits <file>: one line per violation
  local f=$1
  [ -x "$f" ] || echo "$f: not executable"
  if [ -n "$(git ls-files --stage -- "$f" 2> /dev/null)" ] && ! git ls-files --stage -- "$f" | grep -q '^100755 '; then echo "$f: not mode 100755 in git"; fi
  grep -q '^umask 077$' "$f" || echo "$f: no umask 077"
  LC_ALL=C grep -n '[^[:print:][:space:]]' "$f" | sed "s|^|$f: not ASCII: |"
  grep -qF '[ "${BASH_SOURCE[0]}" != "$0" ] && return 0' "$f" || echo "$f: no main guard"
  grep -vE '^[[:space:]]*#' "$f" | grep -nE '(^|[^A-Za-z0-9_./-])(curl|wget|gh|ssh|nc)[[:space:]]|git[[:space:]]+(fetch|pull|push|ls-remote|clone)' | sed "s|^|$f: network command: |"
  (. "$root/release/checklist.sh"; outward_hits "$f") | sed "s|^|$f: an outward string: |"
  grep -n -i -e "$(printf '%s' "$NAME" | sed 's/./[&]/1; s/\(.*\)\(.\)$/\1[\2]/')" "$f" | sed "s|^|$f: the name: |"
  grep -n -i -F -e "$COUCH" -e "$PERSTEP" "$f" | sed "s|^|$f: a banned phrase: |"
}

t_static() {
  local o
  printf '#!/usr/bin/env bash\necho "caf\303\251"\ncurl http://x\nssh h\ngit fetch\nrun gh x\necho %s\necho %s\necho %s\n' "$NAME" "$COUCH" "$PERSTEP" > "$tmp/bad-static.sh"
  printf 'echo %s\n' "--visib""ility" >> "$tmp/bad-static.sh"
  o=$(static_hits "$tmp/bad-static.sh")
  has "break: mode" "$o" "not executable"
  has "break: umask" "$o" "no umask 077"
  has "break: ASCII" "$o" "not ASCII"
  has "break: main guard" "$o" "no main guard"
  eq "break: network lines" "$(printf '%s\n' "$o" | grep -c 'network command')" 4
  has "break: an outward string" "$o" "an outward string"
  has "break: the name" "$o" "the name"
  eq "break: the banned phrases" "$(printf '%s\n' "$o" | grep -c 'a banned phrase')" 2
  o=$(static_hits release/notes.sh)
  eq "release/notes.sh keeps the static rules" "$o" ""
  o=$(static_hits docker/tests/test-release-notes.sh | grep -v -e 'a banned phrase' -e 'the name' -e 'an outward string')
  eq "this file is executable, mode 100755 and ASCII" "$(printf '%s\n' "$o" | grep -e 'not executable' -e 'not ASCII' -e 'not mode')" ""
  eq "this file does not spell the name" "$(grep -c -i -e '[o]pen[c]law' docker/tests/test-release-notes.sh)" 0
  eq "this file does not spell the banned phrases" "$(grep -c -F -e "$COUCH" -e "$PERSTEP" docker/tests/test-release-notes.sh)" 0
  eq "release/notes-areas.txt is ASCII" "$(LC_ALL=C grep -c '[^[:print:][:space:]]' release/notes-areas.txt)" 0
  # One not-affiliated note: the draft's (release/notes.sh), the checklist's (release/checklist.sh) and the README's line.
  eq "the note of release/notes.sh" "$(. release/notes.sh; printf '%s' "$notes_note")" "$NOTE"
  eq "the note of release/checklist.sh" "$(. release/checklist.sh; printf '%s' "$CK_NOTE")" "$NOTE"
  [ "$(grep -c -F -- "$NOTE" README.md)" -gt 0 ] || { echo "  README.md does not hold the note word for word"; bad=1; }
  # names_outside_section is the README's own developer-section rule (dev_names of test-readme.sh): it finds nothing there either,
  # except the line that equals IPM_LOAD of test-readme.sh word for word (read from that one line; a changed load line is reported).
  local ipm_load s
  ipm_load=$(sed -n "s/^IPM_LOAD='\(.*\)'\$/\1/p" docker/tests/test-readme.sh)
  [ -n "$ipm_load" ] || { echo "  static: docker/tests/test-readme.sh holds no IPM_LOAD='...' line"; bad=1; }
  printf '%s\n%sx\nThe class %s does it.\n' "$ipm_load" "$ipm_load" "$PLANT_CLASS" > "$tmp/ipm.md"
  for s in "$tmp/ipm.md" README.md GUIDE.md; do
    o=$(static_names "$ipm_load" "$s")
    if [ "$s" = README.md ] || [ "$s" = GUIDE.md ]; then eq "names_outside_section on $s" "$o" ""
    else eq "break: the load line changed and a class name are reported" "$(printf '%s' "$o" | tr '\n' ' ')" "$s:2 $s:3"; fi
  done
  # The guide's "Gmail and Microsoft 365" section is exempt like "For admins and developers"; any other section is not.
  grep -qxF '## Gmail and Microsoft 365' GUIDE.md || { echo "  static: GUIDE.md holds no Gmail and Microsoft 365 section"; bad=1; }
  printf '\n## Elsewhere\n\nThe class %s does it.\n' "$PLANT_CLASS" | cat GUIDE.md - > "$tmp/guide-else.md"
  o=$(static_names "$ipm_load" "$tmp/guide-else.md")
  eq "break: a class name planted in another guide section is reported" "$o" "$tmp/guide-else.md:$(wc -l < "$tmp/guide-else.md" | tr -d ' ')"
  awk -v c="$PLANT_CLASS" '{ print } $0 == "## Gmail and Microsoft 365" { print "\nThe class " c " does it.\n" }' GUIDE.md > "$tmp/guide-gm.md"
  [ "$(grep -c -F -- "The class $PLANT_CLASS does it." "$tmp/guide-gm.md")" -eq 1 ] || { echo "  static: the planted line is not in the Gmail section copy"; bad=1; }
  o=$(static_names "$ipm_load" "$tmp/guide-gm.md")
  eq "a dotted name in the guide's Gmail and Microsoft 365 section is not reported" "$o" ""
}

areas_ok_real() { # areas_ok_real: the areas row of $out passes, or fails only for unmapped epics outside RELEASE1_EPICS
  local l e
  l=$(printf '%s\n' "$out" | grep -m 1 -E '^(PASS|FAIL) areas ')
  case $l in
    "PASS areas "*) return 0 ;;
    "FAIL areas no area for epic "*) ;;
    *) return 1 ;;
  esac
  l=${l#FAIL areas no area for }
  case $l in *";"*) return 1 ;; esac
  for e in $(printf '%s\n' "$l" | tr ',' '\n' | sed 's/^ *epic //'); do
    case $e in "" | *[!0-9]*) return 1 ;; esac
    case $RELEASE1_EPICS in *" $e "*) return 1 ;; esac
  done
  return 0
}

mkreal() { # mkreal <dir>: a fresh repository (no tag) with the real scripts and mapping, and HEAD's module.xml, tracker and epics.md
  local r=$1 f
  rm -rf "$r"
  for f in release/notes.sh release/lib-release.sh release/notes-areas.txt docker/tests/lib-scan.sh docker/tests/lib-keys.sh; do
    mkdir -p "$r/$(dirname "$f")"
    cp -p "$f" "$r/$f"
  done
  for f in src/module.xml _bmad-output/implementation-artifacts/sprint-status.yaml _bmad-output/planning-artifacts/epics.md; do
    mkdir -p "$r/$(dirname "$f")"
    git show "HEAD:$f" > "$r/$f"
  done
  git init -q "$r" && git -C "$r" add -A && git -C "$r" commit -q -m real
}

run_real() { # run_real <dir> <args>: notes.sh in the fresh repository on its HEAD, with temporary inputs; sets out and rc
  local r=$1
  shift
  out=$(cd "$r" && NETMARK=$netm TMPDIR=$ntmp PATH="$tmp/bin:$PATH" bash release/notes.sh --version "$version" --rc 1 --candidate HEAD \
    --record "$d/rc1.md" --eval "$d/none.json" --notes "$d/notes.md" "$@" 2>&1)
  rc=$?
  after_run
}

t_real() {
  local d r version o stories epics n
  d=$tmp/real
  r=$tmp/realtree
  mkdir -p "$d"
  # The mapping parses, and every story line names a story heading and every epic line an epic heading of the real epics.md.
  o=$(. release/notes.sh; : > "$d/none.txt"; notes_areas release/notes-areas.txt "$d/none.txt" | grep '^!' | tr '\n' ' ')
  eq "the real mapping parses" "$o" ""
  stories=$(sed -n 's/^### Story \([0-9]*\.[0-9]*\):.*/\1/p' _bmad-output/planning-artifacts/epics.md | sort -u)
  epics=$(sed -n 's/^## Epic \([0-9]*\):.*/\1/p' _bmad-output/planning-artifacts/epics.md | sort -u)
  n=0
  while read -r kind id _; do
    case $kind in
      story)
        printf '%s\n' "$stories" | grep -qxF "$id" || { echo "  story $id of the mapping has no heading in epics.md"; bad=1; }
        n=$((n + 1))
        ;;
      epic) printf '%s\n' "$epics" | grep -qxF "$id" || { echo "  epic $id of the mapping has no heading in epics.md"; bad=1; } ;;
    esac
  done < release/notes-areas.txt
  [ "$n" -gt 0 ] || { echo "  the real mapping holds no story line"; bad=1; }
  # A run on a fresh repository with no tag, so neither the checkout's tags nor an epic outside release 1 decides the result.
  mkreal "$r"
  version=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$r/src/module.xml" | head -n 1)
  run_real "$r"
  eq "real tree: exit" "$rc" 1
  has "real tree: RESULT" "$out" "RESULT fail"
  eq "real tree: failed rows" "$(failed_rows | sed 's/^areas //')" "eval rehearsal upgrade "
  eq "real tree: passed rows" "$(passed_rows | sed 's/ areas / /')" "stories dev-only public-text "
  areas_ok_real || { echo "  real tree: $(printf '%s\n' "$out" | grep -m 1 '^FAIL areas ') (an epic of release 1, or a mapping line)"; bad=1; }
  eq "real tree: the repository is unchanged" "$(git -C "$r" status --porcelain)" ""
  eq "real tree: only the notes file" "$(ls -A "$d" | tr '\n' ' ')" "none.txt notes.md "
  # notes.sh itself fails areas for an unmapped epic outside release 1, which the real-tree run tolerates.
  printf '  40-1-a-later-story: done\n' >> "$r/_bmad-output/implementation-artifacts/sprint-status.yaml"
  printf '\n### Story 40.1: A later story\n' >> "$r/_bmad-output/planning-artifacts/epics.md"
  git -C "$r" commit -q -am later
  run_real "$r" --replace
  arow=$(printf '%s\n' "$out" | grep -m 1 '^FAIL areas ')
  has "a later epic: notes.sh fails areas for unmapped epics" "$arow" "FAIL areas no area for epic "
  has "a later epic: notes.sh fails areas, naming it" "$arow" "epic 40"
  areas_ok_real || { echo "  a later epic: the real-tree run does not tolerate it"; bad=1; }
  # An unmapped epic of release 1 is not tolerated.
  grep -v '^epic 8 ' "$r/release/notes-areas.txt" > "$tmp/areas-no8.txt"
  run_real "$r" --replace --areas "$tmp/areas-no8.txt"
  has "an epic of release 1 unmapped: notes.sh fails areas" "$out" "epic 8"
  if areas_ok_real; then
    echo "  an epic of release 1 unmapped: the real-tree run tolerates it"
    bad=1
  fi
}

mkbase
rule base t_base
rule ipm t_ipm
rule later t_later
rule areas t_areas
rule epics t_epics
rule inputs t_inputs
rule eval-forms t_eval_forms
rule dry t_dry
rule checks t_checks
rule defaults t_defaults
rule integration t_integration
rule refusals t_refusals
rule no-network t_nonetwork
rule library t_library
rule static t_static
rule real-tree t_real

if [ "$fails_total" -ne 0 ]; then
  echo "test-release-notes: $fails_total rule(s) failed"
  exit 1
fi
