// Tests the page's idle cap (src/app/session/idle-cap.ts, Story 16.4) on a fake clock: it calls its handler once, at exactly the cap after
// the last touch (not a moment before); a touch counts from the touch; stop() silences it and leaves no timer; a timer that fires late
// (the wall clock jumped, as after a sleep) calls the handler at once, and one that fires early arms itself again; a second start replaces
// the first; a value that is no number above 0 arms nothing; a touch before the first start does nothing.
// The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { fakeClock } from './fake-clock.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const { IdleCap } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'session', 'idle-cap.ts')).href);

/** A cap on a fake clock whose wall clock is the clock's own, unless the test moves `skew` (the wall clock running ahead of the timers). */
function setup() {
  const clock = fakeClock();
  const state = { idle: 0, skew: 0 };
  const cap = new IdleCap({
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    now: () => clock.now + state.skew,
    onIdle: () => {
      state.idle += 1;
    },
  });
  return { cap, clock, state };
}

describe('an idle cap', () => {
  it('calls its handler once, at exactly the cap after start', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    clock.advance(599_999);
    assert.equal(state.idle, 0, 'not a millisecond early');
    clock.advance(1);
    assert.equal(state.idle, 1, 'at the cap');
    clock.advance(3_600_000);
    assert.equal(state.idle, 1, 'and never again');
    assert.equal(cap.active, false);
    assert.equal(clock.pending, 0);
  });

  it('counts from the latest touch, not from the start', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    clock.advance(590_000);
    cap.touch();
    clock.advance(599_999);
    assert.equal(state.idle, 0, '599.999 s after the touch');
    clock.advance(1);
    assert.equal(state.idle, 1, '600 s after the touch');
  });

  it('is kept alive by a touch every few minutes, and falls when they stop', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    for (let i = 0; i < 20; i += 1) {
      clock.advance(300_000);
      cap.touch();
    }
    assert.equal(state.idle, 0);
    clock.advance(600_000);
    assert.equal(state.idle, 1);
  });

  it('is silenced by stop(), which leaves no timer', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    clock.advance(300_000);
    cap.stop();
    assert.equal(clock.pending, 0);
    clock.advance(3_600_000);
    assert.equal(state.idle, 0);
    assert.equal(cap.active, false);
    cap.touch();
    clock.advance(3_600_000);
    assert.equal(state.idle, 0, 'a touch after stop() does not start it again');
  });

  it('calls its handler at once when the timer fires late: the wall clock is past the cap', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    clock.advance(10_000);
    state.skew = 8 * 3600 * 1000;
    clock.advance(590_000);
    assert.equal(state.idle, 1, 'the first timer that fires finds the cap passed');
  });

  it('arms itself again for what is left when the timer fires early', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    clock.advance(300_000);
    state.skew = -200_000;
    clock.advance(300_000);
    assert.equal(state.idle, 0, 'the wall clock is 200 s behind: 200 s are left');
    assert.equal(clock.pending, 1);
    clock.advance(199_999);
    assert.equal(state.idle, 0);
    clock.advance(1);
    assert.equal(state.idle, 1);
  });

  it('is replaced by a second start, which counts again and drops the first timer', () => {
    const { cap, clock, state } = setup();
    cap.start(600);
    clock.advance(500_000);
    cap.start(100);
    assert.equal(clock.pending, 1, 'one timer');
    clock.advance(99_999);
    assert.equal(state.idle, 0);
    clock.advance(1);
    assert.equal(state.idle, 1, 'the second cap fired');
    clock.advance(3_600_000);
    assert.equal(state.idle, 1, 'and the first never does');
  });

  it('arms nothing for a value that is no number above 0, and a touch before start does nothing', () => {
    const { cap, clock, state } = setup();
    cap.touch();
    for (const value of [0, -5, Number.NaN, Number.POSITIVE_INFINITY]) {
      cap.start(value);
      assert.equal(cap.active, false, `start(${value})`);
      assert.equal(clock.pending, 0);
    }
    clock.advance(3_600_000);
    assert.equal(state.idle, 0);
  });

  it('holds a cap longer than a browser timer can, by arming again', () => {
    const { cap, clock, state } = setup();
    const days = 40 * 86_400;
    cap.start(days);
    clock.advance(days * 1000 - 1);
    assert.equal(state.idle, 0);
    clock.advance(1);
    assert.equal(state.idle, 1);
  });
});
