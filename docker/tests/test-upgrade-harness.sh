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
#   - record: the record section (the result, the mode, the pre-release note, the rows, pairing off) and its write (another section
#     kept, a section replaced and not duplicated);
#   - record-contract: what Stories 11.4 and 11.5 read from a record file: the section's lines in their fixed order, one Result:,
#     Mode: and Required: line from the closed set of values, read as a consumer reads them with other sections around, and a table of
#     three-cell ASCII rows;
#   - run: the run command chained over a stub of the harness: the phases in order, the options only on build, the tag shared, report and
#     down after any failed phase, and only down after a refused build;
#   - static: the harness holds no docker push, login, save or export, no compose config without --quiet and no inspect without
#     --format;
#   - real-tree: plan on this checkout writes a dry-run record, a version that is not the candidate's and a phase with no tag exit 2;
#   - storage-base: test-storage.sh judges this checkout's storage blocks against the pinned pre-release commit, so a non-appending
#     storage change since that commit fails this rule (a gate on the real tree), and the storage phase accepts only that verdict;
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
      for id in previous-build upgrade conversation reminder approval watch settings restart storage private-globals; do
        if [ "$2" = partial ] && [ "$id" = restart ]; then continue; fi
        if [ "$2" = partial ] && [ "$id" = storage ]; then continue; fi
        printf 'RECORD %s pass the first check of %s\nRECORD %s pass the second | check\n' "$id" "$id" "$id" >> "$f"
      done
      printf 'RECORD reminder note R1 fired late\n' >> "$f"
      if [ "$2" = fail ]; then printf 'RECORD watch fail Orders is not listed | really\nRECORD watch fail the press answered 409\n' >> "$f"; fi
      ;;
    pairing) printf 'RECORD pairing off held back\n' >> "$f" ;;
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
  eq "the table has a header, a separator and eleven rows" "$(printf '%s\n' "$sec" | grep -c '^| ')" 13
  eq "the rows are in order, pairing last" "$(printf '%s\n' "$sec" | sed -n 's/^| \([a-z ]*\) | [a-z ]* | .*/\1/p' | tr '\n' ',')" "previous build,upgrade,conversation,reminder,approval,watch,settings,restart,storage,private globals,pairing,"
  has "pairing is off in the table" "$sec" "| pairing | off | joins from the release after 1.0.0 (Story 12.7) |"
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
  eq "every row is not run but pairing" "$(printf '%s\n' "$sec" | grep -c '| not run | not run |')" 10

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
  printf 'RECORD pairing off held back\n' >> "$r"
  eq "pairing off is not counted" "$(record_result "$r")" pass
  printf 'RECORD pairing fail never\n' >> "$r"
  eq "a pairing failure line is not counted either" "$(record_result "$r")" pass

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

t_real() {
  local bad=0 rec=$tmp/real-record.md out
  if git rev-parse --verify --quiet 'HEAD~1^{commit}' > /dev/null; then
    out=$(run_plan --previous HEAD~1 --rc 1 --record "$rec" 2>&1)
    eq "plan --previous HEAD~1 exits 0" "$?" 0
    has "plan ends with RESULT not run" "$out" "RESULT not run"
    has "the record is a dry run" "$(cat "$rec" 2> /dev/null)" "Mode: dry run"
    has "the record's result is not run" "$(cat "$rec" 2> /dev/null)" "Result: not run"
    has "the record names the explicit previous build" "$(cat "$rec" 2> /dev/null)" "Previous: explicit HEAD~1 at "
    has "the record's candidate is this checkout's version" "$(cat "$rec" 2> /dev/null)" "Candidate: $(manifest_version src/module.xml) at $(git rev-parse HEAD)"
  else
    echo "  this checkout has no parent commit (a shallow clone): the plan with --previous HEAD~1 cannot run here"
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

  want_order="## Upgrade harness,Result,Mode,Required,Candidate,Previous,Note,Run,| Record"
  write_results "$r" pass
  write_options "$o" pre-release aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa release
  got_order=$(record_section "$r" "$o" | grep -E '^(## Upgrade harness|Result:|Mode:|Required:|Candidate:|Previous:|Note:|Run:|\| Record )' | sed 's/:.*//; s/ |.*$//' | tr '\n' ',')
  eq "the lines of a pre-release section are in the fixed order" "$got_order" "$want_order,"
  write_options "$o" tag v1.0.0 release
  got_order=$(record_section "$r" "$o" | grep -E '^(## Upgrade harness|Result:|Mode:|Required:|Candidate:|Previous:|Note:|Run:|\| Record )' | sed 's/:.*//; s/ |.*$//' | tr '\n' ',')
  eq "a tag section has the same order with no Note" "$got_order" "## Upgrade harness,Result,Mode,Required,Candidate,Previous,Run,| Record,"

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
  eq "the rows are the eleven records" "$v" 11
  [ "$bad" -eq 0 ]
}
b_record_contract() {
  eval "$(declare -f record_section | sed '1s/^record_section/orig_record_section/')"
  record_section() { orig_record_section "$@" | sed 's/^Mode: /Mode:/'; }
}

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

rule resolve-previous t_resolve b_resolve
rule stamp-mode t_stamp_mode b_stamp_mode
rule phase-ready t_phase_ready b_phase_ready
rule reminder-expect t_reminder b_reminder
rule state-readers t_state_readers b_state_readers
rule chat-request t_chat_request b_chat_request
rule storage-compare t_storage b_storage
rule record t_record b_record
rule static t_static b_static
rule real-tree t_real b_real
rule storage-base t_storage_base b_storage_base
rule record-contract t_record_contract b_record_contract
rule run t_run b_run
rule report t_report b_report

if [ "$fails_total" -ne 0 ]; then
  echo "test-upgrade-harness: $fails_total rule(s) failed"
  exit 1
fi
echo "test-upgrade-harness: all rules passed"
