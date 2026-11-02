// Tests the queue behind the page's one announcer (src/app/shared/announce-queue.ts) with a fake clock: one message at 0 ms, the
// messages of one update as one text, a burst as "{n} new updates", texts at least 1 s apart, a lone message past three in 2 s
// waiting for the window, and that nothing is spoken twice or dropped. The module is imported as it is: Node strips its types,
// which holds only while it keeps to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { fakeClock } from './fake-clock.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'shared', 'announce-queue.ts');
const { ANNOUNCE_MERGE_ABOVE, ANNOUNCE_MIN_GAP_MS, ANNOUNCE_WINDOW_MS, AnnounceQueue, NEW_UPDATES } = await import(pathToFileURL(source).href);

/** A queue on a fake clock, with what it spoke and when. */
function setup() {
  const clock = fakeClock();
  const spoken = [];
  const queue = new AnnounceQueue({
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    now: () => clock.now,
    speak: (text) => spoken.push({ at: clock.now, text }),
  });
  return { clock, queue, spoken };
}

/** The texts spoken, without their times. */
const texts = (spoken) => spoken.map((one) => one.text);

describe('the announce queue\'s constants', () => {
  it('are three in two seconds, one second apart, and the plural form of the UX', () => {
    assert.equal(ANNOUNCE_MERGE_ABOVE, 3);
    assert.equal(ANNOUNCE_WINDOW_MS, 2000);
    assert.equal(ANNOUNCE_MIN_GAP_MS, 1000);
    assert.equal(NEW_UPDATES, '{n} new updates');
  });
});

describe('one update', () => {
  it('speaks one message at 0 ms, once, as it is', () => {
    const { clock, queue, spoken } = setup();
    queue.push('Reminder: stretch.');
    assert.deepEqual(spoken, [], 'not within the pushing turn');
    clock.advance(0);
    assert.deepEqual(spoken, [{ at: 0, text: 'Reminder: stretch.' }]);
    clock.advance(10_000);
    assert.equal(spoken.length, 1, 'never spoken twice');
    assert.equal(clock.pending, 0);
  });

  it('does not add a full stop to a lone message, and trims it', () => {
    const { clock, queue, spoken } = setup();
    queue.push('  Message not sent \n');
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['Message not sent']);
  });

  it('ignores an empty message', () => {
    const { clock, queue, spoken } = setup();
    queue.push('');
    queue.push('   \n ');
    assert.equal(clock.pending, 0, 'no timer for nothing');
    clock.advance(5000);
    assert.deepEqual(spoken, []);
  });

  it('speaks messages pushed together as one text, in order, with a full stop only where one is missing', () => {
    const { clock, queue, spoken } = setup();
    queue.push('First banner');
    queue.push('Second one.');
    queue.push('Third?');
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['First banner. Second one. Third?']);
    assert.equal(spoken[0].at, 0);
  });

  it('counts "!" and the ellipsis as the end of a sentence', () => {
    const { clock, queue, spoken } = setup();
    queue.push('Stop!');
    queue.push('Wait\u2026');
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['Stop! Wait\u2026']);
  });

  it('speaks four pushed together as "4 new updates" and none of their texts', () => {
    const { clock, queue, spoken } = setup();
    for (const message of ['a one', 'b two', 'c three', 'd four']) {
      queue.push(message);
    }
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['4 new updates']);
  });

  it('speaks three pushed together as themselves', () => {
    const { clock, queue, spoken } = setup();
    for (const message of ['a one', 'b two', 'c three']) {
      queue.push(message);
    }
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['a one. b two. c three.']);
  });
});

describe('spacing', () => {
  it('speaks a second text 1 s after the first, however soon it was pushed', () => {
    const { clock, queue, spoken } = setup();
    queue.push('first');
    clock.advance(0);
    clock.advance(200);
    queue.push('second');
    clock.advance(799);
    assert.deepEqual(texts(spoken), ['first'], 'not before 1 s');
    clock.advance(1);
    assert.deepEqual(spoken, [
      { at: 0, text: 'first' },
      { at: 1000, text: 'second' },
    ]);
  });

  it('joins what is pushed while it waits for the gap into one text', () => {
    const { clock, queue, spoken } = setup();
    queue.push('first');
    clock.advance(0);
    queue.push('second');
    clock.advance(300);
    queue.push('third');
    clock.advance(700);
    assert.deepEqual(spoken, [
      { at: 0, text: 'first' },
      { at: 1000, text: 'second. third.' },
    ]);
  });

  it('speaks a message pushed after the gap at once', () => {
    const { clock, queue, spoken } = setup();
    queue.push('first');
    clock.advance(0);
    clock.advance(1500);
    queue.push('second');
    clock.advance(0);
    assert.deepEqual(spoken, [
      { at: 0, text: 'first' },
      { at: 1500, text: 'second' },
    ]);
  });
});

describe('more than three in 2 seconds', () => {
  it('speaks two more as "2 new updates" when two were heard within 2 s', () => {
    const { clock, queue, spoken } = setup();
    queue.push('one');
    queue.push('two');
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['one. two.']);
    queue.push('three');
    queue.push('four');
    clock.advance(1000);
    assert.deepEqual(spoken, [
      { at: 0, text: 'one. two.' },
      { at: 1000, text: '2 new updates' },
    ]);
  });

  it('speaks two more as one joined text when one was heard', () => {
    const { clock, queue, spoken } = setup();
    queue.push('one');
    clock.advance(0);
    queue.push('two');
    queue.push('three');
    clock.advance(1000);
    assert.deepEqual(texts(spoken), ['one', 'two. three.']);
  });

  it('makes a lone message wait until 2 s after three heard, and speaks it alone', () => {
    const { clock, queue, spoken } = setup();
    for (const message of ['one', 'two', 'three']) {
      queue.push(message);
    }
    clock.advance(0);
    assert.deepEqual(texts(spoken), ['one. two. three.']);
    clock.advance(1000);
    queue.push('four');
    clock.advance(999);
    assert.equal(spoken.length, 1, 'still waiting at 1999 ms');
    clock.advance(1);
    assert.deepEqual(spoken[1], { at: 2000, text: 'four' });
    assert.ok(!texts(spoken).some((text) => text.includes('1 new update')), 'never "1 new updates"');
  });

  it('joins what arrives while a lone message waits for the window into the same flush', () => {
    const { clock, queue, spoken } = setup();
    for (const message of ['one', 'two', 'three']) {
      queue.push(message);
    }
    clock.advance(0);
    clock.advance(1000);
    queue.push('four');
    clock.advance(500);
    queue.push('five');
    clock.advance(499);
    assert.equal(spoken.length, 1);
    clock.advance(1);
    assert.deepEqual(spoken[1], { at: 2000, text: 'four. five.' });
    assert.equal(spoken.length, 2);
    assert.equal(clock.pending, 0);
  });

  it('turns a flush of four at the end of the wait into "4 new updates"', () => {
    const { clock, queue, spoken } = setup();
    for (const message of ['one', 'two', 'three']) {
      queue.push(message);
    }
    clock.advance(0);
    clock.advance(1000);
    queue.push('four');
    clock.advance(0);
    assert.equal(spoken.length, 1, 'four waits for the window');
    clock.advance(500);
    for (const message of ['five', 'six', 'seven']) {
      queue.push(message);
    }
    clock.advance(500);
    assert.deepEqual(spoken[1], { at: 2000, text: '4 new updates' });
    assert.equal(spoken.length, 2);
  });
});

describe('the whole sequence', () => {
  it('speaks every pushed message exactly once, never closer than 1 s, and joined texts never pass three in 2 s (a fixed seed)', () => {
    let seed = 20261024;
    const random = () => {
      seed = (seed + 0x6d2b79f5) >>> 0;
      let t = seed;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    const { clock, queue, spoken } = setup();
    let pushed = 0;
    for (let step = 0; step < 400; step += 1) {
      const burst = Math.floor(random() * 5);
      for (let i = 0; i < burst; i += 1) {
        pushed += 1;
        queue.push(pushed % 2 === 0 ? `msg ${pushed}.` : `msg ${pushed}`);
      }
      clock.advance(Math.floor(random() * 1600));
    }
    clock.advance(60_000);
    assert.equal(clock.pending, 0, 'nothing left waiting');

    let carried = 0;
    const ids = [];
    for (const one of spoken) {
      const burst = /^(\d+) new updates$/.exec(one.text);
      if (burst) {
        assert.ok(Number(burst[1]) >= 2, 'never fewer than 2 in a burst');
        one.messages = Number(burst[1]);
      } else {
        const found = [...one.text.matchAll(/msg (\d+)/g)].map((match) => Number(match[1]));
        assert.ok(found.length >= 1);
        ids.push(...found);
        one.messages = found.length;
      }
      carried += one.messages;
    }
    assert.equal(carried, pushed, 'nothing dropped, nothing spoken twice');
    assert.equal(new Set(ids).size, ids.length, 'no message in two texts');
    assert.deepEqual(ids, [...ids].sort((a, b) => a - b), 'in push order');
    assert.ok(spoken.length > 20, 'the sequence spoke a good many texts');
    assert.ok(spoken.some((one) => /new updates$/.test(one.text)), 'and it held bursts');
    spoken.forEach((one, i) => {
      if (i > 0) {
        assert.ok(one.at - spoken[i - 1].at >= ANNOUNCE_MIN_GAP_MS, `text ${i} is at least 1 s after the one before`);
      }
      if (!/new updates$/.test(one.text)) {
        const inWindow = spoken.filter((other) => other.at <= one.at && one.at - other.at < ANNOUNCE_WINDOW_MS).reduce((total, other) => total + other.messages, 0);
        assert.ok(inWindow <= ANNOUNCE_MERGE_ABOVE, `a joined text at ${one.at} ms leaves ${inWindow} in its 2 s`);
      }
    });
  });
});

describe('dispose', () => {
  it('leaves no timer and speaks nothing more', () => {
    const { clock, queue, spoken } = setup();
    queue.push('one');
    assert.equal(clock.pending, 1);
    queue.dispose();
    assert.equal(clock.pending, 0);
    clock.advance(10_000);
    assert.deepEqual(spoken, []);
    queue.push('two');
    assert.equal(clock.pending, 0, 'a push after it arms nothing');
    clock.advance(10_000);
    assert.deepEqual(spoken, []);
  });

  it('leaves no timer when it ends a wait for the window', () => {
    const { clock, queue } = setup();
    for (const message of ['one', 'two', 'three']) {
      queue.push(message);
    }
    clock.advance(0);
    clock.advance(1000);
    queue.push('four');
    assert.equal(clock.pending, 1);
    queue.dispose();
    assert.equal(clock.pending, 0);
  });
});

describe('the module', () => {
  it('keeps to erasable syntax, imports nothing and is ASCII', () => {
    const text = readFileSync(source, 'utf8');
    assert.doesNotMatch(text, /^\s*import\s/m, 'no import');
    assert.doesNotMatch(text, /\benum\b|\bnamespace\b/, 'no enum and no namespace');
    assert.doesNotMatch(text, /constructor\s*\([^)]*\b(?:private|public|protected|readonly)\s/, 'no parameter property');
    assert.doesNotMatch(text, /[^\x00-\x7F]/, 'non-ASCII characters are written as escapes');
  });
});
