// Tests the simulated device panel's view model (src/app/devices/device-view.ts, Story 4.5): the fixed strings are the UX's exact
// wording, a tab's name carries its count only while it has new content ("Simulated mailbox, 2 new"), the other tab wraps both ways,
// the stored value names the mailbox only for its flag, and the refs that count as new are those not seen at the last look. The module
// is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { DEVICE_TEXTS, MAILBOX_FLAG, TAB_KEY, baseName, newRefs, otherTab, tabName } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'devices', 'device-view.ts')).href);
const { readFlag } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'shared', 'stored-flag.ts')).href);

describe('the fixed strings', () => {
  it('are the UX\'s exact wording', () => {
    assert.deepEqual({ ...DEVICE_TEXTS }, {
      region: 'Simulated devices',
      phoneTab: 'Simulated phone',
      mailboxTab: 'Simulated mailbox',
      simulated: 'Simulated',
      badge: '{tab}, {n} new',
    });
    assert.equal(TAB_KEY, 'ocutalon.devices.tab');
  });
});

describe('tabName', () => {
  it('is the tab\'s own name with no new content', () => {
    assert.equal(tabName('phone', 0), 'Simulated phone');
    assert.equal(tabName('mailbox', 0), 'Simulated mailbox');
    assert.equal(baseName('phone'), 'Simulated phone');
  });

  it('adds ", {n} new" with new content, as EXPERIENCE writes it', () => {
    assert.equal(tabName('mailbox', 2), 'Simulated mailbox, 2 new');
    assert.equal(tabName('phone', 1), 'Simulated phone, 1 new');
  });
});

describe('otherTab and the stored flag', () => {
  it('wraps both ways between the two tabs', () => {
    assert.equal(otherTab('phone'), 'mailbox');
    assert.equal(otherTab('mailbox'), 'phone');
    assert.equal(otherTab(otherTab('phone')), 'phone');
  });

  it('reads the mailbox from its flag only, and the phone from anything else', () => {
    const open = (value) => () => ({ getItem: (key) => (key === TAB_KEY ? value : null) });
    assert.equal(readFlag(open(MAILBOX_FLAG), TAB_KEY, MAILBOX_FLAG), true);
    for (const other of ['phone', '', 'Mailbox', 'x', null]) {
      assert.equal(readFlag(open(other), TAB_KEY, MAILBOX_FLAG), false, String(other));
    }
  });
});

describe('newRefs', () => {
  it('gives the refs that were not seen, in order', () => {
    assert.deepEqual(newRefs(new Set(['a', 'b']), ['a', 'b', 'c', 'd']), ['c', 'd']);
  });

  it('gives none for what was seen at the load, so the snapshot\'s content is never new', () => {
    assert.deepEqual(newRefs(new Set(['a', 'b']), ['a', 'b']), []);
    assert.deepEqual(newRefs(new Set(), []), []);
  });

  it('counts a ref once even when the list holds it twice', () => {
    assert.deepEqual(newRefs(new Set(), ['x', 'x', 'y']), ['x', 'y']);
  });
});
