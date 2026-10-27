// Tests the incident card's view model (src/app/incidents/incident-view.ts): the texts of the matrix written out, the state chip and
// the bar by state (and the open variants), the compact closed card, the headline (count-of-one and absent nouns, an unreadable
// time), the "more since the notice" line, the cause and fix sentences, the evidence line, the fixing line and its count, the
// footer's decision, the Show details panel (its rows, the held note, the served links), the parts that a snapshot payload lacks, and
// the announcement table. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable
// syntax and imports only types. The times come from the real page-time.ts with named zones.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'incidents', 'incident-view.ts');
const { INCIDENT_TEXTS, announcementOf, categoryText, incidentView, stateText } = await import(pathToFileURL(source).href);
const { messageTime, pageWhen, pageWhenBeside } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'page-time.ts')).href);

const NOW = Date.parse('2026-10-22T14:30:00Z');

/** The context of a page in Europe/Berlin on an instance in UTC; onlineDemo adds " ET" to message times. */
function context(over = {}, { onlineDemo = false, browser = 'Europe/Berlin' } = {}) {
  return {
    decisions: [],
    nowMs: NOW,
    messageTime: (iso, now) => messageTime(iso, now, 'UTC', onlineDemo),
    topTime: (iso, now) => pageWhenBeside(iso, now, 'UTC', 'en-GB', browser),
    itemTime: (iso, now) => pageWhen(iso, now, 'en-GB', browser),
    ...over,
  };
}

const DECISION = { ref: 'D1', outcome: 'act', confidence: 0.94, costUSD: 0.0006, reasons: ['zz reason'] };

/** An awaiting-approval incident with every field, as the fixture of the matrix. */
const full = (over = {}) => ({
  ref: 'I1',
  state: 'awaiting_approval',
  count: 50,
  noticeCount: 50,
  firstAt: '2026-10-22T14:12:00Z',
  lastAt: '2026-10-22T14:13:00Z',
  itemNoun: { one: 'order', other: 'orders' },
  cause: 'The partner changed its date format.',
  fixSummary: 'repair and resend all 50',
  causeCategory: 'data_format_change',
  element: 'order date',
  decisionRef: 'D1',
  groups: [],
  requests: [{ ref: 'A1', state: 'pending' }],
  evidence: {
    sampleHeaderId: 1047,
    sampleError: "Could not parse OrderDate '10/16/2026'",
    items: [{ itemName: 'Order transform', count: 50, firstAt: '2026-10-22T14:12:03Z', lastAt: '2026-10-22T14:12:31Z' }],
  },
  traceTargets: {
    diagnosis: { traceUrl: '/trace/diagnosis' },
    sample: { traceUrl: '/ocutalon/trace/ocuorders/sample' },
    firstFailure: { traceUrl: '/ocutalon/trace/ocuorders/first' },
  },
  ...over,
});

const view = (payload, over, options) => incidentView(payload, context({ decisions: [DECISION], ...over }, options));

describe('a new incident (the matrix\'s first row)', () => {
  const card = view(full());

  it('shows the chip, the top time, the headline, the cause, the evidence line and the fix, each with the exact text', () => {
    assert.equal(card.stateText, 'Awaiting approval');
    assert.equal(card.chip, 'awaiting-approval');
    assert.equal(card.time, '16:13 CEST', 'the page time of lastAt in the browser zone, named because its offset differs');
    assert.equal(card.headline, '50 orders failed since 14:12');
    assert.equal(card.causeSentence, 'The partner changed its date format.');
    assert.equal(card.evidenceLine, 'Data format change \u00B7 order date \u00B7 50 failures grouped into this incident');
    assert.equal(card.fixSentence, 'I can repair and resend all 50.');
    assert.equal(card.more, '');
    assert.equal(card.fixingLine, '');
    assert.equal(card.bar, 'attention');
    assert.equal(card.compact, false);
    assert.equal(card.fallback, false);
    assert.equal(card.key, 'incident:I1');
  });

  it('has no final period on the headline, and the fix never ends in the message\'s "Approve?"', () => {
    assert.ok(!card.headline.endsWith('.'));
    assert.ok(!view(full({ count: 1 })).headline.endsWith('.'));
    assert.equal(view(full({ fixSummary: 'repair and resend all 50. Approve?' })).fixSentence, 'I can repair and resend all 50.');
    assert.equal(view(full({ fixSummary: 'repair and resend all 50 Approve?' })).fixSentence, 'I can repair and resend all 50.');
    assert.ok(!card.fixSentence.includes('Approve?'));
  });

  it('has the footer\'s strip with the decision\'s own cost and the diagnosis trace link', () => {
    assert.equal(card.strip.decision, DECISION);
    assert.equal(card.strip.cost, 0.0006);
    assert.equal(card.strip.fallbackReason, undefined);
    assert.equal(card.diagnosisUrl, '/trace/diagnosis');
  });

  it('writes the headline\'s time as a message time and with " ET" on the online demo', () => {
    assert.equal(view(full(), {}, { onlineDemo: true }).headline, '50 orders failed since 14:12 ET');
  });
});

describe('the state chip and the bar', () => {
  const bars = [
    ['open', 'Open', 'attention'],
    ['awaiting_approval', 'Awaiting approval', 'attention'],
    ['fixing', 'Fixing', 'fixing'],
    ['resolved', 'Resolved', 'resolved'],
    ['closed', 'Closed', 'closed'],
  ];
  for (const [state, text, bar] of bars) {
    it(`shows ${text} and the ${bar} bar for ${state}`, () => {
      const card = view(full({ state }));
      assert.equal(card.stateText, text);
      assert.equal(card.bar, bar);
      assert.equal(stateText(state), text);
    });
  }

  it('keeps the attention bar and the Open chip for every open variant, and the Fallback flag only for a fallback', () => {
    for (const openVariant of ['rejected', 'expired', 'fallback', 'no_fix']) {
      const card = view(full({ state: 'open', openVariant }));
      assert.equal(card.bar, 'attention', openVariant);
      assert.equal(card.stateText, 'Open', openVariant);
      assert.equal(card.fallback, false, openVariant);
    }
    const fallback = view(full({ state: 'open', openVariant: 'fallback', fallback: true, fallbackReason: 'no_key' }));
    assert.equal(fallback.fallback, true);
    assert.equal(fallback.strip.fallbackReason, 'no_key', 'the strip is a fallback strip with the incident\'s reason');
    assert.equal(view(full({ fallback: true })).strip.fallbackReason, '', 'a fallback with no reason');
  });

  it('shows no chip and the attention bar for a state the page does not know, and still renders the rest', () => {
    for (const state of ['mystery', '', undefined, 'toString', '__proto__']) {
      const card = view(full({ state }));
      assert.equal(card.stateText, undefined, String(state));
      assert.equal(card.chip, undefined, String(state));
      assert.equal(card.bar, 'attention', String(state));
      assert.equal(card.headline, '50 orders failed since 14:12', String(state));
      assert.equal(card.compact, false);
    }
  });

  it('ignores an open variant it does not know (the fixture\'s "fix")', () => {
    const card = view(full({ state: 'open', openVariant: 'fix' }));
    assert.equal(card.stateText, 'Open');
    assert.equal(card.bar, 'attention');
  });
});

describe('the same ref again: count and fixing', () => {
  const second = full({
    count: 52,
    noticeCount: 50,
    state: 'fixing',
    requests: [{ ref: 'A1', state: 'executing', result: { total: 50 } }],
  });

  it('reads 52, adds "2 more since the notice", the Fixing chip, the fixing bar and "Repairing and resending 50 orders\u2026"', () => {
    const card = view(second);
    assert.equal(card.headline, '52 orders failed since 14:12');
    assert.equal(card.more, '2 more since the notice');
    assert.equal(card.stateText, 'Fixing');
    assert.equal(card.bar, 'fixing');
    assert.equal(card.fixingLine, 'Repairing and resending 50 orders\u2026');
    assert.equal(card.evidenceLine, 'Data format change \u00B7 order date \u00B7 52 failures grouped into this incident');
  });

  it('takes the fixing count from the first executing request with a total, else noticeCount, else count', () => {
    const two = view(full({ state: 'fixing', requests: [{ state: 'pending' }, { state: 'executing' }, { state: 'executing', result: { total: 7 } }, { state: 'executing', result: { total: 9 } }] }));
    assert.equal(two.fixingLine, 'Repairing and resending 7 orders\u2026');
    assert.equal(view(full({ state: 'fixing', count: 52, noticeCount: 50, requests: [] })).fixingLine, 'Repairing and resending 50 orders\u2026');
    assert.equal(view(full({ state: 'fixing', count: 52, noticeCount: undefined, requests: undefined })).fixingLine, 'Repairing and resending 52 orders\u2026');
    assert.equal(view(full({ state: 'fixing', requests: [{ state: 'executing', result: { total: 1 } }] })).fixingLine, 'Repairing and resending 1 order\u2026', 'count of one');
  });

  it('shows the fixing line only while the state is fixing', () => {
    for (const state of ['open', 'awaiting_approval', 'resolved', 'closed']) {
      assert.equal(view(full({ state, requests: [{ state: 'executing', result: { total: 50 } }] })).fixingLine, '', state);
    }
  });

  it('shows "more" only when count is above noticeCount and both are present', () => {
    assert.equal(view(full({ count: 52, noticeCount: 50 })).more, '2 more since the notice');
    assert.equal(view(full({ count: 51, noticeCount: 50 })).more, '1 more since the notice');
    assert.equal(view(full({ count: 50, noticeCount: 50 })).more, '');
    assert.equal(view(full({ count: 48, noticeCount: 50 })).more, '', 'count below noticeCount is not "-2 more"');
    assert.equal(view(full({ count: 52, noticeCount: undefined })).more, '');
    assert.equal(view(full({ count: undefined, noticeCount: 50 })).more, '');
  });
});

describe('resolved, then closed', () => {
  it('keeps the whole card with the success bar when resolved', () => {
    const card = view(full({ state: 'resolved', requests: [{ state: 'executed', result: { total: 50 } }] }));
    assert.equal(card.bar, 'resolved');
    assert.equal(card.compact, false);
    assert.equal(card.causeSentence, 'The partner changed its date format.');
    assert.notEqual(card.strip, undefined);
  });

  it('compacts a closed card to the chip row, the headline and Show details: no cause, evidence line, fix, more, fixing line or footer', () => {
    const card = view(full({ state: 'closed', count: 52, noticeCount: 50 }));
    assert.equal(card.compact, true);
    assert.equal(card.bar, 'closed');
    assert.equal(card.stateText, 'Closed');
    assert.equal(card.headline, '52 orders failed since 14:12');
    assert.deepEqual([card.causeSentence, card.evidenceLine, card.fixSentence, card.more, card.fixingLine], ['', '', '', '', '']);
    assert.equal(card.strip, undefined);
    assert.equal(card.diagnosisUrl, undefined);
    assert.notEqual(card.panel, undefined, 'Show details stays while the panel has rows');
    assert.equal(card.time, '16:13 CEST');
  });

  it('keeps the Fallback flag of a closed fallback incident and has no Show details when the panel has no row', () => {
    const card = view({ ref: 'I9', state: 'closed', count: 3, firstAt: '2026-10-22T14:12:00Z', fallback: true });
    assert.equal(card.compact, true);
    assert.equal(card.fallback, true);
    assert.equal(card.panel, undefined);
  });
});

describe('the evidence line', () => {
  it('is left out when neither the category nor the element is set, as on a fallback', () => {
    assert.equal(view(full({ causeCategory: '', element: '' })).evidenceLine, '');
    assert.equal(view(full({ causeCategory: undefined, element: undefined })).evidenceLine, '');
    assert.equal(view(full({ causeCategory: '  ', element: ' ' })).evidenceLine, '');
  });

  it('joins what is set: the category alone, the element alone, with or without the grouping', () => {
    assert.equal(view(full({ element: '' })).evidenceLine, 'Data format change \u00B7 50 failures grouped into this incident');
    assert.equal(view(full({ causeCategory: '' })).evidenceLine, 'order date \u00B7 50 failures grouped into this incident');
    assert.equal(view(full({ count: undefined })).evidenceLine, 'Data format change \u00B7 order date');
  });

  it('says "1 failure grouped into this incident" for a count of one', () => {
    assert.equal(view(full({ count: 1, noticeCount: 1 })).evidenceLine, 'Data format change \u00B7 order date \u00B7 1 failure grouped into this incident');
  });

  it('humanizes a snake_case category and renders an unknown one the same way', () => {
    assert.equal(categoryText('data_format_change'), 'Data format change');
    assert.equal(categoryText('brand_new__kind'), 'Brand new kind');
    assert.equal(categoryText('X'), 'X');
    assert.equal(categoryText(''), '');
    assert.equal(categoryText(undefined), '');
    assert.equal(view(full({ causeCategory: 'something_new' })).evidenceLine.startsWith('Something new \u00B7 order date'), true);
  });
});

describe('the headline', () => {
  it('uses the noun\'s one form for a count of one and its other form otherwise', () => {
    assert.equal(view(full({ count: 1, noticeCount: 1 })).headline, '1 order failed since 14:12');
    assert.equal(view(full({ count: 2 })).headline, '2 orders failed since 14:12');
    assert.equal(view(full({ count: 0, noticeCount: 0 })).headline, '0 orders failed since 14:12');
  });

  it('uses "message" and "messages" when there is no item noun, or the noun lacks the form', () => {
    assert.equal(view(full({ itemNoun: undefined })).headline, '50 messages failed since 14:12');
    assert.equal(view(full({ itemNoun: undefined, count: 1 })).headline, '1 message failed since 14:12');
    assert.equal(view(full({ itemNoun: {} })).headline, '50 messages failed since 14:12');
    assert.equal(view(full({ itemNoun: { one: 'order' }, count: 5 })).headline, '5 messages failed since 14:12');
    assert.equal(view(full({ itemNoun: undefined, state: 'fixing', requests: [] })).fixingLine, 'Repairing and resending 50 messages\u2026');
  });

  it('writes the dated forms of the message time for other days', () => {
    assert.equal(view(full({ firstAt: '2026-10-21T14:12:00Z' })).headline, '50 orders failed since Wednesday at 14:12');
    assert.equal(view(full({ firstAt: '2026-10-09T14:12:00Z' })).headline, '50 orders failed since Oct 9 at 14:12');
    assert.equal(view(full({ firstAt: '2025-12-30T10:00:00Z' })).headline, '50 orders failed since Dec 30, 2025 at 10:00');
  });

  it('leaves the time out, never "Invalid Date", when firstAt is absent or unreadable', () => {
    for (const firstAt of [undefined, '', 'not a time']) {
      const card = view(full({ firstAt }));
      assert.equal(card.headline, '50 orders failed', String(firstAt));
      assert.ok(!card.headline.includes('Invalid'));
    }
  });

  it('shows no top time, never "Invalid Date", when lastAt is absent or unreadable', () => {
    for (const lastAt of [undefined, '', 'not a time']) {
      assert.equal(view(full({ lastAt })).time, '', String(lastAt));
    }
  });

  it('puts the day in the top time when it is not today, and names the browser zone only when its offset differs', () => {
    assert.equal(view(full({ lastAt: '2026-10-21T14:13:00Z' })).time, 'Wednesday at 16:13 CEST');
    assert.equal(view(full(), {}, { browser: 'UTC' }).time, '14:13');
  });
});

describe('the cause and fix sentences', () => {
  it('trim, drop one final period and add one', () => {
    assert.equal(view(full({ cause: '  The partner changed its date format  ' })).causeSentence, 'The partner changed its date format.');
    assert.equal(view(full({ cause: 'Ends twice..' })).causeSentence, 'Ends twice..');
    assert.equal(view(full({ fixSummary: ' repair and resend all 50. ' })).fixSentence, 'I can repair and resend all 50.');
  });

  it('are left out when absent or empty', () => {
    for (const value of [undefined, '', '   ', '.']) {
      assert.equal(view(full({ cause: value, fixSummary: value })).causeSentence, '', String(value));
      assert.equal(view(full({ cause: value, fixSummary: value })).fixSentence, '', String(value));
    }
  });

  it('keep the text as it is: markup is not touched here (the components bind it as text)', () => {
    assert.equal(view(full({ cause: '<b>x</b> & y' })).causeSentence, '<b>x</b> & y.');
  });
});

describe('the footer', () => {
  it('shows the diagnosis trace link alone when the store holds no such decision: no strip', () => {
    const card = view(full(), { decisions: [{ ...DECISION, ref: 'other' }] });
    assert.equal(card.strip, undefined);
    assert.equal(card.diagnosisUrl, '/trace/diagnosis');
  });

  it('has no footer when there is neither a decision nor a served diagnosis URL, or no decisionRef', () => {
    const card = view(full({ traceTargets: undefined }), { decisions: [] });
    assert.deepEqual([card.strip, card.diagnosisUrl], [undefined, undefined]);
    assert.equal(view(full({ decisionRef: undefined })).strip, undefined);
    assert.equal(view(full({ decisionRef: '' }), { decisions: [{ ...DECISION, ref: '' }] }).strip, undefined);
  });

  it('reads the decision by its ref among the store\'s, and takes the trace URL only as served', () => {
    const other = { ...DECISION, ref: 'D2', costUSD: 0.5 };
    const card = view(full({ decisionRef: 'D2' }), { decisions: [DECISION, other] });
    assert.equal(card.strip.decision, other);
    assert.equal(card.strip.cost, 0.5);
    assert.equal(view(full({ traceTargets: { diagnosis: { traceHeaderId: 4, traceNamespace: 'OCUTALON' } } })).diagnosisUrl, undefined, 'a header id alone makes no URL');
  });
});

describe('the Show details panel', () => {
  const panel = view(full()).panel;

  it('holds the rows of the matrix in order: cause, sample, error, failures by item, the held note and the two links', () => {
    assert.deepEqual(panel.rows, [
      { label: 'Cause', lines: ['Data format change \u00B7 order date'], mono: false },
      { label: 'Sample failed message', lines: ['1047'], mono: true },
      { label: 'Error', lines: ["Could not parse OrderDate '10/16/2026'"], mono: true },
      { label: 'Failures by item', lines: ['Order transform: 50 failures, first 16:12, last 16:12'], mono: true },
    ]);
    assert.equal(panel.held, true);
    assert.deepEqual(panel.links, [
      { text: 'Sample message', url: '/ocutalon/trace/ocuorders/sample' },
      { text: 'First failure', url: '/ocutalon/trace/ocuorders/first' },
    ]);
  });

  it('writes one line per item: one failure with its one time, more with the first and last, times as page times with their day', () => {
    const items = [
      { itemName: 'Order transform', count: 1, firstAt: '2026-10-22T14:12:03Z', lastAt: '2026-10-22T14:12:03Z' },
      { itemName: 'Order router', count: 3, firstAt: '2026-10-21T14:12:04Z', lastAt: '2026-10-22T14:14:05Z' },
      { itemName: 'Order sender', count: 1, firstAt: '2026-10-21T09:30:00Z', lastAt: '2026-10-21T09:30:00Z' },
    ];
    const lines = view(full({ evidence: { items } })).panel.rows.find((row) => row.label === 'Failures by item').lines;
    assert.deepEqual(lines, [
      'Order transform: 1 failure, at 16:12',
      'Order router: 3 failures, first Wednesday at 16:12, last 16:14',
      'Order sender: 1 failure, at Wednesday at 11:30',
    ]);
  });

  it('shows "Held as an IRIS Workflow task until someone answers." only while some request is pending', () => {
    assert.equal(INCIDENT_TEXTS.held, 'Held as an IRIS Workflow task until someone answers.');
    assert.equal(view(full({ requests: [{ state: 'executed' }, { state: 'pending' }] })).panel.held, true);
    for (const requests of [[{ state: 'approved' }], [{ state: 'executing' }], [{ state: 'rejected' }, { state: 'expired' }], [], undefined]) {
      assert.equal(view(full({ requests })).panel.held, false, JSON.stringify(requests));
    }
  });

  it('leaves out a row with no data, and has no panel with no row at all (no Show details)', () => {
    const lean = view(full({ causeCategory: '', element: '', requests: [], evidence: { sampleError: 'boom' }, traceTargets: undefined })).panel;
    assert.deepEqual(lean.rows.map((row) => row.label), ['Error']);
    assert.deepEqual([lean.held, lean.links], [false, []]);
    assert.equal(view(full({ causeCategory: '', element: '', requests: [], evidence: undefined, traceTargets: undefined })).panel, undefined);
    assert.equal(view(full({ causeCategory: '', element: '', requests: [], evidence: { sampleHeaderId: 0, sampleError: '', items: [] }, traceTargets: {} })).panel, undefined);
  });

  it('counts the held note and a served link as rows of the panel on their own', () => {
    const bare = { ref: 'I2', state: 'awaiting_approval', requests: [{ state: 'pending' }] };
    assert.equal(view(bare).panel.held, true);
    const linked = view({ ref: 'I3', traceTargets: { sample: { traceUrl: '/s' } } }).panel;
    assert.deepEqual(linked.links, [{ text: 'Sample message', url: '/s' }]);
  });

  it('keeps raw values as published, and takes the links only as served', () => {
    const card = view(full({ evidence: { sampleError: '<img src=x onerror=alert(1)>' }, traceTargets: { sample: { traceHeaderId: 1, traceNamespace: 'OCUORDERS' } } }));
    assert.deepEqual(card.panel.rows.find((row) => row.label === 'Error').lines, ['<img src=x onerror=alert(1)>']);
    assert.deepEqual(card.panel.links, []);
  });
});

describe('a payload without parts (a snapshot, or something unexpected)', () => {
  const row = { ref: 'I5', state: 'open', count: 50, noticeCount: 50, firstAt: '2026-10-22T14:12:00Z', lastAt: '2026-10-22T14:13:00Z', cause: 'Because.', causeCategory: 'data_format_change' };

  it('renders the row-backed fields and leaves out every part that its fields would feed', () => {
    const card = view(row);
    assert.equal(card.headline, '50 messages failed since 14:12');
    assert.equal(card.causeSentence, 'Because.');
    assert.equal(card.evidenceLine, 'Data format change \u00B7 50 failures grouped into this incident');
    assert.equal(card.fixSentence, '');
    assert.equal(card.fixingLine, '');
    assert.equal(card.strip, undefined);
    assert.equal(card.diagnosisUrl, undefined);
    assert.deepEqual(card.panel, { rows: [{ label: 'Cause', lines: ['Data format change'], mono: false }], held: false, links: [] });
  });

  it('renders an empty payload without throwing', () => {
    const card = view({});
    assert.equal(card.key, 'incident:');
    assert.equal(card.headline, '0 messages failed');
    assert.equal(card.bar, 'attention');
    assert.equal(card.panel, undefined);
    assert.equal(card.time, '');
  });

  it('does not throw when a part is null, of another type, or holds odd entries', () => {
    const odd = { ref: 'I6', state: 'fixing', requests: [null, 5, {}, { state: 'executing', result: null }], evidence: { items: [null, 7, 'x', {}] }, traceTargets: { diagnosis: null, sample: 3 }, itemNoun: null, groups: 'no' };
    const card = view(odd);
    assert.equal(card.fixingLine, 'Repairing and resending 0 messages\u2026');
    assert.deepEqual(card.panel.rows.map((row) => row.label), ['Failures by item']);
    const notArrays = view({ ref: 'I7', requests: 'x', evidence: { items: 'y' } });
    assert.equal(notArrays.panel, undefined);
  });
});

describe('the announcements', () => {
  const HEAD = '50 orders failed since 14:12';
  const say = (previous, over = {}) => announcementOf(previous, full(over), HEAD);

  it('says "Incident: {headline}. Approval needed." at first sight of an incident awaiting approval', () => {
    assert.equal(say(undefined), 'Incident: 50 orders failed since 14:12. Approval needed.');
  });

  it('says "\u2026 No fix proposed." at first sight of a fallback, a fallback or no-fix variant', () => {
    const none = 'Incident: 50 orders failed since 14:12. No fix proposed.';
    assert.equal(say(undefined, { state: 'open', fallback: true }), none);
    assert.equal(say(undefined, { state: 'open', openVariant: 'fallback' }), none);
    assert.equal(say(undefined, { state: 'open', openVariant: 'no_fix' }), none);
  });

  it('says the state at first sight of any other incident, so that none claims an approval that does not exist', () => {
    assert.equal(say(undefined, { state: 'open', openVariant: 'rejected' }), 'Incident: 50 orders failed since 14:12. Open.');
    assert.equal(say(undefined, { state: 'open', openVariant: 'expired' }), 'Incident: 50 orders failed since 14:12. Open.');
    assert.equal(say(undefined, { state: 'fixing' }), 'Incident: 50 orders failed since 14:12. Fixing.');
    assert.equal(say(undefined, { state: 'resolved' }), 'Incident: 50 orders failed since 14:12. Resolved.');
    assert.equal(say(undefined, { state: 'closed' }), 'Incident: 50 orders failed since 14:12. Closed.');
  });

  it('says the new state once when the state of a known incident changes', () => {
    assert.equal(say('awaiting_approval', { state: 'fixing' }), 'Incident: 50 orders failed since 14:12. Fixing.');
    assert.equal(say('fixing', { state: 'resolved' }), 'Incident: 50 orders failed since 14:12. Resolved.');
    assert.equal(say('resolved', { state: 'closed' }), 'Incident: 50 orders failed since 14:12. Closed.');
    assert.equal(say('awaiting_approval', { state: 'open', openVariant: 'rejected' }), 'Incident: 50 orders failed since 14:12. Open.');
    assert.equal(say('open', { state: 'awaiting_approval' }), 'Incident: 50 orders failed since 14:12. Awaiting approval.', 'a later request: the state\'s own form');
  });

  it('says nothing for a count-only change or an unchanged update of a known incident', () => {
    assert.equal(say('awaiting_approval', { count: 52 }), undefined);
    assert.equal(say('awaiting_approval'), undefined);
    assert.equal(say('open', { state: 'open', fallback: true }), undefined, 'a known fallback incident is not announced again');
    assert.equal(say('', { state: undefined }), undefined);
  });

  it('says nothing for a state the page does not know, at first sight or on a change', () => {
    assert.equal(say(undefined, { state: 'mystery' }), undefined);
    assert.equal(say('open', { state: 'mystery' }), undefined);
    assert.equal(say('open', { state: undefined }), undefined);
  });

  it('holds the texts written out', () => {
    assert.equal(INCIDENT_TEXTS.announceApproval, 'Incident: {headline}. Approval needed.');
    assert.equal(INCIDENT_TEXTS.announceNoFix, 'Incident: {headline}. No fix proposed.');
    assert.equal(INCIDENT_TEXTS.announceState, 'Incident: {headline}. {state}.');
  });
});

describe('the fixed strings', () => {
  it('are the texts of the matrix and the design notes, written out', () => {
    assert.deepEqual(
      { ...INCIDENT_TEXTS },
      {
        stateOpen: 'Open',
        stateAwaitingApproval: 'Awaiting approval',
        stateFixing: 'Fixing',
        stateResolved: 'Resolved',
        stateClosed: 'Closed',
        headline: '{count} {noun} failed since {time}',
        headlineNoTime: '{count} {noun} failed',
        more: '{n} more since the notice',
        grouped: '{count} failures grouped into this incident',
        groupedOne: '1 failure grouped into this incident',
        fix: 'I can {fixSummary}.',
        fixing: 'Repairing and resending {count} {noun}\u2026',
        showDetails: 'Show details',
        nounOne: 'message',
        nounOther: 'messages',
        separator: ' \u00B7 ',
        labelCause: 'Cause',
        labelSample: 'Sample failed message',
        labelError: 'Error',
        labelItems: 'Failures by item',
        itemLine: '{item}: {count} failures, first {first}, last {last}',
        itemLineOne: '{item}: 1 failure, at {time}',
        held: 'Held as an IRIS Workflow task until someone answers.',
        linkSample: 'Sample message',
        linkFirstFailure: 'First failure',
        announceApproval: 'Incident: {headline}. Approval needed.',
        announceNoFix: 'Incident: {headline}. No fix proposed.',
        announceState: 'Incident: {headline}. {state}.',
      },
    );
  });
});

describe('the module', () => {
  it('imports only types, keeps to erasable syntax and writes its non-ASCII characters as escapes', () => {
    const text = readFileSync(source, 'utf8');
    assert.doesNotMatch(text, /^import (?!type )/m, 'type-only imports');
    assert.doesNotMatch(text, /\benum\b|\bnamespace\b|constructor\(\s*(?:public|private|protected|readonly)/, 'erasable syntax');
    assert.doesNotMatch(text, /[^\x00-\x7F]/, 'ASCII');
  });
});
