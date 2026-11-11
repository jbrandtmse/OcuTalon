// Tests of the Webhooks group's view rules (Story 35.3; webhooks-view.ts) and of its fixed strings (SETTINGS_TEXTS.webhooks): the strings are the accepted
// wording of the Message Catalog keys (src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls), the address line, and the classification of a refused or failed call.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { SETTINGS_TEXTS } = await import(app('settings', 'settings-view.ts'));
const { addressText, webhookOutcome } = await import(app('settings', 'webhooks-view.ts'));
const core = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Msg', 'Catalog', 'Core.cls'), 'utf8');

/** The text of a catalog key of Core.cls, as the XData holds it (JSON escapes undone). */
function catalogText(key) {
  const match = core.match(new RegExp(`"${key.replace('.', '\\.')}": \\{\\s*"text": ("(?:[^"\\\\]|\\\\.)*")`));
  assert.ok(match, `${key} is in the Core catalog`);
  return JSON.parse(match[1]);
}

describe('the group\'s fixed strings', () => {
  it('are the texts of the catalog keys, word for word', () => {
    const t = SETTINGS_TEXTS.webhooks;
    assert.equal(t.heading, catalogText('settings.webhooksHeading'));
    assert.equal(t.help, catalogText('settings.webhooksHelp'));
    assert.equal(t.name, catalogText('settings.webhookName'));
    assert.equal(t.secret, catalogText('settings.webhookSecret'));
    assert.equal(t.create, catalogText('settings.webhookCreate'));
    assert.equal(t.address, catalogText('settings.webhookAddress'));
    assert.equal(t.secretSet, catalogText('settings.secretSet'));
    assert.equal(t.offOnDemo, catalogText('settings.webhooksOffOnDemo'));
  });

  it('reuse the page\'s saved, failed and denied texts', () => {
    assert.equal(SETTINGS_TEXTS.saved, 'Saved. Applies within a minute. Recorded in the audit log.');
    assert.equal(SETTINGS_TEXTS.failed, "Couldn't save. Nothing was changed.");
    assert.equal(SETTINGS_TEXTS.denied, 'Only OcuTalon admins can open settings.');
  });
});

describe('addressText', () => {
  it('puts the page\'s origin and the webhook\'s path in the accepted sentence', () => {
    assert.equal(addressText(SETTINGS_TEXTS.webhooks.address, 'https://host.example:8443', '/ocutalon/hook/abc'), 'Send events with POST to https://host.example:8443/ocutalon/hook/abc.');
    assert.equal(addressText(SETTINGS_TEXTS.webhooks.address, 'http://localhost:52773', '/ocutalon/hook/x_y-z'), 'Send events with POST to http://localhost:52773/ocutalon/hook/x_y-z.');
  });
});

describe('webhookOutcome', () => {
  const bad = (fields) => ({ error: { code: 'bad_webhook', message: "Couldn't save. Nothing was changed." }, fields });

  it('is denied for a 403', () => {
    assert.deepEqual(webhookOutcome(403, { error: { code: 'not_admin', message: 'x' } }), { kind: 'denied' });
    assert.deepEqual(webhookOutcome(403, null), { kind: 'denied' });
  });

  it('is off for a 409 not_available only', () => {
    assert.deepEqual(webhookOutcome(409, { error: { code: 'not_available', message: 'x' } }), { kind: 'off' });
    assert.deepEqual(webhookOutcome(409, { error: { code: 'other', message: 'x' } }), { kind: 'form' });
    assert.deepEqual(webhookOutcome(409, undefined), { kind: 'form' });
  });

  it('takes the text of each refused field of a 400 bad_webhook', () => {
    assert.deepEqual(webhookOutcome(400, bad({ name: 'Enter a name.', secret: 'Use a secret.' })), { kind: 'fields', name: 'Enter a name.', secret: 'Use a secret.' });
    assert.deepEqual(webhookOutcome(400, bad({ secret: 'Use a secret.' })), { kind: 'fields', name: '', secret: 'Use a secret.' });
    assert.deepEqual(webhookOutcome(400, bad({ name: 'Taken.' })), { kind: 'fields', name: 'Taken.', secret: '' });
  });

  it('is a form error for a 400 that names no field, or the wrong kind of field, and for every other answer', () => {
    assert.deepEqual(webhookOutcome(400, bad({})), { kind: 'form' });
    assert.deepEqual(webhookOutcome(400, bad({ name: 5, secret: null })), { kind: 'form' });
    assert.deepEqual(webhookOutcome(400, bad(undefined)), { kind: 'form' });
    assert.deepEqual(webhookOutcome(400, { error: { code: 'bad_settings' }, fields: { name: 'x' } }), { kind: 'form' });
    assert.deepEqual(webhookOutcome(404, { error: { code: 'not_found' } }), { kind: 'form' });
    assert.deepEqual(webhookOutcome(500, { error: { code: 'server_error' } }), { kind: 'form' });
    assert.deepEqual(webhookOutcome(0, null), { kind: 'form' });
  });
});
