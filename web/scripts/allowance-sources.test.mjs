// Tests the glue of the page's allowance (QA, Story 16.9; AD-12, AD-20, UX-DR68, DW-361) that Node cannot run because the files are Angular
// components and services: the pure views (allowance-view.ts, banner-view.ts, mailbox-view.ts) have their own tests, and the browser cases
// (e2e-online/allowance/) run the real components against the real stack in minutes. This file reads the sources, as the other *-sources
// ratchets do, so that the guards the browser cases are the only other proof of fail in seconds:
// - the banners' two README targets are built in banner-stack.ts from the anchors install-it-yourself and set-a-model-key, which are
//   headings of the README, and the guide and the about dialog keep their link to the README's top (the splash is served by the server);
// - the explained-disabled controls (the composer's field and Send, the guide's send prompts, the mailbox's chips and Send) are marked
//   aria-disabled and described by their reason, never disabled, and a press while the limit holds does nothing;
// - AllowanceState is read by the banner stack, the composer, the guide and the outbox and by nothing else, so Break the feed's box and
//   the approval and incident cards cannot be disabled by an allowance (the Always list: Break the feed, Approve and Reject);
// - the outbox learns the window from a 429 allowance before it takes the text back, and the mailbox learns its limit from a 429
//   email_limit in both error handlers;
// - the browser case's notice card text takes the time as the clock alone and with its day, so that it holds at any time of day.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const files = sourceFiles(app, ['.ts']);
const { README_URL } = await import(pathToFileURL(join(app, 'links.ts')).href);
const { readmeSection } = await import(pathToFileURL(join(app, 'rail', 'rail-view.ts')).href);

const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

/** The body of a method of a class: from its name to the closing brace at the method's own indent, with the whitespace squeezed. */
const method = (source, name) => {
  const found = new RegExp(`\\n  (?:protected |private )?${name}\\([^)]*\\)[^{]*\\{\\n([\\s\\S]*?)\\n  \\}\\n`).exec(source.code);
  assert.ok(found, `${name} is a method`);
  return found[1].replace(/\s+/g, ' ').trim();
};

/** GitHub's anchor of a heading: lower case, the punctuation dropped, the spaces turned to hyphens. */
const slug = (heading) => heading.toLowerCase().replace(/[^a-z0-9 -]/g, '').replace(/ /g, '-');

const stack = file('banners/banner-stack.ts');
const composer = file('chat/composer.ts');
const guide = file('guide/demo-guide.ts');
const outbox = file('chat/chat-outbox.ts');
const mailbox = file('mailbox/simulated-mailbox.ts');

describe('the README sections that the banner actions open (AC 10, DW-361)', () => {
  const readme = readFileSync(join(here, '..', '..', 'README.md'), 'utf8');
  const slugs = readme.split('\n').filter((line) => /^## /.test(line)).map((line) => slug(line.slice(3).trim()));

  it('the stack builds the install and set-a-key addresses from the anchors of the two README sections, and the Telegram one as before', () => {
    assert.match(stack.code, /const INSTALL_ANCHOR = 'install-it-yourself';/);
    assert.match(stack.code, /const SET_KEY_ANCHOR = 'set-a-model-key';/);
    assert.match(stack.code, /installUrl: readmeSection\(README_URL, INSTALL_ANCHOR\),/);
    assert.match(stack.code, /setKeyUrl: readmeSection\(README_URL, SET_KEY_ANCHOR\),/);
    assert.match(stack.code, /telegramUrl: readmeSection\(README_URL, TELEGRAM_ANCHOR\),/);
  });

  it('those addresses are the repository README with the section\'s anchor, not its top', () => {
    assert.equal(readmeSection(README_URL, 'install-it-yourself'), 'https://github.com/jbrandtmse/OcuTalon#install-it-yourself');
    assert.equal(readmeSection(README_URL, 'set-a-model-key'), 'https://github.com/jbrandtmse/OcuTalon#set-a-model-key');
    assert.notEqual(README_URL, readmeSection(README_URL, 'install-it-yourself'));
  });

  it('the README has a heading for each of the two anchors', () => {
    assert.ok(slugs.includes('install-it-yourself'), `the headings: ${slugs.join(', ')}`);
    assert.ok(slugs.includes('set-a-model-key'));
  });

  it('only the banner stack uses the two anchors, and the guide and the about dialog keep the README\'s top (the Never list)', () => {
    assert.deepEqual(files.filter((one) => /\b(?:INSTALL_ANCHOR|SET_KEY_ANCHOR)\b/.test(one.code)).map((one) => one.name), ['banners/banner-stack.ts']);
    assert.match(guide.code, /protected readonly readme = README_URL;/);
    assert.match(file('about/about-dialog.ts').code, /protected readonly readme = README_URL;/);
  });
});

describe('the banner stack\'s allowance', () => {
  it('shows the window that AllowanceState says holds, in place of the store\'s own allowance condition, so that it clears on the page\'s clock', () => {
    assert.match(stack.code, /status: this\.withAllowance\(store\.status\)/, 'the input\'s status is the store\'s with the allowance replaced');
    const body = method(stack, 'withAllowance');
    assert.match(body, /^const \{ allowance: _stored, \.\.\.rest \} = status; const window = this\.allowance\.active\(\);/, 'the stored condition is dropped first');
    assert.match(body, /return window === undefined \? rest : \{ \.\.\.rest, allowance: \{ condition: 'allowance', active: true, slots: /, 'and rebuilt from the window, or left out when none holds');
    assert.match(body, /slots: \{ \.\.\.\(window\.limit === undefined \? \{\} : \{ limit: window\.limit \}\), time: window\.time \} \} \};$/, 'with the limit when known and the time');
  });
});

describe('the composer (UX-DR68)', () => {
  it('marks the field and Send aria-disabled and described by the reason while the allowance is used up, and never disables them', () => {
    assert.equal((composer.code.match(/\[attr\.aria-disabled\]="reason\(\) \? 'true' : null"/g) ?? []).length, 2, 'the field and Send');
    assert.equal((composer.code.match(/\[attr\.aria-describedby\]="reason\(\) \? reasonId : null"/g) ?? []).length, 2, 'both described by the reason');
    assert.doesNotMatch(composer.code, /\[(?:attr\.)?disabled\]|\sdisabled(?:=|\s|>)/, 'neither is disabled, so both keep their place in the tab order');
    assert.match(composer.code, /export const COMPOSER_REASON_ID = 'composer-allowance-reason';/);
    assert.match(composer.code, /protected readonly reasonId = COMPOSER_REASON_ID;/);
    assert.match(composer.code, /<p class="reason" \[id\]="reasonId">\{\{ text \}\}<\/p>/, 'and the reason is a visible paragraph with that id');
  });

  it('the reason is the banner\'s own text, for the window that AllowanceState says holds', () => {
    assert.match(composer.code, /const window = this\.allowance\.active\(\);\s*return window === undefined \? '' : allowanceReason\(window\);/);
    assert.match(stack.code, /export function allowanceReason\(window: AllowanceWindow\): string \{\s*return bannerText\('banner\.allowance', \{ limit: window\.limit, time: window\.time \}, FORMAT\);/);
  });

  it('send() does nothing while the allowance is used up, before it reads the field, so the text stays', () => {
    assert.match(method(composer, 'send'), /^if \(this\.allowance\.active\(\) !== undefined\) \{ return; \} const field = /);
  });
});

describe('the demo guide', () => {
  it('marks a send prompt aria-disabled and described by the reason while the allowance is used up, and the reason is a visible paragraph', () => {
    assert.match(guide.code, /data-guide-focus="action"\s*\[attr\.aria-disabled\]="allowanceText\(\) \? 'true' : null"\s*\[attr\.aria-describedby\]="allowanceText\(\) \? reasonId : null"\s*\(click\)="send\(prompt\.text\)"/);
    assert.match(guide.code, /@if \(prompt\.action === 'send' && allowanceText\(\); as reason\) \{\s*<p class="reason" \[id\]="reasonId">\{\{ reason \}\}<\/p>/);
    assert.match(guide.code, /protected readonly reasonId = 'guide-allowance-reason';/);
    assert.doesNotMatch(guide.code, /\[(?:attr\.)?disabled\]/);
  });

  it('send() does nothing while the allowance is used up, and only the send prompt is marked', () => {
    assert.match(method(guide, 'send'), /^if \(this\.allowance\.active\(\) !== undefined\) \{ return; \}/);
    assert.equal((guide.code.match(/\[attr\.aria-disabled\]/g) ?? []).length, 1, 'no other action of the guide is marked');
  });
});

describe('the outbox', () => {
  it('learns the window from a 429 allowance, then lets the entry leave, before the failure of any other error', () => {
    const at = (text) => outbox.code.indexOf(text);
    const learn = at("const refusal = refusalOf(error, 'allowance');");
    assert.ok(learn > 0, 'it reads a 429 allowance');
    assert.ok(at('this.allowance.refused(refusal);') > learn, 'it tells the allowance state');
    assert.ok(at('if (this.refuse(entry)) {') > at('this.allowance.refused(refusal);'), 'then it offers the text back');
    assert.ok(at("this.mark(entry.clientId, 'failed');") > at('if (this.refuse(entry)) {'), 'and an entry that did not leave fails as any other');
    assert.match(outbox.code, /if \(refusal !== undefined\) \{\s*this\.allowance\.refused\(refusal\);\s*if \(this\.refuse\(entry\)\) \{\s*return;\s*\}\s*\}/);
  });
});

describe('the simulated mailbox', () => {
  it('holds the limit from a 429 email_limit in both error handlers, before any error text', () => {
    assert.match(mailbox.code, /const refusal = refusalOf\(error, 'email_limit'\);/);
    assert.equal((mailbox.code.match(/if \(!this\.limit\(error\)\) \{/g) ?? []).length, 2, 'the chip press and Send');
    assert.match(mailbox.code, /if \(!this\.limit\(error\)\) \{\s*this\.chipError\.set\(messageOf\(error\)\);/);
    assert.match(mailbox.code, /if \(!this\.limit\(error\)\) \{\s*this\.sendError\.set\(messageOf\(error\)\);/);
  });

  it('marks the chips and Send inactive and described by the reason while it holds, and never disables them', () => {
    assert.match(mailbox.code, /\[inactive\]="limited\(\)"\s*\[describedBy\]="chipDescribed\(\)"/);
    assert.match(mailbox.code, /\[action\]="send" \[inactive\]="limited\(\)" \[describedBy\]="sendDescribed\(\)"/);
    assert.match(mailbox.code, /const LIMIT_ID = 'mailbox-email-limit';/);
    assert.match(mailbox.code, /@if \(limited\(\)\) \{\s*<p class="limit" id="mailbox-email-limit">\{\{ limitText\(\) \}\}<\/p>/);
    assert.doesNotMatch(mailbox.code, /\[(?:attr\.)?disabled\]/);
  });

  it('clears the limit at its time on the page\'s clock, and says nothing of it as an error', () => {
    assert.match(mailbox.code, /const wait = Date\.parse\(this\.limitUntil\(\)\) - Date\.now\(\);\s*if \(!\(wait > 0\)\) \{\s*this\.limitUntil\.set\(''\);/);
    assert.match(mailbox.code, /this\.limitTimer = globalThis\.setTimeout\(\(\) => \{\s*this\.limitTimer = undefined;\s*this\.armLimit\(\);/);
  });
});

describe('who reads the allowance (the Always list: Break the feed, Approve and Reject are never disabled by it)', () => {
  it('AllowanceState is injected by the banner stack, the composer, the guide, the outbox and the Try it yourself row and by nothing else', () => {
    const injecting = files.filter((one) => /inject\(\s*AllowanceState\s*\)/.test(one.code)).map((one) => one.name);
    assert.deepEqual(injecting, ['banners/banner-stack.ts', 'chat/chat-outbox.ts', 'chat/composer.ts', 'chat/try-it-row.ts', 'guide/demo-guide.ts']);
  });

  it('so Break the feed\'s box and the approval and incident cards never name it', () => {
    const naming = files.filter((one) => /\bAllowanceState\b|allowance-state|allowance-view/.test(one.code)).map((one) => one.name);
    assert.deepEqual(naming, ['banners/banner-stack.ts', 'chat/chat-outbox.ts', 'chat/composer.ts', 'chat/try-it-row.ts', 'guide/demo-guide.ts', 'live/allowance-state.ts', 'mailbox/simulated-mailbox.ts']);
    assert.ok(!naming.some((name) => /^(?:feed|approval|incident)\//.test(name)));
  });
});

describe('the browser case\'s notice card text holds at any time of day (Story 16.9 CI rework)', () => {
  const spec = readFileSync(join(here, '..', 'e2e-online', 'allowance', 'messages.spec.ts'), 'utf8');
  const found = /\nconst CARD_TEXT = (\/.*\/);\n/.exec(spec);
  assert.ok(found, 'messages.spec.ts names CARD_TEXT as a regular expression');
  const card = new Function(`return ${found[1]};`)();
  const head = "You've used this session's 50 messages for the hour. You can send more ";
  const tail = ' ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself';

  it('takes the clock alone, as the catalog shows a time on the day of the reading', () => {
    assert.match(`${head}at 15:02${tail}`, card);
  });

  it('takes a clock with its day, as the catalog shows a retryAt after midnight of the instance zone', () => {
    for (const day of ['Friday', 'Monday', 'Oct 9', 'Dec 30, 2025']) {
      assert.match(`${head}on ${day} at 00:09${tail}`, card, day);
    }
  });

  it('takes no other shape', () => {
    for (const text of [`${head}at Friday at 00:09${tail}`, `${head}at Oct 9 at 00:09${tail}`, `${head}at 15:02`, `${head}at 15:02 UTC, or install`, `${head}on Friday 00:09${tail}`, `${head}at 5:02${tail}`, `${head}at 105:02${tail}`, `${head}on Today at 00:09${tail}`, `${head}on Oct at 00:09${tail}`, `${head}on Friday 9 at 00:09${tail}`, `${head}on October 9 at 00:09${tail}`]) {
      assert.doesNotMatch(text, card, text);
    }
  });
});
