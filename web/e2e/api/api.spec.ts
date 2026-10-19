import { expect, test, type APIRequestContext, type APIResponse, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme } from '../sign-in/helpers';

/**
 * Story 0.5, rows 13 to 19: the REST skeleton and the public status over real HTTP, on a stack that
 * test-sign-in.sh has seeded. The script publishes two reminders on the README account's session stream and one
 * status event on the instance stream, and passes what it read back: the manifest's version, the instance zone, the
 * session's epoch and the marker of the seeded texts (reminders `<marker>-1` and `<marker>-2`). It also creates the
 * trace-only user ZzTraceOnly and ZzFirstCall, a user with the user role and no session row. Every variable is
 * required, and the specs fail without it.
 */
function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set by docker/tests/test-sign-in.sh`);
  return value;
}

const VERSION = required('OCUTALON_E2E_VERSION');
const ZONE = required('OCUTALON_E2E_ZONE');
const EPOCH = required('OCUTALON_E2E_EPOCH');
const MARKER = required('OCUTALON_E2E_MARKER');
const TRACE_ONLY = { user: required('OCUTALON_TRACEONLY_USER'), password: required('OCUTALON_TRACEONLY_PASSWORD') };
const FIRST_CALL = { user: required('OCUTALON_FIRSTCALL_USER'), password: required('OCUTALON_FIRSTCALL_PASSWORD') };

/** What a browser always sends, and what a request without a session must still be answered with. */
const BROWSER_HEADERS = { 'accept-language': 'en-US,en;q=0.9' };

const STATE = '/ocutalon/api/v1/state';
const EVENTS = '/ocutalon/api/v1/events';
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const NOT_BUILT = "This part of OcuTalon isn't built yet.";
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';

/** The routes that answer 501 not_built, with the method that each takes. */
const UNBUILT: ReadonlyArray<readonly [method: 'POST', path: string]> = [
  ['POST', '/ocutalon/api/v1/messages'],
  ['POST', '/ocutalon/api/v1/approvals/zz/answer'],
  ['POST', '/ocutalon/api/v1/incidents/zz/dismiss'],
  ['POST', '/ocutalon/api/v1/demo/break-feed'],
  ['POST', '/ocutalon/api/v1/mailbox/incoming'],
  ['POST', '/ocutalon/api/v1/mailbox/samples/zz'],
  ['POST', '/ocutalon/api/v1/guide/markers'],
  ['POST', '/ocutalon/api/v1/session/end'],
];

/** The origin of the stack, which a same-origin POST of the page carries as its Origin header. */
function originOf(baseURL: string | undefined): string {
  if (!baseURL) throw new Error('OCUTALON_URL must name the stack');
  return new URL(baseURL).origin;
}

/** Signs a user in over HTTP, the way a script does: the sign-in page, then the three fields of its form. */
async function signInOverHttp(request: APIRequestContext, user: string, password: string, path = '/ocutalon/'): Promise<APIResponse> {
  await request.get(path);
  return request.post(path, { form: { IRISUsername: user, IRISPassword: password, IRISLogin: 'Sign in' } });
}

/** The error object of an answer, after checking its status and that it is the API's error shape. */
async function expectError(response: APIResponse, status: number, code: string, message?: string): Promise<void> {
  expect(response.status(), await response.text()).toBe(status);
  const body = (await response.json()) as { error: { code: string; message: string } };
  expect(Object.keys(body)).toEqual(['error']);
  expect(Object.keys(body.error).sort()).toEqual(['code', 'message']);
  expect(body.error.code).toBe(code);
  if (message !== undefined) expect(body.error.message).toBe(message);
  else expect(body.error.message.length).toBeGreaterThan(10);
}

/** A state-changing call with a valid envelope; the options override one part of it. */
function post(request: APIRequestContext, baseURL: string | undefined, path: string, headers: Record<string, string | undefined> = {}): Promise<APIResponse> {
  const envelope: Record<string, string | undefined> = {
    'content-type': 'application/json',
    'x-ocutalon-request': '1',
    origin: originOf(baseURL),
    ...headers,
  };
  const sent = Object.fromEntries(Object.entries(envelope).filter((entry): entry is [string, string] => entry[1] !== undefined));
  return request.post(path, { headers: sent, data: '{}' });
}

/** Row 13: the page loads the snapshot, and the snapshot is the seeded session's. */
test('row 13: the page loads /state and marks the snapshot loaded', async ({ page }) => {
  const answered: Response[] = [];
  page.on('response', (response) => {
    if (new URL(response.url()).pathname === STATE) answered.push(response);
  });
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  expect(answered.map((response) => response.status()), 'the page asked for /state once and got 200').toEqual([200]);

  const body = (await answered[0].json()) as Record<string, unknown>;
  expect(Object.keys(body)).toEqual(['version', 'instanceZone', 'epoch', 'streams', 'chat', 'rail']);
  expect(body['version']).toBe(VERSION);
  expect(body['instanceZone']).toBe(ZONE);
  expect(body['epoch']).toBe(EPOCH);
  expect(body['streams']).toEqual({ session: 2, instance: 1 });
  expect(body['chat']).toEqual([]);
  expect(body['rail']).toEqual({ approvals: [], checks: [], reminders: [], decisions: [] });
});

/** Row 13: the first /state of a user with no session row creates it, as that unprivileged user. */
test('row 13: the first /state of a user without a session row creates one, and a second call returns the same', async ({ request }) => {
  await signInOverHttp(request, FIRST_CALL.user, FIRST_CALL.password);
  const first = await request.get(STATE);
  expect(first.status(), await first.text()).toBe(200);
  const body = (await first.json()) as { epoch: string; streams: { session: number; instance: number } };
  expect(body.epoch).toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(body.epoch, "not the README account's epoch").not.toBe(EPOCH);
  expect(body.streams.session).toBe(0);
  const second = (await (await request.get(STATE)).json()) as { epoch: string };
  expect(second.epoch).toBe(body.epoch);
});

/** Row 14: the poll serves the seeded events, session stream first, and refuses a bad cursor. */
test('row 14: /events serves the seeded events by cursor', async ({ request }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const poll = async (query: string): Promise<{ epoch: string; events: Array<Record<string, unknown>> }> => {
    const response = await request.get(`${EVENTS}${query}`);
    expect(response.status(), query).toBe(200);
    return (await response.json()) as { epoch: string; events: Array<Record<string, unknown>> };
  };

  const all = await poll('?after=0&afterInstance=0');
  expect(all.epoch).toBe(EPOCH);
  expect(all.events.map((event) => `${String(event['stream'])}:${String(event['seq'])}:${String(event['type'])}`)).toEqual([
    'session:1:reminder',
    'session:2:reminder',
    'instance:1:status',
  ]);
  for (const event of all.events) {
    expect(Object.keys(event).sort()).toEqual(['payload', 'seq', 'stream', 'ts', 'type']);
    expect(typeof event['seq'], 'seq is a number').toBe('number');
    expect(typeof event['payload'], 'payload is an object').toBe('object');
    expect(String(event['ts'])).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  }
  expect((all.events[0]['payload'] as { text: string }).text).toBe(`${MARKER}-1`);
  expect((all.events[1]['payload'] as { text: string }).text).toBe(`${MARKER}-2`);
  expect(all.events[2]['payload']).toMatchObject({ condition: 'noModelKey', active: true });

  expect((await poll('?after=2&afterInstance=1')).events).toEqual([]);
  const partial = await poll('?after=1&afterInstance=1');
  expect(partial.epoch).toBe(EPOCH);
  expect(partial.events.map((event) => `${String(event['stream'])}:${String(event['seq'])}`)).toEqual(['session:2']);

  for (const query of ['', '?after=0', '?afterInstance=0', '?after=-1&afterInstance=0', '?after=0&afterInstance=-1', '?after=x&afterInstance=0', '?after=0&afterInstance=1.5', '?after=&afterInstance=']) {
    await expectError(await request.get(`${EVENTS}${query}`), 400, 'bad_cursor', 'The after and afterInstance values must be whole numbers of zero or more.');
  }
});

/** Row 15: a state-changing call needs the whole envelope. */
test('row 15: a state-changing call without the browser envelope is refused with 403', async ({ request, baseURL }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages'), 501, 'not_built', NOT_BUILT);
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { 'content-type': 'application/json; charset=utf-8' }), 501, 'not_built');
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { 'content-type': 'text/plain' }), 403, 'not_json');
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { 'x-ocutalon-request': undefined }), 403, 'no_request_header');
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { 'x-ocutalon-request': '0' }), 403, 'no_request_header');
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { origin: 'http://evil.example' }), 403, 'wrong_origin');
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { origin: undefined }), 403, 'wrong_origin');
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/messages', { origin: originOf(baseURL).replace('http://', 'https://') }), 403, 'wrong_origin');
  const read = await request.get(STATE);
  expect(read.status(), 'a GET needs no envelope').toBe(200);
});

/** Row 16: every route that no story has built answers 501, and the pairing routes answer 404. */
test('row 16: unbuilt routes answer 501 not_built, and the pairing routes 404', async ({ request, baseURL }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  for (const [, path] of UNBUILT) {
    await expectError(await post(request, baseURL, path), 501, 'not_built', NOT_BUILT);
  }
  await expectError(await post(request, baseURL, '/ocutalon/api/v1/pairing/code'), 404, 'not_found', NOT_FOUND);
  const unpair = await request.delete('/ocutalon/api/v1/pairing', {
    headers: { 'content-type': 'application/json', 'x-ocutalon-request': '1', origin: originOf(baseURL) },
  });
  await expectError(unpair, 404, 'not_found', NOT_FOUND);
});

/** Row 17: the other errors, signed in and signed out. */
test('row 17: 404, 405 and 401 are in the error shape', async ({ request, playwright, baseURL }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  await expectError(await request.get('/ocutalon/api/v1/zz'), 404, 'not_found', NOT_FOUND);
  const wrongMethod = await request.get('/ocutalon/api/v1/messages');
  await expectError(wrongMethod, 405, 'method_not_allowed', "This address doesn't accept that kind of request.");
  expect(wrongMethod.headers()['allow']).toContain('POST');

  const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: BROWSER_HEADERS });
  for (const path of [STATE, `${EVENTS}?after=0&afterInstance=0`, '/ocutalon/api/v1/zz']) {
    const response = await anonymous.get(path);
    await expectError(response, 401, 'signed_out', SIGNED_OUT);
    expect(response.headers()['www-authenticate'], `${path} sends no challenge`).toBeUndefined();
    expect(response.headers()['content-type']).toContain('application/json');
  }
  await anonymous.dispose();
});

/** Row 18: a user without the OcuTalon user role is refused by the API, and the session stays open. */
test('row 18: a trace-only user gets 403 no_role from the API', async ({ request }) => {
  // A trace window's cookie is scoped to the trace application, so the API does not see it. The route that works
  // is the sign-in form's fields posted to the API itself.
  const signedIn = await request.post(STATE, { form: { IRISUsername: TRACE_ONLY.user, IRISPassword: TRACE_ONLY.password, IRISLogin: 'Sign in' } });
  await expectError(signedIn, 403, 'no_role', NO_ROLE);
  await expectError(await request.get(STATE), 403, 'no_role', NO_ROLE);
  await expectError(await request.get(`${EVENTS}?after=0&afterInstance=0`), 403, 'no_role', NO_ROLE);

  const trace = await request.get('/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen');
  expect(await trace.text(), 'the session is not ended: the trace window still opens').toContain('Message Viewer');
});

test('row 18: the README account gets 200', async ({ request }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  expect((await request.get(STATE)).status()).toBe(200);
});

/** Row 19: the public status answers to anyone, with every key. */
test('row 19: /ocutalon/public/status answers without a session and does not disturb one', async ({ request, playwright, baseURL }) => {
  const check = async (context: APIRequestContext): Promise<void> => {
    const response = await context.get('/ocutalon/public/status');
    expect(response.status()).toBe(200);
    expect(response.headers()['cache-control']).toBe('no-store');
    expect(response.headers()['content-type']).toContain('application/json');
    const body = (await response.json()) as Record<string, unknown>;
    expect(Object.keys(body)).toEqual(['ready', 'nextReset', 'busy', 'lastReset', 'lastResetKind']);
    expect(body['ready']).toBe(true);
    expect(body['busy']).toBe(false);
    for (const key of ['nextReset', 'lastReset', 'lastResetKind']) expect(body[key], key).toBeNull();
  };

  const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: BROWSER_HEADERS });
  await check(anonymous);
  const unknown = await anonymous.get('/ocutalon/public/zz');
  expect(unknown.status()).toBe(404);
  await anonymous.dispose();

  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  await check(request);
  expect((await request.get(STATE)).status(), 'the signed-in session still works').toBe(200);
});
