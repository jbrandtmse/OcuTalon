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
# env_file_hits <env file> <file>...   prints "file:line NAME" for each line of the files that holds the value of a NAME=value line of the env file
#                            (Story 11.3; AD-19). Blank lines, # lines and values of fewer than 8 characters are not read (a short value such as
#                            0 or true is in every log). The env file is read inside awk, and its values are never printed or put on a command
#                            line; a file of - is the standard input. It returns 1 when the env file or a file cannot be read, and 0 otherwise
# project_leftovers <project>  prints "<containers>|<volumes>": how many containers (in any state) and volumes of the compose project <project>
#                            exist, found by the tool itself (a name that is the project followed by - or _), and returns 1 with no output when the
#                            tool cannot be asked. eval/key-proof.sh uses it to check, besides the teardown of ci/iris.sh (which counts a leftover
#                            only when its removal succeeds), that the run left no container and no volume
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

project_leftovers() {
  local c v
  [ -n "$1" ] || return 1
  c=$(docker ps -a --format '{{.Names}}') || return 1
  v=$(docker volume ls --format '{{.Name}}') || return 1
  printf '%s|%s\n' "$(printf '%s\n' "$c" | grep -Ec -- "^$1[-_]" || true)" "$(printf '%s\n' "$v" | grep -Ec -- "^$1[-_]" || true)"
}

env_file_hits() {
  local envf=$1 f rc=0
  shift
  [ -r "$envf" ] || return 1
  for f in "$@"; do
    if [ "$f" != - ] && [ ! -r "$f" ]; then
      rc=1
      continue
    fi
    LC_ALL=C awk -v name="$f" -v envf="$envf" '
      BEGIN {
        while ((getline line < envf) > 0) {
          sub(/\r$/, "", line)
          if (line ~ /^[ \t]*#/) continue
          sub(/^[ \t]*export[ \t]+/, "", line)
          if (line !~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
          eq = index(line, "=")
          nm = substr(line, 1, eq - 1)
          val = substr(line, eq + 1)
          if (val ~ /^".*"$/ || val ~ /^'"'"'.*'"'"'$/) val = substr(val, 2, length(val) - 2)
          if (length(val) >= 8) { n++; names[n] = nm; vals[n] = val }
        }
        close(envf)
      }
      { for (i = 1; i <= n; i++) if (index($0, vals[i])) print name ":" FNR " " names[i] }
    ' "$f" || rc=1
  done
  return $rc
}
