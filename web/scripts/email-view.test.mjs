// Tests of the Email form's view model (Stories 21.2, 21.6 and 21.3): the body of a save leaves an untyped password or client secret out and sends only the
// secrets of the chosen sign-in method, the dirty rule, the texts of a form built from the server's values (the secret texts are always empty), the
// sign-in rules (button, redirect address, state line, the address the consent returns to), and the error under a refused field. The module is framework-free, so Node runs it as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { pathToFileURL } from 'node:url';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const view = await import(pathToFileURL(join(here, '..', 'src', 'app', 'settings', 'email-view.ts')).href);
const settings = await import(pathToFileURL(join(here, '..', 'src', 'app', 'settings', 'settings-view.ts')).href);

const SAVED = { address: 'me@example.com', incoming: 'pop.example.com', outgoing: 'smtp.example.com', user: 'me', password: '', clientId: '', clientSecret: '', signIn: 'password' };
const GOOGLE = { ...SAVED, signIn: 'google', clientId: 'id-1.example' };
const VALUES = { address: 'me@example.com', incoming: 'pop.example.com', outgoing: 'smtp.example.com', user: 'me', passwordSet: true, signIn: 'password', clientId: '', clientSecretSet: false, signedIn: false };

describe('the Email form', () => {
  it('builds its texts from the server values, with an empty password', () => {
    assert.deepEqual(view.emailTextsOf(VALUES), SAVED);
    assert.deepEqual(view.emailTextsOf({ ...VALUES, signIn: 'google', clientId: 'id-1.example', clientSecretSet: true }), GOOGLE);
    assert.deepEqual(view.emailTextsOf(undefined), { address: '', incoming: '', outgoing: '', user: '', password: '', clientId: '', clientSecret: '', signIn: 'password' });
  });

  it('sends the password only when one was typed', () => {
    assert.deepEqual(view.emailBody(SAVED), { address: 'me@example.com', incoming: 'pop.example.com', outgoing: 'smtp.example.com', user: 'me', signIn: 'password' });
    assert.deepEqual(view.emailBody({ ...SAVED, password: 'typed' }), { address: 'me@example.com', incoming: 'pop.example.com', outgoing: 'smtp.example.com', user: 'me', signIn: 'password', password: 'typed' });
  });

  it('sends the client ID always and the client secret only when typed in a provider mode, and never the password', () => {
    assert.deepEqual(view.emailBody(GOOGLE), { address: 'me@example.com', incoming: 'pop.example.com', outgoing: 'smtp.example.com', user: 'me', signIn: 'google', clientId: 'id-1.example' });
    assert.deepEqual(view.emailBody({ ...GOOGLE, clientSecret: 'typed-secret', password: 'left-over' }), { address: 'me@example.com', incoming: 'pop.example.com', outgoing: 'smtp.example.com', user: 'me', signIn: 'google', clientId: 'id-1.example', clientSecret: 'typed-secret' });
    assert.deepEqual(view.emailBody({ ...SAVED, clientId: 'left-over', clientSecret: 'left-over' }).clientId, undefined);
    assert.equal('clientSecret' in view.emailBody({ ...SAVED, clientSecret: 'left-over' }), false);
  });

  it('always sends the outgoing server, so that an empty one clears it', () => {
    assert.deepEqual(view.emailBody({ ...SAVED, outgoing: '' }), { address: 'me@example.com', incoming: 'pop.example.com', outgoing: '', user: 'me', signIn: 'password' });
  });

  it('is dirty when a text changed or a password was typed', () => {
    assert.equal(view.isEmailDirty(SAVED, SAVED), false);
    assert.equal(view.isEmailDirty({ ...SAVED, address: 'other@example.com' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, incoming: 'pop.example.com:110' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, outgoing: 'smtp.example.com:465' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, outgoing: '' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, user: 'you' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, password: 'x' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...SAVED, signIn: 'google' }, SAVED), true);
    assert.equal(view.isEmailDirty({ ...GOOGLE, clientId: 'id-2.example' }, GOOGLE), true);
    assert.equal(view.isEmailDirty({ ...GOOGLE, clientSecret: 'x' }, GOOGLE), true);
    assert.equal(view.isEmailDirty({ ...GOOGLE, password: 'x' }, GOOGLE), false, 'a password typed before a provider was chosen is not sent, so it does not make the form dirty');
    assert.equal(view.isEmailDirty({ ...SAVED, clientSecret: 'x' }, SAVED), false, 'a client secret typed before Password was chosen does not make the form dirty');
    assert.equal(view.isEmailDirty(GOOGLE, GOOGLE), false);
  });

  it('offers the sign-in button only for the saved provider, with a client registered and a clean form', () => {
    assert.equal(view.signInReady(GOOGLE, GOOGLE, true), true);
    assert.equal(view.signInReady(GOOGLE, GOOGLE, false), false);
    assert.equal(view.signInReady({ ...GOOGLE, clientId: 'other' }, GOOGLE, true), false);
    assert.equal(view.signInReady({ ...GOOGLE, clientSecret: 'x' }, GOOGLE, true), false);
    assert.equal(view.signInReady({ ...GOOGLE, signIn: 'microsoft' }, GOOGLE, true), false);
    assert.equal(view.signInReady(SAVED, SAVED, true), false);
  });

  it('names the provider in the button, the redirect help and the state line', () => {
    assert.equal(view.signInButtonText('google'), 'Sign in with Google');
    assert.equal(view.signInButtonText('microsoft'), 'Sign in with Microsoft 365');
    assert.equal(view.redirectHelpText('microsoft'), 'Add this address to your OAuth2 client at Microsoft 365 as an authorized redirect URI.');
    assert.equal(view.stateText('google', true), 'Signed in with Google.');
    assert.equal(view.stateText('microsoft', false), 'Not signed in yet. Save, then sign in with Microsoft 365.');
    assert.deepEqual(view.SIGN_IN_METHODS.map((one) => [one.value, one.label]), [['password', 'Password'], ['google', 'Google'], ['microsoft', 'Microsoft 365']]);
  });

  it('shows IRIS\'s redirection endpoint on the page\'s origin', () => {
    assert.equal(view.redirectAddress('http://127.0.0.1:52773'), 'http://127.0.0.1:52773/csp/sys/oauth2/OAuth2.Response.cls');
  });

  it('reads and clears the signin=1 of the address that the consent returns to', () => {
    assert.equal(view.landedFromSignIn('#/settings/channels?signin=1'), true);
    assert.equal(view.landedFromSignIn('#/settings/channels?x=2&signin=1'), true);
    assert.equal(view.landedFromSignIn('#/settings/channels'), false);
    assert.equal(view.landedFromSignIn('#/settings/channels?signin=10'), false);
    assert.equal(view.withoutLanding('#/settings/channels?signin=1'), '#/settings/channels');
    assert.equal(view.withoutLanding('#/settings/channels?x=2&signin=1'), '#/settings/channels?x=2');
    assert.equal(view.withoutLanding('#/settings/channels'), '#/settings/channels');
  });

  it('shows the setting-reference text for a typed value that holds the characters, else the page text', () => {
    const refused = { ...SAVED, user: 'a@{b' };
    assert.equal(view.fieldErrorText(refused, 'user', settings.SETTINGS_TEXTS.failed), view.EMAIL_TEXTS.refusedExpansion);
    assert.equal(view.fieldErrorText(refused, 'address', settings.SETTINGS_TEXTS.failed), settings.SETTINGS_TEXTS.failed);
    assert.equal(view.holdsReference('x@{'), true);
    assert.equal(view.holdsReference('@ {'), false);
  });

  it('names the seven text fields in the order of the form', () => {
    assert.deepEqual([...view.EMAIL_FIELDS], ['address', 'incoming', 'outgoing', 'user', 'password', 'clientId', 'clientSecret']);
    assert.equal(view.EMAIL_TEXTS.outgoing, 'Outgoing mail server (SMTP)');
  });
});
