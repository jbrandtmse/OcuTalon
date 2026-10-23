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
    for (const expected of ['index.html', 'main.ts', 'app/app.ts', 'app/chat/ocutalon-reply.ts', 'app/chat/notice-card.ts', 'app/chat/chat-panel.ts', 'app/rail/status-rail.ts', 'app/rail/decision-row.ts', 'app/rail/rail-view.ts', 'app/rail/telegram-card/telegram-card.ts', 'app/msg/catalog.ts', 'signin/signin.js', 'styles/base.css']) {
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

  it('bind the status rail\'s texts (a decision\'s summary and reasons, a reminder\'s text, a check\'s name and finding) by interpolation only', () => {
    const rail = files.find((file) => file.name === 'app/rail/status-rail.ts');
    const decision = files.find((file) => file.name === 'app/rail/decision-row.ts');
    assert.ok(rail && decision, 'the rail components exist');
    for (const bound of ['{{ row.lead }}', '{{ row.detail }}', '{{ part }}', '{{ section.empty }}', '{{ section.hint }}']) {
      assert.ok(rail.text.includes(bound), `${bound} is interpolated in the rail`);
    }
    for (const bound of ['{{ row().title }}', '{{ line }}', '{{ decision().firstReason }}', '{{ part }}']) {
      assert.ok(decision.text.includes(bound), `${bound} is interpolated in the decision row`);
    }
    for (const file of [rail, decision]) {
      assert.ok(!/\[(inner|outer)html\]/i.test(file.text), `${file.name} binds no HTML`);
    }
  });

  it('bind a notice card\'s text, Why now line and caption by interpolation only', () => {
    const card = files.find((file) => file.name === 'app/chat/notice-card.ts');
    assert.ok(card, 'the notice card component exists');
    assert.ok(!/\[(inner|outer)html\]/i.test(card.text));
    for (const bound of ['{{ notice().text }}', '{{ notice().whyNow }}', '{{ line }}']) {
      assert.ok(card.text.includes(bound), `${bound} is interpolated`);
    }
  });
});
