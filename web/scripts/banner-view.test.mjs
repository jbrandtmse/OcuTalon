// Tests the status banners' view (src/app/banners/banner-view.ts, Story 2.10): the closed table of nine banners with its ids, variants,
// icons, actions and closing; the exact texts of the catalog with their slots; the stacking order on a local install and on the online
// demo; the closing rule (a closed banner stays away while its condition holds with the same slots, and returns on a changed slot and
// on clear-then-active); that an inactive, unknown or absent condition shows nothing; that a missing or unreadable slot renders empty
// and the banner still shows; that {time} is the browser's page time with no zone name, even on the online demo (DW-29); and that the
// strings are ASCII. The view is given the real catalog, page-time, decision-view, links and rail-view modules, each imported as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { BANNERS, BANNER_TEXTS, REPLACED_BY, activeBanners, bannersView, closeBanner, retainClosed } = await import(app('banners', 'banner-view.ts'));
const { renderPageText } = await import(app('msg', 'catalog.ts'));
const { pageTime } = await import(app('chat', 'page-time.ts'));
const { formatCost } = await import(app('chat', 'decision-view.ts'));
const { README_URL } = await import(app('links.ts'));
const { TELEGRAM_ANCHOR, readmeSection } = await import(app('rail', 'rail-view.ts'));

/** The format the component builds, with the browser's locale and zone named. */
const formatIn = (zone = 'UTC', locale = 'en-GB') => ({
  text: (key, slots) => renderPageText(key, slots),
  time: (iso) => pageTime(iso, locale, zone),
  cost: (amount) => formatCost(amount),
  readmeUrl: README_URL,
  telegramUrl: readmeSection(README_URL, TELEGRAM_ANCHOR),
});
const format = formatIn();

const T = '2026-10-23T12:00:00Z';

/** The status of the store: the conditions given, by condition. */
const status = (...payloads) => Object.fromEntries(payloads.map((payload) => [payload.condition, payload]));
const on = (condition, slots) => (slots === undefined ? { condition, active: true } : { condition, active: true, slots });
const off = (condition) => ({ condition, active: false });

/** The input of the view with the conditions given: a local install by default. */
const input = (payloads = [], over = {}) => ({ status: status(...payloads), own: [], onlineDemo: false, closed: {}, ...over });
const view = (payloads = [], over = {}, fmt = format) => bannersView(input(payloads, over), fmt);
const ids = (banners) => banners.map((banner) => banner.id);

/** The six conditions that stack, all active. */
const SIX = [
  on('allowance', { limit: 20, time: T }),
  on('dailyCap', { cap: 20, time: T }),
  on('noModelKey'),
  on('heartbeatStalled', { time: T }),
  on('telegramPaused', { time: T }),
  on('resetSoon'),
];

describe('the table of banners', () => {
  it('holds the nine banners of the closed catalog, in the order they stack (UX-DR100)', () => {
    assert.deepEqual(
      BANNERS.map((banner) => banner.id),
      ['allowance', 'dailyCap', 'unreachable', 'noModelKey', 'costCap', 'heartbeatStalled', 'telegramPaused', 'resetSoon', 'reconnecting'],
    );
    assert.equal(BANNERS.length, 9);
    assert.equal(new Set(BANNERS.map((banner) => banner.id)).size, 9, 'each id once');
    assert.equal(new Set(BANNERS.map((banner) => banner.key)).size, 9, 'each catalog key once');
  });

  it('gives each banner its catalog key, variant, icon, action and closing as the UX table does', () => {
    const row = (id) => {
      const banner = BANNERS.find((one) => one.id === id);
      return [banner.key, banner.variant, banner.icon, banner.action?.key ?? null, banner.action?.target ?? null, banner.closable];
    };
    assert.deepEqual(row('allowance'), ['banner.allowance', 'danger', 'circle-alert', 'bannerAction.installYourself', 'readme', false]);
    assert.deepEqual(row('dailyCap'), ['banner.dailyCap', 'danger', 'circle-alert', 'bannerAction.installYourself', 'readme', false]);
    assert.deepEqual(row('unreachable'), ['banner.unreachable', 'danger', 'circle-alert', null, null, false]);
    assert.deepEqual(row('noModelKey'), ['banner.noModelKey', 'warning', 'triangle-alert', 'bannerAction.howToSetKey', 'readme', false]);
    assert.deepEqual(row('costCap'), ['banner.costCap', 'warning', 'triangle-alert', null, null, false]);
    assert.deepEqual(row('heartbeatStalled'), ['banner.heartbeatStalled', 'warning', 'triangle-alert', null, null, false]);
    assert.deepEqual(row('telegramPaused'), ['banner.telegramPaused', 'warning', 'triangle-alert', 'bannerAction.setUpBot', 'telegram', false]);
    assert.deepEqual(row('resetSoon'), ['banner.resetSoon', 'warning', 'triangle-alert', null, null, true]);
    assert.deepEqual(row('reconnecting'), ['banner.reconnecting', 'info', 'info', null, null, true]);
  });

  it('shares the daily cap condition between two banners, by onlineDemo, and gives the others one condition each', () => {
    assert.deepEqual(BANNERS.filter((banner) => banner.condition === 'dailyCap').map((banner) => [banner.id, banner.onlineDemo]), [['dailyCap', true], ['costCap', false]]);
    for (const banner of BANNERS.filter((one) => one.condition !== 'dailyCap')) assert.equal(banner.onlineDemo, undefined, banner.id);
  });

  it('closes only Reset soon and Reconnecting', () => {
    assert.deepEqual(BANNERS.filter((banner) => banner.closable).map((banner) => banner.id), ['resetSoon', 'reconnecting']);
  });

  it('has only the Close word of its own, and every string in ASCII', () => {
    assert.deepEqual({ ...BANNER_TEXTS }, { close: 'Close' });
    for (const banner of BANNERS) {
      for (const text of [banner.id, banner.condition, banner.key, banner.variant, banner.icon, banner.action?.key ?? '', banner.action?.target ?? '']) {
        assert.match(text, /^[\x20-\x7e]*$/, `${banner.id}: ${text}`);
      }
    }
    for (const text of Object.values(BANNER_TEXTS)) assert.match(text, /^[\x20-\x7e]+$/, text);
  });
});

describe('the texts', () => {
  const only = (payload, over = {}, fmt = format) => view([payload], over, fmt)[0];

  it('read as the catalog words them, with the slots filled', () => {
    assert.equal(only(on('noModelKey')).text, 'OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon.');
    assert.equal(only(on('dailyCap', { cap: 20, time: T })).text, "OcuTalon has reached today's cost limit of $20.00. Decisions use fixed rules until 12:00.");
    assert.equal(only(on('dailyCap', { cap: 20, time: T }), { onlineDemo: true }).text, "The online demo has used today's model allowance. Decisions use fixed rules until 12:00.");
    assert.equal(
      only(on('allowance', { limit: 20, time: T })).text,
      "You've used this session's 20 messages for the hour (messages you send in the chat or Telegram). You can send more at 12:00.",
    );
    assert.equal(
      only(on('heartbeatStalled', { time: T })).text,
      'Background checks have paused: the heartbeat last ran at 12:00. Watches and reminders may be late until it recovers.',
    );
    assert.equal(
      only(on('telegramPaused', { time: T })).text,
      'Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at 12:00. Each OcuTalon needs its own bot.',
    );
    assert.equal(only(on('resetSoon')).text, 'The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.');
    assert.equal(view([], { own: ['unreachable'] })[0].text, "Can't reach OcuTalon. Retrying every 10 seconds.");
    assert.equal(view([], { own: ['reconnecting'] })[0].text, 'Reconnecting\u2026 New messages may be delayed.');
  });

  it('name the cap as a cost: two decimals from a dollar, three below a dollar', () => {
    const cap = (amount) => only(on('dailyCap', { cap: amount, time: T })).text;
    assert.match(cap(20), /limit of \$20\.00\./);
    assert.match(cap(0.5), /limit of \$0\.500\./);
    assert.match(cap(1234.5), /limit of \$1234\.50\./);
  });

  it('give the limit as digits', () => {
    const limit = (value) => only(on('allowance', { limit: value, time: T })).text;
    assert.match(limit(20), /session's 20 messages/);
    assert.match(limit(5.9), /session's 5 messages/);
    assert.match(limit(0), /session's 0 messages/);
  });

  it('give the time the browser reads, with no zone name and never " ET", on a local install and on the online demo (DW-29)', () => {
    const kolkata = formatIn('Asia/Kolkata');
    for (const onlineDemo of [true, false]) {
      const dailyCap = only(on('dailyCap', { cap: 20, time: T }), { onlineDemo }, kolkata);
      assert.match(dailyCap.text, /until 17:30\.$/, `onlineDemo ${onlineDemo}`);
      assert.doesNotMatch(dailyCap.text, / ET\b|IST|GMT|UTC|America|Asia/, `onlineDemo ${onlineDemo}: no zone name`);
    }
    assert.match(only(on('heartbeatStalled', { time: T }), {}, kolkata).text, /ran at 17:30\./);
    assert.match(only(on('telegramPaused', { time: T }), {}, kolkata).text, /try again at 17:30\./);
    assert.match(only(on('allowance', { limit: 3, time: T }), {}, kolkata).text, /send more at 17:30\.$/);
    const newYork = formatIn('America/New_York', 'en-US');
    const text = only(on('dailyCap', { cap: 20, time: T }), { onlineDemo: true }, newYork).text;
    assert.match(text, /until 8:00 AM\.$/, 'the browser zone and hour format, whatever the instance zone is (the catalog reads a narrow no-break space as a space)');
    assert.doesNotMatch(text, / ET\b|EDT/);
  });

  it('render a missing or unreadable slot empty, and the banner still shows', () => {
    for (const slots of [undefined, {}, { time: '' }, { time: 'tomorrow' }, { time: 5 }, { cap: 'twenty' }, { cap: null }]) {
      const banners = view([on('dailyCap', slots)]);
      assert.deepEqual(ids(banners), ['costCap'], JSON.stringify(slots));
      assert.doesNotMatch(banners[0].text, /\$|NaN|undefined|null|\{/, JSON.stringify(slots));
      assert.match(banners[0].text, /^OcuTalon has reached today's cost limit of/, JSON.stringify(slots));
    }
    assert.equal(view([on('dailyCap', {})])[0].text, "OcuTalon has reached today's cost limit of . Decisions use fixed rules until .");
    assert.equal(view([on('heartbeatStalled')])[0].text, 'Background checks have paused: the heartbeat last ran at . Watches and reminders may be late until it recovers.');
    assert.equal(view([on('allowance', { limit: -1, time: 'x' })])[0].text.slice(0, 40), "You've used this session's  messages for");
  });

  it('show a value that names a placeholder as it is, filled in once', () => {
    assert.equal(only(on('dailyCap', { cap: 20, time: '{cap}' })).text, "OcuTalon has reached today's cost limit of $20.00. Decisions use fixed rules until .");
  });
});

describe('the actions', () => {
  const action = (payload, over) => view([payload], over)[0].action;

  it('are "Install it yourself" to the README for the allowance and the online demo\'s cap, and "How to set a key" to the README', () => {
    assert.deepEqual(action(on('allowance', { limit: 20, time: T })), { text: 'Install it yourself', href: README_URL });
    assert.deepEqual(action(on('dailyCap', { cap: 20, time: T }), { onlineDemo: true }), { text: 'Install it yourself', href: README_URL });
    assert.deepEqual(action(on('noModelKey')), { text: 'How to set a key', href: README_URL });
  });

  it('are "Set up a bot" to the README\'s Telegram section for the paused bot', () => {
    assert.deepEqual(action(on('telegramPaused', { time: T })), { text: 'Set up a bot', href: `${README_URL.slice(0, README_URL.indexOf('#'))}#telegram` });
  });

  it('are none for the cost limit (Budgets waits for the settings page), the heartbeat, Reset soon and the page\'s own', () => {
    assert.equal(action(on('dailyCap', { cap: 20, time: T })), undefined);
    assert.equal(action(on('heartbeatStalled', { time: T })), undefined);
    assert.equal(action(on('resetSoon')), undefined);
    assert.equal(view([], { own: ['unreachable'] })[0].action, undefined);
    assert.equal(view([], { own: ['reconnecting'] })[0].action, undefined);
  });
});

describe('the stack', () => {
  it('orders a local install: allowance, noModelKey, costCap, heartbeatStalled, telegramPaused, resetSoon', () => {
    assert.deepEqual(ids(view(SIX)), ['allowance', 'noModelKey', 'costCap', 'heartbeatStalled', 'telegramPaused', 'resetSoon']);
  });

  it('puts the online demo\'s daily cap second', () => {
    assert.deepEqual(ids(view(SIX, { onlineDemo: true })), ['allowance', 'dailyCap', 'noModelKey', 'heartbeatStalled', 'telegramPaused', 'resetSoon']);
  });

  it('orders the same whatever the order of the store', () => {
    assert.deepEqual(ids(view([...SIX].reverse())), ['allowance', 'noModelKey', 'costCap', 'heartbeatStalled', 'telegramPaused', 'resetSoon']);
  });

  it('puts the page\'s own banners where the table has them: Unreachable before the key, Reconnecting last', () => {
    assert.deepEqual(ids(view(SIX, { own: ['reconnecting', 'unreachable'] })), ['allowance', 'unreachable', 'noModelKey', 'costCap', 'heartbeatStalled', 'telegramPaused', 'resetSoon', 'reconnecting']);
  });

  it('shows nothing for an empty store, an inactive condition, an unknown condition or a condition that is not a banner', () => {
    assert.deepEqual(view(), []);
    assert.deepEqual(view([off('noModelKey'), off('dailyCap'), off('heartbeatStalled'), off('resetSoon')]), []);
    assert.deepEqual(view([{ condition: 'noModelKey' }]), [], 'a payload with no active flag');
    assert.deepEqual(view([{ condition: 'noModelKey', active: 'true' }]), [], 'an active flag that is not true');
    assert.deepEqual(view([on('zzUnknown'), on('constructor'), on('unreachable'), on('reconnecting'), on('costCap')]), [], 'an unknown condition, and a page\'s own condition from the store');
    assert.deepEqual(ids(view([on('zzUnknown'), on('noModelKey')])), ['noModelKey']);
    assert.deepEqual(view([], { own: ['zz'] }), []);
  });

  it('shows the cap as the danger banner on the online demo and the warning otherwise, never both', () => {
    assert.deepEqual(view([on('dailyCap', { cap: 20, time: T })], { onlineDemo: true }).map((banner) => [banner.id, banner.variant, banner.icon]), [['dailyCap', 'danger', 'circle-alert']]);
    assert.deepEqual(view([on('dailyCap', { cap: 20, time: T })]).map((banner) => [banner.id, banner.variant, banner.icon]), [['costCap', 'warning', 'triangle-alert']]);
  });

  it('gives the variant, icon and closing of each banner it shows', () => {
    const banners = view(SIX, {}, format);
    assert.deepEqual(
      banners.map((banner) => [banner.id, banner.variant, banner.icon, banner.closable]),
      [
        ['allowance', 'danger', 'circle-alert', false],
        ['noModelKey', 'warning', 'triangle-alert', false],
        ['costCap', 'warning', 'triangle-alert', false],
        ['heartbeatStalled', 'warning', 'triangle-alert', false],
        ['telegramPaused', 'warning', 'triangle-alert', false],
        ['resetSoon', 'warning', 'triangle-alert', true],
      ],
    );
  });
});

describe('the replacements', () => {
  it('are exactly Unreachable replacing Reconnecting, and each one names banners of the table', () => {
    assert.deepEqual(REPLACED_BY, { reconnecting: 'unreachable' });
    const known = BANNERS.map((banner) => banner.id);
    for (const [leaving, replacement] of Object.entries(REPLACED_BY)) {
      assert.ok(known.includes(leaving), `${leaving} is a banner id`);
      assert.ok(known.includes(replacement), `${replacement} is a banner id`);
    }
  });

  it('are both of the page\'s own banners, and the replacement stacks before the one it replaces', () => {
    const order = BANNERS.map((banner) => banner.id);
    assert.ok(order.indexOf('unreachable') < order.indexOf('reconnecting'));
    assert.deepEqual(ids(view([], { own: ['unreachable'] })), ['unreachable'], 'Unreachable alone, once it replaces Reconnecting');
    assert.deepEqual(ids(view([], { own: ['reconnecting'] })), ['reconnecting']);
  });
});

describe('closing', () => {
  const resetSoon = (payloads = [on('resetSoon')], over = {}) => view(payloads, over).find((banner) => banner.id === 'resetSoon');

  it('hides a closed banner while its condition holds with the same signature', () => {
    const closed = closeBanner({}, resetSoon());
    assert.deepEqual(ids(view([on('resetSoon'), on('noModelKey')], { closed })), ['noModelKey']);
    assert.deepEqual(ids(view([on('resetSoon'), on('noModelKey')], { closed })), ['noModelKey'], 'and again');
    assert.deepEqual(ids(activeBanners(input([on('resetSoon'), on('noModelKey')]), format)), ['noModelKey', 'resetSoon'], 'the active ones still hold it');
  });

  it('shows it again when the slots change', () => {
    const resetSoon = view([on('resetSoon')])[0];
    const record = closeBanner({}, resetSoon);
    assert.deepEqual(view([on('resetSoon')], { closed: record }), [], 'hidden with the slots it was closed with');
    assert.notEqual(view([on('resetSoon', { time: T })])[0].signature, resetSoon.signature, 'a slot changes the signature');
    assert.deepEqual(ids(view([on('resetSoon', { time: T })], { closed: record })), ['resetSoon'], 'it returns with changed slots');
  });

  it('shows it again when the condition clears and starts again, because the clear drops the record', () => {
    const first = view([on('resetSoon')])[0];
    let closed = closeBanner({}, first);
    const active = (payloads) => activeBanners(input(payloads), format);
    assert.equal(retainClosed(closed, active([on('resetSoon')])), closed, 'the record stays while the condition holds');
    closed = retainClosed(closed, active([off('resetSoon')]));
    assert.deepEqual(closed, {}, 'the clear dropped it');
    assert.deepEqual(ids(view([on('resetSoon')], { closed })), ['resetSoon'], 'and it starts again, shown');
  });

  it('drops the record when the slots change, so a change back does not hide it again', () => {
    const plain = view([on('resetSoon')])[0];
    let closed = closeBanner({}, plain);
    closed = retainClosed(closed, activeBanners(input([on('resetSoon', { time: T })]), format));
    assert.deepEqual(closed, {});
    assert.deepEqual(ids(view([on('resetSoon')], { closed })), ['resetSoon']);
  });

  it('remembers only a banner that can be closed, and keeps the other records as they are', () => {
    const key = view([on('noModelKey')])[0];
    assert.deepEqual(closeBanner({}, key), {}, 'noModelKey cannot be closed');
    const reconnecting = view([], { own: ['reconnecting'] })[0];
    const closed = closeBanner(closeBanner({}, reconnecting), resetSoon());
    assert.deepEqual(Object.keys(closed).sort(), ['reconnecting', 'resetSoon']);
    assert.deepEqual(ids(view([on('resetSoon')], { own: ['reconnecting'], closed })), []);
    const kept = retainClosed(closed, activeBanners(input([on('resetSoon')], { own: ['reconnecting'] }), format));
    assert.deepEqual(kept, closed, 'both conditions hold: both records stay');
    assert.deepEqual(retainClosed(closed, activeBanners(input([on('resetSoon')]), format)), { resetSoon: closed.resetSoon }, 'Reconnecting cleared: its record goes');
  });

  it('does not change the records it was given', () => {
    const before = Object.freeze({ resetSoon: 'resetSoon|[null,null,null]' });
    assert.deepEqual(closeBanner(before, view([], { own: ['reconnecting'] })[0]).resetSoon, before.resetSoon);
    assert.deepEqual(retainClosed(before, []), {});
    assert.deepEqual({ ...before }, { resetSoon: 'resetSoon|[null,null,null]' });
  });
});
