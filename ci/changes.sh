#!/usr/bin/env bash
# The classifier of the web and iris jobs (Story 0.7, 32.2): decides which jobs run their steps, and from what base.
#   usage: ci/changes.sh <workflow file name, e.g. ci.yml> [--group <iris group>] [--paths-from <file>]
# It prints, and appends to $GITHUB_OUTPUT when that is set (exit 1 when it cannot), these lines:
#   base=<sha>        the newest commit of HEAD's history whose push run of this workflow concluded success (HEAD itself on a
#                     re-run of a green run), or nothing
#   web=<true|false>  a web input changed since the base (WEB_INPUT_PATTERN of ci/units.sh)
#   run=<true|false>  with --group only: an input of that group changed since the base (group_input_pattern of ci/units.sh)
#   reason=<text>     with --group, why that group runs or skips; otherwise why the run-level answer is what it is
# and, to its standard output only, one line per group of IRIS_GROUPS in matrix order:
#   GROUP <name> run=<true|false>: <reason>
# A skip only repeats a verdict that a green run reached on the same inputs, so a skip never turns a red into a green. Every
# uncertain case has no base, web=true and every group running: an event that is not a push (a pull request), a push to main
# (REL-2 runs the demo path on every one of them), a force push (the payload says forced, or its before is not an ancestor of HEAD
# or is unknown here), a payload that cannot be read, no such commit, any error of the runs API, the base or the diff, and a push
# whose changed paths include one that no group pattern claims and that is neither bookkeeping nor in NOT_IRIS_INPUT_PATTERN (then
# web follows its pattern and every group runs, with the unclassified path as its reason).
# It reads GITHUB_EVENT_NAME, GITHUB_EVENT_PATH, GITHUB_REF, GITHUB_REPOSITORY, GITHUB_API_URL (default https://api.github.com)
# and GH_TOKEN (the job's read-only token), and uses git, curl, jq, grep and awk only. Test seams: OCUTALON_CI_RUNS_FILE is read
# in place of the runs API's answer, and --paths-from names a file of changed paths in place of
# `git diff --name-only <base> HEAD`.
set -u

# It works on the repository of the current directory (the job's checkout); the lists come from ci/units.sh beside this file.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/units.sh"

usage="usage: ci/changes.sh <workflow file name> [--group <name>] [--paths-from <file>]"
workflow=${1:-}
shift || true
paths_from=""
group=""
while [ $# -gt 0 ]; do
  case $1 in
    --paths-from)
      paths_from=${2:-}
      shift 2 || break
      ;;
    --group)
      group=${2:-}
      if [ -z "$group" ]; then
        echo "$usage" >&2
        exit 2
      fi
      shift 2
      ;;
    *) shift ;;
  esac
done
if [ -z "$workflow" ]; then
  echo "$usage" >&2
  exit 2
fi
if [ -n "$group" ]; then
  case " $IRIS_GROUPS " in
    *" $group "*) ;;
    *)
      echo "unknown group '$group'; groups: $IRIS_GROUPS" >&2
      exit 2
      ;;
  esac
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-chg.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')

output() { # output <name=value>: prints the line and appends it to $GITHUB_OUTPUT
  echo "$1"
  # An output that cannot be written would leave the job's gates empty, and the web job's gate (== 'true') skips on an empty web:
  # that is a failure.
  if [ -n "${GITHUB_OUTPUT:-}" ] && ! echo "$1" >> "$GITHUB_OUTPUT"; then
    echo "FAIL ci/changes.sh: cannot append to GITHUB_OUTPUT"
    exit 1
  fi
}

# emit <base> <web> <reason>: the outputs, then the GROUP lines. $tmp/groups.txt holds one line per group of IRIS_GROUPS: the
# group, its run flag and its reason, tab separated.
emit() {
  local base=$1 web=$2 reason=$3 g r why run="" run_reason=""
  while IFS=$tab read -r g r why; do
    if [ "$g" = "$group" ]; then
      run=$r
      run_reason=$why
    fi
  done < "$tmp/groups.txt"
  output "base=$base"
  output "web=$web"
  if [ -n "$group" ]; then
    output "run=$run"
    reason=$run_reason
  fi
  output "reason=$reason"
  while IFS=$tab read -r g r why; do
    echo "GROUP $g run=$r: $why"
  done < "$tmp/groups.txt"
  exit 0
}

everything() { # everything <why>: no base to trust, or no safe reading of the changes: every group runs
  local g
  for g in $IRIS_GROUPS; do printf '%s\ttrue\t%s\n' "$g" "$1: everything runs"; done > "$tmp/groups.txt"
  emit "" true "$1: everything runs"
}

# not_in <file of lines to leave out> <file>: the lines of <file> that are not lines of the first. awk reads the first file itself,
# because no reading of two files by position copes with an empty first file.
not_in() {
  EXCLUDE=$1 LC_ALL=C awk 'BEGIN { f = ENVIRON["EXCLUDE"]; while ((getline line < f) > 0) skip[line] = 1; close(f) } !($0 in skip)' "$2"
}

event=${GITHUB_EVENT_NAME:-}
if [ "$event" != push ]; then
  everything "event '${event:-none}' is not a push"
fi
if [ "${GITHUB_REF:-}" = refs/heads/main ]; then
  everything "push to main"
fi

# The push payload: a force push, or a payload that cannot be read, leaves no trustworthy base.
payload=${GITHUB_EVENT_PATH:-}
if [ -z "$payload" ]; then
  everything "GITHUB_EVENT_PATH is not set"
fi
forced=$(jq -r 'if (.forced | type) == "boolean" then (.forced | tostring) else "invalid" end' "$payload" 2>/dev/null) \
  || everything "the push event payload could not be read"
before=$(jq -r 'if (.before | type) == "string" then .before else "" end' "$payload" 2>/dev/null) \
  || everything "the push event payload could not be read"
case $forced in
  false) ;;
  true) everything "force push (the payload says forced)" ;;
  *) everything "the push event payload has no boolean forced" ;;
esac
if ! printf '%s\n' "$before" | grep -Eq '^[0-9a-fA-F]{40}$'; then
  everything "the push event payload has no 40-hex before"
fi
if [ "$before" != 0000000000000000000000000000000000000000 ]; then
  git merge-base --is-ancestor "$before" HEAD > /dev/null 2>&1
  case $? in
    0) ;;
    1) everything "force push (before $(printf '%.12s' "$before") is not an ancestor of HEAD)" ;;
    *) everything "force push (before $(printf '%.12s' "$before") is unknown here)" ;;
  esac
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

# The changed paths, one per line, without blank lines.
LC_ALL=C awk 'length' "$tmp/paths.txt" > "$tmp/changed.txt" || everything "the changed paths could not be read"
n=$(wc -l < "$tmp/changed.txt" | tr -d ' ')

LC_ALL=C grep -Eq -- "$WEB_INPUT_PATTERN" "$tmp/changed.txt"
case $? in
  0) web=true ;;
  1) web=false ;;
  *) everything "the web input pattern could not be applied" ;;
esac

# One decision per group: it runs when its pattern claims at least one changed path. The count comes from grep itself and not from
# a file, so a temporary file that cannot be written never reads as a group that claims nothing.
: > "$tmp/claimed-all.txt"
: > "$tmp/groups.txt"
for g in $IRIS_GROUPS; do
  pattern=$(group_input_pattern "$g") && [ -n "$pattern" ] || everything "the input pattern of $g could not be read"
  k=$(LC_ALL=C grep -cE -- "$pattern" "$tmp/changed.txt")
  if [ $? -gt 1 ]; then everything "the input pattern of $g could not be applied"; fi
  # A failed append leaves claimed-all.txt shorter, which can only add unclassified paths.
  LC_ALL=C grep -E -- "$pattern" "$tmp/changed.txt" >> "$tmp/claimed-all.txt"
  if [ "$k" -gt 0 ]; then
    printf '%s\ttrue\t%s\n' "$g" "$k input path(s) of $g changed since $base" >> "$tmp/groups.txt"
  else
    printf '%s\tfalse\t%s\n' "$g" "no input changed since $base" >> "$tmp/groups.txt"
  fi
done

# A changed path that no group claims must be declared: bookkeeping, or in NOT_IRIS_INPUT_PATTERN. Any other runs every group.
# A failing grep below leaves the declared set smaller, which can only add unclassified paths.
not_in "$tmp/claimed-all.txt" "$tmp/changed.txt" > "$tmp/unclaimed.txt" || everything "the unclaimed paths could not be found"
{
  LC_ALL=C grep -E -- "$NOT_IRIS_INPUT_PATTERN" "$tmp/unclaimed.txt"
  LC_ALL=C grep -E -- "$BOOKKEEPING_PATTERN" "$tmp/unclaimed.txt" | LC_ALL=C grep -Ev -- "$NOT_BOOKKEEPING_PATTERN"
} > "$tmp/declared.txt"
not_in "$tmp/declared.txt" "$tmp/unclaimed.txt" > "$tmp/unclassified.txt" || everything "the unclassified paths could not be found"
u=$(wc -l < "$tmp/unclassified.txt" | tr -d ' ')
if [ "$u" -gt 0 ]; then
  first=$(head -n 1 "$tmp/unclassified.txt" | LC_ALL=C tr -d '\000-\037')
  for g in $IRIS_GROUPS; do
    printf '%s\ttrue\t%s\n' "$g" "$u unclassified path(s) changed since $base, the first $first: every group runs"
  done > "$tmp/groups.txt"
fi

emit "$base" "$web" "$n path(s) changed since the green run of $(printf '%.12s' "$base")"
