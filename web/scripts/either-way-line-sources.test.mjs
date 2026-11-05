// Story 7.8, AC 5: "no other file under web/src/app holds the words". The approval-sources test reads only the approvals folder; this
// reads every source under web/src/app (.ts, .js, .html, .css; comments included, so not even a doc quotes the line) and finds U-249's
// either-way line in the generated page catalog (msg/catalog.ts) alone. The words are cut from Msg/Catalog/Watch.cls by catalog.mjs, so a
// second typed copy anywhere on the page is a copy that can drift from the notice's text (DW-655 is that kind of defect).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');

/** The one file that holds the line: the generated page catalog. */
const CATALOG = 'msg/catalog.ts';

/** Fragments that belong to the line alone, one of each form (the many form and the one form). */
const FRAGMENTS = ['valid whether read month first or day first', 'they match the day each', 'it matches the day the'];

const files = sourceFiles(app, ['.ts', '.js', '.html', '.css']);

describe('the either-way line (Story 7.8; AC 5)', () => {
  it('scans the app, the approvals folder and the generated catalog', () => {
    const names = files.map((one) => one.name);
    for (const expected of [CATALOG, 'approvals/approval-view.ts', 'approvals/approval-request-card.ts', 'chat/chat-panel.ts']) {
      assert.ok(names.includes(expected), `${expected} is scanned`);
    }
  });

  it('is typed in the generated catalog and in no other source of the page', () => {
    for (const fragment of FRAGMENTS) {
      const holders = files.filter((one) => one.text.includes(fragment)).map((one) => one.name);
      assert.deepEqual(holders, [CATALOG], `"${fragment}" is held by the catalog alone`);
    }
  });

  it('is typed in the catalog once as the many form and once as the one form', () => {
    const catalog = files.find((one) => one.name === CATALOG).text;
    const count = (fragment) => catalog.split(fragment).length - 1;
    assert.equal(count(FRAGMENTS[0]), 2, 'the sentence opens the many form and the one form (as "dates are valid" and "date is valid", one fragment each)');
    assert.equal(count(FRAGMENTS[1]), 1, 'one many form');
    assert.equal(count(FRAGMENTS[2]), 1, 'one one form');
  });
});
