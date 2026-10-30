// Tests the start value of the online-demo units' reset anchor (docker/tests/lib-online.sh, which test-online-demo.sh and test-online-session.sh
// source; Story 16.8, matrix row 16, and Story 16.4): it is computed when the unit starts, as the current time plus two hours, to the minute,
// in the form the Public install step accepts (YYYY-MM-DDThh:mm:ssZ), so that no real reset or reset-soon period falls inside a run; and the
// stack's override quotes it, because compose would otherwise read a timestamp. The test runs the library's own expression, so a changed lead
// or a fixed date fails here and not as a flaky browser step; and it checks that both units source the library.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const tests = join(here, '..', '..', 'docker', 'tests');
const unit = readFileSync(join(tests, 'lib-online.sh'), 'utf8');

describe('the online-demo unit\'s reset anchor (row 16)', () => {
  const definition = /^\s*anchor=\$\(node -e '([^']+)'\)\s*$/m.exec(unit);

  it('is computed by an expression in the unit, not a fixed date', () => {
    assert.ok(definition, 'anchor=$(node -e \'...\') is in the library');
    assert.doesNotMatch(unit, /^\s*anchor=\d{4}-/m, 'no fixed anchor');
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

  it('is the one both online units start from: each sources the library and calls online_values and online_override', () => {
    for (const name of ['test-online-demo.sh', 'test-online-session.sh']) {
      const text = readFileSync(join(tests, name), 'utf8');
      assert.match(text, /^\. "\$\(dirname "\$0"\)\/lib-online\.sh"$/m, `${name} sources lib-online.sh`);
      assert.match(text, /^online_values$/m, `${name} calls online_values`);
      assert.match(text, /^online_override$/m, `${name} calls online_override`);
      assert.doesNotMatch(text, /^\s*anchor=/m, `${name} defines no anchor of its own`);
    }
  });
});
