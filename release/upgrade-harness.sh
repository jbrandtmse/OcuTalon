#!/usr/bin/env bash
# release/upgrade-harness.sh <command> [--version <v>] [--rc <n>] [--previous <ref>] [--rehearsal] [--record <file>]
#
# The release upgrade harness (Story 11.2; FR-6, FR-60, NFR-16, NFR-17, REL-6; AD-5, AD-22, AD-23). A release gate that runs by hand and
# in Story 11.5's sequence; it is no CI unit. It proves that a new OcuTalon build installs over a running one, and survives a container
# restart, with every record still working: it builds the previous build's image from that commit's own tree, seeds a conversation, an
# Orders watch, a pending approval from Break the feed and two reminders through the product's HTTP API and the CI mock, switches demo
# mode off in a second project of the previous build, upgrades both projects in place to this checkout, restarts the records project,
# checks every record after each, diffs the storage against the previous build and writes a pass or fail per record.
#
# Commands:
#   plan       the dry run: prints the plan (refs, shas, versions, stamp, phases, record path), starts no container, and writes the
#              record section with every row "not run" and Mode: dry run
#   run        build, settings, seed, upgrade, restart, storage and report, each as its own process, then down (always)
#   build      resolves the previous build, exports its tree (git archive) into the state folder, stamps its version when it equals
#              the candidate's, and builds its web bundle when the tree has none
#   settings   throwaway project 1 (ocutalon-upgset-<tag>-...): the previous build, SetDemoMode(0), the upgrade, the demo-off checks;
#              the project is removed at the end of the call
#   seed       throwaway project 2 (ocutalon-upgrade-<tag>-...): the previous build, and the records through the HTTP API and the mock;
#              the project and the lane's throwaway lock are kept until down
#   upgrade    the candidate on the same volume, and the checks of every record
#   restart    a clean container restart, and the checks of every record
#   storage    the storage snapshots against each other, and the release-diff rule against the previous commit
#   report     writes the record section (--record, or release/records/<version>/rc<n>.md) and prints RESULT pass|fail|not run
#   down       removes the tag's projects, releases the lock when its content is this harness's, and deletes the state folder
# Options are taken by plan, run and build, and stored in the state. --rc is a positive whole number, required unless --record is given.
# Phase commands need OCUTALON_RUN_TAG; run defaults it to upg-<epoch>. Every phase ends within OCUTALON_LIVE_DEADLINE seconds (default
# 540), so that a call fits ten minutes, and prints PHASE <name> done <s>s (<n> failed). A phase run out of order exits 2.
# The previous build is, in order: --previous <ref>; the highest v* tag merged into HEAD that is not on HEAD and not v<candidate version>;
# the pinned pre-release commit (UPGRADE_PRE_RELEASE_COMMIT), which is the case while 1.0.0 has no previous release. A previous build
# whose version equals the candidate's is stamped <version>-pre.1. Run from a stage, pass --record <file> in a temporary folder, never
# the committed record.
# Exit codes: 0 pass (or a dry run), 1 a failed check or phase, 2 a refusal (bad option, phase out of order, no previous build),
# 75 the lane lock is busy. Needs bash 3.2 or later, git, jq, docker compose, node and npm (the previous tree's web bundle, and the
# demo-switch page project), and the IRIS base image (ci/iris.sh). The model is the CI mock, never a key; every stack is a throwaway
# of docker/tests/lib-live.sh with the CI override.
set -u
umask 077

harness_caller_pwd=$PWD
harness_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$harness_root" || exit 1
. "$harness_root/ci/iris.sh"
. "$harness_root/docker/tests/lib-online.sh"
. "$harness_root/docker/tests/lib-upgrade.sh"

# The commit of the integration branch when Epic 11 started: every release-1 record kind is built in it. It is the previous build while
# no v* tag is merged into HEAD.
UPGRADE_PRE_RELEASE_COMMIT=c9f1288c7a735f1ee3aa14a4f5289de794ce5257

# The record families the harness runs, and the ones it holds back (pairings join from the release after 1.0.0, Story 12.7).
HARNESS_ON="conversation reminder approval watch settings"
HARNESS_OFF="pairing"
# The rows of the record, in order. A row id has no space.
HARNESS_ROWS="previous-build upgrade conversation reminder approval watch settings restart storage private-globals pairing"
PAIRING_OFF_TEXT="joins from the release after 1.0.0 (Story 12.7)"

# The seed's texts, as the CI mock scenarios answer them.
REPLY_WATCH="I'll watch the Orders production and stay quiet unless something needs you."
REPLY_R1="The CI mock set the reminder for after the upgrade."
REPLY_R2="The CI mock set the reminder for tomorrow."
REPLY_TELL="Noted."
REPLY_ASK="Your build server is called ORION-7."
TEXT_R1="check the upgrade"
TEXT_R2="review the upgrade notes"
TEXT_RESULT="All 50 orders went through."
MOCK_LOG=/opt/ocutalon/mock-log/requests.jsonl

# --- pure functions: each takes its inputs as arguments ---

# resolve_previous <repository> <candidate version> [<ref>]: prints "<kind><TAB><ref><TAB><sha>" for the previous build, kind being
# explicit (the given ref), tag (the highest v* tag merged into HEAD, not on HEAD and not v<candidate version>) or pre-release (the pinned
# commit). The commit must be an ancestor of HEAD and not HEAD itself: otherwise nothing is printed, one line goes to stderr and the
# status is 2.
resolve_previous() {
  local repo=$1 cand=$2 ref=${3:-} kind sha head skip tag
  head=$(git -C "$repo" rev-parse --verify --quiet 'HEAD^{commit}') || {
    echo "harness: $repo has no HEAD commit" >&2
    return 2
  }
  if [ -n "$ref" ]; then
    kind=explicit
    sha=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}") || {
      echo "harness: the previous ref '$ref' is not a commit of this repository" >&2
      return 2
    }
  else
    skip=$(git -C "$repo" tag --points-at HEAD)
    ref=""
    while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      [ "$tag" != "v$cand" ] || continue
      if printf '%s\n' "$skip" | grep -qxF -- "$tag"; then continue; fi
      ref=$tag
      break
    done <<EOT
$(git -C "$repo" -c versionsort.suffix=- tag --merged HEAD --list 'v[0-9]*' --sort=-version:refname 2>/dev/null)
EOT
    if [ -n "$ref" ]; then
      kind=tag
      sha=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}") || {
        echo "harness: the tag '$ref' is not a commit of this repository" >&2
        return 2
      }
    else
      kind=pre-release
      ref=$UPGRADE_PRE_RELEASE_COMMIT
      sha=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}") || {
        echo "harness: the pinned pre-release commit $ref is not in this repository (fetch the full history)" >&2
        return 2
      }
    fi
  fi
  if [ "$sha" = "$head" ]; then
    echo "harness: the previous build '$ref' is HEAD itself" >&2
    return 2
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$sha" "$head" 2>/dev/null; then
    echo "harness: the previous build '$ref' is not an ancestor of HEAD" >&2
    return 2
  fi
  printf '%s\t%s\t%s\n' "$kind" "$ref" "$sha"
}

# previous_required <repository> <kind> <ref>: yes when the previous build is a v* release tag (resolved or given), else no.
previous_required() {
  case $2 in
    tag) echo yes ;;
    explicit)
      case $3 in
        v[0-9]*)
          if git -C "$1" rev-parse --verify --quiet "refs/tags/$3" > /dev/null 2>&1; then
            echo yes
            return 0
          fi
          ;;
      esac
      echo no
      ;;
    *) echo no ;;
  esac
}

# stamp_for <previous version> <candidate version>: the version that the previous build is stamped with when the two are equal (the
# version gate of after-start.cos loads whenever the versions differ), else nothing.
stamp_for() {
  if [ "$1" = "$2" ]; then printf '%s-pre.1' "$1"; fi
}

# mode_for <plan 0|1> <rehearsal 0|1> <dirty 0|1>: the Mode line of the record.
mode_for() {
  if [ "$1" = 1 ]; then
    echo "dry run"
  elif [ "$3" = 1 ]; then
    echo "rehearsal (uncommitted changes)"
  elif [ "$2" = 1 ]; then
    echo "rehearsal"
  else
    echo "release"
  fi
}

# phase_ready <state folder> <phase>: 0 when the phase may run now; otherwise one REFUSED line and 1.
phase_ready() {
  local state=$1 ph=$2 need=""
  case $ph in
    down) return 0 ;;
    build)
      if [ -e "$state/p1/project" ]; then
        echo "REFUSED build: the records project of this tag is up; run down first"
        return 1
      fi
      return 0
      ;;
    settings | seed | report) need=build ;;
    upgrade) need=seed ;;
    restart | storage) need=upgrade ;;
    *)
      echo "REFUSED $ph: not a phase"
      return 1
      ;;
  esac
  if [ ! -f "$state/options" ]; then
    echo "REFUSED $ph: no state for this tag; run build first"
    return 1
  fi
  if ! phase_done "$state" "$need"; then
    echo "REFUSED $ph: $need is not done for this tag"
    return 1
  fi
  case $ph in
    settings)
      if [ -e "$state/phase.seed" ]; then
        echo "REFUSED settings: seed has started, and the records project holds the lane lock until down; settings runs before seed"
        return 1
      fi
      ;;
    seed)
      if [ -e "$state/p1/project" ] || phase_done "$state" seed; then
        echo "REFUSED seed: it already ran for this tag; run down, then build again"
        return 1
      fi
      ;;
    upgrade)
      if [ -e "$state/phase.upgrade" ]; then
        echo "REFUSED upgrade: it already ran for this tag; run down, then build again"
        return 1
      fi
      ;;
  esac
  return 0
}

# phase_done <state folder> <phase>: the phase ended (a phase file that holds "done").
phase_done() { [ "$(cut -d' ' -f1 "$1/phase.$2" 2> /dev/null)" = done ]; }

# reminder_expect <due epoch> <ready epoch>: late when the reminder was due more than 20 s before the candidate was ready, on-time when
# more than 20 s after, either inside the band (LATESECONDS is 10 and the waiters are re-armed a few seconds before Ready).
reminder_expect() {
  local d=$(($2 - $1))
  if [ "$d" -gt 20 ]; then
    echo late
  elif [ "$d" -lt -20 ]; then
    echo on-time
  else
    echo either
  fi
}

# due_phrase <due epoch> <ready epoch>: "12 s before the candidate was ready" or "12 s after the candidate was ready".
due_phrase() {
  if [ "$2" -ge "$1" ]; then
    echo "$(($2 - $1)) s before the candidate was ready"
  else
    echo "$(($1 - $2)) s after the candidate was ready"
  fi
}

# iso_epoch <UTC time>: the epoch seconds of 2026-10-31T20:00:00Z (a fraction of a second is dropped).
iso_epoch() { jq -nr --arg t "$1" '$t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2> /dev/null; }

# The readers of a /state answer (a file). Each prints nothing and returns 1 when it finds nothing.

# state_turn <state.json> <clientId>: "state|replyText" of the chat turn the page sent with that id.
state_turn() {
  local out
  out=$(jq -r --arg id "$2" '[.chat[]? | select(.type == "chat.message" and .payload.clientId == $id) | .payload][0] | if . == null then empty else "\(.state)|\((.replyText // "") | gsub("[\r\n]+"; " "))" end' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_pending_approval <state.json> [<request ref>]: "ref|expiresAt" of the first pending approval of the rail (of that request).
state_pending_approval() {
  local out
  out=$(jq -r --arg r "${2:-}" '[.rail.approvals[]? | select(.state == "pending" and ($r == "" or .ref == $r))][0] | if . == null then empty else "\(.ref)|\(.expiresAt)" end' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_reminder_card <state.json> <reminder ref>: "ref|dueAt|state" of the reminder in the rail.
state_reminder_card() {
  local out
  out=$(jq -r --arg r "$2" '[.rail.reminders[]? | select(.ref == $r)][0] | if . == null then empty else "\(.ref)|\(.dueAt)|\(.state)" end' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_reminder_by_text <state.json> <text>: "ref|dueAt" of the pending reminder in the rail with that text.
state_reminder_by_text() {
  local out
  out=$(jq -r --arg t "$2" '[.rail.reminders[]? | select(.text == $t and .state == "pending")][0] | if . == null then empty else "\(.ref)|\(.dueAt)" end' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_checks_orders <state.json>: the production of the Orders check in the rail (a stopped watch does not count).
state_checks_orders() {
  local out
  out=$(jq -r '[.rail.checks[]? | select((.stopped // false) | not) | select(((.production // "") + " " + (.displayName // "")) | test("Orders"; "i"))][0] | if . == null then empty else (.production // "Orders") end' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_new_incident <state.json> [<incident ref to leave out>]: "incidentRef|requestRef" of the newest incident of the chat that awaits
# approval with a pending request, other than the one left out.
state_new_incident() {
  local out
  out=$(jq -r --arg x "${2:-}" '[.chat[]? | select(.type == "incident") | .payload | select(.ref != $x and .state == "awaiting_approval") | . as $i | ([$i.requests[]? | select(.state == "pending")][0]) as $q | select($q != null) | "\($i.ref)|\($q.ref)"] | last // empty' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_incident <state.json> <incident ref>: "state|total|completed|failedAgain" of the incident; the counts are empty until a resend ran.
state_incident() {
  local out
  out=$(jq -r --arg r "$2" '[.chat[]? | select(.type == "incident" and .payload.ref == $r) | .payload][0] | if . == null then empty else ((.requests // [] | map(.result) | map(select(. != null)) | .[0] // {}) as $q | "\(.state)|\($q.total // "")|\($q.completed // "")|\($q.failedAgain // "")") end' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_phone_has <state.json> <text>: a message of the simulated phone has exactly that text.
state_phone_has() { jq -e --arg t "$2" '[.phone[]? | (.text // "")] | any(. == $t)' "$1" > /dev/null 2>&1; }

# state_notice <state.json> <kind> <text part>: the text of the first chat notice of that kind that holds the part.
state_notice() {
  local out
  out=$(jq -r --arg k "$2" --arg s "$3" '[.chat[]? | select(.type == "notification" and .payload.kind == $k) | .payload.text | select(contains($s))][0] // empty' "$1" 2> /dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# state_demo_mode <state.json>: true or false.
state_demo_mode() { jq -r '.demoMode' "$1" 2> /dev/null; }

# chat_request_carries <mock log> <mark> <marker label> <text>: the first line after the first <mark> lines of the log that carries the
# marker and offers tools (the chat agent's request; the triage request offers none) holds the text in its messages (a string or text
# blocks). Returns 1 when there is no such line or it lacks the text.
chat_request_carries() {
  [ -f "$1" ] || return 1
  tail -n +"$(($2 + 1))" "$1" | jq -R 'fromjson?' 2> /dev/null | jq -s -e --arg m "$3" --arg t "$4" '
    [ .[] | select(.marker == $m and ((.request.tools // []) | length) > 0) ][0]
    | if . == null then false
      else ([ .request.messages[]? | (if (.content | type) == "string" then .content else ([.content[]? | (.text? // empty)] | join("\n")) end) ] | join("\n") | contains($t))
      end' > /dev/null 2>&1
}

# chat_request_report <mock log> <mark> <marker label> <text>: one line per request after the mark that carries the marker: its number,
# the count of tools it offers, the count of messages, and whether its messages hold the text (Task 0 (d) of the story).
chat_request_report() {
  [ -f "$1" ] || return 1
  tail -n +"$(($2 + 1))" "$1" | jq -R 'fromjson?' 2> /dev/null | jq -s -r --arg m "$3" --arg t "$4" '
    [ .[] | select(.marker == $m) ] | to_entries[]
    | "request \(.key + 1): tools \((.value.request.tools // []) | length), messages \((.value.request.messages // []) | length), carries the fact: \(([ .value.request.messages[]? | (if (.content | type) == "string" then .content else ([.content[]? | (.text? // empty)] | join("\n")) end) ] | join("\n") | contains($t)))"' 2> /dev/null
}

# storage_compare <before> <after>: every line of the before snapshot (CHK|slot|class|data node|slot|property|type|collection) is in
# the after snapshot. Prints MISSING <line> for up to 20 lines that are not and returns 1; returns 2 for an empty snapshot.
storage_compare() {
  local missing
  if [ ! -s "$1" ] || [ ! -s "$2" ]; then
    echo "a storage snapshot is empty"
    return 2
  fi
  missing=$(LC_ALL=C comm -23 <(LC_ALL=C sort -u "$1") <(LC_ALL=C sort -u "$2"))
  if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | head -n 20 | sed 's/^CHK|slot|/MISSING /'
    return 1
  fi
  return 0
}

# env_get <file> <key> / env_set <file> <key> <value>: key=value files (options, seed.env, upgrade.env).
env_get() { sed -n "s/^$2=//p" "$1" 2> /dev/null | tail -n 1; }
env_set() {
  if [ -f "$1" ]; then
    grep -v "^$2=" "$1" > "$1.new"
    mv "$1.new" "$1"
  fi
  printf '%s=%s\n' "$2" "$3" >> "$1"
}

# detail_clean: a result detail on one line of printable ASCII, 300 characters at most, with no pipe (the record is a table).
detail_clean() { tr -d '\r' | tr '\n' ' ' | LC_ALL=C tr -c '\040-\176' '?' | tr '|' '/' | cut -c1-300; }

row_title() {
  case $1 in
    previous-build) echo "previous build" ;;
    private-globals) echo "private globals" ;;
    *) echo "$1" ;;
  esac
}

# record_rows <results file>: one line per row of the record, in order: id, title, result (pass, fail, not run or off) and detail, tab
# separated. The results file holds "RECORD <row id> pass|fail|off|note|seed <detail>" lines; a row is pass only when it has a pass line
# and no fail line, fail when it has any fail line, off for a row of HARNESS_OFF, and not run when it has none. A note adds to a pass
# detail. A seed line is a passed step of the seed: it is no check of the upgrade, so it never makes a row pass.
record_rows() {
  local results=${1:-/dev/null}
  [ -f "$results" ] || results=/dev/null
  awk -v rows="$HARNESS_ROWS" -v offrows="$HARNESS_OFF" -v offtext="$PAIRING_OFF_TEXT" '
    function title(id) { return id == "previous-build" ? "previous build" : (id == "private-globals" ? "private globals" : id) }
    $1 == "RECORD" {
      id = $2; kind = $3; d = $0
      sub(/^RECORD [^ ]+ [^ ]+ ?/, "", d)
      gsub(/\|/, "/", d)
      if (kind == "pass") { np[id]++ }
      else if (kind == "fail") { nf[id]++; if (nf[id] == 1) firstfail[id] = d }
      else if (kind == "seed") { ns[id]++ }
      else if (kind == "off") { no[id]++; offd[id] = d }
      else if (kind == "note") { notes[id] = notes[id] (notes[id] == "" ? "" : "; ") d }
    }
    END {
      n = split(rows, ids, " ")
      for (i = 1; i <= n; i++) {
        id = ids[i]
        if (index(" " offrows " ", " " id " ")) {
          printf "%s\t%s\toff\t%s\n", id, title(id), (no[id] > 0 ? offd[id] : offtext)
        } else if (nf[id] > 0) {
          printf "%s\t%s\tfail\t%s%s\n", id, title(id), firstfail[id], (nf[id] > 1 ? " (and " (nf[id] - 1) " more failed)" : "")
        } else if (np[id] > 0) {
          printf "%s\t%s\tpass\t%d checks passed%s\n", id, title(id), np[id], (notes[id] != "" ? "; " notes[id] : "")
        } else {
          printf "%s\t%s\tnot run\t%s\n", id, title(id), (ns[id] > 0 ? "not run (seeded only)" : "not run")
        }
      }
    }' "$results"
}

# record_result <results file>: pass when every enabled row passes, not run when none was run, else fail.
record_result() {
  record_rows "${1:-/dev/null}" | awk -F'\t' -v offrows="$HARNESS_OFF" '
    index(" " offrows " ", " " $1 " ") { next }
    { n++; if ($3 == "fail") f++; else if ($3 == "pass") p++; else nr++ }
    END { if (f > 0) print "fail"; else if (n > 0 && p == n) print "pass"; else if (n > 0 && nr == n) print "not run"; else print "fail" }'
}

# record_section <results file> <options file>: the "## Upgrade harness" section of the record, on stdout.
record_section() {
  local results=${1:-/dev/null} options=$2 kind ref sha pv stamp built note ended
  kind=$(env_get "$options" prev_kind)
  ref=$(env_get "$options" prev_ref)
  sha=$(env_get "$options" prev_sha)
  pv=$(env_get "$options" prev_version)
  stamp=$(env_get "$options" stamp)
  built=${stamp:-$pv}
  ended=$(env_get "$options" ended)
  [ -n "$ended" ] || ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "## Upgrade harness"
  echo
  echo "Result: $(record_result "$results")"
  echo "Mode: $(env_get "$options" mode)"
  echo "Required: $(env_get "$options" required)"
  echo "Candidate: $(env_get "$options" version) at $(env_get "$options" cand_sha)"
  if [ "$ref" = "$sha" ]; then
    echo "Previous: $kind $sha, version $pv, built as $built"
  else
    echo "Previous: $kind $ref at $sha, version $pv, built as $built"
  fi
  if [ "$kind" = pre-release ]; then
    note="1.0.0 is the first release: it has no previous release, so the previous side is a pre-release build of the integration branch ($sha), which proves the harness itself."
    echo "Note: $note"
  fi
  echo "Run: $(env_get "$options" started) to $ended, tag $(env_get "$options" tag)"
  echo
  echo "| Record | Result | Detail |"
  echo "| --- | --- | --- |"
  record_rows "$results" | while IFS="$(printf '\t')" read -r _ title result detail; do
    printf '| %s | %s | %s |\n' "$title" "$result" "$detail"
  done
}

# record_write <record file> <section file> [<title>]: replaces the file's "## Upgrade harness" section with the section file's text, or
# appends it when the file has none. A missing file is created with the title (default "# OcuTalon") first. Other sections are kept.
record_write() {
  local file=$1 section=$2 title=${3:-"# OcuTalon"}
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    printf '%s\n\n' "$title" > "$file"
  fi
  awk -v sec="$section" '
    BEGIN { while ((getline l < sec) > 0) s[++n] = l }
    function put(   i) { for (i = 1; i <= n; i++) print s[i]; done = 1 }
    /^## Upgrade harness[ \t]*$/ && !done { skip = 1; put(); next }
    skip && /^## / { skip = 0; print "" }
    skip { next }
    { print; last = $0 }
    END {
      if (!done) { if (NR > 0 && last != "") print ""; put() }
    }' "$file" > "$file.new" && mv "$file.new" "$file"
}

# --- the state folder, the options and the results ---

state_dir() {
  local t=${TMPDIR:-/tmp}
  printf '%s/ocutalon-upgrade-%s\n' "${t%/}" "$1"
}

phase_mark() { printf '%s %s\n' "$2" "$3" > "$state/phase.$1"; }

options_write() { # options_write <file>: the resolved plan (pl_* variables) as key=value lines
  : > "$1"
  env_set "$1" version "$pl_cand_version"
  env_set "$1" rc "$opt_rc"
  env_set "$1" mode "$pl_mode"
  env_set "$1" record "$pl_record"
  env_set "$1" prev_kind "$pl_prev_kind"
  env_set "$1" prev_ref "$pl_prev_ref"
  env_set "$1" prev_sha "$pl_prev_sha"
  env_set "$1" prev_version "$pl_prev_version"
  env_set "$1" stamp "$pl_stamp"
  env_set "$1" cand_sha "$pl_cand_sha"
  env_set "$1" dirty "$pl_dirty"
  env_set "$1" required "$pl_required"
  env_set "$1" tag "${OCUTALON_RUN_TAG:-none}"
  env_set "$1" started "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

opt() { env_get "$state/options" "$1"; }

# parse_options <args>...: sets opt_version, opt_rc, opt_previous, opt_rehearsal and opt_record; prints a FAIL line and returns 2 for a bad
# option.
parse_options() {
  opt_version=""
  opt_rc=""
  opt_previous=""
  opt_rehearsal=0
  opt_record=""
  while [ $# -gt 0 ]; do
    case $1 in
      --version | --rc | --previous | --record)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          echo "FAIL $1 needs a value"
          return 2
        fi
        case $1 in
          --version) opt_version=$2 ;;
          --rc) opt_rc=$2 ;;
          --previous) opt_previous=$2 ;;
          --record) opt_record=$2 ;;
        esac
        shift 2
        ;;
      --rehearsal)
        opt_rehearsal=1
        shift
        ;;
      *)
        echo "FAIL unknown option '$1'"
        return 2
        ;;
    esac
  done
  case $opt_record in
    '' | /*) ;;
    *) opt_record=$harness_caller_pwd/$opt_record ;;
  esac
  if [ -n "$opt_rc" ] && ! printf '%s\n' "$opt_rc" | grep -Eq '^[1-9][0-9]{0,5}$'; then
    echo "FAIL --rc must be a positive whole number"
    return 2
  fi
  if [ -z "$opt_rc" ] && [ -z "$opt_record" ]; then
    echo "FAIL --rc <n> is required unless --record <file> is given"
    return 2
  fi
  return 0
}

# resolve_plan <plan 0|1>: sets the pl_* variables from the options and this checkout; prints a FAIL line and returns 2 when it cannot.
resolve_plan() {
  local line
  pl_cand_version=$(manifest_version src/module.xml)
  if [ -n "$opt_version" ] && [ "$opt_version" != "$pl_cand_version" ]; then
    echo "FAIL --version $opt_version is not the candidate's version ($pl_cand_version in src/module.xml)"
    return 2
  fi
  pl_cand_sha=$(git rev-parse HEAD)
  pl_dirty=0
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then pl_dirty=1; fi
  if ! line=$(resolve_previous "$harness_root" "$pl_cand_version" "$opt_previous" 2>&1); then
    echo "FAIL $line"
    return 2
  fi
  pl_prev_kind=$(printf '%s' "$line" | cut -f1)
  pl_prev_ref=$(printf '%s' "$line" | cut -f2)
  pl_prev_sha=$(printf '%s' "$line" | cut -f3)
  pl_prev_version=$(git show "$pl_prev_sha:src/module.xml" 2> /dev/null | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -n 1)
  if [ -z "$pl_prev_version" ]; then
    echo "FAIL the previous build $pl_prev_sha has no src/module.xml version"
    return 2
  fi
  pl_stamp=$(stamp_for "$pl_prev_version" "$pl_cand_version")
  pl_mode=$(mode_for "$1" "$opt_rehearsal" "$pl_dirty")
  pl_required=$(previous_required "$harness_root" "$pl_prev_kind" "$pl_prev_ref")
  pl_record=${opt_record:-release/records/$pl_cand_version/rc$opt_rc.md}
  return 0
}

record_title() {
  if [ -n "$(opt rc)" ]; then
    echo "# OcuTalon $(opt version) rc$(opt rc)"
  else
    echo "# OcuTalon $(opt version) upgrade harness"
  fi
}

# --- results: every check is one PASS or FAIL line and one RECORD line of the current row ---

cur_row=""
row() { cur_row=$1; }

# note_row <text>: extra detail for the current row's pass line (RECORD <row> note ...).
note_row() {
  echo "INFO $1"
  if [ -n "$cur_row" ] && [ -n "${results:-}" ]; then
    printf 'RECORD %s note %s\n' "$cur_row" "$(printf '%s' "$1" | detail_clean)" >> "$results"
  fi
}

record_line() { # record_line <pass|fail> <text>
  if [ -n "$cur_row" ] && [ -n "${results:-}" ]; then
    printf 'RECORD %s %s %s\n' "$cur_row" "$1" "$(printf '%s' "$2" | detail_clean)" >> "$results"
  fi
  return 0
}

# A check of the seed (except the previous build's) is a seed line: the record's row passes on the checks after the upgrade.
pass() {
  echo "PASS $1"
  if [ "${seeding:-0}" = 1 ] && [ "$cur_row" != previous-build ]; then
    record_line seed "$1"
  else
    record_line pass "$1"
  fi
}
fail() {
  echo "FAIL $1"
  fails=$((${fails:-0} + 1))
  record_line fail "$1"
}
die() {
  fail "$1"
  echo "$(basename "$0" .sh): aborted"
  exit 1
}

# --- the stack: the HTTP surface, the mock log, the iris sessions ---

api_get() { # api_get <path>: the body of GET /ocutalon/api/v1/<path> with a unique probe
  next_probe
  curl -s --max-time 30 -b "$jar" -c "$jar" "$base/ocutalon/api/v1/$1?probe=$probes"
}

api_post() { # api_post <path> <json>: prints the status; the body is in $tmp/post.body
  curl -s --max-time 30 -b "$jar" -c "$jar" -o "$tmp/post.body" -w '%{http_code}' \
    -H 'Content-Type: application/json' -H 'X-OcuTalon-Request: 1' -H "Origin: $base" -d "$2" "$base/ocutalon/api/v1/$1"
}

# state_get [<file>]: GET /v1/state into the file (default $tmp/state.json); 0 when it is a state answer.
state_get() {
  local f=${1:-$tmp/state.json} code
  next_probe
  code=$(curl -s --max-time 30 -b "$jar" -c "$jar" -o "$f" -w '%{http_code}' "$base/ocutalon/api/v1/state?probe=$probes")
  [ "$code" = 200 ] && jq -e 'type == "object" and (.chat | type == "array")' "$f" > /dev/null 2>&1
}

# signin_once: the README account signs in with a fresh jar and /state answers.
signin_once() {
  : > "$jar"
  online_signin "$jar" "" "" ocutalon ocutalon > /dev/null
  state_get
}

signin() { wait_until 60 signin_once || die "the README account could not sign in (the state does not answer)"; }

mock_lines() { dc exec -T iris cat "$MOCK_LOG" 2> /dev/null | wc -l | tr -d ' '; }
mock_dump() { dc exec -T iris cat "$MOCK_LOG" 2> /dev/null > "$1"; }

reminder_waiting() { # the ReminderTimer instances of the Ref that wait
  printf '%s\n' "Write !,\"CHK|w|\",##class(OcuTalon.Test.Schedule.ReminderFixture).WaitingCount(\"$1\")" 'Halt' | session_value OCUTALON w
}
approval_hold() { # the id of the live ApprovalHold of the Ref, or nothing
  printf '%s\n' "Write !,\"CHK|h|\",##class(OcuTalon.Bridge.Approval).LiveHold(\"$1\")" 'Halt' | session_value OCUTALON h
}

demo_row() { # the demo.mode row: "<Value>|<UpdatedAt>"
  printf '%s\n' 'Set r=##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode") Write !,"CHK|row|",$Select($IsObject(r):r.Value_"|"_r.UpdatedAt,1:"<none>")' 'Halt' | session_value OCUTALON row
}

# storage_snapshot <file>: one line per stored property slot of an OcuTalon class, sorted: the class, the data node, the slot, the
# property, its type and its collection from the compiled property (empty when the slot names no property).
storage_snapshot() {
  printf '%s\n' \
    'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT %ID,Name,Value FROM %Dictionary.CompiledStorageDataValue WHERE %ID %STARTSWITH ?","OcuTalon.")' \
    'While rs.%Next() { Set id=rs.%GetData(1),cls=$Piece(id,"||",1),node=$Piece(id,"||",3),slot=rs.%GetData(2),prop=rs.%GetData(3),type="",coll="" Set p=##class(%Dictionary.CompiledProperty).%OpenId(cls_"||"_prop) If $IsObject(p) { Set type=p.Type,coll=p.Collection } Write !,"CHK|slot|",cls,"|",node,"|",slot,"|",prop,"|",type,"|",coll }' \
    'Halt' | iris_script OCUTALON | LC_ALL=C sort -u > "$1"
  [ -s "$1" ]
}

# turn_is_done <clientId>: the chat turn with that id is done in the state (the state file is refreshed).
turn_is_done() { state_get && [ "$(state_turn "$tmp/state.json" "$1" | cut -d'|' -f1)" = done ]; }

# send_turn <clientId> <marker> <text>: POST /v1/messages with the marker of this run's key; 0 when accepted (202).
send_turn() {
  local body
  body=$(jq -cn --arg id "$1" --arg t "[[mock:$2:$key]] $3" '{clientId: $id, text: $t, fromGuide: false}')
  [ "$(api_post messages "$body")" = 202 ]
}

# run_turn <clientId> <marker> <text> <expected reply> <label>: sends the turn, waits for it to be done (120 s) with the mock's reply,
# and keeps the turn in the state's turns file for the later checks. Returns 1 after a FAIL line.
run_turn() {
  local id=$1 marker=$2 text=$3 want=$4 label=$5 got
  if ! send_turn "$id" "$marker" "$text"; then
    fail "$label: POST /v1/messages did not answer 202 (it answered something else)"
    return 1
  fi
  if ! wait_until 120 turn_is_done "$id"; then
    fail "$label: the turn was not done within 120 s"
    return 1
  fi
  got=$(state_turn "$tmp/state.json" "$id" | cut -d'|' -f2-)
  if [ "$got" != "$want" ]; then
    fail "$label: the reply is '$got', wanted '$want'"
    return 1
  fi
  printf '%s\t%s\n' "$id" "$want" >> "$state/turns.tsv"
  pass "$label: the turn is done with the mock's reply"
}

# The press of Break the feed: 200, or a 409 not_watching retried every 2 s for 20 s. Sets press_code.
press_feed() {
  local end=$((SECONDS + 20)) err
  while :; do
    press_code=$(api_post demo/break-feed '{}')
    if [ "$press_code" != 409 ]; then return 0; fi
    err=$(jq -r '.error.code // ""' "$tmp/post.body" 2> /dev/null)
    if [ "$err" != not_watching ] || [ "$SECONDS" -ge "$end" ]; then return 0; fi
    sleep 2
  done
}

# incident_waiting <incident ref to leave out>: sets found_incident to "incidentRef|requestRef" once a new incident awaits approval.
incident_waiting() {
  state_get || return 1
  found_incident=$(state_new_incident "$tmp/state.json" "${1:-}") || return 1
  [ -n "$found_incident" ]
}

# --- the throwaway stacks ---

# The context override of the previous build's tree: the next `up --build` builds the image from that tree's own Dockerfile.
add_previous_context() {
  printf 'services:\n  iris:\n    build:\n      context: %s\n      dockerfile: docker/Dockerfile\n' "$state/previous" > "$tmp/context.yml"
  live_add_file "$tmp/context.yml"
}

# build_up <label>: dc up -d --build of the stack as it is, then the container id; die on a failure.
build_up() {
  if ! dc up -d --build > "$tmp/up.log" 2>&1; then
    tail -n 30 "$tmp/up.log"
    die "$1: the build or the start failed"
  fi
  live_track_image
  cid=$(dc ps -q iris)
  [ -n "$cid" ] || die "$1: no iris container in project $P"
}

# ready_or_die <label> <seconds>: the start's log ends ready and Docker reports healthy, else the log's tail and a die.
ready_or_die() {
  if ! wait_started_ready "$2"; then
    start_log | tail -n 30 | cut -c1-200
    die "$1: the start did not end ready within $2 s"
  fi
}

# The version the previous build is installed as: its stamp, or its manifest version.
prev_installed() {
  local s
  s=$(opt stamp)
  printf '%s\n' "${s:-$(opt prev_version)}"
}

# save_stack: keeps the records project for the later calls (the pattern of ci/warm.sh warm_up): the compose files that live in $tmp are
# copied into p1/, with the lock file and its content, the project, the web port and the images to remove.
save_stack() {
  local d=$state/p1 f out=()
  mkdir -p "$d"
  cp "$tmp/decoy.env" "$d/decoy.env"
  printf 'services:\n  iris:\n    env_file:\n      - %s\n' "$d/decoy.env" > "$d/decoy.yml"
  for f in "${LIVE_FILES[@]}"; do
    case $f in
      "$tmp/decoy.yml") out+=("$d/decoy.yml") ;;
      "$tmp"/*)
        cp "$f" "$d/$(basename "$f")"
        out+=("$d/$(basename "$f")")
        ;;
      *) out+=("$f") ;;
    esac
  done
  printf '%s\n' "${out[@]}" > "$d/files"
  printf '%s' "$LIVE_LOCK_FILE" > "$d/lock.file"
  printf '%s' "$LIVE_LOCK_CONTENT" > "$d/lock.content"
  printf '%s\n' "$web_port" > "$d/web_port"
  printf '%s\n' ${LIVE_IMAGES[@]+"${LIVE_IMAGES[@]}"} > "$d/images"
  printf '%s\n' "$P" > "$d/project"
}

# attach_stack: points P and LIVE_FILES at the records project (the pattern of ci/warm.sh warm_attach). It starts nothing, claims no
# lock and checks that the lock file still holds the content that seed saved.
attach_stack() {
  local d=$state/p1 f held want
  [ -f "$d/project" ] || die "there is no records project for this tag: run seed first"
  P=$(cat "$d/project")
  LIVE_FILES=()
  while IFS= read -r f; do LIVE_FILES+=("$f"); done < "$d/files"
  LIVE_IMAGES=()
  web_port=$(cat "$d/web_port")
  base="http://127.0.0.1:$web_port"
  mgr=/durable/iris/mgr
  fails=0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-live.XXXXXX") || exit 1
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT TERM HUP
  deadline=$((SECONDS + ${OCUTALON_LIVE_DEADLINE:-540}))
  probe_file="$tmp/probe.n"
  echo "$(($(date +%s) * 1000))" > "$probe_file"
  jar="$tmp/jar"
  if [ -s "$d/lock.file" ]; then
    held=$(cat "$(cat "$d/lock.file")" 2> /dev/null)
    want=$(cat "$d/lock.content")
    if [ "$held" != "$want" ]; then die "the lane's throwaway lock no longer holds this run's content, so another run may have taken the lane"; fi
  fi
  cid=$(dc ps -q iris)
  [ -n "$cid" ] || die "the records project $P is not up"
}

# --- the families: seed and check hooks ---

family_on() { case " $HARNESS_ON " in *" $1 "*) return 0 ;; esac; return 1; }

# The pairing family is built as an off hook (Story 12.7 turns it on): it only writes its off row.
seed_pairing() { printf 'RECORD pairing off %s\n' "$PAIRING_OFF_TEXT" >> "$results"; }
check_pairing_upgrade() { printf 'RECORD pairing off %s\n' "$PAIRING_OFF_TEXT" >> "$results"; }
check_pairing_restart() { printf 'RECORD pairing off %s\n' "$PAIRING_OFF_TEXT" >> "$results"; }

seed_watch() {
  row watch
  if run_turn "$c_watch" watch-start-orders "Please watch the Orders production." "$REPLY_WATCH" "watch: the Orders watch is started"; then
    env_set "$state/seed.env" ok_watch 1
  fi
}

seed_approval() {
  row approval
  local expires
  if [ "$(env_get "$state/seed.env" ok_watch)" != 1 ]; then
    fail "approval: Break the feed was not pressed because the watch was not started"
    return
  fi
  press_feed
  if [ "$press_code" != 200 ]; then
    fail "approval: POST /v1/demo/break-feed answered $press_code ($(jq -r '.error.code // ""' "$tmp/post.body" 2> /dev/null))"
    return
  fi
  if ! wait_until 180 incident_waiting ""; then
    fail "approval: no incident awaits approval with a pending request within 180 s of the press"
    return
  fi
  inc_ref=${found_incident%%|*}
  req_ref=${found_incident#*|}
  expires=$(state_pending_approval "$tmp/state.json" "$req_ref") || expires=""
  if [ -z "$expires" ]; then
    fail "approval: the pending request $req_ref is not in the rail's approvals"
    return
  fi
  env_set "$state/seed.env" inc_ref "$inc_ref"
  env_set "$state/seed.env" req_ref "$req_ref"
  env_set "$state/seed.env" req_expires "${expires#*|}"
  env_set "$state/seed.env" hold_before "$(approval_hold "$req_ref")"
  env_set "$state/seed.env" ok_approval 1
  pass "approval: Break the feed gave an incident that awaits approval with one pending request, expiring ${expires#*|}"
  if [ -n "$(approval_hold "$req_ref")" ]; then
    pass "approval: the pending request has a live ApprovalHold"
  else
    fail "approval: the pending request has no live ApprovalHold"
  fi
}

# seed_reminder_one <marker> <client id> <text> <reply> <reminder text> <prefix>: sends one reminder turn and keeps the reminder's ref
# and due time in seed.env under the prefix (r1 or r2). Returns 1 after a FAIL line.
seed_reminder_one() {
  local card ref due
  run_turn "$2" "$1" "$3" "$4" "reminder $6: the turn that sets the reminder" || return 1
  if ! wait_until 30 state_get_reminder "$5"; then
    fail "reminder $6: no pending reminder with the text '$5' is in the rail"
    return 1
  fi
  card=$reminder_card
  ref=${card%%|*}
  due=${card#*|}
  env_set "$state/seed.env" "${6}_ref" "$ref"
  env_set "$state/seed.env" "${6}_due" "$due"
  env_set "$state/seed.env" "${6}_set_epoch" "$(date +%s)"
  if ! wait_until 30 waiting_is_one "$ref"; then
    fail "reminder $6: the reminder $ref (due $due) has no waiting ReminderTimer"
    return 1
  fi
  pass "reminder $6: $ref is pending, due $due, with one waiting ReminderTimer"
}

waiting_is_one() { [ "$(reminder_waiting "$1")" = 1 ]; }

state_get_reminder() { state_get && reminder_card=$(state_reminder_by_text "$tmp/state.json" "$1"); }

seed_reminder() {
  row reminder
  local ok=1
  seed_reminder_one upgrade-reminder-later "$c_r2" "Remind me tomorrow to review the upgrade notes." "$REPLY_R2" "$TEXT_R2" r2 || ok=0
  if [ "$ok" = 1 ]; then
    seed_reminder_one upgrade-reminder "$c_r1" "Remind me in a few minutes to check the upgrade." "$REPLY_R1" "$TEXT_R1" r1 || ok=0
  fi
  if [ "$ok" = 1 ]; then env_set "$state/seed.env" ok_reminder 1; fi
}

seed_conversation() {
  row conversation
  if run_turn "$c_fact" recall-tell "my build server is called ORION-7 ($fact)" "$REPLY_TELL" "conversation: the fact is told"; then
    env_set "$state/seed.env" ok_conversation 1
  fi
}

# --- build ---

phase_build() {
  row previous-build
  local prev=$state/previous kind
  kind=$pl_prev_kind
  mkdir -p "$prev"
  if ! git archive "$pl_prev_sha" | tar -x -C "$prev"; then die "previous build: git archive of $pl_prev_sha failed"; fi
  if [ ! -f "$prev/src/module.xml" ] || [ ! -f "$prev/docker/Dockerfile" ]; then die "previous build: the exported tree of $pl_prev_sha has no src/module.xml or docker/Dockerfile"; fi
  pass "previous build: the tree of the $kind build $pl_prev_sha is exported (version $pl_prev_version)"
  if [ -n "$pl_stamp" ]; then
    stamp_version "$prev/src/module.xml" "$pl_stamp" > "$prev/src/module.xml.new" && mv "$prev/src/module.xml.new" "$prev/src/module.xml"
    if [ "$(manifest_version "$prev/src/module.xml")" = "$pl_stamp" ]; then
      pass "previous build: its version is stamped $pl_stamp (the candidate is $pl_cand_version)"
    else
      die "previous build: the stamp $pl_stamp did not reach its manifest"
    fi
  else
    pass "previous build: its version $pl_prev_version differs from the candidate's $pl_cand_version, so it is not stamped"
  fi
  if [ -f "$prev/src/ocutalon/csp/index.html" ]; then
    pass "previous build: the tree has its web bundle"
  else
    if ! command -v node > /dev/null 2>&1 || ! command -v npm > /dev/null 2>&1; then die "previous build: node and npm are needed to build the web bundle of the previous tree"; fi
    if ! (cd "$prev/web" && npm ci --no-audit --no-fund) > "$state/npm-ci.log" 2>&1; then
      tail -n 15 "$state/npm-ci.log"
      die "previous build: npm ci of the previous tree's web folder failed"
    fi
    if ! (cd "$prev/web" && npm run build) > "$state/npm-build.log" 2>&1; then
      tail -n 15 "$state/npm-build.log"
      die "previous build: the web bundle of the previous tree did not build"
    fi
    if [ ! -f "$prev/src/ocutalon/csp/index.html" ]; then die "previous build: the build left no src/ocutalon/csp/index.html in the previous tree"; fi
    pass "previous build: the web bundle is built from the previous tree's own web folder"
  fi
}

# --- settings: project 1 ---

phase_settings() {
  family_on settings || return 0
  row previous-build
  local outcome row0 row1 code installed_prev=$(prev_installed) cand=$(opt version) ipm
  stack_start upgset
  live_web_port || exit 1
  base="http://127.0.0.1:$web_port"
  probe_file="$tmp/probe.n"
  echo "$(($(date +%s) * 1000))" > "$probe_file"
  jar="$tmp/jar"
  add_previous_context
  echo "STACK settings: project $P (previous build $installed_prev)"
  build_up "settings project"
  ready_or_die "settings project, previous build" 400
  check_installed "settings project, previous build" "$installed_prev"

  row settings
  outcome=$(printf '%s\n' 'Set r=##class(OcuTalon.Core.Admin).SetDemoMode(0)' 'Write !,"CHK|outcome|",r.Outcome' 'Halt' | session_value OCUTALON outcome)
  if [ "$outcome" = off ]; then
    pass "settings: SetDemoMode(0) answered off under the previous build"
  else
    die "settings: SetDemoMode(0) answered '$outcome', wanted off"
  fi
  row0=$(demo_row)
  case $row0 in
    0\|*) pass "settings: the demo.mode row is 0 (written $(printf '%s' "$row0" | cut -d'|' -f2))" ;;
    *) die "settings: the demo.mode row is '$row0' after the switch" ;;
  esac

  row upgrade
  live_pop_file
  echo "UPGRADE settings project to $cand"
  build_up "settings project"
  ready_or_die "settings project, candidate" 400
  ipm=$(sed -n 's:.*ipmwant="\([^"]*\)".*:\1:p' docker/after-start.cos | head -n 1)
  expected_run "cleared" "present $ipm" "already mapped" "ok" "loaded (version $installed_prev to $cand)" "$cand" > "$tmp/expected.settings"
  check_log "settings project upgrade" "$tmp/expected.settings"
  check_installed "settings project, candidate" "$cand"

  row settings
  row1=$(demo_row)
  if [ "$row1" = "$row0" ]; then
    pass "settings: the demo.mode row is unchanged by the upgrade ($row1)"
  else
    fail "settings: the demo.mode row is '$row1' after the upgrade, was '$row0'"
  fi
  check_demo_off "settings after the upgrade"
  signin
  if [ "$(state_demo_mode "$tmp/state.json")" = false ]; then
    pass "settings: /state reports demoMode false"
  else
    fail "settings: /state reports demoMode '$(state_demo_mode "$tmp/state.json")', wanted false"
  fi
  code=$(api_post demo/break-feed '{}')
  if [ "$code" = 404 ] && grep -q '"not_found"' "$tmp/post.body"; then
    pass "settings: POST /v1/demo/break-feed answers 404 not_found"
  else
    fail "settings: POST /v1/demo/break-feed answered '$code', wanted 404"
  fi
  e2e_demo_off
  logout_all "$jar" /ocutalon/api/
}

# e2e_demo_off: the demo-switch page project with the stack's demo mode 0 (web/e2e/demo-switch).
e2e_demo_off() {
  local left=$(((deadline - SECONDS - 20) * 1000))
  if [ "$left" -lt 60000 ]; then
    fail "settings: only $((left / 1000)) s are left of the deadline for the page project"
    return 1
  fi
  if ! npx --prefix web playwright install chromium > "$tmp/pw.log" 2>&1; then
    tail -n 15 "$tmp/pw.log"
    fail "settings: the Chromium of the page project could not be installed"
    return 1
  fi
  if OCUTALON_URL="$base" OCUTALON_E2E_DEMO_MODE=0 OCUTALON_E2E_TIMEOUT_MS="$left" npm --prefix web run e2e:demo-switch > "$tmp/e2e.log" 2>&1; then
    pass "settings: the page shows no badge and the chat region with demo mode off ($(grep -Eo '[0-9]+ passed' "$tmp/e2e.log" | tail -n 1))"
  else
    tail -n 40 "$tmp/e2e.log" | sed 's/^/  /'
    fail "settings: the demo-switch page specs failed with demo mode off"
  fi
}

# --- seed: project 2 ---

phase_seed() {
  row previous-build
  seeding=1
  local installed_prev=$(prev_installed)
  : > "$state/seed.env"
  env_set "$state/seed.env" ok_watch 0
  stack_start upgrade
  live_web_port || exit 1
  base="http://127.0.0.1:$web_port"
  probe_file="$tmp/probe.n"
  echo "$(($(date +%s) * 1000))" > "$probe_file"
  jar="$tmp/jar"
  add_previous_context
  echo "STACK seed: project $P (previous build $installed_prev)"
  build_up "records project"
  ready_or_die "records project, previous build" 400
  check_installed "records project, previous build" "$installed_prev"
  if [ "$(keys_point)" = 1 ]; then
    pass "previous build: the runners' keys point at the mock"
  else
    die "previous build: the runners' keys could not be pointed at the mock"
  fi
  set_probes
  key=u$(hexpw | head -c 12)
  fact=zz$key
  env_set "$state/seed.env" key "$key"
  env_set "$state/seed.env" fact "$fact"
  c_watch=up-$key-1
  c_r2=up-$key-2
  c_r1=up-$key-3
  c_fact=up-$key-4
  env_set "$state/seed.env" c_watch "$c_watch"
  env_set "$state/seed.env" c_r2 "$c_r2"
  env_set "$state/seed.env" c_r1 "$c_r1"
  env_set "$state/seed.env" c_fact "$c_fact"
  : > "$state/turns.tsv"
  signin
  if family_on watch; then seed_watch; fi
  if family_on approval; then seed_approval; fi
  if family_on reminder; then seed_reminder; fi
  if family_on conversation; then seed_conversation; fi
  if family_on pairing; then seed_pairing; fi
  row previous-build
  if storage_snapshot "$state/storage.prev"; then
    pass "previous build: the storage snapshot is taken ($(wc -l < "$state/storage.prev" | tr -d ' ') slot lines)"
  else
    fail "previous build: the storage snapshot is empty"
  fi
  logout_all "$jar" /ocutalon/api/
  save_stack
  trap - EXIT INT TERM HUP
  rm -rf "$tmp"
}

# --- upgrade: project 2 ---

# r1_fired: the R1 reminder has left the rail and a reminder notice is in the chat.
r1_fired() {
  state_get || return 1
  [ -z "$(state_reminder_card "$tmp/state.json" "$r1_ref")" ] && r1_notice=$(state_notice "$tmp/state.json" reminder "$TEXT_R1")
}

# turns_intact: every turn of the state's turns file is in /state with its reply; prints the number of turns.
turns_intact() {
  local id want got n=0 bad=0
  state_get || return 1
  while IFS="$(printf '\t')" read -r id want; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    got=$(state_turn "$tmp/state.json" "$id")
    if [ "$got" != "done|$want" ]; then
      bad=$((bad + 1))
      echo "  turn $id is '$got', wanted 'done|$want'"
    fi
  done < "$state/turns.tsv"
  turns_count=$n
  [ "$bad" -eq 0 ] && [ "$n" -gt 0 ]
}

# ask_again <client id> <label>: a recall-ask turn after a mark of the mock log: done with the scenario's answer, and the first chat
# request after the mark carries the fact told before the upgrade.
ask_again() {
  local id=$1 label=$2 mark
  mark=$(mock_lines)
  if ! send_turn "$id" recall-ask "What is my build server called?"; then
    fail "$label: POST /v1/messages did not answer 202 for the question"
    return 1
  fi
  if ! wait_until 120 turn_is_done "$id"; then
    fail "$label: the question was not done within 120 s"
    return 1
  fi
  mock_dump "$tmp/mock.log"
  chat_request_report "$tmp/mock.log" "$mark" "recall-ask:$key" "$fact" | sed 's/^/INFO Task 0 (d) recall-ask /'
  if [ "$(state_turn "$tmp/state.json" "$id" | cut -d'|' -f2-)" = "$REPLY_ASK" ]; then
    pass "$label: the question is done with the scenario's answer"
  else
    fail "$label: the answer is '$(state_turn "$tmp/state.json" "$id" | cut -d'|' -f2-)', wanted '$REPLY_ASK'"
  fi
  if chat_request_carries "$tmp/mock.log" "$mark" "recall-ask:$key" "$fact"; then
    pass "$label: the chat agent's request carries the fact told before ($fact)"
  else
    fail "$label: the chat agent's request does not carry the fact told before"
  fi
  printf '%s\t%s\n' "$id" "$REPLY_ASK" >> "$state/turns.tsv"
}

check_conversation_upgrade() {
  row conversation
  if [ "$(env_get "$state/seed.env" ok_conversation)" != 1 ]; then
    fail "conversation: the fact was not told in the seed, so there is nothing to check"
    return
  fi
  if turns_intact; then
    pass "conversation: all $turns_count seeded turns are in /state with their replies"
  else
    fail "conversation: a seeded turn is missing from /state or differs"
  fi
  ask_again "up-$key-5" "conversation after the upgrade"
}

check_approval_upgrade() {
  row approval
  local now
  if [ "$(env_get "$state/seed.env" ok_approval)" != 1 ]; then
    fail "approval: no pending request was seeded, so there is nothing to check"
    return
  fi
  state_get || { fail "approval: /state does not answer"; return; }
  now=$(state_pending_approval "$tmp/state.json" "$req_ref") || now=""
  if [ "$now" = "$req_ref|$req_expires" ]; then
    pass "approval: the request is still pending with its original expiry ($req_expires)"
  else
    fail "approval: the pending request is '$now', wanted '$req_ref|$req_expires'"
    return
  fi
  if [ "$(api_post "approvals/$req_ref/answer" '{"action":"approve","channel":"phone"}')" = 200 ]; then
    pass "approval: approving on the phone channel answered 200"
  else
    fail "approval: approving answered something other than 200 ($(jq -r '.error.code // ""' "$tmp/post.body" 2> /dev/null))"
    return
  fi
  if wait_until 120 approval_resolved; then
    pass "approval: the incident is resolved with {total 50, completed 50, failedAgain 0} and the phone says '$TEXT_RESULT'"
  else
    fail "approval: within 120 s the incident was '$(state_incident "$tmp/state.json" "$inc_ref")' and the phone item '$TEXT_RESULT' was $(state_phone_has "$tmp/state.json" "$TEXT_RESULT" && echo there || echo missing)"
  fi
}

approval_resolved() {
  state_get || return 1
  [ "$(state_incident "$tmp/state.json" "$inc_ref")" = "resolved|50|50|0" ] && state_phone_has "$tmp/state.json" "$TEXT_RESULT"
}

check_watch_upgrade() {
  row watch
  local orders
  if [ "$(env_get "$state/seed.env" ok_watch)" != 1 ]; then
    fail "watch: the watch was not started in the seed, so there is nothing to check"
    return
  fi
  state_get || { fail "watch: /state does not answer"; return; }
  orders=$(state_checks_orders "$tmp/state.json") || orders=""
  if [ -n "$orders" ]; then
    pass "watch: the rail lists the Orders check ($orders)"
  else
    fail "watch: the rail lists no Orders check"
    return
  fi
  press_feed
  if [ "$press_code" != 200 ]; then
    fail "watch: a new press answered $press_code ($(jq -r '.error.code // ""' "$tmp/post.body" 2> /dev/null)), wanted 200"
    return
  fi
  if wait_until 180 incident_waiting "$inc_ref"; then
    ref2=${found_incident#*|}
    inc2=${found_incident%%|*}
    expires2=$(state_pending_approval "$tmp/state.json" "$ref2" | cut -d'|' -f2)
    env_set "$state/upgrade.env" inc2 "$inc2"
    env_set "$state/upgrade.env" ref2 "$ref2"
    env_set "$state/upgrade.env" expires2 "$expires2"
    env_set "$state/upgrade.env" hold2 "$(approval_hold "$ref2")"
    pass "watch: a new press gave a new incident $inc2 that awaits approval with the pending request $ref2 (expires $expires2)"
  else
    fail "watch: no new incident awaits approval within 180 s of the new press"
  fi
}

check_reminder_upgrade() {
  row reminder
  local expect fired_by kind
  if [ "$(env_get "$state/seed.env" ok_reminder)" != 1 ]; then
    fail "reminder: the reminders were not seeded, so there is nothing to check"
    return
  fi
  if [ -z "$r1_due_epoch" ]; then
    fail "reminder: R1's dueAt '$r1_due' is not a UTC time"
    return
  fi
  expect=$(reminder_expect "$r1_due_epoch" "$ready_epoch")
  if [ "$r1_due_epoch" -lt "$began_epoch" ]; then
    fail "reminder: R1 was due $((began_epoch - r1_due_epoch)) s before the upgrade began: the phases ran too far apart"
    return
  fi
  fired_by=$((r1_due_epoch + 90 - $(date +%s)))
  if [ "$fired_by" -lt 5 ]; then fired_by=5; fi
  if ! wait_until "$fired_by" r1_fired; then
    fail "reminder: R1 ($r1_ref, due $r1_due) did not fire by its due time + 90 s"
    return
  fi
  pass "reminder: R1 left the rail and the chat holds its notice: $r1_notice"
  case $r1_notice in
    "Reminder (late; "*) kind=late ;;
    "Reminder: $TEXT_R1.") kind=on-time ;;
    *) kind="" ;;
  esac
  if [ -z "$kind" ]; then
    fail "reminder: the notice '$r1_notice' is neither the on-time nor the late text"
  elif [ "$expect" = either ] || [ "$expect" = "$kind" ]; then
    pass "reminder: the notice is $kind, which a reminder due $(due_phrase "$r1_due_epoch" "$ready_epoch") allows ($expect)"
    note_row "R1 fired $kind (due $(due_phrase "$r1_due_epoch" "$ready_epoch"))"
  else
    fail "reminder: the notice is $kind, but a reminder due $(due_phrase "$r1_due_epoch" "$ready_epoch") must be $expect"
  fi
}

check_upgrade_log() {
  row upgrade
  local ipm cand=$(opt version) prev=$(prev_installed) bad ref refs=()
  ipm=$(sed -n 's:.*ipmwant="\([^"]*\)".*:\1:p' docker/after-start.cos | head -n 1)
  expected_run "cleared" "present $ipm" "already mapped" "ok" "loaded (version $prev to $cand)" "$cand" > "$tmp/expected.upgrade"
  check_log "records project upgrade" "$tmp/expected.upgrade"
  check_installed "records project, candidate" "$cand"
  for ref in "$req_ref" "$r1_ref" "$r2_ref"; do
    if [ -n "$ref" ]; then refs+=(-e "$ref"); fi
  done
  if [ "${#refs[@]}" -gt 0 ]; then
    bad=$(start_log | grep -F 'WARN Reconcile' | grep -F "${refs[@]}" | head -n 3)
    if [ -z "$bad" ]; then
      pass "upgrade: no WARN Reconcile line names a seeded reference"
    else
      printf '%s\n' "$bad" | cut -c1-200
      fail "upgrade: Reconcile warned about a seeded reference"
    fi
  fi
  if [ -n "$req_ref" ]; then
    hold_after=$(approval_hold "$req_ref")
    if [ -n "$hold_after" ]; then
      pass "upgrade: the pending request has a live ApprovalHold"
    else
      fail "upgrade: the pending request has no live ApprovalHold after the upgrade"
    fi
    echo "INFO Task 0 (e) the ApprovalHold before: '$hold_before', after: '$hold_after' ($([ "$hold_before" = "$hold_after" ] && echo kept || echo re-armed))"
  fi
  if [ -n "$r2_ref" ]; then
    if [ "$(reminder_waiting "$r2_ref")" = 1 ]; then
      pass "upgrade: R2 has one waiting ReminderTimer"
    else
      fail "upgrade: R2 ($r2_ref) has no waiting ReminderTimer after the upgrade"
    fi
  fi
  if [ -n "$r1_ref" ]; then
    if [ "$(reminder_waiting "$r1_ref")" = 1 ]; then
      pass "upgrade: R1 has one waiting ReminderTimer"
    elif [ "$(date +%s)" -ge "$r1_due_epoch" ]; then
      pass "upgrade: R1 is due or fired already (its waiter has ended)"
    else
      fail "upgrade: R1 ($r1_ref) is not due yet and has no waiting ReminderTimer"
    fi
  fi
}

check_private_globals() {
  row private-globals
  local out
  check_probes "after the upgrade (written under the previous build)"
  out=$(printf '%s\n' 'Set sc=##class(OcuTalon.Install.Step.PrivateData).Run()' 'Write !,"CHK|private|",$SYSTEM.Status.IsOK(sc)' \
    'If $SYSTEM.Status.IsError(sc) Write !,"CHK|reason|",$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  ")' 'Halt' | iris_script OCUTALON)
  if printf '%s\n' "$out" | grep -qx 'CHK|private|1'; then
    pass "private globals: PrivateData.Run() is OK"
  else
    printf '%s\n' "$out" | sed -n 's/^CHK|reason|/  /p' | cut -c1-200
    fail "private globals: PrivateData.Run() failed"
  fi
}

load_seed() {
  key=$(env_get "$state/seed.env" key)
  fact=$(env_get "$state/seed.env" fact)
  req_ref=$(env_get "$state/seed.env" req_ref)
  req_expires=$(env_get "$state/seed.env" req_expires)
  inc_ref=$(env_get "$state/seed.env" inc_ref)
  hold_before=$(env_get "$state/seed.env" hold_before)
  r1_ref=$(env_get "$state/seed.env" r1_ref)
  r1_due=$(env_get "$state/seed.env" r1_due)
  r2_ref=$(env_get "$state/seed.env" r2_ref)
  r2_due=$(env_get "$state/seed.env" r2_due)
  r1_due_epoch=$(iso_epoch "${r1_due:-1970-01-01T00:00:00Z}")
}

phase_upgrade() {
  row upgrade
  local cand=$(opt version) began last
  attach_stack
  load_seed
  began=$(date +%s)
  began_epoch=$began
  last=$(tail -n 1 "$state/p1/files")
  case $last in */context.yml) live_pop_file ;; *) die "the last compose file of the records project is not the previous build's context" ;; esac
  echo "UPGRADE records project to $cand"
  if ! dc build > "$tmp/build.log" 2>&1; then
    tail -n 30 "$tmp/build.log"
    die "upgrade: the candidate image did not build"
  fi
  live_track_image
  printf '%s\n' ${LIVE_IMAGES[@]+"${LIVE_IMAGES[@]}"} >> "$state/p1/images"
  recreate_epoch=$(date +%s)
  if ! dc up -d --no-build > "$tmp/up.log" 2>&1; then
    tail -n 30 "$tmp/up.log"
    die "upgrade: the candidate container did not start"
  fi
  cid=$(dc ps -q iris)
  [ -n "$cid" ] || die "upgrade: no iris container in project $P"
  if ! wait_started_ready 400; then
    start_log | tail -n 30 | cut -c1-200
    die "upgrade: the candidate did not end ready within 400 s"
  fi
  ready_epoch=$(iso_epoch "$(start_log | tail -n 1 | sed -n 's/^AFTER-START end \([0-9T:Z-]*\) ready.*/\1/p')")
  if [ -z "$ready_epoch" ]; then
    echo "INFO the candidate's ready time could not be read from its log: the time of this check stands in for it"
    ready_epoch=$(date +%s)
  fi
  env_set "$state/upgrade.env" ready_epoch "$ready_epoch"
  env_set "$state/upgrade.env" recreate_epoch "$recreate_epoch"
  echo "INFO Task 0 (a) the candidate image built and started in $((ready_epoch - began)) s (build until recreate $((recreate_epoch - began)) s)"
  echo "INFO Task 0 (c) R1 was set $((ready_epoch - $(env_get "$state/seed.env" r1_set_epoch))) s before the candidate was ready (R1 delay 300 s)"
  if ! storage_snapshot "$state/storage.cand"; then
    row storage
    fail "storage: the candidate's storage snapshot is empty"
  fi
  row upgrade
  if [ "$(keys_point)" = 1 ]; then
    pass "upgrade: the runners' keys point at the mock"
  else
    die "upgrade: the runners' keys could not be pointed at the mock"
  fi
  check_upgrade_log
  check_private_globals
  row upgrade
  signin
  if family_on conversation; then check_conversation_upgrade; fi
  if family_on approval; then check_approval_upgrade; fi
  if family_on watch; then check_watch_upgrade; fi
  if family_on reminder; then check_reminder_upgrade; fi
  if family_on pairing; then check_pairing_upgrade; fi
  logout_all "$jar" /ocutalon/api/
}

# --- restart ---

phase_restart() {
  row restart
  local cand=$(opt version) now
  attach_stack
  load_seed
  ref2=$(env_get "$state/upgrade.env" ref2)
  expires2=$(env_get "$state/upgrade.env" expires2)
  echo "RESTART records project (docker compose restart iris)"
  if ! dc restart iris > "$tmp/restart.log" 2>&1; then
    tail -n 20 "$tmp/restart.log"
    die "restart: docker compose restart iris failed"
  fi
  if ! wait_started_ready 300; then
    start_log | tail -n 30 | cut -c1-200
    die "restart: the container was not ready within 300 s"
  fi
  if [ "$(marker)" = "$cand" ]; then
    pass "restart: the ready marker equals $cand"
  else
    fail "restart: the ready marker is '$(marker)', wanted $cand"
  fi
  if [ "$(keys_point)" = 1 ]; then
    pass "restart: the runners' keys point at the mock"
  else
    die "restart: the runners' keys could not be pointed at the mock"
  fi
  signin
  if family_on conversation; then
    if [ "$(env_get "$state/seed.env" ok_conversation)" = 1 ]; then
      if turns_intact; then
        pass "restart: all $turns_count earlier turns are in /state with their replies"
      else
        fail "restart: an earlier turn is missing from /state or differs"
      fi
      ask_again "up-$key-6" "restart"
    else
      fail "restart: the fact was not told in the seed, so the conversation cannot be checked"
    fi
  fi
  if family_on watch; then
    if state_get && [ -n "$(state_checks_orders "$tmp/state.json")" ]; then
      pass "restart: Orders is still listed in the rail's checks"
    else
      fail "restart: Orders is not listed in the rail's checks"
    fi
  fi
  state_get || fail "restart: /state does not answer"
  if family_on reminder; then
    now=$(state_reminder_card "$tmp/state.json" "$r2_ref") || now=""
    if [ "$now" = "$r2_ref|$r2_due|pending" ]; then
      pass "restart: R2 is pending with the same due time ($r2_due)"
    else
      fail "restart: R2 is '$now', wanted '$r2_ref|$r2_due|pending'"
    fi
    if [ "$(reminder_waiting "$r2_ref")" = 1 ]; then
      pass "restart: R2 has one waiting ReminderTimer"
    else
      fail "restart: R2 has no waiting ReminderTimer"
    fi
  fi
  if family_on approval; then
    now=$(state_pending_approval "$tmp/state.json" "$ref2") || now=""
    if [ -z "$ref2" ]; then
      fail "restart: the upgrade left no second pending request to check (the watch check did not get a new incident)"
    elif [ "$now" = "$ref2|$expires2" ]; then
      pass "restart: the second request is pending with the same expiry ($expires2)"
    else
      fail "restart: the second request is '$now', wanted '$ref2|$expires2'"
    fi
    if [ -n "$ref2" ]; then
      if [ -n "$(approval_hold "$ref2")" ]; then
        pass "restart: the second request has a live ApprovalHold"
      else
        fail "restart: the second request has no live ApprovalHold"
      fi
    fi
  fi
  if family_on pairing; then check_pairing_restart; fi
  logout_all "$jar" /ocutalon/api/
}

# --- storage ---

# release_diff_verdict_ok <verdict line> <base commit>: the line is the passing verdict of test-storage.sh judged against that commit.
release_diff_verdict_ok() {
  case $1 in
    "PASS release-diff: the storage blocks only grew since $2"*) return 0 ;;
    *) return 1 ;;
  esac
}

phase_storage() {
  row storage
  local out line sha missing
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-live.XXXXXX") || exit 1
  trap 'rm -rf "$tmp"' EXIT
  sha=$(opt prev_sha)
  if missing=$(storage_compare "$state/storage.prev" "$state/storage.cand"); then
    pass "storage: every slot line of the previous build is in the candidate's ($(wc -l < "$state/storage.prev" | tr -d ' ') lines)"
  else
    printf '%s\n' "$missing" | head -n 10 | sed 's/^/  /'
    fail "storage: a slot line of the previous build is missing from the candidate: $(printf '%s\n' "$missing" | head -n 1)"
  fi
  out=$(OCUTALON_STORAGE_BASE=$sha bash docker/tests/test-storage.sh 2>&1)
  line=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL) release-diff' | head -n 1)
  if release_diff_verdict_ok "$line" "$sha"; then
    pass "storage: $line"
  else
    printf '%s\n' "$out" | tail -n 12 | sed 's/^/  /'
    fail "storage: the release-diff rule against $sha: ${line:-no verdict line}"
  fi
}

# --- report and down ---

phase_report() {
  local record file n ph
  env_set "$state/options" ended "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  : > "$state/results"
  for ph in build settings seed upgrade restart storage; do
    if [ -f "$state/results.$ph" ]; then cat "$state/results.$ph" >> "$state/results"; fi
  done
  record_section "$state/results" "$state/options" > "$state/section.md"
  record=$(opt record)
  file=$record
  case $file in /*) ;; *) file=$harness_root/$file ;; esac
  record_write "$file" "$state/section.md" "$(record_title)"
  n=$(record_result "$state/results")
  echo "RECORD $record"
  echo "RESULT $n"
  if [ "$n" != pass ]; then fails=$((${fails:-0} + 1)); fi
}

cmd_down() {
  local d=$state/p1 img
  cmd_teardown
  if [ -f "$d/lock.file" ] && [ -s "$d/lock.file" ]; then
    LIVE_LOCK_FILE=$(cat "$d/lock.file")
    LIVE_LOCK_CONTENT=$(cat "$d/lock.content")
    P=$(cat "$d/project" 2> /dev/null)
    live_lock_release
  fi
  if [ -f "$d/images" ]; then
    while IFS= read -r img; do
      [ -n "$img" ] || continue
      docker image rm -f "$img" > /dev/null 2>&1
    done < "$d/images"
  fi
  rm -rf "$state"
}

# --- the commands ---

harness_usage() {
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$harness_root/release/upgrade-harness.sh" >&2
}

cmd_plan() {
  local d file
  parse_options "$@" || exit 2
  resolve_plan 1 || exit 2
  echo "PLAN candidate $pl_cand_version at $pl_cand_sha"
  echo "PLAN previous $pl_prev_kind $pl_prev_ref at $pl_prev_sha, version $pl_prev_version, built as ${pl_stamp:-$pl_prev_version}"
  echo "PLAN mode dry run (a run would be: $(mode_for 0 "$opt_rehearsal" "$pl_dirty")); required $pl_required"
  echo "PLAN phases build settings seed upgrade restart storage report down; families $HARNESS_ON; held back $HARNESS_OFF"
  echo "PLAN record $pl_record"
  d=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-plan.XXXXXX") || exit 1
  options_write "$d/options"
  record_section /dev/null "$d/options" > "$d/section.md"
  file=$pl_record
  case $file in /*) ;; *) file=$harness_root/$file ;; esac
  record_write "$file" "$d/section.md" "# OcuTalon $pl_cand_version${opt_rc:+ rc$opt_rc}"
  rm -rf "$d"
  echo "RECORD $pl_record"
  echo "RESULT not run"
  exit 0
}

cmd_phase() {
  local ph=$1 rc
  shift
  if [ "$ph" != build ] && [ $# -gt 0 ]; then
    harness_usage
    exit 2
  fi
  if [ -z "${OCUTALON_RUN_TAG:-}" ]; then
    echo "REFUSED $ph: it needs OCUTALON_RUN_TAG, the tag of the run"
    exit 2
  fi
  if ! live_tag_ok "$OCUTALON_RUN_TAG"; then
    echo "FAIL OCUTALON_RUN_TAG '$OCUTALON_RUN_TAG' $LIVE_TAG_RULE"
    exit 2
  fi
  export OCUTALON_RUN_TAG
  state=$(state_dir "$OCUTALON_RUN_TAG")
  if [ "$ph" = build ]; then
    parse_options "$@" || exit 2
  fi
  if ! phase_ready "$state" "$ph"; then exit 2; fi
  if [ "$ph" = down ]; then
    cmd_down
    exit 0
  fi
  fails=0
  if [ "$ph" = build ]; then
    rm -rf "$state"
    mkdir -p "$state"
    resolve_plan 0 || exit 2
    options_write "$state/options"
  fi
  # A phase writes its own results file, so that a phase run again leaves nothing of its earlier try; report joins them.
  results=$state/results.$ph
  : > "$results"
  run_phase "$ph"
  rc=$?
  exit "$rc"
}

# run_phase <phase>: marks the phase failed, runs it, marks it done, and prints its PHASE line. A phase that dies keeps the failed mark.
run_phase() {
  local ph=$1 began=$SECONDS
  phase_mark "$ph" failed 0
  "phase_$ph"
  phase_mark "$ph" done "$((SECONDS - began))"
  echo "PHASE $ph done $((SECONDS - began))s (${fails:-0} failed)"
  [ "${fails:-0}" -eq 0 ]
}

cmd_run() {
  local me=$harness_root/release/upgrade-harness.sh rc=0 ph build_args
  if [ -z "${OCUTALON_RUN_TAG:-}" ]; then
    OCUTALON_RUN_TAG="upg-$(date +%s)"
  fi
  export OCUTALON_RUN_TAG
  parse_options "$@" || exit 2
  build_args=()
  if [ -n "$opt_version" ]; then build_args+=(--version "$opt_version"); fi
  if [ -n "$opt_rc" ]; then build_args+=(--rc "$opt_rc"); fi
  if [ -n "$opt_previous" ]; then build_args+=(--previous "$opt_previous"); fi
  if [ "$opt_rehearsal" = 1 ]; then build_args+=(--rehearsal); fi
  if [ -n "$opt_record" ]; then build_args+=(--record "$opt_record"); fi
  if ! bash "$me" build "${build_args[@]}"; then
    bash "$me" down
    exit 2
  fi
  for ph in settings seed upgrade restart storage; do
    bash "$me" "$ph" || rc=1
  done
  bash "$me" report || rc=1
  bash "$me" down
  exit "$rc"
}

main() {
  local cmd=${1:-}
  if [ $# -gt 0 ]; then shift; fi
  case $cmd in
    plan) cmd_plan "$@" ;;
    run) cmd_run "$@" ;;
    build | settings | seed | upgrade | restart | storage | report | down) cmd_phase "$cmd" "$@" ;;
    *)
      harness_usage
      exit 2
      ;;
  esac
}

# Sourced (by docker/tests/test-upgrade-harness.sh), it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

main "$@"
