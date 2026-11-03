#!/usr/bin/env bash
# Pins README.md (Stories 10.2, 10.4 and 10.5; FR-4, FR-38, FR-58, UX-DR56, UX-DR98; DW-2, DW-3, DW-45, DW-134). Hermetic: it starts nothing, needs no network
# and no container, and runs in bash 3.2 with BSD or GNU tools (install.sh's rules).
#
# What it pins, one rule each:
#   top            the README opens with "# OcuTalon", a blank line and the owner's opening paragraph, then the teaser line and, after
#                  it, exactly one image line (the hero), then the H2 sections "Try it in two minutes", "What's interesting", "What
#                  you can use it for" and "How you talk to it" in this order; the other H2 sections are there; no "Contest task"
#                  heading and no header row of its table
#   try-it         the online demo link comes before ./install.sh, with "nothing to install, and no Early Access image needed"
#                  beside it and the splash screen; the local path is four numbered steps
#   interesting    "What's interesting" has at most 120 words and names Interoperability, Visual Trace, AI Hub, a dry run and the
#                  audit log
#   use-cases      "What you can use it for" holds exactly the three items, word for word (the third links docs/bridge-guide.md)
#   how-you-talk   "How you talk to it" holds its facts (the web chat page on every install, the demo-only parts, email in a later
#                  release, the link to "Demo mode"), a table and an image line, and never the word Slack
#   teaser         the teaser line is there once, word for word, two lines below the opening paragraph with an empty line between
#                  them and above the first H2 section; no HTML media tag, no image inside a link, and no image that is not an
#                  inline docs/images/<name>.png image
#   images         every Markdown image link of the README has non-empty alt text and a target that is a file directly in
#                  docs/images/ which the tree lists, there is at least one, and "What OcuTalon does" holds at least three, with at
#                  least one under the Chat bullet and two under the Break the feed bullet; each image line has an empty line
#                  before and after it; it names no image file
#   outcomes       the four outcomes, with the meanings that web/src/app/chat/chat-view.ts shows
#   install        the facts of the install sections: Compose 2.24 (DW-2), both image names, load and retag, the portal, the CPUs
#   install-pointer  every README section that install.sh names ("The Troubleshooting section of README.md") is an H2 heading
#   commands       every `docker compose` command that install.sh prints after "run:" is in the README (DW-134), and the README
#                  has no `docker compose restart`, `docker-compose restart`, `docker restart`, "install.sh again", "the install
#                  script again", "rerun" or "re-run"
#   key-account    the provider key line, .env.example, the default model, the fixed-rules sentence of "Set a model key", the
#                  model paragraph and three-row table at the end of "What OcuTalon does", with an empty line above, the README
#                  account and "Sign in to Visual Trace"; no "No key, still works." bullet; no key-shaped example
#   lan            "Sign in" warns that the Management Portal is reachable from the LAN and links to the password steps (DW-3)
#   sign-in-address  the README's ready block is the one install.sh prints, with the compose file's default web port, and "Try it
#                  in two minutes" and "Sign in" give its address ("Try it" its account too)
#   demo-mode      the SetDemoMode line, its roles, and the kept-OCUORDERS sentence word for word from EXPERIENCE.md (DW-45)
#   admin-commands the OCUTALON and %SYS terminal sessions and the password line, as the README walkthrough ran them
#   after-start-log  the README's after-start log command names the path that docker/after-start.sh writes, and says which lines to
#                  look for (the walkthrough ran it)
#   dev-only       no ##class(, class name or error code outside the section "For admins and developers"
#   public-text    the not-affiliated note, the BMAD Method and Claude Code credit, the licence pointers; OpenClaw only in the
#                  note; no other model provider, "from your phone", "per step", private infrastructure or IPv4 address
#   telegram-section  the section "Telegram" is there after "Sign in" and before "Stop, start and update", with its five numbered steps and
#                  the facts a person needs to follow them (@BotFather, /newbot, /setjoingroups, TELEGRAM_BOT_TOKEN=, the restart
#                  command, "its own bot", and that the steps are for "your own install")
#   telegram-strings  every UI string the section quotes is one the built page shows: "Telegram not set up", "Telegram paired" and
#                  "Unpair" are in the rail and card sources, "Approve" and "Reject" are the catalog's button texts (U-228)
#   telegram-facts  what the steps tell a person to do or expect matches what is built (U-228 condition 3): the pause time is
#                  In.cls's PAUSESECONDS, "the Status section" is the page's Status region, the token line is in .env.example and
#                  docker-compose.yml reads .env, and the step 5 address is the one "Sign in" gives
#   telegram-demo  no sentence about the online demo mentions Telegram or pairing, and every other sentence outside the section that
#                  mentions Telegram says "your own install" (U-228: the online demo has no bot)
#   no-telegram    no "Telegram" while Included() has its test-only body
#   product-links  every README anchor the page or the server text can show reaches a heading (#readme while README.md exists)
#   readme-links   every link of the README reaches a heading, a file or folder of the repository, or an allow-listed host;
#                  no two headings share a slug
#   must-scan      docker/tests/test-boundaries.sh's must-scan list for paths and keys names README.md, so the most public file can
#                  never drop out of that scan
#
# What it reads, all from files that git tracks or has not ignored (lib-scan.sh's scan_files; never .env): README.md, install.sh,
# the tree's file list (for the files of docs/images/), src/ocutalon/cls/OcuTalon/Core/Admin.cls, src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls, the UX design's EXPERIENCE.md,
# docker/after-start.sh, docker/tests/test-boundaries.sh, docker-compose.yml, web/src/app/**/*.ts (not *.spec.ts) and src/**/*.cls
# (not /Test/).
#
# The Included() rule (AD-29): while Included() has its test-only body, Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1, the page
# never shows the link to a README Telegram section, so the check prints one "SKIP #telegram" line, leaves #telegram out of
# product-links and refuses the word Telegram. Any other body, or no In.cls, covers #telegram (the README needs a heading with that
# slug) and allows the word, so the change that turns Telegram on edits the README, not this check. Since Story 12.9 Included() is
# Quit $Get(...) '= 0: #telegram is covered and no SKIP line prints; the rule keeps its test for a test-only body.
#
# Each rule first runs on copies of its input that are broken for that rule, each of which it must flag (a rule that can no
# longer flag anything fails), and only then on the real files. With no README.md every rule fails closed, which is checked first
# (a FAIL no-readme line names a rule that does not), and so is that every rule_* function is in RULES (a FAIL rules line names
# one that is not). Prints one PASS, FAIL or SKIP line per rule; a failing rule prints what is
# wrong (a README line number or a missing text); exits 0 only when no rule fails.
# shellcheck disable=SC2016
set -u
export LC_ALL=C

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
# shellcheck source=/dev/null
. "$root/docker/tests/lib-scan.sh"

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-rd.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- the inputs: text files of the tree, read by their paths ---

README=README.md
INSTALL=install.sh
ADMIN=src/ocutalon/cls/OcuTalon/Core/Admin.cls
INCLUDED=src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls
EXPERIENCE=_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md
CHATVIEW=web/src/app/chat/chat-view.ts
AFTER_START=docker/after-start.sh
BOUNDARIES=docker/tests/test-boundaries.sh
COMPOSE=docker-compose.yml
RAILVIEW=web/src/app/rail/rail-view.ts
CARDVIEW=web/src/app/rail/telegram-card/telegram-card-view.ts
BUTTONS=src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls
LAYOUTVIEW=web/src/app/shared/layout-view.ts
ENVEXAMPLE=.env.example

listing=$(scan_files)
if [ -z "$listing" ]; then
  echo "FAIL no files in scope"
  exit 1
fi
in_tree() { printf '%s\n' "$listing" | grep -qxF -- "$1"; }

# of <path>: the path when the tree holds that file, else an empty file, so that a rule that reads it flags the absence.
: > "$tmp/absent"
of() { if in_tree "$1"; then printf '%s' "$1"; else printf '%s' "$tmp/absent"; fi; }

have_readme=0
if in_tree "$README"; then have_readme=1; fi
install_p=$(of "$INSTALL")
admin_p=$(of "$ADMIN")
included_p=$(of "$INCLUDED")
experience_p=$(of "$EXPERIENCE")
chatview_p=$(of "$CHATVIEW")
after_start_p=$(of "$AFTER_START")
boundaries_p=$(of "$BOUNDARIES")
compose_p=$(of "$COMPOSE")
railview_p=$(of "$RAILVIEW")
cardview_p=$(of "$CARDVIEW")
buttons_p=$(of "$BUTTONS")
layoutview_p=$(of "$LAYOUTVIEW")
envexample_p=$(of "$ENVEXAMPLE")

# product_files: from a list of paths on standard input, the files whose README anchors the product can show: the page's sources
# and the server's classes, none of the tests.
product_files() { grep -E '^(web/src/app/.*\.ts|src/.*\.cls)$' | grep -v '\.spec\.ts$' | grep -v '/Test/'; }
printf '%s\n' "$listing" | product_files > "$tmp/product.list"

ARROW=$(printf '\342\206\222')
H_TRY='Try it in two minutes'
H_INT="What's interesting"
H_USE='What you can use it for'
H_TALK='How you talk to it'
# The owner's text of Story 10.4 (epics.md), word for word: the opening paragraph, the two use cases, and the model paragraph
# and table of "What OcuTalon does".
OPENING="Your integrations already tell you when something breaks, usually fifty times. OcuTalon reads the failures, works out the one cause, proposes the fix with a dry run, and only interrupts you when something needs you. Nothing risky runs without your yes: fixed rules that the model can't change decide what is risky, and every approval lands in the IRIS audit log. Every decision is in Visual Trace with its reasons and cost. Without a model it fails safe: it tells you everything and claims nothing."
ITEM1='- **The partner feed that breaks at 2am.** A trading partner changes a date format, and 50 orders fail. Instead of 50 alerts, you get one notice: the cause in plain English, the fix, and a dry run that shows what it would resend. Nothing is resent until you approve, and then OcuTalon reports how many orders went through. Break the feed in the online demo plays this out in two minutes. On your own install you can also approve it in Telegram on your phone, without a laptop or the Management Portal ([how to set up Telegram](#telegram)).'
ITEM2='- **"Only tell me if something needs me."** Ask OcuTalon in plain words to watch a production, and it stays quiet until something needs you. Failures with one cause become one incident, not a flood, and when you ask whether everything is fine, it never gives a false all-clear. It also tells you once when a production stops or one of its items is disabled.'
ITEM3='- **[An AI decision step you can audit, in your own production.](docs/bridge-guide.md)**'
MODEL_PARA="**With a model, and without one.** OcuTalon uses Claude Haiku 5.5 by default. With no model key, or when the model can't give a usable answer, it falls back to fixed rules and says so on the page and in Visual Trace."
T_HEAD='| | With a model | With fixed rules only |'
T_SEP='| --- | --- | --- |'
T_ROW1='| An item arrives | It decides Ignore, Digest, Tell now or Act, and says why | Tell now, marked as a fallback with the reason |'
T_ROW2='| 50 orders fail | One incident, with the cause in plain English, the part at fault, and a fix with a dry run | Grouped by item and error, with no cause and no fix |'
T_ROW3="| You ask in the chat | It answers, watches a production or sets a reminder | It says it couldn't answer, and why |"
MODEL_BLOCK="$MODEL_PARA

$T_HEAD
$T_SEP
$T_ROW1
$T_ROW2
$T_ROW3"
# The sentence of "Set a model key" that stays as it is.
FIXED_SENTENCE='Without a key, OcuTalon still starts. Every decision uses fixed rules, and the page shows a notice that says so.'
TEASER='Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU'
# The facts of "How you talk to it", each on a line of that section.
TALK_FACTS='The web chat page is OcuTalon on every install.
| The web chat page |
Every install
Demo mode
demo guide
Break the feed
Simulated phone
Simulated mailbox
Demo view
Email comes in a later release.
](#demo-mode)'
NOTE='OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.'
OTHER_H2='What OcuTalon does
Install it yourself
Set a model key
Sign in
Stop, start and update
Troubleshooting
For admins and developers
Credits and licences'

# --- readers of the Markdown ---

# headings <file>: level, GitHub slug and text of each heading outside a code fence, tab separated. The slug (Design Note 8) is
# the lower-cased text without every character but letters, digits, spaces, - and _, then spaces to -.
headings() {
  awk '
    function slug(s) { s = tolower(s); gsub(/[^a-z0-9 _-]/, "", s); gsub(/ /, "-", s); return s }
    /^```/ { fence = !fence; next }
    !fence && /^#+ / { match($0, /^#+/); lvl = RLENGTH; t = substr($0, lvl + 2); printf "%d\t%s\t%s\n", lvl, slug(t), t }
  ' "$1"
}

# image_links <file>: line, alt text and target of every inline Markdown image ![alt](target) outside a code fence, tab separated,
# every image of a line. A "![" that is not followed by "...](" (a reference-style image) is not listed.
image_links() {
  awk '
    /^```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      while ((i = index(line, "![")) > 0) {
        rest = substr(line, i + 2)
        j = index(rest, "]")
        if (j == 0) break
        if (substr(rest, j + 1, 1) != "(") { line = rest; continue }
        after = substr(rest, j + 2)
        k = index(after, ")")
        if (k == 0) break
        printf "%d\t%s\t%s\n", FNR, substr(rest, 1, j - 1), substr(after, 1, k - 1)
        line = substr(after, k + 1)
      }
    }
  ' "$1"
}

# section <file> <H2 title>: the lines of that H2 section, subsections included, without its heading.
section() {
  awk -v t="## $2" '
    /^```/ { fence = !fence }
    !fence && /^## / { on = ($0 == t); next }
    on { print }
  ' "$1"
}

# chk_facts <label> <file> <facts, one per line>: "<label>: missing '<fact>'" for each fact the file does not hold word for word.
chk_facts() {
  local fact
  printf '%s\n' "$3" | while IFS= read -r fact; do
    if [ -n "$fact" ] && ! grep -qF -e "$fact" "$2"; then echo "$1: missing '$fact'"; fi
  done
}

# chk_block <label> <file> <lines>: "<label>: ..." unless the file holds the lines one right after the other, in this order, each
# line whole and word for word. An empty line of the block must be an empty line of the file. A line that is nowhere in the file is
# named.
chk_block() {
  printf '%s\n' "$3" > "$tmp/block.want"
  awk -v label="$1" '
    NR == FNR { want[++n] = $0; next }
    { have[++m] = $0; seen[$0] = 1 }
    END {
      for (j = 1; j <= n; j++) {
        if (want[j] != "" && !(want[j] in seen)) { print label ": missing the line \"" substr(want[j], 1, 60) "...\""; bad = 1 }
      }
      if (bad) exit
      for (i = 1; i + n - 1 <= m; i++) {
        ok = 1
        for (j = 1; j <= n; j++) if (have[i + j - 1] != want[j]) { ok = 0; break }
        if (ok) exit
      }
      print label ": the lines of the block \"" substr(want[1], 1, 40) "...\" are not there one right after the other, in this order"
    }
  ' "$tmp/block.want" "$2"
}

# --- the self-test helpers: broken copies of an input ---

st_bad=0
st_msgs=""
S1=""
S2=""
S3=""
# st_note <what>: a broken copy that was not flagged. The notes are shown only when the real input passes, because a real input
# that already has the fault leaves nothing to break.
st_note() {
  st_msgs="$st_msgs  self-test: $1
"
  st_bad=1
}

# mutate <input> <awk program>: writes $tmp/m, the input edited by the program. Returns 1 when the edit changed nothing.
mutate() {
  awk "$2" "$1" > "$tmp/m" || return 1
  ! cmp -s "$1" "$tmp/m"
}

# strip_str <input> <string>: writes $tmp/m, the input with every occurrence of the string replaced by ZZ. Returns 1 when none.
strip_str() {
  awk -v s="$2" '{ out = ""; line = $0; n = length(s); while ((i = index(line, s)) > 0) { out = out substr(line, 1, i - 1) "ZZ"; line = substr(line, i + n) } print out line }' "$1" > "$tmp/m" || return 1
  ! cmp -s "$1" "$tmp/m"
}

# st <label> <slot 1 to 3> <input> <awk program> <checker>: the checker, given S1 S2 S3 with the slot's one replaced by the
# input edited by the program, must print something.
st() {
  local label=$1 slot=$2 in=$3 prog=$4 checker=$5 a1=$S1 a2=$S2 a3=$S3
  if ! mutate "$in" "$prog"; then
    st_note "$label: the edit changed nothing"
    return
  fi
  case $slot in
    1) a1=$tmp/m ;;
    2) a2=$tmp/m ;;
    3) a3=$tmp/m ;;
  esac
  if [ -z "$("$checker" "$a1" "$a2" "$a3")" ]; then st_note "$label: not flagged"; fi
}

# st_append <label> <text> <checker>: the checker must flag the README with the text added as its last line.
st_append() { st "$1" 1 "$README" "{ print } END { print \"$2\" }" "$3"; }

# st_move <label> <H2 title> <line prefix> <checker>: the checker must flag the README with the lines of that section that start
# with the prefix moved to the end of the file, where a check of the whole file would still find them.
st_move() {
  st "$1" 1 "$README" "/^## / { s = (\$0 == \"## $2\") } s && index(\$0, \"$3\") == 1 { held = held \$0 ORS; next } { print } END { printf \"%s%s\", ORS, held }" "$4"
}

# st_facts <checker> <facts, one per line>: the checker must flag the README without any one of the facts.
st_facts() {
  local fact
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    if ! strip_str "$README" "$fact"; then
      st_note "without '$fact': the edit changed nothing"
    elif [ -z "$("$1" "$tmp/m" "$S2" "$S3")" ]; then
      st_note "without '$fact': not flagged"
    fi
  done <<EOF
$2
EOF
}

# rule_begin <rule> <S1> <S2> <S3>: sets the real arguments of the rule. Returns 1, after a FAIL line, when there is no README.
rule_begin() {
  st_bad=0
  st_msgs=""
  S1=${2:-}
  S2=${3:-}
  S3=${4:-}
  if [ "$have_readme" -ne 1 ]; then
    echo "FAIL $1: $README is missing"
    fails=$((fails + 1))
    return 1
  fi
}

# finish <rule> <description> <checker>: runs the checker on the real arguments. FAIL, with what it found, when it finds a problem;
# FAIL when it finds none and a broken copy was not flagged; else PASS.
finish() {
  local out
  out=$("$3" "$S1" "$S2" "$S3")
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | head -n 10 | sed 's/^/  /'
    echo "FAIL $1"
    fails=$((fails + 1))
  elif [ "$st_bad" -ne 0 ]; then
    printf '%s' "$st_msgs"
    echo "FAIL $1: a broken copy was not flagged"
    fails=$((fails + 1))
  else
    echo "PASS $1: $2"
  fi
}

# --- the rules' checkers: each prints one line per problem and nothing when the rule holds ---

# top
chk_top() {
  local f=$1 h2s t n
  awk -v opening="$OPENING" -v teaser="$TEASER" '
    state == 0 && $0 ~ /[^ \t]/ { if ($0 != "# OcuTalon") print FILENAME ":" FNR ": the first line is not \"# OcuTalon\""; state = 1; next }
    state == 1 && /^## / { state = 2 }
    state == 1 && $0 ~ /[^ \t]/ {
      if ($0 == teaser) seen = 1
      else if (index($0, "![") == 1 && (k = index($0, "](")) > 0 && index(substr($0, k + 2), ")") == length($0) - k - 1) {
        imgs++
        if (!seen) print FILENAME ":" FNR ": the image line is above the teaser"
      } else if ($0 != opening) print FILENAME ":" FNR ": a line between the title and the first H2 section that is neither the opening paragraph, the teaser nor the image line"
    }
    state == 0 { next }
    /^#+ Contest task/ || index($0, "| Contest task or criterion") == 1 { print FILENAME ":" FNR ": the Contest task section is back" }
    END { if (imgs != 1) print FILENAME ": " imgs + 0 " image lines between the title and the first H2 section, not exactly one" }
  ' "$f"
  chk_block top "$f" "# OcuTalon

$OPENING"
  n=$(grep -cxF -- "$OPENING" "$f")
  if [ "$n" -gt 1 ]; then echo "$f: the opening paragraph is there $n times, not once"; fi
  h2s=$(headings "$f" | awk -F'\t' '$1 == 2 { print $3 }')
  if [ "$(printf '%s\n' "$h2s" | head -n 4)" != "$(printf '%s\n%s\n%s\n%s' "$H_TRY" "$H_INT" "$H_USE" "$H_TALK")" ]; then
    echo "$f: the first four H2 sections are not, in this order: $H_TRY, $H_INT, $H_USE, $H_TALK"
  fi
  printf '%s\n' "$OTHER_H2" | while IFS= read -r t; do
    if ! printf '%s\n' "$h2s" | grep -qxF -- "$t"; then echo "$f: no H2 section '$t'"; fi
  done
}

# try-it
DEMO_PHRASE='nothing to install, and no Early Access image needed'
TRY_FACTS="https://demo.ocutalon.com
./install.sh
$DEMO_PHRASE
splash"
chk_try_it() {
  local sec="$tmp/sec.try" demo install n
  section "$1" "$H_TRY" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_TRY'"
    return
  fi
  chk_facts try-it "$sec" "$TRY_FACTS"
  demo=$(grep -nF -m 1 'https://demo.ocutalon.com' "$sec" | cut -d: -f1)
  install=$(grep -nF -m 1 './install.sh' "$sec" | cut -d: -f1)
  if [ -n "$demo" ] && [ -n "$install" ] && [ "$demo" -ge "$install" ]; then
    echo "try-it: ./install.sh comes before https://demo.ocutalon.com"
  fi
  if ! grep -F 'https://demo.ocutalon.com' "$sec" | grep -qF -e "$DEMO_PHRASE"; then
    echo "try-it: '$DEMO_PHRASE' is not beside the demo link"
  fi
  for n in 1 2 3 4; do
    if ! grep -q "^$n\\. " "$sec"; then echo "try-it: the local path has no step $n"; fi
  done
  if grep -q '^5\. ' "$sec"; then echo "try-it: the local path has more than four steps"; fi
}

# interesting
INT_FACTS='Interoperability
Visual Trace
AI Hub
dry run
audit log'
chk_interesting() {
  local sec="$tmp/sec.int" n
  section "$1" "$H_INT" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_INT'"
    return
  fi
  n=$(wc -w < "$sec")
  n=$((n + 0))
  if [ "$n" -gt 120 ]; then echo "interesting: $n words, at most 120"; fi
  chk_facts interesting "$sec" "$INT_FACTS"
}

# use-cases
chk_use_cases() {
  local sec="$tmp/sec.use" n
  section "$1" "$H_USE" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_USE'"
    return
  fi
  chk_block use-cases "$sec" "$ITEM1
$ITEM2
$ITEM3"
  n=$(grep -c '[^[:space:]]' "$sec")
  if [ "$n" -ne 3 ]; then echo "use-cases: '$H_USE' has $n lines, not exactly the three items"; fi
}

# how-you-talk
chk_how_you_talk() {
  local sec="$tmp/sec.talk"
  section "$1" "$H_TALK" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_TALK'"
    return
  fi
  chk_facts how-you-talk "$sec" "$TALK_FACTS"
  if ! grep -q '^| --- |' "$sec"; then echo "how-you-talk: '$H_TALK' has no table"; fi
  if ! grep -q '^!\[' "$sec"; then echo "how-you-talk: '$H_TALK' has no image line"; fi
  if grep -qi 'slack' "$sec"; then echo "how-you-talk: '$H_TALK' names Slack"; fi
}

# images: chk_images <readme> <file list>
chk_images() {
  image_links "$1" | awk -F'\t' -v list="$2" -v readme="$1" '
    BEGIN { while ((getline entry < list) > 0) have[entry] = 1 }
    {
      n++
      alt = $2
      gsub(/[ \t]/, "", alt)
      if (alt == "") print "images: " readme ":" $1 ": the image " $3 " has no alt text"
      if ($3 !~ /^docs\/images\/[^\/]+$/ || index($3, "..") > 0) print "images: " readme ":" $1 ": the target " $3 " is not a file directly in docs/images/"
      else if (!($3 in have)) print "images: " readme ":" $1 ": the target " $3 " is not a file the tree lists"
    }
  '
  # Each image line is a paragraph of its own (an empty line before and after it), so that GFM does not join it to a text line.
  image_links "$1" | cut -f1 | uniq | awk -v readme="$1" '
    BEGIN { while ((getline l < readme) > 0) { nl++; blank[nl] = (l !~ /[^ \t]/) } }
    ($1 > 1 && !blank[$1 - 1]) || ($1 < nl && !blank[$1 + 1]) { print "images: " readme ":" $1 ": the image line has no empty line before or after it" }
  '
  # "At least one image link" (AC5) is implied by the count of three below, which is why it has no check of its own.
  local sec="$tmp/sec.what" n
  section "$1" 'What OcuTalon does' > "$sec"
  n=$(image_links "$sec" | wc -l | tr -d ' ')
  if [ "$n" -lt 3 ]; then echo "images: $1: 'What OcuTalon does' holds $n image links, not at least three"; fi
  # Placement (AC4), by bullet and not by file name: the Chat bullet owns at least one image paragraph, the Break the feed bullet at least two.
  awk -v readme="$1" '
    /^- \*\*/ { cur = (index($0, "- **Chat on a live page.**") == 1) ? "chat" : (index($0, "- **Break the feed.**") == 1) ? "break" : "" }
    /^  !\[/ && cur != "" { got[cur]++ }
    END {
      if (got["chat"] < 1) print "images: " readme ": the bullet Chat on a live page. has no image under it"
      if (got["break"] < 2) print "images: " readme ": the bullet Break the feed. has " got["break"] + 0 " images under it, not at least two"
    }
  ' "$sec"
}

# teaser
chk_teaser() {
  local f=$1 n op at h2
  n=$(grep -cxF -- "$TEASER" "$f")
  if [ "$n" -ne 1 ]; then echo "teaser: the line '$TEASER' is there $n times, not once"; fi
  op=$(grep -nxF -- "$OPENING" "$f" | head -n 1 | cut -d: -f1)
  at=$(grep -nxF -- "$TEASER" "$f" | head -n 1 | cut -d: -f1)
  h2=$(grep -n -m 1 '^## ' "$f" | cut -d: -f1)
  if [ -z "$op" ]; then
    echo "teaser: the opening paragraph is not there, so the teaser has no place under it"
  elif [ -n "$at" ]; then
    if [ "$at" -ne $((op + 2)) ]; then
      echo "teaser: $f:$at: it is not the second line below the opening paragraph (line $op)"
    elif [ -n "$(sed -n "$((op + 1))p" "$f" | tr -d ' \t')" ]; then
      echo "teaser: $f:$((op + 1)): there is no empty line between the opening paragraph and the teaser"
    fi
    if [ -n "$h2" ] && [ "$at" -gt "$h2" ]; then echo "teaser: $f:$at: it is below the first H2 section"; fi
  fi
  grep -niE '<(img|iframe|video|embed|object|picture)' "$f" | cut -d: -f1 | sed "s|^|$f:|; s|\$|: an HTML media tag (the teaser is a plain link)|"
  grep -nF '[![' "$f" | cut -d: -f1 | sed "s|^|$f:|; s|\$|: an image inside a link (the teaser is a plain link)|"
  # Every "![" of a line must be an inline docs/images/<name>.png image; a remote, local-elsewhere, non-PNG or reference-style image is not.
  image_links "$f" | awk -F'\t' '$3 ~ /^docs\/images\/[^\/]+\.png$/ { good[$1]++ } END { for (l in good) print l, good[l] }' > "$tmp/img.good"
  awk -v goodfile="$tmp/img.good" -v f="$f" '
    BEGIN { while ((getline entry < goodfile) > 0) { split(entry, p, " "); good[p[1]] = p[2] } }
    { n = 0; s = $0; while ((i = index(s, "![")) > 0) { n++; s = substr(s, i + 2) } }
    n > good[FNR] + 0 { print f ":" FNR ": an image that is not an inline docs/images/<name>.png image" }
  ' "$f"
}

# outcomes: chk_outcomes <readme> <chat-view.ts>
chk_outcomes() {
  local key name meaning
  for key in Ignore:meaningIgnore Digest:meaningDigest 'Tell now:meaningTellNow' Act:meaningAct; do
    name=${key%%:*}
    meaning=$(sed -n "s/^[[:space:]]*${key#*:}: '\\(.*\\)',\$/\\1/p" "$2" | head -n 1)
    if [ -z "$meaning" ]; then
      echo "outcomes: $CHATVIEW has no ${key#*:}"
    elif ! grep -qF -e "**$name**: $meaning." "$1"; then
      echo "outcomes: missing '**$name**: $meaning.'"
    fi
  done
}

# install (DW-2): the facts of the install sections
INSTALL_FACTS='2.24
irishealth-community:2026.3.0AI.154.0
ocutalon-iris-base:2026.3.0AI.154.0
docker load -i
docker tag
docker compose up -d
docker compose ps
https://evaluation.intersystems.com/Eval/early-access/AIHub
arm64
x64
iris-community:2026.3.0AI.154.0
HealthShare
HSCUSTOM
ARM64
15 minutes
(healthy)'
chk_install() {
  local sec="$tmp/sec.install"
  section "$1" 'Install it yourself' > "$sec"
  chk_facts install "$sec" "$INSTALL_FACTS"
}

# install-pointer: chk_install_pointer <readme> <install.sh>
chk_install_pointer() {
  local names name
  names=$(sed -n 's/.*[Tt]he \([A-Za-z][A-Za-z ]*\) section of README\.md.*/\1/p' "$2" | sort -u)
  if [ -z "$names" ]; then
    echo "install-pointer: install.sh names no README section (the extraction found none)"
    return
  fi
  printf '%s\n' "$names" | while IFS= read -r name; do
    if ! grep -qxF -- "## $name" "$1"; then echo "install-pointer: install.sh points to the section '$name', and the README has no '## $name' heading"; fi
  done
}

# commands (DW-134): chk_commands <readme> <install.sh>
chk_commands() {
  local cmds cmd
  cmds=$(sed -n 's/.*run: *\(docker compose[^"]*\)".*/\1/p' "$2" | sed 's/ *$//' | sort -u)
  if [ -z "$cmds" ]; then
    echo "commands: install.sh prints no docker compose command after 'run:' (the extraction found none)"
  else
    printf '%s\n' "$cmds" | while IFS= read -r cmd; do
      if ! grep -qF -e "$cmd" "$1"; then echo "commands: install.sh prints '$cmd', and the README does not"; fi
    done
  fi
  grep -niE 'docker[ -]compose restart|docker restart|install(\.sh`?| script) again|re-?run' "$1" | cut -d: -f1 | sed 's|^|commands: README.md:|; s|$|: wording the README must not use (DW-134)|'
}

# key-account
KEY_FACTS='ANTHROPIC_API_KEY=<your key>
.env.example
Claude Haiku 5.5
Sign in to Visual Trace'
ACCOUNT_FACTS='User name: `ocutalon`
Password: `ocutalon`'
chk_key_account() {
  local sec="$tmp/sec.signin" rows
  chk_facts key-account "$1" "$KEY_FACTS"
  section "$1" 'Sign in' > "$sec"
  chk_facts key-account "$sec" "$ACCOUNT_FACTS"
  section "$1" 'Set a model key' > "$sec"
  chk_facts key-account "$sec" "$FIXED_SENTENCE"
  section "$1" 'What OcuTalon does' > "$sec"
  chk_block key-account "$sec" "$MODEL_BLOCK"
  rows=$(grep -c '^|' "$sec")
  if [ "$rows" -ne 5 ]; then echo "key-account: What OcuTalon does has $rows table lines, not the 5 of the model table"; fi
  awk -v para="$MODEL_PARA" -v last="$T_ROW3" '
    $0 == para && prev != "" { print "key-account: What OcuTalon does: the line above the model paragraph is not empty" }
    { prev = $0 }
    /[^ \t]/ { tail = $0 }
    END { if (tail != last) print "key-account: What OcuTalon does: the model table is not the end of the section" }
  ' "$sec"
  grep -nF 'No key, still works.' "$1" | cut -d: -f1 | sed 's|^|key-account: README.md:|; s|$|: the bullet "No key, still works." is back|'
  grep -n 'ANTHROPIC_API_KEY=' "$1" | grep -v 'ANTHROPIC_API_KEY=<your key>' | cut -d: -f1 | sed 's|^|key-account: README.md:|; s|$|: a key-shaped example|'
}

# lan (DW-3)
LAN_FACTS='LAN
Management Portal
](#change-the-readme-accounts-password)
Change the README account'"'"'s password after your first sign-in'
chk_lan() {
  local sec="$tmp/sec.lan"
  section "$1" 'Sign in' > "$sec"
  chk_facts lan "$sec" "$LAN_FACTS"
}

# sign-in-address: chk_sign_in_address <readme> <install.sh> <docker-compose.yml>
# ready_lines <install.sh> <port>: the Open, User and Password lines of install.sh's ready block, with the port filled in.
ready_lines() {
  sed -n 's/^[[:space:]]*echo "\(  Open: .*\)"$/\1/p; s/^[[:space:]]*echo "\(  User: .*\)"$/\1/p; s/^[[:space:]]*echo "\(  Password: .*\)"$/\1/p' "$1" |
    sed "s/\\\$port/$2/"
}
chk_sign_in_address() {
  local port lines line addr user pass t sec="$tmp/sec.address"
  port=$(sed -n 's/.*OCUTALON_WEB_PORT:-\([0-9][0-9]*\)}.*/\1/p' "$3" | head -n 1)
  if [ -z "$port" ]; then
    echo "sign-in-address: $COMPOSE has no default web port (the extraction found none)"
    return
  fi
  lines=$(ready_lines "$2" "$port")
  if [ "$(printf '%s\n' "$lines" | grep -c '^  ')" -ne 3 ]; then
    echo "sign-in-address: install.sh prints no ready block with one Open, one User and one Password line (the extraction found none)"
    return
  fi
  printf '%s\n' "$lines" | while IFS= read -r line; do
    if ! grep -qxF -- "$line" "$1"; then echo "sign-in-address: install.sh prints '$line', and the README's ready block does not"; fi
  done
  addr=$(printf '%s\n' "$lines" | sed -n 's/^  Open: *//p')
  user=$(printf '%s\n' "$lines" | sed -n 's/^  User: *//p')
  pass=$(printf '%s\n' "$lines" | sed -n 's/^  Password: *//p')
  for t in "$H_TRY" 'Sign in'; do
    section "$1" "$t" > "$sec"
    if ! grep -qF -e "$addr" "$sec"; then echo "sign-in-address: the section '$t' does not give the address $addr"; fi
  done
  section "$1" "$H_TRY" > "$sec"
  if ! grep -qF -e "user name \`$user\` and password \`$pass\`" "$sec"; then
    echo "sign-in-address: the section '$H_TRY' does not give user name \`$user\` and password \`$pass\`"
  fi
}

# demo-mode (DW-45, U-72): chk_demo_mode <readme> <Admin.cls> <EXPERIENCE.md>
DEMO_FACTS='### Demo mode
do ##class(OcuTalon.Core.Admin).SetDemoMode(<0 or 1>)
OcuTalonAdmin
%All'
chk_demo_mode() {
  local kept
  chk_facts demo-mode "$1" "$DEMO_FACTS"
  if ! grep -qF 'ClassMethod SetDemoMode(' "$2"; then echo "demo-mode: Admin.cls has no 'ClassMethod SetDemoMode('"; fi
  kept=$(sed -n 's/^.*"\(OcuTalon left the OCUORDERS namespace[^"]*\)".*$/\1/p' "$3" | head -n 1)
  if [ -z "$kept" ]; then
    echo "demo-mode: EXPERIENCE.md has no kept-OCUORDERS sentence (the extraction found none)"
  elif ! grep -qF -e "$kept" "$1"; then
    echo "demo-mode: the README does not hold EXPERIENCE.md's kept-OCUORDERS sentence word for word"
  fi
}

# admin-commands: the terminal sessions and the password line that the walkthrough ran, in the admin section
ADMIN_FACTS='docker compose exec iris iris session IRIS -U OCUTALON
docker compose exec iris iris session IRIS -U %SYS
kill p set p("Password")="<new password>" write ##class(Security.Users).Modify("ocutalon",.p)'
chk_admin_commands() {
  local sec="$tmp/sec.admin"
  section "$1" 'For admins and developers' > "$sec"
  chk_facts admin-commands "$sec" "$ADMIN_FACTS"
}

# after-start-log: the command that reads the start's log, and the lines to look for in it (Troubleshooting; the walkthrough ran it).
# log_path <after-start.sh>: the default path of the log that the image writes.
LOG_FACTS='begin with `STEP`
begins with `RESULT OK`'
log_path() {
  sed -n 's/^log_file="\${OCUTALON_AFTER_START_LOG:-\([^}"]*\)}".*/\1/p' "$1" | head -n 1
}
# chk_after_start_log <readme> <after-start.sh>
chk_after_start_log() {
  local path
  path=$(log_path "$2")
  if [ -z "$path" ]; then
    echo "after-start-log: docker/after-start.sh has no default log path (the extraction found none)"
  else
    chk_facts after-start-log "$1" "docker compose exec iris cat $path"
  fi
  chk_facts after-start-log "$1" "$LOG_FACTS"
}

# must-scan: chk_must_scan <test-boundaries.sh>: the "for f in ..." list that is followed by the message "not scanned for paths and
# keys" must name README.md.
chk_must_scan() {
  awk '
    /^for f in / { hdr = ""; on = 1 }
    on { hdr = hdr " " $0; if ($0 ~ /; do[ \t]*$/) { on = 0; last = hdr } }
    /not scanned for paths and keys/ { found = last; seen = 1 }
    END {
      if (!seen) { print "must-scan: test-boundaries.sh has no must-scan list for paths and keys (the extraction found none)"; exit }
      n = split(found, w, /[ \t\\;]+/)
      ok = 0
      for (i = 1; i <= n; i++) if (w[i] == "README.md") ok = 1
      if (!ok) print "must-scan: the must-scan list for paths and keys in test-boundaries.sh does not name README.md"
    }
  ' "$1"
}

# dev-only: file:line of each line outside the H2 section "For admins and developers" with a ##class( call, a class name (a dotted
# name whose parts start with an upper-case letter, a leading % allowed), an ERROR #<digits> code or an <UPPER> error name.
dev_names() {
  awk '
    FNR == 1 { stop = 0 }
    /^## / { stop = ($0 == "## For admins and developers") }
    stop { next }
    /##class\(/ || /ERROR #[0-9]+/ || /<[A-Z][A-Z][A-Z]+>/ || /(^|[^A-Za-z0-9_])%?[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)+/ { print FILENAME ":" FNR }
  ' "$@"
}

# public-text: file:line of each line with a provider, "from your phone", "per step", private infrastructure, an IPv4 address other
# than 127.0.0.1 and 0.0.0.0, or OpenClaw outside the note; and what a README lacks: the note, the credit, the licence pointers.
PUBLIC_FACTS='Built with the BMAD Method and Claude Code.
web/public/assets/licenses
docker/ipm/LICENSE
3rdpartylicenses.txt'
public_text_scan() {
  local f
  awk -v note="$NOTE" '
    function word(l, w) { return l ~ ("(^|[^a-z0-9])(" w ")([^a-z]|$)") }
    {
      l = tolower($0)
      if (word(l, "openai|gpt|chatgpt|gemini|mistral|cohere|llama|ollama|bedrock|azure|deepseek|grok")) print FILENAME ":" FNR
      else if (l ~ /from your phone|per[- ]step|find a bug|bonus/) print FILENAME ":" FNR
      else if (l ~ /ocutalon-ci|ocutalon-slot|\.worktrees|\.coordination|digitalocean|droplet|sfo2|contest planner|epic-cycle|self-hosted/) print FILENAME ":" FNR
      else if (l ~ /openclaw/ && $0 != note) print FILENAME ":" FNR
      else {
        s = $0
        while (match(s, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
          ip = substr(s, RSTART, RLENGTH)
          if (ip != "127.0.0.1" && ip != "0.0.0.0") { print FILENAME ":" FNR; break }
          s = substr(s, RSTART + RLENGTH)
        }
      }
    }
  ' "$@"
  for f in "$@"; do
    if ! grep -qxF -- "$NOTE" "$f"; then echo "$f: the not-affiliated note is missing or not word for word"; fi
    chk_facts "$f" "$f" "$PUBLIC_FACTS"
  done
}

# The scanners take files, the self-test helpers three arguments: these give them the first.
dev_names_1() { dev_names "$1"; }
public_text_1() { public_text_scan "$1"; }

# no-telegram: chk_no_telegram <readme> <mode>
chk_no_telegram() {
  if [ "$2" = testonly ]; then
    grep -niF telegram "$1" | cut -d: -f1 | sed 's|^|no-telegram: README.md:|; s|$|: the word Telegram while Included() is test-only|'
  fi
}

# telegram_mode <In.cls>: testonly when Included() has the test-only body, else included.
telegram_mode() {
  local body
  if [ ! -s "$1" ]; then
    echo included
    return
  fi
  body=$(awk '/^ClassMethod Included\(/ { on = 1; next } on && /^\}/ { exit } on { print }' "$1" | tr -d '\r' | tr '\t\n' '  ' | sed 's/  */ /g; s/^ //; s/ $//')
  if [ "$body" = '{ Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1' ]; then echo testonly; else echo included; fi
}

# telegram-section (Story 12.9)
H_TG='Telegram'
TG_FACTS='@BotFather
/newbot
/setjoingroups
TELEGRAM_BOT_TOKEN=
docker compose up -d --force-recreate
its own bot
your own install'
chk_telegram_section() {
  local f=$1 sec="$tmp/sec.tg" n order
  section "$f" "$H_TG" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "telegram-section: no section '$H_TG'"
    return
  fi
  chk_facts telegram-section "$sec" "$TG_FACTS"
  for n in 1 2 3 4 5; do
    if ! grep -q "^$n\. " "$sec"; then echo "telegram-section: no step $n"; fi
  done
  if grep -q '^6\. ' "$sec"; then echo "telegram-section: more than five steps"; fi
  order=$(headings "$f" | awk -F'\t' '$1 == 2 { print $3 }' | grep -xF -e 'Sign in' -e "$H_TG" -e 'Stop, start and update' | tr '\n' '|')
  if [ "$order" != "Sign in|$H_TG|Stop, start and update|" ]; then echo "telegram-section: the section is not between 'Sign in' and 'Stop, start and update'"; fi
}

# telegram-strings (U-228 condition 1): the UI strings the section quotes. Each row is <string>|<source>|<ts, or the catalog key>.
TG_UI='Telegram not set up|RAIL|ts
Telegram paired|CARD|ts
Unpair|CARD|ts
Approve|BUTTONS|button.approve
Reject|BUTTONS|button.reject'
# ui_in_source <string> <source name> <kind> <rail-view.ts> <telegram-card-view.ts> <catalog class>: the string is what the source shows.
ui_in_source() {
  local file
  case $2 in RAIL) file=$4 ;; CARD) file=$5 ;; *) file=$6 ;; esac
  if [ "$3" = ts ]; then
    grep -qF -e "'$1'" "$file"
  else
    awk -v key="\"$3\": {" -v text="\"text\": \"$1\"," '
      index($0, key) { on = 1; next }
      on && index($0, text) { found = 1 }
      on && /^ }/ { exit }
      END { exit !found }
    ' "$file"
  fi
}
# chk_telegram_strings <readme> <rail-view.ts> <telegram-card-view.ts> <catalog class>
chk_telegram_strings() {
  local sec="$tmp/sec.tgs" str src kind
  section "$1" "$H_TG" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "telegram-strings: no section '$H_TG'"
    return
  fi
  grep -o '"[^"]*"' "$sec" | sed 's/^"//; s/"$//' | while IFS= read -r str; do
    if ! printf '%s\n' "$TG_UI" | cut -d'|' -f1 | grep -qxF -e "$str"; then echo "telegram-strings: the section quotes \"$str\", which no pinned UI string is"; fi
  done
  printf '%s\n' "$TG_UI" | while IFS='|' read -r str src kind; do
    if ! grep -qF -e "\"$str\"" "$sec"; then echo "telegram-strings: the section does not quote \"$str\""; fi
    if ! ui_in_source "$str" "$src" "$kind" "$2" "$3" "$4"; then echo "telegram-strings: the built page does not show \"$str\" ($src)"; fi
  done
}

# telegram-facts (U-228 condition 3): the steps against what is built. chk_telegram_facts <readme> <In.cls> <layout-view.ts>; the
# .env.example and the compose file are TGF_ENV and TGF_COMPOSE (the rule swaps them for broken copies).
TGF_ENV=$envexample_p
TGF_COMPOSE=$compose_p
chk_telegram_facts() {
  local sec="$tmp/sec.tgf" signin="$tmp/sec.tgf.signin" mins secs url
  section "$1" "$H_TG" > "$sec"
  section "$1" 'Sign in' > "$signin"
  if [ ! -s "$sec" ]; then
    echo "telegram-facts: no section '$H_TG'"
    return
  fi
  mins=$(sed -n 's/.*after \([0-9][0-9]*\) minutes.*/\1/p' "$sec" | head -n 1)
  if [ -z "$mins" ]; then
    echo "telegram-facts: the section does not say after how many minutes OcuTalon tries again"
  else
    secs=$((mins * 60))
    if ! grep -qE "^Parameter PAUSESECONDS = $secs;" "$2"; then echo "telegram-facts: the section says $mins minutes, and In.cls's PAUSESECONDS is not $secs"; fi
  fi
  if ! grep -qF 'In the Status section' "$sec"; then echo "telegram-facts: step 5 does not name the Status section"; fi
  if ! grep -qE "^  status: 'Status',$" "$3"; then echo "telegram-facts: the page has no region named Status (layout-view.ts), which step 5 names"; fi
  if ! grep -q '^TELEGRAM_BOT_TOKEN=' "$TGF_ENV"; then echo "telegram-facts: .env.example has no TELEGRAM_BOT_TOKEN= line to copy, which step 3 relies on"; fi
  if ! grep -qE '^[[:space:]]+- path: \.env$' "$TGF_COMPOSE"; then echo "telegram-facts: docker-compose.yml does not read .env, so the token of step 3 never reaches OcuTalon"; fi
  url=$(grep '^5\. ' "$sec" | grep -oE 'http://[^ ]+' | head -n 1)
  if [ -z "$url" ]; then
    echo "telegram-facts: step 5 gives no address"
  elif ! grep -qF -e "$url" "$signin"; then
    echo "telegram-facts: the address of step 5 ($url) is not the one 'Sign in' gives"
  fi
}

# telegram-demo (U-228 condition 2): sentence by sentence, outside code fences.
chk_telegram_demo() {
  awk '
    /^```/ { fence = !fence; next }
    fence { next }
    /^## / { sec = ($0 == "## Telegram"); next }
    {
      line = $0; gsub(/\. /, ".\n", line); n = split(line, parts, "\n")
      for (i = 1; i <= n; i++) {
        s = parts[i]
        if (s ~ /online demo|demo\.ocutalon\.com/ && (" " s) ~ /Telegram|[^A-Za-z][Pp]air(ing|ed)?([^a-z]|$)/) print "telegram-demo: " FILENAME ":" FNR ": a sentence about the online demo mentions Telegram or pairing"
        else if (!sec && s ~ /Telegram/ && s !~ /your own install/) print "telegram-demo: " FILENAME ":" FNR ": a sentence outside the Telegram section mentions Telegram without \"your own install\""
      }
    }
  ' "$1"
}

# inventory <list file>: the README anchors that the files of the list can link to, one per line, sorted: the part after # of a
# jbrandtmse/OcuTalon# address, the section argument of a readmeSection(..., '<x>') call, and the value of a *_ANCHOR constant of
# a TypeScript file.
inventory() {
  {
    tr '\n' '\0' < "$1" | xargs -0 grep -hoE 'jbrandtmse/OcuTalon#[A-Za-z0-9_-]+' /dev/null 2>/dev/null | sed 's/.*#//'
    tr '\n' '\0' < "$1" | xargs -0 grep -hoE "readmeSection\\([^,)]*,[[:space:]]*'[^']*'" /dev/null 2>/dev/null | sed "s/.*'\\([^']*\\)'\$/\\1/"
    grep -E '\.ts$' "$1" | tr '\n' '\0' | xargs -0 grep -hoE "[A-Z][A-Z_]*_ANCHOR[^=']*=[[:space:]]*'[^']*'" /dev/null 2>/dev/null | sed "s/.*'\\([^']*\\)'\$/\\1/"
  } | sort -u
}

# product-links: chk_product_links <readme> <list file> <In.cls>
chk_product_links() {
  local anchors mode slugs a
  anchors=$(inventory "$2")
  for a in readme telegram; do
    if ! printf '%s\n' "$anchors" | grep -qxF -- "$a"; then
      echo "product-links: the link inventory finds no '#$a' anchor, so a renamed constant could hide every page link"
    fi
  done
  mode=$(telegram_mode "$3")
  slugs=$(headings "$1" | cut -f2)
  printf '%s\n' "$anchors" | while IFS= read -r a; do
    case $a in
      '') continue ;;
      readme) continue ;;
      telegram) if [ "$mode" = testonly ]; then continue; fi ;;
    esac
    if ! printf '%s\n' "$slugs" | grep -qxF -- "$a"; then echo "product-links: the page links to '#$a', and the README has no heading with that slug"; fi
  done
}

# readme-links (Design Notes 8 and 9)
ALLOWED_HOSTS='localhost demo.ocutalon.com youtu.be github.com/jbrandtmse/OcuTalon github.com/bmad-code-org claude.com console.anthropic.com docs.anthropic.com evaluation.intersystems.com docs.intersystems.com www.intersystems.com docs.docker.com learn.microsoft.com'
URL_RE='https?://[^][:space:])>"<`]+'
url_allowed() {
  local rest=${1#*://} host entry
  case $rest in */../* | */..) return 1 ;; esac
  host=${rest%%[/?#]*}
  host=${host##*@}
  host=${host%%:*}
  for entry in $ALLOWED_HOSTS; do
    case $entry in
      */*)
        case $rest in
          "$entry" | "$entry"/* | "$entry"\?* | "$entry"#* | "$entry".git) return 0 ;;
        esac
        ;;
      *) if [ "$host" = "$entry" ]; then return 0; fi ;;
    esac
  done
  return 1
}
chk_readme_links() {
  local slugs dup
  slugs=$(headings "$1" | cut -f2)
  dup=$(printf '%s\n' "$slugs" | sort | uniq -d)
  if [ -n "$dup" ]; then printf '%s\n' "$dup" | sed 's|^|readme-links: two headings have the slug |'; fi
  grep -oE '\]\([^)]*\)' "$1" | sed 's/^](//; s/)$//' | while IFS= read -r target; do
    case $target in
      '#'*)
        if ! printf '%s\n' "$slugs" | grep -qxF -- "${target:1}"; then echo "readme-links: the link ($target) reaches no heading"; fi
        ;;
      http://* | https://*) ;;
      *://* | mailto:*) echo "readme-links: the link ($target) is not an http or https address" ;;
      *)
        path=${target%%[#?]*}
        if [ -z "$path" ] || [ -z "$(scan_files "${path%/}" | head -n 1)" ]; then echo "readme-links: the link ($target) reaches no file or folder of the repository"; fi
        ;;
    esac
  done
  grep -oE "$URL_RE" "$1" | sed 's/[.,;:]*$//' | sort -u | while IFS= read -r url; do
    if ! url_allowed "$url"; then echo "readme-links: the address $url is not on the allow-list"; fi
  done
}

# --- the rules ---

rule_top() {
  rule_begin top "$README" || return
  st 'a line before the first H2 section' 1 "$README" 'NR == 1 { print; print "A stray line."; next } { print }' chk_top
  st 'a first line that is not the title' 1 "$README" 'NR == 1 { print "# Other"; next } { print }' chk_top
  st 'the first two sections swapped' 1 "$README" '/^## What.s interesting$/ { print "## Try it in two minutes"; next } /^## Try it in two minutes$/ { print "## What'"'"'s interesting"; next } { print }' chk_top
  st 'the opening paragraph changed' 1 "$README" '/^Your integrations already/ { sub(/fifty/, "fifteen") } { print }' chk_top
  st 'the opening paragraph removed' 1 "$README" '!/^Your integrations already/' chk_top
  st 'the opening paragraph twice' 1 "$README" '{ print } /^Watch the 35-second teaser: / { print ""; print o } /^Your integrations already/ { o = $0 }' chk_top
  st 'the opening and the teaser swapped' 1 "$README" '/^Your integrations already/ { o = $0; next } /^Watch the 35-second teaser: / { print; print ""; print o; next } { print }' chk_top
  st 'the use cases section moved down' 1 "$README" '/^## What you can use it for$/ { print "## What OcuTalon does"; next } /^## What OcuTalon does$/ { print "## What you can use it for"; next } { print }' chk_top
  st 'the use cases section renamed' 1 "$README" '/^## What you can use it for$/ { print "## What you can do with it"; next } { print }' chk_top
  st 'a line between the teaser and the first H2 section' 1 "$README" '{ print } /^Watch the 35-second teaser: / { print ""; print "A stray line." }' chk_top
  st 'the hero image line removed' 1 "$README" '!/^!\[The OcuTalon page on the online demo/' chk_top
  st 'a second image line' 1 "$README" '{ print } /^!\[The OcuTalon page on the online demo/ { print ""; print "![Second.](docs/images/page-incident.png)" }' chk_top
  st 'a second image on the hero line' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { $0 = $0 " ![Second.](docs/images/page-incident.png)" } { print }' chk_top
  st 'text after the hero image' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { $0 = $0 " on the demo (live)" } { print }' chk_top
  st 'the hero above the teaser' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { next } /^Watch the 35-second teaser: / { print "![Hero.](docs/images/page-incident.png)"; print "" } { print }' chk_top
  st 'the hero moved under the first H2 section' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { hero = $0; next } { print } /^## Try it in two minutes$/ { print ""; print hero }' chk_top
  st 'the How you talk to it section removed' 1 "$README" '!/^## How you talk to it$/' chk_top
  st 'the How you talk to it section renamed' 1 "$README" '/^## How you talk to it$/ { print "## How to talk to it"; next } { print }' chk_top
  st 'How you talk to it swapped with What OcuTalon does' 1 "$README" '/^## How you talk to it$/ { print "## What OcuTalon does"; next } /^## What OcuTalon does$/ { print "## How you talk to it"; next } { print }' chk_top
  st 'How you talk to it swapped with What you can use it for' 1 "$README" '/^## How you talk to it$/ { print "## What you can use it for"; next } /^## What you can use it for$/ { print "## How you talk to it"; next } { print }' chk_top
  st 'a required section removed' 1 "$README" '!/^## Troubleshooting$/' chk_top
  st 'the Contest task section back' 1 "$README" '{ print } END { print ""; print "## Contest task"; print "" }' chk_top
  st 'the Contest task table header back' 1 "$README" '{ print } /^## What OcuTalon does$/ { print ""; print "| Contest task or criterion | x | y |" }' chk_top
  finish top 'the title, the opening paragraph, the teaser and the hero image, then the four top sections in order, and the other sections are there' chk_top
}

rule_try_it() {
  local n
  rule_begin try-it "$README" || return
  st_facts chk_try_it "$TRY_FACTS"
  st 'install.sh before the demo link' 1 "$README" '{ print } /^## Try it in two minutes$/ { print ""; print "Run ./install.sh first." }' chk_try_it
  for n in 1 2 3; do
    st "step $n removed" 1 "$README" "!/^$n\\. /" chk_try_it
  done
  st 'step 4 removed' 1 "$README" '!/^4\. /' chk_try_it
  st 'a fifth step' 1 "$README" '/^4\. / { print; print "5. One more." ; next } { print }' chk_try_it
  st_move 'step 2 moved out of the section' "$H_TRY" '2. ' chk_try_it
  st 'the phrase away from the demo link' 1 "$README" "{ i = index(\$0, \"$DEMO_PHRASE\"); if (i && index(\$0, \"https://demo.ocutalon.com\")) { print substr(\$0, 1, i - 1) \"zz\" substr(\$0, i + length(\"$DEMO_PHRASE\")); print \"\"; print \"$DEMO_PHRASE\"; next } print }" chk_try_it
  finish try-it 'the online demo comes first, then four numbered steps for the local path' chk_try_it
}

rule_interesting() {
  local n
  rule_begin interesting "$README" || return
  st_facts chk_interesting "$INT_FACTS"
  n=$(section "$README" "$H_INT" | wc -w)
  n=$((n + 0))
  if [ "$n" -le 120 ]; then
    # The limit itself: the section padded to exactly 121 words is flagged, and padded to exactly 120 it is not.
    st 'exactly 121 words' 1 "$README" "{ print } /^## What.s interesting\$/ { print \"\"; for (i = $n; i < 121; i++) printf \"w \"; print \"\" }" chk_interesting
    if ! mutate "$README" "{ print } /^## What.s interesting\$/ { print \"\"; for (i = $n; i < 120; i++) printf \"w \"; print \"\" }"; then
      st_note 'exactly 120 words: the edit changed nothing'
    elif [ -n "$(chk_interesting "$tmp/m")" ]; then
      st_note 'exactly 120 words is flagged'
    fi
  fi
  finish interesting 'at most 120 words, and it names the workflow, Visual Trace, the AI Hub agent, the dry run and the audit log' chk_interesting
}

rule_use_cases() {
  rule_begin use-cases "$README" || return
  st 'item 1 changed' 1 "$README" '/^- \*\*The partner feed/ { sub(/2am/, "3am") } { print }' chk_use_cases
  st 'item 2 changed' 1 "$README" '/^- \*\*"Only tell me/ { sub(/never gives/, "rarely gives") } { print }' chk_use_cases
  st 'item 1 removed' 1 "$README" '!/^- \*\*The partner feed/' chk_use_cases
  st 'item 2 removed' 1 "$README" '!/^- \*\*"Only tell me/' chk_use_cases
  st 'the items swapped' 1 "$README" '/^- \*\*The partner feed/ { held = $0; next } { print } /^- \*\*"Only tell me/ { print held }' chk_use_cases
  st 'a fourth item' 1 "$README" '{ print } /^- \*\*\[An AI decision step/ { print "- **A fourth item.** More." }' chk_use_cases
  st 'the production-stopped sentence appended to item 2' 1 "$README" '/^- \*\*"Only tell me/ { $0 = $0 " It also tells you once when a production stops or one of its items is disabled." } { print }' chk_use_cases
  st 'the production-stopped sentence on a line of its own' 1 "$README" '{ print } /^- \*\*"Only tell me/ { print "It also tells you once when a production stops or one of its items is disabled." }' chk_use_cases
  st 'the audit item without its link' 1 "$README" '/^- \*\*\[An AI decision step/ { $0 = "- **An AI decision step you can audit, in your own production.**" } { print }' chk_use_cases
  st 'the audit item linking another file' 1 "$README" '/^- \*\*\[An AI decision step/ { sub(/docs\/bridge-guide\.md/, "docs/install-ipm.md") } { print }' chk_use_cases
  st 'the audit item removed' 1 "$README" '!/^- \*\*\[An AI decision step/' chk_use_cases
  st 'the section heading removed' 1 "$README" '!/^## What you can use it for$/' chk_use_cases
  finish use-cases 'What you can use it for holds exactly the three items, word for word' chk_use_cases
}

rule_how_you_talk() {
  rule_begin how-you-talk "$README" || return
  st 'the heading removed' 1 "$README" '!/^## How you talk to it$/' chk_how_you_talk
  st_facts chk_how_you_talk "$TALK_FACTS"
  st_move 'the Demo mode paragraph moved out of the section' "$H_TALK" 'Demo mode is on in the online demo' chk_how_you_talk
  st 'the table rows removed' 1 "$README" '/^## / { s = ($0 == "## How you talk to it") } s && /^\|/ { next } { print }' chk_how_you_talk
  st 'the table separator line removed' 1 "$README" '/^## / { s = ($0 == "## How you talk to it") } s && /^\| --- \|/ { next } { print }' chk_how_you_talk
  st 'the image line removed' 1 "$README" '/^## / { s = ($0 == "## How you talk to it") } s && /^!\[/ { next } { print }' chk_how_you_talk
  st 'Slack named in the section' 1 "$README" '{ print } /^## How you talk to it$/ { print ""; print "It also works in Slack." }' chk_how_you_talk
  finish how-you-talk 'the web chat page on every install, the demo-only parts, email in a later release, a table and an image' chk_how_you_talk
}

# swap_target <old> <new>: an awk program that replaces the target <old> of the first image link with <new>.
swap_target() {
  printf '%s' '!done && (j = index($0, "]('"$1"')")) > 0 { $0 = substr($0, 1, j + 1) "'"$2"'" substr($0, j + 2 + length("'"$1"'")); done = 1 } { print }'
}

# set_alt <target> <alt>: an awk program that replaces the alt text of the image link with that target.
set_alt() {
  printf '%s' '!done && (j = index($0, "]('"$1"')")) > 0 { i = index($0, "!["); if (i > 0 && i < j) { $0 = substr($0, 1, i + 1) "'"$2"'" substr($0, j); done = 1 } } { print }'
}

rule_images() {
  local first other
  printf '%s\n' "$listing" > "$tmp/files.list"
  rule_begin images "$README" "$tmp/files.list" || return
  # The self-tests use the README's own first image link, so that no image file is named here.
  first=$(image_links "$README" | head -n 1 | cut -f3)
  other=$(printf '%s\n' "$listing" | grep -m 1 '^logo/.*\.png$')
  if [ -z "$other" ]; then st_note 'the tree lists no logo PNG, the file outside docs/images/ to link'; fi
  st 'an empty alt text' 1 "$README" "$(set_alt "$first" '')" chk_images
  st 'a blank alt text' 1 "$README" "$(set_alt "$first" '   ')" chk_images
  st 'a file the tree does not list' 1 "$README" "$(swap_target "$first" docs/images/zz-missing.png)" chk_images
  st 'a file outside docs/images/' 1 "$README" "$(swap_target "$first" "$other")" chk_images
  st 'dot segments' 1 "$README" "$(swap_target "$first" "docs/images/../images/${first##*/}")" chk_images
  st 'a remote address' 1 "$README" "$(swap_target "$first" https://example.org/hero.png)" chk_images
  st 'a second image on the line with no alt text' 1 "$README" '!done && index($0, "]('"$first"')") > 0 { $0 = $0 " ![]('"$first"')"; done = 1 } { print }' chk_images
  st 'every image line removed' 1 "$README" 'index($0, "![") == 0' chk_images
  st 'the images of What OcuTalon does removed' 1 "$README" '/^## / { s = ($0 == "## What OcuTalon does") } s && /^  !\[/ { next } { print }' chk_images
  st 'the Chat bullet image moved under the Break the feed bullet' 1 "$README" '/^## / { s = ($0 == "## What OcuTalon does") } s && /^  !\[/ && !held { held = $0; next } s && /^  !\[/ && held && !put { print held; print ""; put = 1 } { print }' chk_images
  st 'the images of What OcuTalon does made reference-style' 1 "$README" '/^## / { s = ($0 == "## What OcuTalon does") } s && /^  !\[/ { sub(/\]\(/, "][") } { print }' chk_images
  st 'the last Break the feed image moved under the Chat bullet' 1 "$README" '/^## / { s = ($0 == "## What OcuTalon does") } /^- \*\*/ { b = (index($0, "- **Break the feed.**") == 1) } s && b && /^  !\[/ { last = $0 } { line[NR] = $0 } END { for (i = 1; i <= NR; i++) { if (line[i] == last) continue; print line[i]; if (index(line[i], "- **Chat on a live page.**") == 1) { print ""; print last } } }' chk_images
  st 'no empty line between the text and an image line' 1 "$README" 'held { held = 0; if ($0 == "") next } { print } /^Watch the 35-second teaser: / { held = 1 }' chk_images
  st 'the images under the Break the feed bullet removed' 1 "$README" '/^## / { s = ($0 == "## What OcuTalon does") } /^- \*\*/ { b = (index($0, "- **Break the feed.**") == 1) } s && b && /^  !\[/ { next } { print }' chk_images
  st 'the first image file dropped from the list' 2 "$tmp/files.list" '$0 != "'"$first"'"' chk_images
  # A newly listed and linked docs/images file is not flagged: the rule names no file.
  mkdir -p "$tmp/imgs"
  { cat "$tmp/files.list"; echo docs/images/zz-extra.png; } > "$tmp/imgs/extra.list"
  { cat "$README"; printf '\n![Extra.](docs/images/zz-extra.png)\n'; } > "$tmp/imgs/extra.md"
  if [ -n "$(chk_images "$tmp/imgs/extra.md" "$tmp/imgs/extra.list")" ]; then st_note 'a newly listed and linked docs/images file is flagged'; fi
  finish images 'every image link has alt text and reaches a file of docs/images/ that the tree lists' chk_images
}

rule_teaser() {
  rule_begin teaser "$README" || return
  st 'the teaser line removed' 1 "$README" '!/^Watch the 35-second teaser: /' chk_teaser
  st 'the teaser line changed' 1 "$README" '{ sub(/35-second/, "36-second"); print }' chk_teaser
  st 'the teaser moved to the end of the README' 1 "$README" '/^Watch the 35-second teaser: / { next } { print } END { print ""; print "Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU" }' chk_teaser
  st 'the teaser above the opening paragraph' 1 "$README" '/^Watch the 35-second teaser: / { next } /^Your integrations already/ { print "Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU"; print "" } { print }' chk_teaser
  st 'the teaser under the first H2 section' 1 "$README" '/^Watch the 35-second teaser: / { next } { print } /^## Try it in two minutes$/ { print ""; print "Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU" }' chk_teaser
  st 'no empty line between the opening paragraph and the teaser' 1 "$README" 'held { held = 0; if ($0 == "") next } { print } /^Your integrations already/ { held = 1 }' chk_teaser
  st 'a stray line where the empty line is' 1 "$README" 'held { held = 0; if ($0 == "") { print "x"; next } } { print } /^Your integrations already/ { held = 1 }' chk_teaser
  st_append 'an embedded image' '![teaser](teaser.png)' chk_teaser
  st_append 'a linked image' '[![Teaser](docs/images/page-incident.png)](https://youtu.be/wycbyfnXFMU)' chk_teaser
  st_append 'a remote image' '![teaser](https://youtu.be/wycbyfnXFMU)' chk_teaser
  st_append 'a GIF' '![teaser](docs/images/teaser.gif)' chk_teaser
  st_append 'a reference-style image' '![teaser][t]' chk_teaser
  st_append 'an image tag' '<img src=teaser.png>' chk_teaser
  st_append 'a frame' '<iframe src=teaser></iframe>' chk_teaser
  st_append 'a video tag' '<video src=teaser.mp4></video>' chk_teaser
  st_append 'an image tag in capitals' '<IMG src=teaser.png>' chk_teaser
  st_append 'a picture tag' '<picture><source srcset=teaser.png></picture>' chk_teaser
  st_append 'the teaser line twice' "$TEASER" chk_teaser
  finish teaser 'the teaser is a plain link, word for word, two lines below the opening paragraph, with no media tag and only inline docs/images PNG images' chk_teaser
}

rule_outcomes() {
  local name
  rule_begin outcomes "$README" "$chatview_p" || return
  for name in Ignore Digest 'Tell now' Act; do
    st "the outcome $name removed" 1 "$README" "{ if (index(\$0, \"**$name**: \") > 0) next; print }" chk_outcomes
  done
  st 'a meaning of the page changed' 2 "$chatview_p" '/meaningIgnore:/ { sub(/'"'"'.*'"'"'/, "'"'"'Changed meaning'"'"'") } { print }' chk_outcomes
  st 'no meanings in the page' 2 "$chatview_p" '!/meaningIgnore/' chk_outcomes
  finish outcomes 'Ignore, Digest, Tell now and Act, with the meanings that the page shows' chk_outcomes
}

rule_install() {
  rule_begin install "$README" || return
  st_facts chk_install "$INSTALL_FACTS"
  st_move 'the Compose version moved out of the section' 'Install it yourself' '- Docker Compose 2.24' chk_install
  finish install 'Compose 2.24, both image names, load and retag, the portal, the CPUs and the 15-minute wait' chk_install
}

rule_install_pointer() {
  rule_begin install-pointer "$README" "$install_p" || return
  st 'the Troubleshooting heading removed' 1 "$README" '!/^## Troubleshooting$/' chk_install_pointer
  st 'install.sh names another section' 2 "$install_p" '{ sub(/The Troubleshooting section/, "The Cooking section"); print }' chk_install_pointer
  st 'install.sh names no section' 2 "$install_p" '{ sub(/section of README/, "part of README"); print }' chk_install_pointer
  finish install-pointer 'every README section that install.sh points to is an H2 heading' chk_install_pointer
}

rule_commands() {
  local cmds cmd
  rule_begin commands "$README" "$install_p" || return
  cmds=$(sed -n 's/.*run: *\(docker compose[^"]*\)".*/\1/p' "$install_p" | sed 's/ *$//' | sort -u)
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    if ! strip_str "$README" "$cmd"; then
      st_note "without '$cmd': the edit changed nothing"
    elif [ -z "$(chk_commands "$tmp/m" "$S2")" ]; then
      st_note "without '$cmd': not flagged"
    fi
  done <<EOF
$cmds
EOF
  st_append 'docker compose restart' 'Run docker compose restart to apply it.' chk_commands
  st_append 'install.sh again' 'Run ./install.sh again to apply it.' chk_commands
  st_append 'install.sh in backticks again' 'Run `./install.sh` again to apply it.' chk_commands
  st_append 'the install script again' 'Run the install script again to apply it.' chk_commands
  st_append 'docker restart' 'Run docker restart to apply it.' chk_commands
  st_append 'docker-compose restart' 'Run docker-compose restart to apply it.' chk_commands
  st_append 'rerun' 'Then rerun the script.' chk_commands
  st_append 're-run' 'Then Re-run the script.' chk_commands
  st 'install.sh prints no command after run:' 2 "$install_p" '{ gsub(/run:/, "go:"); print }' chk_commands
  finish commands 'every command that install.sh prints is in the README, and none that it never gives' chk_commands
}

rule_key_account() {
  rule_begin key-account "$README" || return
  st_facts chk_key_account "$KEY_FACTS"
  st_facts chk_key_account "$ACCOUNT_FACTS"
  st_facts chk_key_account "$FIXED_SENTENCE"
  st_facts chk_key_account "$MODEL_BLOCK"
  st 'a cell of the model table changed' 1 "$README" '{ sub(/with no cause and no fix/, "with a cause and no fix"); print }' chk_key_account
  st 'a row of the model table removed' 1 "$README" '!/^\| 50 orders fail \|/' chk_key_account
  st 'a fourth row added to the model table' 1 "$README" '{ print } /^\| You ask in the chat \|/ { print "| Cost | Costs you nothing extra | Free |" }' chk_key_account
  st 'the empty line above the table removed' 1 "$README" '{ line[NR] = $0 } END { for (i = 1; i <= NR; i++) if (!(line[i] == "" && line[i + 1] ~ /^\| \| With a model/)) print line[i] }' chk_key_account
  st 'the empty line above the model paragraph removed' 1 "$README" '{ line[NR] = $0 } END { for (i = 1; i <= NR; i++) if (!(line[i] == "" && index(line[i + 1], "**With a model, and without one.**") == 1)) print line[i] }' chk_key_account
  st 'a line without a bar right under the model table' 1 "$README" '{ print } /^\| You ask in the chat \|/ { print "Cost | Costs you nothing extra | Free" }' chk_key_account
  st 'a bullet after the model table' 1 "$README" '{ print } /^\| You ask in the chat \|/ { print ""; print "- **Extra.** More." }' chk_key_account
  st_move 'the model table moved out of its section' 'What OcuTalon does' '|' chk_key_account
  st_move 'the fixed-rules sentence moved out of its section' 'Set a model key' 'Without a key, OcuTalon still starts.' chk_key_account
  st_append 'the bullet back' '- **No key, still works.** Without a model key, OcuTalon starts and every decision uses fixed rules. The page says so.' chk_key_account
  st_append 'a key-shaped example' 'Set ANTHROPIC_API_KEY=abc in .env.' chk_key_account
  finish key-account 'the key line, .env.example, the default model, the fixed-rules sentence, the model paragraph and table, the README account and the Visual Trace sign-in' chk_key_account
}

rule_lan() {
  rule_begin lan "$README" || return
  st_facts chk_lan "$LAN_FACTS"
  st_move 'the warning moved out of the section' 'Sign in' '**Change the README account' chk_lan
  finish lan 'Sign in warns about the LAN and the Management Portal and links to the password steps' chk_lan
}

rule_sign_in_address() {
  rule_begin sign-in-address "$README" "$install_p" "$compose_p" || return
  st 'another address in the ready block' 1 "$README" '/^  Open: / { $0 = $0 "zz" } { print }' chk_sign_in_address
  st 'another user in the ready block' 1 "$README" '/^  User: / { $0 = $0 "zz" } { print }' chk_sign_in_address
  st 'another password in the ready block' 1 "$README" '/^  Password: / { $0 = $0 "zz" } { print }' chk_sign_in_address
  st 'another address in Try it' 1 "$README" '/^## / { s = ($0 == "## Try it in two minutes") } s { gsub(/http:\/\/localhost/, "http://zz") } { print }' chk_sign_in_address
  st 'another address in Sign in' 1 "$README" '/^## / { s = ($0 == "## Sign in") } s { gsub(/http:\/\/localhost/, "http://zz") } { print }' chk_sign_in_address
  st 'another account in Try it' 1 "$README" '/^## / { s = ($0 == "## Try it in two minutes") } s && /^3\. / { gsub(/`[^`]*`/, "`zz`") } { print }' chk_sign_in_address
  st 'install.sh prints another address' 2 "$install_p" '/^[[:space:]]*echo "  Open: / { sub(/"$/, "zz\"") } { print }' chk_sign_in_address
  st 'install.sh prints no ready block' 2 "$install_p" '!/^[[:space:]]*echo "  Open: /' chk_sign_in_address
  st 'another default port in the compose file' 3 "$compose_p" '{ sub(/OCUTALON_WEB_PORT:-[0-9]+/, "OCUTALON_WEB_PORT:-1"); print }' chk_sign_in_address
  st 'no default port in the compose file' 3 "$compose_p" '{ sub(/OCUTALON_WEB_PORT:-/, "OCUTALON_WEB_PORT:?"); print }' chk_sign_in_address
  finish sign-in-address 'the ready block, the address and the account are the ones install.sh prints, with the default web port' chk_sign_in_address
}

rule_demo_mode() {
  local kept
  rule_begin demo-mode "$README" "$admin_p" "$experience_p" || return
  st_facts chk_demo_mode "$DEMO_FACTS"
  st 'Admin.cls without SetDemoMode' 2 "$admin_p" '{ sub(/ClassMethod SetDemoMode\(/, "ClassMethod SetDemo("); print }' chk_demo_mode
  st 'the kept sentence changed in EXPERIENCE.md' 3 "$experience_p" '{ sub(/OcuTalon left the OCUORDERS namespace/, "&, as agreed"); print }' chk_demo_mode
  st 'no kept sentence in EXPERIENCE.md' 3 "$experience_p" '!/OcuTalon left the OCUORDERS namespace/' chk_demo_mode
  kept=$(sed -n 's/^.*"\(OcuTalon left the OCUORDERS namespace[^"]*\)".*$/\1/p' "$experience_p" | head -n 1)
  if [ -n "$kept" ]; then
    if ! strip_str "$README" "$kept"; then
      st_note "without the kept sentence: the edit changed nothing"
    elif [ -z "$(chk_demo_mode "$tmp/m" "$S2" "$S3")" ]; then
      st_note "without the kept sentence: not flagged"
    fi
  fi
  finish demo-mode 'the SetDemoMode line, its roles and the kept-OCUORDERS sentence as EXPERIENCE.md writes it' chk_demo_mode
}

rule_admin_commands() {
  rule_begin admin-commands "$README" || return
  st_facts chk_admin_commands "$ADMIN_FACTS"
  finish admin-commands 'the terminal sessions and the password line are the ones the walkthrough ran' chk_admin_commands
}

rule_after_start_log() {
  rule_begin after-start-log "$README" "$after_start_p" || return
  st_facts chk_after_start_log "docker compose exec iris cat $(log_path "$after_start_p")
$LOG_FACTS"
  st 'another log path in docker/after-start.sh' 2 "$after_start_p" '/^log_file=/ { sub(/LOG:-[^}]*/, "LOG:-/durable/zz-other.log") } { print }' chk_after_start_log
  st 'no default log path in docker/after-start.sh' 2 "$after_start_p" '{ sub(/^log_file=/, "lf="); print }' chk_after_start_log
  finish after-start-log 'the log command names the path that docker/after-start.sh writes, and the lines to look for' chk_after_start_log
}

rule_dev_only() {
  local text label
  if ! rule_begin dev-only "$README"; then return; fi
  printf '# T\n\nSee OcuTalon.Core.Admin here.\n\n## For admins and developers\n' > "$tmp/dev.bad"
  printf '# T\n\n## Plain\n\nSee README.md, demo.ocutalon.com and docs.docker.com: they are not class names.\n\n## For admins and developers\n\n### Demo mode\n\ndo ##class(OcuTalon.Core.Admin).SetDemoMode(1)\nERROR #5001 <UNDEFINED> %%SYS.Namespace\n\n## Credits\n\nPlain words again.\n' > "$tmp/dev.good"
  while IFS='|' read -r label text; do
    [ -n "$label" ] || continue
    st "$label above the section" 1 "$README" "NR == 1 { print; print \"$text\"; next } { print }" dev_names_1
  done <<'EOF'
a ##class( call|Call ##class(Foo.Bar).Baz() now.
a class name|The class OcuTalon.Core.X does it.
a system class name|Security.Users holds it.
a percent class name|The class %SYS.Namespace holds it.
an error code|It failed with ERROR #5001 today.
an error name|It showed <UNDEFINED> there.
EOF
  st_append 'a class name after the admin section' '## After\n\nThe class OcuTalon.Core.X does it.' dev_names_1
  if [ "$st_bad" -ne 0 ] && [ -z "$(dev_names "$README")" ]; then
    printf '%s' "$st_msgs"
    echo "FAIL dev-only: a broken copy was not flagged"
    fails=$((fails + 1))
    return
  fi
  scan_rule 'dev-only: no ##class(, class name or error code outside "For admins and developers"' dev_names "$tmp/dev.bad" "$tmp/dev.good" "$README"
}

rule_public_text() {
  local text label
  if ! rule_begin public-text "$README"; then return; fi
  printf 'This runs on OpenAI.\n' > "$tmp/pub.bad"
  { printf '%s\n' "$NOTE"; printf '%s\n' "$PUBLIC_FACTS"; printf 'Listen on 127.0.0.1 or 0.0.0.0 only.\nNot providers, only words that contain one: llamas, grokking, gptx and azurite.\n'; } > "$tmp/pub.good"
  st_facts public_text_1 "$PUBLIC_FACTS"
  st 'the note altered' 1 "$README" '{ sub(/not affiliated with/, "affiliated with"); print }' public_text_1
  st 'OpenClaw outside the note' 1 "$README" '/^# OcuTalon$/ { print; print ""; print "An OpenClaw-style assistant."; next } { print }' public_text_1
  while IFS='|' read -r label text; do
    [ -n "$label" ] || continue
    st_append "$label" "$text" public_text_1
  done <<'EOF'
a model provider|It also works with Gemini.
a model provider in capitals|It also works with ChatGPT.
OpenAI|It also works with OpenAI.
GPT|It also works with GPT.
Mistral|It also works with Mistral.
Cohere|It also works with Cohere.
Llama|It also works with Llama.
Ollama|It also works with Ollama.
Bedrock|It also works with Bedrock.
Azure|It also works with Azure.
DeepSeek|It also works with DeepSeek.
Grok|It also works with Grok.
a provider with a version|It also works with GPT4 and Llama3.
from your phone|Approve it from your phone.
per step|Costs are shown per step.
per-step|Costs are shown per-step.
a bug-hunt section|Find a bug in AI Hub and win.
a bonus section|Bonus: a second prize.
a private word|Runs on a droplet.
a CI host name|Runs on ocutalon-ci-b.
a slot name|Runs on ocutalon-slot-a.
a worktree folder|Built in .worktrees today.
a coordination folder|Locks live in .coordination now.
a cloud host|Runs on DigitalOcean.
a data centre|Runs in sfo2.
the planner|The Contest Planner decides.
the cycle|The epic-cycle runs it.
a runner kind|It runs on a self-hosted runner.
an IPv4 address|Open http://192.168.1.10:52773 now.
EOF
  if [ "$st_bad" -ne 0 ] && [ -z "$(public_text_scan "$README")" ]; then
    printf '%s' "$st_msgs"
    echo "FAIL public-text: a broken copy was not flagged"
    fails=$((fails + 1))
    return
  fi
  scan_rule 'public-text: the note, the credit and the licence pointers; no other provider, private word or address' public_text_scan "$tmp/pub.bad" "$tmp/pub.good" "$README"
}

rule_no_telegram() {
  rule_begin no-telegram "$README" "$(telegram_mode "$included_p")" || return
  S2=testonly st_append 'the word Telegram' 'Set up Telegram here.' chk_no_telegram
  S2=testonly st_append 'the word in capitals' 'TELEGRAM_BOT_TOKEN=x' chk_no_telegram
  printf 'Set up Telegram here.\n' > "$tmp/tg.txt"
  if [ -n "$(chk_no_telegram "$tmp/tg.txt" included)" ]; then st_note 'the word is flagged although Included() no longer has its test-only body'; fi
  if [ "$(telegram_mode "$included_p")" = testonly ]; then
    finish no-telegram 'no Telegram while Included() has its test-only body' chk_no_telegram
  else
    finish no-telegram 'Included() no longer has its test-only body, so the word is allowed' chk_no_telegram
  fi
}

rule_product_links() {
  local mode lits got
  rule_begin product-links "$README" "$tmp/product.list" "$included_p" || return
  # Only the product's files are read: a spec file and a class under /Test/ are not.
  got=$(printf '%s\n' web/src/app/a.ts web/src/app/a.spec.ts src/p/C.cls src/p/Test/T.cls web/e2e/x.ts docs/y.cls | product_files)
  if [ "$got" != "$(printf '%s\n%s' web/src/app/a.ts src/p/C.cls)" ]; then st_note 'the product files are not exactly the page sources and the classes that are not tests'; fi
  # An anchor with no heading is named.
  mkdir -p "$tmp/inv"
  printf "export const SETUP_ANCHOR = 'nowhere';\n" > "$tmp/inv/Extra.ts"
  { cat "$tmp/product.list"; printf '%s\n' "$tmp/inv/Extra.ts"; } > "$tmp/inv/with-extra.list"
  if ! chk_product_links "$README" "$tmp/inv/with-extra.list" "$included_p" | grep -q "'#nowhere'"; then st_note 'an anchor with no heading is not named'; fi
  # No inventory: the check fails closed.
  : > "$tmp/inv/none.list"
  if [ -z "$(chk_product_links "$README" "$tmp/inv/none.list" "$included_p")" ]; then st_note 'an empty link inventory is not flagged'; fi
  printf "export const OTHER = 'x';\n" > "$tmp/inv/Other.ts"
  printf '%s\n' "$tmp/inv/Other.ts" > "$tmp/inv/other.list"
  if [ -z "$(chk_product_links "$README" "$tmp/inv/other.list" "$included_p")" ]; then st_note 'an inventory without #readme and #telegram is not flagged'; fi
  # The other two places an anchor is written, a readmeSection literal and an address, are named too.
  printf "const link = readmeSection(README_URL, 'lit-section');\n" > "$tmp/inv/Lit.ts"
  printf '/// https://github.com/jbrandtmse/OcuTalon#lit-address\n' > "$tmp/inv/Lit.cls"
  { cat "$tmp/product.list"; printf '%s\n%s\n' "$tmp/inv/Lit.ts" "$tmp/inv/Lit.cls"; } > "$tmp/inv/with-lits.list"
  lits=$(chk_product_links "$README" "$tmp/inv/with-lits.list" "$included_p")
  case $lits in *"'#lit-section'"*) ;; *) st_note 'a readmeSection literal with no heading is not named' ;; esac
  case $lits in *"'#lit-address'"*) ;; *) st_note 'an address literal with no heading is not named' ;; esac
  # Included() with another body, or no In.cls, covers #telegram: a README without a heading with that slug is flagged. While
  # the body is the test-only one, #telegram is left out. The README of these cases has any Telegram heading renamed.
  awk '/^#+ [Tt]elegram$/ { sub(/[Tt]elegram$/, "Zz") } { print }' "$README" > "$tmp/inv/README.md"
  printf 'ClassMethod Included() As %%Boolean\n{\n\tQuit $Get(^OcuTalonTest("TelegramIncluded")) = 1\n}\n' > "$tmp/inv/In.testonly.cls"
  printf 'ClassMethod Included() As %%Boolean\n{\n\tQuit 1\n}\n' > "$tmp/inv/In.changed.cls"
  if ! chk_product_links "$tmp/inv/README.md" "$tmp/product.list" "$tmp/inv/In.changed.cls" | grep -q "'#telegram'"; then st_note 'Included() with another body does not cover #telegram'; fi
  if ! chk_product_links "$tmp/inv/README.md" "$tmp/product.list" "$tmp/absent" | grep -q "'#telegram'"; then st_note 'no In.cls does not cover #telegram'; fi
  if chk_product_links "$tmp/inv/README.md" "$tmp/product.list" "$tmp/inv/In.testonly.cls" | grep -q "'#telegram'"; then st_note 'the test-only body does not leave #telegram out'; fi
  mode=$(telegram_mode "$included_p")
  finish product-links 'every README anchor that the page or the server text can show reaches a heading' chk_product_links
  if [ "$mode" = testonly ]; then
    echo 'SKIP #telegram: Included() has its test-only body, so the page never shows the link to a README Telegram section'
  fi
}

rule_telegram_section() {
  local n
  rule_begin telegram-section "$README" || return
  st 'the heading renamed' 1 "$README" '/^## Telegram$/ { print "## Phones"; next } { print }' chk_telegram_section
  st 'the section removed' 1 "$README" '/^## Telegram$/ { skip = 1; next } skip && /^## / { skip = 0 } !skip' chk_telegram_section
  st_facts chk_telegram_section "$TG_FACTS"
  for n in 1 2 3 4 5; do
    st "step $n removed" 1 "$README" "/^## / { s = (\$0 == \"## Telegram\") } !(s && /^$n\\. /)" chk_telegram_section
  done
  st 'a sixth step' 1 "$README" '/^5\. / { print; print "6. One more."; next } { print }' chk_telegram_section
  st 'the section above Sign in' 1 "$README" '{ l[NR] = $0 } /^## Telegram$/ { t = NR } END { e = t; while (e < NR && l[e + 1] !~ /^## /) e++; for (i = 1; i <= NR; i++) { if (l[i] == "## Sign in") for (j = t; j <= e; j++) print l[j]; if (t && i >= t && i <= e) continue; print l[i] } }' chk_telegram_section
  finish telegram-section 'the Telegram section sits after Sign in with five steps and the facts a person needs to follow them' chk_telegram_section
}

rule_telegram_strings() {
  local str src kind file out
  rule_begin telegram-strings "$README" || return
  chk_telegram_strings_real() { chk_telegram_strings "$1" "$railview_p" "$cardview_p" "$buttons_p"; }
  st 'Telegram not set up reworded' 1 "$README" '{ sub(/"Telegram not set up"/, "\"Telegram is not set up\"") } { print }' chk_telegram_strings_real
  st 'Telegram paired reworded' 1 "$README" '{ sub(/"Telegram paired"/, "\"Paired with Telegram\"") } { print }' chk_telegram_strings_real
  st 'Unpair reworded' 1 "$README" '{ sub(/"Unpair"/, "\"Disconnect\"") } { print }' chk_telegram_strings_real
  st 'Approve reworded' 1 "$README" '{ sub(/"Approve"/, "\"Yes\"") } { print }' chk_telegram_strings_real
  st 'a new quoted string' 1 "$README" '/^1\. In Telegram/ { $0 = $0 " Tap \"Pair now\"." } { print }' chk_telegram_strings_real
  st 'a quoted string unquoted' 1 "$README" '{ sub(/"Reject"/, "Reject") } { print }' chk_telegram_strings_real
  # The source side: a built page that no longer shows a string is flagged.
  while IFS='|' read -r str src kind; do
    [ -n "$str" ] || continue
    case $src in RAIL) file=$railview_p ;; CARD) file=$cardview_p ;; *) file=$buttons_p ;; esac
    if [ "$kind" = ts ]; then
      strip_str "$file" "'$str'" || { st_note "the source without '$str': the edit changed nothing"; continue; }
    else
      strip_str "$file" "\"text\": \"$str\"," || { st_note "the catalog without \"$str\": the edit changed nothing"; continue; }
    fi
    case $src in
      RAIL) out=$(chk_telegram_strings "$README" "$tmp/m" "$cardview_p" "$buttons_p") ;;
      CARD) out=$(chk_telegram_strings "$README" "$railview_p" "$tmp/m" "$buttons_p") ;;
      *) out=$(chk_telegram_strings "$README" "$railview_p" "$cardview_p" "$tmp/m") ;;
    esac
    if [ -z "$out" ]; then st_note "the built page without \"$str\" is not flagged"; fi
  done <<EOT
$TG_UI
EOT
  finish telegram-strings 'every UI string the Telegram section quotes is shown by the built page' chk_telegram_strings_real
}

rule_telegram_facts() {
  rule_begin telegram-facts "$README" "$included_p" "$layoutview_p" || return
  st 'the pause reworded to 10 minutes' 1 "$README" '{ sub(/after 5 minutes/, "after 10 minutes") } { print }' chk_telegram_facts
  st 'the pause time removed' 1 "$README" '{ sub(/ and tries again after 5 minutes/, "") } { print }' chk_telegram_facts
  st 'the Status section renamed in step 5' 1 "$README" '{ sub(/In the Status section/, "In the Status band") } { print }' chk_telegram_facts
  st 'the address of step 5 changed' 1 "$README" '/^5\. / { sub(/localhost:52773/, "localhost:52774") } { print }' chk_telegram_facts
  st 'step 5 without an address' 1 "$README" '/^5\. / { sub(/http:\/\/localhost:52773\/ocutalon\//, "the page") } { print }' chk_telegram_facts
  st 'PAUSESECONDS changed' 2 "$included_p" '{ sub(/Parameter PAUSESECONDS = 300;/, "Parameter PAUSESECONDS = 600;") } { print }' chk_telegram_facts
  st 'the page region renamed' 3 "$layoutview_p" "{ sub(/status: 'Status',/, \"status: 'State',\") } { print }" chk_telegram_facts
  TGF_ENV=$tmp/env.broken
  sed 's/^TELEGRAM_BOT_TOKEN=/TELEGRAM_TOKEN=/' "$envexample_p" > "$TGF_ENV"
  if [ -z "$(chk_telegram_facts "$README" "$included_p" "$layoutview_p")" ]; then st_note '.env.example without the TELEGRAM_BOT_TOKEN= line is not flagged'; fi
  TGF_ENV=$envexample_p
  TGF_COMPOSE=$tmp/compose.broken
  sed 's/- path: \.env$/- path: .env.local/' "$compose_p" > "$TGF_COMPOSE"
  if [ -z "$(chk_telegram_facts "$README" "$included_p" "$layoutview_p")" ]; then st_note 'a compose file that does not read .env is not flagged'; fi
  TGF_COMPOSE=$compose_p
  finish telegram-facts 'the pause time, the Status section, the token line, the compose env file and the address of the steps are what is built' chk_telegram_facts
}

rule_telegram_demo() {
  rule_begin telegram-demo "$README" || return
  st_append 'a sentence about the online demo that mentions Telegram' 'The online demo also sends Telegram notices.' chk_telegram_demo
  st_append 'a sentence about the online demo that mentions pairing' 'Pairing works in the online demo.' chk_telegram_demo
  st_append 'a sentence about the online demo that mentions a paired chat' 'The online demo keeps your paired chat.' chk_telegram_demo
  st_append 'a sentence about the demo address that mentions a paired phone' 'Visit https://demo.ocutalon.com with your paired phone.' chk_telegram_demo
  st_append 'a Telegram sentence outside the section that does not say your own install' 'You can approve it in Telegram too.' chk_telegram_demo
  st 'the use case without your own install' 1 "$README" '/^- \*\*The partner feed/ { sub(/On your own install you/, "You") } { print }' chk_telegram_demo
  finish telegram-demo 'no sentence about the online demo mentions Telegram, and the other mentions say your own install' chk_telegram_demo
}

rule_readme_links() {
  rule_begin readme-links "$README" || return
  st_append 'a link to a heading that is not there' '[x](#nowhere)' chk_readme_links
  st_append 'a link to a file that is not there' '[x](docs/missing.md)' chk_readme_links
  st_append 'a link to a folder that is not there' '[x](missing-folder/)' chk_readme_links
  st_append 'a link to a host off the list' '[x](https://example.org/a)' chk_readme_links
  st_append 'a bare address off the list' 'See http://example.org/a for more.' chk_readme_links
  st_append 'a repository path off the list' '[x](https://github.com/someone-else/OcuTalon)' chk_readme_links
  st_append 'a host that only starts with an allowed host' '[x](https://claude.com.example.org/a)' chk_readme_links
  st_append 'a host that only ends with an allowed host' '[x](https://notclaude.com/a)' chk_readme_links
  st_append 'an allowed host in front of an at sign' '[x](https://claude.com@example.org/a)' chk_readme_links
  st_append 'an allowed host and a colon in front of an at sign' '[x](https://claude.com:x@example.org/a)' chk_readme_links
  st_append 'the allowed repository left by dot segments' '[x](https://github.com/jbrandtmse/OcuTalon/../../someone-else/repo)' chk_readme_links
  st_append 'a repository that only starts with the allowed one' '[x](https://github.com/jbrandtmse/OcuTalon-fork)' chk_readme_links
  st_append 'a link that is not http' '[x](mailto:a@b.c)' chk_readme_links
  st_append 'two headings with one slug' '## Sign in' chk_readme_links
  # A link by the GitHub slug of a heading (Design Note 8) is not flagged: the arrow, the apostrophe and the parentheses are dropped,
  # the spaces around the arrow stay (two hyphens), and a hyphen of the heading stays. The copy gets its own heading with the arrow.
  awk -v arrow="$ARROW" '{ print } END { print ""; print "## Contest task " arrow " where to see it"; print "[a](#contest-task--where-to-see-it) [b](#whats-interesting) [c](#stop-start-and-update) [d](#the-iris-non-health-image)" }' "$README" > "$tmp/slug.md"
  if [ -n "$(chk_readme_links "$tmp/slug.md")" ]; then st_note 'a link by the GitHub slug of a heading is flagged'; fi
  finish readme-links 'every link reaches a heading, a file or folder of the repository, or an allow-listed host' chk_readme_links
}

rule_must_scan() {
  rule_begin must-scan "$boundaries_p" || return
  st 'README.md gone from test-boundaries.sh' 1 "$boundaries_p" '{ gsub(/README\.md/, "ZZ.md"); print }' chk_must_scan
  st 'the list for paths and keys gone from test-boundaries.sh' 1 "$boundaries_p" '{ gsub(/not scanned for paths and keys/, "not scanned"); print }' chk_must_scan
  # README.md as the last entry of the list, before "; do", is found.
  printf 'for f in A.md \\\n  B.md README.md; do\n  echo "  not scanned for paths and keys: $f"\ndone\n' > "$tmp/ms.sh"
  if [ -n "$(chk_must_scan "$tmp/ms.sh")" ]; then st_note 'README.md as the last entry of the list is not found'; fi
  finish must-scan "the must-scan list for paths and keys in $BOUNDARIES names $README" chk_must_scan
}

RULES='top try_it interesting use_cases how_you_talk teaser images outcomes install install_pointer commands key_account lan sign_in_address demo_mode admin_commands after_start_log dev_only public_text telegram_section telegram_strings telegram_facts telegram_demo no_telegram product_links readme_links must_scan'

# unlisted <rule names>: each rule_* function of this script but rule_begin that the list does not name, one per line.
unlisted() {
  declare -F | sed -n 's/^declare -f rule_//p' | while IFS= read -r r; do
    case " $1 " in *" $r "*) ;; *) if [ "$r" != begin ]; then echo "$r"; fi ;; esac
  done
}

# Every rule the script defines runs: a rule_* function missing from RULES never runs, so CI would not see it. The check first
# proves it flags a list without its last rule.
if [ -z "$(unlisted "${RULES% *}")" ]; then
  echo "FAIL rules: a rule left out of RULES is not found"
  fails=$((fails + 1))
fi
for r in $(unlisted "$RULES"); do
  echo "FAIL rules: rule_$r is not in RULES"
  fails=$((fails + 1))
done

# With no README.md every rule fails closed: each one, run as if the file were absent, must print a FAIL line that says so.
for r in $RULES; do
  out=$(have_readme=0; "rule_$r")
  case $out in
    FAIL*"$README is missing"*) ;;
    *)
      echo "FAIL no-readme: rule $r does not fail when $README is missing"
      fails=$((fails + 1))
      ;;
  esac
done

for r in $RULES; do "rule_$r"; done

if [ "$fails" -ne 0 ]; then
  echo "test-readme: $fails rule(s) failed"
  exit 1
fi
echo "test-readme: all rules passed"
