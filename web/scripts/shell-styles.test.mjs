// Tests that the shell's sources read only custom properties that exist: a generated token (tokens.css), a font
// stack that base.css declares, or a property that one of the scanned sources declares (a component may read one
// that an enclosing component sets). A misspelt var(--name), a wrong letter case included, is not an error in CSS,
// it silently drops the declaration, so only this scan notices it.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const sources = join(here, '..', 'src');

function listFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return listFiles(path);
    return /\.(css|ts)$/.test(entry.name) ? [path] : [];
  });
}

const stripComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '');

const files = listFiles(sources).map((path) => ({
  name: relative(sources, path),
  text: stripComments(readFileSync(path, 'utf8')),
}));

const declared = new Set();
const uses = [];
for (const { name, text } of files) {
  for (const match of text.matchAll(/(?:^|[\s;{])--([A-Za-z0-9_-]+)\s*:/g)) declared.add(match[1]);
  for (const match of text.matchAll(/var\(\s*--([A-Za-z0-9_-]+)/g)) uses.push({ file: name, property: match[1] });
}

describe('the custom properties that the shell reads', () => {
  it('scans the generated tokens, base.css and the component styles', () => {
    const names = files.map((file) => file.name);
    for (const expected of ['styles/tokens.css', 'styles/base.css', 'app/header/header.ts', 'app/app.ts', 'signin/signin.css']) {
      assert.ok(names.includes(expected), `${expected} is scanned`);
    }
    assert.ok(declared.size > 500, `the tokens are declared (${declared.size})`);
    assert.ok(uses.length > 40, `the sources read tokens (${uses.length})`);
  });

  it('declares every property that is read', () => {
    const missing = uses.filter(({ property }) => !declared.has(property)).map(({ file, property }) => `${file}: var(--${property})`);
    assert.deepEqual([...new Set(missing)], []);
  });

  it('reaches the template-literal styles of the components', () => {
    const header = uses.filter(({ file }) => file === 'app/header/header.ts');
    assert.ok(header.length >= 10, `the header's styles are scanned (${header.length} reads)`);
  });
});
