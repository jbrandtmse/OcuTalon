// Tests of the Email form's view model (Story 21.2): the body of a save leaves an untyped password out, the dirty rule, the texts of a form built from the
// server's values (the password text is always empty), and the error under a refused field. The module is framework-free, so Node runs it as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { pathToFileURL } from 'node:url';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const view = await import(pathToFileURL(join(here, '..', 'src', 'app', 'settings', 'email-view.ts')).href);
const settings = await import(pathToFileURL(join(here, '..', 'src', 'app', 'settings', 'settings-view.ts')).href);

const SAVED = { address: 'me@example.com', incoming: 'pop.example.com', user: 'me', password: '' };

describe('the Email form', () => {
  it('builds its texts from the server values, with an empty password', () => {
    assert.deepEqual(view.emailTextsOf({ address: 'me@example.com', incoming: 'pop.example.com', user: 'me', passwordSet: true }), SAVED);
    assert.deepEqual(view.emailTextsOf(undefined), { address: '', incoming: '', user: '', password: '' });
  });

  it('sends the password only when one was typed', () => {
    assert.deepEqual(view.emailBody(SAVED), { address: 'me@example.com', incoming: 'pop.example.com', user: 'me' });
    assert.deepEqual(view.emailBody({ ...SAVED, password: 'typed' }), { address: 'me@example.com', incoming: 'pop.example.com', user: 'me', password: 'typed' });
  });

  it('is dirty when a text changed or a password was typed', () => {
    assert.equal(view.isEmailDirty(SAVED, SAVED), false);
    assert.equal(view.isEmailDirty({ ...SAVED, address: 'other@example.com' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, incoming: 'pop.example.com:110' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, user: 'you' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, password: 'x' }, SAVED), true);
  });

  it('shows the setting-reference text for a typed value that holds the characters, else the page text', () => {
    const refused = { ...SAVED, user: 'a@{b' };
    assert.equal(view.fieldErrorText(refused, 'user', settings.SETTINGS_TEXTS.failed), view.EMAIL_TEXTS.refusedExpansion);
    assert.equal(view.fieldErrorText(refused, 'address', settings.SETTINGS_TEXTS.failed), settings.SETTINGS_TEXTS.failed);
    assert.equal(view.holdsReference('x@{'), true);
    assert.equal(view.holdsReference('@ {'), false);
  });

  it('names the four fields in the order of the form', () => {
    assert.deepEqual([...view.EMAIL_FIELDS], ['address', 'incoming', 'user', 'password']);
  });
});
