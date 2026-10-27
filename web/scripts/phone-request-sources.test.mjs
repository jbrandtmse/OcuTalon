// Tests the shape of the simulated phone's request message sources that Story 6.3 relies on and that no unit of the view model can
// see: the message is drawn by app-phone-request only when it names a request; the two buttons sit in an answer part keyed by the
// message and are replaced by an answer line of the same part and key (focusable, naming its request); the buttons share the card's
// press (AnswerPress) with the channel phone, go busy together and are never `disabled`; the inset sits on the surface colour with the
// example's values in mono-sm, in the danger and the success ink; the two buttons are side by side in equal halves with the phone
// button height as their minimum; every text is bound by interpolation; the phone moves focus only through the shared rule and
// announces nothing itself. The browser cases (answers/answers.spec.ts, X1 to X10) pin what the running page does; this reads the
// sources, so a state no case reaches cannot lose an attribute or read the wrong token without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const phone = sourceFiles(join(app, 'phone'), ['.ts']);
const devices = sourceFiles(join(app, 'devices'), ['.ts']);

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

const request = file(phone, 'phone-request.ts');
const screen = file(phone, 'simulated-phone.ts');
const view = file(phone, 'phone-view.ts');
const template = literal(request, 'template');
const styles = literal(request, 'styles');
const screenTemplate = literal(screen, 'template');

describe('the scan', () => {
  it('reads the phone\'s sources', () => {
    assert.deepEqual(phone.map((one) => one.name).sort(), ['phone-request.ts', 'phone-view.ts', 'simulated-phone.ts']);
  });
});

describe('the phone', () => {
  it('draws a message with an approvalRef by app-phone-request, inside the same notification, and every other message as before', () => {
    assert.match(screenTemplate, /<div class="notification" tabindex="-1" \[attr\.data-key\]="one\.ref">\s*@if \(one\.approvalRef\) \{\s*<app-phone-request\s/);
    assert.match(screenTemplate, /\[message\]="one"\s+\[approval\]="approvalOf\(one\)"\s+\[caption\]="timeOf\(one\)"\s+\[instanceZone\]="instanceZone\(\)"\s+\[onlineDemo\]="onlineDemo\(\)"\s+\[user\]="user\(\)"/);
    assert.match(screenTemplate, /\} @else \{\s*<p class="text">\{\{ one\.text \}\}<\/p>\s*<span class="time">\{\{ timeOf\(one\) \}\}<\/span>\s*\}/);
  });

  it('reads the request from the store by the message\'s approvalRef, and looks for the New messages target among the notifications only', () => {
    assert.match(screen.code, /this\.live\.store\(\)\?\.approvals\?\.\[message\.approvalRef \?\? ''\]/);
    assert.match(screen.code, /querySelectorAll<HTMLElement>\('\.notification\[data-key\]'\)/);
  });

  it('is no live region and speaks nothing itself: the notices of the phone\'s own press go through the Announcer inside AnswerPress', () => {
    for (const one of phone) {
      assert.doesNotMatch(one.code, /aria-live|role="(status|alert|log)"|\.announce\(/, one.name);
    }
    assert.doesNotMatch(request.code, /LiveAnnouncer/);
  });

  it('keeps the view model free of values: it imports types only', () => {
    const imports = [...view.code.matchAll(/^import\s.*$/gm)].map((match) => match[0]);
    assert.ok(imports.length >= 3);
    for (const line of imports) assert.match(line, /^import type /, line);
  });
});

describe('the answer part', () => {
  it('has the two buttons in a span of the answer part keyed by the message, or the answer line of the same part and key, focusable and naming the request', () => {
    assert.match(template, /@if \(view\(\)\.buttons\) \{\s*<span class="buttons" data-part="answer" \[attr\.data-key\]="message\(\)\.ref" \[attr\.data-approval\]="busy\(\) \? message\(\)\.approvalRef : null">/);
    assert.match(template, /\} @else if \(view\(\)\.answer; as line\) \{\s*<p \[class\]="'answered tone-' \+ line\.tone" data-part="answer" \[attr\.data-key\]="message\(\)\.ref" \[attr\.data-approval\]="message\(\)\.approvalRef" tabindex="-1">/);
    assert.match(template, /@if \(line\.icon; as icon\) \{\s*<app-icon \[name\]="icon" \[size\]="16" \/>\s*\}\s*<span>\{\{ line\.text \}\}<\/span>/);
  });

  it('moves the focus of a replaced button through the shared rule on the answer part only', () => {
    assert.match(request.code, /export const PHONE_ANSWER_RULE: FocusRule = \{\s*item: `\[\$\{PART\}="answer"\]\[\$\{KEY\}\]`,\s*keyOf: \(item\) => item\.getAttribute\(KEY\) \?\? '',\s*\};/);
    assert.match(request.code, /keepFocus\(this\.host\.nativeElement, this\.injector, this\.popovers, PHONE_ANSWER_RULE\)/);
    assert.doesNotMatch(request.code, /\.focus\(|afterNextRender|autofocus/);
  });

  it('gives the device panel an item rule that keeps the answer line a replaced button\'s focus', () => {
    const panel = file(devices, 'device-panel.ts');
    assert.match(panel.code, /const FOCUS_RULE: FocusRule = \{\s*item: '\[data-part\]\[data-key\]',/);
    assert.match(panel.code, /keyOf: \(item\) => `\$\{item\.getAttribute\('data-part'\) \?\? ''\}:\$\{item\.getAttribute\('data-key'\) \?\? ''\}`/);
    assert.doesNotMatch(panel.code, /whenGone/);
  });
});

describe('the buttons', () => {
  const buttons = [...template.matchAll(/<button\s([\s\S]*?)>/g)].map((match) => match[1]);

  it('are Approve (primary, first) and Reject (secondary), each a type="button" named with the object', () => {
    assert.equal(buttons.length, 2);
    const [approve, reject] = buttons;
    for (const one of buttons) assert.match(one, /type="button"/);
    assert.match(approve, /class="button button-primary"/);
    assert.match(approve, /\[attr\.aria-label\]="view\(\)\.approveName"/);
    assert.match(approve, /\(click\)="press\('approve'\)"/);
    assert.match(reject, /class="button button-secondary"/);
    assert.match(reject, /\[attr\.aria-label\]="view\(\)\.rejectName"/);
    assert.match(reject, /\(click\)="press\('reject'\)"/);
  });

  it('go busy together: aria-busy and aria-disabled from the one busy signal, a spinner in each, and never the disabled attribute', () => {
    for (const one of buttons) {
      assert.match(one, /\[attr\.aria-busy\]="busy\(\) \? 'true' : null"/);
      assert.match(one, /\[attr\.aria-disabled\]="busy\(\) \? 'true' : null"/);
      assert.match(one, /\[attr\.aria-describedby\]="notice\(\) \? noticeId : null"/);
    }
    assert.equal((template.match(/<app-icon class="spinner" name="loader-circle"/g) ?? []).length, 2);
    assert.doesNotMatch(template, /\[disabled\]|\[attr\.disabled\]|\sdisabled[\s=>]/);
    assert.match(template, /<app-inline-notice variant="warning" \[id\]="noticeId">\{\{ notice\(\) \}\}<\/app-inline-notice>/);
  });

  it('press through AnswerPress with the channel phone, the request of the message, and no session or user', () => {
    assert.match(request.code, /new AnswerPress\(\{\s*answer: \(ref, action, channel\) => this\.api\.answerApproval\(ref, action, channel\),\s*channel: 'phone',/);
    assert.match(request.code, /this\.answer\.press\(this\.approvalRef\(\), action\)/);
    assert.match(request.code, /return this\.message\(\)\.approvalRef \?\? '';/);
    assert.doesNotMatch(request.code, /channel: 'web'/);
    assert.doesNotMatch(request.code, /BusyState|HttpClient|\.post\(/, 'the phone has no busy state or call of its own');
  });

  it('read the texts in message form with message times: renderMessageText and messageTime, never the page\'s', () => {
    assert.match(request.code, /timeBeside: \(iso\) => messageTime\(iso, nowMs, instanceZone, onlineDemo\)/);
    assert.match(request.code, /render: \(key, slots\) => renderMessageText\(key, slots\)/);
    assert.match(request.code, /title: approvalTitle,/);
    assert.doesNotMatch(request.code, /renderPageText|pageTimeBeside|pageWhenBeside/);
  });

  it('sit side by side in two equal columns with the gap of space-2, the phone button height as their minimum', () => {
    const buttonsRule = rule(styles, '.buttons');
    assert.ok(buttonsRule?.includes('display: grid;'));
    assert.ok(buttonsRule?.includes('grid-template-columns: 1fr 1fr;'));
    assert.ok(buttonsRule?.includes('gap: var(--space-2);'));
    const button = rule(styles, '.buttons .button');
    assert.ok(button?.includes('min-height: var(--phone-notification-button-height);'));
    assert.doesNotMatch(styles, /(?<![-a-z])height:\s/, 'no fixed height');
  });
});

describe('the text and the inset', () => {
  it('prints every text by interpolation, in order: the blocks and their parts, the buttons\' labels, the answer line, the notice and the caption', () => {
    const order = ['part.text', 'block.text', 'texts.approve', 'texts.reject', 'line.text', 'notice()', 'caption()'];
    const positions = order.map((name) => template.indexOf(`{{ ${name} }}`));
    assert.ok(positions.every((at) => at >= 0), `every text is printed: ${positions}`);
    for (let i = 2; i < positions.length - 1; i += 1) assert.ok(positions[i] < positions[i + 1], `${order[i]} comes before ${order[i + 1]}`);
    assert.doesNotMatch(request.code, /innerhtml|outerhtml|bypassSecurity|DomSanitizer/i);
  });

  it('draws the inset on the surface colour, and the example\'s before value in the danger ink and its after value in the success ink, both in mono-sm', () => {
    assert.match(template, /<p class="text inset">/);
    assert.match(template, /<span \[class\]="'mono ' \+ part\.kind">\{\{ part\.text \}\}<\/span>/);
    assert.ok(rule(styles, '.inset')?.includes('background: var(--surface);'));
    assert.ok(rule(styles, '.before')?.includes('color: var(--danger-ink);'), 'before');
    assert.ok(rule(styles, '.after')?.includes('color: var(--success-ink);'), 'after');
    const mono = rule(styles, '.mono');
    assert.ok(mono?.includes('font-family: var(--type-mono-sm-font-family), var(--font-mono);'));
    assert.ok(mono?.includes('font-size: var(--type-mono-sm-font-size);'));
    assert.ok(mono?.includes('line-height: var(--type-mono-sm-line-height);'));
  });

  it('gives each answer tone its own token', () => {
    for (const tone of ['approved', 'rejected', 'expired']) {
      assert.ok(rule(styles, `.tone-${tone}`)?.includes(`color: var(--answered-status-${tone});`), `.tone-${tone}`);
    }
  });

  it('holds no colour literal and reads every colour, font and size through a token', () => {
    assert.doesNotMatch(styles, /#[0-9a-fA-F]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|hwb|lab|lch|oklab|oklch|color-mix|color)\(/);
    const bad = [...styles.matchAll(/^\s*(color|background|font-family|font-size|font-weight)\s*:\s*([^;]+);/gm)].filter(([, , value]) => !/var\(--/.test(value)).map(([line]) => line.trim());
    assert.deepEqual(bad, []);
  });
});
