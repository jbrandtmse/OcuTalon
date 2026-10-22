import { expect, test, type APIRequestContext, type APIResponse, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme } from '../sign-in/helpers';

/**
 * Story 0.5, rows 13 to 19: the REST skeleton and the public status over real HTTP, on a stack that
 * test-sign-in.sh has seeded. The script publishes two reminders on the README account's session stream and one
 * status event on the instance stream, and passes what it read back: the manifest's version, the instance zone, the
 * session's epoch and the marker of the seeded texts (reminders `<marker>-1` and `<marker>-2`). It also creates the
 * trace-only user ZzTraceOnly and ZzFirstCall, a user with the user role and no session row. Every variable is
 * required: a test that reads one fails without it. Each is read every time a test uses it, never at import, so that
 * listing the specs (`playwright test --list`) needs none of them.
 */
function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set by docker/tests/test-sign-in.sh`);
  return value;
}

/** What test-sign-in.sh read back from the seeded stack. */
const SEEDED = {
  get version(): string {
    return required('OCUTALON_E2E_VERSION');
  },
  get zone(): string {
    return required('OCUTALON_E2E_ZONE');
  },
  get epoch(): string {
    return required('OCUTALON_E2E_EPOCH');
  },
  get marker(): string {
    return required('OCUTALON_E2E_MARKER');
  },
  get traceOnly(): { user: string; password: string } {
    return { user: required('OCUTALON_TRACEONLY_USER'), password: required('OCUTALON_TRACEONLY_PASSWORD') };
  },
  get firstCall(): { user: string; password: string } {
    return { user: required('OCUTALON_FIRSTCALL_USER'), password: required('OCUTALON_FIRSTCALL_PASSWORD') };
  },
};

/** What a browser always sends, and what a request without a session must still be answered with. */
const BROWSER_HEADERS = { 'accept-language': 'en-US,en;q=0.9' };

const STATE = '/ocutalon/api/v1/state';
const EVENTS = '/ocutalon/api/v1/events';
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const BAD_CURSOR = 'The after and afterInstance values must be whole numbers of zero or more.';
const MESSAGES = '/ocutalon/api/v1/messages';
const PAIRING = '/ocutalon/api/v1/pairing';

/** The three refusals of the browser envelope, with their texts. */
const ENVELOPE_TEXT = {
  not_json: "OcuTalon refused this request because it wasn't sent as JSON.",
  no_request_header: "OcuTalon refused this request because it didn't come from the OcuTalon page.",
  wrong_origin: 'OcuTalon refused this request because it came from another site.',
} as const;

const NOT_BUILT = "This part of OcuTalon isn't built yet.";
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';

/** The routes that answer 501 not_built, with the method that each takes. Session/end is built (Story 2.2) and the two routes that name a record answer 404 first. */
const UNBUILT: ReadonlyArray<readonly [method: 'POST', path: string]> = [
  ['POST', '/ocutalon/api/v1/messages'],
  ['POST', '/ocutalon/api/v1/demo/break-feed'],
  ['POST', '/ocutalon/api/v1/mailbox/incoming'],
  ['POST', '/ocutalon/api/v1/mailbox/samples/zz'],
  ['POST', '/ocutalon/api/v1/guide/markers'],
];

/** The routes that name a record: a ref the session can't see answers 404 not_found, before the 501 of an unbuilt route. */
const BY_REF: ReadonlyArray<readonly [method: 'POST', path: (ref: string) => string]> = [
  ['POST', (ref) => `/ocutalon/api/v1/approvals/${ref}/answer`],
  ['POST', (ref) => `/ocutalon/api/v1/incidents/${ref}/dismiss`],
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

/** The origin of the stack under test: OCUTALON_URL, which the config also uses as baseURL. */
function stackOrigin(): string {
  return originOf(process.env['OCUTALON_URL']);
}

/** A call with the whole browser envelope; the headers override or (when undefined) remove one part of it. */
function call(
  request: APIRequestContext,
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
  path: string,
  headers: Record<string, string | undefined> = {},
): Promise<APIResponse> {
  const envelope: Record<string, string | undefined> = {
    'content-type': 'application/json',
    'x-ocutalon-request': '1',
    origin: stackOrigin(),
    ...headers,
  };
  const sent = Object.fromEntries(Object.entries(envelope).filter((entry): entry is [string, string] => entry[1] !== undefined));
  return method === 'DELETE' ? request.delete(path, { headers: sent }) : request.fetch(path, { method, headers: sent, data: '{}' });
}

/** The "stream:seq" of each event, in the order served. */
function ids(events: Array<Record<string, unknown>>): string[] {
  return events.map((event) => `${String(event['stream'])}:${String(event['seq'])}`);
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
  expect(Object.keys(body)).toEqual(['version', 'instanceZone', 'epoch', 'streams', 'chat', 'rail', 'user', 'onlineDemo', 'demoMode', 'models', 'telegram', 'status']);
  expect(body['version']).toBe(SEEDED.version);
  expect(body['instanceZone']).toBe(SEEDED.zone);
  expect(body['epoch']).toBe(SEEDED.epoch);
  expect(body['streams']).toEqual({ session: 2, instance: 1 });
  expect(body['chat']).toEqual([]);
  expect(body['rail']).toEqual({ approvals: [], checks: [], reminders: [], decisions: [] });
  expect(body['user'], "the session row's user, not the client's").toBe(README_ACCOUNT.user);
  expect(body['onlineDemo'], 'a local install is not the online demo').toBe(false);
  expect(body['demoMode'], 'every Docker throwaway runs in demo mode').toBe(true);
  expect(body['models']).toEqual({ triage: 'Claude Haiku 5.5', diagnosis: 'Claude Haiku 5.5', chat: 'Claude Haiku 5.5' });
  expect(body['telegram'], 'Telegram is not included in this release and nobody is paired').toEqual({
    included: false,
    state: 'off',
    botUserName: '',
    paired: false,
    displayName: '',
    pausedUntil: '',
  });
  expect(body['status'], 'no status condition is computed yet').toEqual([]);
});

/**
 * Rows 13 and 14 and AD-4: a user with no session row has it created, as that unprivileged user, at sign-in (and by the first
 * call if the sign-in did not), a second call returns the same session, and the user's poll holds the instance events and none
 * of another user's session events. It is the only test that signs in as the first-call user, so the row is created in any
 * test order.
 */
test("rows 13 and 14: a user's /state answers the session that sign-in created, and its poll holds the instance events and not another user's session events", async ({ request }) => {
  await signInOverHttp(request, SEEDED.firstCall.user, SEEDED.firstCall.password);
  const first = await request.get(STATE);
  expect(first.status(), await first.text()).toBe(200);
  const body = (await first.json()) as { epoch: string; streams: { session: number; instance: number } };
  expect(body.epoch).toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(body.epoch, "not the README account's epoch").not.toBe(SEEDED.epoch);
  expect(body.streams.session).toBe(0);
  const second = (await (await request.get(STATE)).json()) as { epoch: string };
  expect(second.epoch, 'a second call returns the same session').toBe(body.epoch);

  const response = await request.get(`${EVENTS}?after=0&afterInstance=0`);
  expect(response.status(), await response.text()).toBe(200);
  const poll = (await response.json()) as { epoch: string; events: Array<Record<string, unknown>> };
  expect(ids(poll.events), "the README account's two session events are not here").toEqual(['instance:1']);
  expect(poll.epoch, "the user's own epoch, the same as /state's").toBe(body.epoch);
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
  expect(all.epoch).toBe(SEEDED.epoch);
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
  expect((all.events[0]['payload'] as { text: string }).text).toBe(`${SEEDED.marker}-1`);
  expect((all.events[1]['payload'] as { text: string }).text).toBe(`${SEEDED.marker}-2`);
  expect(all.events[2]['payload']).toMatchObject({ condition: 'noModelKey', active: true });

  expect((await poll('?after=2&afterInstance=1')).events).toEqual([]);
  const partial = await poll('?after=1&afterInstance=1');
  expect(partial.epoch).toBe(SEEDED.epoch);
  expect(ids(partial.events)).toEqual(['session:2']);

  for (const query of ['', '?after=0', '?afterInstance=0', '?after=-1&afterInstance=0', '?after=0&afterInstance=-1', '?after=x&afterInstance=0', '?after=0&afterInstance=1.5', '?after=&afterInstance=']) {
    await expectError(await request.get(`${EVENTS}${query}`), 400, 'bad_cursor', BAD_CURSOR);
  }
});

/** Row 14: each cursor moves its own stream, whatever the other says, and the session's stream is always first. */
test('row 14: the two cursors are independent, and the session stream is served before the instance stream', async ({ request }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const poll = async (query: string): Promise<string[]> => {
    const response = await request.get(`${EVENTS}${query}`);
    expect(response.status(), query).toBe(200);
    return ids(((await response.json()) as { events: Array<Record<string, unknown>> }).events);
  };

  expect(await poll('?after=2&afterInstance=0'), 'the session cursor at its end leaves the instance stream whole').toEqual(['instance:1']);
  expect(await poll('?after=0&afterInstance=1'), 'the instance cursor at its end leaves the session stream whole').toEqual(['session:1', 'session:2']);
  expect(await poll('?after=1&afterInstance=0'), 'a partial session cursor, session first').toEqual(['session:2', 'instance:1']);
  expect(await poll('?after=001&afterInstance=00'), 'leading zeros are whole numbers').toEqual(['session:2', 'instance:1']);
  expect(await poll('?after=999999999999999&afterInstance=999999999999999'), 'a cursor of 15 digits, past the last Seq, is an empty poll').toEqual([]);

  for (const query of ['?after=0&afterInstance=1234567890123456', '?after=1234567890123456&afterInstance=0', '?after=%2B1&afterInstance=0', '?after=0&afterInstance=1e2', '?after=0x1&afterInstance=0']) {
    await expectError(await request.get(`${EVENTS}${query}`), 400, 'bad_cursor', BAD_CURSOR);
  }
});

/**
 * Row 15: the browser envelope, one rule at a time. The checks run in the order not_json, no_request_header,
 * wrong_origin, and each test breaks exactly the rule it names, so a rule that stops being checked fails its own
 * test. One signed-in context serves them all, because none changes any state.
 */
test.describe('row 15: the browser envelope', () => {
  let signedIn: APIRequestContext;

  test.beforeAll(async ({ playwright }) => {
    signedIn = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    await signInOverHttp(signedIn, README_ACCOUNT.user, README_ACCOUNT.password);
  });

  test.afterAll(async () => {
    await signedIn.dispose();
  });

  test('the whole envelope is let through, with or without a charset', async () => {
    await expectError(await call(signedIn, 'POST', MESSAGES), 501, 'not_built', NOT_BUILT);
    await expectError(await call(signedIn, 'POST', MESSAGES, { 'content-type': 'application/json; charset=utf-8' }), 501, 'not_built', NOT_BUILT);
  });

  test('only the Content-Type is wrong: not_json', async () => {
    for (const type of ['text/plain', 'application/x-www-form-urlencoded', 'application/jsonx']) {
      await expectError(await call(signedIn, 'POST', MESSAGES, { 'content-type': type }), 403, 'not_json', ENVELOPE_TEXT.not_json);
    }
  });

  test('only the X-OcuTalon-Request header is wrong: no_request_header', async () => {
    for (const value of [undefined, '0', 'true', '11']) {
      await expectError(await call(signedIn, 'POST', MESSAGES, { 'x-ocutalon-request': value }), 403, 'no_request_header', ENVELOPE_TEXT.no_request_header);
    }
  });

  test('only the Origin is wrong: wrong_origin', async () => {
    const own = stackOrigin();
    for (const origin of [undefined, 'http://evil.example', 'null', own.replace('http://', 'https://'), `${own}.evil.example`, `${own}0`]) {
      await expectError(await call(signedIn, 'POST', MESSAGES, { origin }), 403, 'wrong_origin', ENVELOPE_TEXT.wrong_origin);
    }
  });

  test('with more than one rule broken, the first in the order names the refusal', async () => {
    const evil = 'http://evil.example';
    await expectError(await call(signedIn, 'POST', MESSAGES, { 'content-type': 'text/plain', 'x-ocutalon-request': undefined, origin: evil }), 403, 'not_json', ENVELOPE_TEXT.not_json);
    await expectError(await call(signedIn, 'POST', MESSAGES, { 'content-type': 'text/plain', origin: evil }), 403, 'not_json', ENVELOPE_TEXT.not_json);
    await expectError(await call(signedIn, 'POST', MESSAGES, { 'content-type': 'text/plain', 'x-ocutalon-request': undefined }), 403, 'not_json', ENVELOPE_TEXT.not_json);
    await expectError(await call(signedIn, 'POST', MESSAGES, { 'x-ocutalon-request': undefined, origin: evil }), 403, 'no_request_header', ENVELOPE_TEXT.no_request_header);
  });

  test('every state-changing method is checked, and before the route is looked up', async () => {
    const evil = 'http://evil.example';
    await expectError(await call(signedIn, 'DELETE', PAIRING, { 'content-type': 'text/plain' }), 403, 'not_json', ENVELOPE_TEXT.not_json);
    await expectError(await call(signedIn, 'DELETE', PAIRING, { 'x-ocutalon-request': undefined }), 403, 'no_request_header', ENVELOPE_TEXT.no_request_header);
    await expectError(await call(signedIn, 'DELETE', PAIRING, { origin: evil }), 403, 'wrong_origin', ENVELOPE_TEXT.wrong_origin);
    await expectError(await call(signedIn, 'PUT', MESSAGES, { origin: evil }), 403, 'wrong_origin', ENVELOPE_TEXT.wrong_origin);
    await expectError(await call(signedIn, 'PATCH', MESSAGES, { 'x-ocutalon-request': undefined }), 403, 'no_request_header', ENVELOPE_TEXT.no_request_header);
    // A route that does not exist is refused for its envelope first, and is 404 only with a whole one.
    await expectError(await call(signedIn, 'POST', '/ocutalon/api/v1/zz', { origin: evil }), 403, 'wrong_origin', ENVELOPE_TEXT.wrong_origin);
    await expectError(await call(signedIn, 'POST', '/ocutalon/api/v1/zz'), 404, 'not_found', NOT_FOUND);
  });

  test('a GET needs no envelope, whatever it carries', async () => {
    const carried: Array<Record<string, string>> = [{}, { 'content-type': 'text/plain' }, { origin: 'http://evil.example' }, { 'x-ocutalon-request': '0' }];
    for (const headers of carried) {
      const response = await signedIn.get(STATE, { headers });
      expect(response.status(), JSON.stringify(headers)).toBe(200);
    }
    await expectError(await signedIn.get('/ocutalon/api/v1/zz', { headers: { origin: 'http://evil.example' } }), 404, 'not_found', NOT_FOUND);
  });
});

/**
 * Row 16: every route that no story has built answers 501, the pairing routes answer 404, and the two routes that name a record
 * answer 404 for a ref the session can't see (a random ref, here) with the error shape (AD-4).
 */
test('row 16: unbuilt routes answer 501 not_built, the pairing routes 404, and a ref the session cannot see 404', async ({ request }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  for (const [, path] of UNBUILT) {
    await expectError(await call(request, 'POST', path), 501, 'not_built', NOT_BUILT);
  }
  for (const [, path] of BY_REF) {
    await expectError(await call(request, 'POST', path('ZzNoSuchRef0123456789')), 404, 'not_found', NOT_FOUND);
    await expectError(await call(request, 'POST', path('zz')), 404, 'not_found', NOT_FOUND);
  }
  await expectError(await call(request, 'POST', `${PAIRING}/code`), 404, 'not_found', NOT_FOUND);
  await expectError(await call(request, 'DELETE', PAIRING), 404, 'not_found', NOT_FOUND);
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
  // Without a session the answer is 401, with the envelope whole or broken: the sign-in comes before every other check.
  for (const headers of [{}, { 'content-type': 'text/plain', 'x-ocutalon-request': undefined, origin: 'http://evil.example' }]) {
    await expectError(await call(anonymous, 'POST', MESSAGES, headers), 401, 'signed_out', SIGNED_OUT);
  }
  await expectError(await call(anonymous, 'DELETE', PAIRING), 401, 'signed_out', SIGNED_OUT);
  await anonymous.dispose();
});

/**
 * Row 18: a user without the OcuTalon user role is refused by the API before the envelope and the route are looked
 * at, and the refusal does not end the session, which the trace applications share.
 */
test('row 18: a trace-only user gets 403 no_role from the API, first, and stays signed in', async ({ request }) => {
  // A trace window's cookie is scoped to the trace application, so the API does not see it. The route that works
  // is the sign-in form's fields posted to the API itself.
  const signedIn = await request.post(STATE, { form: { IRISUsername: SEEDED.traceOnly.user, IRISPassword: SEEDED.traceOnly.password, IRISLogin: 'Sign in' } });
  await expectError(signedIn, 403, 'no_role', NO_ROLE);
  await expectError(await request.get(STATE), 403, 'no_role', NO_ROLE);
  await expectError(await request.get(`${EVENTS}?after=0&afterInstance=0`), 403, 'no_role', NO_ROLE);

  // Not 501, 404 or an envelope code: the role is judged before the envelope and the route.
  await expectError(await call(request, 'POST', MESSAGES), 403, 'no_role', NO_ROLE);
  await expectError(await call(request, 'POST', MESSAGES, { 'content-type': 'text/plain', 'x-ocutalon-request': undefined, origin: 'http://evil.example' }), 403, 'no_role', NO_ROLE);
  await expectError(await call(request, 'DELETE', PAIRING), 403, 'no_role', NO_ROLE);
  await expectError(await request.get('/ocutalon/api/v1/zz'), 403, 'no_role', NO_ROLE);

  // Every refusal above left the session open: it still answers, and the trace window still opens.
  await expectError(await request.get(STATE), 403, 'no_role', NO_ROLE);
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
