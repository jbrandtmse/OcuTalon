#!/usr/bin/env bash
# The warm throwaway (Story 32.4): on a developer machine, one IRIS stack per lane that stays up between the calls of a stage, so that
# OCUTALON_WARM=1 ci/iris.sh class|shard runs on it and starts nothing. It is a throwaway like any other (docker/tests/lib-live.sh,
# ci/compose.ci.yml, no key, no published port), and CI never uses it: no workflow names it, and ci/iris.sh loads this file only for
# OCUTALON_WARM=1.
#
#   OCUTALON_RUN_TAG=<tag> ci/warm.sh up       starts the warm stack of the tag, or says that it is already up
#   OCUTALON_RUN_TAG=<tag> ci/warm.sh down     removes every project of the tag (ci/iris.sh teardown) and the state of the stack
#   OCUTALON_RUN_TAG=<tag> ci/warm.sh status   "WARM up project=<P> tag=<tag> since=<UTC>" (exit 0) or "WARM none for tag <tag>" (exit 1)
#
# The tag is the warm stack's own: no fresh run uses it, and no other run's tag ends with it. Exit 2 without a valid tag or for an
# unknown command, 75 when the lane's warm lock is held, 1 for a failed start.
#
# The lock. The stack holds warm-iris.lock in the lane's lock folder (live_lock_dir) from before the start until down, with lib-live's
# protocol: an atomic create, the content "<OCUTALON_LOCK_OWNER> project=<P> acquired_at=<UTC>", the LOCK lines, OCUTALON_LOCK_WAIT and
# the sleep bounds, exit 75 when busy. Fresh stacks keep throwaway-iris.lock, so a lane has at most one warm and one fresh stack, and
# its fresh runs never wait on its warm one. With no lock folder, no lock is taken. The claim and the release are lib-live's own
# functions with the lock's name changed (warm_lock_install); if that change no longer yields warm-iris.lock, up fails closed.
#
# The state. ${TMPDIR:-/tmp}/ocutalon-warm-<tag>/ holds the project name, the repository root, the up time, the stack's compose
# files (the judges' file, a decoy key file, the throwaway and CI overrides, and warm.yml, which mounts ./src read-only at
# /opt/ocutalon/warm-src), the manifest, and a "failed" marker after a reload that did not end OK. The state exists once the project
# file does; a failed or killed up removes the folder, the project, its image and the lock, and so does ci/iris.sh teardown for the tag.
#
# The manifest lists "<content hash> <path>" for every file the image is built from (the Dockerfile's COPY sources, the web bundle
# included) and every file that defines the stack (the compose files and the mock's files under ci/mock, which the mock service mounts
# and loads at its start), taken after the web bundle exists and before the build. A warm run compares the
# tree with it:
#   - any non-class path that changed, appeared or went refuses the run (only classes reload);
#   - a class file that changed or is new is imported from the mounted tree, and a class that went is deleted;
#   - the imported classes and their subclasses are compiled; every class of the tree is compiled after a delete or a failed reload,
#     so a class that names a removed class fails as it would on a fresh stack;
#   - the stored manifest follows each import and delete that succeeded, so one that failed is tried again.
# What the start did (the installer steps, the production's items) is not redone: a change to it is proved on a fresh stack.
#
# Sourced (by ci/iris.sh for a warm run, and by docker/tests/test-ci-warm.sh), it defines functions and runs nothing.
set -u

# --- the state of a warm stack (warm_state_dir is defined in ci/iris.sh, whose teardown removes the folder) ---

# warm_running <project>: the iris container of the project is running.
warm_running() {
  [ -n "$(docker ps --filter "label=com.docker.compose.project=$1" --filter label=com.docker.compose.service=iris --filter status=running --format '{{.ID}}' 2>/dev/null)" ]
}

# warm_usage: the header, which gives the commands and the contract.
warm_usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$root/ci/warm.sh" >&2
}

# --- the lock ---

# warm_lock_text: lib-live's lock claim and release as function definitions, with the lock's name changed to warm-iris.
warm_lock_text() {
  declare -f live_lock_claim live_lock_release | sed 's/throwaway-iris/warm-iris/g'
}

# warm_lock_install: defines the warm claim and release in this process, so that live_start claims warm-iris.lock before anything
# starts and live_cleanup releases it. Returns 1 when the changed text does not name warm-iris.lock, or still names throwaway-iris.
warm_lock_install() {
  local text
  text=$(warm_lock_text)
  if [ -z "$text" ] || [ "${text#*throwaway-iris}" != "$text" ] || [ "${text#*warm-iris.lock}" = "$text" ]; then
    echo "FAIL WARM the warm lock could not be derived from lib-live.sh"
    return 1
  fi
  eval "$text"
}

# --- the manifest of what the stack was built from ---

# warm_manifest: "<content hash> <path>" for each file of the Dockerfile's COPY lines and of the stack's definition that exists (the
# compose files, and the files of ci/mock that the mock service mounts and loads at its start, but not its node tests), sorted by path.
# A .DS_Store is no input of the image or the stack.
warm_manifest() {
  local paths f
  paths=$(
    { copied_files; printf '%s\n' docker/Dockerfile .dockerignore docker-compose.yml docker/tests/compose.throwaway.yml ci/compose.ci.yml
      find ci/mock -type f ! -path 'ci/mock/test/*' 2> /dev/null; } \
      | grep -v '/\.DS_Store$' | LC_ALL=C sort -u | while IFS= read -r f; do
      if [ -f "$f" ]; then printf '%s\n' "$f"; fi
    done
  )
  [ -n "$paths" ] || return 0
  printf '%s\n' "$paths" | git hash-object --no-filters --stdin-paths \
    | PATHS="$paths" awk 'BEGIN { split(ENVIRON["PATHS"], p, "\n") } { print $0 " " p[NR] }'
}

# warm_changes <stored manifest> <current manifest>: "A <path>" for each path that is new, "C <path>" for each that changed and
# "D <path>" for each that went, sorted by path.
warm_changes() {
  awk '
    FNR == NR { i = index($0, " "); old[substr($0, i + 1)] = substr($0, 1, i - 1); next }
    { i = index($0, " "); p = substr($0, i + 1); h = substr($0, 1, i - 1); seen[p] = 1
      if (!(p in old)) print "A " p; else if (old[p] != h) print "C " p }
    END { for (p in old) if (!(p in seen)) print "D " p }
  ' "$1" "$2" | LC_ALL=C sort -k2
}

# warm_manifest_apply <updates> <stored> <current>: the stored manifest without the paths of the updates, plus the current entry of
# each path that an update sets. An update line is "drop <path>" or "set <path>".
warm_manifest_apply() {
  awk -v upd="$1" '
    BEGIN { while ((getline u < upd) > 0) { i = index(u, " "); act[substr(u, i + 1)] = substr(u, 1, i - 1) } }
    { i = index($0, " "); p = substr($0, i + 1) }
    FNR == NR { if (!(p in act)) print; next }
    act[p] == "set" { print }
  ' "$2" "$3" | LC_ALL=C sort -k2
}

# warm_is_class <path>: a class file of either source tree.
warm_is_class() {
  case $1 in
    src/*/cls/*.cls) return 0 ;;
  esac
  return 1
}

# --- up and down ---

# warm_start_result <title>: the check of warm_up, run by stack_ready once the project is up (DW-164). 0 when the last RESULT line of
# the after-start log is "RESULT OK ..." (or the log has no content at all, which only a stub gives: the health gate of the start
# already needs the install to end ready). Otherwise it prints "FAIL <title>: ..." naming that line, or saying there is none, and
# returns 1, which ends the up before any READY line.
warm_start_result() {
  local log line
  log=$(start_log)
  [ -n "$log" ] || return 0
  line=$(printf '%s\n' "$log" | grep '^RESULT ' | tail -n 1)
  case $line in
    "RESULT OK" | "RESULT OK "*) return 0 ;;
  esac
  echo "FAIL $1: the last RESULT line of the after-start log is: ${line:-(no RESULT line)}"
  return 1
}

warm_up() {
  local tag=$OCUTALON_RUN_TAG state started=$SECONDS held
  state=$(warm_state_dir "$tag")
  if [ -f "$state/project" ]; then
    held=$(cat "$state/project")
    if warm_running "$held"; then
      echo "WARM up: project $held is already up"
      return 0
    fi
    warm_down
  fi
  setup_tag
  warm_lock_install || exit 1
  stack_start warm
  WARM_STATE_DIR=$state
  trap 'live_cleanup; rm -rf "$WARM_STATE_DIR"' EXIT
  mkdir -p "$state" || exit 1
  cp "$tmp/decoy.env" "$state/decoy.env" || exit 1
  printf 'services:\n  iris:\n    env_file:\n      - %s\n' "$state/decoy.env" > "$state/decoy.yml"
  printf 'services:\n  iris:\n    volumes:\n      - ./src:/opt/ocutalon/warm-src:ro\n' > "$state/warm.yml"
  LIVE_FILES=("${LIVE_FILES[0]}" "$state/decoy.yml" "${LIVE_FILES[@]:2}" "$state/warm.yml")
  warm_manifest > "$state/manifest" || exit 1
  stack_ready warm "$started" warm_start_result
  printf '%s\n' "$root" > "$state/root"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$state/since"
  printf '%s\n' "${LIVE_FILES[@]}" > "$state/files"
  printf '%s\n' "$P" > "$state/project"
  trap - EXIT INT TERM HUP
  rm -rf "$tmp"
  echo "WARM up project $P tag $tag ready $((SECONDS - started))s"
}

# warm_down: removes every project of the tag and releases its warm lock (ci/iris.sh teardown), then the state. It needs no state.
warm_down() {
  cmd_teardown
  rm -rf "$(warm_state_dir "$OCUTALON_RUN_TAG")"
  echo "WARM down tag $OCUTALON_RUN_TAG"
}

warm_status() {
  local state held
  state=$(warm_state_dir "$OCUTALON_RUN_TAG")
  if [ -f "$state/project" ]; then
    held=$(cat "$state/project")
    if warm_running "$held"; then
      echo "WARM up project=$held tag=$OCUTALON_RUN_TAG since=$(cat "$state/since" 2>/dev/null)"
      return 0
    fi
  fi
  echo "WARM none for tag $OCUTALON_RUN_TAG"
  return 1
}

# --- a run on the warm stack ---

# warm_attach <title>: points P and LIVE_FILES at the warm stack of the tag, reloads the changed classes, and prints the STACK and
# READY lines of the run. Returns 1, saying why, when there is no stack, it was built from another checkout, it is not running, or
# the reload fails. It starts nothing and takes no lock.
warm_attach() {
  local title=$1 started=$SECONDS tag=${OCUTALON_RUN_TAG:-} state f
  state=$(warm_state_dir "$tag")
  if [ ! -f "$state/project" ]; then
    echo "FAIL WARM no warm stack for tag $tag: run ci/warm.sh up first"
    return 1
  fi
  if [ "$(cat "$state/root" 2>/dev/null)" != "$root" ]; then
    echo "FAIL WARM the warm stack of tag $tag was built from another checkout"
    return 1
  fi
  P=$(cat "$state/project")
  if ! warm_running "$P"; then
    echo "FAIL WARM the warm stack $P is not running: run ci/warm.sh down, then ci/warm.sh up"
    return 1
  fi
  LIVE_FILES=()
  while IFS= read -r f; do LIVE_FILES+=("$f"); done < "$state/files"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-warm-run.XXXXXX") || return 1
  trap 'rm -rf "$tmp"' EXIT
  echo "STACK $title: warm project $P"
  warm_reload || return 1
  echo "READY $title $((SECONDS - started))s (warm)"
}

# warm_script <compile flags>: the IRIS session that deletes the classes of $tmp/del, imports the files of
# $tmp/load and compiles the classes of $tmp/compile. Each list is one array line per item: d(n) a class, l(n) a file below the
# mounted tree, c(class) a class to compile. It prints a CHK line for each delete and import (|<class or file>|<1 when OK>|<error>), one
# for the compile (|<1 when OK>) and one for each compile error (|<the class of the list that the text names, or nothing>|<text>).
warm_script() {
  local i=0 class path
  while read -r class path; do
    i=$((i + 1))
    printf 'Set d(%d)="%s"\n' "$i" "$class"
  done < "$tmp/del"
  i=0
  while read -r class path; do
    i=$((i + 1))
    printf 'Set l(%d)="/opt/ocutalon/warm-src/%s"\n' "$i" "${path#src/}"
  done < "$tmp/load"
  while read -r class; do
    printf 'Set c("%s")=""\n' "$class"
  done < "$tmp/compile"
  printf '%s\n' \
    "Set q=\"$1\"" \
    'Set t=$Char(13,10,0,9)' \
    'Set k="" For { Set k=$Order(d(k),1,x) Quit:k=""  Set s=1 If ##class(%Dictionary.ClassDefinition).%ExistsId(x) { Set s=$SYSTEM.OBJ.Delete(x,"-d") } Write !,"CHK|delete|",x,"|",$SYSTEM.Status.IsOK(s),"|",$Select($SYSTEM.Status.IsOK(s):"",1:$Translate($SYSTEM.Status.GetErrorText(s),t,"    ")) }' \
    'Set k="" For { Set k=$Order(l(k),1,x) Quit:k=""  Set s=$SYSTEM.OBJ.Load(x,"-d") Write !,"CHK|import|",x,"|",$SYSTEM.Status.IsOK(s),"|",$Select($SYSTEM.Status.IsOK(s):"",1:$Translate($SYSTEM.Status.GetErrorText(s),t,"    ")) }' \
    'If $Data(c) { Set s=$SYSTEM.OBJ.Compile(.c,q) Write !,"CHK|compile|",$SYSTEM.Status.IsOK(s) If '"'"'$SYSTEM.Status.IsOK(s) { Kill er Do $SYSTEM.Status.DecomposeStatus(s,.er) Set k="" For { Set k=$Order(er(k),1,x) Quit:k=""  Set cl="",n="" For { Set n=$Order(c(n)) Quit:n=""  If x[n,$Length(n)>$Length(cl) { Set cl=n } } Write !,"CHK|error|",cl,"|",$Translate(x,t,"    ") } } }' \
    'Halt'
}

# warm_reload: brings the stack's classes in line with the tree, as the header says. Prints one "WARM reloaded <n>, deleted <m>" line,
# and "WARM compiled every class (<k>): <why>" when it compiled the whole tree. Returns 1, saying why, for a stale input, an import,
# delete or compile that failed, or a session that printed nothing. The failed marker is set before the session and removed only when
# the reload ends OK, so a reload that was interrupted counts as failed. Needs P, LIVE_FILES and tmp.
warm_reload() {
  local state kind hash path class out line what rest n=0 m=0 flags why="" total=0 bad=0 compile_seen=0 session_ok=1
  state=$(warm_state_dir "$OCUTALON_RUN_TAG")
  if ! warm_manifest > "$tmp/now" || [ ! -s "$tmp/now" ]; then
    echo "FAIL WARM the manifest of the tree could not be read"
    return 1
  fi
  if [ ! -s "$state/manifest" ]; then
    echo "FAIL WARM the stored manifest of tag $OCUTALON_RUN_TAG is missing: run ci/warm.sh down, then ci/warm.sh up"
    return 1
  fi
  warm_changes "$state/manifest" "$tmp/now" > "$tmp/changes"
  while read -r kind path; do
    if ! warm_is_class "$path"; then
      echo "FAIL WARM stale: $path changed since warm up, and only classes reload: run ci/warm.sh down, then ci/warm.sh up"
      return 1
    fi
  done < "$tmp/changes"
  : > "$tmp/del"
  : > "$tmp/load"
  while read -r kind path; do
    case $kind in
      D) printf '%s %s\n' "$(class_of "$path")" "$path" >> "$tmp/del" ;;
      *) printf '%s %s\n' "$(class_of "$path")" "$path" >> "$tmp/load" ;;
    esac
  done < "$tmp/changes"
  if [ -s "$tmp/del" ]; then why="after a delete"; elif [ -f "$state/failed" ]; then why="after a failed reload"; fi
  : > "$tmp/compile"
  if [ -n "$why" ]; then
    flags="c-d"
    while read -r hash path; do
      if warm_is_class "$path"; then class_of "$path" >> "$tmp/compile"; fi
    done < "$tmp/now"
    total=$(grep -c . "$tmp/compile")
  else
    flags="cb-d"
    while read -r class path; do printf '%s\n' "$class" >> "$tmp/compile"; done < "$tmp/load"
  fi
  if [ ! -s "$tmp/del" ] && [ ! -s "$tmp/load" ] && [ -z "$why" ]; then
    echo "WARM reloaded 0, deleted 0"
    return 0
  fi
  : > "$state/failed"
  out=$(warm_script "$flags" | iris_script OCUTALON)
  if [ -z "$out" ]; then
    echo "FAIL WARM the IRIS session of $P printed nothing"
    return 1
  fi
  : > "$tmp/updates"
  : > "$tmp/errors"
  while IFS= read -r line; do
    rest=${line#CHK|}
    kind=${rest%%|*}
    rest=${rest#*|}
    case $kind in
      delete | import)
        what=${rest%%|*}
        rest=${rest#*|}
        if [ "${rest%%|*}" = 1 ]; then
          if [ "$kind" = delete ]; then
            m=$((m + 1))
            printf 'drop %s\n' "$(awk -v c="$what" '$1 == c { print $2; exit }' "$tmp/del")" >> "$tmp/updates"
          else
            n=$((n + 1))
            printf 'set src/%s\n' "${what#/opt/ocutalon/warm-src/}" >> "$tmp/updates"
          fi
        else
          bad=1
          printf 'FAIL WARM %s: %s: %s\n' "$kind" "$what" "${rest#*|}" >> "$tmp/errors"
        fi
        ;;
      compile)
        compile_seen=1
        [ "${rest%%|*}" = 1 ] || session_ok=0
        ;;
      error)
        what=${rest%%|*}
        printf 'FAIL WARM compile: %s%s\n' "${what:+$what: }" "${rest#*|}" >> "$tmp/errors"
        ;;
    esac
  done <<EOT
$out
EOT
  if [ -s "$tmp/compile" ] && [ "$compile_seen" -eq 0 ]; then
    session_ok=0
    printf 'FAIL WARM compile: the IRIS session of %s did not report the compile\n' "$P" >> "$tmp/errors"
  fi
  if [ "$session_ok" -eq 0 ] && [ ! -s "$tmp/errors" ]; then
    printf 'FAIL WARM compile: the compile of %s failed and gave no error text\n' "$P" >> "$tmp/errors"
  fi
  if [ -s "$tmp/updates" ]; then
    warm_manifest_apply "$tmp/updates" "$state/manifest" "$tmp/now" > "$tmp/manifest.new" && cp "$tmp/manifest.new" "$state/manifest"
  fi
  echo "WARM reloaded $n, deleted $m"
  if [ -n "$why" ]; then echo "WARM compiled every class ($total): $why"; fi
  if [ "$bad" -eq 0 ] && [ "$session_ok" -eq 1 ] && [ ! -s "$tmp/errors" ]; then
    rm -f "$state/failed"
    return 0
  fi
  cat "$tmp/errors"
  return 1
}

# Sourced, this file defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

if [ -z "${OCUTALON_RUN_TAG:-}" ]; then
  echo "ci/warm.sh needs OCUTALON_RUN_TAG: the warm stack's tag"
  exit 2
fi
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/iris.sh"
case ${1:-} in
  up | down | status) ;;
  *)
    warm_usage
    exit 2
    ;;
esac
setup_tag
case $1 in
  up) warm_up ;;
  down) warm_down ;;
  status) warm_status ;;
esac
exit $?
