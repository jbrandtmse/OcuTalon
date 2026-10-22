// Tests that nothing the page ships renders text as HTML (AD-13): no source under web/src uses innerHTML, outerHTML,
// insertAdjacentHTML, DomSanitizer or bypassSecurityTrust*. The model's reply and every arriving text are bound by interpolation
// and `[href]` only, and the shell keeps sending script-src 'self'. The whole text of a source is scanned, comments included,
// without regard to case, so no source even names them.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const sources = join(here, '..', 'src');

const FORBIDDEN = ['innerHTML', 'outerHTML', 'insertAdjacentHTML', 'DomSanitizer', 'bypassSecurityTrust'];

function listFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return listFiles(path);
    return /\.(ts|js|html|css)$/.test(entry.name) ? [path] : [];
  });
}

const files = listFiles(sources).map((path) => ({ name: relative(sources, path), text: readFileSync(path, 'utf8') }));

describe('the page\'s sources', () => {
  it('scan the app, the sign-in script, the styles and the index', () => {
    const names = files.map((file) => file.name);
    for (const expected of ['index.html', 'main.ts', 'app/app.ts', 'app/chat/ocutalon-reply.ts', 'app/chat/chat-panel.ts', 'app/msg/catalog.ts', 'signin/signin.js', 'styles/base.css']) {
      assert.ok(names.includes(expected), `${expected} is scanned`);
    }
  });

  it('never write HTML, bypass the sanitizer or name an API that does', () => {
    const found = [];
    for (const { name, text } of files) {
      for (const word of FORBIDDEN) {
        if (text.toLowerCase().includes(word.toLowerCase())) found.push(`${name}: ${word}`);
      }
    }
    assert.deepEqual(found, []);
  });

  it('bind the reply by interpolation and href only: its component has no [innerHtml] and no [outerHTML] binding either', () => {
    const reply = files.find((file) => file.name === 'app/chat/ocutalon-reply.ts');
    assert.ok(reply, 'the reply component exists');
    assert.ok(!/\[(inner|outer)html\]/i.test(reply.text));
    assert.ok(/\[href\]="run\.href"/.test(reply.text), 'a link binds [href]');
  });
});
