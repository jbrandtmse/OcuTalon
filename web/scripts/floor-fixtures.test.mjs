// Tests that the floor specs of Story 2.14 leave no turn behind (DW-179): seedTurns records the turns and the Decision rows it writes
// for Test.Data.Fixture.Clean, and every case that seeds a turn lists them (turnRows) in the refs that cleanFixtureRows removes. The
// browser case H1 (web/e2e/floor/fixtures.spec.ts) pins that the clean-up removes them on a running stack; this reads the sources, so
// a seed that forgets its refs cannot come back without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { code } from './source-files.mjs';

const e2e = join(dirname(fileURLToPath(import.meta.url)), '..', 'e2e');
const read = (name) => code(readFileSync(join(e2e, name), 'utf8'));

/** The calls of a function in a source, not counting its import. */
const calls = (text, name) => (text.match(new RegExp(`\\b${name}\\(`, 'g')) ?? []).length;

describe('seedTurns records what it writes', () => {
  const iris = read('support/iris.ts');

  it('adopts each turn and each Decision row it saves, for Fixture.Clean', () => {
    assert.match(iris, /'If \$System\.Status\.IsOK\(sc\) Do ##class\(OcuTalon\.Test\.Data\.Fixture\)\.Adopt\(t\)'/);
    assert.match(iris, /`If \$System\.Status\.IsOK\(sc\) Do ##class\(OcuTalon\.Test\.Data\.Fixture\)\.Adopt\(\$\{variable\}\)`/);
  });

  it('lists the refs of the turns and of both Decision rows in turnRows', () => {
    assert.match(iris, /export const turnRows = \(seeded: Seeded\): string\[\] => \[\.\.\.seeded\.refs, \.\.\.seeded\.decisions\.flatMap\(\(one\) => \[one\.triage, one\.turn\]\)\]/);
  });
});

describe('the floor cases of Story 2.14 list the turns they seed', () => {
  for (const name of ['floor/keyboard.spec.ts', 'floor/words.spec.ts', 'support/floor.ts']) {
    it(`${name}: every seedTurns call has its turnRows`, () => {
      const text = read(name);
      const seeds = calls(text, 'seedTurns');
      assert.ok(seeds > 0, `${name} seeds turns`);
      assert.equal(calls(text, 'turnRows'), seeds, `${name} records the rows of each of its ${seeds} seeds`);
    });
  }
});
