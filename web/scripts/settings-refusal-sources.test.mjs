// Tests the shape of the settings sources that Story 18.3 relies on (DW-948, AD-12): every section that saves or sends classifies a refused or failed call with the one
// shared refusalOf and keeps no status check of its own for 400 or 403 (the page's own load keeps its 403 check); and the banner stack passes the snapshot's admin flag to the banner view, so that the cost-cap
// banner's Budgets action is admin only. The browser cases (S13b, S14, B3b) pin what the running page does; this reads the sources, so a section that goes back to its
// own copy of the classifier turns it red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const files = sourceFiles(join(here, '..', 'src'), ['.ts']);
const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

const SAVING = ['budgets', 'check-thresholds', 'daily-digest', 'demo-mode', 'models', 'on-call', 'time-zone'];

describe('the settings sections share one refusal classifier', () => {
  for (const name of SAVING) {
    it(`${name}-section.ts reads a refusal through refusalOf and keeps no 400 or 403 check of its own`, () => {
      const one = file(`app/settings/${name}-section.ts`);
      assert.match(one.code, /import \{[^}]*\brefusalOf\b[^}]*\} from '\.\/refusal'/, 'it imports refusalOf');
      assert.match(one.code, /\brefusalOf\(/, 'and calls it');
      assert.doesNotMatch(one.code, /\.status\s*===?\s*(400|403)\b/, 'with no status check for 400 or 403 of its own');
    });
  }
});

describe('the banner stack gives the banner view the admin flag', () => {
  it('banner-stack.ts reads it from the snapshot', () => {
    assert.match(file('app/banners/banner-stack.ts').code, /admin:\s*this\.live\.snapshot\(\)\?\.admin === true/);
  });
});
