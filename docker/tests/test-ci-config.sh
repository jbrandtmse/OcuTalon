#!/usr/bin/env bash
# Static pins of the CI configuration (Story 0.7; AD-22, AD-29; CON-1, REL-4). Starts nothing: it reads .github/workflows/*.yml,
# which have a fixed layout (two-space indent, one key per line, flow lists for runs-on and the matrix), ci/units.sh and the
# test folders. The rules, each shown first to flag its bad samples and to pass a good one, then run on the real files:
#   - permissions: the top level is exactly `contents: read`; a job-level block holds only contents: read and actions: read;
#   - triggers: push.branches is main, feature/OCT_OcuTalon_MVP and OCT-epic*; pull_request has no filter; no
#     pull_request_target, workflow_run, paths or paths-ignore, so the workflow itself is never skipped;
#   - concurrency: a push has a group of its own run id and is never cancelled; only a pull request cancels its superseded run;
#   - pins: every action is owner/repo@<40 hex> followed by a version comment, and no docker:// image;
#   - persist-credentials: every checkout sets persist-credentials: false;
#   - runners: ubuntu-24.04 or [self-hosted, ocutalon];
#   - fork-guard: every self-hosted job carries the job-level guard that keeps a fork's pull request off the IRIS runner;
#   - secrets: no secrets reference (a run block, any case, a bracket or the whole context, as in toJSON(secrets), included), and
#     github.token only as GH_TOKEN (the whole github context, which holds the token, counts as a use of it);
#   - image-actions: no docker/* action and no actions/cache anywhere, and no upload-artifact in a self-hosted job;
#   - teardown: every job that runs ci/iris.sh has a step with `if: always()` that runs ci/iris.sh teardown after the steps that
#     run it;
#   - matrix: the group list of ci.yml is `ci/iris.sh groups` (a matrix that is missing or not a flow list fails);
#   - wiring: ci.yml runs ci/checks.sh, each script of WEB_SCRIPTS (the web build and the mock's tests, the step "Mock tests" among
#     them), lint and unit tests, each gated by the classifier's web output; the iris job asks the classifier for its own group
#     (ci/changes.sh ci.yml --group <its group>), runs ci/iris.sh build and group unless the run output is `false`, and otherwise
#     runs the step Skipped with the reason; every step reads only step ids that exist, and the iris job sets the run tag, the
#     image and the deadline;
#   - units: every docker/tests/test-*.sh is in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or one group; every Test/<Area>/
#     folder of either source tree is in exactly one shard; every class with a Method Test... sits directly in an area folder;
#   - demo-path (Story 0.8): live:demo-path is a unit of exactly one IRIS group and docker/tests/test-demo-path.sh exists, every name
#     of BROWSER_UNITS (the live units that need Playwright's Chromium) is a live unit of a group, and every docker/tests/test-*.sh
#     with a code line, not a comment, that runs the Playwright npm script is in BROWSER_UNITS;
#   - groups: IRIS_GROUPS is exactly install-fresh, install-upgrade, production, browser, shards and image in this order, each with a
#     unit, and group_units has no case for the retired group install; install-fresh holds live:install-start, install-upgrade holds
#     live:install-upgrade, and live:demo-path is the first unit of browser (AD-22);
#   - inputs (Story 32.2): every unit of NO_WEB_BUNDLE_UNITS is a unit of a group and no live script of it has a code line that names the
#     web bundle (each of the markers alone is enough); group_input_pattern answers for each group with a pattern that matches
#     ci/units.sh, the workflow and src/, and for no unknown group; and every file that a live script of the group sources or adds
#     ($root/<file>, $(dirname "$0")/<file> in a code line) is claimed by the group's pattern;
#   - recipe: ci/iris.sh (with no OCUTALON_WARM from the caller: Story 32.4's warm mode has its own pins in test-ci-warm.sh) refuses a bad
#     run tag, an unknown shard, class, live unit or group with exit 2, and a missing base image with exit 1; its web port is 52810 plus the runner's number on runners 0 to 9 and 52819 minus it on runners 10 to 19, a set
#     OCUTALON_TEST_WEB_PORT wins (whatever the runner, none included), any other runner name (a number of 20 or more, a letter after
#     the number, none) and no runner leave `auto` (DW-49, Story 32.3), and the ports of runners 1 to 19 are distinct, within
#     52800-52819 and none in LIVE_FORBIDDEN_PORTS; the real live_web_port (port_in_use stubbed, nothing listens) accepts the fixed
#     port of each runner 0 to 19, which setup_tag exports to a child process, refuses it as in use when it is held without taking
#     another, and gives a probing runner 52800, which no runner 1 to 18 owns; `groups` prints the six groups in order, `list` shows the two install groups with their anchors,
#     the retired group install is refused with exit 2, and each group's CI tag (<run id>-<attempt>-<group>) is a valid run tag under
#     which `group <name>` knows the group;
#   - preflight (Story 0.11): the mock's image, read from ci/compose.ci.yml, is pulled up to 3 times when it is missing (a stub docker
#     answers), the FAIL line and exit 1 come before any stack starts when every pull fails, and a present image is never pulled;
#   - mock wrapper (Story 0.11): docker/tests/test-mock.sh runs node --test on every file of ci/mock/test/ and exits with node's
#     status (a stub node answers), so a red mock test turns the web job's step red;
#   - lane-a: lane-a.yml exists and has the job standalone-bridge; both .yml and .yaml files are workflow files;
#   - checks.sh, class verdict, shard order, teardown: ci/checks.sh runs every script and names the failed ones; ci/iris.sh
#     run_class tells a pass, a skip, a failure, an error, a class not compiled, no result and no test apart, shard runs its
#     classes in name order and reversed with --reverse, and teardown removes what carries its tag and nothing else, the lane's
#     warm-iris.lock and the warm state folder included: a lock or folder of the tag is released, and one of another tag, or of a
#     tag that extends this one, is kept (ci/iris.sh is sourced with a stub for dc, docker and run_classes, and a lock folder and
#     a temporary folder of its own);
#   - yaml: ruby -ryaml parses each file (SKIP, and never a PASS, when Ruby is missing).
# A failing rule prints file:line and its name, never the text of the file. Prints one PASS or FAIL line per rule; exits 0
# only when none fails.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
skipped=""
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-cf.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- the facts of a workflow file: kind, line, job, step, text (tab separated) ---

cat > "$tmp/facts.awk" <<'EOA'
function trim(s) { gsub(/^[ \t\r]+/, "", s); gsub(/[ \t\r]+$/, "", s); return s }
function emit(kind, ln, text) { printf "%s\t%d\t%s\t%d\t%s\n", kind, ln, job, step, text }
function parse(t) {
  key = ""; val = ""
  if (match(t, /^[A-Za-z0-9_.-]+:( |$)/)) {
    key = substr(t, 1, RLENGTH - 1)
    sub(/:$/, "", key)
    sub(/ $/, "", key)
    key = key
    val = trim(substr(t, RLENGTH + 1))
  }
}
function unquote(s) { gsub(/["']/, "", s); return s }
function flow(s, ln, kind, prefix,    n, a, i, t) {
  t = s
  gsub(/^\[|\]$/, "", t)
  n = split(t, a, ",")
  for (i = 1; i <= n; i++) if (trim(a[i]) != "") emit(kind, ln, prefix trim(a[i]))
}
BEGIN { job = ""; step = 0; sec = ""; sub2 = ""; inblock = 0 }
/^[ \t]*($|#)/ { next }
{
  line = $0
  sub(/\r$/, "", line)
  match(line, /^ */)
  ind = RLENGTH
  text = substr(line, ind + 1)
  low = tolower(text)
  # A whole context inside an expression, such as toJSON(secrets) or toJSON(github), counts as a use of every value it holds.
  if (low ~ /secrets[.[]/ || low ~ /[$][{][{]([^}]*[^a-z0-9_.-])?secrets([^a-z0-9_.[-]|$)/) emit("secret", FNR, text)
  if (low ~ /github\.token|github\[[^]]*token/ || low ~ /[$][{][{]([^}]*[^a-z0-9_.-])?github([^a-z0-9_.[-]|$)/) emit("token", FNR, text)
  if (inblock) {
    if (ind > blockind) { emit("step:runline", FNR, text); next }
    inblock = 0
  }
  parse(text)
  if (ind == 0) {
    sec = key; sub2 = ""; job = ""; step = 0
    if (key == "permissions") emit("top:permissions", FNR, val)
    if (key == "on" && val != "") emit("on:inline", FNR, val)
    next
  }
  if (sec == "on") {
    if (ind == 2) { ev = key; emit("on:event", FNR, key); if (val != "") emit("on:inline", FNR, key "=" val); next }
    if (ind == 4) {
      evkey = key
      emit("on:filter", FNR, ev "." key)
      if (val ~ /^\[/) flow(val, FNR, "on:item", ev "." key "=")
      next
    }
    if (ind == 6 && text ~ /^- /) { emit("on:item", FNR, ev "." evkey "=" trim(substr(text, 3))); next }
    next
  }
  if (sec == "permissions") { if (ind == 2) emit("top:permissions:entry", FNR, key ": " val); next }
  if (sec == "concurrency") {
    if (ind == 2 && key == "group") emit("conc:group", FNR, val)
    if (ind == 2 && key == "cancel-in-progress") emit("conc:cancel", FNR, val)
    next
  }
  if (sec == "jobs") {
    if (ind == 2) { job = key; step = 0; sub2 = ""; emit("job", FNR, key); next }
    if (ind == 4) {
      sub2 = key; step = 0
      if (key == "runs-on") emit("job:runs-on", FNR, val)
      else if (key == "if") emit("job:if", FNR, val)
      else if (key == "permissions") emit("job:permissions", FNR, val)
      else if (key == "continue-on-error") emit("job:coe", FNR, val)
      next
    }
    if (sub2 == "permissions" && ind == 6) { emit("job:permissions:entry", FNR, key ": " val); next }
    if (sub2 == "env" && ind == 6) { emit("job:env", FNR, key ": " val); next }
    if (sub2 == "strategy") { if (ind == 8 && key == "group") emit("matrix:group", FNR, val); next }
    if (sub2 == "steps") {
      if (ind == 6 && text ~ /^- /) { step++; stepsub = ""; text = substr(text, 3); ind = 8; parse(text) }
      if (ind == 8) {
        stepsub = ""
        if (key == "uses") emit("step:uses", FNR, val)
        else if (key == "id") emit("step:id", FNR, val)
        else if (key == "name") emit("step:name", FNR, val)
        else if (key == "continue-on-error") emit("step:coe", FNR, val)
        else if (key == "if") emit("step:if", FNR, val)
        else if (key == "run") {
          if (val ~ /^[|>]/) { inblock = 1; blockind = 8; emit("step:run", FNR, "") }
          else emit("step:run", FNR, val)
        }
        else if (key == "with" || key == "env") stepsub = key
        next
      }
      if (ind == 10 && stepsub != "") emit("step:" stepsub, FNR, key ": " val)
    }
  }
}
EOA

wf_facts() { awk -f "$tmp/facts.awk" "$1"; }

# --- the rules over the facts: line<TAB>rule for each violation ---

cat > "$tmp/rules.awk" <<'EOA'
function bad(ln, rule) { printf "%d\t%s\n", ln, rule }
function unq(s) { gsub(/["']/, "", s); return s }
BEGIN {
  FS = "\t"
  guard = "github.event_name == 'push' || github.event.pull_request.head.repo.full_name == github.repository"
  group = "${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.run_id }}"
  cancel = "${{ github.event_name == 'pull_request' }}"
  nreq = split("main feature/OCT_OcuTalon_MVP OCT-epic*", req, " ")
}
{ kind = $1; ln = $2; job = $3; st = $4; text = $5 }
kind == "top:permissions" { toppermissions = 1; if (text != "") bad(ln, "permissions") }
kind == "top:permissions:entry" { topentries++; if (text != "contents: read") bad(ln, "permissions") }
kind == "job:permissions" { if (text != "") bad(ln, "permissions") }
kind == "job:permissions:entry" {
  if (text != "contents: read" && text != "actions: read") bad(ln, "permissions")
  if (text == "contents: read") jobcontents[job] = 1
  jobblock[job] = 1
}
kind == "on:event" {
  events[text] = 1
  if (text == "pull_request_target" || text == "workflow_run") bad(ln, "triggers")
}
kind == "on:inline" { bad(ln, "triggers") }
kind == "on:filter" {
  split(text, p, ".")
  if (p[2] == "paths" || p[2] == "paths-ignore") bad(ln, "triggers")
  if (p[1] == "pull_request") bad(ln, "triggers")
}
kind == "on:item" {
  i = index(text, "=")
  if (substr(text, 1, i - 1) == "push.branches") { b = unq(substr(text, i + 1)); branches[b] = 1; nbranch++ }
}
kind == "conc:group" { sawgroup = 1; if (text != group) bad(ln, "concurrency") }
kind == "conc:cancel" { sawcancel = 1; if (text != cancel) bad(ln, "concurrency") }
kind == "job" { jobs[job] = ln }
kind == "job:runs-on" {
  runsline[job] = ln
  if (text == "ubuntu-24.04") hosted[job] = 1
  else if (text == "[self-hosted, ocutalon]") selfhosted[job] = 1
  else bad(ln, "runners")
}
kind == "job:if" { jobif[job] = text }
kind == "job:coe" || kind == "step:coe" { bad(ln, "never-skipped") }
kind == "step:uses" {
  usesline[job, st] = ln
  if (text ~ /^docker:/) bad(ln, "pins")
  else if (text !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@[0-9a-f]+ # v[0-9]+\.[0-9]+\.[0-9]+$/ || text !~ /@[0-9a-f][0-9a-f]* #/) bad(ln, "pins")
  else { sha = text; sub(/^[^@]*@/, "", sha); sub(/ .*$/, "", sha); if (length(sha) != 40) bad(ln, "pins") }
  action = tolower(text); sub(/@.*$/, "", action)
  if (action ~ /^docker\// || action ~ /^actions\/cache($|\/)/) bad(ln, "image-actions")
  if (action ~ /upload-artifact$/) { uploads[job] = uploads[job] " " ln }
  if (action == "actions/checkout") { checkout[job, st] = ln }
}
kind == "step:with" { if (text == "persist-credentials: false") persist[job, st] = 1 }
kind == "step:if" { stepif[job, st] = text }
kind == "step:run" || kind == "step:runline" {
  runtext[job, st] = runtext[job, st] " " text
  if (index(text, "ci/iris.sh") > 0) runsiris[job] = 1
}
kind == "matrix:group" { matrixline = ln; matrix = text }
kind == "secret" { bad(ln, "secrets") }
kind == "token" { if (text != "GH_TOKEN: ${{ github.token }}") bad(ln, "secrets") }
END {
  if (!toppermissions || topentries != 1) bad(1, "permissions")
  if (!("push" in events) || !("pull_request" in events)) bad(1, "triggers")
  nb = 0; for (b in branches) nb++
  okb = (nb == nreq)
  for (i = 1; i <= nreq; i++) if (!(req[i] in branches)) okb = 0
  if (!okb) bad(1, "triggers")
  if (!sawgroup || !sawcancel) bad(1, "concurrency")
  for (j in jobs) {
    if (!(j in runsline)) bad(jobs[j], "runners")
    if (j in selfhosted) {
      if (jobif[j] != guard) bad(jobs[j], "fork-guard")
      n = split(uploads[j], u, " ")
      for (i = 1; i <= n; i++) bad(u[i], "image-actions")
    }
    if ((j in hosted) && jobif[j] != "") bad(jobs[j], "never-skipped")
    if (j in jobblock && !(j in jobcontents)) bad(jobs[j], "permissions")
    if (j in runsiris) {
      ok = 0
      last = 0
      for (key in runtext) {
        split(key, kk, SUBSEP)
        if (kk[1] == j && index(runtext[key], "ci/iris.sh") > 0 && index(runtext[key], "ci/iris.sh teardown") == 0 && kk[2] + 0 > last) last = kk[2] + 0
      }
      for (key in stepif) {
        split(key, kk, SUBSEP)
        if (kk[1] == j && stepif[key] == "always()" && index(runtext[kk[1], kk[2]], "ci/iris.sh teardown") > 0 && kk[2] + 0 > last) ok = 1
      }
      if (!ok) bad(jobs[j], "teardown")
    }
  }
  for (key in checkout) if (!(key in persist)) bad(checkout[key], "persist-credentials")
  if (matrix != "" || groups != "") {
    m = matrix; gsub(/[\[\],]/, " ", m); gsub(/ +/, " ", m); sub(/^ /, "", m); sub(/ $/, "", m)
    if (m != groups) bad(matrixline == "" ? 1 : matrixline, "matrix")
  }
}
EOA

# wf_check <file> [<expected matrix groups>]: line<TAB>rule of each violation, sorted.
wf_check() {
  wf_facts "$1" > "$tmp/facts.tsv"
  awk -v groups="${2:-}" -f "$tmp/rules.awk" "$tmp/facts.tsv" | sort -u
}

# --- the synthetic workflows ---

samples="$tmp/samples"
mkdir -p "$samples"
sha=3d3c42e5aac5ba805825da76410c181273ba90b1
cat > "$samples/good.yml" <<EOS
name: t

on:
  push:
    branches:
      - main
      - feature/OCT_OcuTalon_MVP
      - "OCT-epic*"
  pull_request:

permissions:
  contents: read

concurrency:
  group: \${{ github.workflow }}-\${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.run_id }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}

jobs:
  hosted:
    runs-on: ubuntu-24.04
    steps:
      - name: Check out
        uses: actions/checkout@$sha # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - name: What changed
        run: bash ci/changes.sh ci.yml
        env:
          GH_TOKEN: \${{ github.token }}
  runner:
    if: github.event_name == 'push' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, ocutalon]
    permissions:
      contents: read
      actions: read
    strategy:
      fail-fast: false
      matrix:
        group: [install, production]
    steps:
      - name: Check out
        uses: actions/checkout@$sha # v7.0.1
        with:
          persist-credentials: false
      - name: Run
        run: bash ci/iris.sh group \${{ matrix.group }}
      - name: Tear down
        if: always()
        run: bash ci/iris.sh teardown
EOS

# make_bad <name> <awk program>: a copy of good.yml that the program rewrites (print the line to keep it).
make_bad() { awk "$2" "$samples/good.yml" > "$samples/$1.yml"; }
# insert_after <name> <exact line> <lines to add...>
insert_after() {
  local name=$1 after=$2
  shift 2
  awk -v after="$after" -v add="$(printf '%s\n' "$@")" '{ print } $0 == after { print add }' "$samples/good.yml" > "$samples/$name.yml"
}

make_bad perm-top-missing '!($0 == "permissions:" || $0 == "  contents: read") { print }'
make_bad perm-top-write '$0 == "  contents: read" { print "  contents: write"; next } { print }'
make_bad perm-top-extra '{ print } $0 == "  contents: read" { print "  actions: read" }'
make_bad perm-job-write '$0 == "      actions: read" { print "      actions: write"; next } { print }'
make_bad perm-job-extra '{ print } $0 == "      actions: read" { print "      id-token: write" }'
make_bad perm-job-inline '$0 == "    permissions:" { print "    permissions: write-all"; skip = 2; next } skip > 0 { skip--; next } { print }'
make_bad trigger-no-epic '$0 == "      - \"OCT-epic*\"" { next } { print }'
make_bad trigger-no-feature '$0 == "      - feature/OCT_OcuTalon_MVP" { next } { print }'
make_bad trigger-extra-branch '{ print } $0 == "      - main" { print "      - develop" }'
make_bad trigger-target '$0 == "  pull_request:" { print "  pull_request_target:"; next } { print }'
make_bad trigger-workflow-run '{ print } $0 == "  pull_request:" { print "  workflow_run:"; print "    workflows: [ci]" }'
make_bad trigger-pr-filter '{ print } $0 == "  pull_request:" { print "    branches:"; print "      - main" }'
make_bad trigger-paths '{ print } $0 == "      - \"OCT-epic*\"" { print "    paths:"; print "      - \"web/**\"" }'
make_bad trigger-paths-ignore '{ print } $0 == "      - \"OCT-epic*\"" { print "    paths-ignore:"; print "      - \"docs/**\"" }'
make_bad conc-cancel-true 'index($0, "  cancel-in-progress:") == 1 { print "  cancel-in-progress: true"; next } { print }'
make_bad conc-group-branch 'index($0, "  group:") == 1 { print "  group: ${{ github.workflow }}-${{ github.ref }}"; next } { print }'
make_bad pin-tag 'sub(/@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1/, "@v7") { print; next } { print }'
make_bad pin-no-comment 'sub(/ # v7.0.1$/, "") { print; next } { print }'
make_bad pin-short-sha 'sub(/@3d3c42e5aac5ba805825da76410c181273ba90b1/, "@3d3c42e") { print; next } { print }'
make_bad pin-docker '{ print } $0 == "      - name: What changed" { print "        uses: docker://alpine:3.20" }'
make_bad runner-latest 'sub(/runs-on: ubuntu-24.04/, "runs-on: ubuntu-latest") { print; next } { print }'
make_bad runner-label 'sub(/runs-on: \[self-hosted, ocutalon\]/, "runs-on: [self-hosted, linux]") { print; next } { print }'
make_bad fork-guard-missing 'index($0, "    if: github.event_name") == 1 { next } { print }'
make_bad fork-guard-weak 'index($0, "    if: github.event_name") == 1 { print "    if: github.event_name == '"'"'push'"'"'"; next } { print }'
make_bad secret-ref '{ print } $0 == "          GH_TOKEN: ${{ github.token }}" { print "          OTHER: ${{ secrets.KEY }}" }'
make_bad token-other '$0 == "          GH_TOKEN: ${{ github.token }}" { print "          TOKEN: ${{ github.token }}"; next } { print }'
make_bad secret-block '$0 == "        run: bash ci/iris.sh group ${{ matrix.group }}" { print "        run: |"; print "          echo ${{ secrets.KEY }}"; print "          bash ci/iris.sh group ${{ matrix.group }}"; next } { print }'
make_bad secret-bracket '{ print } $0 == "          GH_TOKEN: ${{ github.token }}" { print "          OTHER: ${{ Secrets['"'"'KEY'"'"'] }}" }'
make_bad token-block '$0 == "        run: bash ci/iris.sh group ${{ matrix.group }}" { print "        run: |"; print "          echo ${{ github.token }}"; print "          bash ci/iris.sh group ${{ matrix.group }}"; next } { print }'
make_bad secret-context '{ print } $0 == "          GH_TOKEN: ${{ github.token }}" { print "          ALL: ${{ toJSON(secrets) }}" }'
make_bad token-context '{ print } $0 == "          GH_TOKEN: ${{ github.token }}" { print "          CTX: ${{ toJSON(github) }}" }'
make_bad persist-true 'sub(/persist-credentials: false/, "persist-credentials: true") { print; next } { print }'
make_bad persist-missing '$0 == "          persist-credentials: false" { next } { print }'
make_bad teardown-no-always '$0 == "        if: always()" { next } { print }'
make_bad teardown-early '$0 == "      - name: Run" { print "      - name: Tear down"; print "        if: always()"; print "        run: bash ci/iris.sh teardown" } $0 == "      - name: Tear down" { skip = 3 } skip > 0 { skip--; next } { print }'
make_bad teardown-missing '$0 == "      - name: Tear down" { skip = 3 } skip > 0 { skip--; next } { print }'
insert_after image-docker "      - name: Run" "        uses: docker/login-action@$sha # v3.0.0"
insert_after image-cache "      - name: Run" "        uses: actions/cache@$sha # v4.0.0"
insert_after image-cache-restore "      - name: Run" "        uses: actions/cache/restore@$sha # v4.0.0"
insert_after image-upload "      - name: Run" "        uses: actions/upload-artifact@$sha # v4.0.0"
insert_after image-docker-upper "      - name: Run" "        uses: Docker/Login-Action@$sha # v3.0.0"
insert_after image-cache-upper "      - name: Run" "        uses: Actions/Cache@$sha # v4.0.0"
insert_after image-upload-upper "      - name: Run" "        uses: Actions/Upload-Artifact@$sha # v4.0.0"
make_bad skip-hosted-job '$0 == "  hosted:" { print; print "    if: github.event_name == '"'"'push'"'"'"; next } { print }'
make_bad coe-job '$0 == "    runs-on: ubuntu-24.04" { print; print "    continue-on-error: true"; next } { print }'
make_bad coe-step '$0 == "      - name: What changed" { print; print "        continue-on-error: true"; next } { print }'
make_bad matrix-extra 'sub(/group: \[install, production\]/, "group: [install, production, other]") { print; next } { print }'
make_bad matrix-block '$0 == "        group: [install, production]" { print "        group:"; print "          - install"; print "          - production"; next } { print }'
make_bad matrix-missing '$0 == "    strategy:" { skip = 4 } skip > 0 { skip--; next } { print }'
make_bad matrix-order 'sub(/group: \[install, production\]/, "group: [production, install]") { print; next } { print }'

expect_rule() { # expect_rule <rule> <sample>...: each sample is flagged under the rule
  local rule=$1 s
  shift
  for s in "$@"; do
    if ! wf_check "$samples/$s.yml" "install production" | awk -F'\t' -v r="$rule" '$2 == r { f = 1 } END { exit !f }'; then
      echo "FAIL $rule: the rule does not flag the sample $s"
      return 1
    fi
  done
  return 0
}

# workflow_files <folder>: the workflow files of GitHub, which accepts both extensions.
workflow_files() { ls "$1"/*.yml "$1"/*.yaml 2>/dev/null; }
wf_files=$(workflow_files .github/workflows)

# rule <name> <description> <samples...>: the samples are flagged, the good sample is clean, and the real files have no violation.
rule() {
  local name=$1 description=$2 f hits ok=1
  shift 2
  if [ -n "$(wf_check "$samples/good.yml" "install production")" ]; then
    echo "FAIL $name: the rule flags the good sample ($(wf_check "$samples/good.yml" "install production" | tr '\t\n' ': '))"
    fails=$((fails + 1))
    return
  fi
  expect_rule "$name" "$@" || ok=0
  if [ -z "$wf_files" ]; then
    echo "FAIL $name: no workflow file below .github/workflows/"
    ok=0
  fi
  for f in $wf_files; do
    groups=""
    if [ "$(basename "$f")" = ci.yml ]; then groups=$(bash ci/iris.sh groups | tr '\n' ' ' | sed 's/ $//'); fi
    hits=$(wf_check "$f" "$groups" | awk -F'\t' -v r="$name" -v file="$f" '$2 == r { print file ":" $1 " " r }')
    if [ -n "$hits" ]; then
      printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
      ok=0
    fi
  done
  if [ "$ok" -eq 1 ]; then
    echo "PASS $name: $description"
  else
    echo "FAIL $name: $description"
    fails=$((fails + 1))
  fi
}

rule permissions "the top level is contents: read; a job-level block holds only contents: read and actions: read" \
  perm-top-missing perm-top-write perm-top-extra perm-job-write perm-job-extra perm-job-inline
rule triggers "push on main, feature/OCT_OcuTalon_MVP and OCT-epic*, every pull request, no pull_request_target, workflow_run, paths or paths-ignore" \
  trigger-no-epic trigger-no-feature trigger-extra-branch trigger-target trigger-workflow-run trigger-pr-filter trigger-paths trigger-paths-ignore
rule concurrency "a push group is its own run id, and only a pull request cancels its superseded run" conc-cancel-true conc-group-branch
rule pins "every action is owner/repo@<40 hex> with a version comment, and no docker:// image" pin-tag pin-no-comment pin-short-sha pin-docker
rule persist-credentials "every checkout sets persist-credentials: false" persist-true persist-missing
rule runners "ubuntu-24.04 or [self-hosted, ocutalon]" runner-latest runner-label
rule fork-guard "every self-hosted job keeps a fork's pull request off the IRIS runner" fork-guard-missing fork-guard-weak
rule secrets "no secrets reference (a run block, any case, a bracket or the whole context included), and github.token only as GH_TOKEN" secret-ref token-other secret-block secret-bracket token-block secret-context token-context
rule image-actions "no docker/* action, no actions/cache, and no upload-artifact in a self-hosted job, whatever the case of the name" \
  image-docker image-cache image-cache-restore image-upload image-docker-upper image-cache-upper image-upload-upper
rule never-skipped "no hosted job has a job-level if, and no job or step ignores a failure with continue-on-error" skip-hosted-job coe-job coe-step
rule teardown "every job that runs ci/iris.sh has an if: always() step that runs ci/iris.sh teardown" teardown-no-always teardown-missing teardown-early
rule matrix "the group list of ci.yml is ci/iris.sh groups" matrix-extra matrix-order matrix-block matrix-missing

# --- wiring: the steps of ci.yml are gated by what the classifier says, and run what the jobs are for ---

cat > "$tmp/wiring.awk" <<'EOA'
function bad(what) { printf "1\twiring\t%s\n", what }
function unq(s) { gsub(/["']/, "", s); return s }
# need <job> <run text> <if text>: the job has a step that runs that command with exactly that condition.
function need(job, run, cond,    key, kk, found) {
  found = 0
  for (key in runs) {
    split(key, kk, SUBSEP)
    if (kk[1] == job && runs[key] == run && ifs[key] == cond) found = 1
  }
  if (!found) bad(job ": no step runs '" run "' with the condition '" cond "'")
}
# need_skip <job> <if text>: the job has a step with that condition, the one that says the job skipped.
function need_skip(job, cond,    key, kk, found) {
  found = 0
  for (key in ifs) {
    split(key, kk, SUBSEP)
    if (kk[1] == job && ifs[key] == cond) found = 1
  }
  if (!found) bad(job ": no step has the condition '" cond "'")
}
# need_named <job> <name> <text in its run line> <if text>: the job has a step of that name, with exactly that condition, whose
# run line holds the text.
function need_named(job, name, hold, cond,    key, kk, found) {
  found = 0
  for (key in snames) {
    split(key, kk, SUBSEP)
    if (kk[1] == job && snames[key] == name && ifs[key] == cond && index(runs[key], hold) > 0) found = 1
  }
  if (!found) bad(job ": no step '" name "' runs a line that holds '" hold "' with the condition '" cond "'")
}
# need_reason <job> <name> <text in its run line> <if text>: ONE step of that name has exactly that condition, a run line that holds
# the text and an env that binds REASON to the classifier's reason, so that the three cannot be shared out over two steps of the name.
function need_reason(job, name, hold, cond,    key, kk, found) {
  found = 0
  for (key in snames) {
    split(key, kk, SUBSEP)
    if (kk[1] == job && snames[key] == name && ifs[key] == cond && index(runs[key], hold) > 0 \
      && reasonenv[key] == "REASON: ${{ steps.changes.outputs.reason }}") found = 1
  }
  if (!found) bad(job ": no one step '" name "' has the condition '" cond "', a run line that holds '" hold "' and REASON bound to the classifier's reason")
}
BEGIN { FS = "\t" }
{ kind = $1; ln = $2; job = $3; st = $4; text = $5 }
kind == "step:name" { snames[job, st] = unq(text) }
kind == "step:env" && index(text, "REASON: ") == 1 { reasonenv[job, st] = text }
kind == "step:run" { runs[job, st] = text }
kind == "step:if" { ifs[job, st] = text }
kind == "step:id" { ids[job, text] = 1 }
kind == "job:env" { i = index(text, ": "); env[job, substr(text, 1, i - 1)] = substr(text, i + 2) }
kind == "step:run" || kind == "step:runline" || kind == "step:if" || kind == "step:env" {
  t = text
  while (match(t, /steps\.[A-Za-z0-9_-]+\./)) { refs[job, substr(t, RSTART + 6, RLENGTH - 7)] = 1; t = substr(t, RSTART + RLENGTH) }
}
END {
  web = "steps.changes.outputs.web == 'true'"
  iris = "steps.changes.outputs.run != 'false'"
  need("checks", "bash ci/checks.sh", "")
  need("web", "bash ci/changes.sh ci.yml", "")
  nw = split(webscripts, ws, " ")
  if (nw == 0) bad("ci/units.sh: WEB_SCRIPTS is empty")
  for (i = 1; i <= nw; i++) need("web", "bash docker/tests/test-" ws[i] ".sh", web)
  need("web", "npm --prefix web run lint", web)
  need("web", "npm --prefix web test", web)
  need_skip("web", "steps.changes.outputs.web != 'true'")
  need_named("web", "Mock tests", "bash docker/tests/test-mock.sh", web)
  need("iris", "bash ci/changes.sh ci.yml --group ${{ matrix.group }}", "")
  need("iris", "bash ci/iris.sh build", iris)
  need("iris", "bash ci/iris.sh group ${{ matrix.group }}", iris)
  need_named("iris", "Skipped", "skipped: $REASON", "steps.changes.outputs.run == 'false'")
  need_reason("iris", "Skipped", "skipped: $REASON", "steps.changes.outputs.run == 'false'")
  if (!(("web", "changes") in ids) || !(("iris", "changes") in ids)) bad("the classifier step has no id changes in the web job or the iris job")
  if (env["iris", "OCUTALON_RUN_TAG"] != "${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.group }}") bad("iris: OCUTALON_RUN_TAG is not run id, attempt and group")
  if (env["iris", "IRIS_IMAGE"] != "ocutalon-iris-base:2026.3.0AI.154.0") bad("iris: IRIS_IMAGE is not the preloaded base image")
  if (unq(env["iris", "OCUTALON_LIVE_DEADLINE"]) != "1200") bad("iris: OCUTALON_LIVE_DEADLINE is not 1200")
  for (key in refs) {
    split(key, kk, SUBSEP)
    if (!((kk[1], kk[2]) in ids)) bad(kk[1] ": a condition or value reads steps." kk[2] ", which no step of the job has as its id")
  }
}
EOA
# wf_wiring <workflow file> [<web scripts>]: the web job must run each script of WEB_SCRIPTS (ci/units.sh), or of the list given.
web_scripts=$(. ./ci/units.sh && printf '%s' "$WEB_SCRIPTS")
wf_wiring() { wf_facts "$1" | awk -v webscripts="${2-$web_scripts}" -f "$tmp/wiring.awk" | sort -u; }

ci_yml=.github/workflows/ci.yml
wiring_bad() { # wiring_bad <name> <awk program>: a copy of ci.yml that the program rewrites
  awk "$2" "$ci_yml" > "$samples/wiring-$1.yml"
}
wiring_bad id '/^        id: changes$/ { n++; if (n == 2) { print "        id: chg"; next } } { print }'
wiring_bad iris-gate '/outputs\.run != / && !done { sub(/outputs\.run != /, "outputs.run == "); done = 1 } { print }'
wiring_bad group-gate '/outputs\.run != / { n++; if (n == 2) sub(/outputs\.run != /, "outputs.run == ") } { print }'
wiring_bad gate-truthy '/if: steps\.changes\.outputs\.run != / { sub(/ != .false./, "") } { print }'
wiring_bad web-gate '/outputs\.web ==/ { n++; if (n == 2) sub(/outputs\.web ==/, "outputs.web !=") } { print }'
wiring_bad skip-step '/outputs\.run == / { sub(/outputs\.run ==/, "outputs.run !=") } { print }'
wiring_bad skip-reason '/^          REASON: / { n++; if (n == 2) { m = "outputs.reason"; i = index($0, m); if (i > 0) $0 = substr($0, 1, i - 1) "outputs.base" substr($0, i + length(m)) } } { print }'
wiring_bad skip-text '/skipped: \$REASON/ && !done { m = "skipped: "; i = index($0, m); if (i > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(m)); done = 1 } { print }'
wiring_bad group-arg '/ci\/changes\.sh ci\.yml --group/ { m = " --group ${{ matrix.group }}"; i = index($0, m); if (i > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(m)) } { print }'
wiring_bad skip-split '/^          REASON: / { n++; if (n == 2) { m = "outputs.reason"; i = index($0, m); if (i > 0) $0 = substr($0, 1, i - 1) "outputs.base" substr($0, i + length(m)) } } { print } END { print "      - name: Skipped"; print "        if: always()"; print "        run: echo skipped"; print "        env:"; print "          REASON: ${{ steps.changes.outputs.reason }}" }'
wiring_bad tag '/OCUTALON_RUN_TAG:/ { m = "-${{ matrix.group }}"; i = index($0, m); if (i > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(m)) } { print }'
wiring_bad checks '$0 == "        run: bash ci/checks.sh" { print "        run: echo checks"; next } { print }'
wiring_bad lint '$0 == "        run: npm --prefix web run lint" { print "        run: echo lint"; next } { print }'
wiring_bad test '$0 == "        run: npm --prefix web test" { print "        run: echo test"; next } { print }'
wiring_bad group '$0 == "        run: bash ci/iris.sh group ${{ matrix.group }}" { print "        run: echo group"; next } { print }'
wiring_bad mock '$0 == "        run: bash docker/tests/test-mock.sh" { print "        run: echo mock"; next } { print }'
wiring_ok=1
for n in id iris-gate group-gate gate-truthy web-gate skip-step skip-reason skip-text skip-split group-arg tag checks lint test group mock; do
  if [ -z "$(wf_wiring "$samples/wiring-$n.yml")" ]; then
    echo "FAIL wiring: the rule does not flag the sample $n"
    wiring_ok=0
  fi
done
# A script of WEB_SCRIPTS that no step of the web job runs, and an empty list.
for extra in "$web_scripts zz-web" ""; do
  if [ -z "$(wf_wiring "$ci_yml" "$extra")" ]; then
    echo "FAIL wiring: the rule does not flag the web scripts '$extra'"
    wiring_ok=0
  fi
done
hits=$(wf_wiring "$ci_yml" | sed "s#^[0-9]*\twiring\t#  $ci_yml: #")
if [ "$wiring_ok" -eq 1 ] && [ -z "$hits" ]; then
  echo "PASS wiring: ci.yml runs the checks, each script of WEB_SCRIPTS, the lint and the unit tests, gated by the classifier's web output, and the iris job asks the classifier for its group and runs the build and the group unless run is false"
else
  printf '%s\n' "$hits" | head -n 10
  echo "FAIL wiring: ci.yml does not run what its jobs are for, or a sample is not flagged"
  fails=$((fails + 1))
fi

# --- units ---

# real_hits <rule> <function> <repository directory>: the function's violation lines for that tree, or one line saying that the
# rule could not read it when the function fails (no ci/units.sh, or a set -u abort while sourcing it), so it never passes.
real_hits() {
  local out
  out=$("$2" "$3") || out="ci/units.sh: the $1 rule could not read the tree ($out)"
  printf '%s' "$out"
}

# units_violations <repository directory>: one line per violation of the unit rules in that tree.
units_violations() {
  (
    cd "$1" || exit 1
    . ./ci/units.sh
    all="$CHECK_SCRIPTS $WEB_SCRIPTS"
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        case $u in
          live:*) all="$all ${u#live:}" ;;
          shard:*) ;;
          *) echo "ci/units.sh: the unit '$u' of group $g is neither live: nor shard:" ;;
        esac
      done
    done
    for f in docker/tests/test-*.sh; do
      [ -f "$f" ] || continue
      name=${f#docker/tests/test-}
      name=${name%.sh}
      n=$(printf '%s\n' $all | grep -c -x -- "$name")
      if [ "$n" -ne 1 ]; then echo "$f: the script is in $n of CHECK_SCRIPTS, WEB_SCRIPTS and the groups, wanted 1"; fi
    done
    for name in $all; do
      [ -f "docker/tests/test-$name.sh" ] || echo "ci/units.sh: the unit '$name' has no docker/tests/test-$name.sh"
    done
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        case $u in
          shard:*) printf '%s\n' $SHARDS | grep -qx -- "${u#shard:}" || echo "ci/units.sh: group $g names the unknown shard ${u#shard:}" ;;
        esac
      done
    done
    for s in $SHARDS; do
      n=$(for g in $IRIS_GROUPS; do group_units "$g"; done | tr ' ' '\n' | grep -c -x -- "shard:$s")
      if [ "$n" -ne 1 ]; then echo "ci/units.sh: the shard $s is in $n groups, wanted 1"; fi
    done
    for d in src/*/cls/OcuTalon/Test/*/; do
      [ -d "$d" ] || continue
      area=$(basename "$d")
      n=$(for s in $SHARDS; do shard_areas "$s"; done | tr ' ' '\n' | grep -c -x -- "$area")
      if [ "$n" -ne 1 ]; then echo "${d%/}: the area $area is in $n shards, wanted 1"; fi
    done
    for f in $(grep -l '^Method Test' $(find src -path '*/cls/OcuTalon/Test/*' -name '*.cls' 2>/dev/null) 2>/dev/null); do
      rest=${f#*/cls/OcuTalon/Test/}
      area=${rest%%/*}
      if [ "$rest" = "$area" ] || [ "$rest" != "$area/${rest#*/}" ] || [ "$(printf '%s' "${rest#*/}" | tr -cd / | wc -c | tr -d ' ')" -ne 0 ]; then
        echo "$f: a class with a Method Test... must sit directly in a Test/<Area>/ folder"
      elif ! for s in $SHARDS; do shard_areas "$s"; done | tr ' ' '\n' | grep -qx -- "$area"; then
        echo "$f: its area $area is in no shard"
      fi
    done
  )
}

# The synthetic trees: a good one, and one for each way to break a unit rule.
mkunits() { # mkunits <dir>: the good tree
  local d=$1
  mkdir -p "$d/ci" "$d/docker/tests" "$d/src/ocutalon/cls/OcuTalon/Test/Alpha" "$d/src/bridge/cls/OcuTalon/Test/Beta"
  cat > "$d/ci/units.sh" <<'EOU'
CHECK_SCRIPTS="a b"
WEB_SCRIPTS="w"
SHARDS="s1 s2"
shard_areas() { case $1 in s1) echo "Alpha" ;; s2) echo "Beta" ;; esac; }
IRIS_GROUPS="g1 g2"
group_units() { case $1 in g1) echo "live:x shard:s1" ;; g2) echo "live:y shard:s2" ;; esac; }
EOU
  for n in a b w x y; do printf '#!/usr/bin/env bash\n' > "$d/docker/tests/test-$n.sh"; done
  printf 'Class OcuTalon.Test.Alpha.One\n{\nMethod TestOne()\n{\n}\n}\n' > "$d/src/ocutalon/cls/OcuTalon/Test/Alpha/One.cls"
  printf 'Class OcuTalon.Test.Beta.Two\n{\nMethod TestTwo()\n{\n}\n}\n' > "$d/src/bridge/cls/OcuTalon/Test/Beta/Two.cls"
}
mkunits "$tmp/u-good"
mkunits "$tmp/u-unlisted"; printf '#!/usr/bin/env bash\n' > "$tmp/u-unlisted/docker/tests/test-z.sh"
mkunits "$tmp/u-twice"; sed 's/live:y shard:s2/live:y live:x shard:s2/' "$tmp/u-twice/ci/units.sh" > "$tmp/u-twice/ci/units.new"; mv "$tmp/u-twice/ci/units.new" "$tmp/u-twice/ci/units.sh"
mkunits "$tmp/u-no-script"; rm "$tmp/u-no-script/docker/tests/test-y.sh"
mkunits "$tmp/u-area"; mkdir -p "$tmp/u-area/src/ocutalon/cls/OcuTalon/Test/Gamma"
mkunits "$tmp/u-two-shards"; sed 's/s2) echo "Beta"/s2) echo "Beta Alpha"/' "$tmp/u-two-shards/ci/units.sh" > "$tmp/u-two-shards/ci/units.new"; mv "$tmp/u-two-shards/ci/units.new" "$tmp/u-two-shards/ci/units.sh"
mkunits "$tmp/u-loose"; printf 'Class OcuTalon.Test.Loose\n{\nMethod TestLoose()\n{\n}\n}\n' > "$tmp/u-loose/src/ocutalon/cls/OcuTalon/Test/Loose.cls"
mkunits "$tmp/u-deep"; mkdir -p "$tmp/u-deep/src/ocutalon/cls/OcuTalon/Test/Alpha/Sub"; printf 'Class OcuTalon.Test.Alpha.Sub.Deep\n{\nMethod TestDeep()\n{\n}\n}\n' > "$tmp/u-deep/src/ocutalon/cls/OcuTalon/Test/Alpha/Sub/Deep.cls"
mkunits "$tmp/u-helper"; printf 'Class OcuTalon.Test.Alpha.Helper\n{\nClassMethod Make()\n{\n}\n}\n' > "$tmp/u-helper/src/ocutalon/cls/OcuTalon/Test/Alpha/Helper.cls"

ok=1
if [ -n "$(units_violations "$tmp/u-good")" ]; then
  echo "FAIL units: the rule flags the good tree ($(units_violations "$tmp/u-good" | head -n 3 | tr '\n' ';'))"
  ok=0
fi
for s in u-unlisted u-twice u-no-script u-area u-two-shards u-loose u-deep; do
  if [ -z "$(units_violations "$tmp/$s")" ]; then
    echo "FAIL units: the rule does not flag the sample $s"
    ok=0
  fi
done
if [ -n "$(units_violations "$tmp/u-helper")" ]; then
  echo "FAIL units: the rule flags a helper class with no test method"
  ok=0
fi
mkdir -p "$tmp/u-unread/ci" && : > "$tmp/u-unread/ci/units.sh"
if [ -z "$(real_hits units units_violations "$tmp/u-unread" 2>/dev/null)" ]; then
  echo "FAIL units: a tree whose ci/units.sh cannot be read passes the rule"
  ok=0
fi
hits=$(real_hits units units_violations "$root")
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "PASS units: every test script is in exactly one place, every Test area is in exactly one shard, and every test class sits in an area"
else
  echo "FAIL units: the test scripts, the shards and the areas"
  fails=$((fails + 1))
fi

# --- demo-path: the demo-path unit and the browser units ---

# The command that a live script runs to drive Playwright, assembled here so that this file never matches its own rule.
e2e_run='npm --prefix web run '
e2e_run="${e2e_run}e2e"

# demo_path_violations <repository directory>: one line per violation of the demo-path rule in that tree.
demo_path_violations() {
  (
    cd "$1" || exit 1
    . ./ci/units.sh
    n=0
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        if [ "$u" = live:demo-path ]; then n=$((n + 1)); fi
      done
    done
    if [ "$n" -ne 1 ]; then echo "ci/units.sh: live:demo-path is in $n groups, wanted 1"; fi
    [ -f docker/tests/test-demo-path.sh ] || echo "docker/tests/test-demo-path.sh does not exist"
    if [ -z "${BROWSER_UNITS:-}" ]; then echo "ci/units.sh: BROWSER_UNITS is empty"; fi
    for b in ${BROWSER_UNITS:-}; do
      n=0
      for g in $IRIS_GROUPS; do
        for u in $(group_units "$g"); do
          if [ "$u" = "live:$b" ]; then n=$((n + 1)); fi
        done
      done
      if [ "$n" -eq 0 ]; then echo "ci/units.sh: the browser unit '$b' is not a live unit of a group"; fi
    done
    for f in docker/tests/test-*.sh; do
      [ -f "$f" ] || continue
      name=${f#docker/tests/test-}
      name=${name%.sh}
      if grep -v '^[[:space:]]*#' "$f" | grep -qF -- "$e2e_run"; then
        printf '%s\n' ${BROWSER_UNITS:-} | grep -qx -- "$name" || echo "$f: it runs Playwright, but $name is not in BROWSER_UNITS"
      fi
    done
  )
}

mkdemo() { # mkdemo <dir> <BROWSER_UNITS> <groups line>: a tree with the good layout; the arguments break it
  local d=$1
  mkdir -p "$d/ci" "$d/docker/tests"
  cat > "$d/ci/units.sh" <<EOU
IRIS_GROUPS="g1 g2"
group_units() { case \$1 in g1) echo "${3:-live:demo-path live:x}" ;; g2) echo "live:y" ;; esac; }
BROWSER_UNITS="$2"
EOU
  printf '#!/usr/bin/env bash\n%s:demo-path\n' "$e2e_run" > "$d/docker/tests/test-demo-path.sh"
  printf '#!/usr/bin/env bash\n  %s\n' "$e2e_run" > "$d/docker/tests/test-x.sh"
  printf '#!/usr/bin/env bash\n# it does not run %s\n  # nor does this, for %s\n' "$e2e_run" "$e2e_run" > "$d/docker/tests/test-y.sh"
}
mkdemo "$tmp/d-good" "demo-path x"
mkdemo "$tmp/d-two" "demo-path x" "live:demo-path live:x"; sed 's/g2) echo "live:y"/g2) echo "live:y live:demo-path"/' "$tmp/d-two/ci/units.sh" > "$tmp/d-two/ci/units.new"; mv "$tmp/d-two/ci/units.new" "$tmp/d-two/ci/units.sh"
mkdemo "$tmp/d-none" "demo-path x" "live:x"
mkdemo "$tmp/d-no-script" "demo-path x"; rm "$tmp/d-no-script/docker/tests/test-demo-path.sh"
mkdemo "$tmp/d-unknown" "demo-path x zz"
mkdemo "$tmp/d-unlisted" "demo-path"
mkdemo "$tmp/d-empty" ""
mkdemo "$tmp/d-demo-unlisted" "x"

ok=1
if [ -n "$(demo_path_violations "$tmp/d-good")" ]; then
  echo "FAIL demo-path: the rule flags the good tree ($(demo_path_violations "$tmp/d-good" | head -n 3 | tr '\n' ';'))"
  ok=0
fi
# Each bad sample must draw its own violation, so that no other violation of the same sample can stand in for it.
for pair in "d-two|live:demo-path is in 2 groups, wanted 1" "d-none|live:demo-path is in 0 groups, wanted 1" \
  "d-no-script|docker/tests/test-demo-path.sh does not exist" "d-unknown|the browser unit 'zz' is not a live unit of a group" \
  "d-unlisted|docker/tests/test-x.sh: it runs Playwright, but x is not in BROWSER_UNITS" "d-empty|BROWSER_UNITS is empty" \
  "d-demo-unlisted|docker/tests/test-demo-path.sh: it runs Playwright, but demo-path is not in BROWSER_UNITS"; do
  s=${pair%%|*}
  want=${pair#*|}
  got=$(demo_path_violations "$tmp/$s")
  case $got in
    *"$want"*) ;;
    *)
      echo "FAIL demo-path: the sample $s does not draw '$want' (got: $(printf '%s' "$got" | head -n 3 | tr '\n' ';'))"
      ok=0
      ;;
  esac
done
hits=$(real_hits demo-path demo_path_violations "$root")
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "PASS demo-path: live:demo-path is a unit of exactly one group, every browser unit is a live unit, and every script that runs Playwright is a browser unit"
else
  echo "FAIL demo-path: the demo-path unit and the browser units"
  fails=$((fails + 1))
fi

# --- groups: the six IRIS groups, the two install anchors and the demo-path first rule ---

# groups_violations <repository directory>: one line per violation of the groups rule in that tree. The names and their order are
# pinned; where a unit sits in a group other than the two anchors is not, so a rebalance of whole units needs no edit here.
groups_violations() {
  (
    cd "$1" || exit 1
    . ./ci/units.sh
    set -- $IRIS_GROUPS
    if [ "$*" != "install-fresh install-upgrade production browser shards image" ]; then
      echo "ci/units.sh: IRIS_GROUPS is '$IRIS_GROUPS', wanted install-fresh, install-upgrade, production, browser, shards and image, in this order"
    fi
    if group_units install > /dev/null 2>&1; then
      echo "ci/units.sh: group_units still has a case for the retired group install"
    fi
    for g in $(printf '%s\n' $IRIS_GROUPS | LC_ALL=C sort | uniq -d); do
      echo "ci/units.sh: the group $g is listed twice in IRIS_GROUPS"
    done
    for g in $IRIS_GROUPS; do
      set -- $(group_units "$g" 2>/dev/null)
      if [ $# -eq 0 ]; then echo "ci/units.sh: the group $g has no unit"; fi
    done
    printf '%s\n' $(group_units install-fresh 2>/dev/null) | grep -qx -- live:install-start \
      || echo "ci/units.sh: install-fresh does not hold live:install-start"
    printf '%s\n' $(group_units install-upgrade 2>/dev/null) | grep -qx -- live:install-upgrade \
      || echo "ci/units.sh: install-upgrade does not hold live:install-upgrade"
    set -- $(group_units browser 2>/dev/null)
    first=${1-}
    if [ "$first" != live:demo-path ]; then
      echo "ci/units.sh: the first unit of browser is '$first', wanted live:demo-path (AD-22)"
    fi
  )
}

mkgroups() { # mkgroups <dir> <IRIS_GROUPS> <install-fresh units> <install-upgrade units> <production units> <browser units> <extra case>: a tree with the good layout; the arguments break it
  local d=$1
  mkdir -p "$d/ci"
  cat > "$d/ci/units.sh" <<EOU
IRIS_GROUPS="${2:-install-fresh install-upgrade production browser shards image}"
group_units() {
  case \$1 in
    install-fresh) echo "${3-live:install-start}" ;;
    install-upgrade) echo "${4-live:install-upgrade live:audit}" ;;
    production) echo "${5-live:production live:production-restart}" ;;
    browser) echo "${6-live:demo-path live:sign-in}" ;;
    shards) echo "shard:lane-a shard:lane-b" ;;
    image) echo "live:storage-roundtrip" ;;
    ${7-}
    *) return 1 ;;
  esac
}
EOU
}
mkgroups "$tmp/g-good"
mkgroups "$tmp/g-old" "install production browser shards image"
mkgroups "$tmp/g-dup" "install-fresh install-upgrade production browser shards image image"
mkgroups "$tmp/g-order" "install-upgrade install-fresh production browser shards image"
mkgroups "$tmp/g-stale" "" "live:install-start" "live:install-upgrade live:audit" "live:production live:production-restart" "live:demo-path live:sign-in" 'install) echo "live:install-start live:install-upgrade" ;;'
mkgroups "$tmp/g-empty" "" "live:install-start" "live:install-upgrade live:audit" ""
mkgroups "$tmp/g-blank" "" "live:install-start" "live:install-upgrade live:audit" " "
mkgroups "$tmp/g-spaced" "" "live:install-start" "live:install-upgrade live:audit" "live:production" "  live:demo-path  live:sign-in"
mkgroups "$tmp/g-moved" "" "live:install-start" "live:install-upgrade" "live:production live:production-restart live:audit" "live:demo-path live:sign-in live:bundle-folder"
mkgroups "$tmp/g-near" "" "live:install-starter" "live:install-upgrade-old live:audit"
mkgroups "$tmp/g-no-fresh" "" "live:sign-in"
mkgroups "$tmp/g-no-upgrade" "" "live:install-start" "live:audit"
mkgroups "$tmp/g-demo-second" "" "live:install-start" "live:install-upgrade live:audit" "live:production" "live:sign-in live:demo-path"

ok=1
# g-moved is a rebalance of whole units (live:audit moved to production, a unit added to browser after live:demo-path): the rule does
# not pin where a unit sits beyond the two anchors and demo-path first, so a rebalance needs no edit here.
for good in g-good g-moved g-spaced; do
  if [ -n "$(groups_violations "$tmp/$good")" ]; then
    echo "FAIL groups: the rule flags the good tree $good ($(groups_violations "$tmp/$good" | head -n 3 | tr '\n' ';'))"
    ok=0
  fi
done
# Each bad sample must draw its own violation, so that no other violation of the same sample can stand in for it.
for pair in "g-old|IRIS_GROUPS is 'install production browser shards image', wanted" "g-dup|the group image is listed twice in IRIS_GROUPS" \
  "g-order|IRIS_GROUPS is 'install-upgrade install-fresh production browser shards image', wanted" \
  "g-stale|group_units still has a case for the retired group install" \
  "g-empty|the group production has no unit" "g-blank|the group production has no unit" \
  "g-no-fresh|install-fresh does not hold live:install-start" \
  "g-no-upgrade|install-upgrade does not hold live:install-upgrade" \
  "g-near|install-fresh does not hold live:install-start" "g-near|install-upgrade does not hold live:install-upgrade" \
  "g-demo-second|the first unit of browser is 'live:sign-in', wanted live:demo-path (AD-22)"; do
  s=${pair%%|*}
  want=${pair#*|}
  got=$(groups_violations "$tmp/$s")
  case $got in
    *"$want"*) ;;
    *)
      echo "FAIL groups: the sample $s does not draw '$want' (got: $(printf '%s' "$got" | head -n 3 | tr '\n' ';'))"
      ok=0
      ;;
  esac
done
hits=$(real_hits groups groups_violations "$root")
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "PASS groups: IRIS_GROUPS is install-fresh, install-upgrade, production, browser, shards and image in this order, group_units has no case for install, every group has a unit, the two install groups hold their anchors, and live:demo-path is the first unit of browser"
else
  echo "FAIL groups: the six IRIS groups"
  fails=$((fails + 1))
fi

# --- inputs: the input pattern of each IRIS group, and the units that do not check the web bundle (Story 32.2) ---

# The names whose appearance in a code line of a live script shows that it reads, compares or serves the built web bundle, assembled
# here so that this file never matches its own rule.
bundle_markers="$tmp/bundle-markers"
: > "$bundle_markers"
for part in "cs:p" "ocutalon-:web" "npm --prefix :web" "live_web_:port" "check_:security" "index:.html" "ensure_web_:bundle" "LIVE_REBUILD_:WEB"; do
  printf '%s%s\n' "${part%%:*}" "${part#*:}" >> "$bundle_markers"
done

# unit_reads <live script>: the repository files that a code line of the script names through $root or through the script's own
# folder (the files it sources and the compose files it adds), one per line, as paths from the repository root. Only a name with an
# extension counts, so that a folder is never taken for a file.
unit_reads() {
  grep -v '^[[:space:]]*#' "$1" | grep -oE '[$][{]?root[}]?/[A-Za-z0-9_./-]+|[$][(]dirname "[$]0"[)]/[A-Za-z0-9_][A-Za-z0-9_.-]*' \
    | sed -e 's#^[$][{]*root[}]*/##' -e 's#^[$](dirname "[$]0")/#docker/tests/#' | grep -E '[.][A-Za-z0-9]+$' | sort -u
}

# inputs_violations <repository directory>: one line per violation of the inputs rule in that tree.
inputs_violations() {
  (
    cd "$1" || exit 1
    . ./ci/units.sh
    all_units=""
    for g in $IRIS_GROUPS; do all_units="$all_units $(group_units "$g")"; done
    for u in ${NO_WEB_BUNDLE_UNITS:-}; do
      printf '%s\n' $all_units | grep -qx -- "$u" || echo "ci/units.sh: NO_WEB_BUNDLE_UNITS names $u, which is a unit of no group"
      case $u in
        live:*)
          f="docker/tests/test-${u#live:}.sh"
          if [ -f "$f" ] && grep -v '^[[:space:]]*#' "$f" | grep -qF -f "$bundle_markers"; then
            echo "$f: it names the web bundle, but $u is in NO_WEB_BUNDLE_UNITS"
          fi
          ;;
      esac
    done
    for g in $IRIS_GROUPS; do
      if ! p=$(group_input_pattern "$g" 2>/dev/null); then
        echo "ci/units.sh: group_input_pattern $g fails"
      elif [ -z "$p" ]; then
        echo "ci/units.sh: group_input_pattern $g prints nothing"
      else
        for path in ci/units.sh .github/workflows/ci.yml src/x; do
          printf '%s\n' "$path" | grep -Eq -- "$p" || echo "ci/units.sh: group_input_pattern $g does not match $path"
        done
        # A file that a live script of the group sources or adds is an input of the group: its pattern must claim it.
        for u in $(group_units "$g"); do
          case $u in
            live:*)
              f="docker/tests/test-${u#live:}.sh"
              [ -f "$f" ] || continue
              for rel in $(unit_reads "$f"); do
                printf '%s\n' "$rel" | grep -Eq -- "$p" || echo "$f: it reads $rel, which the input pattern of group $g does not claim"
              done
              ;;
          esac
        done
      fi
    done
    if p=$(group_input_pattern nosuch-group 2>/dev/null) || [ -n "${p:-}" ]; then
      echo "ci/units.sh: group_input_pattern answers for the unknown group nosuch-group"
    fi
  )
}

# mkinputs <dir> [<shell text appended to ci/units.sh>]: the real ci/units.sh below <dir>, and a stub script for each live unit whose
# only mention of the web bundle is in a comment. The appended text redefines what a sample breaks.
mkinputs() {
  local d=$1 u
  mkdir -p "$d/ci" "$d/docker/tests"
  cp ci/units.sh "$d/ci/units.sh"
  if [ -n "${2:-}" ]; then printf '\n%s\n' "$2" >> "$d/ci/units.sh"; fi
  for u in $(. ./ci/units.sh && for g in $IRIS_GROUPS; do group_units "$g"; done); do
    case $u in
      live:*) printf '#!/usr/bin/env bash\n# it does not use %s\n:\n' "$(tr '\n' ' ' < "$bundle_markers")" > "$d/docker/tests/test-${u#live:}.sh" ;;
    esac
  done
}
# script_line <dir> <unit name> <text>: the unit's script gets that line.
script_line() { printf '%s\n' "$3" >> "$1/docker/tests/test-$2.sh"; }
# bundle_script <dir> <unit name>: the unit's script gets a code line that names the web bundle.
bundle_script() { printf '%s\n' "$(sed -n 1p "$bundle_markers")" >> "$1/docker/tests/test-$2.sh"; }

mkinputs "$tmp/i-good"
mkinputs "$tmp/i-comment-only" 'NO_WEB_BUNDLE_UNITS="$NO_WEB_BUNDLE_UNITS live:install-start live:sign-in"'
mkinputs "$tmp/i-listed-install-start" 'NO_WEB_BUNDLE_UNITS="$NO_WEB_BUNDLE_UNITS live:install-start"'; bundle_script "$tmp/i-listed-install-start" install-start
mkinputs "$tmp/i-listed-sign-in" 'NO_WEB_BUNDLE_UNITS="$NO_WEB_BUNDLE_UNITS live:sign-in"'; bundle_script "$tmp/i-listed-sign-in" sign-in
mkinputs "$tmp/i-unknown-unit" 'NO_WEB_BUNDLE_UNITS="$NO_WEB_BUNDLE_UNITS live:nosuch-unit"'
mkinputs "$tmp/i-fn-fails" 'group_input_pattern() { return 1; }'
mkinputs "$tmp/i-fn-empty" 'group_input_pattern() { group_units "$1" > /dev/null || return 1; }'
mkinputs "$tmp/i-fn-narrow" 'group_input_pattern() { group_units "$1" > /dev/null || return 1; echo "^(ci/|\.github/workflows/ci\.yml\$)"; }'
mkinputs "$tmp/i-fn-any" 'group_input_pattern() { echo "^(src/|ci/|\.github/workflows/ci\.yml\$)"; }'
# A live script reads the files its group claims (a comment may name any): clean. A file that its group does not claim is not.
mkinputs "$tmp/i-reads-claimed"
script_line "$tmp/i-reads-claimed" install-start 'live_add_file "$root/docker-compose.dev.yml"'
script_line "$tmp/i-reads-claimed" install-start '. "$(dirname "$0")/lib-scan.sh"'
script_line "$tmp/i-reads-claimed" compose-start 'live_add_file "${root}/docker/tests/compose.no-after-start.yml"'
mkinputs "$tmp/i-reads-comment"
script_line "$tmp/i-reads-comment" production '# live_add_file "$root/docker/tests/extra/compose.x.yml"'
script_line "$tmp/i-reads-comment" demo-path '  # . "$(dirname "$0")/helper.sh"'
script_line "$tmp/i-reads-comment" sign-in 'cd "$root/web"'
mkinputs "$tmp/i-reads-compose"
script_line "$tmp/i-reads-compose" production 'live_add_file "$root/docker/tests/extra/compose.x.yml"'
mkinputs "$tmp/i-reads-helper"
script_line "$tmp/i-reads-helper" demo-path '. "$(dirname "$0")/helper.sh"'
mkdir -p "$tmp/i-unread/ci" && : > "$tmp/i-unread/ci/units.sh"

ok=1
# The comment-only tree lists two units whose scripts name the bundle only in a comment: it stays clean.
for good in i-good i-comment-only i-reads-claimed i-reads-comment; do
  if [ -n "$(inputs_violations "$tmp/$good")" ]; then
    echo "FAIL inputs: the rule flags the good tree $good ($(inputs_violations "$tmp/$good" | head -n 3 | tr '\n' ';'))"
    ok=0
  fi
done
# Each bad sample must draw its own violation, so that no other violation of the same sample can stand in for it.
for pair in "i-listed-install-start|docker/tests/test-install-start.sh: it names the web bundle, but live:install-start is in NO_WEB_BUNDLE_UNITS" \
  "i-listed-sign-in|docker/tests/test-sign-in.sh: it names the web bundle, but live:sign-in is in NO_WEB_BUNDLE_UNITS" \
  "i-unknown-unit|NO_WEB_BUNDLE_UNITS names live:nosuch-unit, which is a unit of no group" \
  "i-fn-fails|group_input_pattern production fails" "i-fn-empty|group_input_pattern production prints nothing" \
  "i-fn-narrow|group_input_pattern production does not match src/x" "i-fn-any|group_input_pattern answers for the unknown group nosuch-group" \
  "i-reads-compose|docker/tests/test-production.sh: it reads docker/tests/extra/compose.x.yml, which the input pattern of group production does not claim" \
  "i-reads-helper|docker/tests/test-demo-path.sh: it reads docker/tests/helper.sh, which the input pattern of group browser does not claim"; do
  s=${pair%%|*}
  want=${pair#*|}
  got=$(inputs_violations "$tmp/$s")
  case $got in
    *"$want"*) ;;
    *)
      echo "FAIL inputs: the sample $s does not draw '$want' (got: $(printf '%s' "$got" | head -n 3 | tr '\n' ';'))"
      ok=0
      ;;
  esac
done
# Every marker must by itself list a unit that is in NO_WEB_BUNDLE_UNITS as a unit that names the web bundle (audit is one).
nmark=0
while IFS= read -r marker; do
  nmark=$((nmark + 1))
  mkinputs "$tmp/i-marker-$nmark"
  script_line "$tmp/i-marker-$nmark" audit "echo $marker"
  case $(inputs_violations "$tmp/i-marker-$nmark") in
    *"docker/tests/test-audit.sh: it names the web bundle, but live:audit is in NO_WEB_BUNDLE_UNITS"*) ;;
    *)
      echo "FAIL inputs: a code line that holds the marker number $nmark of the web bundle is not flagged"
      ok=0
      ;;
  esac
done < "$bundle_markers"
if [ -z "$(real_hits inputs inputs_violations "$tmp/i-unread" 2>/dev/null)" ]; then
  echo "FAIL inputs: a tree whose ci/units.sh cannot be read passes the rule"
  ok=0
fi
hits=$(real_hits inputs inputs_violations "$root")
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | head -n 10 | sed 's/^/  /'
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "PASS inputs: every unit that is not checked against the web bundle is a unit of a group and names no bundle input in a code line, and each group has an input pattern that claims ci/units.sh, the workflow, src/ and every file that its live scripts source or add"
else
  echo "FAIL inputs: the input patterns of the IRIS groups and NO_WEB_BUNDLE_UNITS"
  fails=$((fails + 1))
fi

# --- the test classes of a shard: a non-abstract class with a Method Test... directly in an area folder ---

# discovered <tree> <area>...: the classes that ci/iris.sh (sourced, which then runs nothing) takes for the test classes of those
# areas in the tree below <tree>, one per line in name order.
discovered() {
  local tree=$1
  shift
  ( . "$root/ci/iris.sh"; cd "$tree" && test_classes "$@" )
}
# tc_class <tree> <Class> <declaration tail> <body lines...>: src/<ocutalon|bridge>/cls/... holding one class; the tree is the
# second argument's prefix, bridge or ocutalon.
tc_class() {
  local tree=$1 class=$2 tail=$3 file
  shift 3
  file="$tree/src/${TC_SRC:-ocutalon}/cls/$(printf '%s' "$class" | tr . /).cls"
  mkdir -p "$(dirname "$file")"
  { printf 'Class %s Extends %%UnitTest.TestCase%s\n{\n' "$class" "$tail"; printf '%s\n' "$@"; printf '}\n'; } > "$file"
}
tc="$tmp/tc"
tc_class "$tc" OcuTalon.Test.Alpha.One "" 'Method TestOne()' '{' '}'
TC_SRC=bridge tc_class "$tc" OcuTalon.Test.Alpha.Two "" 'Method TestTwo()' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.Base " [ Abstract ]" 'Method TestInherited()' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.BaseTwo " [ ProcedureBlock, Abstract ]" 'Method TestInheritedToo()' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.Helper "" 'ClassMethod Make()' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.Sub.Deep "" 'Method TestDeep()' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.HasAbstractMethod "" 'Method TestWithAbstractMember()' '{' '}' 'Method Hook() [ Abstract ]' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.NotAbstract " [ Not Abstract ]" 'Method TestConcrete()' '{' '}'
tc_class "$tc" OcuTalon.Test.Alpha.Depends " [ DependsOn = OcuTalon.Test.AbstractBase ]" 'Method TestDepends()' '{' '}'
tc_class "$tc" OcuTalon.Test.Beta.Zed "" 'Method TestZed()' '{' '}'
tc_class "$tc" OcuTalon.Test.Beta.Abc "" 'Method TestAbc()' '{' '}'
tc_class "$tc" OcuTalon.Test.Gamma.Other "" 'Method TestOther()' '{' '}'
got=$(discovered "$tc" Alpha Beta | tr '\n' ' ')
want="OcuTalon.Test.Alpha.Depends OcuTalon.Test.Alpha.HasAbstractMethod OcuTalon.Test.Alpha.NotAbstract OcuTalon.Test.Alpha.One OcuTalon.Test.Alpha.Two OcuTalon.Test.Beta.Abc OcuTalon.Test.Beta.Zed "
ok=1
if [ "$got" != "$want" ]; then
  echo "FAIL test classes: a synthetic tree gave '$got', wanted '$want' (abstract classes, helpers, sub-folders and other areas are out; both source trees, Not Abstract and a DependsOn that names Abstract are in, in name order)"
  ok=0
fi
# The real tree: every class that ci/iris.sh takes is a concrete class with a test method, and every concrete class with a test
# method that sits directly in an area folder is taken.
want_real=$(for f in $(grep -l '^Method Test' src/*/cls/OcuTalon/Test/*/*.cls); do
  if ! grep -m 1 '^Class ' "$f" | grep -q 'Abstract'; then printf '%s\n' "$f" | sed -e 's#^src/[^/]*/cls/##' -e 's#\.cls$##' -e 's#/#.#g'; fi
done | LC_ALL=C sort | tr '\n' ' ')
got_real=$(bash ci/iris.sh classes | tr '\n' ' ')
if [ -z "$got_real" ] || [ "$got_real" != "$want_real" ]; then
  echo "FAIL test classes: ci/iris.sh classes gives '$got_real', a plain search gives '$want_real'"
  ok=0
fi
shards_real=$( (. ci/units.sh; for s in $SHARDS; do bash ci/iris.sh classes "$s"; done) | LC_ALL=C sort | tr '\n' ' ')
if [ "$shards_real" != "$got_real" ]; then
  echo "FAIL test classes: the classes of the shards together are not the classes of every shard"
  ok=0
fi
if [ "$ok" -eq 1 ]; then
  echo "PASS test classes: a non-abstract class with a Method Test... directly in an area folder is taken, nothing else is, and the shards hold them all"
else
  fails=$((fails + 1))
fi

# --- the recipe's refusals and its web port ---

# iris_env <env assignments...> <command...>: the command with no run tag, web port, runner name or warm mode from the caller's environment.
iris_env() { env -u OCUTALON_RUN_TAG -u OCUTALON_TEST_WEB_PORT -u RUNNER_NAME -u OCUTALON_WARM "$@"; }

# recipe <expected exit> <expected text or -> <env assignments...> -- <ci/iris.sh arguments...>
recipe_fail=""
recipe() {
  local want=$1 text=$2 out rc
  shift 2
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  out=$(iris_env ${envs[@]+"${envs[@]}"} bash ci/iris.sh "$@" 2>&1)
  rc=$?
  if [ "$rc" -ne "$want" ] || { [ "$text" != - ] && ! printf '%s\n' "$out" | grep -q -- "$text"; }; then
    recipe_fail="$recipe_fail [ci/iris.sh $* -> exit $rc, wanted exit $want with '$text']"
  fi
}
recipe 2 "must match" OCUTALON_RUN_TAG=Bad_Tag -- build
recipe 2 "must match" OCUTALON_RUN_TAG=my-slot-tag -- build
recipe 2 "must match" OCUTALON_RUN_TAG=ab -- build
recipe 2 "needs OCUTALON_RUN_TAG" -- teardown
recipe 2 "unknown shard" -- shard nope
recipe 2 "unknown test class" -- class OcuTalon.Test.Nope
recipe 2 "unknown test class" -- class OcuTalon.Test.Install.User.
recipe 2 "unknown test class" -- class '.*'
recipe 2 "unknown live unit" -- live nosuch
recipe 2 "unknown group" -- group nosuch
recipe 2 "Needs bash 3.2 or later" -- nosuchcommand
recipe 1 "base image" IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- build
recipe 0 "^52811$" RUNNER_NAME=ocutalon-ci-1 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52812$" RUNNER_NAME=ocutalon-ci-2 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52819$" RUNNER_NAME=ocutalon-ci-9 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52809$" RUNNER_NAME=ocutalon-ci-10 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52807$" RUNNER_NAME=ocutalon-ci-12 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52805$" RUNNER_NAME=ocutalon-ci-14 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52800$" RUNNER_NAME=ocutalon-ci-19 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52807$" RUNNER_NAME=ocutalon-ci-012 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52818$" RUNNER_NAME=ocutalon-ci-08 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52800$" RUNNER_NAME=ocutalon-ci-019 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52810$" RUNNER_NAME=ocutalon-ci-0 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci-20 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci-114 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci-x OCUTALON_RUN_TAG=abc-1 -- port
# QA (Story 32.3): a number followed by a letter, a trailing hyphen with no number, and a leading-zero 20 are no runner number (the
# digits are not cut out of the suffix; 0020 is 20 in base 10, 16 in octal).
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci-12b OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci-1a OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci- OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=ocutalon-ci-0020 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" RUNNER_NAME=somerunner OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^auto$" OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52805$" OCUTALON_TEST_WEB_PORT=52805 RUNNER_NAME=ocutalon-ci-1 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52805$" OCUTALON_TEST_WEB_PORT=52805 RUNNER_NAME=ocutalon-ci-12 OCUTALON_RUN_TAG=abc-1 -- port
# QA (Story 32.3): a set OCUTALON_TEST_WEB_PORT wins whatever the runner is: one of each branch (0, 1, 9, 10, 12, 19), a number of 20 or
# more, a number with a letter after it, a name with no number, an empty RUNNER_NAME and none at all. 52803 is the fixed port of none of
# them, so a runner that kept its own port would show. A set but empty OCUTALON_TEST_WEB_PORT counts as unset, as it does for live_web_port.
for override_runner in ocutalon-ci-0 ocutalon-ci-1 ocutalon-ci-9 ocutalon-ci-10 ocutalon-ci-12 ocutalon-ci-19 ocutalon-ci-20 ocutalon-ci-12b somerunner ""; do
  recipe 0 "^52803$" OCUTALON_TEST_WEB_PORT=52803 RUNNER_NAME="$override_runner" OCUTALON_RUN_TAG=abc-1 -- port
done
recipe 0 "^52803$" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_RUN_TAG=abc-1 -- port
recipe 0 "^52807$" OCUTALON_TEST_WEB_PORT= RUNNER_NAME=ocutalon-ci-12 OCUTALON_RUN_TAG=abc-1 -- port
recipe 1 "PORT the web port of the browser units: 52812$" RUNNER_NAME=ocutalon-ci-2 IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live sign-in
recipe 1 "PORT the web port of the browser units: 52807$" RUNNER_NAME=ocutalon-ci-12 IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live sign-in
recipe 1 "^FAIL the base image ocutalon-no-such-image:0 is not on this machine" RUNNER_NAME=ocutalon-ci-12 IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live sign-in
recipe 1 "PORT the web port of the browser units: 52803$" OCUTALON_TEST_WEB_PORT=52803 RUNNER_NAME=ocutalon-ci-12 IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live sign-in
recipe 1 "PORT the web port of the browser units: auto$" RUNNER_NAME=ocutalon-ci-20 IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live sign-in
recipe 1 "PORT the web port of the browser units: auto$" IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live sign-in
recipe 1 "PORT the web port of the browser units: auto$" IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- live demo-path
# The runners of one host share its 127.0.0.1 (DW-49), so the 19 runners 1 to 19 must get 19 distinct ports, each one that live_web_port
# accepts: within 52800-52819 and not in LIVE_FORBIDDEN_PORTS (read from a sourced ci/iris.sh, which defines functions and runs nothing).
forbidden_ports=$(unset OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_WARM; . ci/iris.sh; printf '%s' "$LIVE_FORBIDDEN_PORTS")
if [ -z "$forbidden_ports" ]; then
  recipe_fail="$recipe_fail [LIVE_FORBIDDEN_PORTS could not be read from a sourced ci/iris.sh]"
fi
seen_ports=" "
runner_n=1
while [ "$runner_n" -le 19 ]; do
  runner_port=$(iris_env RUNNER_NAME="ocutalon-ci-$runner_n" OCUTALON_RUN_TAG=abc-1 bash ci/iris.sh port 2>&1)
  case $runner_port in
    5280[0-9] | 5281[0-9]) ;;
    *) recipe_fail="$recipe_fail [runner $runner_n: port '$runner_port' is not within 52800-52819]" ;;
  esac
  case $seen_ports in
    *" $runner_port "*) recipe_fail="$recipe_fail [runner $runner_n: port '$runner_port' repeats an earlier runner's]" ;;
  esac
  case " $forbidden_ports " in
    *" $runner_port "*) recipe_fail="$recipe_fail [runner $runner_n: port '$runner_port' is in LIVE_FORBIDDEN_PORTS]" ;;
  esac
  seen_ports="$seen_ports$runner_port "
  runner_n=$((runner_n + 1))
done
# QA (Story 32.3; DW-49): the same ports through the real live_web_port, which a browser unit calls after setup_tag. A subshell sources
# ci/iris.sh (it defines functions and runs nothing), replaces port_in_use by a list of held ports (nothing listens and nothing is
# bound), and for each case runs setup_tag and then live_web_port. The expected fixed port is the spec's mapping, written out here:
# 52810 + n for n from 0 to 9, 52819 - n for n from 10 to 19.
#   - the fixed port of every runner 0 to 19 is accepted as it is, so live_web_port's range holds all twenty, and a child process
#     sees it, because ci/iris.sh live starts the browser unit's script as one; a probing runner's child sees no port;
#   - a fixed port that something already holds fails "in use" and takes no other port (a runner of the same host, or a probing runner
#     that got there first, ends its unit and does not move to a free port);
#   - a probing runner (no RUNNER_NAME, a name with no number or a non-digit suffix, a number of 20 or more) takes 52800, the first
#     port of the range, as a developer machine does today;
#   - that first pick, 52800, is the fixed port of runner 19 alone: runners 1 to 18 never meet it. This is the limit of the design (the
#     header of ci/iris.sh): a probing runner on a host that also ran a runner 19 could meet it, and no such service exists (today's are 3
#     to 14). The race itself (a probe does not bind the port) cannot be shown without a stack.
live_port_checks() {
  (
    unset OCUTALON_TEST_WEB_PORT
    . ci/iris.sh
    OCUTALON_RUN_TAG=abc-1
    tmp="$tmp/live-port"
    mkdir -p "$tmp"
    held=""
    port_in_use() { [[ " $held " == *" $1 "* ]]; }
    # try <runner name> <held ports>: setup_tag, then live_web_port. Sets try_rc, try_port (web_port), try_msg (its first line) and
    # try_child (the port that a child process sees, as the browser unit's own script does). setup_tag leaves a global n behind, so the
    # loops below count with idx.
    try() {
      RUNNER_NAME=$1
      held=$2
      unset OCUTALON_TEST_WEB_PORT
      LIVE_FILES=()
      web_port=""
      setup_tag
      try_child=$(bash -c 'printf %s "${OCUTALON_TEST_WEB_PORT-}"')
      live_web_port > "$tmp/out" 2>&1
      try_rc=$?
      try_port=$web_port
      try_msg=$(head -n 1 "$tmp/out")
    }
    try "" ""
    prober_first=$try_port
    if [ "$try_rc" -ne 0 ] || [ "$prober_first" != 52800 ]; then
      printf ' [no runner: live_web_port gave exit %s and port %s, wanted exit 0 and 52800]' "$try_rc" "${prober_first:-none}"
    fi
    if [ -n "$try_child" ]; then
      printf ' [no runner: a child process sees port %s, wanted none]' "$try_child"
    fi
    for prober in somerunner ocutalon-ci-x ocutalon-ci-12b ocutalon-ci- ocutalon-ci-20 ocutalon-ci-114 ocutalon-ci-0020; do
      try "$prober" ""
      if [ "$try_rc" -ne 0 ] || [ "$try_port" != 52800 ]; then
        printf ' [%s: live_web_port gave exit %s and port %s, wanted exit 0 and 52800]' "$prober" "$try_rc" "${try_port:-none}"
      fi
      if [ -n "$try_child" ]; then
        printf ' [%s: a child process sees port %s, wanted none]' "$prober" "$try_child"
      fi
    done
    idx=0
    while [ "$idx" -le 19 ]; do
      if [ "$idx" -le 9 ]; then want=$((52810 + idx)); else want=$((52819 - idx)); fi
      try "ocutalon-ci-$idx" ""
      if [ "$try_rc" -ne 0 ] || [ "$try_port" != "$want" ]; then
        printf ' [runner %s: live_web_port gave exit %s and port %s, wanted exit 0 and %s: %s]' "$idx" "$try_rc" "${try_port:-none}" "$want" "$try_msg"
      fi
      if [ "$try_child" != "$want" ]; then
        printf ' [runner %s: a child process sees port %s, wanted %s: setup_tag does not export it]' "$idx" "${try_child:-none}" "$want"
      fi
      if [ "$idx" -ge 1 ] && [ "$idx" -le 18 ] && [ "$try_port" = "$prober_first" ]; then
        printf ' [runner %s: its port %s is the first port that a probing runner takes]' "$idx" "$try_port"
      fi
      try "ocutalon-ci-$idx" "$want"
      if [ "$try_rc" -ne 1 ] || [ -n "$try_port" ] || ! printf '%s\n' "$try_msg" | grep -q 'in use'; then
        printf ' [runner %s: with port %s held, live_web_port gave exit %s and port %s, wanted exit 1, no port and an in use message: %s]' \
          "$idx" "$want" "$try_rc" "${try_port:-none}" "$try_msg"
      fi
      idx=$((idx + 1))
    done
    printf ' [live-port-done]'
  )
}
live_port_out=$(live_port_checks)
case $live_port_out in
  *'[live-port-done]') recipe_fail="$recipe_fail${live_port_out%' [live-port-done]'}" ;;
  *) recipe_fail="$recipe_fail [the checks through live_web_port did not run to their end: $(printf '%s' "$live_port_out" | tr -d '[]' | head -c 300)]" ;;
esac
# The six groups through the command line (Story 32.1). `groups` prints the names in order. `list` shows the install groups with their
# anchor units, and no more than that is pinned (a rebalance of whole units needs no edit). The retired name install is refused with
# exit 2 and the new list; it runs with a base image that does not exist, so that a stale `install` case of group_units would end at
# the preflight (exit 1, red) and never start a stack. For every group, the tag of its CI job (<run id>-<attempt>-<group>, as in
# ci.yml) is a valid run tag, and `group <name>` knows the name: with that tag and the missing base image it ends at the preflight
# with exit 1, where an unknown group or a refused tag would give exit 2.
cli_groups=$(bash ci/iris.sh groups 2>&1 | tr '\n' ' ')
if [ "$cli_groups" != "install-fresh install-upgrade production browser shards image " ]; then
  recipe_fail="$recipe_fail [ci/iris.sh groups printed '$cli_groups']"
fi
cli_list=$(bash ci/iris.sh list 2>&1)
printf '%s\n' "$cli_list" | grep -Eq -- '^group install-fresh: (.* )?live:install-start( |$)' \
  || recipe_fail="$recipe_fail [ci/iris.sh list has no group install-fresh line with live:install-start]"
printf '%s\n' "$cli_list" | grep -Eq -- '^group install-upgrade: (.* )?live:install-upgrade( |$)' \
  || recipe_fail="$recipe_fail [ci/iris.sh list has no group install-upgrade line with live:install-upgrade]"
recipe 2 "^unknown group 'install'; groups: install-fresh install-upgrade production browser shards image$" \
  IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG=abc-1 -- group install
for cli_group in $(bash ci/iris.sh groups); do
  recipe 0 "auto" OCUTALON_RUN_TAG="39594299887-1-$cli_group" -- port
  recipe 1 "the base image" IRIS_IMAGE=ocutalon-no-such-image:0 OCUTALON_RUN_TAG="39594299887-1-$cli_group" -- group "$cli_group"
done

# A browser unit installs Chromium before its script runs. A stub docker lets the preflight pass (it answers every `image inspect`,
# the base image's and the mock image's, so nothing is pulled), and a stub npx that records its arguments and fails ends the run
# before the unit's script starts.
mkdir -p "$tmp/chromium-bin"
printf '#!/bin/sh\n[ "$1" = image ] && exit 0\nexit 1\n' > "$tmp/chromium-bin/docker"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "$tmp/chromium.args" > "$tmp/chromium-bin/npx"
chmod +x "$tmp/chromium-bin/docker" "$tmp/chromium-bin/npx"
for browser_unit in $(. ./ci/units.sh && printf '%s' "$BROWSER_UNITS"); do
  : > "$tmp/chromium.args"
  recipe 1 "PORT the web port" PATH="$tmp/chromium-bin:$PATH" OCUTALON_RUN_TAG=abc-1 -- live "$browser_unit"
  if [ "$(cat "$tmp/chromium.args")" != "--prefix web playwright install chromium" ]; then
    recipe_fail="$recipe_fail [ci/iris.sh live $browser_unit does not install Chromium before the unit's script]"
  fi
done
if [ -z "$recipe_fail" ]; then
  echo "PASS recipe: bad tags, units and a missing base image are refused, the web port follows the runner's number (the ports of runners 1 to 19 are distinct and exported, and live_web_port takes each one), and the six groups answer groups, list and group (the retired install is refused) under their CI tags"
else
  printf '%s\n' "$recipe_fail" | tr ']' '\n' | sed 's/^ *\[/  /' | grep . | head -n 10
  echo "FAIL recipe: ci/iris.sh does not refuse, does not choose the port, or does not answer for the six groups, as designed"
  fails=$((fails + 1))
fi

# --- ci/iris.sh preflight: the mock's image is pulled up to 3 times when it is missing, and never when it is present ---

# The image that ci/compose.ci.yml pins for the mock.
mock_ref=$(sed -n 's/^[[:space:]]*image:[[:space:]]*\(node:[^[:space:]]*\)[[:space:]]*$/\1/p' ci/compose.ci.yml)

# preflight_run <mock image present: 1|0> <the pull that succeeds: n, or 99 for none> <OCUTALON_PULL_PAUSE> <function and arguments...>:
# runs the function of a sourced ci/iris.sh with a stub docker, which answers the base image and records every pull, and a stub sleep.
# Sets pf_rc and pf_out, and pf_pulls, pf_composes, pf_sleeps and pf_refs from the calls.
preflight_run() {
  local present=$1 succeed_on=$2 pause=$3
  shift 3
  pf_calls=$tmp/pf-calls
  : > "$pf_calls"
  (
    unset OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_WARM IRIS_IMAGE
    . ci/iris.sh
    OCUTALON_PULL_PAUSE=$pause
    docker() {
      case $1 in
        image)
          case ${!#} in ocutalon-iris-base:*) return 0 ;; esac
          [ "$present" = 1 ]
          ;;
        pull)
          echo "pull $2" >> "$pf_calls"
          [ "$(grep -c '^pull ' "$pf_calls")" -ge "$succeed_on" ]
          ;;
        *) echo "docker $1" >> "$pf_calls" ;;
      esac
    }
    sleep() { echo "sleep $1" >> "$pf_calls"; }
    "$@"
  ) > "$tmp/pf-out" 2>&1
  pf_rc=$?
  pf_out=$(cat "$tmp/pf-out")
  pf_pulls=$(grep -c '^pull ' "$pf_calls")
  pf_composes=$(grep -c '^docker ' "$pf_calls")
  pf_sleeps=$(sed -n 's/^sleep //p' "$pf_calls" | tr '\n' ' ')
  pf_refs=$(sed -n 's/^pull //p' "$pf_calls" | sort -u)
}
pf_ok=1
pf_fail() { echo "FAIL preflight: $1"; pf_ok=0; }
[ -n "$mock_ref" ] || pf_fail "ci/compose.ci.yml names no node image for the mock"
preflight_run 0 3 0 preflight
{ [ "$pf_rc" -eq 0 ] && [ "$pf_pulls" -eq 3 ] && [ "$pf_refs" = "$mock_ref" ]; } || pf_fail "a missing image whose third pull succeeds gave exit $pf_rc after $pf_pulls pull(s) of '$pf_refs'; wanted exit 0 after 3 pulls of the pinned image"
preflight_run 0 1 0 preflight
{ [ "$pf_rc" -eq 0 ] && [ "$pf_pulls" -eq 1 ]; } || pf_fail "a missing image whose first pull succeeds gave exit $pf_rc after $pf_pulls pull(s); wanted exit 0 after 1"
preflight_run 1 99 0 preflight
{ [ "$pf_rc" -eq 0 ] && [ "$pf_pulls" -eq 0 ]; } || pf_fail "a present image gave exit $pf_rc after $pf_pulls pull(s); wanted exit 0 and no pull"
preflight_run 0 99 7 run_classes shard-lane-a lane-a OcuTalon.Test.Nothing
{ [ "$pf_rc" -eq 1 ] && [ "$pf_pulls" -eq 3 ] && [ "$pf_composes" -eq 0 ] && [ "$pf_sleeps" = "7 21 " ] \
  && ! printf '%s\n' "$pf_out" | grep -q '^STACK ' \
  && printf '%s\n' "$pf_out" | grep -qF "FAIL the mock image $mock_ref could not be pulled after 3 tries (Docker Hub); no stack was started"; } \
  || pf_fail "pulls that always fail gave exit $pf_rc, $pf_pulls pull(s), $pf_composes docker call(s) besides inspect and pull, pauses '$pf_sleeps'; wanted the FAIL line, exit 1, 3 pulls, no stack and pauses '7 21 '"
# The pause between tries: 10 s when the variable is unset or empty or not a number, read in decimal, and tripled after each try.
for pc in ':10 30 ' 'abc:10 30 ' '08:8 24 '; do
  preflight_run 0 99 "${pc%%:*}" preflight
  { [ "$pf_rc" -eq 1 ] && [ "$pf_pulls" -eq 3 ] && [ "$pf_sleeps" = "${pc#*:}" ]; } \
    || pf_fail "OCUTALON_PULL_PAUSE='${pc%%:*}' gave exit $pf_rc, $pf_pulls pull(s), pauses '$pf_sleeps'; wanted exit 1, 3 pulls and pauses '${pc#*:}'"
done
if [ "$pf_ok" -eq 1 ]; then
  echo "PASS preflight: a missing mock image is pulled by its pinned reference up to 3 times with growing pauses, the FAIL line and exit 1 come before any stack, and a present image is not pulled"
else
  fails=$((fails + 1))
fi

# --- docker/tests/test-mock.sh: the web job's step is red when a mock test is red ---

# A stub node first on the PATH answers --version and exits with the given status for anything else, printing its arguments.
# The wrapper must run every test file of ci/mock/test/ and must exit with that status.
mock_stub=$tmp/mock-wrapper-stub
mkdir -p "$mock_stub"
mock_files=$(ls ci/mock/test/*.test.mjs | tr '\n' ' ')
mock_ok=1
for rc in 0 3; do
  printf '#!/bin/sh\ncase "$1" in --version) echo v24.0.0; exit 0 ;; esac\necho "stub node $*"\nexit %s\n' "$rc" > "$mock_stub/node"
  chmod +x "$mock_stub/node"
  mock_out=$(PATH="$mock_stub:$PATH" bash docker/tests/test-mock.sh 2>&1)
  mock_rc=$?
  if [ "$mock_rc" -ne "$rc" ]; then
    echo "FAIL mock wrapper: a node that exits $rc gave exit $mock_rc"
    mock_ok=0
  fi
  if [ "$(printf '%s\n' "$mock_out" | sed -n 's/^stub node --test //p')" != "${mock_files% }" ]; then
    echo "FAIL mock wrapper: it ran '$(printf '%s\n' "$mock_out" | sed -n 's/^stub node //p')', not node --test on every file of ci/mock/test/"
    mock_ok=0
  fi
done
if [ "$mock_ok" -eq 1 ]; then
  echo "PASS mock wrapper: docker/tests/test-mock.sh runs node --test on every test file of ci/mock/test/ and exits with node's status"
else
  fails=$((fails + 1))
fi

# --- ci/checks.sh: every script runs, a failure does not stop the others, and the exit code names what failed ---

# mkchecks <dir> <names> <exit code of script b>: a tree with a copy of ci/checks.sh, its list of names and stub scripts.
mkchecks() {
  local d=$1 names=$2 code=$3 n
  mkdir -p "$d/ci" "$d/docker/tests"
  cp ci/checks.sh "$d/ci/checks.sh"
  printf 'CHECK_SCRIPTS="%s"\n' "$names" > "$d/ci/units.sh"
  for n in a b c; do
    if [ "$n" = b ]; then printf 'echo ran %s\nexit %s\n' "$n" "$code" > "$d/docker/tests/test-$n.sh"; else printf 'echo ran %s\n' "$n" > "$d/docker/tests/test-$n.sh"; fi
  done
}
mkchecks "$tmp/ck-good" "a b c" 0
mkchecks "$tmp/ck-fail" "a b c" 3
mkchecks "$tmp/ck-missing" "a b c d" 0
ck_good=$(bash "$tmp/ck-good/ci/checks.sh" 2>&1); ck_good_rc=$?
ck_fail=$(bash "$tmp/ck-fail/ci/checks.sh" 2>&1); ck_fail_rc=$?
ck_missing=$(bash "$tmp/ck-missing/ci/checks.sh" 2>&1); ck_missing_rc=$?
if [ "$ck_good_rc" -eq 0 ] && printf '%s\n' "$ck_good" | grep -q '^ran a$' && printf '%s\n' "$ck_good" | grep -q '^ran c$' && printf '%s\n' "$ck_good" | grep -q '^checks: all scripts passed$' \
  && [ "$ck_fail_rc" -eq 1 ] && printf '%s\n' "$ck_fail" | grep -q '^ran c$' && printf '%s\n' "$ck_fail" | grep -q '^==== b failed (exit 3)' \
  && printf '%s\n' "$ck_fail" | grep -q '^checks: failed: b$' && ! printf '%s\n' "$ck_fail" | grep -q 'all scripts passed' \
  && [ "$ck_missing_rc" -eq 1 ] && printf '%s\n' "$ck_missing" | grep -q '^checks: failed: d$'; then
  echo "PASS checks.sh: it runs every script to its end, exits 1 naming each failed or missing script, and exits 0 when all pass"
else
  echo "FAIL checks.sh: it does not run every script, or its exit code or summary is wrong (good $ck_good_rc, failing $ck_fail_rc, missing $ck_missing_rc)"
  fails=$((fails + 1))
fi

# --- ci/iris.sh run_class: the verdict on one test class, from the lines that its IRIS session prints ---

# verdict_case <label> <wanted exit> <session lines> <regex that the output must hold>...: ci/iris.sh is sourced (it then runs nothing)
# and `dc` answers with the session lines.
verdict_ok=1
verdict_case() {
  local label=$1 want=$2 session=$3 out rc re
  shift 3
  out=$(
    SESSION=$session
    . ci/iris.sh
    dc() { cat > /dev/null; printf '%s\n' "$SESSION"; }
    sleep() { :; }
    run_class OcuTalon.Test.Zz.Sample
  )
  rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL class verdict: $label (exit $rc, wanted $want)"
    verdict_ok=0
    return
  fi
  for re in "$@"; do
    if ! printf '%s\n' "$out" | grep -q -- "$re"; then
      echo "FAIL class verdict: $label (the output has no line like '$re')"
      verdict_ok=0
    fi
  done
}
cls=OcuTalon.Test.Zz.Sample
verdict_case "a pass" 0 "$(printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' "CHK|case|$cls|1|0.0123|2")" "^CLASS $cls passed 0.01s$"
verdict_case "a failed assertion" 1 "$(printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' "CHK|case|$cls|0|0.5|2" 'CHK|assert|0|TestOne|the sum is wrong')" \
  "^CLASS $cls failed 0.50s$" "^  FAIL TestOne: the sum is wrong$"
verdict_case "a skipped assertion passes and is named" 0 "$(printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' "CHK|case|$cls|1|0.01|1" 'CHK|assert|2|TestOne|no production here')" \
  "^CLASS $cls passed" "^  SKIP TestOne: no production here$"
verdict_case "an error" 1 "$(printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' "CHK|case|$cls|0|0.1|1" 'CHK|error|TestOne|boom')" "^CLASS $cls failed" "^  ERROR TestOne: boom$"
verdict_case "a class that is not compiled" 1 "$(printf '%s\n' 'CHK|compiled|0' 'CHK|new|0')" "^CLASS $cls failed" "not compiled"
verdict_case "a run that left no result" 1 "$(printf '%s\n' 'CHK|compiled|1' 'CHK|new|0')" "^CLASS $cls failed" "left no result"
verdict_case "a class that ran no test" 1 "$(printf '%s\n' 'CHK|compiled|1' 'CHK|new|1' "CHK|case|$cls|1|0.01|0")" "^CLASS $cls failed" "ran no test"
verdict_case "a session that printed nothing" 1 "" "^CLASS $cls failed" "not compiled"
if [ "$verdict_ok" -eq 1 ]; then
  echo "PASS class verdict: a pass, a skip and a failed class, an error, a class not compiled, no result, no test and an empty session are told apart"
else
  fails=$((fails + 1))
fi

# --- ci/iris.sh shard: the classes run in name order, and in the reverse order with --reverse ---

# shard_order <arguments of cmd_shard...>: the title and the classes that cmd_shard hands to run_classes, which is a stub.
shard_order() {
  (
    unset OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_WARM
    . ci/iris.sh
    run_classes() { shift; printf '%s\n' "TITLE $1"; shift; printf '%s\n' "$@"; }
    cmd_shard "$@"
  )
}
forward=$(bash ci/iris.sh classes lane-a)
backward=$(printf '%s\n' "$forward" | LC_ALL=C sort -r)
got_forward=$(shard_order lane-a)
got_backward=$(shard_order lane-a --reverse)
if [ "$(printf '%s\n' "$forward" | wc -l | tr -d ' ')" -ge 2 ] && [ "$forward" != "$backward" ] \
  && [ "$got_forward" = "$(printf '%s\n' "TITLE lane-a" "$forward")" ] \
  && [ "$got_backward" = "$(printf '%s\n' "TITLE lane-a (reversed)" "$backward")" ]; then
  echo "PASS shard order: a shard runs its classes in name order, and in the reverse order with --reverse"
else
  echo "FAIL shard order: the classes of 'shard lane-a' or 'shard lane-a --reverse' are not in name order or its reverse"
  fails=$((fails + 1))
fi

# --- ci/iris.sh teardown: it removes what carries its tag, and nothing else ---

# The fixtures: two projects of the tag abc-7; and another tag, a tag that extends this one, a slot, a name outside ocutalon- and the
# preloaded base image, none of which may be touched. `docker` is a stub that answers the listings and records each removal. The lane
# has a lock folder of its own, with a warm-iris.lock that names the project given to teardown_fixture (none when it is empty), and a
# temporary folder of its own with the warm state folders of the tag, of another tag and of the tag abc-7-1.
mine1=ocutalon-shard-lane-a-abc-7-1792446641-23730
mine2=ocutalon-class-abc-7-1792446700-111
others="ocutalon-shard-lane-a-abd-7-1792446641-23730 ocutalon-t07rt-abc-7-1-1792446641-23730 ocutalon-slot-abc-7-1792446641-23730 other-abc-7-1792446641-23730"
teardown_fixture() { # teardown_fixture <project that the warm lock names>: the sorted calls in $tmp/teardown-removed, the output in $tmp/teardown-out
  rm -rf "$tmp/teardown-locks" "$tmp/teardown-tmp"
  mkdir -p "$tmp/teardown-locks" "$tmp/teardown-tmp/ocutalon-warm-abc-7" "$tmp/teardown-tmp/ocutalon-warm-abd-7" "$tmp/teardown-tmp/ocutalon-warm-abc-7-1"
  if [ -n "$1" ]; then printf 'epic=0 stage=qa project=%s acquired_at=2026-10-23T00:00:00Z\n' "$1" > "$tmp/teardown-locks/warm-iris.lock"; fi
  (
    OCUTALON_RUN_TAG=abc-7
    OCUTALON_LOCK_DIR="$tmp/teardown-locks"
    TMPDIR="$tmp/teardown-tmp"
    . ci/iris.sh
    calls="$tmp/teardown-calls"
    : > "$calls"
    : > "$tmp/teardown-compose-args"
    docker() {
      case "$1" in
        ps)
          case "$*" in
            *label=*) printf '%s\n' $mine1 $mine2 $others ;;
            *) for n in $mine1 $mine2 $others; do printf '%s-iris-1\n' "$n"; done; printf '%s\n' ocutalon-slot-a ocupilot ;;
          esac
          ;;
        volume) if [ "$2" = ls ]; then for n in $mine1 $others; do printf '%s_durable\n' "$n"; done; else echo "volume $4" >> "$calls"; fi ;;
        network) if [ "$2" = ls ]; then for n in $mine1 $others; do printf '%s_default\n' "$n"; done; else echo "network $3" >> "$calls"; fi ;;
        image)
          if [ "$2" = ls ]; then
            for n in $mine1 $others; do printf '%s-iris:latest\n' "$n"; done
            printf '%s\n' ocutalon-iris-base:2026.3.0AI.154.0 node:24.15.0-slim
          else echo "image $4" >> "$calls"; fi
          ;;
        compose) echo "compose $3" >> "$calls"; echo "$*" >> "$tmp/teardown-compose-args" ;;
        rm) echo "rm $4" >> "$calls" ;;
      esac
    }
    cmd_teardown > "$tmp/teardown-out"
    sort "$calls"
  ) > "$tmp/teardown-removed"
}
# A warm lock of the tag is released; the lock of another tag, and of a tag that extends this one (abc-7-1), is kept.
teardown_fixture ocutalon-warm-abc-7-1792446641-23730
removed=$(cat "$tmp/teardown-removed")
lock_ok=1
lock_note=""
if [ -e "$tmp/teardown-locks/warm-iris.lock" ] || ! grep -qx 'LOCK released warm-iris project=ocutalon-warm-abc-7-1792446641-23730' "$tmp/teardown-out" \
  || [ "$(tail -n 1 "$tmp/teardown-out" | cut -c 1-16)" != "TEARDOWN tag abc" ]; then
  lock_ok=0
  lock_note="$lock_note [the warm lock of the tag was not released, or TEARDOWN is not the last line]"
fi
if [ -e "$tmp/teardown-tmp/ocutalon-warm-abc-7" ] || [ ! -d "$tmp/teardown-tmp/ocutalon-warm-abd-7" ] || [ ! -d "$tmp/teardown-tmp/ocutalon-warm-abc-7-1" ]; then
  lock_ok=0
  lock_note="$lock_note [the warm state folder of the tag was kept, or the folder of another tag, or of the tag abc-7-1, was removed]"
fi
for other_lock in ocutalon-warm-abd-7-1792446641-23730 ocutalon-warm-abc-7-1-1792446641-23730; do
  teardown_fixture "$other_lock"
  if [ ! -e "$tmp/teardown-locks/warm-iris.lock" ] || grep -q '^LOCK released' "$tmp/teardown-out"; then
    lock_ok=0
    lock_note="$lock_note [the warm lock of $other_lock was released]"
  fi
done
teardown_fixture ""
if grep -q '^LOCK released' "$tmp/teardown-out"; then
  lock_ok=0
  lock_note="$lock_note [a LOCK released line with no warm lock]"
fi
want=$(printf '%s\n' "compose $mine1" "compose $mine2" "image $mine1-iris:latest" "network ${mine1}_default" "rm $mine1-iris-1" "rm $mine2-iris-1" "volume ${mine1}_durable" | sort)
if [ "$removed" = "$want" ] && [ "$lock_ok" -eq 1 ]; then
  echo "PASS teardown: it removes the projects, containers, volumes, networks and images of its tag, and no other tag's, slot's, outside name or the base image or the mock's public image, and releases the lane's warm-iris.lock and removes the warm state folder of its tag only (not another tag's, nor the tag abc-7-1's)"
else
  echo "FAIL teardown: it removed '$(printf '%s' "$removed" | tr '\n' ' ')', wanted '$(printf '%s' "$want" | tr '\n' ' ')'$lock_note"
  fails=$((fails + 1))
fi

# Each project comes down with the CI override among its files and with `down -v --rmi local --remove-orphans`: the volumes and
# the images built for the project go, and a pulled public image such as the mock's stays.
down_ok=1
[ "$(grep -c . "$tmp/teardown-compose-args")" -eq 2 ] || down_ok=0
while IFS= read -r line; do
  case $line in *" -f "*"/ci/compose.ci.yml down -v --rmi local --remove-orphans") ;; *) down_ok=0 ;; esac
done < "$tmp/teardown-compose-args"
if [ "$down_ok" -eq 1 ]; then
  echo "PASS teardown: each project comes down with the CI override, -v and --rmi local, so a pulled image stays"
else
  echo "FAIL teardown: a project did not come down with 'down -v --rmi local --remove-orphans' and the CI override: $(tr '\n' ';' < "$tmp/teardown-compose-args")"
  fails=$((fails + 1))
fi

# --- the workflow files, lane-a and the yaml ---

mkdir -p "$samples/folder"
: > "$samples/folder/a.yml"
: > "$samples/folder/b.yaml"
: > "$samples/folder/c.txt"
if [ "$(workflow_files "$samples/folder" | wc -l | tr -d ' ')" = 2 ]; then
  echo "PASS workflow files: both extensions that GitHub reads, .yml and .yaml, are listed"
else
  echo "FAIL workflow files: the listing misses a .yml or a .yaml file"
  fails=$((fails + 1))
fi

# has_job <file> <job>: the file has a job of that name.
has_job() { [ -f "$1" ] && wf_facts "$1" | awk -F'\t' -v job="$2" '$1 == "job" && $5 == job { f = 1 } END { exit !f }'; }
printf 'name: x\njobs:\n  other:\n    runs-on: ubuntu-24.04\n' > "$samples/other-job.yml"
if has_job "$samples/other-job.yml" standalone-bridge || ! has_job "$samples/other-job.yml" other || has_job "$samples/no-such-file.yml" standalone-bridge; then
  echo "FAIL lane-a: the rule finds the job in a file that has another job, or does not find the job it has"
  fails=$((fails + 1))
elif has_job .github/workflows/lane-a.yml standalone-bridge; then
  echo "PASS lane-a: .github/workflows/lane-a.yml has the job standalone-bridge"
else
  echo "FAIL lane-a: .github/workflows/lane-a.yml is missing or has no job standalone-bridge"
  fails=$((fails + 1))
fi

if command -v ruby >/dev/null 2>&1 && ruby -ryaml -e 'exit 0' >/dev/null 2>&1; then
  printf 'jobs:\n  a: [\n' > "$samples/broken.yml"
  if ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$samples/broken.yml" >/dev/null 2>&1; then
    echo "FAIL yaml: ruby -ryaml parses a broken file"
    fails=$((fails + 1))
  elif [ -n "$wf_files" ] && ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }' $wf_files; then
    echo "PASS yaml: ruby -ryaml parses $(printf '%s\n' $wf_files | wc -l | tr -d ' ') workflow file(s)"
  else
    echo "FAIL yaml: a workflow file does not parse"
    fails=$((fails + 1))
  fi
else
  echo "SKIP yaml: ruby is not installed, so the workflow files were not parsed (this is not a pass)"
  skipped="$skipped yaml"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-ci-config: $fails rule(s) failed"
  exit 1
fi
if [ -n "$skipped" ]; then
  echo "test-ci-config: all rules passed, skipped:$skipped"
else
  echo "test-ci-config: all rules passed"
fi
