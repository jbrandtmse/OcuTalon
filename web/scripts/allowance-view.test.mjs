// Tests the page's view of the session's message allowance (src/app/live/allowance-view.ts, Story 16.9; AD-12, AD-20): the window that
// holds is the store's active allowance condition or the last 429 refusal, whichever has a time still ahead on the page's clock (the
// later one when both do), and nothing once the time has passed, which is how the banner, the composer and the guide's prompts clear at
// the time. refusalOf reads the body of a 429 answer by its code, and nextChange gives the time a timer is set to. The module is imported
// as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { allowanceOf, nextChange, refusalOf } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'live', 'allowance-view.ts')).href);

const NOW = Date.parse('2030-01-01T10:00:00Z');
const AHEAD = '2030-01-01T10:20:00Z';
const LATER = '2030-01-01T10:40:00Z';
const PAST = '2030-01-01T09:59:59Z';

const condition = (slots, active = true) => ({ condition: 'allowance', active, slots });
const refusal = (retryAt, limit) => ({ limit, retryAt });

describe('allowanceOf', () => {
  it('gives the store\'s active condition while its time is ahead, with its limit and time', () => {
    assert.deepEqual(allowanceOf(condition({ limit: 50, time: AHEAD }), undefined, NOW), { limit: 50, time: AHEAD });
  });

  it('gives a 429 refusal while its retryAt is ahead, with its limit and retryAt as the time', () => {
    assert.deepEqual(allowanceOf(undefined, refusal(AHEAD, 50), NOW), { limit: 50, time: AHEAD });
  });

  it('gives the later of the two when both are ahead, and the store\'s on a tie', () => {
    assert.deepEqual(allowanceOf(condition({ limit: 50, time: AHEAD }), refusal(LATER, 40), NOW), { limit: 40, time: LATER });
    assert.deepEqual(allowanceOf(condition({ limit: 50, time: LATER }), refusal(AHEAD, 40), NOW), { limit: 50, time: LATER });
    assert.deepEqual(allowanceOf(condition({ limit: 50, time: AHEAD }), refusal(AHEAD, 40), NOW), { limit: 50, time: AHEAD });
  });

  it('gives the one that is ahead when the other has passed', () => {
    assert.deepEqual(allowanceOf(condition({ limit: 50, time: PAST }), refusal(AHEAD, 40), NOW), { limit: 40, time: AHEAD });
    assert.deepEqual(allowanceOf(condition({ limit: 50, time: AHEAD }), refusal(PAST, 40), NOW), { limit: 50, time: AHEAD });
  });

  it('gives nothing once the time has passed, at the time itself included, on the page\'s clock', () => {
    assert.equal(allowanceOf(condition({ limit: 50, time: PAST }), undefined, NOW), undefined, 'a past time');
    assert.equal(allowanceOf(condition({ limit: 50, time: AHEAD }), undefined, Date.parse(AHEAD)), undefined, 'the store\'s time itself');
    assert.equal(allowanceOf(undefined, refusal(AHEAD, 50), Date.parse(AHEAD)), undefined, 'the refusal\'s time itself');
    assert.notEqual(allowanceOf(condition({ limit: 50, time: AHEAD }), undefined, Date.parse(AHEAD) - 1), undefined, 'a millisecond before it');
  });

  it('gives nothing for no condition and no refusal, an inactive or unreadable condition and an unreadable refusal', () => {
    assert.equal(allowanceOf(undefined, undefined, NOW), undefined);
    assert.equal(allowanceOf(condition({ limit: 50, time: AHEAD }, false), undefined, NOW), undefined, 'an inactive condition');
    assert.equal(allowanceOf({ condition: 'allowance', active: true }, undefined, NOW), undefined, 'an active one with no slots');
    assert.equal(allowanceOf(condition({ limit: 50 }), undefined, NOW), undefined, 'and with no time');
    assert.equal(allowanceOf(condition({ limit: 50, time: 'soon' }), undefined, NOW), undefined, 'and with a time that is not one');
    assert.equal(allowanceOf(undefined, refusal('soon', 50), NOW), undefined, 'a refusal with a time that is not one');
  });

  it('keeps the window when the limit is unknown, with no limit', () => {
    assert.deepEqual(allowanceOf(condition({ time: AHEAD }), undefined, NOW), { limit: undefined, time: AHEAD });
    assert.deepEqual(allowanceOf(condition({ limit: 0, time: AHEAD }), undefined, NOW), { limit: undefined, time: AHEAD });
    assert.deepEqual(allowanceOf(undefined, refusal(AHEAD, undefined), NOW), { limit: undefined, time: AHEAD });
  });
});

describe('nextChange', () => {
  it('is the earliest time that is ahead, in milliseconds', () => {
    assert.equal(nextChange(condition({ limit: 50, time: AHEAD }), refusal(LATER, 50), NOW), Date.parse(AHEAD));
    assert.equal(nextChange(undefined, refusal(LATER, 50), NOW), Date.parse(LATER));
    assert.equal(nextChange(condition({ limit: 50, time: PAST }), refusal(LATER, 50), NOW), Date.parse(LATER), 'a time that has passed is not ahead');
  });

  it('is undefined when no time is ahead', () => {
    assert.equal(nextChange(undefined, undefined, NOW), undefined);
    assert.equal(nextChange(condition({ limit: 50, time: PAST }), refusal(PAST, 50), NOW), undefined);
    assert.equal(nextChange(condition({ limit: 50, time: AHEAD }, false), undefined, NOW), undefined, 'an inactive condition');
  });
});

describe('refusalOf', () => {
  const failure = (status, body) => ({ status, error: body });
  const body = (code, over = {}) => ({ error: { code, message: 'zz' }, retryAt: AHEAD, limit: 50, ...over });

  it('reads the limit and the retryAt of a 429 allowance', () => {
    assert.deepEqual(refusalOf(failure(429, body('allowance')), 'allowance'), { limit: 50, retryAt: AHEAD });
  });

  it('reads the retryAt of a 429 email_limit, which has no limit', () => {
    assert.deepEqual(refusalOf(failure(429, body('email_limit', { limit: undefined })), 'email_limit'), { limit: undefined, retryAt: AHEAD });
  });

  it('reads the code asked for only, and only a 429', () => {
    assert.equal(refusalOf(failure(429, body('email_limit')), 'allowance'), undefined);
    assert.equal(refusalOf(failure(429, body('allowance')), 'email_limit'), undefined);
    assert.equal(refusalOf(failure(500, body('allowance')), 'allowance'), undefined);
    assert.equal(refusalOf(failure(503, body('allowance')), 'allowance'), undefined);
  });

  it('reads nothing from a failure that has no such body, without throwing', () => {
    for (const value of [undefined, null, 'x', 42, {}, { status: 429 }, failure(429, null), failure(429, 'text'), failure(429, {}), failure(429, { error: null }), failure(429, body('allowance', { retryAt: undefined })), failure(429, body('allowance', { retryAt: 'soon' })), failure(429, body('allowance', { retryAt: 5 }))]) {
      assert.equal(refusalOf(value, 'allowance'), undefined, JSON.stringify(value));
    }
  });

  it('drops a limit that is not a count of one or more', () => {
    for (const limit of [0, -1, 'fifty', null, Number.NaN]) {
      assert.deepEqual(refusalOf(failure(429, body('allowance', { limit })), 'allowance'), { limit: undefined, retryAt: AHEAD }, String(limit));
    }
  });
});
