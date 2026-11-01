// Tests the shape of the page's sources that the Demo view switch relies on (Story 4.9; AD-12): the server's demo mode is read in one
// place, DemoView, and every other part that shows only in demo mode goes through it. The browser cases (demo-switch view.spec.ts, answers
// X11) pin what the running page does; this reads every source, so a part added later cannot read the server's flag itself without a
// test turning red.
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

describe('the server\'s demo mode is read in one place', () => {
  it('appears only in the payload types, DemoView, the header pill and the three view-model gates', () => {
    const readers = Object.fromEntries(files.filter((one) => /\bdemoMode\b/.test(one.code)).map((one) => [one.name, count(one.code, /\bdemoMode\b/g)]));
    assert.deepEqual(Object.keys(readers).sort(), [
      'api/api-types.ts',
      'guide/guide-view.ts',
      'header/header.ts',
      'mailbox/mailbox-view.ts',
      'phone/phone-view.ts',
      'shared/demo-view.ts',
    ]);
    assert.equal(readers['header/header.ts'], 1, 'the pill reads it once');
    assert.match(file('header/header.ts').code, /snapshot\?\.demoMode \? 'Demo mode'/);
    for (const name of ['guide/guide-view.ts', 'phone/phone-view.ts', 'mailbox/mailbox-view.ts']) {
      assert.equal(readers[name], 1, `${name} gates on its argument once`);
      assert.match(file(name).code, /snapshot\.demoMode !== true/, `${name} gates on snapshot.demoMode !== true`);
    }
  });
});

describe('the view models are given the demo view\'s snapshot', () => {
  it('passes demoView.snapshot() to every call of guideOf, phoneOf and mailOf outside their modules, and never the live snapshot', () => {
    const own = { guideOf: 'guide/guide-view.ts', phoneOf: 'phone/phone-view.ts', mailOf: 'mailbox/mailbox-view.ts' };
    let calls = 0;
    for (const one of files) {
      for (const [name, module] of Object.entries(own)) {
        if (one.name === module) continue;
        for (const call of one.code.matchAll(new RegExp(`\\b${name}\\(([^)]*)`, 'g'))) {
          calls += 1;
          // The device panel hands over the local that its effect reads from demoView.snapshot() (pinned below).
          const given = one.name === 'devices/device-panel.ts' ? /^\s*snapshot\b/ : /^\s*this\.demoView\.snapshot\(/;
          assert.match(call[1], given, `${one.name}: ${name}( gets demoView.snapshot()`);
        }
      }
    }
    assert.ok(calls >= 5, `the calls are found (${calls})`);
  });

  it('keeps the rest of a view-model caller off the live snapshot for the same purpose: the device panel notes the demo view\'s snapshot', () => {
    assert.match(file('devices/device-panel.ts').code, /const snapshot = this\.demoView\.snapshot\(\);/);
  });
});

describe('the boolean readers use demoView.on()', () => {
  it('has the chat panel, the device panel, the skip links and the status rail read it', () => {
    for (const name of ['chat/chat-panel.ts', 'devices/device-panel.ts', 'header/skip-links.ts', 'rail/status-rail.ts']) {
      assert.match(file(name).code, /\bdemoView\.on\(\)/, `${name} reads demoView.on()`);
    }
  });
});

describe('DemoView keeps the choice in this tab\'s session storage', () => {
  it('reads and writes window.sessionStorage only through readFlag and writeFlag', () => {
    const { code } = file('shared/demo-view.ts');
    assert.equal(count(code, /sessionStorage/g), 2, 'two mentions, one per helper');
    assert.match(code, /readFlag\(\(\) => window\.sessionStorage, DEMO_VIEW_KEY, DEMO_VIEW_OFF\)/);
    assert.match(code, /writeFlag\(\(\) => window\.sessionStorage, DEMO_VIEW_KEY,/);
    assert.doesNotMatch(code, /\.(getItem|setItem|removeItem)\(/);
    assert.match(code, /DEMO_VIEW_KEY = 'ocutalon\.demoView\.off'/);
  });
});

describe('the switch is a native switch that only changes the view', () => {
  it('has role="switch" and aria-checked, and no announcer, focus call or server client', () => {
    const { code } = file('header/demo-view-switch.ts');
    assert.match(code, /role="switch"/);
    assert.match(code, /aria-checked/);
    assert.doesNotMatch(code, /\bAnnouncer\b|\.announce\(|\.focus\(|\bApiClient\b|\bHttpClient\b/);
  });
});
