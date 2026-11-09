#!/usr/bin/env bash
# The six step 4 texts of Story 35.1 (AC 7), the ones EXPERIENCE.md's block "MCP servers and tools (step 4)" accepts and Catalog.Watch ships:
# the block holds exactly the six keys mcp.serverUnavailable, mcp.toolShadowsBuiltIn, mcp.toolChanged, mcp.replayToolChanged, mcp.sourceStopped
# and digest.notCheckedStopped, and for each key the text in the block equals the text of the key in Catalog.Watch character for character.
# Test.Msg.Catalog pins Catalog.Watch to its own fixtures; this script is the one pin that ties the two sides together. Reads files only
# (bash and awk), starts nothing, makes no network call. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

EXPERIENCE=_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md
WATCH=src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls
KEYS="mcp.serverUnavailable mcp.toolShadowsBuiltIn mcp.toolChanged mcp.replayToolChanged mcp.sourceStopped digest.notCheckedStopped"

fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# experience_rows <file>: "<key><TAB><text>" for each table row of the step 4 block (the key is the first backticked word of the Case cell,
# the text is the Text cell without its double quotes).
experience_rows() {
  awk '
    /^### MCP servers and tools \(step 4\)$/ { inblock = 1; next }
    inblock && /^##/ { inblock = 0 }
    inblock && /^\| / && !/^\| (Case|---)/ {
      line = $0
      if (match(line, /`[^`]+`/) == 0) next
      key = substr(line, RSTART + 1, RLENGTH - 2)
      n = index(line, "| \"")
      if (n == 0) next
      text = substr(line, n + 3)
      sub(/\" \|[ ]*$/, "", text)
      printf "%s\t%s\n", key, text
    }
  ' "$1"
}

# watch_text <file> <key>: the "text" of the key in the Entries of Catalog.Watch, as written in its JSON (these texts hold no escape).
watch_text() {
  awk -v key="$2" '
    $0 == " \"" key "\": {" { found = 1; next }
    found && /^  "text": "/ {
      text = substr($0, 12)
      sub(/",$/, "", text)
      print text
      exit
    }
    found && /^ }/ { exit }
  ' "$1"
}

[ -f "$EXPERIENCE" ] && [ -f "$WATCH" ] || { echo "FAIL the files are missing"; exit 1; }

rows=$(experience_rows "$EXPERIENCE")
found=$(printf '%s\n' "$rows" | awk -F'\t' 'NF { print $1 }' | tr '\n' ' ')
if [ "$found" = "$KEYS " ]; then
  pass "keys: the block holds the six keys, in the accepted order"
else
  fail "keys: the block holds [${found% }] and not the six accepted keys"
fi

for key in $KEYS; do
  experience=$(printf '%s\n' "$rows" | awk -F'\t' -v key="$key" '$1 == key { print $2 }')
  watch=$(watch_text "$WATCH" "$key")
  if [ -z "$experience" ] || [ -z "$watch" ]; then
    fail "text $key: EXPERIENCE.md or Catalog.Watch has no text for it"
  elif [ "$experience" = "$watch" ]; then
    pass "text $key: EXPERIENCE.md and Catalog.Watch hold the same text"
  else
    fail "text $key: EXPERIENCE.md and Catalog.Watch differ"
  fi
done

if [ "$fails" -eq 0 ]; then
  echo "test-mcp-notices: all rules passed"
  exit 0
fi
echo "test-mcp-notices: $fails rule(s) failed"
exit 1
