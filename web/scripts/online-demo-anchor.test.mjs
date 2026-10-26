// Tests the start value of the online-demo unit's reset anchor (docker/tests/test-online-demo.sh, Story 16.8, matrix row 16): it is
// computed when the unit starts, as the current time plus two hours, to the minute, in the form the Public install step accepts
// (YYYY-MM-DDThh:mm:ssZ), so that no real reset or reset-soon period falls inside a run; and the stack's override quotes it, because
// compose would otherwise read a timestamp. The test runs the unit's own expression, so a changed lead or a fixed date fails here and
// not as a flaky browser step.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const unit = readFileSync(join(here, '..', '..', 'docker', 'tests', 'test-online-demo.sh'), 'utf8');

describe('the online-demo unit\'s reset anchor (row 16)', () => {
  const definition = /^anchor=\$\(node -e '([^']+)'\)\s*$/m.exec(unit);

  it('is computed by an expression in the unit, not a fixed date', () => {
    assert.ok(definition, 'anchor=$(node -e \'...\') is in the unit');
    assert.doesNotMatch(unit, /^anchor=\d{4}-/m, 'no fixed anchor');
  });

  it('is two hours after the unit\'s start, to the minute, in the Public step\'s time form', () => {
    const before = Date.now();
    const anchor = execFileSync(process.execPath, ['-e', definition[1]], { encoding: 'utf8' }).trim();
    const after = Date.now();
    assert.match(anchor, /^\d{4}-\d\d-\d\dT\d\d:\d\d:00Z$/, 'to the minute');
    const lead = Date.parse(anchor);
    assert.ok(lead >= before + 2 * 3_600_000 - 60_000, `${anchor} is at least two hours (less one minute) ahead`);
    assert.ok(lead <= after + 2 * 3_600_000, `${anchor} is at most two hours ahead`);
  });

  it('is quoted where the stack\'s override sets it', () => {
    assert.match(unit, /OCUTALON_RESET_ANCHOR: \\"\$anchor\\"/);
  });
});
