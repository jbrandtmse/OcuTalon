// Tests the time of a chat entry (src/app/chat/page-time.ts): hour and minute in a named zone and locale, no zone suffix,
// and the browser's own zone and locale by default. The module is imported as it is: Node strips its types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { pageTime } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'page-time.ts')).href);

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
