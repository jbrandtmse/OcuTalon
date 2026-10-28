#!/usr/bin/env bash
# The repository check of the evaluation set (Stories 9.2 and 9.3; AD-22, AD-29; CON-5). It is a unit of the hosted `checks` job (CHECK_SCRIPTS of
# ci/units.sh), starts nothing, and needs bash and Node. It reads the files below eval/, the mock's scenarios below ci/mock/scenarios/A/,
# the workflow files below .github/workflows/ (lane-a.yml's evaluation job, and every one for the switch), eval/run.sh and the
# enumerations of the classes. A failure prints `file: rule` and never the text of the file.
# Each rule first runs on synthetic trees: one for each way to break the rule, which must be flagged, and a good one, which must not be
# (the convention of lib-scan.sh); only then does it read the real tree. It prints one PASS or FAIL line for each rule and exits 0 only
# when none fails.
#   enumerations  the outcomes (Msg.Enum OUTCOME), the cause categories, fix kinds and fix category (Watch.Msg.DiagnosisPayload
#                 CAUSECATEGORIES, FIXKINDS and FIXCATEGORY), the case kinds and the finding keys (Eval.Report CASEKINDS and FINDINGKEYS)
#                 are read from their classes, and each is found;
#   cases         eval/ holds a case.json, and every one is a JSON object that has a name equal to its folder's, a kind of the case kinds, a boolean
#                 heldOut, a description, a recordedBy and an expectation with the fields of its kind, and its kind's record; and every
#                 folder below eval/ that holds a file holds a case.json:
#                   item                expectation.outcome of the outcomes; an item record with an itemId that is the case's name
#                                       (a test-only case below eval/mock-wrong/ is exempt) and a provenance that is
#                                       absent or untrusted, and either the channel mailbox with no catalogKey, or the channel system
#                                       (a finding) with a catalogKey of the finding keys, a slots object, an empty sender and subject
#                                       and a text;
#                   injection           expectation.keyPhrases, a non-empty array whose elements are each a non-empty string or a
#                                       non-empty array of them (alternatives), and no expectation.outcome (an injection is not scored
#                                       by outcome); the item record of an item (itemId and provenance), without the channel rules;
#                   incident            expectation.causeCategory of the categories, an elementAtFault, and a fixKind of the fix kinds
#                                       when the category is the fix category and empty otherwise; a snapshot, the name of a file in the
#                                       folder whose format is ocutalon.readerSnapshot/1;
#                   all-clear           expectation.catalogKey; checks, an array of objects whose result is passed, failed or not_checked;
#   markers       eval/mock-wrong/ holds a case; a [[mock:<name>]] marker appears only in the cases below it; each such case is of kind item
#                 and names a scenario ci/mock/scenarios/A/<name>.json whose first reply is a JSON text with an outcome other than the
#                 case's expected outcome;
#   set           the cases directly below eval/ (not eval/mock-wrong/) hold at least 20 item cases, at least 3 that expect each outcome,
#                 at least one item from the mailbox and one from the system channel, and at least one injection case;
#   job           .github/workflows/lane-a.yml has a job evaluation with a timeout, a run tag of its own (run id, attempt and -eval, so
#                 its teardown never removes another job's stack), a step that runs `bash ci/iris.sh build` before the step that runs
#                 `bash eval/run.sh`, and no workflow file names the switch OCUTALON_EVAL, which eval/run.sh exports for its own
#                 throwaway (owner condition U-131). The other workflow rules (fork guard, pins, persist-credentials, secrets,
#                 teardown) are test-ci-config.sh's, for every job;
#   eval-scripts  eval/run.sh exists, and no code line of a .sh file below eval/ names the container tool or calls dc with config,
#                 convert or push: those scripts reach the container through the functions of ci/iris.sh and lib-live.sh;
#   run-guard     eval/run.sh refuses an OCUTALON_EVAL_WAIT that is not a whole number from 1 to 3600 with exit 2 before it calls the
#                 container tool, accepts one that is (it goes on to the preflight), and makes OCUTALON_EVAL_REPORT_DIR. The script
#                 runs with a stub in place of the container tool that records its calls and fails, so nothing is ever started.
# Each bad sample of a rule carries the reason it must be flagged for (expect.txt in its folder): a sample that another rule flags does
# not count.
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
const FINDINGKEYS = list('ENUM_FINDINGKEYS');
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
// Key phrases: a non-empty array of non-empty strings and non-empty arrays of non-empty strings (alternatives).
const phrases = (v) => Array.isArray(v) && v.length > 0 && v.every((p) => text(p) || (Array.isArray(p) && p.length > 0 && p.every(text)));
// The record of an item case: a mailbox email with no catalog key, or a finding (system channel) with a key of the finding keys, a slots
// object, no sender or subject and a text.
const shape = (file, item) => {
  if (item.channel === 'mailbox') {
    if (item.catalogKey !== undefined) bad(file, 'a mailbox item must not have a catalogKey');
  } else if (item.channel === 'system') {
    if (!FINDINGKEYS.includes(item.catalogKey)) bad(file, 'item.catalogKey is not one of the finding keys');
    if (!isObject(item.slots)) bad(file, 'a system item has no slots object');
    if ((item.sender || '') !== '' || (item.subject || '') !== '') bad(file, 'a system item has a sender or a subject');
    if (!text(item.text)) bad(file, 'a system item has no text');
  } else {
    bad(file, 'item.channel is neither mailbox nor system');
  }
};

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
      if (c.kind === 'item') {
        if (!OUTCOMES.includes(x.outcome)) bad(file, 'expectation.outcome is not one of the outcomes');
      } else {
        if (x.outcome !== undefined) bad(file, 'an injection case is not scored by outcome');
        if (!phrases(x.keyPhrases)) bad(file, 'expectation.keyPhrases is not a non-empty array of phrases (a string, or an array of alternatives)');
      }
      if (!isObject(c.item) || !text(c.item.itemId)) bad(file, 'has no item.itemId');
      else {
        if (c.item.itemId !== c.name && !file.startsWith('eval/mock-wrong/')) bad(file, "item.itemId is not the case's name");
        if (c.item.provenance !== undefined && c.item.provenance !== 'untrusted') bad(file, 'item.provenance is not untrusted');
        if (c.kind === 'item') shape(file, c.item);
      }
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
    if (c.kind !== 'item') bad(file, 'a test-only case must be of kind item');
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

cat > "$tmp/check-set.mjs" <<'EOF'
import fs from 'node:fs';
import path from 'node:path';

const [root, filesPath] = process.argv.slice(2);
const list = (name) => (process.env[name] || '').split(',').filter(Boolean);
const OUTCOMES = list('ENUM_OUTCOME');
const MIN_ITEMS = 20;
const MIN_PER_OUTCOME = 3;
const out = [];
const bad = (rule) => out.push(`eval: ${rule}`);

try {
  const files = fs.readFileSync(filesPath, 'utf8').split('\n').filter((f) => /^eval\/[^/]+\/case\.json$/.test(f) && !f.startsWith('eval/mock-wrong/'));
  const byOutcome = new Map(OUTCOMES.map((o) => [o, 0]));
  const channels = new Set();
  let items = 0;
  let injections = 0;
  for (const file of files.sort()) {
    let c;
    try {
      c = JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
    } catch {
      continue;
    }
    if (c === null || typeof c !== 'object') continue;
    if (c.kind === 'injection') injections += 1;
    if (c.kind !== 'item') continue;
    items += 1;
    const outcome = c.expectation && c.expectation.outcome;
    if (byOutcome.has(outcome)) byOutcome.set(outcome, byOutcome.get(outcome) + 1);
    if (c.item && typeof c.item.channel === 'string') channels.add(c.item.channel);
  }
  if (items < MIN_ITEMS) bad(`the set holds fewer than ${MIN_ITEMS} item cases`);
  for (const [outcome, n] of byOutcome) {
    if (n < MIN_PER_OUTCOME) bad(`the set holds fewer than ${MIN_PER_OUTCOME} item cases that expect ${outcome}`);
  }
  if (!channels.has('mailbox')) bad('the set holds no item case from the mailbox');
  if (!channels.has('system')) bad('the set holds no item case from the system channel');
  if (injections < 1) bad('the set holds no injection case');
} catch {
  bad('could not read the tree');
}
process.stdout.write(out.length ? `${out.join('\n')}\n` : '');
EOF

cat > "$tmp/mksamples.mjs" <<'EOF'
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2];
const OUTCOMES = (process.env.ENUM_OUTCOME || '').split(',').filter(Boolean);
const FINDINGKEY = (process.env.ENUM_FINDINGKEYS || '').split(',').filter(Boolean)[0];
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
const PHRASES = [["can't approve requests", 'cannot approve requests'], ['change a production', 'change the production']];
const injection = (name) => ({
  ...base(name, 'injection', { keyPhrases: clone(PHRASES) }),
  item: { itemId: name, channel: 'mailbox', provenance: 'untrusted', sender: 'a sender', subject: 'a subject', text: 'a text' },
});
const finding = (name) => ({
  ...base(name, 'item', { outcome: 'act' }),
  item: {
    itemId: name,
    channel: 'system',
    provenance: 'untrusted',
    sender: '',
    subject: '',
    text: 'The Orders production stopped at 18:12 UTC.',
    catalogKey: FINDINGKEY,
    slots: { production: 'Orders', time: '2026-10-16T18:12:00Z' },
  },
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
  c.item.itemId = `mock-wrong-${name}`;
  c.item.text = '[[mock:eval-zz]] an urgent notice';
  return c;
};
const scenario = (outcome) => ({
  name: 'eval-zz',
  match: { marker: 'eval-zz' },
  replies: [{ status: 200, text: JSON.stringify({ outcome, reasons: ['a reason'], confidence: 0.9 }) }],
});
const GH = (what) => '$' + '{{ ' + what + ' }}';
const RUN_TAG = `      OCUTALON_RUN_TAG: ${GH('github.run_id')}-${GH('github.run_attempt')}-eval\n`;
const BUILD = '      - name: Build the web bundle\n        run: bash ci/iris.sh build\n';
const job = ({ timeout = '    timeout-minutes: 30\n', tag = RUN_TAG, env = '', build = BUILD, step = '        run: bash eval/run.sh' } = {}) =>
  `name: lane-a\non:\n  push:\n    branches:\n      - main\njobs:\n  other:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n  evaluation:\n    runs-on: [self-hosted, ocutalon]\n${timeout}${tag || env ? '    env:\n' : ''}${tag}${env}    steps:\n${build}      - name: Run the set\n${step}\n`;
const script = `#!/usr/bin/env bash\n# This comment names ${D} and ${DC} config, and is not code.\nset -u\n. ci/iris.sh\n${DC} exec -T iris cat /tmp/x\n`;
// A stand-in for eval/run.sh: the guard of OCUTALON_EVAL_WAIT (the condition is the range test), the report folder, and then the
// preflight, which calls the container tool (the check puts a stub in its place) and ends the script when it fails.
const guarded = ({ digits = true, low = 1, high = 3600, octal = '10#', folder = true } = {}) =>
  '#!/usr/bin/env bash\nset -u\nlimit=${OCUTALON_EVAL_WAIT:-180}\n' +
  (digits ? 'case $limit in\n  \'\' | *[!0-9]*) echo "FAIL wait"; exit 2 ;;\nesac\n' : '') +
  `limit=$((${octal}$limit))\n` +
  `if [ "$limit" -lt ${low} ] || [ "$limit" -gt ${high} ]; then echo "FAIL wait"; exit 2; fi\n` +
  (folder ? 'report_dir=${OCUTALON_EVAL_REPORT_DIR:-}\nif [ -n "$report_dir" ]; then mkdir -p "$report_dir" || exit 1; fi\n' : '') +
  `${D} image inspect --format x base > /dev/null 2>&1 || exit 1\n`;

const good = () => ({
  'eval/item-good/case.json': item('item-good'),
  'eval/injection-good/case.json': injection('injection-good'),
  'eval/finding-good/case.json': finding('finding-good'),
  'eval/incident-good/case.json': incident('incident-good'),
  'eval/incident-good/snapshot.json': { format: 'ocutalon.readerSnapshot/1' },
  'eval/clear-good/case.json': clear('clear-good'),
  'eval/mock-wrong/wrong-good/case.json': wrong('wrong-good'),
  'ci/mock/scenarios/A/eval-zz.json': scenario('ignore'),
  '.github/workflows/lane-a.yml': job(),
  'eval/run.sh': script,
});

// A good tree for the rule `set`: 20 item cases (the outcomes in turn, the first two findings from the system channel), an injection case
// and a test-only case, which the rule does not count.
const setGood = () => {
  const files = {};
  for (let i = 0; i < 20; i += 1) {
    const name = `item-${String(i).padStart(2, '0')}`;
    const c = i < 2 ? finding(name) : item(name);
    c.expectation = { outcome: OUTCOMES[i % OUTCOMES.length] };
    files[`eval/${name}/case.json`] = c;
  }
  files['eval/injection-good/case.json'] = injection('injection-good');
  files['eval/mock-wrong/wrong-good/case.json'] = wrong('wrong-good');
  return files;
};
const setTree = (mutate) => (f) => {
  for (const k of Object.keys(f)) delete f[k];
  Object.assign(f, setGood());
  mutate(f);
};

function write(root, files) {
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, typeof content === 'string' ? content : `${JSON.stringify(content, null, 2)}\n`);
  }
}
// A sample of the rule: the good tree with an edit. A bad sample carries the reason the rule must flag it for in expect.txt, at the root of
// the sample (the rules list eval/, ci/ and .github/ only, so the file is never part of the tree they read).
function variant(rule, name, expect, edit) {
  const files = clone(good());
  edit(files);
  const dir = path.join(out, rule, name);
  write(dir, files);
  fs.mkdirSync(dir, { recursive: true });
  if (expect) fs.writeFileSync(path.join(dir, 'expect.txt'), `${expect}\n`);
}
const ITEM = 'eval/item-good/case.json';
const INJECTION = 'eval/injection-good/case.json';
const FINDING = 'eval/finding-good/case.json';
const INCIDENT = 'eval/incident-good/case.json';
const CLEAR = 'eval/clear-good/case.json';
const WRONG = 'eval/mock-wrong/wrong-good/case.json';
const SCENARIO = 'ci/mock/scenarios/A/eval-zz.json';
const LANE = '.github/workflows/lane-a.yml';

for (const rule of ['cases', 'markers', 'job', 'eval-scripts']) variant(rule, 'good', '', () => {});
variant('set', 'good', '', setTree(() => {}));
variant('run-guard', 'good', '', (f) => { f['eval/run.sh'] = guarded(); });

variant('cases', 'bad-no-expectation', 'has no expectation', (f) => { delete f[ITEM].expectation; });
variant('cases', 'bad-empty-expectation', 'the expectation is empty', (f) => { f[ITEM].expectation = {}; });
variant('cases', 'bad-outcome', 'expectation.outcome is not one of the outcomes', (f) => { f[ITEM].expectation.outcome = 'maybe'; });
variant('cases', 'bad-injection-outcome', 'an injection case is not scored by outcome', (f) => { f[INJECTION].expectation.outcome = 'maybe'; });
variant('cases', 'bad-injection-valid-outcome', 'an injection case is not scored by outcome', (f) => { f[INJECTION].expectation.outcome = 'digest'; });
variant('cases', 'bad-injection-no-phrases', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { delete f[INJECTION].expectation.keyPhrases; });
variant('cases', 'bad-injection-empty-phrases', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = []; });
variant('cases', 'bad-injection-phrases-text', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = "can't approve requests"; });
variant('cases', 'bad-injection-phrase-type', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = ["can't approve requests", 5]; });
variant('cases', 'bad-injection-blank-phrase', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = ['  ']; });
variant('cases', 'bad-injection-empty-alternatives', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = [[]]; });
variant('cases', 'bad-injection-blank-alternative', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = [['can', '']]; });
variant('cases', 'bad-injection-nested-alternatives', 'expectation.keyPhrases is not a non-empty array of phrases', (f) => { f[INJECTION].expectation.keyPhrases = [[['can']]]; });
variant('cases', 'bad-itemid-not-name', "item.itemId is not the case's name", (f) => { f[ITEM].item.itemId = 'another-name'; });
variant('cases', 'bad-itemid-injection', "item.itemId is not the case's name", (f) => { f[INJECTION].item.itemId = 'another-name'; });
variant('cases', 'bad-provenance-and-channel', 'item.channel is neither mailbox nor system', (f) => { f[ITEM].item.provenance = 'user'; f[ITEM].item.channel = 'web'; });
variant('cases', 'bad-mailbox-key', 'a mailbox item must not have a catalogKey', (f) => { f[ITEM].item.catalogKey = FINDINGKEY; });
variant('cases', 'bad-channel', 'item.channel is neither mailbox nor system', (f) => { f[ITEM].item.channel = 'web'; });
variant('cases', 'bad-system-key', 'item.catalogKey is not one of the finding keys', (f) => { f[FINDING].item.catalogKey = 'watch.unknownProduction'; });
variant('cases', 'bad-system-no-key', 'item.catalogKey is not one of the finding keys', (f) => { delete f[FINDING].item.catalogKey; });
variant('cases', 'bad-system-no-slots', 'a system item has no slots object', (f) => { delete f[FINDING].item.slots; });
variant('cases', 'bad-system-slots-text', 'a system item has no slots object', (f) => { f[FINDING].item.slots = 'production=Orders'; });
variant('cases', 'bad-system-sender', 'a system item has a sender or a subject', (f) => { f[FINDING].item.sender = 'a sender'; });
variant('cases', 'bad-system-subject', 'a system item has a sender or a subject', (f) => { f[FINDING].item.subject = 'a subject'; });
variant('cases', 'bad-system-no-text', 'a system item has no text', (f) => { f[FINDING].item.text = ''; });
variant('cases', 'bad-kind', 'kind is not one of the case kinds', (f) => { f[ITEM].kind = 'chat'; });
variant('cases', 'bad-category', 'expectation.causeCategory is not one of the cause categories', (f) => { f[INCIDENT].expectation.causeCategory = 'weather'; });
variant('cases', 'bad-no-element', 'has no expectation.elementAtFault', (f) => { delete f[INCIDENT].expectation.elementAtFault; });
variant('cases', 'bad-heldout', 'heldOut is not a boolean', (f) => { f[ITEM].heldOut = 'false'; });
variant('cases', 'bad-heldout-missing', 'heldOut is not a boolean', (f) => { delete f[ITEM].heldOut; });
variant('cases', 'bad-no-itemid', 'has no item.itemId', (f) => { delete f[ITEM].item.itemId; });
variant('cases', 'bad-no-item', 'has no item.itemId', (f) => { delete f[ITEM].item; });
variant('cases', 'bad-snapshot-missing', 'its snapshot is not a file of the folder', (f) => { delete f['eval/incident-good/snapshot.json']; });
variant('cases', 'bad-snapshot-path', 'its snapshot is not a file of the folder', (f) => { f[INCIDENT].snapshot = '../incident-good/snapshot.json'; });
variant('cases', 'bad-snapshot-format', 'its snapshot is not a reader snapshot', (f) => { f['eval/incident-good/snapshot.json'] = { format: 'other/1' }; });
variant('cases', 'bad-name', "name is not its folder's name", (f) => { f[ITEM].name = 'someone-else'; });
variant('cases', 'bad-no-casejson', 'holds a file but no case.json', (f) => { f['eval/orphan/snapshot.json'] = {}; });
variant('cases', 'bad-fixkind', 'expectation.fixKind is not one of the fix kinds', (f) => { f[INCIDENT].expectation.fixKind = 'nothing'; });
variant('cases', 'bad-fixkind-no-fix-category', 'expectation.fixKind must be empty for a category with no fix', (f) => { f[INCIDENT].expectation.causeCategory = 'unknown'; });
variant('cases', 'bad-not-json', 'is not valid JSON', (f) => { f[ITEM] = 'this is not json\n'; });
variant('cases', 'bad-array', 'is not a JSON object', (f) => { f[ITEM] = []; });
variant('cases', 'bad-no-description', 'has no description', (f) => { f[ITEM].description = ''; });
variant('cases', 'bad-no-recordedby', 'has no recordedBy', (f) => { delete f[ITEM].recordedBy; });
variant('cases', 'bad-provenance', 'item.provenance is not untrusted', (f) => { f[ITEM].item.provenance = 'user'; });
variant('cases', 'bad-clear-no-key', 'has no expectation.catalogKey', (f) => { delete f[CLEAR].expectation.catalogKey; });
variant('cases', 'bad-clear-result', 'checks is not an array of objects with a result', (f) => { f[CLEAR].checks[0].result = 'maybe'; });
variant('cases', 'bad-clear-no-checks', 'checks is not an array of objects with a result', (f) => { delete f[CLEAR].checks; });
variant('cases', 'bad-mock-wrong-case', 'has no expectation', (f) => { delete f[WRONG].expectation; });
variant('cases', 'bad-empty-tree', 'holds no case.json', (f) => { for (const k of Object.keys(f)) if (k.startsWith('eval/')) delete f[k]; });

variant('markers', 'bad-outside', 'a mock marker outside eval/mock-wrong/', (f) => { f[ITEM].item.text = '[[mock:eval-zz]] a text'; });
variant('markers', 'bad-outside-file', 'a mock marker outside eval/mock-wrong/', (f) => { f['eval/incident-good/notes.txt'] = 'a note [[mock:eval-zz]]\n'; });
variant('markers', 'bad-no-marker', 'names no marker scenario', (f) => { f[WRONG].item.text = 'an urgent notice'; });
variant('markers', 'bad-scenario-missing', 'names a marker scenario that is missing or whose first reply is not a JSON text', (f) => { delete f[SCENARIO]; });
variant('markers', 'bad-scenario-same-outcome', 'does not answer an outcome other than the expected one', (f) => { f[SCENARIO] = scenario('tellnow'); });
variant('markers', 'bad-scenario-not-json', 'names a marker scenario that is missing or whose first reply is not a JSON text', (f) => { f[SCENARIO].replies[0].text = 'not json'; });
variant('markers', 'bad-kind', 'a test-only case must be of kind item', (f) => { f[WRONG].kind = 'all-clear'; });
variant('markers', 'bad-kind-injection', 'a test-only case must be of kind item', (f) => { f[WRONG].kind = 'injection'; });
variant('markers', 'bad-no-test-only-case', 'holds no test-only case', (f) => { delete f[WRONG]; });

const LAST = OUTCOMES[OUTCOMES.length - 1];
const ITEM19 = 'eval/item-19/case.json';
variant('set', 'bad-few-items', 'the set holds fewer than 20 item cases', setTree((f) => { delete f[ITEM19]; }));
variant('set', 'bad-few-for-outcome', `the set holds fewer than 3 item cases that expect ${LAST}`, setTree((f) => {
  for (const n of ['03', '07', '11']) f[`eval/item-${n}/case.json`].expectation.outcome = OUTCOMES[0];
}));
variant('set', 'bad-no-mailbox', 'the set holds no item case from the mailbox', setTree((f) => {
  for (const k of Object.keys(f)) if (k.startsWith('eval/item-')) f[k].item.channel = 'system';
}));
variant('set', 'bad-no-system', 'the set holds no item case from the system channel', setTree((f) => {
  for (const k of Object.keys(f)) if (k.startsWith('eval/item-')) f[k].item.channel = 'mailbox';
}));
variant('set', 'bad-no-injection', 'the set holds no injection case', setTree((f) => { delete f[INJECTION]; }));
variant('set', 'bad-injection-is-no-item', 'the set holds fewer than 20 item cases', setTree((f) => { f[ITEM19].kind = 'injection'; }));
variant('set', 'bad-incident-is-no-item', 'the set holds fewer than 20 item cases', setTree((f) => { f[ITEM19].kind = 'incident'; }));
variant('set', 'bad-test-only-is-no-item', 'the set holds fewer than 20 item cases', setTree((f) => {
  f['eval/mock-wrong/extra/case.json'] = f[ITEM19];
  delete f[ITEM19];
}));
variant('set', 'bad-empty-tree', 'the set holds fewer than 20 item cases', setTree((f) => {
  for (const k of Object.keys(f)) delete f[k];
}));

variant('job', 'bad-no-step', 'the job evaluation has no step that runs bash eval/run.sh', (f) => { f[LANE] = job({ step: '        run: echo nothing' }); });
variant('job', 'bad-other-job', 'the job evaluation has no step that runs bash eval/run.sh', (f) => { f[LANE] = job({ step: '        run: echo nothing' }).replace('      - run: echo hi', '      - run: bash eval/run.sh'); });
variant('job', 'bad-names-switch', 'lane-a.yml: the file names the switch OCUTALON_EVAL', (f) => { f[LANE] = job({ env: '      OCUTALON_EVAL: "1"\n' }); });
variant('job', 'bad-switch-in-other-workflow', 'ci.yml: the file names the switch OCUTALON_EVAL', (f) => { f['.github/workflows/ci.yml'] = 'name: ci\non:\n  push:\nenv:\n  OCUTALON_EVAL: "1"\n'; });
variant('job', 'bad-no-job', 'there is no job evaluation', (f) => { f[LANE] = job().replace('  evaluation:', '  something:'); });
variant('job', 'bad-no-timeout', 'the job evaluation has no timeout-minutes', (f) => { f[LANE] = job({ timeout: '' }); });
variant('job', 'bad-no-tag', "the job evaluation's OCUTALON_RUN_TAG is not run id, attempt and -eval", (f) => { f[LANE] = job({ tag: '' }); });
variant('job', 'bad-tag-of-another-job', "the job evaluation's OCUTALON_RUN_TAG is not run id, attempt and -eval", (f) => { f[LANE] = job({ tag: RUN_TAG.replace('-eval', '-bridge') }); });
variant('job', 'bad-tag-no-attempt', "the job evaluation's OCUTALON_RUN_TAG is not run id, attempt and -eval", (f) => { f[LANE] = job({ tag: `      OCUTALON_RUN_TAG: ${GH('github.run_id')}-eval\n` }); });
variant('job', 'bad-no-build', 'the job evaluation does not run bash ci/iris.sh build before bash eval/run.sh', (f) => { f[LANE] = job({ build: '' }); });
variant('job', 'bad-build-after', 'the job evaluation does not run bash ci/iris.sh build before bash eval/run.sh', (f) => { f[LANE] = job({ build: '' }).replace('        run: bash eval/run.sh\n', '        run: bash eval/run.sh\n      - name: Build\n        run: bash ci/iris.sh build\n'); });

variant('eval-scripts', 'bad-inspect', 'a code line names the container tool', (f) => { f['eval/run.sh'] = `${script}${D} inspect abc\n`; });
variant('eval-scripts', 'bad-config', 'a call through the wrapper uses config, convert or push', (f) => { f['eval/run.sh'] = `${script}${DC} config\n`; });
variant('eval-scripts', 'bad-convert', 'a call through the wrapper uses config, convert or push', (f) => { f['eval/run.sh'] = `${script}${DC} convert\n`; });
variant('eval-scripts', 'bad-push', 'a call through the wrapper uses config, convert or push', (f) => { f['eval/run.sh'] = `${script}${DC} -p x push\n`; });
variant('eval-scripts', 'bad-other-script', 'a code line names the container tool', (f) => { f['eval/other.sh'] = `#!/usr/bin/env bash\n${D} ps\n`; });
variant('eval-scripts', 'bad-no-run', 'eval/run.sh: the script is missing', (f) => { delete f['eval/run.sh']; f['eval/other.sh'] = script; });

variant('run-guard', 'bad-no-script', 'eval/run.sh: the script is missing', (f) => { delete f['eval/run.sh']; });
variant('run-guard', 'bad-no-guard', 'is not refused with exit 2', (f) => { f['eval/run.sh'] = `#!/usr/bin/env bash\nset -u\n${D} image inspect --format x base > /dev/null 2>&1 || exit 1\n`; });
variant('run-guard', 'bad-text-accepted', 'is not refused with exit 2', (f) => { f['eval/run.sh'] = guarded({ digits: false }); });
variant('run-guard', 'bad-accepts-zero', 'is not refused with exit 2', (f) => { f['eval/run.sh'] = guarded({ low: 0 }); });
variant('run-guard', 'bad-accepts-3601', 'is not refused with exit 2', (f) => { f['eval/run.sh'] = guarded({ high: 3601 }); });
variant('run-guard', 'bad-refuses-one', 'is not accepted though it is a whole number from 1 to 3600', (f) => { f['eval/run.sh'] = guarded({ low: 2 }); });
variant('run-guard', 'bad-refuses-3600', 'is not accepted though it is a whole number from 1 to 3600', (f) => { f['eval/run.sh'] = guarded({ high: 3599 }); });
variant('run-guard', 'bad-octal', 'is accepted with an error of the shell', (f) => { f['eval/run.sh'] = guarded({ octal: '' }); });
variant('run-guard', 'bad-calls-before-guard', 'reached the container tool before it was refused', (f) => { f['eval/run.sh'] = guarded().replace('set -u\n', `set -u\n${D} version > /dev/null 2>&1\n`); });
variant('run-guard', 'bad-no-report-dir', 'OCUTALON_EVAL_REPORT_DIR is not made', (f) => { f['eval/run.sh'] = guarded({ folder: false }); });
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
    ENUM_FINDINGKEYS="$finding_keys" node "$tmp/$1.mjs" "$2" "$tmp/files.txt" 2>&1 || echo "$1: the program failed"
}

check_cases() { run_node check-cases "$1"; }
check_markers() { run_node check-markers "$1"; }
check_set() { run_node check-set "$1"; }

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
    injobs && job == "evaluation" && /^[ ]+(- )?run:[ ]+bash ci\/iris\.sh build[ ]*$/ && !step { build = 1 }
    injobs && job == "evaluation" && /^    timeout-minutes:[ ]+[0-9]+[ ]*$/ { timeout = 1 }
    injobs && job == "evaluation" && /^      OCUTALON_RUN_TAG:[ ]+.*github\.run_id.*github\.run_attempt.*-eval[ ]*$/ { tag = 1 }
    /OCUTALON_EVAL([^A-Za-z0-9_]|$)/ { named = 1 }
    END {
      if (!found) print ".github/workflows/lane-a.yml: there is no job evaluation"
      else if (!step) print ".github/workflows/lane-a.yml: the job evaluation has no step that runs bash eval/run.sh"
      else {
        if (!build) print ".github/workflows/lane-a.yml: the job evaluation does not run bash ci/iris.sh build before bash eval/run.sh"
        if (!timeout) print ".github/workflows/lane-a.yml: the job evaluation has no timeout-minutes"
        if (!tag) print ".github/workflows/lane-a.yml: the job evaluation'"'"'s OCUTALON_RUN_TAG is not run id, attempt and -eval"
      }
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

# check_run_guard <root>: the violations of eval/run.sh of the tree in its use of OCUTALON_EVAL_WAIT and OCUTALON_EVAL_REPORT_DIR. The
# script runs with a stub in place of the container tool that records its call and fails: a value the script accepts goes on to the
# preflight, calls the stub and ends with exit 1; a value it refuses ends with exit 2 before any call. Nothing is ever started, and the
# lock folder (OCUTALON_LOCK_DIR) names a folder that does not exist, so the script never takes a lane's lock either.
check_run_guard() {
  local script="$1/eval/run.sh" v rc calls="$tmp/stub.calls" dir="$tmp/guard-run" n=0
  if [ ! -f "$script" ]; then
    echo "eval/run.sh: the script is missing"
    return 0
  fi
  rm -rf "$dir"
  mkdir -p "$tmp/stub" "$dir"
  local tool=doc
  tool=${tool}ker
  printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "$calls" > "$tmp/stub/$tool"
  chmod +x "$tmp/stub/$tool"
  for v in abc 0 3601 99999 1.5 -1 ' 5' '1 2'; do
    : > "$calls"
    rc=0
    (cd "$dir" && env -u RUNNER_TEMP OCUTALON_LOCK_DIR="$dir/no-locks" PATH="$tmp/stub:$PATH" TMPDIR="$dir" OCUTALON_RUN_TAG=eval-guard-check OCUTALON_EVAL_WAIT="$v" \
      bash "$script" > "$dir/out.log" 2>&1) || rc=$?
    if [ "$rc" -ne 2 ]; then
      echo "eval/run.sh: OCUTALON_EVAL_WAIT='$v' is not refused with exit 2 (exit $rc)"
    elif [ -s "$calls" ]; then
      echo "eval/run.sh: OCUTALON_EVAL_WAIT='$v' reached the container tool before it was refused"
    fi
  done
  for v in 1 7 08 180 3600; do
    n=$((n + 1))
    : > "$calls"
    rc=0
    (cd "$dir" && env -u RUNNER_TEMP OCUTALON_LOCK_DIR="$dir/no-locks" PATH="$tmp/stub:$PATH" TMPDIR="$dir" OCUTALON_RUN_TAG=eval-guard-check OCUTALON_EVAL_WAIT="$v" OCUTALON_EVAL_REPORT_DIR="$dir/reports-$n" \
      bash "$script" > "$dir/out.log" 2>&1) || rc=$?
    if [ "$rc" -eq 2 ] || [ ! -s "$calls" ]; then
      echo "eval/run.sh: OCUTALON_EVAL_WAIT='$v' is not accepted though it is a whole number from 1 to 3600 (exit $rc)"
    elif grep -Eqi 'too great for base|syntax error|integer expression|invalid arithmetic' "$dir/out.log"; then
      echo "eval/run.sh: OCUTALON_EVAL_WAIT='$v' is accepted with an error of the shell"
    fi
    [ -d "$dir/reports-$n" ] || echo "eval/run.sh: OCUTALON_EVAL_REPORT_DIR is not made"
  done
}

# rule <label> <description> <checker>: every sample bad-* of the label must be flagged, and flagged for the reason in its expect.txt, the
# sample good must not be flagged, and then the real tree must have no violation.
rule() {
  local label=$1 description=$2 checker=$3 s n=0 ok=1 hits want
  for s in "$tmp/samples/$label"/bad-*; do
    [ -d "$s" ] || continue
    n=$((n + 1))
    hits=$("$checker" "$s")
    want=$(head -n 1 "$s/expect.txt" 2> /dev/null)
    if [ -z "$want" ]; then
      echo "FAIL $label: the sample $(basename "$s") names no reason to be flagged for"
      ok=0
    elif [ -z "$hits" ]; then
      echo "FAIL $label: the rule does not flag the sample $(basename "$s")"
      ok=0
    elif ! printf '%s\n' "$hits" | grep -qF -- "$want"; then
      echo "FAIL $label: the rule flags the sample $(basename "$s") but not for its reason '$want': $(printf '%s\n' "$hits" | head -n 2 | tr '\n' ' ')"
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
finding_keys=$(enum_value "$REPORT_FILE" FINDINGKEYS)

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
[ -n "$finding_keys" ] || missing="$missing FINDINGKEYS is missing from $REPORT_FILE;"
if [ -z "$missing" ]; then
  echo "PASS enumerations: the outcomes, cause categories, fix kinds, fix category, case kinds and finding keys are read from their classes"
else
  echo "FAIL enumerations:$missing"
  fails=$((fails + 1))
  echo "test-eval-set: $fails rule(s) failed"
  exit 1
fi

if ! ENUM_OUTCOME="$outcomes" ENUM_FINDINGKEYS="$finding_keys" node "$tmp/mksamples.mjs" "$tmp/samples" > "$tmp/mksamples.log" 2>&1; then
  cat "$tmp/mksamples.log"
  echo "FAIL the synthetic trees could not be written"
  exit 1
fi

rule cases "every case.json below eval/ has its kind, held-out flag, record and expectation, and every folder holds a case.json" check_cases
rule markers "a mock marker is only in eval/mock-wrong/, and its scenario answers an outcome other than the expected one" check_markers
rule set "the set holds at least 20 item cases, at least 3 for each outcome, items from the mailbox and the system channel, and an injection case" check_set
rule job "the job evaluation of lane-a.yml has a timeout and a run tag of its own, builds the bundle and then runs bash eval/run.sh, and no workflow file names OCUTALON_EVAL" check_job
rule eval-scripts "eval/run.sh exists, and the scripts of eval/ name no container tool and make no config, convert or push call through the wrapper" check_eval_scripts
rule run-guard "eval/run.sh refuses an OCUTALON_EVAL_WAIT outside 1 to 3600 with exit 2 before any call to the container tool, accepts one inside, and makes the report folder" check_run_guard

if [ "$fails" -ne 0 ]; then
  echo "test-eval-set: $fails rule(s) failed"
  exit 1
fi
echo "test-eval-set: all rules passed"
