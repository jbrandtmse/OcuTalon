// Tests the sentence above the check rows (src/app/shared/check-sentence.ts, DW-90): the three keys without a slot give the catalog
// text as it is and never an all-clear from the rows (N1), the two keys that name what failed fill {whatFailed} from the rows that did
// not pass (failed rows first, then the others, never a passed row), an empty part is left out, a row with no entry is skipped, a key
// with nothing to name gives no sentence, and any other key gives none. The module and the generated catalog are imported as they are,
// with a stub time function.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { CHECK_TEXTS, checkSentence, whatFailed } = await import(app('shared', 'check-sentence.ts'));
const { PAGE_SLOTS, PAGE_TEXTS, renderPageText } = await import(app('msg', 'catalog.ts'));

const CATALOG = { texts: PAGE_TEXTS, slots: PAGE_SLOTS, render: renderPageText };
/** A stub for the page's time: the clock of the UTC stamp, "" for none. */
const time = (iso) => (iso === '' ? '' : iso.slice(11, 16));

const PASSED = { result: 'passed', entry: 'Inventory production', finding: '', checkedAt: '2026-10-26T14:10:00Z' };
const FAILED = { result: 'failed', entry: 'Orders production', finding: '3 new failures', checkedAt: '2026-10-26T14:13:00Z' };
const NOT_CHECKED = { result: 'not_checked', entry: 'Billing production', finding: 'No answer in time', checkedAt: '2026-10-26T14:12:00Z' };
const NOT_RUN = { result: 'not_checked', entry: 'Shipping production', finding: 'Not run yet', checkedAt: '' };

describe('the strings', () => {
  it('are the four forms of a named row and of the list', () => {
    assert.deepEqual({ ...CHECK_TEXTS }, { entry: '{entry} ({detail})', detail: '{finding}, at {time}', detailTime: 'at {time}', separator: '; ' });
  });
});

describe('whatFailed', () => {
  it('names a failed row as {entry} ({finding}, at {time}), with the first letter of the finding in lower case', () => {
    assert.equal(whatFailed([FAILED], time), 'Orders production (3 new failures, at 14:13)');
    assert.equal(whatFailed([NOT_CHECKED], time), 'Billing production (no answer in time, at 14:12)');
  });

  it('leaves out an empty part', () => {
    assert.equal(whatFailed([{ ...FAILED, checkedAt: '' }], time), 'Orders production (3 new failures)');
    assert.equal(whatFailed([{ ...FAILED, finding: '' }], time), 'Orders production (at 14:13)');
    assert.equal(whatFailed([{ ...FAILED, finding: '', checkedAt: '' }], time), 'Orders production');
    assert.equal(whatFailed([{ ...FAILED, finding: undefined, checkedAt: undefined }], time), 'Orders production');
    assert.equal(whatFailed([NOT_RUN], time), 'Shipping production (not run yet)');
    assert.equal(whatFailed([FAILED], () => ''), 'Orders production (3 new failures)', 'a time the page cannot read');
  });

  it('names every row that did not pass, the failed rows first and then the others, each group in row order, and never a passed row', () => {
    const rows = [NOT_CHECKED, PASSED, { ...FAILED, entry: 'Orders A' }, NOT_RUN, { ...FAILED, entry: 'Orders B' }];
    assert.equal(
      whatFailed(rows, time),
      'Orders A (3 new failures, at 14:13); Orders B (3 new failures, at 14:13); Billing production (no answer in time, at 14:12); Shipping production (not run yet)',
    );
    assert.equal(whatFailed([PASSED], time), '');
    assert.equal(whatFailed([PASSED, { ...PASSED, entry: 'B' }], time), '');
  });

  it('names a row whose result is none of the known ones, as not passed', () => {
    assert.equal(whatFailed([{ ...FAILED, result: 'zz' }, { ...FAILED, result: undefined, entry: 'B' }], time), 'Orders production (3 new failures, at 14:13); B (3 new failures, at 14:13)');
  });

  it('skips a row with an empty entry, and gives "" for no rows', () => {
    assert.equal(whatFailed([{ ...FAILED, entry: '' }, { ...FAILED, entry: '  ' }, { ...FAILED, entry: undefined }], time), '');
    assert.equal(whatFailed([{ ...FAILED, entry: '' }, NOT_CHECKED], time), 'Billing production (no answer in time, at 14:12)');
    assert.equal(whatFailed([], time), '');
  });

  it('reads a value as text, never as a placeholder', () => {
    assert.equal(whatFailed([{ ...FAILED, entry: '{finding}', finding: '{time}' }], time), '{finding} ({time}, at 14:13)');
  });
});

describe('checkSentence', () => {
  it('gives the catalog text of the three keys without a slot, as it is, whatever the rows say', () => {
    const rows = [FAILED, NOT_CHECKED];
    assert.equal(checkSentence('checks.allPassed', rows, CATALOG, time), 'Everything I checked passed.');
    assert.equal(checkSentence('checks.everythingElsePassed', rows, CATALOG, time), 'Everything else I checked passed.');
    assert.equal(checkSentence('checks.nothingWatched', rows, CATALOG, time), "I'm not watching any productions yet, so I can't say. Ask me to watch one.");
    assert.equal(checkSentence('checks.allPassed', [], CATALOG, time), 'Everything I checked passed.', 'the key decides, not the rows');
  });

  it('never derives an all-clear from the rows', () => {
    const passed = [PASSED, { ...PASSED, entry: 'B' }];
    for (const key of ['checks.notEverything', 'checks.notEverythingRestPassed', 'conversation.turnFallback', '']) {
      assert.equal(checkSentence(key, passed, CATALOG, time), '', key);
    }
    for (const key of ['checks.notEverything', 'checks.notEverythingRestPassed']) {
      assert.ok(!/passed/.test(checkSentence(key, [FAILED], CATALOG, time).replace('Everything else I checked passed.', '')), key);
    }
  });

  it('fills whatFailed of checks.notEverything', () => {
    assert.equal(checkSentence('checks.notEverything', [FAILED], CATALOG, time), 'Not everything: Orders production (3 new failures, at 14:13).');
    assert.equal(
      checkSentence('checks.notEverything', [NOT_CHECKED, FAILED], CATALOG, time),
      'Not everything: Orders production (3 new failures, at 14:13); Billing production (no answer in time, at 14:12).',
    );
  });

  it('fills whatFailed of checks.notEverythingRestPassed from the rows that did not pass, and names no passed row', () => {
    assert.equal(
      checkSentence('checks.notEverythingRestPassed', [PASSED, NOT_CHECKED, FAILED], CATALOG, time),
      'Not everything: Orders production (3 new failures, at 14:13); Billing production (no answer in time, at 14:12). Everything else I checked passed.',
    );
  });

  it('gives no sentence when the key needs whatFailed and no row is left to name', () => {
    for (const key of ['checks.notEverything', 'checks.notEverythingRestPassed']) {
      assert.equal(checkSentence(key, [], CATALOG, time), '', key);
      assert.equal(checkSentence(key, [PASSED], CATALOG, time), '', key);
      assert.equal(checkSentence(key, [{ ...FAILED, entry: '' }], CATALOG, time), '', key);
    }
  });

  it('gives no sentence for any other key, or for a key the catalog does not hold', () => {
    for (const key of ['conversation.turnFallback', 'banner.dailyCap', 'checks.other', 'checks.', 'constructor', '__proto__', '']) {
      assert.equal(checkSentence(key, [FAILED], CATALOG, time), '', key);
    }
    const bare = { texts: {}, slots: {}, render: renderPageText };
    assert.equal(checkSentence('checks.allPassed', [], bare, time), '');
    assert.equal(checkSentence('checks.notEverything', [FAILED], bare, time), '');
    const noSlot = { texts: PAGE_TEXTS, slots: {}, render: renderPageText };
    assert.equal(checkSentence('checks.notEverything', [FAILED], noSlot, time), '', 'a key whose slot the catalog does not declare');
  });
});
