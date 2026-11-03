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
