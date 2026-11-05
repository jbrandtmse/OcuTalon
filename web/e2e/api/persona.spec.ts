import { expect, test } from '@playwright/test';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { chk, irisScript, quoted } from '../support/iris';
import { forget, prepare, sessionRef } from '../support/persona';

/**
 * Story 40.8, the Rule 3 evidence for GET and PUT /api/v1/persona over real HTTP, on the stack that test-sign-in.sh seeds (the README
 * account's session). A request with no session is 401 signed_out, with the envelope whole or broken, and writes nothing, and a signed-in
 * POST is 405 naming GET and PUT. A signed-in PUT without the request header, or not sent as JSON, is 403 and writes nothing. The signed-in
 * README account reads the defaults, saves a language name outside ASCII (which also shows that this stack's web gateway passes the PUT
 * method), reads it back, and is refused a language name with a "!", which leaves the row as it was. The rows are read through irisScript.
 * Before the first case the test sets what it asserts on: onlineDemo off, no persona keys and no setting request for the account. It
 * removes the keys again in `finally`, because other specs expect the defaults.
 */
const PERSONA = '/ocutalon/api/v1/persona';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const SAVED = 'Saved. Applies from your next message. Recorded in the audit log.';
const BAD_LANGUAGE = 'Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters.';
const NOT_JSON = "OcuTalon refused this request because it wasn't sent as JSON.";
const NO_HEADER = "OcuTalon refused this request because it didn't come from the OcuTalon page.";
const NOT_ALLOWED = "This address doesn't accept that kind of request.";
/** Portugues with an e circumflex (U+00EA), written as an escape so that the source stays ASCII. */
const LANGUAGE = 'Portugu\u00eas (Brasil)';

const DEFAULTS = { preset: 'professional', language: '', custom: '', customOffered: true, pendingRef: '' };

/** The stored language row as "<length>|<code of its eighth character>|<preset>", or "none" when there is no row. */
async function storedRow(ref: string): Promise<string> {
  const lines = await irisScript(
    [
      `Set l=##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Core.SettingsOps).PersonaKey(${quoted(ref)},"language"))`,
      `Set p=##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Core.SettingsOps).PersonaKey(${quoted(ref)},"preset"))`,
      'Write !,"CHK|row|",$Select($IsObject(l):$Length(l.Value)_"|"_$ASCII($Extract(l.Value,8))_"|"_$Select($IsObject(p):p.Value,1:""),1:"none")',
    ].join('\n'),
  );
  return chk(lines, 'row') ?? 'unread';
}

test('the persona routes: signed out, the envelope, the defaults, a language outside ASCII, and a refused name', async ({ request, playwright, baseURL }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const ref = await sessionRef();
  await forget(ref);
  try {
    await prepare(ref);

    const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
    try {
      for (const method of ['GET', 'PUT'] as const) {
        for (const headers of [envelope(), { 'content-type': 'text/plain', origin: 'http://evil.example' }]) {
          const response = await anonymous.fetch(PERSONA, { method, headers, data: method === 'PUT' ? '{"preset":"pirate"}' : undefined });
          await expectError(response, 401, 'signed_out', SIGNED_OUT);
          expect(response.headers()['www-authenticate'], `${method} sends no challenge`).toBeUndefined();
        }
      }
    } finally {
      await anonymous.dispose();
    }
    expect(await storedRow(ref), 'a request with no session wrote nothing').toBe('none');

    const wrongMethod = await request.fetch(PERSONA, { method: 'POST', headers: envelope(), data: '{}' });
    await expectError(wrongMethod, 405, 'method_not_allowed', NOT_ALLOWED);
    expect(wrongMethod.headers()['allow']).toContain('GET');
    expect(wrongMethod.headers()['allow']).toContain('PUT');

    await expectError(
      await request.fetch(PERSONA, { method: 'PUT', headers: envelope({ 'x-ocutalon-request': undefined }), data: '{"preset":"pirate"}' }),
      403,
      'no_request_header',
      NO_HEADER,
    );
    await expectError(await request.fetch(PERSONA, { method: 'PUT', headers: envelope({ 'content-type': 'text/plain' }), data: '{"preset":"pirate"}' }), 403, 'not_json', NOT_JSON);
    expect(await storedRow(ref), 'a refused envelope wrote nothing').toBe('none');

    const defaults = await request.get(PERSONA);
    expect(defaults.status(), await defaults.text()).toBe(200);
    expect(defaults.headers()['content-type']).toContain('application/json');
    expect(await defaults.text(), 'the five keys in order').toBe(JSON.stringify(DEFAULTS));

    const saved = await request.fetch(PERSONA, { method: 'PUT', headers: envelope(), data: JSON.stringify({ preset: 'language', language: LANGUAGE }) });
    expect(saved.status(), await saved.text()).toBe(200);
    expect(await saved.json()).toEqual({ result: 'done', message: SAVED, preset: 'language', language: LANGUAGE, custom: '' });
    expect(await storedRow(ref), 'the row holds the 18 characters, the e circumflex among them').toBe('18|234|language');

    const read = await request.get(PERSONA);
    expect(await read.json()).toEqual({ ...DEFAULTS, preset: 'language', language: LANGUAGE });

    await expectError(
      await request.fetch(PERSONA, { method: 'PUT', headers: envelope(), data: JSON.stringify({ preset: 'language', language: 'Spanish!' }) }),
      400,
      'bad_language',
      BAD_LANGUAGE,
    );
    expect(await storedRow(ref), 'a refused name leaves the row as it was').toBe('18|234|language');
    const after = await request.get(PERSONA);
    expect(await after.json()).toEqual({ ...DEFAULTS, preset: 'language', language: LANGUAGE });
  } finally {
    await forget(ref);
  }
});
