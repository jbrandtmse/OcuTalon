#!/bin/bash
# After-start script, run by `iris-main --after` once IRIS is up, as the IRIS user under OS authentication.
# In this order it
#   1. deletes the ready marker, so that no health probe during this start sees the previous start's marker and
#      any failure below leaves the container unhealthy (the image's CMD also deletes it before IRIS starts);
#   2. re-applies the image's CPF merge file, because iris-main applies it only at the first start and when
#      the file changes, so a mapping removed by hand would otherwise stay missing. `iris merge` itself does
#      nothing for a file whose path has an unchanged `*.last_merge` record, so it merges a fresh copy;
#   3. runs one IRIS session (after-start.cos) that clears readiness, installs IPM and the `ocutalon` package
#      when the version gate says so, runs the installer-step registry and prints `RESULT OK <version>`;
#   4. writes the ready marker, through a temporary file and a rename, only when that line names the image's version.
# Always exits 0: a non-zero exit makes iris-main stop IRIS, and the restart policy would then loop the container.
# A failure shows only as a missing marker, which the health check reports, and as a line in the log.
# The log is rewritten at every start; its first line carries the start's time stamp and its last line ends the run.
# The paths below can be overridden only so that a test can supply its own files.
version_file="${OCUTALON_VERSION_FILE:-/opt/ocutalon/version}"
marker_file="${OCUTALON_READY_MARKER:-/durable/ocutalon.ready}"
merge_file="${OCUTALON_MERGE_FILE:-/opt/ocutalon/merge.cpf}"
src_dir="${OCUTALON_SRC_DIR:-/opt/ocutalon/src}"
session_script="${OCUTALON_SESSION_SCRIPT:-/opt/ocutalon/after-start.cos}"
log_file="${OCUTALON_AFTER_START_LOG:-/durable/ocutalon-after-start.log}"

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { { printf '%s\n' "$*" >> "$log_file"; } 2>/dev/null; }
say() { printf '%s\n' "$*"; log "$*"; }

drop_marker() { rm -f "$marker_file" "$marker_file".tmp.* 2>/dev/null; }

# Ends the run: the last line of the log, then exit 0.
finish() {
  say "AFTER-START end $(stamp) $1"
  exit 0
}

{ : > "$log_file"; } 2>/dev/null
say "AFTER-START begin $(stamp)"

# 1. No marker from here on, an old one included, until the session has succeeded.
drop_marker

# 2. The merge, of a copy at a path that has no record. A failed merge starts no session.
SECONDS=0
merge_dir=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-merge.XXXXXX") || merge_dir=""
if [ -z "$merge_dir" ]; then
  merge_out="could not create a temporary directory in ${TMPDIR:-/tmp}"
  merge_rc=1
elif cp "$merge_file" "$merge_dir/merge.cpf" 2>/dev/null; then
  merge_out=$(iris merge IRIS "$merge_dir/merge.cpf" 2>&1)
  merge_rc=$?
else
  merge_out="could not copy $merge_file"
  merge_rc=1
fi
if [ -n "$merge_dir" ]; then rm -rf "$merge_dir"; fi
log "$merge_out"
if [ "$merge_rc" -ne 0 ]; then
  say "STEP merge FAILED exit $merge_rc"
  finish "not ready"
fi
say "STEP merge OK ${SECONDS}s"

image_version=$(tr -d '\r' < "$version_file" 2>/dev/null)
if [ -z "$image_version" ]; then
  say "STEP version FAILED no version in $version_file"
  finish "not ready"
fi

# The class names of the public packages, from the .cls files shipped in the image.
public_classes=$(
  cd "$src_dir/ocutalon/cls" 2>/dev/null && for area in Web Data; do
    if [ -d "OcuTalon/$area/Public" ]; then
      find "OcuTalon/$area/Public" -type f -name '*.cls'
    fi
  done | sed -e 's|/|.|g' -e 's|\.cls$||' | sort | paste -s -d, -
)
export OCUTALON_IMAGE_VERSION="$image_version"
export OCUTALON_PUBLIC_CLASSES="$public_classes"

# 3. The session. Its transcript is kept in the log without blank lines and lines that hold only a prompt.
transcript=$(mktemp "${TMPDIR:-/tmp}/ocutalon-after-start.XXXXXX") || {
  say "STEP session FAILED could not create a temporary file in ${TMPDIR:-/tmp}"
  finish "not ready"
}
SECONDS=0
iris session IRIS -U '%SYS' < "$session_script" > "$transcript" 2>&1
session_rc=$?
{ tr -d '\r' < "$transcript" | grep -v -e '^[[:space:]]*$' -e '^[%A-Za-z0-9]*>[[:space:]]*$' >> "$log_file"; } 2>/dev/null
tr -d '\r' < "$transcript" | grep -E '^(STEP|RESULT) '
result=$(tr -d '\r' < "$transcript" | grep '^RESULT ' | tail -n 1)
rm -f "$transcript"

if [ "$session_rc" -ne 0 ]; then
  say "STEP session FAILED exit $session_rc"
  finish "not ready"
fi
if [ -z "$result" ]; then
  say "STEP session FAILED no RESULT line after ${SECONDS}s"
  finish "not ready"
fi
if [ "$result" != "RESULT OK $image_version" ]; then
  say "STEP session FAILED '$result', the image is $image_version"
  finish "not ready"
fi

# 4. The marker.
tmp_marker="$marker_file.tmp.$$"
if printf '%s\n' "$image_version" > "$tmp_marker" 2>/dev/null && mv -f "$tmp_marker" "$marker_file" 2>/dev/null; then
  finish "ready $image_version"
fi
rm -f "$tmp_marker" 2>/dev/null
say "STEP marker FAILED could not write $marker_file"
finish "not ready"
