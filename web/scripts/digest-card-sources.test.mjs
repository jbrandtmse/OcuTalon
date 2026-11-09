// Tests the shape of the digest card's sources that Story 18.4 relies on and that no unit of the view model can see: the notice card draws a
// digest on the --digest-card-* tokens (the surface, the border, the 4px brand-teal accent bar and the medium radius), shows its check rows
// with app-check-rows inside a disclosure button with aria-expanded and aria-controls, and shows Got it (app-got-it) on a tell-now card until
// it is handled; the Got it control is a ServerButton that shows an error reply's message (messageOf) or the busy notice; the simulated phone
// shows the same control on a tell-now message. The browser cases (e2e/chat/notice.spec.ts N16 to N19) pin what the running page does; this
// reads the sources, so a state no case reaches cannot lose an attribute or read the wrong token without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const chat = sourceFiles(join(app, 'chat'), ['.ts']);
const phone = sourceFiles(join(app, 'phone'), ['.ts']);

const file = (list, name) => {
  const found = list.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

/** The text of a component's template literal, or of its styles literal. */
const literal = (source, property) => {
  const found = new RegExp(`${property}: \`([\\s\\S]*?)\`,\\n`).exec(source.code);
  assert.ok(found, `${source.name} has a ${property} literal`);
  return found[1];
};

/** The declarations of the CSS rule with exactly this selector, or undefined when there is none. */
const rule = (css, selector) => {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(?:^|\\n)\\s*${escaped}\\s*\\{([^}]*)\\}`).exec(css)?.[1];
};

const card = file(chat, 'notice-card.ts');
const gotIt = file(chat, 'got-it.ts');
const simulated = file(phone, 'simulated-phone.ts');
const template = literal(card, 'template');
const styles = literal(card, 'styles');

describe('the digest card', () => {
  it('takes the digest card tokens for its surface, border, accent bar and radius', () => {
    const declarations = rule(styles, '.notice.digest');
    assert.ok(declarations, 'a .notice.digest rule');
    assert.match(declarations, /background: var\(--digest-card-background\);/);
    assert.match(declarations, /\bborder: var\(--digest-card-border\);/);
    assert.match(declarations, /border-inline-start: var\(--digest-card-accent-bar\);/);
    assert.match(declarations, /border-inline-start-style: solid;/);
    assert.match(declarations, /border-radius: var\(--digest-card-radius\);/);
  });

  it('shows the check rows with app-check-rows, and no sentence key, inside a disclosure button with aria-expanded and aria-controls', () => {
    assert.match(card.code, /import \{ CheckRows \} from '\.\/check-rows';/);
    assert.match(template, /<app-check-rows \[checks\]="notice\(\)\.checks" \/>/);
    assert.doesNotMatch(template, /<app-check-rows[^>]*checkKey/);
    assert.match(template, /<button type="button" class="disclosure"[^>]*\[attr\.aria-expanded\]="open\(\)"[^>]*\[attr\.aria-controls\]="rowsId"/);
    assert.match(template, /\{\{ whatIChecked\(\) \}\}/);
  });

  it('starts the disclosure from digestOpen and shows it only for a digest with rows', () => {
    assert.match(card.code, /this\.chosen\(\) \?\? digestOpen\(this\.notice\(\)\.checks\)/);
    assert.match(template, /@if \(notice\(\)\.kind === 'digest' && notice\(\)\.checks\.length > 0\)/);
  });

  it('shows Got it on a tell-now card with a decisionRef until it is handled, then the catalog line with the time in the browser zone', () => {
    assert.match(template, /@if \(notice\(\)\.kind === 'tellnow' && notice\(\)\.decisionRef\)/);
    assert.match(template, /<app-got-it \[ref\]="notice\(\)\.decisionRef" channel="web" \/>/);
    assert.match(card.code, /renderPageText\('handled\.marked', \{ time: pageTimeBeside\(at, this\.instanceZone\(\)\) \}\)/);
  });
});

describe('the Got it control', () => {
  it('is a ServerButton labelled from the catalog text of button.gotIt, and calls the got-it route with its ref and channel', () => {
    assert.match(gotIt.code, /import \{ BUSY_NOTICE, ServerButton \} from '\.\.\/shared\/server-button';/);
    assert.match(gotIt.code, /PAGE_TEXTS\['button\.gotIt'\]/);
    assert.match(literal(gotIt, 'template'), /<app-server-button[^>]*\[action\]="press"/);
    assert.match(gotIt.code, /this\.api\.gotIt\(this\.ref\(\), this\.channel\(\)\)/);
  });

  it('shows an error reply\'s message (messageOf), else the busy notice, and announces it', () => {
    assert.match(gotIt.code, /function messageOf\(error: unknown\): string/);
    assert.match(gotIt.code, /const text = messageOf\(error\) \|\| BUSY_NOTICE;/);
    assert.match(gotIt.code, /this\.announcer\.announce\(text\);/);
  });
});

describe('the simulated phone', () => {
  it('shows app-got-it on the phone channel while gotItShown, else the message\'s answer line', () => {
    const phoneTemplate = literal(simulated, 'template');
    assert.match(phoneTemplate, /@if \(gotItShown\(one\)\)/);
    assert.match(phoneTemplate, /<app-got-it \[ref\]="one\.decisionRef \?\? ''" channel="phone" \/>/);
    assert.match(phoneTemplate, /@else if \(one\.decisionRef && one\.answer\)/);
  });
});
