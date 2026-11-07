// Tests the Heartbeat checklist card's fixed texts and rules (src/app/rail/heartbeat-card/heartbeat-card-view.ts, Story 39.5; FR-63 to FR-66, DW-634,
// DW-781). Every string of the card's Public text is written out here, word for word, and compared whole: the UX's own runs, and the ones the Contest
// Planner ruled (planner-2026-11-06-39.5). The values the card shares with the server (the run-now seconds, the two unavailable reasons, the skip
// reasons, the intervals) are read from OcuTalon.Checks.Beat and OcuTalon.Web.Api themselves.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const cls = (...parts) => readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', ...parts), 'utf8');
const {
  HEARTBEAT_TEXTS,
  HEARTBEAT_HEADING_ID,
  INTERVALS,
  QUARTER_HOURS,
  RUN_NOW_SECONDS,
  SEPARATOR,
  SKIP_REASONS,
  cooldownUntil,
  failureOf,
  intervalName,
  lastLine,
  saveBody,
  stateLine,
  todayLine,
  unavailable,
} = await import(app('rail', 'heartbeat-card', 'heartbeat-card-view.ts'));
const { CHAT_TEXTS } = await import(app('chat', 'chat-view.ts'));
const { counterText } = await import(app('rail', 'persona-card', 'persona-card-view.ts'));
const { PAGE_TEXTS } = await import(app('msg', 'catalog.ts'));

const BEAT = cls('Checks', 'Beat.cls');
const API = cls('Web', 'Api.cls');

/** The value of a Parameter of a class, as the source writes it. */
const parameter = (source, name) => {
  const match = new RegExp(`^Parameter ${name} = (?:"([^"]*)"|(\\d+));`, 'm').exec(source);
  assert.ok(match, `Parameter ${name} is in the class`);
  return match[1] ?? match[2];
};

/** A stand-in for the page's time: the clock of the ISO string, or "" for an unreadable one. */
const when = (iso) => (/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(iso) ? iso.slice(11, 16) : '');
const format = {
  when,
  cost: (amount) => `$${amount}`,
  reason: (reason) => (reason === 'timeout' ? "the model didn't answer within 60 seconds" : "the model's reply couldn't be used"),
};

describe('the texts', () => {
  it('are the Public text of Story 39.5, written out here whole', () => {
    assert.deepEqual(
      { ...HEARTBEAT_TEXTS, skip: { ...HEARTBEAT_TEXTS.skip }, intervals: { ...HEARTBEAT_TEXTS.intervals } },
      {
        off: 'Off. Turn it on to have OcuTalon look at your list every 30 minutes.',
        every: 'Every {interval}',
        everyHours: 'Every {interval}, {from} to {to}',
        next: 'Next check-in {time}',
        last: 'Last check-in {time}',
        stayedQuiet: 'Stayed quiet',
        toldNow: 'Told you now',
        digest: 'Saved for the digest',
        offered: 'Offered an action',
        couldntDecide: "Couldn't decide: {reason}",
        skipped: 'Skipped at {time}:',
        skip: {
          empty: 'your checklist is empty.',
          hours: 'outside your active hours.',
          unchanged: 'nothing has changed since the last quiet check-in.',
          cap: "today's cost limit has been reached.",
          nokey: 'no model key is set.',
          backoff: 'waiting after a failed check-in, until {time}.',
        },
        today: 'Today: {n} check-ins, {cost}',
        todayOne: 'Today: 1 check-in, {cost}',
        help: 'Write what OcuTalon should look for, one item per line. With an empty list, OcuTalon makes no model call. It looks at most once per interval, and only when something has changed.',
        run: 'Run the heartbeat now',
        cooldown: 'You can run it again at {time}.',
        unavailableCap: "Today's cost limit has been reached.",
        unavailableNoKey: 'No model key is set.',
        demoNote: "On the online demo the heartbeat is off until you turn it on, and each check-in counts toward the demo's daily cost cap.",
        edit: 'Edit',
        save: 'Save',
        on: 'On',
        interval: 'Interval',
        activeHours: 'Active hours',
        from: 'From',
        to: 'To',
        allDay: 'All day',
        checklist: 'Checklist',
        intervals: { 30: '30 minutes', 60: '1 hour', 120: '2 hours', 240: '4 hours', 480: '8 hours', 1440: '24 hours' },
      },
    );
    const strings = JSON.stringify(HEARTBEAT_TEXTS);
    assert.match(strings, /^[\x20-\x7e]+$/, 'all ASCII');
  });

  it('use the chat\'s separator, the section heading id of the rail and the catalog\'s cap wording', () => {
    assert.equal(SEPARATOR, CHAT_TEXTS.separator);
    assert.equal(HEARTBEAT_HEADING_ID, 'rail-heading-heartbeat');
    assert.equal(HEARTBEAT_TEXTS.skip.cap, `${PAGE_TEXTS['fallbackReason.dailyCap']}.`);
  });

  it('say nothing that reads as an all-clear (AD-28)', () => {
    const text = JSON.stringify(HEARTBEAT_TEXTS).toLowerCase();
    for (const phrase of ['all is well', 'all clear', 'all-clear', 'everything is fine', 'no problems', 'healthy', 'nothing to report']) {
      assert.ok(!text.includes(phrase), phrase);
    }
  });

  it('copy the two unavailable reasons of OcuTalon.Web.Api (DW-634)', () => {
    assert.equal(HEARTBEAT_TEXTS.unavailableCap, parameter(API, 'MESSAGERUNCAP'));
    assert.equal(HEARTBEAT_TEXTS.unavailableNoKey, parameter(API, 'MESSAGERUNNOKEY'));
    assert.equal(HEARTBEAT_TEXTS.cooldown, parameter(API, 'MESSAGERUNCOOLDOWN'));
  });
});

describe('the values shared with Checks', () => {
  it('the checklist counter states the limit that Beat.cls CHECKLISTMAX enforces', () => {
    const limit = Number(parameter(BEAT, 'CHECKLISTMAX'));
    assert.equal(counterText(''), `0 of ${limit.toLocaleString('en-US')} characters`);
  });

  it('RUN_NOW_SECONDS is Beat.cls RUNNOWSECONDS', () => {
    assert.equal(RUN_NOW_SECONDS, Number(parameter(BEAT, 'RUNNOWSECONDS')));
    assert.equal(RUN_NOW_SECONDS, 120);
  });

  it('SKIP_REASONS are the SKIP values of Beat.cls, and each has a text', () => {
    const skips = ['SKIPEMPTY', 'SKIPHOURS', 'SKIPBACKOFF', 'SKIPCAP', 'SKIPNOKEY', 'SKIPUNCHANGED'].map((name) => parameter(BEAT, name));
    assert.deepEqual([...skips].sort(), [...SKIP_REASONS].sort());
    assert.deepEqual(Object.keys(HEARTBEAT_TEXTS.skip).sort(), [...SKIP_REASONS].sort());
  });

  it('INTERVALS are the INTERVALS of Beat.cls, with the ruled names', () => {
    assert.deepEqual(INTERVALS.map((one) => one.minutes), parameter(BEAT, 'INTERVALS').split(',').map(Number));
    assert.deepEqual(INTERVALS.map((one) => one.name), ['30 minutes', '1 hour', '2 hours', '4 hours', '8 hours', '24 hours']);
    assert.equal(intervalName(60), '1 hour');
    assert.equal(intervalName(45), '');
    assert.equal(intervalName(undefined), '');
  });

  it('QUARTER_HOURS are 00:00 to 23:45', () => {
    assert.equal(QUARTER_HOURS.length, 96);
    assert.deepEqual([QUARTER_HOURS[0], QUARTER_HOURS[1], QUARTER_HOURS[4], QUARTER_HOURS[95]], ['00:00', '00:15', '01:00', '23:45']);
    for (const time of QUARTER_HOURS) assert.match(time, /^([01]\d|2[0-3]):(00|15|30|45)$/);
  });
});

describe('the state line', () => {
  const on = { on: true, interval: 60, from: '07:15', to: '21:45', nextDueAt: '2030-01-01T14:30:00Z' };

  it('is the off line while the heartbeat is off, whatever else is set', () => {
    assert.equal(stateLine({ on: false, interval: 60, nextDueAt: on.nextDueAt }, when), 'Off. Turn it on to have OcuTalon look at your list every 30 minutes.');
    assert.equal(stateLine({}, when), 'Off. Turn it on to have OcuTalon look at your list every 30 minutes.');
  });

  it('is the interval, the hours and the next check-in when on', () => {
    assert.equal(stateLine(on, when), 'Every 1 hour, 07:15 to 21:45 \u00b7 Next check-in 14:30');
    assert.equal(stateLine({ ...on, interval: 30 }, when), 'Every 30 minutes, 07:15 to 21:45 \u00b7 Next check-in 14:30');
    assert.equal(stateLine({ ...on, interval: 1440 }, when), 'Every 24 hours, 07:15 to 21:45 \u00b7 Next check-in 14:30');
  });

  it('leaves out the hours for all day, and the next check-in when none is due', () => {
    assert.equal(stateLine({ ...on, from: '', to: '' }, when), 'Every 1 hour \u00b7 Next check-in 14:30');
    assert.equal(stateLine({ ...on, nextDueAt: undefined }, when), 'Every 1 hour, 07:15 to 21:45');
    assert.equal(stateLine({ ...on, nextDueAt: '' }, when), 'Every 1 hour, 07:15 to 21:45');
    assert.equal(stateLine({ ...on, from: '', to: '', nextDueAt: '' }, when), 'Every 1 hour');
    assert.equal(stateLine({ ...on, from: '08:00', to: '08:00' }, when), 'Every 1 hour \u00b7 Next check-in 14:30', 'from equal to to is all day, as Checks.Beat InHours reads it');
  });

  it('is empty for an interval the card does not offer', () => {
    assert.equal(stateLine({ ...on, interval: 45 }, when), '');
  });
});

describe('the last line', () => {
  const beat = { lastBeatAt: '2030-01-01T10:00:00Z', lastOutcome: 'ignore', lastCostUSD: 0.0012, traceUrl: 'https://example.test/trace/1' };
  const line = (state) => lastLine(state, format);

  it('reads "Last check-in {time} \u00b7 Stayed quiet \u00b7 {cost} \u00b7 Trace" for an ignore, the trace address last', () => {
    assert.deepEqual(line(beat), { kind: 'checkin', parts: ['Last check-in 10:00', 'Stayed quiet', '$0.0012'], traceUrl: 'https://example.test/trace/1' });
  });

  it('names each outcome', () => {
    for (const [outcome, text] of [['ignore', 'Stayed quiet'], ['tellnow', 'Told you now'], ['digest', 'Saved for the digest'], ['act', 'Offered an action']]) {
      assert.deepEqual(line({ ...beat, lastOutcome: outcome }).parts, ['Last check-in 10:00', text, '$0.0012'], outcome);
    }
  });

  it('reads "Couldn\'t decide: {plain reason}" for a fallback, whatever its outcome', () => {
    assert.deepEqual(line({ ...beat, lastOutcome: 'tellnow', lastFallback: true, lastFallbackReason: 'timeout' }).parts, [
      'Last check-in 10:00',
      "Couldn't decide: the model didn't answer within 60 seconds",
      '$0.0012',
    ]);
    assert.deepEqual(line({ ...beat, lastFallback: true }).parts[1], "Couldn't decide: the model's reply couldn't be used", 'a fallback with no reason gets the generic one');
  });

  it('leaves out the cost and the trace when the state has none', () => {
    assert.deepEqual(line({ lastBeatAt: beat.lastBeatAt, lastOutcome: 'digest' }), { kind: 'checkin', parts: ['Last check-in 10:00', 'Saved for the digest'], traceUrl: '' });
  });

  it('shows the time alone for a pending beat and for an outcome it does not know', () => {
    assert.deepEqual(line({ lastBeatAt: beat.lastBeatAt }), { kind: 'checkin', parts: ['Last check-in 10:00'], traceUrl: '' });
    assert.deepEqual(line({ ...beat, lastOutcome: 'zz_unknown' }), { kind: 'checkin', parts: ['Last check-in 10:00'], traceUrl: '' });
    assert.deepEqual(line({ ...beat, lastOutcome: '' }), { kind: 'checkin', parts: ['Last check-in 10:00'], traceUrl: '' });
  });

  it('reads each skip reason', () => {
    const skip = { lastSkipAt: '2030-01-01T11:00:00Z', backoffUntil: '2030-01-01T12:30:00Z' };
    const expected = {
      empty: 'Skipped at 11:00: your checklist is empty.',
      hours: 'Skipped at 11:00: outside your active hours.',
      unchanged: 'Skipped at 11:00: nothing has changed since the last quiet check-in.',
      cap: "Skipped at 11:00: today's cost limit has been reached.",
      nokey: 'Skipped at 11:00: no model key is set.',
      backoff: 'Skipped at 11:00: waiting after a failed check-in, until 12:30.',
    };
    for (const [reason, text] of Object.entries(expected)) {
      assert.deepEqual(line({ ...skip, lastSkipReason: reason }), { kind: 'skip', parts: [text], traceUrl: '' }, reason);
    }
  });

  it('shows no skip line for an unknown or empty reason, or for a backoff with no end', () => {
    const none = { kind: 'none', parts: [], traceUrl: '' };
    assert.deepEqual(line({ lastSkipAt: '2030-01-01T11:00:00Z', lastSkipReason: 'zz_unknown' }), none);
    assert.deepEqual(line({ lastSkipAt: '2030-01-01T11:00:00Z', lastSkipReason: '' }), none);
    assert.deepEqual(line({ lastSkipAt: '2030-01-01T11:00:00Z', lastSkipReason: 'backoff' }), none);
    assert.deepEqual(line({ lastSkipAt: '2030-01-01T11:00:00Z', lastSkipReason: 'toString' }), none, 'an inherited name is no reason');
  });

  it('shows the newer of the check-in and the skip', () => {
    const both = { ...beat, lastSkipAt: '2030-01-01T11:00:00Z', lastSkipReason: 'hours' };
    assert.equal(line(both).kind, 'skip');
    assert.equal(line({ ...both, lastSkipAt: '2030-01-01T09:00:00Z' }).kind, 'checkin');
    assert.equal(line({ ...both, lastSkipAt: beat.lastBeatAt }).kind, 'checkin', 'the same instant: the check-in');
  });

  it('shows nothing when there is neither a check-in nor a skip, or only an unreadable time', () => {
    assert.equal(line({}).kind, 'none');
    assert.equal(line({ lastBeatAt: 'zz' }).kind, 'none');
  });
});

describe('the Today line', () => {
  const cost = (amount) => `$${amount}`;

  it('is empty at 0 check-ins and with no figure', () => {
    assert.equal(todayLine({ checkIns: 0, costUSD: 0 }, cost), '');
    assert.equal(todayLine(undefined, cost), '');
  });

  it('is "Today: 1 check-in, {cost}" for one', () => {
    assert.equal(todayLine({ checkIns: 1, costUSD: 0.0021 }, cost), 'Today: 1 check-in, $0.0021');
  });

  it('is "Today: {n} check-ins, {cost}" for two or more', () => {
    assert.equal(todayLine({ checkIns: 2, costUSD: 0.5 }, cost), 'Today: 2 check-ins, $0.5');
    assert.equal(todayLine({ checkIns: 3, costUSD: 1.25 }, cost), 'Today: 3 check-ins, $1.25');
  });
});

describe('the cooldown', () => {
  it('ends 120 seconds after LastRunNowAt', () => {
    assert.equal(cooldownUntil({ lastRunNowAt: '2030-01-01T10:00:00Z' }, ''), '2030-01-01T10:02:00Z');
  });

  it('ends at availableAt when that is all there is, and at the later of the two when both are', () => {
    assert.equal(cooldownUntil(undefined, '2030-01-01T10:05:00Z'), '2030-01-01T10:05:00Z');
    assert.equal(cooldownUntil({ lastRunNowAt: '2030-01-01T10:00:00Z' }, '2030-01-01T10:05:00Z'), '2030-01-01T10:05:00Z');
    assert.equal(cooldownUntil({ lastRunNowAt: '2030-01-01T10:00:00Z' }, '2030-01-01T10:01:00Z'), '2030-01-01T10:02:00Z');
  });

  it('is empty with no readable time', () => {
    assert.equal(cooldownUntil({}, ''), '');
    assert.equal(cooldownUntil(undefined, 'zz'), '');
  });
});

describe('what makes Run unavailable (DW-634)', () => {
  const store = (status) => ({ status });

  it('is the cap first, then the missing key, then nothing', () => {
    assert.equal(unavailable(store({ dailyCap: { active: true }, noModelKey: { active: true } })), 'cap');
    assert.equal(unavailable(store({ dailyCap: { active: true } })), 'cap');
    assert.equal(unavailable(store({ dailyCap: { active: false }, noModelKey: { active: true } })), 'nokey');
    assert.equal(unavailable(store({ noModelKey: { active: true } })), 'nokey');
    assert.equal(unavailable(store({ dailyCap: { active: false }, noModelKey: { active: false } })), '');
    assert.equal(unavailable(store({})), '');
    assert.equal(unavailable(undefined), '');
  });
});

describe('the save body', () => {
  const form = { on: true, interval: 60, allDay: false, from: '07:15', to: '21:45', checklist: 'a\nb' };

  it('carries the five values, in order', () => {
    assert.deepEqual(saveBody(form), { on: true, interval: 60, from: '07:15', to: '21:45', checklist: 'a\nb' });
    assert.deepEqual(Object.keys(saveBody(form)), ['on', 'interval', 'from', 'to', 'checklist']);
  });

  it('sends both hours empty for all day', () => {
    assert.deepEqual(saveBody({ ...form, allDay: true }), { on: true, interval: 60, from: '', to: '', checklist: 'a\nb' });
  });
});

describe('a failed call', () => {
  const refused = (code, message, availableAt) => ({ status: 400, error: { error: { code, message }, ...(availableAt === undefined ? {} : { availableAt }) } });

  it('shows bad_checklist, bad_hours, bad_interval and bad_on beside their field, with the server\'s message', () => {
    for (const [code, where] of [['bad_checklist', 'checklist'], ['bad_hours', 'hours'], ['bad_interval', 'interval'], ['bad_on', 'on']]) {
      assert.deepEqual(failureOf(refused(code, `message of ${code}`)), { where, code, message: `message of ${code}`, availableAt: '' }, code);
    }
  });

  it('shows every other code under the button, with the message and the 409\'s availableAt', () => {
    for (const code of ['bad_heartbeat', 'not_saved', 'server_error', 'not_built', 'cap', 'nokey', 'empty', 'backoff']) {
      assert.deepEqual(failureOf(refused(code, `message of ${code}`)), { where: 'save', code, message: `message of ${code}`, availableAt: '' }, code);
    }
    assert.deepEqual(failureOf(refused('cooldown', 'You can run it again at 10:02.', '2030-01-01T10:02:00Z')), {
      where: 'save',
      code: 'cooldown',
      message: 'You can run it again at 10:02.',
      availableAt: '2030-01-01T10:02:00Z',
    });
  });

  it('has no message for a failure with no body, no error object or no message', () => {
    const nothing = { where: 'save', code: '', message: '', availableAt: '' };
    assert.deepEqual(failureOf(null), nothing);
    assert.deepEqual(failureOf(undefined), nothing);
    assert.deepEqual(failureOf(new Error('x')), nothing);
    assert.deepEqual(failureOf({ status: 0, error: null }), nothing);
    assert.deepEqual(failureOf({ status: 502, error: '<html>' }), nothing);
    assert.deepEqual(failureOf({ status: 500, error: { error: null } }), nothing);
    assert.deepEqual(failureOf({ status: 500, error: { error: { code: 'server_error', message: 7 } } }), { ...nothing, code: 'server_error' });
  });

  it('keeps a field refusal that came with no message beside its field', () => {
    assert.deepEqual(failureOf({ status: 400, error: { error: { code: 'bad_hours' } } }), { where: 'hours', code: 'bad_hours', message: '', availableAt: '' });
  });

  it('takes an inherited name for no code', () => {
    assert.equal(failureOf(refused('toString', 'x')).where, 'save');
  });
});
