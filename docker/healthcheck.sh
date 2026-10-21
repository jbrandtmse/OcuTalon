#!/bin/sh
# Ready only when IRIS is running and the ready marker holds the image's version.
# Opens no IRIS session, so it takes no licence connection: `iris qlist` is its only IRIS call.
# Build 154 separates qlist fields with '^', so the status is matched as '^running'.
# The two paths are overridable only so that a test can supply its own files.
version_file="${OCUTALON_VERSION_FILE:-/opt/ocutalon/version}"
marker_file="${OCUTALON_READY_MARKER:-/durable/ocutalon.ready}"

iris qlist 2>/dev/null | grep -q '\^running' || exit 1
want=$(cat "$version_file" 2>/dev/null) || exit 1
have=$(cat "$marker_file" 2>/dev/null) || exit 1
[ -n "$want" ] && [ "$have" = "$want" ]
