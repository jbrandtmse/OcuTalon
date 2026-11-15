#!/usr/bin/env bash
# Hermetic self-test of the release sequence (Story 11.5; release/release.sh and the candidate_branch, release_tags and next_rc helpers
# of release/lib-release.sh), with no container, no network call and no model. It needs bash, git, awk and tar.
#   bash docker/tests/test-release-sequence.sh [<rule>...]   runs the named rules (default: all)
#   bash docker/tests/test-release-sequence.sh --live        the one real build (IA3): the real npm and docker build of the cut and
#                                                            the image step; never in CI, and in its own call
#   bash docker/tests/test-release-sequence.sh --live ipm    the same, then the real ipm step (Story 11.17, IA1): IPM 0.10.10 in a
#                                                            throwaway build 154 container with no network; never in CI, in its own call,
#                                                            with the lane variables (OCUTALON_LOCK_DIR and OCUTALON_LOCK_OWNER)
#
# Every case builds a throwaway repository from `git archive HEAD` of the real tree (the paths that the scripts read, with the scripts
# of the working tree on top), one commit
# on the integration branch, with a local bare repository as its `origin`. Before anything runs it checks that no remote URL is a
# network URL. HOME, the git configuration, XDG_STATE_HOME and OCUTALON_RELEASE_STATE point into the test's temporary folder. The
# shims for npm, node and docker log every call, and the clock is the seam file. A planted OCUTALON_TEST_SECRET is in the environment of
# every run. The rules:
#   libs      candidate_branch, release_tags and next_rc
#   refusals  the first release, a tagged version, the kit, a bad start state: exit 2, one REFUSED line, nothing written
#   cut       the candidate is the integration head plus one cut commit; the integration branch and the checkout are unchanged; a
#             re-cut keeps rc1 and names the next number; --from with --pick cherry-picks; a bad pick or a conflict gives no branch
#   image     the image is built from the candidate's tree, its version is compared and the check image is removed; a lie, a missing
#             base image or a failed build stops the sequence before the push question
#   overview  (Story 14.1) the overview step runs release/security-overview.sh of the candidate (a stub in the seed repository, so no container is
#             needed): a pass names ipm, a failure stops the release with its record and never reaches ipm, a busy lane lock waits (exit 5);
#             (Story 11.20) the stub fails when an exported file is not readable by others (or a folder not searchable by others), a failing
#             unit's log is kept as overview-fail.log with its path on a LOG line after the FAIL line, and release.sh and lib-release.sh keep
#             their one umask 077 line
#   overviewunit  (Story 14.1) the real release/security-overview.sh in a temporary tree with a stub ci/iris.sh: pass, busy lock, a drift in
#             the live step, a failed class step, --write, the run tag, and the teardown that follows every case
#   overviewdrift (Story 14.1) docker/tests/lib-security-overview.sh on small overview files: the DRIFT line for a changed tool row, for a
#             change outside the rows, for the fix kinds and for the privileges, and nothing for equal files
#   overviewdoc   (Story 14.1, QA; Story 14.2; Story 22.6) the committed docs/security-overview.md: its title, its three marker pairs once each and in order,
#             ASCII only, no machine path, no URL or address; no hand-written placeholder; the privilege-limits paragraph word for word under its
#             heading; EXPERIENCE.md's kept-OCUORDERS sentence word for word; the numbers and the audit types of the code in their sections; the five
#             headings once each and in order, the no-scheduled-purge sentence and the demo section's closing sentence (QA); the MCP tools section
#             (Story 22.6): its opening sentence (MCP servers can be added on a local or IPM install), no can't-connect or "When a release adds MCP
#             support" sentence, a link to the worked example, the classification sentence
#             and the Read-only sentence word for word, and the time-limits paragraph as one whole line; the Data section without "this release can't
#             make"; no line with "deadline" outside the time-limits paragraph and no line about the changed-tool replay path (the checks run
#             whatever src holds); the worked example docs/mcp-jira-example.md (mcp_doc_problems): its title, ASCII and no machine path, every address
#             on example.com, the three shared texts word for word, the classification table's rows and the classification and governance lines word
#             for word (ovw_mcp_example_lines), no other "deadline" line, no replay-path and no source-poll text, the sentence that
#             says MCP is off on the online demo, the expiry sentence of the approval request (the hours of Bridge.Approval EXPIRYSECONDS, read from the
#             class source) and its link to the overview's MCP section; the overview's own demo-off sentence in its MCP tools section, the Data
#             section's MCP bullet, the MCP audit line and the Pairing, MCP and Tool sentence of its audit section, each word for word (VG3); and
#             the CI claims of the file and of the live unit in ci/units.sh (every group runs on the file, shards-5 holds the unit)
#   ipmcheck  (Story 15.4) the ipmcheck step runs release/ipm-install.sh of the candidate (a stub in the seed repository, so no container is needed)
#             on an export of the candidate's tree with the ipm step's artifact, the lane lock folder, a run tag and the job's deadline, and
#             tears down after it: a pass records "## FR-57 job" and names push; a failure (exit 1 or any code but 0 and 75) stops the release before
#             push with the unit's first FAIL line and no push question; a busy lock waits (exit 5, nothing recorded); the refusals come before any
#             run; an artifact over 5000000 bytes warns and fails nothing
#   push      only the candidate branch goes out, on the author's word; a no or the end of input pushes nothing and asks again
#   record    every stop writes the record section and commits only that path; the record question; a moved branch is reported
#   hands     the hands-on time is the sum of the ASK windows, over all candidates of the version, and warns over 15 minutes
#   resume    a stop continues at its step and never repeats a finished one; status changes nothing; two waiting states need a name
#   notes     the notes step runs release/notes.sh and its row carries what that script printed; the draft stays uncommitted
#   gate      the record is accepted by Story 11.2's harness, and its section stays byte for byte
#   secret    a full run prints, records and logs no value of the environment, calls no docker push or login, and the scan finds a
#             planted line
#   first     (QA) every first version but 1.0.0 is refused with nothing written
#   word      (QA) only the line yes proceeds; no option, variable or terminal answers in advance
#   pushes    (QA) exactly two pushes, each to the local bare remote and named; the checkout never switched; the draft never leaves
#   ipm       (Story 11.17) the ipm step packs the cut commit's tree in a throwaway container (docker shim): the artifact holds the bundle
#             byte for byte, the record's section and row, the status line, one run and two runs of the package, clean-up, no second run
#   ipmfail   every shim fault (a failed load, a failed second load in OCUTALON, a failed package, a stop after the copy-out, a dropped
#             bundle file, a changed byte, a wrong version, an empty repository, an instance that is not running, a failed start) fails
#             the step, writes its own section and deletes the file; the refusals (a tree that cannot be exported among them) come before
#             any container; a leftover under the recorded name goes and a bystander stays
#   ipmwait   a busy lane lock gives WAIT and exit 5 with nothing recorded and no container; the next call runs the step again
#   ipmnet    the step sends nothing out (no pull, push or login; a throwaway run has no network), and the scan of the scripts finds no
#             IPM publish form, repository URL or pull
#   ipmlib    the shared helpers: state folder, SHA-256, content digest (one value for two packagings), the artifact check
#   static    mode, ASCII, the main guard, the forbidden commands and push forms
# Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root" || exit 1

live=0
live_ipm=0
rules=""
for a in "$@"; do
  case $a in
    --live) live=1 ;;
    ipm)
      if [ "$live" -eq 1 ]; then live_ipm=1; else rules="$rules $a"; fi
      ;;
    *) rules="$rules $a" ;;
  esac
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-rseq.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P)
LIVE_TAG_PREFIX=ocutalon-release-check
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

export HOME=$tmp/home
export XDG_STATE_HOME=$tmp/xdg-state XDG_CONFIG_HOME=$tmp/xdg-config
export GIT_CONFIG_GLOBAL=$tmp/gitconfig GIT_CONFIG_NOSYSTEM=1
export OCUTALON_TEST_SECRET=zz-planted-value
unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN OCUTALON_RELEASE_NOW IRIS_IMAGE
mkdir -p "$HOME" "$tmp/bin"
git config -f "$GIT_CONFIG_GLOBAL" user.name "Release Test"
git config -f "$GIT_CONFIG_GLOBAL" user.email "release-test@example.invalid"
git config -f "$GIT_CONFIG_GLOBAL" init.defaultBranch main

INTEG=feature/OCT_OcuTalon_MVP
bad=0
fails_total=0
case_n=0
out=""
rc=0
RS_PATH=""

eq() { # eq <label> <got> <want>
  if [ "$2" != "$3" ]; then
    echo "  $1: got '$2', wanted '$3'"
    bad=1
  fi
}
has() { # has <label> <text> <part>
  case $2 in
    *"$3"*) ;;
    *)
      echo "  $1: the text lacks '$3'"
      bad=1
      ;;
  esac
}
lacks() { # lacks <label> <text> <part>
  case $2 in
    *"$3"*)
      echo "  $1: the text holds '$3'"
      bad=1
      ;;
  esac
}
rule() { # rule <name> <function>
  case " $rules " in
    "  ") ;;
    *" $1 "*) ;;
    *) return 0 ;;
  esac
  bad=0
  "$2"
  if [ "$bad" -eq 0 ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    fails_total=$((fails_total + 1))
  fi
}

# --- the shims ---

mkshims() {
  cat > "$tmp/bin/npm" << 'EOF'
#!/bin/sh
echo "npm $*" >> "$SHIMLOG/npm.log"
if [ -f "$SHIMFLAGS/npm-fail" ]; then
  echo "npm ERR! planted failure"
  exit 1
fi
case "$*" in
  *" ci"*) mkdir -p web/node_modules ;;
  *"run build"*)
    mkdir -p src/ocutalon/csp/assets
    echo '<html>fake bundle</html>' > src/ocutalon/csp/index.html
    echo 'fake' > src/ocutalon/csp/main-FAKE.js
    echo 'x' > src/ocutalon/csp/assets/a.txt
    ;;
esac
exit 0
EOF
  cat > "$tmp/bin/node" << 'EOF'
#!/bin/sh
echo "node $*" >> "$SHIMLOG/node.log"
case "$1" in
  --version) echo v24.15.0; exit 0 ;;
esac
exit 1
EOF
  cat > "$tmp/bin/docker" << 'EOF'
#!/bin/sh
echo "$*" >> "$SHIMLOG/docker.log"
img() { printf '%s' "$1" | tr '/:' '__'; }
case "$1" in
  image)
    [ -f "$SHIMFLAGS/no-base" ] && exit 1
    exit 0
    ;;
  build)
    shift
    tag=""
    ctx=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) tag=$2; shift 2 ;;
        -f | --build-arg) shift 2 ;;
        -q) shift ;;
        *) ctx=$1; shift ;;
      esac
    done
    [ -f "$SHIMFLAGS/build-fail" ] && { echo "planted build failure in $ctx/Dockerfile" >&2; exit 1; }
    if [ ! -f "$ctx/src/ocutalon/csp/index.html" ]; then
      echo "web bundle missing: run npm --prefix web run build" >&2
      exit 1
    fi
    ver=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$ctx/src/module.xml" | head -n 1)
    echo "build context-version=$ver bundle=yes" >> "$SHIMLOG/builds.log"
    [ -f "$SHIMFLAGS/lie" ] && ver=0.1.0
    mkdir -p "$SHIMSTATE"
    printf '%s\n' "$ver" > "$SHIMSTATE/$(img "$tag")"
    echo sha256:fake
    exit 0
    ;;
  run)
    shift
    if [ "$1" = "-d" ]; then
      shift
      name=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --name) name=$2; shift 2 ;;
          --pull | --network) shift 2 ;;
          *) break ;;
        esac
      done
      [ -n "$name" ] || { echo "no container name" >&2; exit 125; }
      [ -f "$SHIMFLAGS/ipm-run-fail" ] && { echo "planted run failure" >&2; exit 125; }
      [ -d "$SHIMSTATE/ct.$name" ] && { echo "the name is in use" >&2; exit 125; }
      mkdir -p "$SHIMSTATE/ct.$name/fs"
      echo fakecontainerid
      exit 0
    fi
    ep=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --rm) shift ;;
        --entrypoint) ep=$2; shift 2 ;;
        *) break ;;
      esac
    done
    tag=$1
    shift
    [ -f "$SHIMSTATE/$(img "$tag")" ] || exit 125
    case "$ep" in
      cat) cat "$SHIMSTATE/$(img "$tag")" ;;
      test)
        [ -f "$SHIMFLAGS/no-bundle" ] && exit 1
        exit 0
        ;;
      *) exit 1 ;;
    esac
    exit 0
    ;;
  rm)
    shift
    for t in "$@"; do
      case "$t" in -*) ;; *) rm -rf "${SHIMSTATE:?}/ct.$t" ;; esac
    done
    exit 0
    ;;
  cp)
    shift
    case "$1" in
      /*) # into the container: <host path> <name>:<path>
        c=${2%%:*}; p=${2#*:}; d="$SHIMSTATE/ct.$c"
        [ -d "$d" ] && [ -d "$(dirname "$d/fs$p")" ] || { echo "no such container path" >&2; exit 1; }
        cp -R "$1" "$d/fs$p"
        ;;
      *) # out of the container: <name>:<path> <host path>
        c=${1%%:*}; p=${1#*:}; d="$SHIMSTATE/ct.$c"
        [ -e "$d/fs$p" ] || { echo "no such file in the container" >&2; exit 1; }
        cp -R "$d/fs$p" "$2"
        # ipm-kill-after-copy: the packaging is stopped (TERM) right after its artifact was copied out
        [ ! -f "$SHIMFLAGS/ipm-kill-after-copy" ] || kill -TERM "$PPID"
        ;;
    esac
    exit 0
    ;;
  exec)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in -u) shift 2 ;; -i) shift ;; *) break ;; esac
    done
    c=$1
    shift
    d="$SHIMSTATE/ct.$c"
    [ -d "$d" ] || { echo "No such container: $c" >&2; exit 1; }
    case "$1" in
      mkdir)
        shift
        [ "$1" = -p ] && shift
        mkdir -p "$d/fs$1"
        exit 0
        ;;
      chmod) exit 0 ;;
      iris)
        case "$2" in
          qlist)
            if [ -f "$SHIMFLAGS/ipm-not-running" ]; then
              echo "IRIS^/usr/irissys^2026.3.0AI.154.0^down^x"
            else
              echo "IRIS^/usr/irissys^2026.3.0AI.154.0^running, since 2026-01-01^x"
            fi
            exit 0
            ;;
          session)
            ns=$5
            while IFS= read -r line; do
              case "$line" in
                *'OBJ.Load('*) if [ -f "$SHIMFLAGS/ipm-iris-load-fail" ]; then echo "IPMLOAD FAILED"; echo "ERROR #5001: planted IPM load failure"; else echo "IPMLOAD OK"; fi ;;
                'zpm "'*)
                  echo "$ns $line" >> "$SHIMLOG/zpm.log"
                  case "$line" in
                    'zpm "load '*)
                      dir=${line#zpm \"load -bypass-py-deps }
                      dir=${dir%\"}
                      if [ -f "$SHIMFLAGS/ipm-load-fail" ]; then
                        echo "ERROR! planted install failure"
                      elif [ "$ns" = OCUTALON ] && [ -f "$SHIMFLAGS/ipm-ocutalon-load-fail" ]; then
                        echo "ERROR! planted install failure in OCUTALON"
                      elif [ "$ns" != OCUTALON ] && { [ -f "$SHIMFLAGS/ipm-mapandstop" ] || [ -f "$SHIMFLAGS/ipm-ocutalon-load-fail" ] || grep -q MapAndStop "$d/fs$dir/module.xml"; }; then
                        echo 'ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.'
                        : > "$d/ns-OCUTALON"
                      else
                        printf '[%s|ocutalon]\tActivate SUCCESS\n' "$ns"
                        echo "$dir" > "$d/loaded-$ns"
                      fi
                      ;;
                    'zpm "package '*)
                      out=${line#*-path }
                      out=${out%\"}
                      src=$(cat "$d/loaded-$ns" 2> /dev/null)
                      if [ -z "$src" ]; then
                        echo "ERROR! ocutalon is not installed in $ns"
                      elif [ -f "$SHIMFLAGS/ipm-package-fail" ]; then
                        echo "ERROR! planted package failure"
                      else
                        rm -rf "$d/pk"
                        mkdir -p "$d/pk"
                        # IPM packs the module, not the folder it was loaded from
                        cp -R "$d/fs$src/module.xml" "$d/fs$src/src" "$d/pk/"
                        [ -f "$SHIMFLAGS/ipm-drop-csp" ] && rm -f "$d/pk/src/ocutalon/csp/main-FAKE.js"
                        [ -f "$SHIMFLAGS/ipm-byte" ] && echo x >> "$d/pk/src/ocutalon/csp/main-FAKE.js"
                        if [ -f "$SHIMFLAGS/ipm-version" ]; then
                          sed 's:<Version>[^<]*</Version>:<Version>9.9.9</Version>:' "$d/pk/module.xml" > "$d/pk/module.xml.new"
                          mv "$d/pk/module.xml.new" "$d/pk/module.xml"
                        fi
                        tar -czf "$d/fs$out.tgz" -C "$d/pk" .
                        echo "Package written to $out.tgz"
                      fi
                      ;;
                    'zpm "repo '*'-list-modules'*)
                      if [ ! -f "$SHIMFLAGS/ipm-empty-repo" ]; then
                        rp=$(cat "$d/repopath" 2> /dev/null)
                        for m in "$d/fs$rp"*/module.xml; do
                          [ -f "$m" ] || continue
                          mv_=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$m" | head -n 1)
                          md=${m%module.xml}
                          printf 'ocutalon %s @ %s\n' "$mv_" "${md#"$d/fs"}"
                        done
                      fi
                      ;;
                    'zpm "repo '*)
                      rp=${line#*-path }
                      rp=${rp%\"}
                      echo "$rp" > "$d/repopath"
                      ;;
                  esac
                  ;;
                *Config.Namespaces*)
                  if [ -f "$d/ns-OCUTALON" ]; then echo "NSCHECK 1"; else echo "NSCHECK 0"; fi
                  ;;
              esac
            done
            echo "$ns>"
            exit 0
            ;;
        esac
        ;;
    esac
    echo "unexpected docker exec" >&2
    exit 1
    ;;
  rmi)
    shift
    [ -f "$SHIMFLAGS/rmi-fail" ] && exit 1
    for t in "$@"; do
      case "$t" in -*) ;; *) rm -f "$SHIMSTATE/$(img "$t")" ;; esac
    done
    exit 0
    ;;
esac
echo "unexpected docker call" >&2
exit 1
EOF
  chmod 755 "$tmp/bin/npm" "$tmp/bin/node" "$tmp/bin/docker"
  mkdir -p "$tmp/netmarks"
  for n in curl wget gh ssh nc; do
    printf '#!/bin/sh\n: > "%s/netmarks/%s"\nexit 1\n' "$tmp" "$n" > "$tmp/bin/$n"
    chmod 755 "$tmp/bin/$n"
  done
}

# leanpath <tool>: a PATH of the essential commands and the shims, without the named tool.
leanpath() {
  local d=$tmp/lean.$1 t p
  rm -rf "$d"
  mkdir -p "$d"
  for t in bash sh git awk sed grep cat date head tail tr cut wc sort tar mv rm mkdir basename dirname ls cp chmod find sleep readlink; do
    [ "$t" != "$1" ] || continue
    p=$(command -v "$t" 2> /dev/null)
    case $p in
      /*) ln -s "$p" "$d/$t" ;;
    esac
  done
  for t in npm node docker; do
    [ "$t" != "$1" ] || continue
    ln -s "$tmp/bin/$t" "$d/$t"
  done
  printf '%s\n' "$d"
}

# --- the throwaway repository ---

# stub_text <pass|fail|busy|silent|nolog|quiet>: the text of a stub release/security-overview.sh, the callable unit of the overview step, which prints what the real
# unit prints for that outcome and exits as it does. It makes no call outside its own folder, except that pass and fail use the marker files in
# $SHIMLOG, and nolog, a unit that leaves the step no log, removes that log from the release state folder.
stub_text() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u'
  case $1 in
    pass)
      printf '%s\n' 'bad=$(find . -path ./web/node_modules -prune -o \( ! -perm -004 -o \( -type d ! -perm -001 \) \) -print | head -n 1)' \
        '[ -z "$bad" ] || { echo "FAIL overview $bad is not readable by others"; exit 1; }' \
        'grep -q "<Version>1.0.0</Version>" src/module.xml || { echo "FAIL overview the unit did not run in the cut candidate"; exit 1; }' \
        '[ -d web/node_modules ] || { echo "FAIL overview the web dependencies would be installed"; exit 1; }' \
        '[ -z "${SHIMLOG:-}" ] || echo "${OCUTALON_LOCK_DIR:-}" > "$SHIMLOG/overview-lock-dir.txt"' \
        '[ -z "${SHIMLOG:-}" ] || umask > "$SHIMLOG/overview-umask.txt"' \
        'echo "PASS overview stub: sections equal and tests pass"' 'exit 0'
      ;;
    fail)
      printf '%s\n' '[ -z "${SHIMLOG:-}" ] || [ ! -f "$SHIMLOG/overview-pass" ] || { echo "PASS overview stub: sections equal and tests pass"; exit 0; }' \
        '[ -z "${SHIMLOG:-}" ] || [ ! -f "$SHIMLOG/overview-busy" ] || { echo "WAIT overview the lane lock is busy"; exit 75; }' \
        'echo "DRIFT tool recent_activity"' 'echo "FAIL the generated sections of docs/security-overview.md differ from a fresh generation"' \
        'echo "FAIL overview DRIFT tool recent_activity"' 'exit 1'
      ;;
    busy)
      printf '%s\n' 'echo "LOCK busy: throwaway-iris is held by someone"' 'echo "WAIT overview the lane lock is busy"' 'exit 75'
      ;;
    silent)
      printf '%s\n' 'echo "FAIL overview a step ended with exit 3"' 'exit 1'
      ;;
    nolog)
      printf '%s\n' 'rm -f "$OCUTALON_RELEASE_STATE"/*/overview.log' 'exit 1'
      ;;
    quiet)
      printf '%s\n' 'echo "some output that is not a DRIFT or FAIL line"' 'exit 2'
      ;;
  esac
}

# ipm_stub_text <pass|fail|busy|silent>: the text of a stub release/ipm-install.sh, the unit of the ipmcheck step, which prints what the real unit
# prints for that outcome and exits as it does. It makes no call outside its own folder; the pass notes what it received.
ipm_stub_text() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u'
  case $1 in
    pass)
      printf '%s\n' 'grep -q "<Version>1.0.0</Version>" src/module.xml || { echo "FAIL the unit did not run in the cut candidate"; exit 1; }' \
        '[ -d web/node_modules ] || { echo "FAIL the web dependencies would be installed"; exit 1; }' \
        '[ -f "${OCUTALON_IPM_ARTIFACT:-}" ] || { echo "FAIL the artifact is not a file"; exit 1; }' \
        '[ -z "${SHIMLOG:-}" ] || { echo "artifact=$OCUTALON_IPM_ARTIFACT"; echo "lock=${OCUTALON_LOCK_DIR:-}"; echo "tag=${OCUTALON_RUN_TAG:-}"; echo "deadline=${OCUTALON_LIVE_DEADLINE:-}"; echo "args=$*"; } > "$SHIMLOG/ipmcheck-env.txt"' \
        'echo "PASS part p uninstall: stub"' 'echo "ipm-install: all checks passed"' 'exit 0'
      ;;
    fail)
      printf '%s\n' 'echo "PASS part p: stub"' 'echo "FAIL part p uninstall: USER'"'"'s repository definitions differ, or there are none (differs, or 0 nodes)"' \
        'echo "FAIL part p: a second failure"' 'echo "ipm-install: 2 check(s) failed (project stub)"' 'exit 1'
      ;;
    busy)
      printf '%s\n' 'echo "LOCK busy: throwaway-iris is held by someone"' 'exit 75'
      ;;
    silent)
      printf '%s\n' 'echo "no FAIL line here"' 'exit 3'
      ;;
  esac
}

# set_ipm_stub <pass|fail|busy|silent>: replaces the stub unit of the ipmcheck step in the case's checkout, commits it on the integration branch
# and pushes it, before start.
set_ipm_stub() {
  ipm_stub_text "$1" > "$W/release/ipm-install.sh"
  git -C "$W" add release/ipm-install.sh
  git -C "$W" commit -q -m "ipm stub $1"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
}

# set_stub <pass|fail|busy|silent|nolog|quiet>: replaces the stub in the case's checkout, commits it on the integration branch and pushes it, before start.
set_stub() {
  stub_text "$1" > "$W/release/security-overview.sh"
  git -C "$W" add release/security-overview.sh
  git -C "$W" commit -q -m "stub $1"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
}

mkseed() {
  local s=$tmp/seed m
  mkdir -p "$s"
  if [ "$live" -eq 1 ]; then
    git -C "$root" archive HEAD | tar -x -C "$s" || exit 1
  else
    # Only what the sequence, the notes script and the harness read: the whole tree adds time and no case.
    git -C "$root" archive HEAD release ci docker/tests Dockerfile docker/ipm .gitignore .dockerignore module.xml src/module.xml README.md \
      web/package.json web/package-lock.json _bmad-output/implementation-artifacts/sprint-status.yaml \
      _bmad-output/planning-artifacts/epics.md | tar -x -C "$s" || exit 1
  fi
  # The real tree's records are its own history; every case starts with none and writes its own.
  rm -rf "$s/release/records"
  cp -p "$root/release/release.sh" "$root/release/lib-release.sh" "$s/release/"
  # The fixture's own version, whatever the real tree reads: a candidate's tree is at the release's version, and the rules cut from 0.1.0.
  for m in module.xml src/module.xml; do
    sed 's:<Version>[^<]*</Version>:<Version>0.1.0</Version>:' "$s/$m" > "$s/$m.new" && mv "$s/$m.new" "$s/$m"
  done
  # The overview step runs release/security-overview.sh of the candidate; the seed holds a stub that passes, so that no case needs a container.
  stub_text pass > "$s/release/security-overview.sh"
  chmod 755 "$s/release/security-overview.sh"
  # The ipmcheck step runs release/ipm-install.sh of the candidate and then ci/iris.sh teardown; the seed holds a passing stub unit and a stub
  # ci/iris.sh that only logs its call when run (sourced, it is the real one: the upgrade harness sources it), so that no case needs a container (the live run stops after the ipm step and keeps the real files).
  if [ "$live" -eq 0 ]; then
    ipm_stub_text pass > "$s/release/ipm-install.sh"
    chmod 755 "$s/release/ipm-install.sh"
    mv "$s/ci/iris.sh" "$s/ci/iris-real.sh"
    printf '%s\n' '#!/usr/bin/env bash' \
      'if [ "${BASH_SOURCE[0]}" != "$0" ]; then . "$(dirname "${BASH_SOURCE[0]}")/iris-real.sh"; return 0; fi' \
      '[ -z "${SHIMLOG:-}" ] || echo "$* tag=${OCUTALON_RUN_TAG:-}" >> "$SHIMLOG/iris-calls.txt"' 'exit 0' > "$s/ci/iris.sh"
    chmod 755 "$s/ci/iris.sh"
  fi
  git init -q -b "$INTEG" "$s" || exit 1
  git -C "$s" add -A
  git -C "$s" commit -q -m seed
}

# net_check <repository>: returns 1, saying so, when a remote of the repository is not a local path inside the test's folder.
net_check() {
  local url bad_url=0
  for url in $(git -C "$1" remote -v | awk '{ print $2 }' | sort -u); do
    case $url in
      "$tmp"/*) ;;
      *) bad_url=1 ;;
    esac
  done
  if [ "$bad_url" -eq 1 ]; then
    echo "FAIL a remote of the throwaway is not a local path: stopping"
    return 1
  fi
  return 0
}

newcase() {
  case_n=$((case_n + 1))
  C=$tmp/c$case_n
  W=$C/w
  R=$C/r.git
  mkdir -p "$C/flags" "$C/shim" "$C/shimstate" "$C/locks"
  git clone -q --bare "$tmp/seed" "$R" || exit 1
  git clone -q "$R" "$W" || exit 1
  net_check "$W" || exit 1
  export OCUTALON_RELEASE_STATE=$C/state
  export SHIMLOG=$C/shim SHIMFLAGS=$C/flags SHIMSTATE=$C/shimstate
  unset OCUTALON_RELEASE_NOW OCUTALON_LOCK_WAIT OCUTALON_RELEASE_IPM_WAIT
  if [ "$live" -eq 0 ]; then export OCUTALON_LOCK_DIR=$C/locks; fi
  RS_PATH=""
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
}

flag() { : > "$C/flags/$1"; }
unflag() { rm -f "$C/flags/$1"; }

clockfile() { # clockfile <seconds>...: the seam clock for the next runs
  printf '%s\n' "$@" > "$C/now"
  export OCUTALON_RELEASE_NOW=$C/now
}

# rs <answers> <args>...: runs release.sh in the case's checkout, with the answers on standard input; sets out and rc.
rs() {
  local ans=$1
  shift
  out=$(cd "$W" && printf '%s' "$ans" | PATH="${RS_PATH:-$PATH}" "$BASH" release/release.sh "$@" 2>&1)
  rc=$?
  printf '%s\n' "$out" >> "$tmp/alloutput"
  if [ -n "${RSEQ_DEBUG:-}" ]; then
    printf '>> release.sh %s (exit %s)\n%s\n' "$*" "$rc" "$out" >&2
  fi
}

Y=$'yes\n'
N=$'no\n'

# snap: the state of a case that a refusal must not change.
snap() {
  printf '%s|%s|%s|%s|%s\n' "$(find "$OCUTALON_RELEASE_STATE" -mindepth 1 2> /dev/null | wc -l | tr -d ' ')" \
    "$(git -C "$W" for-each-ref --format='%(objectname) %(refname)')" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')" \
    "$(git -C "$W" status --porcelain)" "$(git -C "$W" rev-parse HEAD)"
}

rec_file() { printf '%s\n' "$W/release/records/1.0.0/rc${1:-1}.md"; }
cand() { git -C "$W" rev-parse --verify --quiet "refs/heads/release/1.0.0-rc${1:-1}" 2> /dev/null; }
rhead() { git --git-dir="$R" rev-parse "refs/heads/$INTEG"; }

# to_step <step>: runs the successful steps up to it (the kit and the push answered yes, the record question answered no).
to_step() {
  rs "$Y" start --version 1.0.0
  case $1 in cut) return 0 ;; esac
  rs '' next
  case $1 in image) return 0 ;; esac
  rs '' next
  case $1 in overview) return 0 ;; esac
  rs '' next
  case $1 in ipm) return 0 ;; esac
  rs '' next
  case $1 in ipmcheck) return 0 ;; esac
  rs '' next
  case $1 in push) return 0 ;; esac
  rs "$Y" next
}

# --- libs ---

t_libs() {
  newcase
  cd "$W" || return
  . "$W/release/lib-release.sh"
  eq "candidate_branch" "$(candidate_branch 1.0.0 3)" "release/1.0.0-rc3"
  eq "next_rc with no candidate" "$(next_rc 1.0.0 origin)" "1"
  git branch release/1.0.0-rc2
  eq "next_rc counts a local branch" "$(next_rc 1.0.0 origin)" "3"
  git push -q origin release/1.0.0-rc2:refs/heads/release/1.0.0-rc7
  eq "next_rc counts a remote branch" "$(next_rc 1.0.0 origin)" "8"
  git branch release/1.0.1-rc9
  eq "next_rc keeps the versions apart" "$(next_rc 1.0.0 origin)" "8"
  eq "next_rc of another version" "$(next_rc 1.0.1 origin)" "10"
  eq "next_rc keeps 1.0.0 apart from 1.0.00" "$(next_rc 1.0.00 origin)" "1"
  git branch release/1.0.2-rc08
  eq "next_rc reads a zero-padded number as decimal" "$(next_rc 1.0.2 origin)" "9"
  eq "release_tags with no tag" "$(release_tags origin)" ""
  git tag v1.0.0
  git tag lightweight-not-a-release
  git --git-dir="$R" tag v1.1.0 "$(git --git-dir="$R" rev-parse HEAD)"
  git tag -a v0.9.0 -m annotated
  git push -q origin v0.9.0
  eq "release_tags joins local and remote, once each" "$(release_tags origin | tr '\n' ' ')" "v0.9.0 v1.0.0 v1.1.0 "
  eq "release_tags of the local repository alone" "$(release_tags | tr '\n' ' ')" "v0.9.0 v1.0.0 "
  release_tags "$tmp/does-not-exist" > /dev/null
  eq "release_tags with an unreachable remote returns 1" "$?" "1"
  cd "$root" || return
}

# --- refusals ---

t_refusals() {
  local before t
  newcase
  before=$(snap)
  rs '' start --version 1.1.0
  eq "1.1.0: exit" "$rc" 2
  eq "1.1.0: the line" "$out" "REFUSED the first release is 1.0.0"
  eq "1.1.0: nothing written" "$(snap)" "$before"
  rs '' start --version 0.1.0
  eq "0.1.0: exit" "$rc" 2
  has "0.1.0: the line" "$out" "REFUSED the first release is 1.0.0"
  eq "0.1.0: nothing written" "$(snap)" "$before"
  rs '' start --version 1.0
  eq "a version that is not x.y.z: exit" "$rc" 2
  has "a version that is not x.y.z" "$out" "REFUSED --version must be x.y.z"
  rs '' start
  has "no version" "$out" "REFUSED --version <x.y.z> is required"
  rs '' start --version 1.0.0 --bogus
  has "an unknown option" "$out" "REFUSED unknown option '--bogus'"
  rs '' start --version 1.0.0 --pick abc
  has "a pick without a source" "$out" "REFUSED --pick needs --from"
  rs '' start --pick --version 1.0.0
  has "a pick with no commit" "$out" "REFUSED --pick needs a commit"
  rs '' start --version 1.0.0 --rc
  has "an option with no value" "$out" "REFUSED --rc needs a value"
  eq "the options: nothing written" "$(snap)" "$before"
  # a tag on the remote only, then on the checkout only
  git --git-dir="$R" tag v1.0.0 "$(rhead)"
  before=$(snap)
  rs "$Y" start --version 1.0.0
  eq "tagged on the remote: exit" "$rc" 2
  eq "tagged on the remote: the line" "$out" "REFUSED v1.0.0 is already tagged"
  eq "tagged on the remote: nothing written" "$(snap)" "$before"
  newcase
  git -C "$W" tag v1.0.0
  before=$(snap)
  rs "$Y" start --version 1.0.0
  eq "tagged locally: exit" "$rc" 2
  eq "tagged locally: the line" "$out" "REFUSED v1.0.0 is already tagged"
  eq "tagged locally: nothing written" "$(snap)" "$before"
  # the kit
  newcase
  before=$(snap)
  rs "$N" start --version 1.0.0
  eq "kit no: exit" "$rc" 2
  has "kit no: the question" "$out" "ASK kit "
  has "kit no: the line" "$out" "REFUSED the author did not confirm the 1.0.0 kit"
  eq "kit no: nothing written" "$(snap)" "$before"
  rs 'maybe' start --version 1.0.0
  eq "kit with another word: exit" "$rc" 2
  rs '' start --version 1.0.0
  eq "kit at the end of input: exit" "$rc" 2
  has "kit at the end of input: the line" "$out" "REFUSED the author did not confirm the 1.0.0 kit"
  eq "kit at the end of input: nothing written" "$(snap)" "$before"
  # the start state
  newcase
  echo changed >> "$W/README.md"
  before=$(snap)
  rs "$Y" start --version 1.0.0
  eq "a tracked change: exit" "$rc" 2
  has "a tracked change: the line" "$out" "REFUSED the checkout has changes outside release/records/: 1 path(s)"
  lacks "a tracked change: no question" "$out" "ASK "
  eq "a tracked change: nothing written" "$(snap)" "$before"
  git -C "$W" checkout -q -- README.md
  echo x > "$W/stray.txt"
  before=$(snap)
  rs "$Y" start --version 1.0.0
  has "an untracked file outside the records" "$out" "outside release/records/: 1 path(s)"
  eq "an untracked file: nothing written" "$(snap)" "$before"
  rm -f "$W/stray.txt"
  git -C "$W" checkout -q -b other
  before=$(snap)
  rs "$Y" start --version 1.0.0
  eq "off the integration branch: exit" "$rc" 2
  has "off the integration branch" "$out" "REFUSED the checkout is not on $INTEG"
  eq "off the integration branch: nothing written" "$(snap)" "$before"
  git -C "$W" checkout -q "$INTEG"
  git -C "$W" commit -q --allow-empty -m local
  before=$(snap)
  rs "$Y" start --version 1.0.0
  eq "a local commit: exit" "$rc" 2
  has "a local commit" "$out" "REFUSED $INTEG differs from origin/$INTEG"
  eq "a local commit: nothing written" "$(snap)" "$before"
  git -C "$W" push -q origin "$INTEG"
  rs "$Y" start --version 1.0.0 --rc 3
  eq "--rc not the next: exit" "$rc" 2
  has "--rc not the next" "$out" "REFUSED --rc 3 is not the next number; the next is rc1"
  for t in main master release/1.0.0-rc1 rehearsal/1.0.0-rc1 refs/heads/x; do
    rs "$Y" start --version 1.0.0 --integration "$t"
    eq "--integration $t: exit" "$rc" 2
    eq "--integration $t: the line" "$out" "REFUSED --integration $t is not an integration branch"
  done
  eq "the integration names: nothing written" "$(find "$OCUTALON_RELEASE_STATE" -mindepth 1 2> /dev/null | wc -l | tr -d ' ')" 0
  rs "$Y" start --version 1.0.0 --integration nope
  has "an integration branch that is not checked out" "$out" "REFUSED the checkout is not on nope"
  rs "$Y" start --version 1.0.0 --remote nowhere
  has "an unknown remote" "$out" "REFUSED no remote named nowhere"
  for t in git node npm docker; do
    RS_PATH=$(leanpath "$t")
    rs "$Y" start --version 1.0.0
    eq "$t missing: exit" "$rc" 2
    eq "$t missing: the line" "$out" "REFUSED $t is not installed"
    eq "$t missing: nothing written" "$(find "$OCUTALON_RELEASE_STATE" -mindepth 1 2> /dev/null | wc -l | tr -d ' ')" 0
  done
  RS_PATH=""
  # a first release, right version: state, NEXT cut, no branch and no record
  newcase
  mkdir -p "$W/release/records/1.0.0"
  echo "an earlier draft" > "$W/release/records/1.0.0/rc9-notes.md"
  rs "$Y" start --version 1.0.0
  eq "start: exit" "$rc" 0
  has "start: the kit question" "$out" "ASK kit "
  has "start: the next step" "$out" "NEXT cut"
  [ -f "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" ] || {
    echo "  start: no state"
    bad=1
  }
  eq "start: no candidate branch" "$(cand)" ""
  eq "start: no record" "$(ls "$W/release/records/1.0.0")" "rc9-notes.md"
  eq "start: the remote is unchanged" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | tr '\n' ' ')" "refs/heads/$INTEG "
}

# --- cut ---

t_cut() {
  local c integ_ver integ_root sha
  newcase
  integ_ver=$(git -C "$W" show "HEAD:src/module.xml")
  integ_root=$(git -C "$W" show "HEAD:module.xml")
  to_step cut
  rs '' next
  eq "cut: exit" "$rc" 0
  has "cut: the line" "$out" "PASS cut "
  has "cut: the next step" "$out" "NEXT image"
  c=$(cand)
  [ -n "$c" ] || {
    echo "  cut: no candidate branch"
    bad=1
  }
  has "cut: the line names the full sha" "$out" "PASS cut $c"
  eq "cut: one commit on the integration head" "$(git -C "$W" rev-list --count "$INTEG..release/1.0.0-rc1")" 1
  eq "cut: its parent is the integration head" "$(git -C "$W" rev-parse "release/1.0.0-rc1^")" "$EXPECT_BASE"
  eq "cut: the candidate's version" "$(git -C "$W" show release/1.0.0-rc1:src/module.xml | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -n 1)" 1.0.0
  eq "cut: only the first <Version> changed" "$(git -C "$W" diff --numstat "$INTEG" release/1.0.0-rc1 -- src/module.xml | awk '{ print $1 "/" $2 }')" "1/1"
  eq "cut: the candidate's root version" "$(git -C "$W" show release/1.0.0-rc1:module.xml | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -n 1)" 1.0.0
  eq "cut: only the first <Version> of the root manifest changed" "$(git -C "$W" diff --numstat "$INTEG" release/1.0.0-rc1 -- module.xml | awk '{ print $1 "/" $2 }')" "1/1"
  eq "cut: the integration branch's module.xml" "$(git -C "$W" show "$INTEG:src/module.xml")" "$integ_ver"
  eq "cut: the integration branch's root module.xml" "$(git -C "$W" show "$INTEG:module.xml")" "$integ_root"
  eq "cut: the integration branch has not moved" "$(git -C "$W" rev-parse "$INTEG")" "$EXPECT_BASE"
  eq "cut: the bundle's index.html is committed" "$(git -C "$W" ls-tree --name-only release/1.0.0-rc1 src/ocutalon/csp/index.html)" "src/ocutalon/csp/index.html"
  eq "cut: the rest of the bundle is committed" "$(git -C "$W" ls-tree -r --name-only release/1.0.0-rc1 -- src/ocutalon/csp | tr '\n' ' ')" "src/ocutalon/csp/assets/a.txt src/ocutalon/csp/index.html src/ocutalon/csp/main-FAKE.js "
  eq "cut: the author's checkout is still on the integration branch" "$(git -C "$W" symbolic-ref --short HEAD)" "$INTEG"
  eq "cut: the author's checkout is clean" "$(git -C "$W" status --porcelain)" ""
  eq "cut: the checkout has no bundle" "$([ -e "$W/src/ocutalon/csp" ] && echo yes || echo no)" no
  eq "cut: the checkout's module.xml" "$(cat "$W/src/module.xml")" "$integ_ver"
  eq "cut: the checkout's root module.xml" "$(cat "$W/module.xml")" "$integ_root"
  eq "cut: the remote has no candidate yet" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | tr '\n' ' ')" "refs/heads/$INTEG "
  eq "cut: npm ci and build ran once each" "$(wc -l < "$SHIMLOG/npm.log" | tr -d ' ')" 2
  has "cut: npm ci" "$(cat "$SHIMLOG/npm.log")" "--prefix web ci"
  has "cut: npm build" "$(cat "$SHIMLOG/npm.log")" "--prefix web run build"
  eq "cut: no record yet" "$([ -e "$(rec_file)" ] && echo yes || echo no)" no
  # a failed build gives no branch, a FAIL line, a stop and exit 1
  newcase
  flag npm-fail
  to_step cut
  rs "$N" next
  eq "failed build: exit" "$rc" 1
  has "failed build: the line" "$out" "FAIL cut "
  has "failed build: the stop" "$out" "RESULT fail"
  eq "failed build: no candidate branch" "$(cand)" ""
  has "failed build: the record" "$(cat "$(rec_file)")" "Result: failed at cut: "
  unflag npm-fail
  rs '' next
  eq "retry of the cut: exit" "$rc" 0
  has "retry of the cut" "$out" "PASS cut "
  # the two manifests read different versions: no branch, a FAIL line, a stop and exit 1
  newcase
  sed 's:<Version>[^<]*</Version>:<Version>0.1.1</Version>:' "$W/module.xml" > "$W/module.xml.new"
  mv "$W/module.xml.new" "$W/module.xml"
  git -C "$W" commit -q -am "the root manifest alone moves"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
  to_step cut
  rs "$N" next
  eq "two versions: exit" "$rc" 1
  has "two versions: the line" "$out" "FAIL cut module.xml and src/module.xml hold different versions"
  eq "two versions: no candidate branch" "$(cand)" ""
  # a tree with no root manifest is the same failure
  newcase
  git -C "$W" rm -q module.xml
  git -C "$W" commit -q -m "no root manifest"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
  to_step cut
  rs "$N" next
  eq "no root manifest: exit" "$rc" 1
  has "no root manifest: the line" "$out" "FAIL cut module.xml and src/module.xml hold different versions"
  eq "no root manifest: no candidate branch" "$(cand)" ""
  # no <Version> in either: nothing to set
  newcase
  grep -v '<Version>' "$W/module.xml" > "$W/module.xml.new"
  mv "$W/module.xml.new" "$W/module.xml"
  grep -v '<Version>' "$W/src/module.xml" > "$W/src/module.xml.new"
  mv "$W/src/module.xml.new" "$W/src/module.xml"
  git -C "$W" commit -q -am "no version"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
  to_step cut
  rs "$N" next
  eq "no version: exit" "$rc" 1
  has "no version: the line" "$out" "FAIL cut module.xml has no <Version> to set"
  eq "no version: no candidate branch" "$(cand)" ""
  # a re-cut from the integration head; rc1 stays
  newcase
  to_step cut
  rs '' next
  c=$(cand)
  rs "$Y" start --version 1.0.0
  eq "second start: exit" "$rc" 0
  has "second start: rc2" "$out" "START 1.0.0 rc2 "
  rs '' next --version 1.0.0 --rc 2
  eq "second cut: exit" "$rc" 0
  eq "rc1 is unchanged" "$(cand 1)" "$c"
  eq "rc2 is on the integration head" "$(git -C "$W" rev-parse release/1.0.0-rc2^)" "$EXPECT_BASE"
  eq "rc2 is its own commit" "$(git -C "$W" rev-list --count "$INTEG..release/1.0.0-rc2")" 1
  [ "$(cand 2)" != "$c" ] || {
    echo "  rc2 equals rc1"
    bad=1
  }
  rs "$N" start --version 1.0.0 --rc 2
  has "rc2 again: refused" "$out" "REFUSED --rc 2 is not the next number; the next is rc3"
  # rc1 on the remote only still counts
  newcase
  to_step cut
  rs '' next
  c=$(cand)
  git -C "$W" push -q origin release/1.0.0-rc1
  git -C "$W" branch -q -D release/1.0.0-rc1
  rm -rf "$OCUTALON_RELEASE_STATE"
  rs "$Y" start --version 1.0.0
  has "rc1 only on the remote: the next is rc2" "$out" "START 1.0.0 rc2 "
  eq "rc1 on the remote is unchanged" "$(git --git-dir="$R" rev-parse refs/heads/release/1.0.0-rc1)" "$c"
  # a name taken after the start is refused at the cut and left alone
  newcase
  rs "$Y" start --version 1.0.0
  git -C "$W" branch release/1.0.0-rc1 "$EXPECT_BASE"
  rs '' next
  eq "a taken name: exit" "$rc" 1
  has "a taken name: the line" "$out" "FAIL cut release/1.0.0-rc1 already exists"
  eq "a taken name is unchanged" "$(cand)" "$EXPECT_BASE"
  # a later release: tags exist, the version is not 1.0.0, and no kit question is asked
  newcase
  git --git-dir="$R" tag v1.0.0 "$EXPECT_BASE"
  rs '' start --version 1.0.1
  eq "a later release: exit" "$rc" 0
  lacks "a later release: no kit question" "$out" "ASK kit"
  has "a later release: the next step" "$out" "NEXT cut"
}

# fixes_case: a case with rc1 pushed, and fix commits on the integration branch (pushed): sets FIX1, FIX2, RC1
fixes_case() {
  newcase
  to_step cut
  rs '' next
  RC1=$(cand 1)
  echo "fix one" > "$W/fix-one.txt"
  git -C "$W" add fix-one.txt
  git -C "$W" commit -q -m "fix one"
  FIX1=$(git -C "$W" rev-parse HEAD)
  echo "fix two" > "$W/fix-two.txt"
  git -C "$W" add fix-two.txt
  git -C "$W" commit -q -m "fix two"
  FIX2=$(git -C "$W" rev-parse HEAD)
  git -C "$W" push -q origin "$INTEG"
  FIXHEAD=$FIX2
}

t_recut() {
  local c2
  fixes_case
  rs "$Y" start --version 1.0.0 --from release/1.0.0-rc1 --pick "$FIX1" "$FIX2"
  eq "start with picks: exit" "$rc" 0
  has "start with picks: rc2" "$out" "START 1.0.0 rc2 "
  rs '' next --version 1.0.0 --rc 2
  eq "cut with picks: exit" "$rc" 0
  c2=$(cand 2)
  eq "rc2: the cut commit's parent is the second pick" "$(git -C "$W" log -1 --format=%s release/1.0.0-rc2~1)" "fix two"
  eq "rc2: the first pick is below" "$(git -C "$W" log -1 --format=%s release/1.0.0-rc2~2)" "fix one"
  eq "rc2: rc1 is below the picks" "$(git -C "$W" rev-parse release/1.0.0-rc2~3)" "$RC1"
  has "rc2: cherry-pick -x" "$(git -C "$W" log -1 --format=%B release/1.0.0-rc2~1)" "(cherry picked from commit $FIX2)"
  eq "rc2: the fix files are in" "$(git -C "$W" ls-tree --name-only release/1.0.0-rc2 fix-one.txt fix-two.txt | tr '\n' ' ')" "fix-one.txt fix-two.txt "
  eq "rc2: the version" "$(git -C "$W" show release/1.0.0-rc2:src/module.xml | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -n 1)" 1.0.0
  eq "rc1 is unchanged by the re-cut" "$(cand 1)" "$RC1"
  # the record names rc1 and each pick, with full shas
  rs "$N" next --version 1.0.0 --rc 2
  rs "$N" next --version 1.0.0 --rc 2
  rs "$N" next --version 1.0.0 --rc 2
  rs "$N" next --version 1.0.0 --rc 2
  rs "$N" next --version 1.0.0 --rc 2
  has "rc2: the record's Candidate" "$(cat "$(rec_file 2)")" "Candidate: 1.0.0 rc2, release/1.0.0-rc2 at $c2"
  has "rc2: the record's Cut from" "$(cat "$(rec_file 2)")" "Cut from: release/1.0.0-rc1 at $RC1, then $FIX1 $FIX2 cherry-picked from $INTEG"
  # a pick that is not on the integration branch
  fixes_case
  git -C "$W" checkout -q -b side "$EXPECT_BASE"
  echo side > "$W/side.txt"
  git -C "$W" add side.txt
  git -C "$W" commit -q -m side
  SIDE=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q "$INTEG"
  rs "$Y" start --version 1.0.0 --from release/1.0.0-rc1 --pick "$SIDE"
  rs "$N" next --version 1.0.0 --rc 2
  eq "a foreign pick: exit" "$rc" 1
  has "a foreign pick: the line" "$out" "FAIL cut pick ${SIDE%"${SIDE#???????}"} is not on $INTEG"
  eq "a foreign pick: no rc2" "$(cand 2)" ""
  git -C "$W" push -q origin "$INTEG"
  rs "$Y" start --version 1.0.0 --from release/1.0.0-rc1 --pick deadbeef
  has "an unknown pick starts" "$out" "START 1.0.0 rc3 "
  rs "$N" next --version 1.0.0 --rc 3
  has "an unknown pick fails the cut" "$out" "FAIL cut pick deadbee is not a commit"
  # a conflict: a version bump on the integration branch against the cut's stamp
  fixes_case
  sed 's:<Version>[^<]*</Version>:<Version>0.1.1</Version>:' "$W/src/module.xml" > "$W/src/module.xml.new"
  mv "$W/src/module.xml.new" "$W/src/module.xml"
  git -C "$W" commit -q -am "bump"
  BUMP=$(git -C "$W" rev-parse HEAD)
  git -C "$W" push -q origin "$INTEG"
  rs "$Y" start --version 1.0.0 --from release/1.0.0-rc1 --pick "$BUMP"
  rs "$N" next --version 1.0.0 --rc 2
  eq "a conflict: exit" "$rc" 1
  has "a conflict: the line" "$out" "FAIL cut pick ${BUMP%"${BUMP#???????}"} did not apply cleanly"
  eq "a conflict: no rc2" "$(cand 2)" ""
  eq "a conflict: the checkout is on the integration branch" "$(git -C "$W" symbolic-ref --short HEAD)" "$INTEG"
  eq "a conflict: no clone is left" "$([ -d "$OCUTALON_RELEASE_STATE/1.0.0-rc2/clone" ] && echo yes || echo no)" no
}

# --- image ---

t_image() {
  local builds
  newcase
  to_step image
  rs '' next
  eq "image: exit" "$rc" 0
  has "image: the line" "$out" "PASS image 1.0.0"
  has "image: the next step" "$out" "NEXT overview"
  eq "image: built from the candidate's tree" "$(cat "$SHIMLOG/builds.log")" "build context-version=1.0.0 bundle=yes"
  eq "image: the author's checkout still says 0.1.0" "$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$W/src/module.xml" | head -n 1)" 0.1.0
  has "image: the version was read" "$(cat "$SHIMLOG/docker.log")" "run --rm --entrypoint cat ocutalon-release-check:1.0.0-rc1-"
  has "image: the check image was removed" "$(cat "$SHIMLOG/docker.log")" "rmi -f ocutalon-release-check:1.0.0-rc1-"
  eq "image: no image is left" "$(ls "$SHIMSTATE" | wc -l | tr -d ' ')" 0
  eq "image: the clone and the context are gone" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | tr '\n' ' ')" "rows.tsv state.env "
  # a lying image stops the sequence before the push question
  newcase
  to_step image
  flag lie
  rs "$N" next
  eq "a lie: exit" "$rc" 1
  has "a lie: the line" "$out" "FAIL image /opt/ocutalon/version reads '0.1.0' in the image built from the candidate, wanted 1.0.0"
  lacks "a lie: no push question" "$out" "ASK push"
  eq "a lie: nothing pushed" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | tr '\n' ' ')" "refs/heads/$INTEG "
  eq "a lie: the check image was removed" "$(ls "$SHIMSTATE" | wc -l | tr -d ' ')" 0
  has "a lie: the record" "$(cat "$(rec_file)")" "Result: failed at image: "
  rs '' status
  has "a lie: the state still names image" "$out" "STATE 1.0.0 rc1 next image"
  # a missing base image, a failed build, no bundle in the image
  unflag lie
  flag no-base
  builds=$(grep -c '^build ' "$SHIMLOG/docker.log")
  rs "$N" next
  has "no base image" "$out" "FAIL image the base image "
  eq "no base image: no build" "$(grep -c '^build ' "$SHIMLOG/docker.log")" "$builds"
  unflag no-base
  flag build-fail
  rs "$N" next
  has "a failed build" "$out" "FAIL image docker build failed: planted build failure in <state>/context/Dockerfile"
  lacks "a failed build: no local path in the record" "$(cat "$(rec_file)")" "$tmp"
  unflag build-fail
  flag no-bundle
  rs "$N" next
  has "no bundle" "$out" "FAIL image the image built from the candidate holds no web bundle"
  unflag no-bundle
  rs "$N" next
  has "the retry passes" "$out" "PASS image 1.0.0"
  has "the retry names the overview" "$out" "NEXT overview"
  newcase
  to_step image
  flag rmi-fail
  rs "$N" next
  has "an image that cannot be removed" "$out" "FAIL image the check image "
}

# --- push ---

t_push() {
  local before after c
  newcase
  to_step push
  c=$(cand)
  before=$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')
  rs "$N" next
  eq "push no: exit" "$rc" 4
  has "push no: the question" "$out" "ASK push Push release/1.0.0-rc1 ("
  has "push no: the line" "$out" "STOPPED push waiting for the author's word"
  eq "push no: the remote has no candidate" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)' | grep -c 'release/')" 0
  rs '' next
  eq "push at the end of input: exit" "$rc" 4
  has "push at the end of input: the line" "$out" "STOPPED push waiting for the author's word"
  eq "push at the end of input: the remote has no candidate" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)' | grep -c 'release/')" 0
  rs 'maybe' next
  eq "push with another word: exit" "$rc" 4
  rs "$Y" next
  has "the next next asks again, and yes pushes" "$out" "PASS push release/1.0.0-rc1"
  eq "yes: the remote holds the candidate at the cut" "$(git --git-dir="$R" rev-parse refs/heads/release/1.0.0-rc1)" "$c"
  after=$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')
  eq "yes: the only new ref is the candidate" "$(printf '%s\n' "$after" | grep -vxF "$before" | tr '\n' ' ')" "$c refs/heads/release/1.0.0-rc1 "
  eq "yes: no tag" "$(git --git-dir="$R" for-each-ref refs/tags | wc -l | tr -d ' ')" 0
  # a candidate branch that moved after the cut is never pushed
  newcase
  to_step push
  git -C "$W" branch -f release/1.0.0-rc1 "$EXPECT_BASE"
  rs '' next
  eq "a moved candidate: exit" "$rc" 1
  has "a moved candidate: the line" "$out" "FAIL push release/1.0.0-rc1 no longer points at the cut commit"
  lacks "a moved candidate: no question" "$out" "ASK push"
  eq "a moved candidate: the remote has no candidate" "$(git --git-dir="$R" for-each-ref refs/heads/release | wc -l | tr -d ' ')" 0
  # a candidate name taken on the remote after the start is never pushed over
  newcase
  to_step push
  git --git-dir="$R" branch release/1.0.0-rc1 "$EXPECT_BASE"
  rs '' next
  eq "a name taken on the remote: exit" "$rc" 1
  has "a name taken on the remote: the line" "$out" "FAIL push release/1.0.0-rc1 already exists on origin at another commit"
  lacks "a name taken on the remote: no question" "$out" "ASK push"
  eq "a name taken on the remote: the remote's branch is unchanged" "$(git --git-dir="$R" rev-parse refs/heads/release/1.0.0-rc1)" "$EXPECT_BASE"
  # a full run that answers yes to every question
  newcase
  before=$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')
  rs "$Y" start --version 1.0.0
  # the author's own tag and branch, which no push may carry along
  git -C "$W" tag note-to-self
  git -C "$W" branch scratch-branch
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$Y" next
  rs "$Y" next
  eq "full run: the last exit" "$rc" 0
  has "full run: the record was pushed" "$out" "PASS record pushed"
  has "full run: the result" "$out" "RESULT stopped"
  after=$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')
  eq "full run: the refs that differ" "$(printf '%s\n' "$after" | grep -vxF "$before" | awk '{ print $2 }' | sort | tr '\n' ' ')" "refs/heads/$INTEG refs/heads/release/1.0.0-rc1 "
  eq "full run: no tag, no main, no other branch" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | grep -c -e 'refs/tags' -e '/main$' -e scratch-branch)" 0
  eq "full run: the integration branch is a fast-forward of the old one" "$(git --git-dir="$R" merge-base --is-ancestor "$EXPECT_BASE" "$(rhead)" && echo yes)" yes
  eq "full run: one record commit" "$(git --git-dir="$R" rev-list --count "$EXPECT_BASE..$INTEG")" 1
  eq "full run: the local branch equals the remote" "$(git -C "$W" rev-parse "$INTEG")" "$(rhead)"
  eq "full run: only the record changed" "$(git --git-dir="$R" diff --name-only "$EXPECT_BASE" "$(rhead)")" "release/records/1.0.0/rc1.md"
}

# --- record ---

t_record() {
  local rec c line
  newcase
  rs "$Y" start --version 1.0.0
  rs '' next
  git -C "$W" checkout -q -b elsewhere
  flag lie
  rs "$N" next
  eq "left the integration branch: exit" "$rc" 1
  has "left the integration branch: the note" "$out" "NOTE the record was written and not committed: the checkout is not on $INTEG"
  lacks "left the integration branch: no question" "$out" "ASK record"
  eq "left the integration branch: no commit" "$(git -C "$W" rev-parse HEAD)" "$EXPECT_BASE"
  eq "left the integration branch: the remote is unchanged" "$(rhead)" "$EXPECT_BASE"
  # the author's own commit on the integration branch is never offered for a push
  newcase
  rs "$Y" start --version 1.0.0
  rs '' next
  echo "own work" > "$W/own.txt"
  git -C "$W" add own.txt
  git -C "$W" commit -q -m "own work"
  flag lie
  rs "$Y" next
  eq "own commit: exit" "$rc" 1
  has "own commit: the note" "$out" "NOTE $INTEG holds commits besides the record; the record commit is not pushed"
  lacks "own commit: no question" "$out" "ASK record"
  eq "own commit: the remote is unchanged" "$(rhead)" "$EXPECT_BASE"
  for c in draft empty merge; do
    newcase
    rs "$Y" start --version 1.0.0
    rs '' next
    if [ "$c" = draft ]; then
      mkdir -p "$W/release/records/1.0.0"
      echo "my draft" > "$W/release/records/1.0.0/rc1-notes.md"
      git -C "$W" add -f release/records/1.0.0/rc1-notes.md
      git -C "$W" commit -q -m "own draft"
    elif [ "$c" = empty ]; then
      git -C "$W" commit -q --allow-empty -m "own empty commit"
    else
      git -C "$W" checkout -q -b side
      mkdir -p "$W/release/records/1.0.0"
      echo "an older record" > "$W/release/records/1.0.0/rc5.md"
      git -C "$W" add release/records/1.0.0/rc5.md
      git -C "$W" commit -q -m "a record on a side branch"
      git -C "$W" checkout -q "$INTEG"
      git -C "$W" merge -q --no-ff -m "own merge" side
    fi
    flag lie
    rs "$Y" next
    has "own $c commit: the note" "$out" "NOTE $INTEG holds commits besides the record; the record commit is not pushed"
    lacks "own $c commit: no question" "$out" "ASK record"
    eq "own $c commit: the remote is unchanged" "$(rhead)" "$EXPECT_BASE"
  done
  newcase
  rs "$Y" start --version 1.0.0
  rs '' next
  c=$(cand)
  # work in progress of the author's: an unstaged change, a staged file, and a draft
  echo "local edit" >> "$W/README.md"
  echo staged > "$W/staged.txt"
  git -C "$W" add staged.txt
  mkdir -p "$W/release/records/1.0.0"
  echo "my draft" > "$W/release/records/1.0.0/rc1-notes.md"
  flag lie
  rs "$N" next
  eq "a failed stop: exit" "$rc" 1
  has "a failed stop: the record line" "$out" "RECORD release/records/1.0.0/rc1.md"
  has "a failed stop: the question" "$out" "ASK record Push the record commit of 1.0.0 rc1 to $INTEG on origin? [yes/no]"
  has "a failed stop: committed, not pushed" "$out" "PASS record committed, not pushed"
  eq "the commit holds only the record" "$(git -C "$W" show --name-only --format= HEAD)" "release/records/1.0.0/rc1.md"
  eq "the unstaged change stays unstaged" "$(git -C "$W" diff --name-only)" "README.md"
  eq "the staged file stays staged" "$(git -C "$W" diff --cached --name-only)" "staged.txt"
  eq "the draft stays untracked" "$(git -C "$W" status --porcelain release/records)" "?? release/records/1.0.0/rc1-notes.md"
  eq "the draft is in no commit" "$(git -C "$W" log --all --format=%H -- release/records/1.0.0/rc1-notes.md)" ""
  eq "no push to the remote" "$(rhead)" "$EXPECT_BASE"
  rec=$(cat "$(rec_file)")
  eq "the record's heading" "$(head -n 1 "$(rec_file)")" "# OcuTalon 1.0.0 rc1"
  has "the section" "$rec" "## Release sequence"
  has "the result" "$rec" "Result: failed at image: "
  has "the mode" "$rec" "Mode: release"
  has "the candidate's full sha" "$rec" "Candidate: 1.0.0 rc1, release/1.0.0-rc1 at $c"
  has "the base's full sha" "$rec" "Cut from: $INTEG at $EXPECT_BASE"
  has "the hands-on line" "$rec" "Hands-on time: "
  has "the run line" "$rec" "Run: "
  has "the table" "$rec" "| Step | Result | Detail |"
  has "the kit row" "$rec" "| kit | confirmed | the author confirmed the 1.0.0 kit is on $INTEG at ${EXPECT_BASE%"${EXPECT_BASE#???????}"} |"
  has "the cut row" "$rec" "| cut | pass | module.xml and src/module.xml set to 1.0.0; web bundle built with Node.js and committed |"
  has "the image row" "$rec" "| image | fail | "
  has "the record row" "$rec" "| record | committed, not pushed | the author did not give the word |"
  lacks "no step beyond the failure" "$rec" "| push |"
  lacks "no local path" "$rec" "$tmp"
  # the stop of an unanswered question, with the record question at the end of input
  unflag lie
  rs '' next
  has "image passes" "$out" "NEXT overview"
  rs '' next
  has "overview passes" "$out" "NEXT ipm"
  rs '' next
  has "ipm passes" "$out" "NEXT ipmcheck"
  rs '' next
  has "ipmcheck passes" "$out" "NEXT push"
  rs '' next
  eq "an unanswered push: exit" "$rc" 4
  has "an unanswered push: the stop" "$out" "STOPPED push waiting for the author's word"
  has "an unanswered push: the record question" "$out" "ASK record "
  has "an unanswered push: the record question is unanswered" "$out" "STOPPED record waiting for the author's word"
  has "an unanswered push: the result" "$out" "RESULT stopped"
  has "an unanswered push: the record" "$(cat "$(rec_file)")" "Result: stopped at push: waiting for the author's word"
  eq "the record commits are local" "$(rhead)" "$EXPECT_BASE"
  eq "two record commits" "$(git -C "$W" rev-list --count "$EXPECT_BASE..HEAD")" 2
  # the record push: yes pushes the record commit only
  rs "$Y" next
  has "push yes" "$out" "PASS push release/1.0.0-rc1"
  rs "$Y" next
  has "record yes: pushed" "$out" "PASS record pushed"
  has "pushed record row" "$(cat "$(rec_file)")" "| record | pushed | committed to $INTEG and pushed on the author's word |"
  has "the record was committed with its final row" "$(git -C "$W" show "HEAD:release/records/1.0.0/rc1.md")" "| record | pushed | "
  eq "the remote holds the record commit" "$(rhead)" "$(git -C "$W" rev-parse HEAD)"
  eq "the record commit changed only the record" "$(git -C "$W" show --name-only --format= HEAD)" "release/records/1.0.0/rc1.md"
  # a moved integration branch is reported, never merged
  newcase
  to_step push
  rs "$Y" next
  git clone -q "$R" "$C/o"
  echo "their work" > "$C/o/theirs.txt"
  git -C "$C/o" add theirs.txt
  git -C "$C/o" commit -q -m "someone else"
  git -C "$C/o" push -q origin "$INTEG"
  rs "$Y" next
  eq "a moved branch: exit" "$rc" 1
  has "a moved branch: the line" "$out" "FAIL record not pushed: $INTEG moved on origin; bring the checkout up to date and run release.sh resume"
  has "a moved branch: the row" "$(cat "$(rec_file)")" "| record | not pushed | not pushed: $INTEG moved on origin |"
  eq "a moved branch: the remote is as the other clone left it" "$(rhead)" "$(git -C "$C/o" rev-parse HEAD)"
  git -C "$W" pull -q --rebase origin "$INTEG" > /dev/null 2>&1
  rs "$Y" resume
  eq "resume after the update: exit" "$rc" 0
  has "resume after the update: pushed" "$out" "PASS record pushed"
  eq "resume after the update: the remote holds the local head" "$(rhead)" "$(git -C "$W" rev-parse HEAD)"
  rs '' next --version 1.0.0 --rc 1
  has "nothing is left" "$out" "DONE every step of 1.0.0 rc1 has run"
  eq "nothing is left: exit" "$rc" 0
  # a record outside the checkout is written and not committed
  newcase
  rs "$Y" start --version 1.0.0 --record "$C/outside.md"
  rs '' next
  flag lie
  rs '' next
  rs "$Y" next
  has "an outside record: not committed" "$out" "NOTE the record was written and not committed: the record is outside the checkout"
  eq "an outside record: no commit" "$(git -C "$W" rev-parse HEAD)" "$EXPECT_BASE"
  has "an outside record: the file" "$(cat "$C/outside.md")" "## Release sequence"
  lacks "an outside record: no question" "$out" "ASK record"
  line=$(sed -n '1p' "$C/outside.md")
  eq "an outside record: the heading" "$line" "# OcuTalon 1.0.0 rc1"
}

# --- hands ---

t_hands() {
  newcase
  clockfile 1000 1100 2000 2060 3000 3041
  rs "$Y" start --version 1.0.0
  eq "kit window: the state" "$(sed -n 's/^handson=//p' "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env")" 100
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$Y" next
  rs "$Y" next
  has "the sum of the windows" "$(cat "$(rec_file)")" "Hands-on time: 3 min 21 s for this candidate; 3 min 21 s for 1.0.0 so far (target at most 15 min; CI and the hands-on pass not counted)"
  lacks "no warning" "$out" "WARN hands-on"
  eq "the status" "$(cd "$W" && PATH="$PATH" "$BASH" release/release.sh status --version 1.0.0 --rc 1 | grep '^Hands-on')" "Hands-on time: 3 min 21 s for this candidate; 3 min 21 s for 1.0.0 so far (target at most 15 min; CI and the hands-on pass not counted)"
  # a second candidate adds to the version's sum
  clockfile 4000 4030 5000 5020 6000 6010
  rs "$Y" start --version 1.0.0
  has "rc2" "$out" "START 1.0.0 rc2 "
  rs '' next --version 1.0.0 --rc 2
  rs '' next --version 1.0.0 --rc 2
  rs '' next --version 1.0.0 --rc 2
  rs '' next --version 1.0.0 --rc 2
  rs '' next --version 1.0.0 --rc 2
  rs "$Y" next --version 1.0.0 --rc 2
  rs "$Y" next --version 1.0.0 --rc 2
  has "this candidate and the version" "$(cat "$(rec_file 2)")" "Hands-on time: 1 min 0 s for this candidate; 4 min 21 s for 1.0.0 so far (target"
  # 900 s is the target; 901 s is over it
  newcase
  clockfile 1000 1900 1900 1900 1900 1900 1900 1900
  rs "$Y" start --version 1.0.0
  flag npm-fail
  rs '' next
  rs "$N" next
  lacks "900 s: no warning" "$out" "WARN"
  lacks "900 s: not over" "$(cat "$(rec_file)")" "over the 15-minute target"
  has "900 s" "$(cat "$(rec_file)")" "Hands-on time: 15 min 0 s for this candidate; 15 min 0 s for 1.0.0 so far (target"
  newcase
  clockfile 1000 1901 1901 1901 1901 1901 1901 1901
  rs "$Y" start --version 1.0.0
  flag npm-fail
  rs '' next
  rs "$N" next
  has "901 s: the warning" "$out" "WARN hands-on time 15 min 1 s for 1.0.0 is over the 15-minute target"
  has "901 s: the record" "$(cat "$(rec_file)")" "Hands-on time: 15 min 1 s for this candidate; 15 min 1 s for 1.0.0 so far, over the 15-minute target (target at most 15 min; CI and the hands-on pass not counted)"
  eq "901 s: it refuses nothing" "$rc" 1
  # an earlier record under a minute counts, and the version's total warns when each candidate is under the target
  newcase
  git -C "$W" branch release/1.0.0-rc1
  mkdir -p "$W/release/records/1.0.0"
  printf '%s\n' "# OcuTalon 1.0.0 rc1" "## Release sequence" "Hands-on time: 45 s for this candidate; 45 s for 1.0.0 so far (target at most 15 min)" > "$W/release/records/1.0.0/rc1.md"
  clockfile 1000 1860 1860 1860 1860 1860 1860 1860
  rs "$Y" start --version 1.0.0
  has "the total over the target: rc2" "$out" "START 1.0.0 rc2 "
  flag npm-fail
  rs '' next --version 1.0.0 --rc 2
  has "the total over the target: the warning" "$out" "WARN hands-on time 15 min 5 s for 1.0.0 is over the 15-minute target"
  has "the total over the target: the record" "$(cat "$(rec_file 2)")" "Hands-on time: 14 min 20 s for this candidate; 15 min 5 s for 1.0.0 so far, over the 15-minute target"
  # a step's own run time does not count: the clock is read by the questions only
  newcase
  clockfile 10 20 30 40 50 60 70 80 90
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$Y" next
  rs "$Y" next
  has "only the question windows count" "$(cat "$(rec_file)")" "Hands-on time: 30 s for this candidate; 30 s for 1.0.0 so far"
  eq "the seam file has lines left" "$(wc -l < "$C/now" | tr -d ' ')" 3
}

# --- resume ---

t_resume() {
  local before after
  newcase
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$N" next
  eq "stopped at push" "$rc" 4
  rs '' status
  eq "status: exit" "$rc" 0
  has "status: the state" "$out" "STATE 1.0.0 rc1 next push"
  has "status: the record" "$out" "RECORD release/records/1.0.0/rc1.md"
  has "status: the hands-on time" "$out" "Hands-on time: "
  has "status: the record's result" "$out" "Result: stopped at push: waiting for the author's word"
  before=$(cd "$OCUTALON_RELEASE_STATE" && find . -type f | sort | xargs cat | cksum; git -C "$W" log --oneline | cksum; cat "$(rec_file)" | cksum; git -C "$W" status --porcelain | cksum)
  rs '' status
  rs '' status --version 1.0.0 --rc 1
  after=$(cd "$OCUTALON_RELEASE_STATE" && find . -type f | sort | xargs cat | cksum; git -C "$W" log --oneline | cksum; cat "$(rec_file)" | cksum; git -C "$W" status --porcelain | cksum)
  eq "status changes nothing" "$after" "$before"
  rs "$Y" resume
  has "resume continues at push" "$out" "PASS push release/1.0.0-rc1"
  eq "a finished step is not repeated: one build" "$(grep -c '^build' "$SHIMLOG/docker.log")" 1
  eq "a finished step is not repeated: one npm ci" "$(grep -c ' ci' "$SHIMLOG/npm.log")" 1
  eq "a finished step is not repeated: one candidate" "$(git -C "$W" for-each-ref 'refs/heads/release/*' | wc -l | tr -d ' ')" 1
  rs "$Y" next
  has "notes ran" "$out" "PASS notes RESULT "
  eq "the end: exit" "$rc" 0
  rs '' status
  has "status at the end" "$out" "STATE 1.0.0 rc1 next done"
  rs '' next
  has "nothing is run again" "$out" "DONE every step of 1.0.0 rc1 has run"
  eq "still one build" "$(grep -c '^build' "$SHIMLOG/docker.log")" 1
  # two waiting sequences need a name
  newcase
  rs "$Y" start --version 1.0.0
  rs "$Y" start --version 1.0.0
  has "a second start is allowed while the first waits" "$out" "START 1.0.0 rc2 "
  rs '' next
  eq "two waiting: exit" "$rc" 2
  has "two waiting: the line" "$out" "REFUSED more than one sequence has steps left; name --version and --rc"
  rs '' status
  has "two waiting: status asks too" "$out" "REFUSED more than one sequence"
  rs '' next --version 1.0.0
  has "a version alone" "$out" "REFUSED pass --version and --rc together"
  rs '' next --version 1.0.0 --rc 2
  eq "named: exit" "$rc" 0
  has "named: runs rc2" "$out" "PASS cut "
  eq "named: rc2 has its branch" "$([ -n "$(cand 2)" ] && echo yes)" yes
  eq "named: rc1 has none" "$(cand 1)" ""
  rs '' status --version 1.0.0 --rc 1
  has "rc1 still waits at cut" "$out" "STATE 1.0.0 rc1 next cut"
  rs '' status --version 9.9.9 --rc 1
  has "an unknown sequence" "$out" "REFUSED no sequence for 9.9.9 rc1"
  newcase
  rs '' next
  has "no sequence" "$out" "REFUSED no sequence has steps left"
}

# --- notes ---

# notes_stub <exit> <result>: a throwaway whose notes.sh prints <result> (nothing when empty) and exits <exit>; runs the push and notes steps.
notes_stub() {
  newcase
  to_step push
  printf '#!/bin/sh\n' > "$W/release/notes.sh"
  if [ -n "$2" ]; then
    printf 'echo "NOTES release/records/1.0.0/rc1-notes.md"\necho "RESULT %s"\n' "$2" >> "$W/release/notes.sh"
  fi
  printf 'exit %s\n' "$1" >> "$W/release/notes.sh"
  rs "$Y" next
  rs "$N" next
}

t_notes() {
  local n res alone
  notes_stub 0 draft
  eq "a draft: exit" "$rc" 0
  has "a draft: the line" "$out" "PASS notes RESULT draft NOTES release/records/1.0.0/rc1-notes.md"
  lacks "a draft: no warning" "$out" "WARN notes"
  has "a draft: the row" "$(cat "$(rec_file)")" "| notes | draft | release/notes.sh: RESULT draft; draft release/records/1.0.0/rc1-notes.md (not committed) |"
  notes_stub 3 "dry run"
  has "a dry run: the line" "$out" "PASS notes RESULT dry run NOTES"
  lacks "a dry run: no warning" "$out" "WARN notes"
  has "a dry run: the row" "$(cat "$(rec_file)")" "| notes | dry run | release/notes.sh: RESULT dry run; "
  notes_stub 0 ""
  eq "no result: exit" "$rc" 1
  has "no result: the line" "$out" "FAIL notes release/notes.sh printed no RESULT"
  newcase
  to_step push
  rs "$Y" next
  rs "$N" next
  n=release/records/1.0.0/rc1-notes.md
  res=$(printf '%s\n' "$out" | sed -n 's/^PASS notes RESULT \([a-z ]*\) NOTES .*/\1/p')
  case $res in
    draft | "dry run" | fail) ;;
    *)
      echo "  the notes step printed no RESULT: $out"
      bad=1
      ;;
  esac
  has "the notes line carries the draft's path" "$out" "NOTES $n"
  alone=$(cd "$W" && "$BASH" release/notes.sh --version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --record release/records/1.0.0/rc1.md --notes "$C/alone.md" | sed -n 's/^RESULT //p')
  eq "the same result as the script alone" "$res" "$alone"
  has "the row carries the result and the path" "$(cat "$(rec_file)")" "| notes | $res | release/notes.sh: RESULT $res; draft $n (not committed) |"
  eq "the draft exists" "$([ -f "$W/$n" ] && echo yes)" yes
  eq "the draft is untracked" "$(git -C "$W" status --porcelain -- "$n")" "?? $n"
  eq "the draft is in no commit" "$(git -C "$W" log --all --format=%H -- "$n")" ""
  eq "the draft is not on the remote" "$(git --git-dir="$R" log --all --format=%H -- "$n")" ""
  # a draft that exists is a refusal: the step fails, the draft is kept
  newcase
  to_step push
  mkdir -p "$W/release/records/1.0.0"
  echo "keep me" > "$W/$n"
  rs "$Y" next
  rs "$N" next
  eq "an existing draft: exit" "$rc" 1
  has "an existing draft: the line" "$out" "FAIL notes release/notes.sh refused: "
  eq "an existing draft is kept" "$(cat "$W/$n")" "keep me"
  has "an existing draft: the row" "$(cat "$(rec_file)")" "| notes | fail | release/notes.sh refused: "
}

# --- gate ---

t_gate() {
  local before after cl
  newcase
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$Y" next
  # another gate's section is already in the record when the sequence writes its own
  mkdir -p "$W/release/records/1.0.0"
  printf '# OcuTalon 1.0.0 rc1\n\n## Clean-machine rehearsal\nResult: not run\nMode: dry run\n' > "$(rec_file)"
  rs "$Y" next
  has "the sequence kept the other gate's section" "$(cat "$(rec_file)")" "## Clean-machine rehearsal
Result: not run
Mode: dry run"
  before=$(awk '/^## Release sequence/ { f = 1; print; next } f && /^## / { exit } f { print }' "$(rec_file)")
  git clone -q "$R" "$C/h" || exit 1
  git -C "$C/h" checkout -q release/1.0.0-rc1
  cl=$(cd "$C/h" && PATH="$PATH" "$BASH" release/upgrade-harness.sh plan --version 1.0.0 --rc 1 --previous "$EXPECT_BASE" --record "$(rec_file)" 2>&1)
  eq "the harness accepts the candidate: exit" "$?" 0
  has "the harness read the stamped version" "$cl" "PLAN candidate 1.0.0 at $(cand)"
  has "the harness wrote its section" "$(cat "$(rec_file)")" "## Upgrade harness"
  after=$(awk '/^## Release sequence/ { f = 1; print; next } f && /^## / { exit } f { print }' "$(rec_file)")
  eq "the release sequence section is byte for byte" "$after" "$before"
  rs '' status --version 1.0.0 --rc 1
  eq "status still reads the record: exit" "$rc" 0
  has "status still reads the record" "$out" "Result: stopped after notes: no gate has run (not a release)"
}

# --- secret ---

forbidden_scan() { # forbidden_scan <file>...: file:line of each forbidden form
  awk '
    function bad(why) { printf "%s:%d\n", FILENAME, FNR }
    {
      line = $0
      if (line ~ /docker[ \t]+(push|login|save|export)([ \t]|$)/) bad()
      else if (line ~ /printenv/) bad()
      else if (line ~ /(^|[;&|(` \t])env[ \t]*($|[|;&)>`])/) bad()
      else if (line ~ /(^|[;& \t])set[ \t]+-[a-zA-Z]*x/) bad()
      else if (line ~ /declare[ \t]+-[a-zA-Z]*p/) bad()
      else if (line ~ /docker[ \t]+compose[ \t]+config/ && line !~ /--quiet/) bad()
      else if (line ~ /docker[^|;&]*[ \t]inspect/ && line !~ /--format/) bad()
      else if (line ~ /docker[ \t]+pull/) bad()
      else if (line ~ /(zpm|repo)[ \t]/ && line ~ /(publish|[ \t]-r[ \t]|-url)/) bad()
      else if (line ~ /git[ \t]+push[^|;&]*(--force|--tags|--all|--mirror|--delete| -f |[ \t]\+)/) bad()
      else if (line ~ /git[^|;&]*[ \t]tag([ \t]|$)/ && line !~ /--list|--merged|--points-at/) bad()
    }' "$@"
}

t_secret() {
  local d f hits plant p
  newcase
  printf '' > "$tmp/alloutput"
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$Y" next
  rs "$Y" next
  rs '' status
  eq "the full run ended well" "$rc" 0
  hits=$(grep -rl "$OCUTALON_TEST_SECRET" "$tmp/alloutput" "$C/shim" "$OCUTALON_RELEASE_STATE" "$W/release/records" 2> /dev/null)
  eq "the planted value is in no output, record, state or shim log" "$hits" ""
  eq "no docker push, login, save or export" "$(grep -cE '^(push|login|save|export)' "$SHIMLOG/docker.log")" 0
  eq "no docker compose or inspect call" "$(grep -cE '^(compose|inspect)' "$SHIMLOG/docker.log")" 0
  eq "the planted value is in the environment of the run" "$(cd "$W" && "$BASH" -c 'echo "${OCUTALON_TEST_SECRET:+set}"')" set
  # the scan of the real scripts, and of planted lines
  eq "the scan of the scripts" "$(forbidden_scan "$root/release/release.sh" "$root/release/lib-release.sh")" ""
  mkdir -p "$tmp/scan"
  for p in "dock""er push img" "dock""er login" "dock""er save x" "dock""er export x" "print""env" "en""v" "x=\$(en""v | sort)" "set"" -x" "declare"" -p" "dock""er compose config" "dock""er image inspect x" "git"" push --force origin x" "git"" push origin --tags" "git"" push origin --all" "git"" push origin +x:y" "git"" tag v1.0.0"; do
    printf '#!/bin/sh\necho ok\n%s\n' "$p" > "$tmp/scan/s.sh"
    eq "the scan flags '$p'" "$(forbidden_scan "$tmp/scan/s.sh")" "$tmp/scan/s.sh:3"
  done
  for p in "dock""er compose config --quiet" "dock""er image inspect --format x y" "git"" push -q origin a:b" "echo no dock""er push here"; do
    printf '#!/bin/sh\n%s\n' "$p" > "$tmp/scan/g.sh"
    case $p in
      "echo no"*) ;;
      *) eq "the scan accepts '$p'" "$(forbidden_scan "$tmp/scan/g.sh")" "" ;;
    esac
  done
  cp "$root/release/release.sh" "$tmp/scan/copy.sh"
  printf '%s\n' "dock""er push registry.invalid/x" >> "$tmp/scan/copy.sh"
  eq "a planted line in a copy of the script" "$(forbidden_scan "$tmp/scan/copy.sh")" "$tmp/scan/copy.sh:$(wc -l < "$tmp/scan/copy.sh" | tr -d ' ')"
  eq "the network stubs were not called" "$(ls "$tmp/netmarks" | tr '\n' ' ')" ""
  plant=$(grep -rl "$OCUTALON_TEST_SECRET" "$tmp"/c*/shim "$tmp/alloutput" 2> /dev/null)
  eq "the planted value is in no output and shim log of any case" "$plant" ""
}

# --- first (QA: the first version must be 1.0.0) ---

t_first() {
  local before v
  newcase
  before=$(snap)
  for v in 1.0.1 1.1.0 2.0.0 0.1.0 0.1.1 0.9.9 10.0.0 1.0.00; do
    rs "$Y" start --version "$v"
    eq "first release $v: exit" "$rc" 2
    eq "first release $v: the line" "$out" "REFUSED the first release is 1.0.0"
    eq "first release $v: nothing written" "$(snap)" "$before"
  done
  rs "$Y" start --version 1.0.0
  eq "first release 1.0.0: exit" "$rc" 0
  has "first release 1.0.0: the kit is asked" "$out" "ASK kit "
}

# --- word (QA: only the line yes proceeds; nothing answers in advance) ---

t_word() {
  local a o v before names
  names="OCUTALON_RELEASE_YES OCUTALON_RELEASE_ANSWER OCUTALON_RELEASE_ANSWERS OCUTALON_RELEASE_ASSUME_YES OCUTALON_RELEASE_CONFIRM OCUTALON_YES OCUTALON_ASSUME_YES RELEASE_YES ASSUME_YES YES ANSWER CI NONINTERACTIVE DEBIAN_FRONTEND OCUTALON_RELEASE_KIT_CONFIRMED"
  # the kit question: any line but yes refuses and writes nothing
  newcase
  before=$(snap)
  for a in y Y YES Yes "yes please" " yes" "yes " ok true 1 "yes!" "no"; do
    rs "$a"$'\n' start --version 1.0.0
    eq "kit '$a': exit" "$rc" 2
    has "kit '$a': the line" "$out" "REFUSED the author did not confirm the 1.0.0 kit"
    eq "kit '$a': nothing written" "$(snap)" "$before"
  done
  # no option answers a question in advance
  for o in --yes -y --assume-yes --answer=yes "--answer yes" --force --no-ask --non-interactive --confirm; do
    # shellcheck disable=SC2086
    rs "$Y" start --version 1.0.0 $o
    eq "start $o: exit" "$rc" 2
    has "start $o: refused" "$out" "REFUSED unknown option"
    lacks "start $o: no question was printed" "$out" "ASK "
    eq "start $o: nothing written" "$(snap)" "$before"
  done
  # no variable of the environment answers a question in advance
  for v in $names; do export "$v=yes"; done
  rs '' start --version 1.0.0
  for v in $names; do unset "$v"; done
  eq "environment answers, start: exit" "$rc" 2
  has "environment answers, start: refused" "$out" "REFUSED the author did not confirm the 1.0.0 kit"
  eq "environment answers, start: nothing written" "$(snap)" "$before"
  # the push question: any other line stops with exit 4 and pushes nothing
  newcase
  to_step push
  before=$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')
  for a in y YES "yes please" " yes" "yes " ok "no"; do
    rs "$a"$'\n' next
    eq "push '$a': exit" "$rc" 4
    has "push '$a': the line" "$out" "STOPPED push waiting for the author's word"
    eq "push '$a': the remote is unchanged" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')" "$before"
  done
  # one line answers one question: the 'no' to push is not followed by the 'yes' reaching push
  rs "no"$'\nyes\n' next
  eq "no then yes: exit" "$rc" 4
  eq "no then yes: the candidate is not on the remote" "$(git --git-dir="$R" for-each-ref refs/heads/release | wc -l | tr -d ' ')" 0
  # the second line answered the record question (a separate question, one line each); the candidate is still not pushed
  before=$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')
  for o in --yes -y --assume-yes --answer=yes --force; do
    rs '' next "$o"
    eq "next $o: exit" "$rc" 2
    has "next $o: refused" "$out" "REFUSED unknown option"
  done
  rs '' resume --yes
  eq "resume --yes: exit" "$rc" 2
  eq "no option pushed anything" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')" "$before"
  for v in $names; do export "$v=yes"; done
  rs '' next
  for v in $names; do unset "$v"; done
  eq "environment answers, push: exit" "$rc" 4
  has "environment answers, push: the line" "$out" "STOPPED push waiting for the author's word"
  eq "environment answers, push: the remote is unchanged" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')" "$before"
  # the script reads one line from standard input, and from nothing else
  eq "one read command, from standard input" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep -E '(^|[^[:alnum:]_])read[[:space:]]' | sed 's/^[[:space:]]*//')" 'if ! IFS= read -r line && [ -z "$line" ]; then'
  eq "no terminal device and no pre-answer file" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep -cE '/dev/tty|/dev/fd|--yes|assume|ANSWER')" 0
}

# --- pushes (QA: exactly two pushes, to the local bare remote only; the author's checkout never switched; the draft never leaves) ---

t_pushes() {
  local real shimdir log pushes head n
  newcase
  shimdir=$C/gitshim
  mkdir -p "$shimdir"
  real=$(command -v git)
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$SHIMLOG/git.log"\nexec "%s" "$@"\n' "$real" > "$shimdir/git"
  chmod 755 "$shimdir/git"
  RS_PATH="$shimdir:$PATH"
  git -C "$W" tag note-to-self
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$Y" next
  rs "$Y" next
  eq "two pushes: the last exit" "$rc" 0
  log=$(cat "$SHIMLOG/git.log")
  pushes=$(printf '%s\n' "$log" | grep -E '(^| )push( |$)')
  head=$(git -C "$W" rev-parse HEAD)
  eq "exactly two pushes" "$(printf '%s\n' "$pushes" | grep -c .)" 2
  eq "the first push is the candidate branch alone" "$(printf '%s\n' "$pushes" | sed -n 1p)" "push -q origin refs/heads/release/1.0.0-rc1:refs/heads/release/1.0.0-rc1"
  eq "the second push is the record commit to the integration branch alone" "$(printf '%s\n' "$pushes" | sed -n 2p)" "push -q origin $head:refs/heads/$INTEG"
  eq "no force, tag, all, mirror, delete, plus refspec or main in a push" "$(printf '%s\n' "$pushes" | grep -cE -e '--force|--tags|--all|--mirror|--delete|--prune| -f |:?\+|refs/tags|main|note-to-self')" 0
  eq "every push names the remote origin" "$(printf '%s\n' "$pushes" | awk '{ print $3 }' | sort -u)" origin
  eq "origin is the local bare repository of the test" "$(git -C "$W" remote get-url origin)" "$R"
  eq "no tag was created (the tag calls only list)" "$(printf '%s\n' "$log" | grep -E '(^| )tag( |$)' | grep -vcE -e '--list|--points-at|--merged')" 0
  eq "no remote was added or changed (the remote calls only read a URL)" "$(printf '%s\n' "$log" | grep -E '(^| )remote( |$)' | grep -vcE 'remote get-url')" 0
  # the author's checkout is never switched: the reflog of HEAD holds the clone and the record commits only
  eq "the checkout stays on the integration branch" "$(git -C "$W" symbolic-ref --short HEAD)" "$INTEG"
  eq "no checkout, switch, reset, rebase, merge or pull in the checkout's HEAD reflog" "$(git -C "$W" reflog show --format=%gs HEAD | grep -vcE '^(clone|commit)')" 0
  eq "the checkout's branches are the integration branch, the candidate and the author's own" "$(git -C "$W" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ')" "$INTEG release/1.0.0-rc1 "
  # the draft exists and is in no commit, locally or on the remote (DW-560)
  n=release/records/1.0.0/rc1-notes.md
  eq "the draft exists in the checkout" "$([ -f "$W/$n" ] && echo yes)" yes
  eq "the draft is untracked" "$(git -C "$W" status --porcelain -- "$n")" "?? $n"
  eq "the draft is in no object of the local history" "$(git -C "$W" log --all --format=%H -- "$n")" ""
  eq "the draft is in no tree of the candidate" "$(git -C "$W" ls-tree -r --name-only release/1.0.0-rc1 | grep -c 'rc1-notes.md')" 0
  eq "the remote's integration tree holds the record and no draft" "$(git --git-dir="$R" ls-tree -r --name-only "$INTEG" -- release/records | tr '\n' ' ')" "release/records/1.0.0/rc1.md "
  eq "the remote's candidate tree holds no draft" "$(git --git-dir="$R" ls-tree -r --name-only release/1.0.0-rc1 | grep -c 'rc1-notes.md')" 0
  eq "the remote has no tag" "$(git --git-dir="$R" for-each-ref refs/tags | wc -l | tr -d ' ')" 0
  # declined words: no push at all
  newcase
  mkdir -p "$C/gitshim"
  cp "$shimdir/git" "$C/gitshim/git"
  RS_PATH="$C/gitshim:$PATH"
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$N" next
  rs '' next
  eq "declined and unanswered words: no push" "$(grep -cE '(^| )push( |$)' "$SHIMLOG/git.log")" 0
  RS_PATH=""
}

# --- overview ---

t_overview() {
  local before kept
  # a pass: the unit ran in the cut candidate, the row is recorded and the next step is ipm
  # The author's repository has the coordination folder, and the case has no lock folder in its environment: the unit gets the lane lock folder
  # that the step derives from the author's repository.
  newcase
  to_step overview
  mkdir -p "$W/.worktrees/.coordination/locks"
  unset OCUTALON_LOCK_DIR
  rs '' next
  export OCUTALON_LOCK_DIR=$C/locks
  eq "overview pass: exit" "$rc" 0
  lacks "overview pass: the export is readable by others" "$out" "not readable by others"
  has "overview pass: the line" "$out" "PASS overview "
  has "overview pass: the next step" "$out" "NEXT ipm"
  eq "overview pass: the unit received the lane lock folder of the author's repository" "$(cat "$SHIMLOG/overview-lock-dir.txt" 2> /dev/null)" "$W/.worktrees/.coordination/locks"
  eq "overview pass: the unit runs under umask 077" "$(cat "$SHIMLOG/overview-umask.txt" 2> /dev/null)" 0077
  eq "overview pass: release.sh keeps its one umask 077 line" "$(grep -c '^umask 077$' "$root/release/release.sh")" 1
  eq "overview pass: lib-release.sh keeps its one umask 077 line" "$(grep -c '^umask 077$' "$root/release/lib-release.sh")" 1
  eq "overview pass: the export and the log are gone" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | tr '\n' ' ')" "rows.tsv state.env "
  rs '' status
  has "overview pass: the state names ipm" "$out" "STATE 1.0.0 rc1 next ipm"
  # a drift: the release stops at overview, with the record written, and never reaches ipm
  newcase
  set_stub fail
  to_step overview
  rs "$N" next
  eq "overview fail: exit" "$rc" 1
  has "overview fail: the line" "$out" "FAIL overview DRIFT tool recent_activity"
  lacks "overview fail: no next step" "$out" "NEXT ipm"
  lacks "overview fail: the unit's own line is not repeated" "$out" "FAIL overview FAIL overview"
  has "overview fail: the result" "$out" "RESULT fail"
  has "overview fail: the record" "$(cat "$(rec_file)")" "Result: failed at overview: DRIFT tool recent_activity"
  has "overview fail: the row" "$(cat "$(rec_file)")" "| overview | fail | DRIFT tool recent_activity |"
  lacks "overview fail: ipm never ran" "$(cat "$(rec_file)")" "| ipm |"
  lacks "overview fail: no local path in the record" "$(cat "$(rec_file)")" "$tmp"
  kept="$OCUTALON_RELEASE_STATE/1.0.0-rc1/overview-fail.log"
  has "overview fail: the log is kept" "$(cat "$kept" 2> /dev/null)" "DRIFT tool recent_activity"
  eq "overview fail: no overview.log or export remains" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | grep -c -e '^overview$' -e '^overview[.]log$')" 0
  has "overview fail: the LOG line" "$out" "LOG overview $kept"
  eq "overview fail: the LOG line follows the FAIL line" "$(printf '%s\n' "$out" | grep -A 1 '^FAIL overview ' | tail -n 1)" "LOG overview $kept"
  lacks "overview fail: the record does not name the kept log" "$(cat "$(rec_file)")" "overview-fail.log"
  eq "overview fail: nothing pushed" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | tr '\n' ' ')" "refs/heads/$INTEG "
  rs '' status
  has "overview fail: the state still names overview" "$out" "STATE 1.0.0 rc1 next overview"
  # a new failure replaces an earlier kept log
  printf '%s\n' "STALE log of an earlier run" > "$kept"
  rs "$N" next
  eq "overview refail: exit" "$rc" 1
  lacks "overview refail: the earlier log is replaced" "$(cat "$kept" 2> /dev/null)" "STALE"
  has "overview refail: the new log is kept" "$(cat "$kept" 2> /dev/null)" "DRIFT tool recent_activity"
  eq "overview refail: the LOG line follows the FAIL line" "$(printf '%s\n' "$out" | grep -A 1 '^FAIL overview ' | tail -n 1)" "LOG overview $kept"
  # a wait keeps the log of the earlier failure
  printf '%s\n' "KEPT log of an earlier run" > "$kept"
  : > "$SHIMLOG/overview-busy"
  rs '' next
  eq "overview wait: exit" "$rc" 5
  has "overview wait: the kept log stays" "$(cat "$kept" 2> /dev/null)" "KEPT log of an earlier run"
  rm -f "$SHIMLOG/overview-busy"
  # a rerun that passes removes the kept log
  printf '%s\n' "KEPT log of an earlier run" > "$kept"
  : > "$SHIMLOG/overview-pass"
  rs '' next
  eq "overview rerun: exit" "$rc" 0
  has "overview rerun: the next step" "$out" "NEXT ipm"
  eq "overview rerun: the kept log is gone" "$([ -e "$kept" ] && echo yes || echo no)" no
  # a failure whose first line is the unit's own FAIL overview line: its prefix is not repeated
  newcase
  set_stub silent
  to_step overview
  rs "$N" next
  eq "overview silent: exit" "$rc" 1
  has "overview silent: the line" "$out" "FAIL overview a step ended with exit 3"
  lacks "overview silent: the unit's own prefix is not repeated" "$out" "FAIL overview FAIL overview"
  has "overview silent: the record" "$(cat "$(rec_file)")" "Result: failed at overview: a step ended with exit 3"
  has "overview silent: the LOG line" "$out" "LOG overview /"
  # a unit that exits with a code but prints no DRIFT or FAIL line: the exit code is named and the log is still kept
  newcase
  set_stub quiet
  to_step overview
  rs "$N" next
  eq "overview quiet: exit" "$rc" 1
  has "overview quiet: the exit code is named" "$out" "FAIL overview the overview unit ended with exit 2"
  eq "overview quiet: the LOG line follows the FAIL line" "$(printf '%s\n' "$out" | grep -A 1 '^FAIL overview ' | tail -n 1)" "LOG overview $OCUTALON_RELEASE_STATE/1.0.0-rc1/overview-fail.log"
  has "overview quiet: the log is kept" "$(cat "$OCUTALON_RELEASE_STATE/1.0.0-rc1/overview-fail.log" 2> /dev/null)" "not a DRIFT or FAIL line"
  eq "overview quiet: no overview.log or export remains" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | grep -c -e '^overview$' -e '^overview[.]log$')" 0
  has "overview quiet: the record names the exit code" "$(cat "$(rec_file)")" "Result: failed at overview: the overview unit ended with exit 2"
  lacks "overview quiet: no local path in the record" "$(cat "$(rec_file)")" "$tmp"
  # a relative state folder: the LOG line still names an absolute path
  newcase
  set_stub fail
  export OCUTALON_RELEASE_STATE=../state
  to_step overview
  rs "$N" next
  export OCUTALON_RELEASE_STATE=$C/state
  eq "overview relative: exit" "$rc" 1
  eq "overview relative: the LOG line names an absolute path" "$(printf '%s\n' "$out" | grep -A 1 '^FAIL overview ' | tail -n 1)" "LOG overview $W/../state/1.0.0-rc1/overview-fail.log"
  eq "overview relative: the log is kept there" "$([ -s "$C/state/1.0.0-rc1/overview-fail.log" ] && echo yes || echo no)" yes
  # a log that cannot be kept: the failure is reported and no LOG line is printed
  newcase
  set_stub nolog
  to_step overview
  rs "$N" next
  eq "overview nolog: exit" "$rc" 1
  has "overview nolog: the line" "$out" "FAIL overview the overview unit ended with exit 1"
  lacks "overview nolog: no LOG line" "$out" "LOG overview"
  has "overview nolog: the record" "$(cat "$(rec_file)")" "Result: failed at overview: the overview unit ended with exit 1"
  # a log that exists but cannot be moved: the failure is reported, no LOG line is printed and the log does not stay behind
  newcase
  set_stub fail
  to_step overview
  mkdir -p "$C/mvshim"
  printf '#!/bin/sh\ncase "$*" in *overview-fail.log) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v mv)" > "$C/mvshim/mv"
  chmod 755 "$C/mvshim/mv"
  RS_PATH="$C/mvshim:$PATH"
  rs "$N" next
  RS_PATH=""
  eq "overview nomove: exit" "$rc" 1
  has "overview nomove: the line" "$out" "FAIL overview DRIFT tool recent_activity"
  lacks "overview nomove: no LOG line" "$out" "LOG overview"
  eq "overview nomove: no log stays" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | grep -c -e '^overview[.]log$' -e '^overview-fail[.]log$')" 0
  has "overview nomove: the record" "$(cat "$(rec_file)")" "Result: failed at overview: DRIFT tool recent_activity"
  # a busy lane lock: WAIT, exit 5, nothing recorded, and the next call runs the step again
  newcase
  set_stub busy
  to_step overview
  before=$(snap)
  rs '' next
  eq "overview busy: exit" "$rc" 5
  eq "overview busy: the line" "$out" "WAIT overview the lane's throwaway lock is busy"
  eq "overview busy: nothing recorded" "$(snap)" "$before"
  eq "overview busy: no record" "$([ -f "$(rec_file)" ] && echo yes || echo no)" no
  rs '' status
  has "overview busy: the state still names overview" "$out" "STATE 1.0.0 rc1 next overview"
  rs '' next
  eq "overview busy: the next call runs the step again" "$rc" 5
}

# --- ipmcheck (Story 15.4) ---

# ipmcheck_to: a fresh case with the unit's stub (pass, fail, busy or silent) committed, run up to the ipmcheck step.
ipmcheck_to() {
  newcase
  if [ "$1" != pass ]; then set_ipm_stub "$1"; fi
  to_step ipmcheck
}

t_ipmcheck() {
  local art bytes before size
  . "$root/release/lib-release.sh"
  # a pass: the unit ran in the cut candidate with the artifact, the lane lock folder, a run tag and the job's deadline; teardown followed
  ipmcheck_to pass
  art=$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz
  bytes=$(wc -c < "$art" | tr -d ' ')
  mkdir -p "$W/.worktrees/.coordination/locks"
  saved_tag=${OCUTALON_RUN_TAG-}
  saved_deadline=${OCUTALON_LIVE_DEADLINE-}
  unset OCUTALON_LOCK_DIR OCUTALON_RUN_TAG OCUTALON_LIVE_DEADLINE
  rs '' next
  export OCUTALON_LOCK_DIR=$C/locks
  if [ -n "$saved_tag" ]; then export OCUTALON_RUN_TAG=$saved_tag; fi
  if [ -n "$saved_deadline" ]; then export OCUTALON_LIVE_DEADLINE=$saved_deadline; fi
  eq "ipmcheck pass: exit" "$rc" 0
  has "ipmcheck pass: the line" "$out" "PASS ipmcheck ocutalon-1.0.0.tgz ($bytes bytes) installs from a local IPM repository"
  has "ipmcheck pass: the next step" "$out" "NEXT push"
  lacks "ipmcheck pass: no question is asked" "$out" "ASK "
  lacks "ipmcheck pass: no warning" "$out" "WARN"
  eq "ipmcheck pass: the artifact handed to the unit" "$(sed -n 's/^artifact=//p' "$SHIMLOG/ipmcheck-env.txt")" "$art"
  eq "ipmcheck pass: the lane lock folder of the author's repository" "$(sed -n 's/^lock=//p' "$SHIMLOG/ipmcheck-env.txt")" "$W/.worktrees/.coordination/locks"
  eq "ipmcheck pass: the unit has no argument" "$(sed -n 's/^args=//p' "$SHIMLOG/ipmcheck-env.txt")" ""
  eq "ipmcheck pass: the job's deadline" "$(sed -n 's/^deadline=//p' "$SHIMLOG/ipmcheck-env.txt")" 1980
  case $(sed -n 's/^tag=//p' "$SHIMLOG/ipmcheck-env.txt") in
    ipmchk-[0-9]*) ;;
    *)
      echo "  ipmcheck pass: the run tag is '$(sed -n 's/^tag=//p' "$SHIMLOG/ipmcheck-env.txt")'"
      bad=1
      ;;
  esac
  eq "ipmcheck pass: teardown ran once, with the unit's tag" "$(cat "$SHIMLOG/iris-calls.txt")" "teardown tag=$(sed -n 's/^tag=//p' "$SHIMLOG/ipmcheck-env.txt")"
  eq "ipmcheck pass: the export and the log are gone" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | grep -c -e '^ipmcheck$' -e '^ipmcheck[.]log$')" 0
  rs '' status
  has "ipmcheck pass: the state names push" "$out" "STATE 1.0.0 rc1 next push"
  has "ipmcheck pass: the record section" "$(sect "$(rec_file)" "## FR-57 job")" "Result: pass"
  has "ipmcheck pass: the artifact line" "$(sect "$(rec_file)" "## FR-57 job")" "Artifact: ocutalon-1.0.0.tgz, $bytes bytes"
  has "ipmcheck pass: the command line" "$(sect "$(rec_file)" "## FR-57 job")" "Command: bash release/ipm-install.sh on an export of the candidate's tree"
  lacks "ipmcheck pass: no size note under the threshold" "$(sect "$(rec_file)" "## FR-57 job")" "Size:"
  lacks "ipmcheck pass: no local path in the record" "$(cat "$(rec_file)")" "$tmp"
  has "ipmcheck pass: the IPM artifact section is still there" "$(cat "$(rec_file)")" "## IPM artifact"
  # the caller's run tag and deadline are kept; the unit still gets the tag of its own
  ipmcheck_to pass
  OCUTALON_RUN_TAG=abc OCUTALON_LIVE_DEADLINE=900 rs '' next
  eq "ipmcheck tag: exit" "$rc" 0
  case $(sed -n 's/^tag=//p' "$SHIMLOG/ipmcheck-env.txt") in
    abc-ipmchk-[0-9]*) ;;
    *)
      echo "  ipmcheck tag: the run tag is '$(sed -n 's/^tag=//p' "$SHIMLOG/ipmcheck-env.txt")'"
      bad=1
      ;;
  esac
  eq "ipmcheck tag: the caller's deadline" "$(sed -n 's/^deadline=//p' "$SHIMLOG/ipmcheck-env.txt")" 900
  # a large artifact: a WARN line and a Size: note, and nothing fails
  ipmcheck_to pass
  art=$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz
  head -c 5100000 /dev/zero >> "$art"
  size=$(wc -c < "$art" | tr -d ' ')
  rs '' next
  eq "ipmcheck large: exit" "$rc" 0
  has "ipmcheck large: the WARN line" "$out" "WARN ipmcheck the artifact is $size bytes, over 5000000; report it to the Contest Planner"
  has "ipmcheck large: still a pass" "$out" "PASS ipmcheck "
  has "ipmcheck large: the next step" "$out" "NEXT push"
  has "ipmcheck large: the Size: note" "$(sect "$(rec_file)" "## FR-57 job")" "Size: $size bytes, over 5000000"
  has "ipmcheck large: the result" "$(sect "$(rec_file)" "## FR-57 job")" "Result: pass"
  # a failure: the unit's first FAIL line, the record, no push question, and the release stops
  ipmcheck_to fail
  rs '' next
  eq "ipmcheck fail: exit" "$rc" 1
  has "ipmcheck fail: the line" "$out" "FAIL ipmcheck part p uninstall: USER's repository definitions differ, or there are none (differs, or 0 nodes)"
  lacks "ipmcheck fail: no PASS line" "$out" "PASS ipmcheck"
  lacks "ipmcheck fail: no next step" "$out" "NEXT push"
  lacks "ipmcheck fail: no push question" "$out" "ASK push"
  lacks "ipmcheck fail: the unit's second FAIL line is not the detail" "$out" "a second failure"
  has "ipmcheck fail: the result" "$out" "RESULT fail"
  has "ipmcheck fail: the record" "$(cat "$(rec_file)")" "Result: failed at ipmcheck: part p uninstall: USER's repository definitions differ"
  has "ipmcheck fail: the row" "$(cat "$(rec_file)")" "| ipmcheck | fail | part p uninstall: USER's repository definitions differ"
  has "ipmcheck fail: the FR-57 section" "$(sect "$(rec_file)" "## FR-57 job")" "Result: fail"
  has "ipmcheck fail: the first failure" "$(sect "$(rec_file)" "## FR-57 job")" "First failure: part p uninstall: USER's repository definitions differ"
  # a large artifact on a failure: the WARN line too, beside the FAIL line
  ipmcheck_to fail
  head -c 5100000 /dev/zero >> "$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz"
  rs '' next
  eq "ipmcheck large fail: exit" "$rc" 1
  has "ipmcheck large fail: the WARN line" "$out" "WARN ipmcheck the artifact is "
  lacks "ipmcheck fail: push never ran" "$(cat "$(rec_file)")" "| push |"
  lacks "ipmcheck fail: no local path in the record" "$(cat "$(rec_file)")" "$tmp"
  eq "ipmcheck fail: nothing pushed" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | tr '\n' ' ')" "refs/heads/$INTEG "
  eq "ipmcheck fail: teardown ran" "$(grep -c '^teardown ' "$SHIMLOG/iris-calls.txt")" 1
  rs '' status
  has "ipmcheck fail: the state still names ipmcheck" "$out" "STATE 1.0.0 rc1 next ipmcheck"
  # a unit that fails without a FAIL line, and an exit that is neither 0, 1 nor 75
  ipmcheck_to silent
  rs '' next
  eq "ipmcheck silent: exit" "$rc" 1
  has "ipmcheck silent: the line" "$out" "FAIL ipmcheck release/ipm-install.sh ended with exit 3"
  lacks "ipmcheck silent: no next step" "$out" "NEXT push"
  has "ipmcheck silent: the FR-57 section" "$(sect "$(rec_file)" "## FR-57 job")" "Result: fail"
  # busy: WAIT, exit 5, nothing recorded, and the next call runs the step again
  ipmcheck_to busy
  before=$(snap)
  rs '' next
  eq "ipmcheck busy: exit" "$rc" 5
  eq "ipmcheck busy: the line" "$out" "WAIT ipmcheck the lane's throwaway lock is busy"
  eq "ipmcheck busy: nothing recorded" "$(snap)" "$before"
  eq "ipmcheck busy: no FR-57 section" "$(cat "$(rec_file)" 2> /dev/null | grep -c 'FR-57 job' || true)" 0
  eq "ipmcheck busy: teardown ran" "$(grep -c '^teardown ' "$SHIMLOG/iris-calls.txt")" 1
  rs '' status
  has "ipmcheck busy: the state still names ipmcheck" "$out" "STATE 1.0.0 rc1 next ipmcheck"
  rs '' next
  eq "ipmcheck busy: the next call runs the step again" "$rc" 5
  eq "ipmcheck busy: teardown ran again" "$(grep -c '^teardown ' "$SHIMLOG/iris-calls.txt")" 2
  # refusals, before any run of the unit: the ipm step did not pass, the artifact is gone, the candidate has no unit
  ipmcheck_to pass
  sed -i.bak '/^ipm_result=/d' "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env"
  rm -f "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env.bak"
  rs '' next
  eq "ipmcheck refusal (ipm not passed): exit" "$rc" 1
  has "ipmcheck refusal (ipm not passed): the line" "$out" "FAIL ipmcheck the ipm step has not passed"
  eq "ipmcheck refusal (ipm not passed): the unit never ran" "$(ls "$SHIMLOG" | grep -c -e ipmcheck-env -e iris-calls)" 0
  ipmcheck_to pass
  rm -f "$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz"
  rs '' next
  eq "ipmcheck refusal (no artifact): exit" "$rc" 1
  has "ipmcheck refusal (no artifact): the line" "$out" "FAIL ipmcheck the IPM artifact ocutalon-1.0.0.tgz is missing"
  eq "ipmcheck refusal (no artifact): the unit never ran" "$(ls "$SHIMLOG" | grep -c -e ipmcheck-env -e iris-calls)" 0
  newcase
  git -C "$W" rm -q release/ipm-install.sh
  git -C "$W" commit -q -m "no unit"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
  to_step ipmcheck
  rs '' next
  eq "ipmcheck refusal (no unit): exit" "$rc" 1
  has "ipmcheck refusal (no unit): the line" "$out" "FAIL ipmcheck the candidate has no release/ipm-install.sh"
  eq "ipmcheck refusal (no unit): nothing ran" "$(ls "$SHIMLOG" | grep -c -e ipmcheck-env -e iris-calls)" 0
  eq "ipmcheck refusal (no unit): the export is gone" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | grep -c ipmcheck)" 0
}

# --- overviewunit (Story 14.1: the real release/security-overview.sh against a stub ci/iris.sh) ---

# ovw_tree: a temporary tree that holds the real unit, a stub docker/tests/test-security-overview.sh and a stub ci/iris.sh. The stub logs each call
# ("<arguments> tag=<run tag> lock=<lock folder>") in calls.log, and answers a live step with live.rc and live.out and a class step with class.rc and
# class.out; a teardown answers 0.
ovw_tree() {
  T=$tmp/ovwunit
  rm -rf "$T"
  mkdir -p "$T/release" "$T/ci" "$T/docker/tests" "$T/locks"
  cp "$root/release/security-overview.sh" "$T/release/security-overview.sh"
  : > "$T/docker/tests/test-security-overview.sh"
  cat > "$T/ci/iris.sh" << 'EOF'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")/.." && pwd -P)
echo "$* tag=${OCUTALON_RUN_TAG:-} lock=${OCUTALON_LOCK_DIR:-}" >> "$here/calls.log"
case ${1:-} in
  live | class)
    if [ -f "$here/$1.out" ]; then cat "$here/$1.out"; fi
    exit "$(cat "$here/$1.rc")"
    ;;
  teardown) exit 0 ;;
esac
exit 9
EOF
}

# ovw_run <live exit> <live output> <class exit> <class output> [argument]: runs the unit with the caller's run tag "base"; sets out, rc and calls
# (the calls of the stub in order, without their tags).
ovw_run() {
  local live_rc=$1 live_out=$2 class_rc=$3 class_out=$4
  shift 4
  rm -f "$T/calls.log"
  printf '%s' "$live_rc" > "$T/live.rc"
  printf '%s\n' "$live_out" > "$T/live.out"
  printf '%s' "$class_rc" > "$T/class.rc"
  printf '%s\n' "$class_out" > "$T/class.out"
  out=$(cd "$T" && OCUTALON_LOCK_DIR=$T/locks OCUTALON_RUN_TAG=base "$BASH" release/security-overview.sh "$@" < /dev/null 2>&1)
  rc=$?
  calls=$(sed 's/ tag=.*//' "$T/calls.log" 2> /dev/null | tr '\n' '|')
}

t_overviewunit() {
  local tags
  ovw_tree
  # a pass: the live step, then the class step, then the teardown; one run tag of the caller's tag and -ovw-<pid> on all three
  ovw_run 0 "PASS the generated sections equal a fresh generation" 0 "CLASS OcuTalon.Test.Install.SecurityOverview passed"
  eq "unit pass: exit" "$rc" 0
  has "unit pass: the line" "$out" "PASS overview "
  eq "unit pass: the calls" "$calls" "live security-overview|class OcuTalon.Test.Install.SecurityOverview|teardown|"
  tags=$(sed 's/.* tag=\([^ ]*\) .*/\1/' "$T/calls.log" | sort -u)
  eq "unit pass: one run tag for the three calls, the caller's plus -ovw-<pid>" "$(printf '%s\n' "$tags" | grep -Ec '^base-ovw-[0-9]+$')" 1
  eq "unit pass: a single tag" "$(printf '%s\n' "$tags" | wc -l | tr -d ' ')" 1
  eq "unit pass: the lane lock folder reaches every call" "$(sed 's/.* lock=//' "$T/calls.log" | sort -u)" "$T/locks"
  # --write reaches the live step and no other call
  ovw_run 0 "PASS wrote the overview" 0 "CLASS OcuTalon.Test.Install.SecurityOverview passed" --write
  eq "unit --write: exit" "$rc" 0
  eq "unit --write: the calls" "$calls" "live security-overview --write|class OcuTalon.Test.Install.SecurityOverview|teardown|"
  # a bad argument is refused before any call
  ovw_run 0 "" 0 "" --bogus
  eq "unit bad argument: exit" "$rc" 2
  eq "unit bad argument: no call" "$calls" ""
  # a busy lane lock in the live step: WAIT and exit 75, the class step never runs, the teardown does
  ovw_run 75 "LOCK busy: throwaway-iris is held by someone" 0 "CLASS OcuTalon.Test.Install.SecurityOverview passed"
  eq "unit busy: exit" "$rc" 75
  has "unit busy: the line" "$out" "WAIT overview "
  lacks "unit busy: no FAIL line" "$out" "FAIL overview"
  eq "unit busy: the calls" "$calls" "live security-overview|teardown|"
  # a drift in the live step: FAIL with the first DRIFT line, exit 1, no class step, the teardown runs
  ovw_run 1 "$(printf '%s\n' 'DRIFT tool recent_activity' 'FAIL the generated sections differ from a fresh generation')" 0 "CLASS OcuTalon.Test.Install.SecurityOverview passed"
  eq "unit drift: exit" "$rc" 1
  has "unit drift: the line" "$out" "FAIL overview DRIFT tool recent_activity"
  eq "unit drift: the calls" "$calls" "live security-overview|teardown|"
  # a failure in the live step with no DRIFT line: the first FAIL line
  ovw_run 1 "FAIL the first start did not end ready within 400 s" 0 "CLASS OcuTalon.Test.Install.SecurityOverview passed"
  eq "unit live failure: exit" "$rc" 1
  has "unit live failure: the line" "$out" "FAIL overview FAIL the first start did not end ready within 400 s"
  eq "unit live failure: the calls" "$calls" "live security-overview|teardown|"
  # a failed class step: FAIL with its CLASS line, exit 1, the teardown runs
  ovw_run 0 "PASS the generated sections equal a fresh generation" 1 "CLASS OcuTalon.Test.Install.SecurityOverview failed 6.25s"
  eq "unit class failure: exit" "$rc" 1
  has "unit class failure: the line" "$out" "FAIL overview CLASS OcuTalon.Test.Install.SecurityOverview failed 6.25s"
  eq "unit class failure: the calls" "$calls" "live security-overview|class OcuTalon.Test.Install.SecurityOverview|teardown|"
  # a failed step with no line to quote still fails with its exit code
  ovw_run 3 "" 0 ""
  eq "unit silent failure: exit" "$rc" 1
  has "unit silent failure: the line" "$out" "FAIL overview a step ended with exit 3"
  eq "unit silent failure: the calls" "$calls" "live security-overview|teardown|"
  # without a caller tag the run tag is ovw-<pid>
  rm -f "$T/calls.log"
  printf '0' > "$T/live.rc"
  printf '0' > "$T/class.rc"
  (cd "$T" && env -u OCUTALON_RUN_TAG "$BASH" release/security-overview.sh < /dev/null > /dev/null 2>&1)
  eq "unit without a caller tag: the run tag" "$(sed 's/.* tag=\([^ ]*\) .*/\1/' "$T/calls.log" | sort -u | grep -Ec '^ovw-[0-9]+$')" 1
  rm -rf "$T"
}

# --- overviewdrift (Story 14.1: the readers of docker/tests/lib-security-overview.sh) ---

# ovw_doc <recent_activity classification> <tools heading> <fix kind name> <privilege cell> [<extra tool row>]: an overview with hand-written lines
# and the three marker pairs, the tools region with two tool rows (and the extra row after them).
ovw_doc() {
  printf '%s\n' '# OcuTalon security overview' 'Hand-written text.'
  printf '%s\n' '<!-- BEGIN GENERATED tools: written by OcuTalon.Install.SecurityOverview, do not edit -->' "$2" '' \
    '| Tool | Classification |' '| --- | --- |' '| `list_reminders` | safe |' "| \`recent_activity\` | $1 |"
  if [ -n "${5:-}" ]; then printf '%s\n' "$5"; fi
  printf '%s\n' '<!-- END GENERATED tools -->' 'More hand-written text.'
  printf '%s\n' '<!-- BEGIN GENERATED fix-kinds: written by OcuTalon.Install.SecurityOverview, do not edit -->' '## Fix kinds' '' \
    '| Class | Name |' '| --- | --- |' "| \`OcuTalon.Fix.Kind.RepairResend\` | \`$3\` |" '<!-- END GENERATED fix-kinds -->'
  printf '%s\n' '<!-- BEGIN GENERATED privileges: written by OcuTalon.Install.SecurityOverview, do not edit -->' '## Privileges' '' \
    '| Role | Resource | Permission |' '| --- | --- | --- |' "| \`OcuTalonServiceRole\` | \`%Ens_MessageResend\` | $4 |" '<!-- END GENERATED privileges -->'
}

# ovw_drift <committed file> <regenerated file>: the output of drift (DRIFT lines and diffs) for the two files.
ovw_drift() {
  (
    tmp=$T/work
    mkdir -p "$tmp"
    . "$root/docker/tests/lib-security-overview.sh"
    drift "$1" "$2"
  )
}

t_overviewdrift() {
  local result
  T=$tmp/ovwdrift
  rm -rf "$T"
  mkdir -p "$T"
  ovw_doc safe '## Built-in tools' repair_resend U > "$T/committed.md"
  # equal files print nothing
  ovw_doc safe '## Built-in tools' repair_resend U > "$T/same.md"
  eq "equal files: nothing is printed" "$(ovw_drift "$T/committed.md" "$T/same.md")" ""
  # one tool row changed: one DRIFT line that names the tool, with the diff of the region
  ovw_doc risky '## Built-in tools' repair_resend U > "$T/row.md"
  result=$(ovw_drift "$T/committed.md" "$T/row.md")
  eq "a changed row: the DRIFT lines" "$(printf '%s\n' "$result" | grep '^DRIFT')" "DRIFT tool recent_activity"
  has "a changed row: the diff names the region" "$result" "--- tools committed"
  has "a changed row: the diff shows the old row" "$result" '-| `recent_activity` | safe |'
  has "a changed row: the diff shows the new row" "$result" '+| `recent_activity` | risky |'
  # a change outside the rows of the tools region
  ovw_doc safe '## Built-in tools (changed)' repair_resend U > "$T/outside.md"
  eq "a change outside the rows: the DRIFT lines" "$(ovw_drift "$T/committed.md" "$T/outside.md" | grep '^DRIFT')" "DRIFT tools"
  # a row added: the new tool is named
  ovw_doc safe '## Built-in tools' repair_resend U '| `add_note` | safe |' > "$T/added.md"
  eq "an added row: the DRIFT lines" "$(ovw_drift "$T/committed.md" "$T/added.md" | grep '^DRIFT')" "DRIFT tool add_note"
  # the fix kinds
  ovw_doc safe '## Built-in tools' repair_other U > "$T/fix.md"
  eq "a fix-kinds change: the DRIFT lines" "$(ovw_drift "$T/committed.md" "$T/fix.md" | grep '^DRIFT')" "DRIFT fix-kinds"
  # the privileges
  ovw_doc safe '## Built-in tools' repair_resend R > "$T/priv.md"
  eq "a privileges change: the DRIFT lines" "$(ovw_drift "$T/committed.md" "$T/priv.md" | grep '^DRIFT')" "DRIFT privileges"
  # a row removed, and a row renamed (a removed and an added row): each name is reported
  ovw_doc safe '## Built-in tools' repair_resend U '| `add_note` | safe |' > "$T/with-note.md"
  eq "a removed row: the DRIFT lines" "$(ovw_drift "$T/with-note.md" "$T/committed.md" | grep '^DRIFT')" "DRIFT tool add_note"
  ovw_doc safe '## Built-in tools' repair_resend U '| `add_memo` | safe |' > "$T/with-memo.md"
  eq "a renamed row: the DRIFT lines (the old and the new name)" "$(ovw_drift "$T/with-note.md" "$T/with-memo.md" | grep '^DRIFT')" "DRIFT tool add_memo
DRIFT tool add_note"
  # a change in hand-written text only is not drift
  ovw_doc safe '## Built-in tools' repair_resend U | sed 's/^Hand-written text\.$/Other hand-written text./' > "$T/hand.md"
  eq "a hand-written change: nothing is printed" "$(ovw_drift "$T/committed.md" "$T/hand.md")" ""
  rm -rf "$T"
}

# --- overviewdoc (Story 14.1, QA: the committed docs/security-overview.md and its CI claims) ---

# The privilege-limits paragraph (AD-24), word for word.
OVW_LIMITS="OcuTalon's production runs as IRIS's Interoperability system user, which holds \`%All\`. The service user is a privilege profile: the gate checks it before every tool call and the fix executor before every fix, but IRIS doesn't enforce it on the running code. The protections are the fixed tool inventory (no shell, no code, no data-changing SQL, tested), classification and approval, each fix kind's own validation, and the IRIS roles on the web and portal applications. Running tool code under the service user's own identity is deferred."
OVW_EXPERIENCE=_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md

# The MCP texts that the overview and the worked example (docs/mcp-jira-example.md) share, word for word (Story 22.6): the classification sentence, the Read-only
# sentence and the time-limits paragraph.
OVW_MCP_RISKY="An MCP tool that runs operating-system commands or arbitrary code must be classified Risky."
OVW_MCP_READONLY="A Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads."
OVW_MCP_LIMITS="OcuTalon's time limits for MCP servers are not hard deadlines. A server has 2 seconds to answer OcuTalon's check before a request offers its tools, and each listing of its tools, and 20 seconds to answer a tool call. Each limit applies to each wait for data and starts again whenever the server sends some, so a slow server can hold a request longer: in a test against a server that sent one byte a second, the 2-second check took 31 seconds and a 20-second call 36 seconds. A server that stops answering in the middle of a request, after its check passed, holds that request until it closes the connection."
OVW_MCP_EXAMPLE=docs/mcp-jira-example.md
OVW_MCP_DEMOOFF="MCP servers are off on the online demo: nobody can add one there, and OcuTalon reaches none."
OVW_MCP_DATA="- In calls to the MCP servers an admin has added, never on the online demo: a check that the server answers, the list of its tools, and each tool call with its arguments, which can hold content that OcuTalon read. The results come back as untrusted content."
OVW_MCP_AUDIT='- `MCP`: a server added or removed, or a tool called or refused;'
OVW_MCP_OPENING="On a local or IPM install, an admin can add MCP servers, and their tools become OcuTalon's tools under the same gate, approval and audit as the built-in ones."
OVW_MCP_PAIRING="Pairing, MCP and Tool entries are written only by the features that pair a chat, add or remove an MCP server, call an MCP tool, or classify an MCP tool, so a release without those features writes none of them."

# ovw_mcp_example_lines: the ruled lines of the worked example (how to classify a tool, how OcuTalon governs MCP tools, how to add a server), one per line, each pinned word for
# word as a whole line (the classification table's rows, the Read-only rule, the refusal line, the governance bullets and the line that opens the Add server step).
ovw_mcp_example_lines() {
  cat << 'EOF'
| `search_issues` | searches tickets | Read-only |
| `get_issue` | reads one ticket | Read-only |
| `create_issue` | creates a ticket | Risky |
| `update_issue` | changes a ticket | Risky |
| `add_comment` | comments on a ticket | Risky |
Classify a tool Read-only only when it reads and changes nothing.
If the server offers a tool with the same name as one of OcuTalon's own tools, or one named `call_mcp_tool`, OcuTalon refuses it: the Tools table shows "Refused: a built-in tool has this name", admins get a notice, and the tool is never offered or run.
- Only admins add or remove a server or classify its tools, only from the settings page.
- A new tool, and a tool whose description or inputs changed, is Unclassified, which counts as risky. OcuTalon identifies a tool by its server and its name, and ignores MCP annotations such as `readOnlyHint`.
- Every call goes through one governed tool, `call_mcp_tool`, and passes the same gate as OcuTalon's built-in tools. Before every call, OcuTalon checks that the tool still has the name, description and inputs it was classified with, and runs nothing if it changed.
- In your own turns, a Read-only tool runs at once, and a Risky or Unclassified tool waits for your approval. In a turn that holds content that didn't come from you, such as an email or an MCP tool's result, only Read-only tools run: any other call is denied, and no approval request is raised.
- A tool's results are untrusted content: they can never approve, classify, change a setting or add a server.
- Each call of a server's tool that runs writes an audit entry with the server, the tool and the outcome, never its arguments or its result, and shows as a step in Visual Trace.
In Settings > Tools and MCP servers, fill in the fields under **Add server**, then press the **Add server** button:
EOF
}

# ovw_section <file> <title>: the lines under the "## <title>" heading, up to the next "## " heading.
ovw_section() { awk -v h="## $2" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$1"; }

# ovw_code_value <sed expression> <file under the repository root>: the numbers that the expression prints from the code, one per line.
ovw_code_value() { sed -n "$1" "$root/$2"; }

# ovw_phrases <file> <section title> <phrase>...: one line for each phrase that the section does not hold. A phrase counts only where no
# letter or digit comes right before it, so "17 days" does not hold "7 days".
ovw_phrases() {
  local f=$1 title=$2 sec p re
  shift 2
  sec=$(ovw_section "$f" "$title")
  for p in "$@"; do
    re=$(printf '%s' "$p" | sed 's/[][\\.*^$(){}+?|]/\\&/g')
    printf '%s\n' "$sec" | grep -qE -e "(^|[^0-9A-Za-z])$re" || echo "the $title section lacks '$p'"
  done
}

# ovw_text_problems <file>: one line per problem of a public text file: a character outside ASCII, a machine path.
ovw_text_problems() {
  local n
  n=$(LC_ALL=C grep -c '[^[:print:][:space:]]' "$1")
  [ "$n" -eq 0 ] || echo "$n line(s) with a character outside ASCII"
  n=$(grep -cE '(/Us''ers/|/ho''me/|/pri''vate/|/t''mp/|[A-Za-z]:\\)' "$1")
  [ "$n" -eq 0 ] || echo "$n line(s) with a machine path"
}

# ovw_mcp_shared_problems <file> <scope> <line prefix>: one line for each shared MCP text that the file lacks, word for word, as a whole line (with the prefix before
# the sentence: "- " in the overview's rules, none in the worked example), and one for a line with "deadline" other than the time-limits paragraph or
# a line about the changed-tool replay path (which no text describes). scope is the section to read ("" for the whole file).
ovw_mcp_shared_problems() {
  local f=$1 title=$2 prefix=$3 sec
  if [ -n "$title" ]; then sec=$(ovw_section "$f" "$title"); else sec=$(cat "$f"); fi
  printf '%s\n' "$sec" | grep -qxF -e "$prefix$OVW_MCP_RISKY" || echo "the MCP text lacks the classification sentence word for word"
  printf '%s\n' "$sec" | grep -qxF -e "$prefix$OVW_MCP_READONLY" || echo "the MCP text lacks the Read-only sentence word for word"
  printf '%s\n' "$sec" | grep -qxF -e "$OVW_MCP_LIMITS" || echo "the MCP text lacks the time-limits paragraph as one whole line"
  grep -iF -e deadline "$f" | grep -vxF -e "$OVW_MCP_LIMITS" | grep -q . && echo "a line other than the time-limits paragraph mentions a deadline"
  grep -qE 'replayToolChanged|after this request was made|needs a new approval' "$f" && echo "a line describes the changed-tool replay path"
  return 0
}

# ovw_doc_problems <file>: one line per problem of the overview, nothing for a good file. The frame: the title line, each marker once and in
# order, ASCII only, no machine path, no URL or address. The hand-written sections (Story 14.2): no placeholder, the privilege-limits paragraph
# under its heading, the kept-OCUORDERS sentence, and the numbers and audit types of the code. The MCP tools section (Story 22.6): no sentence that says the release
# can't connect, a link to the worked example, and the shared texts; the Data section holds no "this release can't make".
ovw_doc_problems() {
  local f=$1 key b e n prev=0 owner='written by OcuTalon.Install.SecurityOverview, do not edit'
  local kept v hours t
  [ "$(sed -n 1p "$f")" = '# OcuTalon security overview' ] || echo "the first line is not the title"
  for key in tools fix-kinds privileges; do
    b=$(grep -nxF "<!-- BEGIN GENERATED $key: $owner -->" "$f" | cut -d: -f1)
    e=$(grep -nxF "<!-- END GENERATED $key -->" "$f" | cut -d: -f1)
    if [ -z "$b" ] || [ -z "$e" ] || [ "$(printf '%s\n' "$b" | grep -c .)" -ne 1 ] || [ "$(printf '%s\n' "$e" | grep -c .)" -ne 1 ]; then
      echo "the $key markers are not there once each"
      continue
    fi
    if [ "$b" -le "$prev" ] || [ "$e" -le "$b" ]; then echo "the $key markers are out of order"; fi
    prev=$e
  done
  ovw_text_problems "$f"
  n=$(grep -cE '(:/''/|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' "$f")
  [ "$n" -eq 0 ] || echo "$n line(s) with a URL or address"
  n=$(grep -c 'HAND-WRITTEN' "$f")
  [ "$n" -eq 0 ] || echo "a hand-written placeholder remains"
  ovw_section "$f" 'Limits of the privilege check' | grep -qxF -e "$OVW_LIMITS" || echo "the privilege-limits paragraph is not there word for word"
  kept=$(sed -n 's/^.*"\(OcuTalon left the OCUORDERS namespace[^"]*\)".*$/\1/p' "$root/$OVW_EXPERIENCE" | head -n 1)
  if [ -z "$kept" ]; then
    echo "EXPERIENCE.md has no kept-OCUORDERS sentence (the extraction found none)"
  elif ! grep -qF -e "$kept" "$f"; then
    echo "the kept-OCUORDERS sentence is not there word for word"
  fi
  ovw_section "$f" 'MCP tools' | grep -qE -e "can't connect to MCP servers|When a release adds MCP support" && echo "the MCP tools section still says that the release can't connect to MCP servers"
  case $(ovw_section "$f" 'MCP tools' | grep -m 1 .) in
    "$OVW_MCP_OPENING"*) ;;
    *) echo "the MCP tools section does not open with the sentence that an admin can add MCP servers on a local or IPM install" ;;
  esac
  ovw_section "$f" 'MCP tools' | grep -qF -e '](mcp-jira-example.md)' || echo "the MCP tools section does not link the worked example"
  ovw_section "$f" 'Data' | grep -qiF -e "this release can't make" && echo "the Data section still says that MCP calls are ones this release can't make"
  ovw_mcp_shared_problems "$f" 'MCP tools' '- '
  ovw_section "$f" 'MCP tools' | grep -qF -e "$OVW_MCP_DEMOOFF" || echo "the MCP tools section lacks the sentence that says MCP is off on the online demo"
  ovw_section "$f" 'Data' | grep -qxF -e "$OVW_MCP_DATA" || echo "the Data section lacks the MCP bullet word for word"
  ovw_section "$f" 'Approval and audit' | grep -qxF -e "$OVW_MCP_AUDIT" || echo "the Approval and audit section lacks the MCP audit line word for word"
  ovw_section "$f" 'Approval and audit' | grep -qF -e "$OVW_MCP_PAIRING" || echo "the Approval and audit section lacks the Pairing, MCP and Tool sentence word for word"
  v=$(ovw_code_value 's/^Parameter EXPIRYSECONDS = \([0-9][0-9]*\);.*$/\1/p' src/bridge/cls/OcuTalon/Bridge/Approval.cls)
  if [ -z "$v" ]; then
    echo "the code has no EXPIRYSECONDS"
  else
    hours=$((v / 3600))
    ovw_phrases "$f" 'Approval and audit' "$hours hours"
  fi
  t=$(ovw_code_value 's/^Parameter TYPES = "\([A-Za-z,]*\)";.*$/\1/p' src/bridge/cls/OcuTalon/Bridge/Audit.cls)
  if [ -z "$t" ]; then
    echo "the code has no audit TYPES"
  else
    for v in $(printf '%s' "$t" | tr ',' ' '); do ovw_phrases "$f" 'Approval and audit' "\`$v\`"; done
  fi
  v=$(ovw_code_value 's/^.*"NumberOfDaysToKeep": \([0-9][0-9]*\).*$/\1/p; s/^.*"DaysToKeep": \([0-9][0-9]*\).*$/\1/p' src/ocutalon/cls/OcuTalon/Install/Step/Retention.cls | sort -un)
  if [ -z "$v" ]; then echo "the code has no day counts"; fi
  for n in $v; do ovw_phrases "$f" 'Data' "$n days"; done
  v=$(ovw_code_value 's/^Parameter DEFAULTLIMIT = \([0-9][0-9]*\);.*$/\1/p' src/ocutalon/cls/OcuTalon/Core/Allowance.cls)
  if [ -z "$v" ]; then echo "the code has no DEFAULTLIMIT"; else ovw_phrases "$f" 'Online demo' "$v messages"; fi
  v=$(ovw_code_value 's/^Parameter EMAILLIMIT = \([0-9][0-9]*\);.*$/\1/p' src/ocutalon/cls/OcuTalon/Core/Allowance.cls)
  if [ -z "$v" ]; then echo "the code has no EMAILLIMIT"; else ovw_phrases "$f" 'Online demo' "$v simulated incoming emails"; fi
  v=$(ovw_code_value 's/^Parameter ADDRESSLIMITSEED = \([0-9][0-9]*\);.*$/\1/p' src/ocutalon/cls/OcuTalon/Data/Setting.cls)
  if [ -z "$v" ]; then echo "the code has no ADDRESSLIMITSEED"; else ovw_phrases "$f" 'Online demo' "$v new sessions"; fi
  # QA (Story 14.2): the five hand-written headings once each and in order; the V1 sentence (U-223) and the closing sentence of the demo section
  # (U-224).
  n=$(grep -nxE '## (Limits of the privilege check|Approval and audit|Data|MCP tools|Online demo)' "$f" | sed 's/^[0-9]*:## //' | tr '\n' '|')
  [ "$n" = 'Limits of the privilege check|Approval and audit|Data|MCP tools|Online demo|' ] || echo "the five hand-written headings are not there once each, in order"
  ovw_section "$f" 'Data' | grep -qF -e 'no scheduled purge removes them' || echo "the Data section lacks the no-scheduled-purge sentence"
  ovw_section "$f" 'Online demo' | grep -qxF -e 'Each protection listed here is checked against the running demo before every release.' || echo "the Online demo section lacks the checked-before-every-release sentence"
  return 0
}

# The approval sentence of the worked example's third step (Story 21.10, D3), and the catalog entry whose first and last lines its two quoted strings are.
OVW_MCP_APPROVAL='The chat shows an approval request that reads "Run add_comment on Jira", says why it waits, lists each of its inputs on a line of its own and ends with "No dry run is available for this tool. Approving runs exactly this call once."'
OVW_MCP_CATALOG=src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls

# mcp_approval_problems <file> [<catalog class>]: one line per problem of the approval sentence of the worked example: it is not in the file exactly once, or the
# catalog's toolCall.requestOnServer text (the Entries block of the class, whose lines are joined by \n) has a first line that, with {tool} add_comment and {server} Jira, is not
# "Run add_comment on Jira", or a last line that is not "No dry run is available for this tool. Approving runs exactly this call once.".
mcp_approval_problems() {
  local f=$1 catalog=${2:-} text first last
  [ -n "$catalog" ] || catalog=$OVW_MCP_CATALOG
  [ "$(grep -cF -e "$OVW_MCP_APPROVAL" "$f")" -eq 1 ] || echo "the example lacks the approval sentence of step 3 exactly once"
  text=$(awk '/^ "toolCall.requestOnServer": \{/ { on = 1; next } on && /^  "text": "/ { sub(/^  "text": "/, ""); sub(/",$/, ""); print; exit }' "$catalog")
  first=${text%%\\n*}
  last=${text##*\\n}
  first=${first//\{tool\}/add_comment}
  first=${first//\{server\}/Jira}
  [ "$first" = 'Run add_comment on Jira' ] || echo "the catalog's first line of the tool call request is not the example's first quoted string"
  [ "$last" = 'No dry run is available for this tool. Approving runs exactly this call once.' ] || echo "the catalog's last line of the tool call request is not the example's last quoted string"
}

# mcp_doc_problems <file> [<catalog class>]: one line per problem of the worked example (Story 22.6), nothing for a good file: its title, ASCII only and no machine path, an address
# only on example.com (a secret:// reference is no address), the shared texts word for word and no other "deadline" line, the lines of ovw_mcp_example_lines word for
# word, no text about the changed-tool replay path or source polls, the sentence that says MCP is off on the online demo, the expiry sentence and the link to the
# overview's MCP section.
mcp_doc_problems() {
  local f=$1 url host v line n=0
  [ -f "$f" ] || { echo "the worked example is not at $OVW_MCP_EXAMPLE"; return 0; }
  [ "$(sed -n 1p "$f")" = '# A Jira MCP server, step by step' ] || echo "the first line is not the title"
  ovw_text_problems "$f"
  for url in $(grep -oE 'https?:/''/[^/ )`]*' "$f"); do
    host=${url#*:/''/}
    host=${host%%:*}
    case $host in
      example.com|*.example.com) ;;
      *) echo "an address is not on example.com" ;;
    esac
  done
  ovw_mcp_shared_problems "$f" '' ''
  while IFS= read -r line; do
    n=$((n + 1))
    grep -qxF -e "$line" "$f" || echo "the example lacks ruled line $n of its classification and governance text word for word"
  done << EOF
$(ovw_mcp_example_lines)
EOF
  grep -qiF -e 'source poll' "$f" && echo "a line mentions a source poll"
  grep -qF -e "$OVW_MCP_DEMOOFF" "$f" || echo "the example lacks the sentence that says MCP is off on the online demo"
  v=$(ovw_code_value 's/^Parameter EXPIRYSECONDS = \([0-9][0-9]*\);.*$/\1/p' src/bridge/cls/OcuTalon/Bridge/Approval.cls)
  if [ -z "$v" ]; then
    echo "the code has no EXPIRYSECONDS"
  else
    grep -qF -e "A request that nobody answers within $((v / 3600)) hours expires." "$f" || echo "the example lacks the sentence that a request expires after $((v / 3600)) hours"
  fi
  grep -qF -e '](security-overview.md#mcp-tools)' "$f" || echo "the example does not link the overview's MCP tools section"
  mcp_approval_problems "$f" "${2:-}"
  return 0
}

# ovw_ci_claims: what ci/units.sh says about the overview, one line per group and two for the unit (a subshell, so no variable of units.sh leaks).
ovw_ci_claims() {
  (
    . "$root/ci/units.sh"
    for grp in $IRIS_GROUPS; do
      pattern=$(group_input_pattern "$grp")
      printf '%s:' "$grp"
      if printf '%s\n' docs/security-overview.md | grep -qE "$pattern"; then printf 'claimed'; else printf 'NOT-claimed'; fi
      if printf '%s\n' docs/security-overview.md.bak docs/other.md | grep -qE "$pattern"; then printf ' and-lookalike\n'; else printf ' lookalike-free\n'; fi
    done
    if group_units shards-5 | grep -qw 'live:security-overview'; then echo "shards-5 holds live:security-overview"; else echo "shards-5 LACKS live:security-overview"; fi
    if printf '%s\n' $NO_WEB_BUNDLE_UNITS | grep -qx 'live:security-overview'; then echo "NO_WEB_BUNDLE_UNITS holds live:security-overview"; else echo "NO_WEB_BUNDLE_UNITS LACKS live:security-overview"; fi
  )
}

t_overviewdoc() {
  local doc=$root/docs/security-overview.md ex=$root/$OVW_MCP_EXAMPLE d=$tmp/ovwdoc grp want
  rm -rf "$d"
  mkdir -p "$d"
  eq "the committed overview has a good frame" "$(ovw_doc_problems "$doc")" ""
  eq "the committed worked example is good" "$(mcp_doc_problems "$ex")" ""
  # controls: the checker finds each kind of fault in a copy of the committed file
  sed 's/^# OcuTalon security overview$/# Overview/' "$doc" > "$d/title.md"
  eq "control: a changed title" "$(ovw_doc_problems "$d/title.md")" "the first line is not the title"
  sed 's/^<!-- BEGIN GENERATED fix-kinds: .*$/<!-- BEGIN GENERATED fix-kinds -->/' "$doc" > "$d/begin.md"
  eq "control: a begin marker without the owner text" "$(ovw_doc_problems "$d/begin.md")" "the fix-kinds markers are not there once each"
  { cat "$doc"; echo '<!-- END GENERATED tools -->'; } > "$d/twice.md"
  eq "control: a repeated end marker" "$(ovw_doc_problems "$d/twice.md")" "the tools markers are not there once each"
  sed 's/^<!-- END GENERATED tools -->$/<!-- END GENERATED TOOLS -->/' "$doc" > "$d/gone.md"
  eq "control: a missing end marker" "$(ovw_doc_problems "$d/gone.md")" "the tools markers are not there once each"
  awk '/^<!-- BEGIN GENERATED fix-kinds:/ { hold = 1 } hold { buf = buf $0 "\n"; if ($0 ~ /^<!-- END GENERATED fix-kinds -->$/) { hold = 0; held = 1 } ; next } { print } /^<!-- END GENERATED privileges -->$/ && held { printf "%s", buf }' "$doc" > "$d/order.md"
  eq "control: the fix-kinds region moved after the privileges region" "$(ovw_doc_problems "$d/order.md")" "the privileges markers are out of order"
  { cat "$doc"; printf 'caf\303\251\n'; } > "$d/ascii.md"
  eq "control: a non-ASCII byte" "$(ovw_doc_problems "$d/ascii.md")" "1 line(s) with a character outside ASCII"
  { cat "$doc"; echo 'See /Us''ers/someone/git/x'; } > "$d/path.md"
  eq "control: a machine path" "$(ovw_doc_problems "$d/path.md")" "1 line(s) with a machine path"
  # controls of the hand-written sections (Story 14.2): each is a copy of the committed file with one fault and yields its own problem line
  { cat "$doc"; echo '<!-- HAND-WRITTEN (Story 14.2) -->'; } > "$d/placeholder.md"
  eq "control: a placeholder" "$(ovw_doc_problems "$d/placeholder.md")" "a hand-written placeholder remains"
  sed 's/which holds `%All`\./which holds %All./' "$doc" > "$d/ticks.md"
  eq "control: the privilege-limits paragraph without its backticks" "$(ovw_doc_problems "$d/ticks.md")" "the privilege-limits paragraph is not there word for word"
  { grep -vxF -e "$OVW_LIMITS" "$doc"; printf '%s\n' "$OVW_LIMITS"; } > "$d/outside.md"
  eq "control: the privilege-limits paragraph outside its section" "$(ovw_doc_problems "$d/outside.md")" "the privilege-limits paragraph is not there word for word"
  sed 's/OcuTalon left the OCUORDERS namespace in place because/OcuTalon left the OCUORDERS namespace in place as/' "$doc" > "$d/kept.md"
  eq "control: a word of the kept sentence" "$(ovw_doc_problems "$d/kept.md")" "the kept-OCUORDERS sentence is not there word for word"
  # controls of the MCP tools section and the Data section (Story 22.6): each is a copy of the committed overview with one fault and yields its own problem line
  awk '{ print } $0 == "## MCP tools" { print ""; print "This release can'"'"'t connect to MCP servers." }' "$doc" > "$d/mcp.md"
  eq "control: the can't-connect sentence put back" "$(ovw_doc_problems "$d/mcp.md")" "the MCP tools section still says that the release can't connect to MCP servers
the MCP tools section does not open with the sentence that an admin can add MCP servers on a local or IPM install"
  sed 's/^On a local or IPM install, an admin can add MCP servers, and their tools become OcuTalon'"'"'s tools under the same gate, approval and audit as the built-in ones\. //' "$doc" > "$d/opening.md"
  eq "control: the opening sentence removed" "$(ovw_doc_problems "$d/opening.md")" "the MCP tools section does not open with the sentence that an admin can add MCP servers on a local or IPM install"
  sed 's/ When a release adds MCP support, these rules apply:$//; s/^\(On a local or IPM install.*\)$/\1 When a release adds MCP support, these rules apply:/' "$doc" > "$d/frame.md"
  eq "control: the old rules sentence put back" "$(ovw_doc_problems "$d/frame.md")" "the MCP tools section still says that the release can't connect to MCP servers"
  sed 's/](mcp-jira-example\.md)/](mcp-jira.md)/' "$doc" > "$d/link.md"
  eq "control: the link to the worked example removed" "$(ovw_doc_problems "$d/link.md")" "the MCP tools section does not link the worked example"
  sed 's/^- An MCP tool that runs operating-system commands or arbitrary code must be classified Risky\./- An MCP tool that runs operating-system commands or arbitrary code should be classified Risky./' "$doc" > "$d/risky.md"
  eq "control: a word of the classification sentence" "$(ovw_doc_problems "$d/risky.md")" "the MCP text lacks the classification sentence word for word"
  sed 's/classify a tool Read-only only when you trust/classify a tool Read-only only if you trust/' "$doc" > "$d/readonly.md"
  eq "control: a word of the Read-only sentence" "$(ovw_doc_problems "$d/readonly.md")" "the MCP text lacks the Read-only sentence word for word"
  sed 's/^OcuTalon'"'"'s time limits for MCP servers are not hard deadlines\. A server has 2 seconds/OcuTalon'"'"'s time limits for MCP servers are not hard deadlines. A server has 3 seconds/' "$doc" > "$d/limits.md"
  eq "control: the time-limits paragraph changed" "$(ovw_doc_problems "$d/limits.md")" "the MCP text lacks the time-limits paragraph as one whole line
a line other than the time-limits paragraph mentions a deadline"
  { cat "$doc"; echo 'The server has a hard deadline of 30 seconds.'; } > "$d/deadline.md"
  eq "control: a hard deadline line added" "$(ovw_doc_problems "$d/deadline.md")" "a line other than the time-limits paragraph mentions a deadline"
  { cat "$doc"; echo 'An approved request whose tool changed before it ran needs a new approval.'; } > "$d/replay.md"
  eq "control: a replay-path line added" "$(ovw_doc_problems "$d/replay.md")" "a line describes the changed-tool replay path"
  sed 's/^- In calls to the MCP servers an admin has added, never on the online demo: .*$/- In calls to configured MCP servers, which this release can'"'"'t make./' "$doc" > "$d/data.md"
  eq "control: the old Data bullet put back" "$(ovw_doc_problems "$d/data.md")" "the Data section still says that MCP calls are ones this release can't make
the Data section lacks the MCP bullet word for word"
  sed 's/MCP servers are off on the online demo: nobody can add one there/MCP servers are on the online demo: anybody can add one there/' "$doc" > "$d/demooff.md"
  eq "control: the demo sentence changed in the overview" "$(ovw_doc_problems "$d/demooff.md")" "the MCP tools section lacks the sentence that says MCP is off on the online demo"
  sed 's/^- In calls to the MCP servers an admin has added, never on the online demo: /- In calls to the MCP servers an admin has added: /' "$doc" > "$d/mcpdata.md"
  eq "control: the Data bullet changed" "$(ovw_doc_problems "$d/mcpdata.md")" "the Data section lacks the MCP bullet word for word"
  sed 's/^- `MCP`: a server added or removed, or a tool called or refused;$/- `MCP`: a server added or removed;/' "$doc" > "$d/mcpaudit.md"
  eq "control: the MCP audit line changed" "$(ovw_doc_problems "$d/mcpaudit.md")" "the Approval and audit section lacks the MCP audit line word for word"
  sed 's/ or classify an MCP tool, so a release without those features writes none of them\./, so a release without those features writes none of them./' "$doc" > "$d/pairing.md"
  eq "control: the Pairing, MCP and Tool sentence changed" "$(ovw_doc_problems "$d/pairing.md")" "the Approval and audit section lacks the Pairing, MCP and Tool sentence word for word"
  sed 's/^- It expires after 24 hours\./- It expires after 48 hours./' "$doc" > "$d/hours.md"
  eq "control: another expiry" "$(ovw_doc_problems "$d/hours.md")" "the Approval and audit section lacks '24 hours'"
  sed 's/^- `Tool`: /- Tool: /' "$doc" > "$d/type.md"
  eq "control: an audit type without backticks" "$(ovw_doc_problems "$d/type.md")" "the Approval and audit section lacks '\`Tool\`'"
  sed 's/^- heartbeat and background-check messages after 7 days;/- heartbeat and background-check messages after 8 days;/' "$doc" > "$d/days.md"
  eq "control: another message retention" "$(ovw_doc_problems "$d/days.md")" "the Data section lacks '7 days'"
  sed 's/^- heartbeat and background-check messages after 7 days;/- heartbeat and background-check messages after 17 days;/' "$doc" > "$d/days17.md"
  eq "control: a longer number that ends in the pinned one" "$(ovw_doc_problems "$d/days17.md")" "the Data section lacks '7 days'"
  sed 's/^- A per-session message allowance, a public setting shown on the splash: 50 messages/- A per-session message allowance, a public setting shown on the splash: 40 messages/' "$doc" > "$d/messages.md"
  eq "control: another message allowance" "$(ovw_doc_problems "$d/messages.md")" "the Online demo section lacks '50 messages'"
  sed 's/^- 20 simulated incoming emails/- 30 simulated incoming emails/' "$doc" > "$d/emails.md"
  eq "control: another email allowance" "$(ovw_doc_problems "$d/emails.md")" "the Online demo section lacks '20 simulated incoming emails'"
  sed 's/ after 90 days;/ after 60 days;/' "$doc" > "$d/days90.md"
  eq "control: another long retention" "$(ovw_doc_problems "$d/days90.md")" "the Data section lacks '90 days'"
  sed 's/ and no scheduled purge removes them\./ and a scheduled purge removes them./' "$doc" > "$d/purge.md"
  eq "control: the no-scheduled-purge sentence changed" "$(ovw_doc_problems "$d/purge.md")" "the Data section lacks the no-scheduled-purge sentence"
  sed 's/^Each protection listed here is checked against the running demo before every release\.$/Each protection listed here is checked against the running demo./' "$doc" > "$d/close.md"
  eq "control: the closing demo sentence changed" "$(ovw_doc_problems "$d/close.md")" "the Online demo section lacks the checked-before-every-release sentence"
  { cat "$doc"; printf '\n## Data\n'; } > "$d/heading.md"
  eq "control: a hand-written heading twice" "$(ovw_doc_problems "$d/heading.md")" "the five hand-written headings are not there once each, in order"
  sed 's/^- 5 new sessions/- 6 new sessions/' "$doc" > "$d/sessions.md"
  eq "control: another session allowance" "$(ovw_doc_problems "$d/sessions.md")" "the Online demo section lacks '5 new sessions'"
  { cat "$doc"; printf 'See %s\n' 'https:/''/example.org/x'; } > "$d/url.md"
  eq "control: a link" "$(ovw_doc_problems "$d/url.md")" "1 line(s) with a URL or address"
  { cat "$doc"; printf 'Host %s\n' '10.20.30.''40'; } > "$d/ip.md"
  eq "control: an address" "$(ovw_doc_problems "$d/ip.md")" "1 line(s) with a URL or address"
  # controls of the worked example (Story 22.6): a copy of the committed file with one fault yields its own problem line
  eq "control: the worked example is missing" "$(mcp_doc_problems "$d/none.md")" "the worked example is not at $OVW_MCP_EXAMPLE"
  sed 's/^# A Jira MCP server, step by step$/# A Jira server/' "$ex" > "$d/e-title.md"
  eq "control: the example's title changed" "$(mcp_doc_problems "$d/e-title.md")" "the first line is not the title"
  { cat "$ex"; printf 'caf\303\251\n'; } > "$d/e-ascii.md"
  eq "control: a non-ASCII byte in the example" "$(mcp_doc_problems "$d/e-ascii.md")" "1 line(s) with a character outside ASCII"
  { cat "$ex"; echo 'See /Us''ers/someone/git/x'; } > "$d/e-path.md"
  eq "control: a machine path in the example" "$(mcp_doc_problems "$d/e-path.md")" "1 line(s) with a machine path"
  sed 's/jira-mcp\.example\.com/jira-mcp.example.org/' "$ex" > "$d/e-host.md"
  eq "control: an address that is not on example.com" "$(mcp_doc_problems "$d/e-host.md")" "an address is not on example.com"
  sed 's/^An MCP tool that runs operating-system commands or arbitrary code must be classified Risky\./An MCP tool that runs operating-system commands or arbitrary code should be classified Risky./' "$ex" > "$d/e-risky.md"
  eq "control: a word of the classification sentence in the example" "$(mcp_doc_problems "$d/e-risky.md")" "the MCP text lacks the classification sentence word for word"
  sed 's/classify a tool Read-only only when you trust/classify a tool Read-only only if you trust/' "$ex" > "$d/e-readonly.md"
  eq "control: a word of the Read-only sentence in the example" "$(mcp_doc_problems "$d/e-readonly.md")" "the MCP text lacks the Read-only sentence word for word"
  sed 's/^OcuTalon'"'"'s time limits for MCP servers are not hard deadlines\. A server has 2 seconds/OcuTalon'"'"'s time limits for MCP servers are not hard deadlines. A server has 3 seconds/' "$ex" > "$d/e-limits.md"
  eq "control: the time-limits paragraph changed in the example" "$(mcp_doc_problems "$d/e-limits.md")" "the MCP text lacks the time-limits paragraph as one whole line
a line other than the time-limits paragraph mentions a deadline"
  { cat "$ex"; echo 'The server has a hard deadline of 30 seconds.'; } > "$d/e-deadline.md"
  eq "control: a hard deadline line in the example" "$(mcp_doc_problems "$d/e-deadline.md")" "a line other than the time-limits paragraph mentions a deadline"
  { cat "$ex"; echo 'The replay says mcp.replayToolChanged.'; } > "$d/e-replay.md"
  eq "control: a replay-path line in the example" "$(mcp_doc_problems "$d/e-replay.md")" "a line describes the changed-tool replay path"
  { cat "$ex"; echo 'Set a source poll to check the server.'; } > "$d/e-poll.md"
  eq "control: a source poll in the example" "$(mcp_doc_problems "$d/e-poll.md")" "a line mentions a source poll"
  sed 's/MCP servers are off on the online demo: nobody can add one there/MCP servers are on the online demo: anybody can add one there/' "$ex" > "$d/e-demo.md"
  eq "control: the demo sentence changed in the example" "$(mcp_doc_problems "$d/e-demo.md")" "the example lacks the sentence that says MCP is off on the online demo"
  sed 's/A request that nobody answers within 24 hours expires\./A request that nobody answers within 48 hours expires./' "$ex" > "$d/e-hours.md"
  eq "control: another expiry in the example" "$(mcp_doc_problems "$d/e-hours.md")" "the example lacks the sentence that a request expires after 24 hours"
  sed 's/^| `add_comment` | comments on a ticket | Risky |$/| `add_comment` | comments on a ticket | Read-only |/' "$ex" > "$d/e-row.md"
  eq "control: a table row's classification changed in the example" "$(mcp_doc_problems "$d/e-row.md")" "the example lacks ruled line 5 of its classification and governance text word for word"
  sed 's/, and runs nothing if it changed\.$/./' "$ex" > "$d/e-bullet.md"
  eq "control: a governance bullet shortened in the example" "$(mcp_doc_problems "$d/e-bullet.md")" "the example lacks ruled line 10 of its classification and governance text word for word"
  sed 's/^In Settings > Tools and MCP servers, fill in the fields under \*\*Add server\*\*, then press the \*\*Add server\*\* button:$/In Settings > Tools and MCP servers, press **Add server** and fill in:/' "$ex" > "$d/e-addstep.md"
  eq "control: the Add server step line put back to the old wording in the example" "$(mcp_doc_problems "$d/e-addstep.md")" "the example lacks ruled line 14 of its classification and governance text word for word"
  sed "s/^- Each call of a server's tool that runs writes/- Each call of a server's tool writes/" "$ex" > "$d/e-audit.md"
  eq "control: \"that runs\" dropped from the audit bullet in the example" "$(mcp_doc_problems "$d/e-audit.md")" "the example lacks ruled line 13 of its classification and governance text word for word"
  sed 's/](security-overview\.md#mcp-tools)/](security-overview.md)/' "$ex" > "$d/e-link.md"
  sed 's/reads "Run add_comment on Jira"/reads "Run add_comment on Jira Cloud"/' "$ex" > "$d/e-approval.md"
  eq "control: the example's first quoted string changed" "$(mcp_doc_problems "$d/e-approval.md")" "the example lacks the approval sentence of step 3 exactly once"
  sed 's/Approving runs exactly this call once\./Approving runs this call./' "$OVW_MCP_CATALOG" > "$d/catalog.cls"
  eq "control: a catalog copy with its last line changed" "$(mcp_doc_problems "$ex" "$d/catalog.cls")" "the catalog's last line of the tool call request is not the example's last quoted string"
  sed 's/"text": "Run {tool} on {server}\\nWhy/"text": "Run {tool} at {server}\\nWhy/' "$OVW_MCP_CATALOG" > "$d/catalog-first.cls"
  eq "control: a catalog copy with its first line changed" "$(mcp_doc_problems "$ex" "$d/catalog-first.cls")" "the catalog's first line of the tool call request is not the example's first quoted string"
  eq "control: the link to the overview removed from the example" "$(mcp_doc_problems "$d/e-link.md")" "the example does not link the overview's MCP tools section"
  # the CI claims (runner ruling 4): the file is an input of every group, a lookalike path is not, and the live unit sits in shards-5
  # (the expected lines follow IRIS_GROUPS, so a group added to the matrix is checked too)
  want=$(ovw_ci_claims)
  expect=$( (. "$root/ci/units.sh"; for grp in $IRIS_GROUPS; do echo "$grp:claimed lookalike-free"; done)
    echo "shards-5 holds live:security-overview"; echo "NO_WEB_BUNDLE_UNITS holds live:security-overview")
  eq "ci/units.sh: every group claims the overview, and the unit is placed" "$want" "$expect"
  rm -rf "$d"
}

# --- ipm (Story 11.17: the IPM artifact carries the built page) ---

# runs_d: the "docker run -d" lines of the case's shim log.
runs_d() { grep -E '^run -d ' "$SHIMLOG/docker.log" 2> /dev/null; }
count_runs() { runs_d | grep -c .; }
# dlog_line <pattern>: the line number of the first shim-log line that matches.
dlog_line() { grep -nE -e "$1" "$SHIMLOG/docker.log" | head -n 1 | cut -d: -f1; }
# sect <file> <title>: the lines of a record section.
sect() { awk -v t="$2" '$0 == t { f = 1; print; next } f && /^## / { exit } f { print }' "$1"; }
# state_get <key>: a value of rc1's state.
state_get() { sed -n "s/^$1=//p" "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" | tail -n 1; }
# ipm_expect <candidate sha> <bytes> <sha256> <content digest> <files> <namespace>: the golden section of a pass.
ipm_expect() {
  printf '%s\n' "## IPM artifact" "Result: pass" "Candidate: 1.0.0 rc1, release/1.0.0-rc1 at $1" \
    "Artifact: ocutalon-1.0.0.tgz, kept in the release state folder (1.0.0-rc1/ipm/), outside the repository; release.sh status prints its full path" \
    "Size: $2 bytes" "SHA-256: $3" \
    "Content SHA-256: $4 (over every file in the artifact; the same for every packaging of this candidate)" \
    "Packaged by: IPM 0.10.10, zpm \"package ocutalon -only\", in namespace $6 of a throwaway build 154 instance with no network" \
    "Web bundle: $5 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's" \
    "Published: no; publishing to the package registry is the author's own action, outside this sequence"
}
# ipm_fail_expect <candidate sha>: the section of a failure.
ipm_fail_expect() {
  printf '%s\n' "## IPM artifact" "Result: fail" "Candidate: 1.0.0 rc1, release/1.0.0-rc1 at $1" \
    "Published: no; publishing to the package registry is the author's own action, outside this sequence"
}
ZPM_ONE='%SYS zpm "enable -map -ns USER"
USER zpm "load -bypass-py-deps /tmp/ocutalon-pkg"
USER zpm "package ocutalon -only -path /tmp/ocutalon-ipm/ocutalon-1.0.0"
USER zpm "repo -name ocutalon-check -fs -depth 2 -path /tmp/ocutalon-check/"
USER zpm "repo -name ocutalon-check -list-modules"'
ZPM_TWO='%SYS zpm "enable -map -ns USER"
USER zpm "load -bypass-py-deps /tmp/ocutalon-pkg"
OCUTALON zpm "load -bypass-py-deps /tmp/ocutalon-pkg"
OCUTALON zpm "package ocutalon -only -path /tmp/ocutalon-ipm/ocutalon-1.0.0"
OCUTALON zpm "repo -name ocutalon-check -fs -depth 2 -path /tmp/ocutalon-check/"
OCUTALON zpm "repo -name ocutalon-check -list-modules"'

# bundle_diff <folder of the extracted artifact> <branch>: the bundle files of the branch that the folder lacks or holds with other bytes.
bundle_diff() {
  local f rel
  for f in $(git -C "$W" ls-tree -r --name-only "$2" -- src/ocutalon/csp); do
    rel=${f#src/ocutalon/csp/}
    cmp -s "$1/src/ocutalon/csp/$rel" <(git -C "$W" cat-file blob "$2:$f") || echo "$rel"
  done
}

# no_leftovers: no throwaway container and no lock of the run is left.
no_leftovers() {
  eq "$1: no throwaway container is left" "$(ls "$SHIMSTATE" | grep -c '^ct\.')" 0
  eq "$1: the lock is released" "$(ls "$C/locks" | wc -l | tr -d ' ')" 0
}

t_ipm() {
  local art bytes sha cdig c name x log
  . "$root/release/lib-release.sh"
  # the pass, with a module that runs once: today's module.xml without its MapAndStop invoke (Epic 15's two-run module is the next case)
  newcase
  if grep -q MapAndStop "$W/module.xml"; then
    grep -v MapAndStop "$W/module.xml" > "$W/module.xml.new"
    mv "$W/module.xml.new" "$W/module.xml"
    git -C "$W" commit -q -am "a module that runs once"
    git -C "$W" push -q origin "$INTEG"
    EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
  fi
  to_step ipm
  c=$(cand)
  rs '' next
  eq "ipm: exit" "$rc" 0
  art=$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz
  [ -f "$art" ] || {
    echo "  ipm: no artifact: $out"
    bad=1
    return 0
  }
  bytes=$(wc -c < "$art" | tr -d ' ')
  sha=$(sha256_file "$art")
  has "ipm: the PASS line" "$out" "PASS ipm ocutalon-1.0.0.tgz $bytes bytes sha256 $sha"
  has "ipm: the ARTIFACT line" "$out" "ARTIFACT $art"
  has "ipm: the next step" "$out" "NEXT ipmcheck"
  x=$C/x
  mkdir -p "$x"
  tar -xzf "$art" -C "$x"
  has "ipm: the module's name" "$(cat "$x/module.xml")" "<Name>ocutalon</Name>"
  has "ipm: the module's version" "$(cat "$x/module.xml")" "<Version>1.0.0</Version>"
  has "ipm: the FileCopy of the bundle" "$(cat "$x/module.xml")" '<FileCopy Name="src/ocutalon/csp/"'
  eq "ipm: the candidate tracks three bundle files" "$(git -C "$W" ls-tree -r --name-only release/1.0.0-rc1 -- src/ocutalon/csp | wc -l | tr -d ' ')" 3
  eq "ipm: every bundle file of the candidate is in the artifact, byte for byte" "$(bundle_diff "$x" release/1.0.0-rc1)" ""
  cdig=$(ipm_content_digest "$art")
  eq "ipm: the record's section" "$(sect "$(rec_file)" "## IPM artifact")" "$(ipm_expect "$c" "$bytes" "$sha" "$cdig" 3 USER)"
  lacks "ipm: the record names no local path" "$(cat "$(rec_file)")" "$tmp"
  name=$(state_get ipm_container)
  case $name in
    ocutalon-release-ipm-100-rc1-[0-9]*-[0-9]*) ;;
    *)
      echo "  ipm: the container's name is '$name'"
      bad=1
      ;;
  esac
  eq "ipm: one throwaway run" "$(count_runs)" 1
  eq "ipm: the throwaway has no network and is never pulled" "$(runs_d)" "run -d --pull never --network none --name $name ocutalon-iris-base:2026.3.0AI.154.0"
  log=$(cat "$SHIMLOG/docker.log")
  has "ipm: the container is removed with its volumes" "$log" "rm -f -v $name"
  [ "$(dlog_line '^run -d ')" -lt "$(dlog_line '^cp ')" ] && [ "$(dlog_line '^cp ')" -lt "$(dlog_line '^exec -u root [^ ]+ chmod -R a\+rX /tmp/ocutalon-pkg')" ] \
    && [ "$(dlog_line '^exec -u root [^ ]+ chmod -R a\+rX /tmp/ocutalon-pkg')" -lt "$(dlog_line '^exec -i [^ ]+ iris session')" ] \
    && [ "$(dlog_line '^exec -i [^ ]+ iris session')" -lt "$(dlog_line '^rm -f -v ')" ] || {
    echo "  ipm: the container calls are not in the order run, cp, chmod, session, rm"
    bad=1
  }
  eq "ipm: the zpm calls of a one-run package" "$(cat "$SHIMLOG/zpm.log")" "$ZPM_ONE"
  eq "ipm: the step makes no pull, push, login, save or export" "$(grep -cE '^(pull|push|login|save|export)' "$SHIMLOG/docker.log")" 0
  no_leftovers "ipm"
  eq "ipm: the tree copy is gone" "$(ls "$OCUTALON_RELEASE_STATE/1.0.0-rc1" | tr '\n' ' ')" "ipm ipm-section.md rows.tsv state.env "
  eq "ipm: the artifact is outside the repository" "$(git -C "$W" status --porcelain | grep -c 'tgz')" 0
  rs '' status
  has "ipm: status prints the artifact" "$out" "ARTIFACT $art $bytes $sha"
  # the sequence goes on to ipmcheck (the seed's stub unit) and push and never packs again; IA2: the real notes step and the stop routine keep the section
  rs '' next
  has "ipm: the ipmcheck step follows" "$out" "PASS ipmcheck "
  rs "$N" next
  eq "ipm: the push question follows (exit)" "$rc" 4
  has "ipm: the push question" "$out" "ASK push "
  has "ipm: the step's row" "$(cat "$(rec_file)")" "| ipm | pass | ocutalon-1.0.0.tgz, $bytes bytes, SHA-256 ${sha:0:12}; carries the candidate's web bundle; not published |"
  eq "ipm: the step does not run again" "$(count_runs)" 1
  rs "$Y" next
  has "ipm: push" "$out" "PASS push release/1.0.0-rc1"
  rs "$Y" next
  has "ipm: the real notes step ran" "$out" "PASS notes RESULT "
  has "ipm: the record was pushed" "$out" "PASS record pushed"
  eq "ipm: the section is byte for byte after the notes step and the stop routine" "$(sect "$(rec_file)" "## IPM artifact")" "$(ipm_expect "$c" "$bytes" "$sha" "$cdig" 3 USER)"
  eq "ipm: the committed record holds the section" "$(git -C "$W" show "HEAD:release/records/1.0.0/rc1.md" | awk '$0 == "## IPM artifact" { f = 1; print; next } f && /^## / { exit } f { print }')" "$(sect "$(rec_file)" "## IPM artifact")"
  rs '' status
  has "ipm: status still prints the artifact at the end" "$out" "ARTIFACT $art $bytes $sha"
  eq "ipm: still one throwaway run" "$(count_runs)" 1
  # a module that stops the first run (Epic 15's, today's module.xml): loaded in USER, then in OCUTALON, packaged there
  newcase
  if ! grep -q MapAndStop "$W/module.xml"; then
    awk '/<\/Module>/ { print "      <Invoke Class=\"OcuTalon.Install.Ipm\" Method=\"MapAndStop\" Phase=\"Initialize\" When=\"After\"/>" } { print }' "$W/module.xml" > "$W/module.xml.new"
    mv "$W/module.xml.new" "$W/module.xml"
    git -C "$W" commit -q -am "a module that stops the first run"
    git -C "$W" push -q origin "$INTEG"
    EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
  fi
  to_step ipm
  rs '' next
  eq "two-run: exit" "$rc" 0
  eq "two-run: the zpm calls" "$(cat "$SHIMLOG/zpm.log")" "$ZPM_TWO"
  has "two-run: the namespace packaged in" "$(cat "$(rec_file)")" "in namespace OCUTALON of a throwaway build 154 instance with no network"
  has "two-run: the artifact" "$out" "PASS ipm ocutalon-1.0.0.tgz "
  no_leftovers "two-run"
  # the shim's flag for the same module
  newcase
  flag ipm-mapandstop
  to_step ipm
  export IRIS_IMAGE=my-base:7
  rs '' next
  unset IRIS_IMAGE
  eq "two-run by flag: the zpm calls" "$(cat "$SHIMLOG/zpm.log")" "$ZPM_TWO"
  eq "IRIS_IMAGE names the base image of the throwaway" "$(runs_d | awk '{ print $NF }')" "my-base:7"
}

t_ipmfail() {
  local art c name i f before msg
  . "$root/release/lib-release.sh"
  # failures after the container started: the file is gone, the container too, no push question
  newcase
  to_step ipm
  c=$(cand)
  art=$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz
  for i in "ipm-load-fail|the package did not install: ERROR! planted install failure" \
    "ipm-iris-load-fail|the package did not install: IPM could not be loaded: ERROR #5001: planted IPM load failure" \
    "ipm-drop-csp|the artifact lacks the bundle file src/ocutalon/csp/main-FAKE.js" \
    "ipm-byte|the artifact holds a different src/ocutalon/csp/main-FAKE.js than the candidate" \
    "ipm-version|the artifact holds a module.xml that does not read version 1.0.0" \
    "ipm-empty-repo|the artifact is not listed by the IPM filesystem repository (it lists nothing for ocutalon 1.0.0)" \
    "ipm-not-running|the package did not install: the throwaway instance was not running after 0 s" \
    "ipm-run-fail|the package did not install: the throwaway instance could not be started" \
    "ipm-ocutalon-load-fail|the package did not install: ERROR! planted install failure in OCUTALON" \
    "ipm-package-fail|the package did not install: the package left no ocutalon-1.0.0.tgz: ERROR! planted package failure" \
    "ipm-kill-after-copy|the package did not install: the packaging ended without a result"; do
    f=${i%%|*}
    msg=${i#*|}
    # each iteration must write its own section: an earlier one's "Result: fail" is made stale first
    if [ -f "$(rec_file)" ]; then
      awk '$0 == "Result: fail" { $0 = "Result: stale" } { print }' "$(rec_file)" > "$C/rec.new" && cat "$C/rec.new" > "$(rec_file)"
    fi
    : > "$SHIMLOG/zpm.log"
    flag "$f"
    [ "$f" != ipm-not-running ] || export OCUTALON_RELEASE_IPM_WAIT=0
    rs "$N" next
    unset OCUTALON_RELEASE_IPM_WAIT
    unflag "$f"
    eq "$f: exit" "$rc" 1
    has "$f: the line" "$out" "FAIL ipm $msg"
    lacks "$f: no push question" "$out" "ASK push"
    eq "$f: no artifact file" "$([ -e "$art" ] && echo yes || echo no)" no
    name=$(state_get ipm_container)
    has "$f: the container is removed" "$(cat "$SHIMLOG/docker.log")" "rm -f -v $name"
    no_leftovers "$f"
    has "$f: the record's result" "$(cat "$(rec_file)")" "Result: failed at ipm: $msg"
    eq "$f: the record's section" "$(sect "$(rec_file)" "## IPM artifact")" "$(ipm_fail_expect "$c")"
    lacks "$f: the record names no local path" "$(cat "$(rec_file)")" "$tmp"
    case $f in
      ipm-load-fail) lacks "$f: no load in OCUTALON" "$(cat "$SHIMLOG/zpm.log")" "OCUTALON zpm" ;;
      ipm-ocutalon-load-fail)
        has "$f: loaded again in OCUTALON" "$(cat "$SHIMLOG/zpm.log")" 'OCUTALON zpm "load -bypass-py-deps /tmp/ocutalon-pkg"'
        lacks "$f: nothing packaged" "$(cat "$SHIMLOG/zpm.log")" 'zpm "package'
        ;;
    esac
    rs '' status
    has "$f: the sequence still waits at ipm" "$out" "STATE 1.0.0 rc1 next ipm"
    lacks "$f: no artifact line in the status" "$out" "ARTIFACT"
  done
  eq "the failed packagings each ran a throwaway" "$(count_runs)" 11
  eq "the install log is kept" "$([ -f "$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/run.log" ] && echo yes || echo no)" yes
  # a leftover under the recorded name goes at the next run, a bystander stays
  name=$(state_get ipm_container)
  mkdir -p "$SHIMSTATE/ct.$name/fs" "$SHIMSTATE/ct.bystander/fs"
  rs "$N" next
  eq "the re-run: exit" "$rc" 0
  has "the re-run packs" "$out" "PASS ipm ocutalon-1.0.0.tgz "
  eq "the recorded leftover is gone" "$([ -d "$SHIMSTATE/ct.$name" ] && echo yes || echo no)" no
  eq "a bystander is kept" "$([ -d "$SHIMSTATE/ct.bystander" ] && echo yes || echo no)" yes
  lacks "no removal of a bystander" "$(cat "$SHIMLOG/docker.log")" "rm -f -v bystander"
  eq "the re-run made a fresh throwaway" "$(count_runs)" 12
  eq "the record holds one section, from the latest attempt" "$(grep -c '^## IPM artifact' "$(rec_file)")" 1
  has "the section reads pass" "$(sect "$(rec_file)" "## IPM artifact")" "Result: pass"
  [ -f "$art" ] || {
    echo "  the re-run left no artifact"
    bad=1
  }
  # refusals before any container
  newcase
  to_step ipm
  c=$(cand)
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" cand_sha 0123456789abcdef0123456789abcdef01234567
  rs "$N" next
  eq "a tree that cannot be exported: exit" "$rc" 1
  has "a tree that cannot be exported: the line" "$out" "FAIL ipm the candidate's tree could not be exported"
  eq "a tree that cannot be exported: no container" "$(count_runs)" 0
  eq "a tree that cannot be exported: no section" "$(grep -c '^## IPM artifact' "$(rec_file)")" 0
  git -C "$W" checkout -q --detach release/1.0.0-rc1
  git -C "$W" rm -rq src/ocutalon/csp
  git -C "$W" commit -q -m "no bundle"
  before=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q "$INTEG"
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" cand_sha "$before"
  rs "$N" next
  eq "no bundle: exit" "$rc" 1
  has "no bundle: the line" "$out" "FAIL ipm the candidate has no committed web bundle (src/ocutalon/csp/index.html)"
  eq "no bundle: no container" "$(count_runs)" 0
  has "no bundle: the record" "$(cat "$(rec_file)")" "Result: failed at ipm: the candidate has no committed web bundle (src/ocutalon/csp/index.html)"
  git -C "$W" checkout -q --detach release/1.0.0-rc1
  sed 's:<Version>[^<]*</Version>:<Version>1.0.1</Version>:' "$W/src/module.xml" > "$W/src/module.xml.new"
  mv "$W/src/module.xml.new" "$W/src/module.xml"
  git -C "$W" commit -q -am "another version"
  before=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q "$INTEG"
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" cand_sha "$before"
  rs "$N" next
  has "a wrong version: the line" "$out" "FAIL ipm src/module.xml reads 1.0.1, not 1.0.0"
  eq "a wrong version: no container" "$(count_runs)" 0
  git -C "$W" checkout -q --detach release/1.0.0-rc1
  sed 's:<Version>[^<]*</Version>:<Version>1.0.1</Version>:' "$W/module.xml" > "$W/module.xml.new"
  mv "$W/module.xml.new" "$W/module.xml"
  git -C "$W" commit -q -am "another root version"
  before=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q "$INTEG"
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" cand_sha "$before"
  rs "$N" next
  has "a wrong root version: the line" "$out" "FAIL ipm module.xml reads 1.0.1, not 1.0.0"
  eq "a wrong root version: no container" "$(count_runs)" 0
  git -C "$W" checkout -q --detach release/1.0.0-rc1
  git -C "$W" rm -q docker/ipm/zpm-0.10.10.xml
  git -C "$W" commit -q -m "no ipm release file"
  before=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q "$INTEG"
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" cand_sha "$before"
  rs "$N" next
  has "no IPM release file: the line" "$out" "FAIL ipm the candidate holds no single docker/ipm/zpm-*.xml"
  eq "no IPM release file: no container" "$(count_runs)" 0
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" cand_sha "$c"
  flag no-base
  rs "$N" next
  has "no base image: the line" "$out" "FAIL ipm the IRIS base image ocutalon-iris-base:2026.3.0AI.154.0 is not on this machine"
  eq "no base image: no container" "$(count_runs)" 0
  eq "no base image: nothing was pulled" "$(grep -cE '^pull' "$SHIMLOG/docker.log")" 0
  lacks "no base image: no push question" "$out" "ASK push"
  unflag no-base
  rs "$N" next
  has "the retry packs" "$out" "PASS ipm ocutalon-1.0.0.tgz "
  eq "the retry made one throwaway" "$(count_runs)" 1
  # a sequence that is not cut: a failure with no section
  newcase
  rs "$Y" start --version 1.0.0
  env_set "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env" next ipm
  rs "$N" next
  has "not cut: the line" "$out" "FAIL ipm the candidate is not cut"
  eq "not cut: no section" "$(grep -c '^## IPM artifact' "$(rec_file)")" 0
  eq "not cut: no container" "$(count_runs)" 0
  # a failed packaging is never pushed: even with "yes" to every question, the candidate branch stays off the remote
  newcase
  to_step ipm
  flag ipm-byte
  rs "$Y" next
  unflag ipm-byte
  eq "a failed packaging, every question answered yes: exit" "$rc" 1
  has "a failed packaging, every question answered yes: the line" "$out" "FAIL ipm the artifact holds a different "
  lacks "a failed packaging, every question answered yes: no push" "$out" "PASS push"
  eq "a failed packaging: the candidate branch is not on the remote" "$(git --git-dir="$R" for-each-ref --format='%(refname)' 'refs/heads/release/*' | wc -l | tr -d ' ')" 0
  eq "a failed packaging: no tag on the remote" "$(git --git-dir="$R" for-each-ref --format='%(refname)' refs/tags | wc -l | tr -d ' ')" 0
  rs '' status
  has "a failed packaging: the sequence still waits at ipm" "$out" "STATE 1.0.0 rc1 next ipm"
}

t_ipmwait() {
  local lock before head
  . "$root/release/lib-release.sh"
  newcase
  to_step ipm
  lock=$C/locks/throwaway-iris.lock
  echo "epic=99 stage=other project=other acquired_at=2026-01-01T00:00:00Z" > "$lock"
  before=$(cat "$lock")
  head=$(git -C "$W" rev-parse HEAD)
  export OCUTALON_LOCK_WAIT=0
  rs '' next
  unset OCUTALON_LOCK_WAIT
  eq "busy lock: exit" "$rc" 5
  has "busy lock: the line" "$out" "WAIT ipm the lane's throwaway lock is busy"
  lacks "busy lock: no question" "$out" "ASK "
  lacks "busy lock: no lock line is printed" "$out" "LOCK "
  eq "busy lock: no container was run" "$(count_runs)" 0
  eq "busy lock: the planted lock is kept" "$(cat "$lock")" "$before"
  eq "busy lock: no record" "$([ -e "$(rec_file)" ] && echo yes || echo no)" no
  eq "busy lock: no commit" "$(git -C "$W" rev-parse HEAD)" "$head"
  rs '' status
  has "busy lock: the sequence still waits at ipm" "$out" "STATE 1.0.0 rc1 next ipm"
  eq "busy lock: no artifact" "$([ -e "$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz" ] && echo yes || echo no)" no
  rm -f "$lock"
  rs '' next
  eq "the next call runs ipm again: exit" "$rc" 0
  has "the next call runs ipm again" "$out" "PASS ipm ocutalon-1.0.0.tgz "
  eq "the next call made one throwaway" "$(count_runs)" 1
  no_leftovers "after the wait"
}

t_ipmnet() {
  local plant hits d
  . "$root/release/lib-release.sh"
  newcase
  printf '' > "$tmp/alloutput"
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  rs "$N" next
  eq "net: the full run stops at the push question" "$rc" 4
  has "net: the throwaway ran" "$(cat "$SHIMLOG/docker.log")" "run -d --pull never --network none --name "
  eq "net: every throwaway run has no network and no pull" "$(runs_d | grep -vc -e '--pull never --network none')" 0
  eq "net: no env, volume, mount or port flag on a throwaway run" "$(runs_d | grep -cE -e ' -e | --env| -v | --mount| -p | --publish| --volume')" 0
  eq "net: no pull, push, login, save or export" "$(grep -cE '^(pull|push|login|save|export)' "$SHIMLOG/docker.log")" 0
  eq "net: the bare remote is unchanged" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')" "$EXPECT_BASE refs/heads/$INTEG"
  hits=$(grep -rl "$OCUTALON_TEST_SECRET" "$tmp/alloutput" "$C/shim" "$OCUTALON_RELEASE_STATE" "$W/release/records" 2> /dev/null)
  eq "net: the planted value is in no output, record, log or shim log" "$hits" ""
  eq "net: the planted value is not in the artifact" "$(tar -xzOf "$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz" 2> /dev/null | grep -c "$OCUTALON_TEST_SECRET")" 0
  # the scan of the scripts for the forms that send something out
  eq "net: the scan of the scripts" "$(forbidden_scan "$root/release/release.sh" "$root/release/lib-release.sh")" ""
  d=$tmp/scan2
  mkdir -p "$d"
  for plant in "dock""er pull ocutalon-iris-base" "zpm \"pub""lish ocutalon\"" "zpm \"repo -""r https://x.invalid/\"" "zpm \"repo -name x -""url https://x.invalid/\"" "zpm \"repo -name x -pub""lish\""; do
    printf '#!/bin/sh\necho ok\n%s\n' "$plant" > "$d/s.sh"
    eq "net: the scan flags '$plant'" "$(forbidden_scan "$d/s.sh")" "$d/s.sh:3"
  done
  printf '#!/bin/sh\n%s\n' 'zpm "repo -name x -fs -depth 2 -path /y/"' > "$d/g.sh"
  eq "net: the scan accepts a filesystem repository" "$(forbidden_scan "$d/g.sh")" ""
  cp "$root/release/lib-release.sh" "$d/copy.sh"
  printf '%s\n' "dock""er pull registry.invalid/x" >> "$d/copy.sh"
  eq "net: a planted line in a copy of the library" "$(forbidden_scan "$d/copy.sh")" "$d/copy.sh:$(wc -l < "$d/copy.sh" | tr -d ' ')"
}

t_ipmlib() {
  local t a b
  . "$root/release/lib-release.sh"
  newcase
  t=$C/t
  eq "release_state_dir" "$(OCUTALON_RELEASE_STATE=/s release_state_dir 1.0.0 2)" "/s/1.0.0-rc2"
  eq "release_state_root from XDG_STATE_HOME" "$(unset OCUTALON_RELEASE_STATE; XDG_STATE_HOME=/x release_state_root)" "/x/ocutalon/release"
  eq "ipm_artifact_path" "$(OCUTALON_RELEASE_STATE=/s ipm_artifact_path 1.0.0 2)" "/s/1.0.0-rc2/ipm/ocutalon-1.0.0.tgz"
  printf 'abc' > "$C/abc"
  eq "sha256_file" "$(sha256_file "$C/abc")" "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  printf 'a\nb\n\nNS>\n  \n' > "$C/sess"
  eq "last_prompt_free_line" "$(last_prompt_free_line "$C/sess")" "b"
  # the content digest: one value for two packagings of one tree, another for other content
  mkdir -p "$t/a/src/ocutalon/csp/assets" "$t/tree/src/ocutalon/csp/assets"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/" Target="x"/>\n' > "$t/a/module.xml"
  printf 'page\n' > "$t/a/src/ocutalon/csp/index.html"
  printf 'asset\n' > "$t/a/src/ocutalon/csp/assets/a.txt"
  cp -R "$t/a/src/ocutalon/csp/." "$t/tree/src/ocutalon/csp/"
  tar -czf "$C/one.tgz" -C "$t/a" .
  touch -t 202001010101 "$t/a/src/ocutalon/csp/assets/a.txt" "$t/a/module.xml"
  tar -czf "$C/two.tgz" -C "$t/a" .
  eq "the two packagings differ in bytes" "$(cmp -s "$C/one.tgz" "$C/two.tgz" && echo same || echo differ)" differ
  a=$(ipm_content_digest "$C/one.tgz")
  b=$(ipm_content_digest "$C/two.tgz")
  eq "the content digest is a SHA-256" "$(printf '%s' "$a" | grep -cE '^[0-9a-f]{64}$')" 1
  eq "the content digest is the same for both packagings" "$a" "$b"
  printf 'asset2\n' > "$t/a/src/ocutalon/csp/assets/a.txt"
  tar -czf "$C/three.tgz" -C "$t/a" .
  [ "$(ipm_content_digest "$C/three.tgz")" != "$a" ] || {
    echo "  the digest ignores a changed file"
    bad=1
  }
  printf 'asset\n' > "$t/a/src/ocutalon/csp/assets/a.txt"
  # the digest covers every file's path and bytes, module.xml included
  eq "the content digest is the SHA-256 of the sorted per-file sums" "$a" "$(cd "$t/a" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do printf '%s  %s\n' "$(sha256_file "$f")" "$f"; done | LC_ALL=C sort | { cat > "$C/lines"; sha256_file "$C/lines"; })"
  printf 'x\n' >> "$t/a/module.xml"
  tar -czf "$C/mod.tgz" -C "$t/a" .
  [ "$(ipm_content_digest "$C/mod.tgz")" != "$a" ] || {
    echo "  the digest ignores module.xml"
    bad=1
  }
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/" Target="x"/>\n' > "$t/a/module.xml"
  mv "$t/a/src/ocutalon/csp/assets/a.txt" "$t/a/src/ocutalon/csp/assets/b.txt"
  tar -czf "$C/ren.tgz" -C "$t/a" .
  [ "$(ipm_content_digest "$C/ren.tgz")" != "$a" ] || {
    echo "  the digest ignores a renamed file"
    bad=1
  }
  mv "$t/a/src/ocutalon/csp/assets/b.txt" "$t/a/src/ocutalon/csp/assets/a.txt"
  # the artifact check
  eq "a good artifact has no problem" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" root)" ""
  has "no temporary folder: a problem, never a pass" "$(TMPDIR=$C/no-such-folder ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" root)" "cannot be checked (no temporary folder)"
  has "another version" "$(ipm_artifact_check "$C/one.tgz" 1.0.1 "$t/tree" root)" "does not read version 1.0.1"
  printf 'asset\nmore\n' > "$t/tree/src/ocutalon/csp/assets/a.txt"
  has "a changed bundle byte" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" root)" "holds a different src/ocutalon/csp/assets/a.txt than the candidate"
  printf 'asset\n' > "$t/tree/src/ocutalon/csp/assets/a.txt"
  printf 'extra\n' > "$t/tree/src/ocutalon/csp/extra.js"
  has "a missing bundle file" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" root)" "lacks the bundle file src/ocutalon/csp/extra.js"
  rm -f "$t/tree/src/ocutalon/csp/extra.js"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version>\n' > "$t/a/module.xml"
  tar -czf "$C/nofc.tgz" -C "$t/a" .
  has "no FileCopy" "$(ipm_artifact_check "$C/nofc.tgz" 1.0.0 "$t/tree" root)" "no FileCopy of src/ocutalon/csp/"
  printf '<Name>other</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/"/>\n' > "$t/a/module.xml"
  tar -czf "$C/name.tgz" -C "$t/a" .
  has "another name" "$(ipm_artifact_check "$C/name.tgz" 1.0.0 "$t/tree" root)" "does not name ocutalon"
  rm -f "$t/a/module.xml"
  tar -czf "$C/nomod.tgz" -C "$t/a" .
  has "no module.xml" "$(ipm_artifact_check "$C/nomod.tgz" 1.0.0 "$t/tree" root)" "has no top-level module.xml"
  printf 'not an archive' > "$C/bad.tgz"
  has "not an archive" "$(ipm_artifact_check "$C/bad.tgz" 1.0.0 "$t/tree" root)" "cannot be read"
  # the layout is an explicit argument: the same checks and the same bundle files for an artifact packed from src/module.xml, and neither
  # layout passes for the other's artifact, file by file
  n=$(find "$t/tree/src/ocutalon/csp" -type f | wc -l | tr -d ' ')
  mkdir -p "$t/s/ocutalon/csp"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="ocutalon/csp/" Target="x"/>\n' > "$t/s/module.xml"
  cp -R "$t/tree/src/ocutalon/csp/." "$t/s/ocutalon/csp/"
  tar -czf "$C/src.tgz" -C "$t/s" .
  eq "src layout: a good artifact has no problem" "$(ipm_artifact_check "$C/src.tgz" 1.0.0 "$t/tree" src)" ""
  has "src layout: another version" "$(ipm_artifact_check "$C/src.tgz" 1.0.1 "$t/tree" src)" "does not read version 1.0.1"
  printf 'asset\nmore\n' > "$t/tree/src/ocutalon/csp/assets/a.txt"
  has "src layout: a changed bundle byte" "$(ipm_artifact_check "$C/src.tgz" 1.0.0 "$t/tree" src)" "holds a different ocutalon/csp/assets/a.txt than the candidate"
  printf 'asset\n' > "$t/tree/src/ocutalon/csp/assets/a.txt"
  printf 'extra\n' > "$t/tree/src/ocutalon/csp/extra.js"
  has "src layout: a missing bundle file" "$(ipm_artifact_check "$C/src.tgz" 1.0.0 "$t/tree" src)" "lacks the bundle file ocutalon/csp/extra.js"
  rm -f "$t/tree/src/ocutalon/csp/extra.js"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version>\n' > "$t/s/module.xml"
  tar -czf "$C/srcnofc.tgz" -C "$t/s" .
  has "src layout: no FileCopy" "$(ipm_artifact_check "$C/srcnofc.tgz" 1.0.0 "$t/tree" src)" "no FileCopy of ocutalon/csp/"
  has "a src artifact checked as root: no FileCopy" "$(ipm_artifact_check "$C/src.tgz" 1.0.0 "$t/tree" root)" "no FileCopy of src/ocutalon/csp/"
  eq "a src artifact checked as root: every bundle file is missing" "$(ipm_artifact_check "$C/src.tgz" 1.0.0 "$t/tree" root | grep -c 'lacks the bundle file src/ocutalon/csp/')" "$n"
  has "a root artifact checked as src: no FileCopy" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" src)" "no FileCopy of ocutalon/csp/"
  eq "a root artifact checked as src: every bundle file is missing" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" src | grep -c 'lacks the bundle file ocutalon/csp/')" "$n"
  has "no layout: a problem, never a pass" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree")" "cannot be checked (the layout '' is not root or src)"
  has "another layout: a problem, never a pass" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" both)" "cannot be checked (the layout 'both' is not root or src)"
  # the Python resources and requirements.txt (Story 19.6, U-294, ruling B4): a FileCopy for each resource of the candidate and the candidate's
  # requirements.txt at the top of the artifact
  mkdir -p "$t/tree/src/ocutalon/python" "$t/py/src/ocutalon/csp" "$t/pys/ocutalon/csp" "$t/py/src/ocutalon/python" "$t/pys/ocutalon/python"
  printf 'resource\n' > "$t/tree/src/ocutalon/python/one.py"
  cp "$t/tree/src/ocutalon/python/one.py" "$t/py/src/ocutalon/python/one.py"
  cp "$t/tree/src/ocutalon/python/one.py" "$t/pys/ocutalon/python/one.py"
  printf 'pin==1\n' > "$t/tree/requirements.txt"
  cp -R "$t/tree/src/ocutalon/csp/." "$t/py/src/ocutalon/csp/"
  cp -R "$t/tree/src/ocutalon/csp/." "$t/pys/ocutalon/csp/"
  cp "$t/tree/requirements.txt" "$t/py/requirements.txt"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/" Target="x"/><FileCopy Name="src/ocutalon/python/one.py" Target="${mgrdir}python/one.py"/>\n' > "$t/py/module.xml"
  tar -czf "$C/py.tgz" -C "$t/py" .
  eq "python: a good root artifact has no problem" "$(ipm_artifact_check "$C/py.tgz" 1.0.0 "$t/tree" root)" ""
  rm -f "$t/py/src/ocutalon/python/one.py"
  tar -czf "$C/pynofile.tgz" -C "$t/py" .
  has "python: an artifact without the resource file" "$(ipm_artifact_check "$C/pynofile.tgz" 1.0.0 "$t/tree" root)" "lacks the Python resource src/ocutalon/python/one.py"
  printf 'other\n' > "$t/py/src/ocutalon/python/one.py"
  tar -czf "$C/pydifffile.tgz" -C "$t/py" .
  has "python: an artifact with other bytes in the resource" "$(ipm_artifact_check "$C/pydifffile.tgz" 1.0.0 "$t/tree" root)" "holds a different src/ocutalon/python/one.py than the candidate"
  cp "$t/tree/src/ocutalon/python/one.py" "$t/py/src/ocutalon/python/one.py"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/" Target="x"/>\n' > "$t/py/module.xml"
  tar -czf "$C/pynofc.tgz" -C "$t/py" .
  has "python: no FileCopy of a resource" "$(ipm_artifact_check "$C/pynofc.tgz" 1.0.0 "$t/tree" root)" "no FileCopy of src/ocutalon/python/one.py"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/" Target="x"/><FileCopy Name="src/ocutalon/python/one.py" Target="y"/>\n' > "$t/py/module.xml"
  tar -czf "$C/pywrongtarget.tgz" -C "$t/py" .
  has "python: a FileCopy of a resource to another Target" "$(ipm_artifact_check "$C/pywrongtarget.tgz" 1.0.0 "$t/tree" root)" "no FileCopy of src/ocutalon/python/one.py"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="src/ocutalon/csp/" Target="x"/><FileCopy Name="src/ocutalon/python/one.py" Target="${mgrdir}python/one.py"/>\n' > "$t/py/module.xml"
  rm -f "$t/py/requirements.txt"
  tar -czf "$C/pynoreq.tgz" -C "$t/py" .
  has "python: no requirements.txt" "$(ipm_artifact_check "$C/pynoreq.tgz" 1.0.0 "$t/tree" root)" "has no top-level requirements.txt"
  printf 'pin==2\n' > "$t/py/requirements.txt"
  tar -czf "$C/pydiffreq.tgz" -C "$t/py" .
  has "python: another requirements.txt" "$(ipm_artifact_check "$C/pydiffreq.tgz" 1.0.0 "$t/tree" root)" "holds a different requirements.txt than the candidate"
  cp "$t/tree/requirements.txt" "$t/py/requirements.txt"
  cp "$t/tree/requirements.txt" "$t/pys/requirements.txt"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="ocutalon/csp/" Target="x"/><FileCopy Name="ocutalon/python/one.py" Target="${mgrdir}python/one.py"/>\n' > "$t/pys/module.xml"
  tar -czf "$C/pysrc.tgz" -C "$t/pys" .
  eq "python: a good src artifact has no problem" "$(ipm_artifact_check "$C/pysrc.tgz" 1.0.0 "$t/tree" src)" ""
  has "python: a src artifact checked as root has no FileCopy of the resource" "$(ipm_artifact_check "$C/pysrc.tgz" 1.0.0 "$t/tree" root)" "no FileCopy of src/ocutalon/python/one.py"
  rm -rf "$t/tree/src/ocutalon/python" "$t/tree/requirements.txt"
  eq "python: a candidate with neither the resource folder nor requirements.txt asks for none" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree" root)" ""
}

# --- static ---

t_static() {
  local f
  for f in release/release.sh docker/tests/test-release-sequence.sh; do
    [ -x "$root/$f" ] || {
      echo "  $f is not executable"
      bad=1
    }
    eq "$f: bash -n" "$(bash -n "$root/$f" 2>&1)" ""
    eq "$f: ASCII only" "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$root/$f" | cut -d: -f1 | tr '\n' ' ')" ""
  done
  eq "security-overview.sh: bash -n" "$(bash -n "$root/release/security-overview.sh" 2>&1)" ""
  eq "security-overview.sh: ASCII only" "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$root/release/security-overview.sh" | cut -d: -f1 | tr '\n' ' ')" ""
  eq "lib-security-overview.sh: bash -n" "$(bash -n "$root/docker/tests/lib-security-overview.sh" 2>&1)" ""
  eq "lib-security-overview.sh: ASCII only" "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$root/docker/tests/lib-security-overview.sh" | cut -d: -f1 | tr '\n' ' ')" ""
  [ -x "$root/release/security-overview.sh" ] || {
    echo "  release/security-overview.sh is not executable"
    bad=1
  }
  eq "the overview step makes no ASK" "$(awk '/^step_overview\(\)/ { f = 1 } /^# --- the ipm step/ { f = 0 } f' "$root/release/release.sh" | grep -c 'ask ')" 0
  eq "lib-release.sh: bash -n" "$(bash -n "$root/release/lib-release.sh" 2>&1)" ""
  eq "the steps, in order" "$(sed -n 's/^STEPS="\(.*\)"$/\1/p' "$root/release/release.sh")" "cut image overview ipm ipmcheck push notes"
  eq "the ipm step makes no ASK" "$(awk '/^step_ipm\(\)/ { f = 1 } /^step_ipmcheck\(\)/ { f = 0 } f' "$root/release/release.sh" | grep -c 'ask ')" 0
  eq "the ipmcheck step makes no ASK" "$(awk '/^step_ipmcheck\(\)/ { f = 1 } /^step_push\(\)/ { f = 0 } f' "$root/release/release.sh" | grep -c 'ask ')" 0
  eq "lib-release.sh: ASCII only" "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$root/release/lib-release.sh" | cut -d: -f1 | tr '\n' ' ')" ""
  eq "the tracked scripts are mode 100755" "$(git -C "$root" ls-files -s release/release.sh release/lib-release.sh release/security-overview.sh docker/tests/test-release-sequence.sh | awk '$1 != "100755" { print $4 }')" ""
  newcase
  net_check "$W"
  eq "a local remote passes the network check" "$?" 0
  git -C "$W" remote add net "https://example.invalid/x.git"
  eq "a network remote stops the test" "$(net_check "$W" > /dev/null; echo $?)" 1
  git -C "$W" remote remove net
  git -C "$W" remote add net2 "git@example.invalid:x/y.git"
  eq "an ssh remote stops the test" "$(net_check "$W" > /dev/null; echo $?)" 1
  eq "sourcing the script runs nothing" "$(cd "$tmp" && "$BASH" -c ". '$root/release/release.sh'; type release_main > /dev/null && echo defined")" defined
  eq "the usage with no command" "$(cd "$root" && "$BASH" release/release.sh 2>&1 | head -n 1 | cut -c1-30)" "release/release.sh start --ver"
  eq "the usage exit" "$(cd "$root" && "$BASH" release/release.sh > /dev/null 2>&1; echo $?)" 2
  has "ci: the unit is listed" "$(sed -n 's/^CHECK_SCRIPTS="\(.*\)"$/\1/p' "$root/ci/units.sh")" " release-sequence"
  eq "(U-294) requirements.txt pins the same distributions as docker/licences/constraints-arm64.txt (the pin lines are equal)" "$(grep -v '^#' "$root/requirements.txt" | grep .)" "$(grep -v '^#' "$root/docker/licences/constraints-arm64.txt" | grep .)"
  eq "(U-294) requirements.txt pins the same distributions as docker/licences/constraints-x64.txt" "$(grep -v '^#' "$root/requirements.txt" | grep .)" "$(grep -v '^#' "$root/docker/licences/constraints-x64.txt" | grep .)"
  eq "(U-294) requirements.txt has 36 pin lines and no line that is not a pin or a comment" "$(grep -v '^#' "$root/requirements.txt" | grep -c '^[A-Za-z0-9_.-]*==[A-Za-z0-9_.-]*$')/$(grep -v '^#' "$root/requirements.txt" | grep -c .)" "36/36"
  eq "(U-294) the root requirements.txt opens with a comment that names its source" "$(sed -n 1p "$root/requirements.txt" | cut -c1-2)" "# "
  eq "(QA) requirements.txt is tracked" "$(git -C "$root" ls-files requirements.txt)" "requirements.txt"
  pip_pins=$(grep -F 'pip install' "$root/Dockerfile" | tr ' ' '\n' | grep '==')
  eq "(U-294) the image's pip line has three pins" "$(printf '%s\n' "$pip_pins" | grep -c .)" 3
  for pin in $pip_pins; do
    eq "(U-294) requirements.txt has the image's pin $pin" "$(grep -cx -e "$pin" "$root/requirements.txt")" 1
  done
  fig_guide=$(grep -F 'pypi.org' "$root/GUIDE.md" | grep -o 'about [0-9][0-9.,]*\( to [0-9][0-9.,]*\)\? \(MB\|seconds\?\|minutes\?\)' | tr '\n' ' ')
  fig_docs=$(grep -F 'pypi.org' "$root/docs/install-ipm.md" | grep -o 'about [0-9][0-9.,]*\( to [0-9][0-9.,]*\)\? \(MB\|seconds\?\|minutes\?\)' | tr '\n' ' ')
  eq "(DW-784) GUIDE.md's IPM section and docs/install-ipm.md quote the same package size, model size and install time" "$fig_docs" "$fig_guide"
  eq "(DW-784) and each quotes all five figures (a size, a size, the Mac run time, the x64 run time and the Mac download time)" "$(printf '%s' "$fig_guide" | grep -o 'about' | wc -l | tr -d ' ')" 5
  # The ruled PUBLIC TEXT (the Contest Planner's ruling of 2026-11-06, A4 to A6), each line compared whole and byte for byte.
  eq "(DW-784, A4) GUIDE.md's IPM paragraph is the ruled text" "$(grep -cxF "The second run also downloads OcuTalon's Python packages from PyPI (fastembed, pdfplumber and python-docx with their dependencies, about 250 MB once installed) and the embedding model from Hugging Face (about 90 MB), so the instance needs network access to pypi.org, files.pythonhosted.org, huggingface.co and its download hosts under hf.co (in our test installs us.aws.cdn.hf.co and cas-server.xethub.hf.co). In our test installs, the whole second run took about 1 to 1.5 minutes on an Apple silicon Mac and about 3 minutes on a shared x64 Linux build server. On the Mac, the downloads took about 20 seconds of that." "$root/GUIDE.md")" 1
  eq "(DW-784, A5) the README's licence bullet is the ruled text" "$(grep -cxF -e "- An IPM install puts the same Python packages, at the same versions, into the instance's \`mgr/python\` folder, each with its licence files." "$root/README.md")" 1
  eq "(DW-784, A6) the install page's network bullet is the ruled text" "$(grep -cxF -e "- Network access from the instance to PyPI (pypi.org and files.pythonhosted.org) and to Hugging Face (huggingface.co and its download hosts under hf.co, in our test installs us.aws.cdn.hf.co and cas-server.xethub.hf.co): the second command downloads OcuTalon's Python packages, about 250 MB once installed, and the embedding model, about 90 MB. In our test installs, the whole second command took about 1 to 1.5 minutes on an Apple silicon Mac and about 3 minutes on a shared x64 Linux build server. On the Mac, the downloads took about 20 seconds of that." "$root/docs/install-ipm.md")" 1
  # The hosts that the two files name (Story 19.8, DW-830): the same set in GUIDE.md's paragraph (A4) and the install page's bullet (A6).
  hosts_guide=$(grep -F 'pypi.org' "$root/GUIDE.md" | grep -o '[a-z][a-z0-9.-]*\.\(org\|co\)' | sort -u | tr '\n' ' ')
  hosts_docs=$(grep -F 'pypi.org' "$root/docs/install-ipm.md" | grep -o '[a-z][a-z0-9.-]*\.\(org\|co\)' | sort -u | tr '\n' ' ')
  eq "(DW-830) GUIDE.md's paragraph and the install page's bullet name the same hosts" "$hosts_docs" "$hosts_guide"
  eq "(DW-830) and those are the hosts of the measured install (hf.co is the parent of the two download hosts)" "$hosts_guide" "cas-server.xethub.hf.co files.pythonhosted.org hf.co huggingface.co pypi.org us.aws.cdn.hf.co "
  # The ruled disclosure bullet (the Contest Planner's ruling of 2026-11-07, DW-829), in the install page only, so it is no part of the pairing above.
  eq "(DW-829, DW-857) the install page's bullet on the shared Python folder is the ruled text" "$(grep -cxF -e "- The second command puts these packages in the instance's shared Python folder, mgr/python in the IRIS install directory. Where that folder already holds other versions of certifi, charset_normalizer, idna, requests, typing_extensions or urllib3, which IPM installs for itself, the second command replaces them with the versions OcuTalon pins. IPM's own packages work with these versions." "$root/docs/install-ipm.md")" 1
  eq "(DW-829) the README has no such bullet (it keeps the licence bullet of A5)" "$(grep -c 'shared Python folder' "$root/README.md")" 0
  eq "(DW-829) GUIDE.md's IPM section has no such bullet either (the install page holds it alone)" "$(grep -c 'shared Python folder' "$root/GUIDE.md")" 0
  # The two extraction reasons that reuse the web app's catalog (U-284) carry its exact bytes (A1).
  for reason in "it isn't a Markdown, plain-text, PDF or Word (.docx) file." "that file is {size}; the limit is 10 MB."; do
    eq "(A1) the web catalog and Docs.Extract both hold: $reason" "$(grep -cF -e "$reason" "$root/web/src/app/documents/documents-view.ts")/$(grep -cF -e "\"$reason\"" "$root/src/ocutalon/cls/OcuTalon/Docs/Extract.cls")" "1/1"
  done
  eq "(QA) every zpm load of the ipm step bypasses pip, which has no network there" "$(grep -c 'zpm \\"load -bypass-py-deps ' "$root/release/release.sh")" 2
  eq "(QA) no zpm load of the ipm step is left without the bypass" "$(grep 'zpm \\"load ' "$root/release/release.sh" | grep -vc -e '-bypass-py-deps')" 0
  eq "(QA) live:memory-offline is a unit of shards-4" "$("$BASH" -c ". '$root/ci/units.sh'; group_units shards-4" | tr ' ' '\n' | grep -cx 'live:memory-offline')" 1
  eq "(QA) the Memory area is in lane-a" "$("$BASH" -c ". '$root/ci/units.sh'; shard_areas lane-a" | tr ' ' '\n' | grep -cx 'Memory')" 1
  eq "the notes step never replaces a draft" "$(grep -c -e '--replace' "$root/release/release.sh")" 0
  eq "no outward form in the script" "$(grep -nE 'gh[ ]release|gh[ ]repo[ ]edit|--visib[i]lity' "$root/release/release.sh" | wc -l | tr -d ' ')" 0
}

# --- the real build (IA3) ---

live_run() {
  local ans c imgs
  newcase
  unset SHIMLOG SHIMFLAGS SHIMSTATE
  # the real npm and docker are used: the shims are not on the PATH
  PATH=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vxF "$tmp/bin" | tr '\n' ':')
  PATH=${PATH%:}
  echo "LIVE the real npm and docker build of the cut and the image step"
  rs "$Y" start --version 1.0.0
  [ "$rc" -eq 0 ] || {
    echo "$out"
    bad=1
    return 0
  }
  rs '' next
  echo "$out" | tail -n 3
  [ "$rc" -eq 0 ] || {
    bad=1
    return 0
  }
  rs '' next
  echo "$out" | tail -n 3
  has "the image step" "$out" "PASS image 1.0.0"
  [ "$bad" -eq 0 ] || return 0
  imgs=$(docker images --format '{{.Repository}}' | grep -c "$LIVE_TAG_PREFIX")
  eq "no check image is left" "$imgs" 0
  eq "the candidate's bundle is committed" "$(git -C "$W" ls-tree --name-only release/1.0.0-rc1 src/ocutalon/csp/index.html)" "src/ocutalon/csp/index.html"
  [ "$live_ipm" -eq 1 ] || return 0
  live_ipm_run
}

# live_ipm_run: IA1, the real packaging of the throwaway candidate with IPM (one call; the lane variables name the lock folder).
live_ipm_run() {
  local t0 art x n lockf
  # the overview step comes before ipm; the seed's passing stub of the unit runs it
  rs '' next
  has "ipm: the overview step before it" "$out" "PASS overview "
  [ "$bad" -eq 0 ] || return 0
  echo "LIVE the real IPM packaging of the candidate (throwaway build 154 container, no network)"
  t0=$SECONDS
  rs '' next
  echo "$out" | tail -n 4
  echo "TIME ipm $((SECONDS - t0)) s"
  eq "ipm: exit" "$rc" 0
  has "ipm: the step" "$out" "PASS ipm ocutalon-1.0.0.tgz "
  [ "$bad" -eq 0 ] || return 0
  art=$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/ocutalon-1.0.0.tgz
  x=$C/x
  mkdir -p "$x"
  tar -xzf "$art" -C "$x"
  n=$(git -C "$W" ls-tree -r --name-only release/1.0.0-rc1 -- src/ocutalon/csp | wc -l | tr -d ' ')
  echo "LIVE the artifact: $(wc -c < "$art" | tr -d ' ') bytes, $n bundle files"
  grep -h -E 'Activate SUCCESS|^ocutalon ' "$OCUTALON_RELEASE_STATE"/1.0.0-rc1/ipm/*.log | sed 's/^/LIVE ipm log: /'
  sect "$(rec_file)" "## IPM artifact" | sed 's/^/LIVE record: /'
  [ "$n" -gt 1 ] || {
    echo "  the candidate tracks $n bundle file(s)"
    bad=1
  }
  eq "IPM's filesystem repository lists the artifact" "$(awk '$1 == "ocutalon" && $2 == "1.0.0" { print $1, $2 }' "$OCUTALON_RELEASE_STATE/1.0.0-rc1/ipm/repo-list.log" | head -n 1)" "ocutalon 1.0.0"
  eq "the artifact holds the real bundle byte for byte" "$(bundle_diff "$x" release/1.0.0-rc1)" ""
  has "the artifact's module.xml" "$(cat "$x/module.xml")" '<FileCopy Name="src/ocutalon/csp/"'
  eq "no ipm throwaway container is left" "$(docker ps -a --format '{{.Names}}' | grep -c '^ocutalon-release-ipm-')" 0
  lockf=${OCUTALON_LOCK_DIR:-}/throwaway-iris.lock
  eq "the lane lock holds nothing of the run" "$(cat "$lockf" 2> /dev/null | grep -c 'project=ocutalon-release-ipm-')" 0
  rs '' status
  has "status prints the artifact" "$out" "ARTIFACT $art "
}

mkshims
export PATH="$tmp/bin:$PATH"
mkseed
printf '' > "$tmp/alloutput"

if [ "$live" -eq 1 ]; then
  # The throwaway repository has no coordination folder, so the lane lock folder is the one lib-live derives from this checkout.
  if [ -z "${OCUTALON_LOCK_DIR:-}" ]; then
    OCUTALON_LOCK_DIR=$(. "$root/docker/tests/lib-live.sh" && live_lock_dir)
    [ -z "$OCUTALON_LOCK_DIR" ] || export OCUTALON_LOCK_DIR
  fi
  rules=" live "
  rule live live_run
  [ "$fails_total" -eq 0 ] || exit 1
  exit 0
fi

rule libs t_libs
rule refusals t_refusals
rule cut t_cut
rule recut t_recut
rule image t_image
rule overview t_overview
rule ipmcheck t_ipmcheck
rule overviewunit t_overviewunit
rule overviewdrift t_overviewdrift
rule overviewdoc t_overviewdoc
rule push t_push
rule record t_record
rule hands t_hands
rule resume t_resume
rule notes t_notes
rule gate t_gate
rule secret t_secret
rule ipm t_ipm
rule ipmfail t_ipmfail
rule ipmwait t_ipmwait
rule ipmnet t_ipmnet
rule ipmlib t_ipmlib
rule first t_first
rule word t_word
rule pushes t_pushes
rule static t_static

if [ "$fails_total" -eq 0 ]; then
  echo "PASS all rules"
  exit 0
fi
echo "FAIL $fails_total rule(s)"
exit 1
