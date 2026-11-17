// Pins the call sites and shapes of Story 0.39 (browser-timing flakes wait for the page's real readiness) by reading their sources, because
// the live proofs run on a throwaway and the repros were scratch: each fix keeps the line that the flake needed changed.
// - DW-1448, DW-1452, DW-1458: the reloads that follow a state change go through loadedAfter / reloadSettled (one logged retry), never bare;
// - DW-1457: HC8's five reloads arm the heartbeat GET before the reload and assert its status 200 by name;
// - DW-1451: memory-card's handled waits for every tracked request to end (finished or failed), bounded and named;
// - DW-1450: row 6 of test-online-demo.sh waits on the public status reading free before its one sign-in, with no new sleep.
// Run with: node --test web/scripts/flake-timing-sources.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { describe, it } from 'node:test';

import { readRepo as read, repoRoot } from './repo-sources.mjs';

const count = (text, pattern) => (text.match(pattern) ?? []).length;
const RELOAD_VIA_FLOOR = /await loadedAfter\(page, \(\) => page\.reload\(\)\);/g;

/** The text of an async function of a spec, from its declaration to the first line that is only a closing brace. */
function fn(source, name) {
  const start = source.indexOf(`async function ${name}(`);
  assert.notEqual(start, -1, `${name} exists`);
  const rest = source.slice(start);
  return rest.slice(0, rest.search(/^\}/m));
}

describe('DW-1448: telegram-page reloads go through loadedAfter', () => {
  const source = read('web/e2e/demo-path/telegram-page.spec.ts');

  it('reloads at six sites through loadedAfter and makes no bare reload', () => {
    assert.equal(count(source, RELOAD_VIA_FLOOR), 6);
    assert.equal(count(source, /page\.reload\(\)/g), 6, 'every reload is the one inside loadedAfter');
  });

  it('no longer has the local loaded() that waited on the snapshot without a retry', () => {
    assert.doesNotMatch(source, /function loaded\(/);
    assert.doesNotMatch(source, /await loaded\(page\)/);
  });
});

describe('DW-1458: history reloads settle through reloadSettled', () => {
  const source = read('web/e2e/history/history.spec.ts');

  it('settles three reloads through reloadSettled and has no bare page.reload()', () => {
    assert.equal(count(source, /await reloadSettled\(page\);/g), 3);
    assert.doesNotMatch(source, /page\.reload\(\)/);
    assert.match(source, /import \{ loadedAfter, reloadSettled \} from '\.\.\/support\/floor';/);
  });
});

describe('DW-1452: the guide spec reopens through loadedAfter', () => {
  it('has reopen() reload through loadedAfter and nothing else', () => {
    const source = read('web/e2e/guide/guide.spec.ts');
    assert.match(fn(source, 'reopen'), /^\s+await loadedAfter\(page, \(\) => page\.reload\(\)\);$/m);
    assert.doesNotMatch(fn(source, 'reopen'), /expect\(|waitForTimeout/);
  });
});

describe('DW-1457: HC8 asserts the heartbeat GET after each of its five reloads', () => {
  const source = read('web/e2e/heartbeat-card.spec.ts');
  const helper = fn(source, 'reloadWithHeartbeat');

  it('arms the wait for the GET before the reload, reloads through loadedAfter, then bounds and names the wait', () => {
    const armed = helper.indexOf('page.waitForResponse(');
    const reloaded = helper.indexOf('await loadedAfter(page, () => page.reload());');
    const awaited = helper.indexOf("boundedStep(asked, waits.action, 'the heartbeat GET after the reload')");
    assert.ok(armed !== -1 && armed < reloaded && reloaded < awaited, 'armed, then reloaded, then awaited');
    assert.match(helper, /request\(\)\.method\(\) === 'GET' && new URL\(response\.url\(\)\)\.pathname === HEARTBEAT/);
  });

  it('asserts status 200 with a message that names the heartbeat GET and the status it answered', () => {
    assert.match(helper, /expect\(response\.status\(\), `the heartbeat GET answered \$\{response\.status\(\)\}`\)\.toBe\(200\);/);
  });

  it('adds no sleep or timeout of its own', () => {
    assert.doesNotMatch(helper, /waitForTimeout|setTimeout|sleep/);
  });

  it('reloads through it five times in HC8, no other test uses it, and HC8 makes no bare reload', () => {
    const start = source.indexOf("test('HC8:");
    assert.notEqual(start, -1, 'HC8 exists');
    const hc8 = source.slice(start, source.indexOf('\ntest(', start + 1));
    assert.equal(count(hc8, /await reloadWithHeartbeat\(page\);/g), 5);
    assert.equal(count(source, /await reloadWithHeartbeat\(page\);/g), 5, 'only HC8 reloads through it');
    assert.doesNotMatch(hc8, /page\.reload\(/, 'HC8 reloads only through reloadWithHeartbeat');
  });
});

describe('DW-1451: memory-card handled waits for every tracked request to end', () => {
  const source = read('web/e2e/memory-card.spec.ts');
  const handled = fn(source, 'handled');

  it('ends a request on requestfinished or requestfailed, both listeners removed on stop', () => {
    const start = source.indexOf('function trackEnds(');
    const tracker = source.slice(start, source.indexOf('\n}\n', start));
    for (const event of ['requestfinished', 'requestfailed']) {
      assert.match(tracker, new RegExp(`page\\.on\\('${event}', onEnd\\)`), `${event} ends a request`);
      assert.match(tracker, new RegExp(`page\\.off\\('${event}', onEnd\\)`), `${event} listener is removed`);
    }
  });

  it('also tracks the answered request, issued before answerOf (the held read at a reload), unless it has already ended', () => {
    const included = handled.indexOf('tracker.include(response.request());');
    const bounded = handled.indexOf('boundedStep(tracker.ended()');
    assert.ok(included !== -1 && bounded !== -1 && included < bounded, 'the answered request is tracked before the wait for the ends');
    const start = source.indexOf('function trackEnds(');
    const tracker = source.slice(start, source.indexOf('\n}\n', start));
    assert.match(tracker, /const onEnd = \(request: Request\): void => \{\s+done\.add\(request\);/);
    assert.match(tracker, /include: \(request\) => \{\s+if \(!done\.has\(request\)\) open\.add\(request\);/);
  });

  it('arms its tracker when answerOf is called, so that it counts the requests issued since', () => {
    const start = source.indexOf('function answerOf(');
    const body = source.slice(start, source.indexOf('\n}\n', start));
    assert.match(body, /const tracker = trackEnds\(page, route, method\);[\s\S]*TRACKERS\.set\(answer, tracker\);/);
  });

  it('waits on the tracker bounded by the action wait, names the route and the open count, and stops the tracker in a finally', () => {
    assert.match(handled, /boundedStep\(tracker\.ended\(\), waits\.action, `handled the end of every \$\{tracker\.method\} \$\{String\(tracker\.route\)\} request`\)/);
    assert.match(handled, /\$\{tracker\.open\.size\} request\(s\) still open/);
    assert.match(handled, /\} finally \{\s+tracker\.stop\(\);/);
  });

  it('does not wait on Response.finished(), which never settles for a request the card aborts after its headers', () => {
    assert.doesNotMatch(handled, /\.finished\(\)/);
  });

  it('draws two frames after the end, as before, and adds no sleep', () => {
    assert.match(handled, /requestAnimationFrame\(\(\) => requestAnimationFrame\(\(\) => setTimeout\(resolve, 0\)\)\)/);
    assert.doesNotMatch(handled, /waitForTimeout/);
  });
});

describe('DW-1450: row 6 of test-online-demo.sh waits for the status to read free before it signs in', () => {
  const script = read('docker/tests/test-online-demo.sh');
  const start = script.indexOf('conn_before_s5=$(script_connections)');
  const row = script.slice(start, script.indexOf('# --- ', start) === -1 ? start + 4000 : Math.min(start + 4000, script.indexOf('# --- ', start)));

  it('reads the held connections, then sets the cap, then waits on status_free with a 30 s bound, then signs in once', () => {
    const order = [
      'conn_before_s5=$(script_connections)',
      'set_cap "$cap_free" > /dev/null',
      'status_free() {',
      'if wait_until 30 status_free; then',
      's5_code=$(online_signin "$jar_s5" "$addr_s5" "")',
    ].map((text) => row.indexOf(text));
    assert.ok(order.every((at) => at !== -1), `every step is in row 6: ${order}`);
    assert.deepEqual([...order].sort((a, b) => a - b), order, 'in that order');
    assert.equal(count(row, /online_signin "\$jar_s5"/g), 1, 'one sign-in');
  });

  it('fails by name, with the last reading, and skips the sign-in when the status never reads free', () => {
    assert.match(row, /row 6: the status did not read free within 30 s after the cap was set to \$cap_free \(last '\$\{s5_last:-<never read>\}'\)/);
    assert.match(row, /if \[ -n "\$s5_free_failed" \]; then\n\s+fail "\$s5_free_failed \(no sign-in was made;/);
  });

  it('adds no sleep to the row', () => {
    assert.doesNotMatch(row.slice(0, row.indexOf('s5_outcome=none')), /\bsleep\b/);
  });

  it('keeps the pass condition and shows the S5 POST status and busy page in the fail line', () => {
    assert.match(row, /\[ "\$s3_ok" = 1 \] && \[ "\$s5_outcome" = shell \] && \[ -n "\$s5_cookie" \] && \[ "\$s5_counter" = 1 \]/);
    assert.match(row, /the S5 POST gave status '\$\{s5_code:-<none>\}', busy page '\$\(busy_page "\$jar_s5\.b"\)'/);
  });

  it('status_free is true only for "false none 200", as the shell runs it', () => {
    const definition = /^\s+status_free\(\) \{\n[\s\S]*?\n\s+\}$/m.exec(row);
    assert.ok(definition, 'status_free is defined in the row');
    const reads = { 'false none 200': 0, 'true none 200': 1, 'true 1 200': 1, 'false 1 200': 1, 'unreadable none 200': 1, 'false none 503': 1, '': 1 };
    for (const [reading, status] of Object.entries(reads)) {
      const run = `status_read() { printf '%s' "$READING"; }\n${definition[0]}\nstatus_free; echo $?`;
      const out = execFileSync('bash', ['-c', run], { cwd: repoRoot, env: { ...process.env, READING: reading }, encoding: 'utf8' });
      assert.equal(Number(out.trim()), status, `'${reading}'`);
    }
  });
});
