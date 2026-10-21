#!/usr/bin/env bash
# The owner's inbox for an unattended /epic-cycle run (doctrine: _bmad/custom/epic-cycle-unattended.md, U12-U13).
#
# Cross-platform: Git Bash on Windows, bash 3.2+ on macOS/Linux; needs awk, sed, date, find, cmp, uname.
# Everything lives in the run state directory <state>, outside git's view (sequential: _bmad-output/unattended/,
# gitignored; orchestrator mode: <worktree_base>/.coordination/unattended/):
#   inbox.journal  append-only event log, one TAB-separated line per event -- the source of truth
#   inbox.md       rendered from the journal on every write -- the file people read; never edited by hand
#   run.lock       present while a run is live: run id, holder, host, heartbeat
#   HOLD           present while a hold is requested
# Only this script writes the journal and inbox.md. A hand edit of inbox.md is never applied: the next write saves
# it as inbox.md.edited-<UTC> (listed in the inbox) and re-renders. `verify` covers inbox.md only -- a determined
# agent with a shell can still run this script, which is why the doctrine never executes outward actions unattended.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: bash unattended-inbox.sh <state-dir> <command> [args]
  init <run-id>                  create the state directory, journal and inbox (idempotent; a new run id is recorded)
  add <kind> "<unit>" "<question>" "<options>" "<recommendation>" "<blocks>"
                                 add an item; prints U-<n>. kind: parked|stopped|veto|held-merge|hold|retro|report.
                                 A parked, stopped, held-merge or retro item is one per unit: an open one is reused
                                 ("U-<n> EXISTS"). veto, hold and report items are always added.
  answer U-<n> "<answer>" --by <who> [--quote "<the owner's words>"] [--via <channel>]
                                 record an answer; anyone but `owner` must pass --quote (a relay quotes the owner verbatim)
  answers                        answered, unresolved items: U-n TAB answer_ref TAB by TAB via TAB answer TAB quote
                                 (answer_ref = <UTC>#<journal line>: it names one answer exactly)
  resolve U-<n> <applied_by> <answer_ref|-> ["<note>"]
                                 mark an item resolved -- once. <answer_ref> must be the latest answer's (from `answers`),
                                 so an answer that arrived meanwhile is never silently dropped; `-` resolves an item nobody
                                 answered (a report, a hold)
  list [open|all]                U-n TAB kind TAB unit TAB state TAB question (default: open = not resolved)
  hold "<reason>"                request a hold (writes HOLD). Holds rank: the owner's (any reason not starting
                                 "auto:"), then "auto: time ...", then "auto: usage ..."; a weaker one never replaces a
                                 stronger one ("HOLD KEPT: <reason>")
  hold-clear "<reason>" [--usage-only]
                                 clear it (a resume does this after a hold); --usage-only (a relaunch) clears only an
                                 "auto: usage" hold and otherwise exits 5 with "HOLD KEPT: <reason>"
  run-status                     print the run lock with its heartbeat age; exit 3 if one exists, 0 ("none") if not
  run-start <run-id> <holder>    take the run lock and print `token=<t>`; exit 3 (printing it) if one exists
  run-takeover <run-id> <holder> "<reason>"
                                 replace a lock that names <run-id> (a resume) -- or, with reason "owner-confirmed ...",
                                 any lock; prints a new `token=<t>`, so the replaced session's next heartbeat fails.
                                 A takeover of the same run keeps its `started` (hold times count from it); an
                                 owner-confirmed one starts the clock again
  run-boundary <run-id> <token> "<where>"   heartbeat; refused (exit 4) unless the lock holds this run id AND token
  run-end <run-id> <token> "<reason>"       release the run lock; refused (exit 4) on any other run id or token
  verify                         exit 0 if inbox.md is exactly the journal's rendering, else 1
  render                         save any hand edit, then rebuild inbox.md from the journal
Values are single-line, contain no TAB, and the unit and question are non-empty; run ids and holders have no spaces.
EOF
  exit 1
}

STATE="${1:-}"; CMD="${2:-}"
[ -n "$STATE" ] && [ -n "$CMD" ] || usage
J="$STATE/inbox.journal"; MD="$STATE/inbox.md"; LOCK="$STATE/inbox.lock"; RL="$STATE/run.lock"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
single() { case "$1" in *$'\n'*|*$'\t'*|*$'\r'*) echo "ERROR: values must be single-line with no TAB" >&2; exit 1 ;; esac; }
need() { [ -n "$2" ] || { echo "ERROR: $1 is required" >&2; exit 1; }; }
rank() { case "$1" in "auto: usage"*) echo 0 ;; "auto:"*) echo 1 ;; *) echo 2 ;; esac; }   # hold strength
need_journal() { [ -f "$J" ] || { echo "ERROR: $J not found; run init first" >&2; exit 1; }; }

# Writers take an exclusive lock (writes take milliseconds). A lock is stale when its content has not changed for a
# whole retry interval AND its writer is gone (same host, dead pid) -- or when it is older than 10 minutes. The content
# is re-read just before removal, so a waiter never removes a lock another waiter has just taken.
lock() {
  tries=0; prev=""
  until ( set -o noclobber; printf 'pid=%s host=%s at=%s\n' "$$" "$(uname -n)" "$(now)" > "$LOCK" ) 2>/dev/null; do
    held="$(cat "$LOCK" 2>/dev/null || true)"
    if [ "$tries" -gt 0 ] && [ "$held" = "$prev" ]; then
      hpid="$(printf '%s' "$held" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')"; hhost="$(printf '%s' "$held" | sed -n 's/.*host=\([^ ]*\).*/\1/p')"
      if [ -n "$(find "$LOCK" -mmin +10 2>/dev/null)" ] || { [ -n "$hpid" ] && [ "$hhost" = "$(uname -n)" ] && pid_gone "$hpid"; }; then
        if [ "$(cat "$LOCK" 2>/dev/null || true)" = "$held" ]; then echo "WARNING: breaking stale $LOCK ($held)" >&2; rm -f "$LOCK"; prev=""; continue; fi
      fi
    fi
    prev="$held"
    tries=$((tries + 1)); [ "$tries" -lt 120 ] || { echo "ERROR: $LOCK held for 120 s by a live writer ($held)" >&2; exit 1; }
    sleep 1
  done
  trap 'rm -f "$LOCK"' EXIT
}

# A pid is gone only if `kill -0` says "No such process" (another user's live process answers "not permitted").
pid_gone() { err="$(LC_ALL=C kill -0 "$1" 2>&1)" && return 1; case "$err" in *"o such process"*) return 0 ;; esac; return 1; }

# The rendering: deterministic, from the journal alone (optionally its first N lines). The footer records how many
# journal lines it reflects, so a render that a crash left behind is never mistaken for a hand edit.
render_to() {
  awk -F'\t' -v lim="${2:-0}" '
    lim > 0 && NR > lim { exit }
    { cnt = NR }
    function sec(k) { return k == "parked" ? 1 : k == "stopped" ? 2 : k == "veto" ? 3 : k == "held-merge" ? 4 : k == "hold" ? 5 : k == "retro" ? 6 : 7 }
    $2 == "init"    { run = $4; next }
    $2 == "add"     { n++; id[n] = $3; at[$3] = $1; kind[$3] = $4; unit[$3] = $5; q[$3] = $6; opt[$3] = $7; rec[$3] = $8; blk[$3] = $9; next }
    $2 == "answer"  { ans[$3] = $5 " (by " $4 (($7 != "") ? " via " $7 : "") ", " $1 "#" NR (($6 != "") ? "; quoting the owner: \"" $6 "\"" : "") ")"; next }
    $2 == "resolve" { res[$3] = "resolved by " $4 ", " $1 (($6 != "") ? " -- " $6 : ""); next }
    $2 == "edit"    { ne++; ed[ne] = $4 " (" $1 ")"; next }
    $2 == "hold"    { hold = "requested " $1 ": " $4; next }
    $2 == "hold-clear" { hold = ""; next }
    END {
      print "# Unattended inbox" (run != "" ? " -- run " run : "")
      print ""
      print "Answer an item with `bash _bmad/scripts/unattended-inbox.sh <this directory> answer U-<n> \"<answer>\" --by owner`, or run `/epic-cycle --review`. This file is generated: a hand edit is saved aside and never applied."
      if (hold != "") { print ""; print "**Hold " hold "**" }
      split("Parked|Stopped|Veto window|Held merges|Holds|Retrospectives to review|Run reports", title, "|")
      for (s = 1; s <= 7; s++) {
        hdr = 0
        for (i = 1; i <= n; i++) {
          u = id[i]; if (sec(kind[u]) != s || (u in res)) continue
          if (!hdr) { print ""; print "## " title[s]; hdr = 1 }
          print ""; print "### " u " | " kind[u] " | " unit[u] " | " at[u]
          print "question: " q[u]; print "options: " opt[u]; print "recommendation: " rec[u]; print "blocks: " blk[u]
          print "answer: " ((u in ans) ? ans[u] : "(none yet -- answer with the script or --review)")
        }
      }
      if (ne) { print ""; print "## Hand edits (saved, not applied)"; for (i = 1; i <= ne; i++) print "- " ed[i] }
      hdr = 0
      for (i = 1; i <= n; i++) {
        u = id[i]; if (!(u in res)) continue
        if (!hdr) { print ""; print "## Resolved"; hdr = 1 }
        print "- " u " | " kind[u] " | " unit[u] ": " q[u] " -> " ((u in ans) ? ans[u] : "(no answer)") "; " res[u]
      }
      print ""; print "<!-- journal: " cnt " lines -->"
    }' "$J" > "$1.tmp.$$" && mv "$1.tmp.$$" "$1"
}

# Called under the lock before every write: a hand edit of inbox.md is saved and recorded, never applied.
save_edit() {
  [ -f "$MD" ] || return 0
  render_to "$STATE/.expected"
  if ! cmp -s "$STATE/.expected" "$MD"; then
    seen="$(sed -n 's/^<!-- journal: \([0-9]*\) lines -->$/\1/p' "$MD" | tail -1)"
    if [ -n "$seen" ]; then render_to "$STATE/.earlier" "$seen"; fi
    if [ -n "$seen" ] && cmp -s "$STATE/.earlier" "$MD"; then
      :   # an earlier rendering left by a crash between a journal write and its render -- not a hand edit
    else
      f="inbox.md.edited-$(date -u +%Y%m%dT%H%M%SZ)-$$"; cp "$MD" "$STATE/$f"
      printf '%s\tedit\t-\t%s\n' "$(now)" "$f" >> "$J"
      echo "NOTE: inbox.md had a hand edit; saved as $f (not applied)" >&2
    fi
  fi
  rm -f "$STATE/.expected" "$STATE/.earlier"
}

item_exists()   { awk -F'\t' -v id="$1" '$2 == "add" && $3 == id { f = 1 } END { exit f ? 0 : 1 }' "$J"; }
item_resolved() { awk -F'\t' -v id="$1" '$2 == "resolve" && $3 == id { f = 1 } END { exit f ? 0 : 1 }' "$J"; }
lock_field()    { [ -f "$RL" ] && awk -v k="$1" '{ for (i = 1; i <= NF; i++) if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } }' "$RL"; }
write_lock() {  # run-id holder started token where
  printf 'run=%s holder=%s host=%s started=%s token=%s heartbeat=%s heartbeat_epoch=%s last_boundary=%s\n' \
    "$1" "$2" "$(uname -n)" "$3" "$4" "$(now)" "$(date -u +%s)" "$5" > "$RL.tmp.$$" && mv "$RL.tmp.$$" "$RL"
}
nospace() { case "$2" in *" "*) echo "ERROR: $1 must not contain spaces" >&2; exit 1 ;; esac; }
new_token() { printf '%s-%s' "$(date -u +%s)" "$$"; }
own_lock() {    # run-id token -- exit 4 unless this session holds the lock
  [ -f "$RL" ] || { echo "ERROR: no run.lock -- this session no longer holds the run" >&2; exit 4; }
  [ "$(lock_field run)" = "$1" ] && [ "$(lock_field token)" = "$2" ] || { echo "ERROR: run.lock is held by run $(lock_field run) (holder $(lock_field holder)), not this session -- stop" >&2; exit 4; }
}

case "$CMD" in
  init)
    need "run-id" "${3:-}"; single "$3"; mkdir -p "$STATE"; lock
    [ ! -f "$J" ] || save_edit
    if [ ! -f "$J" ] || [ "$(awk -F'\t' '$2 == "init" { r = $4 } END { print r }' "$J")" != "$3" ]; then
      printf '%s\tinit\t-\t%s\n' "$(now)" "$3" >> "$J"
    fi
    render_to "$MD"; echo "inbox=$MD" ;;
  add)
    [ $# -eq 8 ] || { echo "ERROR: add needs exactly 6 arguments (see usage)" >&2; usage; }
    case "$3" in parked|stopped|veto|held-merge|hold|retro|report) ;; *) echo "ERROR: kind=$3 is not one of parked|stopped|veto|held-merge|hold|retro|report" >&2; exit 1 ;; esac
    need "unit" "$4"; need "question" "$5"
    for v in "$4" "$5" "$6" "$7" "$8"; do single "$v"; done
    need_journal; lock; save_edit
    case "$3" in veto|hold|report) existing="" ;;
      *) existing="$(K="$3" U="$4" awk -F'\t' '$2 == "add" && $4 == ENVIRON["K"] && $5 == ENVIRON["U"] { last = $3 } $2 == "resolve" { r[$3] = 1 } END { if (last != "" && !(last in r)) print last }' "$J")" ;;
    esac
    if [ -n "$existing" ]; then render_to "$MD"; echo "$existing EXISTS"; exit 0; fi
    n="$(awk -F'\t' '$2 == "add" { c++ } END { print c + 1 }' "$J")"
    printf '%s\tadd\tU-%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(now)" "$n" "$3" "$4" "$5" "$6" "$7" "$8" >> "$J"
    render_to "$MD"; echo "U-$n" ;;
  answer)
    ID="${3:-}"; ANS="${4:-}"; need "U-<n>" "$ID"; need "answer" "$ANS"
    BY=""; QUOTE=""; VIA=""; shift 4
    while [ $# -gt 0 ]; do
      case "$1" in
        --by|--quote|--via) [ $# -ge 2 ] || { echo "ERROR: $1 needs a value" >&2; exit 1; }
          case "$1" in --by) BY="$2" ;; --quote) QUOTE="$2" ;; --via) VIA="$2" ;; esac; shift 2 ;;
        *) usage ;;
      esac
    done
    need "--by" "$BY"
    [ "$BY" = "owner" ] || [ -n "$QUOTE" ] || { echo "ERROR: an answer relayed by '$BY' must quote the owner verbatim (--quote)" >&2; exit 1; }
    for v in "$ID" "$ANS" "$BY" "$QUOTE" "$VIA"; do single "$v"; done
    need_journal; lock; save_edit
    item_exists "$ID" || { echo "ERROR: $ID not found" >&2; exit 1; }
    ! item_resolved "$ID" || { echo "ERROR: $ID is already resolved" >&2; exit 1; }
    printf '%s\tanswer\t%s\t%s\t%s\t%s\t%s\n' "$(now)" "$ID" "$BY" "$ANS" "$QUOTE" "$VIA" >> "$J"
    render_to "$MD"; echo "$ID answered" ;;
  answers)
    need_journal
    awk -F'\t' '$2 == "answer" { a[$3] = $1 "#" NR "\t" $4 "\t" $7 "\t" $5 "\t" $6; if (!($3 in seen)) { seen[$3] = 1; ord[++n] = $3 } } $2 == "resolve" { r[$3] = 1 }
      END { for (i = 1; i <= n; i++) if (!(ord[i] in r)) print ord[i] "\t" a[ord[i]] }' "$J" ;;
  resolve)
    ID="${3:-}"; BY="${4:-}"; AT="${5:-}"; NOTE="${6:-}"
    need "U-<n>" "$ID"; need "applied_by" "$BY"; need "answer_ref (or -)" "$AT"
    for v in "$ID" "$BY" "$AT" "$NOTE"; do single "$v"; done
    need_journal; lock; save_edit
    item_exists "$ID" || { echo "ERROR: $ID not found" >&2; exit 1; }
    ! item_resolved "$ID" || { echo "ERROR: $ID is already resolved -- an item is resolved exactly once" >&2; exit 1; }
    latest="$(awk -F'\t' -v id="$ID" '$2 == "answer" && $3 == id { t = $1 "#" NR } END { print t }' "$J")"
    if [ "$AT" = "-" ]; then
      [ -z "$latest" ] || { echo "ERROR: $ID has an answer ($latest); resolve with that answer_ref after applying it" >&2; exit 1; }
    else
      [ "$AT" = "$latest" ] || { echo "ERROR: $ID: the latest answer is from ${latest:-nobody}, not $AT -- read \`answers\` again and apply that one" >&2; exit 1; }
    fi
    printf '%s\tresolve\t%s\t%s\t%s\t%s\n' "$(now)" "$ID" "$BY" "$AT" "$NOTE" >> "$J"
    render_to "$MD"; echo "$ID resolved" ;;
  list)
    need_journal
    awk -F'\t' -v which="${3:-open}" '$2 == "add" { n++; id[n] = $3; k[$3] = $4; u[$3] = $5; q[$3] = $6 } $2 == "answer" { a[$3] = 1 } $2 == "resolve" { r[$3] = 1 }
      END { for (i = 1; i <= n; i++) { x = id[i]; s = (x in r) ? "resolved" : (x in a) ? "answered" : "open"
            if (which == "all" || s != "resolved") print x "\t" k[x] "\t" u[x] "\t" s "\t" q[x] } }' "$J" ;;
  hold|hold-clear)
    need "reason" "${3:-}"; single "$3"
    case "${4:-}" in "") ;; --usage-only) [ "$CMD" = hold-clear ] || usage ;; *) usage ;; esac
    need_journal; lock; save_edit
    cur=""; [ ! -f "$STATE/HOLD" ] || cur="$(sed -n 's/^requested_at=[^ ]* reason=//p' "$STATE/HOLD")"
    if [ -f "$STATE/HOLD" ]; then
      if [ "$CMD" = hold ] && [ "$(rank "$3")" -lt "$(rank "$cur")" ]; then render_to "$MD"; echo "HOLD KEPT: $cur"; exit 0; fi
      if [ "${4:-}" = --usage-only ] && [ "$(rank "$cur")" -ne 0 ]; then render_to "$MD"; echo "HOLD KEPT: $cur"; exit 5; fi
    fi
    printf '%s\t%s\t-\t%s\n' "$(now)" "$CMD" "$3" >> "$J"
    if [ "$CMD" = hold ]; then printf 'requested_at=%s reason=%s\n' "$(now)" "$3" > "$STATE/HOLD"; else rm -f "$STATE/HOLD"; fi
    render_to "$MD"; echo "$CMD recorded" ;;
  run-status)
    if [ -f "$RL" ]; then
      e="$(lock_field heartbeat_epoch)"; age=$(( ( $(date -u +%s) - ${e:-0} ) / 60 ))
      echo "LIVE? $(cat "$RL") heartbeat_age_min=$age"; exit 3
    fi
    echo "none" ;;
  run-start)
    need "run-id" "${3:-}"; need "holder" "${4:-}"; single "$3"; single "$4"; nospace "run-id" "$3"; nospace "holder" "$4"; mkdir -p "$STATE"; lock
    if ! ( set -o noclobber; : > "$RL" ) 2>/dev/null; then
      e="$(lock_field heartbeat_epoch)"; echo "LIVE? $(cat "$RL") heartbeat_age_min=$(( ( $(date -u +%s) - ${e:-0} ) / 60 ))"; exit 3
    fi
    t="$(new_token)"; write_lock "$3" "$4" "$(now)" "$t" "start"
    [ ! -f "$J" ] || { save_edit; printf '%s\trun-start\t-\t%s %s\n' "$(now)" "$3" "$4" >> "$J"; render_to "$MD"; }
    echo "run.lock taken: run=$3 holder=$4 token=$t" ;;
  run-takeover)
    need "run-id" "${3:-}"; need "holder" "${4:-}"; need "reason" "${5:-}"; single "$3"; single "$4"; single "$5"; nospace "run-id" "$3"; nospace "holder" "$4"
    [ -f "$RL" ] || { echo "ERROR: no run.lock to take over; use run-start" >&2; exit 1; }
    lock; [ -f "$RL" ] || { echo "ERROR: no run.lock to take over; use run-start" >&2; exit 1; }
    held="$(lock_field run)"
    case "$5" in owner-confirmed*) ;; *) [ "$held" = "$3" ] || { echo "ERROR: run.lock names run $held, not $3; only the owner can release another run's lock (reason \"owner-confirmed ...\")" >&2; exit 1; } ;; esac
    st="$(now)"; case "$5" in owner-confirmed*) ;; *) st="$(lock_field started)"; [ -n "$st" ] || st="$(now)" ;; esac
    t="$(new_token)"; write_lock "$3" "$4" "$st" "$t" "takeover"
    [ ! -f "$J" ] || { save_edit; printf '%s\trun-takeover\t-\t%s %s from %s: %s\n' "$(now)" "$3" "$4" "$held" "$5" >> "$J"; render_to "$MD"; }
    echo "run.lock taken over: run=$3 holder=$4 (was $held) token=$t" ;;
  run-boundary)
    need "run-id" "${3:-}"; need "token" "${4:-}"; single "$3"; single "$4"; single "${5:-}"
    own_lock "$3" "$4"; lock; own_lock "$3" "$4"   # checked again under the writer lock: a takeover may have just landed
    write_lock "$3" "$(lock_field holder)" "$(lock_field started)" "$4" "${5:-}" ;;
  run-end)
    need "run-id" "${3:-}"; need "token" "${4:-}"; need "reason" "${5:-}"; single "$3"; single "$4"; single "$5"
    own_lock "$3" "$4"; lock; own_lock "$3" "$4"
    rm -f "$RL"
    [ ! -f "$J" ] || { save_edit; printf '%s\trun-end\t-\t%s: %s\n' "$(now)" "$3" "$5" >> "$J"; render_to "$MD"; }
    echo "run.lock released ($5)" ;;
  verify)
    need_journal; lock; T="$STATE/.verify"; render_to "$T"
    if cmp -s "$T" "$MD"; then rm -f "$T"; echo "ok"; else rm -f "$T"; echo "MISMATCH: inbox.md is not the journal's rendering (a hand edit, or a crash mid-write)"; exit 1; fi ;;
  render)
    need_journal; lock; save_edit; render_to "$MD"; echo "rendered" ;;
  *) usage ;;
esac
