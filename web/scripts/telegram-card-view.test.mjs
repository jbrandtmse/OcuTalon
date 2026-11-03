// Tests the order of the Telegram card's states (src/app/rail/telegram-card/telegram-card-view.ts, Stories 12.8, 12.3, 12.4 and 12.5; DW-527):
// paused first, then not set up, then paired, then just unpaired (for JUST_UNPAIRED_MS after the pairing ended, UX-DR14, UX-DR56), then none
// or unpaired. The browser tests T5 and T6 see the just-unpaired view only after an unpairing, so none of them notices the view coming ahead
// of the paired or paused branch; this pins every pair of neighbours on the framework-free view, as it is imported.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { JUST_UNPAIRED_MS, TELEGRAM_CARD_TEXTS, telegramCardView } = await import(app('rail', 'telegram-card', 'telegram-card-view.ts'));

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
