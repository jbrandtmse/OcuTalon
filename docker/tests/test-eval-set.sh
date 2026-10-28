#!/usr/bin/env bash
# The repository check of the evaluation set (Story 9.2; AD-22, AD-29; CON-5). It is a unit of the hosted `checks` job (CHECK_SCRIPTS of
# ci/units.sh), starts nothing, and needs bash and Node. It reads the files below eval/, the mock's scenarios below ci/mock/scenarios/A/,
# .github/workflows/lane-a.yml and the enumerations of the classes. A failure prints `file: rule` and never the text of the file.
# Each rule first runs on synthetic trees: one for each way to break the rule, which must be flagged, and a good one, which must not be
# (the convention of lib-scan.sh); only then does it read the real tree. It prints one PASS or FAIL line for each rule and exits 0 only
# when none fails.
#   enumerations  the outcomes (Msg.Enum OUTCOME), the cause categories, fix kinds and fix category (Watch.Msg.DiagnosisPayload
#                 CAUSECATEGORIES, FIXKINDS and FIXCATEGORY) and the case kinds (Eval.Report CASEKINDS) are read from their classes, and
#                 each is found;
#   cases         eval/ holds a case.json, and every one is a JSON object that has a name equal to its folder's, a kind of the case kinds, a boolean
#                 heldOut, a description, a recordedBy and an expectation with the fields of its kind, and its kind's record; and every
#                 folder below eval/ that holds a file holds a case.json:
#                   item and injection  expectation.outcome of the outcomes; an item record with an itemId and a provenance that is
#                                       absent or untrusted;
#                   incident            expectation.causeCategory of the categories, an elementAtFault, and a fixKind of the fix kinds
#                                       when the category is the fix category and empty otherwise; a snapshot, the name of a file in the
#                                       folder whose format is ocutalon.readerSnapshot/1;
#                   all-clear           expectation.catalogKey; checks, an array of objects whose result is passed, failed or not_checked;
#   markers       eval/mock-wrong/ holds a case; a [[mock:<name>]] marker appears only in the cases below it; each such case is of kind item or injection
#                 and names a scenario ci/mock/scenarios/A/<name>.json whose first reply is a JSON text with an outcome other than the
#                 case's expected outcome;
#   job           .github/workflows/lane-a.yml has a job evaluation with a step that runs `bash eval/run.sh`, and no workflow file
#                 names the switch OCUTALON_EVAL, which eval/run.sh exports for its own throwaway (owner condition U-131);
#   eval-scripts  eval/run.sh exists, and no code line of a .sh file below eval/ names the container tool or calls dc with config,
#                 convert or push: those scripts reach the container through the functions of ci/iris.sh and lib-live.sh.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
. "$root/docker/tests/lib-scan.sh"

fails=0
if ! command -v node >/dev/null 2>&1; then
  echo "FAIL node is not installed: the case check needs it"
  exit 1
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-es.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

ENUM_FILE=src/ocutalon/cls/OcuTalon/Msg/Enum.cls
DIAGNOSIS_FILE=src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls
REPORT_FILE=src/ocutalon/cls/OcuTalon/Eval/Report.cls

# enum_value <file> <name>: the text of `Parameter <name> = "...";` in the class file.
enum_value() {
  sed -n "s/^Parameter $2 = \"\\(.*\\)\";.*\$/\\1/p" "$1" 2> /dev/null | head -n 1
}

# --- the Node programs ---

cat > "$tmp/check-cases.mjs" <<'EOF'
import fs from 'node:fs';
import path from 'node:path';

const [root, filesPath] = process.argv.slice(2);
const list = (name) => (process.env[name] || '').split(',').filter(Boolean);
const OUTCOMES = list('ENUM_OUTCOME');
const KINDS = list('ENUM_CASEKINDS');
const CATEGORIES = list('ENUM_CAUSECATEGORIES');
const FIXKINDS = list('ENUM_FIXKINDS');
const FIXCATEGORY = process.env.ENUM_FIXCATEGORY || '';
const RESULTS = ['passed', 'failed', 'not_checked'];
const SNAPSHOT_FORMAT = 'ocutalon.readerSnapshot/1';

const out = [];
const bad = (file, rule) => out.push(`${file}: ${rule}`);
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const text = (v) => typeof v === 'string' && v.trim() !== '';
const readJson = (file) => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));

try {
  const files = fs.readFileSync(filesPath, 'utf8').split('\n').filter((f) => f.startsWith('eval/') && !path.posix.basename(f).startsWith('.'));
  const holdsFile = new Set();
  const holdsCase = new Set();
  if (!files.some((f) => path.posix.basename(f) === 'case.json')) bad('eval', 'holds no case.json');
  for (const f of files) {
    const dir = path.posix.dirname(f);
    if (dir === 'eval') continue;
    holdsFile.add(dir);
    if (path.posix.basename(f) === 'case.json') holdsCase.add(dir);
  }
  for (const dir of [...holdsFile].sort()) {
    if (!holdsCase.has(dir)) bad(dir, 'holds a file but no case.json');
  }
  for (const file of files.filter((f) => path.posix.basename(f) === 'case.json').sort()) {
    const dir = path.posix.dirname(file);
    let c;
    try {
      c = readJson(file);
    } catch {
      bad(file, 'is not valid JSON');
      continue;
    }
    if (!isObject(c)) {
      bad(file, 'is not a JSON object');
      continue;
    }
    if (c.name !== path.posix.basename(dir)) bad(file, "name is not its folder's name");
    if (!KINDS.includes(c.kind)) bad(file, 'kind is not one of the case kinds');
    if (typeof c.heldOut !== 'boolean') bad(file, 'heldOut is not a boolean');
    if (!text(c.description)) bad(file, 'has no description');
    if (!text(c.recordedBy)) bad(file, 'has no recordedBy');
    const e = c.expectation;
    if (!isObject(e)) bad(file, 'has no expectation');
    else if (Object.keys(e).length === 0) bad(file, 'the expectation is empty');
    const x = isObject(e) ? e : {};
    if (c.kind === 'item' || c.kind === 'injection') {
      if (!OUTCOMES.includes(x.outcome)) bad(file, 'expectation.outcome is not one of the outcomes');
      if (!isObject(c.item) || !text(c.item.itemId)) bad(file, 'has no item.itemId');
      else if (c.item.provenance !== undefined && c.item.provenance !== 'untrusted') bad(file, 'item.provenance is not untrusted');
    } else if (c.kind === 'incident') {
      if (!CATEGORIES.includes(x.causeCategory)) bad(file, 'expectation.causeCategory is not one of the cause categories');
      if (!text(x.elementAtFault)) bad(file, 'has no expectation.elementAtFault');
      const fix = x.fixKind === undefined ? '' : x.fixKind;
      if (x.causeCategory === FIXCATEGORY) {
        if (!FIXKINDS.includes(fix)) bad(file, 'expectation.fixKind is not one of the fix kinds');
      } else if (fix !== '') {
        bad(file, 'expectation.fixKind must be empty for a category with no fix');
      }
      const name = c.snapshot;
      if (!text(name) || name.includes('/') || name.includes('\\') || !fs.existsSync(path.join(root, dir, name))) {
        bad(file, 'its snapshot is not a file of the folder');
      } else {
        let snapshot = null;
        try {
          snapshot = readJson(path.posix.join(dir, name));
        } catch {
          snapshot = null;
        }
        if (!isObject(snapshot) || snapshot.format !== SNAPSHOT_FORMAT) bad(file, 'its snapshot is not a reader snapshot');
      }
    } else if (c.kind === 'all-clear') {
      if (!text(x.catalogKey)) bad(file, 'has no expectation.catalogKey');
      if (!Array.isArray(c.checks) || !c.checks.every((k) => isObject(k) && RESULTS.includes(k.result))) {
        bad(file, 'checks is not an array of objects with a result of passed, failed or not_checked');
      }
    }
  }
} catch {
  bad('check-cases', 'could not read the tree');
}
process.stdout.write(out.length ? `${out.join('\n')}\n` : '');
EOF

cat > "$tmp/check-markers.mjs" <<'EOF'
import fs from 'node:fs';
import path from 'node:path';

const [root, filesPath] = process.argv.slice(2);
const MARKER = /\[\[mock:([A-Za-z0-9_-]{1,64})\]\]/g;
const OPEN = '[[mock:';
const out = [];
const bad = (file, rule) => out.push(`${file}: ${rule}`);
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const readText = (file) => fs.readFileSync(path.join(root, file), 'utf8');

try {
  const files = fs.readFileSync(filesPath, 'utf8').split('\n').filter((f) => f.startsWith('eval/') && !path.posix.basename(f).startsWith('.'));
  if (!files.some((f) => /^eval\/mock-wrong\/[^/]+\/case\.json$/.test(f))) bad('eval/mock-wrong', 'holds no test-only case');
  for (const file of files.sort()) {
    const inWrong = file.startsWith('eval/mock-wrong/');
    if (!inWrong && readText(file).includes(OPEN)) bad(file, 'a mock marker outside eval/mock-wrong/');
  }
  for (const file of files.filter((f) => /^eval\/mock-wrong\/[^/]+\/case\.json$/.test(f)).sort()) {
    const raw = readText(file);
    let c;
    try {
      c = JSON.parse(raw);
    } catch {
      bad(file, 'is not valid JSON');
      continue;
    }
    if (!isObject(c)) {
      bad(file, 'is not a JSON object');
      continue;
    }
    if (c.kind !== 'item' && c.kind !== 'injection') bad(file, 'a test-only case must be of kind item or injection');
    const names = [...raw.matchAll(MARKER)].map((m) => m[1]);
    if (names.length === 0) bad(file, 'names no marker scenario');
    const expected = isObject(c.expectation) ? c.expectation.outcome : undefined;
    for (const name of names) {
      const scenarioFile = `ci/mock/scenarios/A/${name}.json`;
      let outcome;
      try {
        const scenario = JSON.parse(readText(scenarioFile));
        outcome = JSON.parse(scenario.replies[0].text).outcome;
      } catch {
        bad(file, 'names a marker scenario that is missing or whose first reply is not a JSON text');
        continue;
      }
      if (typeof outcome !== 'string' || outcome === expected) bad(file, 'its marker scenario does not answer an outcome other than the expected one');
    }
  }
} catch {
  bad('check-markers', 'could not read the tree');
}
process.stdout.write(out.length ? `${out.join('\n')}\n` : '');
EOF

cat > "$tmp/mksamples.mjs" <<'EOF'
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2];
const D = 'doc' + 'ker';
const DC = 'd' + 'c';
const clone = (v) => JSON.parse(JSON.stringify(v));
const base = (name, kind, expectation) => ({
  name,
  kind,
  heldOut: false,
  description: 'A synthetic case for the repository check.',
  expectation,
  recordedBy: 'written by the check',
});
const item = (name, kind = 'item') => ({
  ...base(name, kind, { outcome: 'digest' }),
  item: { itemId: name, channel: 'mailbox', provenance: 'untrusted', sender: 'a sender', subject: 'a subject', text: 'a text' },
});
const incident = (name) => ({
  ...base(name, 'incident', { causeCategory: 'data_format_change', elementAtFault: 'OrderDate', fixKind: 'repair_resend' }),
  snapshot: 'snapshot.json',
});
const clear = (name) => ({
  ...base(name, 'all-clear', { catalogKey: 'check.allPassed' }),
  checks: [{ result: 'passed', entry: 'Orders', finding: '', checkedAt: '2026-10-28T10:00:00Z' }],
});
const wrong = (name) => {
  const c = item(name);
  c.expectation = { outcome: 'tellnow' };
  c.item.text = '[[mock:eval-zz]] an urgent notice';
  return c;
};
const scenario = (outcome) => ({
  name: 'eval-zz',
  match: { marker: 'eval-zz' },
  replies: [{ status: 200, text: JSON.stringify({ outcome, reasons: ['a reason'], confidence: 0.9 }) }],
});
const job = (extra = '', step = '        run: bash eval/run.sh') =>
  `name: lane-a\non:\n  push:\n    branches:\n      - main\njobs:\n  other:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n  evaluation:\n    runs-on: [self-hosted, ocutalon]\n${extra}    steps:\n      - name: Run the set\n${step}\n`;
const script = `#!/usr/bin/env bash\n# This comment names ${D} and ${DC} config, and is not code.\nset -u\n. ci/iris.sh\n${DC} exec -T iris cat /tmp/x\n`;

const good = () => ({
  'eval/item-good/case.json': item('item-good'),
  'eval/injection-good/case.json': item('injection-good', 'injection'),
  'eval/incident-good/case.json': incident('incident-good'),
  'eval/incident-good/snapshot.json': { format: 'ocutalon.readerSnapshot/1' },
  'eval/clear-good/case.json': clear('clear-good'),
  'eval/mock-wrong/wrong-good/case.json': wrong('wrong-good'),
  'ci/mock/scenarios/A/eval-zz.json': scenario('ignore'),
  '.github/workflows/lane-a.yml': job(),
  'eval/run.sh': script,
});

function write(root, files) {
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, typeof content === 'string' ? content : `${JSON.stringify(content, null, 2)}\n`);
  }
}
function variant(rule, name, edit) {
  const files = clone(good());
  edit(files);
  write(path.join(out, rule, name), files);
}
const ITEM = 'eval/item-good/case.json';
const INCIDENT = 'eval/incident-good/case.json';
const CLEAR = 'eval/clear-good/case.json';
const WRONG = 'eval/mock-wrong/wrong-good/case.json';
const SCENARIO = 'ci/mock/scenarios/A/eval-zz.json';
const LANE = '.github/workflows/lane-a.yml';

for (const rule of ['cases', 'markers', 'job', 'eval-scripts']) variant(rule, 'good', () => {});

variant('cases', 'bad-no-expectation', (f) => { delete f[ITEM].expectation; });
variant('cases', 'bad-empty-expectation', (f) => { f[ITEM].expectation = {}; });
variant('cases', 'bad-outcome', (f) => { f[ITEM].expectation.outcome = 'maybe'; });
variant('cases', 'bad-kind', (f) => { f[ITEM].kind = 'chat'; });
variant('cases', 'bad-category', (f) => { f[INCIDENT].expectation.causeCategory = 'weather'; });
variant('cases', 'bad-heldout', (f) => { f[ITEM].heldOut = 'false'; });
variant('cases', 'bad-no-itemid', (f) => { delete f[ITEM].item.itemId; });
variant('cases', 'bad-snapshot-missing', (f) => { delete f['eval/incident-good/snapshot.json']; });
variant('cases', 'bad-snapshot-format', (f) => { f['eval/incident-good/snapshot.json'] = { format: 'other/1' }; });
variant('cases', 'bad-name', (f) => { f[ITEM].name = 'someone-else'; });
variant('cases', 'bad-no-casejson', (f) => { f['eval/orphan/snapshot.json'] = {}; });
variant('cases', 'bad-fixkind', (f) => { f[INCIDENT].expectation.fixKind = 'nothing'; });
variant('cases', 'bad-fixkind-no-fix-category', (f) => { f[INCIDENT].expectation.causeCategory = 'unknown'; });
variant('cases', 'bad-not-json', (f) => { f[ITEM] = 'this is not json\n'; });
variant('cases', 'bad-array', (f) => { f[ITEM] = []; });
variant('cases', 'bad-no-description', (f) => { f[ITEM].description = ''; });
variant('cases', 'bad-provenance', (f) => { f[ITEM].item.provenance = 'user'; });
variant('cases', 'bad-clear-no-key', (f) => { delete f[CLEAR].expectation.catalogKey; });
variant('cases', 'bad-clear-result', (f) => { f[CLEAR].checks[0].result = 'maybe'; });
variant('cases', 'bad-mock-wrong-case', (f) => { delete f[WRONG].expectation; });
variant('cases', 'bad-empty-tree', (f) => { for (const k of Object.keys(f)) if (k.startsWith('eval/')) delete f[k]; });

variant('markers', 'bad-outside', (f) => { f[ITEM].item.text = '[[mock:eval-zz]] a text'; });
variant('markers', 'bad-outside-file', (f) => { f['eval/incident-good/notes.txt'] = 'a note [[mock:eval-zz]]\n'; });
variant('markers', 'bad-no-marker', (f) => { f[WRONG].item.text = 'an urgent notice'; });
variant('markers', 'bad-scenario-missing', (f) => { delete f[SCENARIO]; });
variant('markers', 'bad-scenario-same-outcome', (f) => { f[SCENARIO] = scenario('tellnow'); });
variant('markers', 'bad-scenario-not-json', (f) => { f[SCENARIO].replies[0].text = 'not json'; });
variant('markers', 'bad-kind', (f) => { f[WRONG].kind = 'all-clear'; });
variant('markers', 'bad-no-test-only-case', (f) => { delete f[WRONG]; });

variant('job', 'bad-no-step', (f) => { f[LANE] = job('', '        run: echo nothing'); });
variant('job', 'bad-other-job', (f) => { f[LANE] = job('', '        run: echo nothing').replace('      - run: echo hi', '      - run: bash eval/run.sh'); });
variant('job', 'bad-names-switch', (f) => { f[LANE] = job('    env:\n      OCUTALON_EVAL: "1"\n'); });
variant('job', 'bad-switch-in-other-workflow', (f) => { f['.github/workflows/ci.yml'] = 'name: ci\non:\n  push:\nenv:\n  OCUTALON_EVAL: "1"\n'; });
variant('job', 'bad-no-job', (f) => { f[LANE] = job().replace('  evaluation:', '  something:'); });

variant('eval-scripts', 'bad-inspect', (f) => { f['eval/run.sh'] = `${script}${D} inspect abc\n`; });
variant('eval-scripts', 'bad-config', (f) => { f['eval/run.sh'] = `${script}${DC} config\n`; });
variant('eval-scripts', 'bad-convert', (f) => { f['eval/run.sh'] = `${script}${DC} convert\n`; });
variant('eval-scripts', 'bad-push', (f) => { f['eval/run.sh'] = `${script}${DC} -p x push\n`; });
variant('eval-scripts', 'bad-other-script', (f) => { f['eval/other.sh'] = `#!/usr/bin/env bash\n${D} ps\n`; });
variant('eval-scripts', 'bad-no-run', (f) => { delete f['eval/run.sh']; f['eval/other.sh'] = script; });
EOF

# --- the rules ---

# tree_files <root>: the files below eval/, ci/mock/scenarios/ and .github/workflows/, relative to the root, one per line. The real
# tree lists what git tracks or has not ignored; a synthetic tree lists every file.
tree_files() {
  if [ "$1" = "$root" ]; then
    scan_files eval ci/mock/scenarios .github/workflows
  else
    (cd "$1" && find eval ci .github -type f 2> /dev/null | LC_ALL=C sort)
  fi
}

run_node() { # run_node <program> <root>: the violations of the Node program on the tree
  tree_files "$2" > "$tmp/files.txt"
  ENUM_OUTCOME="$outcomes" ENUM_CASEKINDS="$case_kinds" ENUM_CAUSECATEGORIES="$categories" ENUM_FIXKINDS="$fix_kinds" ENUM_FIXCATEGORY="$fix_category" \
    node "$tmp/$1.mjs" "$2" "$tmp/files.txt" 2>&1 || echo "$1: the program failed"
}

check_cases() { run_node check-cases "$1"; }
check_markers() { run_node check-markers "$1"; }

# check_job <root>: the violations of the evaluation job in lane-a.yml of the tree.
check_job() {
  local file="$1/.github/workflows/lane-a.yml"
  if [ ! -f "$file" ]; then
    echo ".github/workflows/lane-a.yml: the file is missing"
    return 0
  fi
  awk '
    /^[A-Za-z]/ { injobs = ($0 ~ /^jobs:/); job = "" }
    injobs && /^  [A-Za-z0-9_-]+:[ ]*$/ { job = $1; sub(/:$/, "", job); if (job == "evaluation") found = 1; next }
    injobs && job == "evaluation" && /^[ ]+(- )?run:[ ]+bash eval\/run\.sh[ ]*$/ { step = 1 }
    /OCUTALON_EVAL([^A-Za-z0-9_]|$)/ { named = 1 }
    END {
      if (!found) print ".github/workflows/lane-a.yml: there is no job evaluation"
      else if (!step) print ".github/workflows/lane-a.yml: the job evaluation has no step that runs bash eval/run.sh"
      if (named) print ".github/workflows/lane-a.yml: the file names the switch OCUTALON_EVAL"
    }
  ' "$file"
  local other
  for other in "$1"/.github/workflows/*.yml "$1"/.github/workflows/*.yaml; do
    [ -f "$other" ] || continue
    [ "$other" = "$file" ] && continue
    if grep -Eq 'OCUTALON_EVAL([^A-Za-z0-9_]|$)' "$other"; then
      echo ".github/workflows/$(basename "$other"): the file names the switch OCUTALON_EVAL"
    fi
  done
}

# check_eval_scripts <root>: the violations of the .sh files below eval/ of the tree.
check_eval_scripts() {
  local base=$1 f
  if [ ! -f "$base/eval/run.sh" ]; then echo "eval/run.sh: the script is missing"; fi
  tree_files "$base" | grep '^eval/.*\.sh$' | while IFS= read -r f; do
    awk -v f="$f" '
      /^[[:space:]]*#/ { next }
      tolower($0) ~ /docker/ { print f ":" FNR ": a code line names the container tool" }
      $0 ~ /(^|[ ;|&(])dc[ ]+([^ ]+[ ]+)*(config|convert|push)([ ]|$)/ { print f ":" FNR ": a call through the wrapper uses config, convert or push" }
    ' "$base/$f"
  done
}

# rule <label> <description> <checker>: every sample bad-* of the label must be flagged, the sample good must not be, and then the real
# tree must have no violation.
rule() {
  local label=$1 description=$2 checker=$3 s n=0 ok=1 hits
  for s in "$tmp/samples/$label"/bad-*; do
    [ -d "$s" ] || continue
    n=$((n + 1))
    if [ -z "$("$checker" "$s")" ]; then
      echo "FAIL $label: the rule does not flag the sample $(basename "$s")"
      ok=0
    fi
  done
  if [ "$n" -eq 0 ]; then
    echo "FAIL $label: there is no bad sample"
    ok=0
  fi
  if [ -n "$("$checker" "$tmp/samples/$label/good")" ]; then
    echo "FAIL $label: the rule flags the good sample: $("$checker" "$tmp/samples/$label/good" | head -n 3 | tr '\n' ' ')"
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    hits=$("$checker" "$root")
    if [ -n "$hits" ]; then
      printf '%s\n' "$hits" | head -n 20 | sed 's/^/  /'
      ok=0
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS $label: $description"
  else
    echo "FAIL $label: $description"
    fails=$((fails + 1))
  fi
}

# --- enumerations ---

outcomes=$(enum_value "$ENUM_FILE" OUTCOME)
categories=$(enum_value "$DIAGNOSIS_FILE" CAUSECATEGORIES)
fix_kinds=$(enum_value "$DIAGNOSIS_FILE" FIXKINDS)
fix_category=$(enum_value "$DIAGNOSIS_FILE" FIXCATEGORY)
case_kinds=$(enum_value "$REPORT_FILE" CASEKINDS)

printf 'Class Zz.Bad\n{\nParameter OTHER = "x";\n}\n' > "$tmp/enum.bad"
printf 'Class Zz.Good\n{\nParameter OUTCOME = "a,b";\n}\n' > "$tmp/enum.good"
missing=""
[ -z "$(enum_value "$tmp/enum.bad" OUTCOME)" ] || missing="$missing the reader finds a value in a class without it;"
[ "$(enum_value "$tmp/enum.good" OUTCOME)" = "a,b" ] || missing="$missing the reader does not find a value in a class with it;"
[ -n "$outcomes" ] || missing="$missing OUTCOME is missing from $ENUM_FILE;"
[ -n "$categories" ] || missing="$missing CAUSECATEGORIES is missing from $DIAGNOSIS_FILE;"
[ -n "$fix_kinds" ] || missing="$missing FIXKINDS is missing from $DIAGNOSIS_FILE;"
[ -n "$fix_category" ] || missing="$missing FIXCATEGORY is missing from $DIAGNOSIS_FILE;"
[ -n "$case_kinds" ] || missing="$missing CASEKINDS is missing from $REPORT_FILE;"
if [ -z "$missing" ]; then
  echo "PASS enumerations: the outcomes, cause categories, fix kinds, fix category and case kinds are read from their classes"
else
  echo "FAIL enumerations:$missing"
  fails=$((fails + 1))
  echo "test-eval-set: $fails rule(s) failed"
  exit 1
fi

if ! node "$tmp/mksamples.mjs" "$tmp/samples" > "$tmp/mksamples.log" 2>&1; then
  cat "$tmp/mksamples.log"
  echo "FAIL the synthetic trees could not be written"
  exit 1
fi

rule cases "every case.json below eval/ has its kind, held-out flag, record and expectation, and every folder holds a case.json" check_cases
rule markers "a mock marker is only in eval/mock-wrong/, and its scenario answers an outcome other than the expected one" check_markers
rule job "lane-a.yml runs bash eval/run.sh in the job evaluation, and no workflow file names OCUTALON_EVAL" check_job
rule eval-scripts "eval/run.sh exists, and the scripts of eval/ name no container tool and make no config, convert or push call through the wrapper" check_eval_scripts

if [ "$fails" -ne 0 ]; then
  echo "test-eval-set: $fails rule(s) failed"
  exit 1
fi
echo "test-eval-set: all rules passed"
