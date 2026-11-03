#!/usr/bin/env bash
# The static pins of the bridge example's files that no IRIS test reads (Story 13.1, QA; AD-22, AD-33; FR-5). Starts nothing: the rules
# read files only (jq reads the scenarios), so the hosted `checks` job runs them.
#   - spine-rows (AD-33, AC 9): the Production items table of the architecture spine holds the two Lane A rows of the example: the
#     five Example items of OcuTalon.BridgeExample.Production with the classes ItemIn, Triage and Outcome, and ExampleRouter with
#     EnsLib.MsgRouter.RoutingEngine and the rule OcuTalon.BridgeExample.Rule; and every item the production names Example... has one
#     row, never paired with the item of another row;
#   - scenarios (AD-22, FR-5): the mock scenarios of the example hold what the matrix of the story reads from them. The default
#     scenario (match.mockkey bridge-example) answers tellnow with confidence 0.7. Each marker scenario bridge-example-<kind> is named
#     for its file and matched by the marker of the same name; digest, ignore and act answer that outcome with reasons and a confidence
#     from 0 to 1; late answers tellnow after 25000 ms (a held reply past a timer of 12 s); refusal stops with `refusal`. The four tool
#     scenarios of Story 13.2 (bridge-example-tool-read, -risky, -unclassified and -untrusted) hold two replies: the first calls the
#     example's tools with the arguments of the story's matrix (count; forward {"team":"operations"}; archive {}; forward, archive and
#     count), every tool name being a Tool Name of OcuTalon.BridgeExample.ToolSet, and the second is a decision with reasons and a
#     confidence from 0 to 1 whose outcome is tellnow (read, untrusted) or act (risky, unclassified). No scenario sets a sampling
#     parameter.
# Each rule first runs on a synthetic tree that breaks it and on one that keeps it, so a rule that can no longer flag anything fails.
# A failing rule prints what is wrong and never a secret. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-be.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

SPINE="_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md"
PRODUCTION="src/bridge/cls/OcuTalon/BridgeExample/Production.cls"
TOOLSET="src/bridge/cls/OcuTalon/BridgeExample/ToolSet.cls"
SCENARIOS="ci/mock/scenarios/A"

command -v jq > /dev/null 2>&1 || { echo "FAIL tooling: jq is not installed"; exit 1; }

# --- spine-rows ---

# table_rows <spine>: the rows of the Production items table, one per line.
table_rows() {
  awk '
    /^\*\*Production items\*\*/ { on = 1; next }
    on && /^\*\*Tables:\*\*/ { exit }
    on && /^\|/ { print }
  ' "$1"
}

# row_with <rows> <name>: the rows whose first cell holds the item name between backticks.
row_with() {
  printf '%s\n' "$1" | awk -F'|' -v name="$2" '{ if (index($2, "`" name "`") > 0) print }'
}

# spine_problems <spine> <production>: one line per problem.
spine_problems() {
  local rows names n row item
  rows=$(table_rows "$1")
  if [ -z "$rows" ]; then
    echo "the Production items table is not found"
    return
  fi
  names=$(grep -o '<Item Name="Example[^"]*"' "$2" | sed 's/<Item Name="//; s/"$//')
  if [ -z "$names" ]; then
    echo "the production names no Example item"
  fi
  for item in $names; do
    n=$(row_with "$rows" "$item" | grep -c .)
    if [ "$n" -ne 1 ]; then echo "$item is in $n rows of the table, wanted 1"; fi
  done
  for item in ExampleItemIn ExampleTriage ExampleNotifyOut ExampleDigestOut ExampleFallbackOut; do
    row=$(row_with "$rows" "$item")
    case $row in
      *'`ExampleItemIn`'*'`ExampleTriage`'*'`ExampleNotifyOut`'*'`ExampleDigestOut`'*'`ExampleFallbackOut`'*) ;;
      *) echo "$item is not in the row of the five Example items" ;;
    esac
    case $row in
      *'`OcuTalon.BridgeExample.ItemIn`'*'`.Triage`'*'`.Outcome`'*) ;;
      *) echo "the row of $item does not name OcuTalon.BridgeExample.ItemIn, .Triage and .Outcome" ;;
    esac
    case $row in
      *'| A |') ;;
      *) echo "the row of $item is not Lane A's" ;;
    esac
  done
  row=$(row_with "$rows" ExampleItemIn)
  for item in ApprovalStartIn ApprovalHold OcuTalonApprovals; do
    if grep -q "<Item Name=\"$item\"" "$2"; then
      case $row in
        *"\`$item\`"*) ;;
        *) echo "the row of the Example items does not name the approval item $item that the production holds" ;;
      esac
    fi
  done
  row=$(row_with "$rows" ExampleRouter)
  case $row in
    *'`EnsLib.MsgRouter.RoutingEngine`'*'`OcuTalon.BridgeExample.Rule`'*'| A |') ;;
    *) echo "the row of ExampleRouter does not name EnsLib.MsgRouter.RoutingEngine and the rule OcuTalon.BridgeExample.Rule for Lane A" ;;
  esac
  case $row in
    *'`ExampleTriage`'* | *'`ExampleItemIn`'*) echo "ExampleRouter shares its row with another Example item" ;;
  esac
}

mkdir -p "$tmp/spine-bad" "$tmp/spine-good"
cat > "$tmp/prod.cls" << 'EOF'
  <Item Name="ExampleItemIn" ClassName="OcuTalon.BridgeExample.ItemIn" PoolSize="0" Enabled="true"/>
  <Item Name="ExampleTriage" ClassName="OcuTalon.BridgeExample.Triage" PoolSize="1" Enabled="true"/>
  <Item Name="Decide" ClassName="OcuTalon.Bridge.Process.Decide" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleRouter" ClassName="EnsLib.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleNotifyOut" ClassName="OcuTalon.BridgeExample.Outcome" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleDigestOut" ClassName="OcuTalon.BridgeExample.Outcome" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleFallbackOut" ClassName="OcuTalon.BridgeExample.Outcome" PoolSize="1" Enabled="true"/>
  <Item Name="ApprovalStartIn" ClassName="OcuTalon.Bridge.Service.ApprovalStart" PoolSize="0" Enabled="true"/>
  <Item Name="ApprovalHold" ClassName="OcuTalon.Bridge.Process.ApprovalHold" PoolSize="1" Enabled="true"/>
  <Item Name="OcuTalonApprovals" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true"/>
EOF
cat > "$tmp/spine-good.md" << 'EOF'
**Production items** (class; lane).

| Item | Class | Lane |
| --- | --- | --- |
| `Decide`, `ApprovalHold` | `OcuTalon.Bridge.Process.Decide`, `.ApprovalHold` | A |
| `ExampleItemIn`, `ExampleTriage`, `ExampleNotifyOut`, `ExampleDigestOut`, `ExampleFallbackOut` (only in the example, beside its `ApprovalStartIn`, `ApprovalHold` and `OcuTalonApprovals`) | `OcuTalon.BridgeExample.ItemIn` (adapterless), `.Triage`, `.Outcome` | A |
| `ExampleRouter` (only in the example) | `EnsLib.MsgRouter.RoutingEngine`, rule `OcuTalon.BridgeExample.Rule` | A |
| `Checks` | `OcuTalon.Checks.Process` | A |

**Tables:** Lane B owns `Session`.
EOF
# bad: the router row is missing; the second bad sample gives the five items to Lane B.
grep -v 'ExampleRouter' "$tmp/spine-good.md" > "$tmp/spine-bad1.md"
sed 's/`.Outcome` | A |/`.Outcome` | B |/' "$tmp/spine-good.md" > "$tmp/spine-bad2.md"
# bad: the router row holds the wrong rule; a third has an item of the production that no row names.
sed 's/OcuTalon.BridgeExample.Rule/OcuTalon.Core.Rule.Outcome/' "$tmp/spine-good.md" > "$tmp/spine-bad3.md"
sed 's/ExampleDigestOut`, //' "$tmp/spine-good.md" > "$tmp/spine-bad4.md"
# bad: the example row does not name one of the approval items that the production holds.
sed '/`ExampleItemIn`/s/`ApprovalHold` and //' "$tmp/spine-good.md" > "$tmp/spine-bad5.md"
sed '/`ExampleItemIn`/s/`OcuTalonApprovals`/`Checks`/' "$tmp/spine-good.md" > "$tmp/spine-bad6.md"
spine_samples_ok=1
[ -z "$(spine_problems "$tmp/spine-good.md" "$tmp/prod.cls")" ] || { echo "FAIL spine-rows: the rule flags a spine that keeps it"; spine_problems "$tmp/spine-good.md" "$tmp/prod.cls" | sed 's/^/  /'; fails=$((fails + 1)); spine_samples_ok=0; }
for bad in 1 2 3 4 5 6; do
  if [ -z "$(spine_problems "$tmp/spine-bad$bad.md" "$tmp/prod.cls")" ]; then
    echo "FAIL spine-rows: the rule does not flag the broken spine sample $bad"
    fails=$((fails + 1)); spine_samples_ok=0
  fi
done
if [ "$spine_samples_ok" -eq 1 ]; then
  hits=$(spine_problems "$SPINE" "$PRODUCTION")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL spine-rows: the Production items table holds the example's two Lane A rows (AD-33)"
    fails=$((fails + 1))
  else
    echo "PASS spine-rows: the Production items table holds the example's two Lane A rows (AD-33)"
  fi
fi

# --- scenarios ---

# one_scenario <dir> <file name without .json> <kind>: the problems of one scenario file. kind is default, tellnow, digest, ignore, act,
# late or refusal.
one_scenario() {
  local file="$1/$2.json" kind=$3 name=$2 want="" reply
  if [ ! -f "$file" ]; then echo "$name: the file is missing"; return; fi
  if ! jq -e . "$file" > /dev/null 2>&1; then echo "$name: not JSON"; return; fi
  jq -e --arg n "$name" '.name == $n' "$file" > /dev/null || echo "$name: name is not the file name"
  if [ "$kind" = default ]; then
    jq -e '.match == {"mockkey": "bridge-example"}' "$file" > /dev/null || echo "$name: it is not matched by the mockkey bridge-example alone"
    want=tellnow
  else
    jq -e --arg n "$name" '.match == {"marker": $n}' "$file" > /dev/null || echo "$name: it is not matched by the marker of its own name alone"
    want=$kind
    [ "$kind" = late ] && want=tellnow
  fi
  jq -e '(.replies | length) == 1 and .replies[0].status == 200' "$file" > /dev/null || echo "$name: it does not hold one reply with status 200"
  jq -e '[.. | objects | keys[]] | map(select(. == "temperature" or . == "top_p" or . == "top_k")) | length == 0' "$file" > /dev/null \
    || echo "$name: it sets a sampling parameter"
  case $kind in
    refusal)
      jq -e '.replies[0].stopReason == "refusal"' "$file" > /dev/null || echo "$name: the reply does not stop with refusal"
      ;;
    *)
      reply=$(jq -r '.replies[0].text' "$file")
      if ! printf '%s' "$reply" | jq -e --arg o "$want" '
          type == "object" and .outcome == $o
          and (.reasons | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
          and (.confidence | type == "number" and . >= 0 and . <= 1)' > /dev/null 2>&1; then
        echo "$name: the reply is not a decision with outcome $want, reasons and a confidence from 0 to 1"
      fi
      if [ "$kind" = default ]; then
        printf '%s' "$reply" | jq -e '.confidence == 0.7' > /dev/null 2>&1 || echo "$name: the confidence is not 0.7"
      fi
      ;;
  esac
  if [ "$kind" = late ]; then
    jq -e '.replies[0].delayMs == 25000' "$file" > /dev/null || echo "$name: the reply is not held for 25000 ms"
  else
    jq -e '.replies[0] | has("delayMs") | not' "$file" > /dev/null || echo "$name: the reply is held"
  fi
}

# tool_scenario <dir> <file name without .json> <the calls of the first reply as a JSON array of {name,input}> <outcome>: the problems of
# one tool scenario file. The tool names must be Tool Names of the example's ToolSet.
tool_scenario() {
  local file="$1/$2.json" name=$2 calls=$3 want=$4 reply tool
  if [ ! -f "$file" ]; then echo "$name: the file is missing"; return; fi
  if ! jq -e . "$file" > /dev/null 2>&1; then echo "$name: not JSON"; return; fi
  jq -e --arg n "$name" '.name == $n' "$file" > /dev/null || echo "$name: name is not the file name"
  jq -e --arg n "$name" '.match == {"marker": $n}' "$file" > /dev/null || echo "$name: it is not matched by the marker of its own name alone"
  jq -e '(.replies | length) == 2 and all(.replies[]; .status == 200)' "$file" > /dev/null || echo "$name: it does not hold two replies with status 200"
  jq -e '[.. | objects | keys[]] | map(select(. == "temperature" or . == "top_p" or . == "top_k")) | length == 0' "$file" > /dev/null \
    || echo "$name: it sets a sampling parameter"
  jq -e --argjson c "$calls" '(.replies[0].toolUse | if type == "array" then . else [.] end | map({name, input})) == $c' "$file" > /dev/null \
    || echo "$name: the first reply does not call $calls"
  for tool in $(jq -r '.replies[0].toolUse | if type == "array" then .[] else . end | .name' "$file" 2> /dev/null); do
    grep -q "<Tool Name=\"$tool\"" "${TOOLSET_UNDER_TEST:-$TOOLSET}" || echo "$name: $tool is not a Tool Name of the example's ToolSet"
  done
  reply=$(jq -r '.replies[1].text // ""' "$file")
  if ! printf '%s' "$reply" | jq -e --arg o "$want" '
      type == "object" and .outcome == $o
      and (.reasons | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
      and (.confidence | type == "number" and . >= 0 and . <= 1)' > /dev/null 2>&1; then
    echo "$name: the second reply is not a decision with outcome $want, reasons and a confidence from 0 to 1"
  fi
}

# scenario_problems <dir>: the problems of the example's ten scenario files.
scenario_problems() {
  one_scenario "$1" bridge-example default
  one_scenario "$1" bridge-example-digest digest
  one_scenario "$1" bridge-example-ignore ignore
  one_scenario "$1" bridge-example-act act
  one_scenario "$1" bridge-example-late late
  one_scenario "$1" bridge-example-refusal refusal
  tool_scenario "$1" bridge-example-tool-read '[{"name":"example_count_items","input":{}}]' tellnow
  tool_scenario "$1" bridge-example-tool-risky '[{"name":"example_forward_item","input":{"team":"operations"}}]' act
  tool_scenario "$1" bridge-example-tool-unclassified '[{"name":"example_archive_item","input":{}}]' act
  tool_scenario "$1" bridge-example-tool-untrusted '[{"name":"example_forward_item","input":{"team":"operations"}},{"name":"example_archive_item","input":{}},{"name":"example_count_items","input":{}}]' tellnow
}

# Sample: the real scenarios copied, then broken one way at a time.
mkdir -p "$tmp/sc-good"
for f in "$SCENARIOS"/bridge-example*.json; do cp "$f" "$tmp/sc-good/"; done
scn_samples_ok=1
if [ -n "$(scenario_problems "$tmp/sc-good")" ]; then
  echo "FAIL scenarios: the rule flags a copy of the scenarios that keeps it, or the real files break it"
  scenario_problems "$tmp/sc-good" | sed 's/^/  /'
  fails=$((fails + 1)); scn_samples_ok=0
fi
break_scenario() { # <label> <file> <jq filter>
  local d="$tmp/sc-$1"
  rm -rf "$d"; mkdir -p "$d"; cp "$tmp/sc-good"/*.json "$d/"
  jq "$3" "$d/$2.json" > "$d/$2.new" && mv "$d/$2.new" "$d/$2.json"
  if [ -z "$(scenario_problems "$d")" ]; then
    echo "FAIL scenarios: the rule does not flag a scenario that breaks it ($1)"
    fails=$((fails + 1)); scn_samples_ok=0
  fi
}
if [ "$scn_samples_ok" -eq 1 ]; then
  break_scenario digest-outcome bridge-example-digest '.replies[0].text = "{\"outcome\":\"tellnow\",\"reasons\":[\"x\"],\"confidence\":0.6}"'
  break_scenario ignore-marker bridge-example-ignore '.match.marker = "ignore"'
  break_scenario act-confidence bridge-example-act '.replies[0].text = "{\"outcome\":\"act\",\"reasons\":[\"x\"],\"confidence\":1.5}"'
  break_scenario late-delay bridge-example-late '.replies[0].delayMs = 5000'
  break_scenario refusal-stop bridge-example-refusal 'del(.replies[0].stopReason)'
  break_scenario default-confidence bridge-example '.replies[0].text = "{\"outcome\":\"tellnow\",\"reasons\":[\"x\"],\"confidence\":0.9}"'
  break_scenario default-sampling bridge-example '.replies[0].temperature = 0'
  break_scenario digest-reasons bridge-example-digest '.replies[0].text = "{\"outcome\":\"digest\",\"reasons\":[],\"confidence\":0.6}"'
  break_scenario tool-read-name bridge-example-tool-read '.replies[0].toolUse.name = "example_count_all"'
  break_scenario tool-risky-argument bridge-example-tool-risky '.replies[0].toolUse.input.team = "sales"'
  break_scenario tool-unclassified-marker bridge-example-tool-unclassified '.match.marker = "bridge-example-tool-risky"'
  break_scenario tool-untrusted-order bridge-example-tool-untrusted '.replies[0].toolUse |= reverse'
  break_scenario tool-risky-outcome bridge-example-tool-risky '.replies[1].text = "{\"outcome\":\"tellnow\",\"reasons\":[\"x\"],\"confidence\":0.8}"'
  break_scenario tool-read-sampling bridge-example-tool-read '.replies[1].temperature = 0'
  break_scenario tool-read-confidence bridge-example-tool-read '.replies[1].text = "{\"outcome\":\"tellnow\",\"reasons\":[\"x\"],\"confidence\":2}"'
  break_scenario tool-unclassified-replies bridge-example-tool-unclassified 'del(.replies[1])'
  break_scenario tool-risky-name bridge-example-tool-risky '.name = "bridge-example-tool-forward"'
  break_scenario tool-untrusted-status bridge-example-tool-untrusted '.replies[0].status = 500'
  # A scenario that keeps its calls but names a tool that the example's ToolSet no longer holds.
  sed '/<Tool Name="example_archive_item"/d' "$TOOLSET" > "$tmp/toolset-bad.cls"
  if [ -z "$(TOOLSET_UNDER_TEST="$tmp/toolset-bad.cls" scenario_problems "$SCENARIOS")" ]; then
    echo "FAIL scenarios: the rule does not flag a tool name that the ToolSet does not hold"
    fails=$((fails + 1)); scn_samples_ok=0
  fi
fi
if [ "$scn_samples_ok" -eq 1 ]; then
  hits=$(scenario_problems "$SCENARIOS")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL scenarios: the example's ten mock scenarios hold what the matrix reads from them"
    fails=$((fails + 1))
  else
    echo "PASS scenarios: the example's ten mock scenarios hold what the matrix reads from them"
  fi
fi

if [ "$fails" -ne 0 ]; then
  echo "test-bridge-example: $fails rule(s) failed"
  exit 1
fi
echo "test-bridge-example: all rules passed"
