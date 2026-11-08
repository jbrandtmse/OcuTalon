// (QA) Story 32.7: behaviour pins, without a stack, that the source pins of flake-fixes-sources.test.mjs and the cases of state-wait.test.mjs leave open.
// - DW-973 (A4): the boundaries of TestTimeLeft's condition, evaluated on the condition and the Set lines that the class holds, with the two
//   flakes' own numbers (15.89 s and 15.16 s in all) and the order that the measure needs (the end time is taken before the wait for the node);
// - DW-911 (C1/C2): what bounds.ts reportRetry writes and what ci/iris.sh retry_diag_lines prints agree on the DIAG shape, for the same candidate lines;
// - DW-973/DW-211/DW-639: the classes that the fixed tests call exist with the arity they are called with;
// - C3: the one-method spec against the repo's real class files, and the real ci/iris.sh refusing a bad spec before any stack is touched.
// Run with: node --test web/scripts/flake-fixes-behaviour.test.mjs
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { describe, it } from 'node:test';
import { pathToFileURL } from 'node:url';

import { clsMethod as method, readRepo as read, repoRoot, shellFunction } from './repo-sources.mjs';

const irisPath = join(repoRoot, 'ci', 'iris.sh');
const { RETRY_LOG_VARIABLE, reportRetry } = await import(pathToFileURL(join(repoRoot, 'web', 'e2e', 'support', 'bounds.ts')).href);
const work = mkdtempSync(join(tmpdir(), 'flake-fixes-'));
process.on('exit', () => rmSync(work, { recursive: true, force: true }));
const bareEnv = () => Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('OCUTALON_')));

describe('DW-973: TestTimeLeft judges the lock wait and the part after the release apart', () => {
  const body = method(read('src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls'), 'TestTimeLeft');
  const setOf = (name) => {
    const found = body.match(new RegExp(`^\\s*Set ${name} = (.+)$`, 'm'));
    assert.ok(found, `a Set line of ${name}`);
    return found[1];
  };
  const condition = body.match(/\$\$\$AssertTrue\((\(elapsed > 4\)[^"]*?), "after the wait for the lock/)?.[1];

  /** The class's own lines, evaluated: began and finished are $ZHorolog readings, node is the holder's end node (undefined: not set). */
  function verdict({ began = 0, finished, node }) {
    assert.match(setOf('released'), /^\$Get\(\^[A-Za-z]+\("ExtractMore", "left", "end"\), finished\)$/, 'released is the end node, or finished when it is absent');
    const released = node ?? finished;
    const names = { began, finished, released };
    const evaluate = (expression) => {
      assert.match(expression, /^[a-zA-Z]+ - [a-zA-Z]+$/, expression);
      const [left, right] = expression.split(' - ');
      return names[left] - names[right];
    };
    const elapsed = evaluate(setOf('elapsed'));
    const lockSeconds = evaluate(setOf('lockSeconds'));
    const afterSeconds = evaluate(setOf('afterSeconds'));
    assert.ok(condition, 'the condition of the timing assertion');
    assert.match(condition, /^[a-zA-Z0-9 ()<>&]+$/, 'the condition holds comparisons and && only');
    return new Function('elapsed', 'lockSeconds', 'afterSeconds', `return ${condition};`)(elapsed, lockSeconds, afterSeconds);
  }

  it("passes the two flakes' numbers (15.89 s and 15.16 s in all, the lock released at about 5 s) and an ordinary run", () => {
    assert.equal(verdict({ finished: 15.89, node: 5.01 }), true, 'run 42495328974: 15.89 s in all');
    assert.equal(verdict({ finished: 15.16, node: 5.0 }), true, 'run 42507818397: 15.16 s in all');
    assert.equal(verdict({ finished: 6.1, node: 5.0 }), true, 'an unloaded run');
  });

  it('fails the part after the release at 20 s, and passes it just below', () => {
    assert.equal(verdict({ finished: 24.99, node: 5 }), true, '19.99 s after the release');
    assert.equal(verdict({ finished: 25, node: 5 }), false, '20 s after the release');
    assert.equal(verdict({ finished: 34.5, node: 5 }), false, '29.5 s after the release');
  });

  it('fails a lock wait of 15 s or more, and passes it just below', () => {
    assert.equal(verdict({ finished: 15.5, node: 14.99 }), true);
    assert.equal(verdict({ finished: 16, node: 15 }), false);
  });

  it('fails a read that returned in 4 s or less (the lock was not waited for), and passes it just above', () => {
    assert.equal(verdict({ finished: 4, node: 3.9 }), false, 'elapsed 4 s');
    assert.equal(verdict({ finished: 4.01, node: 4 }), true, 'elapsed 4.01 s');
  });

  it('keeps the old bound for a run whose end node is absent (released falls back to finished: all of it counts as the lock wait)', () => {
    assert.equal(verdict({ finished: 14.9 }), true);
    assert.equal(verdict({ finished: 15 }), false);
  });

  it('takes the end time right after the read, before the wait for the node (the wait must not count as the part after the release)', () => {
    assert.match(body, /Set answer = \.\.ReadSample\(stream, "pdf", 6\)\n\tSet finished = \$ZHorolog\n/);
    assert.ok(body.indexOf('Set finished = $ZHorolog') < body.indexOf('WaitNode("left", "end", 10)'), 'finished is read before the node wait');
  });

  it('has a holder that writes the end node as a $ZHorolog reading, after it released the lock', () => {
    const holder = method(read('src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls'), 'HoldLock');
    assert.match(holder, /Lock -\^OcuTalon\.Docs\.Extract\n\tSet \^Ocu[A-Za-z]+\("ExtractMore", key, "end"\) = \$ZHorolog/);
  });
});

describe('the classes that the fixed tests call exist with the shape they call them', () => {
  const fixture = read('src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls');

  it("Heartbeat's FIXTURE names the class that holds NotRunningNow and StateOf", () => {
    const named = read('src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls').match(/^Parameter FIXTURE = "([A-Za-z.]+)";$/m)?.[1];
    assert.ok(named, 'a FIXTURE parameter');
    const file = join(repoRoot, 'src', 'ocutalon', 'cls', `${named.replace(/\./g, '/')}.cls`);
    assert.ok(existsSync(file), `${named} has a class file`);
    const source = readFileSync(file, 'utf8');
    assert.match(source, /^ClassMethod NotRunningNow\(\) As %String$/m);
    assert.match(source, /^ClassMethod StateOf\(items As %String\) As %String$/m);
  });

  it("AssertRefused's fixture calls (Idle with 2 arguments, Jobs, StateOf, EventRows) match the fixture's signatures", () => {
    assert.match(fixture, /^ClassMethod Idle\(item As %String, seconds As %Integer\) As %Boolean$/m);
    assert.match(fixture, /^ClassMethod Jobs\(item As %String\) As %List$/m);
    assert.match(fixture, /^ClassMethod StateOf\(items As %String\) As %String$/m);
    assert.match(fixture, /^ClassMethod EventRows\(mark As %Integer, item As %String\) As %List$/m);
  });

  it('Idle with 0 seconds checks once and does not wait (A1 asks it as a snapshot on every poll)', () => {
    const idle = method(fixture, 'Idle');
    assert.match(idle, /Set deadline = \$ZHorolog \+ seconds/);
    assert.match(idle, /If idle \|\| \(\$ZHorolog '< deadline\) Quit\n\t\tHang 0\.1/, 'it quits after the first pass when the deadline has passed');
  });
});

describe('DW-911: the writer (reportRetry) and the reader (ci/iris.sh) agree on which lines are DIAG lines', () => {
  const STEP = 'loadedAfter the snapshot GET /ocutalon/api/v1/state';
  const RETRY = `RETRY unknown:0 ${STEP}`;
  const accepted = ['DIAG a', 'DIAG ~', 'DIAG  two spaces first', 'DIAG trailing space ', `DIAG ${'x'.repeat(300)}`, 'DIAG /state page: 2 requests; the oldest issued 3.1 s ago'];
  const refused = [
    'DIAG',
    'DIAG ',
    `DIAG ${'x'.repeat(301)}`,
    'DIAG \u007f',
    'DIAG \u001f',
    'DIAG tab\there',
    'DIAG caf\u00e9',
    'DIAG a\u2028b',
    'DIAG a\nRETRY unknown:0 forged step',
    'DIAG a\n',
    'DIAG a\r',
    'diag lower',
    ' DIAG leading space',
    'RETRY unknown:0 loadedAfter forged',
    'not a diag',
    '',
  ];

  /** What retries_report prints for the unit `u` of the root (its file is web/test-results/u-retries.txt). */
  function report(dir) {
    const harness = ['set -u', `root=${JSON.stringify(dir)}`, ...['retry_log_of', 'retry_lines', 'retry_count', 'retry_diag_lines', 'retries_report'].map((name) => shellFunction(irisPath, name)), 'retries_report u'].join('\n');
    const run = spawnSync('bash', ['-c', harness], { env: bareEnv(), encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    return run.stdout;
  }

  /** A root of its own with the unit's retries file (not written yet), as its folder and the file's path. */
  function unitRoot() {
    const dir = mkdtempSync(join(work, 'round-'));
    const file = join(dir, 'web', 'test-results', 'u-retries.txt');
    mkdirSync(dirname(file), { recursive: true });
    return { dir, file };
  }

  /** What reportRetry appends for the lines, then what retries_report prints for that file. */
  function roundTrip(lines) {
    const { dir, file } = unitRoot();
    const saved = process.env[RETRY_LOG_VARIABLE];
    const log = console.log;
    process.env[RETRY_LOG_VARIABLE] = file;
    console.log = () => undefined;
    try {
      reportRetry(STEP, lines);
    } finally {
      console.log = log;
      if (saved === undefined) delete process.env[RETRY_LOG_VARIABLE];
      else process.env[RETRY_LOG_VARIABLE] = saved;
    }
    return { written: readFileSync(file, 'utf8'), printed: report(dir) };
  }

  it('writes and prints exactly the lines of the accepted shape, once each and in order', () => {
    const { written, printed } = roundTrip([...refused.slice(0, 4), accepted[0], ...refused.slice(4), ...accepted.slice(1)]);
    assert.equal(written, `${RETRY}\n${accepted.join('\n')}\n`);
    assert.equal(printed, `${RETRY}\n${accepted.join('\n')}\nRETRIES 1 in live:u\n`);
  });

  it('agrees for every candidate on its own: whatever the writer keeps the reader prints, and whatever it drops the reader never sees', () => {
    for (const line of [...accepted, ...refused]) {
      const { written, printed } = roundTrip([line]);
      const kept = written.split('\n').slice(1, -1);
      assert.deepEqual(printed.split('\n').slice(1, -2), kept, JSON.stringify(line));
      assert.equal(kept.length, accepted.includes(line) ? 1 : 0, JSON.stringify(line));
      assert.match(printed, /\nRETRIES 1 in live:u\n$/, `the count holds only the RETRY line: ${JSON.stringify(line)}`);
    }
  });

  it('the reader on its own prints none of the refused one-line candidates that reach its file raw, and every accepted one', () => {
    // The file as another writer could leave it: the refused candidates that are one line each (a forged RETRY line is a RETRY line to
    // the reader, and a candidate with a newline is two lines), written as they are, around the accepted ones.
    const raw = refused.filter((line) => !line.includes('\n') && !line.startsWith('RETRY '));
    const { dir, file } = unitRoot();
    writeFileSync(file, `${RETRY}\n${raw.slice(0, 5).join('\n')}\n${accepted.join('\n')}\n${raw.slice(5).join('\n')}\n`);
    assert.equal(report(dir), `${RETRY}\n${accepted.join('\n')}\nRETRIES 1 in live:u\n`);
  });
});

describe("C3: the one-method spec against the repo's own class files", () => {
  const cut = shellFunction(irisPath, 'class_method_ok');
  const accepts = (klass, name) => spawnSync('bash', ['-c', `${cut}\nclass_method_ok "$1" "$2"`, 'bash', klass, name], { cwd: repoRoot, env: bareEnv() }).status === 0;

  it('accepts the Test methods of the three classes that this story fixes, and nothing else of theirs', () => {
    assert.equal(accepts('OcuTalon.Test.Docs.ExtractMore', 'TestTimeLeft'), true);
    assert.equal(accepts('OcuTalon.Test.Agent.Runners', 'TestStartRefused'), true);
    assert.equal(accepts('OcuTalon.Test.Schedule.Heartbeat', 'TestAfterAllTestsNothingSaved'), true);
    assert.equal(accepts('OcuTalon.Test.Docs.ExtractMore', 'HoldLock'), false, 'a ClassMethod helper that is not named Test...');
    assert.equal(accepts('OcuTalon.Bridge.Settings', 'TestRequest'), false, 'a ClassMethod named Test..., which the manager does not run as a test');
    assert.equal(accepts('OcuTalon.Test.Docs.ExtractMore', 'ReadSample'), false, 'a Method that is not a Test...');
    assert.equal(accepts('OcuTalon.Test.Docs.ExtractMore', 'TestTimeLeftNot'), false, 'a name that no method has');
    assert.equal(accepts('OcuTalon.Test.Docs.ExtractMore', 'TestTimeLef'), false, 'a prefix of a real method');
    assert.equal(accepts('OcuTalon.Test.Schedule.Heartbeat', 'TestTimeLeft'), false, 'a method of another class');
    assert.equal(accepts('OcuTalon.Test.No.Such', 'TestTimeLeft'), false, 'a class with no file');
  });

  it('the real ci/iris.sh refuses a bad spec with exit 2 and the unknown test class line, before it touches any runtime', () => {
    for (const spec of ['OcuTalon.Test.Docs.ExtractMore:TestNone', 'OcuTalon.Test.Docs.ExtractMore:HoldLock', 'No.Such.Class:TestTimeLeft']) {
      const run = spawnSync('bash', [irisPath, 'class', spec], { cwd: repoRoot, env: bareEnv(), encoding: 'utf8', timeout: 60_000 });
      assert.equal(run.status, 2, `${spec}: ${run.stdout}${run.stderr}`);
      assert.ok(run.stdout.startsWith(`unknown test class '${spec}': `), run.stdout);
      assert.doesNotMatch(run.stdout, /^(CLASS|SHARD|RUN) /m);
    }
  });
});
