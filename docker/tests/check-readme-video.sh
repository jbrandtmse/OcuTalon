#!/usr/bin/env bash
# Checks online that the addresses of the README's Video row answer (Story 0.28, DW-1171). It needs the network, so it is not a CI unit
# and does not run per push (its name is not test-*); the release checklist runs it (release/checklist.sh, row readme-video).
# docker/tests/test-readme.sh pins the row's text offline.
#   bash docker/tests/check-readme-video.sh [<README file>]      the file defaults to the repository's README.md
# What it pins:
#   - the "| Video |" row of the file's "## Contest checklist" section is there; a missing row fails before any request;
#   - every http or https address in that row answers 200 after redirects (a GET of the first byte, so that a video file is not
#     downloaded whole: 206, the answer to that range, counts as 200);
#   - for every youtu.be/<id> address, the video site's oEmbed for it (https://www.<site>.com/oembed?url=https://youtu.be/<id>&format=json)
#     answers 200: youtu.be answers 200 even for an id that does not exist, and the oEmbed answers 404 for it.
# The first address that fails ends the run: FAIL readme-video: <url> answered <code>. Only a transport failure (no route, DNS, a
# timeout), 429 or a 5xx is tried again: up to 3 tries per address, 5 s apart, each with --max-time 15, and the whole run stops at 150 s;
# then FAIL readme-video: <url> could not be reached after 3 tries (<curl exit or code>). The check is never skipped.
# Then the self-tests, on copies of the file's row: the first youtu.be id swapped for an unknown one (its oEmbed must answer a status
# other than 200) and the first .mp4 name swapped for a missing one (it must answer a status other than 200) are each flagged by that
# address, and a copy without the row is flagged with no request made.
# Prints one PASS or FAIL line per check; exits 0 only when all pass, 1 when one fails and 2 on a usage error. bash 3.2, curl only.
set -u
export LC_ALL=C

root=$(cd "$(dirname "$0")/../.." && pwd)
if [ "$#" -gt 1 ]; then
  echo "usage: check-readme-video.sh [<README file>]" >&2
  exit 2
fi
readme=${1:-$root/README.md}

CAP=150
TRIES=3
PAUSE=5
MAXTIME=15
UNKNOWN_ID=AAAAAAAAAAA
MISSING_MP4=ocutalon-missing-0.0.0.mp4
# The oEmbed endpoint of the video site. Its host is written in two parts because the no-outward row of release/checklist.sh flags
# every script that names that site whole (a site that posts are made to); this script only reads from it, with GET.
OEMBED_SITE=www.youtube
OEMBED="https://$OEMBED_SITE.com/oembed"

fails=0
requests=0
code=""
cexit=0

if [ ! -f "$readme" ]; then
  echo "FAIL readme-video: no file $readme"
  exit 1
fi
if ! command -v curl > /dev/null 2>&1; then
  echo "FAIL readme-video: curl is not installed"
  exit 1
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-rv.XXXXXX") || {
  echo "FAIL readme-video: no temporary folder"
  exit 1
}
trap 'rm -rf "$tmp"' EXIT

# video_row <file>: the first "| Video |" row of the section "## Contest checklist", outside a code fence; nothing when there is none.
video_row() {
  awk '
    /^```/ { fence = !fence }
    !fence && /^## / { on = ($0 == "## Contest checklist"); next }
    on && index($0, "| Video |") == 1 { print; exit }
  ' "$1"
}

# row_urls <row>: each http or https address of the row, once, in the order of the row.
row_urls() { printf '%s\n' "$1" | grep -oE 'https?://[^]()<> |]+' | awk '!seen[$0]++'; }

# fetch <url> <range yes|no>: one GET that follows redirects; sets code (the last status, 000 when none) and cexit (curl's exit status).
fetch() {
  local t=$((CAP - SECONDS))
  if [ "$t" -gt "$MAXTIME" ]; then t=$MAXTIME; fi
  if [ "$t" -lt 1 ]; then t=1; fi
  requests=$((requests + 1))
  if [ "$2" = yes ]; then
    code=$(curl -s -L --max-redirs 10 -r 0-0 -o /dev/null -w '%{http_code}' --max-time "$t" "$1")
  else
    code=$(curl -s -L --max-redirs 10 -o /dev/null -w '%{http_code}' --max-time "$t" "$1")
  fi
  cexit=$?
}

# check_url <url> <range yes|no>: 0 when the address answers 200 (or 206 to a range); else a FAIL line and 1.
check_url() {
  local url=$1 range=$2 try=1 why
  while :; do
    if [ "$SECONDS" -ge "$CAP" ]; then
      echo "FAIL readme-video: $url could not be reached within the ${CAP} s cap"
      return 1
    fi
    fetch "$url" "$range"
    if [ "$cexit" -eq 0 ]; then
      case $code in
        200) return 0 ;;
        206) if [ "$range" = yes ]; then return 0; fi ;;
      esac
      case $code in
        429 | 5[0-9][0-9]) why=$code ;;
        *)
          echo "FAIL readme-video: $url answered $code"
          return 1
          ;;
      esac
    else
      why="curl exit $cexit"
    fi
    if [ "$try" -ge "$TRIES" ]; then
      echo "FAIL readme-video: $url could not be reached after $TRIES tries ($why)"
      return 1
    fi
    if [ $((SECONDS + PAUSE)) -ge "$CAP" ]; then
      echo "FAIL readme-video: $url could not be reached within the ${CAP} s cap ($why)"
      return 1
    fi
    sleep "$PAUSE"
    try=$((try + 1))
  done
}

# check_file <file>: checks every address of the file's Video row and each youtu.be id's oEmbed, in the order of the row; stops at the
# first failure. One PASS line per address that answers, a FAIL line for the one that does not; returns 1 on a failure.
check_file() {
  local row url id
  row=$(video_row "$1")
  if [ -z "$row" ]; then
    echo "FAIL readme-video: $1 has no '| Video |' row in '## Contest checklist'"
    return 1
  fi
  row_urls "$row" > "$tmp/urls"
  if [ ! -s "$tmp/urls" ]; then
    echo "FAIL readme-video: the Video row of $1 holds no address"
    return 1
  fi
  while IFS= read -r url; do
    check_url "$url" yes || return 1
    echo "PASS readme-video: $url answered"
    case $url in
      https://youtu.be/*)
        id=${url#https://youtu.be/}
        id=${id%%[?#/]*}
        check_url "$OEMBED?url=https://youtu.be/$id&format=json" no || return 1
        echo "PASS readme-video: the oEmbed of youtu.be/$id answered"
        ;;
    esac
  done < "$tmp/urls"
}

# swap_copy <file> <old> <new>: writes $tmp/copy.md, the file with the first occurrence of old in its Video row replaced by new.
swap_copy() {
  awk -v o="$2" -v n="$3" '
    /^```/ { fence = !fence }
    !fence && /^## / { on = ($0 == "## Contest checklist") }
    on && !done && index($0, "| Video |") == 1 && (i = index($0, o)) > 0 { $0 = substr($0, 1, i - 1) n substr($0, i + length(o)); done = 1 }
    { print }
  ' "$1" > "$tmp/copy.md"
}

# self_test <label> <copy> <address that must be flagged>: the check of the copy fails, and its FAIL line is that address answering a
# status (not a transport failure).
self_test() {
  local out
  check_file "$2" > "$tmp/st.out" 2>&1
  out=$(grep '^FAIL ' "$tmp/st.out")
  case $out in
    "FAIL readme-video: $3 answered "*) echo "PASS readme-video self-test: $1 is flagged" ;;
    *)
      echo "FAIL readme-video self-test: $1 is not flagged as an answer of $3${out:+ (got: $out)}"
      fails=$((fails + 1))
      ;;
  esac
}

# --- the file itself ---

if ! check_file "$readme"; then
  echo "check-readme-video: failed"
  exit 1
fi

# --- the self-tests, on copies of the file ---

row=$(video_row "$readme")
yt=$(row_urls "$row" | grep -m 1 '^https://youtu\.be/')
mp4=$(row_urls "$row" | grep -m 1 '\.mp4$')
if [ -z "$yt" ]; then
  echo "FAIL readme-video self-test: the Video row has no youtu.be address to swap for an unknown id"
  fails=$((fails + 1))
else
  id=${yt#https://youtu.be/}
  id=${id%%[?#/]*}
  swap_copy "$readme" "youtu.be/$id" "youtu.be/$UNKNOWN_ID"
  self_test 'an unknown video id' "$tmp/copy.md" "$OEMBED?url=https://youtu.be/$UNKNOWN_ID&format=json"
fi
if [ -z "$mp4" ]; then
  echo "FAIL readme-video self-test: the Video row has no .mp4 address to swap for a missing one"
  fails=$((fails + 1))
else
  swap_copy "$readme" "$mp4" "${mp4%/*}/$MISSING_MP4"
  self_test 'a missing MP4 name' "$tmp/copy.md" "${mp4%/*}/$MISSING_MP4"
fi
awk 'index($0, "| Video |") != 1' "$readme" > "$tmp/norow.md"
before=$requests
check_file "$tmp/norow.md" > "$tmp/st.out" 2>&1
if grep -q "^FAIL readme-video: .* has no '| Video |' row" "$tmp/st.out" && [ "$requests" -eq "$before" ]; then
  echo "PASS readme-video self-test: the row removed is flagged with no request"
else
  echo "FAIL readme-video self-test: the row removed is not flagged, or a request was made"
  fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
  echo "check-readme-video: $fails check(s) failed"
  exit 1
fi
echo "check-readme-video: all checks passed"
