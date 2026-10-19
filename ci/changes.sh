#!/usr/bin/env bash
# The classifier of the web and iris jobs (Story 0.7): decides which jobs run their steps, and from what base.
#   usage: ci/changes.sh <workflow file name, e.g. ci.yml> [--paths-from <file>]
# It prints, and appends to $GITHUB_OUTPUT when that is set, four lines:
#   base=<sha>      the newest commit of HEAD's history whose push run of this workflow concluded success (HEAD itself on a
#                   re-run of a green run), or nothing
#   web=<true|false>  a web input changed since the base (WEB_INPUT_PATTERN of ci/units.sh)
#   iris=<true|false> a path outside the pipeline's bookkeeping changed since the base
#   reason=<text>
# A skip only repeats a verdict that a green run reached on the same inputs, so a skip never turns a red into a green: on a
# pull request, with no such commit, and on any API error there is no base, and web and iris are both true.
# It reads GITHUB_EVENT_NAME, GITHUB_REPOSITORY, GITHUB_API_URL (default https://api.github.com) and GH_TOKEN (the job's
# read-only token), and uses git, curl and jq only. Test seams: OCUTALON_CI_RUNS_FILE is read in place of the runs API's
# answer, and --paths-from names a file of changed paths in place of `git diff --name-only <base> HEAD`.
set -u

# It works on the repository of the current directory (the job's checkout); the lists come from ci/units.sh beside this file.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/units.sh"

workflow=${1:-}
shift || true
paths_from=""
while [ $# -gt 0 ]; do
  case $1 in
    --paths-from)
      paths_from=${2:-}
      shift 2 || break
      ;;
    *) shift ;;
  esac
done
if [ -z "$workflow" ]; then
  echo "usage: ci/changes.sh <workflow file name> [--paths-from <file>]" >&2
  exit 2
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-chg.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

emit() { # emit <base> <web> <iris> <reason>
  local line
  for line in "base=$1" "web=$2" "iris=$3" "reason=$4"; do
    echo "$line"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$line" >> "$GITHUB_OUTPUT"; fi
  done
  exit 0
}

everything() { emit "" true true "$1: everything runs"; }

event=${GITHUB_EVENT_NAME:-}
if [ "$event" != push ]; then
  everything "event '${event:-none}' is not a push"
fi

# The runs of this workflow that concluded success on a push, newest first.
if [ -n "${OCUTALON_CI_RUNS_FILE:-}" ]; then
  cp "$OCUTALON_CI_RUNS_FILE" "$tmp/runs.json" 2>/dev/null || everything "the runs answer could not be read"
else
  if [ -z "${GITHUB_REPOSITORY:-}" ]; then everything "GITHUB_REPOSITORY is not set"; fi
  url="${GITHUB_API_URL:-https://api.github.com}/repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/runs?event=push&status=success&per_page=100"
  # The token goes to curl on its standard input, so that it is on no command line.
  if ! { printf 'header = "Accept: application/vnd.github+json"\nheader = "X-GitHub-Api-Version: 2022-11-28"\n'
    if [ -n "${GH_TOKEN:-}" ]; then printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN"; fi
  } | curl -fsS --max-time 30 --retry 2 -K - "$url" > "$tmp/runs.json" 2> "$tmp/curl.err"; then
    everything "the runs API failed"
  fi
fi
if ! jq -e '.workflow_runs | type == "array"' "$tmp/runs.json" >/dev/null 2>&1; then
  everything "the runs answer holds no run list"
fi
jq -r '.workflow_runs[] | select(.conclusion == "success" and .event == "push") | .head_sha' "$tmp/runs.json" > "$tmp/green.txt" 2>/dev/null
if [ ! -s "$tmp/green.txt" ]; then
  everything "no green push run of $workflow"
fi

# The first commit of HEAD's history with such a run.
base=$(git rev-list HEAD 2>/dev/null | grep -Fx -f "$tmp/green.txt" | head -n 1)
if [ -z "$base" ]; then
  everything "no green ancestor of HEAD"
fi

if [ -n "$paths_from" ]; then
  cp "$paths_from" "$tmp/paths.txt" 2>/dev/null || everything "the paths file could not be read"
else
  if ! git -c core.quotePath=false diff --name-only --no-renames "$base" HEAD > "$tmp/paths.txt" 2>/dev/null; then
    everything "the diff from $base failed"
  fi
fi

web=false
iris=false
n=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  n=$((n + 1))
  if printf '%s\n' "$path" | grep -Eq "$WEB_INPUT_PATTERN"; then web=true; fi
  if printf '%s\n' "$path" | grep -Eq "$NOT_BOOKKEEPING_PATTERN" || ! printf '%s\n' "$path" | grep -Eq "$BOOKKEEPING_PATTERN"; then iris=true; fi
done < "$tmp/paths.txt"

emit "$base" "$web" "$iris" "$n path(s) changed since the green run of $(printf '%.12s' "$base")"
