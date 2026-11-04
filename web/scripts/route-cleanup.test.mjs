// Pins that a test's route callback never outlives its test (Story 11.21; DW-640, DW-665): every spec under e2e/ and e2e-online/ imports
// `test` from the shared module e2e/support/fixtures.ts, which unroutes the page, the context and the context's pages when a test ends, and
// no spec keeps an afterEach copy of that unroute. A spec added later that imports `test` from Playwright itself is named here, so the
// unroute is never silently missing. The classifier is exercised on inline samples first, so that the check is not vacuous.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = join(here, '..');
const FIXTURES = join(webRoot, 'e2e', 'support', 'fixtures.ts');

/** Every `import ... from '<module>';` statement of a source: its clause and its module. */
function importsOf(source) {
  return [...source.matchAll(/^import\s+([^;]*?)\s+from\s+'([^']+)';/gms)].map((m) => ({ clause: m[1], from: m[2] }));
}

/** The value names that an import clause brings in, as written in the module (`test as t` gives `test`), or `*` for a default or namespace import. */
function valueNames(clause) {
  if (/^type\s/.test(clause)) return [];
  const names = [];
  const braces = clause.match(/\{([^}]*)\}/s);
  const outside = clause.replace(/\{[^}]*\}/s, '').replace(/,/g, '').trim();
  if (outside !== '') names.push('*');
  if (braces) {
    for (const part of braces[1].split(',')) {
      const entry = part.trim();
      if (entry === '' || /^type\s/.test(entry)) continue;
      names.push(entry.split(/\s+as\s+/)[0].trim());
    }
  }
  return names;
}

/** What is wrong with a spec's imports for the shared test: the problems, or an empty list. */
function importProblems(source) {
  const problems = [];
  let shared = false;
  for (const { clause, from } of importsOf(source)) {
    const names = valueNames(clause);
    if (from === '@playwright/test' || from === 'playwright/test') {
      if (names.includes('test') || names.includes('*')) problems.push(`imports the value \`test\` (or a default or namespace import) from '${from}'`);
    } else if (/(^|\/)support\/fixtures$/.test(from) && names.includes('test')) {
      shared = true;
    }
  }
  if (!shared) problems.push("does not import `test` from the shared module (a path ending in 'support/fixtures')");
  return problems;
}

/** The afterEach hooks of a source that call unrouteAll: the line of each. A hook ends at the first line that closes it at the indent that opened it. */
function afterEachUnroutes(source) {
  const lines = source.split('\n');
  const found = [];
  lines.forEach((line, i) => {
    if (!/\bafterEach\(/.test(line)) return;
    const indent = line.match(/^\s*/)[0];
    const single = /\);\s*$/.test(line);
    let end = i;
    if (!single) {
      end = lines.findIndex((later, j) => j > i && later === `${indent}});`);
      if (end < 0) end = lines.length - 1;
    }
    if (lines.slice(i, end + 1).some((inner) => inner.includes('unrouteAll'))) found.push(i + 1);
  });
  return found;
}

/** Every *.spec.ts file under e2e/ and e2e-online/, as a path from web/. */
function specs() {
  return ['e2e', 'e2e-online'].flatMap((dir) =>
    readdirSync(join(webRoot, dir), { recursive: true })
      .filter((name) => String(name).endsWith('.spec.ts'))
      .map((name) => relative(webRoot, join(webRoot, dir, String(name))).split('\\').join('/')),
  );
}

describe('the classifier', () => {
  it('flags a spec that imports test from Playwright', () => {
    assert.notDeepEqual(importProblems("import { expect, test, type Page } from '@playwright/test';\n"), []);
    assert.notDeepEqual(importProblems("import { expect, test as t } from '@playwright/test';\n"), []);
    assert.notDeepEqual(importProblems("import { test } from 'playwright/test';\n"), []);
    assert.notDeepEqual(importProblems("import * as pw from '@playwright/test';\nimport { test } from '../support/fixtures';\n"), []);
    assert.notDeepEqual(importProblems("import pw from '@playwright/test';\nimport { test } from '../support/fixtures';\n"), []);
  });

  it('flags a spec that imports no shared test', () => {
    assert.notDeepEqual(importProblems("import { expect } from '../support/fixtures';\n"), []);
    assert.notDeepEqual(importProblems("import { helper } from '../support/api';\n"), []);
  });

  it('passes the shared import, also with a type-only import from Playwright', () => {
    assert.deepEqual(importProblems("import { expect, test, type Page } from '../support/fixtures';\n"), []);
    assert.deepEqual(importProblems("import { expect, test } from '../../e2e/support/fixtures';\n"), []);
    assert.deepEqual(importProblems("import type { Page } from '@playwright/test';\nimport { expect, test } from '../support/fixtures';\n"), []);
    assert.deepEqual(importProblems("import { expect, type Page } from '@playwright/test';\nimport { test } from '../support/fixtures';\n"), []);
  });

  it('flags an afterEach hook that unroutes, and only that one', () => {
    const copy = "test.afterEach(async ({ page }) => {\n  await page.unrouteAll({ behavior: 'ignoreErrors' });\n});\n";
    assert.deepEqual(afterEachUnroutes(copy), [1]);
    assert.deepEqual(afterEachUnroutes(`describe('x', () => {\n  ${copy.replace(/\n/g, '\n  ')}});\n`), [2]);
    assert.deepEqual(afterEachUnroutes("test.afterEach(async ({ page }) => page.unrouteAll({ behavior: 'ignoreErrors' }));\n"), [1]);
    const other = "test.afterEach(async ({ page }) => {\n  await signOut(page);\n});\n\nasync function f(page) {\n  await page.unrouteAll();\n}\n";
    assert.deepEqual(afterEachUnroutes(other), []);
  });
});

describe('every spec of e2e and e2e-online', () => {
  const files = specs();

  it('finds the specs', () => {
    assert.ok(files.length >= 70, `${files.length} specs found`);
  });

  it('imports test from the shared module and nowhere else', () => {
    const offenders = files.flatMap((file) => importProblems(readFileSync(join(webRoot, file), 'utf8')).map((problem) => `${file}: ${problem}`));
    assert.deepEqual(offenders, [], `import test from e2e/support/fixtures (it unroutes when a test ends):\n${offenders.join('\n')}`);
  });

  it('keeps no afterEach copy of the unroute', () => {
    const offenders = files.flatMap((file) => afterEachUnroutes(readFileSync(join(webRoot, file), 'utf8')).map((line) => `${file}:${line}`));
    assert.deepEqual(offenders, [], `the shared test unroutes; delete the afterEach copy:\n${offenders.join('\n')}`);
  });
});

describe('e2e/support/fixtures.ts', () => {
  const source = readFileSync(FIXTURES, 'utf8');
  const extend = source.slice(source.indexOf('base.extend('));

  it('overrides the page and the context fixtures', () => {
    assert.match(extend, /^\s*page: async \(\{ page \}, use\) => \{/m);
    assert.match(extend, /^\s*context: async \(\{ context \}, use\) => \{/m);
  });

  it('unroutes the page, every page of the context and the context after the test', () => {
    assert.match(extend, /await use\(page\);\s*await unroute\(page\);/);
    assert.match(extend, /await use\(context\);\s*for \(const page of context\.pages\(\)\) await unroute\(page\);\s*await unroute\(context\);/);
  });

  it('lets callbacks in flight end quietly and skips only a closed target', () => {
    assert.match(source, /unrouteAll\(\{ behavior: 'ignoreErrors' \}\)/);
    assert.match(source, /message\.includes\('has been closed'\)\) throw error/);
  });

  it('exports the Playwright API beside its own test', () => {
    assert.match(source, /^export \* from '@playwright\/test';$/m);
    assert.match(source, /^export const test = base\.extend\(/m);
  });
});
