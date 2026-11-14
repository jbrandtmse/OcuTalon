#!/usr/bin/env bash
# Hermetic self-test of the release upgrade harness (Story 11.2; release/upgrade-harness.sh): the logic that decides what the harness
# runs, reads and writes, with no container, no network call and no model. It sources the harness and pins, on synthetic git
# repositories and files in its own temporary folder:
#   - resolve-previous: the previous build (an explicit ref, the highest v* tag merged into HEAD with a pre-release before its release,
#     a tag on HEAD, an unmerged tag and v<candidate> skipped, the pinned commit when no tag is left, and the refusals);
#   - stamp-mode: the version stamp, the Mode line and the Required value;
#   - phase-ready: each forbidden order of the phases;
#   - reminder-expect: the late band at its two edges and inside;
#   - state-readers: the readers of a /state answer, on canned JSON;
#   - chat-request: the mock-log reader that finds the fact in the chat agent's request after a mark;
#   - storage-compare: the compiled-storage comparison (appended is clean; renamed, retyped, removed and moved slots are flagged);
#   - record: the record section (the result, the mode, the pre-release note, the rows, pairing as a pass row) and its write (another section
#     kept, a section replaced and not duplicated);
#   - record-contract: what Stories 11.4 and 11.5 read from a record file: the section's lines in their fixed order, one Result:,
#     Mode: and Required: line from the closed set of values, read as a consumer reads them with other sections around, and a table of
#     three-cell ASCII rows;
#   - pairing (Story 12.9): the pairing family over stubs of its five readings of the stack: the seed pairs a chat on the previous build
#     only when that build reports Included() 1; the upgrade check passes on a seeded chat that still names its session and gets a
#     notification, fails on a changed Pairing row or on a missing sendMessage, and writes the note that its upgrade part joins later when
#     the previous build did not include Telegram; the candidate's chat is paired at the end of the upgrade phase, and the restart check
#     passes only with the row intact and the notification delivered, and fails with no paired chat left;
#   - memory-document (Story 19.5): the memory and document families over stubs of built_class, run_turn, session_value and api_post/api_get: a previous
#     build whose MemoryOps or DocumentOps is not built seeds nothing and the upgrade row carries the note that its upgrade part joins later, one that is
#     built is seeded and checked after the upgrade, a search that misses (or a document that is not listed ready) is a fail line, and the record made on the
#     candidate is checked after the restart;
#   - stale-files (Story 36.7): stale_compare on equal, extra, missing and both-way lists and an empty build list (status 2); the plant's name
#     matches the Web step's STALEFILES and its hash holds a character outside esbuild's alphabet; the family is on and its row sits after
#     private globals; the three phases call the seed and the checks; check_stale_files over stubs passes on equal lists (and, after the upgrade,
#     on a 404 for the plant and a 200 for the main script) and fails naming each extra and each missing file, a plant that is served and an
#     empty build output; seed_stale_files over a stub of the plant records the seed line and the note, or fails;
#   - run: the run command chained over a stub of the harness: the phases in order, the options only on build, the tag shared, report and
#     down after any failed phase, and only down after a refused build;
#   - static: the harness holds no docker push, login, save or export, no compose config without --quiet and no inspect without
#     --format;
#   - real-previous: real_previous on a plain commit, a pull request's merge commit, the merge back and a merge of two product sides;
#   - real-tree: plan on this checkout writes a dry-run record, a version that is not the candidate's and a phase with no tag exit 2;
#   - storage-base: test-storage.sh judges this checkout's storage blocks against the pinned pre-release commit, so a non-appending
#     storage change since that commit fails this rule (a gate on the real tree), and the storage phase accepts only that verdict;
#   - merge-retries (Story 0.14): count_merge_retries over a stubbed start_log appends MERGE-RETRIES <n> (0, 1 or 2) and the start's label to the
#     results (a near miss counts too); the five starts each call it right after their wait, before any die
#     (phase_upgrade, phase_restart and ready_or_die run over stubs, ready or not); the record section reads
#     "Merge retries: 0" with no such line and the sum otherwise, right after Run:, with Result: and the table unchanged; report prints
#     MERGE-RETRIES <total> before RECORD and RESULT;
#   - previous-dockerfile (Story 0.15): previous_dockerfile names the previous tree's root Dockerfile, else its docker/Dockerfile (v1.0.4 and
#     earlier), and fails for neither, the root one winning when both exist; add_previous_context writes that path into context.yml and dies
#     for neither; phase_build, run from a synthetic repository over stubs that stop it after the export check, accepts the root layout and
#     the old layout and dies for a tree with neither Dockerfile or with no src/module.xml;
#   - report: report and upgrade over a fabricated state folder: every phase's results joined, the row of a phase that started and did
#     not end failed, exit 1 on any failure, and upgrade refused while seed is not done.
# Each rule first runs on a synthetic break (the rule pattern of test-storage.sh): a check that can no longer fail makes its rule fail.
# Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/release/upgrade-harness.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-uh.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
TAB=$(printf '\t')
bad=0

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
status_is() { # status_is <label> <wanted> <command...>: runs the command and compares its exit status
  local label=$1 want=$2 got
  shift 2
  "$@" > /dev/null 2>&1
  got=$?
  eq "$label (status)" "$got" "$want"
}

# rule <name> <check function> [<break function>]: the break is applied in a subshell and the check must fail there; the check must
# then pass on the real harness.
fails_total=0
rule() {
  local name=$1 check=$2 brk=${3:-} out
  if [ -n "$brk" ]; then
    if ( "$brk"; "$check" ) > /dev/null 2>&1; then
      echo "FAIL $name: the check passes on the synthetic break $brk"
      fails_total=$((fails_total + 1))
      return
    fi
  fi
  if out=$("$check" 2>&1); then
    echo "PASS $name"
  else
    printf '%s\n' "$out" | head -n 12
    echo "FAIL $name"
    fails_total=$((fails_total + 1))
  fi
}

# --- synthetic repositories ---

gcommit() { # gcommit <dir> <message>: a commit; prints its sha
  printf '%s\n' "$2" >> "$1/f.txt"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "$2"
  git -C "$1" rev-parse HEAD
}
ginit() { # ginit <dir>
  rm -rf "$1"
  git init -q "$1"
  git -C "$1" symbolic-ref HEAD refs/heads/main
}

# --- resolve-previous ---

t_resolve() {
  local bad=0 d c1 c2 c3 c4 c5 out saved=$UPGRADE_PRE_RELEASE_COMMIT

  d=$tmp/r-explicit
  ginit "$d"
  c1=$(gcommit "$d" one)
  c2=$(gcommit "$d" two)
  c3=$(gcommit "$d" three)
  out=$(resolve_previous "$d" 1.0.0 HEAD~1)
  eq "an explicit ref" "$out" "explicit${TAB}HEAD~1${TAB}$c2"
  out=$(resolve_previous "$d" 1.0.0 "$c1")
  eq "an explicit sha" "$out" "explicit${TAB}$c1${TAB}$c1"

  d=$tmp/r-tags
  ginit "$d"
  c1=$(gcommit "$d" one)
  git -C "$d" tag v0.9.0
  c2=$(gcommit "$d" two)
  git -C "$d" tag v0.10.0
  c3=$(gcommit "$d" three)
  git -C "$d" tag v1.0.0-rc1
  c4=$(gcommit "$d" four)
  git -C "$d" tag v1.0.0
  c5=$(gcommit "$d" five)
  out=$(resolve_previous "$d" 1.0.1)
  eq "the highest tag, a pre-release before its release" "$out" "tag${TAB}v1.0.0${TAB}$c4"
  git -C "$d" tag -d v1.0.0 > /dev/null
  out=$(resolve_previous "$d" 1.0.1)
  eq "a pre-release when its release is missing" "$out" "tag${TAB}v1.0.0-rc1${TAB}$c3"
  git -C "$d" tag -d v1.0.0-rc1 > /dev/null
  out=$(resolve_previous "$d" 1.0.1)
  eq "the tag by version, not by name (v0.10.0 follows v0.9.0)" "$out" "tag${TAB}v0.10.0${TAB}$c2"

  d=$tmp/r-head-tag
  ginit "$d"
  c1=$(gcommit "$d" one)
  git -C "$d" tag v1.0.0
  c2=$(gcommit "$d" two)
  git -C "$d" tag v1.0.1
  out=$(resolve_previous "$d" 1.0.2)
  eq "a tag on HEAD is skipped" "$out" "tag${TAB}v1.0.0${TAB}$c1"

  d=$tmp/r-unmerged
  ginit "$d"
  c1=$(gcommit "$d" one)
  git -C "$d" tag v0.1.0
  git -C "$d" checkout -q -b side
  gcommit "$d" side > /dev/null
  git -C "$d" tag v0.2.0
  git -C "$d" checkout -q main
  c3=$(gcommit "$d" three)
  out=$(resolve_previous "$d" 0.3.0)
  eq "a tag on an unmerged branch is skipped" "$out" "tag${TAB}v0.1.0${TAB}$c1"
  status_is "an explicit ref that is not an ancestor of HEAD" 2 resolve_previous "$d" 0.3.0 v0.2.0

  d=$tmp/r-candidate
  ginit "$d"
  c1=$(gcommit "$d" one)
  git -C "$d" tag v0.1.0
  c2=$(gcommit "$d" two)
  git -C "$d" tag v0.2.0
  c3=$(gcommit "$d" three)
  out=$(resolve_previous "$d" 0.2.0)
  eq "v<candidate version> is skipped" "$out" "tag${TAB}v0.1.0${TAB}$c1"

  d=$tmp/r-none
  ginit "$d"
  c1=$(gcommit "$d" one)
  gcommit "$d" two > /dev/null
  gcommit "$d" three > /dev/null
  UPGRADE_PRE_RELEASE_COMMIT=$c1
  out=$(resolve_previous "$d" 1.0.0)
  eq "no tag gives the pinned commit" "$out" "pre-release${TAB}$c1${TAB}$c1"
  UPGRADE_PRE_RELEASE_COMMIT=0000000000000000000000000000000000000000
  status_is "a pinned commit that is not in the repository" 2 resolve_previous "$d" 1.0.0
  out=$(resolve_previous "$d" 1.0.0 2>&1)
  has "the refusal names the pinned commit" "$out" "0000000000000000000000000000000000000000"
  UPGRADE_PRE_RELEASE_COMMIT=$(git -C "$d" rev-parse HEAD)
  status_is "the pinned commit is HEAD itself" 2 resolve_previous "$d" 1.0.0
  UPGRADE_PRE_RELEASE_COMMIT=$saved
  status_is "HEAD as the explicit ref" 2 resolve_previous "$d" 1.0.0 HEAD
  status_is "an unknown ref" 2 resolve_previous "$d" 1.0.0 no-such-ref
  out=$(resolve_previous "$d" 1.0.0 no-such-ref 2>&1)
  eq "an unknown ref prints nothing on stdout" "$(resolve_previous "$d" 1.0.0 no-such-ref 2> /dev/null)" ""
  has "an unknown ref gives one line on stderr" "$out" "no-such-ref"
  [ "$bad" -eq 0 ]
}
b_resolve() { resolve_previous() { printf 'explicit\tHEAD\t%s\n' "$(git -C "$1" rev-parse HEAD)"; }; }

# --- stamp-mode ---

t_stamp_mode() {
  local bad=0 d
  eq "equal versions are stamped" "$(stamp_for 0.1.0 0.1.0)" "0.1.0-pre.1"
  eq "different versions are not stamped" "$(stamp_for 0.1.0 0.1.1)" ""
  eq "a clean tree is a release" "$(mode_for 0 0 0)" "release"
  eq "--rehearsal is a rehearsal" "$(mode_for 0 1 0)" "rehearsal"
  eq "tracked changes are a rehearsal with uncommitted changes" "$(mode_for 0 0 1)" "rehearsal (uncommitted changes)"
  eq "--rehearsal on a dirty tree names the changes" "$(mode_for 0 1 1)" "rehearsal (uncommitted changes)"
  eq "plan is a dry run" "$(mode_for 1 0 0)" "dry run"
  eq "plan is a dry run on a dirty rehearsal" "$(mode_for 1 1 1)" "dry run"
  d=$tmp/r-required
  ginit "$d"
  gcommit "$d" one > /dev/null
  gcommit "$d" two > /dev/null
  eq "a resolved tag is required" "$(previous_required "$d" tag v1.0.0)" yes
  eq "a given release tag is required" "$(git -C "$d" tag v7.7.7 && previous_required "$d" explicit v7.7.7)" yes
  eq "a given commit is not required" "$(previous_required "$d" explicit HEAD~1)" no
  eq "a given non-release tag is not required" "$(git -C "$d" tag zz-note && previous_required "$d" explicit zz-note)" no
  eq "the pre-release is not required" "$(previous_required "$d" pre-release c9f1288c)" no
  [ "$bad" -eq 0 ]
}
b_stamp_mode() { stamp_for() { :; }; }

# --- phase-ready ---

t_phase_ready() {
  local bad=0 s=$tmp/state-pr out
  ok() { status_is "$1" 0 phase_ready "$s" "$2"; }
  no() { status_is "$1" 1 phase_ready "$s" "$2"; }
  rm -rf "$s"
  mkdir -p "$s"
  ok "build with no state" build
  ok "down with no state" down
  no "settings with no options" settings
  no "seed with no options" seed
  no "upgrade with no options" upgrade
  no "restart with no options" restart
  no "storage with no options" storage
  no "report with no options" report
  out=$(phase_ready "$s" seed)
  has "the refusal is one REFUSED line" "$out" "REFUSED seed"
  eq "the refusal is one line" "$(printf '%s\n' "$out" | grep -c .)" 1
  no "an unknown phase" frobnicate
  : > "$s/options"
  no "settings before build is done" settings
  printf 'done 5\n' > "$s/phase.build"
  ok "settings after build" settings
  ok "seed after build" seed
  ok "report after build" report
  no "upgrade before seed is done" upgrade
  no "restart before upgrade is done" restart
  no "storage before upgrade is done" storage
  printf 'failed 0\n' > "$s/phase.seed"
  no "upgrade after a failed seed" upgrade
  no "settings after seed has started" settings
  ok "seed again after a seed that failed and left no project" seed
  printf 'done 100\n' > "$s/phase.seed"
  ok "upgrade after seed" upgrade
  no "seed again after it is done" seed
  no "restart before upgrade is done (seed done)" restart
  mkdir -p "$s/p1"
  echo p > "$s/p1/project"
  no "build while the records project is up" build
  ok "down while the records project is up" down
  printf 'done 200\n' > "$s/phase.upgrade"
  ok "restart after upgrade" restart
  ok "storage after upgrade" storage
  no "upgrade again after it ran" upgrade
  [ "$bad" -eq 0 ]
}
b_phase_ready() { phase_ready() { return 0; }; }

# --- reminder-expect ---

t_reminder() {
  local bad=0
  eq "due 21 s before ready is late" "$(reminder_expect 1000 1021)" late
  eq "due 20 s before ready is either" "$(reminder_expect 1000 1020)" either
  eq "due at ready is either" "$(reminder_expect 1000 1000)" either
  eq "due 20 s after ready is either" "$(reminder_expect 1000 980)" either
  eq "due 21 s after ready is on time" "$(reminder_expect 1000 979)" on-time
  eq "the phrase for a reminder due before ready" "$(due_phrase 1000 1021)" "21 s before the candidate was ready"
  eq "the phrase for a reminder due after ready" "$(due_phrase 1000 979)" "21 s after the candidate was ready"
  eq "due long before ready is late" "$(reminder_expect 1000 5000)" late
  eq "due long after ready is on time" "$(reminder_expect 9000 5000)" on-time
  [ "$bad" -eq 0 ]
}
b_reminder() { reminder_expect() { echo either; }; }

# --- state-readers ---

write_state() {
  cat > "$tmp/state.json" <<'EOS'
{"demoMode": false,
 "chat": [
  {"type": "chat.message", "payload": {"clientId": "c1", "state": "done", "replyText": "Noted."}},
  {"type": "chat.message", "payload": {"clientId": "c2", "state": "running", "replyText": ""}},
  {"type": "incident", "payload": {"ref": "I1", "state": "resolved", "requests": [{"ref": "Q1", "state": "done", "result": {"total": 50, "completed": 50, "failedAgain": 0}}]}},
  {"type": "incident", "payload": {"ref": "I2", "state": "awaiting_approval", "requests": [{"ref": "Q2", "state": "pending"}]}},
  {"type": "notification", "payload": {"kind": "reminder", "text": "Reminder: check the upgrade."}},
  {"type": "notification", "payload": {"kind": "tellnow", "text": "Something else."}}
 ],
 "rail": {"approvals": [{"ref": "Q2", "state": "pending", "expiresAt": "2026-11-02T00:00:00Z"}, {"ref": "Q3", "state": "approved", "expiresAt": "2026-11-03T00:00:00Z"}],
  "checks": [{"production": "OcuTalon.Demo.Orders.Production", "displayName": "Orders", "stopped": false}],
  "reminders": [{"ref": "R2", "text": "review the upgrade notes", "dueAt": "2026-11-02T10:00:00Z", "state": "pending"}],
  "decisions": []},
 "phone": [{"text": "All 50 orders went through."}]}
EOS
  cat > "$tmp/state-stopped.json" <<'EOS'
{"demoMode": true, "chat": [], "rail": {"approvals": [], "checks": [{"production": "OcuTalon.Demo.Orders.Production", "displayName": "Orders", "stopped": true}], "reminders": [], "decisions": []}}
EOS
}

t_state_readers() {
  local bad=0 j=$tmp/state.json
  write_state
  eq "a done turn" "$(state_turn "$j" c1)" "done|Noted."
  eq "a running turn" "$(state_turn "$j" c2)" "running|"
  status_is "a turn that is not there" 1 state_turn "$j" c9
  eq "the pending approval" "$(state_pending_approval "$j")" "Q2|2026-11-02T00:00:00Z"
  eq "the pending approval by ref" "$(state_pending_approval "$j" Q2)" "Q2|2026-11-02T00:00:00Z"
  status_is "an approval that is not pending" 1 state_pending_approval "$j" Q3
  status_is "an approval that is not there" 1 state_pending_approval "$j" Q9
  eq "a reminder card" "$(state_reminder_card "$j" R2)" "R2|2026-11-02T10:00:00Z|pending"
  status_is "a reminder that left the rail" 1 state_reminder_card "$j" R1
  eq "a reminder by text" "$(state_reminder_by_text "$j" "review the upgrade notes")" "R2|2026-11-02T10:00:00Z"
  status_is "a reminder text that is not there" 1 state_reminder_by_text "$j" "stretch"
  eq "the Orders check" "$(state_checks_orders "$j")" "OcuTalon.Demo.Orders.Production"
  status_is "a stopped Orders check" 1 state_checks_orders "$tmp/state-stopped.json"
  eq "the new incident" "$(state_new_incident "$j")" "I2|Q2"
  status_is "no new incident other than the one left out" 1 state_new_incident "$j" I2
  eq "the resolved incident's result" "$(state_incident "$j" I1)" "resolved|50|50|0"
  eq "an incident with no result" "$(state_incident "$j" I2)" "awaiting_approval|||"
  status_is "an incident that is not there" 1 state_incident "$j" I9
  status_is "the phone item" 0 state_phone_has "$j" "All 50 orders went through."
  status_is "a phone text that differs" 1 state_phone_has "$j" "All 49 orders went through."
  eq "the reminder notice" "$(state_notice "$j" reminder "check the upgrade")" "Reminder: check the upgrade."
  status_is "a notice of another kind" 1 state_notice "$j" reminder "Something else"
  eq "demo mode off" "$(state_demo_mode "$j")" false
  eq "demo mode on" "$(state_demo_mode "$tmp/state-stopped.json")" true
  eq "an epoch" "$(iso_epoch 1970-01-01T00:00:10Z)" 10
  eq "an epoch with a fraction" "$(iso_epoch 1970-01-01T00:01:10.250Z)" 70
  eq "a time that is not UTC has no epoch" "$(iso_epoch 2026-11-01T00:00:10+00:00)" ""
  [ "$bad" -eq 0 ]
}
b_state_readers() { state_turn() { echo "done|"; }; iso_epoch() { :; }; }

# --- chat-request ---

write_logs() {
  local log=$tmp/mock-all.jsonl
  # line 1, before the mark: a chat request that carries the fact; line 2: the triage request (no tools); line 3: the chat request.
  printf '%s\n' \
    '{"marker":"recall-ask:K1","request":{"tools":[{"name":"x"}],"messages":[{"role":"user","content":"my build server is called ORION-7 (zzK1)"}]}}' \
    '{"marker":"recall-ask:K1","request":{"tools":[],"messages":[{"role":"user","content":"triage zzK1"}]}}' \
    '{"marker":"recall-ask:K1","request":{"tools":[{"name":"x"}],"messages":[{"role":"user","content":"my build server is called ORION-7 (zzK1)"},{"role":"assistant","content":[{"type":"text","text":"Noted."}]},{"role":"user","content":[{"type":"text","text":"[[mock:recall-ask:K1]] what?"}]}]}}' > "$log"
  # triage only
  printf '%s\n' \
    '{"marker":"recall-ask:K1","request":{"tools":[{"name":"x"}],"messages":[{"role":"user","content":"my build server is called ORION-7 (zzK1)"}]}}' \
    '{"marker":"recall-ask:K1","request":{"tools":[],"messages":[{"role":"user","content":"triage zzK1"}]}}' > "$tmp/mock-triage.jsonl"
  # the fact only before the mark; the chat request after it lacks the fact
  printf '%s\n' \
    '{"marker":"recall-ask:K1","request":{"tools":[{"name":"x"}],"messages":[{"role":"user","content":"zzK1"}]}}' \
    '{"marker":"recall-ask:K1","request":{"tools":[{"name":"x"}],"messages":[{"role":"user","content":"what is my build server called?"}]}}' > "$tmp/mock-before.jsonl"
  # the fact in text blocks of an earlier message
  printf '%s\n' \
    '{"marker":"other","request":{"tools":[{"name":"x"}],"messages":[]}}' \
    '{"marker":"recall-ask:K1","request":{"tools":[{"name":"x"}],"messages":[{"role":"user","content":[{"type":"text","text":"told zzK1"},{"type":"text","text":"more"}]},{"role":"user","content":"ask"}]}}' > "$tmp/mock-blocks.jsonl"
  printf 'not json\n' >> "$tmp/mock-blocks.jsonl"
}

t_chat_request() {
  local bad=0
  write_logs
  status_is "the chat request after the mark carries the fact" 0 chat_request_carries "$tmp/mock-all.jsonl" 1 recall-ask:K1 zzK1
  status_is "a triage-only line is not the chat request" 1 chat_request_carries "$tmp/mock-triage.jsonl" 1 recall-ask:K1 zzK1
  status_is "the fact only before the mark" 1 chat_request_carries "$tmp/mock-before.jsonl" 1 recall-ask:K1 zzK1
  status_is "the fact in text blocks" 0 chat_request_carries "$tmp/mock-blocks.jsonl" 1 recall-ask:K1 zzK1
  status_is "another marker" 1 chat_request_carries "$tmp/mock-all.jsonl" 1 recall-ask:K2 zzK1
  status_is "a mark past the end of the log" 1 chat_request_carries "$tmp/mock-all.jsonl" 3 recall-ask:K1 zzK1
  status_is "a log that is not there" 1 chat_request_carries "$tmp/no-such.jsonl" 0 recall-ask:K1 zzK1
  has "the report lists the requests after the mark" "$(chat_request_report "$tmp/mock-all.jsonl" 1 recall-ask:K1 zzK1)" "request 2: tools 1, messages 3, carries the fact: true"
  has "the report shows the triage request" "$(chat_request_report "$tmp/mock-all.jsonl" 1 recall-ask:K1 zzK1)" "request 1: tools 0"
  [ "$bad" -eq 0 ]
}
b_chat_request() {
  chat_request_carries() {
    tail -n +"$(($2 + 1))" "$1" | jq -R 'fromjson?' | jq -s -e --arg m "$3" --arg t "$4" '[ .[] | select(.marker == $m) ][0] | ([ .request.messages[]? | (if (.content | type) == "string" then .content else ([.content[]? | (.text? // empty)] | join("\n")) end) ] | join("\n") | contains($t))' > /dev/null 2>&1
  }
}

# --- storage-compare ---

t_storage() {
  local bad=0 before=$tmp/st-before after=$tmp/st-after out
  printf '%s\n' 'CHK|slot|OcuTalon.A|Default|1|Name|%Library.String|' 'CHK|slot|OcuTalon.A|Default|2|Items|OcuTalon.B|list' > "$before"
  cp "$before" "$after"
  printf '%s\n' 'CHK|slot|OcuTalon.A|Default|3|Extra|%Library.String|' 'CHK|slot|OcuTalon.C|Default|1|Name|%Library.String|' >> "$after"
  status_is "appended slots and a new class are clean" 0 storage_compare "$before" "$after"
  sed 's/|1|Name|/|1|Title|/' "$before" > "$after"
  status_is "a renamed property is flagged" 1 storage_compare "$before" "$after"
  out=$(storage_compare "$before" "$after")
  has "the rename is named" "$out" "OcuTalon.A|Default|1|Name"
  sed 's/|OcuTalon.B|list/|OcuTalon.D|list/' "$before" > "$after"
  status_is "a retyped property is flagged" 1 storage_compare "$before" "$after"
  sed 's/|list$/|array/' "$before" > "$after"
  status_is "a changed collection is flagged" 1 storage_compare "$before" "$after"
  sed '2d' "$before" > "$after"
  status_is "a removed slot is flagged" 1 storage_compare "$before" "$after"
  sed 's/|Default|1|Name|/|Default|3|Name|/' "$before" > "$after"
  status_is "a moved slot is flagged" 1 storage_compare "$before" "$after"
  : > "$after"
  status_is "an empty snapshot is refused" 2 storage_compare "$before" "$after"
  [ "$bad" -eq 0 ]
}
b_storage() {
  storage_compare() {
    local missing
    missing=$(LC_ALL=C comm -23 <(cut -d'|' -f1-6,8 "$1" | LC_ALL=C sort -u) <(cut -d'|' -f1-6,8 "$2" | LC_ALL=C sort -u))
    [ -z "$missing" ]
  }
}

# --- record ---

# write_results <file> <case>: the RECORD lines of a run.
write_results() {
  local f=$1 id
  : > "$f"
  case $2 in
    pass | fail | partial)
      for id in previous-build upgrade conversation reminder approval watch settings restart storage private-globals stale-files pairing memory document; do
        if [ "$2" = partial ] && [ "$id" = restart ]; then continue; fi
        if [ "$2" = partial ] && [ "$id" = storage ]; then continue; fi
        printf 'RECORD %s pass the first check of %s\nRECORD %s pass the second | check\n' "$id" "$id" "$id" >> "$f"
      done
      printf 'RECORD reminder note R1 fired late\n' >> "$f"
      if [ "$2" = fail ]; then printf 'RECORD watch fail Orders is not listed | really\nRECORD watch fail the press answered 409\n' >> "$f"; fi
      ;;
    held) printf 'RECORD pairing off held back\n' >> "$f" ;;
  esac
}

write_options() { # write_options <file> <kind> <ref> <mode>
  : > "$1"
  env_set "$1" version 1.0.1
  env_set "$1" rc 2
  env_set "$1" mode "$4"
  env_set "$1" prev_kind "$2"
  env_set "$1" prev_ref "$3"
  env_set "$1" prev_sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  env_set "$1" prev_version 1.0.0
  env_set "$1" stamp ""
  env_set "$1" cand_sha bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  env_set "$1" required "$([ "$2" = pre-release ] && echo no || echo yes)"
  env_set "$1" tag e11s2t
  env_set "$1" started 2026-11-01T10:00:00Z
  env_set "$1" ended 2026-11-01T10:20:00Z
}

t_record() {
  local bad=0 r=$tmp/results o=$tmp/options sec rec

  write_options "$o" tag v1.0.0 release
  write_results "$r" pass
  sec=$(record_section "$r" "$o")
  eq "all rows pass" "$(printf '%s\n' "$sec" | sed -n 's/^Result: //p')" pass
  eq "the mode line" "$(printf '%s\n' "$sec" | sed -n 's/^Mode: //p')" release
  eq "required for a release tag" "$(printf '%s\n' "$sec" | sed -n 's/^Required: //p')" yes
  eq "the candidate line" "$(printf '%s\n' "$sec" | sed -n 's/^Candidate: //p')" "1.0.1 at bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  eq "the previous line" "$(printf '%s\n' "$sec" | sed -n 's/^Previous: //p')" "tag v1.0.0 at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, version 1.0.0, built as 1.0.0"
  eq "the run line" "$(printf '%s\n' "$sec" | sed -n 's/^Run: //p')" "2026-11-01T10:00:00Z to 2026-11-01T10:20:00Z, tag e11s2t"
  lacks "no note for a release tag" "$sec" "Note:"
  eq "the heading is the first line" "$(printf '%s\n' "$sec" | head -n 1)" "## Upgrade harness"
  eq "the table has a header, a separator and fourteen rows" "$(printf '%s\n' "$sec" | grep -c '^| ')" 16
  eq "the rows are in order, memory and document last" "$(printf '%s\n' "$sec" | sed -n 's/^| \([a-z ]*\) | [a-z ]* | .*/\1/p' | tr '\n' ',')" "previous build,upgrade,conversation,reminder,approval,watch,settings,restart,storage,private globals,stale files,pairing,memory,document,"
  has "pairing is a pass row in the table" "$sec" "| pairing | pass | 2 checks passed |"
  has "stale files is a pass row in the table, after private globals" "$sec" "| private globals | pass | 2 checks passed |
| stale files | pass | 2 checks passed |
| pairing |"
  lacks "no row is off" "$sec" "| off |"
  has "a note adds to a pass detail" "$sec" "| reminder | pass | 2 checks passed; R1 fired late |"

  write_options "$o" pre-release aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "rehearsal (uncommitted changes)"
  sec=$(record_section "$r" "$o")
  eq "no required for a pre-release" "$(printf '%s\n' "$sec" | sed -n 's/^Required: //p')" no
  eq "the mode of a rehearsal with changes" "$(printf '%s\n' "$sec" | sed -n 's/^Mode: //p')" "rehearsal (uncommitted changes)"
  eq "the pre-release previous line" "$(printf '%s\n' "$sec" | sed -n 's/^Previous: //p')" "pre-release aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, version 1.0.0, built as 1.0.0"
  eq "the pre-release note" "$(printf '%s\n' "$sec" | sed -n 's/^Note: //p')" "1.0.0 is the first release: it has no previous release, so the previous side is a pre-release build of the integration branch (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa), which proves the harness itself."
  write_options "$o" explicit HEAD~1 rehearsal
  sec=$(record_section "$r" "$o")
  eq "the mode of a rehearsal" "$(printf '%s\n' "$sec" | sed -n 's/^Mode: //p')" rehearsal
  has "an explicit previous line names the ref and the sha" "$sec" "Previous: explicit HEAD~1 at aaaa"
  write_options "$o" pre-release aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "dry run"
  sec=$(record_section /dev/null "$o")
  eq "no results is not run" "$(printf '%s\n' "$sec" | sed -n 's/^Result: //p')" "not run"
  eq "a dry run's mode" "$(printf '%s\n' "$sec" | sed -n 's/^Mode: //p')" "dry run"
  eq "every row is not run, stale files, pairing, memory and document too" "$(printf '%s\n' "$sec" | grep -c '| not run | not run |')" 14

  write_results "$r" fail
  sec=$(record_section "$r" "$o")
  eq "a failed line fails the result" "$(printf '%s\n' "$sec" | sed -n 's/^Result: //p')" fail
  has "the failed row shows its first failure, with no pipe in it, and the count" "$sec" "| watch | fail | Orders is not listed / really (and 1 more failed) |"
  eq "the result function agrees" "$(record_result "$r")" fail
  write_results "$r" partial
  eq "rows that were never reached fail the result" "$(record_result "$r")" fail
  has "an unreached row is not run" "$(record_section "$r" "$o")" "| restart | not run | not run |"
  write_results "$r" pass
  printf 'RECORD conversation seed the fact is told\nRECORD approval seed Break the feed\n' > "$tmp/results-seed"
  grep -v '^RECORD \(conversation\|approval\) ' "$r" >> "$tmp/results-seed"
  eq "the seed lines are no checks of the upgrade" "$(record_rows "$tmp/results-seed" | awk -F'\t' '$1 == "conversation" || $1 == "approval" { print $3 "," $4 }' | tr '\n' ' ')" "not run,not run (seeded only) not run,not run (seeded only) "
  printf 'RECORD conversation pass after the upgrade\n' >> "$tmp/results-seed"
  eq "a seed line and a check make a pass of one check" "$(record_rows "$tmp/results-seed" | awk -F'\t' '$1 == "conversation" { print $3 "," $4 }')" "pass,1 checks passed"
  eq "pairing is counted: all its rows pass" "$(record_result "$r")" pass
  printf 'RECORD pairing fail the restart lost the chat\n' >> "$r"
  eq "a pairing failure line fails the result" "$(record_result "$r")" fail
  has "and its row shows the failure" "$(record_section "$r" "$o")" "| pairing | fail | the restart lost the chat |"
  write_results "$r" pass
  printf 'RECORD pairing note the upgrade part joins from the release after 1.0.0\n' >> "$r"
  has "the note adds to the pairing pass detail" "$(record_section "$r" "$o")" "| pairing | pass | 2 checks passed; the upgrade part joins from the release after 1.0.0 |"
  write_results "$r" held
  eq "a held-back row is not counted (HARNESS_OFF)" "$(HARNESS_OFF=pairing record_result "$r")" "not run"
  write_results "$r" pass

  # record_write: a missing file, another section kept, the section replaced and not duplicated.
  rec=$tmp/record.md
  rm -f "$rec"
  write_results "$r" pass
  record_section "$r" "$o" > "$tmp/section.md"
  record_write "$rec" "$tmp/section.md" "# OcuTalon 1.0.1 rc2"
  eq "a missing file starts with the title" "$(head -n 1 "$rec")" "# OcuTalon 1.0.1 rc2"
  eq "the section is written once" "$(grep -c '^## Upgrade harness$' "$rec")" 1
  printf '\n## Rehearsal\n\nResult: pass\n' >> "$rec"
  record_write "$rec" "$tmp/section.md" "# OcuTalon 1.0.1 rc2"
  eq "the section is replaced, not duplicated" "$(grep -c '^## Upgrade harness$' "$rec")" 1
  has "another section is kept" "$(cat "$rec")" "## Rehearsal"
  has "the other section keeps its text" "$(cat "$rec")" "Result: pass"
  write_results "$r" fail
  record_section "$r" "$o" > "$tmp/section.md"
  record_write "$rec" "$tmp/section.md" "# OcuTalon 1.0.1 rc2"
  eq "the new section is the one in the file" "$(sed -n '/^## Upgrade harness$/,/^## Rehearsal$/p' "$rec" | sed -n 's/^Result: //p')" fail
  eq "a blank line separates the sections" "$(grep -B1 '^## Rehearsal$' "$rec" | head -n 1)" ""
  eq "still one section after the third write" "$(grep -c '^## Upgrade harness$' "$rec")" 1
  printf '# Other record\n\nSome text.\n' > "$tmp/other.md"
  record_write "$tmp/other.md" "$tmp/section.md"
  eq "a file with no section gets it appended" "$(grep -c '^## Upgrade harness$' "$tmp/other.md")" 1
  has "the appended file keeps its text" "$(cat "$tmp/other.md")" "Some text."
  printf '\n# Appendix\n\nKept text.\n' >> "$tmp/other.md"
  record_write "$tmp/other.md" "$tmp/section.md"
  has "a top-level heading after the section ends it" "$(cat "$tmp/other.md")" "Kept text."
  [ "$bad" -eq 0 ]
}
b_record() { record_result() { echo pass; }; }

# --- static ---

# static_violations <file>: the lines of a script's commands (comments left out) that publish, save, sign in, print a compose
# configuration or inspect without a format: rule<TAB>line number.
static_violations() {
  local f=$1
  grep -nE '^[[:space:]]*[^#[:space:]]' "$f" | grep -E 'docker[[:space:]]+([a-z]+[[:space:]]+)?(push|login|save|export)([[:space:]]|$)' | sed 's/^\([0-9]*\):.*/docker-publish\t\1/'
  grep -nE '^[[:space:]]*[^#[:space:]]' "$f" | grep -E '(compose[^|;&]*|(^|[:[:space:]])dc)[[:space:]]+config([[:space:]]|$)' | grep -v -- '--quiet' | sed 's/^\([0-9]*\):.*/compose-config\t\1/'
  grep -nE '^[[:space:]]*[^#[:space:]]' "$f" | grep -E 'docker[[:space:]]+([a-z]+[[:space:]]+)?inspect' | grep -v -- '--format' | sed 's/^\([0-9]*\):.*/inspect\t\1/'
  return 0
}

t_static() {
  local bad=0 f out d="docker"
  f=$tmp/static-bad
  # The samples are assembled, so that this script does not hold what test-boundaries.sh flags.
  printf '%s\n' "# $d push is only a comment" "$d push registry/x" "$d image save -o x.tar y" "$d login" "$d export abc" > "$f"
  out=$(static_violations "$f")
  eq "push, save, login and export are flagged" "$(printf '%s\n' "$out" | grep -c '^docker-publish')" 4
  printf '%s\n' "$d compose config" "$d compose -p x config" "dc config" "$d compose -p x config --quiet" "$d compose config --quiet" "dc config --quiet" > "$f"
  out=$(static_violations "$f")
  eq "compose config without --quiet is flagged, with flags before config too" "$(printf '%s\n' "$out" | grep -c '^compose-config')" 3
  printf '%s\n' "$d inspect abc" "$d image inspect abc" "$d inspect --format x abc" "$d image inspect --format x abc" > "$f"
  out=$(static_violations "$f")
  eq "inspect without --format is flagged" "$(printf '%s\n' "$out" | grep -c '^inspect')" 2
  printf '%s\n' "# $d push, $d login, $d inspect and compose config in comments only" 'echo ok' > "$f"
  eq "comments are left out" "$(static_violations "$f")" ""
  eq "the harness holds none" "$(static_violations "$root/release/upgrade-harness.sh")" ""
  [ "$bad" -eq 0 ]
}
b_static() { static_violations() { :; }; }

# --- real-tree ---

run_plan() { env -u OCUTALON_RUN_TAG bash "$root/release/upgrade-harness.sh" plan "$@"; }

# real_previous [<repository>]: the first of HEAD~1 and HEAD^2~1 that holds src/module.xml, or nothing. On a pull request's merge commit, and on main's
# merge commit, HEAD~1 is main's old tip, which has no product; at the merge back into the integration branch HEAD~1 is right and HEAD^2~1 is that old tip.
real_previous() {
  local ref
  for ref in 'HEAD~1' 'HEAD^2~1'; do
    if git -C "${1:-.}" cat-file -e "$ref:src/module.xml" 2> /dev/null; then
      echo "$ref"
      return 0
    fi
  done
  return 1
}

# gmerge <dir> <branch>: a merge commit of the branch.
gmerge() { git -C "$1" -c user.name=t -c user.email=t@example.invalid merge -q --no-ff -m "merge $2" "$2"; }

t_real_previous() {
  local bad=0 d=$tmp/real-previous
  ginit "$d"
  git -C "$d" checkout -q -b old-main
  gcommit "$d" "main's old tip" > /dev/null
  git -C "$d" checkout -q -b feature
  mkdir -p "$d/src"
  echo '<Module/>' > "$d/src/module.xml"
  git -C "$d" add src
  gcommit "$d" product > /dev/null
  gcommit "$d" candidate > /dev/null
  eq "a plain commit: HEAD~1" "$(real_previous "$d")" 'HEAD~1'
  git -C "$d" checkout -q -b pr old-main
  gmerge "$d" feature
  eq "a pull request's merge commit: HEAD^2~1" "$(real_previous "$d")" 'HEAD^2~1'
  git -C "$d" checkout -q feature
  gcommit "$d" "after the cut" > /dev/null
  gmerge "$d" pr
  eq "the merge back: HEAD~1, though main's side is the second parent" "$(real_previous "$d")" 'HEAD~1'
  git -C "$d" checkout -q -b epic HEAD~1
  gcommit "$d" "an epic" > /dev/null
  gcommit "$d" "and more" > /dev/null
  git -C "$d" checkout -q feature
  gmerge "$d" epic
  eq "both sides hold the product: HEAD~1 first" "$(real_previous "$d")" 'HEAD~1'
  git -C "$d" checkout -q old-main
  eq "no side holds the product: nothing" "$(real_previous "$d")" ''
  [ "$bad" -eq 0 ]
}

t_real() {
  local bad=0 rec=$tmp/real-record.md out previous
  previous=$(real_previous)
  if [ -n "$previous" ]; then
    out=$(run_plan --previous "$previous" --rc 1 --record "$rec" 2>&1)
    eq "plan --previous $previous exits 0" "$?" 0
    has "plan ends with RESULT not run" "$out" "RESULT not run"
    has "the record is a dry run" "$(cat "$rec" 2> /dev/null)" "Mode: dry run"
    has "the record's result is not run" "$(cat "$rec" 2> /dev/null)" "Result: not run"
    has "the record names the explicit previous build" "$(cat "$rec" 2> /dev/null)" "Previous: explicit $previous at "
    has "the record's candidate is this checkout's version" "$(cat "$rec" 2> /dev/null)" "Candidate: $(manifest_version src/module.xml) at $(git rev-parse HEAD)"
  else
    echo "  this checkout has no parent commit that holds the product (a shallow clone): the plan with --previous cannot run here"
    bad=1
  fi
  out=$(run_plan --rc 1 --record "$tmp/default-record.md" 2>&1)
  eq "plan with no --previous exits 0 on the real tree" "$?" 0
  has "the default previous build is a release tag or the pinned commit" "$(cat "$tmp/default-record.md" 2> /dev/null)" "Previous: "
  case $(grep '^Previous: ' "$tmp/default-record.md" 2> /dev/null) in
    "Previous: tag "* | "Previous: pre-release "*) ;;
    *)
      echo "  the default previous build is neither a tag nor the pinned commit"
      bad=1
      ;;
  esac
  run_plan --version 9.9.9 --rc 1 --record "$tmp/never.md" > /dev/null 2>&1
  eq "plan --version 9.9.9 exits 2" "$?" 2
  [ ! -e "$tmp/never.md" ] || {
    echo "  a refused plan wrote a record"
    bad=1
  }
  run_plan --rc 0 > /dev/null 2>&1
  eq "plan --rc 0 exits 2" "$?" 2
  run_plan --record "$tmp/never.md" --bogus > /dev/null 2>&1
  eq "an unknown option exits 2" "$?" 2
  run_plan > /dev/null 2>&1
  eq "plan with neither --rc nor --record exits 2" "$?" 2
  env -u OCUTALON_RUN_TAG bash "$root/release/upgrade-harness.sh" seed > /dev/null 2>&1
  eq "a phase with no tag exits 2" "$?" 2
  OCUTALON_RUN_TAG=zz-uh-none-$$ bash "$root/release/upgrade-harness.sh" seed > /dev/null 2>&1
  eq "a phase with a tag and no state exits 2" "$?" 2
  OCUTALON_RUN_TAG=zz-uh-none-$$ bash "$root/release/upgrade-harness.sh" upgrade > /dev/null 2>&1
  eq "upgrade with a tag and no state exits 2" "$?" 2
  OCUTALON_RUN_TAG=zz-uh-none-$$ bash "$root/release/upgrade-harness.sh" seed --rc 1 > /dev/null 2>&1
  eq "options on a phase other than build exit 2" "$?" 2
  env -u OCUTALON_RUN_TAG bash "$root/release/upgrade-harness.sh" frobnicate > /dev/null 2>&1
  eq "an unknown command exits 2" "$?" 2
  [ "$bad" -eq 0 ]
}
b_real() { run_plan() { return 1; }; }

# --- storage-base ---

# The storage phase passes only on the base-commit verdict of test-storage.sh, never on its "no release tag yet" line.
run_storage_base() { OCUTALON_STORAGE_BASE=$1 bash "$root/docker/tests/test-storage.sh" 2>&1; }
t_storage_base() {
  local bad=0 pinned=$UPGRADE_PRE_RELEASE_COMMIT line
  line=$(run_storage_base "$pinned" | grep -E '^(PASS|FAIL) release-diff' | head -n 1)
  eq "the real tree is judged against the base commit" "$line" "PASS release-diff: the storage blocks only grew since $pinned"
  status_is "the storage phase accepts that verdict" 0 release_diff_verdict_ok "$line" "$pinned"
  status_is "the storage phase refuses the no-tag verdict" 1 release_diff_verdict_ok "PASS release-diff: no release tag yet" "$pinned"
  status_is "the storage phase refuses a failing verdict" 1 release_diff_verdict_ok "FAIL release-diff: x" "$pinned"
  [ "$bad" -eq 0 ]
}
b_storage_base() {
  run_storage_base() { echo "PASS release-diff: no release tag yet"; }
  release_diff_verdict_ok() { return 0; }
}

# --- record-contract ---

# What Stories 11.4 and 11.5 read from the record: the section's lines in their fixed order, and the values of Result:, Mode: and
# Required: read the way a consumer reads a record file (the lines under the "## Upgrade harness" heading only).
consumer_read() { # consumer_read <record file> <Key>: the value of the key in the harness section
  sed -n '/^## Upgrade harness[[:space:]]*$/,$p' "$1" | awk 'NR > 1 && /^## / { exit } { print }' | sed -n "s/^$2: //p"
}

t_record_contract() {
  local bad=0 r=$tmp/rc-results o=$tmp/rc-options sec rec=$tmp/rc-record.md kind mode res want want_order got_order v rows

  want_order="## Upgrade harness,Result,Mode,Required,Candidate,Previous,Note,Run,Merge retries,| Record"
  write_results "$r" pass
  write_options "$o" pre-release aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa release
  got_order=$(record_section "$r" "$o" | grep -E '^(## Upgrade harness|Result:|Mode:|Required:|Candidate:|Previous:|Note:|Run:|Merge retries:|\| Record )' | sed 's/:.*//; s/ |.*$//' | tr '\n' ',')
  eq "the lines of a pre-release section are in the fixed order" "$got_order" "$want_order,"
  write_options "$o" tag v1.0.0 release
  got_order=$(record_section "$r" "$o" | grep -E '^(## Upgrade harness|Result:|Mode:|Required:|Candidate:|Previous:|Note:|Run:|Merge retries:|\| Record )' | sed 's/:.*//; s/ |.*$//' | tr '\n' ',')
  eq "a tag section has the same order with no Note" "$got_order" "## Upgrade harness,Result,Mode,Required,Candidate,Previous,Run,Merge retries,| Record,"

  # Every value a consumer can meet is one of the words it matches on, once, in a file that holds other sections around it.
  for kind in pass fail partial; do
    for mode in release rehearsal "rehearsal (uncommitted changes)" "dry run"; do
      write_results "$r" "$kind"
      write_options "$o" tag v1.0.0 "$mode"
      record_section "$r" "$o" > "$tmp/rc-section.md"
      printf '# OcuTalon 1.0.1 rc2\n\n## Rehearsal\n\nResult: dry run\nMode: rehearsal\nRequired: maybe\n\n' > "$rec"
      record_write "$rec" "$tmp/rc-section.md"
      printf '\n## Checklist\n\nResult: pass\n' >> "$rec"
      record_write "$rec" "$tmp/rc-section.md"
      res=$(consumer_read "$rec" Result)
      case $kind in pass) want=pass ;; *) want=fail ;; esac
      eq "one Result line for $kind/$mode, read as a consumer reads it" "$res" "$want"
      eq "one Mode line for $kind/$mode" "$(consumer_read "$rec" Mode)" "$mode"
      eq "one Required line for $kind/$mode" "$(consumer_read "$rec" Required)" yes
    done
  done
  record_section /dev/null "$o" > "$tmp/rc-section.md"
  printf '## Other\n\nResult: pass\n' > "$rec"
  record_write "$rec" "$tmp/rc-section.md"
  eq "a section that was never run reads not run" "$(consumer_read "$rec" Result)" "not run"
  eq "the other section's Result line is kept beside the harness's" "$(grep -c '^Result: ' "$rec")" 2

  # The table: three cells per row, a result from the closed set, and no pipe or non-ASCII character inside a cell.
  write_results "$r" fail
  (cur_row=upgrade results=$r record_line fail "$(printf 'a | b caf\303\251 \t tab')")
  write_options "$o" tag v1.0.0 release
  sec=$(record_section "$r" "$o")
  rows=$(printf '%s\n' "$sec" | grep -E '^\| ' | sed '1,2d')
  eq "every table row has three cells" "$(printf '%s\n' "$rows" | awk -F' [|] ' '{ if (NF != 3) bad++ } END { print bad + 0 }')" 0
  eq "every row's result is pass, fail, not run or off" "$(printf '%s\n' "$rows" | awk -F' [|] ' '$2 != "pass" && $2 != "fail" && $2 != "not run" && $2 != "off" { bad++ } END { print bad + 0 }')" 0
  eq "the section is plain ASCII" "$(printf '%s\n' "$sec" | LC_ALL=C grep -c '[^ -~]')" 0
  v=$(printf '%s\n' "$rows" | sed -n 's/^| \([a-z ]*\) | .*/\1/p' | wc -l | tr -d ' ')
  eq "the rows are the fourteen records" "$v" 14
  [ "$bad" -eq 0 ]
}
b_record_contract() {
  eval "$(declare -f record_section | sed '1s/^record_section/orig_record_section/')"
  record_section() { orig_record_section "$@" | sed 's/^Mode: /Mode:/'; }
}

# --- pairing (Story 12.9) ---

# The family over stubs of its five readings of the stack. STUB_* say what the stack answers: the previous build's Included(), the reason
# a move failed, the session a chat's Pairing row names, the number of messages the mock got for the chat before and after the
# notification, and the reason a notification was not sent.
pairing_stubs() {
  wait_until() { shift; "$@"; }
  PAIR_WAIT=1
  pairing_build_included() { echo "${STUB_INC-}"; }
  pairing_move() { echo "${STUB_MOVE_WHY-}"; }
  pairing_session_of() { echo "${STUB_SESSION-}"; }
  pairing_replies() {
    local n
    n=$(cat "$state/replies.n" 2> /dev/null || echo 0)
    echo "$((n + 1))" > "$state/replies.n"
    if [ "$n" -eq 0 ]; then echo "${STUB_BEFORE-3}"; else echo "${STUB_AFTER-4}"; fi
  }
  pairing_notify() { echo "${STUB_NOTIFY_WHY-}"; }
}
pairing_fresh() { # pairing_fresh: an empty state and results
  state=$tmp/pairing-state
  rm -rf "$state"
  mkdir -p "$state"
  results=$state/results
  : > "$results"
  : > "$state/seed.env"
  : > "$state/upgrade.env"
  fails=0
  seeding=0
  cur_row=""
}
pairing_lines() { grep -c "^RECORD pairing $1 " "$results" 2> /dev/null; }

t_pairing() {
  local bad=0
  pairing_stubs

  # The seed: nothing on a previous build that does not include Telegram, a paired chat on one that does.
  pairing_fresh
  seeding=1
  STUB_INC=0 seed_pairing > /dev/null
  eq "a previous build without Telegram: no chat is seeded" "$(env_get "$state/seed.env" pair_chat)" ""
  eq "and the seed remembers that it did not include Telegram" "$(env_get "$state/seed.env" prev_telegram)" 0
  eq "and writes no seed line" "$(pairing_lines seed)" 0
  pairing_fresh
  seeding=1
  STUB_INC=1 STUB_SESSION=zzsession1 seed_pairing > /dev/null
  eq "a previous build with Telegram: the chat is seeded" "$(env_get "$state/seed.env" pair_chat)" 84017734150
  eq "with its session" "$(env_get "$state/seed.env" pair_session)" zzsession1
  eq "and a seed line, which is no check" "$(pairing_lines seed)" 1
  pairing_fresh
  seeding=1
  STUB_INC=1 STUB_MOVE_WHY="no long poll is open" seed_pairing > /dev/null
  eq "a move that fails fails the seed" "$(pairing_lines fail)" 1

  # The upgrade part: a note without a seeded chat, the checks with one.
  pairing_fresh
  env_set "$state/seed.env" prev_telegram 0
  check_pairing_upgrade > /dev/null
  eq "an older previous build: the note says the upgrade part joins later" "$(grep -c "^RECORD pairing note $PAIRING_UPGRADE_NOTE\$" "$results")" 1
  eq "and nothing is checked" "$(pairing_lines pass)$(pairing_lines fail)" 00
  pairing_fresh
  env_set "$state/seed.env" prev_telegram 1
  env_set "$state/seed.env" pair_chat 84017734150
  env_set "$state/seed.env" pair_session zzsession1
  STUB_SESSION=zzsession1 check_pairing_upgrade > /dev/null
  eq "a seeded chat that still names its session and gets the notice: two passes" "$(pairing_lines pass)" 2
  eq "and no failure" "$(pairing_lines fail)" 0
  pairing_fresh
  env_set "$state/seed.env" prev_telegram 1
  env_set "$state/seed.env" pair_chat 84017734150
  env_set "$state/seed.env" pair_session zzsession1
  STUB_SESSION=zzother check_pairing_upgrade > /dev/null
  eq "a Pairing row that names another session fails" "$(pairing_lines fail)" 1
  pairing_fresh
  env_set "$state/seed.env" prev_telegram 1
  env_set "$state/seed.env" pair_chat 84017734150
  env_set "$state/seed.env" pair_session zzsession1
  STUB_SESSION=zzsession1 STUB_AFTER=3 check_pairing_upgrade > /dev/null
  eq "a notice that never reaches the mock fails" "$(pairing_lines fail)" 1
  pairing_fresh
  env_set "$state/seed.env" prev_telegram 1
  check_pairing_upgrade > /dev/null
  eq "a previous build with Telegram and no seeded chat fails" "$(pairing_lines fail)" 1

  # The candidate's chat, paired at the end of the upgrade phase.
  pairing_fresh
  STUB_SESSION=zzsession2 pair_candidate > /dev/null
  eq "the candidate's chat is kept for the restart" "$(env_get "$state/upgrade.env" pair_chat)" 84017734151
  eq "with its session" "$(env_get "$state/upgrade.env" pair_session)" zzsession2
  pairing_fresh
  STUB_MOVE_WHY="the mock did not accept the update" pair_candidate > /dev/null
  eq "a candidate chat that cannot be paired fails and keeps nothing" "$(pairing_lines fail)$(env_get "$state/upgrade.env" pair_chat)" 1

  # The restart part.
  pairing_fresh
  env_set "$state/upgrade.env" pair_chat 84017734151
  env_set "$state/upgrade.env" pair_session zzsession2
  STUB_SESSION=zzsession2 check_pairing_restart > /dev/null
  eq "after the restart the chat is paired and the notice arrives: two passes" "$(pairing_lines pass)" 2
  pairing_fresh
  env_set "$state/upgrade.env" pair_chat 84017734151
  env_set "$state/upgrade.env" pair_session zzsession2
  STUB_SESSION=zzsession2 STUB_AFTER=3 check_pairing_restart > /dev/null
  eq "after the restart a notice with no sendMessage at the mock fails" "$(pairing_lines fail)" 1
  pairing_fresh
  env_set "$state/upgrade.env" pair_chat 84017734151
  env_set "$state/upgrade.env" pair_session zzsession2
  STUB_SESSION="" check_pairing_restart > /dev/null
  eq "after the restart a chat that lost its pairing fails" "$(pairing_lines fail)" 1
  pairing_fresh
  env_set "$state/upgrade.env" pair_chat 84017734151
  env_set "$state/upgrade.env" pair_session zzsession2
  STUB_SESSION=zzsession2 STUB_NOTIFY_WHY="the session has no row" check_pairing_restart > /dev/null
  eq "a notification that cannot be sent fails" "$(pairing_lines fail)" 1
  pairing_fresh
  check_pairing_restart > /dev/null
  eq "no paired chat left by the upgrade fails" "$(pairing_lines fail)" 1

  # The phases' wiring: the three phases that read the pairing keep Telegram on from their first statement, and the upgrade phase pairs
  # the candidate's chat after its own check.
  for fn in phase_seed phase_upgrade phase_restart; do
    eq "$fn keeps Telegram on (LIVE_TELEGRAM=started) as its first statement" "$(declare -f "$fn" | sed -n 3p | tr -d ' ;')" "LIVE_TELEGRAM=started"
  done
  eq "phase_upgrade pairs the candidate's chat right after the upgrade check" "$(declare -f phase_upgrade | tr -s ' \t\n' ' ' | grep -c 'check_pairing_upgrade; pair_candidate;')" 1
  eq "phase_restart checks the pairing after the restart" "$(declare -f phase_restart | tr -s ' \t\n' ' ' | grep -c 'check_pairing_restart')" 1
  eq "phase_seed seeds the pairing" "$(declare -f phase_seed | tr -s ' \t\n' ' ' | grep -c 'seed_pairing')" 1
  [ "$bad" -eq 0 ]
}
b_pairing() { pairing_reached() { return 0; }; }

# --- memory and document (Story 19.5) ---

# The families over stubs of the stack's readings. STUB_BUILT is built_class's answer, STUB_TURN_RC the status of the memory-save turn, STUB_MEM the newest
# memory row ("<Ref>|<SessionRef>"), STUB_MFOUND the memory search (1 or 0), STUB_POST_CODE the POST /v1/documents status, STUB_DOCSTATE the state the list
# shows and STUB_DFOUND the document search ("ok" or its reason).
memdoc_stubs() {
  wait_until() { shift; "$@"; }
  built_class() { echo "${STUB_BUILT-}"; }
  run_turn() { # run_turn <clientId> <scenario> <text> <reply> <label>: the real one records its failure
    if [ "${STUB_TURN_RC-0}" != 0 ]; then
      fail "$5: the turn failed"
      return 1
    fi
    return 0
  }
  session_value() { # session_value <namespace> <name>
    local script
    script=$(cat)
    case $2 in
      mem) echo "${STUB_MEM-}" ;;
      found)
        case $script in
          *"Docs.Live"*) echo "${STUB_DFOUND-ok}" ;;
          *) echo "${STUB_MFOUND-1}" ;;
        esac
        ;;
    esac
  }
  api_post() {
    printf '{"result":"done","ref":"zzdoc1"}' > "$tmp/post.body"
    echo "${STUB_POST_CODE-200}"
  }
  api_get() {
    printf '{"documents":[{"ref":"zzdoc1","state":"%s"}]}' "${STUB_DOCSTATE-ready}" > "$tmp/get.body"
    echo 200
  }
}
md_lines() { grep -c "^RECORD $1 $2 " "$results" 2> /dev/null; }

t_memory_document() {
  local bad=0
  memdoc_stubs
  harness_root=$root
  jar=$tmp/jar
  key=zzkey

  # The seed: nothing on a previous build that cannot save a memory or index a document, the record on one that can.
  pairing_fresh
  seeding=1
  STUB_BUILT=0 seed_memory > /dev/null
  STUB_BUILT=0 seed_document > /dev/null
  eq "a previous build whose MemoryOps is a stub: no memory is seeded" "$(env_get "$state/seed.env" mem_ref)" ""
  eq "and the seed remembers that it was not built" "$(env_get "$state/seed.env" prev_memory)$(env_get "$state/seed.env" prev_document)" 00
  eq "likewise no document" "$(env_get "$state/seed.env" doc_ref)" ""
  eq "and nothing is recorded" "$(md_lines memory pass)$(md_lines memory fail)$(md_lines document pass)$(md_lines document fail)" 0000
  pairing_fresh
  seeding=1
  STUB_BUILT=1 STUB_MEM="zzmem1|zzsession1" seed_memory > /dev/null
  STUB_BUILT=1 seed_document > /dev/null
  eq "a previous build that saves memories: the memory and its session are seeded" "$(env_get "$state/seed.env" mem_ref)|$(env_get "$state/seed.env" mem_session)" "zzmem1|zzsession1"
  eq "and the document" "$(env_get "$state/seed.env" doc_ref)" zzdoc1
  eq "each seed writes one seed line, which is no check" "$(md_lines memory seed)$(md_lines document seed)$(md_lines memory pass)$(md_lines document pass)" 1100
  pairing_fresh
  seeding=1
  STUB_BUILT=1 STUB_TURN_RC=1 seed_memory > /dev/null
  STUB_BUILT=1 STUB_POST_CODE=501 seed_document > /dev/null
  eq "a turn that fails and a route that refuses fail the seeds" "$(md_lines memory fail)$(md_lines document fail)" 11
  eq "and seed nothing" "$(env_get "$state/seed.env" mem_ref)$(env_get "$state/seed.env" doc_ref)" ""
  pairing_fresh
  seeding=1
  STUB_BUILT=1 STUB_MEM="" seed_memory > /dev/null
  eq "a turn that saved no memory fails the seed" "$(md_lines memory fail)" 1
  pairing_fresh
  seeding=1
  STUB_BUILT="" seed_memory > /dev/null
  STUB_BUILT="" seed_document > /dev/null
  eq "an empty answer of built_class fails both seeds and is never 'not built'" "$(md_lines memory fail)$(md_lines document fail)|$(env_get "$state/seed.env" prev_memory)$(env_get "$state/seed.env" prev_document)" "11|"

  # The upgrade part: the note without a seed, the checks with one.
  pairing_fresh
  env_set "$state/seed.env" prev_memory 0
  env_set "$state/seed.env" prev_document 0
  check_memory_upgrade > /dev/null
  check_document_upgrade > /dev/null
  eq "an older previous build: the notes say the upgrade part joins later" "$(grep -c "^RECORD memory note $MEMORY_UPGRADE_NOTE\$" "$results")$(grep -c "^RECORD document note $DOCUMENT_UPGRADE_NOTE\$" "$results")" 11
  eq "and nothing is checked" "$(md_lines memory pass)$(md_lines memory fail)$(md_lines document pass)$(md_lines document fail)" 0000
  pairing_fresh
  env_set "$state/seed.env" prev_memory 1
  env_set "$state/seed.env" prev_document 1
  env_set "$state/seed.env" mem_ref zzmem1
  env_set "$state/seed.env" mem_session zzsession1
  env_set "$state/seed.env" doc_ref zzdoc1
  check_memory_upgrade > /dev/null
  check_document_upgrade > /dev/null
  eq "a seeded memory that is found: one pass" "$(md_lines memory pass)$(md_lines memory fail)" 10
  eq "a seeded document that is listed ready and found: two passes" "$(md_lines document pass)$(md_lines document fail)" 20
  pairing_fresh
  env_set "$state/seed.env" prev_memory 1
  env_set "$state/seed.env" prev_document 1
  env_set "$state/seed.env" mem_ref zzmem1
  env_set "$state/seed.env" mem_session zzsession1
  env_set "$state/seed.env" doc_ref zzdoc1
  STUB_MFOUND=0 check_memory_upgrade > /dev/null
  STUB_DFOUND="the search returned no passage of the document" check_document_upgrade > /dev/null
  eq "a search that misses the memory is a fail line" "$(md_lines memory fail)" 1
  eq "a search that misses the document is a fail line (its listing passed)" "$(md_lines document pass)$(md_lines document fail)" 11
  for answer in "" ok; do
    pairing_fresh
    env_set "$state/seed.env" prev_document 1
    env_set "$state/seed.env" doc_ref zzdoc1
    STUB_DFOUND=$answer check_document_upgrade > /dev/null
    eq "the search's answer '$answer': an empty one is a fail line and never found, a real one passes" "$(md_lines document pass)$(md_lines document fail)" "$([ -z "$answer" ] && echo 11 || echo 20)"
  done
  pairing_fresh
  env_set "$state/seed.env" prev_document 1
  env_set "$state/seed.env" doc_ref zzdoc1
  STUB_DOCSTATE=indexing check_document_upgrade > /dev/null
  eq "a document that is not listed ready fails and is not searched" "$(md_lines document fail)$(md_lines document pass)" 10
  pairing_fresh
  env_set "$state/seed.env" prev_memory 1
  env_set "$state/seed.env" prev_document 1
  check_memory_upgrade > /dev/null
  check_document_upgrade > /dev/null
  eq "a previous build that saves and indexes with nothing seeded fails" "$(md_lines memory fail)$(md_lines document fail)" 11

  # The candidate's records, made when the seed could not, and checked after the restart.
  pairing_fresh
  env_set "$state/seed.env" prev_memory 0
  env_set "$state/seed.env" prev_document 0
  STUB_MEM="zzmem2|zzsession2" memory_candidate > /dev/null
  document_candidate > /dev/null
  eq "the candidate's memory is made and kept for the restart" "$(env_get "$state/upgrade.env" mem_ref)|$(env_get "$state/upgrade.env" mem_session)" "zzmem2|zzsession2"
  eq "and its document" "$(env_get "$state/upgrade.env" doc_ref)" zzdoc1
  STUB_MFOUND=1 check_memory_restart > /dev/null
  check_document_restart > /dev/null
  eq "the candidate made both (a pass each) and after the restart both are found (one pass for the memory, two for the document)" "$(md_lines memory pass)$(md_lines document pass)" 23
  pairing_fresh
  env_set "$state/seed.env" prev_memory 1
  env_set "$state/seed.env" prev_document 1
  memory_candidate > /dev/null
  document_candidate > /dev/null
  eq "records seeded on the previous build are not made again on the candidate" "$(env_get "$state/upgrade.env" mem_ref)$(env_get "$state/upgrade.env" doc_ref)" ""
  env_set "$state/seed.env" mem_ref zzmem1
  env_set "$state/seed.env" mem_session zzsession1
  env_set "$state/seed.env" doc_ref zzdoc1
  check_memory_restart > /dev/null
  check_document_restart > /dev/null
  eq "and the restart checks the seeded ones" "$(md_lines memory pass)$(md_lines document pass)" 12
  pairing_fresh
  STUB_MFOUND=0 check_memory_restart > /dev/null
  check_document_restart > /dev/null
  eq "no record to check after the restart fails both rows" "$(md_lines memory fail)$(md_lines document fail)" 11
  pairing_fresh
  env_set "$state/upgrade.env" mem_ref zzmem2
  env_set "$state/upgrade.env" mem_session zzsession2
  env_set "$state/upgrade.env" doc_ref zzdoc1
  STUB_MFOUND=0 STUB_DOCSTATE=failed check_memory_restart > /dev/null
  STUB_MFOUND=0 STUB_DOCSTATE=failed check_document_restart > /dev/null
  eq "after the restart a lost memory and a document that is no longer ready fail" "$(md_lines memory fail)$(md_lines document fail)" 11

  # The phases' wiring.
  eq "phase_seed seeds the memory and the document" "$(declare -f phase_seed | tr -s ' \t\n' ' ' | grep -c 'if family_on memory; then seed_memory; fi; if family_on document; then seed_document; fi;')" 1
  eq "phase_upgrade checks both and makes the candidate's" "$(declare -f phase_upgrade | tr -s ' \t\n' ' ' | grep -c 'check_memory_upgrade; memory_candidate; fi; if family_on document; then check_document_upgrade; document_candidate; fi;')" 1
  eq "phase_restart checks both" "$(declare -f phase_restart | tr -s ' \t\n' ' ' | grep -c 'if family_on memory; then check_memory_restart; fi; if family_on document; then check_document_restart; fi;')" 1
  on=off
  rows=short
  case " $HARNESS_ON " in *" memory document "*) on=on ;; esac
  case "$HARNESS_ROWS" in *" pairing memory document") rows=rows ;; esac
  eq "the families are on and the rows end with memory and document" "$on$rows" onrows
  [ "$bad" -eq 0 ]
}
b_memory_document() { document_found() { echo; }; memory_found() { echo 1; }; }

# --- stale files (Story 36.7, DW-1320) ---

# sf_check <when>: check_stale_files over stubs of its three readers; STUB_BUILD and STUB_SERVED are the lists (words), STUB_PLANT and STUB_MAIN the
# statuses. Prints its PASS and FAIL lines, then the RECORD lines of the row.
sf_check() {
  local when=$1
  results=$tmp/sf.results
  : > "$results"
  build_tree() { local f; for f in ${STUB_BUILD-./index.html ./main-AB12CD34.js ./chunk-EF56GH78.js}; do echo "$f"; done; }
  served_tree() { local f; for f in ${STUB_SERVED-./index.html ./main-AB12CD34.js ./chunk-EF56GH78.js}; do echo "$f"; done; }
  web_status() { case $1 in "$STALE_PLANT") echo "${STUB_PLANT-404}" ;; *) echo "${STUB_MAIN-200}" ;; esac; }
  check_stale_files "$when"
  cat "$results"
}

t_stale_files() {
  local bad=0 a=$tmp/sf.a b=$tmp/sf.b out re plant_hash
  printf '%s\n' ./index.html ./main-AB12CD34.js ./chunk-EF56GH78.js > "$a"

  # stale_compare
  printf '%s\n' ./chunk-EF56GH78.js ./index.html ./main-AB12CD34.js > "$b"
  status_is "equal lists" 0 stale_compare "$a" "$b"
  eq "equal lists print nothing" "$(stale_compare "$a" "$b")" ""
  printf '%s\n' ./chunk-EF56GH78.js ./index.html ./main-AB12CD34.js ./main-JCJUH3RN.js > "$b"
  status_is "an extra file" 1 stale_compare "$a" "$b"
  eq "an extra file is named" "$(stale_compare "$a" "$b")" "EXTRA ./main-JCJUH3RN.js"
  printf '%s\n' ./index.html ./main-AB12CD34.js > "$b"
  status_is "a missing file" 1 stale_compare "$a" "$b"
  eq "a missing file is named" "$(stale_compare "$a" "$b")" "MISSING ./chunk-EF56GH78.js"
  printf '%s\n' ./index.html ./main-ZZSTALE0.js ./main-AB12CD34.js > "$b"
  eq "an extra and a missing file are both named" "$(stale_compare "$a" "$b" | tr '\n' ' ')" "EXTRA ./main-ZZSTALE0.js MISSING ./chunk-EF56GH78.js "
  : > "$a"
  status_is "an empty build list is refused, not a vacuous pass" 2 stale_compare "$a" "$b"
  has "and says why" "$(stale_compare "$a" "$b")" "empty"
  status_is "a missing build list is refused too" 2 stale_compare "$tmp/sf.none" "$b"
  printf '%s\n' ./index.html ./main-AB12CD34.js ./chunk-EF56GH78.js > "$a"
  : > "$b"
  status_is "an empty served list misses every build file" 1 stale_compare "$a" "$b"
  eq "the names list at most ten per kind" "$(stale_names "$(printf 'EXTRA ./x%s\n' 1 2 3 4 5 6 7 8 9 10 11 12)" EXTRA | wc -w | tr -d ' ')" 10

  # the plant
  re=$(sed -n 's/^Parameter STALEFILES = "\(.*\)";$/\1/p' src/ocutalon/cls/OcuTalon/Install/Step/Web.cls)
  [ -n "$re" ] || { echo "  STALEFILES could not be read from Web.cls"; bad=1; }
  if printf '%s\n' "$STALE_PLANT" | grep -Eq "$re"; then :; else echo "  the plant $STALE_PLANT does not match STALEFILES ($re)"; bad=1; fi
  plant_hash=${STALE_PLANT#main-}
  plant_hash=${plant_hash%.js}
  case $plant_hash in
    *[!A-Z2-7]*) ;;
    *) echo "  the plant's hash $plant_hash is inside esbuild's alphabet"; bad=1 ;;
  esac

  # the placement
  case " $HARNESS_ON " in *" stale-files "*) ;; *) echo "  stale-files is not in HARNESS_ON"; bad=1 ;; esac
  case "$HARNESS_ROWS" in *" private-globals stale-files pairing memory document") ;; *) echo "  HARNESS_ROWS lacks ' private-globals stale-files pairing memory document' at its end"; bad=1 ;; esac
  eq "phase_seed plants" "$(declare -f phase_seed | tr -s ' \t\n' ' ' | grep -c 'if family_on stale-files; then seed_stale_files; fi;')" 1
  eq "phase_upgrade checks after the families" "$(declare -f phase_upgrade | tr -s ' \t\n' ' ' | grep -c 'if family_on stale-files; then check_stale_files upgrade; fi; logout_all')" 1
  eq "phase_restart checks" "$(declare -f phase_restart | tr -s ' \t\n' ' ' | grep -c 'if family_on stale-files; then check_stale_files restart; fi; logout_all')" 1

  # check_stale_files
  out=$(sf_check upgrade)
  has "upgrade, equal lists: the list line" "$out" "PASS after the upgrade the served web folder holds exactly the candidate's 3 build files"
  has "upgrade: the status line" "$out" "PASS after the upgrade /ocutalon/main-ZZSTALE0.js answers 404 and /ocutalon/main-<hash>.js 200"
  eq "upgrade: two pass records" "$(printf '%s\n' "$out" | grep -c '^RECORD stale-files pass ')" 2
  lacks "upgrade: no fail" "$out" "FAIL"
  out=$(sf_check restart)
  has "restart, equal lists" "$out" "PASS after the restart the served web folder holds exactly the candidate's 3 build files"
  eq "restart: one pass record, and no status check" "$(printf '%s\n' "$out" | grep -c '^RECORD stale-files pass ')" 1
  out=$(STUB_SERVED="./index.html ./main-AB12CD34.js ./chunk-EF56GH78.js ./main-JCJUH3RN.js ./main-ZZSTALE0.js" sf_check upgrade)
  has "extra files are named" "$out" "FAIL after the upgrade the served web folder differs from the candidate's build output (3 files): extra ./main-JCJUH3RN.js ./main-ZZSTALE0.js"
  has "and recorded" "$out" "RECORD stale-files fail after the upgrade the served web folder differs"
  out=$(STUB_SERVED="./index.html ./main-AB12CD34.js" sf_check restart)
  has "a missing file is named" "$out" "FAIL after the restart the served web folder differs from the candidate's build output (3 files): missing ./chunk-EF56GH78.js"
  out=$(STUB_SERVED="./index.html ./main-AB12CD34.js ./main-ZZSTALE0.js" sf_check upgrade)
  has "extra and missing in one line" "$out" "(3 files): extra ./main-ZZSTALE0.js missing ./chunk-EF56GH78.js"
  out=$(STUB_PLANT=200 sf_check upgrade)
  has "a plant that is served is a fail" "$out" "FAIL after the upgrade /ocutalon/main-ZZSTALE0.js answers '200' (wanted 404)"
  out=$(STUB_MAIN=404 sf_check upgrade)
  has "a main script that is not served is a fail" "$out" "answers '404' (wanted 200)"
  out=$(STUB_BUILD="" sf_check upgrade)
  has "an empty build output is a fail" "$out" "FAIL after the upgrade the candidate's build output src/ocutalon/csp has no file"
  lacks "and no pass line" "$out" "PASS"

  # seed_stale_files
  results=$tmp/sf.results
  : > "$results"
  seeding=1
  stale_plant() { return 0; }
  out=$(seed_stale_files)
  has "the plant: the seed line" "$out" "PASS stale files: main-ZZSTALE0.js is planted in the served folder"
  has "the plant: the note says it is planted and that every mode plants" "$out" "INFO main-ZZSTALE0.js was planted in the served folder before the upgrade, standing in for an earlier upgrade's leftover; every mode plants it"
  eq "the plant: a seed record and a note, and no pass record" "$(grep -c '^RECORD stale-files \(seed\|note\) ' "$results")$(grep -c '^RECORD stale-files pass ' "$results")" 20
  : > "$results"
  stale_plant() { return 1; }
  out=$(seed_stale_files)
  has "a plant that fails is a fail line" "$out" "FAIL stale files: main-ZZSTALE0.js could not be planted"
  seeding=0
  : > "$results"
  printf 'RECORD stale-files seed planted\nRECORD stale-files note %s\nRECORD stale-files pass one\nRECORD stale-files pass two\nRECORD stale-files pass three\n' "$STALE_NOTE" > "$results"
  write_options "$tmp/sf.options" tag v1.0.0 release
  has "the table row reads three checks and the plant note" "$(record_section "$results" "$tmp/sf.options")" "| stale files | pass | 3 checks passed; main-ZZSTALE0.js was planted in the served folder before the upgrade, standing in for an earlier upgrade's leftover; every mode plants it |"
  [ "$bad" -eq 0 ]
}
b_stale_files() { stale_compare() { return 0; }; }

# --- approval reject (Story 22.4, DW-1239) ---

# The approval family over stubs of the stack: STUB_FP1 and STUB_FP2 are the readings of ToolFingerprint of the two requests (default "=", empty),
# STUB_REJ_CODE and STUB_REJ_BODY the answer of the reject. The calls of api_post go to $tmp/api-calls (path and body).
approval_stubs() {
  wait_until() { shift; "$@"; }
  state_get() {
    cat > "$tmp/state.json" <<'EOS'
{"chat": [{"type": "incident", "payload": {"ref": "I1", "state": "resolved", "requests": [{"ref": "Q1", "state": "done", "result": {"total": 50, "completed": 50, "failedAgain": 0}}]}}],
 "rail": {"approvals": [{"ref": "Q1", "state": "pending", "expiresAt": "2026-11-02T00:00:00Z"}, {"ref": "Q2", "state": "pending", "expiresAt": "2026-11-02T00:00:00Z"}]},
 "phone": [{"text": "$TEXT_RESULT"}]}
EOS
    sed -i.bak "s|\$TEXT_RESULT|$TEXT_RESULT|" "$tmp/state.json" && rm -f "$tmp/state.json.bak"
  }
  approval_fingerprint() {
    case $1 in
      Q1) echo "${STUB_FP1-=}" ;;
      Q2) echo "${STUB_FP2-=}" ;;
    esac
  }
  approval_copy() { echo "${STUB_COPY-Q2}"; }
  approval_hold() { echo hold1; }
  api_post() {
    printf '%s %s\n' "$1" "$2" >> "$tmp/api-calls"
    case $1 in
      approvals/Q1/answer) printf '{"result":"done","approval":{"state":"approved"}}' > "$tmp/post.body"; echo 200 ;;
      *)
        if [ -n "${STUB_REJ_BODY-}" ]; then printf '%s' "$STUB_REJ_BODY" > "$tmp/post.body"; else printf '{"result":"done","approval":{"state":"rejected"}}' > "$tmp/post.body"; fi
        echo "${STUB_REJ_CODE-200}"
        ;;
    esac
  }
}
ap_lines() { grep -c "^RECORD approval $1 " "$results" 2> /dev/null; }
ap_check() { # ap_check: a fresh state with the seed of the two requests, then check_approval_upgrade
  pairing_fresh
  rm -f "$tmp/api-calls"
  req_ref=Q1 req_expires=2026-11-02T00:00:00Z rej_ref=${1-Q2} inc_ref=I1
  env_set "$state/seed.env" ok_approval 1
  check_approval_upgrade
}

t_approval_reject() {
  local bad=0
  approval_stubs
  harness_root=$root
  # the reject answer's reader: done with the request rejected, nothing else
  printf '{"result":"done","approval":{"state":"rejected"}}' > "$tmp/ans"
  status_is "an answer that is done and rejected" 0 answer_rejected "$tmp/ans"
  printf '{"result":"done","approval":{"state":"approved"}}' > "$tmp/ans"
  status_is "an answer that is done and approved" 1 answer_rejected "$tmp/ans"
  printf '{"result":"already_answered","approval":{"state":"rejected"}}' > "$tmp/ans"
  status_is "an answer that is not done" 1 answer_rejected "$tmp/ans"
  printf '{"error":{"code":"bad_answer"}}' > "$tmp/ans"
  status_is "the bad_answer error" 1 answer_rejected "$tmp/ans"
  printf 'not json' > "$tmp/ans"
  status_is "a body that is no JSON" 1 answer_rejected "$tmp/ans"
  status_is "a body that is not there" 1 answer_rejected "$tmp/no-such-answer"
  # the fingerprint reader: empty only
  status_is "an empty fingerprint" 0 fingerprint_empty "="
  status_is "a fingerprint with a value" 1 fingerprint_empty "=abc123"
  status_is "a fingerprint with a value, absent ok" 1 fingerprint_empty "=abc123" absent-ok
  status_is "no column is not empty after the upgrade" 1 fingerprint_empty "<nocolumn>"
  status_is "no column is empty before it (the previous build predates the property)" 0 fingerprint_empty "<nocolumn>" absent-ok
  status_is "no row" 1 fingerprint_empty "<norow>" absent-ok
  status_is "a failed read" 1 fingerprint_empty "<error>" absent-ok
  status_is "no reading" 1 fingerprint_empty "" absent-ok

  # the check after the upgrade: approve Q1, reject Q2, ToolFingerprint empty before the answers and after them
  ap_check
  eq "all good: six pass lines and no fail" "$(ap_lines pass)$(ap_lines fail)" 60
  eq "the approve is unchanged and the reject follows it with action and channel" "$(cat "$tmp/api-calls")" 'approvals/Q1/answer {"action":"approve","channel":"phone"}
approvals/Q2/answer {"action":"reject","channel":"web"}'
  STUB_FP2="=abc" ap_check
  eq "a fingerprint that is not empty fails after the upgrade and again after the answers" "$(ap_lines fail)" 2
  STUB_FP1="<nocolumn>" ap_check
  eq "a missing column after the upgrade fails (twice, as above)" "$(ap_lines fail)" 2
  STUB_REJ_CODE=409 ap_check
  eq "a reject that answers 409 is a fail line" "$(ap_lines fail)" 1
  STUB_REJ_BODY='{"result":"done","approval":{"state":"approved"}}' ap_check
  eq "a reject that answers 200 but leaves the request approved is a fail line" "$(ap_lines fail)" 1
  ap_check ""
  eq "no second request seeded: a fail line and nothing answered" "$(ap_lines fail)|$(cat "$tmp/api-calls" 2> /dev/null | wc -l | tr -d ' ')" "1|0"

  # the seed: a second pending request, then ToolFingerprint of both read empty (or no column yet) on the previous build
  pairing_fresh
  seeding=1 cur_row=approval
  req_ref=Q1 rej_ref=""
  seed_second_request > /dev/null
  eq "the seed raises the second request and records it" "$(env_get "$state/seed.env" rej_ref)|$(ap_lines seed)|$(ap_lines fail)" "Q2|2|0"
  pairing_fresh
  seeding=1 cur_row=approval
  req_ref=Q1 rej_ref=""
  STUB_FP1="<nocolumn>" STUB_FP2="<nocolumn>" seed_second_request > /dev/null
  eq "a previous build with no ToolFingerprint column: both read as empty" "$(ap_lines seed)|$(ap_lines fail)" "2|0"
  pairing_fresh
  seeding=1 cur_row=approval
  req_ref=Q1 rej_ref=""
  STUB_FP1="=zz" seed_second_request > /dev/null
  eq "a non-empty fingerprint before the upgrade is a fail line" "$(ap_lines fail)" 1
  pairing_fresh
  seeding=1 cur_row=approval
  req_ref=Q1 rej_ref=""
  STUB_COPY="" seed_second_request > /dev/null
  eq "a second request that cannot be raised is a fail line and nothing is stored" "$(ap_lines fail)|$(env_get "$state/seed.env" rej_ref)" "1|"
  [ "$bad" -eq 0 ]
}
b_approval_reject() { answer_rejected() { return 0; }; fingerprint_empty() { return 0; }; }

# --- run ---

# The harness's run command chains its phases as processes of itself. Here harness_root points at a folder whose release/upgrade-harness.sh
# is a stub that logs the phase, its arguments and the run tag, and fails for the phases named in STUB_FAIL.
make_run_stub() { # make_run_stub <root>
  mkdir -p "$1/release"
  cat > "$1/release/upgrade-harness.sh" << 'STUB'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$1" "$*" "${OCUTALON_RUN_TAG:-}" >> "$STUB_LOG"
case " ${STUB_FAIL:-} " in *" $1 "*) exit "${STUB_FAIL_RC:-1}" ;; esac
exit 0
STUB
}

run_with_stub() { # run_with_stub <fail phases> <fail rc> <cmd_run arguments...>: prints the exit status; the stub's log is in $STUB_LOG
  local fail=$1 frc=$2
  shift 2
  : > "$STUB_LOG"
  (
    harness_root=$tmp/run-root
    STUB_FAIL=$fail STUB_FAIL_RC=$frc
    export STUB_LOG STUB_FAIL STUB_FAIL_RC
    cmd_run "$@" > /dev/null 2>&1
  )
  echo $?
}

phases_logged() { cut -d'|' -f1 "$STUB_LOG" | tr '\n' ' '; }

t_run() {
  local bad=0 rc tag1 tag2
  STUB_LOG=$tmp/run-stub.log
  make_run_stub "$tmp/run-root"

  rc=$(unset OCUTALON_RUN_TAG; run_with_stub "" 1 --rc 3)
  eq "a run in which every phase passes exits 0" "$rc" 0
  eq "the phases run in order, ending with report and down" "$(phases_logged)" "build settings seed upgrade restart storage report down "
  eq "build gets the options and no phase gets any" "$(cut -d'|' -f2 "$STUB_LOG" | tr '\n' ',')" "build --rc 3,settings,seed,upgrade,restart,storage,report,down,"
  tag1=$(cut -d'|' -f3 "$STUB_LOG" | sort -u)
  case $tag1 in
    upg-[0-9]*) ;;
    *)
      echo "  the default tag '$tag1' is not upg-<epoch>"
      bad=1
      ;;
  esac
  eq "every phase of a run has the same tag" "$(cut -d'|' -f3 "$STUB_LOG" | sort -u | wc -l | tr -d ' ')" 1

  rc=$(OCUTALON_RUN_TAG=mine-1 run_with_stub "" 1 --version 1.0.1 --rc 2 --previous HEAD~1 --rehearsal --record rec/out.md)
  eq "a given tag is kept" "$(cut -d'|' -f3 "$STUB_LOG" | sort -u)" mine-1
  has "every option reaches build" "$(head -n 1 "$STUB_LOG")" "build --version 1.0.1 --rc 2 --previous HEAD~1 --rehearsal --record $harness_caller_pwd/rec/out.md|mine-1"

  rc=$(run_with_stub "seed" 1 --rc 3)
  eq "a failed phase makes the run exit 1" "$rc" 1
  eq "a failed phase does not stop the rest, and report and down still run" "$(phases_logged)" "build settings seed upgrade restart storage report down "
  rc=$(run_with_stub "report" 1 --rc 3)
  eq "a failed report makes the run exit 1" "$rc" 1
  eq "down runs after a failed report" "$(phases_logged | awk '{ print $NF }')" down
  rc=$(run_with_stub "settings upgrade restart storage" 1 --rc 3)
  eq "several failed phases exit 1" "$rc" 1
  eq "report and down run after several failures" "$(phases_logged | awk '{ print $(NF-1), $NF }')" "report down"

  rc=$(run_with_stub "build" 2 --rc 3)
  eq "a refused build makes the run exit 2" "$rc" 2
  eq "after a refused build only down runs" "$(phases_logged)" "build down "
  rc=$(run_with_stub "build" 1 --rc 3)
  eq "a failed build exits 2 as well" "$rc" 2
  eq "after a failed build only down runs" "$(phases_logged)" "build down "

  rc=$(run_with_stub "" 1 --bogus)
  eq "a bad option exits 2" "$rc" 2
  eq "a bad option starts no phase" "$(phases_logged)" ""
  rc=$(run_with_stub "" 1)
  eq "no --rc and no --record exits 2" "$rc" 2
  eq "that starts no phase either" "$(phases_logged)" ""
  rc=$(run_with_stub "" 1 --rc 0)
  eq "--rc 0 exits 2" "$rc" 2
  eq "that starts no phase" "$(phases_logged)" ""
  [ "$bad" -eq 0 ]
}
# The break: a run that never ends with down.
b_run() {
  eval "$(declare -f cmd_run | sed '1s/^cmd_run/orig_cmd_run/; s/^    bash "\$me" down;$/    :;/')"
  cmd_run() { orig_cmd_run "$@"; }
}

# --- report ---

# The report and upgrade commands over a state folder this rule fabricates (TMPDIR in the test's folder; no container): report joins
# every phase's results, fails the row of a phase that started and did not end, and exits 1 on any failure; upgrade is refused while
# seed is not done.
report_state() { # report_state <tag>: a state folder with every phase done and passing results
  local s ph
  s=$(TMPDIR=$tmp/rs state_dir "$1")
  rm -rf "$s"
  mkdir -p "$s"
  write_options "$s/options" tag v1.0.0 release
  env_set "$s/options" record "$tmp/rs-$1.md"
  write_results "$s/results.build" pass
  for ph in build settings seed upgrade restart storage; do printf 'done 1\n' > "$s/phase.$ph"; done
}
run_cmd_phase() { # run_cmd_phase <tag> <phase>: the phase command on that tag's state; its output, then "status <n>"
  (
    TMPDIR=$tmp/rs OCUTALON_RUN_TAG=$1
    export TMPDIR OCUTALON_RUN_TAG
    cmd_phase "$2" 2>&1
  )
  echo "status $?"
}

t_report() {
  local bad=0 s out
  mkdir -p "$tmp/rs"
  report_state rs-pass
  out=$(run_cmd_phase rs-pass report)
  has "report on passing results exits 0" "$out" "status 0"
  has "its record reads pass" "$(cat "$tmp/rs-rs-pass.md" 2> /dev/null)" "Result: pass"

  report_state rs-cut
  s=$(TMPDIR=$tmp/rs state_dir rs-cut)
  printf 'failed 0\n' > "$s/phase.restart"
  out=$(run_cmd_phase rs-cut report)
  has "report after a phase that did not end exits 1" "$out" "status 1"
  has "its record reads fail" "$(cat "$tmp/rs-rs-cut.md" 2> /dev/null)" "Result: fail"
  has "the unfinished phase's row fails" "$(cat "$tmp/rs-rs-cut.md" 2> /dev/null)" "| restart | fail |"

  report_state rs-fail
  s=$(TMPDIR=$tmp/rs state_dir rs-fail)
  write_results "$s/results.upgrade" fail
  : > "$s/results.build"
  out=$(run_cmd_phase rs-fail report)
  has "report after a failed check exits 1" "$out" "status 1"
  has "a later phase's results reach the record" "$(cat "$tmp/rs-rs-fail.md" 2> /dev/null)" "| watch | fail |"

  report_state rs-order
  s=$(TMPDIR=$tmp/rs state_dir rs-order)
  rm -f "$s/phase.seed" "$s/phase.upgrade" "$s/phase.restart" "$s/phase.storage"
  out=$(run_cmd_phase rs-order upgrade)
  has "upgrade with build done and seed not done exits 2" "$out" "status 2"
  has "it names the missing phase" "$out" "REFUSED upgrade: seed is not done"
  [ "$bad" -eq 0 ]
}
b_report() { unfinished_phase_lines() { :; }; }

# --- merge-retries ---

t_merge_retries() {
  local bad=0 r=$tmp/mr-results o=$tmp/mr-options sec out s want

  # The helper: the count of the current start's STEP merge RETRY lines, with the start's label, appended to the results.
  : > "$r"
  (
    results=$r
    start_log() { printf 'AFTER-START begin x\nSTEP merge OK 9s\nRESULT OK 0.1.0\n'; }
    count_merge_retries "settings project, previous build"
    start_log() { printf 'STEP merge RETRY 1 after #453\nSTEP merge OK 9s\n'; }
    count_merge_retries "records project, restart"
    start_log() { printf 'STEP merge RETRY 1 after #453\nSTEP merge RETRY 2 after #453\n'; }
    count_merge_retries "records project, candidate"
  )
  eq "the helper appends one line per start, with its count and label" "$(cat "$r")" "MERGE-RETRIES 0 settings project, previous build
MERGE-RETRIES 1 records project, restart
MERGE-RETRIES 2 records project, candidate"
  eq "the helper's lines are no record row" "$(record_rows "$r" | awk -F'\t' '$3 != "not run" { n++ } END { print n + 0 }')" 0

  # ready_or_die counts a start's retries whether or not it ended ready, and before its die.
  : > "$r"
  (
    results=$r
    start_log() { printf 'STEP merge RETRY 1 after #453\nSTEP merge OK 9s\n'; }
    wait_started_ready() { return 0; }
    die() { echo "die: $1" >> "$r"; }
    ready_or_die "records project, previous build" 400
    wait_started_ready() { return 1; }
    ready_or_die "settings project, candidate" 400
  ) > /dev/null
  eq "ready_or_die counts a ready start, and a start that was not ready before its die" "$(cat "$r")" "MERGE-RETRIES 1 records project, previous build
MERGE-RETRIES 1 settings project, candidate
die: settings project, candidate: the start did not end ready within 400 s"

  # The upgrade's and the restart's own waits (phase_upgrade and phase_restart run over stubs, no Docker): the start's retries are
  # counted whether the start ended ready or not, and in the not-ready case before the die. The stubbed die and the stubbed step that
  # follows the wait (the upgrade's env_set; the restart's keys check, after its marker check, which the stubs let through) both leave the
  # subshell, so a count placed after them, or left out, shows as a missing results line. Straight after the wait is the source pins' part.
  mkdir -p "$tmp/mr-state/p1"
  printf '%s\n' 'x/context.yml' > "$tmp/mr-state/p1/files"
  mr_phase() { # mr_phase <phase> <wait status>: the phase over stubs, its results file on stdout
    : > "$r"
    (
      results=$r state=$tmp/mr-state
      row() { :; }; attach_stack() { :; }; preflight() { :; }; load_seed() { :; }; opt() { echo 9.9.9; }
      env_get() { :; }; env_set() { echo "past: env_set" >> "$r"; exit 3; }; marker() { :; }; fail() { :; }; pass() { :; }; keys_point() { echo 0; }
      dc() { case $* in "ps -q iris") echo cid ;; esac; }
      live_pop_file() { :; }; live_track_image() { :; }
      start_log() { printf 'STEP merge RETRY 1 after #453\nSTEP merge OK 9s\n'; }
      wait_started_ready() { return "$waited"; }
      die() { echo "die: $1" >> "$r"; exit 1; }
      waited=$2
      "phase_$1"
    ) > /dev/null 2>&1
    cat "$r"
  }
  eq "the restart counts a ready start before its next step" "$(mr_phase restart 0)" "MERGE-RETRIES 1 records project, restart
die: restart: the runners' keys could not be pointed at the mock"
  eq "the restart counts a start that was not ready before its die" "$(mr_phase restart 1)" "MERGE-RETRIES 1 records project, restart
die: restart: the container was not ready within 300 s"
  eq "the upgrade counts a ready start before its next step" "$(mr_phase upgrade 0)" "MERGE-RETRIES 1 records project, candidate
past: env_set"
  eq "the upgrade counts a start that was not ready before its die" "$(mr_phase upgrade 1)" "MERGE-RETRIES 1 records project, candidate
die: upgrade: the candidate did not end ready within 400 s"

  # The five starts each count right after their wait, before any die.
  eq "ready_or_die serves three starts" "$(grep -c '^  ready_or_die "' release/upgrade-harness.sh)" 3
  eq "the upgrade's wait is followed by its count" "$(grep -A1 'wait_started_ready 400 || ready=1' release/upgrade-harness.sh | tail -n 1)" '  count_merge_retries "records project, candidate"'
  eq "the restart's wait is followed by its count" "$(grep -A1 'wait_started_ready 300 || ready=1' release/upgrade-harness.sh | tail -n 1)" '  count_merge_retries "records project, restart"'
  eq "ready_or_die counts straight after its wait" "$(grep -A1 'wait_started_ready "\$2" || ready=1' release/upgrade-harness.sh | tail -n 1)" '  count_merge_retries "$1"'

  # The section: Merge retries: right after Run:, 0 with no line (a dry run included), the sum otherwise; nothing else changes.
  write_options "$o" tag v1.0.0 release
  write_results "$r" pass
  sec=$(record_section "$r" "$o")
  has "no MERGE-RETRIES line reads 0" "$sec" "Merge retries: 0"
  eq "the line follows Run:" "$(printf '%s\n' "$sec" | grep -A1 '^Run: ' | tail -n 1)" "Merge retries: 0"
  want=$(printf '%s\n' "$sec" | grep -v '^Merge retries: ')
  printf 'MERGE-RETRIES 0 settings project, candidate\nMERGE-RETRIES 1 records project, restart\nMERGE-RETRIES 2 records project, candidate\n' >> "$r"
  sec=$(record_section "$r" "$o")
  has "lines of 0, 1 and 2 read 3" "$sec" "Merge retries: 3"
  lacks "the total is no longer 0" "$sec" "Merge retries: 0"
  eq "the section is otherwise unchanged" "$(printf '%s\n' "$sec" | grep -v '^Merge retries: ')" "$want"
  has "Result: is unchanged" "$sec" "Result: pass"
  has "a dry run reads 0" "$(record_section /dev/null "$o")" "Merge retries: 0"

  # The report: the total before RECORD and RESULT, which stays last.
  mkdir -p "$tmp/rs"
  report_state rs-mr
  s=$(TMPDIR=$tmp/rs state_dir rs-mr)
  printf 'MERGE-RETRIES 0 settings project, candidate\n' > "$s/results.settings"
  printf 'MERGE-RETRIES 1 records project, restart\nMERGE-RETRIES 2 records project, candidate\n' > "$s/results.restart"
  rm -f "$tmp/rs-rs-mr.md" # the break run's record is no evidence for this run
  out=$(run_cmd_phase rs-mr report)
  eq "report prints the total before RECORD and RESULT" "$(printf '%s\n' "$out" | grep -v '^PHASE' | awk '{ if ($1 == "MERGE-RETRIES") print $1 " " $2; else print $1 }')" "MERGE-RETRIES 3
RECORD
RESULT
status"
  has "report's record holds the total" "$(cat "$tmp/rs-rs-mr.md" 2> /dev/null)" "Merge retries: 3"
  has "its Result: is unchanged" "$(cat "$tmp/rs-rs-mr.md" 2> /dev/null)" "Result: pass"
  [ "$bad" -eq 0 ]
}
b_merge_retries() { count_merge_retries() { printf 'MERGE-RETRIES 0 %s\n' "$1" >> "${results:-/dev/null}"; }; }

# --- previous-dockerfile ---

t_previous_dockerfile() {
  local bad=0 d out line

  # mk_prev <dir> <file>...: a tree holding the files
  mk_prev() {
    local dir=$1 f
    shift
    rm -rf "$dir"
    mkdir -p "$dir"
    for f in "$@"; do
      mkdir -p "$dir/$(dirname "$f")"
      echo x > "$dir/$f"
    done
  }

  # The helper: the root Dockerfile, else docker/Dockerfile; 1 for neither.
  mk_prev "$tmp/pd-root" Dockerfile src/module.xml
  eq "root only" "$(previous_dockerfile "$tmp/pd-root")" "Dockerfile"
  mk_prev "$tmp/pd-old" docker/Dockerfile src/module.xml
  eq "the v1.0.4 layout" "$(previous_dockerfile "$tmp/pd-old")" "docker/Dockerfile"
  mk_prev "$tmp/pd-both" Dockerfile docker/Dockerfile src/module.xml
  eq "both: the root one" "$(previous_dockerfile "$tmp/pd-both")" "Dockerfile"
  mk_prev "$tmp/pd-none" src/module.xml
  status_is "neither" 1 previous_dockerfile "$tmp/pd-none"
  eq "neither prints nothing" "$(previous_dockerfile "$tmp/pd-none")" ""

  # add_previous_context: the dockerfile: line of context.yml names the previous tree's Dockerfile.
  for d in root old both; do
    case $d in
      root) mk_prev "$tmp/pd-state-$d/previous" Dockerfile src/module.xml ;;
      old) mk_prev "$tmp/pd-state-$d/previous" docker/Dockerfile src/module.xml ;;
      both) mk_prev "$tmp/pd-state-$d/previous" Dockerfile docker/Dockerfile src/module.xml ;;
    esac
    mkdir -p "$tmp/pd-ctx-$d"
    out=$(
      state=$tmp/pd-state-$d tmp=$tmp/pd-ctx-$d
      live_add_file() { :; }
      add_previous_context
      sed -n 's/^ *dockerfile: //p' "$tmp/context.yml"
    )
    case $d in
      old) line=docker/Dockerfile ;;
      *) line=Dockerfile ;;
    esac
    eq "context.yml of the $d layout" "$out" "$line"
  done
  mk_prev "$tmp/pd-state-none/previous" src/module.xml
  mkdir -p "$tmp/pd-ctx-none"
  out=$(
    state=$tmp/pd-state-none tmp=$tmp/pd-ctx-none pl_prev_sha=abc123
    live_add_file() { echo "added"; }
    die() { echo "die: $1"; exit 3; }
    add_previous_context
  )
  eq "add_previous_context dies for neither" "$out" "die: previous build: the exported tree of abc123 has no src/module.xml, or neither Dockerfile nor docker/Dockerfile"

  # phase_build, run from a synthetic repository; the stubs stop it right after the export check.
  pd_phase() { # pd_phase <name> <file>...: a repository committed with the files; the phase's one line on stdout
    local name=$1 repo=$tmp/pd-repo-$name f
    shift
    ginit "$repo"
    for f in "$@"; do
      mkdir -p "$repo/$(dirname "$f")"
      echo x > "$repo/$f"
    done
    echo y > "$repo/f.txt"
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m one
    (
      cd "$repo" || exit 1
      state=$tmp/pd-phase-$name pl_prev_sha=$(git rev-parse HEAD) pl_prev_kind=pre-release pl_prev_version=0.0.1 pl_stamp=
      rm -rf "$state"
      row() { :; }
      pass() { echo "pass: $1"; exit 0; }
      die() { echo "die: $1"; exit 3; }
      phase_build
    )
  }
  out=$(pd_phase root Dockerfile src/module.xml)
  has "phase_build, root layout" "$out" "pass: previous build: the tree of the pre-release build"
  out=$(pd_phase old docker/Dockerfile src/module.xml)
  has "phase_build, old layout" "$out" "pass: previous build: the tree of the pre-release build"
  out=$(pd_phase none src/module.xml)
  has "phase_build, neither Dockerfile" "$out" "has no src/module.xml, or neither Dockerfile nor docker/Dockerfile"
  lacks "phase_build, neither Dockerfile: no pass line" "$out" "pass:"
  out=$(pd_phase nomanifest Dockerfile)
  has "phase_build, a Dockerfile and no src/module.xml" "$out" "has no src/module.xml, or neither Dockerfile nor docker/Dockerfile"
  lacks "phase_build, no manifest: no pass line" "$out" "pass:"
  [ "$bad" -eq 0 ]
}
b_previous_dockerfile() { previous_dockerfile() { echo docker/Dockerfile; }; }

rule resolve-previous t_resolve b_resolve
rule stamp-mode t_stamp_mode b_stamp_mode
rule phase-ready t_phase_ready b_phase_ready
rule reminder-expect t_reminder b_reminder
rule state-readers t_state_readers b_state_readers
rule chat-request t_chat_request b_chat_request
rule storage-compare t_storage b_storage
rule record t_record b_record
rule static t_static b_static
rule real-previous t_real_previous
rule real-tree t_real b_real
rule storage-base t_storage_base b_storage_base
rule record-contract t_record_contract b_record_contract
rule pairing t_pairing b_pairing
rule memory-document t_memory_document b_memory_document
rule approval-reject t_approval_reject b_approval_reject
rule stale-files t_stale_files b_stale_files
rule run t_run b_run
rule report t_report b_report
rule merge-retries t_merge_retries b_merge_retries
rule previous-dockerfile t_previous_dockerfile b_previous_dockerfile

if [ "$fails_total" -ne 0 ]; then
  echo "test-upgrade-harness: $fails_total rule(s) failed"
  exit 1
fi
echo "test-upgrade-harness: all rules passed"
