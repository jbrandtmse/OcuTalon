// Tests the online demo's busy state of the signed-in page (src/app/live/demo-busy.ts, Story 16.5, matrix row 17) with a fake clock:
// an API 503 makes it busy and a later 2xx clears it; a busy status makes it busy, arms a check every 10 s and a not-busy check
// clears it; either cause keeps it busy; a 2xx does not clear the trace cause and a status check does not clear the API cause; a
// check that could not be read keeps the trace cause and arms the next check; stop() cancels the timer and drops both causes; one
// onChange per change and none for a repeat. The module is imported as it is: Node strips its types, which holds only while it keeps
// to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { fakeClock } from './fake-clock.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'live', 'demo-busy.ts');
const { DEMO_BUSY_RECHECK_MS, DEMO_BUSY_STATUS, DemoBusyWatch } = await import(pathToFileURL(source).href);

/** A watch on a fake clock, with every value it reported and every check it asked for. */
function setup() {
  const clock = fakeClock();
  const changes = [];
  const rechecks = [];
  const watch = new DemoBusyWatch({
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    recheck: () => rechecks.push(clock.now),
    onChange: (busy) => changes.push(busy),
  });
  return { changes, clock, rechecks, watch };
}

describe('the constants', () => {
  it('are a 10 s re-check and the 503 status', () => {
    assert.equal(DEMO_BUSY_RECHECK_MS, 10_000);
    assert.equal(DEMO_BUSY_STATUS, 503);
  });
});

describe('the API cause', () => {
  it('is not busy at first, and a 503 makes it busy until the next 2xx', () => {
    const { changes, watch } = setup();
    assert.equal(watch.busy, false);
    watch.apiAnswered(503);
    assert.equal(watch.busy, true);
    watch.apiAnswered(503);
    watch.apiAnswered(202);
    assert.equal(watch.busy, false);
    assert.deepEqual(changes, [true, false], 'one change each way, none for a repeat');
  });

  it('is not cleared by another status, and is cleared by any 2xx', () => {
    const { watch } = setup();
    watch.apiAnswered(503);
    for (const status of [401, 403, 404, 500]) {
      watch.apiAnswered(status);
      assert.equal(watch.busy, true, `${status} leaves it`);
    }
    watch.apiAnswered(200);
    assert.equal(watch.busy, false);
  });

  it('arms no timer', () => {
    const { clock, watch } = setup();
    watch.apiAnswered(503);
    assert.equal(clock.pending, 0);
  });
});

describe('the trace cause', () => {
  it('a busy status makes it busy and arms one check, 10 s later, again each time the check says busy', () => {
    const { changes, clock, rechecks, watch } = setup();
    watch.statusChecked(true);
    assert.equal(watch.busy, true);
    assert.equal(clock.pending, 1);
    clock.advance(DEMO_BUSY_RECHECK_MS - 1);
    assert.deepEqual(rechecks, []);
    clock.advance(1);
    assert.deepEqual(rechecks, [10_000], 'the check is asked for at 10 s');
    watch.statusChecked(true);
    clock.advance(DEMO_BUSY_RECHECK_MS);
    assert.deepEqual(rechecks, [10_000, 20_000], 'and again 10 s after each busy answer');
    assert.deepEqual(changes, [true], 'busy stays reported once');
  });

  it('a second busy status does not arm a second timer', () => {
    const { clock, rechecks, watch } = setup();
    watch.statusChecked(true);
    watch.statusChecked(true);
    assert.equal(clock.pending, 1);
    clock.advance(10_000);
    assert.equal(rechecks.length, 1);
  });

  it('a not-busy check clears it and leaves no timer', () => {
    const { changes, clock, rechecks, watch } = setup();
    watch.statusChecked(true);
    clock.advance(10_000);
    watch.statusChecked(false);
    assert.equal(watch.busy, false);
    assert.equal(clock.pending, 0);
    clock.advance(60_000);
    assert.equal(rechecks.length, 1, 'no check is asked for after the demo is free');
    assert.deepEqual(changes, [true, false]);
  });

  it('a not-busy status with no busy before it changes nothing', () => {
    const { changes, clock, watch } = setup();
    watch.statusChecked(false);
    assert.equal(watch.busy, false);
    assert.equal(clock.pending, 0);
    assert.deepEqual(changes, []);
  });

  it('a check that could not be read keeps the cause and arms the next check; with no cause it does nothing', () => {
    const { clock, rechecks, watch } = setup();
    watch.checkFailed();
    assert.equal(clock.pending, 0, 'no cause, no timer');
    watch.statusChecked(true);
    clock.advance(10_000);
    watch.checkFailed();
    assert.equal(watch.busy, true);
    clock.advance(10_000);
    assert.equal(rechecks.length, 2);
  });

  it('a 2xx API answer does not clear it', () => {
    const { watch } = setup();
    watch.statusChecked(true);
    watch.apiAnswered(200);
    assert.equal(watch.busy, true);
  });
});

describe('both causes', () => {
  it('either keeps it busy, and it clears only when both are gone', () => {
    const { changes, watch } = setup();
    watch.apiAnswered(503);
    watch.statusChecked(true);
    watch.apiAnswered(200);
    assert.equal(watch.busy, true, 'the trace cause holds');
    watch.apiAnswered(503);
    watch.statusChecked(false);
    assert.equal(watch.busy, true, 'the API cause holds');
    watch.apiAnswered(202);
    assert.equal(watch.busy, false);
    assert.deepEqual(changes, [true, false]);
  });
});

describe('stop', () => {
  it('cancels the timer, drops both causes and ignores later reports', () => {
    const { changes, clock, rechecks, watch } = setup();
    watch.apiAnswered(503);
    watch.statusChecked(true);
    watch.stop();
    assert.equal(watch.busy, false);
    assert.equal(clock.pending, 0);
    clock.advance(60_000);
    assert.equal(rechecks.length, 0);
    watch.apiAnswered(503);
    watch.statusChecked(true);
    assert.equal(watch.busy, false);
    assert.equal(clock.pending, 0);
    assert.deepEqual(changes, [true, false]);
  });
});
