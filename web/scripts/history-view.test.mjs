// Tests the History page's view rules (src/app/history/history-view.ts; Story 25.2): the fixed strings against the ruled PUBLIC TEXT, the address (what
// paramsOf reads and queryOf writes, the invalid values dropped, the round trip), the filters' options, and the empty, pager, times and summary texts.
// The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports only types; the shared labels
// come from chat-view.ts and usage-view.ts, as the page passes them.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const {
  CHANNELS,
  FALLBACKS,
  HISTORY_TABS,
  HISTORY_TEXTS,
  MAX_PAGE,
  OUTCOMES,
  PARAMS,
  channelOptions,
  cleared,
  emptyText,
  fallbackOptions,
  filtered,
  incidentTimes,
  isCanonical,
  isDay,
  mergeQueryOf,
  noSummaryText,
  otherTab,
  outcomeOptions,
  pageOf,
  pageText,
  paramsOf,
  queryOf,
  summaryLines,
} = await import(app('history', 'history-view.ts'));
const { CHAT_TEXTS } = await import(app('chat', 'chat-view.ts'));
const { USAGE_TEXTS } = await import(app('usage', 'usage-view.ts'));

/** A queryParamMap-like of the object. */
const map = (values) => ({ get: (name) => (Object.hasOwn(values, name) ? values[name] : null) });
const NONE = { tab: 'decisions', outcome: '', channel: '', day: '', fallback: '', page: 1 };
const OUTCOME_LABELS = { ignore: CHAT_TEXTS.chipIgnore, digest: CHAT_TEXTS.chipDigest, tellnow: CHAT_TEXTS.chipTellNow, act: CHAT_TEXTS.chipAct };

describe('the fixed strings', () => {
  it('are the ruled PUBLIC TEXT, exactly', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(HISTORY_TEXTS)), {
      title: 'History \u00B7 OcuTalon',
      heading: 'History',
      tabDecisions: 'Decisions',
      tabIncidents: 'Incidents',
      outcome: 'Outcome',
      channel: 'Channel',
      date: 'Date',
      fallback: 'Fallback',
      anyOutcome: 'Any outcome',
      anyChannel: 'Any channel',
      fallbackAll: 'All decisions',
      fallbackOnly: 'Fallback only',
      fallbackNone: 'Without fallback',
      clear: 'Clear filters',
      noticed: 'Noticed {time}',
      closed: 'Closed {time}',
      noSummaryOpen: 'No summary yet. OcuTalon writes one when the incident closes.',
      noSummaryClosed: 'No summary was written for this incident.',
      previous: 'Previous page',
      next: 'Next page',
      pageOf: 'Page {page} of {pages}',
      decisionPages: 'Decision pages',
      incidentPages: 'Incident pages',
      emptyFiltered: 'No decisions match these filters.',
      emptyDecisions: 'No decisions yet.',
      emptyIncidents: 'No incidents yet.',
      error: "Couldn't load your history.",
      retry: 'Retry',
    });
  });

  it('use ASCII except the middle dot of the title', () => {
    for (const char of JSON.stringify(HISTORY_TEXTS).replace('\u00B7', '')) {
      assert.ok(char.charCodeAt(0) < 128, `${JSON.stringify(char)} is ASCII`);
    }
  });
});

describe('the values', () => {
  it('are the route\'s: the outcomes and channels in the enums\' order, and the two fallback values', () => {
    assert.deepEqual([...OUTCOMES], ['ignore', 'digest', 'tellnow', 'act']);
    assert.deepEqual([...CHANNELS], ['web', 'phone', 'mailbox', 'telegram', 'email', 'webhook', 'slack', 'system', 'heartbeat']);
    assert.deepEqual([...FALLBACKS], ['yes', 'no']);
    assert.deepEqual([...HISTORY_TABS], ['decisions', 'incidents']);
    assert.equal(MAX_PAGE, 9999);
  });

  it('give every channel the ruled label of the Usage page, and every outcome the chip\'s word', () => {
    const options = channelOptions(USAGE_TEXTS.channels);
    assert.deepEqual(options.map((one) => one.value), ['', ...CHANNELS]);
    assert.deepEqual(options.map((one) => one.label), ['Any channel', 'Web chat', 'Simulated phone', 'Simulated mailbox', 'Telegram', 'Email', 'Webhook', 'Slack', 'System', 'Heartbeat']);
    assert.deepEqual(outcomeOptions(OUTCOME_LABELS).map((one) => [one.value, one.label]), [['', 'Any outcome'], ['ignore', 'Ignore'], ['digest', 'Digest'], ['tellnow', 'Tell now'], ['act', 'Act']]);
    assert.deepEqual(fallbackOptions().map((one) => [one.value, one.label]), [['', 'All decisions'], ['yes', 'Fallback only'], ['no', 'Without fallback']]);
  });

  it('keep a value that has no label as it is', () => {
    assert.equal(channelOptions({}).at(1)?.label, 'web');
  });
});

describe('the address', () => {
  it('reads no parameter as the first page of the Decisions tab with no filter', () => {
    assert.deepEqual(paramsOf(map({})), NONE);
    assert.equal(isCanonical(map({})), true);
  });

  it('reads every valid value', () => {
    assert.deepEqual(paramsOf(map({ tab: 'incidents', outcome: 'tellnow', channel: 'mailbox', day: '2026-11-10', fallback: 'yes', page: '12' })), {
      tab: 'incidents',
      outcome: 'tellnow',
      channel: 'mailbox',
      day: '2026-11-10',
      fallback: 'yes',
      page: 12,
    });
  });

  it('drops every value that the server would not take', () => {
    const bad = { tab: 'decisions', outcome: 'Act', channel: 'x', day: '2026-13-01', fallback: '1', page: '01' };
    assert.deepEqual(paramsOf(map(bad)), NONE);
    assert.equal(isCanonical(map(bad)), false);
    for (const outcome of ['foo', '', 'ACT', 'tell now', 'act,ignore']) assert.equal(paramsOf(map({ outcome })).outcome, '', `outcome ${outcome}`);
    for (const channel of ['x', '', 'Web', 'web,phone']) assert.equal(paramsOf(map({ channel })).channel, '', `channel ${channel}`);
    for (const fallback of ['1', '0', '', 'Yes', 'true']) assert.equal(paramsOf(map({ fallback })).fallback, '', `fallback ${fallback}`);
    for (const day of ['2026-13-01', '2026-02-30', '2025-02-29', '11/10/2026', '', '2026-1-1', '20261110', '2026-11-10T00:00', 'today']) assert.equal(paramsOf(map({ day })).day, '', `day ${day}`);
    for (const page of ['0', '01', 'abc', '10000', '', '-1', '1.5', '+1', '1e1', ' 1']) assert.equal(paramsOf(map({ page })).page, 1, `page ${page}`);
    assert.equal(paramsOf(map({ tab: 'other' })).tab, 'decisions');
  });

  it('knows the days of the calendar, leap years included', () => {
    for (const day of ['2026-11-10', '2024-02-29', '2000-02-29', '2026-12-31', '2026-01-01']) assert.equal(isDay(day), true, day);
    for (const day of ['2025-02-29', '1900-02-29', '2026-04-31', '2026-00-10', '2026-11-00', '0000-01-01']) assert.equal(isDay(day), false, day);
  });

  it('takes no day before 1841, which the server cannot read: the years that a typed year passes through are not days', () => {
    assert.equal(isDay('1841-01-01'), true);
    for (const day of ['1840-12-31', '1800-01-01', '0002-11-10', '0020-11-10', '0202-11-10']) assert.equal(isDay(day), false, day);
    assert.equal(paramsOf(map({ day: '1800-01-01' })).day, '', 'an address with such a day is cleaned');
  });

  it('reads page as digits with no leading zero, 1 to 9999', () => {
    assert.deepEqual(['1', '2', '25', '9999'].map(pageOf), [1, 2, 25, 9999]);
    assert.deepEqual([null, '0', '00', '09', '10000', 'x'].map(pageOf), [1, 1, 1, 1, 1, 1]);
  });

  it('writes only the values that are set: tab only for incidents, page only above 1', () => {
    assert.deepEqual(queryOf(NONE), {});
    assert.deepEqual(queryOf({ ...NONE, page: 1 }), {});
    assert.deepEqual(queryOf({ ...NONE, page: 2 }), { page: '2' });
    assert.deepEqual(queryOf({ ...NONE, tab: 'incidents' }), { tab: 'incidents' });
    assert.deepEqual(queryOf({ tab: 'decisions', outcome: 'act', channel: 'mailbox', day: '2026-11-10', fallback: 'no', page: 3 }), {
      outcome: 'act',
      channel: 'mailbox',
      day: '2026-11-10',
      fallback: 'no',
      page: '3',
    });
  });

  it('round-trips every state that the page can be in', () => {
    const states = [
      NONE,
      { ...NONE, outcome: 'ignore' },
      { ...NONE, channel: 'heartbeat', page: 9999 },
      { ...NONE, day: '2024-02-29', fallback: 'yes' },
      { tab: 'incidents', outcome: 'digest', channel: 'web', day: '2026-11-10', fallback: 'no', page: 2 },
      { ...NONE, tab: 'incidents', page: 4 },
    ];
    for (const state of states) {
      const query = queryOf(state);
      assert.deepEqual(paramsOf(map(query)), state, JSON.stringify(state));
      assert.equal(isCanonical(map(query)), true, JSON.stringify(state));
    }
  });

  it('calls an address canonical only when it holds exactly what queryOf writes', () => {
    assert.equal(isCanonical(map({ page: '1' })), false, 'page 1 is not written');
    assert.equal(isCanonical(map({ tab: 'decisions' })), false, 'tab decisions is not written');
    assert.equal(isCanonical(map({ outcome: 'foo' })), false);
    assert.equal(isCanonical(map({ outcome: 'act', foo: '1' })), true, 'an unknown parameter is ignored');
  });

  it('writes a merge query that removes the parameters that are not set', () => {
    assert.deepEqual(mergeQueryOf(NONE), { tab: null, outcome: null, channel: null, day: null, fallback: null, page: null });
    assert.deepEqual(mergeQueryOf({ ...NONE, outcome: 'act', page: 2 }), { tab: null, outcome: 'act', channel: null, day: null, fallback: null, page: '2' });
    assert.deepEqual(Object.keys(mergeQueryOf(NONE)), [...PARAMS]);
  });

  it('clears the filters and the page, and keeps the tab', () => {
    assert.deepEqual(cleared({ tab: 'decisions', outcome: 'act', channel: 'web', day: '2026-11-10', fallback: 'yes', page: 3 }), NONE);
    assert.equal(filtered(NONE), false);
    for (const one of [{ outcome: 'act' }, { channel: 'web' }, { day: '2026-11-10' }, { fallback: 'no' }]) assert.equal(filtered({ ...NONE, ...one }), true);
    assert.equal(filtered({ ...NONE, page: 3 }), false, 'a page is not a filter');
  });

  it('has the other tab for either arrow key', () => {
    assert.equal(otherTab('decisions'), 'incidents');
    assert.equal(otherTab('incidents'), 'decisions');
  });
});

describe('the texts of the lists', () => {
  it('says why a list is empty', () => {
    assert.equal(emptyText(NONE), 'No decisions yet.');
    assert.equal(emptyText({ ...NONE, page: 2 }), 'No decisions yet.');
    for (const one of [{ outcome: 'act' }, { channel: 'web' }, { day: '2026-11-10' }, { fallback: 'no' }]) assert.equal(emptyText({ ...NONE, ...one }), 'No decisions match these filters.');
    assert.equal(emptyText({ ...NONE, tab: 'incidents' }), 'No incidents yet.');
    assert.equal(emptyText({ ...NONE, tab: 'incidents', outcome: 'act' }), 'No incidents yet.', 'a filter of the Decisions tab does not change the Incidents tab');
  });

  it('writes the pager text', () => {
    assert.equal(pageText(2, 3), 'Page 2 of 3');
    assert.equal(pageText(1, 1), 'Page 1 of 1');
  });

  it('writes the times of an incident row: noticed, and closed once it is', () => {
    const when = (iso) => `at ${iso.slice(11, 16)}`;
    assert.deepEqual(incidentTimes({ noticedAt: '2026-11-10T09:00:00Z', closedAt: '' }, when), ['Noticed at 09:00']);
    assert.deepEqual(incidentTimes({ noticedAt: '2026-11-10T09:00:00Z', closedAt: '2026-11-10T10:30:00Z' }, when), ['Noticed at 09:00', 'Closed at 10:30']);
    assert.deepEqual(incidentTimes({ noticedAt: '2026-11-10T09:00:00Z', closedAt: 'x' }, (iso) => (iso === 'x' ? '' : 'T')), ['Noticed T'], 'a time that cannot be read leaves its part out');
    assert.deepEqual(incidentTimes({ noticedAt: '', closedAt: '' }, when), []);
  });

  it('splits a summary at its line feeds and leaves out an empty line', () => {
    assert.deepEqual(summaryLines('One.\nTwo.\n\n  \nThree.'), ['One.', 'Two.', 'Three.']);
    assert.deepEqual(summaryLines(''), []);
  });

  it('says why an incident has no summary: closed or not', () => {
    assert.equal(noSummaryText('closed'), 'No summary was written for this incident.');
    for (const state of ['open', 'awaiting_approval', 'fixing', 'resolved']) assert.equal(noSummaryText(state), 'No summary yet. OcuTalon writes one when the incident closes.');
  });
});
