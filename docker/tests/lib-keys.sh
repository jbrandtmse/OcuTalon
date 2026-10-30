# The one definition of "key-like text", and the scan for the value of the model key, shared by docker/tests/test-boundaries.sh (the
# repository scan), eval/run.sh (the release-candidate result pair, the override, and the key proof of the key-path rehearsal) and
# eval/key-proof.sh (the harness). Story 9.10; AD-19, AD-22.
# Sourced, not run: it defines one variable, KEY_LIKE_ERE, and functions, and nothing else.
#
# key_like <file>...         prints file:line for each line of the files that holds a key-like string, and never the text of the line
# key_value_hits <file>...   prints file:line for each line that holds the value of ANTHROPIC_API_KEY. The value is read from the
#                            environment by awk (ENVIRON), never from an argument, a here-document or a file, and is never printed. A file
#                            of - is the standard input. It prints nothing and returns 2 when the variable is unset or empty, so an
#                            empty value never reads as clean; it returns 1 when a file cannot be read, and 0 otherwise
KEY_LIKE_ERE='sk-ant-[A-Za-z0-9_-]{8,}|[0-9]{8,10}:[A-Za-z0-9_-]{35}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|dop_v1_[a-f0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY'

key_like() { grep -nHIE -e "$KEY_LIKE_ERE" "$@" | cut -d: -f1,2; }

key_value_hits() {
  local f rc=0
  [ -n "$(printenv ANTHROPIC_API_KEY 2> /dev/null)" ] || return 2
  for f in "$@"; do
    if [ "$f" != - ] && [ ! -r "$f" ]; then
      rc=1
      continue
    fi
    LC_ALL=C awk -v name="$f" 'BEGIN { k = ENVIRON["ANTHROPIC_API_KEY"] } k != "" && index($0, k) { print name ":" FNR }' "$f" || rc=1
  done
  return $rc
}
