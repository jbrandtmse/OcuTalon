// Tests the time of a chat entry (src/app/chat/page-time.ts): hour and minute in a named zone and locale, no zone suffix,
// and the browser's own zone and locale by default. The module is imported as it is: Node strips its types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { pageTime, pageTimeBeside } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'page-time.ts')).href);

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
