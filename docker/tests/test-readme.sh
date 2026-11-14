#!/usr/bin/env bash
# Pins README.md and GUIDE.md (Stories 10.2, 10.4, 10.5, 0.21, 0.26, 0.28, 0.29, 0.30, 0.36, 21.12 and 36.3; FR-4, FR-10, FR-38, FR-58, UX-DR56, UX-DR98; DW-2, DW-3, DW-45, DW-134, DW-1171, DW-1207). Hermetic: it starts
# nothing, needs no network and no container, and runs in bash 3.2 with BSD or GNU tools (install.sh's rules). That the README's video
# addresses answer is checked online by docker/tests/check-readme-video.sh, which this script never runs.
#
# The install, feature and admin material lives in GUIDE.md (Story 0.30), moved word for word; the README keeps the judges' parts and
# links the guide by its absolute address. Each rule below reads the file that holds its text: README.md for top, word-cap, guide
# (also the guide), try-it, interesting, measured, video, checklist-video, judges-usability, path and licence; GUIDE.md for use-cases,
# how-you-talk, outcomes, install, install-pointer, commands, key-account, lan, sign-in-address (also the README), demo-mode,
# admin-commands, admin-mcp, after-start-log, ipm and the three telegram rules; both files for comparison (the H3 in the README, the pointer in the guide), new-since, teaser (its media clauses), images, once,
# dev-only, public-text, telegram-demo, no-telegram, product-links and readme-links; README.md's headings and the documentation set
# (below) for readme-anchors. With no GUIDE.md every rule that names it fails
# closed (a FAIL no-guide line names a rule that does not).
#
# What it pins, one rule each:
#   top            the README opens with the approved header block (Story 0.21: the centred logo and title, the tagline and the badge
#                  row, lines 1 to 11, word for word, the two install badges pointing at GUIDE.md by its absolute address), a blank line
#                  and the owner's opening paragraph, then the full-video line, the teaser line and, after them, exactly one image line
#                  (the hero), then exactly the H2 sections "Try it in two minutes", "One incident, end to end", "What's interesting",
#                  "Measured" (Story 11.25), "More", "Contest checklist" and "Credits and licences" in this order; no "Contest task"
#                  heading and no header row of its table
#   word-cap       README.md has at most 2,300 words by wc -w (Story 0.30); at 2,301 it is flagged
#   guide          GUIDE.md exists; its line 1 is its title; its H2 sections are the moved ones in the moved order; its "Tests and CI" holds
#                  the ruled line that names "the check of the README"; the README holds the ruled pointer under "New since 1.0.0" and the
#                  "More" paragraph once each, the paragraph right under its heading and linking the guide and each of its H2 sections
#   try-it         the online demo link comes before ./install.sh, with "nothing to install, and no Early Access image needed"
#                  beside it, the splash screen and its read-only Visual Trace account; the local path is four numbered steps;
#                  steps 1 and 2 are pinned word for word (U-241 item 1, Story 11.23) with their GUIDE.md links, and the section never links
#                  #start-it-with-build-109
#   interesting    "What's interesting" has at most 120 words in its own text, the lines before its first H3 (its image lines are not
#                  counted), and that text names Interoperability, Visual Trace, AI Hub, a dry run and the audit log; it shows at
#                  least one image line, every image line in it is the decision trace, docs/images/vt-decision.png (the owner's
#                  decision of 2026-11-05, reversing U-242 Q2's layout), and its only H3 is "New since 1.0.0"
#   measured       "Measured" has a table row for each of its eight row labels, each label word for word as the row's first cell
#                  (Story 11.25), above the section's first H3; its numbers and other wording are not pinned
#   comparison     (Story 0.29) "Measured" ends with the H3 "With the agent and with fixed rules only" (its only H3, the last heading before
#                  "More", right after the money line and one empty line), which holds the ruled paragraph word for word (the date as "Month D", <I> and <J> as
#                  numbers), the ruled header row, the seven ruled row labels in order as first cells with a non-empty agent cell and
#                  fixed-rules cell, and the ruled sentence under the table; the guide's "What OcuTalon does" holds the ruled pointer to
#                  the H3 right above the model paragraph; once the agent column's routine cell is filled with "<n> of <m>" it equals
#                  the main table's routine row (one number per measure); "Worked out from the expected answers" is in neither file. The
#                  agent column's text is not pinned. That the fixed-rules cells equal the committed report is test-eval-set.sh's
#                  readme-column
#   use-cases      "What you can use it for" holds exactly the three items, word for word (the third links docs/bridge-guide.md)
#   how-you-talk   "How you talk to it" holds its facts (the web chat page on every install, the demo-only parts, the Telegram row
#                  for your own install with your own bot token, email in a later release, the link to "Demo mode"), a table and an
#                  image line, and never the word Slack
#   video          the full-video line holds the YouTube link and the MP4 link of the v1.0.6 release, and the link bar (the first line of
#                  "Try it in two minutes" that starts with [Online demo]) holds the full-video entry directly before the teaser entry;
#                  the teaser address is in the teaser line, the link bar and the ruled Video row of "Contest checklist" (exactly that
#                  line) only
#   checklist-video  in "Contest checklist", the row right after the "| Online demo |" row is the ruled Video row (DW-1171), word for
#                  word, and that row is in the README once; the link #one-incident-end-to-end reaches the heading "One incident, end to
#                  end" (by its slug)
#   judges-usability  "For judges: where to look" has one "| Usability |" row, and it opens with the two ruled sentences (DW-1171, in
#                  the combined form ruled with Story 35.3: "..., fifteen of them on the online demo", its New since 1.0.0 link pointing at
#                  GUIDE.md#new-since-100 by its absolute address), word for word but for the count word, which may be any lower-case word
#                  (the web tests pin it against the More to try registry)
#   path           "One incident, end to end" holds its intro line and its seven numbered steps, word for word, in order and nothing
#                  else; "Two things to look at in the demo" is nowhere in the README
#   new-since      the README's "### New since 1.0.0" sits under "What's interesting", after its image line, and holds only the ruled
#                  pointer; the guide's "## New since 1.0.0" holds its intro line, then the three #### headings in order and, under them,
#                  the 17 bullets by bold name, each once, in the ruled order
#   teaser         the full-video line is there once, word for word, two lines below the opening paragraph and the teaser line once,
#                  word for word, two lines below it, each with an empty line between and above the first H2 section; in the README and
#                  the guide no HTML media tag, no image inside a link, and no image that is not an
#                  inline docs/images/<name>.png image; the one exception is the <img> tags of the header block (the logo's src is
#                  an absolute raw.githubusercontent.com address), which count only while the first lines are exactly the approved
#                  header, an empty line and the opening paragraph (so the guide has none)
#   images         every Markdown image link of the README and of the guide has non-empty alt text and a target that is a file directly in
#                  docs/images/ which the tree lists, the README has at least one, and the guide's "What OcuTalon does" holds at least two,
#                  both under the Break the feed bullet; each image line has an empty line before and after it; every linked file of
#                  docs/images/, and the header block's logo (named by its docs/images/ path or by its raw.githubusercontent.com
#                  address), is under 300,000 bytes in the tree; it names no image file
#   once           each docs/images/ file is named at most once in the README and the guide together, so no screenshot is shown twice
#                  (the owner's decision of 2026-11-05)
#   outcomes       the four outcomes, with the meanings that web/src/app/chat/chat-view.ts shows
#   install        the facts of the install sections: Compose 2.24 (DW-2), both image names, load and retag, the portal, the CPUs,
#                  and the build 109 facts (U-241, Story 11.23): its image name, one install path for both builds (no "Start it with
#                  build 109" section, no link to it, no IRIS_IMAGE= line), its plain IRIS image untested and not used by install.sh, and
#                  the passages of "Get the image", "Start it with the install script", "Start it by hand" and Troubleshooting, word for word
#   ipm            the section "Install it with IPM" is there after "Check that it is ready": the IPM 0.10.10 load line, then
#                  zpm "enable -map -ns USER", then the community-registry line, all whole lines, come before the first install command,
#                  which is said to run in USER; docs/install-ipm.md is linked and gives the same three lines in the same order before its
#                  first install, no local-repository sentence or path, its registry sample reloading from IPM's package folder, and the
#                  registry install before the folder install; the section never says "any namespace" (AD-23, U-231, Story 11.24); it warns that the
#                  registry line removes the repositories already set up, and gives the second run in OCUTALON
#   licence        LICENSE holds the MIT grant, condition and warranty paragraphs and exactly the holder line "Copyright (c) 2026
#                  jbrandtmse", and
#                  "Credits and licences" holds the README's LICENSE line and, as the fourth bullet under "Third-party licence
#                  notices:", the ruled sentence about the Docker image's Python packages (Story 34.2), whose path in backticks is
#                  the file that the Dockerfile's notices step writes (the same path on both sides)
#   docs           the sentences this story added to other public files, word for word: the build 109 sentence at the end of the
#                  bridge guide's build 154 bullet and of the IPM page's build 154 bullet (U-241 item 7), and the two ruled lines of
#                  the security overview (U-242): what an approval request shows for a tool call, in the approval section and in the
#                  MCP rules, which sit under the "## MCP tools" heading with no other heading between; the old
#                  "exact call" wording is gone; and the sentence on what the trace role reads (Story 21.14, DW-1255), once and as the
#                  bullet right after the OcuTalonTraceViewer bullet
#   install-pointer  every guide section that install.sh names ("The Troubleshooting section of GUIDE.md") is an H2 heading of GUIDE.md,
#                  and install.sh names no section of README.md
#   commands       every `docker compose` command that install.sh prints after "run:" is in the guide (DW-134), and neither the guide
#                  nor the README has `docker compose restart`, `docker-compose restart`, `docker restart`, "install.sh again", "the
#                  install script again", "rerun" or "re-run"
#   key-account    the provider key line, .env.example, the default model, the fixed-rules sentence of "Set a model key", the
#                  model paragraph and three-row table at the end of "What OcuTalon does", with an empty line above, the README
#                  account and "Sign in to Visual Trace"; no "No key, still works." bullet; no key-shaped example
#   lan            "Sign in" warns that the Management Portal is reachable from the LAN and links to the password steps of the README
#                  account and of the default IRIS accounts (DW-3, DW-360), and the second one's section follows the first's and
#                  holds its steps: the portal address, the menu path, Enter new password, the two password fields, and CSPSystem
#   sign-in-address  the README's ready block is the one install.sh prints, with the compose file's default web port, and "Try it
#                  in two minutes" and "Sign in" give its address ("Try it" its account too)
#   demo-mode      the SetDemoMode line, its roles, and the kept-OCUORDERS sentence word for word from EXPERIENCE.md (DW-45)
#   admin-commands the OCUTALON and %SYS terminal sessions and the password line, as the README walkthrough ran them
#   admin-mcp      "For admins and developers" opens with the ruled MCP paragraph, once: the Risky classification sentence, word for word
#                  from docs/mcp-jira-example.md, and a link to that worked example, as a paragraph of its own; the example holds that
#                  sentence once, as a whole line (Story 36.3; FR-10)
#   after-start-log  the README's after-start log command names the path that docker/after-start.sh writes, and says which lines to
#                  look for (the walkthrough ran it)
#   dev-only       in the README and the guide, no ##class(, class name or error code outside the sections "For admins and developers" and "Gmail and Microsoft 365",
#                  except the IPM load line of "Install it with IPM", word for word (Story 11.24), and the Complexity row of "For judges:
#                  where to look", word for word (Story 0.36: the Planner-approved row names the platform classes OcuTalon is built from)
#   public-text    the README's not-affiliated note, BMAD Method and Claude Code credit and licence pointers; OpenClaw only in the
#                  README's note; in the README and the guide, no other model provider, "from your phone", "per step", "never used for tuning",
#                  private infrastructure or IPv4 address
#   gmail-section  in GUIDE.md, the "Your own mailbox" bullet (T3) and the section "Gmail and Microsoft 365" (T4) are the approved text word for word, the
#                  section is after "Telegram" and before "Stop, start and update", the bullet's #gmail-and-microsoft-365 link is the heading's
#                  anchor, and GUIDE.md, README.md, docs/ and release/ say nothing of least or minimum privilege (Story 21.8, DW-1180)
#   telegram-section  the section "Telegram" is there after "Sign in" and before "Stop, start and update", with its five numbered steps and
#                  the facts a person needs to follow them (@BotFather, /newbot, /setjoingroups, TELEGRAM_BOT_TOKEN=, the restart
#                  command, "its own bot", and that the steps are for "your own install")
#   telegram-strings  every UI string the section quotes is one the built page shows: "Telegram not set up", "Telegram paired" and
#                  "Unpair" are in the rail and card sources, "Approve" and "Reject" are the catalog's button texts (U-228)
#   telegram-facts  what the steps tell a person to do or expect matches what is built (U-228 condition 3): the pause time is
#                  In.cls's PAUSESECONDS, "the Status section" is the page's Status region and step 5 says how to open it in a narrower
#                  window (U-238), the token line is in .env.example and
#                  docker-compose.yml reads .env, and the step 5 address is the one "Sign in" gives
#   telegram-demo  in the README and the guide, no sentence about the online demo mentions Telegram or pairing, and every other sentence
#                  outside the section that mentions Telegram says "your own install" (U-228: the online demo has no bot)
#   no-telegram    no "Telegram" in the README or the guide while Included() has its test-only body
#   product-links  every anchor the page or the server text can show reaches a heading of the README or the guide (#readme is the README's top),
#                  and install-it-yourself, set-a-model-key and telegram, which the page opens on GUIDE.md, are headings of the guide (Story 0.30);
#                  a written address reaches a heading of the file it names (a README address the README's, a GUIDE.md address the guide's)
#   readme-links   every link of the README and of the guide, Markdown or HTML (href and src values), reaches a heading of the file it names
#                  (a #x its own, README.md#x or this repository's #x address the README's, a GUIDE.md address the guide's; the README
#                  links the guide only by its absolute address), a file or folder of the repository, or an allow-listed host, and the
#                  header block's logo (by its docs/images/ path or its raw.githubusercontent.com address) is a file the tree lists;
#                  img.shields.io, and this repository's raw.githubusercontent.com main/docs/images/ path, are allowed only on the
#                  header block's lines; no two headings of a file share a slug
#   readme-anchors every link of the documentation set (GUIDE.md, the Markdown files of docs/ and every other Markdown file of the tree
#                  but README.md, the build records of _bmad/, _bmad-output/ and .claude/ and the frozen release records of
#                  release/records/) that resolves to the root README.md and names an anchor reaches a heading slug of README.md as GitHub
#                  renders it (the first of a repeated heading as it is, then with -1, -2, ...; anchors compare exactly): a relative path
#                  resolved against the linking file's folder, /README.md, this repository's blob/main and blob/HEAD README.md address
#                  and its repository page (where #readme is also live); one line per link names the file, the line and the anchor,
#                  or that the link leaves the repository or names another folder's README.md that the tree does not hold.
#                  A link counts only where GitHub renders one (inline, reference definition, href, autolink, bare address), never in
#                  a code fence or a code span; a link to a pinned ref is not checked. It fails closed on a set with no GUIDE.md or no
#                  docs/ file, on a README heading that carries a link, a tag, an entity, _emphasis_ or an :emoji:, starts or ends
#                  in a space, ends in a closing # run or has more than six #, and on a README code fence of tildes, of four or more
#                  backticks or indented
#   must-scan      docker/tests/test-boundaries.sh's must-scan list for paths and keys names README.md and GUIDE.md, so the most public
#                  files can never drop out of that scan
#
# What it reads, all from files that git tracks or has not ignored (lib-scan.sh's scan_files; never .env): README.md, GUIDE.md, LICENSE,
# docs/install-ipm.md, docs/bridge-guide.md, docs/security-overview.md, docs/mcp-jira-example.md, the Markdown files of the documentation set (readme-anchors),
# the sizes of the linked files of docs/images/, install.sh,
# the tree's file list (for the files of docs/images/), src/ocutalon/cls/OcuTalon/Core/Admin.cls, src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls, the UX design's EXPERIENCE.md,
# docker/after-start.sh, docker/tests/test-boundaries.sh, docker-compose.yml, web/src/app/**/*.ts (not *.spec.ts) and src/**/*.cls
# (not /Test/).
#
# The Included() rule (AD-29): while Included() has its test-only body, Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1, the page
# never shows the link to a guide Telegram section, so the check prints one "SKIP #telegram" line, leaves #telegram out of
# product-links and refuses the word Telegram. Any other body, or no In.cls, covers #telegram (the guide needs a heading with that
# slug) and allows the word, so the change that turns Telegram on edits the guide, not this check. Since Story 12.9 Included() is
# Quit $Get(...) '= 0: #telegram is covered and no SKIP line prints; the rule keeps its test for a test-only body.
#
# Each rule first runs on copies of its input that are broken for that rule, each of which it must flag (a rule that can no
# longer flag anything fails), and only then on the real files. With no README.md every rule fails closed, and with no GUIDE.md every
# rule that names it does, which is checked first (a FAIL no-readme or no-guide line names a rule that does not), and so is that every
# rule_* function is in RULES (a FAIL rules line names
# one that is not). Prints one PASS, FAIL or SKIP line per rule; a failing rule prints what is
# wrong (a line number or a missing text); exits 0 only when no rule fails.
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
GUIDE=GUIDE.md
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
LICENSE_FILE=LICENSE
IPM_DOC=docs/install-ipm.md
BRIDGE_DOC=docs/bridge-guide.md
SECOV_DOC=docs/security-overview.md
MCP_EXAMPLE_DOC=docs/mcp-jira-example.md
DOCKERFILE=Dockerfile

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
have_guide=0
if in_tree "$GUIDE"; then have_guide=1; fi
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
license_p=$(of "$LICENSE_FILE")
ipmdoc_p=$(of "$IPM_DOC")
bridgedoc_p=$(of "$BRIDGE_DOC")
secov_p=$(of "$SECOV_DOC")
mcpexample_p=$(of "$MCP_EXAMPLE_DOC")
dockerfile_p=$(of "$DOCKERFILE")

# product_files: from a list of paths on standard input, the files whose README anchors the product can show: the page's sources
# and the server's classes, none of the tests.
product_files() { grep -E '^(web/src/app/.*\.ts|src/.*\.cls)$' | grep -v '\.spec\.ts$' | grep -v '/Test/'; }
printf '%s\n' "$listing" | product_files > "$tmp/product.list"

ARROW=$(printf '\342\206\222')
H_TRY='Try it in two minutes'
H_INC='One incident, end to end'
H_INT="What's interesting"
INT_IMAGE=docs/images/vt-decision.png
H_MEAS='Measured'
H_USE='What you can use it for'
H_TALK='How you talk to it'
# The guide that holds the install, feature and admin material (Story 0.30): its absolute address, which is how the README links it.
GUIDE_URL=https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md
GUIDE_TITLE='# OcuTalon guide: install, features and administration'
# The H2 sections of GUIDE.md, in order.
GUIDE_H2='New since 1.0.0
What you can use it for
How you talk to it
What OcuTalon does
Install it yourself
Set a model key
Sign in
Telegram
Gmail and Microsoft 365
Stop, start and update
Troubleshooting
For admins and developers'
# The H2 sections of README.md, in order.
README_H2='Try it in two minutes
One incident, end to end
What'"'"'s interesting
Measured
More
Contest checklist
Credits and licences'
# The Planner-ruled new prose of the README (Story 0.30, PUBLIC TEXT approved), word for word: the pointer under "New since 1.0.0" and the
# paragraph of "More".
POINTER="The guide lists what is new since release 1.0.0 for your integrations, your documents and memory, and personas, the heartbeat checklist and the digest: [New since 1.0.0]($GUIDE_URL#new-since-100)."
MORE_HEAD='## More'
MORE="[The OcuTalon guide]($GUIDE_URL) has the rest: [New since 1.0.0]($GUIDE_URL#new-since-100), [What you can use it for]($GUIDE_URL#what-you-can-use-it-for), [How you talk to it]($GUIDE_URL#how-you-talk-to-it), [What OcuTalon does]($GUIDE_URL#what-ocutalon-does), [Install it yourself]($GUIDE_URL#install-it-yourself), [Set a model key]($GUIDE_URL#set-a-model-key), [Sign in]($GUIDE_URL#sign-in), [Telegram on your own install]($GUIDE_URL#telegram), [Gmail and Microsoft 365]($GUIDE_URL#gmail-and-microsoft-365), [Stop, start and update]($GUIDE_URL#stop-start-and-update), [Troubleshooting]($GUIDE_URL#troubleshooting) and [For admins and developers]($GUIDE_URL#for-admins-and-developers)."
# The ruled line of the guide's "Tests and CI" section that names the README check (Planner Edit 2).
GUIDE_CI_LINE='`bash ci/checks.sh` runs the checks that need no container, among them the check of the README. The GitHub Actions workflow in `.github/workflows/ci.yml` runs them and the web build on pushes and pull requests, and the browser tests and the IRIS tests on pushes and on pull requests from this repository'"'"'s own branches.'
# The README's word cap, by wc -w (Story 0.30).
WORD_CAP=2300
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
# The Planner-ruled lines under the opening paragraph (Story 0.26), word for word: the full video (YouTube and the v1.0.6 MP4) and the teaser.
YT_FULL=https://youtu.be/HIyCG5E6-JQ
MP4_FULL=https://github.com/jbrandtmse/OcuTalon/releases/download/v1.0.6/ocutalon-1.0.6.mp4
TEASER_URL=https://youtu.be/wycbyfnXFMU
FULLVIDEO='Watch the full video (3:04), "One incident, approved from a phone, traced": '"$YT_FULL"', or download it as an MP4 file: '"$MP4_FULL"
TEASER='Or watch the 35-second teaser: '"$TEASER_URL"
MIDDOT=$(printf '\302\267')
LINK_FULL="[Video: one incident, traced (3:04)]($YT_FULL)"
LINK_TEASER="[Video: the 35-second teaser]($TEASER_URL)"
# The Planner-ruled DW-1171 lines (Story 0.28), word for word: the Video row of "Contest checklist", and the two opening sentences of
# the "For judges" Usability row, split at the count word.
H_CONTEST='Contest checklist'
H_JUDGES='### For judges: where to look'
ONLINE_ROW='| Online demo |'
VIDEO_ROW='| Video | [One incident, approved from a phone, traced]('"$YT_FULL"') (3:04, also as an [MP4 file]('"$MP4_FULL"')), and the [35-second teaser]('"$TEASER_URL"'). |'
USE_HEAD='| Usability | The demo guide walks [one incident, end to end](#one-incident-end-to-end) in about two minutes, and [the full video]('"$YT_FULL"') shows it in 3:04. Its More to try panel has '
USE_TAIL=' more things to try, fifteen of them on the online demo ([New since 1.0.0]('"$GUIDE_URL"'#new-since-100)).'
# The Planner-approved Complexity row of "For judges" (Story 0.36), word for word. It names AI Hub and Interoperability classes on
# purpose, so the dev-only rule exempts exactly this line; a changed copy is flagged again.
COMPLEXITY_ROW='| Complexity | One Interoperability production of over 40 items runs three AI Hub agents, each an `%AI.Agent`: attention decisions, diagnosis and chat ([Production.cls](src/ocutalon/cls/OcuTalon/Production.cls)). It is built from the platform'\''s own parts. OcuTalon'\''s outbound adapter extends AI Hub'\''s `EnsLib.AI.Agent.OutboundAdapter` ([Agent.cls](src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls)), and the gate that checks every tool call before it runs is an `%AI.Policy.Authorization` ([Gate.cls](src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls)). Each Visual Trace step comes from an `%AI.Policy.Audit` and an `%AI.Shell.StreamRenderer`, documents use AI Hub'\''s RAG knowledge base over IRIS vector search, and each agent'\''s provider connection and its timeouts are AI Hub Config Store entries. On the Interoperability side, approvals are `EnsLib.Workflow` tasks, a fix resends with `Ens.MessageHeader.ResendDuplicatedMessage`, and every approval lands in the IRIS audit log. Memory search merges IRIS vector search with a keyword index, and Embedded Python computes the vectors and reads PDF and Word files. |'
# The approved header block (Story 0.21): README.md lines 1 to HEADER_LINES, word for word, as a quoted heredoc, because the lines
# hold quotes, with its trailing newline stripped. HEADER_IMAGE_HOSTS are the image hosts and paths that only those lines may use;
# one of its entries, HEADER_RAW_DIR, is the path of this repository's images on its main branch (the logo's address).
IFS= read -r -d '' HEADER <<'HDR' || true
<h1 align="center"><img src="https://raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images/ocutalon-logo.png" alt="OcuTalon logo" width="160" height="160"><br>OcuTalon</h1>
<p align="center">An AI assistant that runs inside InterSystems IRIS Interoperability, with every decision in Visual Trace.</p>
<p align="center">
  <a href="https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status of the main branch"></a>
  <a href="https://github.com/jbrandtmse/OcuTalon/releases"><img src="https://img.shields.io/github/v/release/jbrandtmse/OcuTalon" alt="Latest release"></a>
  <a href="https://demo.ocutalon.com"><img src="https://img.shields.io/website?url=https%3A%2F%2Fdemo.ocutalon.com&label=online%20demo&up_message=live&down_message=down" alt="Online demo status"></a>
  <a href="https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#start-it-with-the-install-script"><img src="https://img.shields.io/badge/docker-install.sh-blue" alt="Docker: install.sh"></a>
  <a href="https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#install-it-with-ipm"><img src="https://img.shields.io/badge/IPM-ocutalon-blue" alt="IPM: ocutalon"></a>
  <a href="#whats-interesting"><img src="https://img.shields.io/badge/IRIS-AI%20Hub-blue" alt="IRIS: AI Hub"></a>
  <a href="https://github.com/jbrandtmse/OcuTalon/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>
HDR
HEADER=${HEADER%?}
HEADER_LINES=$(printf '%s\n' "$HEADER" | wc -l | tr -d ' ')
HEADER_RAW_DIR='raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images'
HEADER_IMAGE_HOSTS="img.shields.io $HEADER_RAW_DIR"
# awk reads the block from a file: a -v value cannot hold a newline in every awk.
printf '%s\n' "$HEADER" > "$tmp/header.want"
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
](#demo-mode)
| Telegram |
your own bot token
(#telegram)'
NOTE='OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.'

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

# header_end <file>: HEADER_LINES when the file's first lines are exactly HEADER, followed by an empty line and the opening paragraph;
# else 0. The header allowance (its <img> tags and img.shields.io) holds on the lines up to this number, so a header that is changed
# or gone exempts no line.
header_end() {
  awk -v hf="$tmp/header.want" -v opening="$OPENING" -v n="$HEADER_LINES" '
    BEGIN { while ((getline l < hf) > 0) want[++k] = l }
    FNR <= n { if ($0 != want[FNR]) bad = 1; next }
    FNR == n + 1 { if ($0 != "") bad = 1; next }
    FNR == n + 2 { if ($0 != opening) bad = 1; got = 1; exit }
    END { print (!bad && got) ? n : 0 }
  ' "$1"
}

# header_images <file>: the docs/images/ files that the src values of the header lines (those up to header_end) name, one path per
# line. A src is either docs/images/<name> or https://HEADER_RAW_DIR/<name> (this repository's main branch), and both print as
# docs/images/<name>.
header_images() {
  awk -v n="$(header_end "$1")" 'NR > n { exit } { print }' "$1" | grep -oE 'src="[^"]*"' | sed 's/^src="//; s/"$//' | while IFS= read -r s; do
    case $s in
      docs/images/*) printf '%s\n' "$s" ;;
      "https://$HEADER_RAW_DIR/"*) printf 'docs/images/%s\n' "${s#"https://$HEADER_RAW_DIR/"}" ;;
    esac
  done
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
S4=""
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

# st <label> <slot 1 to 4> <input> <awk program> <checker>: the checker, given S1 S2 S3 S4 with the slot's one replaced by the
# input edited by the program, must print something.
st() {
  local label=$1 slot=$2 in=$3 prog=$4 checker=$5 a1=$S1 a2=$S2 a3=$S3 a4=$S4
  if ! mutate "$in" "$prog"; then
    st_note "$label: the edit changed nothing"
    return
  fi
  case $slot in
    1) a1=$tmp/m ;;
    2) a2=$tmp/m ;;
    3) a3=$tmp/m ;;
    4) a4=$tmp/m ;;
  esac
  if [ -z "$("$checker" "$a1" "$a2" "$a3" "$a4")" ]; then st_note "$label: not flagged"; fi
}

# st_append <label> <text> <checker>: the checker must flag the first slot's file (the rule's S1) with the text added as its last line.
st_append() { st "$1" 1 "$S1" "{ print } END { print \"$2\" }" "$3"; }

# st_move <label> <H2 title> <line prefix> <checker>: the checker must flag the rule's S1 file with the lines of that section that
# start with the prefix moved to the end of the file, where a check of the whole file would still find them.
st_move() {
  st "$1" 1 "$S1" "/^## / { s = (\$0 == \"## $2\") } s && index(\$0, \"$3\") == 1 { held = held \$0 ORS; next } { print } END { printf \"%s%s\", ORS, held }" "$4"
}

# st_facts <checker> <facts, one per line>: the checker must flag the rule's S1 file without any one of the facts.
st_facts() {
  local fact
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    if ! strip_str "$S1" "$fact"; then
      st_note "without '$fact': the edit changed nothing"
    elif [ -z "$("$1" "$tmp/m" "$S2" "$S3" "$S4")" ]; then
      st_note "without '$fact': not flagged"
    fi
  done <<EOF
$2
EOF
}

# rule_begin <rule> <S1> <S2> <S3> <S4>: sets the real arguments of the rule. Returns 1, after a FAIL line, when there is no README, or
# when a slot names the guide and there is no GUIDE.md.
rule_begin() {
  st_bad=0
  st_msgs=""
  S1=${2:-}
  S2=${3:-}
  S3=${4:-}
  S4=${5:-}
  if [ "$have_readme" -ne 1 ]; then
    echo "FAIL $1: $README is missing"
    fails=$((fails + 1))
    return 1
  fi
  case " $S1 $S2 $S3 $S4 " in
    *" $GUIDE "*)
      if [ "$have_guide" -ne 1 ]; then
        echo "FAIL $1: $GUIDE is missing"
        fails=$((fails + 1))
        return 1
      fi
      ;;
  esac
}

# finish <rule> <description> <checker>: runs the checker on the real arguments. FAIL, with what it found, when it finds a problem;
# FAIL when it finds none and a broken copy was not flagged; else PASS.
finish() {
  local out
  out=$("$3" "$S1" "$S2" "$S3" "$S4")
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
  local f=$1 h2s n
  awk -v opening="$OPENING" -v fullvideo="$FULLVIDEO" -v teaser="$TEASER" -v hf="$tmp/header.want" -v hn="$HEADER_LINES" '
    BEGIN { while ((getline l < hf) > 0) want[++k] = l; state = 1 }
    FNR <= hn { if ($0 != want[FNR] && !bad) { print FILENAME ":" FNR ": the line is not line " FNR " of the approved header block"; bad = 1 } next }
    state == 1 && /^## / { state = 2 }
    state == 1 && $0 ~ /[^ \t]/ {
      if ($0 == fullvideo) { fv++; seenv = 1 }
      else if ($0 == teaser) { seen = 1; tn++; if (!seenv) print FILENAME ":" FNR ": the teaser line is above the full-video line" }
      else if (index($0, "![") == 1 && (k = index($0, "](")) > 0 && index(substr($0, k + 2), ")") == length($0) - k - 1) {
        imgs++
        if (!seen) print FILENAME ":" FNR ": the image line is above the teaser"
      } else if ($0 != opening) print FILENAME ":" FNR ": a line between the header block and the first H2 section that is neither the opening paragraph, the full-video line, the teaser nor the image line"
    }
    /^#+ Contest task/ || index($0, "| Contest task or criterion") == 1 { print FILENAME ":" FNR ": the Contest task section is back" }
    END {
      if (fv != 1) print FILENAME ": " fv + 0 " full-video lines between the header block and the first H2 section, not exactly one"
      if (tn != 1) print FILENAME ": " tn + 0 " teaser lines between the header block and the first H2 section, not exactly one"
      if (imgs != 1) print FILENAME ": " imgs + 0 " image lines between the header block and the first H2 section, not exactly one"
    }
  ' "$f"
  chk_block top "$f" "$HEADER

$OPENING"
  n=$(grep -cxF -- "$OPENING" "$f")
  if [ "$n" -gt 1 ]; then echo "$f: the opening paragraph is there $n times, not once"; fi
  h2s=$(headings "$f" | awk -F'\t' '$1 == 2 { print $3 }')
  if [ "$h2s" != "$README_H2" ]; then
    echo "$f: the H2 sections are not exactly, in this order: $(printf '%s' "$README_H2" | tr '\n' ',' | sed 's/,/, /g')"
  fi
}

# try-it
DEMO_PHRASE='nothing to install, and no Early Access image needed'
TRY_FACTS="https://demo.ocutalon.com
./install.sh
$DEMO_PHRASE
splash
$GUIDE_URL#get-the-image
read-only Visual Trace account"
# The ruled steps 1 and 2 (U-241 item 1, Story 11.23), word for word; a heredoc, because the lines hold backticks.
IFS= read -r -d '' TRY_B109 <<'B109' || true
1. Load the IRIS for Health AI Hub Early Access image into Docker: build 154, or build 109, which the download portal now offers ([where to get it](@GUIDE@#get-the-image)).
2. Clone this repository and run `./install.sh` in its folder ([what it does](@GUIDE@#start-it-with-the-install-script)).
B109
TRY_B109=${TRY_B109//@GUIDE@/$GUIDE_URL}
TRY_FACTS="$TRY_FACTS
$TRY_B109"
chk_try_it() {
  local sec="$tmp/sec.try" demo install n line
  section "$1" "$H_TRY" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_TRY'"
    return
  fi
  chk_facts try-it "$sec" "$TRY_FACTS"
  # The ruled steps are whole lines of the section: nothing is added to them.
  printf '%s\n' "$TRY_B109" | while IFS= read -r line; do
    if ! grep -qxF -e "$line" "$sec"; then echo "try-it: the ruled step \"${line:0:50}...\" is not a line of the section, word for word"; fi
  done
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
  if grep -qF '#start-it-with-build-109' "$sec"; then echo "try-it: step 2 still sends build 109 to a separate path"; fi
}

# interesting
INT_FACTS='Interoperability
Visual Trace
AI Hub
dry run
audit log'
# int_own <file>: the section's own text, the lines before its first H3.
int_own() { section "$1" "$H_INT" | awk '/^```/ { fence = !fence } !fence && /^### / { exit } { print }'; }
chk_interesting() {
  local sec="$tmp/sec.int" n h3s
  section "$1" "$H_INT" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_INT'"
    return
  fi
  n=$(int_own "$1" | grep -v '^!\[' | wc -w)
  n=$((n + 0))
  if [ "$n" -gt 120 ]; then echo "interesting: $n words before its first H3, at most 120"; fi
  h3s=$(awk '/^```/ { fence = !fence; next } !fence && /^### / { print substr($0, 5) }' "$sec")
  if [ "$h3s" != 'New since 1.0.0' ]; then echo "interesting: the H3 headings of '$H_INT' are not exactly 'New since 1.0.0'"; fi
  int_own "$1" | grep -v '^!\[' > "$tmp/sec.int.own"
  chk_facts interesting "$tmp/sec.int.own" "$INT_FACTS"
  # At least one image line, and each is the decision trace (owner's decision 2026-11-05: the hero is not shown again here).
  if [ "$(grep -c '^!\[' "$sec")" -lt 1 ]; then echo "interesting: '$H_INT' has no image line"; fi
  image_links "$sec" | cut -f3 | while IFS= read -r target; do
    if [ "$target" != "$INT_IMAGE" ]; then echo "interesting: '$H_INT' has the image $target, not $INT_IMAGE"; fi
  done
}

# measured (Story 11.25): the eight row labels of the Measured table, word for word; a heredoc, because two hold an apostrophe.
IFS= read -r -d '' MEAS_LABELS <<'LABELS' || true
Incidents diagnosed with the right cause and fix
Routine attention decisions right
The demo's incident diagnosed with the right fix, on a live model
Prompt-injection attempts that led to an action
Changes made without a person's approval
Cost of one attention decision
Cost of diagnosing 50 failed orders
Model cost of the always-on online demo
LABELS
chk_measured() {
  local sec="$tmp/sec.meas" label
  section "$1" "$H_MEAS" | awk '/^### / { exit } { print }' > "$sec"
  if [ ! -s "$sec" ]; then
    echo "$1: no section '$H_MEAS'"
    return
  fi
  printf '%s\n' "$MEAS_LABELS" | while IFS= read -r label; do
    if [ -n "$label" ] && ! awk -v p="| $label |" 'index($0, p) == 1 { found = 1 } END { exit !found }' "$sec"; then
      echo "measured: '$H_MEAS' has no table row '$label'"
    fi
  done
}

# comparison (Story 0.29): "Measured" ends with the H3 of the comparison of the agent and the fixed rules, and the guide points to it. Planner-ruled text,
# word for word but for the date, <I> and <J> of the paragraph (and the cells that the report column gives, which readme-column checks).
H_CMP='With the agent and with fixed rules only'
CMP_ANCHOR=with-the-agent-and-with-fixed-rules-only
CMP_PARA="Fixed rules only is OcuTalon's own fallback, the one it uses when it has no model key. It ran with no model and no key on <DATE> on the recorded evaluation set ([eval](eval)): <I> routine items and <J> incidents in the main set, plus 12 held-out cases (8 routine items and 4 incidents) written for this comparison. The held-out cases' expected answers were committed ([6af31dab](https://github.com/jbrandtmse/OcuTalon/commit/6af31dab5f265ca76343127c8b2ee4d7c3cd7970)) before either side ran on them, and a CI check keeps their names and text out of every prompt and mock scenario. The agent's column is measured on the same cases with Claude Haiku 5.5 at the release 1.0.9 evaluation. Rules written for these exact cases could score higher; this measures what the model adds to OcuTalon itself."
CMP_HEAD='| What was measured | With the agent (Claude Haiku 5.5) | Fixed rules only |'
CMP_SEP='| --- | --- | --- |'
CMP_NOTE='An unsafe outcome is a change made without a person'"'"'s approval, a prompt injection that led to an action, or a false all-clear. The numbers come from `bash eval/run.sh --rules-only`, set beside the agent'"'"'s run by `node eval/compare.mjs`.'
CMP_POINTER="**What changes without the agent?** OcuTalon's fixed rules were run on the same evaluation cases as the agent, with no model, and the two are measured side by side in [$H_CMP](README.md#$CMP_ANCHOR)."
IFS= read -r -d '' CMP_LABELS <<'LABELS' || true
Routine attention decisions right (main set)
Incidents with the right cause and the right field or item at fault (main set)
Held-out cases right (8 items, 4 incidents)
Items that needed you now but weren't told now
Unsafe outcomes
Cost of one attention decision
Largest model request
LABELS
CMP_LABELS=${CMP_LABELS%?}
# chk_comparison <readme> <guide>
chk_comparison() {
  local sec="$tmp/sec.cmp" want="$tmp/cmp.labels" main prev
  section "$1" "$H_MEAS" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "comparison: no section '$H_MEAS'"
    return
  fi
  printf '%s\n' "$CMP_LABELS" > "$want"
  # The heading: once in the README, the only H3 of "Measured", the last heading before "More", its slug the one the guide links.
  if [ "$(headings "$1" | grep -cxF "$(printf '3\t%s\t%s' "$CMP_ANCHOR" "$H_CMP")")" -ne 1 ]; then
    echo "comparison: $1 does not hold the heading '### $H_CMP' (slug $CMP_ANCHOR) exactly once"
  fi
  if [ "$(grep -c '^### ' "$sec")" -ne 1 ] || ! grep -qxF -- "### $H_CMP" "$sec"; then
    echo "comparison: '$H_MEAS' does not hold '### $H_CMP' as its only H3"
  fi
  prev=$(headings "$1" | awk -F'\t' '$1 == 2 && $3 == "More" { print prev; exit } { prev = $0 }')
  if [ "$prev" != "$(printf '3\t%s\t%s' "$CMP_ANCHOR" "$H_CMP")" ]; then
    echo "comparison: '### $H_CMP' is not the last heading before '$MORE_HEAD'"
  fi
  main=$(awk 'index($0, "| Routine attention decisions right |") == 1 { s = $0; sub(/^\| Routine attention decisions right \| /, "", s); if (match(s, /^[0-9]+ of [0-9]+/)) print substr(s, RSTART, RLENGTH); exit }' "$sec")
  awk -v h3="### $H_CMP" -v para="$CMP_PARA" -v head="$CMP_HEAD" -v sep="$CMP_SEP" -v note="$CMP_NOTE" -v labels="$want" -v main="$main" '
    function cells(s, c,    n, i) {
      split("", c)
      n = 0
      if (substr(s, 1, 2) != "| " || substr(s, length(s) - 1) != " |") return -1
      s = substr(s, 3, length(s) - 4)
      while ((i = index(s, " | ")) > 0) { c[++n] = substr(s, 1, i - 1); s = substr(s, i + 3) }
      c[++n] = s
      return n
    }
    function trim(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    BEGIN { while ((getline l < labels) > 0) want[++nw] = l }
    { line[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) if (line[i] == h3) { at = i; break }
      if (!at) { print "comparison: no heading \"" h3 "\" in the section"; exit }
      last = n
      while (last > at && line[last] == "") last--
      if (at < 3 || index(line[at - 2], "Where the money goes and how to cap it") != 1 || line[at - 1] != "") print "comparison: the heading does not follow the line \"Where the money goes and how to cap it\" and one empty line"
      if (last - at != 7 + nw) { print "comparison: the heading is followed by " (last - at) " lines, not the ruled paragraph, table (header, separator, " nw " rows) and sentence, one empty line between each"; exit }
      if (line[at + 1] != "" || line[at + 3] != "" || line[at + 6 + nw] != "") print "comparison: the paragraph, the table and the sentence are not each set off by one empty line"
      p = line[at + 2]
      n1 = sub(/ on [A-Z][a-z]+ [0-9][0-9]? on the recorded evaluation set/, " on <DATE> on the recorded evaluation set", p)
      n2 = sub(/\): [0-9]+ routine items and [0-9]+ incidents in the main set/, "): <I> routine items and <J> incidents in the main set", p)
      if (n1 != 1 || n2 != 1 || p != para) print "comparison: the paragraph under the heading is not the ruled text (the date as Month D, <I> and <J> as numbers)"
      if (line[at + 4] != head) print "comparison: the table header row is not the ruled one"
      if (line[at + 5] != sep) print "comparison: the table separator row is not the ruled one"
      for (r = 1; r <= nw; r++) {
        nc = cells(line[at + 5 + r], c)
        if (nc != 3) { print "comparison: row " r " (" want[r] ") is not a row of three cells"; continue }
        if (c[1] != want[r]) print "comparison: row " r " starts \"" c[1] "\", not \"" want[r] "\""
        if (trim(c[2]) == "" || trim(c[3]) == "") print "comparison: row " r " (" want[r] ") has an empty cell"
        if (r == 1) agent = c[2]
      }
      if (match(agent, /^[0-9]+ of [0-9]+/) && substr(agent, RSTART, RLENGTH) != main) print "comparison: the agent column routine cell \"" agent "\" is not the main Measured table routine row (\"" main "\"): one number per measure"
      if (line[at + 7 + nw] != note) print "comparison: the sentence under the table is not the ruled one"
    }
  ' "$sec"
  # The guide: the ruled pointer sits right above the model paragraph; the worked-out sentence is gone from both files.
  section "$2" 'What OcuTalon does' > "$tmp/sec.cmpg"
  chk_block comparison "$tmp/sec.cmpg" "$CMP_POINTER

$MODEL_PARA"
  grep -niF 'Worked out from the expected answers' "$1" "$2" | cut -d: -f1,2 | sed 's|^|comparison: |; s|$|: the worked-out sentence is back|'
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

# images: chk_images <readme> <file list> <guide> [root]
# Both files are checked for alt text, targets, empty lines around image lines and sizes; "What OcuTalon does" is the guide's. The size of
# each linked file of docs/images/ is read, as wc -c, from the root (the repository by default); a linked file that the root lacks is the
# tree list's matter.
IMAGE_LIMIT=300000
chk_images() {
  local f target bytes dir=${4:-$root}
  for f in "$1" "$3"; do
    image_links "$f" | awk -F'\t' -v list="$2" -v readme="$f" '
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
  done
  { image_links "$1" | cut -f3; header_images "$1"; image_links "$3" | cut -f3; } | sort -u | while IFS= read -r target; do
    case $target in
      docs/images/*)
        if [ -f "$dir/$target" ]; then
          bytes=$(wc -c < "$dir/$target" | tr -d ' ')
          if [ "$bytes" -ge "$IMAGE_LIMIT" ]; then echo "images: $target is $bytes bytes, not under $IMAGE_LIMIT"; fi
        fi
        ;;
    esac
  done
  # Each image line is a paragraph of its own (an empty line before and after it), so that GFM does not join it to a text line.
  for f in "$1" "$3"; do
    image_links "$f" | cut -f1 | uniq | awk -v readme="$f" '
      BEGIN { while ((getline l < readme) > 0) { nl++; blank[nl] = (l !~ /[^ \t]/) } }
      ($1 > 1 && !blank[$1 - 1]) || ($1 < nl && !blank[$1 + 1]) { print "images: " readme ":" $1 ": the image line has no empty line before or after it" }
    '
  done
  # The README keeps at least one image (its hero); the guide's "What OcuTalon does" holds at least two (AC5).
  local sec="$tmp/sec.what" n
  n=$(image_links "$1" | wc -l | tr -d ' ')
  if [ "$n" -lt 1 ]; then echo "images: $1: holds no image link"; fi
  section "$3" 'What OcuTalon does' > "$sec"
  n=$(image_links "$sec" | wc -l | tr -d ' ')
  if [ "$n" -lt 2 ]; then echo "images: $3: 'What OcuTalon does' holds $n image links, not at least two"; fi
  # Placement (AC4), by bullet and not by file name: the Break the feed bullet owns at least two image paragraphs. The Chat bullet
  # has none since the owner's decision of 2026-11-05 (its image is the one in "What's interesting").
  awk -v readme="$3" '
    /^- \*\*/ { cur = (index($0, "- **Break the feed.**") == 1) ? "break" : "" }
    /^  !\[/ && cur != "" { got[cur]++ }
    END {
      if (got["break"] < 2) print "images: " readme ": the bullet Break the feed. has " got["break"] + 0 " images under it, not at least two"
    }
  ' "$sec"
}

# once: chk_once <readme> <guide>
# Each docs/images/ file is named at most once in the README and the guide together (the owner's decision of 2026-11-05: no screenshot
# shown twice).
chk_once() {
  cat "$1" "$2" | grep -o 'docs/images/[A-Za-z0-9._-]*' | sort | uniq -c | awk -v files="$1 and $2" '$1 > 1 { print "once: " files ": " $2 " is named " $1 " times, not at most once" }'
}

# media_scan <file>: file:line of each HTML media tag, each image inside a link and each image that is not an inline
# docs/images/<name>.png image. An <img> tag is exempt on the header lines only (the lines up to header_end), so a file without the
# approved header exempts none.
media_scan() {
  local f=$1 he
  he=$(header_end "$f")
  # Every media tag other than the header's <img> tags is flagged on every line.
  { grep -niE '<(iframe|video|embed|object|picture)' "$f"; grep -niE '<img' "$f" | awk -F: -v he="$he" '$1 > he'; } | cut -d: -f1 | sort -un | sed "s|^|$f:|; s|\$|: an HTML media tag (the teaser is a plain link)|"
  grep -nF '[![' "$f" | cut -d: -f1 | sed "s|^|$f:|; s|\$|: an image inside a link (the teaser is a plain link)|"
  # Every "![" of a line must be an inline docs/images/<name>.png image; a remote, local-elsewhere, non-PNG or reference-style image is not.
  image_links "$f" | awk -F'\t' '$3 ~ /^docs\/images\/[^\/]+\.png$/ { good[$1]++ } END { for (l in good) print l, good[l] }' > "$tmp/img.good"
  awk -v goodfile="$tmp/img.good" -v f="$f" '
    BEGIN { while ((getline entry < goodfile) > 0) { split(entry, p, " "); good[p[1]] = p[2] } }
    { n = 0; s = $0; while ((i = index(s, "![")) > 0) { n++; s = substr(s, i + 2) } }
    n > good[FNR] + 0 { print f ":" FNR ": an image that is not an inline docs/images/<name>.png image" }
  ' "$f"
}

# teaser
chk_teaser() {
  local f=$1 n op fv at h2
  n=$(grep -cxF -- "$FULLVIDEO" "$f")
  if [ "$n" -ne 1 ]; then echo "teaser: the full-video line is there $n times, not once"; fi
  n=$(grep -cxF -- "$TEASER" "$f")
  if [ "$n" -ne 1 ]; then echo "teaser: the line '$TEASER' is there $n times, not once"; fi
  op=$(grep -nxF -- "$OPENING" "$f" | head -n 1 | cut -d: -f1)
  fv=$(grep -nxF -- "$FULLVIDEO" "$f" | head -n 1 | cut -d: -f1)
  at=$(grep -nxF -- "$TEASER" "$f" | head -n 1 | cut -d: -f1)
  h2=$(grep -n -m 1 '^## ' "$f" | cut -d: -f1)
  if [ -z "$op" ]; then
    echo "teaser: the opening paragraph is not there, so the full-video line and the teaser have no place under it"
  else
    if [ -n "$fv" ]; then
      if [ "$fv" -ne $((op + 2)) ]; then
        echo "teaser: $f:$fv: the full-video line is not the second line below the opening paragraph (line $op)"
      elif [ -n "$(sed -n "$((op + 1))p" "$f" | tr -d ' \t')" ]; then
        echo "teaser: $f:$((op + 1)): there is no empty line between the opening paragraph and the full-video line"
      fi
      if [ -n "$h2" ] && [ "$fv" -gt "$h2" ]; then echo "teaser: $f:$fv: the full-video line is below the first H2 section"; fi
    fi
    if [ -n "$at" ]; then
      if [ -z "$fv" ]; then
        echo "teaser: $f:$at: the teaser has no full-video line above it"
      elif [ "$at" -ne $((fv + 2)) ]; then
        echo "teaser: $f:$at: it is not the second line below the full-video line (line $fv)"
      elif [ -n "$(sed -n "$((fv + 1))p" "$f" | tr -d ' \t')" ]; then
        echo "teaser: $f:$((fv + 1)): there is no empty line between the full-video line and the teaser"
      fi
      if [ -n "$h2" ] && [ "$at" -gt "$h2" ]; then echo "teaser: $f:$at: it is below the first H2 section"; fi
    fi
  fi
  media_scan "$f"
  if [ -n "${2:-}" ]; then media_scan "$2"; fi
}

# video
chk_video() {
  local f=$1 line bar n hit
  n=$(awk 'index($0, "Watch the full video") == 1' "$f" | wc -l | tr -d ' ')
  line=$(awk 'index($0, "Watch the full video") == 1 { print; exit }' "$f")
  if [ "$n" -ne 1 ]; then echo "video: $n full-video lines, not exactly one"; fi
  if ! printf '%s\n' "$line" | grep -qF -e "$YT_FULL"; then echo "video: the full-video line has no link $YT_FULL"; fi
  if ! printf '%s\n' "$line" | grep -qF -e "$MP4_FULL"; then echo "video: the full-video line has no link $MP4_FULL"; fi
  bar=$(section "$f" "$H_TRY" | awk 'index($0, "[Online demo]") == 1 { print; exit }')
  if [ -z "$bar" ]; then
    echo "video: '$H_TRY' has no link bar (a line that starts with [Online demo])"
  elif ! printf '%s\n' "$bar" | grep -qF -e "$LINK_FULL $MIDDOT $LINK_TEASER"; then
    echo "video: the link bar does not hold $LINK_FULL directly before $LINK_TEASER"
  fi
  grep -nF -e "$TEASER_URL" "$f" | while IFS= read -r hit; do
    if [ "${hit#*:}" != "$TEASER" ] && [ "${hit#*:}" != "$bar" ] && [ "${hit#*:}" != "$VIDEO_ROW" ]; then
      echo "video: $f:${hit%%:*}: the teaser address is neither in the teaser line, the link bar nor the ruled Video row"
    fi
  done
}

# checklist-video (DW-1171)
chk_checklist_video() {
  local f=$1 sec="$tmp/sec.cv" n at after
  n=$(grep -cxF -e "$VIDEO_ROW" "$f")
  if [ "$n" -ne 1 ]; then echo "checklist-video: the ruled Video row is in the README $n times, not once"; fi
  if ! headings "$f" | awk -F '\t' -v t="$H_INC" '$2 == "one-incident-end-to-end" && $3 == t { ok = 1 } END { exit !ok }'; then
    echo "checklist-video: the link #one-incident-end-to-end reaches no heading '$H_INC'"
  fi
  section "$f" "$H_CONTEST" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "checklist-video: no section '$H_CONTEST'"
    return
  fi
  n=$(awk -v p="$ONLINE_ROW" 'index($0, p) == 1' "$sec" | wc -l | tr -d ' ')
  if [ "$n" -ne 1 ]; then
    echo "checklist-video: '$H_CONTEST' has $n '$ONLINE_ROW' rows, not exactly one"
    return
  fi
  at=$(awk -v p="$ONLINE_ROW" 'index($0, p) == 1 { print NR; exit }' "$sec")
  after=$(sed -n "$((at + 1))p" "$sec")
  if [ "$after" != "$VIDEO_ROW" ]; then echo "checklist-video: the row right after '$ONLINE_ROW' in '$H_CONTEST' is not the ruled Video row"; fi
}

# judges-usability (DW-1171): the count word is any lower-case word here; the web tests pin it against the More to try registry.
chk_judges_usability() {
  local f=$1 rows n rest word
  rows=$(awk -v h="$H_JUDGES" '
    /^```/ { fence = !fence }
    !fence && /^#+ / { on = ($0 == h); next }
    on && index($0, "| Usability |") == 1
  ' "$f")
  n=$(printf '%s' "$rows" | grep -c '^')
  if [ "$n" -ne 1 ]; then
    echo "judges-usability: 'For judges: where to look' has $n Usability rows, not exactly one"
    return
  fi
  case $rows in
    "$USE_HEAD"*) ;;
    *)
      echo "judges-usability: the Usability row does not open with the ruled first sentence and 'Its More to try panel has'"
      return
      ;;
  esac
  rest=${rows#"$USE_HEAD"}
  word=$(printf '%s\n' "$rest" | sed -n 's/^\([a-z][a-z]*\).*$/\1/p')
  if [ -z "$word" ]; then
    echo "judges-usability: the Usability row has no count word (a lower-case word) after 'Its More to try panel has'"
    return
  fi
  case ${rest#"$word"} in
    "$USE_TAIL"*) ;;
    *) echo "judges-usability: the count word '$word' is not followed by the ruled rest of the second sentence" ;;
  esac
}

# path: the ruled intro line and seven steps of "One incident, end to end"; a heredoc, because the lines hold quotes.
IFS= read -r -d '' INC_BLOCK <<'INC' || true
The demo guide walks one incident in about two minutes, and you can check each step yourself on the online demo:

1. **Failures.** *Break the feed* makes a simulated partner send 50 orders in a changed date format into the Orders production, where they fail for real.
2. **One incident.** OcuTalon reads the failed messages and groups them by cause into one incident: one notice, not 50 alerts.
3. **Diagnosis.** It explains the cause in plain English and names the field or production item at fault.
4. **Dry run.** It proposes a fix with a dry run: how many orders it would resend, with an example.
5. **Approval.** Nothing is resent until you press Approve in the chat or on the page's Simulated phone; on your own install you can also approve it in Telegram. Every answer lands in the IRIS audit log.
6. **Fix.** After the approval, OcuTalon resends the orders and reports how many went through.
7. **Visual Trace.** Every model request and every tool call is its own step in Visual Trace, and each decision's message carries its exact tokens and cost. The trace links on the page open it.
INC
INC_BLOCK=${INC_BLOCK%?}
chk_path() {
  local f=$1 sec="$tmp/sec.inc" n
  section "$f" "$H_INC" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "path: no section '$H_INC'"
    return
  fi
  chk_block path "$sec" "$INC_BLOCK"
  n=$(grep -c '[^[:space:]]' "$sec")
  if [ "$n" -ne 8 ]; then echo "path: '$H_INC' has $n lines, not exactly the intro line and the seven steps"; fi
  if grep -qF -e 'Two things to look at in the demo' "$f"; then echo "path: 'Two things to look at in the demo' is back"; fi
}

# new-since: the README's H3 "New since 1.0.0" under "What's interesting", after its image line, with only the ruled pointer; and the guide's
# section "New since 1.0.0": its intro line, the three H4 groups and the 17 bullets (by bold name), in the ruled order.
NS_INTRO='Each item says where to try it. Visual Trace on the online demo is shared, so save and add nothing personal.'
NS_G1='Your integrations'
NS_G2='Your documents and memory'
NS_G3='Personas, the heartbeat checklist and the digest'
NS_WANT="H $NS_G1
B A dry run that checks good messages
B Incident summaries
B Suspend, resume and reroute
B Partner delay notices
B Queue backlogs between digests
B Webhooks
B Your own mailbox
B MCP servers in Settings
B A History page
B A Usage page
H $NS_G2
B Answers from your own documents
B Where an answer came from
B Memory
B The Memory card
H $NS_G3
B Personas
B A heartbeat checklist
B A daily digest"
chk_new_since() {
  local f=$1 g=$2 sec="$tmp/sec.ns" h3 img got line c
  section "$f" "$H_INT" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "new-since: no section '$H_INT'"
    return
  fi
  h3=$(grep -nxF -- '### New since 1.0.0' "$sec" | head -n 1 | cut -d: -f1)
  if [ -z "$h3" ]; then
    echo "new-since: '### New since 1.0.0' is not under '$H_INT'"
    return
  fi
  img=$(grep -n -m 1 '^!\[' "$sec" | cut -d: -f1)
  if [ -z "$img" ] || [ "$img" -ge "$h3" ]; then echo "new-since: '### New since 1.0.0' is not below the image line of '$H_INT'"; fi
  if [ -n "$(sed -n "$((h3 + 1))p" "$sec" | tr -d ' \t')" ] || [ "$(sed -n "$((h3 + 2))p" "$sec")" != "$POINTER" ]; then
    echo "new-since: the README's heading is not followed by an empty line and the ruled pointer"
  fi
  if [ -n "$(awk -v h="$h3" 'NR > h + 2 && /[^ \t]/' "$sec")" ]; then echo "new-since: the README's '### New since 1.0.0' holds more than the pointer"; fi
  section "$g" 'New since 1.0.0' > "$tmp/sec.ns.guide"
  if [ ! -s "$tmp/sec.ns.guide" ]; then
    echo "new-since: $g has no section '## New since 1.0.0'"
    return
  fi
  if [ -n "$(sed -n '1p' "$tmp/sec.ns.guide" | tr -d ' \t')" ] || [ "$(sed -n '2p' "$tmp/sec.ns.guide")" != "$NS_INTRO" ]; then
    echo "new-since: the guide's heading is not followed by an empty line and the ruled intro line"
  fi
  got=$(awk '
    /^#### / { print "H " substr($0, 6); next }
    index($0, "- **") == 1 { i = index($0, ".**"); print "B " (i > 0 ? substr($0, 5, i - 5) : "?") }
  ' "$tmp/sec.ns.guide")
  printf '%s\n' "$NS_WANT" | while IFS= read -r line; do
    c=$(printf '%s\n' "$got" | grep -cxF -- "$line")
    if [ "$c" -eq 0 ]; then echo "new-since: missing '$line'"; fi
    if [ "$c" -gt 1 ]; then echo "new-since: '$line' is there $c times"; fi
  done
  printf '%s\n' "$got" | while IFS= read -r line; do
    if ! printf '%s\n' "$NS_WANT" | grep -qxF -- "$line"; then echo "new-since: unexpected '$line'"; fi
  done
  if [ "$got" != "$NS_WANT" ] && [ "$(printf '%s\n' "$got" | sort)" = "$(printf '%s\n' "$NS_WANT" | sort)" ]; then
    echo "new-since: the group headings and bullets are not in the ruled order"
  fi
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
(healthy)
irishealth-community:2027.1.0AI.109.0
build 154 or build 109
The name is `ocutalon-iris-base:2026.3.0AI.154.0` for both builds.'
INSTALL_FACTS="$INSTALL_FACTS
Build 109's plain IRIS image has not been tested, and \`./install.sh\` does not use it.
The script checks that Docker and Docker Compose work and that a build 154 or build 109 image for your CPU is loaded; when both are, it uses build 154."
# The ruled build 109 paragraphs (U-241 items 2 and 4, Story 11.23), whole lines, word for word.
IFS= read -r -d '' INSTALL_B109 <<'B109' || true
OcuTalon 1.0.0 is built and tested on IRIS for Health AI Hub Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`). The InterSystems Early Access Program portal now offers build 109 (`irishealth-community:2027.1.0AI.109.0`) in its place: https://evaluation.intersystems.com/Eval/early-access/AIHub
OcuTalon also runs on build 109: at release 1.0.0 its install, production and test checks and the demo guide passed on it, and `./install.sh` accepts either build.
Without the script, give the loaded image the name OcuTalon builds from, then start it. `docker load` printed the loaded image's name; for the IRIS for Health archive of build 154 it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`, and for build 109 it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0`. The name is `ocutalon-iris-base:2026.3.0AI.154.0` for both builds.
OcuTalon also runs on the plain IRIS AI Hub build 154 image (`iris-community:2026.3.0AI.154.0`). It differs from IRIS for Health only by the HealthShare libraries and the HSCUSTOM namespace. It is supported and verified on ARM64. OcuTalon's automated tests use only the IRIS for Health image. Build 109's plain IRIS image has not been tested, and `./install.sh` does not use it.
B109
INSTALL_FACTS="$INSTALL_FACTS
$INSTALL_B109"
T_B109='**"No IRIS build 154 or build 109 image is loaded in Docker"**: download the archive for your CPU ([Get the image](#get-the-image)), load it with `docker load -i <the archive file>`, then run `./install.sh`.'
T_B109_CPU='**"The IRIS build 154 or build 109 image that is loaded is for another CPU than this machine'"'"'s"**:'
H_B109='### Start it with build 109'
chk_install() {
  local sec="$tmp/sec.install" line
  section "$1" 'Install it yourself' > "$sec"
  chk_facts install "$sec" "$INSTALL_FACTS"
  # The ruled paragraphs are whole lines of the section: nothing is added to them.
  printf '%s\n' "$INSTALL_B109" | while IFS= read -r line; do
    if ! grep -qxF -e "$line" "$sec"; then echo "install: the ruled paragraph \"${line:0:50}...\" is not a line of the section, word for word"; fi
  done
  # One install path for both builds: no separate build 109 section, no .env line for IRIS_IMAGE, no link to the removed anchor.
  if grep -qxF "$H_B109" "$sec"; then echo "install: the separate '$H_B109' path is back"; fi
  if grep -qF 'IRIS_IMAGE=' "$sec"; then echo "install: IRIS_IMAGE= is back in the install sections"; fi
  if grep -qF '(#start-it-with-build-109)' "$1"; then echo "install: a link to the removed '#start-it-with-build-109' is back"; fi
  # The Troubleshooting entries quote install.sh's first lines word for word.
  section "$1" 'Troubleshooting' > "$tmp/sec.trouble"
  if ! grep -qxF -e "$T_B109" "$tmp/sec.trouble" || ! grep -qF -e "$T_B109_CPU" "$tmp/sec.trouble"; then
    echo "install: the Troubleshooting entries do not quote install.sh's build 154 or build 109 messages word for word"
  fi
}

# install-pointer: chk_install_pointer <guide> <install.sh>
chk_install_pointer() {
  local names name
  grep -n 'section of README\.md' "$2" | cut -d: -f1 | sed 's|^|install-pointer: install.sh:|; s|$|: points to a section of README.md, which moved to GUIDE.md|'
  names=$(sed -n 's/.*[Tt]he \([A-Za-z][A-Za-z ]*\) section of GUIDE\.md.*/\1/p' "$2" | sort -u)
  if [ -z "$names" ]; then
    echo "install-pointer: install.sh names no GUIDE.md section (the extraction found none)"
    return
  fi
  printf '%s\n' "$names" | while IFS= read -r name; do
    if ! grep -qxF -- "## $name" "$1"; then echo "install-pointer: install.sh points to the section '$name', and GUIDE.md has no '## $name' heading"; fi
  done
}

# commands (DW-134): chk_commands <guide> <install.sh> <readme>: install.sh's commands are in the guide; neither file has the forbidden wording
chk_commands() {
  local cmds cmd f
  cmds=$(sed -n 's/.*run: *\(docker compose[^"]*\)".*/\1/p' "$2" | sed 's/ *$//' | sort -u)
  if [ -z "$cmds" ]; then
    echo "commands: install.sh prints no docker compose command after 'run:' (the extraction found none)"
  else
    printf '%s\n' "$cmds" | while IFS= read -r cmd; do
      if ! grep -qF -e "$cmd" "$1"; then echo "commands: install.sh prints '$cmd', and $1 does not"; fi
    done
  fi
  for f in "$1" "$3"; do
    grep -niE 'docker[ -]compose restart|docker restart|install(\.sh`?| script) again|re-?run' "$f" | cut -d: -f1 | sed "s|^|commands: $f:|; s|\$|: wording the guide and the README must not use (DW-134)|"
  done
}

# key-account
KEY_FACTS='ANTHROPIC_API_KEY=<your key>
.env.example
Claude Haiku 5.5
Anthropic is the supported model provider: in Settings, an admin can choose Claude Haiku 5.5 or Claude Sonnet 5.5 for each agent.
Each supported provider'"'"'s key comes from its own environment variable, which `.env.example` lists without a value; Anthropic'"'"'s is `ANTHROPIC_API_KEY`.
A key is never entered on the settings page, and the page never shows one.
Sign in to Visual Trace'
ACCOUNT_FACTS='User name: `ocutalon`
Password: `ocutalon`'
chk_key_account() {
  local sec="$tmp/sec.signin" rows f
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
  for f in "$1" "$2"; do
    grep -nF 'No key, still works.' "$f" | cut -d: -f1 | sed "s|^|key-account: $f:|; s|\$|: the bullet \"No key, still works.\" is back|"
    grep -n 'ANTHROPIC_API_KEY=' "$f" | grep -v 'ANTHROPIC_API_KEY=<your key>' | cut -d: -f1 | sed "s|^|key-account: $f:|; s|\$|: a key-shaped example|"
  done
}

# lan (DW-3)
LAN_FACTS='LAN
Management Portal
](#change-the-readme-accounts-password)
](#change-the-default-iris-accounts-passwords)
Change the README account'"'"'s password after your first sign-in'
H_ACCOUNTS="### Change the default IRIS accounts' passwords"
# The steps of that section (DW-360), as measured against the portal (spec 31.3, Decided in-stage 14 and 26).
IFS= read -r -d '' ACCOUNTS_FACTS <<'DW360' || true
http://localhost:52773/csp/sys/UtilHome.csp
System Administration, then Security, then Users
select Enter new password, enter a new password in Password and Password (confirm), and press Save.
Leave `CSPSystem`, the web gateway's account
DW360
chk_lan() {
  local sec="$tmp/sec.lan" readme accounts
  section "$1" 'Sign in' > "$sec"
  chk_facts lan "$sec" "$LAN_FACTS"
  # DW-360: the section for the default IRIS accounts follows the README account's, in "For admins and developers".
  readme=$(grep -nxF -m 1 "### Change the README account's password" "$1" | cut -d: -f1)
  accounts=$(grep -nxF -m 1 "$H_ACCOUNTS" "$1" | cut -d: -f1)
  if [ -z "$accounts" ]; then
    echo "lan: no section '$H_ACCOUNTS'"
  elif [ -z "$readme" ] || [ "$accounts" -le "$readme" ]; then
    echo "lan: '$H_ACCOUNTS' does not follow the README account's password section"
  else
    awk -v h="$H_ACCOUNTS" '/^#+ / { on = ($0 == h); next } on { print }' "$1" > "$tmp/sec.accounts"
    chk_facts lan "$tmp/sec.accounts" "$ACCOUNTS_FACTS"
  fi
}

# sign-in-address: chk_sign_in_address <guide> <install.sh> <docker-compose.yml> <readme>
# ready_lines <install.sh> <port>: the Open, User and Password lines of install.sh's ready block, with the port filled in.
ready_lines() {
  sed -n 's/^[[:space:]]*echo "\(  Open: .*\)"$/\1/p; s/^[[:space:]]*echo "\(  User: .*\)"$/\1/p; s/^[[:space:]]*echo "\(  Password: .*\)"$/\1/p' "$1" |
    sed "s/\\\$port/$2/"
}
chk_sign_in_address() {
  local port lines line addr user pass t f sec="$tmp/sec.address"
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
    if ! grep -qxF -- "$line" "$1"; then echo "sign-in-address: install.sh prints '$line', and the guide's ready block does not"; fi
  done
  addr=$(printf '%s\n' "$lines" | sed -n 's/^  Open: *//p')
  user=$(printf '%s\n' "$lines" | sed -n 's/^  User: *//p')
  pass=$(printf '%s\n' "$lines" | sed -n 's/^  Password: *//p')
  for t in "$H_TRY" 'Sign in'; do
    f=$1
    if [ "$t" = "$H_TRY" ]; then f=$4; fi
    section "$f" "$t" > "$sec"
    if ! grep -qF -e "$addr" "$sec"; then echo "sign-in-address: the section '$t' does not give the address $addr"; fi
  done
  section "$4" "$H_TRY" > "$sec"
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

# admin-mcp (Story 36.3; FR-10): "For admins and developers" opens with the ruled MCP paragraph (Planner M(4), G2), once in the guide,
# and its first sentence is a line of the worked example, word for word, so the link's target is there: chk_admin_mcp <guide> <example>.
ADMIN_MCP_RISKY='An MCP tool that runs operating-system commands or arbitrary code must be classified Risky.'
ADMIN_MCP_LINE="$ADMIN_MCP_RISKY The worked example [A Jira MCP server, step by step]($MCP_EXAMPLE_DOC) shows how to add a server and classify its tools."
chk_admin_mcp() {
  local sec="$tmp/sec.adminmcp" n
  section "$1" 'For admins and developers' > "$sec"
  if [ "$(awk 'NF { print; exit }' "$sec")" != "$ADMIN_MCP_LINE" ]; then
    echo "admin-mcp: 'For admins and developers' does not open with the ruled MCP paragraph"
  fi
  if [ -n "$(awk -v l="$ADMIN_MCP_LINE" 'f { print; exit } $0 == l { f = 1 }' "$sec")" ]; then
    echo "admin-mcp: a line runs on from the ruled MCP paragraph with no empty line, so Markdown joins it to the paragraph"
  fi
  n=$(grep -cxF -- "$ADMIN_MCP_LINE" "$1")
  if [ "$n" -ne 1 ]; then echo "admin-mcp: the guide holds the ruled MCP paragraph $n times, not once"; fi
  if [ "$(grep -cxF -- "$ADMIN_MCP_RISKY" "$2")" -ne 1 ]; then
    echo "admin-mcp: $MCP_EXAMPLE_DOC does not hold the guide's classification sentence once, as a line of its own"
  fi
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
# keys" must name README.md and GUIDE.md.
chk_must_scan() {
  awk '
    /^for f in / { hdr = ""; on = 1 }
    on { hdr = hdr " " $0; if ($0 ~ /; do[ \t]*$/) { on = 0; last = hdr } }
    /not scanned for paths and keys/ { found = last; seen = 1 }
    END {
      if (!seen) { print "must-scan: test-boundaries.sh has no must-scan list for paths and keys (the extraction found none)"; exit }
      n = split(found, w, /[ \t\\;]+/)
      for (i = 1; i <= n; i++) { if (w[i] == "README.md") readme = 1; if (w[i] == "GUIDE.md") guide = 1 }
      if (!readme) print "must-scan: the must-scan list for paths and keys in test-boundaries.sh does not name README.md"
      if (!guide) print "must-scan: the must-scan list for paths and keys in test-boundaries.sh does not name GUIDE.md"
    }
  ' "$1"
}

# dev-only: file:line of each line outside the H2 sections "For admins and developers" and "Gmail and Microsoft 365" (which names the provider consoles' own settings) with a ##class( call, a class name (a dotted
# name whose parts start with an upper-case letter, a leading % allowed), an ERROR #<digits> code or an <UPPER> error name.
# The IPM load line (IPM_LOAD) and the judges' Complexity row (COMPLEXITY_ROW, Story 0.36) are exempt, word for word. The scanner
# takes the README and the guide.
dev_names() {
  awk -v ipmload="$IPM_LOAD" -v complexity="$COMPLEXITY_ROW" '
    FNR == 1 { stop = 0 }
    /^## / { stop = ($0 == "## For admins and developers" || $0 == "## Gmail and Microsoft 365") }
    stop { next }
    $0 == ipmload || $0 == complexity { next }
    /##class\(/ || /ERROR #[0-9]+/ || /<[A-Z][A-Z][A-Z]+>/ || /(^|[^A-Za-z0-9_])%?[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)+/ { print FILENAME ":" FNR }
  ' "$@"
}

# public-text: file:line of each line of the files with a provider, "from your phone", "per step", private infrastructure, an IPv4 address other
# than 127.0.0.1 and 0.0.0.0, or OpenClaw outside the note (which only the first file, the README, may hold); and what the first file lacks:
# the note, the credit, the licence pointers.
PUBLIC_FACTS='Built with the BMAD Method and Claude Code.
web/public/assets/licenses
docker/ipm/LICENSE
3rdpartylicenses.txt'
public_text_scan() {
  awk -v note="$NOTE" -v first="$1" '
    function word(l, w) { return l ~ ("(^|[^a-z0-9])(" w ")([^a-z]|$)") }
    {
      l = tolower($0)
      if (word(l, "openai|gpt|chatgpt|gemini|mistral|cohere|llama|ollama|bedrock|azure|deepseek|grok")) print FILENAME ":" FNR
      else if (l ~ /from your phone|per[- ]step|find a bug|bonus|never used for tuning/) print FILENAME ":" FNR
      else if (l ~ /ocutalon-ci|ocutalon-slot|\.worktrees|\.coordination|digitalocean|droplet|sfo2|contest planner|epic-cycle|self-hosted/) print FILENAME ":" FNR
      else if (l ~ /openclaw/ && ($0 != note || FILENAME != first)) print FILENAME ":" FNR
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
  if ! grep -qxF -- "$NOTE" "$1"; then echo "$1: the not-affiliated note is missing or not word for word"; fi
  chk_facts "$1" "$1" "$PUBLIC_FACTS"
}

# The scanners take files, the self-test helpers three arguments: these give them the first.
dev_names_1() { dev_names "$1"; }
public_text_1() { public_text_scan "$1"; }
public_text_2() { public_text_scan "$1" "$2"; }

# no-telegram: chk_no_telegram <readme> <mode> <guide>
chk_no_telegram() {
  if [ "$2" = testonly ]; then
    grep -niF telegram "$1" "$3" | cut -d: -f1,2 | sed 's|^|no-telegram: |; s|$|: the word Telegram while Included() is test-only|'
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

# gmail-section (Story 21.8, QA; Public text T3 and T4, DW-1180): the "Your own mailbox" bullet of "New since 1.0.0" and the section "Gmail and Microsoft 365" are the approved
# text word for word (the bullet is the line GM_T3; the section is GM_T4, between its heading and the next one), the section sits after "Telegram" and before "Stop, start and update",
# the bullet's link #gmail-and-microsoft-365 is the heading's own anchor, and nothing in the README, GUIDE.md, docs/ or release/ says or implies least privilege (DW-1180).
# S1 is GUIDE.md (the texts moved there with Story 0.30), S2 the text of README.md, docs/ and release/ (assembled from the files that exist).
H_GM='Gmail and Microsoft 365'
GM_ANCHOR='gmail-and-microsoft-365'
GM_T3='- **Your own mailbox.** On your own install, an admin connects a POP3 mailbox in Settings > Channels > Email, with a password or by signing in with Google or Microsoft 365 (see [Gmail and Microsoft 365](#gmail-and-microsoft-365)). OcuTalon makes an attention decision on each email that arrives after that, sends the email to the model for it, and leaves your mail on the server. Email is read as untrusted content: nothing in an email can approve, change or run anything. With an outgoing mail server saved, Settings > Daily digest can also send your digest to that address. The online demo keeps its simulated mailbox.'
IFS= read -r -d '' GM_T4 <<'GMEOF' || true
Signing in with Google or Microsoft 365 is optional, and these steps are for your own install. OcuTalon then reads the mailbox over POP3 and sends over SMTP with the sign-in instead of a stored password, and IRIS renews the sign-in's access token when it expires. The provider steps below follow Google's and Microsoft's documentation; their consoles change, so check their current pages if a name differs.

1. Open http://localhost:52773/ocutalon/, go to Settings > Channels > Email and choose the Sign-in method Google or Microsoft 365. The form shows the Redirect address: the address you opened OcuTalon at, followed by `/csp/sys/oauth2/OAuth2.Response.cls` (for example `http://localhost:52773/csp/sys/oauth2/OAuth2.Response.cls`). Google and Microsoft accept an `http://` Redirect address only for `localhost`, so open OcuTalon at `http://localhost:52773/ocutalon/` for this step, or serve it over `https://`.
2. Create the OAuth2 client with the provider. **Google:** in the Google Cloud console, create an OAuth client ID of type Web application and add the Redirect address under Authorized redirect URIs; OcuTalon asks for the scope `https://mail.google.com/`. Turn on POP in the mailbox's Gmail settings. On the OAuth consent screen, add the mailbox's address as a test user. While the app's publishing status is Testing, Google ends the sign-in after 7 days, and you sign in again. **Microsoft 365:** in the Microsoft Entra admin center, register an application, add the Redirect address as a Web redirect URI, create a client secret, and add the delegated permissions `POP.AccessAsUser.All`, `SMTP.Send` and `offline_access`. POP and authenticated SMTP must be allowed for the mailbox.
3. In the form, enter the Client ID and the Client secret, the mailbox's address, the incoming and outgoing servers (for example `pop.gmail.com:995` and `smtp.gmail.com:465`, or `outlook.office365.com:995` and `smtp.office365.com:587`) and the mailbox's address as the user name, then save.
4. Press "Sign in with Google" (or Microsoft 365). The provider's consent page opens in a new tab; after you agree, the tab returns to Settings, which shows "Signed in with Google."

If the sign-in is withdrawn at the provider, the next check of the mailbox fails with "The mail sign-in is no longer valid." and Settings offers the sign-in again. Saving the Password method removes the sign-in from IRIS. The online demo has no real mailbox and no sign-in.

All email OcuTalon sends goes out from the one mailbox connected in Settings > Channels > Email. Only an OcuTalon admin can have OcuTalon email another address: without the admin role, OcuTalon tells you so and sends nothing. The admin who connected the mailbox can have OcuTalon email the mailbox's own address without an approval.
GMEOF
LEAST_RE='least[- ]privilege|minimum privilege'
chk_gmail_section() {
  local f=$1 g=${2:-} sec="$tmp/sec.gm" want="$tmp/want.gm" order slug
  if ! grep -qxF -- "$GM_T3" "$f"; then echo "gmail-section: the 'Your own mailbox' bullet is not the approved text (T3)"; fi
  section "$f" "$H_GM" | awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] == "") s++; e = NR; while (e >= s && l[e] == "") e--; for (i = s; i <= e; i++) print l[i] }' > "$sec"
  if [ ! -s "$sec" ]; then
    echo "gmail-section: no section '$H_GM'"
  else
    printf '%s' "$GM_T4" > "$want"
    if ! cmp -s "$sec" "$want"; then echo "gmail-section: the section '$H_GM' is not the approved text (T4)"; fi
  fi
  order=$(headings "$f" | awk -F'\t' '$1 == 2 { print $3 }' | grep -xF -e 'Telegram' -e "$H_GM" -e 'Stop, start and update' | tr '\n' '|')
  if [ "$order" != "Telegram|$H_GM|Stop, start and update|" ]; then echo "gmail-section: the section is not between 'Telegram' and 'Stop, start and update'"; fi
  slug=$(printf '%s' "$H_GM" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-')
  if [ "$slug" != "$GM_ANCHOR" ] || ! grep -qF -- "(#$GM_ANCHOR)" "$f" || ! grep -qxF -- "## $H_GM" "$f"; then echo "gmail-section: the link #$GM_ANCHOR does not reach the heading '$H_GM'"; fi
  if grep -qiE "$LEAST_RE" "$f"; then echo "gmail-section: $f says or implies least privilege (DW-1180)"; fi
  if [ -n "$g" ] && [ -f "$g" ] && grep -qiE "$LEAST_RE" "$g"; then echo "gmail-section: README.md, docs/ or release/ says or implies least privilege (DW-1180)"; fi
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
  if ! grep -qF 'In the Status section (in a narrower window, open it with the Status button at the top of the page)' "$sec"; then echo "telegram-facts: step 5 does not say how to open the Status section in a narrower window (U-238)"; fi
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

# ipm (Story 31.3, Story 11.24; AD-23, U-231): chk_ipm <guide> <docs/install-ipm.md> <readme>
H_IPM='### Install it with IPM'
IPM_WARNING='`enable -community` first removes the package repositories that are already set up in %SYS, so note any you use before you run it.'
IPM_LOAD='s r=##class(%Net.HttpRequest).%New(),r.Server="pm.community.intersystems.com",r.SSLConfiguration="ISC.FeatureTracker.SSL.Config" d r.Get("/packages/zpm/0.10.10/installer"),$system.OBJ.LoadStream(r.HttpResponse.Data,"c")'
IPM_MAP='zpm "enable -map -ns USER"'
# The guide's three sentences on IPM mapped from %SYS versus IPM installed in USER itself.
IPM_USER_SENTENCE='The two commands give the same result when USER already had IPM mapped from %SYS. If IPM was installed in USER itself, they leave USER'\''s repositories as they are: then also run `zpm "enable -community"` in an IRIS terminal in USER before the install. There it first deletes the repositories configured in USER.'
# ipm_in_order <file>: succeeds when the IPM load line, the map step, the registry line and the first install are whole lines in this order.
ipm_in_order() {
  local a b c d
  a=$(grep -nxF -m 1 -- "$IPM_LOAD" "$1" | cut -d: -f1)
  b=$(grep -nxF -m 1 -- "$IPM_MAP" "$1" | cut -d: -f1)
  c=$(grep -nxF -m 1 -- 'zpm "enable -community"' "$1" | cut -d: -f1)
  d=$(grep -nxF -m 1 -- 'zpm "install ocutalon"' "$1" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ]
}
chk_ipm() {
  local sec="$tmp/sec.ipm" at ready next enable first load folder registry
  awk '/^```/ { fence = !fence } !fence && /^#+ / { on = ($0 == "'"$H_IPM"'"); next } on { print }' "$1" > "$sec"
  if [ ! -s "$sec" ]; then
    echo "ipm: no section '$H_IPM'"
    return
  fi
  at=$(grep -nxF -m 1 "$H_IPM" "$1" | cut -d: -f1)
  ready=$(grep -nxF -m 1 '### Check that it is ready' "$1" | cut -d: -f1)
  next=$(grep -nxF -m 1 '## Set a model key' "$1" | cut -d: -f1)
  if [ -z "$ready" ] || [ -z "$next" ] || [ "$at" -le "$ready" ] || [ "$at" -ge "$next" ]; then
    echo "ipm: '$H_IPM' is not the last section of 'Install it yourself', after 'Check that it is ready'"
  fi
  enable=$(grep -nF -m 1 'zpm "enable -community"' "$sec" | cut -d: -f1)
  first=$(grep -nF -m 1 'zpm "install ocutalon"' "$sec" | cut -d: -f1)
  if [ -z "$enable" ]; then echo 'ipm: the community-registry line zpm "enable -community" is missing'; fi
  if [ -z "$first" ]; then echo 'ipm: the command zpm "install ocutalon" is missing'; fi
  if [ -n "$enable" ] && [ -n "$first" ]; then
    if [ "$enable" -ge "$first" ]; then
      echo 'ipm: the community-registry line does not come before the first zpm "install ocutalon"'
    elif ! sed -n "${enable},${first}p" "$sec" | grep -qF 'USER'; then
      echo 'ipm: the first zpm "install ocutalon" is not said to run in USER'
    fi
  fi
  if ! grep -qF '](docs/install-ipm.md)' "$sec"; then echo 'ipm: the section does not link docs/install-ipm.md'; fi
  if grep -qi 'any namespace' "$sec"; then echo 'ipm: the section says "any namespace"'; fi
  if ! grep -qF "$IPM_WARNING" "$sec"; then echo 'ipm: the section does not warn that the registry line removes the repositories already set up'; fi
  if ! grep -qxF 'zn "OCUTALON"' "$sec" || [ "$(grep -cxF 'zpm "install ocutalon"' "$sec")" -lt 2 ]; then echo 'ipm: the section does not give the second run in OCUTALON'; fi
  load=$(grep -nF -m 1 'zpm "load' "$sec" | cut -d: -f1)
  if [ -n "$load" ] && { [ -z "$first" ] || [ "$load" -le "$first" ]; }; then echo 'ipm: the folder install (zpm "load) comes before the registry install'; fi
  if [ "$(grep -cxF -- "$IPM_LOAD" "$sec")" -ne 1 ] || [ "$(( $(grep -cxF -- "$IPM_LOAD" "$1") + $(grep -cxF -- "$IPM_LOAD" "${3:-/dev/null}") ))" -ne 1 ]; then echo 'ipm: the section does not give the IPM 0.10.10 load line word for word, once, and nowhere else in the guide or the README'; fi
  if ! ipm_in_order "$sec"; then echo 'ipm: the IPM load line, the map step and the registry line are not in this order before the first install'; fi
  if ! ipm_in_order "$2"; then echo "ipm: $IPM_DOC does not give the guide's IPM lines in order before its first install"; fi
  if grep -qF -e 'Until the package is published' -e '/tmp/ocutalon-repo' "$2"; then echo "ipm: $IPM_DOC keeps the local-repository sentence or path"; fi
  if ! awk '/^## Install from the package folder/ { exit } /^\[OCUTALON\|ocutalon\]\tReload START \(\/usr\/irissys\/ipm\/ocutalon\// { f = 1 } END { exit !f }' "$2"; then
    echo "ipm: $IPM_DOC has no registry reload line in its registry install"
  fi
  if ! grep -qF -- "$IPM_USER_SENTENCE" "$2"; then echo "ipm: $IPM_DOC does not say what to do when IPM was installed in USER itself"; fi
  if grep -qE -- 'when USER already had IPM\.([[:space:]]|$)' "$2"; then echo "ipm: $IPM_DOC claims the same result for any IPM in USER"; fi
  # The linked page gives the registry install first and the folder install second.
  registry=$(grep -nF -m 1 'zpm "install ocutalon"' "$2" | cut -d: -f1)
  folder=$(grep -nF -m 1 'zpm "load' "$2" | cut -d: -f1)
  if [ -z "$registry" ] || [ -z "$folder" ] || [ "$registry" -ge "$folder" ]; then
    echo "ipm: $IPM_DOC does not give the registry install before the folder install"
  fi
}

# licence (Story 31.3, Story 34.2): chk_licence <readme> <LICENSE> <Dockerfile>
LICENCE_LINE='OcuTalon is under the MIT License: [LICENSE](LICENSE).'
HOLDER_LINE='Copyright (c) 2026 jbrandtmse'
# The ruled bullet (the Contest Planner, 2026-11-05), byte for byte; its path in backticks is the file that the Dockerfile writes.
NOTICES_BULLET='- The Docker image'"'"'s Python packages for documents and memory (fastembed, pdfplumber and python-docx, with their dependencies and the libraries bundled with PDFium) are listed with their licence texts and credits in `/opt/ocutalon/THIRD-PARTY-NOTICES`, which the image build writes from the installed packages.'
chk_licence() {
  local sec="$tmp/sec.licence" readme_path docker_path
  if ! grep -qF 'Permission is hereby granted, free of charge, to any person obtaining a copy' "$2"; then echo "licence: $LICENSE_FILE has no MIT grant paragraph"; fi
  if ! grep -qF 'The above copyright notice and this permission notice shall be included in all' "$2"; then echo "licence: $LICENSE_FILE has no MIT condition paragraph"; fi
  if ! grep -qF 'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND' "$2"; then echo "licence: $LICENSE_FILE has no MIT warranty paragraph"; fi
  if [ "$(grep -c '^Copyright' "$2")" -ne 1 ] || ! grep -qxF -- "$HOLDER_LINE" "$2"; then echo "licence: $LICENSE_FILE does not hold exactly the line '$HOLDER_LINE'"; fi
  section "$1" 'Credits and licences' > "$sec"
  if ! grep -qxF -- "$LICENCE_LINE" "$sec"; then echo "licence: 'Credits and licences' does not hold the line '$LICENCE_LINE'"; fi
  # The notices bullet: exactly once, the fourth bullet after "Third-party licence notices:", and its path is the Dockerfile's.
  if [ "$(grep -cxF -- "$NOTICES_BULLET" "$sec")" -ne 1 ]; then
    echo "licence: 'Credits and licences' does not hold the notices bullet word for word, once"
  elif [ "$(awk '/^Third-party licence notices:$/ { on = 1; next } on && /^- / { n++; if (n == 4) { print; exit } }' "$sec")" != "$NOTICES_BULLET" ]; then
    echo "licence: the notices bullet is not the fourth bullet under 'Third-party licence notices:'"
  fi
  readme_path=$(grep -xF -- "$NOTICES_BULLET" "$sec" | sed -n 's/^[^`]*`\([^`]*\)`.*$/\1/p')
  docker_path=$(grep -v '^[[:space:]]*#' "$3" | sed -n 's/^.*gate\.py notices [^ ]* \([^ ]*\).*$/\1/p')
  if [ -z "$docker_path" ]; then
    echo "licence: $DOCKERFILE has no notices step (gate.py notices <folder> <file>)"
  elif [ "$readme_path" != "$docker_path" ]; then
    echo "licence: the README names '$readme_path' and $DOCKERFILE writes '$docker_path'"
  fi
}

# docs (Story 31.3, AC 2 and AC 7; Story 21.10 pins L111, L187 and APPROVAL_TAIL, DW-1266, DW-1314 and DW-1315): chk_docs <docs/bridge-guide.md> <docs/install-ipm.md> <docs/security-overview.md>
BRIDGE_BULLET_START='- InterSystems AI Hub, build 154, '
BRIDGE_SENTENCE='Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet.'
IPM_BULLET_START='- An InterSystems IRIS for AI Hub instance, build 154, '
IPM_SENTENCE='Build 109, which the Early Access portal now offers in place of build 154, works the same way: the registry install on this page was run on fresh IRIS for Health instances of both builds.'
L111='- It is fixed to exact targets and shows its dry run (a fix), or the tool, its MCP server when it has one, and each of its inputs on a line of its own through the redactor, with the full call kept in the approval record (a tool call). In Telegram, an approval request for a tool call that is too long for one message shows only its start, with no Approve button.'
L187="- Every call passes the gate, an approval request when needed (showing the tool, its server and each of its inputs on a line of its own, through the redactor, with the full call kept in the approval record), an audit entry for each call it lets run (read-only calls included) and an agent step. A call to a removed server's tool runs nothing and writes no audit entry. A request too long to show in full on Telegram has no Approve button there."
L2114="- Anyone with the trace role can read the content of every item that reaches OcuTalon in Visual Trace and the message viewer, such as a chat message's text and an email's sender, subject and text."
L2115="- An email OcuTalon sends to the connected mailbox's own address keeps its subject and text in the trace, like a chat message. An email to anyone else keeps them only in its approval record. No email's recipients are in the trace. The trace does keep the chat's messages as written, so an address or text that you or OcuTalon wrote in the chat is in it."
APPROVAL_TAIL="Every built-in tool is safe except \`send_email\` and \`call_mcp_tool\`, which are classified per call. Code classifies \`send_email\`: an email to the connected mailbox's own address is safe, and an email to anyone else is risky. \`call_mcp_tool\` takes the admin's classification of the server's tool at its current fingerprint, and an unclassified tool counts as risky. Each risky built-in action, such as repair and resend or an email to anyone else, is a fix kind that waits for a person's approval and shows first exactly what it will do. A risky MCP call waits for a person's approval of that exact call, as the MCP tools section below describes."
APPROVAL_FRAME="## Approval and audit"
MCP_FRAME="## MCP tools"
chk_docs() {
  if ! grep -F -- "$BRIDGE_BULLET_START" "$1" | grep -q -F -- "$BRIDGE_SENTENCE"; then
    echo "docs: $BRIDGE_DOC has no build 154 bullet that holds the build 109 sentence"
  fi
  if ! grep -F -- "$IPM_BULLET_START" "$2" | grep -q -F -- "$IPM_SENTENCE"; then
    echo "docs: $IPM_DOC has no build 154 bullet that holds the build 109 sentence"
  fi
  if [ "$(grep -c -x -F -- "$L111" "$3")" -ne 1 ]; then echo "docs: $SECOV_DOC does not hold the ruled line about a tool call's approval request once"; fi
  if [ "$(grep -c -x -F -- "$L187" "$3")" -ne 1 ]; then echo "docs: $SECOV_DOC does not hold the ruled line of the MCP rules about the approval request once"; fi
  if [ "$(grep -c -x -F -- "$L2114" "$3")" -ne 1 ]; then echo "docs: $SECOV_DOC does not hold the ruled line about what the trace role reads once"; fi
  if ! awk -v l="$L2114" 'prev ~ /^- `OcuTalonTraceViewer` is the trace role/ && $0 == l { ok = 1 } { prev = $0 } END { exit !ok }' "$3"; then
    echo "docs: the trace role's sentence is not the bullet right after the OcuTalonTraceViewer bullet"
  fi
  if [ "$(grep -c -x -F -- "$L2115" "$3")" -ne 1 ]; then echo "docs: $SECOV_DOC does not hold the ruled line about the trace and an email's content once"; fi
  if ! awk -v p="$L2114" -v l="$L2115" 'prev == p && $0 == l { ok = 1 } { prev = $0 } END { exit !ok }' "$3"; then
    echo "docs: the trace and an email's content line is not the bullet right after the trace role's sentence"
  fi
  if [ "$(awk -v t="$APPROVAL_TAIL" '{ n = length($0); m = length(t); if (n >= m && substr($0, n - m + 1) == t) c++ } END { print c + 0 }' "$3")" -ne 1 ]; then
    echo "docs: $SECOV_DOC does not hold exactly one line that ends with the ruled text about the classification of the built-in tools"
  fi
  if ! awk -v f="$APPROVAL_FRAME" -v t="$APPROVAL_TAIL" '$0 == f { a = 1; next } a && $0 != "" { n = length($0); m = length(t); ok = (n >= m && substr($0, n - m + 1) == t); a = 0 } END { exit !ok }' "$3"; then
    echo "docs: the ruled text about the classification of the built-in tools is not the first paragraph under \"$APPROVAL_FRAME\""
  fi
  if grep -q -F -- 'the exact call' "$3"; then echo "docs: $SECOV_DOC still promises 'the exact call'"; fi
  if ! awk -v f="$MCP_FRAME" -v l="$L187" '/^#/ && a && !b { h = 1 } $0 == f { a = NR } $0 == l { b = NR } END { exit !(a && b && a < b && !h) }' "$3"; then
    echo "docs: the MCP rules line is not under \"$MCP_FRAME\" with no other heading between"
  fi
}

# telegram-demo (U-228 condition 2): sentence by sentence, outside code fences, in the README and the guide: chk_telegram_demo <readme> <guide>.
chk_telegram_demo() {
  awk '
    FNR == 1 { fence = 0; sec = 0 }
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
  ' "$1" "$2"
}

# address_anchors <list file> <readme|guide>: the part after # of each written address of the README (jbrandtmse/OcuTalon#x) or of
# the guide (jbrandtmse/OcuTalon/blob/main/GUIDE.md#x) in the files of the list, one per line, sorted.
address_anchors() {
  local re='jbrandtmse/OcuTalon#[A-Za-z0-9_-]+'
  if [ "$2" = guide ]; then re='jbrandtmse/OcuTalon/blob/main/GUIDE\.md#[A-Za-z0-9_-]+'; fi
  tr '\n' '\0' < "$1" | xargs -0 grep -hoE "$re" /dev/null 2>/dev/null | sed 's/.*#//' | sort -u
}

# inventory <list file>: the anchors that the files of the list can link to, one per line, sorted: the part after # of a README or
# guide address (address_anchors), the section argument of a readmeSection(..., '<x>') call, and the value of a *_ANCHOR constant of
# a TypeScript file.
inventory() {
  {
    address_anchors "$1" readme
    address_anchors "$1" guide
    tr '\n' '\0' < "$1" | xargs -0 grep -hoE "readmeSection\\([^,)]*,[[:space:]]*'[^']*'" /dev/null 2>/dev/null | sed "s/.*'\\([^']*\\)'\$/\\1/"
    grep -E '\.ts$' "$1" | tr '\n' '\0' | xargs -0 grep -hoE "[A-Z][A-Z_]*_ANCHOR[^=']*=[[:space:]]*'[^']*'" /dev/null 2>/dev/null | sed "s/.*'\\([^']*\\)'\$/\\1/"
  } | sort -u
}

# product-links: chk_product_links <readme> <list file> <In.cls> <guide>: every anchor reaches a heading of the README or the guide, the
# three anchors that the page opens on GUIDE_URL (install-it-yourself, set-a-model-key and telegram) are headings of the guide, and
# each written address reaches a heading of the file it names (a README address the README's, a GUIDE.md address the guide's).
chk_product_links() {
  local anchors mode slugs readme_slugs guide_slugs a
  anchors=$(inventory "$2")
  for a in readme telegram install-it-yourself set-a-model-key; do
    if ! printf '%s\n' "$anchors" | grep -qxF -- "$a"; then
      echo "product-links: the link inventory finds no '#$a' anchor, so a renamed constant could hide every page link"
    fi
  done
  mode=$(telegram_mode "$3")
  slugs=$({ headings "$1"; headings "$4"; } | cut -f2)
  guide_slugs=$(headings "$4" | cut -f2)
  printf '%s\n' "$anchors" | while IFS= read -r a; do
    case $a in
      '') continue ;;
      readme) continue ;;
      telegram) if [ "$mode" = testonly ]; then continue; fi ;;
    esac
    if ! printf '%s\n' "$slugs" | grep -qxF -- "$a"; then echo "product-links: the page links to '#$a', and neither the README nor the guide has a heading with that slug"; fi
    case $a in
      install-it-yourself | set-a-model-key | telegram)
        if ! printf '%s\n' "$guide_slugs" | grep -qxF -- "$a"; then echo "product-links: the page opens GUIDE.md#$a, and GUIDE.md has no heading with that slug"; fi
        ;;
    esac
  done
  readme_slugs=$(headings "$1" | cut -f2)
  address_anchors "$2" readme | while IFS= read -r a; do
    case $a in
      readme) continue ;;
      telegram) if [ "$mode" = testonly ]; then continue; fi ;;
    esac
    if ! printf '%s\n' "$readme_slugs" | grep -qxF -- "$a"; then echo "product-links: the code names the README address '#$a', and the README has no heading with that slug"; fi
  done
  address_anchors "$2" guide | while IFS= read -r a; do
    if [ "$a" = telegram ] && [ "$mode" = testonly ]; then continue; fi
    if ! printf '%s\n' "$guide_slugs" | grep -qxF -- "$a"; then echo "product-links: the code names the guide address 'GUIDE.md#$a', and GUIDE.md has no heading with that slug"; fi
  done
}

# readme-links (Design Notes 8 and 9): chk_readme_links <readme> <guide>: both files are checked.
# Any edit to the ALLOWED_HOSTS line below must update the no-outward allowance in release/checklist.sh in the same commit.
ALLOWED_HOSTS='localhost demo.ocutalon.com youtu.be github.com/jbrandtmse/OcuTalon github.com/bmad-code-org claude.com console.anthropic.com docs.anthropic.com evaluation.intersystems.com docs.intersystems.com www.intersystems.com ideas.intersystems.com docs.docker.com learn.microsoft.com community.intersystems.com openexchange.intersystems.com mail.google.com'
URL_RE='https?://[^][:space:])>"<`]+'
# url_allowed <url> [extra hosts]: the allow-list, plus the extra hosts (space separated) when given.
url_allowed() {
  local rest=${1#*://} host entry
  case $rest in */../* | */..) return 1 ;; esac
  host=${rest%%[/?#]*}
  host=${host##*@}
  host=${host%%:*}
  for entry in $ALLOWED_HOSTS ${2:-}; do
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
  local f own rs gs dup he hit n url extra
  rs=$(headings "$1" | cut -f2)
  gs=$(headings "$2" | cut -f2)
  for f in "$1" "$2"; do
    if [ "$f" = "$1" ]; then own=$rs; else own=$gs; fi
    he=$(header_end "$f")
    dup=$(printf '%s\n' "$own" | sort | uniq -d)
    if [ -n "$dup" ]; then printf '%s\n' "$dup" | sed "s|^|readme-links: $f: two headings have the slug |"; fi
    # The targets include header_images, so the header logo, whichever form its src takes, must be a file the tree lists. A link to a
    # heading names the file it lands in: a #x its own, a README.md#x or this repository's #x address the README's, a GUIDE.md address
    # the guide's. The README links the guide only by its absolute address.
    { grep -oE '\]\([^)]*\)' "$f" | sed 's/^](//; s/)$//'; grep -oE '(href|src)="[^"]*"' "$f" | sed 's/^[a-z]*="//; s/"$//'; header_images "$f"; } | while IFS= read -r target; do
      case $target in
        '#'*)
          if ! printf '%s\n' "$own" | grep -qxF -- "${target:1}"; then echo "readme-links: $f: the link ($target) reaches no heading"; fi
          ;;
        "$GUIDE_URL" | "$GUIDE_URL#"*)
          if [ "$target" != "$GUIDE_URL" ] && ! printf '%s\n' "$gs" | grep -qxF -- "${target#"$GUIDE_URL#"}"; then echo "readme-links: $f: the link ($target) reaches no heading of $2"; fi
          ;;
        https://github.com/jbrandtmse/OcuTalon#* | https://github.com/jbrandtmse/OcuTalon/blob/main/README.md#*)
          if ! printf '%s\n' "$rs" | grep -qxF -- "${target#*#}"; then echo "readme-links: $f: the link ($target) reaches no heading of $1"; fi
          ;;
        http://* | https://*) ;;
        *://* | mailto:*) echo "readme-links: $f: the link ($target) is not an http or https address" ;;
        GUIDE.md | GUIDE.md'#'*)
          if [ "$f" = "$1" ]; then
            echo "readme-links: $f: the link ($target) is relative; the README links the guide only by $GUIDE_URL"
          elif [ "$target" != "$2" ] && ! printf '%s\n' "$gs" | grep -qxF -- "${target#*#}"; then
            echo "readme-links: $f: the link ($target) reaches no heading"
          fi
          ;;
        README.md | README.md'#'*)
          if [ "$target" != "$1" ] && ! printf '%s\n' "$rs" | grep -qxF -- "${target#*#}"; then echo "readme-links: $f: the link ($target) reaches no heading of $1"; fi
          ;;
        *)
          path=${target%%[#?]*}
          if [ -z "$path" ] || [ -z "$(scan_files "${path%/}" | head -n 1)" ]; then echo "readme-links: $f: the link ($target) reaches no file or folder of the repository"; fi
          ;;
      esac
    done
    # The header lines (up to header_end) may also use HEADER_IMAGE_HOSTS; every other line is checked against the allow-list alone.
    grep -noE "$URL_RE" "$f" | sed 's/[.,;:]*$//' | sort -u | while IFS= read -r hit; do
      n=${hit%%:*}
      url=${hit#*:}
      extra=""
      if [ "$n" -le "$he" ]; then extra=$HEADER_IMAGE_HOSTS; fi
      if ! url_allowed "$url" "$extra"; then echo "readme-links: $f: the address $url is not on the allow-list"; fi
    done | sort -u
  done
}

# readme-anchors: the README anchors that the other Markdown files link.
REPO_URL=https://github.com/jbrandtmse/OcuTalon

# doc_files: from a list of paths on standard input, the Markdown files of the documentation set: every *.md and *.markdown file but
# the root README, the build records (_bmad/, _bmad-output/, .claude/) and the frozen release records (release/records/).
doc_files() {
  local f
  while IFS= read -r f; do
    case $f in
      "$README" | _bmad/* | _bmad-output/* | .claude/* | release/records/*) continue ;;
      *.md | *.markdown) printf '%s\n' "$f" ;;
    esac
  done
}

# readme_slugs <readme>: the anchor of each heading outside a code fence, as GitHub renders it: the slug of headings, and for a slug that
# an earlier heading holds, the slug with -1, then -2, and on.
readme_slugs() {
  headings "$1" | cut -f2 | awk '
    { s = $0; c = s; k = cnt[s]
      while (c in used) { k++; c = s "-" k }
      cnt[s] = k; used[c] = 1; print c }
  '
}

# md_links <file>: line and target of each link that GitHub renders outside a code fence and a code span, tab separated: an inline
# link or image [t](target), a reference definition [label]: target (a footnote [^label]: is text whose links count), an
# href="target", an autolink <https://...> and a bare https:// address. A link that more than one form matches, and a target repeated
# on a line, is listed once.
md_links() {
  awk '
    function nospans(s,   out, n, i, run, j, k, found) {
      out = ""; n = length(s); i = 1
      while (i <= n) {
        if (substr(s, i, 1) != "`") { out = out substr(s, i, 1); i++; continue }
        run = 0
        while (substr(s, i + run, 1) == "`") run++
        j = i + run; found = 0
        while (j <= n) {
          if (substr(s, j, 1) == "`") {
            k = 0
            while (substr(s, j + k, 1) == "`") k++
            if (k == run) { found = 1; break }
            j += k
          } else j++
        }
        if (found) { out = out " "; i = j + run } else { out = out substr(s, i, run); i += run }
      }
      return out
    }
    function emit(t) {
      if (t == "" || ((FNR SUBSEP t) in seen)) return
      seen[FNR SUBSEP t] = 1
      printf "%d\t%s\n", FNR, t
    }
    function first(p, kind) { if (p > 0 && (best == 0 || p < best)) { best = p; how = kind } }
    BEGIN { pun = "?!.,:;*_~\047\"" }
    {
      s = $0; sub(/^[ ]+/, "", s)
      c = substr(s, 1, 1)
      if ((c == "`" || c == "~") && substr(s, 1, 3) == c c c) {
        run = 0
        while (substr(s, run + 1, 1) == c) run++
        tail = substr(s, run + 1)
        if (fence == "" && !(c == "`" && index(tail, "`") > 0)) { fence = c; flen = run; next }
        if (fence == c && run >= flen && tail ~ /^[ \t]*$/) { fence = ""; next }
      }
      if (fence != "") next
      rest = nospans($0)
      if (rest ~ /^ *\[[^]^][^]]*\]:[ \t]*[^ \t]/) {
        t = rest; sub(/^ *\[[^]]+\]:[ \t]*/, "", t)
        if (substr(t, 1, 1) == "<") { sub(/^</, "", t); sub(/>.*/, "", t) } else sub(/[ \t].*/, "", t)
        emit(t); next
      }
      while (rest != "") {
        best = 0; how = ""
        first(index(rest, "]("), "inline")
        first(index(rest, "href=\""), "dq")
        first(index(rest, "href=\047"), "sq")
        first(index(rest, "https://"), "bare")
        first(index(rest, "http://"), "bare")
        if (best == 0) break
        if (how == "inline") {
          rest = substr(rest, best + 2); sub(/^[ \t]+/, "", rest)
          if (substr(rest, 1, 1) == "<") {
            q = index(rest, ">"); t = (q > 0) ? substr(rest, 2, q - 2) : ""; rest = (q > 0) ? substr(rest, q + 1) : substr(rest, 2)
          } else {
            depth = 0; n = length(rest)
            for (i = 1; i <= n; i++) {
              c = substr(rest, i, 1)
              if (c == " " || c == "\t") break
              if (c == "(") depth++
              else if (c == ")") { if (depth == 0) break; depth-- }
            }
            t = substr(rest, 1, i - 1); rest = substr(rest, i)
          }
          emit(t)
          q = index(rest, ")"); rest = (q > 0) ? substr(rest, q + 1) : ""
        } else if (how == "dq" || how == "sq") {
          rest = substr(rest, best + 6)
          q = index(rest, (how == "dq") ? "\"" : "\047")
          if (q == 0) break
          emit(substr(rest, 1, q - 1)); rest = substr(rest, q + 1)
        } else {
          rest = substr(rest, best); n = length(rest)
          for (i = 1; i <= n; i++) {
            c = substr(rest, i, 1)
            if (c == " " || c == "\t" || c == "<" || c == ">" || c == "\"" || c == "]") break
          }
          t = substr(rest, 1, i - 1); rest = substr(rest, i)
          while (t != "") {
            c = substr(t, length(t), 1)
            if (index(pun, c) > 0) { t = substr(t, 1, length(t) - 1); continue }
            if (c == ")") {
              u = t; o = gsub(/\(/, "", u); u = t; cl = gsub(/\)/, "", u)
              if (cl > o) { t = substr(t, 1, length(t) - 1); continue }
            }
            break
          }
          emit(t)
        }
      }
    }
  ' "$1"
}

# readme_target <repository path of the linking file> <target without its ?query and #anchor>: what the target is when it resolves to a
# README.md: "readme" (the root file), "repo" (this repository's page, where #readme is also an anchor), "leaves" (a relative path out
# of the repository) or "other <path>" (another folder's README.md). Nothing for any other target.
readme_target() {
  local dir path=$2 r
  case $path in
    "$REPO_URL/blob/main/$README" | "$REPO_URL/blob/HEAD/$README") echo readme; return ;;
    "$REPO_URL" | "$REPO_URL/") echo repo; return ;;
    *:* | //*) return ;;
  esac
  if [ "${path##*/}" != "$README" ]; then return; fi
  dir=""
  case $path in
    /*) ;;
    *) case $1 in */*) dir=${1%/*} ;; esac ;;
  esac
  r=$(printf '%s/%s\n' "$dir" "$path" | awk -F/ '
    { n = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "" || $i == ".") continue
        if ($i == "..") { if (n == 0) { print "OUT"; exit } n--; continue }
        p[++n] = $i
      }
      out = ""
      for (i = 1; i <= n; i++) out = out (i > 1 ? "/" : "") p[i]
      print out }')
  case $r in
    OUT) echo leaves ;;
    "$README") echo readme ;;
    *) echo "other $r" ;;
  esac
}

# readme-anchors: chk_readme_anchors <readme> <list file> <guide>: the list holds one repository-path TAB file-to-read pair per line,
# the documentation set. Fails closed on a list without the guide or without a docs/ file, and on a README heading in a form that
# headings does not slug as GitHub does, or on a README code fence that headings does not read (tildes, four or more backticks,
# indented). Every link of the list's files that resolves to the README and names an anchor reaches a heading slug of the README
# (readme_slugs); on this repository's page #readme is live too.
chk_readme_anchors() {
  local slugs p f row lvl text h n t before frag res
  if ! cut -f1 "$2" | grep -qxF -- "$3"; then echo "readme-anchors: the documentation set holds no $3"; fi
  if ! cut -f1 "$2" | grep -qE '^docs/.*\.(md|markdown)$'; then echo "readme-anchors: the documentation set holds no docs/*.md file"; fi
  slugs=$(readme_slugs "$1")
  grep -nE '^ *(~~~|````)|^ +```' "$1" | cut -d: -f1 | while IFS= read -r n; do
    echo "readme-anchors: $README:$n: a code fence in a form this check does not read as GitHub does"
  done
  headings "$1" | while IFS= read -r row; do
    lvl=${row%%$'\t'*}
    text=${row#*$'\t'}
    text=${text#*$'\t'}
    if [ "$lvl" -gt 6 ] || printf '%s' "$text" | grep -Eq '\]\(|\]\[|<|&[A-Za-z0-9#]+;|(^|[[:space:]])_|_($|[[:space:]])|:[a-z0-9_+-]+:|(^|[[:space:]])#+$|^[[:space:]]|[[:space:]]$'; then
      h=$(printf '%*s' "$lvl" '' | tr ' ' '#')
      n=$(grep -nxF -- "$h $text" "$1" | head -n 1 | cut -d: -f1)
      echo "readme-anchors: $README:$n: the heading '$text' is not in a form this check slugs as GitHub does"
    fi
  done
  while IFS=$'\t' read -r p f; do
    [ -n "$p" ] || continue
    md_links "$f" | while IFS=$'\t' read -r n t; do
      case $t in *'#'*) ;; *) continue ;; esac
      before=${t%%#*}
      before=${before%%\?*}
      frag=${t#*#}
      res=$(readme_target "$p" "$before")
      case $res in
        '') continue ;;
        leaves)
          echo "readme-anchors: $p:$n: the link ($t) leaves the repository"
          continue
          ;;
        "other "*)
          if ! in_tree "${res#other }" 2>/dev/null; then echo "readme-anchors: $p:$n: the link ($t) names ${res#other }, which is not a file of the tree"; fi
          continue
          ;;
      esac
      if [ -n "$frag" ]; then
        if printf '%s\n' "$slugs" | grep -qxF -- "$frag"; then continue; fi
        if [ "$res" = repo ] && [ "$frag" = readme ]; then continue; fi
      fi
      echo "readme-anchors: $p:$n: the link ($t) names '#$frag', and $README has no heading with that slug"
    done
  done < "$2"
}

# word-cap: chk_word_cap <readme>: wc -w at most WORD_CAP.
chk_word_cap() {
  local n
  n=$(wc -w < "$1")
  n=$((n + 0))
  if [ "$n" -gt "$WORD_CAP" ]; then echo "word-cap: $1 has $n words, at most $WORD_CAP"; fi
}

# guide: chk_guide <readme> <guide>: the guide's title, its H2 sections in order, the Planner-ruled line of its "Tests and CI", and the
# README's ruled pointer and "More" paragraph, each once, the paragraph right under its heading and linking the guide and each of its
# H2 sections.
chk_guide() {
  local n at h2s t slug para
  if [ "$(sed -n '1p' "$2")" != "$GUIDE_TITLE" ]; then echo "guide: line 1 of $2 is not exactly '$GUIDE_TITLE'"; fi
  h2s=$(headings "$2" | awk -F'\t' '$1 == 2 { print $3 }')
  if [ "$h2s" != "$GUIDE_H2" ]; then echo "guide: the H2 sections of $2 are not exactly, in this order: $(printf '%s' "$GUIDE_H2" | tr '\n' ',' | sed 's/,/, /g')"; fi
  n=$(grep -cxF -- "$GUIDE_CI_LINE" "$2")
  if [ "$n" -ne 1 ]; then echo "guide: $2 holds the ruled line of Tests and CI ('... the check of the README. ...') $n times, not once"; fi
  n=$(grep -cxF -- "$POINTER" "$1")
  if [ "$n" -ne 1 ]; then echo "guide: the ruled pointer is in $1 $n times, not once"; fi
  n=$(grep -cxF -- "$MORE_HEAD" "$1")
  if [ "$n" -ne 1 ]; then echo "guide: the heading '$MORE_HEAD' is in $1 $n times, not once"; fi
  n=$(grep -cxF -- "$MORE" "$1")
  if [ "$n" -ne 1 ]; then echo "guide: the ruled More paragraph is in $1 $n times, not once"; fi
  at=$(grep -nxF -m 1 -- "$MORE_HEAD" "$1" | cut -d: -f1)
  if [ -n "$at" ]; then
    para=$(sed -n "$((at + 2))p" "$1")
    if [ -n "$(sed -n "$((at + 1))p" "$1" | tr -d ' \t')" ] || [ "$para" != "$MORE" ]; then echo "guide: the More paragraph is not right under its heading, after an empty line"; fi
    if ! printf '%s\n' "$para" | grep -qF -e "]($GUIDE_URL)"; then echo "guide: the More paragraph does not link $GUIDE_URL"; fi
    headings "$2" | awk -F'\t' '$1 == 2 { print $2 " " $3 }' | while read -r slug t; do
      if ! printf '%s\n' "$para" | grep -qF -e "]($GUIDE_URL#$slug)"; then echo "guide: the More paragraph does not link the guide's section '$t'"; fi
    done
  fi
}

# --- the rules ---

rule_top() {
  rule_begin top "$README" || return
  st 'a line before the first H2 section' 1 "$README" 'NR == 1 { print; print "A stray line."; next } { print }' chk_top
  st 'the bare title back as the first line' 1 "$README" 'NR == 1 { print "# OcuTalon"; next } { print }' chk_top
  st 'the header replaced by the bare title' 1 "$README" 'NR == 1 { print "# OcuTalon"; next } NR <= '"$HEADER_LINES"' { next } { print }' chk_top
  st 'a stray line between the header and the opening paragraph' 1 "$README" 'NR == '"$HEADER_LINES"' { print; print "A stray line."; next } { print }' chk_top
  st 'a header badge from another host' 1 "$README" 'NR <= '"$HEADER_LINES"' && !done && /img\.shields\.io/ { sub(/img\.shields\.io/, "badgen.net"); done = 1 } { print }' chk_top
  st 'the tagline changed' 1 "$README" 'NR == 2 { sub(/every decision/, "each decision") } { print }' chk_top
  st 'a header logo with a different src' 1 "$README" 'NR == 1 { sub(/src="[^"]*"/, "src=\"https://example.org/logo.png\"") } { print }' chk_top
  st 'the first two sections swapped' 1 "$README" '/^## What.s interesting$/ { print "## Try it in two minutes"; next } /^## Try it in two minutes$/ { print "## What'"'"'s interesting"; next } { print }' chk_top
  st 'the opening paragraph changed' 1 "$README" '/^Your integrations already/ { sub(/fifty/, "fifteen") } { print }' chk_top
  st 'the opening paragraph removed' 1 "$README" '!/^Your integrations already/' chk_top
  st 'the opening paragraph twice' 1 "$README" '{ print } /^Or watch the 35-second teaser: / { print ""; print o } /^Your integrations already/ { o = $0 }' chk_top
  st 'the opening and the teaser swapped' 1 "$README" '/^Your integrations already/ { o = $0; next } /^Or watch the 35-second teaser: / { print; print ""; print o; next } { print }' chk_top
  st 'Credits and licences moved above Contest checklist' 1 "$README" '/^## Contest checklist$/ { print "## Credits and licences"; next } /^## Credits and licences$/ { print "## Contest checklist"; next } { print }' chk_top
  st 'the Contest checklist section renamed' 1 "$README" '/^## Contest checklist$/ { print "## Checklist"; next } { print }' chk_top
  st 'a moved section back in the README' 1 "$README" '/^## More$/ { print "## What you can use it for"; print ""; print "Back."; print "" } { print }' chk_top
  st 'a GUIDE badge URL back to a README anchor' 1 "$README" 'NR <= '"$HEADER_LINES"' && /GUIDE\.md#install-it-with-ipm/ { sub(/https:[^"]*GUIDE\.md#/, "#") } { print }' chk_top
  st 'a GUIDE badge URL with another anchor' 1 "$README" 'NR <= '"$HEADER_LINES"' && /GUIDE\.md#start-it-with-the-install-script/ { sub(/#start-it-with-the-install-script/, "#sign-in") } { print }' chk_top
  st 'a line between the teaser and the first H2 section' 1 "$README" '{ print } /^Or watch the 35-second teaser: / { print ""; print "A stray line." }' chk_top
  st 'the hero image line removed' 1 "$README" '!/^!\[The OcuTalon page on the online demo/' chk_top
  st 'a second image line' 1 "$README" '{ print } /^!\[The OcuTalon page on the online demo/ { print ""; print "![Second.](docs/images/page-incident.png)" }' chk_top
  st 'a second image on the hero line' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { $0 = $0 " ![Second.](docs/images/page-incident.png)" } { print }' chk_top
  st 'text after the hero image' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { $0 = $0 " on the demo (live)" } { print }' chk_top
  st 'the hero above the teaser' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { next } /^Or watch the 35-second teaser: / { print "![Hero.](docs/images/page-incident.png)"; print "" } { print }' chk_top
  st 'the hero moved under the first H2 section' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { hero = $0; next } { print } /^## Try it in two minutes$/ { print ""; print hero }' chk_top
  st 'the More section removed' 1 "$README" '!/^## More$/' chk_top
  st 'the More section renamed' 1 "$README" '/^## More$/ { print "## Further reading"; next } { print }' chk_top
  st 'More swapped with Contest checklist' 1 "$README" '/^## More$/ { print "## Contest checklist"; next } /^## Contest checklist$/ { print "## More"; next } { print }' chk_top
  st 'More swapped with Measured' 1 "$README" '/^## More$/ { print "## Measured"; next } /^## Measured$/ { print "## More"; next } { print }' chk_top
  st 'a required section removed' 1 "$README" '!/^## Credits and licences$/' chk_top
  st 'the Contest task section back' 1 "$README" '{ print } END { print ""; print "## Contest task"; print "" }' chk_top
  st 'the Contest task table header back' 1 "$README" '{ print } /^## Measured$/ { print ""; print "| Contest task or criterion | x | y |" }' chk_top
  st 'the Measured section removed' 1 "$README" '!/^## Measured$/' chk_top
  st 'the Measured section above What'"'"'s interesting' 1 "$README" '/^## Measured$/ { print "## What'"'"'s interesting"; next } /^## What.s interesting$/ { print "## Measured"; next } { print }' chk_top
  st 'the Measured section below More' 1 "$README" '/^## Measured$/ { print "## More"; next } /^## More$/ { print "## Measured"; next } { print }' chk_top
  st 'the Measured heading one level down' 1 "$README" '/^## Measured$/ { print "### Measured"; next } { print }' chk_top
  st 'the full-video line removed' 1 "$README" '!/^Watch the full video /' chk_top
  st 'the full-video line below the teaser' 1 "$README" '/^Watch the full video / { fv = $0; next } { print } /^Or watch the 35-second teaser: / { print ""; print fv }' chk_top
  st 'the full-video line reworded' 1 "$README" '/^Watch the full video / { sub(/full video/, "long video") } { print }' chk_top
  st 'a stray line between the full-video line and the teaser' 1 "$README" '{ print } /^Watch the full video / { print ""; print "A stray line." }' chk_top
  st 'the full-video line twice' 1 "$README" '{ print } /^Watch the full video / { print ""; print $0 }' chk_top
  st 'the incident section heading removed' 1 "$README" '!/^## One incident, end to end$/' chk_top
  st 'the incident section renamed' 1 "$README" '/^## One incident, end to end$/ { print "## One incident"; next } { print }' chk_top
  st 'the incident section below What'"'"'s interesting' 1 "$README" '/^## One incident, end to end$/ { print "## What'"'"'s interesting"; next } /^## What.s interesting$/ { print "## One incident, end to end"; next } { print }' chk_top
  st 'the teaser line removed' 1 "$README" '!/^Or watch the 35-second teaser: /' chk_top
  st 'the teaser line twice' 1 "$README" '{ print } /^Or watch the 35-second teaser: / { print ""; print $0 }' chk_top
  st 'the hero above the full-video line' 1 "$README" '/^!\[The OcuTalon page on the online demo/ { next } /^Watch the full video / { print "![Hero.](docs/images/page-incident.png)"; print "" } { print }' chk_top
  st 'the Try it section removed' 1 "$README" '!/^## Try it in two minutes$/' chk_top
  st 'the Try it section and the incident section swapped' 1 "$README" '/^## Try it in two minutes$/ { print "## One incident, end to end"; next } /^## One incident, end to end$/ { print "## Try it in two minutes"; next } { print }' chk_top
  finish top 'the header block (its GUIDE badge URLs word for word), the opening paragraph, the full-video line, the teaser and the hero image, then the seven H2 sections in order' chk_top
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
  st 'the separate build 109 step back' 1 "$README" '/^2\. / { print $0 " With build 109, follow [Start it with build 109](#start-it-with-build-109) instead."; next } { print }' chk_try_it
  st 'text added to step 2' 1 "$README" '/^2\. / { print $0 " With build 109, follow [Start it by hand](#start-it-by-hand) instead."; next } { print }' chk_try_it
  st 'a fifth step' 1 "$README" '/^4\. / { print; print "5. One more." ; next } { print }' chk_try_it
  st_move 'step 2 moved out of the section' "$H_TRY" '2. ' chk_try_it
  st 'the phrase away from the demo link' 1 "$README" "{ i = index(\$0, \"$DEMO_PHRASE\"); if (i && index(\$0, \"https://demo.ocutalon.com\")) { print substr(\$0, 1, i - 1) \"zz\" substr(\$0, i + length(\"$DEMO_PHRASE\")); print \"\"; print \"$DEMO_PHRASE\"; next } print }" chk_try_it
  finish try-it 'the online demo comes first, then four numbered steps for the local path' chk_try_it
}

rule_interesting() {
  local n other
  rule_begin interesting "$README" || return
  st_facts chk_interesting "$INT_FACTS"
  # The image's alt text and the bullets below the H3 also hold these two facts; the section's own text must hold them itself.
  st 'Visual Trace only in the image and below the H3' 1 "$README" '/^## / { s = ($0 ~ /^## What.s interesting$/) } /^### / { s = 0 } s && index($0, "![") != 1 { gsub(/Visual Trace/, "ZZ") } { print }' chk_interesting
  st 'dry run only in the image and below the H3' 1 "$README" '/^## / { s = ($0 ~ /^## What.s interesting$/) } /^### / { s = 0 } s && index($0, "![") != 1 { gsub(/dry run/, "ZZ") } { print }' chk_interesting
  n=$(int_own "$README" | grep -v '^!\[' | wc -w)
  n=$((n + 0))
  other=$(image_links "$README" | cut -f3 | grep -vxF -- "$INT_IMAGE" | head -n 1)
  st 'the image line dropped from the section' 1 "$README" '/^## / { s = ($0 ~ /^## What.s interesting$/) } s && index($0, "![") == 1 { next } { print }' chk_interesting
  st 'its image line pointing at another image' 1 "$README" '/^## / { s = ($0 ~ /^## What.s interesting$/) } s && index($0, "![") == 1 { sub(/\]\([^)]*\)/, "]('"$other"')") } { print }' chk_interesting
  st 'a second image line with another image' 1 "$README" '{ print } /^## / { s = ($0 ~ /^## What.s interesting$/) } s && index($0, "![") == 1 && !done { print ""; print "![Another.]('"$other"')"; done = 1 }' chk_interesting
  if [ "$n" -le 120 ]; then
    # The limit itself: the section padded to exactly 121 words is flagged, and padded to exactly 120 it is not.
    st 'exactly 121 words' 1 "$README" "{ print } /^## What.s interesting\$/ { print \"\"; for (i = $n; i < 121; i++) printf \"w \"; print \"\" }" chk_interesting
    if ! mutate "$README" "{ print } /^## What.s interesting\$/ { print \"\"; for (i = $n; i < 120; i++) printf \"w \"; print \"\" }"; then
      st_note 'exactly 120 words: the edit changed nothing'
    elif [ -n "$(chk_interesting "$tmp/m")" ]; then
      st_note 'exactly 120 words is flagged'
    fi
  fi
  st 'a second H3 in the section' 1 "$README" '{ print } /^### New since 1.0.0$/ { print ""; print "### Another" }' chk_interesting
  st 'the H3 renamed' 1 "$README" '/^### New since 1.0.0$/ { print "### Since 1.0.0"; next } { print }' chk_interesting
  st 'the H3 removed' 1 "$README" '!/^### New since 1.0.0$/' chk_interesting
  # Words after the first H3 are not the section's own text: 200 more there are not flagged.
  if ! mutate "$README" '{ print } /^### New since 1.0.0$/ { print ""; for (i = 0; i < 200; i++) printf "w "; print "" }'; then
    st_note 'words after the H3: the edit changed nothing'
  elif [ -n "$(chk_interesting "$tmp/m")" ]; then
    st_note 'words after the first H3 are flagged'
  fi
  finish interesting 'at most 120 words before its first H3, and it names the workflow, Visual Trace, the AI Hub agent, the dry run and the audit log' chk_interesting
}

rule_measured() {
  rule_begin measured "$README" || return
  st 'the heading removed' 1 "$README" '!/^## Measured$/' chk_measured
  st 'the heading renamed' 1 "$README" '/^## Measured$/ { print "## Measurements"; next } { print }' chk_measured
  st_facts chk_measured "$MEAS_LABELS"
  st_move 'a row moved out of the section' "$H_MEAS" '| Routine attention decisions right |' chk_measured
  st 'a row label not in the first cell' 1 "$README" '{ sub(/^\| Cost of one attention decision \| /, "| Cost | Cost of one attention decision | ") } { print }' chk_measured
  st 'a row label extended in its cell' 1 "$README" '{ sub(/^\| Routine attention decisions right \|/, "| Routine attention decisions right today |") } { print }' chk_measured
  st 'a row removed whose label the comparison table repeats' 1 "$README" '/^## / { m = ($0 == "## Measured") } /^### / { m = 0 } m && /^\| Cost of one attention decision \|/ { next } { print }' chk_measured
  # A changed number, intro line or result is not flagged: the rule pins the heading and the row labels, not the numbers or wording.
  mutate "$README" '/^\| Routine attention decisions right \|/ { n += sub(/[0-9]+ of 24/, "20 of 24") } /^From the real-model evaluation of release/ { $0 = "From the evaluations."; n++ } /^\| Prompt-injection attempts/ { n += sub(/ 0 /, " 1 ") } { print } END { exit (n != 3) }' || st_note 'an edit of the numbers or the intro did not apply'
  if [ -n "$(chk_measured "$tmp/m")" ]; then st_note 'a changed number, result or intro line is flagged'; fi
  finish measured 'Measured has a table row for each of its eight row labels, word for word' chk_measured
}

rule_comparison() {
  rule_begin comparison "$README" "$GUIDE" || return
  st 'the added sentence removed' 1 "$README" '{ sub(/ Rules written for these exact cases could score higher; this measures what the model adds to OcuTalon itself\./, "") } { print }' chk_comparison
  st 'the added sentence changed' 1 "$README" '{ sub(/could score higher/, "will score higher") } { print }' chk_comparison
  st 'the heading moved after More' 1 "$README" '/^### With the agent and with fixed rules only$/ { hold = 1 } /^## More$/ { hold = 0 } hold { held = held $0 ORS; next } { print } END { printf "%s%s", ORS, held }' chk_comparison
  st 'the heading renamed' 1 "$README" '/^### With the agent and with fixed rules only$/ { print "### With the agent and fixed rules"; next } { print }' chk_comparison
  st 'a second H3 in Measured' 1 "$README" '/^## More$/ { print "### Another"; print "" } { print }' chk_comparison
  st 'the money line after the heading' 1 "$README" '/^Where the money goes and how to cap it/ { held = $0; next } /^## More$/ { print held; print "" } { print }' chk_comparison
  st 'a paragraph between the money line and the heading' 1 "$README" '/^### With the agent and with fixed rules only$/ { print "A stray paragraph."; print "" } { print }' chk_comparison
  st 'a word of the paragraph changed' 1 "$README" '{ sub(/own fallback/, "own default") } { print }' chk_comparison
  st 'the commit link changed' 1 "$README" '{ sub(/commit\/6af31dab/, "commit/6af31dac") } { print }' chk_comparison
  st 'the date not written as Month D' 1 "$README" '{ sub(/no key on November 12 on/, "no key on 2026-11-12 on") } { print }' chk_comparison
  st 'a count that is not a number' 1 "$README" '{ sub(/): 24 routine items/, "): many routine items") } { print }' chk_comparison
  st 'a row label reworded' 1 "$README" '{ sub(/^\| Held-out cases right /, "| Held-out cases correct ") } { print }' chk_comparison
  st 'two row labels swapped' 1 "$README" '/^\| Items that needed you now but/ { held = $0; next } /^\| Unsafe outcomes \| measured/ { print; print held; next } { print }' chk_comparison
  st 'a row removed' 1 "$README" '!/^\| Largest model request \|/' chk_comparison
  st 'an empty fixed-rules cell' 1 "$README" '/^\| Unsafe outcomes \|/ { sub(/ \| 0 \|$/, " |  |") } { print }' chk_comparison
  st 'an empty agent cell' 1 "$README" '/^\| Unsafe outcomes \|/ { split($0, c, / \| /); $0 = c[1] " |  | " c[3] } { print }' chk_comparison
  st 'the header row reworded' 1 "$README" '{ sub(/\| Fixed rules only \|$/, "| Rules only |") } { print }' chk_comparison
  st 'the separator row changed' 1 "$README" '{ sub(/^\| --- \| --- \| --- \|$/, "| --- | --- |") } { print }' chk_comparison
  st 'the empty line before the sentence replaced' 1 "$README" '{ if (p ~ /^\| Largest model request \|/ && $0 == "") $0 = "x"; p = $0; print }' chk_comparison
  st 'a row of four cells' 1 "$README" '/^\| Unsafe outcomes \|/ { $0 = $0 " x |" } { print }' chk_comparison
  st 'the sentence under the table changed' 1 "$README" '{ sub(/^An unsafe outcome is a change/, "An unsafe outcome is any change") } { print }' chk_comparison
  st 'a filled agent routine cell that differs from the main table' 1 "$README" '/^\| Routine attention decisions right \|/ { if (match($0, /[0-9]+ of [0-9]+/)) { split(substr($0, RSTART, RLENGTH), v, " of "); off = (v[1] + 1) " of " v[2] } } /^\| Routine attention decisions right \(main set\) \|/ { split($0, c, / \| /); $0 = c[1] " | " off " | " c[3] } { print }' chk_comparison
  st 'the pointer removed from the guide' 2 "$GUIDE" 'index($0, "**What changes without the agent?**") != 1' chk_comparison
  st 'the pointer anchor changed' 2 "$GUIDE" '{ sub(/#with-the-agent-and-with-fixed-rules-only/, "#fixed-rules-only") } { print }' chk_comparison
  st 'a paragraph between the pointer and the model paragraph' 2 "$GUIDE" '{ print } index($0, "**What changes without the agent?**") == 1 { print ""; print "A stray paragraph." }' chk_comparison
  st 'the worked-out sentence restored in the guide' 2 "$GUIDE" 'index($0, "**What changes without the agent?**") == 1 { $0 = "**What changes without the agent?** Worked out from the expected answers of the recorded evaluation set." } { print }' chk_comparison
  st_append 'the worked-out sentence restored in the README' 'Worked out from the expected answers of the recorded evaluation set.' chk_comparison
  # A filled agent routine cell that agrees with the main table's routine row is not flagged (the cell as it stands is the real-tree check).
  if ! awk '/^\| Routine attention decisions right \|/ { if (match($0, /[0-9]+ of [0-9]+/)) same = substr($0, RSTART, RLENGTH) } /^\| Routine attention decisions right \(main set\) \|/ { split($0, c, / \| /); $0 = c[1] " | " same " | " c[3] } { print }' "$README" > "$tmp/m" || ! grep -q '^| Routine attention decisions right (main set) | [0-9][0-9]* of [0-9][0-9]* | ' "$tmp/m"; then
    st_note 'the agreeing routine cell did not apply'
  elif [ -n "$(chk_comparison "$tmp/m" "$S2" "$S3" "$S4")" ]; then
    st_note 'a filled agent routine cell that agrees with the main table is flagged'
  fi
  finish comparison 'Measured ends with the ruled comparison of the agent and the fixed rules (paragraph, table and sentence), the guide points to it, and the agent column agrees with the main table once filled' chk_comparison
}

rule_use_cases() {
  rule_begin use-cases "$GUIDE" || return
  st 'item 1 changed' 1 "$GUIDE" '/^- \*\*The partner feed/ { sub(/2am/, "3am") } { print }' chk_use_cases
  st 'item 2 changed' 1 "$GUIDE" '/^- \*\*"Only tell me/ { sub(/never gives/, "rarely gives") } { print }' chk_use_cases
  st 'item 1 removed' 1 "$GUIDE" '!/^- \*\*The partner feed/' chk_use_cases
  st 'item 2 removed' 1 "$GUIDE" '!/^- \*\*"Only tell me/' chk_use_cases
  st 'the items swapped' 1 "$GUIDE" '/^- \*\*The partner feed/ { held = $0; next } { print } /^- \*\*"Only tell me/ { print held }' chk_use_cases
  st 'a fourth item' 1 "$GUIDE" '{ print } /^- \*\*\[An AI decision step/ { print "- **A fourth item.** More." }' chk_use_cases
  st 'the production-stopped sentence appended to item 2' 1 "$GUIDE" '/^- \*\*"Only tell me/ { $0 = $0 " It also tells you once when a production stops or one of its items is disabled." } { print }' chk_use_cases
  st 'the production-stopped sentence on a line of its own' 1 "$GUIDE" '{ print } /^- \*\*"Only tell me/ { print "It also tells you once when a production stops or one of its items is disabled." }' chk_use_cases
  st 'the audit item without its link' 1 "$GUIDE" '/^- \*\*\[An AI decision step/ { $0 = "- **An AI decision step you can audit, in your own production.**" } { print }' chk_use_cases
  st 'the audit item linking another file' 1 "$GUIDE" '/^- \*\*\[An AI decision step/ { sub(/docs\/bridge-guide\.md/, "docs/install-ipm.md") } { print }' chk_use_cases
  st 'the audit item removed' 1 "$GUIDE" '!/^- \*\*\[An AI decision step/' chk_use_cases
  st 'the section heading removed' 1 "$GUIDE" '!/^## What you can use it for$/' chk_use_cases
  finish use-cases 'What you can use it for holds exactly the three items, word for word' chk_use_cases
}

rule_how_you_talk() {
  rule_begin how-you-talk "$GUIDE" || return
  st 'the heading removed' 1 "$GUIDE" '!/^## How you talk to it$/' chk_how_you_talk
  st_facts chk_how_you_talk "$TALK_FACTS"
  st_move 'the Demo mode paragraph moved out of the section' "$H_TALK" 'Demo mode is on in the online demo' chk_how_you_talk
  st 'the table rows removed' 1 "$GUIDE" '/^## / { s = ($0 == "## How you talk to it") } s && /^\|/ { next } { print }' chk_how_you_talk
  st 'the table separator line removed' 1 "$GUIDE" '/^## / { s = ($0 == "## How you talk to it") } s && /^\| --- \|/ { next } { print }' chk_how_you_talk
  st 'the image line removed' 1 "$GUIDE" '/^## / { s = ($0 == "## How you talk to it") } s && /^!\[/ { next } { print }' chk_how_you_talk
  st 'Slack named in the section' 1 "$GUIDE" '{ print } /^## How you talk to it$/ { print ""; print "It also works in Slack." }' chk_how_you_talk
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
  local first first_g other target logo
  printf '%s\n' "$listing" > "$tmp/files.list"
  rule_begin images "$README" "$tmp/files.list" "$GUIDE" || return
  # The self-tests use each file's own first image link, so that no image file is named here.
  first=$(image_links "$README" | head -n 1 | cut -f3)
  first_g=$(image_links "$GUIDE" | head -n 1 | cut -f3)
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
  st 'the images of What OcuTalon does removed' 3 "$GUIDE" '/^## / { s = ($0 == "## What OcuTalon does") } s && /^  !\[/ { next } { print }' chk_images
  st 'the images of What OcuTalon does made reference-style' 3 "$GUIDE" '/^## / { s = ($0 == "## What OcuTalon does") } s && /^  !\[/ { sub(/\]\(/, "][") } { print }' chk_images
  st 'the last Break the feed image moved under the Chat bullet (one left under Break the feed)' 3 "$GUIDE" '/^## / { s = ($0 == "## What OcuTalon does") } /^- \*\*/ { b = (index($0, "- **Break the feed.**") == 1) } s && b && /^  !\[/ { last = $0 } { line[NR] = $0 } END { for (i = 1; i <= NR; i++) { if (line[i] == last) continue; print line[i]; if (index(line[i], "- **Chat on a live page.**") == 1) { print ""; print last } } }' chk_images
  st 'no empty line between the text and an image line' 1 "$README" '{ L[NR] = $0 } END { for (i = 1; i <= NR; i++) { if (L[i] == "" && index(L[i + 1], "![The OcuTalon page on the online demo") == 1) continue; print L[i] } }' chk_images
  st 'the images under the Break the feed bullet removed' 3 "$GUIDE" '/^## / { s = ($0 == "## What OcuTalon does") } /^- \*\*/ { b = (index($0, "- **Break the feed.**") == 1) } s && b && /^  !\[/ { next } { print }' chk_images
  st 'the first image file dropped from the list' 2 "$tmp/files.list" '$0 != "'"$first"'"' chk_images
  st 'the guide first image file dropped from the list' 2 "$tmp/files.list" '$0 != "'"$first_g"'"' chk_images
  st 'an empty alt text in the guide' 3 "$GUIDE" "$(set_alt "$first_g" '')" chk_images
  st 'a file the tree does not list, in the guide' 3 "$GUIDE" "$(swap_target "$first_g" docs/images/zz-missing.png)" chk_images
  st 'a remote address in the guide' 3 "$GUIDE" "$(swap_target "$first_g" https://example.org/hero.png)" chk_images
  st 'no empty line between the text and an image line, in the guide' 3 "$GUIDE" '/^  !\[/ && !done { L = $0; done = 1; print "A stray line."; print L; next } { print }' chk_images
  # A linked file of exactly 300,000 bytes is flagged, and one byte less is not: the sizes are read from a root of the rule's own.
  mkdir -p "$tmp/size/docs/images"
  { image_links "$README" | cut -f3; header_images "$README"; image_links "$GUIDE" | cut -f3; } | sort -u | while IFS= read -r target; do
    case $target in docs/images/*) head -c 10 /dev/zero > "$tmp/size/$target" ;; esac
  done
  head -c 299999 /dev/zero > "$tmp/size/$first"
  if [ -n "$(chk_images "$README" "$tmp/files.list" "$GUIDE" "$tmp/size")" ]; then st_note 'a linked file of 299,999 bytes is flagged'; fi
  head -c 300000 /dev/zero > "$tmp/size/$first"
  if [ -z "$(chk_images "$README" "$tmp/files.list" "$GUIDE" "$tmp/size")" ]; then st_note 'a linked file of exactly 300,000 bytes is not flagged'; fi
  # The header's logo is read too: at exactly 300,000 bytes it is flagged (the first image goes back to 10 bytes, so that it is the only one).
  # A header that names no docs/images logo gives the check nothing to flag, so it counts as not flagged.
  head -c 10 /dev/zero > "$tmp/size/$first"
  logo=$(header_images "$README" | head -n 1)
  if [ -n "$logo" ]; then head -c 300000 /dev/zero > "$tmp/size/$logo"; fi
  if [ -z "$logo" ] || [ -z "$(chk_images "$README" "$tmp/files.list" "$GUIDE" "$tmp/size")" ]; then st_note 'the header logo of exactly 300,000 bytes is not flagged'; fi
  # A newly listed and linked docs/images file is not flagged: the rule names no file.
  mkdir -p "$tmp/imgs"
  { cat "$tmp/files.list"; echo docs/images/zz-extra.png; } > "$tmp/imgs/extra.list"
  { cat "$README"; printf '\n![Extra.](docs/images/zz-extra.png)\n'; } > "$tmp/imgs/extra.md"
  if [ -n "$(chk_images "$tmp/imgs/extra.md" "$tmp/imgs/extra.list" "$GUIDE")" ]; then st_note 'a newly listed and linked docs/images file is flagged'; fi
  finish images 'every image link of the README and the guide has alt text and reaches a file of docs/images/ that the tree lists' chk_images
}

rule_once() {
  local first first_g
  rule_begin once "$README" "$GUIDE" || return
  first=$(image_links "$README" | head -n 1 | cut -f3)
  first_g=$(image_links "$GUIDE" | head -n 1 | cut -f3)
  # A repeated image is flagged: the first image line again, as a paragraph of its own at the end.
  st 'the first image shown twice' 1 "$README" '{ print } index($0, "]('"$first"')") > 0 && !done { held = $0; done = 1 } END { print ""; print held }' chk_once
  st 'the guide first image shown twice' 2 "$GUIDE" '{ print } index($0, "]('"$first_g"')") > 0 && !done { held = $0; done = 1 } END { print ""; print held }' chk_once
  # An image of one file shown again in the other is flagged too.
  st 'the README first image shown again in the guide' 2 "$GUIDE" '{ print } END { print ""; print "![Again.]('"$first"')" }' chk_once
  st 'the guide first image shown again in the README' 1 "$README" '{ print } END { print ""; print "![Again.]('"$first_g"')" }' chk_once
  # A new image named once is not flagged.
  mkdir -p "$tmp/once"
  { cat "$README"; printf '\n![Extra.](docs/images/zz-extra.png)\n'; } > "$tmp/once/extra.md"
  if [ -n "$(chk_once "$tmp/once/extra.md" "$GUIDE")" ]; then st_note 'a new image named once is flagged'; fi
  finish once 'each docs/images/ file is named at most once in the README and the guide together' chk_once
}

rule_video() {
  rule_begin video "$README" || return
  st 'the full-video line without the YouTube link' 1 "$README" '/^Watch the full video / { sub(/https:\/\/youtu\.be\/HIyCG5E6-JQ/, "https://example.org/v") } { print }' chk_video
  st 'the full-video line without the MP4 link' 1 "$README" '/^Watch the full video / { sub(/https:\/\/github\.com\/[^ ]*\.mp4/, "https://example.org/v.mp4") } { print }' chk_video
  st 'the MP4 of another release' 1 "$README" '/^Watch the full video / { sub(/download\/v1\.0\.6\//, "download/v1.0.5/") } { print }' chk_video
  st 'the full-video line removed' 1 "$README" '!/^Watch the full video /' chk_video
  st 'the full-video line twice' 1 "$README" '/^Watch the full video / { fv = $0 } { print } END { print ""; print fv }' chk_video
  st 'the link bar removed' 1 "$README" '!/^\[Online demo\]/' chk_video
  st 'the full-video entry removed from the link bar' 1 "$README" '/^\[Online demo\]/ { sub(/\[Video: one incident, traced \(3:04\)\]\([^)]*\) [^ ]+ /, "") } { print }' chk_video
  st 'the teaser entry removed from the link bar' 1 "$README" '/^\[Online demo\]/ { sub(/ [^ ]+ \[Video: the 35-second teaser\]\([^)]*\)/, "") } { print }' chk_video
  st 'the full-video entry after the teaser entry' 1 "$README" '/^\[Online demo\]/ { a = "[Video: one incident, traced (3:04)](https://youtu.be/HIyCG5E6-JQ)"; b = "[Video: the 35-second teaser](https://youtu.be/wycbyfnXFMU)"; i = index($0, a); j = index($0, b); if (i && j) $0 = substr($0, 1, i - 1) b substr($0, i + length(a), j - i - length(a)) a substr($0, j + length(b)) } { print }' chk_video
  st 'the full-video entry reworded' 1 "$README" '/^\[Online demo\]/ { sub(/one incident, traced/, "the incident") } { print }' chk_video
  st 'the full-video entry pointing at the teaser' 1 "$README" '/^\[Online demo\]/ { sub(/\(3:04\)\]\(https:\/\/youtu\.be\/HIyCG5E6-JQ\)/, "(3:04)](https://youtu.be/wycbyfnXFMU)") } { print }' chk_video
  st 'another entry between the two video entries' 1 "$README" '/^\[Online demo\]/ { sub(/\[Video: the 35-second teaser\]/, "[Releases](LICENSE) | [Video: the 35-second teaser]") } { print }' chk_video
  st 'the teaser address in the full-video line' 1 "$README" '/^Watch the full video / { $0 = $0 " and " "'"$TEASER_URL"'" } { print }' chk_video
  st 'the teaser address in the incident section' 1 "$README" '{ print } /^## One incident, end to end$/ { print ""; print "See '"$TEASER_URL"'." }' chk_video
  st_append 'the teaser address a third time' "See $TEASER_URL" chk_video
  st 'the teaser address in a reworded Video row' 1 "$README" 'index($0, "| Video |") == 1 { sub(/35-second teaser/, "short teaser") } { print }' chk_video
  st 'the teaser address in another checklist row' 1 "$README" '{ print } index($0, "| Online demo |") == 1 { print "| Teaser | '"$TEASER_URL"' |" }' chk_video
  finish video 'the full-video line holds the YouTube and MP4 links, the link bar holds the full video directly before the teaser, and the teaser address is only in those two places and the ruled Video row' chk_video
}

rule_checklist_video() {
  rule_begin checklist-video "$README" || return
  st 'the Video row removed' 1 "$README" 'index($0, "| Video |") != 1' chk_checklist_video
  st_move 'the Video row moved out of the section' "$H_CONTEST" '| Video |' chk_checklist_video
  st 'the Video row moved below Community idea' 1 "$README" 'index($0, "| Video |") == 1 { held = $0; next } { print } index($0, "| Community idea |") == 1 { print held }' chk_checklist_video
  st 'the Video row above Online demo' 1 "$README" 'index($0, "| Online demo |") == 1 { held = $0; next } { print } index($0, "| Video |") == 1 { print held }' chk_checklist_video
  st 'the Video row twice' 1 "$README" '{ print } index($0, "| Video |") == 1 { print }' chk_checklist_video
  st 'the Video row again in another section' 1 "$README" '{ print } index($0, "| Video |") == 1 { held = $0 } END { print ""; print held }' chk_checklist_video
  st 'the Video row reworded' 1 "$README" 'index($0, "| Video |") == 1 { sub(/approved from a phone/, "approved by phone") } { print }' chk_checklist_video
  st 'the Video row with a word added' 1 "$README" 'index($0, "| Video |") == 1 { sub(/ \|$/, " Watch it. |") } { print }' chk_checklist_video
  st 'the Video row with the MP4 of another release' 1 "$README" 'index($0, "| Video |") == 1 { sub(/download\/v1\.0\.6\//, "download/v1.0.5/") } { print }' chk_checklist_video
  st 'the Video row with the full video pointing at the teaser' 1 "$README" 'index($0, "| Video |") == 1 { sub(/traced\]\(https:\/\/youtu\.be\/HIyCG5E6-JQ\)/, "traced](https://youtu.be/wycbyfnXFMU)") } { print }' chk_checklist_video
  st 'the Online demo row removed' 1 "$README" 'index($0, "| Online demo |") != 1' chk_checklist_video
  st 'the section renamed' 1 "$README" '$0 == "## Contest checklist" { print "## Checklist"; next } { print }' chk_checklist_video
  st "the anchor's heading renamed" 1 "$README" '$0 == "## One incident, end to end" { print "## One incident"; next } { print }' chk_checklist_video
  st "the anchor's heading reworded with the same slug" 1 "$README" '$0 == "## One incident, end to end" { print "## One incident: end to end"; next } { print }' chk_checklist_video
  finish checklist-video 'the ruled Video row is right after Online demo in Contest checklist, once, and #one-incident-end-to-end reaches its heading' chk_checklist_video
}

rule_judges_usability() {
  rule_begin judges-usability "$README" || return
  st 'the first sentence reworded' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/in about two minutes/, "in about five minutes") } { print }' chk_judges_usability
  st 'the incident link removed' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/\[one incident, end to end\]\(#one-incident-end-to-end\)/, "one incident") } { print }' chk_judges_usability
  st 'the incident link to another heading' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/\(#one-incident-end-to-end\)/, "(#measured)") } { print }' chk_judges_usability
  st 'the full-video link changed' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/\[the full video\]\(https:\/\/youtu\.be\/HIyCG5E6-JQ\)/, "[the full video](https://youtu.be/wycbyfnXFMU)") } { print }' chk_judges_usability
  st 'the full-video length changed' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/shows it in 3:04\./, "shows it in 3 minutes.") } { print }' chk_judges_usability
  st 'the second sentence reworded' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/ Its More to try panel has /, " Its panel has ") } { print }' chk_judges_usability
  st 'the two sentences folded back into one' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/, and \[the full video\]\(https:\/\/youtu\.be\/HIyCG5E6-JQ\) shows it in 3:04\. Its More/, ", and its More") } { print }' chk_judges_usability
  st 'the count as a number' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/ has [a-z]+ more things/, " has 15 more things") } { print }' chk_judges_usability
  st 'the second sentence cut after the count word' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/ more things to try, fifteen of them on the online demo \(\[New since 1\.0\.0\]\([^)]*\)\)\./, " more things.") } { print }' chk_judges_usability
  st 'the online-demo count changed' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/, fifteen of them on the online demo/, ", fourteen of them on the online demo") } { print }' chk_judges_usability
  st 'the online-demo clause removed' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/, fifteen of them on the online demo/, "") } { print }' chk_judges_usability
  st 'the New since link back to the README heading' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/\(https:[^)]*GUIDE\.md#new-since-100\)/, "(#new-since-100)") } { print }' chk_judges_usability
  st 'the New since link to another guide section' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/GUIDE\.md#new-since-100\)/, "GUIDE.md#sign-in)") } { print }' chk_judges_usability
  st 'the New since link to the guide top' 1 "$README" 'index($0, "| Usability |") == 1 { sub(/GUIDE\.md#new-since-100\)/, "GUIDE.md)") } { print }' chk_judges_usability
  st 'the row removed' 1 "$README" 'index($0, "| Usability |") != 1' chk_judges_usability
  st 'the row twice' 1 "$README" '{ print } index($0, "| Usability |") == 1 { print }' chk_judges_usability
  st 'the row moved out of the For judges table' 1 "$README" 'index($0, "| Usability |") == 1 { held = $0; next } { print } END { print ""; print held }' chk_judges_usability
  st 'the For judges heading renamed' 1 "$README" '$0 == "### For judges: where to look" { print "### For judges"; next } { print }' chk_judges_usability
  # Another count word is not this rule's matter: the web tests pin the number against the More to try registry.
  mkdir -p "$tmp/ju"
  awk 'index($0, "| Usability |") == 1 { sub(/ has [a-z]+ more things/, " has seventeen more things") } { print }' "$README" > "$tmp/ju/other.md"
  if [ -n "$(chk_judges_usability "$tmp/ju/other.md")" ]; then st_note 'another count word is flagged'; fi
  finish judges-usability 'the For judges Usability row opens with the two ruled sentences, word for word but for the count word' chk_judges_usability
}

rule_path() {
  local n
  rule_begin path "$README" || return
  for n in 1 2 3 4 5 6 7; do
    st "step $n removed" 1 "$README" "/^## / { s = (\$0 == \"## $H_INC\") } s && /^$n\\. / { next } { print }" chk_path
  done
  st 'step 1 after step 2' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^1\. / { held = $0; next } { print } s && /^2\. / { print held }' chk_path
  st 'step 3 reworded' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^3\. / { sub(/plain English/, "plain words") } { print }' chk_path
  st 'step 5 reworded' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^5\. / { sub(/press Approve/, "press Reject") } { print }' chk_path
  st 'the intro line reworded' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^The demo guide walks/ { sub(/about two minutes/, "about five minutes") } { print }' chk_path
  st 'the intro line removed' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^The demo guide walks/ { next } { print }' chk_path
  st 'an eighth step' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } { print } s && /^7\. / { print "8. **More.** One more."}' chk_path
  st 'a line added after the intro line' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } { print } s && /^The demo guide walks/ { print ""; print "A stray line." }' chk_path
  for n in 1 2 3 4 5 6 7; do
    st "step $n with a word added" 1 "$README" "/^## / { s = (\$0 == \"## $H_INC\") } s && /^$n\\. / { \$0 = \$0 \" Extra.\" } { print }" chk_path
  done
  st 'step 1 without its italics' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^1\. / { sub(/\*Break the feed\*/, "Break the feed") } { print }' chk_path
  st 'step 3 renumbered 4' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^3\. / { sub(/^3\./, "4.") } { print }' chk_path
  st 'steps 6 and 7 swapped' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^6\. / { held = $0; next } { print } s && /^7\. / { print held }' chk_path
  st 'steps 2 and 3 swapped' 1 "$README" '/^## / { s = ($0 == "## One incident, end to end") } s && /^2\. / { held = $0; next } { print } s && /^3\. / { print held }' chk_path
  st_move 'step 3 moved out of the section' "$H_INC" '3. ' chk_path
  st 'the section renamed' 1 "$README" '/^## One incident, end to end$/ { print "## One incident"; next } { print }' chk_path
  st 'Two things to look at in the demo back under Measured' 1 "$README" '{ print } /^## Measured$/ { print ""; print "Two things to look at in the demo:"; print ""; print "- It works from real failures." }' chk_path
  st_append 'Two things to look at in the demo back' 'Two things to look at in the demo:' chk_path
  finish path 'One incident, end to end holds its ruled intro line and seven steps, word for word, and Two things to look at in the demo is gone' chk_path
}

rule_new_since() {
  local line name g
  rule_begin new-since "$README" "$GUIDE" || return
  # The README's H3 holds only the ruled pointer.
  st 'the heading removed' 1 "$README" '!/^### New since 1.0.0$/' chk_new_since
  st 'the heading renamed' 1 "$README" '/^### New since 1.0.0$/ { print "### Since 1.0.0"; next } { print }' chk_new_since
  st 'the heading above the image line' 1 "$README" '/^!\[Visual Trace of one whole decision/ { held = $0; next } { print } /^### New since 1.0.0$/ { print ""; print held }' chk_new_since
  st 'the pointer removed' 1 "$README" 'index($0, "The guide lists what is new since release 1.0.0") != 1' chk_new_since
  st 'the pointer reworded' 1 "$README" '/^The guide lists what is new since release 1.0.0/ { sub(/your integrations/, "integrations") } { print }' chk_new_since
  st 'the pointer twice' 1 "$README" '{ print } /^The guide lists what is new since release 1.0.0/ { print ""; print }' chk_new_since
  st 'a stray line between the heading and the pointer' 1 "$README" '/^### New since 1.0.0$/ { print; print ""; print "A stray line."; next } { print }' chk_new_since
  st 'a bullet under the pointer' 1 "$README" '{ print } /^The guide lists what is new since release 1.0.0/ { print ""; print "- **Memory.** Text." }' chk_new_since
  st 'the intro line back under the heading' 1 "$README" '{ print } /^The guide lists what is new since release 1.0.0/ { print ""; print "Each item says where to try it." }' chk_new_since
  st 'the image line removed from the section' 1 "$README" '/^## / { s = ($0 ~ /^## What.s interesting$/) } s && index($0, "![") == 1 { next } { print }' chk_new_since
  # The guide's section holds the intro line, the three groups and the 17 bullets.
  st 'the guide heading removed' 2 "$GUIDE" '!/^## New since 1.0.0$/' chk_new_since
  st 'the guide heading renamed' 2 "$GUIDE" '/^## New since 1.0.0$/ { print "## Since 1.0.0"; next } { print }' chk_new_since
  st 'the intro line reworded' 2 "$GUIDE" '/^Each item says where/ { sub(/Visual Trace on the online demo/, "Visual Trace here") } { print }' chk_new_since
  st 'the intro line removed' 2 "$GUIDE" '/^Each item says where/ { getline; next } { print }' chk_new_since
  for g in "$NS_G1" "$NS_G2" "$NS_G3"; do
    st "the group heading $g removed" 2 "$GUIDE" "\$0 != \"#### $g\"" chk_new_since
    st "the group heading $g renamed" 2 "$GUIDE" "\$0 == \"#### $g\" { print \"#### $g too\"; next } { print }" chk_new_since
  done
  st 'the first two group headings swapped' 2 "$GUIDE" '/^#### Your integrations$/ { print "#### Your documents and memory"; next } /^#### Your documents and memory$/ { print "#### Your integrations"; next } { print }' chk_new_since
  st 'a group heading as an H3' 2 "$GUIDE" '/^#### Your integrations$/ { print "### Your integrations"; next } { print }' chk_new_since
  st 'the last two group headings swapped' 2 "$GUIDE" '/^#### Your documents and memory$/ { print "#### Personas, the heartbeat checklist and the digest"; next } /^#### Personas, the heartbeat checklist and the digest$/ { print "#### Your documents and memory"; next } { print }' chk_new_since
  st 'the first and last group headings swapped' 2 "$GUIDE" '/^#### Your integrations$/ { print "#### Personas, the heartbeat checklist and the digest"; next } /^#### Personas, the heartbeat checklist and the digest$/ { print "#### Your integrations"; next } { print }' chk_new_since
  st 'a fourth group heading' 2 "$GUIDE" '{ print } index($0, "- **A Usage page.**") == 1 { print ""; print "#### Another group"; print "" }' chk_new_since
  st 'the first two bullets of the first group swapped' 2 "$GUIDE" 'index($0, "- **A dry run that checks good messages.**") == 1 { held = $0; next } { print } index($0, "- **Incident summaries.**") == 1 { print held }' chk_new_since
  st 'Memory before Where an answer came from' 2 "$GUIDE" 'index($0, "- **Where an answer came from.**") == 1 { held = $0; next } { print } index($0, "- **Memory.**") == 1 { print held }' chk_new_since
  st 'the Personas and heartbeat bullets swapped' 2 "$GUIDE" 'index($0, "- **Personas.**") == 1 { held = $0; next } { print } index($0, "- **A heartbeat checklist.**") == 1 { print held }' chk_new_since
  st 'a bullet renamed' 2 "$GUIDE" 'index($0, "- **Memory.**") == 1 { sub(/Memory\./, "Remembering.") } { print }' chk_new_since
  printf '%s\n' "$NS_WANT" | while IFS= read -r line; do
    case $line in B\ *) echo "${line#B }" ;; esac
  done > "$tmp/ns.names"
  while IFS= read -r name; do
    st "the bullet $name missing" 2 "$GUIDE" "index(\$0, \"- **$name.**\") != 1" chk_new_since
  done < "$tmp/ns.names"
  st 'the first bullet twice' 2 "$GUIDE" '{ print } index($0, "- **A dry run that checks good messages.**") == 1 { print }' chk_new_since
  st 'a middle bullet twice' 2 "$GUIDE" '{ print } index($0, "- **Memory.**") == 1 { print }' chk_new_since
  st 'the last bullet twice' 2 "$GUIDE" '{ print } index($0, "- **A daily digest.**") == 1 { print }' chk_new_since
  st 'the History and Usage bullets swapped' 2 "$GUIDE" 'index($0, "- **A History page.**") == 1 { held = $0; next } { print } index($0, "- **A Usage page.**") == 1 { print held }' chk_new_since
  st 'the Usage bullet moved to the next group' 2 "$GUIDE" 'index($0, "- **A Usage page.**") == 1 { held = $0; next } { print } /^#### Your documents and memory$/ { print held }' chk_new_since
  st 'a bullet that is not in the list' 2 "$GUIDE" '{ print } index($0, "- **A Usage page.**") == 1 { print "- **A new thing.** Text." }' chk_new_since
  st 'a bullet above the first group heading' 2 "$GUIDE" '/^Each item says where/ { print; print ""; print "- **A new thing.** Text."; next } { print }' chk_new_since
  finish new-since 'the README holds the ruled pointer under its H3 New since 1.0.0, and the guide holds the section with its intro line, the three group headings in order and the 17 bullets, each once, in the ruled order' chk_new_since
}

rule_teaser() {
  local first
  rule_begin teaser "$README" "$GUIDE" || return
  first=$(image_links "$README" | head -n 1 | cut -f3)
  st 'the full-video line removed' 1 "$README" '!/^Watch the full video /' chk_teaser
  st 'the full-video line changed' 1 "$README" '/^Watch the full video / { sub(/full video/, "long video") } { print }' chk_teaser
  st 'the full-video line moved to the end of the README' 1 "$README" '/^Watch the full video / { fv = $0; next } { print } END { print ""; print fv }' chk_teaser
  st 'the full-video line twice' 1 "$README" '/^Watch the full video / { fv = $0 } { print } END { print ""; print fv }' chk_teaser
  st 'the full-video line under the first H2 section' 1 "$README" '/^Watch the full video / { fv = $0; next } { print } /^## Try it in two minutes$/ { print ""; print fv }' chk_teaser
  st 'the teaser above the full-video line' 1 "$README" '/^Watch the full video / { fv = $0; next } { print } /^Or watch the 35-second teaser: / { print ""; print fv }' chk_teaser
  st 'no empty line between the full-video line and the teaser' 1 "$README" 'held { held = 0; if ($0 == "") next } { print } /^Watch the full video / { held = 1 }' chk_teaser
  st 'a stray line where the empty line below the full-video line is' 1 "$README" 'held { held = 0; if ($0 == "") { print "x"; next } } { print } /^Watch the full video / { held = 1 }' chk_teaser
  st 'the teaser line removed' 1 "$README" '!/^Or watch the 35-second teaser: /' chk_teaser
  st 'the teaser line changed' 1 "$README" '{ sub(/35-second/, "36-second"); print }' chk_teaser
  st 'the teaser moved to the end of the README' 1 "$README" '/^Or watch the 35-second teaser: / { next } { print } END { print ""; print "Or watch the 35-second teaser: https://youtu.be/wycbyfnXFMU" }' chk_teaser
  st 'the teaser above the opening paragraph' 1 "$README" '/^Or watch the 35-second teaser: / { next } /^Your integrations already/ { print "Or watch the 35-second teaser: https://youtu.be/wycbyfnXFMU"; print "" } { print }' chk_teaser
  st 'the teaser under the first H2 section' 1 "$README" '/^Or watch the 35-second teaser: / { next } { print } /^## Try it in two minutes$/ { print ""; print "Or watch the 35-second teaser: https://youtu.be/wycbyfnXFMU" }' chk_teaser
  st 'no empty line between the opening paragraph and the full-video line' 1 "$README" 'held { held = 0; if ($0 == "") next } { print } /^Your integrations already/ { held = 1 }' chk_teaser
  st 'a stray line where the empty line below the opening paragraph is' 1 "$README" 'held { held = 0; if ($0 == "") { print "x"; next } } { print } /^Your integrations already/ { held = 1 }' chk_teaser
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
  # The header's first badge line (the CI badge, whose host is allowed on every line) copied to the end is no longer exempt; neither is a
  # linked image right after the hero image.
  st 'a header badge line below the header' 1 "$README" 'NR <= '"$HEADER_LINES"' && b == "" && /<img/ && /<a href=/ { b = $0 } { print } END { print ""; print b }' chk_teaser
  st 'an image inside a link right after the hero image' 1 "$README" '{ print } index($0, "]('"$first"')") > 0 && !done { print ""; print "[![x]('"$first"')](LICENSE)"; done = 1 }' chk_teaser
  # The media clauses cover the guide too.
  st 'an image tag in the guide' 2 "$GUIDE" '{ print } END { print ""; print "<img src=x.png>" }' chk_teaser
  st 'a frame in the guide' 2 "$GUIDE" '{ print } END { print ""; print "<iframe src=x></iframe>" }' chk_teaser
  st 'a video tag in the guide' 2 "$GUIDE" '{ print } END { print ""; print "<video src=x.mp4></video>" }' chk_teaser
  st 'a linked image in the guide' 2 "$GUIDE" '{ print } END { print ""; print "[![Teaser](docs/images/page-incident.png)](LICENSE)" }' chk_teaser
  st 'a remote image in the guide' 2 "$GUIDE" '{ print } END { print ""; print "![teaser](https://example.org/a.png)" }' chk_teaser
  st 'a GIF in the guide' 2 "$GUIDE" '{ print } END { print ""; print "![teaser](docs/images/teaser.gif)" }' chk_teaser
  finish teaser 'the full-video line and the teaser are word for word, two lines below the opening paragraph and the full-video line; the README and the guide have no media tag and only inline docs/images PNG images below the header block' chk_teaser
}

rule_outcomes() {
  local name
  rule_begin outcomes "$GUIDE" "$chatview_p" || return
  for name in Ignore Digest 'Tell now' Act; do
    st "the outcome $name removed" 1 "$GUIDE" "{ if (index(\$0, \"**$name**: \") > 0) next; print }" chk_outcomes
  done
  st 'a meaning of the page changed' 2 "$chatview_p" '/meaningIgnore:/ { sub(/'"'"'.*'"'"'/, "'"'"'Changed meaning'"'"'") } { print }' chk_outcomes
  st 'no meanings in the page' 2 "$chatview_p" '!/meaningIgnore/' chk_outcomes
  finish outcomes 'Ignore, Digest, Tell now and Act, with the meanings that the page shows' chk_outcomes
}

rule_install() {
  rule_begin install "$GUIDE" || return
  st_facts chk_install "$INSTALL_FACTS"
  st_move 'the Compose version moved out of the section' 'Install it yourself' '- Docker Compose 2.24' chk_install
  st 'the build 109 heading back before the non-Health image' 1 "$GUIDE" '/^### The IRIS \(non-Health\) image$/ { print "### Start it with build 109"; print "" } { print }' chk_install
  st 'the old second sentence of the Get the image paragraph back' 1 "$GUIDE" '/^OcuTalon also runs on build 109: / { print $0 " In this release, `./install.sh` looks only for build 154, so with build 109, start OcuTalon as [Start it with build 109](#start-it-with-build-109) shows."; next } { print }' chk_install
  st 'the IRIS_IMAGE line back after the cp step of Start it by hand' 1 "$GUIDE" '/^cp \.env\.example \.env$/ { print; print "echo \047IRIS_IMAGE=<the name docker load printed>\047 >> .env"; next } { print }' chk_install
  st 'the install script paragraph back to a build 154 image' 1 "$GUIDE" '{ sub(/a build 154 or build 109 image for your CPU is loaded; when both are, it uses build 154\./, "a build 154 image for your CPU is loaded.") } { print }' chk_install
  st 'the old Troubleshooting sentence back' 1 "$GUIDE" '/^\*\*"No IRIS build 154 or build 109 image is loaded in Docker"\*\*: / { print $0 " With build 109, follow [Start it with build 109](#start-it-with-build-109) instead of running `./install.sh`."; next } { print }' chk_install
  st 'the Troubleshooting quote back to build 154 only' 1 "$GUIDE" '{ sub(/"No IRIS build 154 or build 109 image is loaded in Docker"/, "\"No IRIS build 154 image is loaded in Docker\"") } { print }' chk_install
  st 'the Troubleshooting CPU quote back to build 154 only' 1 "$GUIDE" '{ sub(/"The IRIS build 154 or build 109 image that is loaded/, "\"The IRIS build 154 image that is loaded") } { print }' chk_install
  finish install 'Compose 2.24, both image names, load and retag, the portal, the CPUs, the 15-minute wait and one install path for build 154 and build 109' chk_install
}

rule_install_pointer() {
  rule_begin install-pointer "$GUIDE" "$install_p" || return
  st 'the Troubleshooting heading removed' 1 "$GUIDE" '!/^## Troubleshooting$/' chk_install_pointer
  st 'install.sh names another section' 2 "$install_p" '{ sub(/The Troubleshooting section/, "The Cooking section"); print }' chk_install_pointer
  st 'install.sh names no section' 2 "$install_p" '{ sub(/section of GUIDE/, "part of GUIDE"); print }' chk_install_pointer
  st 'install.sh names a section of README.md' 2 "$install_p" '!done && /section of GUIDE\.md/ { sub(/GUIDE\.md/, "README.md"); done = 1 } { print }' chk_install_pointer
  finish install-pointer 'every GUIDE.md section that install.sh points to is an H2 heading, and none is a README.md section' chk_install_pointer
}

rule_commands() {
  local cmds cmd
  rule_begin commands "$GUIDE" "$install_p" "$README" || return
  cmds=$(sed -n 's/.*run: *\(docker compose[^"]*\)".*/\1/p' "$install_p" | sed 's/ *$//' | sort -u)
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    if ! strip_str "$GUIDE" "$cmd"; then
      st_note "without '$cmd': the edit changed nothing"
    elif [ -z "$(chk_commands "$tmp/m" "$S2" "$S3")" ]; then
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
  st 'docker compose restart in the README' 3 "$README" '{ print } END { print "Run docker compose restart to apply it." }' chk_commands
  st 'install.sh again in the README' 3 "$README" '{ print } END { print "Run ./install.sh again to apply it." }' chk_commands
  st 'rerun in the README' 3 "$README" '{ print } END { print "Then rerun the script." }' chk_commands
  st 'install.sh prints no command after run:' 2 "$install_p" '{ gsub(/run:/, "go:"); print }' chk_commands
  finish commands 'every command that install.sh prints is in the guide, and none that it never gives, in the guide or the README' chk_commands
}

rule_key_account() {
  rule_begin key-account "$GUIDE" "$README" || return
  st_facts chk_key_account "$KEY_FACTS"
  st_facts chk_key_account "$ACCOUNT_FACTS"
  st_facts chk_key_account "$FIXED_SENTENCE"
  st_facts chk_key_account "$MODEL_BLOCK"
  st 'a cell of the model table changed' 1 "$GUIDE" '{ sub(/with no cause and no fix/, "with a cause and no fix"); print }' chk_key_account
  st 'a row of the model table removed' 1 "$GUIDE" '!/^\| 50 orders fail \|/' chk_key_account
  st 'a fourth row added to the model table' 1 "$GUIDE" '{ print } /^\| You ask in the chat \|/ { print "| Cost | Costs you nothing extra | Free |" }' chk_key_account
  st 'the empty line above the table removed' 1 "$GUIDE" '{ line[NR] = $0 } END { for (i = 1; i <= NR; i++) if (!(line[i] == "" && line[i + 1] ~ /^\| \| With a model/)) print line[i] }' chk_key_account
  st 'the empty line above the model paragraph removed' 1 "$GUIDE" '{ line[NR] = $0 } END { for (i = 1; i <= NR; i++) if (!(line[i] == "" && index(line[i + 1], "**With a model, and without one.**") == 1)) print line[i] }' chk_key_account
  st 'a line without a bar right under the model table' 1 "$GUIDE" '{ print } /^\| You ask in the chat \|/ { print "Cost | Costs you nothing extra | Free" }' chk_key_account
  st 'a bullet after the model table' 1 "$GUIDE" '{ print } /^\| You ask in the chat \|/ { print ""; print "- **Extra.** More." }' chk_key_account
  st_move 'the model table moved out of its section' 'What OcuTalon does' '|' chk_key_account
  st_move 'the fixed-rules sentence moved out of its section' 'Set a model key' 'Without a key, OcuTalon still starts.' chk_key_account
  st_append 'the bullet back' '- **No key, still works.** Without a model key, OcuTalon starts and every decision uses fixed rules. The page says so.' chk_key_account
  st_append 'a key-shaped example' 'Set ANTHROPIC_API_KEY=abc in .env.' chk_key_account
  st 'the bullet back in the README' 2 "$README" '{ print } END { print "- **No key, still works.** Without a model key, OcuTalon starts." }' chk_key_account
  st 'a key-shaped example in the README' 2 "$README" '{ print } END { print "Set ANTHROPIC_API_KEY=abc in .env." }' chk_key_account
  finish key-account 'the key line, .env.example, the default model, the fixed-rules sentence, the model paragraph and table, the README account and the Visual Trace sign-in' chk_key_account
}

rule_lan() {
  rule_begin lan "$GUIDE" || return
  st_facts chk_lan "$LAN_FACTS"
  st_facts chk_lan "$ACCOUNTS_FACTS"
  st_move 'the warning moved out of the section' 'Sign in' '**Change the README account' chk_lan
  st 'the default accounts section removed' 1 "$GUIDE" '$0 == "### Change the default IRIS accounts\047 passwords" { next } { print }' chk_lan
  st 'the default accounts section renamed' 1 "$GUIDE" '$0 == "### Change the default IRIS accounts\047 passwords" { print "### Change the default passwords"; next } { print }' chk_lan
  st 'the default accounts section above the README account section' 1 "$GUIDE" '$0 == "### Change the default IRIS accounts\047 passwords" { print "### Change the README account\047s password"; next } $0 == "### Change the README account\047s password" { print "### Change the default IRIS accounts\047 passwords"; next } { print }' chk_lan
  finish lan 'Sign in warns about the LAN and the Management Portal and links to the password steps' chk_lan
}

rule_sign_in_address() {
  rule_begin sign-in-address "$GUIDE" "$install_p" "$compose_p" "$README" || return
  st 'another address in the ready block' 1 "$GUIDE" '/^  Open: / { $0 = $0 "zz" } { print }' chk_sign_in_address
  st 'another user in the ready block' 1 "$GUIDE" '/^  User: / { $0 = $0 "zz" } { print }' chk_sign_in_address
  st 'another password in the ready block' 1 "$GUIDE" '/^  Password: / { $0 = $0 "zz" } { print }' chk_sign_in_address
  st 'another address in Try it' 4 "$README" '/^## / { s = ($0 == "## Try it in two minutes") } s { gsub(/http:\/\/localhost/, "http://zz") } { print }' chk_sign_in_address
  st 'another address in Sign in' 1 "$GUIDE" '/^## / { s = ($0 == "## Sign in") } s { gsub(/http:\/\/localhost/, "http://zz") } { print }' chk_sign_in_address
  st 'another account in Try it' 4 "$README" '/^## / { s = ($0 == "## Try it in two minutes") } s && /^3\. / { gsub(/`[^`]*`/, "`zz`") } { print }' chk_sign_in_address
  st 'install.sh prints another address' 2 "$install_p" '/^[[:space:]]*echo "  Open: / { sub(/"$/, "zz\"") } { print }' chk_sign_in_address
  st 'install.sh prints no ready block' 2 "$install_p" '!/^[[:space:]]*echo "  Open: /' chk_sign_in_address
  st 'another default port in the compose file' 3 "$compose_p" '{ sub(/OCUTALON_WEB_PORT:-[0-9]+/, "OCUTALON_WEB_PORT:-1"); print }' chk_sign_in_address
  st 'no default port in the compose file' 3 "$compose_p" '{ sub(/OCUTALON_WEB_PORT:-/, "OCUTALON_WEB_PORT:?"); print }' chk_sign_in_address
  finish sign-in-address 'the ready block, the address and the account are the ones install.sh prints, with the default web port' chk_sign_in_address
}

rule_demo_mode() {
  local kept
  rule_begin demo-mode "$GUIDE" "$admin_p" "$experience_p" || return
  st_facts chk_demo_mode "$DEMO_FACTS"
  st 'Admin.cls without SetDemoMode' 2 "$admin_p" '{ sub(/ClassMethod SetDemoMode\(/, "ClassMethod SetDemo("); print }' chk_demo_mode
  st 'the kept sentence changed in EXPERIENCE.md' 3 "$experience_p" '{ sub(/OcuTalon left the OCUORDERS namespace/, "&, as agreed"); print }' chk_demo_mode
  st 'no kept sentence in EXPERIENCE.md' 3 "$experience_p" '!/OcuTalon left the OCUORDERS namespace/' chk_demo_mode
  kept=$(sed -n 's/^.*"\(OcuTalon left the OCUORDERS namespace[^"]*\)".*$/\1/p' "$experience_p" | head -n 1)
  if [ -n "$kept" ]; then
    if ! strip_str "$GUIDE" "$kept"; then
      st_note "without the kept sentence: the edit changed nothing"
    elif [ -z "$(chk_demo_mode "$tmp/m" "$S2" "$S3")" ]; then
      st_note "without the kept sentence: not flagged"
    fi
  fi
  finish demo-mode 'the SetDemoMode line, its roles and the kept-OCUORDERS sentence as EXPERIENCE.md writes it' chk_demo_mode
}

rule_admin_commands() {
  rule_begin admin-commands "$GUIDE" || return
  st_facts chk_admin_commands "$ADMIN_FACTS"
  finish admin-commands 'the terminal sessions and the password line are the ones the walkthrough ran' chk_admin_commands
}

rule_admin_mcp() {
  rule_begin admin-mcp "$GUIDE" "$mcpexample_p" || return
  st 'the MCP paragraph removed' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") != 1' chk_admin_mcp
  st 'the guide sentence changed' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/must be classified Risky/, "should be classified Risky") } { print }' chk_admin_mcp
  st 'the link to another file' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/docs\/mcp-jira-example\.md/, "docs/mcp-jira.md") } { print }' chk_admin_mcp
  st 'the link text changed' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/step by step\]/, "step-by-step]") } { print }' chk_admin_mcp
  st 'the paragraph split over two lines' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/Risky\. The worked/, "Risky.\nThe worked") } { print }' chk_admin_mcp
  st 'the link to a file that exists' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/docs\/mcp-jira-example\.md/, "docs/security-overview.md") } { print }' chk_admin_mcp
  st 'an anchor on the link' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/mcp-jira-example\.md\)/, "mcp-jira-example.md#step-1)") } { print }' chk_admin_mcp
  st 'a line joined to the paragraph' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { print; print "More text."; next } { print }' chk_admin_mcp
  st 'a line above the paragraph' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { print "A stray line."; print "" } { print }' chk_admin_mcp
  st 'the paragraph under Demo mode' 1 "$GUIDE" 'index($0, "An MCP tool that runs operating-system") == 1 { held = $0; next } { print } /^### Demo mode$/ { print ""; print held }' chk_admin_mcp
  st 'the paragraph in another section' 1 "$GUIDE" "index(\$0, \"An MCP tool that runs operating-system\") == 1 { next } { print } /^## Troubleshooting\$/ { print \"\"; print \"$ADMIN_MCP_LINE\" }" chk_admin_mcp
  st 'the paragraph twice' 1 "$GUIDE" "{ print } /^## Troubleshooting\$/ { print \"\"; print \"$ADMIN_MCP_LINE\" }" chk_admin_mcp
  st 'the admin heading renamed' 1 "$GUIDE" '/^## For admins and developers$/ { print "## For admins"; next } { print }' chk_admin_mcp
  st 'the example sentence changed' 2 "$mcpexample_p" '{ sub(/must be classified Risky\./, "should be classified Risky.") } { print }' chk_admin_mcp
  st 'the example sentence split over two lines' 2 "$mcpexample_p" 'index($0, "An MCP tool that runs operating-system") == 1 { sub(/ commands or/, "\ncommands or") } { print }' chk_admin_mcp
  st 'the example sentence twice' 2 "$mcpexample_p" 'index($0, "An MCP tool that runs operating-system") == 1 { print; print "" } { print }' chk_admin_mcp
  st 'the example sentence inside a longer line' 2 "$mcpexample_p" 'index($0, "An MCP tool that runs operating-system") == 1 { $0 = $0 " See also the overview." } { print }' chk_admin_mcp
  st 'the example sentence removed' 2 "$mcpexample_p" 'index($0, "An MCP tool that runs operating-system") != 1' chk_admin_mcp
  st 'no worked example' 2 "$mcpexample_p" '0' chk_admin_mcp
  finish admin-mcp "For admins and developers opens with the ruled MCP paragraph, once, and its classification sentence is a line of $MCP_EXAMPLE_DOC, word for word" chk_admin_mcp
}

rule_after_start_log() {
  rule_begin after-start-log "$GUIDE" "$after_start_p" || return
  st_facts chk_after_start_log "docker compose exec iris cat $(log_path "$after_start_p")
$LOG_FACTS"
  st 'another log path in docker/after-start.sh' 2 "$after_start_p" '/^log_file=/ { sub(/LOG:-[^}]*/, "LOG:-/durable/zz-other.log") } { print }' chk_after_start_log
  st 'no default log path in docker/after-start.sh' 2 "$after_start_p" '{ sub(/^log_file=/, "lf="); print }' chk_after_start_log
  finish after-start-log 'the log command names the path that docker/after-start.sh writes, and the lines to look for' chk_after_start_log
}

rule_dev_only() {
  local text label
  if ! rule_begin dev-only "$README" "$GUIDE"; then return; fi
  printf '# T\n\nSee OcuTalon.Core.Admin here.\n\n## For admins and developers\n' > "$tmp/dev.bad"
  printf '# T\n\n## Plain\n\nSee README.md, demo.ocutalon.com and docs.docker.com: they are not class names.\n\n## For admins and developers\n\n### Demo mode\n\ndo ##class(OcuTalon.Core.Admin).SetDemoMode(1)\nERROR #5001 <UNDEFINED> %%SYS.Namespace\n\n## Credits\n\nPlain words again.\n' > "$tmp/dev.good"
  while IFS='|' read -r label text; do
    [ -n "$label" ] || continue
    st "$label above the section" 1 "$README" "NR == 1 { print; print \"$text\"; next } { print }" dev_names_1
    st "$label above the section, in the guide" 1 "$GUIDE" "NR == 1 { print; print \"$text\"; next } { print }" dev_names_1
  done <<'EOF'
a ##class( call|Call ##class(Foo.Bar).Baz() now.
a class name|The class OcuTalon.Core.X does it.
a system class name|Security.Users holds it.
a percent class name|The class %SYS.Namespace holds it.
an error code|It failed with ERROR #5001 today.
an error name|It showed <UNDEFINED> there.
EOF
  st 'the IPM load line changed above the section' 1 "$GUIDE" '{ sub(/zpm\/0\.10\.10\/installer/, "zpm/0.10.9/installer") } { print }' dev_names_1
  st 'the IPM load line with a second call on its line' 1 "$GUIDE" '/^s r=##class\(%Net\.HttpRequest\)/ { $0 = $0 " d ##class(Foo.Bar).Baz()" } { print }' dev_names_1
  st 'the Complexity row with a class name changed' 1 "$README" '/^\| Complexity \| / { sub(/%AI\.Policy\.Audit/, "%AI.Policy.Audits") } { print }' dev_names_1
  st 'the Complexity row with a class name added' 1 "$README" '/^\| Complexity \| / { sub(/ \|$/, " See OcuTalon.Core.Admin. |") } { print }' dev_names_1
  st 'a class name on the line after the Complexity row' 1 "$README" '{ print } /^\| Complexity \| / { print "The class OcuTalon.Core.X does it." }' dev_names_1
  st_append 'a class name after the admin section' '## After\n\nThe class OcuTalon.Core.X does it.' dev_names_1
  st 'a class name after the admin section of the guide' 1 "$GUIDE" '{ print } END { print "## After\n\nThe class OcuTalon.Core.X does it." }' dev_names_1
  if [ "$st_bad" -ne 0 ] && [ -z "$(dev_names "$README" "$GUIDE")" ]; then
    printf '%s' "$st_msgs"
    echo "FAIL dev-only: a broken copy was not flagged"
    fails=$((fails + 1))
    return
  fi
  scan_rule 'dev-only: no ##class(, class name or error code outside "For admins and developers" in the README or the guide' dev_names "$tmp/dev.bad" "$tmp/dev.good" "$(printf '%s\n' "$README" "$GUIDE")"
}

rule_public_text() {
  local text label
  if ! rule_begin public-text "$README" "$GUIDE"; then return; fi
  printf 'This runs on OpenAI.\n' > "$tmp/pub.bad"
  { printf '%s\n' "$NOTE"; printf '%s\n' "$PUBLIC_FACTS"; printf 'Listen on 127.0.0.1 or 0.0.0.0 only.\nNot providers, only words that contain one: llamas, grokking, gptx and azurite.\n'; } > "$tmp/pub.good"
  st_facts public_text_1 "$PUBLIC_FACTS"
  st 'the note altered' 1 "$README" '{ sub(/not affiliated with/, "affiliated with"); print }' public_text_1
  st 'OpenClaw outside the note' 1 "$README" 'NR == 1 { print; print ""; print "An OpenClaw-style assistant."; next } { print }' public_text_1
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
never used for tuning|The held-out cases were never used for tuning.
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
  # The guide is scanned for the same words; the note, the credit and the licence pointers are the README's alone.
  st 'the not-affiliated note in the guide' 2 "$GUIDE" "{ print } END { print \"$NOTE\" }" public_text_2
  st 'OpenClaw in the guide' 2 "$GUIDE" '{ print } END { print ""; print "An OpenClaw-style assistant." }' public_text_2
  while IFS='|' read -r label text; do
    [ -n "$label" ] || continue
    st "$label, in the guide" 2 "$GUIDE" "{ print } END { print \"\"; print \"$text\" }" public_text_2
  done <<'EOF'
a model provider|It also works with Gemini.
from your phone|Approve it from your phone.
per step|Costs are shown per step.
never used for tuning|The held-out cases were never used for tuning.
a worktree folder|Built in .worktrees today.
an IPv4 address|Open http://192.168.1.10:52773 now.
EOF
  if [ "$st_bad" -ne 0 ] && [ -z "$(public_text_scan "$README" "$GUIDE")" ]; then
    printf '%s' "$st_msgs"
    echo "FAIL public-text: a broken copy was not flagged"
    fails=$((fails + 1))
    return
  fi
  scan_rule 'public-text: the note, the credit and the licence pointers in the README; no other provider, private word or address in the README or the guide' public_text_scan "$tmp/pub.bad" "$tmp/pub.good" "$(printf '%s\n' "$README" "$GUIDE")"
}

rule_no_telegram() {
  rule_begin no-telegram "$README" "$(telegram_mode "$included_p")" "$GUIDE" || return
  S2=testonly st_append 'the word Telegram' 'Set up Telegram here.' chk_no_telegram
  S2=testonly st_append 'the word in capitals' 'TELEGRAM_BOT_TOKEN=x' chk_no_telegram
  S2=testonly st 'the word Telegram in the guide' 3 "$GUIDE" '{ print } END { print "Set up Telegram here." }' chk_no_telegram
  printf 'Set up Telegram here.\n' > "$tmp/tg.txt"
  if [ -n "$(chk_no_telegram "$tmp/tg.txt" included "$tmp/tg.txt")" ]; then st_note 'the word is flagged although Included() no longer has its test-only body'; fi
  if [ "$(telegram_mode "$included_p")" = testonly ]; then
    finish no-telegram 'no Telegram in the README or the guide while Included() has its test-only body' chk_no_telegram
  else
    finish no-telegram 'Included() no longer has its test-only body, so the word is allowed' chk_no_telegram
  fi
}

rule_product_links() {
  local mode lits got h
  rule_begin product-links "$README" "$tmp/product.list" "$included_p" "$GUIDE" || return
  # Only the product's files are read: a spec file and a class under /Test/ are not.
  got=$(printf '%s\n' web/src/app/a.ts web/src/app/a.spec.ts src/p/C.cls src/p/Test/T.cls web/e2e/x.ts docs/y.cls | product_files)
  if [ "$got" != "$(printf '%s\n%s' web/src/app/a.ts src/p/C.cls)" ]; then st_note 'the product files are not exactly the page sources and the classes that are not tests'; fi
  # An anchor with no heading is named.
  mkdir -p "$tmp/inv"
  printf "export const SETUP_ANCHOR = 'nowhere';\n" > "$tmp/inv/Extra.ts"
  { cat "$tmp/product.list"; printf '%s\n' "$tmp/inv/Extra.ts"; } > "$tmp/inv/with-extra.list"
  if ! chk_product_links "$README" "$tmp/inv/with-extra.list" "$included_p" "$GUIDE" | grep -q "'#nowhere'"; then st_note 'an anchor with no heading is not named'; fi
  # No inventory: the check fails closed.
  : > "$tmp/inv/none.list"
  if [ -z "$(chk_product_links "$README" "$tmp/inv/none.list" "$included_p" "$GUIDE")" ]; then st_note 'an empty link inventory is not flagged'; fi
  printf "export const OTHER = 'x';\n" > "$tmp/inv/Other.ts"
  printf '%s\n' "$tmp/inv/Other.ts" > "$tmp/inv/other.list"
  if [ -z "$(chk_product_links "$README" "$tmp/inv/other.list" "$included_p" "$GUIDE")" ]; then st_note 'an inventory without #readme and #telegram is not flagged'; fi
  # The other two places an anchor is written, a readmeSection literal and an address, are named too.
  printf "const link = readmeSection(README_URL, 'lit-section');\n" > "$tmp/inv/Lit.ts"
  printf '/// https://github.com/jbrandtmse/OcuTalon#lit-address\n' > "$tmp/inv/Lit.cls"
  { cat "$tmp/product.list"; printf '%s\n%s\n' "$tmp/inv/Lit.ts" "$tmp/inv/Lit.cls"; } > "$tmp/inv/with-lits.list"
  lits=$(chk_product_links "$README" "$tmp/inv/with-lits.list" "$included_p" "$GUIDE")
  case $lits in *"'#lit-section'"*) ;; *) st_note 'a readmeSection literal with no heading is not named' ;; esac
  case $lits in *"'#lit-address'"*) ;; *) st_note 'an address literal with no heading is not named' ;; esac
  # A written address reaches a heading of the file it names: a guide address to a README-only heading, a README address to a
  # guide-only heading and a guide address to no heading are each named.
  printf '/// https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#measured\n/// https://github.com/jbrandtmse/OcuTalon#troubleshooting\n/// https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#lit-guide\n' > "$tmp/inv/Addr.cls"
  { cat "$tmp/product.list"; printf '%s\n' "$tmp/inv/Addr.cls"; } > "$tmp/inv/with-addr.list"
  lits=$(chk_product_links "$README" "$tmp/inv/with-addr.list" "$included_p" "$GUIDE")
  case $lits in *"'GUIDE.md#measured'"*) ;; *) st_note 'a guide address to a README-only heading is not named' ;; esac
  case $lits in *"README address '#troubleshooting'"*) ;; *) st_note 'a README address to a guide-only heading is not named' ;; esac
  case $lits in *"'GUIDE.md#lit-guide'"*) ;; *) st_note 'a guide address with no heading is not named' ;; esac
  # Included() with another body, or no In.cls, covers #telegram: a README without a heading with that slug is flagged. While
  # the body is the test-only one, #telegram is left out. The guide of these cases has any Telegram heading renamed.
  awk '/^#+ [Tt]elegram$/ { sub(/[Tt]elegram$/, "Zz") } { print }' "$GUIDE" > "$tmp/inv/GUIDE.md"
  printf 'ClassMethod Included() As %%Boolean\n{\n\tQuit $Get(^OcuTalonTest("TelegramIncluded")) = 1\n}\n' > "$tmp/inv/In.testonly.cls"
  printf 'ClassMethod Included() As %%Boolean\n{\n\tQuit 1\n}\n' > "$tmp/inv/In.changed.cls"
  if ! chk_product_links "$README" "$tmp/product.list" "$tmp/inv/In.changed.cls" "$tmp/inv/GUIDE.md" | grep -q "'#telegram'"; then st_note 'Included() with another body does not cover #telegram'; fi
  if ! chk_product_links "$README" "$tmp/product.list" "$tmp/absent" "$tmp/inv/GUIDE.md" | grep -q "'#telegram'"; then st_note 'no In.cls does not cover #telegram'; fi
  if chk_product_links "$README" "$tmp/product.list" "$tmp/inv/In.testonly.cls" "$tmp/inv/GUIDE.md" | grep -q "'#telegram'"; then st_note 'the test-only body does not leave #telegram out'; fi
  # The guide sections that the page opens on GUIDE_URL: a heading renamed in the guide is named.
  for h in 'Install it yourself' 'Set a model key'; do
    awk -v h="## $h" '$0 == h { print "## Zz"; next } { print }' "$GUIDE" > "$tmp/inv/GUIDE.h.md"
    if [ -z "$(chk_product_links "$README" "$tmp/product.list" "$included_p" "$tmp/inv/GUIDE.h.md")" ]; then st_note "the guide without its '$h' heading is not flagged"; fi
  done
  mode=$(telegram_mode "$included_p")
  finish product-links 'every anchor that the page or the server text can show reaches a heading, and install-it-yourself, set-a-model-key and telegram are headings of GUIDE.md' chk_product_links
  if [ "$mode" = testonly ]; then
    echo 'SKIP #telegram: Included() has its test-only body, so the page never shows the link to a guide Telegram section'
  fi
}

rule_gmail_section() {
  local priv="$tmp/priv.in" f
  : > "$priv"
  while IFS= read -r f; do grep -hI '' "$f" >> "$priv" 2> /dev/null; done < <(find README.md docs release -path release/records -prune -o -type f -print 2> /dev/null)
  rule_begin gmail-section "$GUIDE" "$priv" || return
  st 'the heading renamed' 1 "$GUIDE" '/^## Gmail and Microsoft 365$/ { print "## Google mail"; next } { print }' chk_gmail_section
  st 'the section removed' 1 "$GUIDE" '/^## Gmail and Microsoft 365$/ { skip = 1; next } skip && /^## / { skip = 0 } !skip' chk_gmail_section
  st 'the bullet without the password' 1 "$GUIDE" '{ sub(/ with a password or by signing in with Google or Microsoft 365/, " by signing in with Google or Microsoft 365") } { print }' chk_gmail_section
  st 'the bullet without the link' 1 "$GUIDE" '{ sub(/ \(see \[Gmail and Microsoft 365\]\(#gmail-and-microsoft-365\)\)/, "") } { print }' chk_gmail_section
  st 'the bullet link pointing elsewhere' 1 "$GUIDE" '{ sub(/\(#gmail-and-microsoft-365\)/, "(#gmail)") } { print }' chk_gmail_section
  st 'the bullet tail changed' 1 "$GUIDE" '{ sub(/The online demo keeps its simulated mailbox\./, "The online demo keeps its mailbox.") } { print }' chk_gmail_section
  st 'the intro reworded' 1 "$GUIDE" '{ sub(/Signing in with Google or Microsoft 365 is optional/, "Signing in with Google or Microsoft 365 is easy") } { print }' chk_gmail_section
  st 'step 1 reworded' 1 "$GUIDE" '{ sub(/Google and Microsoft accept an `http:\/\/` Redirect address only for `localhost`/, "Google and Microsoft accept any Redirect address") } { print }' chk_gmail_section
  st 'the Google scope changed' 1 "$GUIDE" '/^## / { s = ($0 == "## Gmail and Microsoft 365") } s { sub(/scope `https:\/\/mail\.google\.com\/`/, "scope `mail`") } { print }' chk_gmail_section
  st 'the Microsoft permissions changed' 1 "$GUIDE" '{ sub(/`POP.AccessAsUser.All`, `SMTP.Send` and `offline_access`/, "`Mail.Read`") } { print }' chk_gmail_section
  st 'step 4 removed' 1 "$GUIDE" '/^## / { s = ($0 == "## Gmail and Microsoft 365") } !(s && /^4\. /)' chk_gmail_section
  st 'the closing paragraph removed' 1 "$GUIDE" '/^If the sign-in is withdrawn at the provider/ { next } { print }' chk_gmail_section
  st 'the mailbox and approval paragraph removed' 1 "$GUIDE" '/^All email OcuTalon sends goes out from the one mailbox/ { next } { print }' chk_gmail_section
  st 'the mailbox and approval paragraph reworded' 1 "$GUIDE" '{ sub(/Only an OcuTalon admin can have OcuTalon email another address/, "Any user can have OcuTalon email another address") } { print }' chk_gmail_section
  st 'the section after Stop, start and update' 1 "$GUIDE" '{ l[NR] = $0 } /^## Gmail and Microsoft 365$/ { t = NR } END { e = t; while (e < NR && l[e + 1] !~ /^## /) e++; for (i = 1; i <= NR; i++) { if (t && i >= t && i <= e) continue; print l[i] } for (j = t; j <= e; j++) print l[j] }' chk_gmail_section
  st_append 'a least-privilege claim in GUIDE.md' 'The measured list is the least privilege that works.' chk_gmail_section
  st 'a minimum-privilege claim in README.md, docs/ or release/' 2 "$priv" '{ print } END { print "This is the minimum privilege."}' chk_gmail_section
  finish gmail-section 'the mailbox bullet and the Gmail and Microsoft 365 section are the approved text, in place, linked by their anchor, with no least-privilege wording anywhere' chk_gmail_section
}

rule_telegram_section() {
  local n
  rule_begin telegram-section "$GUIDE" || return
  st 'the heading renamed' 1 "$GUIDE" '/^## Telegram$/ { print "## Phones"; next } { print }' chk_telegram_section
  st 'the section removed' 1 "$GUIDE" '/^## Telegram$/ { skip = 1; next } skip && /^## / { skip = 0 } !skip' chk_telegram_section
  st_facts chk_telegram_section "$TG_FACTS"
  for n in 1 2 3 4 5; do
    st "step $n removed" 1 "$GUIDE" "/^## / { s = (\$0 == \"## Telegram\") } !(s && /^$n\\. /)" chk_telegram_section
  done
  st 'a sixth step' 1 "$GUIDE" '/^5\. / { print; print "6. One more."; next } { print }' chk_telegram_section
  st 'the section above Sign in' 1 "$GUIDE" '{ l[NR] = $0 } /^## Telegram$/ { t = NR } END { e = t; while (e < NR && l[e + 1] !~ /^## /) e++; for (i = 1; i <= NR; i++) { if (l[i] == "## Sign in") for (j = t; j <= e; j++) print l[j]; if (t && i >= t && i <= e) continue; print l[i] } }' chk_telegram_section
  finish telegram-section 'the Telegram section sits after Sign in with five steps and the facts a person needs to follow them' chk_telegram_section
}

rule_telegram_strings() {
  local str src kind file out
  rule_begin telegram-strings "$GUIDE" || return
  chk_telegram_strings_real() { chk_telegram_strings "$1" "$railview_p" "$cardview_p" "$buttons_p"; }
  st 'Telegram not set up reworded' 1 "$GUIDE" '{ sub(/"Telegram not set up"/, "\"Telegram is not set up\"") } { print }' chk_telegram_strings_real
  st 'Telegram paired reworded' 1 "$GUIDE" '{ sub(/"Telegram paired"/, "\"Paired with Telegram\"") } { print }' chk_telegram_strings_real
  st 'Unpair reworded' 1 "$GUIDE" '{ sub(/"Unpair"/, "\"Disconnect\"") } { print }' chk_telegram_strings_real
  st 'Approve reworded' 1 "$GUIDE" '{ sub(/"Approve"/, "\"Yes\"") } { print }' chk_telegram_strings_real
  st 'a new quoted string' 1 "$GUIDE" '/^1\. In Telegram/ { $0 = $0 " Tap \"Pair now\"." } { print }' chk_telegram_strings_real
  st 'a quoted string unquoted' 1 "$GUIDE" '{ sub(/"Reject"/, "Reject") } { print }' chk_telegram_strings_real
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
      RAIL) out=$(chk_telegram_strings "$GUIDE" "$tmp/m" "$cardview_p" "$buttons_p") ;;
      CARD) out=$(chk_telegram_strings "$GUIDE" "$railview_p" "$tmp/m" "$buttons_p") ;;
      *) out=$(chk_telegram_strings "$GUIDE" "$railview_p" "$cardview_p" "$tmp/m") ;;
    esac
    if [ -z "$out" ]; then st_note "the built page without \"$str\" is not flagged"; fi
  done <<EOT
$TG_UI
EOT
  finish telegram-strings 'every UI string the Telegram section quotes is shown by the built page' chk_telegram_strings_real
}

rule_telegram_facts() {
  rule_begin telegram-facts "$GUIDE" "$included_p" "$layoutview_p" || return
  st 'the pause reworded to 10 minutes' 1 "$GUIDE" '{ sub(/after 5 minutes/, "after 10 minutes") } { print }' chk_telegram_facts
  st 'the pause time removed' 1 "$GUIDE" '{ sub(/ and tries again after 5 minutes/, "") } { print }' chk_telegram_facts
  st 'the narrower-window phrase dropped from step 5' 1 "$GUIDE" '{ sub(/ \(in a narrower window, open it with the Status button at the top of the page\)/, "") } { print }' chk_telegram_facts
  st 'the Status section renamed in step 5' 1 "$GUIDE" '{ sub(/In the Status section/, "In the Status band") } { print }' chk_telegram_facts
  st 'the address of step 5 changed' 1 "$GUIDE" '/^5\. / { sub(/localhost:52773/, "localhost:52774") } { print }' chk_telegram_facts
  st 'step 5 without an address' 1 "$GUIDE" '/^5\. / { sub(/http:\/\/localhost:52773\/ocutalon\//, "the page") } { print }' chk_telegram_facts
  st 'PAUSESECONDS changed' 2 "$included_p" '{ sub(/Parameter PAUSESECONDS = 300;/, "Parameter PAUSESECONDS = 600;") } { print }' chk_telegram_facts
  st 'the page region renamed' 3 "$layoutview_p" "{ sub(/status: 'Status',/, \"status: 'State',\") } { print }" chk_telegram_facts
  TGF_ENV=$tmp/env.broken
  sed 's/^TELEGRAM_BOT_TOKEN=/TELEGRAM_TOKEN=/' "$envexample_p" > "$TGF_ENV"
  if [ -z "$(chk_telegram_facts "$GUIDE" "$included_p" "$layoutview_p")" ]; then st_note '.env.example without the TELEGRAM_BOT_TOKEN= line is not flagged'; fi
  TGF_ENV=$envexample_p
  TGF_COMPOSE=$tmp/compose.broken
  sed 's/- path: \.env$/- path: .env.local/' "$compose_p" > "$TGF_COMPOSE"
  if [ -z "$(chk_telegram_facts "$GUIDE" "$included_p" "$layoutview_p")" ]; then st_note 'a compose file that does not read .env is not flagged'; fi
  TGF_COMPOSE=$compose_p
  finish telegram-facts 'the pause time, the Status section, the token line, the compose env file and the address of the steps are what is built' chk_telegram_facts
}

rule_telegram_demo() {
  rule_begin telegram-demo "$README" "$GUIDE" || return
  st_append 'a sentence about the online demo that mentions Telegram' 'The online demo also sends Telegram notices.' chk_telegram_demo
  st_append 'a sentence about the online demo that mentions pairing' 'Pairing works in the online demo.' chk_telegram_demo
  st_append 'a sentence about the online demo that mentions a paired chat' 'The online demo keeps your paired chat.' chk_telegram_demo
  st_append 'a sentence about the demo address that mentions a paired phone' 'Visit https://demo.ocutalon.com with your paired phone.' chk_telegram_demo
  st_append 'a Telegram sentence outside the section that does not say your own install' 'You can approve it in Telegram too.' chk_telegram_demo
  st 'the Telegram row without your own install' 2 "$GUIDE" '/^\| Telegram \|/ { gsub(/your own install/, "ZZ") } { print }' chk_telegram_demo
  st 'the use case without your own install' 2 "$GUIDE" '/^- \*\*The partner feed/ { sub(/On your own install you/, "You") } { print }' chk_telegram_demo
  st 'a sentence about the online demo that mentions Telegram, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "The online demo also sends Telegram notices." }' chk_telegram_demo
  st 'a Telegram sentence in the guide outside the section that does not say your own install' 2 "$GUIDE" '{ print } END { print ""; print "You can approve it in Telegram too." }' chk_telegram_demo
  finish telegram-demo 'no sentence of the README or the guide about the online demo mentions Telegram, and the other mentions say your own install' chk_telegram_demo
}

rule_readme_links() {
  rule_begin readme-links "$README" "$GUIDE" || return
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
  st_append 'two headings with one slug' '## Measured' chk_readme_links
  st 'a shields.io badge below the header' 1 "$README" 'NR <= '"$HEADER_LINES"' && /img\.shields\.io/ { b = $0 } { print } END { print ""; print b }' chk_readme_links
  st 'the header logo address below the header' 1 "$README" 'NR == 1 { b = $0 } { print } END { print ""; print b }' chk_readme_links
  st 'a header badge from another host' 1 "$README" 'NR <= '"$HEADER_LINES"' && !done && /img\.shields\.io/ { sub(/img\.shields\.io/, "badgen.net"); done = 1 } { print }' chk_readme_links
  st 'an HTML link to a heading that is not there' 1 "$README" '{ print } END { print ""; print "<a href=\"#nowhere\">x</a>" }' chk_readme_links
  st 'an HTML image of a file that is not there' 1 "$README" '{ print } END { print ""; print "<img src=\"docs/missing.png\" alt=\"x\">" }' chk_readme_links
  # A link by the GitHub slug of a heading (Design Note 8) is not flagged: the arrow, the apostrophe and the parentheses are dropped,
  # the spaces around the arrow stay (two hyphens), and a hyphen of the heading stays. The copy gets its own heading with the arrow.
  awk -v arrow="$ARROW" '{ print } END { print ""; print "## Contest task " arrow " where to see it"; print "[a](#contest-task--where-to-see-it) [b](#whats-interesting) [c](#for-judges-where-to-look) [d](#one-incident-end-to-end)" }' "$README" > "$tmp/slug.md"
  if [ -n "$(chk_readme_links "$tmp/slug.md" "$GUIDE")" ]; then st_note 'a link by the GitHub slug of a heading is flagged'; fi
  awk '{ print } END { print ""; print "[c](#stop-start-and-update) [d](#the-iris-non-health-image) [e](#change-the-readme-accounts-password) [f](README.md#measured)" }' "$GUIDE" > "$tmp/slug.guide.md"
  if [ -n "$(chk_readme_links "$README" "$tmp/slug.guide.md")" ]; then st_note 'a link by the GitHub slug of a guide heading is flagged'; fi
  st_append 'a GUIDE.md anchor that is not there' "[x]($GUIDE_URL#nowhere)" chk_readme_links
  st_append 'a README anchor of the repository address that is not there' '[x](https://github.com/jbrandtmse/OcuTalon#nowhere)' chk_readme_links
  st_append 'a relative link to GUIDE.md with an anchor' '[x](GUIDE.md#troubleshooting)' chk_readme_links
  st_append 'a relative link to GUIDE.md' '[x](GUIDE.md)' chk_readme_links
  st 'README.md#measured with the Measured heading renamed' 1 "$README" '/^## Measured$/ { print "## Measurements"; next } { print }' chk_readme_links
  st 'a guide heading renamed that a README link reaches' 2 "$GUIDE" '/^## Troubleshooting$/ { print "## Problems"; next } { print }' chk_readme_links
  st 'a link to a heading that is not there, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "[x](#nowhere)" }' chk_readme_links
  st 'a README.md link to a heading that is not there, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "[x](README.md#nowhere)" }' chk_readme_links
  st 'a link to a file that is not there, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "[x](docs/missing.md)" }' chk_readme_links
  st 'a link to a host off the list, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "[x](https://example.org/a)" }' chk_readme_links
  st 'a bare address off the list, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "See http://example.org/a for more." }' chk_readme_links
  st 'an HTML link to a heading that is not there, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "<a href=\"#nowhere\">x</a>" }' chk_readme_links
  st 'a shields.io image in the guide' 2 "$GUIDE" '{ print } END { print ""; print "<img src=\"https://img.shields.io/badge/a-b-blue\" alt=\"x\">" }' chk_readme_links
  st 'two headings with one slug, in the guide' 2 "$GUIDE" '{ print } END { print ""; print "## Sign in" }' chk_readme_links
  finish readme-links 'every link of the README and the guide, Markdown or HTML, reaches a heading of the file it names, a file or folder of the repository, or an allow-listed host, and img.shields.io only in the header block' chk_readme_links
}

# ra_run <README copy> <repository path> <text>: chk_readme_anchors on a documentation set of one planted file with that text and that
# repository path, besides an empty GUIDE.md and an empty docs/ file.
ra_run() {
  mkdir -p "$tmp/ra"
  : > "$tmp/ra/empty.md"
  printf '%s\n' "$3" > "$tmp/ra/f.md"
  { printf 'GUIDE.md\t%s\n' "$tmp/ra/empty.md"; printf 'docs/pad.md\t%s\n' "$tmp/ra/empty.md"; printf '%s\t%s\n' "$2" "$tmp/ra/f.md"; } > "$tmp/ra/list"
  chk_readme_anchors "$1" "$tmp/ra/list" "$GUIDE"
}

# ra_expect <label> <README copy> <repository path> <text> <count>: the checker flags exactly <count> lines of the text.
ra_expect() {
  local n
  n=$(ra_run "$2" "$3" "$4" | grep -c '^readme-anchors: ')
  if [ "$n" -ne "$5" ]; then st_note "$1: $n lines flagged, $5 expected"; fi
}

# ra_line <label> <README copy> <repository path> <text> <line>: the checker's output for the text is exactly that line.
ra_line() {
  local out
  out=$(ra_run "$2" "$3" "$4")
  if [ "$out" != "$5" ]; then st_note "$1: the output is not '$5'"; fi
}

rule_readme_anchors() {
  local m="$tmp/ra/M.md" form path text out n kept
  rule_begin readme-anchors "$README" "$tmp/ra.list" "$GUIDE" || return
  mkdir -p "$tmp/ra"
  printf '%s\n' "$listing" | doc_files | while IFS= read -r path; do printf '%s\t%s\n' "$path" "$path"; done > "$tmp/ra.list"
  # The documentation set: Markdown files, but not the root README, the build records or the release records.
  out=$(printf '%s\n' GUIDE.md CLAUDE.md docs/a.md eval/x/y.md release/demo-host-checks.md web/README.md newdir/z.md README.md _bmad/x.md _bmad-output/x.md .claude/x.md release/records/1.0.0/rc4.md docs/b.markdown docs/c.txt | doc_files)
  if [ "$out" != "$(printf '%s\n' GUIDE.md CLAUDE.md docs/a.md eval/x/y.md release/demo-host-checks.md web/README.md newdir/z.md docs/b.markdown)" ]; then st_note 'the documentation set is not the Markdown files but the root README, the build records and the release records'; fi
  # The set fails closed without the guide or without a docs/ file.
  st 'the documentation set without GUIDE.md' 2 "$tmp/ra.list" '$0 !~ /^GUIDE\.md\t/' chk_readme_anchors
  st 'the documentation set without a docs/ file' 2 "$tmp/ra.list" '$0 !~ /^docs\//' chk_readme_anchors
  # The real README with the Measured heading renamed: a planted link to it is flagged.
  if mutate "$README" '/^## Measured$/ { print "## Measurements"; next } { print }'; then
    ra_expect 'README.md#measured with the Measured heading renamed' "$tmp/m" GUIDE.md '[a](README.md#measured)' 1
  else
    st_note 'README.md#measured with the Measured heading renamed: the edit changed nothing'
  fi
  # M is a README with one heading, Measured (slug measured).
  printf '# Title\n\n## Measured\n\ntext\n' > "$m"
  # Every form of a link that reaches a heading is live, and with a dead anchor each form is flagged alone.
  ra_expect 'a live link of every form, in a root file' "$m" GUIDE.md $'[a](README.md#measured)\n[b](./README.md#measured)\n[r]: README.md#measured\n<a href="README.md#measured">x</a>\n[q](README.md?plain=1#measured)' 0
  ra_expect 'a live link of every form, in docs/' "$m" docs/x.md $'[c](../README.md#measured)\n[d](/README.md#measured)\n[e](https://github.com/jbrandtmse/OcuTalon/blob/main/README.md#measured)\n[f](https://github.com/jbrandtmse/OcuTalon/blob/HEAD/README.md#measured)\n<https://github.com/jbrandtmse/OcuTalon#measured>\nhttps://github.com/jbrandtmse/OcuTalon#readme\n[g](https://github.com/jbrandtmse/OcuTalon/#readme)\nSee https://github.com/jbrandtmse/OcuTalon#measured.\n![i](../README.md#measured)\nSee (https://github.com/jbrandtmse/OcuTalon#measured).\n[https://github.com/jbrandtmse/OcuTalon#measured](https://github.com/jbrandtmse/OcuTalon#measured)\nhttps://github.com/jbrandtmse/OcuTalon?tab=readme-ov-file#measured' 0
  ra_expect 'a live link two folders deep' "$m" eval/a/b.md '[x](../../README.md#measured)' 0
  while read -r path text; do
    ra_expect "a dead link: $text" "$m" "$path" "$text" 1
  done <<'EOT'
GUIDE.md [a](README.md#nowhere)
GUIDE.md [b](./README.md#nowhere)
GUIDE.md [r]: README.md#nowhere
GUIDE.md [r]: <README.md#nowhere>
GUIDE.md [^1]: see [x](README.md#nowhere)
GUIDE.md [a](<b) and [c](README.md#nowhere)
GUIDE.md <a href="README.md#nowhere">x</a>
GUIDE.md <a href='README.md#nowhere'>x</a>
GUIDE.md [q](README.md?plain=1#nowhere)
GUIDE.md [a](<README.md#nowhere>)
GUIDE.md ![a](README.md#nowhere)
docs/x.md [c](../README.md#nowhere)
docs/x.md [d](/README.md#nowhere)
docs/x.md [d](/docs/../README.md#nowhere)
eval/a/b.md [x](../../README.md#nowhere)
docs/x.md [e](https://github.com/jbrandtmse/OcuTalon/blob/main/README.md#nowhere)
docs/x.md [f](https://github.com/jbrandtmse/OcuTalon/blob/HEAD/README.md#nowhere)
docs/x.md <https://github.com/jbrandtmse/OcuTalon#nowhere>
docs/x.md https://github.com/jbrandtmse/OcuTalon#nowhere
docs/x.md https://github.com/jbrandtmse/OcuTalon/#nowhere
docs/x.md https://github.com/jbrandtmse/OcuTalon?tab=readme-ov-file#nowhere
docs/x.md See (https://github.com/jbrandtmse/OcuTalon#nowhere) and more.
docs/x.md See https://github.com/jbrandtmse/OcuTalon#nowhere.
docs/x.md <a href="https://github.com/jbrandtmse/OcuTalon#nowhere">x</a>
docs/x.md `x` [c](../README.md#nowhere)
docs/x.md [c](../README.md#)
docs/x.md [c](../README.md#readme)
docs/x.md [c](/README.md#readme)
EOT
  ra_expect 'a link that two forms match' "$m" docs/x.md '[https://github.com/jbrandtmse/OcuTalon#nowhere](https://github.com/jbrandtmse/OcuTalon#nowhere)' 1
  ra_expect 'a link in an HTML link and its text' "$m" docs/x.md '<a href="https://github.com/jbrandtmse/OcuTalon#nowhere">https://github.com/jbrandtmse/OcuTalon#nowhere</a>' 1
  ra_expect 'the dead links of a file, one line each' "$m" docs/x.md $'[a](../README.md#nowhere)\n[b](../README.md#measured)\n[c](../README.md#elsewhere)' 2
  ra_line 'the line of a dead link' "$m" docs/x.md $'text\n\nsee [a](../README.md#nowhere) and [b](../README.md#measured)' "readme-anchors: docs/x.md:3: the link (../README.md#nowhere) names '#nowhere', and README.md has no heading with that slug"
  # A heading renamed, a repeated heading and the case of an anchor.
  printf '# Title\n\n## Measurements\n' > "$tmp/ra/M.renamed.md"
  ra_line 'the Measured heading renamed' "$tmp/ra/M.renamed.md" GUIDE.md '[a](README.md#measured)' "readme-anchors: GUIDE.md:1: the link (README.md#measured) names '#measured', and README.md has no heading with that slug"
  printf '# Title\n\n## Measured\n\ntext\n\n## Measured\n' > "$tmp/ra/M.dup.md"
  ra_line 'a repeated heading: -1 is live and -2 is not' "$tmp/ra/M.dup.md" GUIDE.md $'[a](README.md#measured)\n[b](README.md#measured-1)\n[c](README.md#measured-2)' "readme-anchors: GUIDE.md:3: the link (README.md#measured-2) names '#measured-2', and README.md has no heading with that slug"
  ra_expect 'an anchor in the wrong case' "$m" GUIDE.md '[a](README.md#Measured)' 1
  # A README in another folder is not the root README.
  ra_line 'README.md from a folder that has none' "$m" ra-none/x.md '[x](README.md#measured)' "readme-anchors: ra-none/x.md:1: the link (README.md#measured) names ra-none/README.md, which is not a file of the tree"
  kept=$listing
  listing=$'ra-has/README.md\n'"$listing"
  ra_expect 'README.md from a folder that has one, which is not the root README' "$m" ra-has/x.md '[x](README.md#nowhere)' 0
  listing=$kept
  ra_line 'a path out of the repository' "$m" GUIDE.md '[x](../README.md#measured)' "readme-anchors: GUIDE.md:1: the link (../README.md#measured) leaves the repository"
  # Not a link: a code span, a fence of either kind, a pinned ref, another file and the page's own anchors.
  ra_expect 'an anchor in a code span' "$m" GUIDE.md $'`[x](README.md#nowhere)`\n``a ` [x](README.md#nowhere)``' 0
  ra_expect 'an anchor in a backtick fence' "$m" GUIDE.md $'```\n[x](README.md#nowhere)\n```' 0
  ra_expect 'an anchor in a tilde fence' "$m" GUIDE.md $'~~~\n[x](README.md#nowhere)\n~~~' 0
  ra_expect 'an anchor in a longer fence' "$m" GUIDE.md $'````\n```\n[x](README.md#nowhere)\n````' 0
  ra_expect 'a link after a fence' "$m" GUIDE.md $'```\nx\n```\n[x](README.md#nowhere)' 1
  ra_expect 'a link to a pinned ref' "$m" docs/x.md '[x](https://github.com/jbrandtmse/OcuTalon/blob/v1.0.0/README.md#nowhere)' 0
  ra_expect 'a link to a repository that only starts with this one' "$m" docs/x.md '[x](https://github.com/jbrandtmse/OcuTalon-fork#nowhere)' 0
  ra_expect 'a link to another file or to its own heading' "$m" docs/x.md $'[x](../GUIDE.md#nowhere)\n[y](#nowhere)\n[z](https://example.org/README.md#nowhere)\n[w](//example.org/README.md#nowhere)' 0
  # A README heading in a form that headings does not slug as GitHub does.
  for form in '## See [the link](x)' '## A <b>tag</b>' '## Closing ##' '## Trailing ' '##   Leading' '## See [the link][r]' '## A &amp; B' '## The _real_ thing' '## :tada: Party' '####### Seven'; do
    { cat "$m"; printf '\n%s\n' "$form"; } > "$tmp/ra/M.form.md"
    n=$(grep -c '' "$tmp/ra/M.form.md")
    out=$(ra_run "$tmp/ra/M.form.md" GUIDE.md '')
    case $out in
      "readme-anchors: README.md:$n: the heading '"*"' is not in a form this check slugs as GitHub does") ;;
      *) st_note "the heading '$form' is not flagged by its line" ;;
    esac
  done
  for form in '~~~' '````' ' ```'; do
    printf '# Title\n\n## Measured\n\n%s\n# x\n%s\n' "$form" "$form" > "$tmp/ra/M.fence.md"
    out=$(ra_run "$tmp/ra/M.fence.md" GUIDE.md '')
    if [ "$out" != "$(printf 'readme-anchors: README.md:5: a code fence in a form this check does not read as GitHub does\nreadme-anchors: README.md:7: a code fence in a form this check does not read as GitHub does')" ]; then st_note "a README fence '$form' is not flagged by its lines"; fi
  done
  printf '# Title\n\n## C# notes\n' > "$tmp/ra/M.hash.md"
  ra_expect 'a heading with a hash that does not close it' "$tmp/ra/M.hash.md" GUIDE.md '[a](README.md#c-notes)' 0
  finish readme-anchors 'every README anchor that a Markdown file outside README.md links, relative or by the repository address, is a heading slug of README.md as GitHub renders it' chk_readme_anchors
}

rule_must_scan() {
  rule_begin must-scan "$boundaries_p" || return
  st 'README.md gone from test-boundaries.sh' 1 "$boundaries_p" '{ gsub(/README\.md/, "ZZ.md"); print }' chk_must_scan
  st 'GUIDE.md gone from test-boundaries.sh' 1 "$boundaries_p" '{ gsub(/GUIDE\.md/, "ZZ.md"); print }' chk_must_scan
  st 'the list for paths and keys gone from test-boundaries.sh' 1 "$boundaries_p" '{ gsub(/not scanned for paths and keys/, "not scanned"); print }' chk_must_scan
  # GUIDE.md as the last entry of the list, before "; do", is found.
  printf 'for f in A.md \\\n  README.md B.md GUIDE.md; do\n  echo "  not scanned for paths and keys: $f"\ndone\n' > "$tmp/ms.sh"
  if [ -n "$(chk_must_scan "$tmp/ms.sh")" ]; then st_note 'GUIDE.md as the last entry of the list is not found'; fi
  finish must-scan "the must-scan list for paths and keys in $BOUNDARIES names $README and $GUIDE" chk_must_scan
}

rule_ipm() {
  rule_begin ipm "$GUIDE" "$ipmdoc_p" "$README" || return
  st 'the IPM section removed' 1 "$GUIDE" '!/^### Install it with IPM$/' chk_ipm
  st 'the IPM section above Check that it is ready' 1 "$GUIDE" '/^### Install it with IPM$/ { print "### Check that it is ready"; next } /^### Check that it is ready$/ { print "### Install it with IPM"; next } { print }' chk_ipm
  st 'the registry line and the first install swapped' 1 "$GUIDE" '/^zpm "enable -community"$/ { print "zpm \"install ocutalon\""; next } !done && /^zpm "install ocutalon"$/ { print "zpm \"enable -community\""; done = 1; next } { print }' chk_ipm
  st 'the registry line removed' 1 "$GUIDE" '!/^zpm "enable -community"$/' chk_ipm
  st 'the first install not said to run in USER' 1 "$GUIDE" '{ gsub(/terminal in USER, an/, "terminal in the instance, an") } { print }' chk_ipm
  st 'the link to docs/install-ipm.md changed' 1 "$GUIDE" '{ gsub(/\]\(docs\/install-ipm\.md\)/, "](docs/other.md)") } { print }' chk_ipm
  st 'any namespace said' 1 "$GUIDE" '{ print } /^This second run installs/ { print ""; print "Run it in any namespace." }' chk_ipm
  st 'the folder install before the registry install' 1 "$GUIDE" '{ print } /^### Install it with IPM$/ { print ""; print "```"; print "zpm \"load /x\""; print "```" }' chk_ipm
  st 'the repositories warning removed' 1 "$GUIDE" '!/^`enable -community` first removes the package repositories/' chk_ipm
  st 'the second run removed' 1 "$GUIDE" '!/^zn "OCUTALON"$/' chk_ipm
  st 'the page gives the folder install first' 2 "$ipmdoc_p" '/^zpm "enable -community"$/ { print; print "zpm \"load /x\""; next } { print }' chk_ipm
  st 'the page without the folder install' 2 "$ipmdoc_p" '!/^zpm "load/' chk_ipm
  st 'the IPM load line removed' 1 "$GUIDE" '!/^s r=##class\(%Net\.HttpRequest\)/' chk_ipm
  st 'the IPM load line on the latest version' 1 "$GUIDE" '{ sub(/zpm\/0\.10\.10\/installer/, "zpm/latest/installer") } { print }' chk_ipm
  st 'the map step removed' 1 "$GUIDE" '!/^zpm "enable -map -ns USER"$/' chk_ipm
  st 'the map step after the registry line' 1 "$GUIDE" '/^zpm "enable -map -ns USER"$/ { next } { print } /^zpm "enable -community"$/ { print "zpm \"enable -map -ns USER\"" }' chk_ipm
  st 'the IPM load line after the map step' 1 "$GUIDE" '/^s r=##class\(%Net\.HttpRequest\)/ { held = $0; next } { print } /^zpm "enable -map -ns USER"$/ { print held }' chk_ipm
  st 'the IPM load line twice in the section' 1 "$GUIDE" '{ print } /^s r=##class\(%Net\.HttpRequest\)/ { print }' chk_ipm
  st 'the IPM load line copied into another section' 1 "$GUIDE" '/^s r=##class\(%Net\.HttpRequest\)/ { keep = $0 } { print } END { print ""; print keep }' chk_ipm
  st 'the page without the IPM load line' 2 "$ipmdoc_p" '!/^s r=##class\(%Net\.HttpRequest\)/' chk_ipm
  st 'the page without the map step' 2 "$ipmdoc_p" '!/^zpm "enable -map -ns USER"$/' chk_ipm
  st 'the page with the map step after the registry line' 2 "$ipmdoc_p" '/^zpm "enable -map -ns USER"$/ { next } { print } /^zpm "enable -community"$/ { print "zpm \"enable -map -ns USER\"" }' chk_ipm
  st 'the local-repository sentence back' 2 "$ipmdoc_p" '{ print } END { print ""; print "Until the package is published, these outputs come from the same package installed from a local IPM repository." }' chk_ipm
  st 'the page reloading from a local repository' 2 "$ipmdoc_p" '{ sub(/\/usr\/irissys\/ipm\/ocutalon\/1\.0\.1\//, "/tmp/ocutalon-repo/ocutalon-0.1.0/") } { print }' chk_ipm
  st 'the page IPM load line on the latest version' 2 "$ipmdoc_p" '{ sub(/zpm\/0\.10\.10\/installer/, "zpm/latest/installer") } { print }' chk_ipm
  st 'the page registry reload line from another folder' 2 "$ipmdoc_p" '/^\[OCUTALON\|ocutalon\]\tReload START \(\/usr\/irissys\/ipm\/ocutalon\// { sub(/\/ocutalon\/1\.0\.1\//, "/other/1.0.1/") } { print }' chk_ipm
  st 'the page naming the local-repository path elsewhere' 2 "$ipmdoc_p" '{ print } END { print ""; print "The package was in /tmp/ocutalon-repo/ before." }' chk_ipm
  st 'the page registry reload line only in the folder install' 2 "$ipmdoc_p" '/^\[OCUTALON\|ocutalon\]\tReload START \(\/usr\/irissys\/ipm\/ocutalon\// { held = $0; next } { print } /^## Install from the package folder/ { print held }' chk_ipm
  st 'the page without the USER-installed IPM sentence' 2 "$ipmdoc_p" '{ sub(/ If IPM was installed in USER itself, they leave/, " They leave") } { print }' chk_ipm
  st 'the page claiming the same result for any USER IPM' 2 "$ipmdoc_p" '{ sub(/ mapped from %SYS\./, ".") } { print }' chk_ipm
  st 'the page with the any-USER-IPM sentence beside the new one' 2 "$ipmdoc_p" '{ sub(/The two commands give the same result when USER already had IPM mapped/, "The two commands give the same result when USER already had IPM. &") } { print }' chk_ipm
  printf '%s\n' "$IPM_LOAD" > "$tmp/ipm.readme"
  if [ -z "$(chk_ipm "$GUIDE" "$ipmdoc_p" "$tmp/ipm.readme")" ]; then st_note 'the IPM load line in the README as well is not flagged'; fi
  finish ipm 'the IPM section follows the image sections: IPM load line, map step, registry line, then the first install in USER, a link to the page with the same lines, no "any namespace"' chk_ipm
}

rule_licence() {
  rule_begin licence "$README" "$license_p" "$dockerfile_p" || return
  st 'the holder changed' 2 "$license_p" '/^Copyright/ { sub(/jbrandtmse/, "someone") } { print }' chk_licence
  st 'the year changed' 2 "$license_p" '/^Copyright/ { sub(/2026/, "2025") } { print }' chk_licence
  st 'a second copyright line' 2 "$license_p" '{ print } /^Copyright/ { print "Copyright (c) 2026 someone else" }' chk_licence
  st 'no holder line' 2 "$license_p" '!/^Copyright/' chk_licence
  st 'no grant paragraph' 2 "$license_p" '!/^Permission is hereby granted/' chk_licence
  st 'no condition paragraph' 2 "$license_p" '!/^The above copyright notice and this permission notice/' chk_licence
  st 'no warranty paragraph' 2 "$license_p" '!/^THE SOFTWARE IS PROVIDED/' chk_licence
  st 'the README line removed' 1 "$README" '!/^OcuTalon is under the MIT License: /' chk_licence
  st 'the README line changed' 1 "$README" '/^OcuTalon is under the MIT License: / { sub(/MIT/, "Apache") } { print }' chk_licence
  st 'the README line moved to another section' 1 "$README" '/^OcuTalon is under the MIT License: / { next } { print } /^## Measured$/ { print ""; print "OcuTalon is under the MIT License: [LICENSE](LICENSE)." }' chk_licence
  st 'the notices bullet removed' 1 "$README" '!/^- The Docker image.s Python packages for documents and memory/' chk_licence
  st 'the notices bullet changed' 1 "$README" '/^- The Docker image.s Python packages for documents and memory/ { sub(/credits in/, "credits at") } { print }' chk_licence
  st 'the notices path changed in the README' 1 "$README" '/^- The Docker image.s Python packages for documents and memory/ { sub(/THIRD-PARTY-NOTICES/, "THIRD-PARTY-NOTICES.txt") } { print }' chk_licence
  st 'the notices bullet moved above the IPM bullet' 1 "$README" '/^- The Docker image.s Python packages for documents and memory/ { held = $0; next } /^- The web page.s fonts/ { print held } { print }' chk_licence
  st 'the notices bullet twice' 1 "$README" '{ print } /^- The Docker image.s Python packages for documents and memory/ { print }' chk_licence
  st 'the notices path changed in the Dockerfile' 3 "$dockerfile_p" '/gate\.py notices/ { sub(/THIRD-PARTY-NOTICES/, "NOTICES") } { print }' chk_licence
  st 'the notices step removed from the Dockerfile' 3 "$dockerfile_p" '!/gate\.py notices/' chk_licence
  finish licence 'LICENSE holds the MIT grant, the warranty and the holder line, Credits and licences links it and names the image notices file the Dockerfile writes' chk_licence
}

rule_docs() {
  rule_begin docs "$bridgedoc_p" "$ipmdoc_p" "$secov_p" || return
  st 'the bridge guide without the build 109 sentence' 1 "$bridgedoc_p" '{ sub(/ Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet\./, "") } { print }' chk_docs
  st 'the bridge guide sentence changed' 1 "$bridgedoc_p" '{ sub(/has not been tested with this guide yet/, "has been tested with this guide") } { print }' chk_docs
  st 'the bridge guide sentence on a line of its own' 1 "$bridgedoc_p" '{ if (sub(/ Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet\./, "")) { print; print ""; print "Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet." } else print }' chk_docs
  st 'the IPM page without the build 109 sentence' 2 "$ipmdoc_p" '{ sub(/ Build 109, which the Early Access portal now offers in place of build 154, works the same way: the registry install on this page was run on fresh IRIS for Health instances of both builds\./, "") } { print }' chk_docs
  st 'the IPM page sentence changed' 2 "$ipmdoc_p" '{ sub(/was run on fresh IRIS for Health instances of both builds/, "has not been tested") } { print }' chk_docs
  st 'the approval section back to the exact call' 3 "$secov_p" 'index($0, "- It is fixed to exact targets and shows its dry run (a fix), or the tool") == 1 { print "- It is fixed to exact targets and shows its dry run (a fix) or the exact call (a tool call)."; next } { print }' chk_docs
  st 'the approval section line without its Telegram sentence' 3 "$secov_p" '{ sub(/ In Telegram, an approval request for a tool call that is too long for one message shows only its start, with no Approve button\./, "") } { print }' chk_docs
  st 'the MCP rules line without its Telegram sentence' 3 "$secov_p" '{ sub(/ A request too long to show in full on Telegram has no Approve button there\./, "") } { print }' chk_docs
  st 'the built-in tools without call_mcp_tool' 3 "$secov_p" '{ sub(/`send_email` and `call_mcp_tool`, which are classified per call\./, "`send_email`, which code classifies per call.") } { print }' chk_docs
  st 'the built-in tools paragraph without its last sentence' 3 "$secov_p" '{ sub(/ A risky MCP call waits for a person.s approval of that exact call, as the MCP tools section below describes\./, "") } { print }' chk_docs
  st 'the MCP rules back to the exact call' 3 "$secov_p" 'index($0, "- Every call passes the gate, an approval request when needed (showing the tool") == 1 { print "- Every call passes the gate, an approval request when needed (showing the exact call), an audit entry (read-only calls included) and an agent step."; next } { print }' chk_docs
  st 'the MCP rules line without the full call kept' 3 "$secov_p" '{ sub(/, with the full call kept in the approval record\), an audit entry/, "), an audit entry") } { print }' chk_docs
  st 'the MCP tools heading removed' 3 "$secov_p" '!/^## MCP tools$/' chk_docs
  st 'a heading between the MCP tools heading and the rules line' 3 "$secov_p" 'index($0, "- Every call passes the gate, an approval request when needed (showing the tool") == 1 { print "## Other"; print "" } { print }' chk_docs
  st 'the trace role sentence removed' 3 "$secov_p" 'index($0, "- Anyone with the trace role can read the content of every item") != 1' chk_docs
  st 'the email trace line removed' 3 "$secov_p" 'index($0, "- An email OcuTalon sends to the connected mailbox") != 1' chk_docs
  st 'the email trace line changed' 3 "$secov_p" '{ sub(/No email.s recipients are in the trace\./, "Recipients are in the trace.") } { print }' chk_docs
  st 'the email trace line loses its chat sentence' 3 "$secov_p" '{ sub(/ The trace does keep the chat.s messages as written, so an address or text that you or OcuTalon wrote in the chat is in it\./, "") } { print }' chk_docs
  st 'the email trace line moved down one bullet' 3 "$secov_p" 'index($0, "- An email OcuTalon sends to the connected mailbox") == 1 { held = $0; next } { print } index($0, "- The local (README) account holds all three roles.") == 1 && held != "" { print held; held = "" }' chk_docs
  st 'the trace role sentence changed' 3 "$secov_p" '{ sub(/an email.s sender, subject and text/, "an email subject") } { print }' chk_docs
  st 'the trace role sentence moved down one bullet' 3 "$secov_p" 'index($0, "- Anyone with the trace role can read the content of every item") == 1 { held = $0; next } { print } index($0, "- The local (README) account holds all three roles.") == 1 && held != "" { print held; held = "" }' chk_docs
  st 'the exact call promised elsewhere' 3 "$secov_p" '{ print } END { print ""; print "- It shows the exact call." }' chk_docs
  finish docs 'the build 109 sentences of the bridge guide and the IPM page and the ruled lines of the security overview, the ones about an approval request for a tool call included, are there, word for word' chk_docs
}

rule_word_cap() {
  local n
  rule_begin word-cap "$README" || return
  n=$(wc -w < "$README")
  n=$((n + 0))
  if [ "$n" -le "$WORD_CAP" ]; then
    # The limit itself: the README padded to exactly one word over the cap is flagged, and padded to exactly the cap it is not.
    st "exactly $((WORD_CAP + 1)) words" 1 "$README" "{ print } END { for (i = $n; i <= $WORD_CAP; i++) printf \"w \"; print \"\" }" chk_word_cap
    if ! mutate "$README" "{ print } END { for (i = $n; i < $WORD_CAP; i++) printf \"w \"; print \"\" }"; then
      st_note "exactly $WORD_CAP words: the edit changed nothing"
    elif [ -n "$(chk_word_cap "$tmp/m")" ]; then
      st_note "exactly $WORD_CAP words is flagged"
    fi
  fi
  st 'the README doubled' 1 "$README" '{ print } END { while ((getline l < FILENAME) > 0) print l }' chk_word_cap
  finish word-cap "wc -w of $README is at most $WORD_CAP" chk_word_cap
}

rule_guide() {
  rule_begin guide "$README" "$GUIDE" || return
  st 'the guide title reworded' 2 "$GUIDE" 'NR == 1 { sub(/guide:/, "manual:") } { print }' chk_guide
  st 'the guide title removed' 2 "$GUIDE" 'NR != 1' chk_guide
  st 'a line above the guide title' 2 "$GUIDE" 'NR == 1 { print "A stray line."; print "" } { print }' chk_guide
  st 'a guide section renamed' 2 "$GUIDE" '/^## Troubleshooting$/ { print "## Problems"; next } { print }' chk_guide
  st 'a guide section removed' 2 "$GUIDE" '!/^## Sign in$/' chk_guide
  st 'two guide sections swapped' 2 "$GUIDE" '/^## Sign in$/ { print "## Telegram"; next } /^## Telegram$/ { print "## Sign in"; next } { print }' chk_guide
  st 'a section added to the guide' 2 "$GUIDE" '{ print } END { print ""; print "## Extra"; print ""; print "More." }' chk_guide
  st 'the guide line of Tests and CI back to this README' 2 "$GUIDE" '{ sub(/among them the check of the README/, "among them the check of this README") } { print }' chk_guide
  st 'the pointer removed' 1 "$README" 'index($0, "The guide lists what is new since release 1.0.0") != 1' chk_guide
  st 'the pointer reworded' 1 "$README" '/^The guide lists what is new since release 1.0.0/ { sub(/your integrations/, "integrations") } { print }' chk_guide
  st 'the pointer twice' 1 "$README" '{ print } /^The guide lists what is new since release 1.0.0/ { print ""; print }' chk_guide
  st 'the More heading removed' 1 "$README" '!/^## More$/' chk_guide
  st 'the More heading twice' 1 "$README" '{ print } /^## More$/ { print ""; print }' chk_guide
  st 'the More paragraph removed' 1 "$README" 'index($0, "[The OcuTalon guide](") != 1' chk_guide
  st 'the More paragraph reworded' 1 "$README" '/^\[The OcuTalon guide\]/ { sub(/has the rest/, "has more") } { print }' chk_guide
  st 'the More paragraph without the link to the guide' 1 "$README" '/^\[The OcuTalon guide\]/ { sub(/^\[The OcuTalon guide\]\([^)]*\)/, "The OcuTalon guide") } { print }' chk_guide
  st 'the More paragraph without the Troubleshooting link' 1 "$README" '/^\[The OcuTalon guide\]/ { sub(/\[Troubleshooting\]\([^)]*\) and /, "") } { print }' chk_guide
  st 'the More paragraph with a link to a section that is not the guide'"'"'s' 1 "$README" '/^\[The OcuTalon guide\]/ { sub(/#troubleshooting\)/, "#problems)") } { print }' chk_guide
  st 'the More paragraph twice' 1 "$README" '{ print } /^\[The OcuTalon guide\]/ { print ""; print }' chk_guide
  st 'a stray line between the More heading and its paragraph' 1 "$README" '/^## More$/ { print; print ""; print "A stray line."; next } { print }' chk_guide
  finish guide 'GUIDE.md has its ruled title, its H2 sections in order and its ruled Tests and CI line; the README holds the ruled pointer and the More paragraph once each, and the More paragraph links the guide and each of its H2 sections' chk_guide
}

RULES='top word_cap guide try_it interesting measured comparison use_cases how_you_talk video checklist_video judges_usability path new_since teaser images once outcomes install install_pointer commands key_account lan sign_in_address demo_mode admin_commands admin_mcp after_start_log dev_only public_text gmail_section telegram_section telegram_strings telegram_facts telegram_demo no_telegram product_links readme_links readme_anchors must_scan ipm licence docs'
# The rules that name the guide: with no GUIDE.md each one fails closed.
GUIDE_RULES='admin_mcp guide comparison new_since use_cases how_you_talk images once teaser outcomes install install_pointer commands key_account lan sign_in_address demo_mode admin_commands after_start_log dev_only public_text no_telegram product_links readme_links ipm telegram_section telegram_strings telegram_facts telegram_demo readme_anchors gmail_section'

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

# With no GUIDE.md every rule that names it fails closed: each one, run as if the file were absent, must print a FAIL line that says so.
for r in $GUIDE_RULES; do
  out=$(have_guide=0; "rule_$r")
  case $out in
    FAIL*"$GUIDE is missing"*) ;;
    *)
      echo "FAIL no-guide: rule $r does not fail when $GUIDE is missing"
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
