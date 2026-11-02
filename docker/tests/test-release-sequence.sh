#!/usr/bin/env bash
# Hermetic self-test of the release sequence (Story 11.5 and Story 11.14; release/release.sh and the candidate_branch, release_tags,
# next_rc, record_field, production_stubs, candidate_clone and gh_repo helpers of release/lib-release.sh), with no container, no network
# call and no model. It needs bash, git, awk, node and tar.
#   bash docker/tests/test-release-sequence.sh [<rule>...]   runs the named rules (default: all)
#   bash docker/tests/test-release-sequence.sh --live        the one real build (IA3): the real npm and docker build of the cut and
#                                                            the image step; never in CI, and in its own call
#   bash docker/tests/test-release-sequence.sh --live-gates prepare|next|check|clean
#                                                            the real upgrade harness through the gate steps (IA4): never in CI, one part
#                                                            per call, with OCUTALON_RUN_TAG and the lane's variables
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
#   stubs     (11.14) the production scan, and the stubs gate: an enabled item that answers "not implemented" refuses the candidate
#   ci        (11.14) the pushed commit's runs through the gh shim: pass, wait, fail; only run list is called
#   eval      (11.14) the author's evaluation result: pass, REL-5's override, and every other result refused
#   override  (11.14) no option, variable or record line overrides a gate; a gate's exit status and section must both pass
#   upgrade   (11.14) the harness drive: one phase per call, in cmd_run's order, one run tag, down always
#   rehearsal (11.14) the rehearsal drive: rehearse.sh run once per call, exit 4 and 75 wait, 3 is a dry run
#   checklist (11.14) the checklist after the notes, then the hands-on stop that never passes
#   fail      (11.14) each gate that fails stops the sequence at it, in the record, and runs again on the next call
#   real      (11.14) the real checklist.sh (IA1), eval/run.sh --override with notes.sh (IA2) and rehearse.sh (IA3)
#   secret    a full run prints, records and logs no value of the environment, calls no docker push or login, and the scan finds a
#             planted line
#   first     (QA) every first version but 1.0.0 is refused with nothing written
#   word      (QA) only the line yes proceeds; no option, variable or terminal answers in advance
#   pushes    (QA) exactly two pushes, each to the local bare remote and named; the checkout never switched; the draft never leaves
#   static    mode, ASCII, the main guard, the forbidden commands and push forms
# Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root" || exit 1

live=0
live_gates=0
rules=""
for a in "$@"; do
  case $a in
    --live) live=1 ;;
    --live-gates) live_gates=1 ;;
    *) rules="$rules $a" ;;
  esac
done

# --- the real upgrade harness through the gate steps (IA4): --live-gates prepare|next|check|clean, one part per call ---
# The throwaway lives in ${TMPDIR:-/tmp}/ocutalon-rseq-lg-$OCUTALON_RUN_TAG between the calls: a clone of HEAD with its full history, a local
# bare remote, and the sequence's state. prepare cuts and pushes the candidate with the real npm and docker and clears ci (a gh shim) and eval (a
# fixture); each next runs one phase of the real harness; check compares the record with the gate's row; clean removes what the run made.
if [ "$live_gates" -eq 1 ]; then
  lg_part=${rules# }
  lg_tag=${OCUTALON_RUN_TAG:-}
  case $lg_part in
    prepare | next | check | clean) ;;
    *)
      echo "usage: bash docker/tests/test-release-sequence.sh --live-gates prepare|next|check|clean   (with OCUTALON_RUN_TAG and the lane's variables)"
      exit 2
      ;;
  esac
  case $lg_tag in
    '' | *[!a-z0-9-]* | *slot*)
      echo "REFUSED --live-gates needs OCUTALON_RUN_TAG: lower-case letters, digits and hyphens, no 'slot'"
      exit 2
      ;;
  esac
  LG=${TMPDIR:-/tmp}
  LG=${LG%/}/ocutalon-rseq-lg-$lg_tag
  LGW=$LG/w
  LGR=$LG/r.git
  LGS=$LG/state
  LGI=feature/OCT_OcuTalon_MVP
  export OCUTALON_RELEASE_STATE=$LGS GIT_CONFIG_GLOBAL=$LG/gitconfig GIT_CONFIG_NOSYSTEM=1 OCUTALON_RELEASE_GH_REPO=test/repo
  unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN OCUTALON_RELEASE_NOW
  lg_rel() { # lg_rel <answers> <args>...: release.sh in the throwaway's checkout, with the gh shim first on the path
    local ans=$1
    shift
    (cd "$LGW" && printf '%s' "$ans" | PATH="$LG/bin:$PATH" bash release/release.sh "$@" 2>&1)
  }
  lg_state() { sed -n "s/^$1=//p" "$LGS/1.0.0-rc1/state.env" 2> /dev/null; }
  lg_leftovers() { # lg_leftovers <tag>: what a harness run of the tag leaves
    {
      docker ps -a --format '{{.Names}}' | grep -- "$1"
      docker images --format '{{.Repository}}:{{.Tag}}' | grep -- "$1"
      docker volume ls --format '{{.Name}}' | grep -- "$1"
      docker network ls --format '{{.Name}}' | grep -- "$1"
      ls -d "${TMPDIR:-/tmp}"/ocutalon-upgrade-"$1"* 2> /dev/null
    } 2> /dev/null | grep -c . || true
  }
  case $lg_part in
    prepare)
      if [ -e "$LG" ]; then
        echo "REFUSED $LG exists: run --live-gates clean first"
        exit 2
      fi
      mkdir -p "$LG/bin" || exit 1
      git config -f "$GIT_CONFIG_GLOBAL" user.name "Release Test"
      git config -f "$GIT_CONFIG_GLOBAL" user.email "release-test@example.invalid"
      git config -f "$GIT_CONFIG_GLOBAL" init.defaultBranch main
      git clone -q "$root" "$LGW" || exit 1
      git -C "$LGW" checkout -q -b "$LGI" || exit 1
      cp -p "$root/release/release.sh" "$root/release/lib-release.sh" "$LGW/release/"
      git -C "$LGW" add -A
      git -C "$LGW" commit -q --allow-empty -m "live gates: the scripts of the working tree"
      git clone -q --bare "$LGW" "$LGR" || exit 1
      git -C "$LGW" remote set-url origin "$LGR"
      case $(git -C "$LGW" remote get-url origin) in
        "$LG"/*) ;;
        *)
          echo "FAIL the throwaway's remote is not a local path"
          exit 1
          ;;
      esac
      cat > "$LG/bin/gh" << 'EOGH'
#!/bin/sh
case "$1 $2" in
  "run list") echo '[{"conclusion":"success","databaseId":101,"status":"completed","url":"u","workflowName":"ci"},{"conclusion":"success","databaseId":102,"status":"completed","url":"u","workflowName":"lane-a"}]' ;;
  *) exit 1 ;;
esac
EOGH
      chmod 755 "$LG/bin/gh"
      echo "LIVE-GATES prepare: start, cut, image, stubs, push, ci and eval (real npm and docker for the cut and the image)"
      lg_rel "yes
" start --version 1.0.0 | tail -n 2
      lg_rel '' next | tail -n 2
      lg_rel '' next | tail -n 2
      lg_rel '' next | tail -n 2
      lg_rel "yes
" next | tail -n 2
      lg_rel '' next | tail -n 2
      lg_rel '' next | tail -n 3
      lg_cand=$(lg_state cand_sha)
      mkdir -p "$LGS/1.0.0-rc1/eval/eval"
      printf '{"format":"ocutalon.evalResult/1","commit":"%s","onMock":false,"treeClean":true,"verdict":"pass","override":null}\n' "$lg_cand" > "$LGS/1.0.0-rc1/eval/eval/release-candidate.json"
      lg_rel '' next | tail -n 3
      if [ "$(lg_state next)" != upgrade ]; then
        echo "FAIL live-gates prepare: the state names '$(lg_state next)', not upgrade"
        exit 1
      fi
      echo "PASS live-gates prepare: $LG, candidate $lg_cand, next upgrade"
      exit 0
      ;;
    next)
      [ -d "$LGW" ] || {
        echo "REFUSED no throwaway for the tag: run --live-gates prepare first"
        exit 2
      }
      lg_out=$(lg_rel '' next)
      lg_rc=$?
      printf '%s\n' "$lg_out" | tail -n 12
      echo "LIVE-GATES next exit $lg_rc, the state names '$(lg_state next)' phase '$(lg_state upg_phase)'"
      exit 0
      ;;
    check)
      lg_cand=$(lg_state cand_sha)
      lg_rec=$LGW/release/records/1.0.0/rc1.md
      lg_bad=0
      lg_res=$(sed -n '/^## Upgrade harness/,/^## /p' "$lg_rec" 2> /dev/null | sed -n 's/^Result: //p' | head -n 1)
      lg_cl=$(sed -n '/^## Upgrade harness/,/^## /p' "$lg_rec" 2> /dev/null | sed -n 's/^Candidate: //p' | head -n 1)
      lg_mode=$(sed -n '/^## Upgrade harness/,/^## /p' "$lg_rec" 2> /dev/null | sed -n 's/^Mode: //p' | head -n 1)
      lg_row=$(grep "^upgrade$(printf '\t')" "$LGS/1.0.0-rc1/rows.tsv" 2> /dev/null | tail -n 1)
      lg_rrow=$(printf '%s' "$lg_row" | cut -f2)
      lg_rdet=$(printf '%s' "$lg_row" | cut -f3)
      echo "LIVE-GATES check: the record's Result '$lg_res', Mode '$lg_mode', Candidate '$lg_cl'; the sequence's row '$lg_rrow': $lg_rdet"
      [ -n "$lg_res" ] || { echo "FAIL the record has no ## Upgrade harness section from the real harness"; lg_bad=1; }
      [ "$lg_cl" = "1.0.0 at $lg_cand" ] || { echo "FAIL the section's Candidate is not the cut commit $lg_cand"; lg_bad=1; }
      [ "$lg_mode" = release ] || { echo "FAIL the section's Mode is not release"; lg_bad=1; }
      if [ "$lg_res" = pass ]; then
        [ "$lg_rrow" = pass ] || { echo "FAIL the harness says pass and the row says '$lg_rrow'"; lg_bad=1; }
      else
        [ "$lg_rrow" = fail ] || { echo "FAIL the harness says '$lg_res' and the row says '$lg_rrow'"; lg_bad=1; }
        case $lg_rdet in *"Result: $lg_res"*) ;; *) echo "FAIL the row does not say the harness's Result"; lg_bad=1 ;; esac
      fi
      [ "$lg_bad" -eq 0 ] || exit 1
      echo "PASS live-gates check: the upgrade row matches the real harness's Result ($lg_res)"
      exit 0
      ;;
    clean)
      docker info > /dev/null 2>&1 || {
        echo "FAIL live-gates clean: docker is not reachable, so nothing could be checked"
        exit 1
      }
      lg_cd=$LGS/1.0.0-rc1/candidate
      [ -d "$lg_cd" ] || lg_cd=$LGW
      if [ -d "$lg_cd/release" ]; then
        (cd "$lg_cd" && OCUTALON_RUN_TAG=rel100rc1upg bash release/upgrade-harness.sh down < /dev/null 2>&1 | tail -n 2)
      fi
      rm -rf "$LG"
      lg_left=$(lg_leftovers rel100rc1upg)
      lg_img=$(docker images --format '{{.Repository}}' | grep -c ocutalon-release-check || true)
      if [ "$lg_left" != 0 ] || [ "$lg_img" != 0 ] || [ -e "$LG" ]; then
        echo "FAIL live-gates clean: $lg_left container, image, volume, network or folder of the run tag left; $lg_img check image(s); folder $([ -e "$LG" ] && echo left || echo removed)"
        exit 1
      fi
      echo "PASS live-gates clean: no container, image tag or folder of the run tag is left"
      exit 0
      ;;
  esac
fi

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
unset ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN OCUTALON_RELEASE_NOW
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
  -e) exec "$REAL_NODE" "$@" ;;
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
  export NETMARKS=$tmp/netmarks
  cat > "$tmp/bin/gh" << 'EOF'
#!/bin/sh
echo "$*" >> "$SHIMLOG/gh.log"
case "$1 $2" in
  "run list" | "run view") ;;
  *)
    : > "$NETMARKS/gh"
    exit 1
    ;;
esac
[ -f "$SHIMFLAGS/gh-fail" ] && exit 1
if [ -f "$SHIMFLAGS/gh.json" ]; then cat "$SHIMFLAGS/gh.json"; else echo '[]'; fi
exit 0
EOF
  chmod 755 "$tmp/bin/gh"
  for n in curl wget ssh nc; do
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

# mkseedbase: the files of HEAD that the scripts read, in one folder. The seeds are made from it on demand (seed_for).
mkseedbase() {
  local s=$tmp/seed-base
  mkdir -p "$s"
  if [ "$live" -eq 1 ]; then
    git -C "$root" archive HEAD | tar -x -C "$s" || exit 1
  else
    # Only what the sequence, the notes script, the harness, the stubs gate and the real gates read: the whole tree adds time and no case.
    git -C "$root" archive HEAD release ci docker/tests docker/Dockerfile .gitignore .dockerignore src/module.xml \
      src/ocutalon/cls/OcuTalon/Production.cls src/ocutalon/cls/OcuTalon/Channel/Telegram src/ocutalon/cls/OcuTalon/Demo/Orders/Production.cls \
      src/bridge/cls/OcuTalon/BridgeExample/Production.cls README.md web/package.json web/package-lock.json eval/run.sh \
      _bmad-output/implementation-artifacts/sprint-status.yaml _bmad-output/planning-artifacts/epics.md | tar -x -C "$s" || exit 1
  fi
}

mkgatestub() {
  cat > "$tmp/gatestub.sh" << 'EOSTUB'
#!/usr/bin/env bash
# A gate stub of docker/tests/test-release-sequence.sh: it stands in for release/upgrade-harness.sh, release/rehearse.sh and
# release/checklist.sh inside a throwaway candidate. It logs its call, writes the gate's section into the record from a fixture, and exits as
# the case's queue says (GATEFIX/<script>.<command>: one line per call, "<exit> [<section fixture>|none]").
root=$(cd "$(dirname "$0")/.." && pwd -P)
me=$(basename "$0" .sh)
. "$root/release/lib-release.sh"
cmd=${1:-}
case $me in checklist) cmd=check ;; esac
rec="" notes="" prev=""
for a in "$@"; do
  case $prev in
    --record) rec=$a ;;
    --notes) notes=$a ;;
  esac
  prev=$a
done
sha=$(git -C "$root" rev-parse HEAD)
dirty=$(git -C "$root" status --porcelain | wc -l | tr -d ' ')
printf '%s %s | tag=%s dir=%s head=%s dirty=%s notes=%s\n' "$me" "$*" "${OCUTALON_RUN_TAG:-}" "$(basename "$root")" "$sha" "$dirty" \
  "$([ -n "$notes" ] && [ -f "$notes" ] && echo yes || echo no)" >> "$GATELOG"
q=$GATEFIX/$me.$cmd
code=0
sec=""
if [ -s "$q" ]; then
  line=$(head -n 1 "$q")
  tail -n +2 "$q" > "$q.new"
  mv "$q.new" "$q"
  code=${line%% *}
  sec=${line#"$code"}
  sec=${sec# }
fi
if [ "$me:$cmd" = upgrade-harness:build ] && [ -n "$rec" ]; then printf '%s\n' "$rec" > "$GATEFIX/upgrade.record"; fi
if [ "$me:$cmd" = upgrade-harness:report ]; then rec=$(cat "$GATEFIX/upgrade.record" 2> /dev/null); fi
write=0
case $me:$cmd in
  upgrade-harness:report | checklist:check) write=1 ;;
  rehearse:run)
    case $code in 0 | 1 | 3) write=1 ;; esac
    ;;
esac
case $code in
  4)
    n=$(cat "$GATEFIX/rehearse.n" 2> /dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$GATEFIX/rehearse.n"
    echo "NEXT run: planted step $n"
    ;;
  75) echo "LOCK busy: planted" ;;
  2) echo "REFUSED planted refusal" ;;
  1) [ "$me" != rehearse ] || echo "FAIL run 2 step demo bound notice 60 s in 19 of 20: planted miss" ;;
  *) echo "PHASE $cmd done 1s (0 failed)" ;;
esac
if [ "$write" = 1 ] && [ -n "$rec" ] && [ "$sec" != none ]; then
  t=$(mktemp "${TMPDIR:-/tmp}/gatestub.XXXXXX")
  if [ -n "$sec" ] && [ -f "$GATEFIX/$sec" ]; then
    near=$(printf '%.7s' "$sha")0000000000000000000000000000000000
    sed -e "s/@SHA@/$sha/g" -e "s/@NEAR@/$near/g" -e "s/@SHORT@/$(printf '%.7s' "$sha")/g" "$GATEFIX/$sec" > "$t"
  else
    res=pass
    [ "$code" = 0 ] || res=fail
    case $me in
      upgrade-harness)
        printf '## Upgrade harness\n\nResult: %s\nMode: release\nRequired: no\nCandidate: 1.0.0 at %s\nPrevious: pre-release c9f1288\n' "$res" "$sha" > "$t"
        ;;
      rehearse)
        mode=rehearsal
        if [ "$code" = 3 ]; then res="dry run"; mode="dry run"; fi
        printf '## Clean-machine rehearsal\nResult: %s\nMode: %s\nCandidate: 1.0.0 rc1, branch release/1.0.0-rc1 at %s\n' "$res" "$mode" "$sha" > "$t"
        ;;
      checklist)
        printf '## Release checklist\n\nResult: %s\nCandidate: 1.0.0 rc1 at %s\n' "$res" "$sha" > "$t"
        ;;
    esac
  fi
  record_write "$rec" "$t"
  rm -f "$t"
fi
exit "$code"
EOSTUB
  chmod 755 "$tmp/gatestub.sh"
}

# seed_for <variant>: prints the seed repository of a variant, made on first use: one commit on the integration branch, the scripts of the
# working tree on top. stub has gate stubs for the harness, the rehearsal and the checklist; chk keeps the real checklist, reh the real
# rehearsal, and real has no stub.
seed_for() {
  local v=$1 s=$tmp/seed.$1 f
  if [ ! -d "$s/.git" ]; then
    cp -R "$tmp/seed-base" "$s"
    cp -p "$root/release/release.sh" "$root/release/lib-release.sh" "$s/release/"
    case $v in
      stub) for f in upgrade-harness rehearse checklist; do cp -p "$tmp/gatestub.sh" "$s/release/$f.sh"; done ;;
      chk) for f in upgrade-harness rehearse; do cp -p "$tmp/gatestub.sh" "$s/release/$f.sh"; done ;;
      reh) for f in upgrade-harness checklist; do cp -p "$tmp/gatestub.sh" "$s/release/$f.sh"; done ;;
    esac
    git init -q -b "$INTEG" "$s" || exit 1
    git -C "$s" add -A
    git -C "$s" commit -q -m seed
  fi
  printf '%s\n' "$s"
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

# newcase [<variant>]: a new case on a new copy of the seed (default: gate stubs).
newcase() {
  local seed
  case_n=$((case_n + 1))
  C=$tmp/c$case_n
  W=$C/w
  R=$C/r.git
  seed=$(seed_for "${1:-stub}")
  mkdir -p "$C/flags" "$C/shim" "$C/shimstate"
  git clone -q --bare "$seed" "$R" || exit 1
  git clone -q "$R" "$W" || exit 1
  net_check "$W" || exit 1
  case_env
  ghgreen
  RS_PATH=""
  EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
}

# case_env: the environment of the case in C: the state, the shims' folders, the gate fixtures and the gh repository seam.
case_env() {
  export OCUTALON_RELEASE_STATE=$C/state
  export SHIMLOG=$C/shim SHIMFLAGS=$C/flags SHIMSTATE=$C/shimstate
  mkdir -p "$C/gate" "$C/flags" "$C/shim" "$C/shimstate"
  export GATEFIX=$C/gate GATELOG=$C/gate/calls.log
  : > "$GATELOG"
  export OCUTALON_RELEASE_GH_REPO=test/repo
  unset OCUTALON_RELEASE_NOW
}

# snap_case <name> / fork_case <name>: a copy of a case at a step, and a new case that starts from it.
snap_case() {
  rm -rf "${tmp:?}/snap.$1"
  cp -R "$C" "$tmp/snap.$1"
}
fork_case() {
  case_n=$((case_n + 1))
  C=$tmp/c$case_n
  W=$C/w
  R=$C/r.git
  cp -R "$tmp/snap.$1" "$C"
  git -C "$W" remote set-url origin "$R"
  net_check "$W" || exit 1
  rm -rf "$C/gate" "$C/flags" "$C/shim" "$C/shimstate"
  case_env
  ghgreen
  RS_PATH=""
  EXPECT_BASE=$(sed -n 's/^base_sha=//p' "$C/state/1.0.0-rc1/state.env")
}

# ghjson <workflow:status:conclusion:id>...: the gh shim's answer to run list (a conclusion is empty while a run is not completed).
ghjson() {
  local a first=1 name st cc id
  {
    printf '['
    for a in "$@"; do
      IFS=: read -r name st cc id << EOT
$a
EOT
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{"conclusion":"%s","databaseId":%s,"status":"%s","url":"https://example.invalid/%s","workflowName":"%s"}' "$cc" "$id" "$st" "$id" "$name"
    done
    printf ']\n'
  } > "$C/flags/gh.json"
}
ghgreen() { ghjson ci:completed:success:101 lane-a:completed:success:102; }

# queue <script.command> <line>...: the answers of the gate stub to its next calls ("<exit> [<section fixture>|none]").
queue() {
  local f=$1
  shift
  printf '%s\n' "$@" >> "$GATEFIX/$f"
}

# state_get <key> [<rc>]: a value of the state of rc1 (or of the given rc).
state_get() { sed -n "s/^$1=//p" "$OCUTALON_RELEASE_STATE/1.0.0-${2:-rc1}/state.env" 2> /dev/null; }

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

# put_eval <kind> [<reason>] [<rc>]: the author's evaluation result in the eval clone of the sequence. kinds: pass, blocked, incomplete, mock,
# commit (another commit), dirty, format, overridden (with the reason), noreason, nullreason, nomock, weird, json (not JSON).
put_eval() {
  local n=${3:-1} d sha mock=false clean=true verdict=pass ov=null fmt=ocutalon.evalResult/1 commit mockfield
  d=$OCUTALON_RELEASE_STATE/1.0.0-rc$n/eval/eval
  sha=$(cand "$n")
  commit=$sha
  mockfield='"onMock":false,'
  case $1 in
    pass) ;;
    blocked) verdict=blocked ;;
    incomplete) verdict=incomplete ;;
    mock) mockfield='"onMock":true,' ;;
    nomock) mockfield='' ;;
    commit) commit=0000000000000000000000000000000000000000 ;;
    dirty) clean=false ;;
    format) fmt=ocutalon.evalResult/2 ;;
    overridden) verdict=overridden ov="{\"reason\":\"$2\",\"at\":\"2026-11-01T10:00:00Z\"}" ;;
    noreason) verdict=overridden ov='{"reason":"","at":"2026-11-01T10:00:00Z"}' ;;
    nullreason) verdict=overridden ;;
    weird) verdict=weird ;;
  esac
  mkdir -p "$d"
  if [ "$1" = json ]; then
    echo 'this is not json' > "$d/release-candidate.json"
  else
    printf '{"format":"%s","commit":"%s",%s"treeClean":%s,"verdict":"%s","override":%s}\n' "$fmt" "$commit" "$mockfield" "$clean" "$verdict" "$ov" > "$d/release-candidate.json"
  fi
  printf '# Release-candidate result\n\nVerdict: %s\n' "$verdict" > "$d/release-candidate.md"
}

# drive_until <step> [<rc>]: runs next until the state names <step> (the push answered yes, the evaluation written when it is asked for,
# every other question left unanswered). A call that fails or waits for anything else sets bad.
drive_until() {
  local until=$1 n=${2:-1} guard=0 want opt=""
  [ "$n" = 1 ] || opt="--version 1.0.0 --rc $n"
  while :; do
    want=$(state_get next "rc$n")
    if [ "$want" = "$until" ] || [ "$want" = done ]; then return 0; fi
    guard=$((guard + 1))
    if [ "$guard" -gt 40 ]; then
      echo "  drive_until $until: too many calls"
      bad=1
      return 1
    fi
    # shellcheck disable=SC2086
    case $want in
      push) rs "$Y" next $opt ;;
      *) rs '' next $opt ;;
    esac
    case $rc in
      0) ;;
      5)
        case $out in
          *"WAIT eval"*) put_eval pass "" "$n" ;;
          *)
            echo "  drive_until $until: $want waits: $out"
            bad=1
            return 1
            ;;
        esac
        ;;
      *)
        echo "  drive_until $until: $want exit $rc: $out"
        bad=1
        return 1
        ;;
    esac
  done
}

# to_step <step>: start, then the successful steps up to it (the kit and the push answered yes, every gate green).
to_step() {
  rs "$Y" start --version 1.0.0
  case $1 in cut) return 0 ;; esac
  drive_until "$1"
}

# ensure_snap <name>: the snapshots of the gate chain: pushed (next ci), cleared (eval), evalwait (eval, clone made), evaled (upgrade),
# upgraded (rehearsal), rehearsed (notes), noted (checklist).
ensure_snap() {
  [ ! -d "$tmp/snap.$1" ] || return 0
  case $1 in
    pushed)
      newcase
      to_step ci
      ;;
    cleared)
      ensure_snap pushed
      fork_case pushed
      drive_until eval
      ;;
    evalwait)
      ensure_snap cleared
      fork_case cleared
      rs '' next
      ;;
    evaled)
      ensure_snap evalwait
      fork_case evalwait
      put_eval pass
      drive_until upgrade
      ;;
    upgraded)
      ensure_snap evaled
      fork_case evaled
      drive_until rehearsal
      ;;
    rehearsed)
      ensure_snap upgraded
      fork_case upgraded
      drive_until notes
      ;;
    noted)
      ensure_snap rehearsed
      fork_case rehearsed
      drive_until checklist
      ;;
  esac
  snap_case "$1"
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
  # record_field reads one field of one section
  printf '%s\n' "# Record" "" "## Upgrade harness" "Result: pass" "Results: no" "Mode: release" "" "## Clean-machine rehearsal" "Result: fail" "Candidate: 1.0.0 rc1 at abc" "### Runs" "Mode: inner" "## Last" "Note:   spaced  " > "$C/rec.md"
  eq "record_field: a field" "$(record_field "$C/rec.md" '## Upgrade harness' Result)" "pass"
  eq "record_field: the heading without ## " "$(record_field "$C/rec.md" 'Clean-machine rehearsal' Result)" "fail"
  eq "record_field: a field of the other section" "$(record_field "$C/rec.md" 'Clean-machine rehearsal' Candidate)" "1.0.0 rc1 at abc"
  eq "record_field: a field the section lacks" "$(record_field "$C/rec.md" 'Upgrade harness' Candidate)" ""
  eq "record_field: not a field of the next section" "$(record_field "$C/rec.md" 'Upgrade harness' Note)" ""
  eq "record_field: a ### line does not end the section" "$(record_field "$C/rec.md" 'Clean-machine rehearsal' Mode)" "inner"
  eq "record_field: the value is trimmed at its start" "$(record_field "$C/rec.md" 'Last' Note)" "spaced"
  eq "record_field: a missing section" "$(record_field "$C/rec.md" 'Nothing' Result)" ""
  eq "record_field: a missing file" "$(record_field "$C/none.md" 'Upgrade harness' Result)" ""
  # gh_repo
  unset OCUTALON_RELEASE_GH_REPO
  git remote add gh1 https://github.com/jbrandtmse/OcuTalon.git
  git remote add gh2 git@github.com:owner/repo.git
  git remote add gh3 https://token@github.com/owner/repo2
  git remote add gh4 https://example.invalid/owner/repo.git
  git remote add gh5 ssh://git@github.com/owner/repo3.git
  eq "gh_repo: an https URL" "$(gh_repo gh1)" "jbrandtmse/OcuTalon"
  eq "gh_repo: an ssh URL" "$(gh_repo gh2)" "owner/repo"
  eq "gh_repo: an URL with credentials, without the credentials" "$(gh_repo gh3)" "owner/repo2"
  eq "gh_repo: a ssh:// URL" "$(gh_repo gh5)" "owner/repo3"
  gh_repo gh4 > /dev/null
  eq "gh_repo: another host, no seam" "$?" "1"
  gh_repo origin > /dev/null
  eq "gh_repo: a local remote, no seam" "$?" "1"
  eq "gh_repo: the seam" "$(OCUTALON_RELEASE_GH_REPO=test/repo gh_repo origin)" "test/repo"
  eq "gh_repo: a github URL wins over the seam" "$(OCUTALON_RELEASE_GH_REPO=test/repo gh_repo gh2)" "owner/repo"
  eq "gh_repo: a bad seam" "$(OCUTALON_RELEASE_GH_REPO='a b/c' gh_repo origin; echo "rc=$?")" "rc=1"
  export OCUTALON_RELEASE_GH_REPO=test/repo
  # candidate_clone
  git branch -q release/1.0.0-rc4 "$EXPECT_BASE"
  git push -q origin release/1.0.0-rc4
  git tag v0.0.1 "$EXPECT_BASE"
  git push -q origin v0.0.1
  candidate_clone "$C/cl" 1.0.0 4 "$EXPECT_BASE" origin
  eq "candidate_clone: status" "$?" 0
  eq "candidate_clone: HEAD is the candidate" "$(git -C "$C/cl" rev-parse HEAD)" "$EXPECT_BASE"
  eq "candidate_clone: on the candidate branch" "$(git -C "$C/cl" symbolic-ref --short HEAD)" "release/1.0.0-rc4"
  eq "candidate_clone: full history" "$(git -C "$C/cl" rev-parse --is-shallow-repository)" "false"
  has "candidate_clone: the tags" "$(git -C "$C/cl" tag --list | tr '\n' ' ')" "v0.0.1 "
  eq "candidate_clone: the author's checkout is untouched" "$(git symbolic-ref --short HEAD)" "$INTEG"
  : > "$C/cl/marker"
  candidate_clone "$C/cl" 1.0.0 4 "$EXPECT_BASE" origin
  eq "candidate_clone: a clone at the commit is kept" "$([ -f "$C/cl/marker" ] && echo kept)" "kept"
  candidate_clone "$C/cl" 1.0.0 4 0000000000000000000000000000000000000000 origin
  eq "candidate_clone: another commit than the remote's branch" "$?" "1"
  has "candidate_clone: the reason" "$CLONE_WHY" "does not hold release/1.0.0-rc4 at the cut commit"
  git -C "$C/cl" checkout -q --detach HEAD~0
  git -C "$C/cl" commit -q --allow-empty -m moved
  candidate_clone "$C/cl" 1.0.0 4 "$EXPECT_BASE" origin
  eq "candidate_clone: a moved HEAD is cloned again" "$(git -C "$C/cl" rev-parse HEAD):$([ -f "$C/cl/marker" ] && echo kept)" "$EXPECT_BASE:"
  candidate_clone "$C/cl2" 1.0.0 9 "$EXPECT_BASE" origin
  eq "candidate_clone: a branch the remote lacks" "$?" "1"
  eq "candidate_clone: no folder is left" "$([ -e "$C/cl2" ] && echo left)" ""
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
  has "image: the next step" "$out" "NEXT stubs"
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
  has "the retry names the stubs gate" "$out" "NEXT stubs"
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
  # the stop of an unanswered question, with the record question at the end of input; the author's draft is moved away first, since the
  # notes step never replaces a draft
  rm -f "$W/release/records/1.0.0/rc1-notes.md"
  unflag lie
  rs '' next
  has "image passes" "$out" "NEXT stubs"
  rs '' next
  has "the stubs gate passes" "$out" "NEXT push"
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
  drive_until hands-on
  rs "$Y" next
  has "record yes: pushed" "$out" "PASS record pushed"
  has "pushed record row" "$(cat "$(rec_file)")" "| record | pushed | committed to $INTEG and pushed on the author's word |"
  has "the record was committed with its final row" "$(git -C "$W" show "HEAD:release/records/1.0.0/rc1.md")" "| record | pushed | "
  eq "the remote holds the record commit" "$(rhead)" "$(git -C "$W" rev-parse HEAD)"
  eq "the record commit changed only the record" "$(git -C "$W" show --name-only --format= HEAD)" "release/records/1.0.0/rc1.md"
  # a moved integration branch is reported, never merged
  ensure_snap noted
  fork_case noted
  rs '' next
  git clone -q "$R" "$C/o"
  echo "their work" > "$C/o/theirs.txt"
  git -C "$C/o" add theirs.txt
  git -C "$C/o" commit -q -m "someone else"
  git -C "$C/o" push -q origin "$INTEG"
  rs "$Y" next
  eq "a moved branch: exit (the hands-on stop)" "$rc" 4
  has "a moved branch: the line" "$out" "FAIL record not pushed: $INTEG moved on origin; bring the checkout up to date and run release.sh resume"
  has "a moved branch: the row" "$(cat "$(rec_file)")" "| record | not pushed | not pushed: $INTEG moved on origin |"
  eq "a moved branch: the remote is as the other clone left it" "$(rhead)" "$(git -C "$C/o" rev-parse HEAD)"
  git -C "$W" pull -q --rebase origin "$INTEG" > /dev/null 2>&1
  rs "$Y" resume
  eq "resume after the update: exit (the hands-on stop)" "$rc" 4
  has "resume after the update: pushed" "$out" "PASS record pushed"
  eq "resume after the update: the remote holds the local head" "$(rhead)" "$(git -C "$W" rev-parse HEAD)"
  rs '' next --version 1.0.0 --rc 1
  has "the hands-on gate is still the step" "$out" "STOPPED hands-on the hands-on gate is Story 11.15's"
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
  # kit 1000-1100, push question 2000-2060, the push time 2070, record question 3000-3041; two more lines that nothing may read
  clockfile 1000 1100 2000 2060 2070 3000 3041 3100 3200
  rs "$Y" start --version 1.0.0
  eq "kit window: the state" "$(sed -n 's/^handson=//p' "$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env")" 100
  drive_until hands-on
  rs "$Y" next
  has "the sum of the windows" "$(cat "$(rec_file)")" "Hands-on time: 3 min 21 s for this candidate; 3 min 21 s for 1.0.0 so far (target at most 15 min; CI and the hands-on pass not counted)"
  lacks "no warning" "$out" "WARN hands-on"
  eq "a step's own run time does not count: the seam file has lines left" "$(wc -l < "$C/now" | tr -d ' ')" 2
  eq "the status" "$(cd "$W" && PATH="$PATH" "$BASH" release/release.sh status --version 1.0.0 --rc 1 | grep '^Hands-on')" "Hands-on time: 3 min 21 s for this candidate; 3 min 21 s for 1.0.0 so far (target at most 15 min; CI and the hands-on pass not counted)"
  # a second candidate adds to the version's sum (its cut fails, which stops it with the record question)
  clockfile 4000 4030 5000 5020
  flag npm-fail
  rs "$Y" start --version 1.0.0
  has "rc2" "$out" "START 1.0.0 rc2 "
  rs "$Y" next --version 1.0.0 --rc 2
  has "this candidate and the version" "$(cat "$(rec_file 2)")" "Hands-on time: 50 s for this candidate; 4 min 11 s for 1.0.0 so far (target"
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
  drive_until hands-on
  rs '' status
  has "status at the hands-on gate" "$out" "STATE 1.0.0 rc1 next hands-on"
  rs '' next
  eq "the hands-on stop: exit" "$rc" 4
  has "the hands-on stop" "$out" "STOPPED hands-on the hands-on gate is Story 11.15's"
  rs '' next
  has "the hands-on gate does not pass, and nothing is run again" "$out" "STOPPED hands-on"
  rs '' status
  has "status after the stop" "$out" "STATE 1.0.0 rc1 next hands-on"
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

# notes_stub <exit> <result>: a throwaway whose notes.sh prints <result> (nothing when empty) and exits <exit>; runs the steps up to and
# including notes, and (when notes passed) on to the hands-on stop, which writes the record. NOTES_OUT and NOTES_RC are the notes call's.
NOTES_OUT=""
NOTES_RC=0
notes_stub() {
  ensure_snap rehearsed
  fork_case rehearsed
  printf '#!/bin/sh\n' > "$W/release/notes.sh"
  if [ -n "$2" ]; then
    printf 'echo "NOTES release/records/1.0.0/rc1-notes.md"\necho "RESULT %s"\n' "$2" >> "$W/release/notes.sh"
  fi
  printf 'exit %s\n' "$1" >> "$W/release/notes.sh"
  rs "$N" next
  NOTES_OUT=$out
  NOTES_RC=$rc
  if [ "$rc" -eq 0 ]; then
    drive_until hands-on
    rs "$N" next
  fi
}

t_notes() {
  local n res alone
  notes_stub 0 draft
  eq "a draft: exit" "$NOTES_RC" 0
  has "a draft: the line" "$NOTES_OUT" "PASS notes RESULT draft NOTES release/records/1.0.0/rc1-notes.md"
  lacks "a draft: no warning" "$NOTES_OUT" "WARN notes"
  has "a draft: the row" "$(cat "$(rec_file)")" "| notes | draft | release/notes.sh: RESULT draft; draft release/records/1.0.0/rc1-notes.md (not committed) |"
  notes_stub 3 "dry run"
  has "a dry run: the line" "$NOTES_OUT" "PASS notes RESULT dry run NOTES"
  lacks "a dry run: no warning" "$NOTES_OUT" "WARN notes"
  has "a dry run: the row" "$(cat "$(rec_file)")" "| notes | dry run | release/notes.sh: RESULT dry run; "
  notes_stub 0 ""
  eq "no result: exit" "$NOTES_RC" 1
  has "no result: the line" "$NOTES_OUT" "FAIL notes release/notes.sh printed no RESULT"
  fork_case rehearsed
  rs '' next
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
  alone=$(cd "$W" && "$BASH" release/notes.sh --version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --record release/records/1.0.0/rc1.md --eval "$OCUTALON_RELEASE_STATE/1.0.0-rc1/release-candidate.json" --notes "$C/alone.md" | sed -n 's/^RESULT //p')
  eq "the same result as the script alone, with the same evaluation" "$res" "$alone"
  eq "the draft exists" "$([ -f "$W/$n" ] && echo yes)" yes
  eq "the draft is untracked" "$(git -C "$W" status --porcelain -- "$n")" "?? $n"
  eq "the draft is in no commit" "$(git -C "$W" log --all --format=%H -- "$n")" ""
  eq "the draft is not on the remote" "$(git --git-dir="$R" log --all --format=%H -- "$n")" ""
  drive_until hands-on
  rs "$N" next
  has "the row carries the result and the path" "$(cat "$(rec_file)")" "| notes | $res | release/notes.sh: RESULT $res; draft $n (not committed) |"
  # a draft that exists is a refusal: the step fails, the draft is kept
  fork_case rehearsed
  mkdir -p "$W/release/records/1.0.0"
  echo "keep me" > "$W/$n"
  rs "$N" next
  eq "an existing draft: exit" "$rc" 1
  has "an existing draft: the line" "$out" "FAIL notes release/notes.sh refused: "
  eq "an existing draft is kept" "$(cat "$W/$n")" "keep me"
  has "an existing draft: the row" "$(cat "$(rec_file)")" "| notes | fail | release/notes.sh refused: "
}

# --- gate ---

t_gate() {
  local before after cl
  newcase real
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  # another gate's section is already in the record when the sequence writes its own
  mkdir -p "$W/release/records/1.0.0"
  printf '# OcuTalon 1.0.0 rc1\n\n## Clean-machine rehearsal\nResult: not run\nMode: dry run\n' > "$(rec_file)"
  rs "$N" next
  eq "the push is left unanswered: exit" "$rc" 4
  has "the sequence kept the other gate's section" "$(cat "$(rec_file)")" "## Clean-machine rehearsal
Result: not run
Mode: dry run"
  before=$(awk '/^## Release sequence/ { f = 1; print; next } f && /^## / { exit } f { print }' "$(rec_file)")
  rs "$Y" next
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
  has "status still reads the record" "$out" "Result: stopped at push: waiting for the author's word"
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
      else if (line ~ /git[ \t]+push[^|;&]*(--force|--tags|--all|--mirror|--delete| -f |[ \t]\+)/) bad()
      else if (line ~ /git[^|;&]*[ \t]tag([ \t]|$)/ && line !~ /--list|--merged|--points-at/) bad()
    }' "$@"
}

t_secret() {
  local d f hits plant p
  newcase
  rs "$Y" start --version 1.0.0
  drive_until push
  rs '' status
  eq "the run ended well" "$rc" 0
  # every case of the test so far (the gate chain included) is searched: the output of every call is in alloutput
  hits=$(grep -rl --exclude-dir=candidate --exclude-dir=eval "$OCUTALON_TEST_SECRET" "$tmp/alloutput" "$tmp"/c*/shim "$tmp"/c*/gate "$tmp"/c*/state "$tmp"/c*/w/release/records 2> /dev/null)
  eq "the planted value is in no output, record, state, gate log or shim log" "$hits" ""
  eq "no docker push, login, save or export" "$(cat "$tmp"/c*/shim/docker.log | grep -cE '^(push|login|save|export)')" 0
  eq "no docker compose or inspect call" "$(cat "$tmp"/c*/shim/docker.log | grep -cE '^(compose|inspect)')" 0
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
  plant=$(grep -rl "$OCUTALON_TEST_SECRET" "$tmp"/c*/shim "$tmp"/c*/gate "$tmp/alloutput" 2> /dev/null)
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
  git -C "$W" branch scratch-branch
  rs "$Y" start --version 1.0.0
  drive_until hands-on
  rs "$Y" next
  eq "two pushes: the last exit (the hands-on stop)" "$rc" 4
  has "a full run: the record was pushed" "$out" "PASS record pushed"
  has "a full run: the result" "$out" "RESULT stopped"
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
  eq "the checkout's branches are the integration branch, the candidate and the author's own" "$(git -C "$W" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ')" "$INTEG release/1.0.0-rc1 scratch-branch "
  # the draft exists and is in no commit, locally or on the remote (DW-560)
  n=release/records/1.0.0/rc1-notes.md
  eq "the draft exists in the checkout" "$([ -f "$W/$n" ] && echo yes)" yes
  eq "the draft is untracked" "$(git -C "$W" status --porcelain -- "$n")" "?? $n"
  eq "the draft is in no object of the local history" "$(git -C "$W" log --all --format=%H -- "$n")" ""
  eq "the draft is in no tree of the candidate" "$(git -C "$W" ls-tree -r --name-only release/1.0.0-rc1 | grep -c 'rc1-notes.md')" 0
  eq "the remote's integration tree holds the record and no draft" "$(git --git-dir="$R" ls-tree -r --name-only "$INTEG" -- release/records | tr '\n' ' ')" "release/records/1.0.0/rc1.md "
  eq "the remote's candidate tree holds no draft" "$(git --git-dir="$R" ls-tree -r --name-only release/1.0.0-rc1 | grep -c 'rc1-notes.md')" 0
  eq "the remote has no tag" "$(git --git-dir="$R" for-each-ref refs/tags | wc -l | tr -d ' ')" 0
  eq "the refs of the remote" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | sort | tr '\n' ' ')" "refs/heads/$INTEG refs/heads/release/1.0.0-rc1 "
  eq "the author's own tag is not on the remote, nor main" "$(git --git-dir="$R" for-each-ref --format='%(refname)' | grep -c -e 'refs/tags' -e '/main$')" 0
  eq "the integration branch is a fast-forward of the old one" "$(git --git-dir="$R" merge-base --is-ancestor "$EXPECT_BASE" "$(rhead)" && echo yes)" yes
  eq "one record commit" "$(git --git-dir="$R" rev-list --count "$EXPECT_BASE..$INTEG")" 1
  eq "the local branch equals the remote" "$(git -C "$W" rev-parse "$INTEG")" "$(rhead)"
  eq "only the record changed" "$(git --git-dir="$R" diff --name-only "$EXPECT_BASE" "$(rhead)")" "release/records/1.0.0/rc1.md"
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

# --- the gates (Story 11.14) ---

# put_sec <fixture> <title> <result> <mode> <candidate line>: a section fixture for the gate stub (@SHA@ stands for the candidate's sha, @NEAR@ for a 40-character sha that shares its first seven characters, @SHORT@ for those seven).
put_sec() {
  {
    printf '## %s\n' "$2"
    [ "$2" != "Release checklist" ] || printf '\n'
    printf 'Result: %s\n' "$3"
    [ -z "$4" ] || printf 'Mode: %s\n' "$4"
    printf 'Candidate: %s\n' "$5"
  } > "$GATEFIX/$1"
}

# state_set <key> <value>: sets a value in the state of rc1 (a test shortcut to a later phase of a gate).
state_set() {
  local f=$OCUTALON_RELEASE_STATE/1.0.0-rc1/state.env
  grep -v "^$1=" "$f" > "$f.new"
  mv "$f.new" "$f"
  printf '%s=%s\n' "$1" "$2" >> "$f"
}

# row_of <step>: the row of a step in the state.
row_of() { grep "^$1$(printf '\t')" "$OCUTALON_RELEASE_STATE/1.0.0-rc1/rows.tsv" | tail -n 1 | tr '\t' '|'; }

# --- stubs ---

t_stubs() {
  local d v t
  . "$root/release/lib-release.sh"
  d=$tmp/stubtree
  rm -rf "$d"
  mkdir -p "$d/src/fx/cls/Fx/Test"
  cat > "$d/src/fx/cls/Fx/Base.cls" << 'EOC'
/// A stub.
Class Fx.Base Extends Ens.BusinessService
{

/// Not built yet.
Parameter STUB = 1;

}
EOC
  printf 'Class Fx.Sub Extends (Fx.Base, Ens.Util.Dummy) [ ProcedureBlock ]\n{\n\n}\n' > "$d/src/fx/cls/Fx/Sub.cls"
  printf 'Class Fx.Built Extends Ens.BusinessService\n{\n\n}\n' > "$d/src/fx/cls/Fx/Built.cls"
  printf 'Class Fx.Off Extends Ens.BusinessService\n{\n\nParameter STUB = 0;\n\n}\n' > "$d/src/fx/cls/Fx/Off.cls"
  printf 'Class Fx.Cm Extends Ens.BusinessService\n{\n\n// Parameter STUB = 1;\n\n}\n' > "$d/src/fx/cls/Fx/Cm.cls"
  cat > "$d/src/fx/cls/Fx/Production.cls" << 'EOC'
Class Fx.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Fx.Production" TestingEnabled="false">
  <Item Name="A" ClassName="Fx.Built" PoolSize="1" Enabled="true"/>
  <Item Name="B" ClassName="Fx.Base" PoolSize="1" Enabled="false"/>
  <Item Name="C" ClassName="Fx.Sub" PoolSize="1"/>
  <Item Name="D" ClassName="Fx.Base" PoolSize="1" Enabled="0"/>
  <Item Name="O" ClassName="Fx.Off" PoolSize="1" Enabled="true"/>
  <Item Name="K" ClassName="Fx.Cm" PoolSize="1" Enabled="true"/>
  <!-- <Item Name="E" ClassName="Fx.Base" PoolSize="1" Enabled="true"/> -->
  <Item Name="F"
        ClassName="Fx.Base"
        PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="X">1</Setting>
  </Item>
</Production>
}

}
EOC
  cat > "$d/src/fx/cls/Fx/Test/Production.cls" << 'EOC'
Class Fx.Test.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Fx.Test.Production" TestingEnabled="false">
  <Item Name="T" ClassName="Fx.Base" PoolSize="1" Enabled="true"/>
</Production>
}

}
EOC
  v=$(production_stubs "$d")
  eq "production_stubs on the fixture: status" "$?" 1
  eq "production_stubs on the fixture: the enabled stubs and the counts" "$v" "FOUND|Fx.Production|C|Fx.Sub
FOUND|Fx.Production|F|Fx.Base
COUNTS|7|1|2|2"
  rm -f "$d/src/fx/cls/Fx/Production.cls.new"
  sed -e '/Name="C"/d' -e '/Name="F"$/,/<\/Item>/d' "$d/src/fx/cls/Fx/Production.cls" > "$d/p.new"
  mv "$d/p.new" "$d/src/fx/cls/Fx/Production.cls"
  v=$(production_stubs "$d")
  eq "production_stubs without the enabled stubs: status" "$?" 0
  eq "production_stubs without the enabled stubs: the counts" "$v" "COUNTS|5|1|2|0"
  v=$(production_stubs "$tmp/nothing")
  eq "production_stubs of a tree with no production: status" "$?" 2
  # a subclass that sets STUB = 0, a continued Extends list, single quotes, CRLF and a folder with a space
  rm -rf "$tmp/stubtree3"
  mkdir -p "$tmp/stubtree3/src/fx/cls/Fx" "$tmp/stubtree3/src/fx sp/cls/Fx"
  printf 'Class Fx.Base Extends Ens.BusinessService\n{\n\nParameter STUB = 1;\n\n}\n' > "$tmp/stubtree3/src/fx/cls/Fx/Base.cls"
  printf 'Class Fx.Built Extends Fx.Base\n{\n\nParameter STUB = 0;\n\n}\n' > "$tmp/stubtree3/src/fx/cls/Fx/Built.cls"
  printf 'Class Fx.Cont Extends (Ens.Util.Dummy,\n    Fx.Base)\n{\n\n}\n' > "$tmp/stubtree3/src/fx/cls/Fx/Cont.cls"
  printf 'Class Fx.P1 Extends Ens.Production\r\n{\r\n\r\nXData ProductionDefinition\r\n{\r\n<Production Name="Fx.P1">\r\n  <Item Name="Built" ClassName="Fx.Built" Enabled="true"/>\r\n  <Item Name="Cont" ClassName="Fx.Cont" Enabled="true"/>\r\n</Production>\r\n}\r\n\r\n}\r\n' > "$tmp/stubtree3/src/fx/cls/Fx/P1.cls"
  printf "Class Fx.P2 Extends Ens.Production\n{\n\nXData ProductionDefinition\n{\n<Production Name='Fx.P2'>\n  <Item Name='Q' ClassName='Fx.Base' Enabled='true'/>\n</Production>\n}\n\n}\n" > "$tmp/stubtree3/src/fx/cls/Fx/P2.cls"
  printf 'Class Fx.P3 Extends Ens.Production\n{\n\nXData ProductionDefinition\n{\n<Production Name="Fx.P3">\n  <Item Name="Sp" ClassName="Fx.Base"/>\n</Production>\n}\n\n}\n' > "$tmp/stubtree3/src/fx sp/cls/Fx/P3.cls"
  v=$(production_stubs "$tmp/stubtree3")
  eq "production_stubs on the edge fixture: status" "$?" 1
  has "a continued Extends list finds the stub superclass" "$v" "FOUND|Fx.P1|Cont|Fx.Cont"
  lacks "a subclass that sets STUB = 0 is not a stub (CRLF file)" "$v" "|Built|"
  has "single-quoted attributes are read" "$v" "FOUND|Fx.P2|Q|Fx.Base"
  has "a folder with a space is scanned" "$v" "FOUND|Fx.P3|Sp|Fx.Base"
  has "the edge fixture's counts" "$v" "COUNTS|4|3|0|3"
  # the real tree: no enabled stub; TelegramIn and TelegramOut are stubs, disabled
  v=$(production_stubs "$tmp/seed-base")
  eq "production_stubs on the real tree: status" "$?" 0
  lacks "production_stubs on the real tree: no enabled stub" "$v" "FOUND"
  has "production_stubs on the real tree: the counts" "$v" "COUNTS|"
  has "production_stubs on the real tree: three productions" "$v" "|3|"
  rm -rf "$tmp/stubtree2"
  mkdir -p "$tmp/stubtree2"
  cp -R "$tmp/seed-base/src" "$tmp/stubtree2/src"
  sed 's|\(Name="TelegramIn".*\) Enabled="false"|\1 Enabled="true"|' "$tmp/seed-base/src/ocutalon/cls/OcuTalon/Production.cls" > "$tmp/stubtree2/src/ocutalon/cls/OcuTalon/Production.cls"
  v=$(production_stubs "$tmp/stubtree2")
  eq "production_stubs with TelegramIn enabled: status" "$?" 1
  has "production_stubs with TelegramIn enabled: reported" "$v" "FOUND|OcuTalon.Production|TelegramIn|OcuTalon.Channel.Telegram.In"
  # the sequence: the real tree passes
  newcase
  to_step stubs
  rs '' next
  eq "stubs on the real tree: exit" "$rc" 0
  has "stubs on the real tree: the line" "$out" "PASS stubs "
  has "stubs on the real tree: the next step" "$out" "NEXT push"
  has "stubs on the real tree: the row counts items and productions" "$(row_of stubs)" "items in 3 productions checked, 2 stub item(s), all disabled"
  # an enabled stub refuses the candidate before any push question
  for v in true removed; do
    newcase
    case $v in
      true) sed 's|\(Name="TelegramIn".*\) Enabled="false"|\1 Enabled="true"|' "$W/src/ocutalon/cls/OcuTalon/Production.cls" > "$W/p.new" ;;
      removed) sed 's|\(Name="TelegramIn".*\) Enabled="false"|\1|' "$W/src/ocutalon/cls/OcuTalon/Production.cls" > "$W/p.new" ;;
    esac
    mv "$W/p.new" "$W/src/ocutalon/cls/OcuTalon/Production.cls"
    git -C "$W" commit -q -am "enable TelegramIn ($v)"
    git -C "$W" push -q origin "$INTEG"
    EXPECT_BASE=$(git -C "$W" rev-parse HEAD)
    rs "$Y" start --version 1.0.0
    rs '' next
    rs '' next
    rs '' next
    eq "stubs, TelegramIn $v: exit" "$rc" 1
    has "stubs, TelegramIn $v: the line" "$out" 'FAIL stubs OcuTalon.Production:TelegramIn (OcuTalon.Channel.Telegram.In) answers "not implemented"'
    lacks "stubs, TelegramIn $v: no push question" "$out" "ASK push"
    eq "stubs, TelegramIn $v: the remote is unchanged" "$(git --git-dir="$R" for-each-ref --format='%(objectname) %(refname)')" "$EXPECT_BASE refs/heads/$INTEG"
    has "stubs, TelegramIn $v: the record" "$(cat "$(rec_file)")" 'Result: failed at stubs: OcuTalon.Production:TelegramIn (OcuTalon.Channel.Telegram.In) answers "not implemented"'
    has "stubs, TelegramIn $v: the row" "$(cat "$(rec_file)")" "| stubs | fail | OcuTalon.Production:TelegramIn "
    eq "stubs, TelegramIn $v: the step stays" "$(state_get next)" stubs
    rs '' next
    has "stubs, TelegramIn $v: the next call runs the gate again" "$out" "FAIL stubs OcuTalon.Production:TelegramIn"
    lacks "stubs, TelegramIn $v: the push is not reached" "$out" "ASK push"
    eq "stubs, TelegramIn $v: still nothing pushed" "$(git --git-dir="$R" for-each-ref refs/heads/release | wc -l | tr -d ' ')" 0
  done
}

# --- ci ---

t_ci() {
  local sha short pushed head
  ensure_snap pushed
  fork_case pushed
  sha=$(cand)
  short=${sha%"${sha#???????}"}
  pushed=$(state_get pushed_at)
  head=$(git -C "$W" rev-parse HEAD)
  ghjson ci:in_progress::101 lane-a:completed:success:102
  rs '' next
  eq "a run in progress: exit" "$rc" 5
  has "a run in progress: the line" "$out" "WAIT ci ci run 101 in_progress"
  lacks "a run in progress: no question" "$out" "ASK "
  lacks "a run in progress: no record" "$out" "RECORD"
  eq "a run in progress: no record commit" "$(git -C "$W" rev-parse HEAD)" "$head"
  eq "a run in progress: no record file" "$([ -e "$(rec_file)" ] && echo yes || echo no)" no
  eq "a run in progress: the step stays" "$(state_get next)" ci
  ghjson ci:queued::101 lane-a:queued::102
  rs '' next
  eq "queued runs: exit" "$rc" 5
  has "queued runs: the line" "$out" "WAIT ci ci run 101 queued, lane-a run 102 queued"
  ghjson
  clockfile $((pushed + 899))
  rs '' next
  eq "no run 14 min 59 s after the push: exit" "$rc" 5
  has "no run yet: the line" "$out" "WAIT ci no ci, lane-a run on $short yet"
  eq "no run yet: no record commit" "$(git -C "$W" rev-parse HEAD)" "$head"
  clockfile $((pushed + 900))
  rs '' next
  has "both workflows missing 15 min after the push: both are named" "$out" "FAIL ci no ci, lane-a run on $short"
  ghjson lane-a:completed:success:102
  clockfile $((pushed + 900))
  rs '' next
  eq "ci missing 15 min after the push: exit" "$rc" 1
  has "ci missing 15 min after the push: the line" "$out" "FAIL ci no ci run on $short"
  has "ci missing: the record" "$(cat "$(rec_file)")" "Result: failed at ci: no ci run on $short"
  ghjson ci:completed:success:101
  clockfile $((pushed + 900))
  rs '' next
  has "lane-a missing 15 min after the push" "$out" "FAIL ci no lane-a run on $short"
  ghjson lane-a:completed:failure:102
  clockfile $((pushed + 1))
  rs '' next
  has "a red run is a failure before the 15 minutes" "$out" "FAIL ci lane-a run 102 failure"
  ghjson ci:completed:success:101 lane-a:completed:failure:102
  rs '' next
  eq "a red lane-a: exit" "$rc" 1
  has "a red lane-a: the line" "$out" "FAIL ci lane-a run 102 failure"
  has "a red lane-a: the record" "$(cat "$(rec_file)")" "Result: failed at ci: lane-a run 102 failure"
  has "a red lane-a: the row" "$(cat "$(rec_file)")" "| ci | fail | lane-a run 102 failure |"
  eq "a red lane-a: the step stays" "$(state_get next)" ci
  ghjson ci:completed:cancelled:103 lane-a:completed:success:102
  rs '' next
  has "a cancelled run" "$out" "FAIL ci ci run 103 cancelled"
  ghjson ci:completed:skipped:103 lane-a:completed:success:102
  rs '' next
  has "a skipped run" "$out" "FAIL ci ci run 103 skipped"
  ghjson ci:completed:success:101 lane-a:completed:success:102 other:completed:failure:104
  rs '' next
  has "another workflow that is red" "$out" "FAIL ci other run 104 failure"
  ghjson ci:completed:success:101 lane-a:completed:success:102 other:in_progress::104
  rs '' next
  eq "another workflow in progress: exit" "$rc" 5
  ghjson ci:completed:failure:90 ci:completed:success:101 lane-a:completed:success:102
  rs '' next
  eq "an older red run and a newer green one: exit" "$rc" 0
  has "the newest run of a workflow counts" "$out" "PASS ci ci run 101; lane-a run 102"
  fork_case pushed
  ghjson ci:completed:success:90 ci:completed:failure:101 lane-a:completed:success:102
  rs '' next
  has "an older green run and a newer red one" "$out" "FAIL ci ci run 101 failure"
  flag gh-fail
  rs '' next
  has "gh fails" "$out" "FAIL ci gh run list failed"
  unflag gh-fail
  echo 'not json' > "$C/flags/gh.json"
  rs '' next
  has "gh prints no list" "$out" "FAIL ci gh run list printed no list of runs"
  export OCUTALON_RELEASE_GH_REPO=
  ghgreen
  rs '' next
  export OCUTALON_RELEASE_GH_REPO=test/repo
  has "a remote that is not on github.com" "$out" "FAIL ci origin is not a github.com repository, so its runs cannot be read"
  fork_case pushed
  ghjson
  state_set pushed_at ""
  clockfile $((pushed + 5))
  rs '' next
  eq "no recorded push time: the wait starts now: exit" "$rc" 5
  eq "no recorded push time: it is kept for the next call" "$(state_get pushed_at)" "$((pushed + 5))"
  clockfile $((pushed + 5 + 900))
  rs '' next
  eq "no recorded push time: the 15 minutes still end" "$rc" 1
  has "no recorded push time: the line" "$out" "FAIL ci no ci, lane-a run on $short"
  fork_case pushed
  ghgreen
  rs '' next
  eq "all push runs green: exit" "$rc" 0
  has "all push runs green: the line" "$out" "PASS ci ci run 101; lane-a run 102"
  has "all push runs green: the next step" "$out" "NEXT eval"
  has "all push runs green: the row" "$(row_of ci)" "ci|pass|every push run of $short concluded success: ci run 101; lane-a run 102"
  # the shim saw run list only, with the candidate's branch, commit and the push event
  has "gh: the call" "$(cat "$SHIMLOG/gh.log")" "run list --repo test/repo --branch release/1.0.0-rc1 --commit $sha --event push"
  eq "gh: every call is run list" "$(grep -vc '^run list ' "$SHIMLOG/gh.log")" 0
  eq "gh: nothing but a read was attempted" "$(ls "$tmp/netmarks" | tr '\n' ' ')" ""
}

# --- eval ---

# eval_case <kind> <reason> <want exit> <want text> <want row>: one accepted evaluation result in a fresh copy of the waiting case.
eval_case() {
  fork_case evalwait
  put_eval "$1" "$2"
  rs '' next
  eq "eval $1: exit" "$rc" "$3"
  has "eval $1: the line" "$out" "$4"
  has "eval $1: the next step" "$out" "NEXT upgrade"
  has "eval $1: the row" "$(row_of eval)" "$5"
  eq "eval $1: the result is kept" "$(cmp "$OCUTALON_RELEASE_STATE/1.0.0-rc1/release-candidate.json" "$OCUTALON_RELEASE_STATE/1.0.0-rc1/eval/eval/release-candidate.json" && echo same)" same
}

# eval_bad <kind> <reason> <want text>: one refused evaluation result; the case stays at the eval step, so the next one is tried in it.
eval_bad() {
  put_eval "$1" "$2"
  rs '' next
  eq "eval $1: exit" "$rc" 1
  has "eval $1: the line" "$out" "$3"
  has "eval $1: the row" "$(row_of eval)" "eval|fail|"
  eq "eval $1: nothing is kept" "$([ -e "$OCUTALON_RELEASE_STATE/1.0.0-rc1/release-candidate.json" ] && echo yes || echo no)" no
  eq "eval $1: the step stays" "$(state_get next)" eval
}

t_eval() {
  local sha
  ensure_snap evalwait
  fork_case cleared
  sha=$(cand)
  rs '' next
  eq "no result yet: exit" "$rc" 5
  has "no result yet: the line" "$out" "WAIT eval no evaluation result of ${sha%"${sha#???????}"} yet"
  eq "no result yet: one RUN line" "$(printf '%s\n' "$out" | grep -c '^RUN ')" 1
  has "no result yet: the command" "$out" "&& bash eval/run.sh --release-candidate"
  lacks "no result yet: no key and no question" "$out" "ASK "
  eq "no result yet: the eval clone is at the candidate" "$(git -C "$OCUTALON_RELEASE_STATE/1.0.0-rc1/eval" rev-parse HEAD)" "$sha"
  eq "no result yet: no record" "$([ -e "$(rec_file)" ] && echo yes || echo no)" no
  eval_case pass "" 0 "PASS eval pass" "eval|pass|pass: the real model's result for the candidate, tree clean"
  eval_case overridden "fixture reason" 0 "PASS eval overridden (REL-5): fixture reason" "eval|overridden|overridden (REL-5): fixture reason"
  fork_case evalwait
  eval_bad blocked "" "FAIL eval the verdict is blocked (REL-5: the author may override it with eval/run.sh --override"
  eval_bad incomplete "" "FAIL eval the verdict is incomplete"
  eval_bad mock "" "FAIL eval the result ran on the mock"
  eval_bad nomock "" "FAIL eval the result ran on the mock"
  eval_bad commit "" "FAIL eval the result is of another commit (0000000)"
  eval_bad dirty "" "FAIL eval the result was made on a tree that was not clean"
  eval_bad format "" "FAIL eval the result file is of an unknown format"
  eval_bad noreason "" "FAIL eval the result is overridden with no reason"
  eval_bad nullreason "" "FAIL eval the result is overridden with no reason"
  eval_bad weird "" "FAIL eval the verdict is weird"
  eval_bad json "" "FAIL eval the result file is not valid JSON"
  has "eval: the record names the gate" "$(cat "$(rec_file)")" "Result: failed at eval: "
  # the file is read again by the next call
  fork_case evalwait
  put_eval blocked
  rs '' next
  eq "blocked, then overridden: the first call fails" "$rc" 1
  put_eval overridden "after the fact"
  rs '' next
  eq "blocked, then overridden: the next call reads the file again" "$rc" 0
  has "blocked, then overridden: passes with the reason" "$out" "PASS eval overridden (REL-5): after the fact"
}

# --- override ---

# upg_at <phase>: the upgrade gate at a later phase of its drive (a test shortcut), with the harness stub's record named.
upg_at() {
  state_set upg_phase "$1"
  state_set upg_fail 0
  state_set upg_why ""
  printf '%s\n' "$(rec_file)" > "$GATEFIX/upgrade.record"
}

# run_gate_calls <pattern>: next, until the output holds the pattern (at most 12 calls).
run_gate_calls() {
  local n=0
  while [ "$n" -lt 12 ]; do
    rs '' next
    n=$((n + 1))
    case $out in *"$1"*) return 0 ;; esac
  done
  echo "  run_gate_calls: no '$1' after 12 calls"
  bad=1
  return 1
}

t_override() {
  local o before v
  ensure_snap evaled
  fork_case evaled
  before=$(snap)
  for o in --skip --force "--override x" --no-gate --ignore-gate "--skip upgrade"; do
    # shellcheck disable=SC2086
    rs '' next $o
    eq "next $o: exit" "$rc" 2
    has "next $o: refused" "$out" "REFUSED unknown option"
    # shellcheck disable=SC2086
    rs '' resume $o
    eq "resume $o: exit" "$rc" 2
    # shellcheck disable=SC2086
    rs "$Y" start --version 1.0.0 $o
    eq "start $o: exit" "$rc" 2
    has "start $o: refused" "$out" "REFUSED unknown option"
  done
  eq "the options change nothing" "$(snap)" "$before"
  eq "the gate stubs were not called" "$(wc -l < "$GATELOG" | tr -d ' ')" 0
  # no variable, state value or record line passes a gate
  fork_case pushed
  ghjson ci:completed:success:101 lane-a:completed:failure:102
  export OCUTALON_RELEASE_SKIP=ci OCUTALON_RELEASE_FORCE=1 OCUTALON_RELEASE_OVERRIDE=1 OCUTALON_SKIP_GATES=1 SKIP_GATES=1 FORCE=1
  mkdir -p "$W/release/records/1.0.0"
  printf '# OcuTalon 1.0.0 rc1\n\n## Overrides\n- ci: overridden\nGates skipped: ci\nSkip: ci\nForce: yes\n' > "$(rec_file)"
  state_set skip ci
  state_set force 1
  rs '' next
  unset OCUTALON_RELEASE_SKIP OCUTALON_RELEASE_FORCE OCUTALON_RELEASE_OVERRIDE OCUTALON_SKIP_GATES SKIP_GATES FORCE
  eq "variables, state and record lines do not skip ci: exit" "$rc" 1
  has "variables, state and record lines do not skip ci" "$out" "FAIL ci lane-a run 102 failure"
  # a gate that exits 1 with a planted pass, 0 with a fail, or a section naming another candidate
  fork_case evaled
  put_sec upg.pass "Upgrade harness" pass release "1.0.0 at @SHA@"
  put_sec upg.fail "Upgrade harness" fail release "1.0.0 at @SHA@"
  put_sec upg.other "Upgrade harness" pass release "1.0.0 at 0000000000000000000000000000000000000000"
  put_sec upg.dry "Upgrade harness" pass "dry run" "1.0.0 at @SHA@"
  put_sec upg.reh "Upgrade harness" pass rehearsal "1.0.0 at @SHA@"
  put_sec upg.nores "Upgrade harness" "" release "1.0.0 at @SHA@"
  put_sec upg.near "Upgrade harness" pass release "1.0.0 at @NEAR@"
  put_sec upg.short "Upgrade harness" pass release "1.0.0 at @SHORT@"
  upg_at report
  queue upgrade-harness.report "1 upg.pass"
  run_gate_calls "FAIL upgrade"
  has "upgrade: exit 1 with a planted pass" "$out" "FAIL upgrade the script exited 1 although its section reads Result: pass"
  upg_at report
  queue upgrade-harness.report "0 upg.fail"
  run_gate_calls "FAIL upgrade"
  has "upgrade: exit 0 with Result: fail" "$out" "FAIL upgrade Result: fail"
  upg_at report
  queue upgrade-harness.report "0 upg.other"
  run_gate_calls "FAIL upgrade"
  has "upgrade: a section naming another candidate" "$out" "FAIL upgrade the section names another candidate than "
  upg_at report
  queue upgrade-harness.report "0 upg.dry"
  run_gate_calls "FAIL upgrade"
  has "upgrade: Mode: dry run" "$out" "FAIL upgrade Mode: dry run, wanted release"
  upg_at report
  queue upgrade-harness.report "0 upg.reh"
  run_gate_calls "FAIL upgrade"
  has "upgrade: Mode: rehearsal" "$out" "FAIL upgrade Mode: rehearsal, wanted release"
  upg_at report
  queue upgrade-harness.report "0 upg.near"
  run_gate_calls "FAIL upgrade"
  has "upgrade: a section naming a sha that shares the first seven characters" "$out" "FAIL upgrade the section names another candidate than "
  upg_at report
  queue upgrade-harness.report "0 upg.short"
  run_gate_calls "FAIL upgrade"
  has "upgrade: a section naming only the short sha" "$out" "FAIL upgrade the section names another candidate than "
  upg_at report
  queue upgrade-harness.report "0 upg.nores"
  run_gate_calls "FAIL upgrade"
  has "upgrade: a section with no Result" "$out" "FAIL upgrade the record has no Upgrade harness section with a Result"
  upg_at report
  queue upgrade-harness.report "0 none"
  run_gate_calls "FAIL upgrade"
  has "upgrade: a report that writes no section is judged on what the record holds" "$out" "FAIL upgrade"
  eq "upgrade: the state never advanced" "$(state_get next)" upgrade
  # the rehearsal, the same
  ensure_snap upgraded
  fork_case upgraded
  put_sec reh.pass "Clean-machine rehearsal" pass rehearsal "1.0.0 rc1, branch release/1.0.0-rc1 at @SHA@"
  put_sec reh.fail "Clean-machine rehearsal" fail rehearsal "1.0.0 rc1, branch release/1.0.0-rc1 at @SHA@"
  put_sec reh.dry "Clean-machine rehearsal" pass "dry run" "1.0.0 rc1, branch release/1.0.0-rc1 at @SHA@"
  put_sec reh.rel "Clean-machine rehearsal" pass release "1.0.0 rc1, branch release/1.0.0-rc1 at @SHA@"
  put_sec reh.other "Clean-machine rehearsal" pass rehearsal "1.0.0 rc1, branch release/1.0.0-rc1 at 0000000000000000000000000000000000000000"
  put_sec reh.near "Clean-machine rehearsal" pass rehearsal "1.0.0 rc1, branch release/1.0.0-rc1 at @NEAR@"
  for v in "1 reh.pass|FAIL rehearsal the script exited 1 although its section reads Result: pass" "0 reh.fail|FAIL rehearsal Result: fail" \
    "3 reh.pass|FAIL rehearsal the script exited 3 although its section reads Result: pass" \
    "0 reh.near|FAIL rehearsal the section names another candidate than " \
    "0 reh.dry|FAIL rehearsal Mode: dry run, wanted rehearsal" "0 reh.rel|FAIL rehearsal Mode: release, wanted rehearsal" \
    "0 reh.other|FAIL rehearsal the section names another candidate than "; do
    queue rehearse.run "${v%%|*}"
    rs '' next
    has "rehearsal: ${v%%|*}" "$out" "${v#*|}"
  done
  eq "rehearsal: the state never advanced" "$(state_get next)" rehearsal
  # the checklist, the same
  ensure_snap noted
  fork_case noted
  put_sec chk.pass "Release checklist" pass "" "1.0.0 rc1 at @SHA@"
  put_sec chk.other "Release checklist" pass "" "1.0.0 rc1 at 0000000000000000000000000000000000000000"
  put_sec chk.near "Release checklist" pass "" "1.0.0 rc1 at @NEAR@"
  queue checklist.check "1 chk.pass"
  rs '' next
  has "checklist: exit 1 with a planted pass" "$out" "FAIL checklist the script exited 1 although its section reads Result: pass"
  queue checklist.check "0 chk.other"
  rs '' next
  has "checklist: a section naming another candidate" "$out" "FAIL checklist the section names another candidate than "
  queue checklist.check "0 chk.near"
  rs '' next
  has "checklist: a section naming a sha that shares the first seven characters" "$out" "FAIL checklist the section names another candidate than "
}

# --- upgrade ---

t_upgrade() {
  local ph i expect harness_loop got log remote_was
  ensure_snap evaled
  fork_case evaled
  harness_loop=$(sed -n '/^cmd_run()/,/^}/p' "$root/release/upgrade-harness.sh" | sed -n 's/^  for ph in \(.*\); do$/\1/p')
  expect="build $harness_loop report down"
  eq "the harness drive's phases are cmd_run's: build, the loop, report, down" "$(sed -n '/^cmd_run()/,/^}/p' "$root/release/upgrade-harness.sh" | grep -E 'bash "\$me" (build|report|down)|for ph in' | sed 's/^ *//' | tr '\n' '|')" 'if ! bash "$me" build "${build_args[@]}"; then|bash "$me" down|for ph in settings seed upgrade restart storage; do|bash "$me" report || rc=1|bash "$me" down|'
  eq "release.sh's phase list equals cmd_run's" "$("$BASH" -c ". '$root/release/release.sh'; echo \"\$UPG_PHASES\"")" "$expect"
  i=0
  for ph in $expect; do
    rs '' next
    i=$((i + 1))
    got=$(tail -n 1 "$GATELOG" | awk '{ print $2 }')
    eq "upgrade call $i runs $ph" "$got" "$ph"
    eq "upgrade call $i: one more call of the stub" "$(wc -l < "$GATELOG" | tr -d ' ')" "$i"
    eq "upgrade call $i: exit" "$rc" 0
    if [ "$ph" = down ]; then
      has "the last phase passes the gate" "$out" "PASS upgrade Result pass, Mode release, Required no"
      has "the last phase names the next step" "$out" "NEXT rehearsal"
    else
      has "upgrade call $i: the step stays" "$out" "NEXT upgrade"
      lacks "upgrade call $i: no record" "$out" "RECORD"
    fi
  done
  log=$(cat "$GATELOG")
  eq "only build gets --version, --rc and --record" "$(grep -c -e '--version' -e '--rc' -e '--record' "$GATELOG")" 1
  has "build gets the version, the rc and the record" "$(sed -n 1p "$GATELOG")" "upgrade-harness build --version 1.0.0 --rc 1 --record $(rec_file) |"
  eq "one run tag on every call" "$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^tag=/) print $i }' "$GATELOG" | sort -u)" "tag=rel100rc1upg"
  eq "every phase ran in the candidate clone, at the candidate, clean" "$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^(dir|head|dirty)=/) printf "%s ", $i; print "" }' "$GATELOG" | sort -u)" "dir=candidate head=$(cand) dirty=0 "
  has "the row" "$(row_of upgrade)" "upgrade|pass|release/upgrade-harness.sh: Result pass, Mode release, Required no, candidate "
  # a failed build runs down and fails; a 75 repeats the phase; a failed seed does not stop the later phases
  fork_case evaled
  queue upgrade-harness.build 1
  rs '' next
  eq "a failed build: exit" "$rc" 1
  has "a failed build: the line" "$out" "FAIL upgrade the build phase exited 1"
  eq "a failed build runs down, and nothing else" "$(awk '{ print $2 }' "$GATELOG" | tr '\n' ' ')" "build down "
  has "a failed build: the record" "$(cat "$(rec_file)")" "Result: failed at upgrade: the build phase exited 1"
  rs '' next
  eq "the next call starts at build again" "$(awk '{ print $2 }' "$GATELOG" | tr '\n' ' ')" "build down build "
  queue upgrade-harness.settings 75
  rs '' next
  eq "a 75: exit" "$rc" 5
  has "a 75: the line" "$out" "WAIT upgrade the lane lock is busy; the settings phase runs again on the next call"
  rs '' next
  eq "the phase after a 75 is the same phase" "$(awk '{ print $2 }' "$GATELOG" | tr '\n' ' ')" "build down build settings settings "
  queue upgrade-harness.seed 1
  rs '' next
  has "a failed seed warns" "$out" "WARN upgrade the seed phase exited 1; the remaining phases still run"
  eq "a failed seed: exit" "$rc" 0
  rs '' next
  rs '' next
  rs '' next
  rs '' next
  eq "a failed seed does not stop restart, storage, report or down" "$(awk '{ print $2 }' "$GATELOG" | tr '\n' ' ')" "build down build settings settings seed upgrade restart storage report "
  rs '' next
  eq "the gate fails at the end: exit" "$rc" 1
  has "the gate fails at the end: the line" "$out" "FAIL upgrade the script exited 1 although its section reads Result: pass; phases that failed: seed(1)"
  eq "down always runs" "$(awk '{ print $2 }' "$GATELOG" | tail -n 1)" "down"
  eq "the step stays" "$(state_get next)" upgrade
  rs '' next
  eq "the next call starts the drive again, never the gate after it" "$(awk '{ print $2 }' "$GATELOG" | tail -n 1)" "build"
  lacks "no later gate ran" "$(cat "$GATELOG")" "rehearse "
  # a clone that fails in the middle of the drive keeps the phase, so the drive is never restarted over its leftovers
  fork_case evaled
  rs '' next
  rs '' next
  remote_was=$(state_get remote)
  state_set remote "$tmp/nowhere.git"
  rs '' next
  eq "a failed clone mid-drive: exit" "$rc" 1
  has "a failed clone mid-drive: the line" "$out" "FAIL upgrade "
  eq "a failed clone mid-drive: the phase stays" "$(state_get upg_phase)" seed
  state_set remote "$remote_was"
  rs '' next
  eq "the phase runs once the remote is back" "$(awk '{ print $2 }' "$GATELOG" | tail -n 1)" "seed"
  # a down that exits non-zero is reported, and the gate is judged on its report
  fork_case evaled
  queue upgrade-harness.down 1
  for ph in 1 2 3 4 5 6 7 8; do
    rs '' next
  done
  has "a failed down warns" "$out" "WARN upgrade the down phase exited 1; leftovers of run tag rel100rc1upg may remain"
  has "a failed down: the gate is still judged on its report" "$out" "PASS upgrade Result pass, Mode release"
}

# --- rehearsal ---

t_rehearsal() {
  local i
  ensure_snap upgraded
  fork_case upgraded
  queue rehearse.run 4 4 4 0
  for i in 1 2 3; do
    rs '' next
    eq "rehearsal call $i: exit" "$rc" 5
    has "rehearsal call $i: waits" "$out" "WAIT rehearsal planted step $i"
    lacks "rehearsal call $i: no record" "$out" "RECORD"
    lacks "rehearsal call $i: no question" "$out" "ASK "
    : > "$OCUTALON_RELEASE_STATE/1.0.0-rc1/candidate/marker"
  done
  rs '' next
  eq "rehearsal call 4: exit" "$rc" 0
  has "rehearsal call 4: passes" "$out" "PASS rehearsal Result pass, Mode rehearsal, 20 runs"
  has "rehearsal call 4: the next step" "$out" "NEXT notes"
  eq "four calls of rehearse.sh run, nothing else" "$(awk '{ print $1 " " $2 }' "$GATELOG" | tr '\n' ',')" "rehearse run,rehearse run,rehearse run,rehearse run,"
  eq "the same options on every call, and no --plant" "$(sed -e 's/ |.*$//' -e 's/^rehearse run //' "$GATELOG" | sort -u)" "--version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --record $(rec_file) --runs 20"
  eq "one run tag on every call" "$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^tag=/) print $i }' "$GATELOG" | sort -u)" "tag=rel100rc1reh"
  eq "every call ran in the same candidate clone, at the candidate" "$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^(dir|head)=/) printf "%s ", $i; print "" }' "$GATELOG" | sort -u)" "dir=candidate head=$(cand) "
  eq "the clone was kept between the calls" "$(sed -n 's/.*dirty=\([0-9]*\).*/\1/p' "$GATELOG" | tr '\n' ' ')" "0 1 1 1 "
  has "the row" "$(row_of rehearsal)" "rehearsal|pass|release/rehearse.sh run: Result pass, Mode rehearsal, 20 runs, candidate "
  # a dry run (exit 3), a failing run, a refusal, a 75, and the clone made again for the next attempt
  fork_case upgraded
  queue rehearse.run 3
  rs '' next
  eq "exit 3: exit" "$rc" 1
  has "exit 3 is a dry run, never a pass" "$out" "FAIL rehearsal Result: dry run (exit 3)"
  has "exit 3: the record" "$(cat "$(rec_file)")" "Result: failed at rehearsal: Result: dry run (exit 3)"
  : > "$OCUTALON_RELEASE_STATE/1.0.0-rc1/candidate/marker"
  put_sec reh.fail "Clean-machine rehearsal" fail rehearsal "1.0.0 rc1, branch release/1.0.0-rc1 at @SHA@"
  queue rehearse.run 4 4 "1 reh.fail"
  rs '' next
  eq "a failing run: the clone is made again for a new attempt" "$([ -e "$OCUTALON_RELEASE_STATE/1.0.0-rc1/candidate/marker" ] && echo kept || echo new)" new
  rs '' next
  rs '' next
  eq "a failing run: exit" "$rc" 1
  has "a failing run: the line" "$out" "FAIL rehearsal Result: fail (exit 1); first failure: FAIL run 2 step demo bound notice 60 s in 19 of 20: planted miss"
  queue rehearse.run 2
  rs '' next
  eq "a refusal: exit" "$rc" 1
  has "a refusal: the line names the script's refusal" "$out" "FAIL rehearsal release/rehearse.sh refused: REFUSED planted refusal"
  eq "a refusal is followed by down" "$(awk '{ print $2 }' "$GATELOG" | tail -n 1)" "down"
  queue rehearse.run 75
  rs '' next
  eq "a 75: exit" "$rc" 5
  has "a 75: the line" "$out" "WAIT rehearsal the lane lock is busy; the same phase runs again on the next call"
  lacks "a 75: no record" "$out" "RECORD"
  rs '' next
  eq "after a 75 the same call runs again" "$(awk '{ print $2 }' "$GATELOG" | tail -n 2 | tr '\n' ' ')" "run run "
  eq "the step stays" "$(state_get next)" "notes"
}

# --- checklist and hands-on ---

t_checklist() {
  local sec
  ensure_snap noted
  fork_case noted
  rs '' next
  eq "checklist: exit" "$rc" 0
  has "checklist: passes" "$out" "PASS checklist Result pass"
  has "checklist: the next step" "$out" "NEXT hands-on"
  eq "checklist ran once, in the candidate clone, after the notes" "$(grep -c . "$GATELOG")" 1
  has "checklist: the call" "$(cat "$GATELOG")" "checklist --version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --record $(rec_file) --notes $W/release/records/1.0.0/rc1-notes.md | tag= dir=candidate head=$(cand) dirty=0 notes=yes"
  rs "$Y" next
  eq "hands-on: exit" "$rc" 4
  has "hands-on: the stop" "$out" "STOPPED hands-on the hands-on gate is Story 11.15's"
  has "hands-on: the record is pushed on the word" "$out" "PASS record pushed"
  has "hands-on: the result" "$out" "RESULT stopped"
  has "hands-on: the record" "$(cat "$(rec_file)")" "Result: stopped at hands-on: every automated gate passed; no hands-on pass recorded (not a release)"
  has "hands-on: the row" "$(cat "$(rec_file)")" "| hands-on | not run | the hands-on gate is Story 11.15's; no hands-on pass is recorded |"
  sec=$(awk '/^## Release sequence/ { f = 1; next } f && /^## / { exit } f { print }' "$(rec_file)")
  lacks "hands-on is never a pass" "$sec" "| hands-on | pass"
  lacks "no line of the sequence reads Result: pass" "$sec" "Result: pass"
  eq "the state stays at hands-on" "$(state_get next)" hands-on
  eq "the record commit changed only the record" "$(git -C "$W" show --name-only --format= HEAD)" "release/records/1.0.0/rc1.md"
  rs '' next
  eq "hands-on again: exit" "$rc" 4
  has "hands-on again: the same stop" "$out" "STOPPED hands-on"
  # a checklist that is not pass stops the sequence at it
  fork_case noted
  put_sec chk.nc "Release checklist" "not confirmed" "" "1.0.0 rc1 at @SHA@"
  put_sec chk.fail "Release checklist" fail "" "1.0.0 rc1 at @SHA@"
  queue checklist.check "1 chk.nc" "1 chk.fail" "0 chk.nc" 2
  rs '' next
  eq "not confirmed: exit" "$rc" 1
  has "not confirmed: the line" "$out" "FAIL checklist Result: not confirmed (exit 1)"
  lacks "not confirmed: hands-on is not reached" "$out" "STOPPED hands-on"
  rs '' next
  has "fail: the line" "$out" "FAIL checklist Result: fail (exit 1)"
  rs '' next
  has "exit 0 with a section that is not pass" "$out" "FAIL checklist Result: not confirmed"
  rs '' next
  has "a refusal" "$out" "FAIL checklist release/checklist.sh refused: REFUSED planted refusal"
  eq "the step stays" "$(state_get next)" checklist
  rs '' next
  has "the checklist runs again and passes" "$out" "PASS checklist Result pass"
}

# --- fail: each gate that fails stops the sequence at it ---

t_fail() {
  local g snapn n before
  for g in ci eval upgrade rehearsal checklist; do
    case $g in
      ci) snapn=pushed ;;
      eval) snapn=evalwait ;;
      upgrade) snapn=evaled ;;
      rehearsal) snapn=upgraded ;;
      checklist) snapn=noted ;;
    esac
    ensure_snap "$snapn"
    fork_case "$snapn"
    case $g in
      ci) ghjson ci:completed:failure:101 lane-a:completed:success:102 ;;
      eval) put_eval blocked ;;
      upgrade) queue upgrade-harness.storage 1 ;;
      rehearsal)
        put_sec reh.fail "Clean-machine rehearsal" fail rehearsal "1.0.0 rc1, branch release/1.0.0-rc1 at @SHA@"
        queue rehearse.run "1 reh.fail" "1 reh.fail"
        ;;
      checklist)
        put_sec chk.fail "Release checklist" fail "" "1.0.0 rc1 at @SHA@"
        queue checklist.check "1 chk.fail" "1 chk.fail"
        ;;
    esac
    n=0
    while [ "$n" -lt 12 ]; do
      rs '' next
      n=$((n + 1))
      [ "$rc" -eq 0 ] || break
    done
    eq "$g fails: exit" "$rc" 1
    has "$g fails: the line" "$out" "FAIL $g "
    has "$g fails: the stop" "$out" "RESULT fail"
    has "$g fails: the record names the gate" "$(cat "$(rec_file)")" "Result: failed at $g: "
    has "$g fails: the record has the row" "$(cat "$(rec_file)")" "| $g | fail | "
    eq "$g fails: the record is committed" "$(git -C "$W" log -1 --format=%s)" "Record the release sequence of 1.0.0 rc1"
    eq "$g fails: the step stays" "$(state_get next)" "$g"
    case $g in
      ci | eval) eq "$g fails: no later gate ran" "$(grep -c . "$GATELOG")" 0 ;;
      upgrade) lacks "$g fails: no later gate ran" "$(cat "$GATELOG")" "rehearse " ;;
      rehearsal) lacks "$g fails: no later gate ran" "$(cat "$GATELOG")" "checklist " ;;
      checklist) lacks "$g fails: hands-on is not reached" "$out" "STOPPED hands-on" ;;
    esac
    before=$(grep -c . "$GATELOG")
    rs '' next
    case $g in
      upgrade)
        eq "$g: the next call runs the gate again, from its first phase" "$(awk '{ print $2 }' "$GATELOG" | tail -n 1)" build
        lacks "$g: and not the gate after it" "$(cat "$GATELOG")" "rehearse "
        ;;
      *)
        eq "$g: the next call runs the gate again: exit" "$rc" 1
        has "$g: the next call runs the gate again" "$out" "FAIL $g "
        case $g in
          rehearsal) lacks "$g: and not the gate after it" "$(cat "$GATELOG")" "checklist " ;;
          checklist) lacks "$g: and not the gate after it" "$out" "STOPPED hands-on" ;;
        esac
        ;;
    esac
    eq "$g: still at the gate" "$(state_get next)" "$g"
  done
}

# --- real: the real checklist (IA1), the real override with the real notes (IA2) and the real rehearsal (IA3) ---

t_real() {
  local before after r draft dl
  . "$root/release/lib-release.sh"
  # IA1: the real checklist.sh, with no author confirmations in the record
  newcase chk
  rs "$Y" start --version 1.0.0
  rs '' next
  rs '' next
  rs '' next
  rs "$N" next
  before=$(grep -E '^\| (kit|cut|image|stubs) \|' "$(rec_file)")
  has "checklist: the earlier rows are in the record" "$before" "| stubs | pass |"
  lacks "checklist: no author confirmations yet" "$(cat "$(rec_file)")" "## Author confirmations"
  drive_until checklist
  rs '' next
  eq "the real checklist: exit" "$rc" 1
  has "the real checklist: the line" "$out" "FAIL checklist Result: "
  r=$(record_field "$(rec_file)" "Release checklist" Result)
  case $r in
    fail | "not confirmed") ;;
    *)
      echo "  the real checklist: Result '$r'"
      bad=1
      ;;
  esac
  has "the real checklist: the section is in the record" "$(cat "$(rec_file)")" "## Release checklist"
  has "the real checklist: the row says what it printed" "$(cat "$(rec_file)")" "| checklist | fail | Result: $r (exit 1)"
  has "the real checklist: its own output" "$out" "checklist: RESULT $r"
  after=$(grep -E '^\| (kit|cut|image|stubs) \|' "$(rec_file)")
  eq "the other rows of the release sequence are byte for byte" "$after" "$before"
  for r in push ci eval upgrade rehearsal notes; do
    has "the record holds the sequence's row of $r" "$(cat "$(rec_file)")" "| $r | $(row_of "$r" | cut -d'|' -f2) |"
  done
  lacks "the sequence wrote no author confirmation" "$(cat "$(rec_file)")" "## Author confirmations"
  # IA2: a blocked result that the real eval/run.sh --override turns into an override, then the real notes.sh
  ensure_snap evalwait
  fork_case evalwait
  put_eval blocked
  (cd "$OCUTALON_RELEASE_STATE/1.0.0-rc1/eval" && "$BASH" eval/run.sh --override "fixture reason") > "$C/override.out" 2>&1
  eq "the real override: exit" "$?" 0
  has "the real override: recorded" "$(cat "$C/override.out")" "OVERRIDE recorded"
  rs '' next
  eq "an overridden result: exit" "$rc" 0
  has "an overridden result: the line" "$out" "PASS eval overridden (REL-5): fixture reason"
  has "an overridden result: the row" "$(row_of eval)" "eval|overridden|overridden (REL-5): fixture reason"
  state_set next notes
  rs '' next
  draft=$W/release/records/1.0.0/rc1-notes.md
  has "the real notes: the draft carries the override reason" "$(cat "$draft")" "fixture reason"
  state_set next hands-on
  rs '' next
  has "the record's row names the override" "$(cat "$(rec_file)")" "| eval | overridden | overridden (REL-5): fixture reason |"
  # IA3: the real rehearse.sh with no release.conf refuses, and starts no container
  newcase reh
  to_step rehearsal
  dl=$(grep -c . "$SHIMLOG/docker.log")
  mkdir -p "$tmp/rehtmp"
  export OCUTALON_RELEASE_CONFIG=$tmp/none/release.conf
  TMPDIR=$tmp/rehtmp rs '' next
  unset OCUTALON_RELEASE_CONFIG
  eq "the real rehearsal without release.conf: exit" "$rc" 1
  has "the real rehearsal without release.conf: the refusal" "$out" "FAIL rehearsal release/rehearse.sh refused: REFUSED config: the configuration file is missing or not readable"
  eq "the real rehearsal without release.conf: no container" "$(grep -c . "$SHIMLOG/docker.log")" "$dl"
  eq "the real rehearsal without release.conf: no state" "$(ls "$tmp/rehtmp" | grep -c rehearsal)" 0
  has "the real rehearsal without release.conf: the record" "$(cat "$(rec_file)")" "Result: failed at rehearsal: release/rehearse.sh refused: REFUSED config"
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
  eq "lib-release.sh: ASCII only" "$(LC_ALL=C grep -n '[^[:print:][:space:]]' "$root/release/lib-release.sh" | cut -d: -f1 | tr '\n' ' ')" ""
  eq "the tracked scripts are mode 100755" "$(git -C "$root" ls-files -s release/release.sh docker/tests/test-release-sequence.sh | awk '$1 != "100755" { print $4 }')" ""
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
  eq "the steps" "$("$BASH" -c ". '$root/release/release.sh'; echo \"\$STEPS\"")" "cut image stubs push ci eval upgrade rehearsal notes checklist hands-on"
  eq "the script lists runs with gh, once" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep -c 'gh run list --repo ')" 1
  eq "no gh call of the script changes anything" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep -cE '(^|[^[:alnum:]_./-])gh[ ]+(rerun|run[ ]+(rerun|cancel|delete|watch|download)|workflow|api|pr|release|repo|issue|secret|variable|auth|label|cache|codespace|gist|ssh-key|extension)')" 0
  eq "the script runs the rehearsal through gate_run, as run and as down" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep 'gate_run' | grep -c 'release/rehearse.sh \(run\|down\)')" 2
  eq "the script calls the rehearsal with run once, never install or runs" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep -cE 'release/rehearse.sh (run |install|runs|report)')" 1
  eq "no option, variable or record line skips, forces or overrides a gate" "$(grep -v '^[[:space:]]*#' "$root/release/release.sh" | grep -ciE -e '--skip|--force|--no-gate|--ignore-gate|RELEASE_SKIP|RELEASE_FORCE|RELEASE_OVERRIDE')" 0
  eq "both workflows build a release candidate" "$(grep -c '^      - "release/\*"$' "$root/.github/workflows/ci.yml" "$root/.github/workflows/lane-a.yml" | tr '\n' ' ' | sed 's#[^ ]*/##g')" "ci.yml:1 lane-a.yml:1 "
  eq "the planted value is in no output, record, state, gate log or shim log of any case of the whole test" "$(grep -rl --exclude-dir=candidate --exclude-dir=eval "$OCUTALON_TEST_SECRET" "$tmp/alloutput" "$tmp"/c*/shim "$tmp"/c*/gate "$tmp"/c*/state "$tmp"/c*/w/release/records 2> /dev/null)" ""
  eq "no workflow builds a rehearsal candidate" "$(grep -c 'rehearsal/' "$root/.github/workflows/ci.yml" "$root/.github/workflows/lane-a.yml" | sed 's#[^:]*:##' | tr '\n' ' ')" "0 0 "
}

# --- the real build (IA3) ---

live_run() {
  local ans c imgs
  newcase real
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
}

REAL_NODE=$(command -v node)
export REAL_NODE
mkshims
mkgatestub
export PATH="$tmp/bin:$PATH"
mkseedbase
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
rule first t_first
rule word t_word
rule pushes t_pushes
rule stubs t_stubs
rule ci t_ci
rule eval t_eval
rule override t_override
rule upgrade t_upgrade
rule rehearsal t_rehearsal
rule checklist t_checklist
rule fail t_fail
rule real t_real
rule static t_static

if [ "$fails_total" -eq 0 ]; then
  echo "PASS all rules"
  exit 0
fi
echo "FAIL $fails_total rule(s)"
exit 1
