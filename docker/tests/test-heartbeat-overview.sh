#!/usr/bin/env bash
# The run-now sentence of the security overview (Story 39.2; DW-684, FR-66). Starts nothing: it reads one file, so the hosted `checks` job runs it.
#   - runnow: docs/security-overview.md holds the sentence "Run now sends the same kind of beat, at most once every 2 minutes per session and only within
#     the daily cost cap." exactly once in the whole file, that once is inside the line that starts `- In model requests to the configured provider` under
#     `Data leaves the instance only:` with no heading between, and it comes directly after the beat sentence ("A heartbeat check-in (a beat) sends the
#     person's checklist and a status snapshot to the configured provider, at most once per interval."), a space between.
# The overview rule is overview_bullet_rule of docker/tests/lib-heartbeat-overview.sh, which test-triage-heartbeat.sh shares.
# Each way of breaking the rule is first tried on a synthetic file that must be flagged, and a good one that must not be, so a rule that can no longer flag
# anything fails. A failing rule prints what is wrong. Prints one PASS or FAIL line for each rule; exits 0 only when every rule passes.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

. "$root/docker/tests/lib-heartbeat-overview.sh"

OVERVIEW="$HEARTBEAT_OVERVIEW"
BEAT="$HEARTBEAT_BEAT_SENTENCE"
SENTENCE="Run now sends the same kind of beat, at most once every 2 minutes per session and only within the daily cost cap."

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ho.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# chk_runnow <security-overview.md>: prints one line for each way the sentence is wrong (the rule is lib-heartbeat-overview.sh's)
chk_runnow() {
  overview_bullet_rule runnow "$1" "$SENTENCE" "$BEAT $SENTENCE" "the run-now sentence" " directly after the beat sentence"
}

# good_overview <text>: a synthetic overview whose model-requests bullet ends with the text, under the right heading
good_overview() {
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). A request carries the agent's instructions. $1"
  printf '%s\n' '- In messages on configured channels: the web page.' '' '## MCP tools' ''
}

good_overview "$BEAT $SENTENCE" > "$tmp/good.md"
good_overview "$BEAT" > "$tmp/none.md"
good_overview "$BEAT $SENTENCE $SENTENCE" > "$tmp/twice.md"
good_overview "$SENTENCE $BEAT" > "$tmp/before.md"
good_overview "$BEAT Something else. $SENTENCE" > "$tmp/apart.md"
good_overview "$BEAT  $SENTENCE" > "$tmp/spaces.md"
good_overview "$BEAT Run now sends the same kind of beat, at most once every 5 minutes per session and only within the daily cost cap." > "$tmp/word.md"
good_overview "$BEAT Run now sends the same kind of beat, at most once every 2 minutes per session and only within the daily cost cap" > "$tmp/nodot.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $BEAT"
  printf '%s\n' "- In messages on configured channels: the web page. $SENTENCE" ''
} > "$tmp/otherbullet.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $BEAT" '' '## MCP tools' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $BEAT $SENTENCE" ''
} > "$tmp/heading.md"
{
  printf '%s\n' '## Data' '' 'Data stays on the instance:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $BEAT $SENTENCE" ''
} > "$tmp/section.md"
{
  printf '%s\n' '## Data' '' 'Data leaves the instance only:' ''
  printf '%s\n' "- In model requests to the configured provider (Anthropic). $BEAT"
  printf '%s\n' "$SENTENCE" ''
} > "$tmp/ownline.md"

fails=0
self=$(chk_runnow "$tmp/good.md")
if [ -n "$self" ]; then echo "FAIL runnow: the rule flags an overview that keeps it: $self"; fails=1; fi
for bad in none twice before apart spaces word nodot otherbullet heading section ownline; do
  if [ -z "$(chk_runnow "$tmp/$bad.md")" ]; then echo "FAIL runnow: the rule does not flag the overview variant '$bad'"; fails=1; fi
done

if [ "$fails" -eq 0 ]; then
  found=$(chk_runnow "$OVERVIEW")
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    echo "FAIL runnow"
    fails=1
  else
    echo "PASS runnow"
  fi
fi
exit "$fails"
