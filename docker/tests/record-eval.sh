#!/usr/bin/env bash
# Records the evaluation set's incidents. Not a CI unit and not a check: nothing runs it but a person, and its name is not test-*.
#   bash docker/tests/record-eval.sh        records eval/orders-date-format/snapshot.json (Story 0.10)
#   bash docker/tests/record-eval.sh feed   records the nine incidents of the test feed (Story 9.9), eval/<name>/case.json and snapshot.json
#   bash docker/tests/record-eval.sh no-evidence   records eval/orders-date-no-evidence/case.json and snapshot.json (Story 39.6, DW-653)
# Any other argument exits 2 before anything starts. Each mode starts one throwaway project of its own (docker/tests/lib-live.sh, the
# throwaway and CI overrides, no key and no host port), waits for a ready start, and ends with an EXIT trap that removes the project
# with its volume and images.
# The default mode has OcuTalon.Test.Demo.Production.Record send one real batch of 50 orders (order date MM/DD/YYYY, written
# 2026-10-16) into the Orders production, wait for its 50 failures at OrdersFromPartner and write the reader snapshot of them. The file is
# passed through jq, so it is written pretty-printed, and replaced only when it holds the 50 failures, is ASCII and names no home folder
# (test-boundaries.sh scans the committed file for every local machine path). Prints the number of failures it recorded.
# The feed mode has OcuTalon.Test.Eval.Feed.Fixture.Record install the test feed in its own namespace of the throwaway, send its cases,
# record each with OcuTalon.Eval.Record (the case and the reader's snapshot, redacted) and remove the feed again. Each of the two files of
# each case is copied out with jq, so it is written pretty-printed. Nothing is written unless the recording succeeded and every file is
# JSON, is ASCII and names no home folder, and no case is orders-date-format (the default mode records that one); then every
# eval/<name>/ is written and "record-eval: <n> feed cases written" is printed.
# The feed mode also dies on a feed case named orders-date-no-evidence, which the no-evidence mode records.
# The no-evidence mode has OcuTalon.Test.Eval.Record.RecordNoEvidence hold the Orders failures, send 3 orders from the simulated partner dated
# 03/05/2026 (MM/DD/YYYY, a date that reads both ways, on an arrival day that matches neither reading), record their failures with
# OcuTalon.Eval.Record as the case orders-date-no-evidence (a data-format change at OrderDate with no fix, Story 7.7) and release the hold and
# remove the batch. Its two files are copied out with jq and checked as the feed mode's are (JSON, not empty, ASCII, no home folder); then
# eval/orders-date-no-evidence/ is written and "record-eval: eval/orders-date-no-evidence written" is printed.
# Every mode exits 0 only when its files were written, and 1 when it refuses or fails.
# Test.Eval.Record re-induces every committed incident, the Orders demo's and the feed's, on every CI run and compares the evidence pack of
# each committed snapshot with a fresh recording's. Rerun this script (the mode of the incident) whenever TestSnapshotIsReadableAndCurrent (the
# demo's snapshot) or Test.Eval.Record's TestCommittedIsCurrent reports that a fresh recording differs from the committed one because the
# production or the feed changed, then commit the files.
# Needs docker compose, jq, and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

mode=demo
if [ "$#" -eq 1 ] && [ "$1" = feed ]; then
  mode=feed
elif [ "$#" -eq 1 ] && [ "$1" = no-evidence ]; then
  mode=noevidence
elif [ "$#" -gt 0 ]; then
  echo "usage: record-eval.sh [feed|no-evidence]" >&2
  exit 2
fi

. "$(dirname "$0")/lib-live.sh"

repo=$(cd "$(dirname "$0")/../.." && pwd)
# copy_out <file in the container> <local file> <label>: copies the file out through jq (pretty-printed) and dies unless it is JSON, is not empty,
# is ASCII and names no home folder.
copy_out() {
  if ! dc exec -T iris cat "$1" | tr -d '\r' | jq . > "$2"; then die "$3 is not JSON"; fi
  if [ ! -s "$2" ]; then die "$3 is empty"; fi
  if LC_ALL=C grep -q '[^ -~]' "$2"; then die "$3 holds a character that is not ASCII"; fi
  if grep -q '/Users/\|/home/' "$2"; then die "$3 holds an absolute path"; fi
}

if ! command -v jq >/dev/null 2>&1; then die "jq is not installed"; fi
if [ "$mode" = demo ] && [ ! -f "$repo/eval/orders-date-format/case.json" ]; then die "eval/orders-date-format/case.json does not exist"; fi

case $mode in
  feed) live_start r99f ;;
  noevidence) live_start r39e ;;
  *) live_start r10e ;;
esac

target=eval/orders-date-format/snapshot.json

if ! dc up -d --build > "$tmp/up.log" 2>&1; then
  tail -n 30 "$tmp/up.log"
  die "build or start failed"
fi
live_track_image
cid=$(dc ps -q iris)
[ -n "$cid" ] || die "no iris container in project $P"
if ! wait_started_ready 400; then
  start_log | tail -n 30 | cut -c1-200
  die "the start did not end ready within 400 s"
fi

if [ "$mode" = feed ]; then
  # The first CHK line keeps iris_script from running the recording a second time when the session prints a result late.
  result=$(printf '%s\n' \
    'Write !,"CHK|started|1"' \
    'Set sc=##class(OcuTalon.Test.Eval.Feed.Fixture).Record("/tmp/zz-eval-feed/",.names)' \
    'Write !,"CHK|record|",$Select($SYSTEM.Status.IsOK(sc):"ok "_names,1:$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  "))' \
    'Halt' | session_value OCUTALON record)
  case $result in
    "ok "*) names=${result#ok } ;;
    *) die "the recording failed: ${result:-no answer from the session}" ;;
  esac
  mkdir -p "$tmp/feed"
  count=0
  for name in $(printf '%s' "$names" | tr ',' ' '); do
    case $name in
      '' | *[!a-z0-9-]*) die "the feed recorded a case with the name '$name'" ;;
      orders-date-format) die "the feed recorded the case orders-date-format, which the default mode records" ;;
      orders-date-no-evidence) die "the feed recorded the case orders-date-no-evidence, which the no-evidence mode records" ;;
    esac
    mkdir -p "$tmp/feed/$name"
    for file in case.json snapshot.json; do
      copy_out "/tmp/zz-eval-feed/$name/$file" "$tmp/feed/$name/$file" "$name/$file"
    done
    count=$((count + 1))
  done
  if [ "$count" -eq 0 ]; then die "the feed recorded no case"; fi
  for name in $(printf '%s' "$names" | tr ',' ' '); do
    mkdir -p "eval/$name" || die "eval/$name could not be made"
    cp "$tmp/feed/$name/case.json" "$tmp/feed/$name/snapshot.json" "eval/$name/" || die "eval/$name could not be written"
  done
  echo "record-eval: $count feed cases written"
  exit 0
fi

if [ "$mode" = noevidence ]; then
  name=orders-date-no-evidence
  # The first CHK line keeps iris_script from running the recording a second time when the session prints a result late.
  result=$(printf '%s\n' \
    'Write !,"CHK|started|1"' \
    'Set sc=##class(OcuTalon.Test.Eval.Record).RecordNoEvidence("/tmp/zz-eval-noevidence/")' \
    'Write !,"CHK|record|",$Select($SYSTEM.Status.IsOK(sc):"ok",1:$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  "))' \
    'Halt' | session_value OCUTALON record)
  if [ "$result" != ok ]; then die "the recording failed: ${result:-no answer from the session}"; fi
  mkdir -p "$tmp/noevidence"
  for file in case.json snapshot.json; do
    copy_out "/tmp/zz-eval-noevidence/$name/$file" "$tmp/noevidence/$file" "$name/$file"
  done
  mkdir -p "eval/$name" || die "eval/$name could not be made"
  cp "$tmp/noevidence/case.json" "$tmp/noevidence/snapshot.json" "eval/$name/" || die "eval/$name could not be written"
  echo "record-eval: eval/$name written"
  exit 0
fi

result=$(printf '%s\n' \
  'Set sc=##class(OcuTalon.Test.Demo.Production).Record("/tmp/ocutalon-snapshot.json")' \
  'Write !,"CHK|record|",$Select($SYSTEM.Status.IsOK(sc):"ok",1:$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  "))' \
  'Halt' | session_value OCUTALON record)
if [ "$result" != ok ]; then die "the recording failed: $result"; fi

if ! dc exec -T iris cat /tmp/ocutalon-snapshot.json | tr -d '\r' | jq . > "$tmp/snapshot.json"; then
  die "the snapshot is not JSON"
fi
count=$(jq '.failures | length' "$tmp/snapshot.json")
if [ "$count" != 50 ]; then die "the snapshot holds $count failures, not 50"; fi
if LC_ALL=C grep -q '[^ -~]' "$tmp/snapshot.json"; then die "the snapshot holds a character that is not ASCII"; fi
if grep -q '/Users/\|/home/' "$tmp/snapshot.json"; then die "the snapshot holds an absolute path"; fi
mkdir -p "$(dirname "$target")"
cp "$tmp/snapshot.json" "$target"
echo "record-eval: $count failures written to $target"
