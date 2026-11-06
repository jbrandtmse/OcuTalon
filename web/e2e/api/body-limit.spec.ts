import { expect, test, type APIRequestContext } from '../support/fixtures';

import { MESSAGES, post } from '../support/api';
import { README_ACCOUNT, signInOverHttp } from '../sign-in/helpers';

/**
 * Story 11.22 (DW-687): the request body limit over real HTTP, on a stack that test-sign-in.sh has seeded. A signed-in POST whose body is
 * 262,144 bytes (256 KB) reaches the route, which answers its own 400 bad_message because the body is JSON but not a message; the same
 * body one byte longer is refused with 413 body_too_large before the route reads it. No message is ever started: both bodies are refused.
 */

const LIMIT = 262_144;
const TOO_LARGE = 'OcuTalon refused this request because its body is larger than it accepts.';
const BAD_MESSAGE = 'A message needs a clientId and some text.';

/** A JSON object that is not a message, of exactly `bytes` ASCII bytes. */
function paddedBody(bytes: number): string {
  const frame = '{"pad":""}';
  return `{"pad":"${'x'.repeat(bytes - frame.length)}"}`;
}

test.describe('story 11.22: the request body limit', () => {
  let signedIn: APIRequestContext;

  test.beforeAll(async ({ playwright }) => {
    signedIn = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    await signInOverHttp(signedIn, README_ACCOUNT.user, README_ACCOUNT.password);
  });

  test.afterAll(async () => {
    await signedIn.dispose();
  });

  test('a body of exactly 262,144 bytes reaches the route: 400 bad_message', async () => {
    const body = paddedBody(LIMIT);
    expect(Buffer.byteLength(body, 'utf8')).toBe(LIMIT);
    const response = await post(signedIn, MESSAGES, body);
    expect(response.status(), await response.text()).toBe(400);
    const answer = (await response.json()) as { error: { code: string; message: string } };
    expect(answer.error.code).toBe('bad_message');
    expect(answer.error.message).toBe(BAD_MESSAGE);
  });

  test('a body of 262,145 bytes is refused before the route: 413 body_too_large', async () => {
    const body = paddedBody(LIMIT + 1);
    expect(Buffer.byteLength(body, 'utf8')).toBe(LIMIT + 1);
    const response = await post(signedIn, MESSAGES, body);
    expect(response.status(), await response.text()).toBe(413);
    const answer = (await response.json()) as { error: { code: string; message: string } };
    expect(Object.keys(answer)).toEqual(['error']);
    expect(Object.keys(answer.error).sort()).toEqual(['code', 'message']);
    expect(answer.error.code).toBe('body_too_large');
    expect(answer.error.message).toBe(TOO_LARGE);
  });
});
