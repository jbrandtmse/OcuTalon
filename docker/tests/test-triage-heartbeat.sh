#!/usr/bin/env bash
# The heartbeat paragraph of the Triage agent (Story 39.4; AD-7, AD-18). Starts nothing: it reads two files, so the hosted `checks` job runs it.
#   - paragraph: the quoted text of the `**Triage, heartbeat:**` entry of EXPERIENCE.md is not empty, and Agent/Triage.cls holds exactly that text as one
#     whole line (the paragraph of XData INSTRUCTIONS), and the text holds no template token.
# The rule first runs on a synthetic pair that breaks it and on one that keeps it, so a rule that can no longer flag anything fails. A failing rule
# prints what is wrong. Prints one PASS or FAIL line; exits 0 only when it passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

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
  fi
  if printf '%s\n' "$text" | grep -qF '{{'; then
    echo "paragraph: the text of '**Triage, heartbeat:**' holds a template token"
  fi
}

printf '%s\n' '- **Triage, heartbeat:** "An item on the channel heartbeat is the checklist."' > "$tmp/good-ux.md"
printf '%s\n' 'Class X' '{' 'Before.' '' 'An item on the channel heartbeat is the checklist.' '}' > "$tmp/good-triage.cls"
printf '%s\n' 'Class X' '{' 'An item on the channel heartbeat is the list.' '}' > "$tmp/bad-triage.cls"
printf '%s\n' '- **Triage, persona:** "Something else."' > "$tmp/no-ux.md"
printf '%s\n' '- **Triage, heartbeat:** "An item on the channel {{channel}}."' > "$tmp/token-ux.md"

fails=0
self=$(chk_paragraph "$tmp/good-ux.md" "$tmp/good-triage.cls")
if [ -n "$self" ]; then echo "FAIL paragraph: the rule flags a pair that keeps it: $self"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/good-ux.md" "$tmp/bad-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag a changed word"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/no-ux.md" "$tmp/good-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag an empty extraction"; fails=1; fi
if [ -z "$(chk_paragraph "$tmp/token-ux.md" "$tmp/good-triage.cls")" ]; then echo "FAIL paragraph: the rule does not flag a template token"; fails=1; fi

if [ "$fails" -eq 0 ]; then
  found=$(chk_paragraph "$EXPERIENCE" "$TRIAGE")
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    echo "FAIL paragraph"
    fails=1
  else
    echo "PASS paragraph"
  fi
fi
exit "$fails"
