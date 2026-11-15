#!/usr/bin/env bash
# The static pins of the bridge developer guide, docs/bridge-guide.md (Story 13.3; AD-2, AD-22, AD-29; FR-5). Starts nothing and makes no
# network call: the rules read files only (bash, awk, sed and grep), so the hosted `checks` job and the release checklist (row bridge-guide)
# run them. The commands of the guide are proved live by the standalone-bridge job (release/standalone-bridge.sh), which reads the marked
# blocks from the guide; this script keeps the guide, the job and the code from drifting apart.
#   - blocks     the install section holds the blocks load, install, provider, start and send, in that order, and every objectscript fence
#                in it has a marker (<!-- guide-run: <name> -->); each marker is in the guide once and has a non-empty block, closed by its
#                own fence, with exactly one `Set sc=`; the set of names that release/standalone-bridge.sh passes to guide_block and guide_check, and its
#                GUIDE_BLOCKS list, equal the guide's marker set; and no command line of a block is also a line or a literal of the script
#   - reference  the guide names every setting of Decide, Adapter.Agent and AgentRunner, every refused setting, the four settings of AI Hub's
#                runner, every property of the message classes, the three fields of the decision payload, every enum value, every event of
#                the host sink, the five results
#                of Approval.Answer, the timer limits as "<n> seconds", the fixed phrases of the reference sections (Timeouts.Derive,
#                Timeouts.Apply, @{config:, @{env:ANTHROPIC_API_KEY}, embedded Python, the experimental marks, the package sentence and
#                the follow-on sentence), the fixed phrases of PROSE_PHRASES in any section (step 6's Visual Trace path and timer, the
#                Govern section's Portal notice, the user rule), and the USERANSWERED reason, read from Process/Decide.cls (a change
#                to that parameter fails this rule until the guide follows it)
#   - tables     every setting of Decide, Adapter.Agent and AgentRunner and every AI Hub runner setting is the first cell of a row of the
#                guide's "Settings" section, and every property of Request the first cell of a row of its "Messages and enumerations"
#                section (a name that only the prose mentions, or that a table of another section holds, is not in its reference table)
#   - retrytext  the eight lines that DW-850 rules are, each as a whole line compared as a fixed string, in the guide: the TimerSeconds and
#                DecisionTokenBudget rows, the two Timeouts paragraphs, the fallback route, the Model row of DecisionResponse, the retry list's
#                bullet for a model test and the paragraph about the decision's record (the rest of the retry section is not pinned)
#   - livetext   the two lines that DW-773 rules are, each as a whole line compared as a fixed string, in the guide: the Settings
#                section's intro (which settings are read each time they are used) and the retry section's RetryItem bullet
#   - turntools  the four lines that Story 19.5, Story 35.1 and Story 22.6 rule are, each as a whole line compared as a fixed string, in the guide: the Settings table's
#                TurnToolsClass row, the lead-in of "The extension classes" (six classes), its TurnTools bullet (which ends with the sentence of DW-950: a held call
#                runs later on the agent's own tool manager, which does not hold the tools) and its McpServers bullet (the report's refused names, the probe, the proxy)
#   - contenttext the two lines that Story 26.3 rules are, each as a whole line compared as a fixed string, in the guide: the Settings table's
#                ContentClass row and the ContentClass bullet of "The extension classes"
#   - u229       the sentence of the owner's answers U-229 and U-237 (what is audited: no entry for a setting change; a tool call is a step unless
#                the decision times out; an approval and an approved call's run each write an entry) is, on one line, in the guide and in the
#                "Approval and audit" section of docs/security-overview.md
#   - public     the guide is ASCII and holds no local path, key-like string, URL, IP address, instance name, or name of the project that the
#                README's note says OcuTalon is not affiliated with (public-text rules; it prints file:line only, never the text)
# Each rule first runs on a synthetic sample that breaks it and on one that keeps it, so a rule that can no longer flag anything fails.
# A failing rule prints what is missing and never a secret. Prints one PASS or FAIL line per rule; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-bg.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

. "$root/docker/tests/lib-scan.sh"
. "$root/docker/tests/lib-keys.sh"

GUIDE=docs/bridge-guide.md
JOB=release/standalone-bridge.sh
OVERVIEW=docs/security-overview.md
BRIDGE=src/bridge/cls/OcuTalon/Bridge
INSTALL_ORDER="load install provider start send"
ALL_BLOCKS="approval-role install load provider send start tool-classification"
U229="In this release, changing this setting writes no OcuTalon audit entry. Each tool call is recorded as a step of its decision unless the decision times out, and an approval and an approved call's run each write an audit entry."
PKG_SENTENCE='OcuTalon installs this same bridge as part of its own package.'
FOLLOW_SENTENCE='A separate bridge package and listing are a follow-on.'
AIHUB_SETTINGS="AgentClass ProviderName ProviderConfig Model"
ANSWER_RESULTS="done already_answered expired not_found not_allowed"
# The fixed phrases of the guide's prose (AC 1 and AC 2): the requirements, the load without IPM, what the installer sets up, the
# instance-auditing check, the Visual Trace step and its timer, the Portal notice, the Workflow approvals, the developer-tool rules and the
# user rule.
PROSE_PHRASES='build 154
IRIS for Health
Interoperability namespace
$SYSTEM.OBJ.LoadDir
It needs no IPM
Visual Trace
OcuTalon.Bridge.Installer.InstanceAuditing
`OcuTalonApprovals`
`OcuTalonWorkflow`
No person is a Workflow
OcuTalon.Bridge.Approval.Answer
STEPLABEL
makes no `%AI` call
the default is empty, which refuses every class
View Full Trace
The header id is not a link
`Ens.AlarmRequest` to `Ens.Alarm`
needs an update
You can ignore it, because the bridge reads both settings live
Click the row
then the Trace tab
Session number
for a `decide` request whose provenance is `user`
changes an `ignore` or `digest` outcome to `tellnow`
The item of step 5 is sent as `untrusted`'

# --- helpers ---

# section_of <heading line> <file>: the lines of the H2 section whose heading line equals the first argument.
section_of() {
  awk -v h="$1" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$2"
}

# block_lines <name> <file>: the lines between the fences of the marked block, or nothing when the marker is not followed by a fence.
block_lines() {
  awk -v m="<!-- guide-run: $1 -->" '
    state == 0 && $0 == m { state = 1; next }
    state == 1 { if ($0 == "```objectscript") { state = 2; next } exit }
    state == 2 { if ($0 == "```") exit; print }
  ' "$2"
}

# block_closed <name> <file>: exits 0 when the marked block's fence is closed by a fence line of its own before any other fence line or the
# end of the file, as release/standalone-bridge.sh guide_block requires.
block_closed() {
  awk -v m="<!-- guide-run: $1 -->" '
    state == 0 && $0 == m { state = 1; next }
    state == 1 { if ($0 == "```objectscript") { state = 2; next } exit }
    state == 2 && /^```/ { if ($0 == "```") state = 3; exit }
    END { exit (state == 3 ? 0 : 1) }
  ' "$2"
}

# sorted_names <words>: the words, one per line, sorted and unique.
sorted_names() { printf '%s\n' $1 | sort -u; }

# --- blocks ---

# blocks_problems <guide> <job>: one line per problem.
blocks_problems() {
  local guide=$1 job=$2 order name n lines l i gc gb gd want
  # The markers of the install section, in order, and the fences without one.
  order=$(awk '
    /^## / { on = ($0 == "## Install and run the example"); prev = ""; next }
    on && /^```objectscript$/ {
      if (prev ~ /^<!-- guide-run: [a-z-]+ -->$/) { sub(/^<!-- guide-run: /, "", prev); sub(/ -->$/, "", prev); printf "%s ", prev }
      else printf "?%d ", FNR
    }
    { prev = $0 }
  ' "$guide")
  case $order in
    *'?'*) echo "an objectscript fence of the install section has no marker (line $(printf '%s' "$order" | tr ' ' '\n' | sed -n 's/^?//p' | head -n 1))" ;;
    *)
      if [ "$(printf '%s' "$order" | sed 's/ $//')" != "$INSTALL_ORDER" ]; then
        echo "the install section holds the blocks '$(printf '%s' "$order" | sed 's/ $//')', wanted '$INSTALL_ORDER' in that order"
      fi
      ;;
  esac
  # Each marker: once in the file, a fence after it, a non-empty block with one Set sc=.
  for name in $(grep -o '^<!-- guide-run: [a-z-]* -->$' "$guide" | sed 's/^<!-- guide-run: //; s/ -->$//' | sort -u); do
    n=$(grep -cxF -- "<!-- guide-run: $name -->" "$guide")
    if [ "$n" -ne 1 ]; then echo "the block $name: its marker is in the guide $n times, not once"; continue; fi
    lines=$(block_lines "$name" "$guide")
    if [ -z "$(printf '%s' "$lines" | tr -d '[:space:]')" ]; then echo "the block $name: it is empty, or its marker is not followed by an objectscript fence"; continue; fi
    block_closed "$name" "$guide" || echo "the block $name: its fence is not closed before the next fence or the end of the file"
    n=$(printf '%s\n' "$lines" | grep -c 'Set sc=')
    if [ "$n" -ne 1 ]; then echo "the block $name: it has $n commands that set sc, wanted 1"; fi
  done
  # The names: the guide's markers, GUIDE_BLOCKS of the job and the names that the job passes to guide_check and guide_block.
  gd=$(grep -o '^<!-- guide-run: [a-z-]* -->$' "$guide" | sed 's/^<!-- guide-run: //; s/ -->$//' | sort -u)
  gb=$(sed -n 's/^GUIDE_BLOCKS="\(.*\)"$/\1/p' "$job" | tr ' ' '\n' | sort -u)
  gc=$( { sed -n 's/^[[:space:]]*guide_check "[^"]*" \([a-z][a-z-]*\).*$/\1/p' "$job"; grep -o 'guide_block [a-z][a-z-]*' "$job" | sed 's/^guide_block //'; } | sort -u)
  if [ "$gd" != "$(sorted_names "$ALL_BLOCKS")" ]; then
    echo "the guide's markers are '$(printf '%s' "$gd" | tr '\n' ' ' | sed 's/ $//')', wanted '$ALL_BLOCKS'"
  fi
  for want in $gd; do
    printf '%s\n' "$gb" | grep -qx -- "$want" || echo "the block $want is not in GUIDE_BLOCKS of $job"
    printf '%s\n' "$gc" | grep -qx -- "$want" || echo "$job does not run the block $want (guide_check)"
  done
  for name in $gb; do
    printf '%s\n' "$gd" | grep -qx -- "$name" || echo "GUIDE_BLOCKS of $job names $name, which the guide has no block for"
  done
  for name in $gc; do
    printf '%s\n' "$gd" | grep -qx -- "$name" || echo "$job runs the block $name, which the guide has no block for"
  done
  # No command of a block is a line or a literal of the job.
  for name in $gd; do
    i=0
    while IFS= read -r l; do
      i=$((i + 1))
      [ -n "$l" ] || continue
      if grep -qF -- "$l" "$job"; then echo "the block $name, command $i, is also in $job"; fi
    done <<< "$(block_lines "$name" "$guide")"
  done
}

# Samples: a small guide and job that keep the rule, and one break at a time.
good_guide() {
  cat << 'EOF'
# Guide

## Install and run the example

<!-- guide-run: load -->
```objectscript
Set sc=1
Write sc
```

<!-- guide-run: install -->
```objectscript
Set sc=2
```

<!-- guide-run: provider -->
```objectscript
Set sc=3
```

<!-- guide-run: start -->
```objectscript
Set sc=4
```

<!-- guide-run: send -->
```objectscript
Set sc=5
```

## Govern the example's tools

<!-- guide-run: tool-classification -->
```objectscript
Set sc=6
```

<!-- guide-run: approval-role -->
```objectscript
Set sc=7
```

```objectscript
Set unmarked=1
```
EOF
}
good_job() {
  cat << 'EOF'
GUIDE_BLOCKS="load install provider tool-classification approval-role start send"
guide_check "label one" load ""
guide_check "label two" install "x"
guide_check "label three" provider ""
guide_check "label four" tool-classification ""
guide_check "label five" approval-role ""
guide_check "label six" start "y"
guide_check "label seven" send "z"
EOF
}
mkdir -p "$tmp/b"
good_guide > "$tmp/b/guide.md"
good_job > "$tmp/b/job.sh"
blocks_samples_ok=1
if [ -n "$(blocks_problems "$tmp/b/guide.md" "$tmp/b/job.sh")" ]; then
  echo "FAIL blocks: the rule flags a guide and a job that keep it"
  blocks_problems "$tmp/b/guide.md" "$tmp/b/job.sh" | sed 's/^/  /'
  fails=$((fails + 1)); blocks_samples_ok=0
fi
# break_blocks <label> <expected phrase> <guide sed program or -> <job sed program or ->: the break must be flagged, and one of the
# problems printed must hold the phrase, so that a sample is caught by the check it names and not by another one.
break_blocks() {
  local out
  cp "$tmp/b/guide.md" "$tmp/b/g.md"; cp "$tmp/b/job.sh" "$tmp/b/j.sh"
  [ "$3" = - ] || sed -i.bak "$3" "$tmp/b/g.md"
  [ "$4" = - ] || sed -i.bak "$4" "$tmp/b/j.sh"
  out=$(blocks_problems "$tmp/b/g.md" "$tmp/b/j.sh")
  if [ -z "$out" ]; then
    echo "FAIL blocks: the rule does not flag a break ($1)"
    fails=$((fails + 1)); blocks_samples_ok=0
  elif ! printf '%s\n' "$out" | grep -qF -- "$2"; then
    echo "FAIL blocks: a break ($1) is not flagged by the check that names '$2'"
    fails=$((fails + 1)); blocks_samples_ok=0
  fi
}
if [ "$blocks_samples_ok" -eq 1 ]; then
  break_blocks "a marker missing" "has no marker" '/guide-run: provider/d' -
  break_blocks "a marker twice" "not once" '$ a\
<!-- guide-run: send -->\
```objectscript\
Set sc=8\
```' -
  break_blocks "a marker renamed" "the install section holds the blocks" 's/guide-run: start -->/guide-run: begin -->/' -
  break_blocks "a fence in the install section without a marker" "has no marker" '/guide-run: install/d' -
  break_blocks "an empty block" "it is empty" '/^Set sc=3$/d' -
  break_blocks "a block that sets sc twice" "commands that set sc" '/^Set sc=3$/a\
Set sc=33' -
  break_blocks "the order of the install section" "in that order" 's/guide-run: install -->/guide-run: swap -->/;s/guide-run: provider -->/guide-run: install -->/;s/guide-run: swap -->/guide-run: provider -->/' -
  break_blocks "a marker not followed by a fence" "not followed by an objectscript fence" '/guide-run: tool-classification/{n;s/^```objectscript$/```text/;}' -
  break_blocks "a name the job lacks" "does not run the block" - '/ send "z"$/d'
  break_blocks "a name the guide lacks" "which the guide has no block for" - 's/send "z"/sendx "z"/'
  break_blocks "a block that the job does not run" "does not run the block" - '/approval-role ""$/d'
  break_blocks "a block whose fence is not closed before the next fence" "is not closed" '/^Set sc=7$/{n;d;}' -
  break_blocks "a block whose fence is not closed before the end of the file" "is not closed" '/^Set sc=7$/{n;d;};$d' -
  break_blocks "a name missing from GUIDE_BLOCKS" "is not in GUIDE_BLOCKS" - 's/^\(GUIDE_BLOCKS=.*\) send"$/\1"/'
  break_blocks "a name in GUIDE_BLOCKS that the guide lacks" "names sendx, which the guide has no block for" - 's/^\(GUIDE_BLOCKS=.*\) send"$/\1 send sendx"/'
  break_blocks "a command copied into the job" "is also in" - '$ a\
Set sc=4'
  break_blocks "a command copied as a literal" "is also in" - '$ a\
echo "Set sc=5"'
fi
if [ "$blocks_samples_ok" -eq 1 ]; then
  hits=$(blocks_problems "$GUIDE" "$JOB")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL blocks: the guide's marked blocks and the job that runs them agree"
    fails=$((fails + 1))
  else
    echo "PASS blocks: the guide's marked blocks and the job that runs them agree"
  fi
fi

# --- reference ---

# names_of <parameter> <file>: the names of a SETTINGS-style parameter value ("Name:Category,..."), one per line.
names_of() {
  sed -n "s/^Parameter $1 = \"\(.*\)\";\$/\1/p" "$2" | tr ',' '\n' | sed 's/:.*$//' | sed '/^$/d'
}
# properties_of <file>: the property names of a class, one per line.
properties_of() {
  sed -n 's/^Property \([A-Za-z][A-Za-z0-9]*\) .*$/\1/p' "$1"
}
# enum_values <file>: every value of the Parameter lines of Msg.Enum, one per line.
enum_values() {
  sed -n 's/^Parameter [A-Z]* = "\(.*\)";$/\1/p' "$1" | tr ',' '\n' | sed '/^$/d' | sort -u
}
# reference_names: every name that the guide must show between backticks, one per line.
reference_names() {
  {
    names_of SETTINGS "$BRIDGE/Process/Decide.cls"
    names_of SETTINGS "$BRIDGE/Adapter/Agent.cls"
    names_of REFUSED "$BRIDGE/Adapter/Agent.cls"
    names_of SETTINGS "$BRIDGE/Operation/AgentRunner.cls"
    printf '%s\n' $AIHUB_SETTINGS
    for c in Request Result DecisionResponse AgentStep; do properties_of "$BRIDGE/Msg/$c.cls"; done
    sed -n 's/.*%JSONFIELDNAME = "\([a-z]*\)".*/\1/p' "$BRIDGE/Msg/DecisionPayload.cls"
    enum_values "$BRIDGE/Msg/Enum.cls"
    sed -n 's/^Parameter [A-Z]* = "\([a-z]*\.[a-z]*\)";$/\1/p' "$BRIDGE/Ext/HostSink.cls"
    printf '%s\n' $ANSWER_RESULTS
  } | sort -u
}

# reference_problems <guide>: one line per problem.
reference_problems() {
  local guide=$1 name max min ua
  for name in $(reference_names); do
    grep -qF -- "\`$name\`" "$guide" || echo "the guide does not name \`$name\`"
  done
  max=$(sed -n 's/^Parameter MAXTIMER = \([0-9][0-9]*\);$/\1/p' "$BRIDGE/Process/Decide.cls")
  min=$(sed -n 's/^Parameter MINTIMER = \([0-9][0-9]*\);$/\1/p' "$BRIDGE/Process/Decide.cls")
  if [ -z "$max" ] || [ -z "$min" ]; then echo "MAXTIMER or MINTIMER of Decide.cls could not be read"; fi
  grep -qF -- "$max seconds" "$guide" || echo "the guide does not give the timer ceiling as '$max seconds'"
  grep -qF -- "$min seconds" "$guide" || echo "the guide does not give the timer floor as '$min seconds'"
  for name in 'Timeouts.Derive' 'Timeouts.Apply' '@{config:' '@{env:ANTHROPIC_API_KEY}' 'embedded Python' "$PKG_SENTENCE" "$FOLLOW_SENTENCE"; do
    grep -qF -- "$name" "$guide" || echo "the guide lacks '$name'"
  done
  while IFS= read -r name; do
    grep -qF -- "$name" "$guide" || echo "the guide lacks the prose phrase '$name'"
  done <<< "$PROSE_PHRASES"
  ua=$(sed -n 's/^Parameter USERANSWERED = "\(.*\)";$/\1/p' "$BRIDGE/Process/Decide.cls")
  if [ -z "$ua" ]; then echo "USERANSWERED of Decide.cls could not be read"; fi
  if [ -n "$ua" ]; then grep -qF -- "$ua" "$guide" || echo "the guide lacks the USERANSWERED reason of Decide"; fi
  grep -F 'StreamRenderer' "$guide" | grep -q 'experimental' || echo "no line of the guide holds both StreamRenderer and 'experimental'"
  grep -F 'SetAuthPolicy' "$guide" | grep -F 'SetAuditPolicy' | grep -q 'experimental' || echo "no line of the guide holds both policy setters and 'experimental'"
}
mkdir -p "$tmp/r"
ref_samples_ok=1
# break_ref <label> <sed program>: the keep sample with one edit must break the rule, and the edit must change the sample.
break_ref() {
  sed "$2" "$tmp/r/keep.md" > "$tmp/r/g.md"
  if cmp -s "$tmp/r/keep.md" "$tmp/r/g.md"; then
    echo "FAIL reference: the break sample '$1' changed nothing"
    fails=$((fails + 1)); ref_samples_ok=0
  elif [ -z "$(reference_problems "$tmp/r/g.md")" ]; then
    echo "FAIL reference: the rule does not flag a break ($1)"
    fails=$((fails + 1)); ref_samples_ok=0
  fi
}
if [ -z "$(reference_names)" ] || [ "$(reference_names | wc -l)" -lt 60 ]; then
  echo "FAIL reference: the names read from the sources are too few ($(reference_names | wc -l | tr -d ' '))"
  fails=$((fails + 1)); ref_samples_ok=0
fi
# The keep sample: a guide that names every item (the reference names, each between backticks, and the phrases) has no problem.
{
  reference_names | sed 's/.*/`&`/'
  echo "110 seconds 12 seconds Timeouts.Derive Timeouts.Apply @{config: @{env:ANTHROPIC_API_KEY} embedded Python"
  echo "$PKG_SENTENCE $FOLLOW_SENTENCE"
  printf '%s\n' "$PROSE_PHRASES"
  echo "StreamRenderer is experimental."
  echo "SetAuthPolicy and SetAuditPolicy are experimental."
  sed -n 's/^Parameter USERANSWERED = "\(.*\)";$/\1/p' "$BRIDGE/Process/Decide.cls"
} > "$tmp/r/keep.md"
if [ "$ref_samples_ok" -eq 1 ] && [ -n "$(reference_problems "$tmp/r/keep.md")" ]; then
  echo "FAIL reference: the rule flags a guide that names every item"
  reference_problems "$tmp/r/keep.md" | sed 's/^/  /'
  fails=$((fails + 1)); ref_samples_ok=0
fi
if [ "$ref_samples_ok" -eq 1 ]; then
  break_ref "a setting removed" 's/`RequestTokenLimit`/`Gone`/g'
  break_ref "a refused setting removed" 's/`SessionConfigString`/`Gone`/g'
  break_ref "an AI Hub setting removed" 's/`ProviderName`/`Gone`/g'
  break_ref "a message property removed" 's/`EstimatedTokens`/`Gone`/g'
  break_ref "a request property removed" 's/`ThreadSessionId`/`Gone`/g'
  break_ref "a payload field removed" 's/`confidence`/`Gone`/g'
  break_ref "an enum value removed" 's/`rate_limited`/`Gone`/g'
  break_ref "a channel removed" 's/`webhook`/`Gone`/g'
  break_ref "an Answer result removed" 's/`already_answered`/`Gone`/g'
  break_ref "the timer ceiling removed" 's/110 seconds/110 s/g'
  break_ref "the timer floor removed" 's/12 seconds/12 s/g'
  break_ref "a host-sink event removed" 's/`budget\.capped`/`Gone`/g'
  break_ref "Timeouts.Apply removed" 's/Timeouts\.Apply/Timeouts/g'
  break_ref "the config placeholder removed" 's/@{config:/@{cfg:/g'
  break_ref "the embedded Python rule removed" 's/embedded Python/a scripting language/g'
  break_ref "the experimental marks removed" 's/experimental//g'
  break_ref "the build requirement removed" 's/build 154/a build/g'
  break_ref "the Visual Trace step removed" 's/Visual Trace/the viewer/g'
  break_ref "the instance-auditing check removed" 's/OcuTalon\.Bridge\.Installer\.InstanceAuditing/Installer/g'
  break_ref "the Workflow role removed" 's/`OcuTalonApprovals`/`Gone`/g'
  break_ref "the no-Workflow-user statement removed" 's/No person is a Workflow/Some person is a Workflow/g'
  break_ref "the developer-tool %AI rule removed" 's/makes no `%AI` call/may call AI/g'
  break_ref "the allow-list default removed" 's/the default is empty, which refuses every class/see below/'
  break_ref "View Full Trace removed" 's/View Full Trace/the trace/g'
  break_ref "the header-id note removed" 's/The header id is not a link/The header id is a link/'
  break_ref "the alarm request removed" 's/AlarmRequest` to `Ens.Alarm`/AlarmRequest` to the timer/'
  break_ref "the Portal notice removed" 's/needs an update/is fine/g'
  break_ref "the Portal advice changed" 's/You can ignore it, because the bridge reads both settings live/Restart the production/'
  break_ref "the Trace tab removed" 's/then the Trace tab/then the page/'
  break_ref "the Session number removed" 's/Session number/Session link/g'
  break_ref "the row step removed" 's/Click the row/Click its header id/'
  break_ref "the Ens. prefix removed" 's/`Ens\.AlarmRequest`/`AlarmRequest`/'
  break_ref "the user-rule condition changed" 's/whose provenance is `user`/whose provenance is `untrusted`/'
  break_ref "the user-rule outcome removed" 's/changes an `ignore` or `digest` outcome to `tellnow`/leaves the outcome alone/'
  break_ref "the untrusted item note removed" 's/The item of step 5 is sent as `untrusted`/The item is sent/'
  break_ref "the user-rule reason changed" 's/a message the user writes is always answered/a message the user writes is answered/'
  break_ref "the package sentence removed" 's/OcuTalon installs this same bridge as part of its own package\.//'
  break_ref "the follow-on sentence removed" 's/A separate bridge package and listing are a follow-on\.//'
fi
if [ "$ref_samples_ok" -eq 1 ]; then
  hits=$(reference_problems "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL reference: the guide names every setting, field and value of the bridge, and the fixed phrases"
    fails=$((fails + 1))
  else
    echo "PASS reference: the guide names every setting, field and value of the bridge, and the fixed phrases"
  fi
fi

# --- tables ---

# tables_section <guide> <heading>: the lines of the "### <heading>" section of the guide, up to the next "##" or "###" heading.
tables_section() {
  awk -v h="### $2" '$0 == h { on = 1; next } /^###? / { on = 0 } on' "$1"
}

# tables_settings: every setting that must be the first cell of a row of the Settings tables, one per line.
tables_settings() {
  {
    names_of SETTINGS "$BRIDGE/Process/Decide.cls"
    names_of SETTINGS "$BRIDGE/Adapter/Agent.cls"
    names_of SETTINGS "$BRIDGE/Operation/AgentRunner.cls"
    printf '%s\n' $AIHUB_SETTINGS
  } | sort -u
}

# tables_properties: every property of Request, one per line. Each must be the first cell of a row of the Messages and enumerations tables.
tables_properties() {
  properties_of "$BRIDGE/Msg/Request.cls" | sort -u
}

# tables_names: every name checked, one per line.
tables_names() {
  { tables_settings; tables_properties; } | sort -u
}

# tables_problems <guide>: one line per name that is not the first cell of a row of the section that documents it.
tables_problems() {
  local name
  tables_section "$1" "Settings" > "$tmp/t/settings.md"
  tables_section "$1" "Messages and enumerations" > "$tmp/t/messages.md"
  for name in $(tables_settings); do
    grep -q -- "^| \`$name\` |" "$tmp/t/settings.md" || echo "no row of the Settings tables of the guide starts with \`$name\`"
  done
  for name in $(tables_properties); do
    grep -q -- "^| \`$name\` |" "$tmp/t/messages.md" || echo "no row of the Messages and enumerations tables of the guide starts with \`$name\`"
  done
}
mkdir -p "$tmp/t"
tables_ok=1
if [ "$(tables_names | wc -l)" -lt 30 ]; then
  echo "FAIL tables: the names read from the sources are too few ($(tables_names | wc -l | tr -d ' '))"
  fails=$((fails + 1)); tables_ok=0
fi
{
  echo "### Settings"
  tables_settings | sed 's/.*/| `&` | a value | what it does |/'
  echo "### Messages and enumerations"
  tables_properties | sed 's/.*/| `&` | what it holds |/'
  echo "### The fallback route"
} > "$tmp/t/keep.md"
if [ "$tables_ok" -eq 1 ] && [ -n "$(tables_problems "$tmp/t/keep.md")" ]; then
  echo "FAIL tables: the rule flags a guide whose tables hold every name"
  tables_problems "$tmp/t/keep.md" | sed 's/^/  /'
  fails=$((fails + 1)); tables_ok=0
fi
# break_tables <label> <name> <sed program>: the keep sample with one edit must be flagged, and the problem must name the name.
break_tables() {
  sed "$3" "$tmp/t/keep.md" > "$tmp/t/g.md"
  if cmp -s "$tmp/t/keep.md" "$tmp/t/g.md"; then
    echo "FAIL tables: the break sample '$1' changed nothing"
    fails=$((fails + 1)); tables_ok=0
  elif ! printf "%s\n" "$(tables_problems "$tmp/t/g.md")" | grep -qF -- "\`$2\`"; then
    echo "FAIL tables: the rule does not flag a break ($1)"
    fails=$((fails + 1)); tables_ok=0
  fi
}
if [ "$tables_ok" -eq 1 ]; then
  break_tables "the RetryItem row removed" RetryItem '/^| `RetryItem` |/d'
  break_tables "the RetryOf row removed" RetryOf '/^| `RetryOf` |/d'
  break_tables "a setting that is named in prose only" TimerSeconds 's/^| `TimerSeconds` | a value /The `TimerSeconds` setting | a value /'
  break_tables "a setting in the second cell of a row" TimerSeconds 's/^| `TimerSeconds` | a value /| Timer | `TimerSeconds` | a value /'
  break_tables "a Request property in the Settings section only" RetryOf '/^### Messages and enumerations$/d'
  break_tables "a setting in the Messages and enumerations section only" TimerSeconds 's/^### Settings$/### Messages and enumerations/'
  break_tables "a section that runs into a chapter" RetryOf 's/^### The fallback route$/## Second-model retry/;/^| `RetryOf` |/d;$a\
| `RetryOf` | what it holds |'
  break_tables "an AI Hub setting removed" ProviderName '/^| `ProviderName` |/d'
fi
if [ "$tables_ok" -eq 1 ]; then
  hits=$(tables_problems "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL tables: every setting is the first cell of a row of the Settings tables and every Request property of a row of the Messages and enumerations tables of the guide"
    fails=$((fails + 1))
  else
    echo "PASS tables: every setting is the first cell of a row of the Settings tables and every Request property of a row of the Messages and enumerations tables of the guide"
  fi
fi

# --- retrytext ---

# retry_lines: the ruled lines of the guide (DW-850), one per line.
retry_lines() {
  cat << 'EOF'
| `TimerSeconds` | 60 | How long `Decide` waits for the runner's reply, in whole seconds, from 12 seconds to 110 seconds. When it passes, the fallback route is taken with the reason `timeout`, unless the second-model retry is sent. The retry waits the lesser of `TimerSeconds` and 110 seconds minus the first attempt's timer. See "Timeouts" and "Second-model retry". |
| `DecisionTokenBudget` | 0 (none) | The token budget of each attempt of a decision, checked against the attempt's estimate before it is sent. A request whose estimate is above it takes the fallback route with the reason `budget`, and is never sent. A second-model retry is checked against it again, on its own estimate. The budget is not a total over both attempts. |
`TimerSeconds` is the one timer. A decision with a second-model retry has two attempts, which share the 110 seconds: the retry waits the lesser of `TimerSeconds` and 110 seconds minus the first attempt's timer (see "Second-model retry"). Two things depend on it, and `OcuTalon.Bridge.Timeouts` works both out so that no other place holds a second copy of a number:
The timer can be 12 seconds at the least and 110 seconds at the most. After you change `TimerSeconds`, edit the `ProviderConfig` row so that its `http_config` is the new `Derive(timer)`'s (for a retry runner, `Derive(Timeouts.RetryTimer(timer))`'s, see "Second-model retry") and update the production, or keep the provider in the Config Store as an entry and let `Timeouts.Apply(timer)` change the timer, the entries and the runners together. Apply needs each runner's `ProviderConfig` to be `@{config:<name>}`, and restarts `Decide` and the runners.
| `Model` | The model that answered. After a second-model retry, the second model; when the retry's timer passes before its reply arrives, the model of the last model request counted for the decision, which can be the first model. Empty when no model was asked. |
When the model cannot give a usable answer, `Decide` does not guess. When a second model is set, `Decide` may first try the request once on it, as "Second-model retry" says, and takes the fallback route only when no retry is sent or the retry gives no usable answer either. It records one decision with the outcome `tellnow`, `Fallback` 1 and the reason (after a retry, the last attempt's), keeps no model text, and answers with it, so that the person is told. A fallback starts no tool, fix or approval. The reasons:
- A model test request (its `ItemId` starts with `test.`), so that the test says whether the first model answered.
The decision is still one record and one answer. Its tokens, cost and steps are the sums of both attempts, its `Model` is as the `Model` field of `OcuTalon.Bridge.Msg.DecisionResponse` says, and, when both attempts fail, its reason is the last attempt's.
EOF
}

# retry_problems <guide>: one line per ruled line that the guide lacks as a whole line.
retry_problems() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    grep -qxF -- "$line" "$1" || echo "the guide lacks ruled line $n of the second-model retry wording (starting '$(printf '%s' "$line" | cut -c1-40)')"
  done < <(retry_lines)
}
mkdir -p "$tmp/m"
retry_ok=1
retry_lines > "$tmp/m/keep.md"
if [ "$(wc -l < "$tmp/m/keep.md" | tr -d ' ')" -ne 8 ]; then
  echo "FAIL retrytext: the ruled text is not eight lines"
  fails=$((fails + 1)); retry_ok=0
fi
if [ "$retry_ok" -eq 1 ] && [ -n "$(retry_problems "$tmp/m/keep.md")" ]; then
  echo "FAIL retrytext: the rule flags a guide that holds the ruled text"
  retry_problems "$tmp/m/keep.md" | sed 's/^/  /'
  fails=$((fails + 1)); retry_ok=0
fi
# One character of each ruled line changed, one line at a time: the rule must flag that line.
if [ "$retry_ok" -eq 1 ]; then
  for i in 1 2 3 4 5 6 7 8; do
    awk -v n="$i" 'NR == n { sub(/[a-z]/, "X") } { print }' "$tmp/m/keep.md" > "$tmp/m/g.md"
    if cmp -s "$tmp/m/keep.md" "$tmp/m/g.md"; then
      echo "FAIL retrytext: the break sample for ruled line $i changed nothing"
      fails=$((fails + 1)); retry_ok=0
    elif ! retry_problems "$tmp/m/g.md" | grep -qF -- "ruled line $i "; then
      echo "FAIL retrytext: the rule does not flag a changed character in ruled line $i"
      fails=$((fails + 1)); retry_ok=0
    fi
  done
fi
if [ "$retry_ok" -eq 1 ]; then
  hits=$(retry_problems "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL retrytext: the guide's second-model retry wording is the ruled text"
    fails=$((fails + 1))
  else
    echo "PASS retrytext: the guide's second-model retry wording is the ruled text"
  fi
fi

# --- livetext ---

# live_lines: the ruled lines of the guide (DW-773), one per line.
live_lines() {
  cat << 'EOF'
The bridge is configured only by settings. Each is a setting of a production item, or a System Default Settings row for the item, and the default applies until you set one. These settings are read each time they are used, so a change needs no update: `DecisionTokenBudget`, `RequestTokenLimit`, `DailyCostCapUSD`, `GatewaySpendUSD`, `GatewaySpendDate`, `InstanceZone`, `ServiceUser`, `ApprovalRole`, `ToolClassification`, `ClassificationClass`, `TurnToolsClass` and `ContentClass` of `Decide`, and `ReplyClass` and `RetryItem` of a runner. `Decide` reads `DecisionTokenBudget` and `RequestTokenLimit` this way only when it runs in a job of its own (a pool size of 1 or more, as in the example); in the shared actor pool, update the production after you change them. `HostSinkClass` is read each time too, except for the events that `Decide` fires itself, which follow a change only after `Decide` restarts. Every other setting takes effect when its item restarts: after you write or change one, update the production, for example with `Do ##class(Ens.Director).UpdateProduction()`. For `TimerSeconds`, see "Timeouts".
- `RetryItem` is a setting of a runner item, and `Decide` reads it. It names the retry runner of that runner: another enabled `OcuTalon.Bridge.Operation.AgentRunner` item of the production, whose `Model` setting is the second model. An empty value means no second model, and it is empty by default. A value that names the runner itself, a missing, disabled or non-runner item, or (for a decision or a diagnosis) an item whose `ReplyClass` is refused is not used: `Decide` logs one warning that names the setting and takes the fallback route. A retry runner's own `RetryItem` is never followed, so a retry is never retried. Write `RetryItem` as any setting in "Settings" is written. `Decide` reads it live, so it needs no update; a retry runner item that you add to the production starts when you update the production. The retry runner is set up like any runner: `AgentClass`, `AgentAllowList`, `ProviderConfig`, and `ReplyClass` for a decision or a diagnosis.
EOF
}

# live_problems <guide>: one line per ruled line that the guide lacks as a whole line.
live_problems() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    grep -qxF -- "$line" "$1" || echo "the guide lacks ruled line $n of the live-settings wording (starting '$(printf '%s' "$line" | cut -c1-40)')"
  done < <(live_lines)
}
mkdir -p "$tmp/l"
live_ok=1
live_lines > "$tmp/l/keep.md"
if [ "$(wc -l < "$tmp/l/keep.md" | tr -d ' ')" -ne 2 ]; then
  echo "FAIL livetext: the ruled text is not two lines"
  fails=$((fails + 1)); live_ok=0
fi
if [ "$live_ok" -eq 1 ] && [ -n "$(live_problems "$tmp/l/keep.md")" ]; then
  echo "FAIL livetext: the rule flags a guide that holds the ruled text"
  live_problems "$tmp/l/keep.md" | sed 's/^/  /'
  fails=$((fails + 1)); live_ok=0
fi
# One character of each ruled line changed, one line at a time: the rule must flag that line.
if [ "$live_ok" -eq 1 ]; then
  for i in 1 2; do
    awk -v n="$i" 'NR == n { sub(/[a-z]/, "X") } { print }' "$tmp/l/keep.md" > "$tmp/l/g.md"
    if cmp -s "$tmp/l/keep.md" "$tmp/l/g.md"; then
      echo "FAIL livetext: the break sample for ruled line $i changed nothing"
      fails=$((fails + 1)); live_ok=0
    elif ! live_problems "$tmp/l/g.md" | grep -qF -- "ruled line $i "; then
      echo "FAIL livetext: the rule does not flag a changed character in ruled line $i"
      fails=$((fails + 1)); live_ok=0
    fi
  done
fi
if [ "$live_ok" -eq 1 ]; then
  hits=$(live_problems "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL livetext: the guide's live-settings wording is the ruled text"
    fails=$((fails + 1))
  else
    echo "PASS livetext: the guide's live-settings wording is the ruled text"
  fi
fi

# --- turntools ---

# turn_lines: the lines of the guide that Story 19.5 ruled for the TurnToolsClass extension (the settings table row, the lead-in of "The extension classes" with its
# six classes, and the fourth and fifth bullets), one per line.
turn_lines() {
  cat << 'EOF'
| `TurnToolsClass` | `OcuTalon.Bridge.Ext.TurnTools` | The class that gives one request tools of its own, such as a knowledge base of the person's documents. See "The extension classes". |
The bridge reaches your code only through six classes, each with a do-nothing default, so that the bridge runs alone. You extend a class and name the subclass in its `Decide` setting:
- `OcuTalon.Bridge.Ext.TurnTools` (`TurnToolsClass`): `Tools(ownerRef, kind, tools)` returns the tools to add to one request, each an object with `AddToManager(manager)`, such as an AI Hub knowledge base. When it returns any, the runner gives that request a new tool manager with the agent's own tools, the tools attached when the agent was built, these tools, the gate and the step audit, and puts the agent's own manager back afterwards; an agent that declares skills cannot take tools of its own this way. It returns none by default. Classify each tool it returns safe (a `ToolClassification` row): a call held for approval runs later on the agent's own tool manager, which does not hold these tools.
- `OcuTalon.Bridge.Ext.McpServers` (`McpServersClass`): `Servers(servers)` returns the MCP servers to attach, each an object with `server` and `config` (the name of a Config Store entry `AI.MCP.<name>`); `OnAttach(server, report)` receives the report of each attach: `status` (`attached` or `unavailable`), `reason`, the `tools` attached, the `refused` ones (a name that one of the agent's own tools, or the proxy `call_mcp_tool`, already has) and, for an attached server, their `fingerprints`. `Probe(server, config)` says whether a server answers before its tools are offered, and must return within a few seconds; `ProxyToolSet()` names the toolset of the one governed tool, `call_mcp_tool`, through which every MCP call runs; `ServerOf(toolref)` names the server of a toolref; and `ToolsReadOnly(server)` says whether every tool of a server is classified read-only. The agent's own tool manager holds no MCP server: each request gets a manager of its own with the proxy and the servers whose probe answered, an agent that declares skills gets no MCP tools, and an unavailable server never fails the build. It attaches nothing by default.
EOF
}

# turn_problems <guide>: one line per ruled line that the guide lacks as a whole line.
turn_problems() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    grep -qxF -- "$line" "$1" || echo "the guide lacks ruled line $n of the TurnToolsClass wording (starting '$(printf '%s' "$line" | cut -c1-40)')"
  done < <(turn_lines)
}
mkdir -p "$tmp/t"
turn_ok=1
turn_lines > "$tmp/t/keep.md"
if [ "$(wc -l < "$tmp/t/keep.md" | tr -d ' ')" -ne 4 ]; then
  echo "FAIL turntools: the ruled text is not four lines"
  fails=$((fails + 1)); turn_ok=0
fi
if [ "$turn_ok" -eq 1 ] && [ -n "$(turn_problems "$tmp/t/keep.md")" ]; then
  echo "FAIL turntools: the rule flags a guide that holds the ruled text"
  turn_problems "$tmp/t/keep.md" | sed 's/^/  /'
  fails=$((fails + 1)); turn_ok=0
fi
# One character of each ruled line changed, one line at a time: the rule must flag that line.
if [ "$turn_ok" -eq 1 ]; then
  for i in 1 2 3 4; do
    awk -v n="$i" 'NR == n { sub(/[a-z]/, "X") } { print }' "$tmp/t/keep.md" > "$tmp/t/g.md"
    if cmp -s "$tmp/t/keep.md" "$tmp/t/g.md"; then
      echo "FAIL turntools: the break sample for ruled line $i changed nothing"
      fails=$((fails + 1)); turn_ok=0
    elif ! turn_problems "$tmp/t/g.md" | grep -qF -- "ruled line $i "; then
      echo "FAIL turntools: the rule does not flag a changed character in ruled line $i"
      fails=$((fails + 1)); turn_ok=0
    fi
  done
fi
if [ "$turn_ok" -eq 1 ]; then
  hits=$(turn_problems "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL turntools: the guide's TurnToolsClass wording is the ruled text"
    fails=$((fails + 1))
  else
    echo "PASS turntools: the guide's TurnToolsClass wording is the ruled text"
  fi
fi

# --- contenttext ---

# content_lines: the lines of the guide that Story 26.3 ruled for the ContentClass extension (the settings table row and the bullet of "The extension classes"), one
# per line.
content_lines() {
  cat << 'EOF'
| `ContentClass` | `OcuTalon.Bridge.Ext.Content` | The class that gives an untrusted chat turn one image to send with its text, and receives each accepted chat reply. See "The extension classes". |
- `OcuTalon.Bridge.Ext.Content` (`ContentClass`): `Part(request, mediaType, data)` returns one image, a JPEG or PNG stream and its media type, to send with an untrusted chat turn; the runner sends the turn's text and the image together in that turn's throwaway session, and the image never enters a message body, an agent step or the event log. `Accepted(request, text, hostData)` is called once after `Decide` accepts a usable chat reply, with the filtered reply text, and the members it returns in `hostData` are added to the reply's `HostData`. Both do nothing by default.
EOF
}

# content_problems <guide>: one line per ruled line that the guide lacks as a whole line.
content_problems() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    grep -qxF -- "$line" "$1" || echo "the guide lacks ruled line $n of the ContentClass wording (starting '$(printf '%s' "$line" | cut -c1-40)')"
  done < <(content_lines)
}
mkdir -p "$tmp/c"
content_ok=1
content_lines > "$tmp/c/keep.md"
if [ "$(wc -l < "$tmp/c/keep.md" | tr -d ' ')" -ne 2 ]; then
  echo "FAIL contenttext: the ruled text is not two lines"
  fails=$((fails + 1)); content_ok=0
fi
if [ "$content_ok" -eq 1 ] && [ -n "$(content_problems "$tmp/c/keep.md")" ]; then
  echo "FAIL contenttext: the rule flags a guide that holds the ruled text"
  content_problems "$tmp/c/keep.md" | sed 's/^/  /'
  fails=$((fails + 1)); content_ok=0
fi
# One character of each ruled line changed, one line at a time: the rule must flag that line.
if [ "$content_ok" -eq 1 ]; then
  for i in 1 2; do
    awk -v n="$i" 'NR == n { sub(/[a-z]/, "X") } { print }' "$tmp/c/keep.md" > "$tmp/c/g.md"
    if cmp -s "$tmp/c/keep.md" "$tmp/c/g.md"; then
      echo "FAIL contenttext: the break sample for ruled line $i changed nothing"
      fails=$((fails + 1)); content_ok=0
    elif ! content_problems "$tmp/c/g.md" | grep -qF -- "ruled line $i "; then
      echo "FAIL contenttext: the rule does not flag a changed character in ruled line $i"
      fails=$((fails + 1)); content_ok=0
    fi
  done
fi
if [ "$content_ok" -eq 1 ]; then
  hits=$(content_problems "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL contenttext: the guide's ContentClass wording is the ruled text"
    fails=$((fails + 1))
  else
    echo "PASS contenttext: the guide's ContentClass wording is the ruled text"
  fi
fi

# --- u229 ---

# u229_problems <guide> <overview>: one line per problem.
u229_problems() {
  grep -qF -- "$U229" "$1" || echo "$1 lacks the U-229 sentence"
  section_of '## Approval and audit' "$2" | grep -qF -- "$U229" || echo "the Approval and audit section of $2 lacks the U-229 sentence"
}
mkdir -p "$tmp/u"
printf 'Guide.\n%s\n' "$U229" > "$tmp/u/guide-good.md"
printf '# Overview\n\n## Approval and audit\n\nFirst sentence. %s Next.\n\n## Other\n\nText.\n' "$U229" > "$tmp/u/over-good.md"
printf 'Guide.\nIn this release, changing this setting writes no OcuTalon audit entry; each tool call is still audited.\n' > "$tmp/u/guide-old.md"
printf 'Guide.\n%s\n' "$(printf '%s' "$U229" | sed 's/writes no OcuTalon/writes an OcuTalon/')" > "$tmp/u/guide-word.md"
printf 'Guide.\n%s\n' "$(printf '%s' "$U229" | sed 's/ entry\. Each/ entry.\
Each/')" > "$tmp/u/guide-split.md"
printf '# Overview\n\n## Approval and audit\n\nFirst sentence. Next.\n\n## Other\n\n%s\n' "$U229" > "$tmp/u/over-bad.md"
printf '# Overview\n\n## Approval and audit\n\nFirst sentence. In this release, changing this setting writes no OcuTalon audit entry; each tool call is still audited. Next.\n' > "$tmp/u/over-old.md"
u_ok=1
[ -z "$(u229_problems "$tmp/u/guide-good.md" "$tmp/u/over-good.md")" ] || { echo "FAIL u229: the rule flags files that keep it"; fails=$((fails + 1)); u_ok=0; }
for f in old word split; do
  [ -n "$(u229_problems "$tmp/u/guide-$f.md" "$tmp/u/over-good.md")" ] || { echo "FAIL u229: the rule does not flag a bad sentence in the guide ($f)"; fails=$((fails + 1)); u_ok=0; }
done
cmp -s "$tmp/u/guide-good.md" "$tmp/u/guide-word.md" && { echo "FAIL u229: the one-word break sample changed nothing"; fails=$((fails + 1)); u_ok=0; }
[ "$(wc -l < "$tmp/u/guide-split.md")" -eq 3 ] || { echo "FAIL u229: the split-line break sample is not on two lines"; fails=$((fails + 1)); u_ok=0; }
[ -n "$(u229_problems "$tmp/u/guide-good.md" "$tmp/u/over-old.md")" ] || { echo "FAIL u229: the rule does not flag the old sentence in the overview"; fails=$((fails + 1)); u_ok=0; }
[ -n "$(u229_problems "$tmp/u/guide-good.md" "$tmp/u/over-bad.md")" ] || { echo "FAIL u229: the rule does not flag a sentence outside the Approval and audit section"; fails=$((fails + 1)); u_ok=0; }
if [ "$u_ok" -eq 1 ]; then
  hits=$(u229_problems "$GUIDE" "$OVERVIEW")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL u229: the U-229 sentence is in the guide and in the Approval and audit section of the security overview"
    fails=$((fails + 1))
  else
    echo "PASS u229: the U-229 sentence is in the guide and in the Approval and audit section of the security overview"
  fi
fi

# --- public ---

# public_hits <file>...: file:line of each line that breaks a public-text rule, and never the text. The words are bracketed so that this
# file does not hold them.
public_hits() {
  {
    LC_ALL=C grep -nH '[^[:print:][:space:]]' "$@" | cut -d: -f1,2
    local_path "$@"
    key_like "$@"
    grep -nHiE 'https?://' "$@" | cut -d: -f1,2
    grep -nHE '(^|[^0-9.])[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}($|[^0-9.])' "$@" | cut -d: -f1,2
    grep -nHiE 'ocutalon-slo[t]|aihub-tes[t]|ocutalon-c[i]|ocupilo[t]|iris-community-editio[n]|iris[ ]cou[c]h|[o]pen[c]law' "$@" | cut -d: -f1,2
  } | sort -u
}
mkdir -p "$tmp/p"
printf 'A plain line.\nAnother line with a path /opt/ocutalon/src/bridge and build 154.\n' > "$tmp/p/good.md"
pub_ok=1
[ -z "$(public_hits "$tmp/p/good.md")" ] || { echo "FAIL public: the rule flags a file that keeps it"; public_hits "$tmp/p/good.md" | sed 's/^/  /'; fails=$((fails + 1)); pub_ok=0; }
break_pub() { # <label> <text of the line>
  printf 'A plain line.\n%s\n' "$2" > "$tmp/p/bad.md"
  if [ "$(public_hits "$tmp/p/bad.md")" != "$tmp/p/bad.md:2" ]; then
    echo "FAIL public: the rule does not flag, or does not locate, a break ($1)"
    fails=$((fails + 1)); pub_ok=0
  fi
  case $(public_hits "$tmp/p/bad.md") in *"$2"*) echo "FAIL public: the rule prints the text of a break ($1)"; fails=$((fails + 1)); pub_ok=0 ;; esac
}
if [ "$pub_ok" -eq 1 ]; then
  break_pub "a non-ASCII byte" "caf$(printf '\303\251') line"
  break_pub "a local path" "see /Use""rs/someone/work here"
  break_pub "a key-like string" "key sk-""ant-""aaaaaaaaaaaaaaaa here"
  break_pub "a URL" "see ht""tps://example.invalid/page here"
  break_pub "an IP address" "host 10.20.""30.40 here"
  break_pub "an instance name" "the ocutalon-""slot-b container"
  break_pub "a test instance name" "the aihub-""test instance"
  break_pub "a runner host name" "the ocutalon-""ci-b host"
  break_pub "a container name" "the ocu""pilot container"
  break_pub "the community instance" "the iris-community-""edition container"
  break_pub "the forbidden product name in any case" "the IRIS Cou""ch name"
  break_pub "the unaffiliated project's name in any case" "the Open""Claw name"
fi
if [ "$pub_ok" -eq 1 ]; then
  hits=$(public_hits "$GUIDE")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "FAIL public: the guide is ASCII and holds no local path, key, URL, IP address, instance name or forbidden name"
    fails=$((fails + 1))
  else
    echo "PASS public: the guide is ASCII and holds no local path, key, URL, IP address, instance name or forbidden name"
  fi
fi

if [ "$fails" -ne 0 ]; then
  echo "test-bridge-guide: $fails rule(s) failed"
  exit 1
fi
echo "test-bridge-guide: all rules passed"
