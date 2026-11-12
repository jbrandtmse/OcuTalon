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
#   - runners: ubuntu-24.04, macos-15 (the install-macos job: macOS's own bash 3.2) or [self-hosted, ocutalon]; the hosted ones
#     are never skipped, and macos-latest is flagged like ubuntu-latest;
#   - fork-guard: every self-hosted job carries the job-level guard that keeps a fork's pull request off the IRIS runner;
#   - secrets: no secrets reference (a run block, any case, a bracket or the whole context, as in toJSON(secrets), included), and
#     github.token only as GH_TOKEN (the whole github context, which holds the token, counts as a use of it);
#   - image-actions: no docker/* action and no actions/cache anywhere, and no upload-artifact in a self-hosted job except the one that keeps
#     a failed browser unit's Playwright results (Story 11.22): its `if:` starts with failure() and holds no always() or ||, its `path` is
#     web/test-results or below it, and its `retention-days` is 1 to 7;
#   - traces (Story 11.27; AD-22): no upload-artifact step of any job, hosted or self-hosted, in any workflow file has a missing path, a
#     block-scalar path, a path that names the trace folder of ci/iris.sh (TRACE_FOLDER_NAME, read from a sourced ci/iris.sh; FAIL when it
#     cannot be read), a trace file (any "trace"), a home folder (~ or home) or .., or includes hidden files, so that a Playwright trace
#     (which can hold a throwaway stack's passwords; the repository is public) never leaves the CI host;
#   - traces kept (Story 11.27): the real cmd_live of a sourced ci/iris.sh, over a fake checkout and a fake unit script that fails and
#     leaves a trace.zip, another file and a .playwright-artifacts-0 folder: on a self-hosted runner (GITHUB_ACTIONS=true,
#     RUNNER_ENVIRONMENT=self-hosted) with a root outside the workspace and the checkout the unit gets OCUTALON_E2E_TRACE=retain-on-failure,
#     the trace moves to <root>/<tag>/<unit>/... (folders mode 700, the trace 600), nothing of a trace stays below web/test-results, the other
#     files and the unit's exit code stay, and the log names no host path; a trace that cannot be moved and a link named like a trace are
#     deleted, never kept, and a link's target is not touched; on a hosted runner, with no runner, with a root inside the workspace, inside
#     the checkout, through a link into the workspace, through a .. that climbs back into it, or not absolute the unit gets no switch, the trace is deleted and nothing is written
#     to the root; with GITHUB_ACTIONS unset nothing is touched; traces_prune removes the run folders older than 7 days, keeps younger ones
#     and names that are not run tags, and does nothing when traces are off; cmd_group calls traces_prune after setup_tag;
#   - teardown: every job that runs ci/iris.sh has a step with `if: always()` that runs ci/iris.sh teardown after the steps that
#     run it;
#   - matrix: the group list of ci.yml is `ci/iris.sh groups` (a matrix that is missing or not a flow list fails);
#   - wiring: the checks job of ci.yml runs the ShellCheck step of install.sh and its hermetic test (Story 10.1) and ci/checks.sh, the install-macos job
#     on macos-15 runs that test as OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh within timeout-minutes: 10, and the web job runs each
#     script of WEB_SCRIPTS (the web build and the mock's tests, the step "Mock tests" among them), lint and unit tests, each gated by
#     the classifier's web output; the iris job asks the classifier for its own group
#     (ci/changes.sh ci.yml --group <its group>), runs ci/iris.sh build and group unless the run output is `false`, and otherwise
#     runs the step Skipped with the reason; every step reads only step ids that exist, and the iris job sets the run tag, the
#     image and the deadline;
#   - units: every docker/tests/test-*.sh is in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or one group; every Test/<Area>/
#     folder of either source tree is in exactly one shard; every class with a Method Test... sits directly in an area folder;
#     every shard runs in the groups either whole, as exactly one unit shard:<name>, or in pieces shard:<name>@<piece> (DW-337) whose
#     area lists name only areas of the shard, each once, with at most one piece rest, which must keep an area, and without rest
#     cover every area of the shard; the PASS line states the units the groups hold (live scripts and shard units, counted from the
#     tree);
#   - demo-path (Story 0.8): live:demo-path is a unit of exactly one IRIS group and docker/tests/test-demo-path.sh exists, every name
#     of BROWSER_UNITS (the live units that need Playwright's Chromium) is a live unit of a group, and every docker/tests/test-*.sh
#     with a code line, not a comment, that runs the Playwright npm script is in BROWSER_UNITS;
#   - groups: IRIS_GROUPS is exactly install-fresh, install-upgrade, production, browser, shards, shards-2, image, shards-3, shards-4, shards-5, shards-6, shards-7, shards-8, shards-9, shards-10 and shards-11 in this order, each with a
#     unit, and group_units has no case for the retired group install; install-fresh holds live:install-start, install-upgrade holds
#     live:install-upgrade, and live:demo-path is the first unit of browser (AD-22);
#   - inputs (Story 32.2): every unit of NO_WEB_BUNDLE_UNITS is a unit of a group and no live script of it has a code line that names the
#     web bundle (each of the markers alone is enough); group_input_pattern answers for each group with a pattern that matches
#     ci/units.sh, the workflow and src/, and for no unknown group; and every file that a live script of the group sources or adds
#     ($root/<file>, $(dirname "$0")/<file> in a code line) is claimed by the group's pattern, or by no group at all: a path that no
#     group claims, that NOT_IRIS_INPUT_PATTERN does not declare and that is not bookkeeping makes ci/changes.sh run every group (install.sh
#     is one), so reading it is safe, while the read of a path that another group claims, or that is declared a non-input, is not;
#   - recipe: ci/iris.sh (with no OCUTALON_WARM from the caller: Story 32.4's warm mode has its own pins in test-ci-warm.sh) refuses a bad
#     run tag, an unknown shard, class, live unit or group with exit 2, and a missing base image with exit 1; its web port is 52810 plus the runner's number on runners 0 to 9 and 52819 minus it on runners 10 to 19, a set
#     OCUTALON_TEST_WEB_PORT wins (whatever the runner, none included), any other runner name (a number of 20 or more, a letter after
#     the number, none) and no runner leave `auto` (DW-49, Story 32.3), and the ports of runners 1 to 19 are distinct, within
#     52800-52819 and none in LIVE_FORBIDDEN_PORTS; the real live_web_port (port_in_use stubbed, nothing listens) accepts the fixed
#     port of each runner 0 to 19, which setup_tag exports to a child process, refuses it as in use when it is held without taking
#     another, and gives a probing runner 52800, which no runner 1 to 18 owns; `groups` prints the sixteen groups in order, `list` shows the two install groups with their anchors,
#     the retired group install is refused with exit 2, and each group's CI tag (<run id>-<attempt>-<group>) is a valid run tag under
#     which `group <name>` knows the group;
#   - preflight (Story 0.11): the mock's image, read from ci/compose.ci.yml, is pulled up to 3 times when it is missing (a stub docker
#     answers), the FAIL line and exit 1 come before any stack starts when every pull fails, and a present image is never pulled;
#   - mock wrapper (Story 0.11): docker/tests/test-mock.sh runs node --test on every file of ci/mock/test/ and exits with node's
#     status (a stub node answers), so a red mock test turns the web job's step red;
#   - budgets (Story 0.32; DW-1082, DW-1195): unit_live_deadline holds exactly the audited floors, each a live unit of a group, an integer in
#     (1200, 2340], and returns 1 for any other name; the real cmd_live (over a fake checkout) runs a unit with a floor with at least the
#     floor and prints one DEADLINE line when it raised the deadline, and leaves a higher given deadline and any unlisted unit alone; the
#     first-start wait is LIVE_FIRST_START_WAIT (default 510 s) in every live script, whose die names it; the three waits of
#     live:install-upgrade and the two audited waits of live:install-start have their budgets, and the MEASURED lines of the upgrade's
#     waits come before their dies and are unconditional (printed on a pass too); test-sign-in.sh prints the suite budget before the
#     browser run and the suite seconds right after it; the evidence table's new-value column equals the code's values; the four job
#     timeouts of DW-1212, DW-1213 and DW-1214 (ci.yml iris 50 and checks 25 minutes, lane-a.yml ipm-install and ipm-install-p 45), and the REL-4 lines of
#     the two lane-a IPM jobs: `build` takes a start stamp and `teardown` prints `MEASURED <job> N s` and, over 2100 s, `over REL-4` to the log and the
#     step summary (a stub clock; no line for another job, a run with no stamp or a stamp that is not a number);
#   - lane-a: lane-a.yml exists and has the job standalone-bridge; both .yml and .yaml files are workflow files;
#   - checks.sh, class verdict, shard order, teardown: ci/checks.sh runs every script and names the failed ones; ci/iris.sh
#     run_class tells a pass, a skip, a failure, an error, a class not compiled, no result and no test apart, shard runs its
#     classes in name order and reversed with --reverse, the shard units of the groups run every test class of every shard once (a
#     piece keeps only its areas, a bad piece is refused with exit 2) and every area of each shard once, through shard_unit_areas (the
#     PASS line states the areas, units and classes of each shard, counted from the tree), a new area of lane-a (a stub shard_areas names
#     one more) is run by lane-a@rest and by no other piece (Story 0.20, AC6), and teardown removes what carries its tag and nothing else, the lane's
#     warm-iris.lock and the warm state folder included: the warm stack of the tag (an orphan of a killed stage) goes and its lock
#     and folder are released, and the stack, lock or folder of another tag, of a tag that extends this one, and of the tag with a
#     w after it (the warm tag of a stage whose fresh tag this is) are kept (ci/iris.sh is sourced with a stub for dc, docker and
#     run_classes, and a lock folder and a temporary folder of its own);
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
      else if (key == "timeout-minutes") emit("job:timeout", FNR, val)
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
  if (text == "ubuntu-24.04" || text == "macos-15") hosted[job] = 1
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
  if (action ~ /upload-artifact$/) { upl[job SUBSEP st] = ln }
  if (action == "actions/checkout") { checkout[job, st] = ln }
}
kind == "step:with" {
  if (text == "persist-credentials: false") persist[job, st] = 1
  if (text ~ /^path: /) { withpath[job, st] = text; sub(/^path: /, "", withpath[job, st]) }
  if (text ~ /^retention-days: /) { withret[job, st] = text; sub(/^retention-days: /, "", withret[job, st]) }
  if (text ~ /^include-hidden-files: /) { withhidden[job, st] = tolower(text); gsub(/["']/, "", withhidden[job, st]); sub(/^include-hidden-files: */, "", withhidden[job, st]) }
}
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
      for (key in upl) {
        split(key, kk, SUBSEP)
        if (kk[1] != j) continue
        # The one upload a self-hosted job may make: the Playwright results of a failure, kept for at most 7 days.
        s2 = stepif[j, kk[2]]; p2 = withpath[j, kk[2]]; r2 = withret[j, kk[2]]
        good = (index(s2, "failure()") == 1 && index(s2, "always()") == 0 && index(s2, "||") == 0 && index(s2, "cancelled()") == 0)
        good = good && (p2 ~ /^web\/test-results(\/[A-Za-z0-9_.\/-]*)?$/ && index(p2, "..") == 0)
        good = good && (r2 ~ /^[1-7]$/)
        if (!good) bad(upl[key], "image-actions")
      }
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
  # An upload of any job (hosted ones included) must stay off traces, home folders and hidden files.
  if (tracename == "") bad(1, "traces")
  for (key in upl) {
    split(key, kk, SUBSEP)
    p3 = withpath[kk[1], kk[2]]; lp = tolower(p3)
    unsafe = (p3 == "" || p3 ~ /^[|>]/ || tracename == "" || index(lp, tolower(tracename)) > 0 || index(lp, "trace") > 0 || index(lp, "~") > 0 || index(lp, "home") > 0 || index(lp, "..") > 0)
    if (withhidden[kk[1], kk[2]] != "" && withhidden[kk[1], kk[2]] != "false") unsafe = 1
    if (unsafe) bad(upl[key], "traces")
  }
  for (key in checkout) if (!(key in persist)) bad(checkout[key], "persist-credentials")
  if (matrix != "" || groups != "") {
    m = matrix; gsub(/[\[\],]/, " ", m); gsub(/ +/, " ", m); sub(/^ /, "", m); sub(/ $/, "", m)
    if (m != groups) bad(matrixline == "" ? 1 : matrixline, "matrix")
  }
}
EOA

# The folder name that ci/iris.sh keeps traces in (rule traces); empty when a sourced ci/iris.sh does not define it, which fails the rule.
trace_folder=$(unset OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_WARM; . "$root/ci/iris.sh" >/dev/null 2>&1; printf '%s' "${TRACE_FOLDER_NAME:-}")

# wf_check <file> [<expected matrix groups>]: line<TAB>rule of each violation, sorted.
wf_check() {
  wf_facts "$1" > "$tmp/facts.tsv"
  awk -v groups="${2:-}" -v tracename="$trace_folder" -f "$tmp/rules.awk" "$tmp/facts.tsv" | sort -u
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
make_bad runner-macos-latest 'sub(/runs-on: ubuntu-24.04/, "runs-on: macos-latest") { print; next } { print }'
make_bad runner-macos-14 'sub(/runs-on: ubuntu-24.04/, "runs-on: macos-14") { print; next } { print }'
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
# upload_sample <name> <if line or empty> <path> <retention line or empty> [<uses>]: good.yml with a step that uploads an artifact before Tear down.
upload_sample() {
  local uses=${5:-actions/upload-artifact@$sha # v7.0.2}
  awk -v cond="$2" -v path="$3" -v ret="$4" -v uses="$uses" '
    $0 == "      - name: Tear down" {
      print "      - name: Keep the results"
      if (cond != "") print "        if: " cond
      print "        uses: " uses
      print "        with:"
      print "          name: playwright-results"
      print "          path: " path
      if (ret != "") print "          retention-days: " ret
    }
    { print }' "$samples/good.yml" > "$samples/$1.yml"
}
upload_sample upload-good "failure() && steps.changes.outputs.run != 'false'" "web/test-results/" "3"
upload_sample upload-good-bare "failure()" "web/test-results" "7"
upload_sample image-upload-no-if "" "web/test-results/" "3"
upload_sample image-upload-always "always()" "web/test-results/" "3"
upload_sample image-upload-always-or "failure() || always()" "web/test-results/" "3"
upload_sample image-upload-or-success "failure() || success()" "web/test-results/" "3"
upload_sample image-upload-success "success()" "web/test-results/" "3"
upload_sample image-upload-path "failure()" "web/dist/" "3"
upload_sample image-upload-path-up "failure()" "web/test-results/../.." "3"
upload_sample image-upload-path-prefix "failure()" "web/test-results-all" "3"
upload_sample image-upload-no-retention "failure()" "web/test-results/" ""
upload_sample image-upload-retention-30 "failure()" "web/test-results/" "30"
upload_sample image-upload-retention-0 "failure()" "web/test-results/" "0"
# traces: uploads that could carry a trace out of the CI host, in a self-hosted and in a hosted job.
upload_sample traces-home-tilde "failure()" "~/ocutalon-traces/" "3"
upload_sample traces-home-env "failure()" "\${{ env.HOME }}/ocutalon-traces" "3"
upload_sample traces-zip "failure()" "web/test-results/**/trace.zip" "3"
upload_sample traces-folder-name "failure()" "web/ocutalon-traces" "3"
upload_sample traces-block-path "failure()" "|" "3"
upload_sample traces-no-path "failure()" "" "3"
upload_sample traces-up "failure()" "web/test-results/../../x" "3"
# Home paths that name no trace: only the ~ and home checks flag them.
upload_sample traces-home-plain "failure()" "~/results" "3"
upload_sample traces-home-env-plain "failure()" "\${{ env.HOME }}/out" "3"
# A folder that only the trace-folder-name check flags, when the rule is given that name (see the check after rule traces).
upload_sample traces-own-name "failure()" "web/keepme" "3"
awk '{ print } $0 == "          path: web/test-results/" { print "          include-hidden-files: true" }' "$samples/upload-good.yml" > "$samples/traces-hidden.yml"
awk '{ print } $0 == "          path: web/test-results/" { print "          include-hidden-files: false" }' "$samples/upload-good.yml" > "$samples/traces-hidden-false.yml"
# hosted_upload_sample <name> <path>: good.yml with an upload step added at the end of the hosted job.
hosted_upload_sample() {
  printf '%s\n' "      - name: Keep" "        uses: actions/upload-artifact@$sha # v7.0.2" "        with:" "          name: x" "          path: $2" > "$samples/step.txt"
  awk -v stepfile="$samples/step.txt" '{ print } $0 == "          GH_TOKEN: ${{ github.token }}" { while ((getline line < stepfile) > 0) print line; close(stepfile) }' "$samples/good.yml" > "$samples/$1.yml"
}
hosted_upload_sample traces-hosted-home "/$(printf 'ho%s' me)/runner/$trace_folder"
hosted_upload_sample traces-hosted-home-plain "/$(printf 'ho%s' me)/runner/out"
hosted_upload_sample traces-hosted-good web/dist/
make_bad skip-hosted-job '$0 == "  hosted:" { print; print "    if: github.event_name == '"'"'push'"'"'"; next } { print }'
make_bad skip-macos-job '$0 == "    runs-on: ubuntu-24.04" { print "    runs-on: macos-15"; print "    if: github.event_name == '"'"'push'"'"'"; next } { print }'
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
rule runners "ubuntu-24.04, macos-15 or [self-hosted, ocutalon]" runner-latest runner-macos-latest runner-macos-14 runner-label
rule fork-guard "every self-hosted job keeps a fork's pull request off the IRIS runner" fork-guard-missing fork-guard-weak
rule secrets "no secrets reference (a run block, any case, a bracket or the whole context included), and github.token only as GH_TOKEN" secret-ref token-other secret-block secret-bracket token-block secret-context token-context
rule image-actions "no docker/* action, no actions/cache, and no upload-artifact in a self-hosted job but a failure-only one of web/test-results kept 1 to 7 days" \
  image-docker image-cache image-cache-restore image-upload image-docker-upper image-cache-upper image-upload-upper \
  image-upload-no-if image-upload-always image-upload-always-or image-upload-or-success image-upload-success image-upload-path image-upload-path-up image-upload-path-prefix \
  image-upload-no-retention image-upload-retention-30 image-upload-retention-0
for good_upload in upload-good upload-good-bare; do
  hits=$(wf_check "$samples/$good_upload.yml" "install production")
  if [ -z "$hits" ]; then
    echo "PASS image-actions: the sample $good_upload (a failure-only upload of web/test-results kept for days) is clean"
  else
    echo "FAIL image-actions: the sample $good_upload is flagged ($(printf '%s' "$hits" | tr '\t\n' ': '))"
    fails=$((fails + 1))
  fi
done
rule never-skipped "no hosted job (macOS included) has a job-level if, and no job or step ignores a failure with continue-on-error" skip-hosted-job skip-macos-job coe-job coe-step
rule traces "no upload-artifact step of any job names the trace folder, a trace file, a home or .. path, has no path or a block path, or includes hidden files" \
  traces-home-tilde traces-home-env traces-zip traces-folder-name traces-block-path traces-no-path traces-up traces-hidden traces-hosted-home \
  traces-home-plain traces-home-env-plain traces-hosted-home-plain
# The trace folder's own name is flagged when it holds no "trace", and a folder name that cannot be read flags the rule.
wf_facts "$samples/traces-own-name.yml" > "$tmp/facts.tsv"
own_name=$(awk -v groups="install production" -v tracename=keepme -f "$tmp/rules.awk" "$tmp/facts.tsv" | awk -F'\t' '$2 == "traces"')
wf_facts "$samples/good.yml" > "$tmp/facts.tsv"
no_name=$(awk -v groups="install production" -v tracename= -f "$tmp/rules.awk" "$tmp/facts.tsv" | awk -F'\t' '$2 == "traces"')
if [ -n "$own_name" ] && [ -n "$no_name" ]; then
  echo "PASS traces: an upload of the trace folder's own name is flagged, and a folder name that cannot be read fails the rule"
else
  echo "FAIL traces:$([ -n "$own_name" ] || printf ' [the trace folder own name is not flagged]')$([ -n "$no_name" ] || printf ' [an unread folder name does not fail the rule]')"
  fails=$((fails + 1))
fi
for good_upload in upload-good upload-good-bare traces-hidden-false traces-hosted-good; do
  hits=$(wf_check "$samples/$good_upload.yml" "install production" | awk -F'\t' '$2 == "traces"')
  if [ -z "$hits" ]; then
    echo "PASS traces: the sample $good_upload (an upload of web/test-results or web/dist, hidden files not included) is clean"
  else
    echo "FAIL traces: the sample $good_upload is flagged ($(printf '%s' "$hits" | tr '\t\n' ': '))"
    fails=$((fails + 1))
  fi
done
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
kind == "job:runs-on" { runson[job] = text }
kind == "job:timeout" { timeouts[job] = unq(text) }
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
  need("checks", "shellcheck --version && shellcheck install.sh docker/tests/test-install-script.sh", "")
  need("install-macos", "OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh", "")
  if (runson["install-macos"] != "macos-15") bad("install-macos: the job does not run on macos-15")
  if (timeouts["install-macos"] != "10") bad("install-macos: the job has no timeout-minutes of 10")
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
wiring_bad shellcheck 'index($0, "        run: shellcheck --version") == 1 { print "        run: echo lint"; next } { print }'
wiring_bad shellcheck-scope 'index($0, "        run: shellcheck --version") == 1 { sub(/ install\.sh docker/, " docker") } { print }'
wiring_bad macos-bash 'sub(/ \/bin\/bash docker\/tests\/test-install-script\.sh/, " docker/tests/test-install-script.sh") { print; next } { print }'
wiring_bad macos-major 'sub(/OCUTALON_TEST_BASH_MAJOR=3 /, "") { print; next } { print }'
wiring_bad macos-runner 'sub(/runs-on: macos-15/, "runs-on: ubuntu-24.04") { print; next } { print }'
wiring_bad macos-timeout-gone '$0 == "  install-macos:" { inmac = 1 } inmac && index($0, "    timeout-minutes:") == 1 { inmac = 0; next } { print }'
wiring_bad macos-timeout-long '$0 == "  install-macos:" { inmac = 1 } inmac && index($0, "    timeout-minutes:") == 1 { inmac = 0; print "    timeout-minutes: 360"; next } { print }'
wiring_bad macos-job-gone '$0 == "  install-macos:" { skip = 1 } skip && /^  web:$/ { skip = 0 } skip { next } { print }'
wiring_ok=1
for n in id iris-gate group-gate gate-truthy web-gate skip-step skip-reason skip-text skip-split group-arg tag checks lint test group mock \
  shellcheck shellcheck-scope macos-bash macos-major macos-runner macos-timeout-gone macos-timeout-long macos-job-gone; do
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
  echo "PASS wiring: the checks job of ci.yml runs ShellCheck on install.sh and its hermetic test and the checks, the install-macos job runs that test on macos-15 under /bin/bash with OCUTALON_TEST_BASH_MAJOR=3 and a timeout of 10 minutes, and the web job runs each script of WEB_SCRIPTS, the lint and the unit tests, gated by the classifier's web output, and the iris job asks the classifier for its group and runs the build and the group unless run is false"
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
          shard:*)
            sn=${u#shard:}
            sn=${sn%%@*}
            printf '%s\n' $SHARDS | grep -qx -- "$sn" || echo "ci/units.sh: group $g names the unknown shard $sn"
            ;;
        esac
      done
    done
    # A shard runs whole in exactly one unit, or in pieces (shard:<name>@<piece>) that run each of its areas exactly once.
    sunits=$(for g in $IRIS_GROUPS; do group_units "$g"; done | tr ' ' '\n' | grep '^shard:')
    for s in $SHARDS; do
      whole=$(printf '%s\n' "$sunits" | grep -c -x -- "shard:$s")
      if ! printf '%s\n' "$sunits" | grep -q -- "^shard:$s@"; then
        if [ "$whole" -ne 1 ]; then echo "ci/units.sh: the shard $s is in $whole groups, wanted 1"; fi
        continue
      fi
      pieces=$(printf '%s\n' "$sunits" | grep -- "^shard:$s@" | sed "s/^shard:$s@//")
      if [ "$whole" -ne 0 ]; then echo "ci/units.sh: the shard $s runs whole and in pieces"; fi
      if printf '%s\n' "$pieces" | grep -qx ''; then echo "ci/units.sh: a piece of the shard $s names no area"; fi
      rests=$(printf '%s\n' "$pieces" | grep -c -x rest)
      if [ "$rests" -gt 1 ]; then echo "ci/units.sh: the shard $s has $rests pieces rest, wanted at most 1"; fi
      named=$(printf '%s\n' "$pieces" | grep -v -x rest | tr ',' '\n' | grep .)
      for a in $named; do
        case " $(shard_areas "$s") " in
          *" $a "*) ;;
          *) echo "ci/units.sh: a piece of the shard $s names $a, which is not one of its areas" ;;
        esac
      done
      for a in $(printf '%s\n' "$named" | grep . | LC_ALL=C sort | uniq -d); do
        echo "ci/units.sh: the area $a is in more than one piece of the shard $s"
      done
      left=0
      for a in $(shard_areas "$s"); do
        printf '%s\n' "$named" | grep -qx -- "$a" || left=$((left + 1))
      done
      if [ "$rests" -eq 0 ] && [ "$left" -gt 0 ]; then
        echo "ci/units.sh: $left area(s) of the shard $s are in no piece, and no piece is rest"
      fi
      if [ "$rests" -gt 0 ] && [ "$left" -eq 0 ]; then echo "ci/units.sh: the piece rest of the shard $s keeps no area"; fi
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
mkpieces() { # mkpieces <dir> <more units of g1> <more units of g2>: the good tree with a shard s1 of the areas Alpha and Gamma, which runs only in the units given
  mkunits "$1"
  mkdir -p "$1/src/ocutalon/cls/OcuTalon/Test/Gamma"
  printf 'Class OcuTalon.Test.Gamma.Three\n{\nMethod TestThree()\n{\n}\n}\n' > "$1/src/ocutalon/cls/OcuTalon/Test/Gamma/Three.cls"
  cat > "$1/ci/units.sh" <<EOU
CHECK_SCRIPTS="a b"
WEB_SCRIPTS="w"
SHARDS="s1 s2"
shard_areas() { case \$1 in s1) echo "Alpha Gamma" ;; s2) echo "Beta" ;; esac; }
IRIS_GROUPS="g1 g2"
group_units() { case \$1 in g1) echo "live:x $2" ;; g2) echo "live:y shard:s2 $3" ;; esac; }
EOU
}
mkpieces "$tmp/u-pieces" "shard:s1@Alpha" "shard:s1@rest"
mkpieces "$tmp/u-pieces-listed" "shard:s1@Gamma" "shard:s1@Alpha"
mkpieces "$tmp/u-piece-gap" "shard:s1@Alpha" ""
mkpieces "$tmp/u-piece-twice" "shard:s1@Alpha" "shard:s1@Alpha,Gamma"
mkpieces "$tmp/u-piece-foreign" "shard:s1@Alpha,Beta" "shard:s1@rest"
mkpieces "$tmp/u-piece-whole" "shard:s1" "shard:s1@Alpha"
mkpieces "$tmp/u-piece-two-rest" "shard:s1@rest" "shard:s1@rest"
mkpieces "$tmp/u-piece-empty-rest" "shard:s1@Alpha,Gamma" "shard:s1@rest"
mkpieces "$tmp/u-piece-blank" "shard:s1@" "shard:s1@rest"
mkpieces "$tmp/u-piece-unknown" "shard:s9@Alpha" "shard:s1"

ok=1
for good in u-good u-pieces u-pieces-listed; do
  if [ -n "$(units_violations "$tmp/$good")" ]; then
    echo "FAIL units: the rule flags the good tree $good ($(units_violations "$tmp/$good" | head -n 3 | tr '\n' ';'))"
    ok=0
  fi
done
# Each piece sample must draw its own violation, so that no other violation of the same sample can stand in for it.
for pair in "u-piece-gap|1 area(s) of the shard s1 are in no piece, and no piece is rest" \
  "u-piece-twice|the area Alpha is in more than one piece of the shard s1" \
  "u-piece-foreign|a piece of the shard s1 names Beta, which is not one of its areas" \
  "u-piece-whole|the shard s1 runs whole and in pieces" "u-piece-two-rest|the shard s1 has 2 pieces rest, wanted at most 1" \
  "u-piece-empty-rest|the piece rest of the shard s1 keeps no area" "u-piece-blank|a piece of the shard s1 names no area" \
  "u-piece-unknown|group g1 names the unknown shard s9"; do
  sample=${pair%%|*}
  want=${pair#*|}
  got=$(units_violations "$tmp/$sample")
  case $got in
    *"$want"*) ;;
    *)
      echo "FAIL units: the sample $sample does not draw '$want' (got: $(printf '%s' "$got" | head -n 3 | tr '\n' ';'))"
      ok=0
      ;;
  esac
done
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
# The units the groups hold, counted from the tree: a unit dropped from a group, or one added, changes the tally.
unit_list=$(cd "$root" && . ./ci/units.sh && for g in $IRIS_GROUPS; do group_units "$g"; done | tr ' ' '\n' | grep .)
unit_total=$(printf '%s\n' "$unit_list" | grep -c .)
unit_live=$(printf '%s\n' "$unit_list" | grep -c '^live:')
unit_shard=$(printf '%s\n' "$unit_list" | grep -c '^shard:')
if [ "$ok" -eq 1 ]; then
  echo "PASS units: every test script is in exactly one place, every Test area is in exactly one shard, every shard runs whole once or in pieces that run each of its areas once, and every test class sits in an area; the groups hold $unit_total units, $unit_live of them live scripts and $unit_shard shard units"
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

# --- groups: the sixteen IRIS groups, the two install anchors and the demo-path first rule ---

# groups_violations <repository directory>: one line per violation of the groups rule in that tree. The names and their order are
# pinned; where a unit sits in a group other than the two anchors is not, so a rebalance of whole units needs no edit here.
groups_violations() {
  (
    cd "$1" || exit 1
    . ./ci/units.sh
    set -- $IRIS_GROUPS
    if [ "$*" != "install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11" ]; then
      echo "ci/units.sh: IRIS_GROUPS is '$IRIS_GROUPS', wanted install-fresh, install-upgrade, production, browser, shards, shards-2, image, shards-3, shards-4, shards-5, shards-6, shards-7, shards-8, shards-9, shards-10 and shards-11, in this order"
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
IRIS_GROUPS="${2:-install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11}"
group_units() {
  case \$1 in
    install-fresh) echo "${3-live:install-start}" ;;
    install-upgrade) echo "${4-live:install-upgrade live:audit}" ;;
    production) echo "${5-live:production live:production-restart}" ;;
    browser) echo "${6-live:demo-path live:sign-in}" ;;
    shards) echo "shard:lane-a@Alpha live:floor" ;;
    shards-2) echo "shard:lane-a@rest" ;;
    image) echo "live:storage-roundtrip shard:lane-b" ;;
    shards-3) echo "live:demo-switch" ;;
    shards-4) echo "shard:lane-a@Channel" ;;
    shards-5) echo "shard:lane-a@Bridge,Agent" ;;
    shards-6) echo "live:documents" ;;
    shards-7) echo "shard:lane-a@Docs" ;;
    shards-8) echo "shard:lane-a@Watch" ;;
    shards-9) echo "shard:lane-b@rest" ;;
    shards-10) echo "live:sign-in-3" ;;
    shards-11) echo "shard:lane-a@Fix" ;;
    ${7-}
    *) return 1 ;;
  esac
}
EOU
}
mkgroups "$tmp/g-good"
mkgroups "$tmp/g-old" "install production browser shards image"
mkgroups "$tmp/g-dup" "install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11 shards-4 image"
mkgroups "$tmp/g-order" "install-upgrade install-fresh production browser shards shards-2 image"
mkgroups "$tmp/g-seven" "install-fresh install-upgrade production browser shards shards-2 image"
mkgroups "$tmp/g-eight" "install-fresh install-upgrade production browser shards shards-2 image shards-3"
mkgroups "$tmp/g-nine" "install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4"
mkgroups "$tmp/g-ten" "install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5"
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
  "g-order|IRIS_GROUPS is 'install-upgrade install-fresh production browser shards shards-2 image', wanted" \
  "g-seven|IRIS_GROUPS is 'install-fresh install-upgrade production browser shards shards-2 image', wanted" \
  "g-eight|IRIS_GROUPS is 'install-fresh install-upgrade production browser shards shards-2 image shards-3', wanted" \
  "g-nine|IRIS_GROUPS is 'install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4', wanted" \
  "g-ten|IRIS_GROUPS is 'install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5', wanted" \
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
  echo "PASS groups: IRIS_GROUPS is install-fresh, install-upgrade, production, browser, shards, shards-2, image, shards-3, shards-4, shards-5, shards-6, shards-7, shards-8, shards-9, shards-10 and shards-11 in this order, group_units has no case for install, every group has a unit, the two install groups hold their anchors, and live:demo-path is the first unit of browser"
else
  echo "FAIL groups: the sixteen IRIS groups"
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
        # A file that a live script of the group sources or adds is an input of the group: its pattern must claim it. A read that no
        # group claims, that NOT_IRIS_INPUT_PATTERN does not declare and that is not bookkeeping is also safe: ci/changes.sh runs every
        # group for a changed path of that kind. A read that another group claims, or that is declared a non-input, is not.
        for u in $(group_units "$g"); do
          case $u in
            live:*)
              f="docker/tests/test-${u#live:}.sh"
              [ -f "$f" ] || continue
              for rel in $(unit_reads "$f"); do
                printf '%s\n' "$rel" | grep -Eq -- "$p" && continue
                known=0
                for g2 in $IRIS_GROUPS; do
                  p2=$(group_input_pattern "$g2" 2>/dev/null) || continue
                  if printf '%s\n' "$rel" | grep -Eq -- "$p2"; then known=1; fi
                done
                if printf '%s\n' "$rel" | grep -Eq -- "$NOT_IRIS_INPUT_PATTERN"; then known=1; fi
                if printf '%s\n' "$rel" | grep -Eq -- "$BOOKKEEPING_PATTERN" && ! printf '%s\n' "$rel" | grep -Eq -- "$NOT_BOOKKEEPING_PATTERN"; then known=1; fi
                if [ "$known" -eq 1 ]; then echo "$f: it reads $rel, which the input pattern of group $g does not claim"; fi
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
# A live script reads the files its group claims (a comment may name any): clean. So is a read that no group claims and that is neither
# declared a non-input nor bookkeeping (install.sh, .env, a new helper or compose file: ci/changes.sh runs every group for it).
mkinputs "$tmp/i-reads-claimed"
script_line "$tmp/i-reads-claimed" install-start 'live_add_file "$root/docker-compose.dev.yml"'
script_line "$tmp/i-reads-claimed" install-start '. "$(dirname "$0")/lib-scan.sh"'
script_line "$tmp/i-reads-claimed" compose-start 'live_add_file "${root}/docker/tests/compose.no-after-start.yml"'
mkinputs "$tmp/i-reads-comment"
script_line "$tmp/i-reads-comment" production '# live_add_file "$root/docker/tests/extra/compose.x.yml"'
script_line "$tmp/i-reads-comment" demo-path '  # . "$(dirname "$0")/helper.sh"'
script_line "$tmp/i-reads-comment" sign-in 'cd "$root/web"'
mkinputs "$tmp/i-reads-unclassified"
script_line "$tmp/i-reads-unclassified" production 'live_add_file "$root/docker/tests/extra/compose.x.yml"'
script_line "$tmp/i-reads-unclassified" demo-path '. "$(dirname "$0")/helper.sh"'
script_line "$tmp/i-reads-unclassified" install-script-live 'bash "$root/install.sh"'
script_line "$tmp/i-reads-unclassified" install-script-live '[ -e "$root/.env" ]'
# A read of a path that a group other than the script's claims, or that is declared a non-input or bookkeeping, still fails.
mkinputs "$tmp/i-reads-other-group"
script_line "$tmp/i-reads-other-group" production 'cat "$root/web/src/app/app.ts"'
mkinputs "$tmp/i-reads-declared-test"
script_line "$tmp/i-reads-declared-test" demo-path '. "$(dirname "$0")/test-x.sh"'
mkinputs "$tmp/i-reads-declared-md"
script_line "$tmp/i-reads-declared-md" production 'cat "$root/README.md"'
mkinputs "$tmp/i-reads-declared-example"
script_line "$tmp/i-reads-declared-example" install-script-live 'cp "$root/.env.example" "$tmp/x"'
mkinputs "$tmp/i-reads-bookkeeping"
script_line "$tmp/i-reads-bookkeeping" production 'cat "$root/_bmad-output/x.md"'
mkdir -p "$tmp/i-unread/ci" && : > "$tmp/i-unread/ci/units.sh"

ok=1
# The comment-only tree lists two units whose scripts name the bundle only in a comment: it stays clean.
for good in i-good i-comment-only i-reads-claimed i-reads-comment i-reads-unclassified; do
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
  "i-reads-other-group|docker/tests/test-production.sh: it reads web/src/app/app.ts, which the input pattern of group production does not claim" \
  "i-reads-declared-test|docker/tests/test-demo-path.sh: it reads docker/tests/test-x.sh, which the input pattern of group browser does not claim" \
  "i-reads-declared-md|docker/tests/test-production.sh: it reads README.md, which the input pattern of group production does not claim" \
  "i-reads-declared-example|docker/tests/test-install-script-live.sh: it reads .env.example, which the input pattern of group shards-2 does not claim" \
  "i-reads-bookkeeping|docker/tests/test-production.sh: it reads _bmad-output/x.md, which the input pattern of group production does not claim"; do
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
  echo "PASS inputs: every unit that is not checked against the web bundle is a unit of a group and names no bundle input in a code line, and each group has an input pattern that claims ci/units.sh, the workflow, src/ and every file that its live scripts source or add, unless no group claims the file and it is neither declared a non-input nor bookkeeping"
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
    LIVE_PORT_WAIT=0 # the held ports below stay held, so live_web_port must not wait for them
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
# The sixteen groups through the command line (Story 32.1; shards-2 since DW-337, shards-3 since Epic 30's CI step, shards-4 since Epic 12's close, shards-5 since Story 19.8's CI split, shards-6 to shards-11 since Story 0.20). `groups` prints the names in order. `list` shows the install groups with their
# anchor units, and no more than that is pinned (a rebalance of whole units needs no edit). The retired name install is refused with
# exit 2 and the new list; it runs with a base image that does not exist, so that a stale `install` case of group_units would end at
# the preflight (exit 1, red) and never start a stack. For every group, the tag of its CI job (<run id>-<attempt>-<group>, as in
# ci.yml) is a valid run tag, and `group <name>` knows the name: with that tag and the missing base image it ends at the preflight
# with exit 1, where an unknown group or a refused tag would give exit 2.
cli_groups=$(bash ci/iris.sh groups 2>&1 | tr '\n' ' ')
if [ "$cli_groups" != "install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11 " ]; then
  recipe_fail="$recipe_fail [ci/iris.sh groups printed '$cli_groups']"
fi
cli_list=$(bash ci/iris.sh list 2>&1)
printf '%s\n' "$cli_list" | grep -Eq -- '^group install-fresh: (.* )?live:install-start( |$)' \
  || recipe_fail="$recipe_fail [ci/iris.sh list has no group install-fresh line with live:install-start]"
printf '%s\n' "$cli_list" | grep -Eq -- '^group install-upgrade: (.* )?live:install-upgrade( |$)' \
  || recipe_fail="$recipe_fail [ci/iris.sh list has no group install-upgrade line with live:install-upgrade]"
recipe 2 "^unknown group 'install'; groups: install-fresh install-upgrade production browser shards shards-2 image shards-3 shards-4 shards-5 shards-6 shards-7 shards-8 shards-9 shards-10 shards-11$" \
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
  echo "PASS recipe: bad tags, units and a missing base image are refused, the web port follows the runner's number (the ports of runners 1 to 19 are distinct and exported, and live_web_port takes each one), and the sixteen groups answer groups, list and group (the retired install is refused) under their CI tags"
else
  printf '%s\n' "$recipe_fail" | tr ']' '\n' | sed 's/^ *\[/  /' | grep . | head -n 10
  echo "FAIL recipe: ci/iris.sh does not refuse, does not choose the port, or does not answer for the sixteen groups, as designed"
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

# --- ci/iris.sh shard with a piece: the shard units of the groups run every test class of every shard exactly once (DW-337) ---

# shard_piece_run <arguments of cmd_shard...>: the label, the title and the classes that cmd_shard hands to run_classes, which is a stub.
shard_piece_run() {
  (
    unset OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_WARM
    . ci/iris.sh
    run_classes() { printf '%s\n' "LABEL $1" "TITLE $2"; shift 2; printf '%s\n' "$@"; }
    cmd_shard "$@"
  )
}
piece_fail=""
piece_all=$(bash ci/iris.sh classes)
piece_ran=""
piece_count=0
for piece_unit in $(. ./ci/units.sh && for g in $IRIS_GROUPS; do group_units "$g"; done | tr ' ' '\n' | grep '^shard:'); do
  piece_name=${piece_unit#shard:}
  case $piece_name in *@*) piece_count=$((piece_count + 1)) ;; esac
  if ! piece_out=$(shard_piece_run "$piece_name" 2>&1); then
    piece_fail="$piece_fail [$piece_unit: cmd_shard refused it]"
    continue
  fi
  piece_list=$(printf '%s\n' "$piece_out" | sed 1,2d)
  if [ "$(printf '%s\n' "$piece_out" | sed -n 1p)" != "LABEL shard-${piece_name%%@*}" ]; then piece_fail="$piece_fail [$piece_unit: label]"; fi
  if [ "$(printf '%s\n' "$piece_out" | sed -n 2p)" != "TITLE $piece_name" ]; then piece_fail="$piece_fail [$piece_unit: title]"; fi
  if [ -z "$piece_list" ]; then piece_fail="$piece_fail [$piece_unit: no class]"; fi
  if [ "$piece_list" != "$(printf '%s\n' "$piece_list" | LC_ALL=C sort)" ]; then piece_fail="$piece_fail [$piece_unit: not in name order]"; fi
  if [ "$piece_list" != "$(bash ci/iris.sh classes "$piece_name")" ]; then piece_fail="$piece_fail [$piece_unit: classes and shard disagree]"; fi
  piece_ran=$(printf '%s\n%s' "$piece_ran" "$piece_list")
done
piece_ran=$(printf '%s\n' "$piece_ran" | grep . | LC_ALL=C sort)
piece_twice=$(printf '%s\n' "$piece_ran" | uniq -d | head -n 3 | tr '\n' ' ')
if [ -n "$piece_twice" ]; then piece_fail="$piece_fail [classes that run twice: $piece_twice]"; fi
if [ "$(printf '%s\n' "$piece_ran" | uniq)" != "$piece_all" ]; then
  piece_fail="$piece_fail [the shard units do not run exactly the classes of every shard]"
fi
if [ "$piece_count" -lt 1 ]; then piece_fail="$piece_fail [no group runs a shard in pieces]"; fi
# Every area of each shard is run once, through shard_unit_areas: the areas of the shard units of a shard in the groups, sorted, are the
# areas of the shard (a piece left out, or an area in two pieces, changes the list).
piece_shard_rows() { # the shard, its units in the groups, the sorted areas those units run and the sorted areas of the shard, one line per shard
  . ./ci/units.sh
  local s g u n got
  for s in $SHARDS; do
    n=0
    got=""
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        case $u in
          "shard:$s" | "shard:$s@"*)
            n=$((n + 1))
            got="$got $(shard_unit_areas "${u#shard:}")"
            ;;
        esac
      done
    done
    printf '%s|%s|%s|%s\n' "$s" "$n" "$(printf '%s\n' $got | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" \
      "$(shard_areas "$s" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  done
}
piece_rows=$(piece_shard_rows)
piece_tally=""
while IFS='|' read -r piece_shard piece_units piece_got piece_want; do
  [ -n "$piece_shard" ] || continue
  if [ "$piece_got" != "$piece_want" ]; then
    piece_fail="$piece_fail [the shard units of $piece_shard run the areas '$piece_got', wanted each of '$piece_want' once]"
  fi
  piece_tally="$piece_tally${piece_tally:+; }$piece_shard: $(printf '%s\n' $piece_want | grep -c .) areas in $piece_units units, $(bash ci/iris.sh classes "$piece_shard" | grep -c .) classes"
done <<EOROWS
$piece_rows
EOROWS
if [ -z "$piece_tally" ]; then piece_fail="$piece_fail [no shard unit was read from ci/units.sh]"; fi
# A new area of lane-a (Epic 35's Mcp is the first) lands in the piece rest and in no other piece: with a stub shard_areas that names
# one more area, shard:lane-a@rest answers its areas now plus the new one, and every other lane-a piece answers what it answered before.
piece_absorb() { # the answers of every lane-a shard unit of the groups, one line each: first with the real shard_areas, then with one more area
  . ./ci/units.sh
  local g u real_areas
  real_areas=$(shard_areas lane-a)
  for pass in real extra; do
    if [ "$pass" = extra ]; then
      shard_areas() { case $1 in lane-a) echo "$real_areas Zz0NewArea" ;; *) return 1 ;; esac; }
    fi
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        case $u in "shard:lane-a@"*) printf '%s|%s|%s\n' "$pass" "$u" "$(shard_unit_areas "${u#shard:}")" ;; esac
      done
    done
  done
}
piece_absorbed=$(piece_absorb)
piece_rest_real=$(printf '%s\n' "$piece_absorbed" | sed -n 's/^real|shard:lane-a@rest|//p')
piece_rest_extra=$(printf '%s\n' "$piece_absorbed" | sed -n 's/^extra|shard:lane-a@rest|//p')
if [ -z "$piece_rest_real" ]; then
  piece_fail="$piece_fail [no group holds shard:lane-a@rest (or it answers no area), so a new area of lane-a runs in no piece]"
elif [ "$piece_rest_extra" != "$piece_rest_real Zz0NewArea" ]; then
  piece_fail="$piece_fail [shard:lane-a@rest answers '$piece_rest_extra' with a new area, wanted '$piece_rest_real Zz0NewArea']"
fi
piece_others_real=$(printf '%s\n' "$piece_absorbed" | grep -v '|shard:lane-a@rest|' | sed -n 's/^real|//p')
piece_others_extra=$(printf '%s\n' "$piece_absorbed" | grep -v '|shard:lane-a@rest|' | sed -n 's/^extra|//p')
if [ -z "$piece_others_real" ] || [ "$piece_others_real" != "$piece_others_extra" ]; then
  piece_fail="$piece_fail [a new area of lane-a changes a piece other than rest]"
fi
for piece_bad in 'lane-a@Nope' 'lane-a@' 'lane-a@Checks,Checks' 'lane-a@Contract' 'nope@rest'; do
  piece_status=0
  piece_msg=$(shard_piece_run "$piece_bad" 2>&1) || piece_status=$?
  case "$piece_status:$piece_msg" in
    "2:unknown shard"*) ;;
    *) piece_fail="$piece_fail [$piece_bad: exit $piece_status, wanted 2 with unknown shard]" ;;
  esac
done
if [ -z "$piece_fail" ]; then
  echo "PASS shard pieces: the $(printf '%s\n' "$piece_ran" | grep -c .) test classes of the shards run once each across the shard units of the groups ($piece_count of them pieces; $piece_tally), and a bad piece is refused with exit 2"
else
  printf '%s\n' "$piece_fail" | tr ']' '\n' | sed 's/^ *\[/  /' | grep . | head -n 10
  echo "FAIL shard pieces: the shard units of the groups do not run every test class exactly once"
  fails=$((fails + 1))
fi

# --- ci/iris.sh teardown: it removes what carries its tag, and nothing else ---

# The fixtures: two projects of the tag abc-7, and the warm stack of that tag (what a killed stage leaves behind); and another tag, a tag
# that extends this one, the same tag with a w after it (the warm tag of a stage whose fresh tag is abc-7, so that the teardown of the
# fresh tag never reaches the warm stack), another tag's warm stack, a slot, a name outside ocutalon- and the preloaded base image,
# none of which may be touched. `docker` is a stub that answers the listings and records each removal. The lane
# has a lock folder of its own, with a warm-iris.lock that names the project given to teardown_fixture (none when it is empty), and a
# temporary folder of its own with the warm state folders of the tag, of another tag and of the tag abc-7-1.
mine1=ocutalon-shard-lane-a-abc-7-1792446641-23730
mine2=ocutalon-class-abc-7-1792446700-111
mine3=ocutalon-warm-abc-7-1792446641-23730
others="ocutalon-shard-lane-a-abd-7-1792446641-23730 ocutalon-t07rt-abc-7-1-1792446641-23730 ocutalon-slot-abc-7-1792446641-23730 other-abc-7-1792446641-23730"
others="$others ocutalon-warm-abc-7w-1792446641-23730 ocutalon-warm-abd-7-1792446641-23730"
teardown_fixture() { # teardown_fixture <project that the warm lock names>: the sorted calls in $tmp/teardown-removed, the output in $tmp/teardown-out
  rm -rf "$tmp/teardown-locks" "$tmp/teardown-tmp"
  mkdir -p "$tmp/teardown-locks" "$tmp/teardown-tmp/ocutalon-warm-abc-7" "$tmp/teardown-tmp/ocutalon-warm-abd-7" "$tmp/teardown-tmp/ocutalon-warm-abc-7-1" \
    "$tmp/teardown-tmp/ocutalon-warm-abc-7w"
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
            *label=*) printf '%s\n' $mine1 $mine2 $mine3 $others ;;
            *) for n in $mine1 $mine2 $mine3 $others; do printf '%s-iris-1\n' "$n"; done; printf '%s\n' ocutalon-slot-a ocupilot ;;
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
# The warm stack of the tag goes with the rest (an orphan), and its lock is released; the stack and the lock of another tag, of a tag that
# extends this one (abc-7-1) and of the tag with a w after it (abc-7w) are kept.
teardown_fixture $mine3
removed=$(cat "$tmp/teardown-removed")
lock_ok=1
lock_note=""
if [ -e "$tmp/teardown-locks/warm-iris.lock" ] || ! grep -qx 'LOCK released warm-iris project=ocutalon-warm-abc-7-1792446641-23730' "$tmp/teardown-out" \
  || [ "$(tail -n 1 "$tmp/teardown-out" | cut -c 1-16)" != "TEARDOWN tag abc" ]; then
  lock_ok=0
  lock_note="$lock_note [the warm lock of the tag was not released, or TEARDOWN is not the last line]"
fi
if [ -e "$tmp/teardown-tmp/ocutalon-warm-abc-7" ] || [ ! -d "$tmp/teardown-tmp/ocutalon-warm-abd-7" ] || [ ! -d "$tmp/teardown-tmp/ocutalon-warm-abc-7-1" ] \
  || [ ! -d "$tmp/teardown-tmp/ocutalon-warm-abc-7w" ]; then
  lock_ok=0
  lock_note="$lock_note [the warm state folder of the tag was kept, or the folder of another tag, of the tag abc-7-1 or of the tag abc-7w was removed]"
fi
for other_lock in ocutalon-warm-abd-7-1792446641-23730 ocutalon-warm-abc-7-1-1792446641-23730 ocutalon-warm-abc-7w-1792446641-23730; do
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
want=$(printf '%s\n' "compose $mine1" "compose $mine2" "compose $mine3" "image $mine1-iris:latest" "network ${mine1}_default" "rm $mine1-iris-1" "rm $mine2-iris-1" "rm $mine3-iris-1" "volume ${mine1}_durable" | sort)
if [ "$removed" = "$want" ] && [ "$lock_ok" -eq 1 ]; then
  echo "PASS teardown: it removes the projects, containers, volumes, networks and images of its tag, and no other tag's, slot's, outside name or the base image or the mock's public image, and also the warm stack of its tag (an orphan), releases the lane's warm-iris.lock and removes the warm state folder of its tag only (not another tag's, nor the tag abc-7-1's, nor the tag abc-7w's)"
else
  echo "FAIL teardown: it removed '$(printf '%s' "$removed" | tr '\n' ' ')', wanted '$(printf '%s' "$want" | tr '\n' ' ')'$lock_note"
  fails=$((fails + 1))
fi

# Each project comes down with the CI override among its files and with `down -v --rmi local --remove-orphans`: the volumes and
# the images built for the project go, and a pulled public image such as the mock's stays.
down_ok=1
[ "$(grep -c . "$tmp/teardown-compose-args")" -eq 3 ] || down_ok=0
while IFS= read -r line; do
  case $line in *" -f "*"/ci/compose.ci.yml down -v --rmi local --remove-orphans") ;; *) down_ok=0 ;; esac
done < "$tmp/teardown-compose-args"
if [ "$down_ok" -eq 1 ]; then
  echo "PASS teardown: each project comes down with the CI override, -v and --rmi local, so a pulled image stays"
else
  echo "FAIL teardown: a project did not come down with 'down -v --rmi local --remove-orphans' and the CI override: $(tr '\n' ';' < "$tmp/teardown-compose-args")"
  fails=$((fails + 1))
fi

# --- ci/iris.sh traces kept: a failing unit's trace moves off the workspace on a self-hosted runner, and is deleted anywhere else (Story 11.27) ---

# tk_mode <folder>: the octal mode of the folder (GNU stat, else BSD stat).
tk_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# tk_traces <folder>: the first trace file or Playwright artifacts folder below the folder, or nothing.
tk_traces() { find "$1" \( -name 'trace*.zip' -o -name '.playwright-artifacts-*' \) 2>/dev/null | head -n 1; }
# tk_live <row> <variable=value...>: the real cmd_live of a sourced ci/iris.sh over a fake checkout of the row ($tk_dir/checkout), whose fake unit
# script (docker/tests/test-$TK_UNIT.sh, fake by default) records OCUTALON_E2E_TRACE, leaves t1/trace.zip, t2/state-diagnosis.txt and an artifacts folder
# below OCUTALON_E2E_OUTPUT, runs the row's TK_UNIT_EXTRA, and exits 1. Every variable the code reads is set by the row or unset. Sets tk_dir, tk_rc and tk_out.
tk_live() {
  local row=$1 assignment unit=fake
  shift
  for assignment in "$@"; do
    case $assignment in TK_UNIT=*) unit=${assignment#TK_UNIT=} ;; esac
  done
  tk_dir="$tmp/tk-$row"
  rm -rf "$tk_dir"
  mkdir -p "$tk_dir/checkout/docker/tests" "$tk_dir/checkout/web" "$tk_dir/work" "$tk_dir/home"
  cat > "$tk_dir/checkout/docker/tests/test-$unit.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "${OCUTALON_E2E_TRACE-unset}" > "$FAKE_RECORD"
out="web/$OCUTALON_E2E_OUTPUT"
mkdir -p "$out/t1" "$out/t2" "$out/.playwright-artifacts-0/traces"
: > "$out/t1/trace.zip"
echo kept > "$out/t2/state-diagnosis.txt"
: > "$out/.playwright-artifacts-0/traces/x.trace"
[ -z "${TK_UNIT_EXTRA:-}" ] || eval "$TK_UNIT_EXTRA"
exit 1
EOS
  (
    unset GITHUB_ACTIONS RUNNER_ENVIRONMENT GITHUB_WORKSPACE OCUTALON_TRACE_DIR OCUTALON_RUN_TAG OCUTALON_E2E_TRACE OCUTALON_WARM RUNNER_NAME OCUTALON_TEST_WEB_PORT OCUTALON_LIVE_DEADLINE
    export HOME="$tk_dir/home" FAKE_RECORD="$tk_dir/record"
    for assignment in "$@"; do export "$assignment"; done
    [ -z "${TK_SETUP:-}" ] || eval "$TK_SETUP"
    . "$root/ci/iris.sh"
    root="$tk_dir/checkout"
    cd "$root" || exit 99
    WARM_MODE=cold
    live_known() { return 0; }
    warm_check() { :; }
    setup_tag() { :; }
    preflight() { :; }
    npx() { :; }
    cmd_live "$unit"
  ) > "$tk_dir/out" 2>&1
  tk_rc=$?
  tk_out=$(cat "$tk_dir/out")
}
tk_fail=""
tk_bad() { tk_fail="$tk_fail [$1]"; }
tk_results() { printf '%s' "$tk_dir/checkout/web/test-results"; }

# On: a self-hosted runner, a root outside the workspace and the checkout.
tk_live on GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-on/work" OCUTALON_TRACE_DIR="$tmp/tk-on/traces" OCUTALON_RUN_TAG=tk-run1
[ "$tk_rc" -eq 1 ] || tk_bad "on: the unit's exit status 1 became $tk_rc"
[ "$(cat "$tk_dir/record" 2>/dev/null)" = retain-on-failure ] || tk_bad "on: the unit did not get OCUTALON_E2E_TRACE=retain-on-failure"
[ -f "$tk_dir/traces/tk-run1/fake/t1/trace.zip" ] || tk_bad "on: the trace is not at <root>/<tag>/<unit>/<test>/trace.zip"
[ -z "$(tk_traces "$(tk_results)")" ] || tk_bad "on: a trace or artifacts folder stays below web/test-results"
[ -f "$(tk_results)/fake/t2/state-diagnosis.txt" ] || tk_bad "on: the other files of the unit did not stay"
[ "$(tk_mode "$tk_dir/traces")" = 700 ] || tk_bad "on: the root's mode is $(tk_mode "$tk_dir/traces"), wanted 700"
[ "$(tk_mode "$tk_dir/traces/tk-run1")" = 700 ] && [ "$(tk_mode "$tk_dir/traces/tk-run1/fake/t1")" = 700 ] || tk_bad "on: the run and test folders are not mode 700"
[ "$(tk_mode "$tk_dir/traces/tk-run1/fake/t1/trace.zip")" = 600 ] || tk_bad "on: the kept trace's mode is $(tk_mode "$tk_dir/traces/tk-run1/fake/t1/trace.zip"), wanted 600"
printf '%s\n' "$tk_out" | grep -qx 'TRACE on' || tk_bad "on: no 'TRACE on' line"
printf '%s\n' "$tk_out" | grep -qx 'TRACE kept 1 of fake under tk-run1/fake' || tk_bad "on: no 'TRACE kept 1 of fake under tk-run1/fake' line"
if printf '%s\n' "$tk_out" | grep -qF "$tk_dir"; then tk_bad "on: a log line names a host path"; fi

# On, but a trace cannot be moved (a file stands where the run folder belongs), and a link named like a trace: both are deleted, not kept.
tk_live unmovable GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-unmovable/work" OCUTALON_TRACE_DIR="$tmp/tk-unmovable/traces" OCUTALON_RUN_TAG=tk-run1 \
  TK_SETUP='mkdir -p "$OCUTALON_TRACE_DIR" && : > "$OCUTALON_TRACE_DIR/tk-run1"'
[ "$tk_rc" -eq 1 ] || tk_bad "unmovable: the unit's exit status 1 became $tk_rc"
[ -z "$(tk_traces "$(tk_results)")" ] || tk_bad "unmovable: a trace or artifacts folder stays below web/test-results"
[ -z "$(tk_traces "$tk_dir/traces")" ] || tk_bad "unmovable: a trace was written to the root"
printf '%s\n' "$tk_out" | grep -qx 'TRACE removed 1 of fake (traces are off or could not be moved)' || tk_bad "unmovable: no 'TRACE removed 1 of fake' line"
printf '%s\n' "$tk_out" | grep -q '^TRACE kept' && tk_bad "unmovable: a trace was reported kept"
tk_live trlink GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-trlink/work" OCUTALON_TRACE_DIR="$tmp/tk-trlink/traces" OCUTALON_RUN_TAG=tk-run1 \
  TK_UNIT_EXTRA='mkdir -p "$out/t3" && : > "$GITHUB_WORKSPACE/linked.zip" && ln -s "$GITHUB_WORKSPACE/linked.zip" "$out/t3/trace.zip"'
[ "$tk_rc" -eq 1 ] || tk_bad "trace link: the unit's exit status 1 became $tk_rc"
[ -z "$(tk_traces "$(tk_results)")" ] || tk_bad "trace link: a trace, a link or an artifacts folder stays below web/test-results"
[ -f "$tk_dir/traces/tk-run1/fake/t1/trace.zip" ] && [ ! -e "$tk_dir/traces/tk-run1/fake/t3" ] || tk_bad "trace link: the file was not kept, or the link was moved"
[ -f "$tk_dir/work/linked.zip" ] || tk_bad "trace link: the link's target was touched"
printf '%s\n' "$tk_out" | grep -qx 'TRACE removed 1 of fake (traces are off or could not be moved)' || tk_bad "trace link: no 'TRACE removed 1 of fake' line"

# Off: each row leaves the unit no switch, deletes the trace, keeps the other files and the exit status, and writes nothing to the root.
tk_off() { # tk_off <row> <why it is off> <variable=value...>
  local row=$1 why=$2
  shift 2
  tk_live "$row" "$@"
  [ "$tk_rc" -eq 1 ] || tk_bad "$why: the unit's exit status 1 became $tk_rc"
  [ "$(cat "$tk_dir/record" 2>/dev/null)" = unset ] || tk_bad "$why: the unit got an OCUTALON_E2E_TRACE"
  [ -z "$(tk_traces "$(tk_results)")" ] || tk_bad "$why: a trace or artifacts folder stays below web/test-results"
  [ -f "$(tk_results)/fake/t2/state-diagnosis.txt" ] || tk_bad "$why: the other files of the unit did not stay"
  printf '%s\n' "$tk_out" | grep -q '^TRACE off: ' || tk_bad "$why: no 'TRACE off:' line"
  printf '%s\n' "$tk_out" | grep -q '^TRACE kept' && tk_bad "$why: a trace was reported kept"
  if printf '%s\n' "$tk_out" | grep -qF "$tk_dir"; then tk_bad "$why: a log line names a host path"; fi
}
tk_off hosted "a hosted runner" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted GITHUB_WORKSPACE="$tmp/tk-hosted/work" OCUTALON_TRACE_DIR="$tmp/tk-hosted/traces" OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/traces" ] || tk_bad "a hosted runner: the root was made"
tk_off norunner "no runner" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT= GITHUB_WORKSPACE="$tmp/tk-norunner/work" OCUTALON_TRACE_DIR="$tmp/tk-norunner/traces" OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/traces" ] || tk_bad "no runner: the root was made"
tk_off inwork "a root inside the workspace" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-inwork/work" OCUTALON_TRACE_DIR="$tmp/tk-inwork/work/deep/traces" OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/work/deep" ] || tk_bad "a root inside the workspace: the root was made"
tk_off incheckout "a root inside the checkout" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-incheckout/work" OCUTALON_TRACE_DIR="$tmp/tk-incheckout/checkout/web/out" OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/checkout/web/out" ] || tk_bad "a root inside the checkout: the root was made"
# A link into the workspace is resolved (pwd -P) before the root is judged.
mkdir -p "$tmp/tk-link/work"
ln -s "$tmp/tk-link/work" "$tmp/tk-link-target" 2>/dev/null
tk_off link "a root behind a link into the workspace" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-link/work" OCUTALON_TRACE_DIR="$tmp/tk-link-target/traces" OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/work/traces" ] || tk_bad "a root behind a link: the root was made"
# A ".." through a folder that does not exist yet is not resolved by pwd -P: the root is refused on the text, before mkdir -p can make it inside the workspace.
tk_off dotdot "a root that climbs back into the workspace through .." GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-dotdot/work" OCUTALON_TRACE_DIR="$tmp/tk-dotdot/nope/../work/deep/traces" OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/work/deep" ] && [ ! -e "$tk_dir/nope" ] || tk_bad "a root with ..: the root was made"
tk_off relative "a root that is not absolute" GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-relative/work" OCUTALON_TRACE_DIR=relative/traces OCUTALON_RUN_TAG=tk-run1
[ ! -e "$tk_dir/checkout/relative" ] || tk_bad "a relative root: the root was made"

# A developer machine: no CI, nothing is switched on and nothing under web/test-results is touched.
tk_live dev OCUTALON_TRACE_DIR="$tmp/tk-dev/traces" OCUTALON_RUN_TAG=tk-run1
[ "$tk_rc" -eq 1 ] || tk_bad "dev: the unit's exit status 1 became $tk_rc"
[ "$(cat "$tk_dir/record" 2>/dev/null)" = unset ] || tk_bad "dev: the unit got an OCUTALON_E2E_TRACE"
[ -f "$(tk_results)/fake/t1/trace.zip" ] && [ -d "$(tk_results)/fake/.playwright-artifacts-0" ] || tk_bad "dev: web/test-results was touched"
[ ! -e "$tk_dir/traces" ] || tk_bad "dev: the root was made"

# The prune: run folders aged 8 and 6 days, and a name that is not a run tag aged 8 days; only the 8-day run folder goes, and only with traces on.
tk_age() { # tk_age <folder> <days>: sets the folder's modification time to that many days ago
  local t=$(( $(date +%s) - $2 * 86400 ))
  touch -t "$(date -u -d "@$t" +%Y%m%d%H%M 2>/dev/null || date -u -r "$t" +%Y%m%d%H%M)" "$1"
}
tk_prune() { # tk_prune <row> <variable=value...>: the folders are made, then traces_prune runs in a subshell of the sourced ci/iris.sh
  local row=$1 assignment
  shift
  tk_dir="$tmp/tk-$row"
  rm -rf "$tk_dir"
  mkdir -p "$tk_dir/traces/old-run" "$tk_dir/traces/new-run" "$tk_dir/traces/Keep Me" "$tk_dir/work"
  tk_age "$tk_dir/traces/old-run" 8
  tk_age "$tk_dir/traces/new-run" 6
  tk_age "$tk_dir/traces/Keep Me" 8
  (
    unset GITHUB_ACTIONS RUNNER_ENVIRONMENT GITHUB_WORKSPACE OCUTALON_TRACE_DIR OCUTALON_RUN_TAG OCUTALON_WARM RUNNER_NAME OCUTALON_TEST_WEB_PORT
    export HOME="$tk_dir/home"
    for assignment in "$@"; do export "$assignment"; done
    . "$root/ci/iris.sh"
    traces_prune
  ) > "$tk_dir/out" 2>&1
}
tk_prune prune GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted GITHUB_WORKSPACE="$tmp/tk-prune/work" OCUTALON_TRACE_DIR="$tmp/tk-prune/traces"
[ ! -e "$tk_dir/traces/old-run" ] || tk_bad "prune: the 8-day run folder stays"
[ -d "$tk_dir/traces/new-run" ] || tk_bad "prune: the 6-day run folder was removed"
[ -d "$tk_dir/traces/Keep Me" ] || tk_bad "prune: a folder that is not a run tag was removed"
tk_prune prune-off GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted GITHUB_WORKSPACE="$tmp/tk-prune-off/work" OCUTALON_TRACE_DIR="$tmp/tk-prune-off/traces"
[ -d "$tk_dir/traces/old-run" ] || tk_bad "prune: a hosted runner removed a run folder"

# cmd_group prunes once, after setup_tag; cmd_live is where the trace switch and the sweep live.
group_body=$(awk '/^cmd_group\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' ci/iris.sh)
tag_at=$(printf '%s\n' "$group_body" | grep -n '^  setup_tag$' | head -n 1 | cut -d: -f1)
prune_at=$(printf '%s\n' "$group_body" | grep -n '^  traces_prune$' | head -n 1 | cut -d: -f1)
{ [ -n "$tag_at" ] && [ -n "$prune_at" ] && [ "$prune_at" -gt "$tag_at" ]; } || tk_bad "cmd_group does not call traces_prune after setup_tag"
live_body=$(awk '/^cmd_live\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' ci/iris.sh)
printf '%s\n' "$live_body" | grep -q 'traces_keep ' || tk_bad "cmd_live does not call traces_keep"
printf '%s\n' "$live_body" | grep -q '^  exit "\$rc"$' || tk_bad "cmd_live does not exit with the unit's status"

if [ -z "$tk_fail" ]; then
  echo "PASS traces kept: a failing unit's trace moves to <root>/<tag>/<unit>/ (folders mode 700, the trace 600) on a self-hosted runner, and one that cannot be moved or is a link is deleted; it is deleted on a hosted one, with no runner, with a root inside the workspace or the checkout, behind a link, through .. or not absolute, and nothing is touched off CI; the exit status stays; traces_prune removes only run folders older than 7 days and cmd_group calls it after setup_tag"
else
  echo "FAIL traces kept:$tk_fail"
  fails=$((fails + 1))
fi

# --- budgets (Story 0.32; DW-1082, DW-1195): the floors of unit_live_deadline, the one first-start budget, and the audited waits ---

# budget_pos <file> <fixed text>: the line number of the one line that holds the text; nothing when it occurs on none or on several.
budget_pos() {
  local n
  n=$(grep -nF -e "$2" "$1" | cut -d: -f1)
  case $n in '' | *[!0-9]*) return 1 ;; esac
  printf '%s\n' "$n"
}
# budget_seq <file> <wait text> <measured text> <die text>: 0 when the three lines are each unique and come in that order, which
# puts the MEASURED line before the die on a failing wait too.
budget_seq() {
  local a b c
  a=$(budget_pos "$1" "$2") || return 1
  b=$(budget_pos "$1" "$3") || return 1
  c=$(budget_pos "$1" "$4") || return 1
  [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}

# budget_live_units: the live units of the groups, one name per line without live:.
budget_live_units() {
  (
    . "$root/ci/units.sh"
    for g in $IRIS_GROUPS; do
      for u in $(group_units "$g"); do
        case $u in
          live:*) echo "${u#live:}" ;;
        esac
      done
    done
  )
}
# budget_floor_report: "SEEN <unit>=<floor>..." for the live units that have a floor, and a BAD line for a floor outside (1200, 2340] or
# not an integer, and for a name that has a floor but should not.
budget_floor_report() {
  (
    . "$root/ci/units.sh"
    seen=""
    for n in $(budget_live_units); do
      if v=$(unit_live_deadline "$n"); then
        case $v in
          '' | *[!0-9]*) echo "BAD $n: floor '$v' is not an integer" ;;
          *) if [ "$v" -le 1200 ] || [ "$v" -gt 2340 ]; then echo "BAD $n: floor $v is not in (1200, 2340]"; fi ;;
        esac
        seen="$seen $n=$v"
      fi
    done
    echo "SEEN$seen"
    for n in floor cards nonesuch "" live:sign-in sign-in-4 SIGN-IN; do
      if unit_live_deadline "$n" > /dev/null; then echo "BAD '$n' has a floor"; fi
    done
  )
}

tk_fail=""
# The floors: exactly these units, each a live unit of a group, an integer above CI's 1200 s and at most 2340 s; any other name returns 1.
budget_floors=$(budget_floor_report)
budget_seen=$(printf '%s\n' "$budget_floors" | sed -n 's/^SEEN//p' | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ')
case "$budget_seen" in
  "install-start=1440 install-upgrade=1440 sign-in-2=1500 sign-in-3=1500 sign-in=1560 ") ;;
  *) tk_bad "the floors are '$budget_seen', wanted install-start=1440 install-upgrade=1440 sign-in-2=1500 sign-in-3=1500 sign-in=1560 (each a live unit of a group)" ;;
esac
printf '%s\n' "$budget_floors" | grep -q '^BAD' && tk_bad "unit_live_deadline: $(printf '%s\n' "$budget_floors" | grep '^BAD' | head -n 3 | tr '\n' ';')"

# The first start: one budget, LIVE_FIRST_START_WAIT, whose default is the audited 510 s and stays under AD-23's 720 s; no live script
# keeps a literal, and every first-start die names the variable.
grep -qx 'LIVE_FIRST_START_WAIT=${LIVE_FIRST_START_WAIT:-510}' docker/tests/lib-live.sh || tk_bad "lib-live.sh: LIVE_FIRST_START_WAIT does not default to 510"
budget_first=0
for budget_unit in $(budget_live_units); do
  budget_file="docker/tests/test-$budget_unit.sh"
  [ -f "$budget_file" ] || continue
  for budget_line in $(grep -n 'the first start did not end ready within' "$budget_file" | cut -d: -f1); do
    budget_first=$((budget_first + 1))
    budget_text=$(sed -n "${budget_line}p" "$budget_file")
    case $budget_text in
      *'within $LIVE_FIRST_START_WAIT s"') ;;
      *) tk_bad "$budget_file:$budget_line: the first-start die does not name \$LIVE_FIRST_START_WAIT" ;;
    esac
    budget_wait=$(sed -n "$((budget_line > 8 ? budget_line - 8 : 1)),${budget_line}p" "$budget_file" | grep 'wait_started_ready' | tail -n 1)
    case $budget_wait in
      *'wait_started_ready "$LIVE_FIRST_START_WAIT"; then') ;;
      *) tk_bad "$budget_file:$budget_line: the first-start wait is not wait_started_ready \"\$LIVE_FIRST_START_WAIT\"" ;;
    esac
  done
done
[ "$budget_first" -ge 23 ] || tk_bad "only $budget_first first-start dies in the live scripts, wanted 23"
for budget_file in docker/tests/test-*.sh; do
  case $budget_file in */test-ci-config.sh | */test-release-sequence.sh | */test-lib-live.sh | */test-upgrade-harness.sh) continue ;; esac
  if grep -v '^ *#' "$budget_file" | grep -q 'first start did not end ready within [0-9]'; then tk_bad "$budget_file: a first-start die names a literal budget"; fi
done

# DW-1082: the three waits of live:install-upgrade, each timed before its die; row 6 is 300 s (ruled), row 7 at least 300 s.
budget_up=docker/tests/test-install-upgrade.sh
budget_seq "$budget_up" 'wait_started_ready 300' 'echo "MEASURED row 6: the upgrade took $((SECONDS - wait_began)) s to ready"' 'die "row 6 the upgrade did not end ready within 300 s"' \
  || tk_bad "$budget_up: row 6 is not wait_started_ready 300, then its MEASURED line, then its die"
budget_seq "$budget_up" 'wait_started_log 300' 'echo "MEASURED row 7: the start with a failing step took $((SECONDS - wait_began)) s to end"' 'die "row 7 the start with a failing step did not end within 300 s"' \
  || tk_bad "$budget_up: row 7's failing step is not wait_started_log 300, then its MEASURED line, then its die"
budget_seq "$budget_up" 'wait_started_ready 330' 'echo "MEASURED row 7: the next good image took $((SECONDS - wait_began)) s to ready"' 'die "row 7 the next good image did not end ready within 330 s"' \
  || tk_bad "$budget_up: row 7's next good image is not wait_started_ready 330, then its MEASURED line, then its die"
[ "$(grep -c 'wait_started_\(ready\|log\) [0-9]' "$budget_up")" -eq 3 ] || tk_bad "$budget_up: not three literal waits"
# "Pass or fail" (AC 1): each MEASURED line is unconditional, straight after the wait's status and straight before the status test, so
# a line moved into the failing branch (still before the die) is caught here; the status is the wait's own (wait_rc=$? straight after
# the wait) and the seconds count from this row's start time (wait_began=$SECONDS straight before the wait).
for budget_m in 'echo "MEASURED row 6: the upgrade took|wait_started_ready 300' 'echo "MEASURED row 7: the start with a failing step took|wait_started_log 300' 'echo "MEASURED row 7: the next good image took|wait_started_ready 330'; do
  budget_ml=$(budget_pos "$budget_up" "${budget_m%%|*}") || budget_ml=0
  { [ "$budget_ml" -gt 3 ] && [ "$(sed -n "$((budget_ml - 1))p" "$budget_up")" = 'wait_rc=$?' ] && [ "$(sed -n "$((budget_ml + 1))p" "$budget_up")" = 'if [ "$wait_rc" -ne 0 ]; then' ]; } \
    || tk_bad "$budget_up: '${budget_m%%|*}' is not the unconditional line between wait_rc=\$? and the status test"
  { [ "$budget_ml" -gt 3 ] && [ "$(sed -n "$((budget_ml - 2))p" "$budget_up")" = "${budget_m#*|}" ] && [ "$(sed -n "$((budget_ml - 3))p" "$budget_up")" = 'wait_began=$SECONDS' ]; } \
    || tk_bad "$budget_up: '${budget_m%%|*}' does not follow wait_began=\$SECONDS, ${budget_m#*|} and wait_rc=\$? line by line"
done

# DW-1195: the sign-in suite prints its budget before the npm run and its seconds right after e2e_status=$?, whatever the outcome.
budget_si=docker/tests/test-sign-in.sh
budget_b=$(budget_pos "$budget_si" 'echo "MEASURED live:$suite_unit suite budget $((remaining - 20)) s"') || budget_b=0
budget_n=$(budget_pos "$budget_si" 'npm --prefix web run "$e2e_script"') || budget_n=0
budget_s=$(budget_pos "$budget_si" 'e2e_status=$?') || budget_s=0
{ [ "$budget_b" -gt 0 ] && [ "$budget_b" -lt "$budget_n" ] && [ "$(sed -n "$((budget_b + 1))p" "$budget_si")" = 'suite_began=$SECONDS' ]; } \
  || tk_bad "$budget_si: the suite budget line is missing, or does not come right before the browser run's start time and command"
[ "$budget_s" -gt "$budget_n" ] && [ "$(sed -n "$((budget_s + 1))p" "$budget_si")" = 'echo "MEASURED live:$suite_unit suite $((SECONDS - suite_began)) s"' ] \
  || tk_bad "$budget_si: the suite result line is not the unconditional line after e2e_status=\$?"
[ "$budget_s" -gt 1 ] && sed -n "$((budget_s - 1))p" "$budget_si" | grep -q 'npm --prefix web run' || tk_bad "$budget_si: e2e_status=\$? is not the line straight after the npm run"
[ "$(grep -c '^suite_unit=\${unit_name#test-}$' "$budget_si")" -eq 1 ] || tk_bad "$budget_si: suite_unit is not the unit name without test-"

# The other audited waits of live:install-start.
budget_is=docker/tests/test-install-start.sh
budget_pos "$budget_is" 'die "row 3 the dev start did not end ready within 300 s"' > /dev/null && [ "$(grep -B2 'row 3 the dev start did not end ready within 300 s' "$budget_is" | grep -c 'wait_started_ready 300; then')" -eq 1 ] \
  || tk_bad "$budget_is: row 3's wait is not 300 s with its die"
budget_pos "$budget_is" 'die "row 4 the restart did not end ready within 270 s"' > /dev/null && [ "$(grep -B2 'row 4 the restart did not end ready within 270 s' "$budget_is" | grep -c 'wait_started_ready 270; then')" -eq 1 ] \
  || tk_bad "$budget_is: row 4's restart wait is not 270 s with its die"

# AC 5: the committed audit table's new-value column equals the code (the floors, the first-start default and the five wait literals).
budget_ev=_bmad-output/implementation-artifacts/evidence/0-32-task0-ci-time-budgets.md
# budget_new <row label>: the "after" cell of the one row of the evidence's changed-budgets table whose budget cell is the label.
budget_new() {
  awk -F'|' -v want="$1" '{ k = $3; gsub(/^ +| +$/, "", k); if (k == want) { v = $5; gsub(/^ +| +$/, "", v); print v; n++ } } END { exit (n == 1 ? 0 : 1) }' "$budget_ev"
}
# budget_code_die <file> <die text before the number>: the number in the one die that names the wait's budget.
budget_code_die() { grep -F -e "$2" "$1" | sed -n 's/.*within \([0-9][0-9]*\) s".*/\1/p'; }
if [ ! -f "$budget_ev" ]; then
  tk_bad "the evidence file $budget_ev is missing"
else
  for budget_fl in install-start install-upgrade sign-in sign-in-2 sign-in-3; do
    budget_want=$(budget_new "live:$budget_fl deadline") || budget_want="(no single row)"
    budget_have=$(. "$root/ci/units.sh"; unit_live_deadline "$budget_fl")
    [ "$budget_want" = "$budget_have" ] || tk_bad "evidence table: live:$budget_fl deadline is '$budget_want', ci/units.sh has '$budget_have'"
  done
  budget_want=$(budget_new 'first start, 23 scripts (`LIVE_FIRST_START_WAIT`)') || budget_want="(no single row)"
  budget_have=$(sed -n 's/^LIVE_FIRST_START_WAIT=\${LIVE_FIRST_START_WAIT:-\([0-9][0-9]*\)}$/\1/p' docker/tests/lib-live.sh)
  [ "$budget_want" = "$budget_have" ] || tk_bad "evidence table: the first start is '$budget_want', lib-live.sh has '$budget_have'"
  for budget_row in \
    "test-install-upgrade.sh row 6|$budget_up|row 6 the upgrade did not end ready" \
    "test-install-upgrade.sh row 7 failing step|$budget_up|row 7 the start with a failing step did not end" \
    "test-install-upgrade.sh row 7 next good image|$budget_up|row 7 the next good image did not end ready" \
    "test-install-start.sh row 3|$budget_is|row 3 the dev start did not end ready" \
    "test-install-start.sh row 4 restart|$budget_is|row 4 the restart did not end ready"; do
    budget_want=$(budget_new "${budget_row%%|*}") || budget_want="(no single row)"
    budget_rest=${budget_row#*|}
    budget_have=$(budget_code_die "${budget_rest%%|*}" "${budget_rest#*|}")
    [ "$budget_want" = "$budget_have" ] || tk_bad "evidence table: ${budget_row%%|*} is '$budget_want', the code's die says '$budget_have'"
  done
  # The inventory tables (U and R) carry the same values in their "new" column (the eighth cell).
  budget_inv() {
    awk -F'|' -v want="$1" '{ k = $2; gsub(/^ +| +$/, "", k); if (k == want) { v = $9; gsub(/^ +| +$/, "", v); print v; n++ } } END { exit (n == 1 ? 0 : 1) }' "$budget_ev"
  }
  for budget_fl in install-start install-upgrade sign-in sign-in-2 sign-in-3; do
    budget_want=$(budget_inv "live:$budget_fl") || budget_want="(no single row)"
    budget_have=$(. "$root/ci/units.sh"; unit_live_deadline "$budget_fl")
    [ "$budget_want" = "$budget_have" ] || tk_bad "evidence U table: live:$budget_fl is '$budget_want', ci/units.sh has '$budget_have'"
  done
  [ "$(grep -c '| floor in `unit_live_deadline` |' "$budget_ev")" -eq 5 ] || tk_bad "evidence U table: not five rows with a floor"
  budget_have=$(sed -n 's/^LIVE_FIRST_START_WAIT=\${LIVE_FIRST_START_WAIT:-\([0-9][0-9]*\)}$/\1/p' docker/tests/lib-live.sh)
  budget_fs=$(awk -F'|' '$2 ~ /^ first start in / { v = $9; gsub(/^ +| +$/, "", v); print v }' "$budget_ev" | sort -u | tr '\n' ' ')
  [ "$budget_fs" = "$budget_have " ] || tk_bad "evidence R table: the first-start rows' new values are '$budget_fs', lib-live.sh has '$budget_have'"
  for budget_row in \
    "test-install-upgrade.sh:170 row 6|$budget_up|row 6 the upgrade did not end ready" \
    "test-install-upgrade.sh:205 row 7 failing step (log)|$budget_up|row 7 the start with a failing step did not end" \
    "test-install-upgrade.sh:256 row 7 next good image|$budget_up|row 7 the next good image did not end ready" \
    "test-install-start.sh:295 row 3|$budget_is|row 3 the dev start did not end ready" \
    "test-install-start.sh:665 row 4 restart|$budget_is|row 4 the restart did not end ready"; do
    budget_want=$(budget_inv "${budget_row%%|*}") || budget_want="(no single row)"
    budget_rest=${budget_row#*|}
    budget_have=$(budget_code_die "${budget_rest%%|*}" "${budget_rest#*|}")
    [ "$budget_want" = "$budget_have" ] || tk_bad "evidence R table: ${budget_row%%|*} is '$budget_want', the code's die says '$budget_have'"
  done
fi

# The floor in cmd_live, through the real cmd_live and the real unit_live_deadline over a fake checkout whose unit script records the
# deadline it sees (the rows that the consumer reads the producer's value).
budget_rec='printf "%s\n" "${OCUTALON_LIVE_DEADLINE-unset}" > "$FAKE_RECORD.deadline"'
tk_live floor-1200 TK_UNIT=sign-in OCUTALON_LIVE_DEADLINE=1200 TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = 1560 ] || tk_bad "floor over 1200: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted 1560"
printf '%s\n' "$tk_out" | grep -qx 'DEADLINE live:sign-in 1560 s' || tk_bad "floor over 1200: no 'DEADLINE live:sign-in 1560 s' line"
tk_live floor-unset TK_UNIT=install-upgrade TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = 1440 ] || tk_bad "floor, deadline unset: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted 1440"
printf '%s\n' "$tk_out" | grep -qx 'DEADLINE live:install-upgrade 1440 s' || tk_bad "floor, deadline unset: no 'DEADLINE live:install-upgrade 1440 s' line"
tk_live floor-above TK_UNIT=sign-in-2 OCUTALON_LIVE_DEADLINE=1980 TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = 1980 ] || tk_bad "floor below the given deadline: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted 1980"
printf '%s\n' "$tk_out" | grep -q '^DEADLINE' && tk_bad "floor below the given deadline: a DEADLINE line was printed"
tk_live floor-equal TK_UNIT=sign-in-3 OCUTALON_LIVE_DEADLINE=1500 TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = 1500 ] || tk_bad "floor equal to the given deadline: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted 1500"
printf '%s\n' "$tk_out" | grep -q '^DEADLINE' && tk_bad "floor equal to the given deadline: a DEADLINE line was printed"
tk_live floor-nonnumeric TK_UNIT=sign-in OCUTALON_LIVE_DEADLINE=abc TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = 1560 ] || tk_bad "floor over a non-numeric deadline: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted 1560"
printf '%s\n' "$tk_out" | grep -qx 'DEADLINE live:sign-in 1560 s' || tk_bad "floor over a non-numeric deadline: no 'DEADLINE live:sign-in 1560 s' line"
tk_live floor-none TK_UNIT=floor OCUTALON_LIVE_DEADLINE=1200 TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = 1200 ] || tk_bad "a unit with no floor: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted 1200"
printf '%s\n' "$tk_out" | grep -q '^DEADLINE' && tk_bad "a unit with no floor: a DEADLINE line was printed"
tk_live floor-none-unset TK_UNIT=floor TK_UNIT_EXTRA="$budget_rec"
[ "$(cat "$tk_dir/record.deadline" 2>/dev/null)" = unset ] || tk_bad "a unit with no floor and no deadline: the unit saw '$(cat "$tk_dir/record.deadline" 2>/dev/null)', wanted it unset"
printf '%s\n' "$tk_out" | grep -q '^DEADLINE' && tk_bad "a unit with no floor and no deadline: a DEADLINE line was printed"
# The four job timeouts (DW-1212, DW-1213, DW-1214): the backstops of a hang. REL-4's 35 minutes is the target the IPM jobs measure below.
budget_timeout() { # budget_timeout <workflow> <job>: the one timeout-minutes of the job
  awk -v job="$2" '/^  [A-Za-z0-9_-]+:[ \t]*$/ { cur = $1; sub(/:$/, "", cur) } cur == job && /^    timeout-minutes:/ { print $2; n++ } END { exit (n == 1 ? 0 : 1) }' "$1"
}
budget_to=""
for budget_row in ci.yml:iris:50 ci.yml:checks:25 lane-a.yml:ipm-install:45 lane-a.yml:ipm-install-p:45; do
  budget_f=.github/workflows/${budget_row%%:*}
  budget_rest=${budget_row#*:}
  budget_have=$(budget_timeout "$budget_f" "${budget_rest%%:*}") || budget_have="(no single timeout)"
  [ "$budget_have" = "${budget_rest#*:}" ] || tk_bad "$budget_f: job ${budget_rest%%:*} has timeout-minutes '$budget_have', wanted ${budget_rest#*:}"
  budget_to="$budget_to ${budget_rest%%:*}=$budget_have"
done
[ "$(. "$root/ci/units.sh"; printf '%s/%s' "$REL4_JOBS" "$REL4_TARGET_SECONDS")" = "ipm-install ipm-install-p/2100" ] \
  || tk_bad "ci/units.sh: REL4_JOBS / REL4_TARGET_SECONDS are not 'ipm-install ipm-install-p' / 2100"

# The REL-4 lines of the two lane-a IPM jobs, through the real cmd_build (the start stamp) and cmd_teardown (the lines) of a sourced
# ci/iris.sh, with a stub clock and stub docker. budget_job <row> <job or none> <start second or none> <end second> [<second build's second>]:
# sets budget_out (the output of the build and of the teardown, which always ends with the TEARDOWN line) and budget_sum (the step summary
# file); a fifth argument runs `build` a second time at that second.
budget_job() {
  local d="$tmp/budget-job-$1"
  rm -rf "$d"
  mkdir -p "$d/tmp" "$d/locks"
  (
    export TMPDIR="$d/tmp" GITHUB_STEP_SUMMARY="$d/summary" OCUTALON_RUN_TAG=bud-run1 OCUTALON_LOCK_DIR="$d/locks"
    unset RUNNER_NAME OCUTALON_TEST_WEB_PORT
    if [ "$2" = none ]; then unset GITHUB_JOB; else export GITHUB_JOB=$2; fi
    . "$root/ci/iris.sh"
    preflight() { :; }
    ensure_web_bundle() { return 0; }
    docker() { return 0; }
    budget_at=$3
    if [ "$3" != none ]; then
      job_now() { echo "$budget_at"; }
      cmd_build
      if [ -n "${5:-}" ]; then budget_at=$5; cmd_build; fi
    fi
    budget_at=$4
    cmd_teardown
  ) > "$d/out" 2>&1
  budget_out=$(cat "$d/out")
  budget_sum=$(cat "$d/summary" 2>/dev/null)
}
budget_job rel4-under ipm-install 1000 3000
printf '%s\n' "$budget_out" | grep -qx 'MEASURED ipm-install 2000 s' || tk_bad "REL-4 under: no 'MEASURED ipm-install 2000 s' line"
printf '%s\n' "$budget_out$budget_sum" | grep -q 'over REL-4' && tk_bad "REL-4 under the target: an 'over REL-4' flag was printed"
budget_job rel4-edge ipm-install-p 1000 3100
printf '%s\n' "$budget_out" | grep -qx 'MEASURED ipm-install-p 2100 s' || tk_bad "REL-4 at the target: no 'MEASURED ipm-install-p 2100 s' line"
printf '%s\n' "$budget_out$budget_sum" | grep -q 'over REL-4' && tk_bad "REL-4 exactly at 2100 s: an 'over REL-4' flag was printed"
budget_job rel4-over ipm-install-p 1000 3101
printf '%s\n' "$budget_out" | grep -qx 'MEASURED ipm-install-p 2101 s' || tk_bad "REL-4 over: no 'MEASURED ipm-install-p 2101 s' line"
printf '%s\n' "$budget_out" | grep -qx 'over REL-4: ipm-install-p took 2101 s, the target is 2100 s' || tk_bad "REL-4 over: no 'over REL-4' line in the log"
printf '%s\n' "$budget_sum" | grep -qx 'over REL-4: ipm-install-p took 2101 s, the target is 2100 s' || tk_bad "REL-4 over: no 'over REL-4' line in the step summary"
[ -z "$(ls "$tmp/budget-job-rel4-over/tmp" 2>/dev/null)" ] || tk_bad "REL-4 over: the start stamp is still there after teardown"
budget_job rel4-twice ipm-install 1000 3101 2500
printf '%s\n' "$budget_out" | grep -qx 'over REL-4: ipm-install took 2101 s, the target is 2100 s' || tk_bad "REL-4 with a second build: the stamp of the first build was not kept"
budget_job rel4-other iris 1000 9000
printf '%s\n' "$budget_out" | grep -q '^TEARDOWN tag bud-run1' || tk_bad "another job (iris): the teardown did not run to its TEARDOWN line"
printf '%s\n' "$budget_out$budget_sum" | grep -q -e 'MEASURED' -e 'over REL-4' && tk_bad "another job (iris): a REL-4 line was printed"
[ -z "$(ls "$tmp/budget-job-rel4-other/tmp" 2>/dev/null)" ] || tk_bad "another job (iris): a start stamp was written"
budget_job rel4-nojob none 1000 9000
printf '%s\n' "$budget_out" | grep -q '^TEARDOWN tag bud-run1' || tk_bad "no GITHUB_JOB: the teardown did not run to its TEARDOWN line"
printf '%s\n' "$budget_out$budget_sum" | grep -q -e 'MEASURED' -e 'over REL-4' && tk_bad "no GITHUB_JOB: a REL-4 line was printed"
budget_job rel4-nostamp ipm-install none 9000
printf '%s\n' "$budget_out" | grep -q '^TEARDOWN tag bud-run1' || tk_bad "no start stamp: the teardown did not run to its TEARDOWN line"
printf '%s\n' "$budget_out$budget_sum" | grep -q -e 'MEASURED' -e 'over REL-4' && tk_bad "no start stamp: a REL-4 line was printed"
budget_job rel4-badstamp ipm-install x1000 9000
printf '%s\n' "$budget_out" | grep -q '^TEARDOWN tag bud-run1' || tk_bad "a stamp that is not a number: the teardown did not run to its TEARDOWN line"
printf '%s\n' "$budget_out$budget_sum" | grep -q -e 'MEASURED' -e 'over REL-4' && tk_bad "a stamp that is not a number: a REL-4 line was printed"
[ -z "$(ls "$tmp/budget-job-rel4-badstamp/tmp" 2>/dev/null)" ] || tk_bad "a stamp that is not a number: the stamp is still there after teardown"

live_body=$(awk '/^cmd_live\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' ci/iris.sh)
printf '%s\n' "$live_body" | grep -q 'unit_live_deadline "\$name"' || tk_bad "cmd_live does not read unit_live_deadline"
printf '%s\n' "$live_body" | grep -q 'OCUTALON_E2E_OUTPUT="test-results/\$name" bash "docker/tests/test-\$name.sh" "\$@"' || tk_bad "cmd_live's run line changed"

if [ -z "$tk_fail" ]; then
  echo "PASS budgets (Story 0.32): unit_live_deadline holds exactly the five floors (${budget_seen% }), each a live unit of a group in (1200, 2340], cmd_live raises a lower or unset deadline to the floor with one DEADLINE line and keeps a higher one and any unlisted unit, the $budget_first first-start waits use LIVE_FIRST_START_WAIT (510 s) with dies that name it, and the audited waits of live:install-start and live:install-upgrade, with the MEASURED lines before the dies, and the sign-in suite's two MEASURED lines are in place, and the evidence table's new-value column equals the code, the job timeouts are${budget_to} minutes, and the lane-a IPM jobs print MEASURED <job> N s at teardown and flag over REL-4 (log and step summary) above 2100 s only"
else
  echo "FAIL budgets (Story 0.32):$tk_fail"
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

# --- ci/iris.sh shard --part k/n: the k-th of n contiguous parts of the ordered class list ---

# shard_part_run <arguments of cmd_shard...>: the title, then the classes, that cmd_shard hands to the run_classes stub; the exit status
# of cmd_shard is kept.
shard_part_run() {
  (
    unset OCUTALON_RUN_TAG OCUTALON_TEST_WEB_PORT RUNNER_NAME OCUTALON_WARM
    . ci/iris.sh
    run_classes() { printf '%s\n' "LABEL $1" "TITLE $2"; shift 2; printf '%s\n' "$@"; }
    cmd_shard "$@"
  )
}
part_ok=1
part_all=$(bash ci/iris.sh classes lane-a)
part_all_rev=$(printf '%s\n' "$part_all" | LC_ALL=C sort -r)
for part_n in 1 2 3; do
  for part_dir in "" "--reverse"; do
    part_joined=""
    part_min=999999
    part_max=0
    part_k=1
    while [ "$part_k" -le "$part_n" ]; do
      # shellcheck disable=SC2086
      part_out=$(shard_part_run lane-a $part_dir --part "$part_k/$part_n")
      part_label=$(printf '%s\n' "$part_out" | sed -n '1s/^LABEL //p')
      part_title=$(printf '%s\n' "$part_out" | sed -n '2s/^TITLE //p')
      part_list=$(printf '%s\n' "$part_out" | sed 1,2d)
      if [ "$part_label" != "shard-lane-a" ]; then part_ok=0; fi
      part_size=$(printf '%s\n' "$part_list" | grep -c .)
      case $part_title in
        *" part $part_k/$part_n") ;;
        *) part_ok=0 ;;
      esac
      if [ -n "$part_dir" ]; then
        case $part_title in "lane-a (reversed) part "*) ;; *) part_ok=0 ;; esac
      else
        case $part_title in "lane-a part "*) ;; *) part_ok=0 ;; esac
      fi
      if [ "$part_size" -lt 1 ]; then part_ok=0; fi
      if [ "$part_k" -eq 1 ]; then part_first=$part_size; fi
      if [ "$part_size" -lt "$part_min" ]; then part_min=$part_size; fi
      if [ "$part_size" -gt "$part_max" ]; then part_max=$part_size; fi
      part_joined=$(printf '%s\n%s' "$part_joined" "$part_list")
      part_k=$((part_k + 1))
    done
    part_joined=$(printf '%s\n' "$part_joined" | sed 1d)
    if [ -n "$part_dir" ]; then part_want=$part_all_rev; else part_want=$part_all; fi
    if [ "$part_joined" != "$part_want" ] || [ $((part_max - part_min)) -gt 1 ]; then part_ok=0; fi
    if [ "$part_size" -gt "$part_first" ]; then part_ok=0; fi
  done
done
part_eq=$(shard_part_run lane-a --part=2/3)
if [ "$part_eq" != "$(shard_part_run lane-a --part 2/3)" ]; then part_ok=0; fi
if [ "$part_eq" != "$(shard_part_run --part 2/3 lane-a)" ]; then part_ok=0; fi
part_none=$(shard_part_run lane-a)
if [ "$(printf '%s\n' "$part_none" | sed -n 2p)" != "TITLE lane-a" ] || [ "$(printf '%s\n' "$part_none" | sed 1,2d)" != "$part_all" ]; then part_ok=0; fi
for part_bad in 0/2 3/2 2 a/b 1/0 1/999 1/1000000 ""; do
  part_status=0
  part_msg=$(shard_part_run lane-a --part "$part_bad" 2>&1) || part_status=$?
  if [ "$part_status" -ne 2 ]; then part_ok=0; fi
  case $part_msg in *--part*) ;; *) part_ok=0 ;; esac
done
for part_form in "--part=" "--part"; do
  part_status=0
  part_msg=$(shard_part_run lane-a "$part_form" 2>&1) || part_status=$?
  if [ "$part_status" -ne 2 ]; then part_ok=0; fi
  case $part_msg in *--part*) ;; *) part_ok=0 ;; esac
done
if [ "$part_ok" -eq 1 ]; then
  echo "PASS shard part"
else
  echo "FAIL shard part"
  exit 1
fi
