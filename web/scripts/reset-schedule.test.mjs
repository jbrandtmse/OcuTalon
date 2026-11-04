// Tests the page's view of the demo's reset (src/app/live/reset-schedule.ts, Story 16.8; matrix rows 10 to 12): the countdown pill's
// texts, urgency, visibility and update times; the pending reset (an earlier offer replaces it, a later one only while more than 300 s
// remain, an empty one never); the "due" rule; and the resetting view's poller (a GET with no credentials and no cache every 10 s, a
// 3 s limit, a failed, timed-out or non-JSON answer counting as not ready, and exactly one navigation, to the splash with the load
// time, when the status is ready with a last reset later than the load time or the page is 15 minutes past the reset); and that the
// reset-soon threshold is the same in the server (Public.Settings), the splash script and the page. The module is imported as it is
// (Node strips its types); the clock, timers and fetch are fakes.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { fakeClock } from './fake-clock.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { RESET_POLL_MS, RESET_SOON_MS, RESET_TEXTS, RESET_WINDOW_MS, STATUS_LIMIT_MS, ResetPoller, isDue, offerReset, parseStatus, pillDelayMs, pillView, shouldNavigate } = await import(app('live', 'reset-schedule.ts'));
const { countdownSpokenMinutes, countdownText, pageTime } = await import(app('chat', 'page-time.ts'));
const { PAGE_LOADED_AT, PAGE_LOADED_AT_MS, splashAddress, utcSeconds } = await import(app('session', 'splash-address.ts'));

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const T = Date.parse('2026-10-25T16:00:00Z');
const iso = (ms) => new Date(ms).toISOString();
const FORMAT = {
  time: (value) => pageTime(value, 'en-GB', 'UTC'),
  countdown: countdownText,
  spoken: countdownSpokenMinutes,
};

describe('the pill (row 10)', () => {
  const pill = (left, onlineDemo = true, pending = iso(T)) => pillView(onlineDemo, pending, T - left, FORMAT);

  it('reads "Next reset {time} \u00b7 in {countdown}" with the countdown of countdownText, without its "in"', () => {
    assert.equal(pill(HOUR + 42 * MINUTE + 30 * SECOND).text, 'Next reset 16:00 \u00b7 in 1 h 42 min');
    assert.equal(pill(10 * MINUTE).text, 'Next reset 16:00 \u00b7 in 10 min');
    assert.equal(pill(10 * MINUTE + SECOND).text, 'Next reset 16:00 \u00b7 in 10 min');
    assert.equal(pill(MINUTE).text, 'Next reset 16:00 \u00b7 in 1 min');
    assert.equal(pill(59 * SECOND).text, 'Next reset 16:00 \u00b7 in 59 s');
    assert.equal(pill(23 * SECOND).text, 'Next reset 16:00 \u00b7 in 23 s');
    assert.equal(pill(SECOND).text, 'Next reset 16:00 \u00b7 in 1 s');
    assert.equal(RESET_TEXTS.countdown, 'Next reset {time} \u00b7 in {countdown}');
  });

  it('says the same in words of whole minutes, and "in 1 minute" through the last minute', () => {
    assert.equal(pill(HOUR + 42 * MINUTE + 30 * SECOND).spoken, 'Next reset 16:00 \u00b7 in 1 hour 42 minutes');
    assert.equal(pill(10 * MINUTE).spoken, 'Next reset 16:00 \u00b7 in 10 minutes');
    assert.equal(pill(10 * MINUTE + SECOND).spoken, 'Next reset 16:00 \u00b7 in 10 minutes');
    assert.equal(pill(MINUTE).spoken, 'Next reset 16:00 \u00b7 in 1 minute');
    for (const left of [59 * SECOND, 23 * SECOND, SECOND]) {
      assert.equal(pill(left).spoken, 'Next reset 16:00 \u00b7 in 1 minute', `${left} ms left`);
    }
  });

  it('is urgent from 10 minutes before the reset (600 s or less), and not before', () => {
    assert.equal(pill(10 * MINUTE + SECOND).urgent, false);
    assert.equal(pill(10 * MINUTE).urgent, true);
    assert.equal(pill(MINUTE).urgent, true);
    assert.equal(pill(HOUR).urgent, false);
  });

  it('shows nothing without the online demo, without a reset or with an unreadable one', () => {
    assert.equal(pill(HOUR, false), undefined);
    assert.equal(pill(HOUR, true, ''), undefined);
    assert.equal(pill(HOUR, true, 'not a time'), undefined);
  });

  it('changes within a second of each whole minute, every second in the last minute and when it turns urgent', () => {
    const delay = (left) => pillDelayMs(iso(T), T - left);
    assert.equal(delay(HOUR + 42 * MINUTE + 30 * SECOND), 30 * SECOND + SECOND, 'the minute count drops one second before the whole minute');
    assert.equal(delay(30 * MINUTE), SECOND, 'on a whole minute: the next one is a minute on, one second early');
    assert.equal(delay(11 * MINUTE), SECOND, 'at 11:00 the minute count drops to 10 one second on');
    assert.equal(delay(10 * MINUTE + SECOND), SECOND, 'at 10:01 the next change is the urgent mark at 10:00');
    assert.equal(delay(10 * MINUTE + 30 * SECOND), 30 * SECOND, 'at 10:30 the next is the urgent mark at 10:00');
    assert.equal(delay(61 * SECOND), 2 * SECOND, 'at 1:01 the next is 0:59');
    assert.equal(delay(MINUTE), SECOND);
    assert.equal(delay(59_500), 500);
    assert.equal(delay(1500), 500);
    assert.equal(delay(1000), SECOND);
    assert.equal(pillDelayMs(iso(T), T), undefined, 'nothing to wait for at the reset');
    assert.equal(pillDelayMs('', T - HOUR), undefined);
    for (let left = 1; left < 3 * HOUR; left += 997) {
      const wait = pillDelayMs(iso(T), T - left);
      assert.ok(wait >= 1 && wait <= left, `a delay of ${wait} ms with ${left} ms left`);
      const before = pillView(true, iso(T), T - left, FORMAT);
      const after = pillView(true, iso(T), T - left + wait, FORMAT);
      const later = pillView(true, iso(T), T - left + wait - 1, FORMAT);
      assert.ok(before.text === later.text && before.urgent === later.urgent || wait === 1, `${left} ms left: nothing changes before the delay ends`);
      assert.ok(wait >= left || after.text !== before.text || after.urgent !== before.urgent, `${left} ms left: something changes when the delay ends`);
    }
  });
});

describe('the pending reset (row 11)', () => {
  it('is replaced by an earlier offer at any time', () => {
    assert.equal(offerReset(iso(T), iso(T - HOUR), T - 2 * MINUTE), iso(T - HOUR));
    assert.equal(offerReset(iso(T), iso(T - SECOND), T + HOUR), iso(T - SECOND));
  });

  it('is replaced by a later offer only while the clock is more than 300 s before it', () => {
    assert.equal(RESET_SOON_MS, 300_000);
    assert.equal(offerReset(iso(T), iso(T + 4 * HOUR), T - 6 * MINUTE), iso(T + 4 * HOUR));
    assert.equal(offerReset(iso(T), iso(T + 4 * HOUR), T - 5 * MINUTE), iso(T), 'at exactly 300 s it stays');
    assert.equal(offerReset(iso(T), iso(T + 4 * HOUR), T - 5 * MINUTE - 1), iso(T + 4 * HOUR));
    assert.equal(offerReset(iso(T), iso(T + 4 * HOUR), T + 10 * SECOND), iso(T));
  });

  it('keeps an equal offer and ignores an empty or unreadable one', () => {
    assert.equal(offerReset(iso(T), iso(T), T - HOUR), iso(T));
    assert.equal(offerReset(iso(T), '', T - HOUR), iso(T));
    assert.equal(offerReset(iso(T), 'not a time', T - HOUR), iso(T));
  });

  it('takes the first offer when there is none yet', () => {
    assert.equal(offerReset('', iso(T), T - HOUR), iso(T));
    assert.equal(offerReset('', '', T), '');
  });

  it('is due when the clock reaches it, and never with no reset', () => {
    assert.equal(isDue(iso(T), T - SECOND), false);
    assert.equal(isDue(iso(T), T), true);
    assert.equal(isDue(iso(T), T + HOUR), true);
    assert.equal(isDue('', T), false);
    assert.equal(isDue('not a time', T), false);
  });
});

describe('the reset-soon threshold', () => {
  it('is the same 300 s in Public.Settings, the splash script and the page', () => {
    const settings = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Data', 'Public', 'Settings.cls'), 'utf8');
    const splash = readFileSync(join(here, '..', 'src', 'signin', 'splash.js'), 'utf8');
    const server = /^Parameter RESETSOONSECONDS = (\d+);$/m.exec(settings);
    const script = /\bvar SOON_MS = (\d+);/.exec(splash);
    assert.ok(server && script, 'both thresholds are found');
    assert.equal(Number(server[1]) * SECOND, RESET_SOON_MS, 'Settings.RESETSOONSECONDS');
    assert.equal(Number(script[1]), RESET_SOON_MS, 'splash.js SOON_MS');
  });
});

describe('the splash address', () => {
  it('is /ocutalon/?since= and the time to the second, in UTC with Z', () => {
    assert.equal(splashAddress(Date.parse('2026-10-25T07:49:30.987Z')), '/ocutalon/?since=2026-10-25T07:49:30Z');
    assert.equal(utcSeconds(Date.parse('2026-10-25T07:49:30.987Z')), '2026-10-25T07:49:30Z');
  });

  it('adds &ended=1 after an epoch change (Story 16.4), and only then', () => {
    const loaded = Date.parse('2026-10-25T07:49:30.987Z');
    assert.equal(splashAddress(loaded, true), '/ocutalon/?since=2026-10-25T07:49:30Z&ended=1');
    assert.equal(splashAddress(loaded, false), '/ocutalon/?since=2026-10-25T07:49:30Z');
  });

  it('holds the load time, captured once when the module starts', () => {
    assert.equal(PAGE_LOADED_AT, utcSeconds(PAGE_LOADED_AT_MS));
    assert.ok(Math.abs(Date.now() - PAGE_LOADED_AT_MS) < 60_000);
  });
});

describe('what the status says', () => {
  it('reads the status JSON and nothing else', () => {
    assert.deepEqual(parseStatus({ ready: true, lastReset: '2026-10-25T16:00:00Z', busy: false }), { ready: true, lastReset: '2026-10-25T16:00:00Z' });
    assert.deepEqual(parseStatus({ ready: false, lastReset: null }), { ready: false, lastReset: null });
    for (const body of [undefined, null, 'x', 5, {}, { ready: 'yes' }, { ready: true, lastReset: 5 }]) {
      assert.equal(parseStatus(body), undefined, JSON.stringify(body));
    }
  });

  it('goes to the splash on ready with a last reset later than the load time, or 15 minutes past the reset', () => {
    const loaded = '2026-10-25T15:50:00Z';
    const ready = (lastReset) => ({ ready: true, lastReset });
    assert.equal(shouldNavigate(ready('2026-10-25T16:00:00Z'), loaded, iso(T), T + SECOND), true);
    assert.equal(shouldNavigate(ready(loaded), loaded, iso(T), T + SECOND), false, 'equal is not later');
    assert.equal(shouldNavigate(ready('2026-10-25T15:00:00Z'), loaded, iso(T), T + SECOND), false);
    assert.equal(shouldNavigate(ready(null), loaded, iso(T), T + SECOND), false);
    assert.equal(shouldNavigate({ ready: false, lastReset: '2026-10-25T16:00:00Z' }, loaded, iso(T), T + SECOND), false);
    assert.equal(shouldNavigate(undefined, loaded, iso(T), T + HOUR), false);
    assert.equal(RESET_WINDOW_MS, 15 * MINUTE);
    assert.equal(shouldNavigate(ready('2026-10-25T15:00:00Z'), loaded, iso(T), T + 15 * MINUTE - 1), false);
    assert.equal(shouldNavigate(ready('2026-10-25T15:00:00Z'), loaded, iso(T), T + 15 * MINUTE), true);
  });
});

/** A poller on a fake clock whose fetch answers from a script: each answer is a response, an Error to reject with, 'hang' or 'html'. */
function rig(answers, { loadedAt = '2026-10-25T15:50:00Z', startAt = T } = {}) {
  const clock = fakeClock();
  const calls = [];
  const navigations = [];
  let next = 0;
  const poller = new ResetPoller({
    fetch: (address, init) => {
      calls.push({ address, init, at: clock.now });
      const answer = answers[Math.min(next, answers.length - 1)];
      next += 1;
      if (answer === 'hang') return new Promise(() => undefined);
      if (answer instanceof Error) return Promise.reject(answer);
      if (answer === 'html') return Promise.resolve({ ok: true, json: () => Promise.reject(new SyntaxError('Unexpected token <')) });
      return Promise.resolve({ ok: true, json: () => Promise.resolve(answer) });
    },
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (handle) => clock.clearTimeout(handle),
    now: () => startAt + clock.now,
    loadedAt,
    pending: iso(T),
    target: '/ocutalon/?since=2026-10-25T15:50:00Z',
    navigate: (address) => navigations.push([address, clock.now]),
  });
  return { clock, calls, navigations, poller };
}

/** Lets the promises that a poll started settle. */
const settle = async () => {
  for (let i = 0; i < 10; i += 1) await Promise.resolve();
};

describe('waiting it out (row 12)', () => {
  it('asks at once and then every 10 s, with no credentials and no cache, and goes only on the answer with a last reset after the load', async () => {
    const { clock, calls, navigations, poller } = rig([
      new TypeError('network error'),
      'hang',
      'html',
      { ready: false, lastReset: null, busy: false },
      { ready: true, lastReset: '2026-10-25T15:00:00Z' },
      { ready: true, lastReset: iso(T) },
    ]);
    poller.start();
    await settle();
    assert.equal(calls.length, 1, 'one poll at once');
    for (let poll = 2; poll <= 6; poll += 1) {
      clock.advance(RESET_POLL_MS);
      await settle();
      assert.equal(calls.length, poll, `poll ${poll} after ${(poll - 1) * 10} s`);
      assert.deepEqual(navigations, poll < 6 ? [] : [['/ocutalon/?since=2026-10-25T15:50:00Z', 5 * RESET_POLL_MS]], `after poll ${poll}`);
    }
    for (const [index, call] of calls.entries()) {
      assert.match(call.address, new RegExp(`^/ocutalon/public/status\\?t=${index + 1}$`));
      assert.equal(call.init.credentials, 'omit');
      assert.equal(call.init.cache, 'no-store');
      assert.ok(call.init.signal instanceof AbortSignal);
    }
    clock.advance(5 * RESET_POLL_MS);
    await settle();
    assert.equal(calls.length, 6, 'it stopped polling');
    assert.equal(navigations.length, 1, 'and navigated once');
    assert.equal(clock.pending, 0, 'no timer is left');
  });

  it('gives up on a request after 3 s and aborts it', async () => {
    const { clock, calls, poller } = rig(['hang']);
    poller.start();
    await settle();
    assert.equal(STATUS_LIMIT_MS, 3000);
    assert.equal(calls[0].init.signal.aborted, false);
    clock.advance(STATUS_LIMIT_MS);
    await settle();
    assert.equal(calls[0].init.signal.aborted, true);
  });

  it('navigates once at the first ready answer 15 minutes past the reset, whatever its last reset', async () => {
    const { clock, calls, navigations, poller } = rig([{ ready: true, lastReset: '2026-10-25T15:00:00Z' }], { startAt: T + 15 * MINUTE - 15 * SECOND });
    poller.start();
    await settle();
    clock.advance(RESET_POLL_MS);
    await settle();
    assert.equal(navigations.length, 0, 'the 15 minutes have not passed at the second poll');
    clock.advance(RESET_POLL_MS);
    await settle();
    assert.equal(calls.length, 3);
    assert.equal(navigations.length, 1);
    clock.advance(60 * SECOND);
    await settle();
    assert.equal(navigations.length, 1, 'once');
    assert.equal(calls.length, 3);
  });

  it('counts a non-ok response as not ready, and says nothing for a failed poll', async () => {
    const clock = fakeClock();
    const navigations = [];
    const poller = new ResetPoller({
      fetch: () => Promise.resolve({ ok: false, json: () => Promise.resolve({ ready: true, lastReset: iso(T) }) }),
      setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
      clearTimeout: (handle) => clock.clearTimeout(handle),
      now: () => T,
      loadedAt: '2026-10-25T15:50:00Z',
      pending: iso(T),
      target: '/ocutalon/',
      navigate: (address) => navigations.push(address),
    });
    poller.start();
    await settle();
    clock.advance(RESET_POLL_MS);
    await settle();
    assert.deepEqual(navigations, []);
    poller.stop();
    assert.equal(clock.pending, 0);
  });

  it('does not navigate after stop()', async () => {
    const { clock, navigations, poller } = rig([{ ready: true, lastReset: iso(T) }]);
    poller.start();
    poller.stop();
    await settle();
    clock.advance(RESET_POLL_MS);
    await settle();
    assert.deepEqual(navigations, []);
  });
});
