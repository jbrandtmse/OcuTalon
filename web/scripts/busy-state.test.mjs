// Tests the busy state machine of the server button (src/app/shared/busy-state.ts) with a fake clock: busy until the
// answer, restored with one notice at 10 s, a repeated press ignored, a late answer clearing the notice. The module is
// imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'shared', 'busy-state.ts');
const { BusyState, BUSY_TIMEOUT_MS } = await import(pathToFileURL(source).href);

/** A clock that runs a timer only when the test advances it. */
function fakeClock() {
  let now = 0;
  let next = 1;
  const timers = new Map();
  return {
    setTimeout(handler, ms) {
      const id = next++;
      timers.set(id, { at: now + ms, handler });
      return id;
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    advance(ms) {
      const target = now + ms;
      for (;;) {
        const due = [...timers.entries()].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        timers.delete(due[0]);
        now = due[1].at;
        due[1].handler();
      }
      now = target;
    },
    get pending() {
      return timers.size;
    },
  };
}

/** A state machine on a fake clock, with what it reported. */
function setup() {
  const clock = fakeClock();
  const seen = { notices: 0, views: [] };
  const state = new BusyState({
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    onChange: (view) => seen.views.push(view),
    onNotice: () => {
      seen.notices += 1;
    },
  });
  return { clock, seen, state };
}

describe('the server button\'s busy state', () => {
  it('imports as plain TypeScript and times out at 10 seconds', () => {
    assert.equal(BUSY_TIMEOUT_MS, 10_000);
    const { state } = setup();
    assert.deepEqual(state.view, { busy: false, notice: false });
  });

  it('is busy from the press until the answer, then normal, with no timer left', () => {
    const { clock, seen, state } = setup();
    assert.equal(state.press(), true);
    assert.deepEqual(state.view, { busy: true, notice: false });
    clock.advance(9_999);
    assert.deepEqual(state.view, { busy: true, notice: false }, 'still busy just before 10 s');
    state.answered(state.call);
    assert.deepEqual(state.view, { busy: false, notice: false });
    assert.equal(clock.pending, 0, 'the answer cancels the timer');
    clock.advance(60_000);
    assert.equal(seen.notices, 0, 'no notice for an answer in time');
    assert.deepEqual(state.view, { busy: false, notice: false });
  });

  it('restores at 10 seconds and raises the notice once', () => {
    const { clock, seen, state } = setup();
    state.press();
    clock.advance(10_000);
    assert.deepEqual(state.view, { busy: false, notice: true });
    assert.equal(seen.notices, 1);
    clock.advance(120_000);
    assert.equal(seen.notices, 1, 'the notice is raised once');
    assert.deepEqual(seen.views.at(-1), { busy: false, notice: true });
  });

  it('ignores a press while busy and makes no second call', () => {
    const { clock, state } = setup();
    assert.equal(state.press(), true);
    const call = state.call;
    clock.advance(5_000);
    assert.equal(state.press(), false, 'the repeated press is refused');
    assert.equal(state.call, call, 'no second call was numbered');
    clock.advance(5_000);
    assert.deepEqual(state.view, { busy: false, notice: true }, 'the refused press did not restart the 10 s');
  });

  it('clears the notice when the late answer arrives', () => {
    const { clock, seen, state } = setup();
    state.press();
    const call = state.call;
    clock.advance(10_000);
    assert.equal(state.view.notice, true);
    state.answered(call);
    assert.deepEqual(state.view, { busy: false, notice: false });
    assert.equal(seen.notices, 1, 'the notice was raised once and not again');
  });

  it('accepts a press after the restore, and the first call\'s late answer does not end the second', () => {
    const { clock, seen, state } = setup();
    state.press();
    const first = state.call;
    clock.advance(10_000);
    assert.equal(state.press(), true, 'the restored button takes a new press');
    const second = state.call;
    assert.notEqual(second, first);
    assert.deepEqual(state.view, { busy: true, notice: false }, 'a new press clears the old notice');
    state.answered(first);
    assert.deepEqual(state.view, { busy: true, notice: false }, 'the first call\'s answer leaves the second busy');
    clock.advance(9_999);
    assert.equal(state.view.busy, true);
    clock.advance(1);
    assert.deepEqual(state.view, { busy: false, notice: true });
    assert.equal(seen.notices, 2, 'each timeout raises its own notice');
  });

  it('drops its timer when disposed', () => {
    const { clock, seen, state } = setup();
    state.press();
    state.dispose();
    assert.equal(clock.pending, 0);
    clock.advance(20_000);
    assert.equal(seen.notices, 0);
  });

  it('keeps to erasable syntax and imports nothing', () => {
    const text = readFileSync(source, 'utf8');
    assert.doesNotMatch(text, /^\s*import\s/m, 'no import');
    assert.doesNotMatch(text, /\benum\b|\bnamespace\b/, 'no enum and no namespace');
    assert.doesNotMatch(text, /constructor\s*\([^)]*\b(?:private|public|protected|readonly)\s/, 'no parameter property');
  });
});
