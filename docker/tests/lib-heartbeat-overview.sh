#!/usr/bin/env bash
# The rule on the heartbeat sentences of docs/security-overview.md for docker/tests/test-triage-heartbeat.sh and docker/tests/test-heartbeat-overview.sh
# (Story 39.9; DW-785), sourced and never run: it holds no state and changes no file.

HEARTBEAT_OVERVIEW="docs/security-overview.md"
HEARTBEAT_BEAT_SENTENCE="A heartbeat check-in (a beat) sends the person's checklist and a status snapshot to the configured provider, at most once per interval."

# overview_bullet_rule <rule> <file> <sentence> <placed> <what> [<how>]: prints one line for each way the sentence is wrong in the file. The sentence must be in
# the whole file exactly once, and the text <placed> (the sentence itself, or a longer run that holds it) must be inside the line that starts
# `- In model requests to the configured provider` under `Data leaves the instance only:` with no heading between. <what> names the sentence in a line
# and <how> (empty by default) the way it must be placed; the lines start with <rule>.
overview_bullet_rule() {
  local rule=$1 file=$2 sentence=$3 placed=$4 what=$5 how=${6:-} total ok
  total=$(grep -oF -e "$sentence" "$file" | wc -l | tr -d ' ')
  if [ "$total" != "1" ]; then
    echo "$rule: $file holds $what $total times, not once"
  fi
  ok=$(P="$placed" awk '
    BEGIN { p = ENVIRON["P"]; sect = 0; ok = 0 }
    /^#/ { sect = 0 }
    $0 == "Data leaves the instance only:" { sect = 1; next }
    sect && index($0, "- In model requests to the configured provider") == 1 && index($0, p) > 0 { ok = 1 }
    END { print ok }' "$file")
  if [ "$ok" != "1" ]; then
    echo "$rule: $file does not hold $what$how in the line '- In model requests to the configured provider' under 'Data leaves the instance only:'"
  fi
}

# overview_after_rule <rule> <file> <sentence> <previous> <what>: prints one line for each way the bullet "- <sentence>" is wrong in the file. The sentence must be in the whole
# file exactly once, and that once must be a whole bullet (a line that is "- " and the sentence) whose line before it starts with <previous> (the text of the bullet it must
# follow). <what> names the sentence in a line; the lines start with <rule>.
overview_after_rule() {
  local rule=$1 file=$2 sentence=$3 previous=$4 what=$5 total ok
  total=$(grep -oF -e "$sentence" "$file" | wc -l | tr -d ' ')
  if [ "$total" != "1" ]; then
    echo "$rule: $file holds $what $total times, not once"
  fi
  ok=$(S="- $sentence" P="$previous" awk '
    BEGIN { s = ENVIRON["S"]; p = ENVIRON["P"]; ok = 0; prev = "" }
    $0 == s && index(prev, p) == 1 { ok = 1 }
    { prev = $0 }
    END { print ok }' "$file")
  if [ "$ok" != "1" ]; then
    echo "$rule: $file does not hold $what as its own bullet directly after the bullet that starts '$previous'"
  fi
}
