// Pins Story 11.7's AC6 (the retired route): the marker route that Story 11.1 used to start step 2's watch is gone for good. Its marker
// scenario in the A/ tree, the web run's message helper, the countdown helper and the online run's watch-text constant were replaced by
// the guide's own Send and the keyed B/guide-* scenarios (U-194), so no file outside the kit's folders (_bmad-output/ and _bmad/, where
// records and rules may name them) may name them again and the scenario file may not come back. The four names are built from parts
// below, so that this file does not match its own search. The search reads every file that git tracks or would track (so an uncommitted
// file counts too, and an ignored file such as the IRIS reference folders does not).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const RETIRED = [
  ['watch', 'act', 'orders'].join('-'),
  ['watch', 'Message'].join(''),
  ['arm', 'Countdown'].join(''),
  ['WATCH', 'MESSAGE'].join('_'),
];

const files = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' })
  .split('\0')
  .filter((f) => f && !f.startsWith('_bmad-output/') && !f.startsWith('_bmad/') && existsSync(join(root, f)));

describe('the retired marker route of Story 11.1 (Story 11.7, AC6)', () => {
  it('searches a real tree: the repository lists files, among them this one', () => {
    assert.ok(files.length > 100, `${files.length} files listed`);
    assert.ok(files.includes('web/scripts/retired-demo-path-names.test.mjs'), 'this test is in the list');
  });

  it('keeps the marker scenario file out of the A/ tree', () => {
    assert.equal(existsSync(join(root, 'ci', 'mock', 'scenarios', 'A', `${RETIRED[0]}.json`)), false);
  });

  for (const name of RETIRED) {
    it(`names ${name} in no file outside _bmad-output and _bmad`, () => {
      const hits = files.filter((f) => {
        const text = readFileSync(join(root, f));
        return text.includes(0) ? false : text.toString('utf8').includes(name);
      });
      assert.deepEqual(hits, []);
    });
  }
});
