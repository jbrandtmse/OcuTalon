#!/usr/bin/env bash
# The heartbeat paragraph of the Triage agent (Story 39.4; AD-7, AD-18). Starts nothing: it reads two files, so the hosted `checks` job runs it.
#   - paragraph: the quoted text of the `**Triage, heartbeat:**` entry of EXPERIENCE.md is not empty, and Agent/Triage.cls holds exactly that text as one
#     whole line, a paragraph of its own (a blank line before it, and a blank line or the end of the XData after it) inside XData INSTRUCTIONS, and the
#     text holds no template token.
#   - overview (Story 39.6; FR-64): docs/security-overview.md holds the sentence "A heartbeat check-in (a beat) sends the person's checklist and a status
#     snapshot to the configured provider, at most once per interval." exactly once in the whole file, and that once is inside the line that starts
#     `- In model requests to the configured provider`, under `Data leaves the instance only:` with no heading between.
# The overview rule is overview_bullet_rule of docker/tests/lib-heartbeat-overview.sh, which test-heartbeat-overview.sh shares.
# Each rule first runs on a synthetic pair that breaks it and on one that keeps it, so a rule that can no longer flag anything fails. A failing rule
# prints what is wrong. Prints one PASS or FAIL line for each rule; exits 0 only when every rule passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

. "$root/docker/tests/lib-heartbeat-overview.sh"

OVERVIEW="$HEARTBEAT_OVERVIEW"
SENTENCE="$HEARTBEAT_BEAT_SENTENCE"
EXPERIENCE="_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md"
TRIAGE="src/ocutalon/cls/OcuTalon/Agent/Triage.cls"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-th.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# chk_paragraph <EXPERIENCE.md> <Triage.cls>: prints one line for each way the paragraph is wrong
chk_paragraph() {
  local text
  text=$(sed -n 's/^- \*\*Triage, heartbeat:\*\* "\(.*\)"$/\1/p' "$1" | head -n 1)
  if [ -z "$text" ]; then
    echo "paragraph: $1 has no quoted text after '**Triage, heartbeat:**' (the extraction found none)"
    return
  fi
  if ! grep -qxF -e "$text" "$2"; then
    echo "paragraph: $2 does not hold the text of '**Triage, heartbeat:**' as one whole line, word for word"
  else
    # found = 1 when the line is inside XData INSTRUCTIONS, alone = 1 when the line before it is blank and the line after it is blank or ends the XData
    # (a paragraph of its own)
    placed=$(TEXT="$text" awk '
      BEGIN { t = ENVIRON["TEXT"]; state = 0; found = 0; alone = 0; prev = "x"; after = 0 }
      state == 0 && /^XData INSTRUCTIONS/ { state = 1; next }
      state == 1 && $0 == "{" { state = 2; prev = "x"; next }
      state == 2 && after { if ($0 != "" && $0 != "}") alone = 0; after = 0 }
      state == 2 && $0 == "}" { state = 3 }
      state == 2 { if ($0 == t) { found = 1; if (prev == "") { alone = 1; after = 1 } } prev = $0 }
      END { print found alone }' "$2")
    if [ "${placed%?}" != "1" ]; then
      echo "paragraph: $2 holds the text of '**Triage, heartbeat:**' outside XData INSTRUCTIONS"
    elif [ "${placed#?}" != "1" ]; then
      echo "paragraph: the text of '**Triage, heartbeat:**' is not a paragraph of its own in XData INSTRUCTIONS (a blank line must come before it, and a blank line or the end of the XData after it)"
    fi
  fi
  if printf '%s\n' "$text" | grep -qF '{{'; then
    echo "paragraph: the text of '**Triage, heartbeat:**' holds a template token"
  fi
}

# chk_overview <security-overview.md>: prints one line for each way the sentence is wrong (the rule is lib-heartbeat-overview.sh's)
chk_overview() {
  overview_bullet_rule overview "$1" "$SENTENCE" "$SENTENCE" "the sentence about a heartbeat check-in"
}

printf '%s\n' '- **Triage, heartbeat:** "An item on the channel heartbeat is the checklist."' > "$tmp/good-ux.md"
printf '%s\n' 'Class X' '{' 'XData INSTRUCTIONS [ MimeType = text/markdown ]' '{' 'Before.' '' 'An item on the channel heartbeat is the checklist.' '}' '}' > "$tmp/good-triage.cls"
printf '%s\n' 'Class X' '{' 'Parameter P = "' '' 'An item on the channel heartbeat is the checklist.' '";' 'XData INSTRUCTIONS [ MimeType = text/markdown ]' '{' 'Before.' '}' '}' > "$tmp/outside-triage.cls"
printf '%s\n' 'Class X' '{' 'XData INSTRUCTIONS [ MimeType = text/markdown ]' '{' 'Before.' 'An item on the channel heartbeat is the checklist.' '}' '}' > "$tmp/joined-triage.cls"
printf '%s\n' 'Class X' '{' 'An item on the channel heartbeat is the list.' '}' > "$tmp/bad-triage.cls"
printf '%s\n' '- **Triage, persona:** "Something else."' > "$tmp/no-ux.md"
printf '%s\n' 'Class X' '{' 'XData INSTRUCTIONS [ MimeType = text/markdown ]' '{' 'Before.' '' 'An item on the channel heartbeat is the checklist.' 'After.' '}' '}' > "$tmp/joined-after-triage.cls"
printf '%s\n' '- **Triage, heartbeat:** "An item on the channel {{channel}}."' > "$tmp/token-ux.md"
printf '%s\n' 'Class X' '{' 'XData INSTRUCTIONS [ MimeType = text/markdown ]' '{' 'Before.' '' 'An item on the channel {{channel}}.' '}' '}' > "$tmp/token-triage.cls"

# synthetic overviews: the good one, and one that breaks the rule in each way
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). A request carries the agent's instructions. $SENTENCE"
  printf '%s\n' '- In messages on configured channels: the web page.' '' '## MCP tools' ''
} > "$tmp/good-overview.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). A request carries the agent's instructions. A heartbeat check-in (a beat) sends the person's checklist and a status snapshot to the configured provider, at most once per day."
  printf '%s\n' '- In messages on configured channels: the web page.' ''
} > "$tmp/word-overview.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' '- In model requests to the configured provider (Anthropic). A request carries the agent'"'"'s instructions.'
  printf '%s\n' '- In messages on configured channels: the web page.' ''
} > "$tmp/none-overview.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $SENTENCE $SENTENCE"
  printf '%s\n' '- In messages on configured channels: the web page.' ''
} > "$tmp/twice-overview.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' '- In model requests to the configured provider (Anthropic). A request carries the agent'"'"'s instructions.'
  printf '%s\n' "- In messages on configured channels: the web page. $SENTENCE" ''
} > "$tmp/otherbullet-overview.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' '- In model requests to the configured provider (Anthropic). A request carries the agent'"'"'s instructions.' '' '## MCP tools' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $SENTENCE" ''
} > "$tmp/heading-overview.md"
{
  printf '%s\n' '## Data' '' 'Data stays on the instance:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $SENTENCE" ''
} > "$tmp/section-overview.md"
printf '%s\n' '## Data' '' 'Data leaves the instance only:' '' "- In model requests to the configured provider (Anthropic)." "$SENTENCE" '' > "$tmp/ownline-overview.md"

fails=0
self=$(chk_paragraph "$tmp/good-ux.md" "$tmp/good-triage.cls")
if [ -n "$self" ]; then echo "FAIL paragraph: the rule flags a pair that keeps it: $self"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/good-ux.md" "$tmp/bad-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag a changed word"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/good-ux.md" "$tmp/outside-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag the text outside XData INSTRUCTIONS"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/good-ux.md" "$tmp/joined-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag a paragraph that is joined to the one before"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/good-ux.md" "$tmp/joined-after-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag a paragraph that is joined to the one after"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/no-ux.md" "$tmp/good-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag an empty extraction"; fails=1; fi
if [ -n "$(chk_paragraph "$tmp/token-ux.md" "$tmp/token-triage.cls" | grep -v 'template token')" ] || [ -z "$(chk_paragraph "$tmp/token-ux.md" "$tmp/token-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag a template token on its own"; fails=1; fi

self=$(chk_overview "$tmp/good-overview.md")
if [ -n "$self" ]; then echo "FAIL overview: the rule flags an overview that keeps it: $self"; fails=1; fi
for bad in word none twice otherbullet heading section ownline; do
  if [ -z "$(chk_overview "$tmp/$bad-overview.md")" ]; then echo "FAIL overview: the rule does not flag the overview variant '$bad'"; fails=1; fi
done

if [ "$fails" -eq 0 ]; then
  found=$(chk_paragraph "$EXPERIENCE" "$TRIAGE")
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    echo "FAIL paragraph"
    fails=1
  else
    echo "PASS paragraph"
  fi
  found=$(chk_overview "$OVERVIEW")
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    echo "FAIL overview"
    fails=1
  else
    echo "PASS overview"
  fi
fi
exit "$fails"
