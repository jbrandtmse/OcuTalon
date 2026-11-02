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
#   ipmfail   every shim fault (a failed load, a dropped bundle file, a changed byte, a wrong version, an empty repository, an instance that
#             is not running, a failed start) fails the step and deletes the file; the refusals come before any container; a leftover
#             under the recorded name goes and a bystander stays
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
    [ -f "$SHIMFLAGS/build-fail" ] && { echo "planted build failure in $ctx/docker/Dockerfile" >&2; exit 1; }
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
                      dir=${line#zpm \"load }
                      dir=${dir%\"}
                      if [ -f "$SHIMFLAGS/ipm-load-fail" ]; then
                        echo "ERROR! planted install failure"
                      elif [ "$ns" != OCUTALON ] && { [ -f "$SHIMFLAGS/ipm-mapandstop" ] || grep -q MapAndStop "$d/fs$dir/module.xml"; }; then
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
                      else
                        rm -rf "$d/pk"
                        mkdir -p "$d/pk"
                        cp -R "$d/fs$src/." "$d/pk/"
                        [ -f "$SHIMFLAGS/ipm-drop-csp" ] && rm -f "$d/pk/ocutalon/csp/main-FAKE.js"
                        [ -f "$SHIMFLAGS/ipm-byte" ] && echo x >> "$d/pk/ocutalon/csp/main-FAKE.js"
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

mkseed() {
  local s=$tmp/seed
  mkdir -p "$s"
  if [ "$live" -eq 1 ]; then
    git -C "$root" archive HEAD | tar -x -C "$s" || exit 1
  else
    # Only what the sequence, the notes script and the harness read: the whole tree adds time and no case.
    git -C "$root" archive HEAD release ci docker/tests docker/Dockerfile docker/ipm .gitignore .dockerignore src/module.xml README.md \
      web/package.json web/package-lock.json _bmad-output/implementation-artifacts/sprint-status.yaml \
      _bmad-output/planning-artifacts/epics.md | tar -x -C "$s" || exit 1
  fi
  cp -p "$root/release/release.sh" "$root/release/lib-release.sh" "$s/release/"
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
  case $1 in ipm) return 0 ;; esac
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
  local c integ_ver sha
  newcase
  integ_ver=$(git -C "$W" show "HEAD:src/module.xml")
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
  eq "cut: the integration branch's module.xml" "$(git -C "$W" show "$INTEG:src/module.xml")" "$integ_ver"
  eq "cut: the integration branch has not moved" "$(git -C "$W" rev-parse "$INTEG")" "$EXPECT_BASE"
  eq "cut: the bundle's index.html is committed" "$(git -C "$W" ls-tree --name-only release/1.0.0-rc1 src/ocutalon/csp/index.html)" "src/ocutalon/csp/index.html"
  eq "cut: the rest of the bundle is committed" "$(git -C "$W" ls-tree -r --name-only release/1.0.0-rc1 -- src/ocutalon/csp | tr '\n' ' ')" "src/ocutalon/csp/assets/a.txt src/ocutalon/csp/index.html src/ocutalon/csp/main-FAKE.js "
  eq "cut: the author's checkout is still on the integration branch" "$(git -C "$W" symbolic-ref --short HEAD)" "$INTEG"
  eq "cut: the author's checkout is clean" "$(git -C "$W" status --porcelain)" ""
  eq "cut: the checkout has no bundle" "$([ -e "$W/src/ocutalon/csp" ] && echo yes || echo no)" no
  eq "cut: the checkout's module.xml" "$(cat "$W/src/module.xml")" "$integ_ver"
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
  has "image: the next step" "$out" "NEXT ipm"
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
  has "a failed build" "$out" "FAIL image docker build failed: planted build failure in <state>/context/docker/Dockerfile"
  lacks "a failed build: no local path in the record" "$(cat "$(rec_file)")" "$tmp"
  unflag build-fail
  flag no-bundle
  rs "$N" next
  has "no bundle" "$out" "FAIL image the image built from the candidate holds no web bundle"
  unflag no-bundle
  rs "$N" next
  has "the retry passes" "$out" "PASS image 1.0.0"
  has "the retry names the packaging" "$out" "NEXT ipm"
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
  has "the cut row" "$rec" "| cut | pass | src/module.xml set to 1.0.0; web bundle built with Node.js and committed |"
  has "the image row" "$rec" "| image | fail | "
  has "the record row" "$rec" "| record | committed, not pushed | the author did not give the word |"
  lacks "no step beyond the failure" "$rec" "| push |"
  lacks "no local path" "$rec" "$tmp"
  # the stop of an unanswered question, with the record question at the end of input
  unflag lie
  rs '' next
  has "image passes" "$out" "NEXT ipm"
  rs '' next
  has "ipm passes" "$out" "NEXT push"
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
  rs "$N" next
  rs '' next
  eq "declined and unanswered words: no push" "$(grep -cE '(^| )push( |$)' "$SHIMLOG/git.log")" 0
  RS_PATH=""
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
USER zpm "load /tmp/ocutalon-pkg/src"
USER zpm "package ocutalon -only -path /tmp/ocutalon-ipm/ocutalon-1.0.0"
USER zpm "repo -name ocutalon-check -fs -depth 2 -path /tmp/ocutalon-check/"
USER zpm "repo -name ocutalon-check -list-modules"'
ZPM_TWO='%SYS zpm "enable -map -ns USER"
USER zpm "load /tmp/ocutalon-pkg/src"
OCUTALON zpm "load /tmp/ocutalon-pkg/src"
OCUTALON zpm "package ocutalon -only -path /tmp/ocutalon-ipm/ocutalon-1.0.0"
OCUTALON zpm "repo -name ocutalon-check -fs -depth 2 -path /tmp/ocutalon-check/"
OCUTALON zpm "repo -name ocutalon-check -list-modules"'

# bundle_diff <folder of the extracted artifact> <branch>: the bundle files of the branch that the folder lacks or holds with other bytes.
bundle_diff() {
  local f rel
  for f in $(git -C "$W" ls-tree -r --name-only "$2" -- src/ocutalon/csp); do
    rel=${f#src/ocutalon/csp/}
    cmp -s "$1/ocutalon/csp/$rel" <(git -C "$W" cat-file blob "$2:$f") || echo "$rel"
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
  # the pass, with today's module.xml (one run)
  newcase
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
  has "ipm: the next step" "$out" "NEXT push"
  x=$C/x
  mkdir -p "$x"
  tar -xzf "$art" -C "$x"
  has "ipm: the module's name" "$(cat "$x/module.xml")" "<Name>ocutalon</Name>"
  has "ipm: the module's version" "$(cat "$x/module.xml")" "<Version>1.0.0</Version>"
  has "ipm: the FileCopy of the bundle" "$(cat "$x/module.xml")" '<FileCopy Name="ocutalon/csp/"'
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
  # the sequence goes on to push and never packs again; IA2: the real notes step and the stop routine keep the section
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
  # a module that stops the first run (Epic 15's): loaded in USER, then in OCUTALON, packaged there
  newcase
  awk '/<\/Module>/ { print "      <Invoke Class=\"OcuTalon.Install.Ipm\" Method=\"MapAndStop\" Phase=\"Initialize\" When=\"After\"/>" } { print }' "$W/src/module.xml" > "$W/src/module.xml.new"
  mv "$W/src/module.xml.new" "$W/src/module.xml"
  git -C "$W" commit -q -am "a module that stops the first run"
  git -C "$W" push -q origin "$INTEG"
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
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
    "ipm-drop-csp|the artifact lacks the bundle file ocutalon/csp/main-FAKE.js" \
    "ipm-byte|the artifact holds a different ocutalon/csp/main-FAKE.js than the candidate" \
    "ipm-version|the artifact holds a module.xml that does not read version 1.0.0" \
    "ipm-empty-repo|the artifact is not listed by the IPM filesystem repository (it lists nothing for ocutalon 1.0.0)" \
    "ipm-not-running|the package did not install: the throwaway instance was not running after 0 s" \
    "ipm-run-fail|the package did not install: the throwaway instance could not be started"; do
    f=${i%%|*}
    msg=${i#*|}
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
    rs '' status
    has "$f: the sequence still waits at ipm" "$out" "STATE 1.0.0 rc1 next ipm"
    lacks "$f: no artifact line in the status" "$out" "ARTIFACT"
  done
  eq "the failed packagings each ran a throwaway" "$(count_runs)" 8
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
  eq "the re-run made a fresh throwaway" "$(count_runs)" 9
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
  mkdir -p "$t/a/ocutalon/csp/assets" "$t/tree/src/ocutalon/csp/assets"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="ocutalon/csp/" Target="x"/>\n' > "$t/a/module.xml"
  printf 'page\n' > "$t/a/ocutalon/csp/index.html"
  printf 'asset\n' > "$t/a/ocutalon/csp/assets/a.txt"
  cp -R "$t/a/ocutalon/csp/." "$t/tree/src/ocutalon/csp/"
  tar -czf "$C/one.tgz" -C "$t/a" .
  touch -t 202001010101 "$t/a/ocutalon/csp/assets/a.txt" "$t/a/module.xml"
  tar -czf "$C/two.tgz" -C "$t/a" .
  eq "the two packagings differ in bytes" "$(cmp -s "$C/one.tgz" "$C/two.tgz" && echo same || echo differ)" differ
  a=$(ipm_content_digest "$C/one.tgz")
  b=$(ipm_content_digest "$C/two.tgz")
  eq "the content digest is a SHA-256" "$(printf '%s' "$a" | grep -cE '^[0-9a-f]{64}$')" 1
  eq "the content digest is the same for both packagings" "$a" "$b"
  printf 'asset2\n' > "$t/a/ocutalon/csp/assets/a.txt"
  tar -czf "$C/three.tgz" -C "$t/a" .
  [ "$(ipm_content_digest "$C/three.tgz")" != "$a" ] || {
    echo "  the digest ignores a changed file"
    bad=1
  }
  printf 'asset\n' > "$t/a/ocutalon/csp/assets/a.txt"
  # the digest covers every file's path and bytes, module.xml included
  eq "the content digest is the SHA-256 of the sorted per-file sums" "$a" "$(cd "$t/a" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do printf '%s  %s\n' "$(sha256_file "$f")" "$f"; done | LC_ALL=C sort | { cat > "$C/lines"; sha256_file "$C/lines"; })"
  printf 'x\n' >> "$t/a/module.xml"
  tar -czf "$C/mod.tgz" -C "$t/a" .
  [ "$(ipm_content_digest "$C/mod.tgz")" != "$a" ] || {
    echo "  the digest ignores module.xml"
    bad=1
  }
  printf '<Name>ocutalon</Name><Version>1.0.0</Version><FileCopy Name="ocutalon/csp/" Target="x"/>\n' > "$t/a/module.xml"
  mv "$t/a/ocutalon/csp/assets/a.txt" "$t/a/ocutalon/csp/assets/b.txt"
  tar -czf "$C/ren.tgz" -C "$t/a" .
  [ "$(ipm_content_digest "$C/ren.tgz")" != "$a" ] || {
    echo "  the digest ignores a renamed file"
    bad=1
  }
  mv "$t/a/ocutalon/csp/assets/b.txt" "$t/a/ocutalon/csp/assets/a.txt"
  # the artifact check
  eq "a good artifact has no problem" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree")" ""
  has "another version" "$(ipm_artifact_check "$C/one.tgz" 1.0.1 "$t/tree")" "does not read version 1.0.1"
  printf 'asset\nmore\n' > "$t/tree/src/ocutalon/csp/assets/a.txt"
  has "a changed bundle byte" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree")" "holds a different ocutalon/csp/assets/a.txt than the candidate"
  printf 'asset\n' > "$t/tree/src/ocutalon/csp/assets/a.txt"
  printf 'extra\n' > "$t/tree/src/ocutalon/csp/extra.js"
  has "a missing bundle file" "$(ipm_artifact_check "$C/one.tgz" 1.0.0 "$t/tree")" "lacks the bundle file ocutalon/csp/extra.js"
  rm -f "$t/tree/src/ocutalon/csp/extra.js"
  printf '<Name>ocutalon</Name><Version>1.0.0</Version>\n' > "$t/a/module.xml"
  tar -czf "$C/nofc.tgz" -C "$t/a" .
  has "no FileCopy" "$(ipm_artifact_check "$C/nofc.tgz" 1.0.0 "$t/tree")" "no FileCopy of ocutalon/csp/"
  printf '<Name>other</Name><Version>1.0.0</Version><FileCopy Name="ocutalon/csp/"/>\n' > "$t/a/module.xml"
  tar -czf "$C/name.tgz" -C "$t/a" .
  has "another name" "$(ipm_artifact_check "$C/name.tgz" 1.0.0 "$t/tree")" "does not name ocutalon"
  rm -f "$t/a/module.xml"
  tar -czf "$C/nomod.tgz" -C "$t/a" .
  has "no module.xml" "$(ipm_artifact_check "$C/nomod.tgz" 1.0.0 "$t/tree")" "has no top-level module.xml"
  printf 'not an archive' > "$C/bad.tgz"
  has "not an archive" "$(ipm_artifact_check "$C/bad.tgz" 1.0.0 "$t/tree")" "cannot be read"
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
  eq "lib-release.sh: bash -n" "$(bash -n "$root/release/lib-release.sh" 2>&1)" ""
  eq "the steps, in order" "$(sed -n 's/^STEPS="\(.*\)"$/\1/p' "$root/release/release.sh")" "cut image ipm push notes"
  eq "no file release/ipm* is changed or added" "$(git -C "$root" status --porcelain -- 'release/ipm*' | wc -l | tr -d ' ')" 0
  eq "the ipm step makes no ASK" "$(awk '/^step_ipm\(\)/ { f = 1 } /^step_push\(\)/ { f = 0 } f' "$root/release/release.sh" | grep -c 'ask ')" 0
  eq "lib-release.sh: ASCII only" "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$root/release/lib-release.sh" | cut -d: -f1 | tr '\n' ' ')" ""
  eq "the tracked scripts are mode 100755" "$(git -C "$root" ls-files -s release/release.sh release/lib-release.sh docker/tests/test-release-sequence.sh | awk '$1 != "100755" { print $4 }')" ""
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
  has "the artifact's module.xml" "$(cat "$x/module.xml")" '<FileCopy Name="ocutalon/csp/"'
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
