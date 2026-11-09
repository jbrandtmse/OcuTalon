#!/usr/bin/env bash
# release/release.sh start --version <x.y.z> [--from release/<v>-rc<m> --pick <sha>...] [--integration <branch>] [--remote <name>] [--record <file>] [--rc <n>]
# release/release.sh next|resume|status [--version <v> --rc <n>]   (required when more than one state has steps left)
# Steps, in order: cut, stubs, image, overview, ipm, ipmcheck, push, ci, eval, upgrade, rehearsal, notes, checklist, hands-on  (Stories 11.16 and 11.18 extend STEPS)
# Exit: 0 step done, a gate phase done (NEXT <step>: the step stays current) or end of steps, 1 a step failed, 2 refused (nothing written),
#       4 stopped for the author's word, 5 waited: the lane's throwaway lock is busy, CI has not finished or the evaluation has not run
#       (nothing recorded; the next call runs the step again)
# State: ${OCUTALON_RELEASE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ocutalon/release}/<v>-rc<n>/
# Test seam: OCUTALON_RELEASE_NOW names a file of epoch seconds read one per clock read (unset: date -u +%s)
#
# The release sequence (Story 11.5; REL-1, REL-3, REL-7, REL-8, REL-9, REL-11, AD-22, AD-23, AD-29). It takes the integration branch to a
# release candidate, one short step per call, and keeps the candidate's record on the integration branch. It runs from the author's
# checkout and is the only place that writes release/records/<v>/rc<n>.md's "## Release sequence" section.
#
# start    refuses a wrong first version (the first release is 1.0.0), a tagged version, a checkout that is not clean and on the
#          integration branch at the remote's head, an --rc that is not the next number and a missing node, npm, docker or git; for
#          1.0.0 it asks the author to confirm the kit; it then creates the state and prints NEXT cut. It writes no branch and no record.
# next     runs the step that the state names (resume is the same command). A step that passes names the next one (NEXT <step>);
#          the last one ends the sequence. A stop (a step that fails, an ASK that is not answered yes, the hands-on stop, or the end of the steps) writes
#          the record, commits only that file on the integration branch, and asks to push that commit.
# status   prints STATE <v> rc<n> next <step>, RECORD <file>, the hands-on time and the record's result, and after a passed ipm step
#          ARTIFACT <absolute path> <bytes> <sha256>; it changes nothing.
#
# The steps. cut makes the candidate in a temporary clone inside the state folder (so the author's checkout is never switched): the
# integration head (or --from's candidate plus the cherry-picked --pick commits, each an integration-branch commit), one cut commit that
# sets module.xml and src/module.xml to the version, which fails when the two differ, and force-adds the built web bundle, then the branch release/<v>-rc<n> in the author's repository.
# A candidate branch is never moved, re-committed, force-pushed or deleted. image builds the candidate's own tree and reads
# /opt/ocutalon/version in the image, which must equal the version, and removes the check image. overview runs release/security-overview.sh on an
# export of the candidate's tree: a fresh generation of docs/security-overview.md against the committed sections, and the overview tests; a drift or a failure
# stops the release (the author runs the unit with --write on the integration branch, commits, and cuts the next candidate). ipm loads the root module.xml
# over a full export of the cut commit's tree, what the package registry does with the GitHub archive, and packs it with
# IPM in a throwaway container with no network, keeps the .tgz in the state folder (never in the repository), checks that it carries
# the module's name and version and every file of the committed web bundle byte for byte, and records its size and checksums in
# "## IPM artifact"; it sends nothing out. ipmcheck runs the FR-57 job's own command, release/ipm-install.sh, on an export of the candidate's
# tree with that artifact (OCUTALON_IPM_ARTIFACT): the exact artifact is installed from a local IPM repository on a fresh instance with no
# Node.js, signed in to and uninstalled, with USER's repository definitions unchanged; a failure stops the release before push, and the
# result is recorded in "## FR-57 job" (a WARN line and a Size: note when the artifact is over 5000000 bytes). push asks, then pushes the candidate branch. notes runs release/notes.sh for the draft,
# which stays uncommitted.
#
# The gates (Story 11.14; REL-1, REL-5, REL-6, REL-7, AD-29). stubs refuses an enabled production item whose class carries Parameter STUB = 1. ci reads, with gh run list, the push runs of ci and lane-a on the cut commit; each must succeed. eval judges the author's eval/run.sh --release-candidate result in <state>/eval; REL-5's override (eval/run.sh --override) is the only override. upgrade and rehearsal run release/upgrade-harness.sh and release/rehearse.sh of the candidate, one phase per call. checklist runs release/checklist.sh. A gate passes only when its script exits 0 and its own section reads Result: pass for this commit. hands-on stops and names the candidate to install; the Contest Planner records the author's hands-on pass (REL-7), or a carry-over, in the record's "## Hands-on pass" section, which this sequence only reads, and release.sh resume refuses (exit 2) until that section holds one for this commit (Story 11.15).
#
# The author's word. Each outward step prints "ASK <id> <question> [yes/no]" and reads one line of standard input; only "yes" goes on.
# End of input is no answer: STOPPED <id> waiting for the author's word, exit 4. No option or variable answers a question.
# Hands-on time is the sum of the windows from printing an ASK to reading its answer on one clock; it is kept in the state, written into
# the record at every stop, and WARN is printed when the version's sum is over 15 minutes (900 s). It refuses nothing.
#
# Pushes: exactly two, each on the author's word: the candidate branch, and the integration branch fast-forward with the record commit.
# Never a force, a tag, main or another ref. No value of the environment is ever printed.
# Output: PASS|FAIL|WAIT <step> <detail>, then RECORD <file> and RESULT <stopped|fail>; a WAIT prints only its own line (exit 5), and a
# passed ipm step also prints ARTIFACT <absolute path>. This script reports no pass for a release.
# Needs bash 3.2 or later, git, awk, tar, gzip, sha256sum or shasum, node, npm and docker (the base image of docker/Dockerfile for the
# image and ipm steps).
#
# Sourced, it defines its functions and runs nothing.
umask 077

rel_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$rel_root/release/lib-release.sh"
. "$rel_root/docker/tests/lib-live.sh"
. "$rel_root/docker/tests/lib-upgrade.sh"

# The ordered steps; step_<name> is the function of a step. A sibling story adds its name and its function.
STEPS="cut stubs image overview ipm ipmcheck push ci eval upgrade rehearsal notes checklist hands-on"
HANDS_TARGET=900
TAB=$(printf '\t')
KIT_VERSION=1.0.0

# --- output ---

refuse() {
  echo "REFUSED $*"
  exit 2
}

# --- the state ---

state_root() { release_state_root; }

sget() { env_get "$sfile" "$1"; }
sset() { env_set "$sfile" "$1" "$2"; }

# row_set <id> <result> <detail>: the row of a step, replacing an earlier one.
row_set() {
  local detail
  detail=$(printf '%s' "$3" | detail_clean)
  if [ -f "$rows" ]; then
    grep -v "^$1$TAB" "$rows" > "$rows.new"
    mv "$rows.new" "$rows"
  fi
  printf '%s\t%s\t%s\n' "$1" "$2" "$detail" >> "$rows"
}

# next_step <step>: the step after it in STEPS, or done.
next_step() {
  local s want=""
  for s in $STEPS; do
    if [ "$want" = yes ]; then
      echo "$s"
      return 0
    fi
    [ "$s" != "$1" ] || want=yes
  done
  echo done
}

# --- the clock and the author's word ---

# clock: epoch seconds, from the seam file when OCUTALON_RELEASE_NOW names one with a line left, else date -u +%s.
clock() {
  local f=${OCUTALON_RELEASE_NOW:-} v
  if [ -n "$f" ] && [ -s "$f" ]; then
    v=$(head -n 1 "$f")
    tail -n +2 "$f" > "$f.new" && mv "$f.new" "$f"
    case $v in
      '' | *[!0-9]*) ;;
      *)
        printf '%s\n' "$v"
        return 0
        ;;
    esac
  fi
  date -u +%s
}

HANDS_PENDING=0

# hands_add <seconds>: adds an answered window to the state, or to the pending sum before the state exists.
hands_add() {
  if [ -n "${sfile:-}" ] && [ -f "$sfile" ]; then
    sset handson $(($(sget handson) + $1))
  else
    HANDS_PENDING=$((HANDS_PENDING + $1))
  fi
}

# ask <id> <question>: prints the ASK line and reads one line. Returns 0 for yes, 1 for any other line, 2 at the end of input.
# The window from the printed question to the answer goes into the hands-on sum.
ask() {
  local t0 t1 line="" w
  t0=$(clock)
  printf 'ASK %s %s [yes/no]\n' "$1" "$2"
  if ! IFS= read -r line && [ -z "$line" ]; then
    return 2
  fi
  t1=$(clock)
  w=$((t1 - t0))
  [ "$w" -ge 0 ] || w=0
  hands_add "$w"
  [ "$line" = yes ]
}

# stopped <id>: the line of an unanswered question.
stopped() {
  echo "STOPPED $1 waiting for the author's word"
}

# fmt_dur <seconds>: "2 min 41 s", or "41 s" under a minute.
fmt_dur() {
  if [ "$1" -ge 60 ]; then
    printf '%d min %d s' $(($1 / 60)) $(($1 % 60))
  else
    printf '%d s' "$1"
  fi
}

# earlier_hands <record dir> <rc>: the seconds that the records of the lower candidates of the folder give for "this candidate".
earlier_hands() {
  local dir=$1 rc=$2 f base m line sum=0
  for f in "$dir"/rc*.md; do
    [ -f "$f" ] || continue
    base=${f##*/}
    m=${base#rc}
    m=${m%.md}
    case $m in
      '' | *[!0-9]*) continue ;;
    esac
    [ "$m" -lt "$rc" ] || continue
    line=$(sed -n 's/^Hands-on time: \(.*\) for this candidate;.*/\1/p' "$f" | head -n 1)
    [ -n "$line" ] || continue
    sum=$((sum + $(printf '%s\n' "$line" | awk '$2 == "min" { print $1 * 60 + $3; next } { print $1 + 0 }')))
  done
  echo "$sum"
}

# hands_line <this seconds> <earlier seconds> <version>: the record's Hands-on time line; sets HANDS_OVER to 1 when over the target.
hands_line() {
  local total=$(($1 + $2)) over=""
  HANDS_OVER=0
  if [ "$total" -gt "$HANDS_TARGET" ]; then
    HANDS_OVER=1
    over=", over the 15-minute target"
  fi
  printf 'Hands-on time: %s for this candidate; %s for %s so far%s (target at most 15 min; CI and the hands-on pass not counted)\n' \
    "$(fmt_dur "$1")" "$(fmt_dur "$total")" "$3" "$over"
}

# --- the record ---

# record_abs: the record file as an absolute path.
record_abs() {
  case $record in
    /*) printf '%s\n' "$record" ;;
    *) printf '%s\n' "$rel_root/$record" ;;
  esac
}

# record_render <result>: the "## Release sequence" section, from the state and the rows.
record_render() {
  local from_line cut_line picks started id res det
  started=$(sget started)
  picks=$(sget picks_full)
  [ -n "$picks" ] || picks=$(sget picks)
  if [ -n "$(sget from)" ]; then
    from_line="$(sget from) at $(sget from_sha)"
    [ -z "$picks" ] || from_line="$from_line, then $picks cherry-picked from $integration"
  else
    from_line="$integration at $(sget base_sha)"
  fi
  if [ -n "$(sget cand_sha)" ]; then
    cut_line="$version rc$rc, $branch at $(sget cand_sha)"
  else
    cut_line="$version rc$rc, $branch (not cut yet)"
  fi
  {
    echo "## Release sequence"
    echo "Result: $1"
    echo "Mode: release"
    echo "Candidate: $cut_line"
    echo "Cut from: $from_line"
    hands_line "$(sget handson)" "$(earlier_hands "$(dirname "$(record_abs)")" "$rc")" "$version"
    echo "Run: $started to $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "| Step | Result | Detail |"
    echo "| --- | --- | --- |"
    for id in kit $STEPS record; do
      [ -f "$rows" ] || continue
      line=$(grep "^$id$TAB" "$rows" | tail -n 1)
      [ -n "$line" ] || continue
      res=$(printf '%s' "$line" | cut -f2)
      det=$(printf '%s' "$line" | cut -f3)
      printf '| %s | %s | %s |\n' "$id" "$res" "$det"
    done
  } > "$sdir/section.md"
}

# record_put <result>: renders the section and writes it into the record file.
record_put() {
  record_render "$1"
  record_write "$(record_abs)" "$sdir/section.md" "# OcuTalon $version rc$rc"
}

# record_relpath: the record's path below the checkout, empty when it is outside it.
record_relpath() {
  local abs
  abs=$(record_abs)
  case $abs in
    "$rel_root"/*) printf '%s\n' "${abs#"$rel_root"/}" ;;
  esac
}

# record_commit <fresh|amend>: commits the record file and nothing else on the integration branch, with an explicit pathspec.
# Sets REC_STATE to committed, unchanged or not-committed (and REC_WHY) and REC_SHA to HEAD.
REC_STATE=""
REC_WHY=""
REC_SHA=""
REC_OWN=0
record_commit() {
  local rel head
  rel=$(record_relpath)
  REC_WHY=""
  if [ -z "$rel" ]; then
    REC_STATE=not-committed
    REC_WHY="the record is outside the checkout"
    return 0
  fi
  head=$(git symbolic-ref --short -q HEAD < /dev/null 2> /dev/null)
  if [ "$head" != "$integration" ]; then
    REC_STATE=not-committed
    REC_WHY="the checkout is not on $integration"
    return 0
  fi
  git add -- "$rel" < /dev/null > /dev/null 2>&1
  if git diff --cached --quiet < /dev/null -- "$rel" 2> /dev/null && [ -z "$(git status --porcelain < /dev/null -- "$rel")" ]; then
    REC_STATE=unchanged
  elif [ "$1" = amend ] && [ "$REC_OWN" = 1 ] && [ "$(git rev-parse HEAD < /dev/null)" = "$REC_SHA" ]; then
    git commit -q --amend --no-edit < /dev/null -- "$rel" > /dev/null 2>&1 || {
      REC_STATE=not-committed
      REC_WHY="git commit failed"
      return 0
    }
    REC_STATE=committed
  else
    git commit -q -m "Record the release sequence of $version rc$rc" < /dev/null -- "$rel" > /dev/null 2>&1 || {
      REC_STATE=not-committed
      REC_WHY="git commit failed"
      return 0
    }
    REC_STATE=committed
    REC_OWN=1
  fi
  REC_SHA=$(git rev-parse HEAD < /dev/null)
  return 0
}

# record_only: succeeds when every commit that the record push would add to the remote (those after the start and after the remote's
# head, when that head is known here) changes this record or another candidate record (release/records/<v>/rc<n>.md) and
# nothing else; a draft, any other path, an empty commit or a merge (both list no path, and the empty line counts) fails it.
record_only() {
  local c paths rel not rhead
  rel=$(record_relpath)
  not=$(sget base_sha)
  rhead=$(git ls-remote "$remote" "refs/heads/$integration" < /dev/null 2> /dev/null | awk '{ print $1 }')
  if [ -n "$rhead" ] && git cat-file -e "$rhead^{commit}" < /dev/null 2> /dev/null; then not="$not $rhead"; fi
  for c in $(git rev-list "$REC_SHA" --not $not < /dev/null 2> /dev/null); do
    paths=$(git diff-tree --no-commit-id --name-only -r "$c" < /dev/null 2> /dev/null)
    paths=$(printf '%s\n' "$paths" | grep -vxF -e "$rel" | grep -Evx 'release/records/[^/]+/rc[0-9]+\.md' | wc -l | tr -d ' ')
    [ "$paths" -eq 0 ] || return 1
  done
  return 0
}

# record_push: the fast-forward push of the integration branch with the record commit. Prints one line and returns 0 when pushed,
# 1 when the remote's branch moved on, 2 for another failure.
record_push() {
  local log="$sdir/push.log"
  if LC_ALL=C git push -q "$remote" "$REC_SHA:refs/heads/$integration" < /dev/null > "$log" 2>&1; then
    rm -f "$log"
    return 0
  fi
  if grep -qiE 'rejected|non-fast-forward|fetch first' "$log"; then
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  return 2
}

# stop_routine <end|stopped|hands|failed> <step> <detail>: writes the record, commits it, asks to push it, and sets STOP_CODE.
STOP_CODE=0
stop_routine() {
  local kind=$1 step=$2 detail=$3 result last rec_detail code
  case $kind in
    end)
      last=$(printf '%s\n' $STEPS | tail -n 1)
      result="stopped after $last: no step after the gates has run (not a release)"
      STOP_CODE=0
      ;;
    hands)
      result="stopped at hands-on: every automated gate passed; no hands-on pass is recorded (not a release)"
      STOP_CODE=4
      ;;
    stopped)
      result="stopped at $step: waiting for the author's word"
      STOP_CODE=4
      ;;
    failed)
      result="failed at $step: $detail"
      STOP_CODE=1
      ;;
  esac
  result=$(printf '%s' "$result" | detail_clean)
  REC_SHA=""
  REC_OWN=0
  row_set record "committed, not pushed" "waiting for the author's word"
  record_put "$result"
  record_commit fresh
  echo "RECORD $(record_relpath_or_abs)"
  if [ "$REC_STATE" = not-committed ]; then
    sset rec_pushed na
    row_set record "not committed" "$REC_WHY"
    record_put "$result"
    echo "NOTE the record was written and not committed: $REC_WHY"
  elif ! record_only; then
    sset rec_pushed na
    row_set record "committed, not pushed" "$integration holds commits besides the record, so it was not offered for a push"
    record_put "$result"
    record_commit amend
    echo "NOTE $integration holds commits besides the record; the record commit is not pushed"
  else
    sset rec_pushed 0
    ask record "Push the record commit of $version rc$rc to $integration on $remote?"
    code=$?
    case $code in
      0)
        row_set record pushed "committed to $integration and pushed on the author's word"
        record_put "$result"
        record_commit amend
        if record_push; then
          sset rec_pushed 1
          echo "PASS record pushed"
        else
          code=$?
          [ "$code" -ne 0 ] || code=2
          if [ "$code" -eq 1 ]; then
            rec_detail="not pushed: $integration moved on $remote"
            echo "FAIL record $rec_detail; bring the checkout up to date and run release.sh resume (git pull --rebase: a merge is never offered for a push)"
          else
            rec_detail="not pushed: git push failed"
            echo "FAIL record $rec_detail"
          fi
          row_set record "not pushed" "$rec_detail"
          record_put "$result"
          record_commit amend
          sset rec_pushed 0
          [ "$STOP_CODE" -eq 4 ] || STOP_CODE=1
        fi
        ;;
      1)
        row_set record "committed, not pushed" "the author did not give the word"
        record_put "$result"
        record_commit amend
        sset rec_pushed 0
        echo "PASS record committed, not pushed"
        ;;
      *)
        row_set record "committed, not pushed" "the author's word was not given"
        record_put "$result"
        record_commit amend
        sset rec_pushed 0
        stopped record
        [ "$STOP_CODE" -ne 0 ] || STOP_CODE=4
        ;;
    esac
  fi
  if [ "$(hands_total)" -gt "$HANDS_TARGET" ]; then
    echo "WARN hands-on time $(fmt_dur "$(hands_total)") for $version is over the 15-minute target"
  fi
  case $kind in
    failed) echo "RESULT fail" ;;
    *) echo "RESULT stopped" ;;
  esac
}

record_relpath_or_abs() {
  local rel
  rel=$(record_relpath)
  if [ -n "$rel" ]; then printf '%s\n' "$rel"; else basename "$record"; fi
}

# hands_total: this candidate's seconds plus the earlier candidates' of the version.
hands_total() {
  echo $(($(sget handson) + $(earlier_hands "$(dirname "$(record_abs)")" "$rc")))
}

# --- the steps: each prints one PASS or FAIL line, sets STEP_ROW and STEP_DETAIL, and returns 0 (pass), 1 (fail) or 4 (not answered) ---

STEP_ROW=""
STEP_DETAIL=""

step_fail() { # step_fail <step> <detail>: the detail names no local path (the state folder, the checkout or the home folder)
  local d=$2 home_mark='~'
  [ -z "${sdir:-}" ] || d=${d//"$sdir"/<state>}
  d=${d//"$rel_root"/.}
  [ -z "${HOME:-}" ] || d=${d//"$HOME"/$home_mark}
  STEP_ROW=fail
  STEP_DETAIL=$(printf '%s' "$d" | detail_clean)
  echo "FAIL $1 $STEP_DETAIL"
  return 1
}

# base_image: the IRIS image that the image and ipm steps build on.
base_image() { printf '%s\n' "${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}"; }

# cut_clean: removes the temporary clone and the image context.
cut_clean() { rm -rf "$sdir/clone" "$sdir/context"; }

step_cut() {
  local clone="$sdir/clone" start_sha picks full p short out name email cand m
  if git rev-parse --verify --quiet "refs/heads/$branch" < /dev/null > /dev/null 2>&1; then
    step_fail cut "$branch already exists; a candidate is never moved, so start the next one"
    return 1
  fi
  cut_clean
  if [ -n "$(sget from)" ]; then start_sha=$(sget from_sha); else start_sha=$(sget base_sha); fi
  if ! git clone -q --shared "$rel_root" "$clone" < /dev/null > /dev/null 2>&1; then
    step_fail cut "the temporary clone failed"
    return 1
  fi
  name=$(git config user.name < /dev/null 2> /dev/null)
  email=$(git config user.email < /dev/null 2> /dev/null)
  [ -z "$name" ] || git -C "$clone" config user.name "$name"
  [ -z "$email" ] || git -C "$clone" config user.email "$email"
  if ! git -C "$clone" checkout -q -b cut "$start_sha" < /dev/null > /dev/null 2>&1; then
    cut_clean
    step_fail cut "the start commit ${start_sha%"${start_sha#???????}"} is not in the repository"
    return 1
  fi
  picks=""
  for p in $(sget picks); do
    full=$(git rev-parse --verify --quiet "$p^{commit}" < /dev/null 2> /dev/null)
    short=${p%"${p#???????}"}
    if [ -z "$full" ]; then
      cut_clean
      step_fail cut "pick $short is not a commit of this repository"
      return 1
    fi
    if ! git merge-base --is-ancestor "$full" "$(sget base_sha)" < /dev/null 2> /dev/null; then
      cut_clean
      step_fail cut "pick $short is not on $integration"
      return 1
    fi
    if ! git -C "$clone" cherry-pick -x "$full" < /dev/null > /dev/null 2>&1; then
      git -C "$clone" cherry-pick --abort < /dev/null > /dev/null 2>&1
      cut_clean
      step_fail cut "pick $short did not apply cleanly"
      return 1
    fi
    picks="${picks:+$picks }$full"
  done
  if [ "$(manifest_version "$clone/module.xml" 2> /dev/null)" != "$(manifest_version "$clone/src/module.xml" 2> /dev/null)" ]; then
    cut_clean
    step_fail cut "module.xml and src/module.xml hold different versions"
    return 1
  fi
  for m in module.xml src/module.xml; do
    stamp_version "$clone/$m" "$version" > "$clone/$m.new" && mv "$clone/$m.new" "$clone/$m"
    if [ "$(manifest_version "$clone/$m")" != "$version" ]; then
      cut_clean
      step_fail cut "$m has no <Version> to set"
      return 1
    fi
  done
  out=$(
    cd "$clone" || exit 1
    LIVE_REBUILD_WEB=1
    ensure_web_bundle < /dev/null 2>&1
  )
  if [ $? -ne 0 ]; then
    cut_clean
    out=$(printf '%s\n' "$out" | tail -n 1)
    step_fail cut "${out#FAIL }"
    return 1
  fi
  if [ ! -f "$clone/src/ocutalon/csp/index.html" ]; then
    cut_clean
    step_fail cut "the web build left no src/ocutalon/csp/index.html"
    return 1
  fi
  if ! git -C "$clone" add -f -- module.xml src/module.xml src/ocutalon/csp < /dev/null > /dev/null 2>&1 \
    || ! git -C "$clone" commit -q --allow-empty -m "Release $version rc$rc: set the version and add the built web bundle" < /dev/null > /dev/null 2>&1; then
    cut_clean
    step_fail cut "the cut commit failed"
    return 1
  fi
  cand=$(git -C "$clone" rev-parse HEAD < /dev/null)
  if ! git fetch -q "$clone" "refs/heads/cut:refs/heads/$branch" < /dev/null > /dev/null 2>&1 \
    || [ "$(git rev-parse "refs/heads/$branch" < /dev/null)" != "$cand" ]; then
    cut_clean
    step_fail cut "the candidate branch could not be created"
    return 1
  fi
  sset cand_sha "$cand"
  sset picks_full "$picks"
  rm -rf "$clone"
  STEP_ROW=pass
  STEP_DETAIL="module.xml and src/module.xml set to $version; web bundle built with Node.js and committed"
  [ -z "$picks" ] || STEP_DETAIL="$STEP_DETAIL; fixes cherry-picked: $(printf '%s\n' $picks | wc -l | tr -d ' ')"
  echo "PASS cut $cand"
  return 0
}

step_image() {
  local ctx="$sdir/context" tag base got log="$sdir/image.log"
  if [ -z "$(sget cand_sha)" ]; then
    step_fail image "the candidate is not cut"
    return 1
  fi
  base=$(base_image)
  tag="ocutalon-release-check:$version-rc$rc-$$"
  rm -rf "$ctx"
  mkdir -p "$ctx"
  if ! git archive "$(sget cand_sha)" < /dev/null | tar -x -C "$ctx"; then
    rm -rf "$ctx"
    step_fail image "the candidate's tree could not be exported"
    return 1
  fi
  if ! docker image inspect --format '{{.Id}}' "$base" < /dev/null > /dev/null 2>&1; then
    rm -rf "$ctx"
    step_fail image "the base image $base is missing; build or load it first (ci/iris.sh)"
    return 1
  fi
  if ! docker build -q -f "$ctx/docker/Dockerfile" --build-arg "IRIS_IMAGE=$base" -t "$tag" "$ctx" < /dev/null > "$log" 2>&1; then
    got=$(tail -n 2 "$log" | tr '\n' ' ')
    rm -rf "$ctx" "$log"
    step_fail image "docker build failed: $got"
    return 1
  fi
  rm -f "$log"
  got=$(docker run --rm --entrypoint cat "$tag" /opt/ocutalon/version < /dev/null 2> /dev/null | tr -d '\r\n')
  if [ "$got" != "$version" ]; then
    docker rmi -f "$tag" < /dev/null > /dev/null 2>&1
    rm -rf "$ctx"
    step_fail image "/opt/ocutalon/version reads '$got' in the image built from the candidate, wanted $version"
    return 1
  fi
  if ! docker run --rm --entrypoint test "$tag" -f /opt/ocutalon/src/ocutalon/csp/index.html < /dev/null > /dev/null 2>&1; then
    docker rmi -f "$tag" < /dev/null > /dev/null 2>&1
    rm -rf "$ctx"
    step_fail image "the image built from the candidate holds no web bundle"
    return 1
  fi
  if ! docker rmi -f "$tag" < /dev/null > /dev/null 2>&1; then
    rm -rf "$ctx"
    step_fail image "the check image $tag could not be removed"
    return 1
  fi
  cut_clean
  STEP_ROW=pass
  STEP_DETAIL="/opt/ocutalon/version reads $version in the image built from the candidate"
  echo "PASS image $got"
  return 0
}

# --- the overview step (Story 14.1) ---

# candidate_export <step> <folder>: exports the candidate's tree into the folder (emptied first). On a failure it prints the step's FAIL line,
# removes the folder and returns 1.
candidate_export() {
  local cand
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail "$1" "the candidate is not cut"
    return 1
  fi
  rm -rf "$2"
  mkdir -p "$2"
  if ! (set -o pipefail; git archive "$cand" < /dev/null | tar -x -C "$2"); then
    rm -rf "$2"
    step_fail "$1" "the candidate's tree could not be exported"
    return 1
  fi
  return 0
}

# candidate_lock_dir: the lane's throwaway lock folder of the author's repository, or nothing.
candidate_lock_dir() {
  (
    root=$rel_root
    live_lock_dir
  )
}

# step_overview: runs release/security-overview.sh in an export of the candidate's tree, so that the candidate's own code and its own
# docs/security-overview.md are the ones checked. An empty web/node_modules folder keeps the unit from installing the web dependencies, which it never
# reads. The lane's throwaway lock folder, when the author's repository has one, is handed to the unit. Exit 0 of the unit is PASS, exit 75 is
# WAIT (nothing is recorded; the next call runs the step again), anything else fails the step with the first DRIFT or FAIL line of the unit,
# and the release stops. "Regenerates" means a fresh generation from the candidate's code compared with the candidate's committed sections;
# the author runs the unit with --write on the integration branch, commits, and cuts the next candidate. A failing unit's log is kept as
# overview-fail.log in the release state folder (a pass removes it), and its absolute path is printed on a LOG line right after the FAIL line.
step_overview() {
  local ctx="$sdir/overview" log="$sdir/overview.log" lockdir code line kept
  candidate_export overview "$ctx" || return 1
  # The unit copies these files into a container whose IRIS user is not this one, and the owner-only file mode (077) this script sets
  # at its start leaves them readable by their owner alone (Story 11.20): open the export to other users, as step_ipm does inside its
  # container. That setting stays: the state files rely on it.
  chmod -R a+rX "$ctx"
  if [ ! -f "$ctx/release/security-overview.sh" ]; then
    rm -rf "$ctx"
    step_fail overview "the candidate has no release/security-overview.sh"
    return 1
  fi
  mkdir -p "$ctx/web/node_modules"
  lockdir=$(candidate_lock_dir)
  (
    cd "$ctx" || exit 1
    if [ -n "$lockdir" ]; then export OCUTALON_LOCK_DIR="$lockdir"; fi
    bash release/security-overview.sh
  ) < /dev/null > "$log" 2>&1
  code=$?
  rm -rf "$ctx"
  case $code in
    0)
      rm -f "$log" "$sdir/overview-fail.log"
      STEP_ROW=pass
      STEP_DETAIL="the generated sections equal a fresh generation from the candidate, and the overview tests pass"
      echo "PASS overview $STEP_DETAIL"
      return 0
      ;;
    75)
      rm -f "$log"
      echo "WAIT overview the lane's throwaway lock is busy"
      return 5
      ;;
  esac
  line=$(grep -m 1 -E '^(DRIFT |FAIL |CLASS .* failed)' "$log" 2> /dev/null)
  line=${line#FAIL overview }
  kept=0
  if mv -f "$log" "$sdir/overview-fail.log" 2> /dev/null; then kept=1; else rm -f "$log"; fi
  step_fail overview "${line:-the overview unit ended with exit $code}"
  if [ "$kept" = 1 ]; then
    case $sdir in
      /*) echo "LOG overview $sdir/overview-fail.log" ;;
      *) echo "LOG overview $PWD/$sdir/overview-fail.log" ;;
    esac
  fi
  return 1
}

# --- the ipm step (Story 11.17) ---

# ipm_section_fail: "## IPM artifact" of a failed packaging, at step time.
ipm_section_fail() {
  {
    echo "## IPM artifact"
    echo "Result: fail"
    echo "Candidate: $version rc$rc, $branch at $(sget cand_sha)"
    echo "Published: no; publishing to the package registry is the author's own action, outside this sequence"
  } > "$sdir/ipm-section.md"
  record_write "$(record_abs)" "$sdir/ipm-section.md" "# OcuTalon $version rc$rc" > /dev/null 2>&1
}

# ipm_fail <detail>: the failure of the step after the tree was read.
ipm_fail() {
  sset ipm_result fail
  ipm_section_fail
  step_fail ipm "$1"
}

# ipm_pack_fail <kind> <line>: ends the packaging subshell with the reason (kind install or artifact) in the state folder.
ipm_pack_fail() {
  printf '%s|%s\n' "$1" "$2" > "$IPM_IDIR/fail.txt"
  exit 1
}

# ipm_pack_clean: the EXIT trap of the packaging subshell: the container, the lock and the temporary folders go.
ipm_pack_clean() {
  if [ "$IPM_ATTEMPT" = 1 ]; then
    docker rm -f -v "$IPM_C" < /dev/null > /dev/null 2>&1
  fi
  live_lock_release >> "$IPM_IDIR/run.log" 2>&1
  rm -rf "${IPM_TREE:?}" "${IPM_TMP:-}"
}

# ipm_session <name> <namespace> <script>: runs the script in a terminal session of the throwaway; the plain output is <idir>/<name>.log.
ipm_session() {
  local raw="${IPM_IDIR:?}/$1.raw"
  printf '%s\nHalt\n' "$3" | docker exec -i "$IPM_C" iris session IRIS -U "$2" > "$raw" 2>&1
  tr -d '\r' < "$raw" | sed $'s/\033\\[[0-9;?]*[A-Za-z]//g' > "$IPM_IDIR/$1.log"
  rm -f "$raw"
}

# ipm_load_ok <log> <namespace>: succeeds when the load reached Activate SUCCESS in the namespace.
ipm_load_ok() {
  grep -Eq "\\[$2\\|ocutalon\\][[:space:]]*Activate SUCCESS[[:space:]]*\$" "$1"
}

# ipm_pack <container> <tree> <state ipm folder> <zpm file name>: the whole packaging; runs in a subshell of step_ipm. The tree is a full
# export of the candidate and IPM loads its root, so the module.xml and the preload folder at the top are the ones the package registry reads. Exit 75 is a busy
# lane lock, 1 a failure (the reason in fail.txt), 0 a verified artifact in <folder>/ocutalon-<v>.tgz and result.env.
ipm_pack() {
  local zpmfile=$4 pkg=/tmp/ocutalon-pkg out=/tmp/ocutalon-ipm chk=/tmp/ocutalon-check
  local ns="" art waited deadline last problems files ext
  IPM_C=$1
  IPM_TREE=$2
  IPM_IDIR=$3
  IPM_ATTEMPT=0
  IPM_TMP=""
  art="$IPM_IDIR/ocutalon-$version.tgz"
  trap 'exit 130' INT TERM HUP
  trap ipm_pack_clean EXIT
  root=$rel_root
  P=$IPM_C
  live_lock_claim >> "$IPM_IDIR/run.log" 2>&1
  IPM_ATTEMPT=1
  docker run -d --pull never --network none --name "$IPM_C" "$(base_image)" < /dev/null >> "$IPM_IDIR/run.log" 2>&1 \
    || ipm_pack_fail install "the throwaway instance could not be started"
  waited=${OCUTALON_RELEASE_IPM_WAIT:-300}
  deadline=$((SECONDS + waited))
  until docker exec "$IPM_C" iris qlist < /dev/null 2> /dev/null | grep -q '\^running'; do
    [ "$SECONDS" -lt "$deadline" ] || ipm_pack_fail install "the throwaway instance was not running after $waited s"
    sleep 2
  done
  docker exec -u root "$IPM_C" mkdir -p "$pkg" < /dev/null > /dev/null 2>&1 \
    && docker cp "$IPM_TREE/." "$IPM_C:$pkg" < /dev/null >> "$IPM_IDIR/run.log" 2>&1 \
    && docker exec -u root "$IPM_C" chmod -R a+rX "$pkg" < /dev/null > /dev/null 2>&1 \
    && docker exec "$IPM_C" mkdir -p "$out" < /dev/null > /dev/null 2>&1 \
    || ipm_pack_fail install "the source tree could not be copied into the throwaway instance"
  ipm_session ipm-load %SYS "Set sc=\$SYSTEM.OBJ.Load(\"$pkg/docker/ipm/$zpmfile\",\"ck-d\") Write !,\"IPMLOAD \",\$Select(\$SYSTEM.Status.IsError(sc):\"FAILED\",1:\"OK\")
zpm \"enable -map -ns USER\""
  grep -q '^IPMLOAD OK' "$IPM_IDIR/ipm-load.log" || ipm_pack_fail install "IPM could not be loaded: $(last_prompt_free_line "$IPM_IDIR/ipm-load.log")"
  ipm_session load-user USER "zpm \"load -bypass-py-deps $pkg\""
  last="$IPM_IDIR/load-user.log"
  if ipm_load_ok "$last" USER; then
    ns=USER
  else
    ipm_session ns-check %SYS 'Write !,"NSCHECK ",##class(Config.Namespaces).Exists("OCUTALON")'
    if grep -Eq '^NSCHECK 1[[:space:]]*$' "$IPM_IDIR/ns-check.log"; then
      ipm_session load-ocutalon OCUTALON "zpm \"load -bypass-py-deps $pkg\""
      last="$IPM_IDIR/load-ocutalon.log"
      ! ipm_load_ok "$last" OCUTALON || ns=OCUTALON
    fi
  fi
  [ -n "$ns" ] || ipm_pack_fail install "$(last_prompt_free_line "$last")"
  ipm_session package "$ns" "zpm \"package ocutalon -only -path $out/ocutalon-$version\""
  docker cp "$IPM_C:$out/ocutalon-$version.tgz" "$art" < /dev/null >> "$IPM_IDIR/run.log" 2>&1 \
    || ipm_pack_fail install "the package left no ocutalon-$version.tgz: $(last_prompt_free_line "$IPM_IDIR/package.log")"
  problems=$(ipm_artifact_check "$art" "$version" "$IPM_TREE" root)
  if [ -n "$problems" ]; then
    rm -f "$art"
    ipm_pack_fail artifact "$(printf '%s\n' "$problems" | head -n 1)"
  fi
  IPM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ipmrepo.XXXXXX") || ipm_pack_fail artifact "could not be checked (no temporary folder)"
  ext="$IPM_TMP/ocutalon-$version"
  ipm_unpack "$art" "$ext"
  docker exec "$IPM_C" mkdir -p "$chk" < /dev/null > /dev/null 2>&1 \
    && docker cp "$ext" "$IPM_C:$chk/ocutalon-$version" < /dev/null >> "$IPM_IDIR/run.log" 2>&1 \
    && docker exec -u root "$IPM_C" chmod -R a+rX "$chk" < /dev/null > /dev/null 2>&1 \
    || {
      rm -f "$art"
      ipm_pack_fail artifact "could not be copied back for the repository check"
    }
  ipm_session repo-add "$ns" "zpm \"repo -name ocutalon-check -fs -depth 2 -path $chk/\""
  ipm_session repo-list "$ns" 'zpm "repo -name ocutalon-check -list-modules"'
  if ! awk -v v="$version" '$1 == "ocutalon" && $2 == v { f = 1 } END { exit !f }' "$IPM_IDIR/repo-list.log"; then
    rm -f "$art"
    ipm_pack_fail artifact "is not listed by the IPM filesystem repository (it lists nothing for ocutalon $version)"
  fi
  files=$(find "$IPM_TREE/src/ocutalon/csp" -type f | wc -l | tr -d ' ')
  env_set "$IPM_IDIR/result.env" ns "$ns"
  env_set "$IPM_IDIR/result.env" files "$files"
  env_set "$IPM_IDIR/result.env" zpm "$zpmfile"
  return 0
}

step_ipm() {
  local cand tree="$sdir/ipm-tree" idir="$sdir/ipm" base cname zpmfile got old sub_rc fail kind line art bytes sha cdig ns files ipmver m
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail ipm "the candidate is not cut"
    return 1
  fi
  rm -rf "$tree"
  mkdir -p "$tree"
  if ! git archive -o "$tree.tar" "$cand" < /dev/null > /dev/null 2>&1 || ! tar -x -C "$tree" -f "$tree.tar" < /dev/null > /dev/null 2>&1; then
    rm -rf "$tree" "$tree.tar"
    step_fail ipm "the candidate's tree could not be exported"
    return 1
  fi
  rm -f "$tree.tar"
  if [ ! -f "$tree/src/ocutalon/csp/index.html" ]; then
    rm -rf "$tree"
    ipm_fail "the candidate has no committed web bundle (src/ocutalon/csp/index.html)"
    return 1
  fi
  for m in module.xml src/module.xml; do
    got=$(manifest_version "$tree/$m" 2> /dev/null)
    if [ "$got" != "$version" ]; then
      rm -rf "$tree"
      ipm_fail "$m reads ${got:-no version}, not $version"
      return 1
    fi
  done
  set -- "$tree"/docker/ipm/zpm-*.xml
  if [ $# -ne 1 ] || [ ! -f "$1" ]; then
    rm -rf "$tree"
    ipm_fail "the candidate holds no single docker/ipm/zpm-*.xml"
    return 1
  fi
  zpmfile=${1##*/}
  base=$(base_image)
  if ! docker image inspect --format '{{.Id}}' "$base" < /dev/null > /dev/null 2>&1; then
    rm -rf "$tree"
    ipm_fail "the IRIS base image $base is not on this machine"
    return 1
  fi
  old=$(sget ipm_container)
  [ -z "$old" ] || docker rm -f -v "$old" < /dev/null > /dev/null 2>&1
  cname="ocutalon-release-ipm-$(printf '%s' "$version" | tr -d '.')-rc$rc-$(date -u +%s)-$$"
  sset ipm_container "$cname"
  rm -rf "$idir"
  mkdir -p "$idir"
  (ipm_pack "$cname" "$tree" "$idir" "$zpmfile") >> "$idir/run.log" 2>&1
  sub_rc=$?
  rm -rf "$tree"
  case $sub_rc in
    0) ;;
    75)
      echo "WAIT ipm the lane's throwaway lock is busy"
      return 5
      ;;
    *)
      rm -f "$idir/ocutalon-$version.tgz"
      fail=$(head -n 1 "$idir/fail.txt" 2> /dev/null)
      kind=${fail%%|*}
      line=${fail#*|}
      [ -n "$fail" ] || {
        kind=install
        line="the packaging ended without a result"
      }
      if [ "$kind" = artifact ]; then
        ipm_fail "the artifact $line"
      else
        ipm_fail "the package did not install: $line"
      fi
      return 1
      ;;
  esac
  art=$(ipm_artifact_path "$version" "$rc")
  ns=$(env_get "$idir/result.env" ns)
  files=$(env_get "$idir/result.env" files)
  ipmver=$(env_get "$idir/result.env" zpm)
  ipmver=${ipmver#zpm-}
  ipmver=${ipmver%.xml}
  bytes=$(wc -c < "$art" | tr -d ' ')
  sha=$(sha256_file "$art")
  if ! cdig=$(ipm_content_digest "$art"); then
    rm -f "$art"
    ipm_fail "the artifact content could not be hashed"
    return 1
  fi
  {
    echo "## IPM artifact"
    echo "Result: pass"
    echo "Candidate: $version rc$rc, $branch at $cand"
    echo "Artifact: ocutalon-$version.tgz, kept in the release state folder ($version-rc$rc/ipm/), outside the repository; release.sh status prints its full path"
    echo "Size: $bytes bytes"
    echo "SHA-256: $sha"
    echo "Content SHA-256: $cdig (over every file in the artifact; the same for every packaging of this candidate)"
    echo "Packaged by: IPM $ipmver, zpm \"package ocutalon -only\", in namespace $ns of a throwaway build 154 instance with no network"
    echo "Web bundle: $files files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's"
    echo "Published: no; publishing to the package registry is the author's own action, outside this sequence"
  } > "$sdir/ipm-section.md"
  if ! record_write "$(record_abs)" "$sdir/ipm-section.md" "# OcuTalon $version rc$rc"; then
    rm -f "$art"
    ipm_fail "the artifact could not be written into the record"
    return 1
  fi
  sset ipm_result pass
  sset ipm_ns "$ns"
  STEP_ROW=pass
  STEP_DETAIL="ocutalon-$version.tgz, $bytes bytes, SHA-256 ${sha%"${sha#????????????}"}; carries the candidate's web bundle; not published"
  echo "PASS ipm ocutalon-$version.tgz $bytes bytes sha256 $sha"
  echo "ARTIFACT $art"
  return 0
}

# --- the ipmcheck step (Story 15.4) ---

IPM_SIZE_WARN=5000000

# ipmcheck_section <pass|fail> <bytes> <detail>: "## FR-57 job" in the record. The detail is the first FAIL line of the unit on a failure.
ipmcheck_section() {
  {
    echo "## FR-57 job"
    echo "Result: $1"
    echo "Candidate: $version rc$rc, $branch at $(sget cand_sha)"
    echo "Command: bash release/ipm-install.sh on an export of the candidate's tree, with the IPM artifact ocutalon-$version.tgz of this candidate as OCUTALON_IPM_ARTIFACT; the CI job ipm-install runs the same command"
    echo "Artifact: ocutalon-$version.tgz, $2 bytes"
    if [ "$2" -gt "$IPM_SIZE_WARN" ] 2> /dev/null; then
      echo "Size: $2 bytes, over $IPM_SIZE_WARN"
    fi
    if [ "$1" = pass ]; then
      echo "Checks: the exact artifact installed from a local IPM repository on a fresh build 154 instance with no Node.js, in USER and then in OCUTALON; OCUTALON served the sign-in page and the README account signed in; the uninstall left USER's repository definitions unchanged"
    else
      echo "First failure: $3"
    fi
  } > "$sdir/ipmcheck-section.md"
  record_write "$(record_abs)" "$sdir/ipmcheck-section.md" "# OcuTalon $version rc$rc"
}

# step_ipmcheck: runs release/ipm-install.sh, the FR-57 job's own command, in an export of the candidate's tree with the artifact of the ipm
# step as OCUTALON_IPM_ARTIFACT, on the lane's throwaway lock (the folder of the author's repository), with the job's live deadline (1980 s,
# unless the caller set one) and a run tag of its own; ci/iris.sh teardown always runs after it. Exit 0 of the unit is PASS, 75 is WAIT
# (nothing is recorded; the next call runs the step again), anything else fails the step with the unit's first FAIL line, and the release
# stops before push. It asks nothing. An artifact over 5000000 bytes prints a WARN line and a Size: note, and fails nothing.
step_ipmcheck() {
  local ctx="$sdir/ipmcheck" log="$sdir/ipmcheck.log" art lockdir code line bytes
  if [ "$(sget ipm_result)" != pass ]; then
    step_fail ipmcheck "the ipm step has not passed"
    return 1
  fi
  art=$(ipm_artifact_path "$version" "$rc")
  if [ ! -f "$art" ]; then
    step_fail ipmcheck "the IPM artifact ocutalon-$version.tgz is missing"
    return 1
  fi
  case $art in /*) ;; *) art="$PWD/$art" ;; esac
  bytes=$(wc -c < "$art" | tr -d ' ')
  candidate_export ipmcheck "$ctx" || return 1
  if [ ! -f "$ctx/release/ipm-install.sh" ]; then
    rm -rf "$ctx"
    step_fail ipmcheck "the candidate has no release/ipm-install.sh"
    return 1
  fi
  mkdir -p "$ctx/web/node_modules"
  lockdir=$(candidate_lock_dir)
  (
    cd "$ctx" || exit 1
    if [ -n "$lockdir" ]; then export OCUTALON_LOCK_DIR="$lockdir"; fi
    export OCUTALON_IPM_ARTIFACT="$art"
    export OCUTALON_RUN_TAG="${OCUTALON_RUN_TAG:+$OCUTALON_RUN_TAG-}ipmchk-$$"
    export OCUTALON_LIVE_DEADLINE="${OCUTALON_LIVE_DEADLINE:-1980}"
    bash release/ipm-install.sh
    code=$?
    bash ci/iris.sh teardown < /dev/null > /dev/null 2>&1
    exit "$code"
  ) < /dev/null > "$log" 2>&1
  code=$?
  rm -rf "$ctx"
  if [ "$code" -eq 75 ]; then
    rm -f "$log"
    echo "WAIT ipmcheck the lane's throwaway lock is busy"
    return 5
  fi
  if [ "$bytes" -gt "$IPM_SIZE_WARN" ]; then
    echo "WARN ipmcheck the artifact is $bytes bytes, over $IPM_SIZE_WARN; report it to the Contest Planner"
  fi
  if [ "$code" -ne 0 ]; then
    line=$(grep -m 1 '^FAIL ' "$log" 2> /dev/null)
    line=${line#FAIL }
    rm -f "$log"
    step_fail ipmcheck "${line:-release/ipm-install.sh ended with exit $code}"
    ipmcheck_section fail "$bytes" "$STEP_DETAIL" > /dev/null 2>&1
    return 1
  fi
  rm -f "$log"
  if ! ipmcheck_section pass "$bytes" ""; then
    step_fail ipmcheck "the result could not be written into the record"
    return 1
  fi
  STEP_ROW=pass
  STEP_DETAIL="ocutalon-$version.tgz ($bytes bytes) installs from a local IPM repository on a fresh instance with no Node.js and uninstalls leaving the repository definitions unchanged"
  echo "PASS ipmcheck $STEP_DETAIL"
  return 0
}

step_push() {
  local cand remote_sha
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail push "the candidate is not cut"
    return 1
  fi
  if [ "$(git rev-parse "refs/heads/$branch" < /dev/null 2> /dev/null)" != "$cand" ]; then
    step_fail push "$branch no longer points at the cut commit; a candidate is never moved"
    return 1
  fi
  remote_sha=$(git ls-remote "$remote" "refs/heads/$branch" < /dev/null 2> /dev/null | awk '{ print $1 }')
  if [ -n "$remote_sha" ] && [ "$remote_sha" != "$cand" ]; then
    step_fail push "$branch already exists on $remote at another commit; a candidate is never moved, so start the next one"
    return 1
  fi
  ask push "Push $branch (${cand%"${cand#???????}"}) to $remote?"
  case $? in
    0) ;;
    *)
      STEP_ROW=stopped
      STEP_DETAIL="the author's word was not given"
      stopped push
      return 4
      ;;
  esac
  if ! git push -q "$remote" "refs/heads/$branch:refs/heads/$branch" < /dev/null > /dev/null 2>&1; then
    step_fail push "git push of $branch to $remote failed"
    return 1
  fi
  remote_sha=$(git ls-remote "$remote" "refs/heads/$branch" < /dev/null 2> /dev/null | awk '{ print $1 }')
  if [ "$remote_sha" != "$cand" ]; then
    step_fail push "$remote does not hold $branch at the cut commit"
    return 1
  fi
  STEP_ROW=pass
  STEP_DETAIL="$branch pushed to $remote on the author's word"
  echo "PASS push $branch"
  return 0
}

step_notes() {
  local out code res file notes
  notes=$(notes_path "$version" "$rc")
  out=$(bash "$rel_root/release/notes.sh" --version "$version" --rc "$rc" --candidate "$branch" --record "$record" --eval "$sdir/release-candidate.json" < /dev/null 2>&1)
  code=$?
  case $code in
    0 | 1 | 3)
      res=$(printf '%s\n' "$out" | sed -n 's/^RESULT //p' | tail -n 1)
      file=$(printf '%s\n' "$out" | sed -n 's/^NOTES //p' | tail -n 1)
      case $file in
        "$rel_root"/*) file=${file#"$rel_root"/} ;;
        /*) file=$(basename "$file") ;;
      esac
      [ -n "$file" ] || file=$notes
      case $res in
        draft | "dry run" | fail) ;;
        *)
          step_fail notes "release/notes.sh printed no RESULT"
          return 1
          ;;
      esac
      STEP_ROW=$res
      STEP_DETAIL="release/notes.sh: RESULT $res; draft $file (not committed)"
      echo "PASS notes RESULT $res NOTES $file"
      [ "$res" != fail ] || echo "WARN notes the draft needs editing before the checklist"
      return 0
      ;;
    *)
      step_fail notes "release/notes.sh refused: $(printf '%s\n' "$out" | tail -n 1)"
      return 1
      ;;
  esac
}

# --- the gates (Story 11.14) ---

CI_WORKFLOWS="ci lane-a"
CI_WINDOW=900
UPGRADE_PHASES="build settings seed upgrade restart storage report"
REHEARSAL_RUNS=20

# short_sha <sha>: the first seven characters.
short_sha() { printf '%s\n' "${1%"${1#???????}"}"; }

# abs_path <path>: the path as an absolute one.
abs_path() {
  case $1 in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

# gate_fail <gate> <detail>: step_fail, then the LOG line when the gate kept a log.
gate_fail() {
  step_fail "$1" "$2"
  if [ -s "$sdir/$1.log" ]; then echo "LOG $1 $(abs_path "$sdir/$1.log")"; fi
  return 1
}

# gate_script <gate> <dir> <tag|-> <args>...: runs bash <args> in the clone <dir> with the gate's run tag and the lane's throwaway lock folder,
# and no standard input. The output is appended to <state>/<gate>.log and kept in <state>/<gate>.call (GATE_CALL); GATE_CODE is the exit code.
GATE_CALL=""
GATE_CODE=0
gate_script() {
  local gate=$1 dir=$2 tag=$3 lockdir
  shift 3
  lockdir=$(candidate_lock_dir)
  GATE_CALL="$sdir/$gate.call"
  (
    cd "$dir" || exit 1
    if [ -n "$lockdir" ]; then export OCUTALON_LOCK_DIR="$lockdir"; fi
    if [ "$tag" != - ]; then export OCUTALON_RUN_TAG="$tag"; fi
    bash "$@"
  ) < /dev/null > "$GATE_CALL" 2>&1
  GATE_CODE=$?
  cat "$GATE_CALL" >> "$sdir/$gate.log"
}

# gate_line <pattern>: the last line of the last gate call that matches the pattern, else its last non-blank line.
gate_line() {
  local line
  line=$(grep -E "$1" "$GATE_CALL" 2> /dev/null | tail -n 1)
  [ -n "$line" ] || line=$(grep -v '^[[:space:]]*$' "$GATE_CALL" 2> /dev/null | tail -n 1)
  printf '%s\n' "$line"
}

# gate_verdict <section heading> <mode|->: judges the section that a gate wrote into the record. Sets GATE_RESULT, GATE_MODE and GATE_CAND.
# Returns 0 when the section reads Result: pass, the Candidate line ends with " at <the cut's full sha>" and, with a mode, Mode: reads it;
# 1 when the result or the mode is another; 2 when the section names another commit.
GATE_RESULT=""
GATE_MODE=""
GATE_CAND=""
gate_verdict() {
  local rec cand
  rec=$(record_abs)
  cand=$(sget cand_sha)
  GATE_RESULT=$(record_field "$rec" "$1" Result)
  GATE_MODE=$(record_field "$rec" "$1" Mode)
  GATE_CAND=$(record_field "$rec" "$1" Candidate)
  [ "$GATE_RESULT" = pass ] || return 1
  if [ "$2" != - ] && [ "$GATE_MODE" != "$2" ]; then return 1; fi
  [ -n "$cand" ] || return 2
  case $GATE_CAND in
    *" at $cand") return 0 ;;
  esac
  return 2
}

# dash <text>: the text, or - when it is empty.
dash() { printf '%s\n' "${1:--}"; }

# step_stubs: refuses a candidate with an enabled production item whose class carries Parameter STUB = 1 (AD-29), on an export of the candidate's
# tree. It asks nothing and runs before push.
step_stubs() {
  local ctx="$sdir/stubs" out code counts found
  candidate_export stubs "$ctx" || return 1
  out=$(production_stubs "$ctx")
  code=$?
  rm -rf "$ctx"
  counts=$(printf '%s\n' "$out" | grep '^COUNTS|' | tail -n 1)
  if [ "$code" -eq 3 ] || [ -z "$counts" ]; then
    step_fail stubs "the production classes could not be read"
    return 1
  fi
  if [ "$code" -eq 1 ]; then
    found=$(printf '%s\n' "$out" | awk -F'|' '$1 == "FOUND" { printf "%s:%s (%s) answers \"not implemented\"; disable it in its production, or build it, and cut the next candidate\n", $2, $3, $4 }')
    step_fail stubs "$(printf '%s\n' "$found" | head -n 1)" > /dev/null
    printf '%s\n' "$found" | sed 's/^/FAIL stubs /'
    return 1
  fi
  STEP_ROW=pass
  STEP_DETAIL="no enabled item answers \"not implemented\" ($(printf '%s' "$counts" | cut -d'|' -f2) enabled items in $(printf '%s' "$counts" | cut -d'|' -f3) productions)"
  echo "PASS stubs $STEP_DETAIL"
  return 0
}

# step_ci: reads, with gh run list, the push runs on the cut commit. The newest run of each workflow (the highest id) must be completed and
# successful, and every workflow of CI_WORKFLOWS must have one. A completed run that is not a success fails first; a run that has not finished
# waits (exit 5, nothing recorded); a required workflow with no run waits for CI_WINDOW seconds after the step's first check (ci_first of the
# state, on the clock seam) and then fails. gh is called with run list only.
step_ci() {
  local cand short repo runs code now first elapsed newest verdict w red pend detail missing="" late="" found
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail ci "the candidate is not cut"
    return 1
  fi
  short=$(short_sha "$cand")
  if ! command -v gh > /dev/null 2>&1; then
    step_fail ci "gh is not installed"
    return 1
  fi
  if ! repo=$(gh_repo "$remote"); then
    step_fail ci "the remote $remote is not a GitHub repository, so its runs cannot be read"
    return 1
  fi
  now=$(clock)
  first=$(sget ci_first)
  if [ -z "$first" ]; then
    first=$now
    sset ci_first "$first"
  fi
  elapsed=$((now - first))
  [ "$elapsed" -ge 0 ] || elapsed=0
  runs=$(ci_runs "$repo" "$cand" push "$branch")
  code=$?
  if [ "$code" -eq 127 ]; then
    step_fail ci "gh is not installed"
    return 1
  fi
  if [ "$code" -ne 0 ]; then
    echo "WAIT ci gh could not read the runs (exit $code); the next call reads them again"
    return 5
  fi
  newest=$(printf '%s\n' "$runs" | awk -F'\t' 'NF >= 3 { if (!($2 in id) || $1 + 0 > id[$2] + 0) { id[$2] = $1; st[$2] = $3; cc[$2] = $4 } }
    END { for (w in id) printf "%s\t%s\t%s\t%s\n", id[w], w, st[w], cc[w] }' | LC_ALL=C sort -t "$TAB" -k2,2)
  verdict=$(printf '%s\n' "$newest" | awk -F'\t' '
    NF >= 3 {
      if ($3 == "completed") { if ($4 != "success" && red == "") red = $2 " run " $1 " concluded " $4 }
      else if (pend == "") pend = $2 " run " $1 " is " $3
      detail = detail (detail == "" ? "" : ", ") $2 " run " $1
    }
    END { print "red=" red; print "pend=" pend; print "detail=" detail }')
  red=$(printf '%s\n' "$verdict" | sed -n 's/^red=//p')
  pend=$(printf '%s\n' "$verdict" | sed -n 's/^pend=//p')
  detail=$(printf '%s\n' "$verdict" | sed -n 's/^detail=//p')
  for w in $CI_WORKFLOWS; do
    found=$(printf '%s\n' "$newest" | awk -F'\t' -v w="$w" '$2 == w { print "yes"; exit }')
    [ -n "$found" ] && continue
    if [ "$elapsed" -ge "$CI_WINDOW" ]; then
      late="${late:-$w}"
    else
      missing="${missing:-$w}"
    fi
  done
  if [ -n "$red" ]; then
    step_fail ci "$red"
    return 1
  fi
  if [ -n "$late" ]; then
    step_fail ci "no $late push run on $cand 15 minutes after the first check"
    return 1
  fi
  if [ -n "$pend" ]; then
    echo "WAIT ci $pend"
    return 5
  fi
  if [ -n "$missing" ]; then
    echo "WAIT ci no $missing push run on $short yet ($elapsed s of $CI_WINDOW s)"
    return 5
  fi
  STEP_ROW=pass
  STEP_DETAIL=$(printf '%s' "every push run on $short succeeded: $detail" | detail_clean)
  echo "PASS ci $STEP_DETAIL"
  return 0
}

# step_eval: judges the author's evaluation result of the candidate, <state>/eval/eval/release-candidate.json (eval/run.sh --release-candidate in
# a clone that this step makes once). The sequence never reads or holds a model key. Only a pass, or REL-5's override with a reason (written
# by eval/run.sh --override), passes. A pass is copied to <state>/release-candidate.json for notes. Exit 5 while the result is not there.
step_eval() {
  local dir="$sdir/eval" file="$sdir/eval/eval/release-candidate.json" cand short info fmt commit mock clean verdict by reason lockdir
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail eval "the candidate is not cut"
    return 1
  fi
  short=$(short_sha "$cand")
  if [ ! -f "$file" ]; then
    if [ ! -d "$dir/.git" ] && ! candidate_clone "$dir" "$branch" "$cand"; then
      step_fail eval "$CLONE_WHY"
      return 1
    fi
    echo "WAIT eval no evaluation result for $short yet; the author runs the evaluation"
    lockdir=$(candidate_lock_dir)
    if [ -n "$lockdir" ]; then
      echo "RUN cd $(abs_path "$dir") && OCUTALON_LOCK_DIR=$lockdir bash eval/run.sh --release-candidate"
    else
      echo "RUN cd $(abs_path "$dir") && bash eval/run.sh --release-candidate"
    fi
    return 5
  fi
  info=$(node -e '
    const fs = require("fs");
    let r;
    try { r = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(3); }
    if (!r || typeof r !== "object" || Array.isArray(r)) process.exit(3);
    const f = (v) => String(v == null ? "" : v).replace(/[\r\n\t]+/g, " ");
    const b = (v) => (v === true ? "true" : v === false ? "false" : "?");
    const o = r.override && typeof r.override === "object" ? r.override : null;
    console.log("format=" + f(r.format));
    console.log("commit=" + f(r.commit));
    console.log("onMock=" + b(r.onMock));
    console.log("treeClean=" + b(r.treeClean));
    console.log("verdict=" + f(r.verdict));
    console.log("decidedBy=" + f(r.decidedBy));
    console.log("reason=" + f(o && typeof o.reason === "string" ? o.reason.trim() : ""));' "$file" < /dev/null 2> /dev/null)
  fmt=$(printf '%s\n' "$info" | sed -n 's/^format=//p')
  commit=$(printf '%s\n' "$info" | sed -n 's/^commit=//p')
  mock=$(printf '%s\n' "$info" | sed -n 's/^onMock=//p')
  clean=$(printf '%s\n' "$info" | sed -n 's/^treeClean=//p')
  verdict=$(printf '%s\n' "$info" | sed -n 's/^verdict=//p')
  by=$(printf '%s\n' "$info" | sed -n 's/^decidedBy=//p')
  reason=$(printf '%s\n' "$info" | sed -n 's/^reason=//p')
  if [ "$fmt" != ocutalon.evalResult/1 ]; then
    step_fail eval "the result is not an ocutalon.evalResult/1 file"
    return 1
  fi
  if [ "$commit" != "$cand" ]; then
    step_fail eval "the result is of commit $(dash "$commit"), not of the candidate $cand"
    return 1
  fi
  if [ "$mock" != false ]; then
    step_fail eval "the result was made on the CI mock, not on the model"
    return 1
  fi
  if [ "$clean" != true ]; then
    step_fail eval "the result was made on a tree with uncommitted changes"
    return 1
  fi
  case $verdict in
    pass) STEP_DETAIL="pass: $by" ;;
    overridden)
      if [ -z "$reason" ]; then
        step_fail eval "overridden with no reason"
        return 1
      fi
      STEP_DETAIL="overridden (REL-5): $reason"
      ;;
    blocked)
      step_fail eval "blocked: $by; REL-5's override is the author's: eval/run.sh --override \"<reason>\" in the evaluation clone"
      echo "RUN cd $(abs_path "$dir") && bash eval/run.sh --override \"<reason>\""
      return 1
      ;;
    incomplete)
      step_fail eval "incomplete: $by"
      return 1
      ;;
    *)
      step_fail eval "the result is not an ocutalon.evalResult/1 file"
      return 1
      ;;
  esac
  if ! cp "$file" "$sdir/release-candidate.json"; then
    step_fail eval "the result could not be kept for the notes"
    return 1
  fi
  rm -rf "$dir"
  STEP_DETAIL=$(printf '%s' "$STEP_DETAIL" | detail_clean)
  STEP_ROW=pass
  echo "PASS eval $STEP_DETAIL"
  return 0
}

# upgrade_down <tag> <clone>: the harness's down phase; WARN when it exits non-zero.
upgrade_down() {
  gate_script upgrade "$2" "$1" release/upgrade-harness.sh down
  echo "PHASE upgrade down exit $GATE_CODE"
  if [ "$GATE_CODE" -ne 0 ]; then
    echo "WARN upgrade the down phase exited $GATE_CODE; containers or volumes of run tag $1 may remain"
  fi
}

# upgrade_end: removes the clone and forgets the phase, so that the next call starts again.
upgrade_end() {
  rm -rf "$sdir/gate-upgrade"
  sset upg_phase ""
}

# step_upgrade: drives release/upgrade-harness.sh of the candidate, one phase per call, in a clone of the author's repository under one run tag:
# build (it alone gets the options), then settings, seed, upgrade, restart and storage whatever an earlier phase gave, then report and down in
# one call. A phase that is done gives NEXT upgrade (exit 0 of this script); 75 waits on the same phase; a failed build runs down and fails,
# and exit 2 from a later phase runs report, then down, and fails. The gate passes only when report exits 0 and the harness's section reads Result: pass and Mode: release for
# the cut commit. The remote's v* tags must all be in this repository first, because the harness picks the previous build from them.
step_upgrade() {
  local dir="$sdir/gate-upgrade" cand tag phase next t all_tags local_tags missing="" code ra line r m
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail upgrade "the candidate is not cut"
    return 1
  fi
  tag="rel-$(printf '%s' "$version" | tr . -)-rc$rc-upg"
  phase=$(sget upg_phase)
  if [ -z "$phase" ]; then
    all_tags=$(release_tags "$remote")
    code=$?
    local_tags=$(git tag --list 'v*' < /dev/null 2> /dev/null)
    for t in $all_tags; do
      printf '%s\n' "$local_tags" | grep -qxF -- "$t" || missing="${missing:+$missing }$t"
    done
    if [ "$code" -ne 0 ]; then
      step_fail upgrade "the tags of $remote could not be read; run git fetch --tags $remote, then release.sh next"
      return 1
    fi
    if [ -n "$missing" ]; then
      step_fail upgrade "the tags of $remote are not all in this repository (missing: $missing); run git fetch --tags $remote, then release.sh next"
      return 1
    fi
    : > "$sdir/upgrade.log"
    phase=build
    sset upg_phase build
  fi
  if [ ! -d "$dir/.git" ] && ! candidate_clone "$dir" "$branch" "$cand" web; then
    upgrade_end
    gate_fail upgrade "$CLONE_WHY"
    return 1
  fi
  if [ "$phase" = build ]; then
    gate_script upgrade "$dir" "$tag" release/upgrade-harness.sh build --version "$version" --rc "$rc" --record "$(record_abs)"
  elif [ "$phase" = report ]; then
    gate_script upgrade "$dir" "$tag" release/upgrade-harness.sh report
  else
    gate_script upgrade "$dir" "$tag" release/upgrade-harness.sh "$phase"
  fi
  code=$GATE_CODE
  if [ "$code" -eq 75 ]; then
    echo "WAIT upgrade the lane's throwaway lock is busy"
    return 5
  fi
  echo "PHASE upgrade $phase exit $code"
  if [ "$code" -eq 2 ] || { [ "$phase" = build ] && [ "$code" -ne 0 ]; }; then
    line=$(gate_line '^(REFUSED|FAIL) ')
    if [ "$phase" != build ] && [ "$phase" != report ]; then
      gate_script upgrade "$dir" "$tag" release/upgrade-harness.sh report
      echo "PHASE upgrade report exit $GATE_CODE"
    fi
    upgrade_down "$tag" "$dir"
    upgrade_end
    if [ "$phase" = build ] && [ "$code" -eq 1 ]; then
      gate_fail upgrade "the harness's build failed: $line"
    else
      gate_fail upgrade "the harness refused $phase: $line"
    fi
    return 1
  fi
  if [ "$phase" != report ]; then
    next=$(printf '%s\n' $UPGRADE_PHASES | awk -v p="$phase" 'found { print; exit } $0 == p { found = 1 }')
    sset upg_phase "$next"
    [ "$phase" != seed ] || echo "NOTE upgrade run the next call now: the reminder that the seed set must still be pending when the upgrade begins"
    return 3
  fi
  ra=$code
  upgrade_down "$tag" "$dir"
  upgrade_end
  gate_verdict "## Upgrade harness" release
  code=$?
  r=$(dash "$GATE_RESULT")
  m=$(dash "$GATE_MODE")
  if [ "$ra" -eq 0 ] && [ "$code" -eq 0 ]; then
    STEP_ROW=pass
    STEP_DETAIL="Result: pass, Mode: release, Previous: $(record_field "$(record_abs)" "## Upgrade harness" Previous)"
    STEP_DETAIL=$(printf '%s' "$STEP_DETAIL" | detail_clean)
    echo "PASS upgrade $STEP_DETAIL"
    return 0
  fi
  if [ "$ra" -ne 0 ] && [ "$r" = pass ]; then r=fail; fi
  if [ "$ra" -eq 0 ] && [ "$code" -eq 2 ]; then
    gate_fail upgrade "the section names another commit than the candidate"
  else
    gate_fail upgrade "the harness's section reads Result: $r, Mode: $m"
  fi
  return 1
}

# rehearsal_end: removes the clone and forgets that the rehearsal began.
rehearsal_end() {
  rm -rf "$sdir/gate-rehearsal"
  sset reh_started ""
}

# step_rehearsal: drives release/rehearse.sh run of the candidate (DW-548), one phase per call, in a clone of the author's repository under one
# run tag and with the same options on every call. Exit 4 of the script is a phase done (PHASE rehearsal, NEXT rehearsal); 75 waits; exit 2
# fails with its REFUSED text and runs down; exit 3 (a dry run) and every other code fail. Only exit 0 with a section that reads Result: pass
# and Mode: rehearsal for the cut commit passes.
step_rehearsal() {
  local dir="$sdir/gate-rehearsal" cand tag code line r m verdict
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail rehearsal "the candidate is not cut"
    return 1
  fi
  tag="rel-$(printf '%s' "$version" | tr . -)-rc$rc-reh"
  if [ "$(sget reh_started)" != 1 ] || [ ! -d "$dir/.git" ]; then
    : > "$sdir/rehearsal.log"
    if ! candidate_clone "$dir" "$branch" "$cand" web; then
      rehearsal_end
      gate_fail rehearsal "$CLONE_WHY"
      return 1
    fi
    sset reh_started 1
  fi
  gate_script rehearsal "$dir" "$tag" release/rehearse.sh run --version "$version" --rc "$rc" --candidate "$branch" --record "$(record_abs)" --runs "$REHEARSAL_RUNS"
  code=$GATE_CODE
  case $code in
    75)
      echo "WAIT rehearsal the lane's throwaway lock is busy"
      return 5
      ;;
    4)
      line=$(sed -n 's/^NEXT run: *//p' "$GATE_CALL" | tail -n 1)
      echo "PHASE rehearsal $line"
      return 3
      ;;
    2)
      line=$(gate_line '^REFUSED ')
      line=${line#REFUSED }
      gate_script rehearsal "$dir" "$tag" release/rehearse.sh down
      rehearsal_end
      gate_fail rehearsal "release/rehearse.sh refused: $line"
      return 1
      ;;
    3)
      rehearsal_end
      gate_fail rehearsal "a dry run is never a pass"
      return 1
      ;;
  esac
  rehearsal_end
  gate_verdict "## Clean-machine rehearsal" rehearsal
  verdict=$?
  r=$(dash "$GATE_RESULT")
  m=$(dash "$GATE_MODE")
  if [ "$code" -eq 0 ] && [ "$verdict" -eq 0 ]; then
    line=$(record_section "$(record_abs)" "## Clean-machine rehearsal" | awk '/^\| demo path runs \|/ { split($0, f, "|"); v = f[4]; gsub(/^ +| +$/, "", v); print v; exit }')
    STEP_ROW=pass
    STEP_DETAIL=$(printf '%s' "Result: pass, Mode: rehearsal, $(dash "$line")" | detail_clean)
    echo "PASS rehearsal $STEP_DETAIL"
    return 0
  fi
  if [ "$code" -eq 0 ] && [ "$verdict" -eq 2 ]; then
    gate_fail rehearsal "the section names another commit than the candidate"
    return 1
  fi
  if [ "$code" -ne 0 ] && [ "$r" = pass ]; then r=fail; fi
  line=$(grep '^FAIL ' "$GATE_CALL" | head -n 1)
  gate_fail rehearsal "the section reads Result: $r, Mode: $m: $(dash "$line")"
  return 1
}

# step_checklist: runs release/checklist.sh of the candidate in a fresh clone of the author's repository, with the absolute record and the notes
# draft (copied into the clone). Its CONFIRM and LATER lines are printed as they are. Only exit 0 with a section that reads Result: pass for the cut commit passes.
step_checklist() {
  local dir="$sdir/gate-checklist" cand notes code line r k verdict
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail checklist "the candidate is not cut"
    return 1
  fi
  notes=$(notes_path "$version" "$rc")
  : > "$sdir/checklist.log"
  if ! candidate_clone "$dir" "$branch" "$cand"; then
    gate_fail checklist "$CLONE_WHY"
    return 1
  fi
  # The draft goes into the clone and is named by the clone's own path, so that checklist.sh records it relative to the repository.
  if [ -f "$rel_root/$notes" ]; then
    mkdir -p "$dir/$(dirname "$notes")" && cp "$rel_root/$notes" "$dir/$notes"
  fi
  notes="$(cd "$dir" && pwd -P)/$notes"
  gate_script checklist "$dir" - release/checklist.sh --version "$version" --rc "$rc" --candidate "$branch" --record "$(record_abs)" --notes "$notes"
  code=$GATE_CODE
  rm -rf "$dir"
  grep -E '^(CONFIRM|LATER) ' "$GATE_CALL"
  if [ "$code" -eq 2 ]; then
    gate_fail checklist "release/checklist.sh refused: $(gate_line '^(REFUSED|FAIL) ')"
    return 1
  fi
  gate_verdict "## Release checklist" -
  verdict=$?
  if [ "$code" -eq 0 ] && [ "$verdict" -eq 0 ]; then
    STEP_ROW=pass
    STEP_DETAIL="Result: pass"
    echo "PASS checklist $STEP_DETAIL"
    return 0
  fi
  if [ "$code" -eq 0 ] && [ "$verdict" -eq 2 ]; then
    gate_fail checklist "the section names another commit than the candidate"
    return 1
  fi
  r=$(sed -n 's/^RESULT //p' "$GATE_CALL" | tail -n 1)
  [ -n "$r" ] || r=$GATE_RESULT
  if [ "$r" = pass ]; then r=fail; fi
  line=$(grep '^FAIL ' "$GATE_CALL" | head -n 1)
  line=${line#FAIL }
  if [ "$r" = "not confirmed" ]; then
    k=$(grep -c '^CONFIRM ' "$GATE_CALL")
    line="$k author rows not confirmed"
  fi
  gate_fail checklist "Result: $(dash "$r"): $(dash "$line")"
  return 1
}

# handson_fixes <Fixes: value>: the commits that the value names, resolved to full ids, one per line, in HANDS_FIXES and as short ids in HANDS_SHORTS
# (the value none names no commit). Returns 1 when a token is not a commit of this repository, and sets HANDS_BAD to it.
HANDS_FIXES=""
HANDS_SHORTS=""
HANDS_BAD=""
handson_fixes() {
  local t full
  HANDS_FIXES=""
  HANDS_SHORTS=""
  HANDS_BAD=""
  [ "$1" != none ] || return 0
  set -f
  for t in $1; do
    full=$(git rev-parse --verify --quiet "$t^{commit}" < /dev/null 2> /dev/null)
    if [ -z "$full" ]; then
      HANDS_BAD=$(printf '%s' "$t" | detail_clean)
      set +f
      return 1
    fi
    HANDS_FIXES="$HANDS_FIXES$full
"
    HANDS_SHORTS="$HANDS_SHORTS $(short_sha "$full")"
  done
  set +f
  return 0
}

# handson_verdict: judges the record's "## Hands-on pass" section for the cut's commit (Story 11.15; REL-7). Only the Contest Planner writes the
# section; this function reads it and writes nothing. The form (lines in any order, prose may follow):
#   ## Hands-on pass
#   Result: pass | carry-over
#   Candidate: <v> rc<n>, release/<v>-rc<n> at <the cut's full sha>
#   Fixes: none | <commit>...            (a pass)
#   Note: <the Contest Planner's note>   (a carry-over)
# Refuses (exit 2, nothing written) in this order: no section, another commit, a result that is neither, a pass without a usable Fixes: line, a
# carry-over without a note. A pass with no fix outstanding passes (row pass); a pass with fixes fails the candidate (return 1, through step_fail).
# A carry-over passes (row carried over) in a fixes-only release (the version's last number is above 0), and in a feature release only in a re-cut
# (state from) whose source record, rc<m>.md of this record's folder, reads Mode: release and a pass at from_sha, with Fixes: equal to the picks.
handson_verdict() {
  local rec cand h="## Hands-on pass" t note from src bad=0 want got k fshort
  rec=$(record_abs)
  cand=$(sget cand_sha)
  [ -n "$(record_section "$rec" "$h")" ] ||
    refuse "hands-on the record holds no \"## Hands-on pass\" section for $branch ($(short_sha "$cand")); the Contest Planner records the pass or the carry-over there first"
  gate_verdict "$h" -
  case $GATE_CAND in
    *" at $cand") ;;
    *) refuse "hands-on the \"## Hands-on pass\" section names another commit; its Candidate: line must end with \" at $cand\"" ;;
  esac
  case $GATE_RESULT in
    pass | carry-over) ;;
    *) refuse "hands-on the \"## Hands-on pass\" section reads Result: $(dash "$(printf '%s' "$GATE_RESULT" | detail_clean)"); only pass or carry-over goes on" ;;
  esac
  if [ "$GATE_RESULT" = pass ]; then
    t=$(record_field "$rec" "$h" Fixes)
    [ -n "$t" ] || refuse "hands-on a pass needs a Fixes: line: none, or the commits that fix its findings"
    handson_fixes "$t" || refuse "hands-on the Fixes: line names $HANDS_BAD, which is not a commit of this repository"
    if [ -n "$HANDS_SHORTS" ]; then
      step_fail hands-on "the pass on $branch recorded fixes that are not in this candidate; cut the next one with release.sh start --version $version --from $branch --pick$HANDS_SHORTS"
      return 1
    fi
    STEP_ROW=pass
    STEP_DETAIL=$(printf '%s' "the author's hands-on pass (REL-7) on $branch ($(short_sha "$cand")) is recorded, with no fix outstanding" | detail_clean)
    echo "PASS hands-on $STEP_DETAIL"
    return 0
  fi
  note=$(record_field "$rec" "$h" Note)
  [ -n "$note" ] || refuse "hands-on a carry-over needs the Contest Planner's note on a Note: line"
  note=$(printf '%s' "$note" | detail_clean)
  STEP_ROW="carried over"
  if [ "$((10#${version##*.}))" -ne 0 ]; then
    STEP_DETAIL=$(printf '%s' "the author's hands-on pass (REL-7) is carried over to $branch ($(short_sha "$cand")), a fixes-only release: $note" | detail_clean)
    echo "PASS hands-on $STEP_DETAIL"
    return 0
  fi
  from=$(sget from)
  [ -n "$from" ] ||
    refuse "hands-on $version is a feature release, so it needs a fresh pass on this candidate; a pass carries over only to a re-cut from the passed candidate plus the fixes it recorded"
  src="$(dirname "$rec")/rc${from##*-rc}.md"
  [ "$(record_field "$src" "## Release sequence" Mode)" = release ] || bad=1
  [ "$(record_field "$src" "$h" Result)" = pass ] || bad=1
  case $(record_field "$src" "$h" Candidate) in
    *" at $(sget from_sha)") ;;
    *) bad=1 ;;
  esac
  t=$(record_field "$src" "$h" Fixes)
  [ -n "$t" ] || bad=1
  if [ "$bad" -eq 0 ]; then handson_fixes "$t" || bad=1; fi
  [ "$bad" -eq 0 ] ||
    refuse "hands-on $from, which this candidate was cut from, has no hands-on pass on $(short_sha "$(sget from_sha)") in a release record"
  want=$(printf '%s' "$HANDS_FIXES" | sed '/^$/d' | sort -u)
  # shellcheck disable=SC2046
  got=$(printf '%s\n' $(sget picks_full) | sed '/^$/d' | sort -u)
  [ "$want" = "$got" ] || refuse "hands-on the picks of this re-cut are not the fixes that the pass on $from recorded"
  k=$(printf '%s\n' "$got" | sed '/^$/d' | wc -l | tr -d ' ')
  fshort=$(short_sha "$(sget from_sha)")
  STEP_DETAIL=$(printf '%s' "the author's hands-on pass (REL-7) on $from ($fshort) is carried over to $branch ($(short_sha "$cand")) with the fixes it recorded ($k): $note" | detail_clean)
  echo "PASS hands-on $STEP_DETAIL"
  return 0
}

# step_hands_on: the first arrival stops (row waiting; return 6 maps to the hands-on stop) and names the candidate to install and the form of the
# Contest Planner's section; no pass is recorded here (REL-7). Every later call returns what handson_verdict returns. It asks nothing.
step_hands_on() {
  local cand
  if ! grep -q "^hands-on$TAB" "$rows" 2> /dev/null; then
    cand=$(sget cand_sha)
    STEP_ROW=waiting
    STEP_DETAIL="the author's hands-on pass (REL-7) on $branch is not recorded"
    echo "STOPPED hands-on every automated gate passed; install $branch ($(short_sha "$cand")) for the author's hands-on pass (REL-7); this sequence does not record that pass"
    echo "NOTE hands-on the Contest Planner records it in $(record_relpath_or_abs) under \"## Hands-on pass\" with Result: pass and Fixes: none (or the fix commits), or Result: carry-over and Note: <why>, and Candidate: $version rc$rc, $branch at $cand; release.sh resume then reads it"
    return 6
  fi
  handson_verdict
}

# --- commands ---

cli_usage() {
  sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

# need_value <option> <argument count>: refuses an option with no value.
need_value() {
  [ "$2" -ge 2 ] || refuse "$1 needs a value"
}

# load_state: sets sdir, sfile, rows and the variables of the state for version/rc.
load_state() {
  sdir=$(release_state_dir "$version" "$rc")
  sfile="$sdir/state.env"
  rows="$sdir/rows.tsv"
  [ -f "$sfile" ] || return 1
  integration=$(sget integration)
  remote=$(sget remote)
  record=$(sget record)
  branch=$(candidate_branch "$version" "$rc")
  return 0
}

# find_state: picks the state of the command: the given version and rc, or the one state with steps left.
find_state() {
  local root f v r next pushed found="" n=0
  if [ -n "$version" ] && [ -n "$rc" ]; then
    load_state || refuse "no sequence for $version rc$rc"
    return 0
  fi
  if [ -n "$version$rc" ]; then
    refuse "pass --version and --rc together"
  fi
  root=$(state_root)
  for f in "$root"/*/state.env; do
    [ -f "$f" ] || continue
    next=$(env_get "$f" next)
    pushed=$(env_get "$f" rec_pushed)
    if [ "$next" != done ] || [ "$pushed" = 0 ]; then
      found="$f"
      n=$((n + 1))
    fi
  done
  if [ "$n" -eq 0 ]; then
    n=0
    for f in "$root"/*/state.env; do
      [ -f "$f" ] || continue
      found="$f"
      n=$((n + 1))
    done
    [ "$n" -le 1 ] || refuse "more than one sequence exists and none has steps left; name --version and --rc"
  fi
  [ "$n" -ge 1 ] || refuse "no sequence has steps left; start one, or name --version and --rc"
  [ "$n" -le 1 ] || refuse "more than one sequence has steps left; name --version and --rc"
  version=$(env_get "$found" version)
  rc=$(env_get "$found" rc)
  load_state
}

cmd_status() {
  local line art
  find_state
  echo "STATE $version rc$rc next $(sget next)"
  echo "RECORD $(record_relpath_or_abs)"
  hands_line "$(sget handson)" "$(earlier_hands "$(dirname "$(record_abs)")" "$rc")" "$version"
  if [ -f "$(record_abs)" ]; then
    line=$(awk '/^## Release sequence[ \t]*$/ { in_s = 1; next } in_s && /^## / { exit } in_s && /^Result: / { print; exit }' "$(record_abs)")
    [ -z "$line" ] || echo "$line"
  fi
  art=$(ipm_artifact_path "$version" "$rc")
  if [ "$(sget ipm_result)" = pass ] && [ -f "$art" ]; then
    echo "ARTIFACT $art $(wc -c < "$art" | tr -d ' ') $(sha256_file "$art")"
  fi
  exit 0
}

cmd_next() {
  local step code
  find_state
  step=$(sget next)
  if [ "$step" = done ]; then
    if [ "$(sget rec_pushed)" = 0 ]; then
      stop_routine end done ""
      exit "$STOP_CODE"
    fi
    echo "DONE every step of $version rc$rc has run"
    exit 0
  fi
  if ! type "step_${step//-/_}" > /dev/null 2>&1; then
    refuse "the state names an unknown step '$step'"
  fi
  "step_${step//-/_}"
  code=$?
  case $code in
    0)
      row_set "$step" "$STEP_ROW" "$STEP_DETAIL"
      sset next "$(next_step "$step")"
      if [ "$(sget next)" = done ]; then
        stop_routine end "$step" ""
        exit "$STOP_CODE"
      fi
      echo "NEXT $(sget next)"
      exit 0
      ;;
    4)
      row_set "$step" "$STEP_ROW" "$STEP_DETAIL"
      stop_routine stopped "$step" ""
      exit "$STOP_CODE"
      ;;
    3)
      echo "NEXT $step"
      exit 0
      ;;
    5) exit 5 ;;
    6)
      row_set "$step" "$STEP_ROW" "$STEP_DETAIL"
      stop_routine hands "$step" ""
      exit "$STOP_CODE"
      ;;
    *)
      row_set "$step" "$STEP_ROW" "$STEP_DETAIL"
      stop_routine failed "$step" "$STEP_DETAIL"
      exit "$STOP_CODE"
      ;;
  esac
}

cmd_start() {
  local tools t head_branch dirty remote_head head_sha tags n highest d from_ref="" from_sha="" picks="" opt_rc="" short answer code
  while [ $# -gt 0 ]; do
    case $1 in
      --version | --integration | --remote | --record | --rc | --from)
        need_value "$1" $#
        case $1 in
          --version) version=$2 ;;
          --integration) integration=$2 ;;
          --remote) remote=$2 ;;
          --record) record=$2 ;;
          --rc) opt_rc=$2 ;;
          --from) from_ref=$2 ;;
        esac
        shift 2
        ;;
      --pick)
        need_value "$1" $#
        shift
        while [ $# -gt 0 ]; do
          case $1 in
            -*) break ;;
          esac
          picks="${picks:+$picks }$1"
          shift
        done
        [ -n "$picks" ] || refuse "--pick needs a commit"
        ;;
      *) refuse "unknown option '$1'" ;;
    esac
  done
  [ -n "$version" ] || refuse "--version <x.y.z> is required"
  printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse "--version must be x.y.z"
  [ -z "$opt_rc" ] || printf '%s\n' "$opt_rc" | grep -Eq '^[1-9][0-9]{0,5}$' || refuse "--rc must be a positive whole number"
  [ -n "$integration" ] || integration=feature/OCT_OcuTalon_MVP
  case $integration in
    main | master | HEAD | release/* | rehearsal/* | refs/* | -* | *:* | +*) refuse "--integration $integration is not an integration branch" ;;
  esac
  [ -n "$remote" ] || remote=origin
  for t in git node npm docker; do
    command -v "$t" > /dev/null 2>&1 || refuse "$t is not installed"
  done
  [ "$(git rev-parse --show-toplevel < /dev/null 2> /dev/null)" = "$rel_root" ] || refuse "$rel_root is not the top of a git repository"
  git remote get-url "$remote" < /dev/null > /dev/null 2>&1 || refuse "no remote named $remote"
  head_branch=$(git symbolic-ref --short -q HEAD < /dev/null 2> /dev/null)
  [ "$head_branch" = "$integration" ] || refuse "the checkout is not on $integration"
  dirty=$(git status --porcelain --untracked-files=all < /dev/null 2> /dev/null | grep -v '^?? release/records/' | wc -l | tr -d ' ')
  [ "$dirty" -eq 0 ] || refuse "the checkout has changes outside release/records/: $dirty path(s)"
  remote_head=$(git ls-remote "$remote" "refs/heads/$integration" < /dev/null 2> /dev/null | awk '{ print $1 }')
  [ -n "$remote_head" ] || refuse "$remote has no branch $integration"
  head_sha=$(git rev-parse HEAD < /dev/null)
  [ "$remote_head" = "$head_sha" ] || refuse "$integration differs from $remote/$integration; bring them level first"
  tags=$(release_tags "$remote") || refuse "the tags of $remote could not be read"
  if printf '%s\n' "$tags" | grep -qxF "v$version"; then
    refuse "v$version is already tagged"
  fi
  if [ -z "$tags" ] && [ "$version" != "$KIT_VERSION" ]; then
    refuse "the first release is $KIT_VERSION"
  fi
  n=$(next_rc "$version" "$remote") || refuse "the branches of $remote could not be read"
  for d in "$(state_root)/$version-rc"*; do
    [ -f "$d/state.env" ] || continue
    highest=${d##*-rc}
    case $highest in
      '' | *[!0-9]*) continue ;;
    esac
    [ "$highest" -lt "$n" ] || n=$((highest + 1))
  done
  [ -z "$opt_rc" ] || [ "$opt_rc" = "$n" ] || refuse "--rc $opt_rc is not the next number; the next is rc$n"
  rc=$n
  branch=$(candidate_branch "$version" "$rc")
  if git rev-parse --verify --quiet "refs/heads/$branch" < /dev/null > /dev/null 2>&1; then
    refuse "$branch already exists"
  fi
  if [ -n "$from_ref" ]; then
    case $from_ref in
      "release/$version-rc"[1-9]*) ;;
      *) refuse "--from must name a candidate branch release/$version-rc<m>" ;;
    esac
    from_sha=$(git rev-parse --verify --quiet "refs/heads/$from_ref^{commit}" < /dev/null 2> /dev/null)
    [ -n "$from_sha" ] || from_sha=$(git rev-parse --verify --quiet "refs/remotes/$remote/$from_ref^{commit}" < /dev/null 2> /dev/null)
    [ -n "$from_sha" ] || refuse "--from $from_ref is not a branch of this repository; fetch it first"
  elif [ -n "$picks" ]; then
    refuse "--pick needs --from <candidate branch>"
  fi
  [ -n "$record" ] || record=$(record_path "$version" "$rc")
  short=${head_sha%"${head_sha#???????}"}
  if [ "$version" = "$KIT_VERSION" ]; then
    ask kit "Is everything that $version should hold on $integration at $short?"
    code=$?
    [ "$code" -eq 0 ] || refuse "the author did not confirm the $version kit"
  fi
  sdir=$(release_state_dir "$version" "$rc")
  sfile="$sdir/state.env"
  rows="$sdir/rows.tsv"
  rm -rf "$sdir"
  mkdir -p "$sdir" || refuse "the state folder could not be created"
  : > "$sfile"
  : > "$rows"
  sset version "$version"
  sset rc "$rc"
  sset integration "$integration"
  sset remote "$remote"
  sset record "$record"
  sset from "$from_ref"
  sset from_sha "$from_sha"
  sset picks "$picks"
  sset base_sha "$head_sha"
  sset next "$(printf '%s\n' $STEPS | head -n 1)"
  sset handson "$HANDS_PENDING"
  sset rec_pushed 0
  sset started "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$version" = "$KIT_VERSION" ]; then
    row_set kit confirmed "the author confirmed the $version kit is on $integration at $short"
  fi
  echo "START $version rc$rc from $integration at $short"
  echo "NEXT $(sget next)"
  exit 0
}

release_main() {
  local cmd=${1:-}
  version=""
  rc=""
  integration=""
  remote=""
  record=""
  if [ $# -eq 0 ]; then
    cli_usage
    exit 2
  fi
  shift
  cd "$rel_root" || exit 1
  case $cmd in
    start) cmd_start "$@" ;;
    next | resume | status)
      while [ $# -gt 0 ]; do
        case $1 in
          --version)
            need_value "$1" $#
            version=$2
            shift 2
            ;;
          --rc)
            need_value "$1" $#
            rc=$2
            shift 2
            ;;
          *) refuse "unknown option '$1'" ;;
        esac
      done
      if [ "$cmd" = status ]; then cmd_status; else cmd_next; fi
      ;;
    *)
      cli_usage
      exit 2
      ;;
  esac
}

# Sourced, it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi
release_main "$@"
