// Tests the rehearsal's seams in the e2e support code (e2e/support/rehearsal.ts, Story 11.11; release/rehearse.sh): the page marks and the
// choice of the IRIS channel are inert unless the rehearsal asks for them (AC8), and write the grammar that rehearse.sh reads when it does.
// The source pins read iris.ts and demo-path.ts and hold that the channel choice sits in runOnce and that the five marks sit next to their
// clicks, and (Story 11.12) that the repeat's marked send and approval helpers read their own card, that the tell-now spec marks its send,
// and that every selector and wording a page probe reads is still in web/src (DW-534). The module is imported as it is: Node strips its
// types, which holds only while it keeps to erasable syntax.
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
const webRoot = join(here, '..');
const repoRoot = join(webRoot, '..');

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
  });

  it('treats an empty variable as off', () => {
    process.env.OCUTALON_E2E_MARKS = '';
    assert.equal(marksOn(), false);
    mark('step1_sent');
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

  it('markedSend holds step1_sent just before the click and the two step 1 marks just after it', () => {
    const start = at('async function markedSend');
    const sent = at("mark('step1_sent')", start);
    const click = at('await click();', sent);
    const decision = at("markWhen('step1_decision_seen'", click);
    const reply = at("markWhen('step1_reply_seen'", decision);
    assert.equal(click - sent, 1, 'the mark is the line before the click');
    assert.equal(decision - click, 1, 'the decision mark is the line after the click');
    assert.equal(reply - decision, 1);
  });

  it('watchThroughGuide clicks the guide Send through markedSend, before any other wait and before the IRIS-reading doneTurn', () => {
    const start = at('export async function watchThroughGuide');
    const send = at('await markedSend(page, () => guideSend(page).click());', start);
    assert.ok(send < at('await expectGuideMessage(page, WATCH_PROMPT)', send), 'before any other wait');
    assert.ok(send < at('doneTurn(page, before)', send), 'and before the IRIS-reading doneTurn');
  });

  it('sendThroughComposer sends through markedSend only when asked for the step 1 marks', () => {
    const start = at('export async function sendThroughComposer');
    const marked = at('if (step1Marks) await markedSend(page, send);', start);
    assert.match(lines[marked + 1], /^\s*else await send\(\);$/);
    assert.match(lines.slice(start, marked).join('\n'), /composer\(page\)\.fill\(prompt\)/);
  });

  it('the reply probe counts replies, so that an earlier run\'s reply is not this one', () => {
    const start = at('async function markedSend');
    const counted = at('const repliesBefore =', start);
    assert.match(lines[counted], /marksOn\(\) \? await replies\.count\(\) : 0/, 'counted behind marksOn()');
    const reply = at("markWhen('step1_reply_seen'", counted);
    assert.match(lines[reply], /\(await replies\.count\(\)\) > repliesBefore/);
    assert.match(lines[reply], /replies\.last\(\)\.locator\('\.text'\)\.allTextContents\(\)/, 'and the newest reply\'s own text is not empty (an earlier reply\'s text is not this one)');
  });

  it('the approval_result_seen probe reads the card parameter, never the page\'s first incident card (a false pass on a repeat)', () => {
    const press = at('async function pressOnPhone');
    const body = lines.slice(at('const { notice, phone } = await requestNotice(page);', press), at('readApproval(key)', press)).join('\n');
    assert.match(body, /const status = card\.locator\('\[data-part="approval"\] p\.status'\);/);
    assert.doesNotMatch(body, /incidentCard\(page\)/);
    assert.match(lines.slice(press, press + 6).join('\n'), /card: Locator = incidentCard\(page\)/, 'the default is today\'s card');
    const approve = at('export async function approveOnPhone');
    assert.match(lines[approve], /card: Locator = incidentCard\(page\)/);
    assert.match(lines.slice(approve, approve + 6).join('\n'), /pressOnPhone\(page, key, 'approve', card\)/);
    assert.match(lines.slice(approve, approve + 40).join('\n'), /toHaveCount\(resultsBefore \+ 1/, 'the phone result is the count before the press plus one');
  });

  it('the tell-now spec marks tellnow_sent just before its Send, and tellnow_seen right after it', () => {
    const spec = readFileSync(join(webRoot, 'e2e-rehearsal', 'tell-now.spec.ts'), 'utf8').split('\n');
    const sent = spec.findIndex((line) => line.includes("mark('tellnow_sent')"));
    assert.ok(sent >= 0, 'the spec marks tellnow_sent');
    assert.match(spec[sent + 1], /getByRole\('button', \{ name: 'Send', exact: true \}\)\.click\(\);$/, 'the line after the mark is the Send click');
    assert.match(spec[sent + 2], /markWhen\(\s*$/);
    assert.match(spec[sent + 3], /'tellnow_seen'/);
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

  it('(QA) counts the strips before the click only when marks are on, and marks the Approve press only for approve', () => {
    const start = at('async function markedSend');
    const counted = at('const stripsBefore =', start);
    assert.match(lines[counted], /marksOn\(\) \? await strips\.count\(\) : 0/, 'the count is behind marksOn(), so CI makes no extra page query');
    const press = at('async function pressOnPhone');
    const pressed = at("mark('approve_pressed')", press);
    assert.match(lines[pressed], /^\s*if \(action === 'approve'\) mark\('approve_pressed'\);$/, 'a reject press leaves no approve mark');
    const seen = at("markWhen('approval_result_seen'", pressed);
    assert.match(lines.slice(seen - 3, seen).join('\n'), /if \(action === 'approve'\) \{/, 'and starts no result wait');
  });

  it('has exactly the five mark names in demo-path.ts, and the two tell-now names in the tell-now spec', () => {
    const tell = readFileSync(join(webRoot, 'e2e-rehearsal', 'tell-now.spec.ts'), 'utf8');
    assert.deepEqual([...tell.matchAll(/\bmark(?:When)?\(\s*'([a-z0-9_]+)'/g)].map((match) => match[1]).sort(), ['tellnow_seen', 'tellnow_sent']);
    const names = [...demo.matchAll(/\bmark(?:When)?\('([a-z0-9_]+)'/g)].map((match) => match[1]);
    assert.deepEqual([...names].sort(), ['approval_result_seen', 'approve_pressed', 'step1_decision_seen', 'step1_reply_seen', 'step1_sent']);
  });
});

// The page sources that the probes of the rehearsal read (DW-534): the probes run only in a live rehearsal, so a renamed selector or a
// reworded text in web/src would break the marks unseen. Each pin names what the probe reads and where.
describe('the page sources behind the probes', () => {
  const src = (...parts) => readFileSync(join(webRoot, 'src', 'app', ...parts), 'utf8');

  it('the decision strip draws its reasons as .reason (step1_decision_seen)', () => {
    assert.match(src('chat', 'decision-strip.ts'), /<p class="reason"/);
    assert.match(src('chat', 'decision-strip.ts'), /selector: 'app-decision-strip'/);
  });

  it('the reply is data-part="reply" and its text is class="text" (step1_reply_seen)', () => {
    const reply = src('chat', 'ocutalon-reply.ts');
    assert.match(reply, /data-part="reply"/);
    assert.match(reply, /<div class="text">/);
  });

  it('the approved status starts "Approved from the simulated phone at" once the channel name is filled in (approval_result_seen)', () => {
    const catalog = src('msg', 'catalog.ts');
    const approved = /'answered\.approved': '([^']*)'/.exec(catalog)?.[1];
    assert.ok(approved, 'the catalog holds answered.approved');
    const names = /CHANNEL_NAMES[^{]*\{([^}]*)\}/.exec(catalog)?.[1] ?? '';
    const phone = /'phone': '([^']*)'/.exec(names)?.[1];
    assert.ok(phone, 'the catalog names the phone channel');
    assert.ok(approved.replace('{channel}', phone).startsWith('Approved from the simulated phone at'), approved);
  });

  it('the chat card is app-notice-card inside app-chat-panel, the chip is app-outcome-chip, and the phone message is .notification (tellnow_seen)', () => {
    assert.match(src('chat', 'chat-panel.ts'), /selector: 'app-chat-panel'/);
    assert.match(src('chat', 'outcome-chip.ts'), /selector: 'app-outcome-chip'/);
    assert.match(src('chat', 'notice-card.ts'), /selector: 'app-notice-card'/);
    assert.match(src('phone', 'simulated-phone.ts'), /<div class="notification"/);
  });

  it('the outcome chip reads "Tell now", and the tell-now notice carries a "Why now:" line', () => {
    assert.match(src('chat', 'chat-view.ts'), /chipTellNow: 'Tell now'/);
    assert.match(src('chat', 'chat-view.ts'), /Why now:/);
    assert.match(src('chat', 'notice-card.ts'), /Why now:/);
    assert.match(readFileSync(join(repoRoot, 'src', 'ocutalon', 'cls', 'OcuTalon', 'Core', 'Rule', 'Notice.cls'), 'utf8'), /Why now:/);
  });

  it('the composer has a Send button, and the mailbox has the compose labels the tell-now spec fills', () => {
    assert.match(src('chat', 'chat-view.ts'), /send: 'Send'/);
    assert.match(src('chat', 'composer.ts'), /selector: 'app-composer'/);
    const mailbox = readFileSync(join(webRoot, 'src', 'app', 'mailbox', 'mailbox-view.ts'), 'utf8');
    for (const word of ["simulate: 'Simulate an incoming email'", "labelFrom: 'From'", "labelSubject: 'Subject'", "labelBody: 'Body'", "send: 'Send'"]) assert.ok(mailbox.includes(word), `the mailbox texts hold ${word}`);
  });

  it('a fired reminder reads "Reminder: {text}." on every channel, which the repeat\'s real-model phone check filters by (never by buttons alone)', () => {
    const core = readFileSync(join(repoRoot, 'src', 'ocutalon', 'cls', 'OcuTalon', 'Msg', 'Catalog', 'Core.cls'), 'utf8');
    assert.match(core, /"reminder\.due": \{\s*"text": "Reminder: \{text\}\."/);
    const repeat = readFileSync(join(webRoot, 'e2e-rehearsal', 'repeat.spec.ts'), 'utf8');
    const phone = /const landedPhone = [^\n]*/.exec(repeat)?.[0] ?? '';
    assert.match(phone, /\/Reminder: \\S\//, 'the real-model phone check reads the reminder text');
    assert.doesNotMatch(phone, /hasNot/, "the approval's answered notice and result message have no buttons either");
  });
});

// (QA, Story 11.12) The names the two rehearsal specs and release/rehearse.sh must agree on. Neither side runs the other offline: the
// specs run only against a live install, and rehearse.sh's self-test stubs npm. A drift would show only as a failed live run (a
// missing tell-now server line, or a FAIL line that names no step), so each name is read from the script and pinned against the specs.
describe('(QA) the rehearsal specs agree with release/rehearse.sh', () => {
  const rehearse = readFileSync(join(repoRoot, 'release', 'rehearse.sh'), 'utf8');
  const specs = join(webRoot, 'e2e-rehearsal');
  const titles = (name) => [...readFileSync(join(specs, name), 'utf8').matchAll(/^\s*test\('([^']*)'/gm)].map((match) => match[1]);

  it('the tell-now spec stamps the subject with the prefix that the collector selects by', () => {
    const spec = readFileSync(join(specs, 'tell-now.spec.ts'), 'utf8');
    const stamp = /const stamp = `([^`]*)`;/.exec(spec)?.[1];
    assert.equal(stamp, 'Rehearsal run ${run}: ');
    assert.ok(/const subject = `\$\{stamp\}/.test(spec), 'the subject starts with the stamp');
    const collector = /Subject LIKE \?[^\n]*"(Rehearsal run @RUN@: %)"/.exec(rehearse)?.[1];
    assert.ok(collector, 'the collector selects the tell-now email by its subject prefix');
    assert.equal(collector.replace('@RUN@', '${run}').replace(/%$/, ''), stamp);
  });

  it('every --steps id of rehearse.sh is a spec file of the rehearsal project', () => {
    const ids = [...rehearse.matchAll(/--steps ([a-z,-]+)/g)].map((match) => match[1]).flatMap((list) => list.split(','));
    assert.deepEqual([...new Set(ids)].sort(), ['repeat', 'tell-now']);
    for (const id of ids) assert.ok(existsSync(join(specs, `${id}.spec.ts`)), `${id}.spec.ts exists`);
  });

  it('each test title starts with the step id that a FAIL line names, and that id is a step of the bounds table (again and trace measure no bound)', () => {
    const steps = /nsteps = split\("([^"]*)"/.exec(rehearse)?.[1].split(' ') ?? [];
    assert.ok(steps.includes('tell-now') && steps.includes('watch'), 'the steps are read from the script');
    const own = titles('repeat.spec.ts').map((title) => /^([a-z-]+): /.exec(title)?.[1]);
    assert.deepEqual(own, ['again', 'watch', 'reminder', 'incident', 'approval', 'trace', 'reminder']);
    for (const id of own.filter((name) => !['again', 'trace'].includes(name))) assert.ok(steps.includes(id), `${id} is a step of the bounds table`);
    assert.deepEqual(titles('tell-now.spec.ts').map((title) => /^([a-z-]+): /.exec(title)?.[1]), ['tell-now']);
  });
});
