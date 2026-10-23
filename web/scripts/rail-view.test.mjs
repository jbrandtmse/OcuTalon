// Tests the status rail's view (src/app/rail/rail-view.ts): the fixed strings against the UX's wording, the order of the sections with
// and without Telegram, the counts and the spoken headings, the filters and sorts of each list (the store keeps everything and the
// view shows what a reload shows), rows that a later event replaces in place or removes, the titles, details and meta lines of every
// kind of row, the empty texts and hints, the README link of the Telegram card, and that a value which names a placeholder is shown as
// typed. The view is given the real page-time, decision-view, chat-view and links modules, each imported as it is, and a stub for the
// catalog's fallback sentences. Every module is imported as it is: Node strips its types, which holds only while it keeps to erasable
// syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { RAIL_TEXTS, TELEGRAM_ANCHOR, approvalTitle, checkTitle, railView, readmeSection } = await import(app('rail', 'rail-view.ts'));
const { countdownText, pageWhen } = await import(app('chat', 'page-time.ts'));
const { DECISION_TEXTS, confidenceText, formatCost, outcomeOf, reasonLines } = await import(app('chat', 'decision-view.ts'));
const { CHAT_TEXTS, NOTICE_TEXTS } = await import(app('chat', 'chat-view.ts'));
const { README_URL } = await import(app('links.ts'));
const { applyEvents, fromSnapshot } = await import(app('live', 'live-store.ts'));

/** Thursday 22 October 2026, 14:13:30 UTC. */
const NOW = Date.parse('2026-10-22T14:13:30Z');

/** The format the component builds, with the browser's zone and locale named, and a stub for the catalog's fallback sentences. */
const format = (now = NOW) => ({
  when: (iso) => pageWhen(iso, now, 'en-GB', 'UTC'),
  countdown: (due) => countdownText(due, now),
  cost: formatCost,
  confidence: confidenceText,
  reasonLines,
  outcome: outcomeOf,
  fallbackSentence: (reason) => (reason === undefined ? undefined : `Zz sentence of ${reason}.`),
  separator: CHAT_TEXTS.separator,
  due: NOTICE_TEXTS.due,
  words: { passed: DECISION_TEXTS.passed, failed: DECISION_TEXTS.failed, notChecked: DECISION_TEXTS.notChecked },
});

const TELEGRAM_OFF = { included: false, state: 'off', botUserName: '', paired: false, displayName: '', pausedUntil: '' };

/** A snapshot with the rail's lists given; the rest is empty. */
const snapshot = (rail = {}, telegram = TELEGRAM_OFF) => ({
  version: '1',
  instanceZone: 'UTC',
  epoch: 'e1',
  streams: { session: 5, instance: 0 },
  chat: [],
  rail: { approvals: [], checks: [], reminders: [], decisions: [], ...rail },
  user: 'zz',
  onlineDemo: false,
  demoMode: false,
  models: { triage: '', diagnosis: '', chat: '' },
  telegram,
  status: [],
});

const viewOf = (rail = {}, telegram = TELEGRAM_OFF, now = NOW) => railView(fromSnapshot(snapshot(rail, telegram)), format(now));
const section = (view, id) => view.sections.find((one) => one.id === id);
const keys = (one) => one.rows.map((row) => row.key);
const titles = (one) => one.rows.map((row) => row.title);

const approval = (ref, over = {}) => ({
  ref,
  kind: 'fix',
  state: 'pending',
  incidentRef: 'inc1',
  dryRun: { affected: 50, resend: 49, leftOut: 1, field: 'OrderDate', before: '16/10/2026', after: '2026-10-16', itemNoun: { one: 'order', other: 'orders' } },
  raisedAt: '2026-10-22T14:13:00Z',
  expiresAt: '2026-10-23T14:13:00Z',
  ...over,
});
const check = (ref, over = {}) => ({ ref, kind: 'production', namespace: 'ZZNS', production: 'Zz.Orders', displayName: 'Orders', stopped: false, nextDueAt: '', lastRunAt: '2026-10-22T14:13:00Z', result: 'failed', finding: '50 new failures', ...over });
const reminder = (ref, over = {}) => ({ ref, text: `zz ${ref}`, dueAt: '2026-10-22T14:14:29Z', state: 'pending', late: false, ...over });
const decision = (ref, recordedAt, over = {}) => ({
  ref,
  kind: 'decide',
  itemId: `item-${ref}`,
  itemSummary: `summary ${ref}`,
  outcome: 'act',
  reasons: `first of ${ref}\nsecond of ${ref}`,
  confidence: 0.9,
  fallback: false,
  costUSD: 0.0003,
  recordedAt,
  ...over,
});

describe('the fixed strings', () => {
  it('are the UX\'s wording, written out here, with straight ASCII quotes', () => {
    assert.deepEqual(
      { ...RAIL_TEXTS },
      {
        telegram: 'Telegram',
        approvals: 'Approval requests',
        checks: 'Background checks',
        reminders: 'Reminders',
        decisions: 'Recent decisions',
        headingVisible: '{label} ({n})',
        headingSpoken: '{label}, {n}',
        emptyApprovals: 'None waiting.',
        emptyChecks: 'Ask OcuTalon to watch a production.',
        emptyReminders: 'None pending.',
        emptyDecisions: 'No decisions yet.',
        hintChecks: 'To stop, ask: "Stop watching Orders."',
        hintReminders: 'To cancel, ask: "Cancel my reminder to stretch."',
        repair: 'Repair and resend',
        repairCount: 'Repair and resend {n} {noun}',
        runTool: 'Run {toolName}',
        raised: 'Raised {when}',
        expires: 'expires {when}',
        checkTitle: '{name} production',
        checkSchedule: 'Live, plus a check every minute',
        lastRun: 'Last run {when}',
        titleWithCountdown: '{text}{separator}{countdown}',
        telegramNotSetUp: 'Telegram not set up',
        telegramHowTo: 'How to set it up',
      },
    );
    for (const value of Object.values(RAIL_TEXTS)) {
      assert.match(value, /^[\x20-\x7e]+$/, `${value} is ASCII`);
    }
  });

  it('use the middle dot U+00B7 as the one separator, from the chat\'s own constant', () => {
    assert.equal(CHAT_TEXTS.separator, ' \u00B7 ');
    assert.equal(format().separator, ' \u00B7 ');
  });

  it('link the README\'s Telegram section in place of #readme', () => {
    assert.equal(TELEGRAM_ANCHOR, 'telegram');
    assert.equal(readmeSection(README_URL, TELEGRAM_ANCHOR), 'https://github.com/jbrandtmse/OcuTalon#telegram');
    assert.equal(readmeSection('https://example.test/r', 'x'), 'https://example.test/r#x');
  });
});

describe('the sections', () => {
  it('come in order without Telegram: Approval requests, Background checks, Reminders, Recent decisions', () => {
    const view = viewOf();
    assert.deepEqual(view.sections.map((one) => one.id), ['approvals', 'checks', 'reminders', 'decisions']);
    assert.deepEqual(view.sections.map((one) => one.label), ['Approval requests', 'Background checks', 'Reminders', 'Recent decisions']);
    assert.equal(view.telegramShown, false);
  });

  it('start with Telegram, with no count, when the release includes it', () => {
    const view = viewOf({}, { ...TELEGRAM_OFF, included: true });
    assert.deepEqual(view.sections.map((one) => one.id), ['telegram', 'approvals', 'checks', 'reminders', 'decisions']);
    assert.equal(view.telegramShown, true);
    const telegram = section(view, 'telegram');
    assert.equal(telegram.count, undefined);
    assert.equal(telegram.heading, 'Telegram');
    assert.equal(telegram.spoken, 'Telegram');
    assert.deepEqual(telegram.rows, []);
  });

  it('show "(0)" and "None waiting." and the other empty texts, with both hints, when there is nothing', () => {
    const view = viewOf();
    const expected = {
      approvals: ['Approval requests (0)', 'Approval requests, 0', 'None waiting.', ''],
      checks: ['Background checks (0)', 'Background checks, 0', 'Ask OcuTalon to watch a production.', 'To stop, ask: "Stop watching Orders."'],
      reminders: ['Reminders (0)', 'Reminders, 0', 'None pending.', 'To cancel, ask: "Cancel my reminder to stretch."'],
      decisions: ['Recent decisions (0)', 'Recent decisions, 0', 'No decisions yet.', ''],
    };
    for (const [id, [heading, spoken, empty, hint]] of Object.entries(expected)) {
      const one = section(view, id);
      assert.equal(one.count, 0, id);
      assert.deepEqual([one.heading, one.spoken, one.empty, one.hint], [heading, spoken, empty, hint], id);
      assert.deepEqual(one.rows, [], id);
    }
  });

  it('count their rows in the visible and the spoken heading: "Background checks (1)" and "Background checks, 1"', () => {
    const view = viewOf({ checks: [check('c1')], approvals: [approval('a1'), approval('a2')] });
    assert.equal(section(view, 'checks').heading, 'Background checks (1)');
    assert.equal(section(view, 'checks').spoken, 'Background checks, 1');
    assert.equal(section(view, 'approvals').heading, 'Approval requests (2)');
    assert.equal(section(view, 'approvals').spoken, 'Approval requests, 2');
    assert.equal(section(view, 'approvals').count, 2);
  });

  it('keep the hints under a list that has rows', () => {
    const view = viewOf({ checks: [check('c1')], reminders: [reminder('r1')] });
    assert.equal(section(view, 'checks').hint, 'To stop, ask: "Stop watching Orders."');
    assert.equal(section(view, 'reminders').hint, 'To cancel, ask: "Cancel my reminder to stretch."');
  });
});

describe('approval requests', () => {
  it('lists the pending ones only', () => {
    const states = ['pending', 'approved', 'rejected', 'expired', 'cancelled', 'executing', 'done', 'failed'];
    const view = viewOf({ approvals: states.map((state) => approval(`a-${state}`, { state })) });
    assert.deepEqual(keys(section(view, 'approvals')), ['approvals:a-pending']);
    assert.equal(section(view, 'approvals').heading, 'Approval requests (1)');
  });

  it('orders them by raised time, then by the store\'s order', () => {
    const view = viewOf({
      approvals: [
        approval('late', { raisedAt: '2026-10-22T14:13:00Z' }),
        approval('early', { raisedAt: '2026-10-22T09:00:00Z' }),
        approval('tie-1', { raisedAt: '2026-10-22T12:00:00Z' }),
        approval('tie-2', { raisedAt: '2026-10-22T12:00:00Z' }),
      ],
    });
    assert.deepEqual(keys(section(view, 'approvals')), ['approvals:early', 'approvals:tie-1', 'approvals:tie-2', 'approvals:late']);
  });

  it('names the action: the dry run\'s count with the noun by the count, "Repair and resend" without a dry run, "Run zz_tool" for a tool call', () => {
    assert.equal(approvalTitle(approval('a')), 'Repair and resend 50 orders');
    assert.equal(approvalTitle(approval('a', { dryRun: { affected: 1, itemNoun: { one: 'order', other: 'orders' } } })), 'Repair and resend 1 order');
    assert.equal(approvalTitle(approval('a', { dryRun: { affected: 0, itemNoun: { one: 'order', other: 'orders' } } })), 'Repair and resend 0 orders');
    assert.equal(approvalTitle(approval('a', { dryRun: undefined })), 'Repair and resend');
    assert.equal(approvalTitle(approval('a', { kind: 'tool_call', toolName: 'zz_tool', dryRun: undefined })), 'Run zz_tool');
    const view = viewOf({ approvals: [approval('a1'), approval('a2', { dryRun: { affected: 1, itemNoun: { one: 'order', other: 'orders' } } })] });
    assert.deepEqual(titles(section(view, 'approvals')), ['Repair and resend 50 orders', 'Repair and resend 1 order']);
  });

  it('shows when it was raised and when it expires, with no detail line', () => {
    const row = section(viewOf({ approvals: [approval('a1')] }), 'approvals').rows[0];
    assert.deepEqual(row.meta, ['Raised 14:13', 'expires tomorrow at 14:13']);
    assert.equal(row.meta.join(CHAT_TEXTS.separator), 'Raised 14:13 \u00B7 expires tomorrow at 14:13');
    assert.equal(row.detail, undefined);
    assert.equal(row.kind, 'approval');
  });

  it('keeps a part out of the meta line when its time is missing', () => {
    const row = section(viewOf({ approvals: [approval('a1', { expiresAt: undefined })] }), 'approvals').rows[0];
    assert.deepEqual(row.meta, ['Raised 14:13']);
  });

  it('leaves the list when a later event says it is answered, expired or cancelled, and counts the rest', () => {
    const store = fromSnapshot(snapshot({ approvals: [approval('a1'), approval('a2')] }));
    assert.deepEqual(keys(section(railView(store, format()), 'approvals')), ['approvals:a1', 'approvals:a2']);
    let seq = 5;
    let current = store;
    for (const state of ['approved', 'expired', 'cancelled']) {
      const result = applyEvents(current, { epoch: 'e1', events: [{ type: 'approval', stream: 'session', seq: ++seq, ts: '', payload: approval('a1', { state }) }] });
      current = result.store;
      assert.deepEqual(keys(section(railView(current, format()), 'approvals')), ['approvals:a2'], state);
      assert.equal(section(railView(current, format()), 'approvals').heading, 'Approval requests (1)', state);
    }
  });

  it('adds a raised request that an event brings', () => {
    const store = fromSnapshot(snapshot());
    const result = applyEvents(store, { epoch: 'e1', events: [{ type: 'approval', stream: 'session', seq: 6, ts: '', payload: approval('a1') }] });
    assert.deepEqual(keys(section(railView(result.store, format()), 'approvals')), ['approvals:a1']);
  });
});

describe('background checks', () => {
  it('lists every check in the store\'s order, keyed by ref', () => {
    const view = viewOf({ checks: [check('c2'), check('c1', { displayName: 'Billing' })] });
    assert.deepEqual(keys(section(view, 'checks')), ['checks:c2', 'checks:c1']);
    assert.deepEqual(titles(section(view, 'checks')), ['Orders production', 'Billing production']);
  });

  it('names a production check "{name} production" with its schedule, and any other kind by its name alone, with no detail', () => {
    assert.equal(checkTitle(check('c')), 'Orders production');
    assert.equal(checkTitle(check('c', { kind: 'other' })), 'Orders');
    const rows = section(viewOf({ checks: [check('c1'), check('c2', { kind: 'other' })] }), 'checks').rows;
    assert.equal(rows[0].detail, 'Live, plus a check every minute');
    assert.equal(rows[1].detail, undefined);
    assert.equal(rows[0].kind, 'check');
  });

  it('shows the last run and the finding: "Last run 14:13 \u00B7 50 new failures"', () => {
    const row = section(viewOf({ checks: [check('c1')] }), 'checks').rows[0];
    assert.deepEqual(row.meta, ['Last run 14:13', '50 new failures']);
    assert.equal(row.meta.join(CHAT_TEXTS.separator), 'Last run 14:13 \u00B7 50 new failures');
  });

  it('puts the result word in the place of a missing finding, and shows the last run alone with neither', () => {
    const meta = (over) => section(viewOf({ checks: [check('c1', over)] }), 'checks').rows[0].meta;
    assert.deepEqual(meta({ finding: undefined, result: 'passed' }), ['Last run 14:13', 'Passed']);
    assert.deepEqual(meta({ finding: '', result: 'failed' }), ['Last run 14:13', 'Failed']);
    assert.deepEqual(meta({ finding: '', result: 'not-checked' }), ['Last run 14:13', 'Not checked']);
    assert.deepEqual(meta({ finding: '', result: '' }), ['Last run 14:13']);
    assert.deepEqual(meta({ finding: undefined, result: undefined }), ['Last run 14:13']);
  });

  it('has no meta line before the first run', () => {
    const row = section(viewOf({ checks: [check('c1', { lastRunAt: '', result: '', finding: '' })] }), 'checks').rows[0];
    assert.deepEqual(row.meta, []);
  });

  it('updates a row in place when a later event has the same ref: one row, the same count and place, the new text', () => {
    const store = fromSnapshot(snapshot({ checks: [check('c1'), check('c2', { displayName: 'Billing' })] }));
    const event = { type: 'check', stream: 'session', seq: 6, ts: '', payload: check('c1', { finding: 'No new failures', result: 'passed' }) };
    const result = applyEvents(store, { epoch: 'e1', events: [event] });
    const one = section(railView(result.store, format()), 'checks');
    assert.deepEqual(keys(one), ['checks:c1', 'checks:c2']);
    assert.equal(one.heading, 'Background checks (2)');
    assert.deepEqual(one.rows[0].meta, ['Last run 14:13', 'No new failures']);
  });

  it('shows markup in a display name or a finding as it is', () => {
    const row = section(viewOf({ checks: [check('c1', { displayName: '<b>zz</b>', finding: '<i>zz</i>' })] }), 'checks').rows[0];
    assert.equal(row.title, '<b>zz</b> production');
    assert.deepEqual(row.meta, ['Last run 14:13', '<i>zz</i>']);
  });
});

describe('reminders', () => {
  it('lists the pending ones only, by due time and then the store\'s order', () => {
    const view = viewOf({
      reminders: [
        reminder('r-late', { dueAt: '2026-10-22T16:00:00Z' }),
        reminder('r-fired', { state: 'fired' }),
        reminder('r-cancelled', { state: 'cancelled' }),
        reminder('r-tie-1', { dueAt: '2026-10-22T15:00:00Z' }),
        reminder('r-soon', { dueAt: '2026-10-22T14:14:00Z' }),
        reminder('r-tie-2', { dueAt: '2026-10-22T15:00:00Z' }),
      ],
    });
    assert.deepEqual(keys(section(view, 'reminders')), ['reminders:r-soon', 'reminders:r-tie-1', 'reminders:r-tie-2', 'reminders:r-late']);
    assert.equal(section(view, 'reminders').heading, 'Reminders (4)');
  });

  it('shows the text, the countdown and the due time: "zz r1 \u00B7 in 59 s", spoken "in 59 seconds", "Due 14:14"', () => {
    const row = section(viewOf({ reminders: [reminder('r1')] }), 'reminders').rows[0];
    assert.equal(row.title, 'zz r1 \u00B7 in 59 s');
    assert.equal(row.lead, 'zz r1');
    assert.deepEqual(row.countdown, { text: 'in 59 s', spoken: 'in 59 seconds' });
    assert.deepEqual(row.meta, ['Due 14:14']);
    assert.equal(row.kind, 'reminder');
  });

  it('counts down against the clock it is given, and a later clock changes the text', () => {
    const rail = { reminders: [reminder('r1')] };
    const at = (offset) => section(viewOf(rail, TELEGRAM_OFF, NOW + offset), 'reminders').rows[0].countdown.text;
    assert.equal(at(0), 'in 59 s');
    assert.equal(at(10_000), 'in 49 s');
    assert.equal(at(70_000), 'in 0 s');
  });

  it('shows the text alone, with no meta, for a reminder with no due time', () => {
    const rows = section(viewOf({ reminders: [reminder('r1', { dueAt: '' }), reminder('r2', { dueAt: undefined })] }), 'reminders').rows;
    assert.deepEqual(
      rows.map((row) => [row.title, row.countdown, row.meta]),
      [
        ['zz r1', undefined, []],
        ['zz r2', undefined, []],
      ],
    );
  });

  it('shows the text as it is, with markup left as text and the case kept', () => {
    const row = section(viewOf({ reminders: [reminder('r1', { text: '<b>zz</b> Stretch' })] }), 'reminders').rows[0];
    assert.equal(row.title, '<b>zz</b> Stretch \u00B7 in 59 s');
  });

  it('updates a row in place on a later event with the same ref, and drops it when it fired or was cancelled', () => {
    const store = fromSnapshot(snapshot({ reminders: [reminder('r1'), reminder('r2', { dueAt: '2026-10-22T16:00:00Z' })] }));
    const update = { type: 'reminder', stream: 'session', seq: 6, ts: '', payload: reminder('r1', { dueAt: '2026-10-22T14:13:50Z' }) };
    let current = applyEvents(store, { epoch: 'e1', events: [update] }).store;
    const one = section(railView(current, format()), 'reminders');
    assert.deepEqual(keys(one), ['reminders:r1', 'reminders:r2']);
    assert.equal(one.rows[0].countdown.text, 'in 20 s');
    for (const state of ['fired', 'cancelled']) {
      current = applyEvents(store, { epoch: 'e1', events: [{ ...update, payload: reminder('r1', { state }) }] }).store;
      assert.deepEqual(keys(section(railView(current, format()), 'reminders')), ['reminders:r2'], state);
    }
  });
});

describe('recent decisions', () => {
  /** A minute apart from 13:00 on, so that a larger number is newer. */
  const at = (n) => `2026-10-22T${String(13 + Math.floor(n / 60)).padStart(2, '0')}:${String(n % 60).padStart(2, '0')}:00Z`;

  it('lists the attention decisions only, newest first, at most 20', () => {
    const decisions = [decision('turn-one', at(50), { kind: 'turn' })];
    for (let n = 21; n >= 1; n -= 1) {
      decisions.push(decision(`d${n}`, at(n)));
    }
    const one = section(viewOf({ decisions }), 'decisions');
    assert.equal(one.rows.length, 20);
    assert.deepEqual(keys(one).slice(0, 3), ['decisions:d21', 'decisions:d20', 'decisions:d19']);
    assert.equal(keys(one)[19], 'decisions:d2');
    assert.ok(!keys(one).includes('decisions:turn-one'), 'a turn decision is not shown');
    assert.ok(!keys(one).includes('decisions:d1'), 'the oldest decision is cut');
    assert.equal(one.heading, 'Recent decisions (20)');
    assert.equal(one.spoken, 'Recent decisions, 20');
  });

  it('sorts by the time recorded and keeps the store\'s order for a tie', () => {
    const view = viewOf({ decisions: [decision('old', at(1)), decision('tie-1', at(5)), decision('tie-2', at(5)), decision('new', at(9))] });
    assert.deepEqual(keys(section(view, 'decisions')), ['decisions:new', 'decisions:tie-1', 'decisions:tie-2', 'decisions:old']);
  });

  it('puts a decision that an event brings first, and the 20th leaves; a turn decision changes nothing', () => {
    const decisions = [];
    for (let n = 20; n >= 1; n -= 1) {
      decisions.push(decision(`d${n}`, at(n)));
    }
    const store = fromSnapshot(snapshot({ decisions }));
    const fresh = { type: 'decision', stream: 'session', seq: 6, ts: '', payload: decision('new', at(30)) };
    const after = applyEvents(store, { epoch: 'e1', events: [fresh] }).store;
    const one = section(railView(after, format()), 'decisions');
    assert.equal(keys(one)[0], 'decisions:new');
    assert.equal(one.rows.length, 20);
    assert.ok(!keys(one).includes('decisions:d1'), 'the oldest left');
    const turn = { type: 'decision', stream: 'session', seq: 7, ts: '', payload: decision('turn-new', at(31), { kind: 'turn' }) };
    const same = section(railView(applyEvents(after, { epoch: 'e1', events: [turn] }).store, format()), 'decisions');
    assert.deepEqual(keys(same), keys(one));
  });

  it('shows the chip, the summary, the first reason, every reason and the meta: "14:11 \u00B7 Confidence 0.90 \u00B7 $0.0003"', () => {
    const row = section(viewOf({ decisions: [decision('d1', '2026-10-22T14:11:00Z', { itemSummary: 'Incident: 50 orders failed' })] }), 'decisions').rows[0];
    assert.equal(row.title, 'Incident: 50 orders failed');
    assert.equal(row.kind, 'decision');
    assert.deepEqual(row.decision, { chip: 'act', fallback: false, fallbackLine: false, firstReason: 'first of d1', reasons: ['first of d1', 'second of d1'] });
    assert.deepEqual(row.meta, ['14:11', 'Confidence 0.90', '$0.0003']);
    assert.equal(row.meta.join(CHAT_TEXTS.separator), '14:11 \u00B7 Confidence 0.90 \u00B7 $0.0003');
  });

  it('maps every outcome to its chip, and none for an outcome the page does not know', () => {
    const chip = (outcome) => section(viewOf({ decisions: [decision('d1', at(1), { outcome })] }), 'decisions').rows[0].decision.chip;
    assert.equal(chip('tellnow'), 'tell-now');
    assert.equal(chip('ignore'), 'ignore');
    assert.equal(chip('digest'), 'digest');
    assert.equal(chip('act'), 'act');
    assert.equal(chip('zz'), undefined);
  });

  it('shows a fallback with the Tell now chip, the flag, its sentence first and no confidence', () => {
    const fallback = decision('d1', '2026-10-22T14:11:00Z', { fallback: true, fallbackReason: 'timeout', outcome: 'act', confidence: 0.9 });
    const row = section(viewOf({ decisions: [fallback] }), 'decisions').rows[0];
    assert.deepEqual(row.decision, {
      chip: 'tell-now',
      fallback: true,
      fallbackLine: true,
      firstReason: 'Zz sentence of timeout.',
      reasons: ['Zz sentence of timeout.', 'first of d1', 'second of d1'],
    });
    assert.deepEqual(row.meta, ['14:11', '$0.0003']);
    assert.ok(!row.meta.join('').includes('Confidence'));
  });

  it('leaves the cost out of a decision that has none, and the confidence out of one that has none', () => {
    const bare = decision('d1', '2026-10-22T14:11:00Z', { costUSD: undefined, confidence: undefined });
    assert.deepEqual(section(viewOf({ decisions: [bare] }), 'decisions').rows[0].meta, ['14:11']);
    const free = decision('d2', '2026-10-22T14:11:00Z', { costUSD: 0 });
    assert.deepEqual(section(viewOf({ decisions: [free] }), 'decisions').rows[0].meta, ['14:11', 'Confidence 0.90', '<$0.0001']);
  });

  it('has no first reason for a decision with no reasons, and shows markup in a summary as it is', () => {
    const row = section(viewOf({ decisions: [decision('d1', at(1), { reasons: '', itemSummary: '<i>zz</i> Your message' })] }), 'decisions').rows[0];
    assert.equal(row.decision.firstReason, '');
    assert.deepEqual(row.decision.reasons, []);
    assert.equal(row.title, '<i>zz</i> Your message');
  });
});

describe('a value that holds a placeholder', () => {
  it('is shown as typed and filled in once: a reminder text that names {countdown}, a noun that names {n}', () => {
    const view = viewOf({
      approvals: [approval('a1', { dryRun: { affected: 3, itemNoun: { one: 'thing', other: '{n}' } } })],
      reminders: [reminder('r1', { text: '{countdown}' })],
    });
    const [row] = section(view, 'reminders').rows;
    assert.equal(row.lead, '{countdown}');
    assert.equal(row.title, '{countdown} \u00B7 in 59 s');
    assert.equal(section(view, 'approvals').rows[0].title, 'Repair and resend 3 {n}');
  });
});

describe('a reload', () => {
  it('shows what the events built: the view of the live store equals the view of a snapshot that holds the same things', () => {
    const initial = snapshot({ approvals: [approval('a1')], checks: [check('c1')], reminders: [reminder('r1')], decisions: [decision('d1', '2026-10-22T14:00:00Z')] });
    const events = [
      { type: 'approval', stream: 'session', seq: 6, ts: '', payload: approval('a2', { raisedAt: '2026-10-22T14:13:10Z' }) },
      { type: 'approval', stream: 'session', seq: 7, ts: '', payload: approval('a1', { state: 'approved' }) },
      { type: 'check', stream: 'session', seq: 8, ts: '', payload: check('c1', { finding: 'No new failures', result: 'passed' }) },
      { type: 'reminder', stream: 'session', seq: 9, ts: '', payload: reminder('r1', { state: 'fired' }) },
      { type: 'decision', stream: 'session', seq: 10, ts: '', payload: decision('d2', '2026-10-22T14:10:00Z') },
      { type: 'decision', stream: 'session', seq: 11, ts: '', payload: decision('d3', '2026-10-22T14:05:00Z') },
    ];
    const live = applyEvents(fromSnapshot(initial), { epoch: 'e1', events }).store;
    const reloaded = fromSnapshot(
      snapshot({
        approvals: [approval('a1', { state: 'approved' }), approval('a2', { raisedAt: '2026-10-22T14:13:10Z' })],
        checks: [check('c1', { finding: 'No new failures', result: 'passed' })],
        reminders: [reminder('r1', { state: 'fired' })],
        decisions: [decision('d2', '2026-10-22T14:10:00Z'), decision('d3', '2026-10-22T14:05:00Z'), decision('d1', '2026-10-22T14:00:00Z')],
      }),
    );
    assert.deepEqual(railView(live, format()), railView(reloaded, format()));
  });
});
