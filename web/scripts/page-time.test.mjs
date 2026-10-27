// Tests the times of the page (src/app/chat/page-time.ts): hour and minute in a named zone and locale, no zone suffix, and the
// browser's own zone and locale by default; the day words of pageWhen (the same date, tomorrow, up to six dates either way, a
// short date with the year only when it differs) in the zone named, across the date line; and the countdown (seconds rounded up,
// minutes rounded down, both units from an hour, never below 0 s) with its spoken form. The module is imported as it is: Node
// strips its types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { WHEN_TEXTS, countdownText, elapsedText, pageTime, pageTimeBeside, pageWhen } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'page-time.ts')).href);

const INSTANT = '2026-10-22T14:11:00Z';

/**
 * The text with the space before the day period read as one: some ICU data put U+202F, the narrow no-break space, there and
 * other data a plain space (Node 26 with ICU 78 gives the plain space), so a runtime may carry either.
 */
const spaced = (text) => text.replace(/\u202F/g, ' ');

describe('pageTime', () => {
  it('writes the hour and minute in the zone and the hour format asked for', () => {
    const india = pageTime(INSTANT, 'en-US', 'Asia/Kolkata');
    assert.equal(spaced(india), '7:41 PM');
    assert.match(india, /^7:41[ \u202F]PM$/);
    assert.equal(pageTime(INSTANT, 'en-GB', 'Europe/Berlin'), '16:11');
  });

  it('follows the zone through its offset: 14:11 UTC is 10:11 AM in New York in October', () => {
    assert.equal(spaced(pageTime(INSTANT, 'en-US', 'America/New_York')), '10:11 AM');
  });

  it('holds no seconds, no date and no zone name', () => {
    for (const [locale, zone] of [['en-US', 'Asia/Kolkata'], ['en-GB', 'Europe/Berlin'], ['de-DE', 'UTC']]) {
      const text = pageTime('2026-10-22T14:11:42Z', locale, zone);
      assert.ok(!/\d:\d\d:\d\d/.test(text), `no seconds in ${text}`);
      assert.ok(!/UTC|GMT|IST|CEST|20\d\d|\//.test(text), `no zone or date in ${text}`);
    }
  });

  it('uses the browser\'s own zone and locale when none is named', () => {
    const own = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(INSTANT));
    assert.equal(pageTime(INSTANT), own);
  });

  it('answers an empty text for an empty or unreadable time', () => {
    assert.equal(pageTime(''), '');
    assert.equal(pageTime('not a time'), '');
  });
});

describe('pageTimeBeside', () => {
  const SUMMER = '2026-07-15T12:00:00Z';
  const WINTER = '2026-01-15T12:00:00Z';

  it('adds no zone name in the instance\'s own zone: 12:00 stays 12:00', () => {
    assert.equal(pageTimeBeside(SUMMER, 'UTC', 'en-GB', 'UTC'), '12:00');
    assert.equal(spaced(pageTimeBeside(SUMMER, 'America/New_York', 'en-US', 'America/New_York')), '8:00 AM');
  });

  it('names the browser\'s zone when its offset differs: Berlin in en-GB reads 14:00 CEST in summer and 13:00 CET in winter', () => {
    assert.equal(pageTimeBeside(SUMMER, 'UTC', 'en-GB', 'Europe/Berlin'), '14:00 CEST');
    assert.equal(pageTimeBeside(WINTER, 'UTC', 'en-GB', 'Europe/Berlin'), '13:00 CET');
  });

  it('names a zone that has no abbreviation in the locale by its offset: Kolkata in en-US is GMT+5:30', () => {
    const text = pageTimeBeside('2026-10-22T14:11:00Z', 'UTC', 'en-US', 'Asia/Kolkata');
    assert.equal(spaced(text), '7:41 PM GMT+5:30');
    assert.match(text, /^7:41[ \u202F]PM GMT\+5:30$/);
  });

  it('compares offsets at the instant, not zone names: London in January and UTC read alike, London in July does not', () => {
    assert.equal(pageTimeBeside(WINTER, 'UTC', 'en-GB', 'Europe/London'), '12:00');
    assert.equal(pageTimeBeside(SUMMER, 'UTC', 'en-GB', 'Europe/London'), '13:00 BST');
    assert.equal(pageTimeBeside(WINTER, 'Europe/London', 'en-GB', 'UTC'), '12:00');
    assert.equal(pageTimeBeside(SUMMER, 'Europe/Berlin', 'en-GB', 'Europe/Paris'), '14:00', 'two names, one offset');
  });

  it('shows the name when the instance zone is not a valid zone, or is empty', () => {
    assert.equal(pageTimeBeside(SUMMER, 'Not/AZone', 'en-GB', 'UTC'), '12:00 UTC');
    assert.equal(pageTimeBeside(SUMMER, '', 'en-GB', 'UTC'), '12:00 UTC');
  });

  it('uses the browser\'s own zone and locale when none is named', () => {
    const own = Intl.DateTimeFormat().resolvedOptions().timeZone;
    assert.equal(pageTimeBeside(SUMMER, own), pageTime(SUMMER), 'in the instance zone');
  });

  it('answers an empty text for an empty or unreadable time, whatever the zones', () => {
    assert.equal(pageTimeBeside('', 'UTC', 'en-GB', 'Europe/Berlin'), '');
    assert.equal(pageTimeBeside('not a time', 'Not/AZone', 'en-GB', 'Europe/Berlin'), '');
  });
});

describe('pageWhen', () => {
  /** Wednesday 7 October 2026. */
  const NOW = Date.parse('2026-10-07T14:11:00Z');
  const when = (iso, now = NOW, locale = 'en-GB', zone = 'UTC') => spaced(pageWhen(iso, now, locale, zone));

  it('writes the time alone on the same date', () => {
    assert.equal(when('2026-10-07T14:13:00Z'), '14:13');
    assert.equal(when('2026-10-07T23:59:00Z'), '23:59');
  });

  it('writes "tomorrow at" on the next date, and the weekday for up to six dates either way', () => {
    assert.equal(when('2026-10-08T14:13:00Z'), 'tomorrow at 14:13');
    assert.equal(when('2026-10-04T14:13:00Z'), 'Sunday at 14:13', '3 days back');
    assert.equal(when('2026-10-06T14:13:00Z'), 'Tuesday at 14:13', 'yesterday');
    assert.equal(when('2026-10-13T14:13:00Z'), 'Tuesday at 14:13', '6 days on');
    assert.equal(when('2026-10-01T14:13:00Z'), 'Thursday at 14:13', '6 days back');
  });

  it('writes the short date from the seventh date on, with the year only when it differs', () => {
    assert.equal(when('2026-10-14T14:13:00Z'), 'Oct 14 at 14:13', '7 days on');
    assert.equal(when('2026-09-30T14:13:00Z'), 'Sep 30 at 14:13', '7 days back');
    assert.equal(when('2026-10-17T14:12:00Z'), 'Oct 17 at 14:12', '10 days on');
    assert.equal(when('2025-10-17T14:12:00Z'), 'Oct 17, 2025 at 14:12', 'another year');
    assert.equal(when('2027-01-05T14:05:00Z'), 'Jan 5, 2027 at 14:05');
  });

  it('keeps the weekday across a new year when the dates are within six days', () => {
    assert.equal(when('2027-01-02T14:13:00Z', Date.parse('2026-12-30T10:00:00Z')), 'Saturday at 14:13');
    assert.equal(when('2027-01-01T14:13:00Z', Date.parse('2026-12-31T10:00:00Z')), 'tomorrow at 14:13');
  });

  it('writes the hour in the format asked for: 12-hour in en-US', () => {
    assert.equal(when('2026-10-07T14:13:00Z', NOW, 'en-US'), '2:13 PM');
    assert.equal(when('2026-10-08T14:13:00Z', NOW, 'en-US'), 'tomorrow at 2:13 PM');
    assert.equal(when('2026-10-17T14:12:00Z', NOW, 'en-US'), 'Oct 17 at 2:12 PM');
  });

  it('counts the dates in the zone named, across the date line: Berlin is two hours ahead of UTC in October', () => {
    const late = Date.parse('2026-10-07T22:30:00Z');
    assert.equal(when('2026-10-08T10:00:00Z', late, 'en-GB', 'UTC'), 'tomorrow at 10:00', 'in UTC it is the next date');
    assert.equal(when('2026-10-08T10:00:00Z', late, 'en-GB', 'Europe/Berlin'), '12:00', 'in Berlin both are 8 October');
    assert.equal(when('2026-10-07T21:30:00Z', late, 'en-GB', 'UTC'), '21:30', 'in UTC both are 7 October');
    assert.equal(when('2026-10-07T21:30:00Z', late, 'en-GB', 'Europe/Berlin'), 'Wednesday at 23:30', 'in Berlin it is yesterday');
    assert.equal(when('2026-10-07T22:30:00Z', late, 'en-US', 'America/New_York'), '6:30 PM');
  });

  it('uses English day and month names whatever the locale is', () => {
    assert.equal(when('2026-10-08T14:13:00Z', NOW, 'de-DE'), 'tomorrow at 14:13');
    assert.equal(when('2026-10-04T14:13:00Z', NOW, 'de-DE'), 'Sunday at 14:13');
    assert.equal(when('2026-10-17T14:12:00Z', NOW, 'de-DE'), 'Oct 17 at 14:12');
  });

  it('uses the browser\'s own zone and locale when none is named: the same instant reads as pageTime', () => {
    assert.equal(pageWhen(INSTANT, Date.parse(INSTANT)), pageTime(INSTANT));
  });

  it('answers an empty text for an empty or unreadable time', () => {
    assert.equal(pageWhen('', NOW, 'en-GB', 'UTC'), '');
    assert.equal(pageWhen('not a time', NOW, 'en-GB', 'UTC'), '');
  });

  it('holds the day words written out, in ASCII', () => {
    assert.deepEqual([...WHEN_TEXTS.weekdays], ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']);
    assert.deepEqual([...WHEN_TEXTS.months], ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']);
    assert.equal(WHEN_TEXTS.tomorrowAt, 'tomorrow at {time}');
    for (const value of Object.values(WHEN_TEXTS).flat()) {
      assert.match(value, /^[\x20-\x7e]+$/);
    }
  });
});

describe('countdownText', () => {
  const NOW = 1_000_000_000_000;
  const left = (ms) => countdownText(new Date(NOW + ms).toISOString(), NOW);
  const SECOND = 1000;
  const MINUTE = 60 * SECOND;
  const HOUR = 60 * MINUTE;

  it('counts seconds under a minute: 23 s', () => {
    assert.deepEqual(left(23 * SECOND), { text: 'in 23 s', spoken: 'in 23 seconds' });
    assert.deepEqual(left(SECOND), { text: 'in 1 s', spoken: 'in 1 second' });
    assert.deepEqual(left(59 * SECOND), { text: 'in 59 s', spoken: 'in 59 seconds' });
  });

  it('rounds the seconds up: 22.2 s is 23 s, and 59.2 s is a minute', () => {
    assert.equal(left(22_200).text, 'in 23 s');
    assert.equal(left(59_200).text, 'in 1 min');
    assert.equal(left(1).text, 'in 1 s');
  });

  it('counts whole minutes, rounded down, under an hour: 9 min 30 s is 9 min', () => {
    assert.deepEqual(left(9 * MINUTE + 30 * SECOND), { text: 'in 9 min', spoken: 'in 9 minutes' });
    assert.deepEqual(left(MINUTE), { text: 'in 1 min', spoken: 'in 1 minute' });
    assert.deepEqual(left(59 * MINUTE + 59 * SECOND), { text: 'in 59 min', spoken: 'in 59 minutes' });
  });

  it('counts hours and minutes from one hour, always with both units', () => {
    assert.deepEqual(left(HOUR + 42 * MINUTE), { text: 'in 1 h 42 min', spoken: 'in 1 hour 42 minutes' });
    assert.deepEqual(left(2 * HOUR), { text: 'in 2 h 0 min', spoken: 'in 2 hours 0 minutes' });
    assert.deepEqual(left(HOUR + MINUTE), { text: 'in 1 h 1 min', spoken: 'in 1 hour 1 minute' });
    assert.deepEqual(left(3 * HOUR + 59 * MINUTE + 59 * SECOND), { text: 'in 3 h 59 min', spoken: 'in 3 hours 59 minutes' });
    assert.equal(left(HOUR - 500).text, 'in 1 h 0 min', '59 min 59.5 s counts as an hour');
  });

  it('never goes below 0 s: due now and past due are "in 0 s"', () => {
    assert.deepEqual(left(0), { text: 'in 0 s', spoken: 'in 0 seconds' });
    assert.deepEqual(left(-5 * SECOND), { text: 'in 0 s', spoken: 'in 0 seconds' });
    assert.deepEqual(left(-3 * HOUR), { text: 'in 0 s', spoken: 'in 0 seconds' });
  });

  it('answers empty texts for an empty or unreadable time', () => {
    assert.deepEqual(countdownText('', NOW), { text: '', spoken: '' });
    assert.deepEqual(countdownText('not a time', NOW), { text: '', spoken: '' });
  });
});

describe('elapsedText', () => {
  const NOW = 1_000_000_000_000;
  const since = (ms) => elapsedText(new Date(NOW - ms).toISOString(), NOW);
  const SECOND = 1000;

  it('counts seconds under a minute: 23 s, spoken in full words with the singular for 1', () => {
    assert.deepEqual(since(0), { text: '0 s', spoken: '0 seconds' });
    assert.deepEqual(since(SECOND), { text: '1 s', spoken: '1 second' });
    assert.deepEqual(since(23 * SECOND), { text: '23 s', spoken: '23 seconds' });
    assert.deepEqual(since(59 * SECOND), { text: '59 s', spoken: '59 seconds' });
  });

  it('rounds the seconds down, and counts whole minutes from 60 s', () => {
    assert.equal(since(59_999).text, '59 s');
    assert.deepEqual(since(60 * SECOND), { text: '1 min', spoken: '1 minute' });
    assert.deepEqual(since(119 * SECOND), { text: '1 min', spoken: '1 minute' });
    assert.deepEqual(since(180 * SECOND), { text: '3 min', spoken: '3 minutes' });
  });

  it('is never below 0: a time ahead of the clock reads 0 s', () => {
    assert.deepEqual(since(-5 * SECOND), { text: '0 s', spoken: '0 seconds' });
  });

  it('gives empty texts for an empty or unreadable time', () => {
    assert.deepEqual(elapsedText('', NOW), { text: '', spoken: '' });
    assert.deepEqual(elapsedText('not a time', NOW), { text: '', spoken: '' });
  });
});
