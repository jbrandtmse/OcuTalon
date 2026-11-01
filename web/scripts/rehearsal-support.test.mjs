// Tests the rehearsal's seams in the e2e support code (e2e/support/rehearsal.ts, Story 11.11; release/rehearse.sh): the page marks and the
// choice of the IRIS channel are inert unless the rehearsal asks for them (AC8), and write the grammar that rehearse.sh reads when it does.
// The source pins read iris.ts and demo-path.ts and hold that the channel choice sits in runOnce and that the five marks sit next to their
// clicks. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const e2e = join(here, '..', 'e2e', 'support');
const { irisSessionCommand, mark, markWhen, marksOn } = await import(pathToFileURL(join(e2e, 'rehearsal.ts')).href);

const read = (name) => readFileSync(join(e2e, name), 'utf8');

let dir;
let file;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'ocutalon-marks-'));
  file = join(dir, 'marks.page');
});
afterEach(() => {
  delete process.env.OCUTALON_E2E_MARKS;
  rmSync(dir, { recursive: true, force: true });
});

describe('marks are off', () => {
  it('writes nothing and calls no probe', async () => {
    delete process.env.OCUTALON_E2E_MARKS;
    assert.equal(marksOn(), false);
    mark('step1_sent');
    let probed = 0;
    const started = Date.now();
    await markWhen('step1_reply_seen', async () => {
      probed += 1;
      return false;
    }, 5_000);
    assert.equal(probed, 0, 'the probe is never called');
    assert.ok(Date.now() - started < 1_000, 'and nothing is waited for');
    assert.equal(existsSync(file), false);
  });

  it('treats an empty variable as off', () => {
    process.env.OCUTALON_E2E_MARKS = '';
    assert.equal(marksOn(), false);
    mark('step1_sent');
    assert.equal(existsSync(file), false);
  });
});

describe('marks are on', () => {
  it('mark appends "<name> <epoch ms>" lines', () => {
    process.env.OCUTALON_E2E_MARKS = file;
    assert.equal(marksOn(), true);
    const before = Date.now();
    mark('step1_sent');
    mark('approve_pressed');
    const after = Date.now();
    const lines = readFileSync(file, 'utf8').split('\n');
    assert.equal(lines.pop(), '', 'every line ends with a newline');
    assert.equal(lines.length, 2);
    const [name, value] = lines[0].split(' ');
    assert.equal(name, 'step1_sent');
    assert.match(value, /^\d{13}$/);
    assert.ok(Number(value) >= before && Number(value) <= after);
    assert.match(lines[1], /^approve_pressed \d{13}$/);
  });

  it('markWhen polls about every 100 ms and marks once the probe turns true', async () => {
    process.env.OCUTALON_E2E_MARKS = file;
    const times = [];
    const started = Date.now();
    await markWhen('step1_decision_seen', async () => {
      times.push(Date.now());
      return times.length >= 4;
    }, 5_000);
    assert.equal(times.length, 4);
    const gaps = times.slice(1).map((time, i) => time - times[i]);
    for (const gap of gaps) assert.ok(gap >= 90 && gap < 2000, `a gap of ${gap} ms is about 100 ms`);
    const lines = readFileSync(file, 'utf8').trim().split('\n');
    assert.equal(lines.length, 1, 'one mark');
    assert.match(lines[0], /^step1_decision_seen \d{13}$/);
    assert.ok(Number(lines[0].split(' ')[1]) >= started + 250);
  });

  it('markWhen marks at once when the probe is true at the first look', async () => {
    process.env.OCUTALON_E2E_MARKS = file;
    await markWhen('approval_result_seen', async () => true, 5_000);
    assert.match(readFileSync(file, 'utf8'), /^approval_result_seen \d{13}\n$/);
  });

  it('markWhen writes no line on a timeout, and a probe that throws counts as not yet', async () => {
    process.env.OCUTALON_E2E_MARKS = file;
    let calls = 0;
    await markWhen('step1_reply_seen', async () => {
      calls += 1;
      throw new Error('the page is not ready');
    }, 350);
    assert.ok(calls >= 2, 'it tried more than once');
    assert.equal(existsSync(file), false, 'no line is written');
  });
});

describe('irisSessionCommand', () => {
  it('runs the exec channel through sh -c when OCUTALON_E2E_IRIS_EXEC is set, and never looks the container up', () => {
    let looked = 0;
    const got = irisSessionCommand({ OCUTALON_E2E_IRIS_EXEC: "bash 'release/rehearse.sh' exec" }, () => {
      looked += 1;
      return 'c1';
    });
    assert.deepEqual(got, { cmd: 'sh', args: ['-c', "bash 'release/rehearse.sh' exec"] });
    assert.equal(looked, 0, 'the container is not looked up');
  });

  it('is today\'s docker exec when it is unset or empty', () => {
    for (const env of [{}, { OCUTALON_E2E_IRIS_EXEC: '' }]) {
      let looked = 0;
      const got = irisSessionCommand(env, () => {
        looked += 1;
        return 'c1';
      });
      assert.deepEqual(got, { cmd: 'docker', args: ['exec', '-i', 'c1', 'iris', 'session', 'IRIS', '-U', 'OCUTALON'] });
      assert.equal(looked, 1);
    }
  });
});

describe('by source', () => {
  it('runOnce in iris.ts spawns what irisSessionCommand gives', () => {
    const iris = read('iris.ts');
    const body = iris.slice(iris.indexOf('function runOnce'), iris.indexOf('export async function irisScript'));
    assert.match(body, /irisSessionCommand\(process\.env, irisContainer\)/);
    assert.match(body, /spawn\(cmd, args,/);
    assert.doesNotMatch(body, /spawn\('docker'/, 'the docker argv lives in rehearsal.ts only');
  });

  const demo = read('demo-path.ts');
  const lines = demo.split('\n');
  const at = (needle, from = 0) => {
    const found = lines.findIndex((line, i) => i >= from && line.includes(needle));
    assert.ok(found >= 0, `demo-path.ts holds ${needle}`);
    return found;
  };

  it('step1_sent sits just before the guide Send click, and the two step 1 marks just after it', () => {
    const start = at('export async function watchThroughGuide');
    const sent = at("mark('step1_sent')", start);
    const click = at('await guideSend(page).click();', sent);
    const decision = at("markWhen('step1_decision_seen'", click);
    const reply = at("markWhen('step1_reply_seen'", decision);
    assert.equal(click - sent, 1, 'the mark is the line before the click');
    assert.equal(decision - click, 1, 'the decision mark is the line after the click');
    assert.equal(reply - decision, 1);
    assert.ok(reply < at('await expectGuideMessage(page, WATCH_PROMPT)', click), 'before any other wait');
    assert.ok(reply < at('doneTurn(page, before)', click), 'and before the IRIS-reading doneTurn');
  });

  it('approve_pressed sits just before the phone Approve click, and approval_result_seen just after it and before the IRIS read', () => {
    const start = at('async function pressOnPhone');
    const pressed = at("mark('approve_pressed')", start);
    const click = at("await notice.getByRole('button'", pressed);
    const seen = at("markWhen('approval_result_seen'", click);
    const read = at('readApproval(key)', click);
    assert.equal(click - pressed, 1, 'the mark is the line before the click');
    assert.ok(seen > click && seen < read, 'the result mark is after the click and before the first IRIS read');
    assert.ok(seen - click <= 5, 'right after the click');
  });

  it('has exactly the five mark names', () => {
    const names = [...demo.matchAll(/\bmark(?:When)?\('([a-z0-9_]+)'/g)].map((match) => match[1]);
    assert.deepEqual([...names].sort(), ['approval_result_seen', 'approve_pressed', 'step1_decision_seen', 'step1_reply_seen', 'step1_sent']);
  });
});
