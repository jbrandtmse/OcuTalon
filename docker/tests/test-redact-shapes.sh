#!/usr/bin/env bash
# Keeps the redactor's test oracle equal to the definition of key-like text (DW-386, Story 30.8; AD-31, AD-19). The KEYLIKE parameter of
# src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls is a verbatim copy of KEY_LIKE_ERE in docker/tests/lib-keys.sh; Test.Bridge.Redact runs a fixture
# through the redactor for each alternative of the copy. When lib-keys.sh gains or changes a shape and the copy does not follow, this script fails,
# so the redactor cannot fall behind key_like unseen. It prints PASS or FAIL lines that name files only, never a pattern or a key, and it first
# proves that its comparison fails for a pair that differs. Exit 0 only when every check passes.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. docker/tests/lib-keys.sh
test_file=src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls
lib_file=docker/tests/lib-keys.sh
fails=0
pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}
# copy_of <file>: the text of the KEYLIKE parameter line of the file; empty when the file has none or more than one.
copy_of() { grep -E '^Parameter KEYLIKE = ".*";$' "$1" | awk 'END { if (NR == 1) print $0 }' | sed -e 's/^Parameter KEYLIKE = "//' -e 's/";$//'; }
same() { [ -n "$1" ] && [ "$1" = "$2" ]; }

if same "abc|def" "abc|def" && ! same "abc|def" "abc|deg" && ! same "" ""; then
  pass "the comparison tells an equal pair from a different one and from an empty one"
else
  fail "the comparison of this script does not tell an equal pair from a different one"
fi
copy=$(copy_of "$test_file")
if [ -z "$copy" ]; then
  fail "$test_file holds no single KEYLIKE parameter line"
elif same "$copy" "$KEY_LIKE_ERE"; then
  pass "KEYLIKE in $test_file equals KEY_LIKE_ERE in $lib_file"
else
  fail "KEYLIKE in $test_file differs from KEY_LIKE_ERE in $lib_file: update the copy, and the fixtures of each changed alternative in Test.Bridge.Redact"
fi
[ "$fails" -eq 0 ]
