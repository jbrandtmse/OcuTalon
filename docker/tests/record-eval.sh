#!/usr/bin/env bash
# Records eval/orders-date-format/snapshot.json (Story 0.10). Not a CI unit and not a check: nothing runs it but a person, and its
# name is not test-*. It starts one throwaway project (docker/tests/lib-live.sh, the throwaway and CI overrides, no key and no
# host port), waits for a ready start, and has OcuTalon.Test.Demo.Production.Record send one real batch of 50 orders (order
# date MM/DD/YYYY, written 2026-10-16) into the Orders production, wait for its 50 failures at OrdersFromPartner and write the
# reader snapshot of them. The file is passed through jq, so it is written pretty-printed, and replaced only when it holds the
# 50 failures; it is ASCII and holds no absolute path. An EXIT trap removes the project with its volume and images.
# Rerun it whenever TestSnapshotIsReadableAndCurrent reports that a fresh recording differs from the committed one because the
# production changed, then commit the file. Story 9.4's Eval.Record replaces this script.
# Prints the number of failures it recorded; exits 0 only when the snapshot was written.
# Needs docker compose, jq, and the build 154 base image (IRIS_IMAGE, default ocutalon-iris-base:2026.3.0AI.154.0).
set -u

. "$(dirname "$0")/lib-live.sh"

repo=$(cd "$(dirname "$0")/../.." && pwd)
if ! command -v jq >/dev/null 2>&1; then die "jq is not installed"; fi
if [ ! -f "$repo/eval/orders-date-format/case.json" ]; then die "eval/orders-date-format/case.json does not exist"; fi

live_start r10e

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
