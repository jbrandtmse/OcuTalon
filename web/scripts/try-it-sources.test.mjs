// Tests the shape of the sources of the "Try it yourself" row (Story 4.10): the row reads the demo view and never the server's flag, sends
// through the outbox with the text alone, calls no announcer, focus or server client, and has native buttons only; the empty chat and the
// demo guide's finish place it where the story says. The browser cases (e2e/chat/try-it.spec.ts) pin what the running page does; this
// reads the sources, so a later change cannot break a rule without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const files = sourceFiles(join(here, '..', 'src', 'app'), ['.ts']);
const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};
const count = (text, pattern) => (text.match(pattern) ?? []).length;

describe('the row (try-it-row.ts)', () => {
  const { code } = file('chat/try-it-row.ts');

  it('reads demoView.on(), never the server\'s demoMode', () => {
    assert.match(code, /\bdemoView\.on\(\)/);
    assert.doesNotMatch(code, /\bdemoMode\b/);
  });

  it('sends once through the outbox with the text alone: no fromGuide, no true', () => {
    const calls = [...code.matchAll(/\boutbox\.send\(([^)]*)\)/g)];
    assert.equal(calls.length, 1);
    assert.equal(calls[0][1].trim(), 'text');
    assert.doesNotMatch(code, /fromGuide/);
  });

  it('has no announcer, focus call, server client or key binding, and only buttons of type="button"', () => {
    assert.doesNotMatch(code, /\bAnnouncer\b|\.announce\(|\.focus\(|\bApiClient\b|\bHttpClient\b|\(keydown|\(keyup|\(keypress/);
    const buttons = count(code, /<button\b/g);
    assert.equal(buttons, 1, 'one button in the template');
    assert.equal(count(code, /<button\s[^>]*type="button"/g), buttons);
  });

  it('describes the chips by the composer\'s exported reason id, not a literal', () => {
    assert.match(code, /COMPOSER_REASON_ID/);
    assert.doesNotMatch(code, /composer-allowance-reason/);
  });
});

describe('the placements', () => {
  it('has the empty chat\'s template hold the row after its last line', () => {
    const { code } = file('chat/empty-chat.ts');
    const lastLine = code.lastIndexOf('class="line"');
    assert.ok(lastLine > 0, 'the lines are found');
    assert.ok(code.indexOf('<app-try-it-row') > lastLine, 'the row follows the last line');
    assert.equal(count(code, /<app-try-it-row/g), 1);
  });

  it('has the guide\'s finish hold the row after More to try and before Run again, as the finish part tryIt', () => {
    const { code } = file('guide/demo-guide.ts');
    const more = code.indexOf('class="more"');
    const row = code.indexOf('<app-try-it-row');
    const again = code.indexOf('class="run-again"');
    assert.ok(more > 0 && row > more && again > row, 'more < row < run again');
    assert.match(code, /<app-try-it-row data-guide-focus="tryIt"/);
    assert.match(code, /const FINISH_PARTS = \[[^\]]*'tryIt'[^\]]*\]/);
  });

  it('centres the chips in the empty chat only, and lets them wrap', () => {
    assert.match(file('chat/empty-chat.ts').code, /<app-try-it-row \[centered\]="true" \/>/);
    assert.doesNotMatch(file('guide/demo-guide.ts').code, /<app-try-it-row[^>]*centered/);
    const { code } = file('chat/try-it-row.ts');
    assert.match(code, /\.try-chips \{[^}]*flex-wrap: wrap;/);
    assert.match(code, /\.row\.centered \{[^}]*align-items: center;/);
    assert.match(code, /\.centered \.try-chips \{[^}]*justify-content: center;/);
  });
});
