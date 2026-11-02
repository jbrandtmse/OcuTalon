// Tests the page's contact watch (src/app/live/contact-watch.ts, Story 2.11) with a fake clock: nothing armed before the first answer;
// ok at 9 999 ms, reconnecting at 10 000, still reconnecting at 29 999, unreachable at 30 000; an answer giving ok from either state
// and counting again from that call; one onChange per change and none for a repeat; stop() giving ok, leaving no timer and ignoring a
// later answer; the poll delay (normal for ok and reconnecting, what is left of 10 s for unreachable, 0 at or past it); the busy status.
// The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { fakeClock } from './fake-clock.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'live', 'contact-watch.ts');
const { BUSY_STATUS, ContactWatch, RECONNECTING_AFTER_MS, UNREACHABLE_AFTER_MS, UNREACHABLE_RETRY_MS, pollDelay } = await import(pathToFileURL(source).href);

/** A watch on a fake clock, with every state it reported. */
function setup() {
  const clock = fakeClock();
  const changes = [];
  const watch = new ContactWatch({
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    onChange: (state) => changes.push(state),
  });
  return { changes, clock, watch };
}

describe('the thresholds', () => {
  it('are 10 s, 30 s and a 10 s retry, and a 503 is the busy status', () => {
    assert.equal(RECONNECTING_AFTER_MS, 10_000);
    assert.equal(UNREACHABLE_AFTER_MS, 30_000);
    assert.equal(UNREACHABLE_RETRY_MS, 10_000);
    assert.equal(BUSY_STATUS, 503);
  });
});

describe('a contact watch', () => {
  it('is ok with no timer armed before the first answer', () => {
    const { changes, clock, watch } = setup();
    assert.equal(watch.state, 'ok');
    assert.equal(clock.pending, 0);
    clock.advance(60_000);
    assert.equal(watch.state, 'ok', 'however long nothing answers, a watch that was never armed says nothing');
    assert.deepEqual(changes, []);
  });

  it('is ok at 9 999 ms, reconnecting at 10 000, reconnecting at 29 999 and unreachable at 30 000', () => {
    const { changes, clock, watch } = setup();
    watch.answered();
    clock.advance(9_999);
    assert.equal(watch.state, 'ok');
    clock.advance(1);
    assert.equal(watch.state, 'reconnecting');
    clock.advance(19_999);
    assert.equal(watch.state, 'reconnecting');
    clock.advance(1);
    assert.equal(watch.state, 'unreachable');
    clock.advance(60_000);
    assert.equal(watch.state, 'unreachable', 'and it stays unreachable');
    assert.deepEqual(changes, ['reconnecting', 'unreachable']);
  });

  it('gives ok at an answer from either state, and counts both thresholds again from that call', () => {
    const { changes, clock, watch } = setup();
    watch.answered();
    clock.advance(12_000);
    assert.equal(watch.state, 'reconnecting');
    watch.answered();
    assert.equal(watch.state, 'ok', 'an answer while reconnecting');
    clock.advance(9_999);
    assert.equal(watch.state, 'ok', '10 s count from the answer, not from the first one');
    clock.advance(1);
    assert.equal(watch.state, 'reconnecting');
    clock.advance(19_999);
    assert.equal(watch.state, 'reconnecting', '30 s count from the answer too');
    clock.advance(1);
    assert.equal(watch.state, 'unreachable');
    watch.answered();
    assert.equal(watch.state, 'ok', 'an answer while unreachable');
    clock.advance(9_999);
    assert.equal(watch.state, 'ok');
    assert.deepEqual(changes, ['reconnecting', 'ok', 'reconnecting', 'unreachable', 'ok']);
  });

  it('never changes while it is answered more often than every 10 s, and keeps only its two thresholds armed', () => {
    const { changes, clock, watch } = setup();
    watch.answered();
    for (let at = 0; at < 120; at += 1) {
      clock.advance(1_500);
      watch.answered();
    }
    assert.equal(watch.state, 'ok');
    assert.deepEqual(changes, []);
    assert.equal(clock.pending, 2, 'only the two thresholds are armed, however many answers came');
  });

  it('calls onChange once per change and not for a repeat', () => {
    const { changes, watch } = setup();
    watch.answered();
    watch.answered();
    assert.deepEqual(changes, [], 'ok again is no change');
    const second = setup();
    second.watch.answered();
    second.clock.advance(10_000);
    second.watch.answered();
    second.watch.answered();
    assert.deepEqual(second.changes, ['reconnecting', 'ok'], 'an answer that follows an answer is a repeat');
  });

  it('gives ok at stop(), leaves no timer pending, and ignores an answer after it', () => {
    const { changes, clock, watch } = setup();
    watch.answered();
    clock.advance(15_000);
    assert.equal(watch.state, 'reconnecting');
    watch.stop();
    assert.equal(watch.state, 'ok');
    assert.equal(clock.pending, 0, 'both timers were cleared');
    watch.answered();
    assert.equal(clock.pending, 0, 'a later answer arms nothing');
    clock.advance(60_000);
    assert.equal(watch.state, 'ok');
    assert.deepEqual(changes, ['reconnecting', 'ok']);
  });

  it('stops quietly when it is ok, and stays stopped when it was never armed', () => {
    const { changes, clock, watch } = setup();
    watch.stop();
    watch.answered();
    clock.advance(60_000);
    assert.equal(watch.state, 'ok');
    assert.equal(clock.pending, 0);
    assert.deepEqual(changes, []);
  });
});

describe('the poll delay', () => {
  it('is the normal delay for ok and reconnecting, whatever the elapsed time', () => {
    for (const elapsed of [0, 400, 10_000, 25_000]) {
      assert.equal(pollDelay('ok', elapsed, 1_000), 1_000);
      assert.equal(pollDelay('reconnecting', elapsed, 1_000), 1_000);
    }
  });

  it('is 10 000 minus the elapsed time for unreachable, and 0 at or past 10 000', () => {
    assert.equal(pollDelay('unreachable', 0, 1_000), 10_000);
    assert.equal(pollDelay('unreachable', 3, 1_000), 9_997);
    assert.equal(pollDelay('unreachable', 9_999, 1_000), 1);
    assert.equal(pollDelay('unreachable', 10_000, 1_000), 0);
    assert.equal(pollDelay('unreachable', 10_001, 1_000), 0);
    assert.equal(pollDelay('unreachable', 60_000, 1_000), 0);
  });
});

describe('the module', () => {
  it('keeps to erasable syntax and imports nothing', () => {
    const text = readFileSync(source, 'utf8');
    assert.doesNotMatch(text, /^\s*import\s/m, 'no import');
    assert.doesNotMatch(text, /\benum\b|\bnamespace\b/, 'no enum and no namespace');
    assert.doesNotMatch(text, /constructor\s*\([^)]*\b(?:private|public|protected|readonly)\s/, 'no parameter property');
  });
});
