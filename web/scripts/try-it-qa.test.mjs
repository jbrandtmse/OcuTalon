// Tests, from the sources, the parts of Story 4.10's acceptance that the browser cases cannot pin cheaply (Story 4.10): the row
// is gated by the demo view around the whole group; its chips are native buttons named by their text alone (no aria-label, no
// tabindex, never disabled, aria-disabled bound), under a labelled group whose label is a paragraph, not a heading; a press is refused
// by the row's own state (a turn in flight or a used-up allowance) before anything is sent; the chips are described by the composer's
// reason only while the allowance is used up; and the in-flight reader looks at chat messages only.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const files = sourceFiles(join(here, '..', 'src', 'app'), ['.ts']);
const { code } = files.find((one) => one.name === 'chat/try-it-row.ts') ?? {};
const { turnInFlight } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'try-it-view.ts')).href);

describe('the row (try-it-row.ts), QA', () => {
  it('is read from the sources', () => {
    assert.equal(typeof code, 'string');
  });

  it('shows nothing outside the demo view: the whole group sits inside @if (demoView.on())', () => {
    const gate = code.indexOf('@if (demoView.on())');
    const group = code.indexOf('role="group"');
    const button = code.indexOf('<button');
    assert.ok(gate > 0, 'the gate is in the template');
    assert.ok(group > gate && button > group, 'gate < group < buttons');
    assert.equal((code.match(/@if \(/g) ?? []).length, 1, 'one gate, and nothing else conditional shows a chip');
  });

  it('has native buttons named by their text alone, never disabled and always focusable', () => {
    const button = code.match(/<button[\s\S]*?<\/button>/)[0];
    assert.match(button, /\{\{ prompt \}\}/, 'the name is the prompt text');
    assert.doesNotMatch(button, /aria-label|aria-labelledby|title=|tabindex|\[disabled\]|\[attr\.disabled\]|\sdisabled[\s=>]/i);
    assert.match(button, /\[attr\.aria-disabled\]="blocked\(\) \? 'true' : null"/);
    assert.doesNotMatch(code, /<img|<svg|<mat-icon|<app-icon/, 'no icon');
  });

  it('labels the group by a visible paragraph and never by a heading', () => {
    assert.match(code, /role="group"[^>]*\[attr\.aria-labelledby\]="labelId"/);
    assert.match(code, /<p class="try-label" \[id\]="labelId">\{\{ texts\.label \}\}<\/p>/);
    assert.doesNotMatch(code, /<h[1-6]\b|role="heading"/);
    assert.match(code, /`try-it-label-\$\{\+\+rows\}`/, 'a label id per instance, from a module counter');
  });

  it('refuses a press before it sends: blocked is a turn in flight or a used-up allowance, checked first in press()', () => {
    assert.match(code, /blocked = computed\(\(\) => this\.inFlight\(\) \|\| this\.used\(\)\)/);
    assert.match(code, /inFlight = computed\(\(\) => turnInFlight\(this\.live\.store\(\)\?\.chat \?\? \[\], this\.outbox\.entries\(\)\)\)/);
    assert.match(code, /used = computed\(\(\) => this\.allowance\.active\(\) !== undefined\)/);
    const press = code.slice(code.indexOf('protected press('));
    assert.ok(press.indexOf('this.blocked()') > 0 && press.indexOf('this.blocked()') < press.indexOf('this.outbox.send('), 'blocked is checked before send');
    assert.match(press, /if \(this\.blocked\(\)\) \{\s*return;\s*\}/);
  });

  it('describes the chips by the composer\'s reason only while the allowance is used up', () => {
    assert.match(code, /describedBy = computed\(\(\) => \(this\.used\(\) \? COMPOSER_REASON_ID : null\)\)/);
    assert.match(code, /\[attr\.aria-describedby\]="describedBy\(\)"/);
  });
});

describe('turnInFlight, QA', () => {
  const entry = (status) => ({ clientId: 'c', text: 't', fromGuide: false, sentAt: '2037-07-01T12:00:00Z', status });

  it('looks at chat messages only: another item type that is running or queued is not a turn', () => {
    assert.equal(turnInFlight([{ type: 'reminder.state', payload: { state: 'running' } }], []), false);
    assert.equal(turnInFlight([{ type: 'chat.notice', payload: { state: 'queued' } }], []), false);
  });

  it('is true while an entry is sent and the store holds nothing (the window before the first poll answer)', () => {
    assert.equal(turnInFlight([], [entry('sent')]), true);
    assert.equal(turnInFlight([], [entry('sending')]), true);
  });

  it('is false again once the entry failed and every message is done', () => {
    assert.equal(turnInFlight([{ type: 'chat.message', payload: { state: 'done' } }], [entry('failed')]), false);
  });
});
