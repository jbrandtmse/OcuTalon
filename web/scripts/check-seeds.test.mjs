// Pins that a check row seeded for a browser spec is not run by the real heartbeat (DW-349, AD-18). Checks runs every check row
// whose next due time is empty or has passed and overwrites its last run, result and finding, so a spec that asserts the seeded
// values needs a row that no tick runs. Test.Data.Fixture.Check stores NextDueAt an hour ahead unless the fields carry one
// (pinned on IRIS by Test.Data.FixtureDefaults.TestCheckIsNotDue); this reads the web sources and pins the other half:
//   (a) seedCheck adds no due time of its own, and an empty nextDueAt still reaches Fixture.Check, as the opt-in;
//   (b) each opt-in (an empty nextDueAt, or a direct Fixture.Check call that passes NextDueAt) says `real watch` in a comment on
//       its line or directly above it;
//   (c) no e2e source stores a check row except through Fixture.Check.
// It reads web sources only: no stack, no rows. Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const files = ['e2e', 'e2e-online'].flatMap((folder) => sourceFiles(join(web, folder), ['.ts']).map((file) => ({ ...file, name: `${folder}/${file.name}` })));
const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is a web source`);
  return found;
};

/** The lines of a source with its comments removed, one entry per original line (block comments keep their line breaks). */
const codeLines = (text) =>
  text
    .replace(/\/\*[\s\S]*?\*\//g, (block) => block.replace(/[^\n]/g, ''))
    .split('\n')
    .map((line) => line.replace(/(^|\s)\/\/.*$/, '$1'));

/** Whether a comment says `real watch`: on the line itself, or in the unbroken run of comment lines directly above it. */
function saysRealWatch(lines, index, lineCode) {
  const mark = /real watch/i;
  if (mark.test(lines[index]) && !mark.test(lineCode[index])) return true;
  for (let above = index - 1; above >= 0 && /^\s*(\/\/|\/?\*)/.test(lines[above]); above -= 1) {
    if (mark.test(lines[above])) return true;
  }
  return false;
}

/** The "file:line" of each line of a file whose code matches, and that carries no `real watch` comment. */
function unmarked(one, matches) {
  const lines = one.text.split('\n');
  const lineCode = codeLines(one.text);
  return lineCode.flatMap((line, index) => (matches(line) && !saysRealWatch(lines, index, lineCode) ? [`${one.name}:${index + 1}`] : []));
}

const emptyDueTime = (line) => /\bnextDueAt['"]?\s*:\s*(''|""|``)/.test(line);
const directCheckWithDueTime = (line) => /Fixture\)\.Check\(/.test(line) && /NextDueAt/i.test(line);

describe('seedCheck adds no due time of its own', () => {
  const iris = file('e2e/support/iris.ts');
  const start = iris.code.indexOf('export async function seedCheck');
  const body = iris.code.slice(start, iris.code.indexOf('\nexport ', start + 1));

  it('is found in e2e/support/iris.ts', () => {
    assert.ok(start >= 0 && body.length > 0, 'e2e/support/iris.ts holds seedCheck');
  });

  it('passes NextDueAt as fields.nextDueAt alone: no default with ?? or ||', () => {
    assert.equal(body.match(/NextDueAt/g)?.length, 1, 'e2e/support/iris.ts: seedCheck names NextDueAt once');
    assert.equal(body.match(/\bnextDueAt\b/g)?.length, 1, 'e2e/support/iris.ts: seedCheck reads nextDueAt once');
    assert.match(body, /^\s*NextDueAt: fields\.nextDueAt,\s*$/m, 'e2e/support/iris.ts: seedCheck passes `NextDueAt: fields.nextDueAt,` and nothing more');
  });

  it('calls Fixture.Check with the fields object made from the row', () => {
    assert.match(body, /const row = properties\(\{/, 'e2e/support/iris.ts: seedCheck makes its row with properties()');
    assert.match(body, /Fixture\)\.Check\([^\n]*\$\{fieldsObject\(row\)\}\)/, 'e2e/support/iris.ts: seedCheck passes fieldsObject(row) to Fixture.Check');
  });

  it('keeps an empty nextDueAt, because properties() drops undefined only', () => {
    const start = iris.code.indexOf('function properties(');
    assert.ok(start >= 0, 'e2e/support/iris.ts holds properties()');
    const properties = iris.code.slice(start, iris.code.indexOf('\n}', start));
    assert.match(
      properties,
      /return Object\.fromEntries\(Object\.entries\(values\)\.filter\(\(entry\): entry is \[string, string\] => entry\[1\] !== undefined\)\);/,
      'e2e/support/iris.ts: properties() filters on `entry[1] !== undefined` and nothing more',
    );
  });

  it('adds no key in fieldsObject: the row is the JSON of the properties given', () => {
    assert.match(
      iris.code,
      /const fieldsObject = \(properties: Record<string, string>\): string => `##class\(%DynamicObject\)\.%FromJSON\(\$\{quoted\(JSON\.stringify\(properties\)\)\}\)`;/,
      'e2e/support/iris.ts: fieldsObject() passes JSON.stringify(properties) alone',
    );
  });
});

describe('an opt-in to the real watch says so', () => {
  it('finds the seeding calls that this pin covers', () => {
    const seeds = (name) => file(name).code.match(/\bseedCheck\(/g)?.length ?? 0;
    for (const name of [
      'e2e/answers/close-loop.spec.ts',
      'e2e/banners/banners.spec.ts',
      'e2e/floor/focus.spec.ts',
      'e2e/floor/guide.spec.ts',
      'e2e/rail/rail.spec.ts',
      'e2e/trace/links.spec.ts',
      'e2e/heartbeat/heartbeat.spec.ts',
      'e2e/support/floor.ts',
    ]) {
      assert.ok(seeds(name) > 0, `${name} calls seedCheck`);
    }
    assert.ok(/Fixture\)\.Check\(/.test(file('e2e/session/session.spec.ts').code), 'e2e/session/session.spec.ts calls Fixture.Check directly');
  });

  it('finds the opt-in test on a marked and an unmarked sample', () => {
    const sample = (text) => unmarked({ name: 'sample.ts', text }, (line) => emptyDueTime(line) || directCheckWithDueTime(line));
    assert.deepEqual(sample("await seedCheck(u, { nextDueAt: '' });"), ['sample.ts:1']);
    assert.deepEqual(sample('await seedCheck(u, { nextDueAt: "" });'), ['sample.ts:1']);
    assert.deepEqual(sample("await seedCheck(u, { nextDueAt: '' }); // The real watch runs it"), []);
    assert.deepEqual(sample("// A case for the real watch.\n// It runs the row.\nawait seedCheck(u, { nextDueAt: '' });"), []);
    assert.deepEqual(sample("// A case for the real watch.\n\nawait seedCheck(u, { nextDueAt: '' });"), ['sample.ts:3']);
    assert.deepEqual(sample("/* real watch */ const a = seedCheck(u, { nextDueAt: `` });"), []);
    assert.deepEqual(sample('Write Fixture).Check(s.Ref,"ZZNS","P",{"NextDueAt":""})'), ['sample.ts:1']);
    assert.deepEqual(sample("await seedCheck(u, { nextDueAt: inMs(1) });"), []);
    assert.deepEqual(sample("await seedCheck(u, { 'nextDueAt': '' });"), ['sample.ts:1']);
  });

  it('has a real watch comment on every empty nextDueAt', () => {
    const offences = files.flatMap((one) => unmarked(one, emptyDueTime));
    assert.deepEqual(offences, [], `an empty nextDueAt makes the row due at the next tick; say "real watch" in a comment on the line or directly above it: ${offences.join(', ')}`);
  });

  it('has a real watch comment on every direct Fixture.Check call that passes NextDueAt', () => {
    const offences = files.flatMap((one) => unmarked(one, directCheckWithDueTime));
    assert.deepEqual(offences, [], `a direct Fixture.Check call with NextDueAt needs a "real watch" comment on the line or directly above it: ${offences.join(', ')}`);
  });
});

describe('no e2e source stores a check row except through Fixture.Check', () => {
  const bypasses = [/BackgroundCheck\)\.%New/, /INSERT\s+INTO\s+OcuTalon_Data\.BackgroundCheck/i, /UPDATE\s+OcuTalon_Data\.BackgroundCheck/i];

  it('catches each way around Fixture.Check, and allows a DELETE', () => {
    const hit = (text) => bypasses.some((pattern) => pattern.test(text));
    assert.ok(hit('##class(OcuTalon.Data.BackgroundCheck).%New()'));
    assert.ok(hit('INSERT INTO OcuTalon_Data.BackgroundCheck (Ref) VALUES (1)'));
    assert.ok(hit('update OcuTalon_Data.BackgroundCheck set NextDueAt = 0'));
    assert.ok(!hit('DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?'));
  });

  it('holds in every e2e and e2e-online source', () => {
    assert.ok(files.length > 0, 'e2e sources are listed');
    for (const one of files) {
      for (const pattern of bypasses) {
        assert.doesNotMatch(one.code, pattern, `${one.name} stores a check row without Fixture.Check (${pattern}); a seeded row must come from Fixture.Check so that it is not due`);
      }
    }
  });
});
