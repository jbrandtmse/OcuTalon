#!/usr/bin/env bash
# release/release.sh start --version <x.y.z> [--from release/<v>-rc<m> --pick <sha>...] [--integration <branch>] [--remote <name>] [--record <file>] [--rc <n>]
# release/release.sh next|resume|status [--version <v> --rc <n>]   (required when more than one state has steps left)
# Steps, in order: cut image stubs push ci eval upgrade rehearsal notes checklist hands-on  (Stories 11.15-11.18 build on STEPS)
# Exit: 0 step or phase done, 1 a step failed, 2 refused (nothing written), 4 stopped for the author's word, 5 waiting (nothing written)
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
#          the last one ends the sequence. A stop (a step that fails, an ASK that is not answered yes, or the end of the steps) writes
#          the record, commits only that file on the integration branch, and asks to push that commit.
# status   prints STATE <v> rc<n> next <step>, RECORD <file>, the hands-on time and the record's result; it changes nothing.
#
# The steps. cut makes the candidate in a temporary clone inside the state folder (so the author's checkout is never switched): the
# integration head (or --from's candidate plus the cherry-picked --pick commits, each an integration-branch commit), one cut commit that
# sets src/module.xml to the version and force-adds the built web bundle, then the branch release/<v>-rc<n> in the author's repository.
# A candidate branch is never moved, re-committed, force-pushed or deleted. image builds the candidate's own tree and reads
# /opt/ocutalon/version in the image, which must equal the version, and removes the check image. push asks, then pushes the candidate
# branch. notes runs release/notes.sh for the draft, which stays uncommitted.
#
# The gates (Story 11.14; REL-1, REL-5, REL-6, REL-7, AD-5, AD-29). Each runs a gate's own script, or reads its verdict, and the first that
# does not pass stops the sequence and is named: FAIL <gate> <what it said>, and the record reads "Result: failed at <gate>: ...". The next
# next runs the same gate again, never the one after it. stubs (before the push) refuses an enabled production item whose class has
# Parameter STUB = 1. ci reads the push runs of the candidate's commit with gh run list (read only). eval reads the author's evaluation
# result in the clone <state>/eval: the author runs "bash eval/run.sh --release-candidate" there, with the key, and REL-5's override
# (eval/run.sh --override) is the only override. upgrade and rehearsal run in the clone <state>/candidate, one phase of the gate's script per
# next, with a fixed run tag; the rehearsal is rehearse.sh run, called once per next. checklist runs release/checklist.sh there after
# notes. A gate passes only on its script's exit 0, its own section reading Result: pass, the candidate's full sha in the section's
# Candidate: line and the real Mode: (release for the upgrade harness, rehearsal for the rehearsal). Exit 5 (WAIT <step> <reason>) is a wait
# for work outside the sequence (CI, the evaluation, a busy lane lock): it writes no record and asks nothing. hands-on is the last gate and
# stops here, never passing, until Story 11.15 builds it.
#
# The author's word. Each outward step prints "ASK <id> <question> [yes/no]" and reads one line of standard input; only "yes" goes on.
# End of input is no answer: STOPPED <id> waiting for the author's word, exit 4. No option or variable answers a question.
# Hands-on time is the sum of the windows from printing an ASK to reading its answer on one clock; it is kept in the state, written into
# the record at every stop, and WARN is printed when the version's sum is over 15 minutes (900 s). It refuses nothing.
#
# Pushes: exactly two, each on the author's word: the candidate branch, and the integration branch fast-forward with the record commit.
# Never a force, a tag, main or another ref. No value of the environment is ever printed.
# Output: PASS|FAIL <step> <detail>, then RECORD <file> and RESULT <stopped|fail>. This script reports no pass for a release.
# Needs bash 3.2 or later, git, awk, node, npm and docker (the base image of docker/Dockerfile for the image step), and gh for the ci step.
#
# Sourced, it defines its functions and runs nothing.
umask 077

rel_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$rel_root/release/lib-release.sh"
. "$rel_root/docker/tests/lib-live.sh"
. "$rel_root/docker/tests/lib-upgrade.sh"

# The ordered steps; step_<name> is the function of a step. A sibling story adds its name and its function.
STEPS="cut image stubs push ci eval upgrade rehearsal notes checklist hands-on"
HANDS_TARGET=900
TAB=$(printf '\t')
KIT_VERSION=1.0.0

# --- output ---

refuse() {
  echo "REFUSED $*"
  exit 2
}

# --- the state ---

state_root() { printf '%s\n' "${OCUTALON_RELEASE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ocutalon/release}"; }

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

# stop_routine <end|stopped|handson|failed> <step> <detail>: writes the record, commits it, asks to push it, and sets STOP_CODE.
STOP_CODE=0
stop_routine() {
  local kind=$1 step=$2 detail=$3 result last rec_detail code
  case $kind in
    end)
      last=$(printf '%s\n' $STEPS | tail -n 1)
      result="stopped after $last: no hands-on pass is recorded (not a release)"
      STOP_CODE=0
      ;;
    handson)
      result="stopped at $step: every automated gate passed; no hands-on pass recorded (not a release)"
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

# cut_clean: removes the temporary clone and the image context.
cut_clean() { rm -rf "$sdir/clone" "$sdir/context"; }

step_cut() {
  local clone="$sdir/clone" start_sha picks full p short out name email cand
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
  stamp_version "$clone/src/module.xml" "$version" > "$clone/src/module.xml.new" && mv "$clone/src/module.xml.new" "$clone/src/module.xml"
  if [ "$(manifest_version "$clone/src/module.xml")" != "$version" ]; then
    cut_clean
    step_fail cut "src/module.xml has no <Version> to set"
    return 1
  fi
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
  if ! git -C "$clone" add -f -- src/module.xml src/ocutalon/csp < /dev/null > /dev/null 2>&1 \
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
  STEP_DETAIL="src/module.xml set to $version; web bundle built with Node.js and committed"
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
  base=${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}
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
  sset pushed_at "$(clock)"
  STEP_ROW=pass
  STEP_DETAIL="$branch pushed to $remote on the author's word"
  echo "PASS push $branch"
  return 0
}

step_notes() {
  local out code res file notes eval_args
  notes=$(notes_path "$version" "$rc")
  eval_args=()
  [ ! -f "$sdir/release-candidate.json" ] || eval_args=(--eval "$sdir/release-candidate.json")
  out=$(bash "$rel_root/release/notes.sh" --version "$version" --rc "$rc" --candidate "$branch" --record "$record" ${eval_args[@]+"${eval_args[@]}"} < /dev/null 2>&1)
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
# A gate step prints one PASS, FAIL or WAIT line. It returns 0 (passed, or a phase done with STEP_MORE=1), 1 (failed), 5 (waiting for work
# outside the sequence) or 6 (the hands-on stop).

STEP_MORE=0
GATE_WHY=""
UPG_PHASES="build settings seed upgrade restart storage report down"
REH_RUNS=20
CI_WAIT=900

# run_tag <upg|reh>: the fixed run tag of a gate's phases, for example rel100rc1upg.
run_tag() { printf 'rel%src%s%s\n' "${version//./}" "$rc" "$1"; }

# gate_run <label> <dir> <tag> <log> <script> <argument>...: runs a gate's script in <dir> (with the run tag when one is given), prints its
# output behind the label, keeps it in <log> and returns its exit status.
gate_run() {
  local label=$1 dir=$2 tag=$3 log=$4 script=$5
  shift 5
  : > "$log"
  (
    cd "$dir" || exit 1
    [ -z "$tag" ] || export OCUTALON_RUN_TAG="$tag"
    bash "$script" "$@" < /dev/null 2>&1
  ) | tee -a "$log" | sed "s/^/$label: /"
  return "${PIPESTATUS[0]}"
}

# log_line <log> <prefix>: the last line of the log that starts with the prefix.
log_line() { grep -e "^$2" "$1" 2> /dev/null | tail -n 1; }

# gate_verdict <section heading> <wanted Mode: or empty> <exit status of the gate> [<more>]: judges a gate that writes its own section into the
# record. It passes only when the exit status is 0, the section reads Result: pass, its Candidate: line holds the candidate's full sha and,
# when a mode is wanted, its Mode: is that one. Sets GATE_WHY otherwise.
gate_verdict() {
  local rec res cand mode sha=$(sget cand_sha)
  rec=$(record_abs)
  res=$(record_field "$rec" "$1" Result)
  cand=$(record_field "$rec" "$1" Candidate)
  mode=$(record_field "$rec" "$1" Mode)
  GATE_WHY=""
  if [ -z "$sha" ]; then
    GATE_WHY="the candidate's sha is not in the state"
    return 1
  fi
  if [ "$3" -ne 0 ]; then
    if [ -n "$res" ] && [ "$res" != pass ]; then
      GATE_WHY="Result: $res (exit $3)"
    elif [ -n "$res" ]; then
      GATE_WHY="the script exited $3 although its section reads Result: pass"
    else
      GATE_WHY="the script exited $3 and its section has no Result"
    fi
    [ -z "${4:-}" ] || GATE_WHY="$GATE_WHY; $4"
    return 1
  fi
  if [ -z "$res" ]; then
    GATE_WHY="the record has no ${1#\#\# } section with a Result"
    return 1
  fi
  if [ "$res" != pass ]; then
    GATE_WHY="Result: $res"
    [ -z "${4:-}" ] || GATE_WHY="$GATE_WHY; $4"
    return 1
  fi
  case $cand in
    *"$sha"*) ;;
    *)
      GATE_WHY="the section names another candidate than ${sha%"${sha#???????}"}"
      return 1
      ;;
  esac
  if [ -n "$2" ] && [ "$mode" != "$2" ]; then
    GATE_WHY="Mode: ${mode:-none}, wanted $2"
    return 1
  fi
  return 0
}

step_stubs() {
  local cand tree out code counts found items prods dis
  cand=$(sget cand_sha)
  if [ -z "$cand" ]; then
    step_fail stubs "the candidate is not cut"
    return 1
  fi
  tree="$sdir/stubs-tree"
  rm -rf "$tree"
  mkdir -p "$tree"
  if ! git archive "$cand" src < /dev/null | tar -x -C "$tree"; then
    rm -rf "$tree"
    step_fail stubs "the candidate's source could not be exported"
    return 1
  fi
  out=$(production_stubs "$tree")
  code=$?
  rm -rf "$tree"
  case $code in
    0) ;;
    1)
      found=$(printf '%s\n' "$out" | awk -F'|' '$1 == "FOUND" { printf "%s%s:%s (%s) answers \"not implemented\"", sep, $2, $3, $4; sep = "; " }')
      step_fail stubs "$found"
      return 1
      ;;
    3)
      step_fail stubs "the scan of the candidate's productions printed no result"
      return 1
      ;;
    *)
      step_fail stubs "the candidate holds no production definition to check"
      return 1
      ;;
  esac
  counts=$(printf '%s\n' "$out" | sed -n 's/^COUNTS|//p' | tail -n 1)
  items=${counts%%|*}
  counts=${counts#*|}
  prods=${counts%%|*}
  counts=${counts#*|}
  dis=${counts%%|*}
  STEP_ROW=pass
  STEP_DETAIL="no enabled item answers \"not implemented\": $items items in $prods productions checked, $dis stub item(s), all disabled"
  echo "PASS stubs $items items in $prods productions, $dis stub item(s) disabled"
  return 0
}

# ci_runs <json>: one line "<workflow><TAB><run id><TAB><status><TAB><conclusion>" for the newest run of each workflow, then OK; BAD when the
# text is not a list of runs.
ci_runs() {
  printf '%s' "$1" | node -e '
let s = "";
process.stdin.on("data", (d) => { s += d; }).on("end", () => {
  let a;
  try { a = JSON.parse(s); } catch (e) { console.log("BAD"); return; }
  if (!Array.isArray(a)) { console.log("BAD"); return; }
  const m = {};
  for (const r of a) {
    if (r === null || typeof r !== "object" || typeof r.workflowName !== "string") continue;
    const id = Number(r.databaseId);
    const name = r.workflowName.replace(/[^A-Za-z0-9_.-]/g, "?");
    if (!(name in m) || id > m[name].id) m[name] = { id: id, status: String(r.status), conclusion: String(r.conclusion || "") };
  }
  for (const k of Object.keys(m).sort()) console.log([k, m[k].id, m[k].status, m[k].conclusion].join("\t"));
  console.log("OK");
});' 2> /dev/null
}

step_ci() {
  local cand repo json runs w red ok_list pending now pushed missing="" short
  cand=$(sget cand_sha)
  short=${cand%"${cand#???????}"}
  if ! command -v gh > /dev/null 2>&1; then
    step_fail ci "gh is not installed"
    return 1
  fi
  if ! repo=$(gh_repo "$remote"); then
    step_fail ci "$remote is not a github.com repository, so its runs cannot be read"
    return 1
  fi
  if ! json=$(gh run list --repo "$repo" --branch "$branch" --commit "$cand" --event push --limit 100 --json databaseId,workflowName,status,conclusion,url < /dev/null 2> /dev/null); then
    step_fail ci "gh run list failed"
    return 1
  fi
  runs=$(ci_runs "$json")
  if [ "$(printf '%s\n' "$runs" | tail -n 1)" != OK ]; then
    step_fail ci "gh run list printed no list of runs"
    return 1
  fi
  red=$(printf '%s\n' "$runs" | awk -F'\t' '$1 != "OK" && $3 == "completed" && $4 != "success" { c = $4; if (c == "") c = $3; print $1 " run " $2 " " c; exit }')
  if [ -n "$red" ]; then
    step_fail ci "$red"
    return 1
  fi
  pending=$(printf '%s\n' "$runs" | awk -F'\t' '$1 != "OK" && $3 != "completed" { printf "%s%s run %s %s", sep, $1, $2, $3; sep = ", " }')
  ok_list=$(printf '%s\n' "$runs" | awk -F'\t' '$1 != "OK" && $3 == "completed" && $4 == "success" { printf "%s%s run %s", sep, $1, $2; sep = "; " }')
  for w in ci lane-a; do
    printf '%s\n' "$runs" | cut -f1 | grep -qxF "$w" || missing="${missing:+$missing, }$w"
  done
  if [ -n "$missing" ]; then
    pushed=$(sget pushed_at)
    now=$(clock)
    case $pushed in
      '' | *[!0-9]*)
        pushed=$now
        sset pushed_at "$now"
        ;;
    esac
    if [ $((now - pushed)) -ge "$CI_WAIT" ]; then
      step_fail ci "no $missing run on $short"
      return 1
    fi
    echo "WAIT ci no $missing run on $short yet (it may start up to 15 min after the push)"
    return 5
  fi
  if [ -n "$pending" ]; then
    echo "WAIT ci $pending"
    return 5
  fi
  STEP_ROW=pass
  STEP_DETAIL="every push run of ${short} concluded success: $ok_list"
  echo "PASS ci $ok_list"
  return 0
}

# eval_result <file> <sha>: "OK pass", "OK overridden<TAB><reason>" or "BAD <what is wrong>" for the author's evaluation result.
eval_result() {
  node -e '
const fs = require("fs");
const file = process.argv[1];
const sha = process.argv[2];
const clean = (v) => String(v).replace(/\s+/g, " ").replace(/[^\x20-\x7e]/g, "?").trim();
const res = (() => {
  let r;
  try { r = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { return "BAD the result file is not valid JSON"; }
  if (r === null || typeof r !== "object" || Array.isArray(r)) return "BAD the result file is not a JSON object";
  if (r.format !== "ocutalon.evalResult/1") return "BAD the result file is of an unknown format";
  if (r.commit !== sha) return "BAD the result is of another commit (" + clean(r.commit).slice(0, 7) + "), not the candidate";
  if (r.onMock !== false) return "BAD the result ran on the mock, so it is not the real model";
  if (r.treeClean !== true) return "BAD the result was made on a tree that was not clean";
  if (r.verdict === "pass") return "OK pass";
  if (r.verdict === "overridden") {
    const reason = r.override !== null && typeof r.override === "object" && typeof r.override.reason === "string" ? clean(r.override.reason) : "";
    if (reason === "") return "BAD the result is overridden with no reason";
    return "OK overridden\t" + reason;
  }
  if (r.verdict === "blocked") return "BAD the verdict is blocked (REL-5: the author may override it with eval/run.sh --override, with a reason, in the eval clone)";
  if (r.verdict === "incomplete") return "BAD the verdict is incomplete: not every attempt has run";
  return "BAD the verdict is " + clean(r.verdict);
})();
console.log(res);' "$1" "$2" 2> /dev/null
}

step_eval() {
  local cand clone file res kind reason
  cand=$(sget cand_sha)
  clone="$sdir/eval"
  if ! candidate_clone "$clone" "$version" "$rc" "$cand" "$remote"; then
    step_fail eval "$CLONE_WHY"
    return 1
  fi
  file="$clone/eval/release-candidate.json"
  if [ ! -f "$file" ]; then
    echo "WAIT eval no evaluation result of ${cand%"${cand#???????}"} yet; the author runs it, with the model key, in the eval clone"
    echo "RUN cd $clone && bash eval/run.sh --release-candidate"
    return 5
  fi
  res=$(eval_result "$file" "$cand")
  [ -n "$res" ] || res="BAD the result file could not be judged (node failed)"
  kind=${res%%[ ]*}
  if [ "$kind" != OK ]; then
    step_fail eval "${res#BAD }"
    return 1
  fi
  cp "$file" "$sdir/release-candidate.json"
  reason=${res#*"$TAB"}
  case $res in
    "OK overridden$TAB"*)
      STEP_ROW=overridden
      STEP_DETAIL="overridden (REL-5): $reason"
      echo "PASS eval overridden (REL-5): $reason"
      ;;
    *)
      STEP_ROW=pass
      STEP_DETAIL="pass: the real model's result for the candidate, tree clean"
      echo "PASS eval pass"
      ;;
  esac
  return 0
}

# upg_next <phase>: the harness phase after it.
upg_next() {
  local p want=""
  for p in $UPG_PHASES; do
    if [ "$want" = yes ]; then
      echo "$p"
      return 0
    fi
    [ "$p" != "$1" ] || want=yes
  done
  echo done
}

step_upgrade() {
  local ph tag clone log code failed why req
  ph=$(sget upg_phase)
  [ -n "$ph" ] || ph=build
  tag=$(run_tag upg)
  clone="$sdir/candidate"
  log="$sdir/upgrade.log"
  if [ "$ph" = build ]; then
    rm -rf "$clone"
    sset upg_fail 0
    sset upg_why ""
  fi
  if ! candidate_clone "$clone" "$version" "$rc" "$(sget cand_sha)" "$remote"; then
    step_fail upgrade "$CLONE_WHY"
    return 1
  fi
  if [ "$ph" = build ]; then
    gate_run upgrade "$clone" "$tag" "$log" release/upgrade-harness.sh build --version "$version" --rc "$rc" --record "$(record_abs)"
  else
    gate_run upgrade "$clone" "$tag" "$log" release/upgrade-harness.sh "$ph"
  fi
  code=$?
  if [ "$code" -eq 75 ]; then
    echo "WAIT upgrade the lane lock is busy; the $ph phase runs again on the next call"
    return 5
  fi
  case $ph in
    build)
      if [ "$code" -ne 0 ]; then
        gate_run upgrade "$clone" "$tag" "$sdir/upgrade-down.log" release/upgrade-harness.sh down
        sset upg_phase build
        step_fail upgrade "the build phase exited $code: $(tail -n 1 "$log")"
        return 1
      fi
      ;;
    down)
      sset upg_phase build
      [ "$code" -eq 0 ] || echo "WARN upgrade the down phase exited $code; leftovers of run tag $tag may remain"
      failed=$(sget upg_fail)
      why=$(sget upg_why)
      if [ "$failed" = 1 ]; then
        gate_verdict "## Upgrade harness" release 1 "phases that failed:${why}" || true
        step_fail upgrade "$GATE_WHY"
        return 1
      fi
      if ! gate_verdict "## Upgrade harness" release 0; then
        step_fail upgrade "$GATE_WHY"
        return 1
      fi
      req=$(record_field "$(record_abs)" "## Upgrade harness" Required)
      STEP_ROW=pass
      STEP_DETAIL="release/upgrade-harness.sh: Result pass, Mode release, Required ${req:-unknown}, candidate $(sget cand_sha | cut -c1-7)"
      echo "PASS upgrade Result pass, Mode release, Required ${req:-unknown}"
      return 0
      ;;
    *)
      if [ "$code" -ne 0 ]; then
        sset upg_fail 1
        sset upg_why "$(sget upg_why) $ph($code)"
        echo "WARN upgrade the $ph phase exited $code; the remaining phases still run"
      fi
      ;;
  esac
  sset upg_phase "$(upg_next "$ph")"
  STEP_MORE=1
  echo "PASS upgrade phase $ph done"
  return 0
}

step_rehearsal() {
  local tag clone log code refused first due
  tag=$(run_tag reh)
  clone="$sdir/candidate"
  log="$sdir/rehearsal.log"
  if [ "$(sget reh_on)" != 1 ]; then
    rm -rf "$clone"
  fi
  if ! candidate_clone "$clone" "$version" "$rc" "$(sget cand_sha)" "$remote"; then
    sset reh_on 0
    step_fail rehearsal "$CLONE_WHY"
    return 1
  fi
  sset reh_on 1
  gate_run rehearsal "$clone" "$tag" "$log" release/rehearse.sh run --version "$version" --rc "$rc" --candidate "$branch" --record "$(record_abs)" --runs "$REH_RUNS"
  code=$?
  case $code in
    4)
      due=$(log_line "$log" 'NEXT run: ' | sed 's/^NEXT run: //')
      echo "WAIT rehearsal ${due:-the next phase is due}"
      return 5
      ;;
    75)
      echo "WAIT rehearsal the lane lock is busy; the same phase runs again on the next call"
      return 5
      ;;
  esac
  sset reh_on 0
  first=$(log_line "$log" 'FAIL ')
  case $code in
    2)
      gate_run rehearsal "$clone" "$tag" "$sdir/rehearsal-down.log" release/rehearse.sh down
      refused=$(log_line "$log" 'REFUSED ')
      [ -n "$refused" ] || refused=$(tail -n 1 "$log")
      step_fail rehearsal "release/rehearse.sh refused: $refused"
      return 1
      ;;
  esac
  if ! gate_verdict "## Clean-machine rehearsal" rehearsal "$code" "${first:+first failure: $first}"; then
    step_fail rehearsal "$GATE_WHY"
    return 1
  fi
  STEP_ROW=pass
  STEP_DETAIL="release/rehearse.sh run: Result pass, Mode rehearsal, $REH_RUNS runs, candidate $(sget cand_sha | cut -c1-7)"
  echo "PASS rehearsal Result pass, Mode rehearsal, $REH_RUNS runs"
  return 0
}

step_checklist() {
  local clone log code
  clone="$sdir/candidate"
  log="$sdir/checklist.log"
  rm -rf "$clone"
  if ! candidate_clone "$clone" "$version" "$rc" "$(sget cand_sha)" "$remote"; then
    step_fail checklist "$CLONE_WHY"
    return 1
  fi
  gate_run checklist "$clone" "" "$log" release/checklist.sh --version "$version" --rc "$rc" --candidate "$branch" --record "$(record_abs)" --notes "$rel_root/$(notes_path "$version" "$rc")"
  code=$?
  if [ "$code" -eq 2 ]; then
    step_fail checklist "release/checklist.sh refused: $(log_line "$log" 'REFUSED ')"
    return 1
  fi
  if ! gate_verdict "## Release checklist" "" "$code"; then
    step_fail checklist "$GATE_WHY"
    return 1
  fi
  STEP_ROW=pass
  STEP_DETAIL="release/checklist.sh: Result pass, candidate $(sget cand_sha | cut -c1-7)"
  echo "PASS checklist Result pass"
  return 0
}

step_hands_on() {
  STEP_ROW="not run"
  STEP_DETAIL="the hands-on gate is Story 11.15's; no hands-on pass is recorded"
  echo "STOPPED hands-on the hands-on gate is Story 11.15's"
  return 6
}

# --- commands ---

cli_usage() {
  sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

# need_value <option> <argument count>: refuses an option with no value.
need_value() {
  [ "$2" -ge 2 ] || refuse "$1 needs a value"
}

# load_state: sets sdir, sfile, rows and the variables of the state for version/rc.
load_state() {
  sdir="$(state_root)/$version-rc$rc"
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
  local line
  find_state
  echo "STATE $version rc$rc next $(sget next)"
  echo "RECORD $(record_relpath_or_abs)"
  hands_line "$(sget handson)" "$(earlier_hands "$(dirname "$(record_abs)")" "$rc")" "$version"
  if [ -f "$(record_abs)" ]; then
    line=$(awk '/^## Release sequence[ \t]*$/ { in_s = 1; next } in_s && /^## / { exit } in_s && /^Result: / { print; exit }' "$(record_abs)")
    [ -z "$line" ] || echo "$line"
  fi
  exit 0
}

cmd_next() {
  local step code fn
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
  fn="step_${step//-/_}"
  if ! type "$fn" > /dev/null 2>&1; then
    refuse "the state names an unknown step '$step'"
  fi
  STEP_MORE=0
  "$fn"
  code=$?
  case $code in
    0)
      if [ "$STEP_MORE" = 1 ]; then
        echo "NEXT $step"
        exit 0
      fi
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
    5) exit 5 ;;
    6)
      row_set "$step" "$STEP_ROW" "$STEP_DETAIL"
      stop_routine handson "$step" ""
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
  sdir="$(state_root)/$version-rc$rc"
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
