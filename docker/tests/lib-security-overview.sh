#!/usr/bin/env bash
# Readers of docs/security-overview.md for docker/tests/test-security-overview.sh (Story 14.1), sourced and never run: they hold no state beyond
# $tmp, the folder that drift writes its working files to, and they change no file but those.

# region <file> <key>: the lines between the begin and the end marker of the key, the markers left out.
region() {
  awk -v b="<!-- BEGIN GENERATED $2:" -v e="<!-- END GENERATED $2 -->" '
    index($0, b) == 1 { on = 1; next }
    $0 == e || $0 == e "\r" { on = 0 }
    on { sub(/\r$/, ""); print }
  ' "$1"
}

# tool_rows <region file>: one "<tool name><TAB><row>" line per tool row of the tools region.
tool_rows() {
  awk -F'`' '/^\| `/ { print $2 "\t" $0 }' "$1"
}

# drift <committed file> <regenerated file>: prints the DRIFT lines and the diff of each region that differs.
drift() {
  local key names old new
  for key in tools fix-kinds privileges; do
    old="$tmp/old.$key"
    new="$tmp/new.$key"
    region "$1" "$key" > "$old"
    region "$2" "$key" > "$new"
    if cmp -s "$old" "$new"; then continue; fi
    if [ "$key" = tools ]; then
      tool_rows "$old" > "$old.rows"
      tool_rows "$new" > "$new.rows"
      names=$(awk -F'\t' '
        NR == FNR { o[$1] = $2; next }
        { n[$1] = $2 }
        END {
          for (k in o) if (!(k in n) || o[k] != n[k]) print k
          for (k in n) if (!(k in o)) print k
        }' "$old.rows" "$new.rows" | sort -u)
      if [ -n "$names" ]; then
        printf '%s\n' "$names" | while IFS= read -r name; do echo "DRIFT tool $name"; done
      else
        echo "DRIFT tools"
      fi
    else
      echo "DRIFT $key"
    fi
    diff -u -L "$key committed" -L "$key regenerated" "$old" "$new" | sed 's/^/  /'
  done
}
