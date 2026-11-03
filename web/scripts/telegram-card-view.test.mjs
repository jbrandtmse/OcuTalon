// Tests the order of the Telegram card's states (src/app/rail/telegram-card/telegram-card-view.ts, Stories 12.8, 12.3, 12.4 and 12.5; DW-527):
// paused first, then not set up, then paired, then just unpaired (for JUST_UNPAIRED_MS after the pairing ended, UX-DR14, UX-DR56), then none
// or unpaired. The browser tests T5 and T6 see the just-unpaired view only after an unpairing, so none of them notices the view coming ahead
// of the paired or paused branch; this pins every pair of neighbours on the framework-free view, as it is imported.
// It also pins when the card asks for a code (CodeSchedule, on the fake clock): the first request after an unpair goes out at once,
// every other request keeps the 10 s spacing, a failure asks again 30 s later, a 409 stops the asking, and the card hands the schedule
// its `paired` value before it starts asking (a source pin on telegram-card.ts).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { CODE_RETRY_MS, CODE_SPACING_MS, CodeSchedule, JUST_UNPAIRED_MS, TELEGRAM_CARD_TEXTS, telegramCardView } = await import(app('rail', 'telegram-card', 'telegram-card-view.ts'));
const { fakeClock } = await import(pathToFileURL(join(here, 'fake-clock.mjs')).href);

const NOW = 1_800_000_000_000;
const format = { time: (iso) => iso };

/** The store's status conditions: the pause, active or not. */
const paused = { telegramPaused: { condition: 'telegramPaused', active: true, slots: { time: '12:30' } } };
const notPaused = { telegramPaused: { condition: 'telegramPaused', active: false } };

/** The snapshot's Telegram block, with the fields given over a paired, named, on-state default. */
const telegram = (over = {}) => ({ state: 'on', botUserName: 'ocutalon_pair_bot', paired: true, displayName: 'Dana', ...over });

/** What the card itself holds: a code that is still due, not refused, and the pairing not just ended unless said. */
const own = (over = {}) => ({ code: { code: 'K1', due: NOW + 600_000 }, refused: false, justUnpaired: false, now: NOW, ...over });

const kind = (tg, status, mine) => telegramCardView(tg, status, mine, format).kind;

describe('the Telegram card just unpaired', () => {
  it('shows for 5 seconds and says "Telegram unpaired"', () => {
    assert.equal(JUST_UNPAIRED_MS, 5000);
    assert.equal(TELEGRAM_CARD_TEXTS.unpaired, 'Telegram unpaired');
  });

  it('is the view of an unpaired, on card that has just lost its pairing, with no link, code or minutes', () => {
    const view = telegramCardView(telegram({ paired: false, displayName: '' }), notPaused, own({ justUnpaired: true }), format);
    assert.deepEqual(view, { kind: 'just-unpaired', retry: '', paired: '', link: '', minutes: 0 });
  });

  it('gives way to the fresh code once the window is over', () => {
    const view = telegramCardView(telegram({ paired: false, displayName: '' }), notPaused, own(), format);
    assert.equal(view.kind, 'unpaired');
    assert.equal(view.link, 'https://t.me/ocutalon_pair_bot?start=K1');
  });

  it('is shown with no code held yet, where an ordinary unpaired card with no code shows nothing', () => {
    const unpaired = telegram({ paired: false, displayName: '' });
    assert.equal(kind(unpaired, notPaused, own({ code: undefined, justUnpaired: true })), 'just-unpaired');
    assert.equal(kind(unpaired, notPaused, own({ code: undefined })), 'none');
  });
});

describe('the order of the card\'s states', () => {
  it('shows paired, not just unpaired, when a pairing happens inside the 5 s window', () => {
    const view = telegramCardView(telegram(), notPaused, own({ justUnpaired: true }), format);
    assert.equal(view.kind, 'paired');
    assert.equal(view.paired, 'Telegram paired \u00b7 Dana');
  });

  it('shows paired with no name, not just unpaired, inside the window', () => {
    assert.equal(telegramCardView(telegram({ displayName: '' }), notPaused, own({ justUnpaired: true }), format).paired, 'Telegram paired');
  });

  it('shows paused ahead of just unpaired, and ahead of paired', () => {
    assert.equal(kind(telegram({ paired: false }), paused, own({ justUnpaired: true })), 'paused');
    assert.equal(kind(telegram({ paired: true }), paused, own({ justUnpaired: true })), 'paused');
    assert.equal(telegramCardView(telegram({ paired: false }), paused, own({ justUnpaired: true }), format).retry, 'Trying again at 12:30');
  });

  it('shows not set up ahead of just unpaired, for an off or rejected bot and for a refused code', () => {
    const gone = telegram({ paired: false, displayName: '' });
    assert.equal(kind({ ...gone, state: 'off' }, notPaused, own({ justUnpaired: true })), 'not-set-up');
    assert.equal(kind({ ...gone, state: 'rejected' }, notPaused, own({ justUnpaired: true })), 'not-set-up');
    assert.equal(kind(gone, notPaused, own({ justUnpaired: true, refused: true })), 'not-set-up');
  });

  it('shows not set up ahead of paired when the bot is off, and paired ahead of unpaired', () => {
    assert.equal(kind(telegram({ state: 'off' }), notPaused, own()), 'not-set-up');
    assert.equal(kind(telegram(), notPaused, own({ code: undefined })), 'paired');
  });

  it('shows the just-unpaired state only through justUnpaired, never for a plain unpaired card', () => {
    const gone = telegram({ paired: false, displayName: '' });
    assert.equal(kind(gone, undefined, own()), 'unpaired');
    assert.equal(kind(gone, undefined, own({ justUnpaired: true })), 'just-unpaired');
  });
});

/** A schedule on a fake clock, and a request that records when it went out and keeps the reply it was given. */
function scheduled() {
  const clock = fakeClock();
  const schedule = new CodeSchedule({ setTimeout: (h, ms) => clock.setTimeout(h, ms), clearTimeout: (h) => clock.clearTimeout(h), now: () => clock.now });
  const sent = [];
  let reply;
  let cancelled = 0;
  const request = (given) => {
    sent.push(clock.now);
    reply = given;
    return () => {
      cancelled += 1;
    };
  };
  return { clock, schedule, sent, request, reply: () => reply, cancelled: () => cancelled };
}

/** Starts an asking, lets its first request go out at the clock's time 0, and answers it with a code due at `due`. */
function firstRequest(t, due = 600_000) {
  t.schedule.paired(false);
  const stop = t.schedule.start(t.request);
  t.clock.advance(0);
  t.reply().code(due);
  return stop;
}

describe('when the card asks for a code', () => {
  it('keeps a 10 s spacing and a 30 s retry', () => {
    assert.equal(CODE_SPACING_MS, 10_000);
    assert.equal(CODE_RETRY_MS, 30_000);
  });

  it('sends the first request ever at once', () => {
    const t = scheduled();
    t.schedule.paired(true);
    t.schedule.start(t.request);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0]);
  });

  it('the first value grants nothing: a card whose first value is unpaired still waits out the spacing', () => {
    const t = scheduled();
    const stop = t.schedule.start(t.request);
    t.clock.advance(0);
    t.reply().code(600_000);
    t.clock.advance(2_000);
    stop();
    t.schedule.paired(false);
    t.schedule.start(t.request);
    t.clock.advance(CODE_SPACING_MS - 2_000 - 1);
    assert.deepEqual(t.sent, [0]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, CODE_SPACING_MS]);
  });

  it('after an unpair, the request goes out at once, even 2 s after the last one', () => {
    const t = scheduled();
    t.schedule.paired(false);
    const stop = t.schedule.start(t.request);
    t.clock.advance(0);
    t.reply().code(600_000);
    t.clock.advance(1_000);
    stop();
    t.schedule.paired(true);
    t.clock.advance(1_000);
    t.schedule.paired(false);
    t.schedule.start(t.request);
    assert.equal(t.clock.now, 2_000);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0, 2_000]);
  });

  it('a new round with no unpair waits until exactly 10 s after the last request', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(2_000);
    stop();
    t.schedule.start(t.request);
    t.clock.advance(CODE_SPACING_MS - 2_000 - 1);
    assert.deepEqual(t.sent, [0]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, CODE_SPACING_MS]);
  });

  it('after the exempt request, a code that is due at once waits until 10 s after it', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(2_000);
    stop();
    t.schedule.paired(true);
    t.schedule.paired(false);
    t.schedule.start(t.request);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0, 2_000]);
    t.reply().code(t.clock.now);
    t.clock.advance(CODE_SPACING_MS - 1);
    assert.deepEqual(t.sent, [0, 2_000]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, 2_000, 2_000 + CODE_SPACING_MS]);
  });

  it('a request after an exempt one is spaced again even when a new round starts with no unpair', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(2_000);
    stop();
    t.schedule.paired(true);
    t.schedule.paired(false);
    const second = t.schedule.start(t.request);
    t.clock.advance(0);
    second();
    t.schedule.start(t.request);
    t.clock.advance(CODE_SPACING_MS - 1);
    assert.deepEqual(t.sent, [0, 2_000]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, 2_000, 2_000 + CODE_SPACING_MS]);
  });

  it('a failure asks again exactly 30 000 ms later, the exempt request included, with no second exemption', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(2_000);
    stop();
    t.schedule.paired(true);
    t.schedule.paired(false);
    t.schedule.start(t.request);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0, 2_000]);
    t.reply().failed();
    t.clock.advance(CODE_RETRY_MS - 1);
    assert.deepEqual(t.sent, [0, 2_000]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, 2_000, 2_000 + CODE_RETRY_MS]);
    t.reply().failed();
    t.clock.advance(CODE_RETRY_MS);
    assert.deepEqual(t.sent, [0, 2_000, 2_000 + CODE_RETRY_MS, 2_000 + 2 * CODE_RETRY_MS]);
  });

  it('a request that is never answered leaves no timer, so a refusal (no reply) ends the asking', () => {
    const t = scheduled();
    t.schedule.start(t.request);
    t.clock.advance(0);
    assert.equal(t.clock.pending, 0);
    t.clock.advance(CODE_RETRY_MS * 10);
    assert.deepEqual(t.sent, [0]);
  });

  it('gives one exemption for each unpair', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(1_000);
    stop();
    t.schedule.paired(true);
    t.schedule.paired(false);
    const second = t.schedule.start(t.request);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0, 1_000]);
    t.clock.advance(1_000);
    second();
    t.schedule.paired(true);
    t.schedule.paired(false);
    t.schedule.start(t.request);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0, 1_000, 2_000]);
  });

  it('gives one exemption for two unpairs with no request in between', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(1_000);
    stop();
    t.schedule.paired(true);
    t.schedule.paired(false);
    t.schedule.paired(true);
    t.schedule.paired(false);
    const second = t.schedule.start(t.request);
    t.clock.advance(0);
    assert.deepEqual(t.sent, [0, 1_000]);
    second();
    t.schedule.start(t.request);
    t.clock.advance(CODE_SPACING_MS - 1);
    assert.deepEqual(t.sent, [0, 1_000]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, 1_000, 1_000 + CODE_SPACING_MS]);
  });

  it('asks again at the code\'s due time, and stop clears the timer and cancels the request in flight', () => {
    const t = scheduled();
    const stop = firstRequest(t, 40_000);
    assert.equal(t.clock.pending, 1);
    t.clock.advance(39_999);
    assert.deepEqual(t.sent, [0]);
    t.clock.advance(1);
    assert.deepEqual(t.sent, [0, 40_000]);
    t.reply().code(100_000);
    assert.equal(t.clock.pending, 1);
    stop();
    assert.equal(t.clock.pending, 0);
    assert.equal(t.cancelled(), 1);
    t.clock.advance(1_000_000);
    assert.deepEqual(t.sent, [0, 40_000]);
  });

  it('ignores a reply that comes after stop', () => {
    const t = scheduled();
    const stop = firstRequest(t);
    t.clock.advance(100);
    const late = t.reply();
    stop();
    late.code(0);
    late.failed();
    assert.equal(t.clock.pending, 0);
  });
});

describe('the card hands its schedule the pairing', () => {
  const source = readFileSync(join(here, '..', 'src', 'app', 'rail', 'telegram-card', 'telegram-card.ts'), 'utf8');
  const askingFrom = source.indexOf('// The asking:');
  const asking = source.slice(askingFrom, source.indexOf("// The countdown's tick", askingFrom));

  it('builds the schedule, and keeps no spacing of its own', () => {
    assert.match(source, /new CodeSchedule\(/);
    assert.doesNotMatch(source, /lastRequest|CODE_SPACING_MS|CODE_RETRY_MS/);
  });

  it('tells it the paired value inside the asking effect, untracked, before it starts asking', () => {
    assert.ok(asking.length > 0, 'the asking effect is found');
    const untrackedAt = asking.indexOf('untracked(');
    const toldAt = asking.search(/this\.schedule\.paired\(this\.telegram\(\)\.paired\)/);
    const emptyKeyAt = asking.indexOf("if (key === '')");
    const askingAt = asking.indexOf('this.ask(');
    assert.ok(untrackedAt >= 0 && toldAt > untrackedAt, 'the value is read untracked');
    assert.ok(emptyKeyAt > toldAt, 'the schedule is told on every run, before the early returns');
    assert.ok(askingAt > emptyKeyAt, 'the schedule is told before the asking starts');
  });

  it('a 409 shows the not-set-up view and returns without a reply, so the schedule stops asking', () => {
    const errorBranch = source.slice(source.indexOf('error: (error: unknown)'));
    assert.match(errorBranch, /status === 409\) \{\s*this\.refusedAt\.set\(key\);\s*return;\s*\}\s*reply\.failed\(\);/);
  });
});
